#!/usr/bin/env bash
# Install a pinned lint/security tool into ./.tools/ (gitignored).
#
#   ./scripts/install-tool.sh gitleaks actionlint hadolint shellcheck
#
# Why downloaded binaries rather than brew, go install, or pip: every repo in
# the portfolio runs the same gates, and they are written in Go, Haskell, Rust
# and Python. Tying the harness to any one language toolchain would mean the
# docs repo needs Go, or the Terraform repo needs a Haskell runtime. A pinned
# binary has no such dependency and behaves identically on a laptop and a CI
# runner.
#
# Everything is pinned by version on purpose. An unpinned linter that silently
# changes its ruleset makes the gate's verdict non-reproducible — today's green
# and tomorrow's green would not mean the same thing.
#
# Canonical copy: getgoodorc/ci-workflows/tools/install-tool.sh
set -euo pipefail

DEST="${TOOLS_DIR:-.tools}"

GITLEAKS_VERSION="8.30.1"
ACTIONLINT_VERSION="1.7.12"
HADOLINT_VERSION="2.15.1"
SHELLCHECK_VERSION="0.11.0"
TFLINT_VERSION="0.64.0"

case "$(uname -s)" in
  Darwin) OS=darwin ;;
  Linux)  OS=linux  ;;
  *) echo "install-tool: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=amd64 ;;
  *) echo "install-tool: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$DEST"

have() { # have <bin> <version-substring>
  [ -x "$DEST/$1" ] && "$DEST/$1" --version 2>/dev/null | grep -q "$2"
}

fetch_tar() { # fetch_tar <url> <member> <dest-name>
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "$1" -o "$tmp/a"
  tar -xzf "$tmp/a" -C "$tmp" "$2"
  mv "$tmp/$2" "$DEST/$3"; chmod +x "$DEST/$3"
  rm -rf "$tmp"
}

fetch_bin() { # fetch_bin <url> <dest-name>
  curl -fsSL "$1" -o "$DEST/$2"; chmod +x "$DEST/$2"
}

fetch_zip() { # fetch_zip <url> <member> <dest-name>
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "$1" -o "$tmp/a.zip"
  unzip -qo "$tmp/a.zip" "$2" -d "$tmp"
  mv "$tmp/$2" "$DEST/$3"; chmod +x "$DEST/$3"
  rm -rf "$tmp"
}

install_gitleaks() {
  have gitleaks "$GITLEAKS_VERSION" && return 0
  local a=x64; [ "$ARCH" = arm64 ] && a=arm64
  echo "installing gitleaks $GITLEAKS_VERSION"
  fetch_tar "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_${OS}_${a}.tar.gz" gitleaks gitleaks
}

install_actionlint() {
  have actionlint "$ACTIONLINT_VERSION" && return 0
  echo "installing actionlint $ACTIONLINT_VERSION"
  fetch_tar "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_${OS}_${ARCH}.tar.gz" actionlint actionlint
}

install_hadolint() {
  have hadolint "$HADOLINT_VERSION" && return 0
  local o=$OS a=x86_64
  [ "$OS" = darwin ] && o=macos
  [ "$ARCH" = arm64 ] && a=arm64
  echo "installing hadolint $HADOLINT_VERSION"
  fetch_bin "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-${o}-${a}" hadolint
}

install_shellcheck() {
  have shellcheck "$SHELLCHECK_VERSION" && return 0
  local a=x86_64; [ "$ARCH" = arm64 ] && a=aarch64
  echo "installing shellcheck $SHELLCHECK_VERSION"
  fetch_tar "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.${OS}.${a}.tar.gz" \
            "shellcheck-v${SHELLCHECK_VERSION}/shellcheck" shellcheck
}

# Python tools live in an isolated venv. System pythons are increasingly
# PEP 668 "externally managed", so `pip install` fails outright — and a
# harness that needs sudo, or that mutates the system interpreter, is a
# harness people work around.
install_pytools() {
  local py="$DEST/venv/bin/python"
  if [ -x "$py" ] && "$py" -c "import yaml, yamllint, sqlfluff" 2>/dev/null; then return 0; fi
  echo "creating $DEST/venv (pyyaml, yamllint, sqlfluff)"
  python3 -m venv "$DEST/venv"
  "$DEST/venv/bin/pip" install --quiet --disable-pip-version-check \
    "pyyaml==6.0.2" "yamllint==1.35.1" "sqlfluff==3.4.2"
}

install_tflint() {
  have tflint "$TFLINT_VERSION" && return 0
  echo "installing tflint $TFLINT_VERSION"
  fetch_zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_${OS}_${ARCH}.zip" tflint tflint
}

for tool in "$@"; do
  case "$tool" in
    gitleaks)   install_gitleaks   ;;
    actionlint) install_actionlint ;;
    hadolint)   install_hadolint   ;;
    shellcheck) install_shellcheck ;;
    tflint)     install_tflint     ;;
    pytools)    install_pytools    ;;
    *) echo "install-tool: unknown tool '$tool'" >&2; exit 1 ;;
  esac
done
