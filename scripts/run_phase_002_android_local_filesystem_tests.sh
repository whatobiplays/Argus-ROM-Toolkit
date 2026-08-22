#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="com.argusromtoolkit.argus"
FIXTURE_ROOT="/sdcard/ArgusP02002Fixture"

adb_command="${ARGUS_ANDROID_ADB:-$(command -v adb || true)}"
if [[ -z "$adb_command" || ! -x "$adb_command" ]]; then
  printf 'Required developer tool is missing: adb (set ARGUS_ANDROID_ADB to its path)\n' >&2
  exit 1
fi
command -v fvm >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: fvm\n' >&2
  exit 1
}

device_id="${ARGUS_ANDROID_DEVICE_ID:-}"
if [[ -z "$device_id" ]]; then
  devices="$($adb_command devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
  if [[ -z "$devices" ]]; then
    printf 'No connected Android device found; connect a compatible ARM64 API-30+ device or emulator\n' >&2
    exit 1
  fi
  count="$(printf '%s\n' "$devices" | wc -l | tr -d ' ')"
  if (( count != 1 )); then
    printf 'Exactly one connected Android device is required or set ARGUS_ANDROID_DEVICE_ID\n' >&2
    exit 1
  fi
  device_id="$devices"
fi

api_level="$($adb_command -s "$device_id" shell getprop ro.build.version.sdk | tr -d '\r')"
if [[ "$api_level" != 36 ]]; then
  printf 'P02-002 requires Android API 36; device reports %s\n' "$api_level" >&2
  exit 1
fi

abi="$($adb_command -s "$device_id" shell getprop ro.product.cpu.abi | tr -d '\r')"
if [[ "$abi" != "arm64-v8a" ]]; then
  printf 'P02-002 native milestone requires ARM64; device reports %s\n' "$abi" >&2
  exit 1
fi

cleanup() {
  "$adb_command" -s "$device_id" shell rm -rf "$FIXTURE_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Building the ARM64 debug APK through repository build plumbing\n'
(
  cd "$ROOT_DIR/flutter"
  fvm flutter build apk --debug --target-platform android-arm64
)

printf 'Installing the debug APK on %s\n' "$device_id"
"$adb_command" -s "$device_id" install -r \
  "$ROOT_DIR/flutter/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
"$adb_command" -s "$device_id" shell pm clear "$PACKAGE_ID" >/dev/null
"$adb_command" -s "$device_id" shell appops set --uid "$PACKAGE_ID" \
  MANAGE_EXTERNAL_STORAGE allow
if (( api_level >= 33 )); then
  "$adb_command" -s "$device_id" shell pm grant "$PACKAGE_ID" \
    android.permission.POST_NOTIFICATIONS || true
fi

printf 'Preparing the primary shared-storage fixture at %s\n' "$FIXTURE_ROOT"
"$adb_command" -s "$device_id" shell rm -rf "$FIXTURE_ROOT"
"$adb_command" -s "$device_id" shell mkdir -p "$FIXTURE_ROOT/Child"
printf 'P02-002 sentinel\n' | "$adb_command" -s "$device_id" shell \
  "cat > '$FIXTURE_ROOT/Child/phase-002-sentinel.txt'"

run_integration_phase() {
  local mode="$1"
  printf 'Running P02-002 Android integration phase: %s\n' "$mode"
  (
    cd "$ROOT_DIR/flutter"
    fvm flutter test integration_test/phase_002_android_local_filesystem_test.dart \
      --dart-define="ARGUS_PHASE_002_MODE=$mode" \
      --no-uninstall \
      -d "$device_id"
  )
}

run_integration_phase seed
printf 'Restarting the Android application process before verification\n'
"$adb_command" -s "$device_id" shell am force-stop "$PACKAGE_ID"
run_integration_phase verify

if ! "$adb_command" -s "$device_id" shell test -f \
  "$FIXTURE_ROOT/Child/phase-002-sentinel.txt"; then
  printf 'P02-002 sentinel disappeared after root removal\n' >&2
  exit 1
fi

printf 'P02-002 Android LocalFilesystem milestone passed on %s\n' "$device_id"
