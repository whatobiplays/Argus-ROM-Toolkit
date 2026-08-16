#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$ROOT_DIR/.dart_tool/cargo-ndk"
JNI_DIR="$ROOT_DIR/flutter/android/app/src/main/jniLibs"
CARGO_NDK_VERSION="4.1.2"

rust_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
[[ -n "$rust_channel" ]] || { printf 'Missing Rust toolchain pin\n' >&2; exit 1; }

rustup target add --toolchain "$rust_channel" aarch64-linux-android x86_64-linux-android

if [[ ! -x "$TOOL_ROOT/bin/cargo-ndk" ]]; then
  bash "$ROOT_DIR/scripts/run_rust.sh" cargo install cargo-ndk \
    --version "$CARGO_NDK_VERSION" --locked --root "$TOOL_ROOT"
fi

# cargo-ndk requires an explicit NDK. Prefer ANDROID_NDK_HOME; otherwise
# resolve a single installed NDK under the SDK and fail with guidance when
# the host does not provide exactly one usable candidate.
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}}"
  ndk_versions_dir="$sdk_root/ndk"
  if [[ ! -d "$ndk_versions_dir" ]]; then
    printf 'Android NDK not found; set ANDROID_NDK_HOME or install an NDK under %s\n' \
      "$ndk_versions_dir" >&2
    exit 1
  fi
  ndk_versions=()
  while IFS= read -r candidate; do
    ndk_versions+=("$candidate")
  done < <(find "$ndk_versions_dir" -mindepth 1 -maxdepth 1 -type d | sort)
  if (( ${#ndk_versions[@]} != 1 )); then
    printf 'Could not resolve one Android NDK; set ANDROID_NDK_HOME explicitly\n' >&2
    exit 1
  fi
  export ANDROID_NDK_HOME="${ndk_versions[0]}"
fi

rm -rf "$JNI_DIR/arm64-v8a" "$JNI_DIR/x86_64"
mkdir -p "$JNI_DIR"

(
  cd "$ROOT_DIR/rust"
  env \
    PATH="$TOOL_ROOT/bin:$PATH" \
    CARGO_NDK_PLATFORM=30 \
    bash "$ROOT_DIR/scripts/run_rust.sh" cargo ndk \
      -t arm64-v8a \
      -t x86_64 \
      -o "$JNI_DIR" \
      --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
      build \
      --package argus-bridge \
      --locked
)
