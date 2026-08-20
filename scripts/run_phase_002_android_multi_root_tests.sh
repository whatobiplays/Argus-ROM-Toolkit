#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="/sdcard/ArgusP02005MultiRoot"
EVIDENCE_ROOT="/sdcard/ArgusP02005Evidence"
EVIDENCE_PATH="${EVIDENCE_ROOT}/multi-root.txt"
PACKAGE_ID="dev.argusromtoolkit.argus"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"
argus_android_require_device
trap '"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell rm -rf "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}" >/dev/null 2>&1 || true' EXIT
argus_android_build_and_install "${ROOT_DIR}"

"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell rm -rf \
  "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}"
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell mkdir -p \
  "${FIXTURE_ROOT}/ArgusP02005RootA" "${FIXTURE_ROOT}/ArgusP02005RootB" \
  "${EVIDENCE_ROOT}"
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell \
  "printf 'root A\n' > '${FIXTURE_ROOT}/ArgusP02005RootA/a.bin'; \
   printf 'root B\n' > '${FIXTURE_ROOT}/ArgusP02005RootB/b.bin'"

printf 'Running focused multi-root admission phase\n'
argus_android_run_integration \
  "${ROOT_DIR}" \
  phase_002_android_multi_root_scan_all_test.dart \
  --dart-define=ARGUS_PHASE_002_MULTI_ROOT_MODE=seed \
  --dart-define=ARGUS_PHASE_002_MULTI_ROOT_EVIDENCE_PATH="${EVIDENCE_PATH}"

"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell am force-stop "${PACKAGE_ID}"

printf 'Running focused Scan All execution phase\n'
argus_android_run_integration \
  "${ROOT_DIR}" \
  phase_002_android_multi_root_scan_all_test.dart \
  --dart-define=ARGUS_PHASE_002_MULTI_ROOT_MODE=scan \
  --dart-define=ARGUS_PHASE_002_MULTI_ROOT_EVIDENCE_PATH="${EVIDENCE_PATH}"

printf 'P02-005 multi-root and Scan All scenario passed on %s\n' \
  "${ARGUS_ANDROID_SCENARIO_DEVICE}"
