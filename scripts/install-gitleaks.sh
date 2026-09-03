#!/usr/bin/env bash
# Install a pinned gitleaks into ./.tools/ (gitignored).
#
# Why a downloaded binary rather than brew or `go install`: this script has to
# work identically on a laptop and on a CI runner that has only Node or only
# Terraform installed. Every repo in the portfolio runs the same secret scan,
# so it cannot depend on a language toolchain that some of them lack.
#
# Pinned by version deliberately — an unpinned security scanner that silently
# changes its ruleset makes the gate's verdict non-reproducible.
set -euo pipefail

VERSION="8.30.1"
DEST="${1:-.tools}"
BIN="${DEST}/gitleaks"

if [ -x "${BIN}" ] && "${BIN}" version 2>/dev/null | grep -q "${VERSION}"; then
  exit 0
fi

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux"  ;;
  *) echo "install-gitleaks: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="x64"   ;;
  *) echo "install-gitleaks: unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

TARBALL="gitleaks_${VERSION}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/${TARBALL}"

echo "installing gitleaks ${VERSION} (${OS}/${ARCH}) into ${DEST}/"
mkdir -p "${DEST}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
curl -fsSL "${URL}" -o "${TMP}/${TARBALL}"
tar -xzf "${TMP}/${TARBALL}" -C "${TMP}" gitleaks
mv "${TMP}/gitleaks" "${BIN}"
chmod +x "${BIN}"
"${BIN}" version
