#!/usr/bin/env bash
# Downloads and checksum-verifies pinned CLI tool binaries into ./bin/.
# bin/ is gitignored on purpose — this script is what reproduces it on a
# fresh clone or after bin/ is wiped.
#
# Versions and sha256 sums below were captured from each project's official
# GitHub/HashiCorp release at pin time. Bump deliberately, not silently:
# update both the *_VERSION and *_SHA256 together after checking upstream.
#
# Usage: scripts/bootstrap-bin.sh [terraform|sops|age|all]
# Default (no args): all

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${REPO_ROOT}/bin"
mkdir -p "$BIN_DIR"

TERRAFORM_VERSION="1.15.5"
TERRAFORM_SHA256="702b2136af6728c8ff037f843dd2dbce2b7ad88786b7381d1d72aefa250f601c"

SOPS_VERSION="3.13.1"
SOPS_SHA256="620a9d7e3352ababeca6908cea24a6e8b14ce89a448ddbd3f94f1ef3398f470a"

AGE_VERSION="1.3.1"
AGE_SHA256="bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377"

verify_sha256() {
  local file="$1" expected="$2" actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for $file: expected $expected, got $actual" >&2
    exit 1
  fi
}

install_terraform() {
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/terraform.zip" \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  verify_sha256 "$tmp/terraform.zip" "$TERRAFORM_SHA256"
  unzip -oq "$tmp/terraform.zip" -d "$tmp"
  install -m 0755 "$tmp/terraform" "$BIN_DIR/terraform"
  echo "installed terraform ${TERRAFORM_VERSION} -> $BIN_DIR/terraform"
}

install_sops() {
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/sops" \
    "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"
  verify_sha256 "$tmp/sops" "$SOPS_SHA256"
  install -m 0755 "$tmp/sops" "$BIN_DIR/sops"
  echo "installed sops ${SOPS_VERSION} -> $BIN_DIR/sops"
}

install_age() {
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL -o "$tmp/age.tar.gz" \
    "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz"
  verify_sha256 "$tmp/age.tar.gz" "$AGE_SHA256"
  tar -xzf "$tmp/age.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/age/age" "$BIN_DIR/age"
  install -m 0755 "$tmp/age/age-keygen" "$BIN_DIR/age-keygen"
  echo "installed age ${AGE_VERSION} -> $BIN_DIR/age, $BIN_DIR/age-keygen"
}

if [[ $# -eq 0 ]]; then
  targets=(all)
else
  targets=("$@")
fi

for t in "${targets[@]}"; do
  case "$t" in
    terraform) install_terraform ;;
    sops) install_sops ;;
    age) install_age ;;
    all) install_terraform; install_sops; install_age ;;
    *) echo "unknown target: $t (expected terraform|sops|age|all)" >&2; exit 1 ;;
  esac
done
