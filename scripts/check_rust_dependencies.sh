#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/rust/Cargo.toml"
RUST_RUNNER="$ROOT_DIR/scripts/run_rust.sh"

check_argus_dependencies() {
  local package_name="$1"
  shift

  local actual
  local expected

  actual="$(
    bash "$RUST_RUNNER" cargo tree \
      --manifest-path "$MANIFEST" \
      --package "$package_name" \
      --depth 1 \
      --edges normal \
      --prefix none \
      --locked \
      | tail -n +2 \
      | sed -n 's/^\(argus-[^ ]*\) .*/\1/p' \
      | LC_ALL=C sort
  )"

  expected="$(printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort)"

  if [[ "$actual" != "$expected" ]]; then
    printf 'Unexpected Argus crate dependencies for %s.\n' "$package_name" >&2
    printf 'Expected:\n%s\n' "$expected" >&2
    printf 'Actual:\n%s\n' "$actual" >&2
    return 1
  fi
}

check_argus_dependencies argus-domain
check_argus_dependencies argus-application argus-domain
check_argus_dependencies argus-infrastructure argus-application argus-domain
check_argus_dependencies argus-runtime argus-application argus-domain argus-infrastructure
check_argus_dependencies argus-bridge argus-application argus-runtime
