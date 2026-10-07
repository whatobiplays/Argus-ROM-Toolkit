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

# Fails when any effective Rust flag source still carries the retired Cargo
# metadata deployment marker. The deployment fingerprint must only ever appear
# as the benign `--cfg=` marker so Cargo keeps ownership of crate identity.
assert_no_cargo_metadata_deployment_marker() {
  local variable_name
  local value
  for variable_name in \
    CARGO_ENCODED_RUSTFLAGS \
    RUSTFLAGS \
    CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS \
    CARGO_BUILD_RUSTFLAGS; do
    value="${!variable_name-}"
    if [[ "$value" == *"metadata=argus-macos-deployment-target-"* ]]; then
      fail "effective Rust flags ($variable_name injects a Cargo metadata deployment marker)"
    fi
  done
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

assert_file_matches() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  if ! rg -q -- "$pattern" "$path"; then
    fail "$description ($path should match '$pattern')"
  fi
}

# The workspace Release profile must keep build-time crates (build scripts,
# proc macros, and their dependencies) unstripped. rust-lang/rust issue
# #157750: the debuginfo stripping pass can emit host dylibs with a misaligned
# Mach-O LC_SYMTAB string pool on current macOS toolchains; dyld rejects those
# dylibs, and rustc then reports proc macros as missing crates (E0463).
assert_release_build_override_disables_stripping() {
  local manifest="$ROOT_DIR/rust/Cargo.toml"
  if ! awk '
    /^\[profile\.release\.build-override\][[:space:]]*$/ { in_override = 1; next }
    /^\[/ { in_override = 0 }
    in_override && /^[[:space:]]*strip[[:space:]]*=[[:space:]]*"none"[[:space:]]*$/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$manifest"; then
    fail 'rust/Cargo.toml must keep [profile.release.build-override] strip = "none"'
  fi
}

# ARGUS_RUST_PROFILE is the single Xcode-configuration-to-Cargo-profile mapping
# shared by the native bridge build phase's declared archive output and its
# Cargo invocation. Resolving it through xcodebuild proves Debug, Release, and
# Profile cannot silently drift from the archive paths their force_load linker
# flags consume.
assert_effective_argus_rust_profile() {
  local configuration="$1"
  local expected="$2"
  local project_dir
  local settings
  project_dir="$(dirname "$xcode_project")"
  settings="$(xcodebuild -project "$project_dir" -target Runner \
    -configuration "$configuration" -showBuildSettings 2>/dev/null)" ||
    fail "xcodebuild could not resolve $configuration build settings"
  assert_contains "ARGUS_RUST_PROFILE = $expected" "$settings" \
    "$configuration configuration must resolve ARGUS_RUST_PROFILE to $expected"
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
assert_equal "12.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "native arm64 macOS should receive the default deployment target"
assert_unset RUSTFLAGS
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "native arm64 macOS should receive a Cargo deployment-target fingerprint"
assert_no_cargo_metadata_deployment_marker
assert_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS" \
  "native arm64 macOS should receive a native deployment-target fingerprint"
assert_occurrences "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_BUILD_RUSTFLAGS" 1 \
  "native arm64 macOS should receive one Cargo deployment-target fingerprint"
assert_no_cargo_metadata_deployment_marker

argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_occurrences "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_BUILD_RUSTFLAGS" 1 \
  "reapplying the policy should not duplicate the fingerprint"
assert_no_cargo_metadata_deployment_marker
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
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$RUSTFLAGS" \
  "an explicit deployment target must be fingerprinted"
assert_no_cargo_metadata_deployment_marker
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
  "the effective target-specific Rust flags must receive the fingerprint"
assert_no_cargo_metadata_deployment_marker
assert_contains "-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=" \
  "$CFLAGS" \
  "an explicit deployment target must fingerprint native flags"

reset_policy_environment
export RUSTFLAGS="-C metadata=caller-owned-metadata"
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_contains "-C metadata=caller-owned-metadata" "$RUSTFLAGS" \
  "a caller-supplied Cargo metadata flag must be preserved"
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$RUSTFLAGS" \
  "a caller-supplied Cargo metadata flag must not replace the fingerprint"
assert_no_cargo_metadata_deployment_marker

reset_policy_environment
export CARGO_BUILD_RUSTFLAGS="-C debuginfo=1"
export CFLAGS_aarch64_apple_darwin="-DARGUS_CALLER_FLAG=1"
export TARGET_CFLAGS="-DARGUS_LOWER_PRIORITY_FLAG=1"
export CFLAGS="-DARGUS_PLAIN_FLAG=1"
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_contains "-C debuginfo=1" "$CARGO_BUILD_RUSTFLAGS" \
  "an existing additive Cargo Rust flag must remain effective"
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "an existing additive Cargo Rust flag source must receive the fingerprint"
assert_no_cargo_metadata_deployment_marker
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
assert_equal "12.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "an explicitly empty deployment target must resolve to the default"
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "an explicitly empty deployment target must use the default fingerprint"
assert_no_cargo_metadata_deployment_marker

reset_policy_environment
export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
export RUSTFLAGS="-C debuginfo=1"
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_equal "-C debuginfo=1" "$RUSTFLAGS" \
  "an encoded Rust flag source must not mutate the lower-precedence RUSTFLAGS"
assert_contains "opt-level=1" "$CARGO_ENCODED_RUSTFLAGS" \
  "existing encoded Rust flags must remain present"
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_ENCODED_RUSTFLAGS" \
  "the encoded Rust flag source must receive the fingerprint"
assert_no_cargo_metadata_deployment_marker
assert_unset CARGO_BUILD_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
  --target aarch64-apple-darwin \
  --config 'build.rustflags=["-C","opt-level=1"]'
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "the build.rustflags path must receive an additive fingerprint"
assert_no_cargo_metadata_deployment_marker
assert_unset RUSTFLAGS
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

reset_policy_environment
argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
  --target aarch64-apple-darwin \
  --config 'target.aarch64-apple-darwin.rustflags=["-C","opt-level=1"]'
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
  "the target-specific Cargo config path must receive an additive fingerprint"
assert_no_cargo_metadata_deployment_marker
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
assert_equal "12.0" "$MACOSX_DEPLOYMENT_TARGET" \
  "an explicit native arm64 target should receive the default"
assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
  "$CARGO_BUILD_RUSTFLAGS" \
  "an explicit native arm64 target should receive a fingerprint"
assert_no_cargo_metadata_deployment_marker

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
assert_occurrences "MACOSX_DEPLOYMENT_TARGET = 12.0;" "$xcode_settings" 3 \
  "all macOS product configurations must use the arm64 deployment floor"
assert_file_not_contains "$xcode_project" \
  "MACOSX_DEPLOYMENT_TARGET = 10.15;"
assert_file_contains "$xcode_project" \
  "rust/target/\$(ARGUS_RUST_PROFILE)/libargus_bridge.a"
assert_file_not_contains "$xcode_project" \
  "rust/target/\$(CONFIGURATION)/libargus_bridge.a"
bridge_build_phase="$(rg -F 'run_rust.sh' "$xcode_project")"
assert_contains "\$ARGUS_RUST_PROFILE" "$bridge_build_phase" \
  "the native bridge build phase must choose its Cargo profile from ARGUS_RUST_PROFILE"
assert_not_contains "\$CONFIGURATION" "$bridge_build_phase" \
  "the native bridge build phase must not choose its Cargo profile from CONFIGURATION"
assert_contains 'profile=--release' "$bridge_build_phase" \
  "the native bridge build phase must map the release profile to Cargo --release"
# The linker consumes the archive through -force_load, so the phase that
# produces it must run before compile sources; otherwise the Xcode build
# graph reports a dependency cycle between the link command and the bridge
# build phase on a clean Debug build.
bridge_phase_line="$(rg -n -- '33CC11252044A8840003C045 /\* Build Argus native bridge \*/,$' "$xcode_project" | cut -d: -f1)"
sources_phase_line="$(rg -n -- '33CC10E92044A3C60003C045 /\* Sources \*/,$' "$xcode_project" | cut -d: -f1)"
if [[ -z "$bridge_phase_line" || -z "$sources_phase_line" ]]; then
  fail "the Runner build phase list must contain the native bridge phase and Sources"
fi
[[ "$bridge_phase_line" -lt "$sources_phase_line" ]] ||
  fail "the native bridge build phase must run before compile sources"
assert_file_contains "$ROOT_DIR/flutter/macos/Runner/Configs/Debug.xcconfig" \
  'ARGUS_RUST_PROFILE = debug'
assert_file_contains "$ROOT_DIR/flutter/macos/Runner/Configs/Release.xcconfig" \
  'ARGUS_RUST_PROFILE = release'
assert_effective_argus_rust_profile Debug debug
assert_effective_argus_rust_profile Release release
assert_effective_argus_rust_profile Profile release
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

# Builds one package into a shared target directory and keeps the log of that
# phase, so both sides of a deployment-target transition stay inspectable. The
# verbose log records whether each unit was compiled or reused, which lets the
# transition assert that a native build script reran instead of staying fresh.
run_pinned_native_cargo_build_probe() {
  local target_directory="$1"
  local package="$2"
  local log_name="$3"
  local log_file

  mkdir -p "$target_directory"
  log_file="$target_directory/$log_name"
  if ! RUSTUP_TOOLCHAIN="$RUST_CHANNEL" rustup run "$RUST_CHANNEL" cargo build \
    --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --package "$package" --lib --locked \
    --target "$ARGUS_MACOS_RUST_TARGET" \
    --target-dir "$target_directory" \
    -vv >"$log_file" 2>&1; then
    fail "pinned native Cargo build probe failed; inspect $log_file"
  fi

  printf '%s\n' "$log_file"
}

# Builds a product package in Release mode whose dependency graph contains host
# proc-macro crates from scratch in one output directory. The rust-lang/rust
# issue #157750 misalignment only appears in Release builds, where debuginfo
# stripping runs, so this probe must use the Release profile. Proc-macro crates
# are compiled for the running machine and loaded by rustc while it expands
# attributes and derives, so a successful Release build proves the real host
# build-time graph loads its proc macros under the normal policy.
run_pinned_proc_macro_build_probe() {
  local target_directory="$1"
  local log_file
  shift

  mkdir -p "$target_directory"
  log_file="$target_directory/cargo-build.log"
  if ! RUSTUP_TOOLCHAIN="$RUST_CHANNEL" rustup run "$RUST_CHANNEL" cargo build \
    --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --package argus-bridge --lib --release --locked \
    --target "$ARGUS_MACOS_RUST_TARGET" \
    --target-dir "$target_directory" \
    "$@" >"$log_file" 2>&1; then
    fail "pinned Release proc-macro build probe failed; inspect $log_file"
  fi

  printf '%s\n' "$log_file"
}

# Reports the minimum macOS version recorded by a Mach-O build-version command.
# Cargo keeps the objects that native build scripts produce as members of the
# Rust archives it links, so this reports the deployment target an artifact was
# actually compiled for.
argus_macho_minimum_os_version() {
  local path="$1"
  local version

  version="$(xcrun vtool -show-build "$path" 2>/dev/null |
    sed -n 's/^ *minos \([0-9][0-9.]*\)$/\1/p' | head -1)"
  if [[ -z "$version" ]]; then
    printf 'Could not read a minimum macOS version from %s\n' "$path" >&2
    return 1
  fi

  printf '%s\n' "$version"
}

# Print the Mach-O symbol-table string-pool offset (LC_SYMTAB.stroff) of a
# dylib. The 64-bit macOS loader requires that offset to stay 8-byte aligned;
# rust-lang/rust issue #157750 describes a stripping path that breaks it.
argus_macho_symtab_stroff() {
  local path="$1"
  local stroff

  stroff="$(otool -l "$path" 2>/dev/null | awk '
    /cmd LC_SYMTAB/ { in_symtab = 1; next }
    in_symtab && $1 == "stroff" { print $2; exit }
  ')"
  if [[ -z "$stroff" ]]; then
    printf 'Could not read LC_SYMTAB.stroff from %s\n' "$path" >&2
    return 1
  fi

  printf '%s\n' "$stroff"
}

# Succeeds when the first dotted version is not newer than the second.
argus_version_is_at_most() {
  local candidate="$1"
  local limit="$2"
  local candidate_major candidate_minor limit_major limit_minor

  candidate_major="${candidate%%.*}"
  candidate_minor="${candidate#*.}"
  candidate_minor="${candidate_minor%%.*}"
  limit_major="${limit%%.*}"
  limit_minor="${limit#*.}"
  limit_minor="${limit_minor%%.*}"

  if ((candidate_major != limit_major)); then
    if ((candidate_major < limit_major)); then
      return 0
    fi
    return 1
  fi
  if ((candidate_minor <= limit_minor)); then
    return 0
  fi

  return 1
}

# Reports the build-script output directory Cargo records for one package in a
# shared target directory. The expected build has already completed, so this
# replays Cargo's cached build-script metadata instead of rebuilding. The
# static link directives recorded by that build script must resolve to
# archives inside the reported directory, so callers inspect the native
# libraries a link would actually consume.
argus_package_build_script_out_dir() {
  local target_directory="$1"
  local package="$2"
  local messages
  local script_record
  local record_count
  local out_dir
  local linked_libs
  local linked_lib
  local linked_lib_name
  local linked_lib_archive

  if ! messages="$(RUSTUP_TOOLCHAIN="$RUST_CHANNEL" rustup run "$RUST_CHANNEL" cargo build \
    --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --package "$package" --lib --locked \
    --target "$ARGUS_MACOS_RUST_TARGET" \
    --target-dir "$target_directory" \
    --message-format=json 2>&1)"; then
    fail "pinned Cargo build-script probe failed for $package"
  fi

  if ! script_record="$(printf '%s\n' "$messages" |
    rg -F '"reason":"build-script-executed"' |
    rg -F "#$package@")"; then
    script_record=""
  fi
  record_count="$(printf '%s\n' "$script_record" |
    sed '/^$/d' | wc -l | tr -d '[:space:]')"
  if [[ "$record_count" != "1" ]]; then
    fail "expected exactly one $package build-script record, found $record_count"
  fi

  if ! out_dir="$(printf '%s\n' "$script_record" |
    rg -o '"out_dir":"[^"]*"' |
    rg -o '/[^"]*')"; then
    out_dir=""
  fi
  if [[ -z "$out_dir" || ! -d "$out_dir" ]]; then
    fail "could not resolve the $package build-script output directory"
  fi

  if ! linked_libs="$(printf '%s\n' "$script_record" |
    rg -o 'static=[^",]*')"; then
    linked_libs=""
  fi
  while IFS= read -r linked_lib; do
    [[ -n "$linked_lib" ]] || continue
    linked_lib_name="$(printf '%s' "$linked_lib" | sed 's/^static=//')"
    linked_lib_archive="$out_dir/lib$linked_lib_name.a"
    if [[ ! -f "$linked_lib_archive" ]]; then
      fail "the $package build script links $linked_lib_name without $linked_lib_archive"
    fi
  done <<<"$linked_libs"

  printf '%s\n' "$out_dir"
}

# Reports the distinct minimum macOS versions recorded by the Mach-O object
# members of every static library in one build-script output directory. Native
# build scripts compile those objects for the effective deployment target, so
# the reported versions show whether a reused archive still holds objects that
# were built for a different target.
argus_native_archive_member_versions() {
  local out_dir="$1"
  local scratch_directory="$2"
  local archive_count=0
  local member_count=0
  local archive
  local archive_scratch
  local member
  local version
  local member_versions_file

  mkdir -p "$scratch_directory"
  member_versions_file="$scratch_directory/member-versions"
  : >"$member_versions_file"
  for archive in "$out_dir"/*.a; do
    [[ -f "$archive" ]] || continue
    archive_count=$((archive_count + 1))
    archive_scratch="$scratch_directory/archive-$archive_count"
    mkdir -p "$archive_scratch"
    if ! (cd "$archive_scratch" && ar x "$archive"); then
      fail "could not extract the native archive $archive"
    fi
    member_count=0
    for member in "$archive_scratch"/*.o; do
      [[ -f "$member" ]] || continue
      member_count=$((member_count + 1))
      if ! version="$(argus_macho_minimum_os_version "$member")"; then
        fail "could not read a minimum macOS version from $member"
      fi
      printf '%s\n' "$version" >>"$member_versions_file"
    done
    if ((member_count == 0)); then
      fail "the native archive $archive should contain at least one object member"
    fi
  done
  if ((archive_count == 0)); then
    fail "no native archive was produced in $out_dir"
  fi

  sort -u "$member_versions_file"
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
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$rustflags_probe_log" "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET"
  encoded_probe_log="$(run_pinned_cargo_rustc_probe "$cargo_probe_root/encoded")"
  assert_file_contains "$encoded_probe_log" "opt-level=1"
  assert_file_contains "$encoded_probe_log" \
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$encoded_probe_log" "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="-C opt-level=1"
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET"
  target_environment_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/target-environment")"
  assert_file_contains "$target_environment_probe_log" "-C opt-level=1"
  assert_file_contains "$target_environment_probe_log" \
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$target_environment_probe_log" "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  build_config='build.rustflags=["-C","opt-level=1"]'
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET" --config "$build_config"
  build_config_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/build-config" --config "$build_config")"
  assert_file_contains "$build_config_probe_log" "-C opt-level=1"
  assert_file_contains "$build_config_probe_log" \
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$build_config_probe_log" "metadata=argus-macos-deployment-target-"

  reset_policy_environment
  target_config='target.aarch64-apple-darwin.rustflags=["-C","opt-level=1"]'
  argus_configure_macos_rust_build_environment Darwin arm64 cargo rustc \
    --target "$ARGUS_MACOS_RUST_TARGET" --config "$target_config"
  target_config_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/target-config" --config "$target_config")"
  assert_file_contains "$target_config_probe_log" "-C opt-level=1"
  assert_file_contains "$target_config_probe_log" \
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$target_config_probe_log" "metadata=argus-macos-deployment-target-"

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
      "--cfg=argus_macos_deployment_target_fingerprint_"
    assert_file_not_contains "$probe_log" "metadata=argus-macos-deployment-target-"
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
  assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
    "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
    "a matching cfg target table must receive an additive fingerprint"
  assert_no_cargo_metadata_deployment_marker
  assert_unset CARGO_BUILD_RUSTFLAGS
  matching_cfg_probe_log="$(run_pinned_cargo_rustc_probe \
    "$cargo_probe_root/matching-cfg-config" \
    --config "$matching_cfg_config_file")"
  assert_file_contains "$matching_cfg_probe_log" "-C opt-level=1"
  assert_file_contains "$matching_cfg_probe_log" \
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$matching_cfg_probe_log" "metadata=argus-macos-deployment-target-"

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
      assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
        "${CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS-}" \
        "a CLI include target source must receive an additive fingerprint"
      assert_no_cargo_metadata_deployment_marker
      assert_unset CARGO_BUILD_RUSTFLAGS
      CARGO_HOME="$cli_cargo_home" \
        run_pinned_cargo_cli_config_rustc_probe \
        "$cargo_probe_root/$probe_name" "$config_value"
    )"
    assert_file_contains "$probe_log" "-C opt-level=1"
    assert_file_contains "$probe_log" \
      "--cfg=argus_macos_deployment_target_fingerprint_"
    assert_file_not_contains "$probe_log" "metadata=argus-macos-deployment-target-"
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
    assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
      "${CARGO_BUILD_RUSTFLAGS-}" \
      "an optional CLI include without target flags must use build rustflags"
    assert_no_cargo_metadata_deployment_marker
    assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
    CARGO_HOME="$cli_cargo_home" \
      run_pinned_cargo_cli_config_rustc_probe \
      "$cargo_probe_root/optional-cli-include" "$optional_cli_config"
  )"
  assert_file_contains "$optional_cli_probe_log" \
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$optional_cli_probe_log" "metadata=argus-macos-deployment-target-"

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
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$multiple_config_probe_log" "metadata=argus-macos-deployment-target-"

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
    assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
      "${CARGO_BUILD_RUSTFLAGS-}" \
      "active .cargo/config build flags must receive the deployment marker"
    assert_no_cargo_metadata_deployment_marker
    assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
    run_pinned_cargo_rustc_probe "$precedence_root/target"
  )"
  assert_file_contains "$precedence_probe_log" "-C opt-level=1"
  assert_file_contains "$precedence_probe_log" \
    "--cfg=argus_macos_deployment_target_fingerprint_"
  assert_file_not_contains "$precedence_probe_log" "metadata=argus-macos-deployment-target-"
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
  assert_contains "--cfg=argus_macos_deployment_target_fingerprint_" \
    "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS" \
    "a dotted matching cfg target table must receive an additive fingerprint"
  assert_no_cargo_metadata_deployment_marker

  reset_policy_environment
  export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
  export MACOSX_DEPLOYMENT_TARGET=26.5
  argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
    --target "$ARGUS_MACOS_RUST_TARGET"
  higher_rust_fingerprint="--cfg=argus_macos_deployment_target_fingerprint_"
  higher_rust_fingerprint+="$(argus_deployment_target_fingerprint 26.5)"
  floor_rust_fingerprint="--cfg=argus_macos_deployment_target_fingerprint_"
  floor_rust_fingerprint+="$(argus_deployment_target_fingerprint 12.0)"
  [[ "$higher_rust_fingerprint" != "$floor_rust_fingerprint" ]] ||
    fail "distinct deployment targets must produce distinct Rust fingerprint markers"
  assert_contains "$higher_rust_fingerprint" "$CARGO_ENCODED_RUSTFLAGS" \
    "the encoded 26.5 Rust flags must carry the 26.5 fingerprint marker"
  encoded_transition_directory="$cargo_probe_root/encoded-transition"
  first_transition_log="$(run_pinned_cargo_build_probe \
    "$encoded_transition_directory")"
  assert_file_contains "$first_transition_log" "Compiling argus-domain"

  reset_policy_environment
  export CARGO_ENCODED_RUSTFLAGS="-C${encoded_separator}opt-level=1"
  export MACOSX_DEPLOYMENT_TARGET=12.0
  argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
    --target "$ARGUS_MACOS_RUST_TARGET"
  assert_contains "$floor_rust_fingerprint" "$CARGO_ENCODED_RUSTFLAGS" \
    "the encoded 12.0 Rust flags must carry the 12.0 fingerprint marker"
  second_transition_log="$(run_pinned_cargo_build_probe \
    "$encoded_transition_directory")"
  assert_file_contains "$second_transition_log" "Compiling argus-domain"
  assert_file_not_contains "$second_transition_log" "Fresh argus-domain"

  # Cargo's own fingerprint cannot make a native build script rebuild when only
  # the deployment target changes; the effective C flag fingerprint is that
  # input for cc-rs. Distinct deployment targets must therefore reach cc-rs as
  # distinct fingerprints, so shared Cargo output cannot keep native members
  # that were compiled for a target above the 12.0 product floor.
  higher_target_fingerprint="-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=$(
    argus_deployment_target_fingerprint 26.5
  )"
  floor_fingerprint="-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=$(
    argus_deployment_target_fingerprint 12.0
  )"
  [[ "$higher_target_fingerprint" != "$floor_fingerprint" ]] ||
    fail "distinct deployment targets must produce distinct native fingerprints"
  assert_contains "$floor_fingerprint" "$CFLAGS" \
    "the 12.0 product floor must be the effective native fingerprint"

  # Cargo's Rust fingerprint only tracks Rust flags, so the native fingerprint
  # has to reach cc-rs as a distinct input. blake3 compiles its C sources
  # through cc-rs for the arm64 macOS product and archives them into the static
  # library the final link consumes, so both sides of the transition can be
  # inspected through one shared target directory: the native build must rerun,
  # and the archive consumed afterwards must not still hold objects that were
  # built for the higher deployment target.
  native_transition_directory="$cargo_probe_root/native-transition"
  reset_policy_environment
  export MACOSX_DEPLOYMENT_TARGET=26.5
  argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
    --target "$ARGUS_MACOS_RUST_TARGET"
  higher_native_log="$(run_pinned_native_cargo_build_probe \
    "$native_transition_directory" blake3 build-26.5.log)"
  assert_file_contains "$higher_native_log" "Compiling blake3"
  assert_file_matches "$higher_native_log" \
    'Running .*build/blake3-[0-9a-f]+/build-script-build' \
    "the 26.5 native build must execute its build script"
  higher_native_out_dir="$(argus_package_build_script_out_dir \
    "$native_transition_directory" blake3)"
  assert_equal "26.5" \
    "$(argus_native_archive_member_versions "$higher_native_out_dir" \
      "$cargo_probe_root/higher-native-members")" \
    "a 26.5 deployment target must reach the native build-script objects"

  reset_policy_environment
  export MACOSX_DEPLOYMENT_TARGET=12.0
  argus_configure_macos_rust_build_environment Darwin arm64 cargo build \
    --target "$ARGUS_MACOS_RUST_TARGET"
  floor_native_log="$(run_pinned_native_cargo_build_probe \
    "$native_transition_directory" blake3 build-12.0.log)"
  assert_file_contains "$floor_native_log" "Compiling blake3"
  assert_file_not_contains "$floor_native_log" "Fresh blake3"
  assert_file_matches "$floor_native_log" \
    'Running .*build/blake3-[0-9a-f]+/build-script-build' \
    "the 12.0 native build must rerun its build script"
  floor_native_out_dir="$(argus_package_build_script_out_dir \
    "$native_transition_directory" blake3)"
  assert_equal "12.0" \
    "$(argus_native_archive_member_versions "$floor_native_out_dir" \
      "$cargo_probe_root/floor-native-members")" \
    "returning to the 12.0 floor must rebuild native objects at the floor"

  # A clean dependency graph must still compile and load host proc-macro crates
  # under the normal policy. Building the bridge package covers the product's
  # real host dependency graph, and the diagnostics asserted below are the
  # signatures a broken proc-macro load leaves behind.
  # The probe builds in the Release profile because the upstream defect
  # (rust-lang/rust issue #157750) only appears when debuginfo stripping runs.
  assert_release_build_override_disables_stripping
  proc_macro_probe_log="$(run_pinned_proc_macro_build_probe \
    "$cargo_probe_root/proc-macro")"
  assert_file_contains "$proc_macro_probe_log" "Compiling strum_macros"
  assert_file_contains "$proc_macro_probe_log" "Compiling rustversion"
  assert_file_not_contains "$proc_macro_probe_log" "E0463"
  assert_file_not_contains "$proc_macro_probe_log" "defined multiple times"
  assert_file_not_contains "$proc_macro_probe_log" "dlopen"
  assert_file_not_contains "$proc_macro_probe_log" "mis-aligned LINKEDIT string pool"

  # Every host dylib the Release probe produced must keep its symbol-table
  # string pool aligned: dyld refuses to load a misaligned image, which is the
  # upstream failure rustc then reports as a missing proc-macro crate.
  release_proc_macro_dylibs=("$cargo_probe_root/proc-macro/release/deps"/*.dylib)
  [[ -e "${release_proc_macro_dylibs[0]}" ]] ||
    fail "the Release proc-macro probe must produce host dylibs"
  for release_proc_macro_dylib in "${release_proc_macro_dylibs[@]}"; do
    release_proc_macro_stroff="$(argus_macho_symtab_stroff "$release_proc_macro_dylib")" ||
      fail "could not read LC_SYMTAB.stroff from $release_proc_macro_dylib"
    assert_equal "0" "$((release_proc_macro_stroff % 8))" \
      "Release build-time dylib must keep an 8-byte aligned LC_SYMTAB.stroff ($release_proc_macro_dylib)"
  done
else
  printf 'Pinned Cargo effective rustflags probes: SKIP (requires Darwin arm64 and rustup)\n'
fi

printf 'macOS Rust build contract: PASS\n'
