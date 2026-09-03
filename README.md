# ci-workflows

Reusable GitHub Actions workflows implementing the **rail** from
[The Delegation Pyramid](https://github.com/getgoodorc/docs/blob/main/plan/07-TESTING-HARNESS.md).

> `getgoodorc/ci-workflows` — deliberately **public**, even though every other repo in the
> org is private. Two reasons: a private reusable workflow can only be called by repos with
> the same owner, so public keeps it usable from projects outside the org (chestful, and
> anything else); and public repos get branch protection for free. There is nothing
> proprietary here — it is generic CI plumbing.

## The one rule

**CI runs `make check` and nothing else.**

Every workflow here does exactly three things: check out the code, install the language
toolchain, and run `make check`. It must never run a bespoke sequence of steps, because the
moment it does, your laptop, an agent's sandbox, and the pipeline can disagree about what
"green" means — and the entire value of the harness evaporates.

If something needs to happen in CI, it goes in the Makefile, where you can also run it.

## Usage

Each consuming repo's `.github/workflows/ci.yml` is about ten lines:

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request:
jobs:
  check:
    uses: getgoodorc/ci-workflows/.github/workflows/rail-go.yml@v0
```

No `with:` block needed. The toolchain version comes from the repo's own
`.go-version` (or `.nvmrc` for `rail-node`) — the same file your local version
manager reads, so a laptop and CI cannot drift apart. Pass `go-version` /
`node-version` explicitly only to override.

Upgrading every repo's pipeline is then a matter of moving one tag.

## Available workflows

| Workflow | For | Toolchain it installs |
|---|---|---|
| `rail-go.yml` | Go repos, including multi-module ones | Go + module/build cache |
| `rail-node.yml` | Node/TypeScript repos | Node + npm cache |
| `rail-infra.yml` | Terraform / Helm / compose repos | Terraform + Helm |

All three accept a `working-directory` input for repos where the Makefile isn't at the root.

## Self-check

`self-check.yml` runs `actionlint` over this repo's own workflows. The pipelines lint the
pipelines — per the north star, the harness is under its own test.

## Versioning

Consumers pin a tag (`@v0`). Cut a new tag when a workflow's behavior changes; move the
major tag only for backward-compatible changes. Consumers should never pin `@main`.

## Roadmap

This is the **S0 skeleton** — the rail only. Deliberately minimal, because a rail that
works everywhere beats a rich pipeline that works in one repo.

| Sprint | Adds |
|---|---|
| **S0** *(here)* | `make check` gate per language, self-check |
| **S1** | L1: `gitleaks`, `govulncheck`, `actionlint`, `hadolint`, `trivy`, Renovate config presets. **SHA-pin every third-party action** (currently tag-pinned — a known, deliberate gap). |
| **S3** | `l3-test.yml`: coverage upload, cassette-replay-only enforcement, mutation score reporting |
| **S4** | `l4-db.yml`: schema-is-a-pure-function check, migration rehearsal |
| **S5** | `l5-e2e.yml`: Playwright, screenshot artifacts, mobile viewport sweep |
| **S6** | `l6-release.yml`: build, SBOM, cosign, smoke-in-image, digest-pinned deploy |
