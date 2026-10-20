#!/usr/bin/env bash
set -euo pipefail

# Build and inspect the isolated Android qualification APK. This is a host-only
# operation: it never starts ADB, contacts a device, or installs an artifact.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUALIFICATION_OUTPUT="$ROOT_DIR/flutter/build/qualification"
QUALIFICATION_APK="$QUALIFICATION_OUTPUT/argus-qualification.apk"
QUALIFICATION_PROVENANCE="$QUALIFICATION_OUTPUT/argus-qualification-provenance.json"
PREBUILD_SOURCE="$QUALIFICATION_OUTPUT/prebuild-source.json"
NATIVE_METADATA="$ROOT_DIR/flutter/build/native-jni/release/native-build.json"
RELEASE_APK="$ROOT_DIR/flutter/build/app/outputs/flutter-apk/app-release.apk"
DEBUG_APK="$ROOT_DIR/flutter/build/app/outputs/flutter-apk/app-debug.apk"

fail() {
  printf 'Android qualification build failed: %s\n' "$*" >&2
  exit 1
}

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

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/android_sdk_common.sh"

# Resolve the debug keystore with the same precedence as the qualification
# verifier. Gradle and the verifier must use one location so the package
# signature can be inspected on a host that has never built an Android app.
if [[ -n "${ANDROID_USER_HOME:-}" ]]; then
  debug_keystore_directory="$ANDROID_USER_HOME"
elif [[ -n "${ANDROID_PREFS_ROOT:-}" ]]; then
  debug_keystore_directory="$ANDROID_PREFS_ROOT/.android"
elif [[ -n "${ANDROID_SDK_HOME:-}" ]]; then
  debug_keystore_directory="$ANDROID_SDK_HOME/.android"
elif [[ -n "${HOME:-}" ]]; then
  debug_keystore_directory="$HOME/.android"
else
  fail "the Android debug keystore directory cannot be resolved: set ANDROID_USER_HOME, ANDROID_PREFS_ROOT, ANDROID_SDK_HOME, or HOME"
fi

# Android Gradle Plugin 9 rejects deprecated preference variables that differ
# from ANDROID_USER_HOME. The resolved path is the single authoritative
# location for the build and verifier.
unset ANDROID_PREFS_ROOT
unset ANDROID_SDK_HOME

mkdir -p "$debug_keystore_directory" || \
  fail "the Android debug keystore directory could not be created"
debug_keystore_directory="$(cd "$debug_keystore_directory" && pwd -P)"
export ANDROID_USER_HOME="$debug_keystore_directory"
debug_keystore="$ANDROID_USER_HOME/debug.keystore"

if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/keytool" ]]; then
  keytool_binary="$JAVA_HOME/bin/keytool"
elif command -v keytool >/dev/null 2>&1; then
  keytool_binary="$(command -v keytool)"
else
  fail "keytool is required for Android qualification signing: set JAVA_HOME or add keytool to PATH"
fi

if [[ ! -f "$debug_keystore" ]]; then
  debug_keystore_temporary_directory="$(mktemp -d "$debug_keystore_directory/.debug-keystore.XXXXXX")" || \
    fail "a temporary Android debug keystore directory could not be created"
  debug_keystore_temporary="$debug_keystore_temporary_directory/debug.keystore"
  if ! "$keytool_binary" -genkeypair \
    -keystore "$debug_keystore_temporary" \
    -storepass android \
    -keypass android \
    -alias androiddebugkey \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" \
    -noprompt; then
    rm -f -- "$debug_keystore_temporary"
    rmdir -- "$debug_keystore_temporary_directory" 2>/dev/null || true
    fail "the Android debug keystore could not be created"
  fi
  if ! mv -- "$debug_keystore_temporary" "$debug_keystore"; then
    rm -f -- "$debug_keystore_temporary"
    rmdir -- "$debug_keystore_temporary_directory" 2>/dev/null || true
    fail "the Android debug keystore could not be installed"
  fi
  rmdir -- "$debug_keystore_temporary_directory"
fi

if [[ ! -f "$ROOT_DIR/flutter/android/local.properties" ]]; then
  (
    cd "$ROOT_DIR/flutter"
    fvm flutter pub get --enforce-lockfile
  )
fi

# Use the Flutter-pinned NDK when the host has multiple NDK installations.
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if pinned_ndk="$(argus_resolve_pinned_ndk_home "$ROOT_DIR")"; then
    export ANDROID_NDK_HOME="$pinned_ndk"
  fi
fi

# A fresh checkout does not contain the generated Gradle wrapper or Android
# local configuration. Flutter's configuration-only build creates those
# ignored prerequisites without packaging or signing an APK. Run it before
# the source snapshot so generated Kotlin session state cannot race the build.

# Capture the ordinary APK bytes before Flutter can touch the Android build.
# The configuration-only prerequisite must leave both artifacts unchanged; a
# later final check repeats this assertion after qualification packaging.
release_before=""
if [[ -f "$RELEASE_APK" ]]; then
  release_before="$(sha256_file "$RELEASE_APK")"
fi
debug_before=""
if [[ -f "$DEBUG_APK" ]]; then
  debug_before="$(sha256_file "$DEBUG_APK")"
fi

if ! (
  cd "$ROOT_DIR/flutter"
  fvm flutter build apk --release --config-only --target-platform android-arm64
); then
  fail "Flutter Android configuration could not be initialized"
fi

if [[ -n "$release_before" ]]; then
  [[ -f "$RELEASE_APK" ]] || \
    fail "Flutter configuration-only removed the existing distributable Release APK"
  release_after_config="$(sha256_file "$RELEASE_APK")"
  [[ "$release_before" == "$release_after_config" ]] || \
    fail "Flutter configuration-only changed the existing distributable Release APK"
else
  [[ ! -f "$RELEASE_APK" ]] || \
    fail "Flutter configuration-only created an ordinary Release APK"
fi
if [[ -n "$debug_before" ]]; then
  [[ -f "$DEBUG_APK" ]] || \
    fail "Flutter configuration-only removed the existing Debug APK"
  debug_after_config="$(sha256_file "$DEBUG_APK")"
  [[ "$debug_before" == "$debug_after_config" ]] || \
    fail "Flutter configuration-only changed the existing Debug APK"
else
  [[ ! -f "$DEBUG_APK" ]] || \
    fail "Flutter configuration-only created an ordinary Debug APK"
fi

# Remove only this variant's prior outputs. No Gradle clean task runs, so
# Debug and distributable Release outputs are not deleted or rebuilt.
mkdir -p "$QUALIFICATION_OUTPUT"
for path in \
  "$QUALIFICATION_APK" \
  "$QUALIFICATION_PROVENANCE" \
  "$PREBUILD_SOURCE" \
  "$QUALIFICATION_OUTPUT/qualification-build.json" \
  "$QUALIFICATION_OUTPUT/native-build.json"; do
  if [[ -e "$path" ]]; then
    rm -f -- "$path"
  fi
done
agp_qualification_output="$ROOT_DIR/flutter/build/app/outputs/apk/qualification"
if [[ -d "$agp_qualification_output" ]]; then
  rm -rf -- "$agp_qualification_output"
fi

# Freeze the source fingerprint before Gradle can run any Flutter or native
# compilation. The embedded build record and final verifier must agree with it.
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ROOT_DIR" python3 \
  -m scripts.android_qualification.packaging source-state \
  --root "$ROOT_DIR" \
  --output "$PREBUILD_SOURCE"

(
  cd "$ROOT_DIR/flutter/android"
  ./gradlew :app:packageQualification \
    --console=plain \
    -Ptarget=lib/main.dart \
    -Ptarget-platform=android-arm64 \
    -Ptrack-widget-creation=false \
    -Ptree-shake-icons=true
)

if [[ -n "$release_before" ]]; then
  [[ -f "$RELEASE_APK" ]] || fail "the existing distributable Release APK disappeared"
  release_after="$(sha256_file "$RELEASE_APK")"
  [[ "$release_before" == "$release_after" ]] || \
    fail "qualification packaging changed the existing distributable Release APK"
fi
if [[ -n "$debug_before" ]]; then
  [[ -f "$DEBUG_APK" ]] || fail "the existing Debug APK disappeared"
  debug_after="$(sha256_file "$DEBUG_APK")"
  [[ "$debug_before" == "$debug_after" ]] || \
    fail "qualification packaging changed the existing Debug APK"
fi

built_apk="$(find "$agp_qualification_output" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null || true)"
[[ -n "$built_apk" ]] || fail "Gradle did not produce a qualification APK"
if [[ "$(find "$agp_qualification_output" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d '[:space:]')" != "1" ]]; then
  fail "Gradle produced more than one qualification APK; the artifact is ambiguous"
fi

cp "$built_apk" "$QUALIFICATION_APK"
unzip -p "$QUALIFICATION_APK" assets/qualification-build.json \
  > "$QUALIFICATION_OUTPUT/qualification-build.json"
[[ -f "$NATIVE_METADATA" ]] || fail "Release-profile native build metadata is missing"
cp "$NATIVE_METADATA" "$QUALIFICATION_OUTPUT/native-build.json"

verification_arguments=(
  verify
  --root "$ROOT_DIR"
  --apk "$QUALIFICATION_APK"
  --debug-keystore "$debug_keystore"
  --keytool "$keytool_binary"
  --native-metadata "$NATIVE_METADATA"
  --provenance-out "$QUALIFICATION_PROVENANCE"
  --prebuild-source-state "$PREBUILD_SOURCE"
  --allow-provisional
)

aapt2_binary="$(argus_resolve_build_tool aapt2 || true)"
apksigner_binary="$(argus_resolve_build_tool apksigner || true)"
zipalign_binary="$(argus_resolve_build_tool zipalign || true)"
[[ -n "$aapt2_binary" ]] || fail "Android aapt2 is required for independent verification"
[[ -n "$apksigner_binary" ]] || fail "Android apksigner is required for independent verification"
[[ -n "$zipalign_binary" ]] || fail "Android zipalign is required for independent verification"
verification_arguments+=(
  --aapt2 "$aapt2_binary"
  --apksigner "$apksigner_binary"
  --zipalign "$zipalign_binary"
)

if [[ -n "${ARGUS_QUALIFICATION_EXPECTED_REVISION:-}" ]]; then
  verification_arguments+=("--expected-revision" "$ARGUS_QUALIFICATION_EXPECTED_REVISION")
fi
if [[ -n "${ARGUS_QUALIFICATION_COMPARISON_APK:-}" ]]; then
  [[ -n "${ARGUS_QUALIFICATION_COMPARISON_REVISION:-}" ]] || \
    fail "ARGUS_QUALIFICATION_COMPARISON_APK requires ARGUS_QUALIFICATION_COMPARISON_REVISION"
  verification_arguments+=("--comparison-apk" "$ARGUS_QUALIFICATION_COMPARISON_APK")
fi
if [[ -n "${ARGUS_QUALIFICATION_COMPARISON_REVISION:-}" ]]; then
  [[ -n "${ARGUS_QUALIFICATION_COMPARISON_APK:-}" ]] || \
    fail "ARGUS_QUALIFICATION_COMPARISON_REVISION requires ARGUS_QUALIFICATION_COMPARISON_APK"
  verification_arguments+=("--comparison-revision" "$ARGUS_QUALIFICATION_COMPARISON_REVISION")
fi

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ROOT_DIR" python3 \
  -m scripts.android_qualification.packaging \
  "${verification_arguments[@]}"

printf 'Qualification APK: %s\n' "$QUALIFICATION_APK"
printf 'Qualification provenance: %s\n' "$QUALIFICATION_PROVENANCE"
