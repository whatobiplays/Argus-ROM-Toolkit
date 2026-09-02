#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_TOOLCHAIN_FILE="$ROOT_DIR/rust-toolchain.toml"

rust_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$RUST_TOOLCHAIN_FILE")"
if [[ -z "$rust_channel" ]]; then
  printf 'Could not read Rust channel from %s\n' "$RUST_TOOLCHAIN_FILE" >&2
  exit 1
fi

if ! command -v rustup >/dev/null 2>&1; then
  printf 'Required developer tool is missing: rustup\n' >&2
  exit 1
fi

if (( $# == 0 )); then
  printf 'Usage: %s <command> [argument ...]\n' "${BASH_SOURCE[0]}" >&2
  exit 2
fi

# Keep deployment-target policy before Cargo sees the invocation so native
# dependency build scripts and Rust compilation receive the same inputs.
# shellcheck disable=SC1091
export ARGUS_MACOS_RUST_CHANNEL="$rust_channel"
source "$ROOT_DIR/scripts/macos_rust_build_environment.sh"
argus_configure_macos_rust_build_environment "$(uname -s)" "$(uname -m)" "$@"
unset ARGUS_MACOS_RUST_CHANNEL

# Converts rustup's Cargo path to an absolute Git Bash path and removes the
# executable component without passing native Windows paths to POSIX dirname.
rust_toolchain_bin_from_cargo_path() {
  local cargo_path="$1"
  local drive_letter
  local rust_toolchain_bin

  cargo_path="${cargo_path//$'\r'/}"
  cargo_path="${cargo_path//\\//}"

  if [[ "$cargo_path" =~ ^([[:alpha:]]):(/.*)$ ]]; then
    drive_letter="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    cargo_path="/$drive_letter${BASH_REMATCH[2]}"
  fi

  if [[ "$cargo_path" != /* || "$cargo_path" == */ ]]; then
    printf 'Rustup returned an invalid Cargo executable path: %s\n' "$cargo_path" >&2
    return 1
  fi

  rust_toolchain_bin="${cargo_path%/*}"
  if [[ -z "$rust_toolchain_bin" || "$rust_toolchain_bin" == "$cargo_path" ]]; then
    printf 'Could not resolve the Rust toolchain directory from: %s\n' "$cargo_path" >&2
    return 1
  fi

  printf '%s\n' "$rust_toolchain_bin"
}

if ! cargo_path="$(RUSTUP_TOOLCHAIN="$rust_channel" rustup which cargo)"; then
  printf 'Could not locate Cargo for Rust toolchain %s.\n' "$rust_channel" >&2
  exit 1
fi

rust_toolchain_bin="$(rust_toolchain_bin_from_cargo_path "$cargo_path")"
if [[ ! -d "$rust_toolchain_bin" ]]; then
  printf 'Resolved Rust toolchain directory does not exist: %s\n' "$rust_toolchain_bin" >&2
  exit 1
fi

# Pass the native environment assignments after policy evaluation. This
# preserves cc-rs variable names such as CFLAGS_aarch64-apple-darwin, which
# cannot be represented as Bash variables.
if (( ${#ARGUS_MACOS_ENV_ASSIGNMENTS[@]} > 0 )); then
  exec env "${ARGUS_MACOS_ENV_ASSIGNMENTS[@]}" \
    PATH="$rust_toolchain_bin:$PATH" rustup run "$rust_channel" "$@"
fi

exec env PATH="$rust_toolchain_bin:$PATH" rustup run "$rust_channel" "$@"
