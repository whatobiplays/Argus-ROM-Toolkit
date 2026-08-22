#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="/sdcard/ArgusP02005PermissionRoot"
EVIDENCE_ROOT="/sdcard/ArgusP02005Evidence"
EVIDENCE_PATH="${EVIDENCE_ROOT}/permission-root-id.txt"
PACKAGE_ID="com.argusromtoolkit.argus"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"
argus_android_require_device
trap '"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell rm -rf "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}" >/dev/null 2>&1 || true' EXIT
argus_android_build_and_install "${ROOT_DIR}"

"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell rm -rf \
  "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}"
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell mkdir -p \
  "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}"
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell \
  "printf 'permission fixture\n' > '${FIXTURE_ROOT}/sentinel.bin'"

run_permission_phase() {
  local mode="$1"
  argus_android_run_integration \
    "${ROOT_DIR}" \
    phase_002_android_permission_reconciliation_test.dart \
    --dart-define=ARGUS_PHASE_002_PERMISSION_MODE="${mode}" \
    --dart-define=ARGUS_PHASE_002_PERMISSION_EVIDENCE_PATH="${EVIDENCE_PATH}" \
    --dart-define=ARGUS_PHASE_002_PERMISSION_ROOT="$(basename "${FIXTURE_ROOT}")"
}

printf 'Recording durable root identity before permission loss\n'
run_permission_phase snapshot
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell am force-stop "${PACKAGE_ID}"

printf 'Revoking All files access and checking the readiness boundary\n'
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell appops set --uid "${PACKAGE_ID}" MANAGE_EXTERNAL_STORAGE ignore
run_permission_phase revoked
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell am force-stop "${PACKAGE_ID}"

printf 'Regranting All files access and checking explicit availability refresh\n'
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell appops set --uid "${PACKAGE_ID}" MANAGE_EXTERNAL_STORAGE allow
run_permission_phase restored

printf 'P02-005 permission revoke/regrant scenario passed on %s\n' \
  "${ARGUS_ANDROID_SCENARIO_DEVICE}"
