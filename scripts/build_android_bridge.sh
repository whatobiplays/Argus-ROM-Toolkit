#!/usr/bin/env bash
set -euo pipefail

# Build the ARM64 Argus native libraries used by one Android Cargo profile.
# Debug and Release outputs are kept in separate directories so a stale build
# can never be packaged under the other profile.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$ROOT_DIR/.dart_tool/cargo-ndk"
CARGO_NDK_VERSION="4.1.2"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/android_sdk_common.sh"

usage() {
  printf 'Usage: %s [--debug|--release] [--output-dir <directory>]\n' "$0" >&2
  printf 'Defaults to the Debug profile under flutter/build/native-jni/debug.\n' >&2
}

build_mode="debug"
output_directory=""
while (( $# > 0 )); do
  case "$1" in
    --debug)
      build_mode="debug"
      shift
      ;;
    --release)
      build_mode="release"
      shift
      ;;
    --output-dir)
      if (( $# < 2 )); then
        usage
        exit 2
      fi
      output_directory="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

default_output_directory="$ROOT_DIR/flutter/build/native-jni/$build_mode"
if [[ -z "$output_directory" ]]; then
  output_directory="$default_output_directory"
fi
case "$output_directory" in
  /*) ;;
  *) output_directory="$ROOT_DIR/$output_directory" ;;
esac
# The Python helper rejects root, symlinked, and unowned explicit output
# directories before this script can replace anything inside them. It also
# prints the canonical path used for the remaining build and metadata steps.
if ! output_directory="$(
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ROOT_DIR" python3 \
    -m scripts.android_qualification.packaging native-output-dir \
    --root "$ROOT_DIR" \
    --output "$output_directory" \
    --default-output "$default_output_directory"
)"; then
  exit 2
fi

profile_flag=""
if [[ "$build_mode" == "release" ]]; then
  profile_flag="--release"
fi

# Capture source identity before native compilation. The same fingerprint is
# emitted in native-build.json and checked by the independent APK verifier.
source_state_file="$output_directory/source-state.json"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ROOT_DIR" python3 \
  -m scripts.android_qualification.packaging source-state \
  --root "$ROOT_DIR" \
  --output "$source_state_file"
IFS=$'\t' read -r source_revision source_dirty source_fingerprint < <(
  PYTHONDONTWRITEBYTECODE=1 python3 -c \
    'import json,sys; value=json.load(open(sys.argv[1])); print("%s\t%s\t%s" % (value["revision"], str(value["dirty"]).lower(), value["fingerprint"]))' \
    "$source_state_file"
)

rust_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
[[ -n "$rust_channel" ]] || { printf 'Missing Rust toolchain pin\n' >&2; exit 1; }

rustup target add --toolchain "$rust_channel" aarch64-linux-android

if [[ ! -x "$TOOL_ROOT/bin/cargo-ndk" ]]; then
  # The pinned Rust toolchain has a stripping defect when it compiles
  # build-time proc-macro crates. The workspace already disables stripping for
  # those crates; repeat the setting here because `cargo install` runs outside
  # the workspace manifest and would otherwise inherit the broken behavior.
  CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_STRIP=none \
    CARGO_PROFILE_RELEASE_STRIP=none \
    bash "$ROOT_DIR/scripts/run_rust.sh" cargo install cargo-ndk \
      --version "$CARGO_NDK_VERSION" --locked --root "$TOOL_ROOT"
fi

cargo_ndk_version="$(
  PATH="$TOOL_ROOT/bin:$PATH" bash "$ROOT_DIR/scripts/run_rust.sh" cargo ndk --version
)"
rustc_version="$(bash "$ROOT_DIR/scripts/run_rust.sh" rustc --version)"

# cargo-ndk requires an explicit NDK. Prefer ANDROID_NDK_HOME; otherwise
# resolve a single installed NDK under the SDK and fail with guidance when
# the host does not provide exactly one usable candidate.
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if pinned_ndk="$(argus_resolve_pinned_ndk_home "$ROOT_DIR")"; then
    export ANDROID_NDK_HOME="$pinned_ndk"
  else
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
fi

ndk_strip=""
while IFS= read -r candidate; do
  if [[ -x "$candidate" ]]; then
    ndk_strip="$candidate"
    break
  fi
done < <(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -maxdepth 3 \
  \( -type f -o -type l \) -name llvm-strip | sort)
[[ -n "$ndk_strip" ]] || {
  printf 'Android NDK llvm-strip was not found under %s\n' "$ANDROID_NDK_HOME" >&2
  exit 1
}

staging_root="$(mktemp -d "$output_directory/.argus-bridge.XXXXXX")"
metadata_temporary=""
cleanup() {
  status=$?
  if [[ -n "${metadata_temporary:-}" ]]; then
    rm -f -- "$metadata_temporary" || true
  fi
  if [[ -n "${staging_root:-}" && -d "$staging_root" ]]; then
    rm -rf -- "$staging_root"
  fi
  return "$status"
}
trap cleanup EXIT

cargo_arguments=(
  ndk
  -t arm64-v8a
  -o "$staging_root"
  --manifest-path "$ROOT_DIR/rust/Cargo.toml"
  build
  --package argus-bridge
  --locked
)
if [[ -n "$profile_flag" ]]; then
  cargo_arguments+=("$profile_flag")
fi

(
  cd "$ROOT_DIR/rust"
  env \
    PATH="$TOOL_ROOT/bin:$PATH" \
    CARGO_NDK_PLATFORM=30 \
    bash "$ROOT_DIR/scripts/run_rust.sh" cargo "${cargo_arguments[@]}"
)

staged_abi="$staging_root/arm64-v8a"
[[ -f "$staged_abi/libargus_bridge.so" ]] || {
  printf 'Android bridge library was not produced\n' >&2
  exit 1
}
keyring_library="$(find "$staged_abi" -maxdepth 1 -type f \
  -name 'libandroid_native_keyring_store-*.so' -print -quit)"
[[ -n "$keyring_library" ]] || {
  printf 'Android native keyring library was not produced\n' >&2
  exit 1
}
mv "$keyring_library" "$staged_abi/libandroid_native_keyring_store.so"

# Strip before the replacement so a stripping failure cannot damage the last
# complete ABI output. AGP performs the same operation before packaging; the
# recorded hashes therefore describe the exact bytes Gradle packages.
while IFS= read -r library; do
  "$ndk_strip" --strip-unneeded "$library"
done < <(find "$staged_abi" -maxdepth 1 -type f -name '*.so' | sort)

# Replacement is deferred until every staged library and metadata record is
# ready. The Python commit helper reopens and pins the validated output
# directory, rechecks its ownership marker, and performs the directory swap
# relative to that descriptor instead of trusting paths checked earlier.

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'A SHA-256 tool is required (sha256sum or shasum)\n' >&2
    return 1
  fi
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

case "$output_directory" in
  "$ROOT_DIR"/*) output_relative="${output_directory#"$ROOT_DIR"/}" ;;
  *) output_relative="$(basename "$output_directory")" ;;
esac

cargo_lock_sha256="$(sha256_file "$ROOT_DIR/rust/Cargo.lock")"

metadata_file="$output_directory/native-build.json"
metadata_temporary="$staging_root/native-build.json"
{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "build_profile": "%s",\n' "$(json_escape "$build_mode")"
  printf '  "cargo_command": ['
  # Record every build-affecting argument while replacing the unpredictable
  # temporary staging path with a stable, non-private placeholder.
  recorded_command=(cargo ndk -t arm64-v8a -o '<temporary-staging-directory>' --manifest-path rust/Cargo.toml build --package argus-bridge --locked)
  if [[ -n "$profile_flag" ]]; then
    recorded_command+=("$profile_flag")
  fi
  first=true
  for argument in "${recorded_command[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$argument")"
  done
  printf '],\n'
  printf '  "features": "default",\n'
  printf '  "rust_toolchain": "%s",\n' "$(json_escape "$rust_channel")"
  printf '  "rustc_version": "%s",\n' "$(json_escape "$rustc_version")"
  printf '  "cargo_ndk_version": "%s",\n' "$(json_escape "$cargo_ndk_version")"
  printf '  "cargo_ndk_platform": "30",\n'
  printf '  "cargo_lock_sha256": "%s",\n' "$cargo_lock_sha256"
  printf '  "source_revision": "%s",\n' "$(json_escape "$source_revision")"
  printf '  "source_dirty": %s,\n' "$source_dirty"
  printf '  "source_fingerprint": "%s",\n' "$source_fingerprint"
  printf '  "output_directory": "%s",\n' "$(json_escape "$output_relative")"
  printf '  "libraries": {\n'
  first=true
  while IFS= read -r library; do
    name="$(basename "$library")"
    packaged_name="lib/arm64-v8a/$name"
    digest="$(sha256_file "$library")"
    size="$(wc -c < "$library" | tr -d '[:space:]')"
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ',\n'
    fi
    printf '    "%s": {"sha256": "%s", "size_bytes": %s}' \
      "$(json_escape "$packaged_name")" "$digest" "$size"
  done < <(find "$staged_abi" -maxdepth 1 -type f -name '*.so' | sort)
  printf '\n  }\n'
  printf '}\n'
} > "$metadata_temporary"

if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ROOT_DIR" python3 \
  -m scripts.android_qualification.packaging native-output-commit \
  --root "$ROOT_DIR" \
  --output "$output_directory" \
  --default-output "$default_output_directory" \
  --staged-abi "$staged_abi" \
  --metadata-temporary "$metadata_temporary" \
  --metadata "$metadata_file" >/dev/null; then
  exit 2
fi

printf 'ARM64 %s bridge libraries: %s\n' "$build_mode" "$output_directory/arm64-v8a"
printf 'Native build metadata: %s\n' "$metadata_file"
