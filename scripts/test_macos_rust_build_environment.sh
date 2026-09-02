#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_CHANNEL="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
encoded_separator=$'\x1f'

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/macos_rust_build_environment.sh"
ARGUS_MACOS_RUST_CHANNEL="$RUST_CHANNEL"

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
  unset TARGET_CFLAGS
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
export TARGET_CFLAGS="-DARGUS_LOWER_PRIORITY_FLAG=1"
export CFLAGS="-DARGUS_PLAIN_FLAG=1"
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
assert_not_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$TARGET_CFLAGS" \
  "lower-priority TARGET_CFLAGS must not receive the native fingerprint"
assert_not_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS" \
  "lower-priority CFLAGS must not receive the native fingerprint"
assert_contains "-DARGUS_PLAIN_FLAG=1" "$CFLAGS" \
  "lower-priority CFLAGS must remain unchanged"

reset_policy_environment
export TARGET_CFLAGS="-DARGUS_CALLER_FLAG=target"
export CFLAGS="-DARGUS_LOWER_PRIORITY_FLAG=plain"
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_contains "-DARGUS_CALLER_FLAG=target" "$TARGET_CFLAGS" \
  "TARGET_CFLAGS must remain effective when it is the highest defined source"
assert_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$TARGET_CFLAGS" \
  "TARGET_CFLAGS must receive the native fingerprint"
assert_not_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS" \
  "plain CFLAGS must not receive the fingerprint when TARGET_CFLAGS is defined"

reset_policy_environment
# shellcheck disable=SC2016
hyphenated_cflags_output="$(
  env \
    'CFLAGS_aarch64-apple-darwin=-DARGUS_CALLER_FLAG=hyphen' \
    'CFLAGS_aarch64_apple_darwin=-DARGUS_LOWER_PRIORITY_FLAG=underscore' \
    'TARGET_CFLAGS=-DARGUS_LOWER_PRIORITY_FLAG=target' \
    'CFLAGS=-DARGUS_LOWER_PRIORITY_FLAG=plain' \
    bash -euc '
      source "$1"
      argus_configure_macos_rust_build_environment Darwin arm64 cargo build
      printf "%s\n" "${ARGUS_MACOS_ENV_ASSIGNMENTS[0]-}"
    ' bash "$ROOT_DIR/scripts/macos_rust_build_environment.sh"
)"
assert_contains "CFLAGS_aarch64-apple-darwin=-DARGUS_CALLER_FLAG=hyphen" \
  "$hyphenated_cflags_output" \
  "the hyphenated target C flag source must be selected first"
assert_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$hyphenated_cflags_output" \
  "the hyphenated target C flag source must receive the native fingerprint"
# shellcheck disable=SC2016
assert_file_contains "$ROOT_DIR/scripts/run_rust.sh" \
  'exec env "${ARGUS_MACOS_ENV_ASSIGNMENTS[@]}"'
# shellcheck disable=SC2016
assert_file_contains "$ROOT_DIR/scripts/run_rust.sh" \
  'PATH="$rust_toolchain_bin:$PATH" rustup run'

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
assert_file_contains "$ROOT_DIR/justfile" "build-macos-debug:"
assert_file_contains "$ROOT_DIR/justfile" \
  "fvm flutter build macos --debug --no-pub"

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

run_pinned_cargo_cli_config_rustc_probe() {
  local target_directory="$1"
  local config_value="$2"
  local log_file

  mkdir -p "$target_directory"
  log_file="$target_directory/cargo-verbose.log"
  if ! RUSTUP_TOOLCHAIN="$RUST_CHANNEL" rustup run "$RUST_CHANNEL" cargo \
    --config "$config_value" rustc \
    --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --package argus-domain --lib \
    --target "$ARGUS_MACOS_RUST_TARGET" \
    --target-dir "$target_directory" \
    -vv >"$log_file" 2>&1; then
    fail "pinned Cargo CLI config rustc probe failed; inspect $log_file"
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

  run_config_rustflags_probe() {
    local probe_name="$1"
    local config_value="$2"
    local probe_log

    reset_policy_environment
    argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
      --target "$ARGUS_MACOS_RUST_TARGET" --config "$config_value"
    probe_log="$(run_pinned_cargo_rustc_probe \
      "$cargo_probe_root/$probe_name" --config "$config_value")"
    assert_file_contains "$probe_log" "-C opt-level=1"
    assert_file_contains "$probe_log" \
      "metadata=argus-macos-deployment-target-"
  }

  target_config_with_whitespace='target.aarch64-apple-darwin.rustflags = ["-C", "opt-level=1"]'
  run_config_rustflags_probe target-config-whitespace \
    "$target_config_with_whitespace"

  matching_cfg_config="target.'cfg(all(target_arch = \"aarch64\", target_os = \"macos\"))'.rustflags=[\"-C\",\"opt-level=1\"]"
  run_config_rustflags_probe matching-cfg-inline-config "$matching_cfg_config"

  matching_cfg_config_with_whitespace="target.'cfg(all(target_arch = \"aarch64\", target_os = \"macos\"))'.rustflags = [\"-C\", \"opt-level=1\"]"
  run_config_rustflags_probe matching-cfg-config-whitespace \
    "$matching_cfg_config_with_whitespace"

  matching_cfg_config_file="$cargo_probe_root/matching-cfg-config.toml"
  printf '%s\n' \
    "[target.'cfg(all(target_arch = \"aarch64\", target_os = \"macos\"))']" \
    'rustflags = ["-C", "opt-level=1"]' >"$matching_cfg_config_file"
  reset_policy_environment
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET" --config "$matching_cfg_config_file"
  assert_contains "-C metadata=argus-macos-deployment-target-" \
    "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
    "a matching cfg target table must receive an additive fingerprint"
  assert_unset CARGO_BUILD_RUSTFLAGS
  matching_cfg_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/matching-cfg-config" \
    --config "$matching_cfg_config_file")"
  assert_file_contains "$matching_cfg_probe_log" "-C opt-level=1"
  assert_file_contains "$matching_cfg_probe_log" \
    "metadata=argus-macos-deployment-target-"

  included_config_root="$cargo_probe_root/included-config"
  mkdir -p "$included_config_root/nested"
  included_config_file="$included_config_root/root.toml"
  included_target_config_file="$included_config_root/included-target.toml"
  printf '%s\n' 'include = ["included-target.toml"]' >"$included_config_file"
  printf '%s\n' \
    "[target.'cfg(target_os = \"macos\")']" \
    'rustflags = ["-C", "opt-level=1"]' >"$included_target_config_file"
  run_config_rustflags_probe included-config "$included_config_file"

  recursive_config_file="$included_config_root/recursive-root.toml"
  recursive_nested_config_file="$included_config_root/nested/recursive-level-one.toml"
  recursive_target_config_file="$included_config_root/nested/recursive-level-two.toml"
  printf '%s\n' 'include = ["nested/recursive-level-one.toml"]' \
    >"$recursive_config_file"
  printf '%s\n' 'include = ["recursive-level-two.toml"]' \
    >"$recursive_nested_config_file"
  printf '%s\n' \
    '[target.aarch64-apple-darwin]' \
    'rustflags = ["-C", "opt-level=1"]' >"$recursive_target_config_file"
  run_config_rustflags_probe recursive-included-config "$recursive_config_file"

  cli_include_root="$cargo_probe_root/cli-included-config"
  mkdir -p "$cli_include_root/configs"
  cli_cargo_home="$cli_include_root/cargo-home"
  mkdir -p "$cli_cargo_home"
  cli_include_target_config_file="$cli_include_root/configs/target.toml"
  printf '%s\n' \
    '[target.aarch64-apple-darwin]' \
    'rustflags = ["-C", "opt-level=1"]' >"$cli_include_target_config_file"

  run_cli_config_rustflags_probe() {
    local probe_name="$1"
    local config_value="$2"
    local probe_log

    probe_log="$(
      cd "$cli_include_root"
      reset_policy_environment
      CARGO_HOME="$cli_cargo_home" \
        argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
        --target "$ARGUS_MACOS_RUST_TARGET" --config "$config_value"
      assert_contains "-C metadata=argus-macos-deployment-target-" \
        "${CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS-}" \
        "a CLI include target source must receive an additive fingerprint"
      assert_unset CARGO_BUILD_RUSTFLAGS
      CARGO_HOME="$cli_cargo_home" \
        run_pinned_cargo_cli_config_rustc_probe \
        "$cargo_probe_root/$probe_name" "$config_value"
    )"
    assert_file_contains "$probe_log" "-C opt-level=1"
    assert_file_contains "$probe_log" \
      "metadata=argus-macos-deployment-target-"
  }

  run_cli_config_rustflags_probe cli-string-include \
    'include = ["configs/target.toml"]'
  run_cli_config_rustflags_probe cli-inline-table-include \
    'include = [{ path = "configs/target.toml" }]'

  optional_cli_config='include = [{ path = "missing.toml", optional = true }]'
  optional_cli_probe_log="$(
    cd "$cli_include_root"
    reset_policy_environment
    CARGO_HOME="$cli_cargo_home" \
      argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
      --target "$ARGUS_MACOS_RUST_TARGET" --config "$optional_cli_config"
    assert_contains "-C metadata=argus-macos-deployment-target-" \
      "${CARGO_BUILD_RUSTFLAGS-}" \
      "an optional CLI include without target flags must use build rustflags"
    assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
    CARGO_HOME="$cli_cargo_home" \
      run_pinned_cargo_cli_config_rustc_probe \
      "$cargo_probe_root/optional-cli-include" "$optional_cli_config"
  )"
  assert_file_contains "$optional_cli_probe_log" \
    "metadata=argus-macos-deployment-target-"

  multiple_config_build_file="$included_config_root/multiple-build.toml"
  multiple_config_target_file="$included_config_root/multiple-target.toml"
  printf '%s\n' \
    '[build]' \
    'rustflags = ["-C", "opt-level=1"]' >"$multiple_config_build_file"
  printf '%s\n' \
    '[target.aarch64-apple-darwin]' \
    'rustflags = ["-C", "opt-level=1"]' >"$multiple_config_target_file"
  reset_policy_environment
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET" \
    --config "$multiple_config_build_file" \
    --config "$multiple_config_target_file"
  multiple_config_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/multiple-config-files" \
    --config "$multiple_config_build_file" \
    --config "$multiple_config_target_file")"
  assert_file_contains "$multiple_config_probe_log" "-C opt-level=1"
  assert_file_contains "$multiple_config_probe_log" \
    "metadata=argus-macos-deployment-target-"

  optional_config_file="$included_config_root/optional-config.toml"
  printf '%s\n' \
    'include = [' \
    '  { path = "missing-optional.toml", optional = true },' \
    ']' \
    '[build]' \
    'rustflags = ["-C", "opt-level=1"]' >"$optional_config_file"
  run_config_rustflags_probe optional-included-config "$optional_config_file"

  cycle_config_file="$included_config_root/cycle-root.toml"
  cycle_nested_config_file="$included_config_root/cycle-nested.toml"
  printf '%s\n' 'include = ["cycle-nested.toml"]' >"$cycle_config_file"
  printf '%s\n' 'include = ["cycle-root.toml"]' >"$cycle_nested_config_file"
  if argus_cargo_config_file_has_native_target_rustflags "$cycle_config_file"; then
    fail "an include cycle without target flags must not report a target source"
  fi

  precedence_root="$cargo_probe_root/config-precedence"
  mkdir -p "$precedence_root/.cargo" "$precedence_root/cargo-home"
  printf '%s\n' \
    '[build]' \
    'rustflags = ["-C", "opt-level=1"]' >"$precedence_root/.cargo/config"
  printf '%s\n' \
    "[target.'cfg(target_os = \"macos\")']" \
    'rustflags = ["-C", "opt-level=2"]' \
    >"$precedence_root/.cargo/config.toml"
  precedence_probe_log="$(
    cd "$precedence_root"
    export CARGO_HOME="$precedence_root/cargo-home"
    reset_policy_environment
    argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
      --target "$ARGUS_MACOS_RUST_TARGET"
    assert_contains "-C metadata=argus-macos-deployment-target-" \
      "${CARGO_BUILD_RUSTFLAGS-}" \
      "active .cargo/config build flags must receive the deployment marker"
    assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
    run_pinned_cargo_rustc_probe "$precedence_root/target"
  )"
  assert_file_contains "$precedence_probe_log" "-C opt-level=1"
  assert_file_contains "$precedence_probe_log" \
    "metadata=argus-macos-deployment-target-"
  assert_file_not_contains "$precedence_probe_log" "-C opt-level=2"

  if ! argus_cfg_expression_matches_target \
    'all(target_arch = "aarch64", target_os = "macos")'; then
    fail "matching all(...) cfg expression should match the native target"
  fi
  if argus_cfg_expression_matches_target \
    'any(target_os = "ios", target_arch = "x86_64")'; then
    fail "non-matching any(...) cfg expression should not match the native target"
  fi
  if ! argus_cfg_expression_matches_target \
    'any(target_os = "ios", not(target_os = "ios"))'; then
    fail "nested not(...) cfg expression should be evaluated"
  fi
  if ! argus_cfg_expression_matches_target \
    'target = "aarch64-apple-darwin"'; then
    fail "the Cargo target-name cfg predicate should match the native target"
  fi

  dotted_cfg_config_file="$cargo_probe_root/dotted-cfg-config.toml"
  printf '%s\n' \
    "target.'cfg(target_os = \"macos\")'.rustflags = [\"-C\", \"opt-level=1\"]" \
    >"$dotted_cfg_config_file"
  reset_policy_environment
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET" --config "$dotted_cfg_config_file"
  assert_contains "-C metadata=argus-macos-deployment-target-" \
    "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
    "a dotted matching cfg target table must receive an additive fingerprint"

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
