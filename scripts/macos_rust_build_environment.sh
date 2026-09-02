#!/usr/bin/env bash
set -euo pipefail

ARGUS_MACOS_RUST_TARGET="aarch64-apple-darwin"
ARGUS_MACOS_DEPLOYMENT_TARGET_DEFAULT="11.0"

# Cargo accepts the target from either the environment or the command line.
# The command-line form wins, matching Cargo's precedence rules for an
# invocation that explicitly names a cross-compilation target.
argus_cargo_target_from_arguments() {
  local target="${CARGO_BUILD_TARGET:-}"
  local expects_target=false
  local argument

  for argument in "$@"; do
    if [[ "$expects_target" == true ]]; then
      target="$argument"
      expects_target=false
      continue
    fi

    case "$argument" in
      --target=*) target="${argument#--target=}" ;;
      --target) expects_target=true ;;
    esac
  done

  printf '%s\n' "$target"
}

# Convert the deployment target into shell-safe bytes for the Cargo metadata
# salt. This keeps an unusual explicit value from becoming executable flag
# text while still making every distinct value a distinct Cargo input.
argus_deployment_target_fingerprint() {
  local deployment_target="$1"

  if [[ -z "$deployment_target" ]]; then
    printf 'empty\n'
    return 0
  fi

  printf '%s' "$deployment_target" |
    LC_ALL=C od -An -v -tx1 |
    tr -d '[:space:]'
  printf '\n'
}

# Configure the environment shared by the Rust compiler and native C build
# scripts. The host parameters are explicit so the contract can be tested on
# a non-macOS machine without pretending that its uname output is different.
argus_configure_macos_rust_build_environment() {
  local host_os="$1"
  local host_arch="$2"
  shift 2

  if [[ "$host_os" != Darwin || "$host_arch" != arm64 ]]; then
    return 0
  fi

  if [[ "${1:-}" != cargo || "${2:-}" == ndk ]]; then
    return 0
  fi

  local cargo_target
  cargo_target="$(argus_cargo_target_from_arguments "$@")"
  if [[ -n "$cargo_target" && "$cargo_target" != "$ARGUS_MACOS_RUST_TARGET" ]]; then
    return 0
  fi

  # Native dependency build scripts, including BLAKE3's C compiler setup,
  # consume this value when compiling objects for the arm64 macOS product.
  if [[ -z "${MACOSX_DEPLOYMENT_TARGET+x}" ]]; then
    export MACOSX_DEPLOYMENT_TARGET="$ARGUS_MACOS_DEPLOYMENT_TARGET_DEFAULT"
  fi

  local deployment_target_fingerprint
  local deployment_target_salt
  local existing_rustflags
  deployment_target_fingerprint="$(argus_deployment_target_fingerprint "$MACOSX_DEPLOYMENT_TARGET")"
  deployment_target_salt="-C metadata=argus-macos-deployment-target-${deployment_target_fingerprint}"
  existing_rustflags="${RUSTFLAGS:-}"

  # This semantically inert Rust flag changes Cargo's shared fingerprint
  # whenever the deployment target changes. Global RUSTFLAGS reaches the
  # dependency build-script path as well as the final crate, so the static
  # archive cannot retain stale native or Rust members from shared target/.
  if [[ " $existing_rustflags " != *" $deployment_target_salt "* ]]; then
    if [[ -n "$existing_rustflags" ]]; then
      existing_rustflags+=" "
    fi
    export RUSTFLAGS="${existing_rustflags}${deployment_target_salt}"
  fi
}
