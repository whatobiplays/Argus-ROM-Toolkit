#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_CHANNEL="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
encoded_separator=$'\x1f'

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
  unset CARGO_BUILD_RUSTFLAGS
  unset RUSTFLAGS
  unset CARGO_ENCODED_RUSTFLAGS
  unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
  unset CFLAGS
  unset CFLAGS_aarch64_apple_darwin
}

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_equal "11.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "native arm64 macOS should receive the default deployment target"
assert_unset RUSTFLAGS
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "native arm64 macOS should receive a Cargo deployment-target fingerprint"
assert_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS" \
  "native arm64 macOS should receive a native deployment-target fingerprint"
assert_occurrences "argus-macos-deployment-target-" \
  "$CARGO_BUILD_RUSTFLAGS" 1 \
  "native arm64 macOS should receive one Cargo deployment-target fingerprint"

argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_occurrences "-C metadata=argus-macos-deployment-target-" \
  "$CARGO_BUILD_RUSTFLAGS" 1 \
  "reapplying the policy should not duplicate the fingerprint"
assert_occurrences "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS" 1 \
  "reapplying the policy should not duplicate the native fingerprint"

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
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
  "the effective target-specific Rust flags must receive the fingerprint"
assert_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS" \
  "an explicit deployment target must fingerprint native flags"

reset_policy_environment
export CARGO_BUILD_RUSTFLAGS="-C debuginfo=1"
export CFLAGS_aarch64_apple_darwin="-DARGUS_CALLER_FLAG=1"
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_contains "-C debuginfo=1" "$CARGO_BUILD_RUSTFLAGS" \
  "an existing additive Cargo Rust flag must remain effective"
assert_contains "metadata=argus-macos-deployment-target-" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "an existing additive Cargo Rust flag source must receive the fingerprint"
assert_contains "-DARGUS_CALLER_FLAG=1" \
  "$CFLAGS_aarch64_apple_darwin" \
  "an existing target-specific C flag must remain effective"
assert_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS_aarch64_apple_darwin" \
  "the effective target-specific C flag source must receive the fingerprint"
assert_unset CFLAGS

reset_policy_environment
export MACOSX_DEPLOYMENT_TARGET=""
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_declared MACOSX_DEPLOYMENT_TARGET
assert_equal "11.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "an explicitly empty deployment target must resolve to the default"
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "an explicitly empty deployment target must use the default fingerprint"

reset_policy_environment
export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
export RUSTFLAGS="-C debuginfo=1"
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_equal "-C debuginfo=1" "$RUSTFLAGS" \
  "an encoded Rust flag source must not mutate the lower-precedence RUSTFLAGS"
assert_contains "opt-level=1" "$CARGO_ENCODED_RUSTFLAGS" \
  "existing encoded Rust flags must remain present"
assert_contains "metadata=argus-macos-deployment-target-" \
  "$CARGO_ENCODED_RUSTFLAGS" \
  "the encoded Rust flag source must receive the fingerprint"
assert_unset CARGO_BUILD_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
  --target aarch64-apple-darwin \
  --config 'build.rustflags=["-C","opt-level=1"]'
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "the build.rustflags path must receive an additive fingerprint"
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
  --target aarch64-apple-darwin \
  --config 'target.aarch64-apple-darwin.rustflags=["-C","opt-level=1"]'
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
  "the target-specific Cargo config path must receive an additive fingerprint"
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS

reset_policy_environment
if unsupported_target_output="$(
  argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
    --target x86_64-apple-darwin 2>&1
)"; then
  fail "Intel macOS target must be rejected"
fi
assert_contains "support only aarch64-apple-darwin" "$unsupported_target_output" \
  "Intel macOS target rejection must name the supported target"

reset_policy_environment
if unsupported_host_output="$(
  argus_configure_macos_rust_build_environment Darwin x86_64 cargo build 2>&1
)"; then
  fail "Intel macOS host builds must be rejected"
fi
assert_contains "Apple Silicon" "$unsupported_host_output" \
  "Intel macOS host rejection must identify the supported host"

reset_policy_environment
export CARGO_BUILD_TARGET=aarch64-linux-android
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS
assert_unset CARGO_ENCODED_RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
assert_unset CFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
  --target=aarch64-linux-android
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS
assert_unset CARGO_ENCODED_RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
assert_unset CFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
  --target aarch64-linux-android
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS
assert_unset CARGO_ENCODED_RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
assert_unset CFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
  --target aarch64-apple-darwin
assert_equal "11.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "an explicit native arm64 target should receive the default"
assert_contains "-C metadata=argus-macos-deployment-target-" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "an explicit native arm64 target should receive a fingerprint"

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo ndk build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS
assert_unset CARGO_ENCODED_RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
assert_unset CFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Linux x86_64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS
assert_unset CARGO_ENCODED_RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
assert_unset CFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Windows x86_64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS
assert_unset CARGO_ENCODED_RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
assert_unset CFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 rustc --version
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset RUSTFLAGS
assert_unset CARGO_BUILD_RUSTFLAGS
assert_unset CARGO_ENCODED_RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
assert_unset CFLAGS

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

run_pinned_cargo_rustc_probe() {
  local target_directory="$1"
  local log_file
  shift

  mkdir -p "$target_directory"
  log_file="$target_directory/cargo-verbose.log"
  if ! RUSTUP_TOOLCHAIN="$RUST_CHANNEL" rustup run "$RUST_CHANNEL" cargo rustc \
    --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --package argus-domain --lib \
    --target "$ARGUS_MACOS_RUST_TARGET" \
    --target-dir "$target_directory" \
    "$@" -vv >"$log_file" 2>&1; then
    fail "pinned Cargo rustc probe failed; inspect $log_file"
  fi

  printf '%s\n' "$log_file"
}

run_pinned_cargo_build_probe() {
  local target_directory="$1"
  local log_file
  shift

  mkdir -p "$target_directory"
  log_file="$target_directory/cargo-build.log"
  if ! RUSTUP_TOOLCHAIN="$RUST_CHANNEL" rustup run "$RUST_CHANNEL" cargo build \
    --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --package argus-domain --lib --locked \
    --target "$ARGUS_MACOS_RUST_TARGET" \
    --target-dir "$target_directory" \
    "$@" >"$log_file" 2>&1; then
    fail "pinned Cargo build probe failed; inspect $log_file"
  fi

  printf '%s\n' "$log_file"
}

if [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] &&
  command -v rustup >/dev/null 2>&1 && [[ -n "$RUST_CHANNEL" ]]; then
  cargo_probe_root="$(mktemp -d)"
  trap 'rm -rf "$cargo_probe_root"' EXIT

  reset_policy_environment
  export RUSTFLAGS="-C opt-level=1"
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET"
  rustflags_probe_log="$(run_pinned_cargo_rustc_probe "$cargo_probe_root/rustflags")"
  assert_file_contains "$rustflags_probe_log" "-C opt-level=1"
  assert_file_contains "$rustflags_probe_log" \
    "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET"
  encoded_probe_log="$(run_pinned_cargo_rustc_probe "$cargo_probe_root/encoded")"
  assert_file_contains "$encoded_probe_log" "opt-level=1"
  assert_file_contains "$encoded_probe_log" \
    "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="-C opt-level=1"
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET"
  target_environment_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/target-environment")"
  assert_file_contains "$target_environment_probe_log" "-C opt-level=1"
  assert_file_contains "$target_environment_probe_log" \
    "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  build_config='build.rustflags=["-C","opt-level=1"]'
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET" --config "$build_config"
  build_config_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/build-config" --config "$build_config")"
  assert_file_contains "$build_config_probe_log" "-C opt-level=1"
  assert_file_contains "$build_config_probe_log" \
    "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  target_config='target.aarch64-apple-darwin.rustflags=["-C","opt-level=1"]'
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET" --config "$target_config"
  target_config_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/target-config" --config "$target_config")"
  assert_file_contains "$target_config_probe_log" "-C opt-level=1"
  assert_file_contains "$target_config_probe_log" \
    "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
  export MACOSX_DEPLOYMENT_TARGET=26.5
  argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
    --target "$ARGUS_MACOS_RUST_TARGET"
  encoded_transition_directory="$cargo_probe_root/encoded-transition"
  first_transition_log="$(run_pinned_cargo_build_probe \
    "$encoded_transition_directory")"
  assert_file_contains "$first_transition_log" "Compiling argus-domain"

  reset_policy_environment
  export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
  export MACOSX_DEPLOYMENT_TARGET=11.0
  argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
    --target "$ARGUS_MACOS_RUST_TARGET"
  second_transition_log="$(run_pinned_cargo_build_probe \
    "$encoded_transition_directory")"
  assert_file_contains "$second_transition_log" "Compiling argus-domain"
  assert_file_not_contains "$second_transition_log" "Fresh argus-domain"
else
  printf 'Pinned Cargo effective rustflags probes: SKIP (requires Darwin arm64 and rustup)\n'
fi

printf 'macOS Rust build contract: PASS\n'
