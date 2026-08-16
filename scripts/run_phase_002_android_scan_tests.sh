#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="dev.argusromtoolkit.argus"
FIXTURE_ROOT="/sdcard/ArgusP02003Fixture"
EVIDENCE_ROOT="/sdcard/ArgusP02003Evidence"
SEED_ENTRY_EVIDENCE="${EVIDENCE_ROOT}/seed-entry-id.txt"
CANCEL_JOB_EVIDENCE="${SEED_ENTRY_EVIDENCE}"
CANCEL_DIRECTORIES=120
CANCEL_FILES_PER_DIRECTORY=80

adb_command="${ARGUS_ANDROID_ADB:-$(command -v adb || true)}"
if [[ -z "${adb_command}" || ! -x "${adb_command}" ]]; then
  printf 'Required developer tool is missing: adb (set ARGUS_ANDROID_ADB to its path)\n' >&2
  exit 1
fi
command -v fvm >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: fvm\n' >&2
  exit 1
}
command -v unzip >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: unzip\n' >&2
  exit 1
}

device_id="${ARGUS_ANDROID_DEVICE_ID:-}"
if [[ -z "${device_id}" ]]; then
  devices="$(${adb_command} devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
  if [[ -z "${devices}" ]]; then
    printf 'No connected Android device found; connect an ARM64 API 36 device or emulator\n' >&2
    exit 1
  fi
  count="$(printf '%s\n' "${devices}" | wc -l | tr -d ' ')"
  if (( count != 1 )); then
    printf 'Exactly one connected Android device is required or set ARGUS_ANDROID_DEVICE_ID\n' >&2
    exit 1
  fi
  device_id="${devices}"
else
  state="$(${adb_command} -s "${device_id}" get-state 2>/dev/null | tr -d '\r')"
  if [[ "${state}" != device ]]; then
    printf 'Selected Android device %s is not online (state: %s)\n' "${device_id}" "${state}" >&2
    exit 1
  fi
fi

api_level="$(${adb_command} -s "${device_id}" shell getprop ro.build.version.sdk | tr -d '\r')"
if [[ "${api_level}" != 36 ]]; then
  printf 'P02-003 requires Android API 36; device reports %s\n' "${api_level}" >&2
  exit 1
fi

abi="$(${adb_command} -s "${device_id}" shell getprop ro.product.cpu.abi | tr -d '\r')"
if [[ "${abi}" != arm64-v8a ]]; then
  printf 'P02-003 native execution requires ARM64; device reports %s\n' "${abi}" >&2
  exit 1
fi

cleanup() {
  "${adb_command}" -s "${device_id}" shell rm -rf "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}" \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Building the dual-ABI debug APK through repository build plumbing\n'
(
  cd "${ROOT_DIR}/flutter"
  fvm flutter build apk --debug --target-platform android-arm64,android-x64
)

apk_path="${ROOT_DIR}/flutter/build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "${apk_path}" ]]; then
  printf 'Expected debug APK was not produced: %s\n' "${apk_path}" >&2
  exit 1
fi
apk_entries="$(unzip -Z1 "${apk_path}")"
if ! grep -q '^lib/arm64-v8a/' <<<"${apk_entries}"; then
  printf 'Dual-ABI APK is missing arm64-v8a native packaging\n' >&2
  exit 1
fi
if ! grep -q '^lib/x86_64/' <<<"${apk_entries}"; then
  printf 'Dual-ABI APK is missing x86_64 native packaging\n' >&2
  exit 1
fi
printf 'Verified dual-ABI packaging: arm64-v8a and x86_64\n'

printf 'Installing the debug APK on %s\n' "${device_id}"
"${adb_command}" -s "${device_id}" install -r "${apk_path}" >/dev/null
"${adb_command}" -s "${device_id}" shell pm clear "${PACKAGE_ID}" >/dev/null
"${adb_command}" -s "${device_id}" shell appops set --uid "${PACKAGE_ID}" \
  MANAGE_EXTERNAL_STORAGE allow
if (( api_level >= 33 )); then
  "${adb_command}" -s "${device_id}" shell pm grant "${PACKAGE_ID}" \
    android.permission.POST_NOTIFICATIONS || true
fi

printf 'Preparing the P02-003 fixture at %s\n' "${FIXTURE_ROOT}"
"${adb_command}" -s "${device_id}" shell rm -rf "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}"
"${adb_command}" -s "${device_id}" shell mkdir -p \
  "${FIXTURE_ROOT}/Nested" "${EVIDENCE_ROOT}"
"${adb_command}" -s "${device_id}" shell \
  "printf 'nested fixture\\n' > '${FIXTURE_ROOT}/Nested/nested.bin'; \
   printf 'keep fixture\\n' > '${FIXTURE_ROOT}/keep.txt'; \
   printf 'remove fixture\\n' > '${FIXTURE_ROOT}/remove-me.bin'; \
   printf 'move fixture\\n' > '${FIXTURE_ROOT}/move-me.bin'"

run_integration_phase() {
  local mode="$1"
  printf 'Running P02-003 Android integration phase: %s\n' "${mode}"
  (
    cd "${ROOT_DIR}/flutter"
    fvm flutter test integration_test/phase_002_android_scan_hierarchy_test.dart \
      --dart-define="ARGUS_PHASE_002_MODE=${mode}" \
      --dart-define="ARGUS_PHASE_002_EVIDENCE_PATH=${SEED_ENTRY_EVIDENCE}" \
      --no-uninstall \
      -d "${device_id}"
  )
}

run_integration_phase seed
if ! "${adb_command}" -s "${device_id}" shell test -s "${SEED_ENTRY_EVIDENCE}"; then
  printf 'Seed phase did not write native move-identity evidence\n' >&2
  exit 1
fi

printf 'Capturing native identity before the Android fixture mutation\n'
native_identity() {
  local path="$1"
  "${adb_command}" -s "${device_id}" shell stat -c '%d:%i' "${path}" \
    | tr -d '\r'
}

identity_before="$(native_identity "${FIXTURE_ROOT}/move-me.bin")"
if [[ ! "${identity_before}" =~ ^[0-9]+:[0-9]+$ ]]; then
  printf 'Could not capture a deterministic native identity before rename: %s\n' \
    "${identity_before}" >&2
  exit 1
fi
"${adb_command}" -s "${device_id}" shell \
  "printf 'added fixture\\n' > '${FIXTURE_ROOT}/added.bin'; \
   rm -f '${FIXTURE_ROOT}/remove-me.bin'; \
   mkdir -p '${FIXTURE_ROOT}/Moved'; \
   mv '${FIXTURE_ROOT}/move-me.bin' '${FIXTURE_ROOT}/Moved/move-me.bin'"
identity_after="$(native_identity "${FIXTURE_ROOT}/Moved/move-me.bin")"
if [[ "${identity_before}" != "${identity_after}" ]]; then
  printf 'Android API 36 did not preserve native identity across rename: %s -> %s\n' \
    "${identity_before}" "${identity_after}" >&2
  exit 1
fi
printf 'Verified native identity continuity across rename: %s\n' "${identity_before}"

"${adb_command}" -s "${device_id}" shell am force-stop "${PACKAGE_ID}"
run_integration_phase reconcile
"${adb_command}" -s "${device_id}" shell am force-stop "${PACKAGE_ID}"

printf 'Preparing the deterministic cancellation subtree\n'
"${adb_command}" -s "${device_id}" shell \
  "i=1; while [ \"\$i\" -le ${CANCEL_DIRECTORIES} ]; do \
     directory='${FIXTURE_ROOT}/CancelBig/d'\"\$i\"; \
     mkdir -p \"\${directory}\"; \
     j=1; while [ \"\$j\" -le ${CANCEL_FILES_PER_DIRECTORY} ]; do \
       printf 'cancel fixture %s/%s\\n' \$i \$j > \$directory/f\$j.bin; \
       j=\$((j + 1)); \
     done; \
     i=\$((i + 1)); \
   done"
run_integration_phase cancel
if ! "${adb_command}" -s "${device_id}" shell test -s "${CANCEL_JOB_EVIDENCE}"; then
  printf 'Cancel phase did not write the cancelled JobRun identity\n' >&2
  exit 1
fi

"${adb_command}" -s "${device_id}" shell am force-stop "${PACKAGE_ID}"
"${adb_command}" -s "${device_id}" shell rm -rf "${FIXTURE_ROOT}/CancelBig"
run_integration_phase retry

printf 'P02-003 Android scan, reconciliation, hierarchy, cancel, and retry milestone passed on %s (API %s, %s)\n' \
  "${device_id}" "${api_level}" "${abi}"
