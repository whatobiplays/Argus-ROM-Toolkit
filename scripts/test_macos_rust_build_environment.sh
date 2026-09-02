#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/macos_rust_build_environment.sh"

fail() {
  printf 'macOS Rust build contract failed: %s\n' "$1" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  [[ "$expected" == "$actual" ]] ||
    fail "$description (expected '$expected', got '$actual')"
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local description="$3"
  [[ "$haystack" == *"$needle"* ]] ||
    fail "$description (missing '$needle' in '$haystack')"
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local description="$3"
  [[ "$haystack" != *"$needle"* ]] ||
    fail "$description (unexpected '$needle')"
}

assert_unset() {
  local name="$1"
  if declare -p "$name" >/dev/null 2>&1; then
    fail "$name should be unset"
  fi
}

assert_declared() {
  local name="$1"
  declare -p "$name" >/dev/null 2>&1 || fail "$name should be set"
}

assert_occurrences() {
  local needle="$1"
  local value="$2"
  local expected_count="$3"
  local description="$4"
  local remainder="$value"
  local actual_count=0

  while [[ "$remainder" == *"$needle"* ]]; do
    remainder="${remainder#*"$needle"}"
    actual_count=$((actual_count + 1))
  done

  assert_equal "$expected_count" "$actual_count" "$description"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if ! rg -Fq -- "$needle" "$path"; then
    fail "$path should contain '$needle'"
  fi
}

assert_file_not_contains() {
  local path="$1"
  local needle="$2"
  if rg -Fq -- "$needle" "$path"; then
    fail "$path should not contain '$needle'"
  fi
}

reset_policy_environment() {
  unset MACOSX_DEPLOYMENT_TARGET
  unset CARGO_BUILD_TARGET
  unset RUSTFLAGS
  unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
}

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_equal "11.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "native arm64 macOS should receive the default deployment target"
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$RUSTFLAGS" \
  "native arm64 macOS should receive a deployment-target fingerprint"
assert_occurrences "-C metadata=argus-macos-deployment-target-" \
  "$RUSTFLAGS" 1 \
  "native arm64 macOS should receive one deployment-target fingerprint"

argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_occurrences "-C metadata=argus-macos-deployment-target-" \
  "$RUSTFLAGS" 1 \
  "reapplying the policy should not duplicate the fingerprint"

reset_policy_environment
export MACOSX_DEPLOYMENT_TARGET=26.5
export RUSTFLAGS="-C opt-level=1"
export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="-C opt-level=1"
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_equal "26.5" "$MACOSX_DEPLOYMENT_TARGET" \
  "an explicit deployment target must be preserved"
assert_contains "-C opt-level=1" "$RUSTFLAGS" \
  "existing global Rust flags must be preserved"
assert_contains "-C opt-level=1" \
  "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
  "existing target-specific Rust flags must be preserved"
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$RUSTFLAGS" \
  "an explicit deployment target must be fingerprinted"

reset_policy_environment
export MACOSX_DEPLOYMENT_TARGET=""
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_declared MACOSX_DEPLOYMENT_TARGET
assert_equal "" "$MACOSX_DEPLOYMENT_TARGET" \
  "an explicitly empty deployment target must not be replaced"
assert_contains "-C metadata=argus-macos-deployment-target-" "$RUSTFLAGS" \
  "an explicitly empty deployment target must be fingerprinted"

reset_policy_environment
export CARGO_BUILD_TARGET=aarch64-linux-android
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
  --target=aarch64-linux-android
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
  --target aarch64-linux-android
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
  --target aarch64-apple-darwin
assert_equal "11.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "an explicit native arm64 target should receive the default"
assert_contains "-C metadata=argus-macos-deployment-target-" "$RUSTFLAGS" \
  "an explicit native arm64 target should receive a fingerprint"

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo ndk build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Linux x86_64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin x86_64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 rustc --version
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

assert_file_contains "$ROOT_DIR/scripts/run_phase_000_native_tests.sh" \
  "scripts/run_rust.sh"
assert_file_contains "$ROOT_DIR/scripts/run_phase_001_native_tests.sh" \
  "scripts/run_rust.sh"
assert_file_contains "$ROOT_DIR/flutter/linux/CMakeLists.txt" \
  "scripts/run_rust.sh"
assert_file_contains "$ROOT_DIR/flutter/windows/CMakeLists.txt" \
  "scripts/run_rust.sh"
assert_file_contains "$ROOT_DIR/scripts/build_android_bridge.sh" \
  "scripts/run_rust.sh"
assert_file_contains "$ROOT_DIR/flutter/macos/Runner.xcodeproj/project.pbxproj" \
  "scripts/run_rust.sh"

xcode_project="$ROOT_DIR/flutter/macos/Runner.xcodeproj/project.pbxproj"
xcode_settings="$(<"$xcode_project")"
assert_occurrences "ARCHS = arm64;" "$xcode_settings" 3 \
  "all macOS product configurations must be arm64-only"
assert_occurrences "MACOSX_DEPLOYMENT_TARGET = 11.0;" "$xcode_settings" 3 \
  "all macOS product configurations must use the arm64 deployment floor"
assert_file_not_contains "$xcode_project" \
  "MACOSX_DEPLOYMENT_TARGET = 10.15;"
assert_file_contains "$xcode_project" \
  "rust/target/\$(CONFIGURATION)/libargus_bridge.a"

printf 'macOS Rust build contract: PASS\n'
