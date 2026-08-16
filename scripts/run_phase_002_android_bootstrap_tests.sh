#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="dev.argusromtoolkit.argus"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required developer tool is missing: %s\n' "$command_name" >&2
    return 1
  fi
}

for command_name in adb fvm; do
  require_command "$command_name"
done

device_id="${ARGUS_ANDROID_DEVICE_ID:-}"
if [[ -z "$device_id" ]]; then
  devices="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
  if [[ -z "$devices" ]]; then
    printf 'No connected Android device found; start an x86_64 API-30+ emulator or set ARGUS_ANDROID_DEVICE_ID\n' >&2
    exit 1
  fi
  count="$(printf '%s\n' "$devices" | wc -l | tr -d ' ')"
  if (( count != 1 )); then
    printf 'Exactly one connected Android device is required or set ARGUS_ANDROID_DEVICE_ID\n' >&2
    exit 1
  fi
  device_id="$(printf '%s\n' "$devices")"
fi

api_level="$(adb -s "$device_id" shell getprop ro.build.version.sdk | tr -d '\r')"
if (( api_level < 30 )); then
  printf 'Android API %s is below the P02-001 minimum of 30\n' "$api_level" >&2
  exit 1
fi

abi="$(adb -s "$device_id" shell getprop ro.product.cpu.abi | tr -d '\r')"
if [[ "$abi" != "x86_64" ]]; then
  printf 'Slice-001 emulator milestone requires x86_64; device reports %s\n' "$abi" >&2
  exit 1
fi

printf 'Building the debug APK through repository build plumbing\n'
(
  cd "$ROOT_DIR/flutter"
  fvm flutter build apk --debug --target-platform android-arm64,android-x64
)

printf 'Installing the debug APK on %s\n' "$device_id"
adb -s "$device_id" install -r \
  "$ROOT_DIR/flutter/build/app/outputs/flutter-apk/app-debug.apk"

printf 'Scenario 1: denied All files access must block startup\n'
adb -s "$device_id" shell pm clear "$PACKAGE_ID" >/dev/null
adb -s "$device_id" shell appops set --uid "$PACKAGE_ID" \
  MANAGE_EXTERNAL_STORAGE deny
(
  cd "$ROOT_DIR/flutter"
  fvm flutter test integration_test/phase_002_android_permission_gate_test.dart \
    -d "$device_id"
)

printf 'Scenario 2: granted readiness must boot the real stack\n'
adb -s "$device_id" shell pm clear "$PACKAGE_ID" >/dev/null
adb -s "$device_id" shell appops set --uid "$PACKAGE_ID" \
  MANAGE_EXTERNAL_STORAGE allow
if (( api_level >= 33 )); then
  adb -s "$device_id" shell pm grant "$PACKAGE_ID" \
    android.permission.POST_NOTIFICATIONS || true
fi
(
  cd "$ROOT_DIR/flutter"
  fvm flutter test integration_test/phase_002_android_bootstrap_test.dart \
    -d "$device_id"
)

printf 'P02-001 Android bootstrap milestone passed on %s\n' "$device_id"
