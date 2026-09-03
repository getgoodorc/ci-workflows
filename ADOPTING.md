# The Harness

**How to put any repo — in any language — onto the same rail, and what you get for it.**

---

## The name

The whole thing is **the Harness**.

It is deliberately the word the north-star doc already uses ("the harness rail", "the
harness is under its own test"), and it is already the word the artifacts use, so there is
nothing new to learn:

| Name | What it is |
|---|---|
| **The Harness** | The whole system: the rail, the gates, the declarations, the runbooks. |
| **The rail** | The layer under the pyramid: one command per verb, the same command in CI. |
| **`harness.yaml`** | Per-repo declaration — current level, target level, enabled gates, known gaps. |
| **`ci-workflows`** | This repo. The rail, as reusable GitHub Actions. |
| **The ratchet** | `scripts/ratchet.py` — the check that makes "gates only tighten" true rather than aspirational. |

Distinguish it from **the Delegation Pyramid**, which is the *model* — the six levels and
the reasoning. The pyramid is the map; the Harness is the vehicle. One is a document, the
other is code you run.

---

## The one rule

> **CI runs `make check` and nothing else.**

This is the load-bearing constraint, not a stylistic preference. The moment CI runs its own
sequence of steps, your laptop, an agent's sandbox, and the pipeline can disagree about
what "green" means — and every guarantee above it evaporates. If something needs to happen
in CI, it goes in the Makefile, where you can also run it.

Everything else in this document follows from that one rule.

---

## Adopting it in a new repo

Roughly an hour, most of it waiting for downloads.

### 1. The verb interface

Create a `Makefile` at the repo root implementing exactly these, whatever the language:

| Verb | Contract |
|---|---|
| `bootstrap` | Install/verify every tool the repo needs. Idempotent. |
| `fmt` | Apply canonical formatting. Mutates files. |
| `lint` | All static checks. Read-only, non-zero exit on violation. |
| `test` | Hermetic suite. No credentials, no shared state. |
| `build` | Produce the artifact. |
| `run` | Start it the way production starts it. |
| `check` | Everything above that gates. **What CI runs.** |
| `clean` | Remove build output. |

Add `record`, `migrate`, `seed`, `e2e` where they apply. The bodies differ per language;
the names never do. That uniformity is the entire reuse mechanism — it is what lets a
person or an agent move between a Go service and a React Native app at zero cost.

### 2. Pin the toolchain in one file

`.go-version`, `.nvmrc`, `.python-version` — whatever your version manager reads. CI reads
the same file (`go-version-file`, `node-version-file`). Then make `bootstrap` or
`require-tools` **fail** if the toolchain on PATH does not match:

```make
require-tools:
	@want=$$(cat .go-version); have=$$($(GO) env GOVERSION | sed 's/^go//'); \
	if [ "$$want" != "$$have" ]; then \
		echo "ERROR: .go-version wants $$want, PATH has $$have."; \
		echo "       CI installs from .go-version, so your green is not CI's green."; \
		exit 1; fi
```

Two places to declare a version is one place too many. This repo's own history has the
receipts: three Go modules had drifted to three different declared versions.

### 3. Wire up CI

```yaml
# .github/workflows/check.yml — the entire pipeline
name: ci
on:
  push: { branches: [main] }
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  check:
    uses: getgoodorc/ci-workflows/.github/workflows/rail-go.yml@v0
```

Pick `rail-go`, `rail-node`, or `rail-infra`. No `with:` block needed — the version comes
from your version file.

### 4. Install the tools

Copy `tools/install-tool.sh` to `scripts/`, and call it from `bootstrap`:

```make
bootstrap:
	@./scripts/install-tool.sh gitleaks actionlint shellcheck pytools
```

It downloads pinned binaries into `.tools/` (gitignore it). Pinned binaries rather than
brew, `go install`, or pip because the tools are written in Go, Haskell, Rust and Python —
tying the harness to one language would mean your docs repo needs Go.

### 5. Declare where you stand

Copy `harness.yaml` and fill it in honestly. `level` is what is true today, including
`none`. `target` follows **blast radius, not ambition** — and stopping early is a correctly
sized investment, not immaturity. A static site that ends at L1 is finished, not lazy.

### 6. Turn on the ratchet

Copy `tools/ratchet.py` to `scripts/` and add it to `lint`. It fails the build if `level`
or `target` moved down, or if a gate that was enabled is not. Adding gates, adding gaps,
and raising levels all pass. That asymmetry is the point: weakening a gate becomes a
conversation instead of a line in a diff.

---

## The gates, by level

Add these in order. Skipping produces checks nobody trusts.

| Level | Go | TypeScript | Python | Everything committed |
|---|---|---|---|---|
| **L1** | gofumpt, golangci-lint, govulncheck | prettier, eslint | ruff, bandit | gitleaks, actionlint, hadolint, shellcheck, yamllint, markdownlint, tflint, sqlfluff, Renovate |
| **L2** | depguard boundaries, `unused` | `tsc --noEmit`, knip, madge | mypy on a ratchet, import-linter | — |
| **L3** | `go test`, go-vcr, gremlins | vitest, MSW, stryker | pytest, pytest-recording, mutmut | coverage as a searchlight, never a target |
| **L4** | testcontainers, OpenAPI codegen | generated clients | testcontainers, alembic rehearsal | schema as a pure function of the repo |
| **L5** | — | Playwright + screenshots | — | chaos/fault injection, mobile viewport sweep |
| **L6** | — | — | — | digest-pinned builds, smoke-in-image, merge-is-deploy, read-only prod |

---

## What this actually buys you

Not theory — this is what the gates caught the first time they ran on a codebase that
already looked clean and had been reviewed:

- A **reachable CVE** (`golang.org/x/text`, GO-2026-5970) sitting in three modules. Nothing
  in the repo would ever have mentioned it.
- A **latent audit-chain bug**: `err != pgx.ErrNoRows` instead of `errors.Is`, which would
  have made the first audit record for every tenant fail to write.
- A **console that passed locally and failed in CI** — a generated type existed only
  because a stale build directory happened to be lying around. A clean checkout had never
  been attempted until CI attempted one.
- A **Helm chart that had never been rendered**, failing because a README inside
  `templates/` was being parsed as a Go template.
- **Six Terraform modules with no version constraints**, so `terraform init` could resolve a
  different provider major than the one they were written against.
- **Dockerfiles using a named `USER`**, which Kubernetes `runAsNonRoot` cannot verify.
- A committed `.gitignore` rule that excluded `.terraform.lock.hcl`, quietly making
  provider versions irreproducible.

Every one of those was invisible to review and obvious to a machine. That is the argument.

---

## Reusing it across projects

Three artifacts, in order of leverage:

1. **`getgoodorc/ci-workflows`** *(this repo, public)* — reusable workflows plus
   `tools/install-tool.sh` and `tools/ratchet.py`. Bump one tag, every repo's pipeline
   upgrades. Public on purpose: private reusable workflows can only be called by repos with
   the same owner.
2. **`harness-make`** *(not built yet)* — the verb implementations as includable `.mk`
   files, so a root Makefile is five lines. Extract this once the same Makefile has been
   copied three times and the shape has stopped changing.
3. **`claude-harness`** *(not built yet)* — the runbooks as a Claude Code plugin:
   `test-local`, `record-cassettes`, `add-a-migration`, `ship`, `investigate`,
   `climb-a-level`.

**Skills over memory, deliberately.** A makefile captures a verb; a skill captures a
workflow. Memory holds facts; skills hold procedures. A procedure in memory is loaded
probabilistically and drifts silently — a skill is a file in the repo, reviewed in PRs,
versioned with the code it describes, and linted in CI.

---

## Two GitHub gotchas, learned expensively

Both cost an afternoon here. Neither produces a useful error message.

1. **Actions does not follow transfer redirects** when resolving a reusable workflow. Move
   a repo and every `uses:` pointing at the old path fails — with zero jobs created, no
   logs, and only "This run likely failed because of a workflow file issue" to go on.
2. **`jobs.<id>.defaults.run.working-directory` does not accept the `inputs` context.**
   `actionlint` passes it happily; GitHub rejects the workflow at resolution. Set
   `working-directory` on the steps instead.

A third, cheaper one: pin actions by **commit SHA**, not tag. Tags are mutable, so a major
tag can be repointed at code that then runs with your workflow's permissions — and if you
guess a tag that does not exist, every consumer fails before a single job starts.
