#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="${ROOT_DIR}/build/phase-002-android-final"
EVIDENCE_PATH="${EVIDENCE_DIR}/native-qualification.txt"
REQUIRED_TOOLS=(adb fvm unzip rg timeout mktemp zip sqlite3 javac jar)

record() {
  printf '%s\n' "$1" >> "${EVIDENCE_PATH}"
}

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"

mkdir -p "${EVIDENCE_DIR}"
: > "${EVIDENCE_PATH}"

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    record "run=phase-002-android-final|started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    record "device_id=${ARGUS_ANDROID_SCENARIO_DEVICE:-unavailable}"
    record "result=not_run|reason=required host tool is missing: ${tool}"
    printf 'Final Phase 002 Android milestone could not run: missing %s\n' \
      "${tool}" >&2
    exit 2
  fi
done

if ! argus_android_require_device; then
  record "run=phase-002-android-final|started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  record "device_id=${ARGUS_ANDROID_SCENARIO_DEVICE:-unavailable}|api=${ARGUS_ANDROID_SCENARIO_API:-unavailable}|abi=${ARGUS_ANDROID_SCENARIO_ABI:-unavailable}"
  record "result=not_run|reason=no supported API 36 arm64-v8a Android device"
  exit 2
fi

record "run=phase-002-android-final|started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
record "device_id=${ARGUS_ANDROID_SCENARIO_DEVICE}|api=${ARGUS_ANDROID_SCENARIO_API}|abi=${ARGUS_ANDROID_SCENARIO_ABI}"

export ARGUS_ANDROID_DEVICE_ID="${ARGUS_ANDROID_SCENARIO_DEVICE}"
export ARGUS_ANDROID_ADB="${ARGUS_ANDROID_SCENARIO_ADB}"

scenarios=(
  'bootstrap|run_phase_002_android_bootstrap_tests.sh'
  'local_filesystem|run_phase_002_android_local_filesystem_tests.sh'
  'scan|run_phase_002_android_scan_tests.sh'
  'foreground|run_phase_002_android_foreground_execution_tests.sh'
  'applicable_features|run_phase_002_android_applicable_features_tests.sh'
  'multi_root|run_phase_002_android_multi_root_tests.sh'
  'permission_reconciliation|run_phase_002_android_permission_reconciliation_tests.sh'
  'removable_volume|run_phase_002_android_removable_volume_tests.sh'
  'diagnostics|run_phase_002_android_diagnostics_tests.sh'
  'adaptive_ux|run_phase_002_android_adaptive_ux_tests.sh'
)

final_status=0
for entry in "${scenarios[@]}"; do
  scenario_name="${entry%%|*}"
  scenario_script="${entry#*|}"
  set +e
  output="$(bash "${ROOT_DIR}/scripts/${scenario_script}" 2>&1)"
  status=$?
  set -e

  result="failed"
  reason=""
  if (( status == 0 )); then
    result="passed"
  elif [[ "${scenario_name}" == removable_volume && "${status}" == 2 ]]; then
    result="not_applicable"
    reason="$(printf '%s\n' "${output}" |
      rg -o 'UNVERIFIED:.*' | head -n 1 || true)"
  fi
  if [[ "${result}" == failed ]]; then
    reason="$(printf '%s\n' "${output}" | tail -n 5 | tr '\n' ' ' |
      cut -c1-200)"
    final_status=2
  fi
  record "scenario=${scenario_name}|result=${result}|exit_code=${status}|reason=${reason}"
  printf 'scenario=%s result=%s exit_code=%s\n' \
    "${scenario_name}" "${result}" "${status}"
done

record "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if (( final_status != 0 )); then
  printf 'Final Phase 002 Android milestone recorded failures; see %s\n' \
    "${EVIDENCE_PATH}" >&2
  exit "${final_status}"
fi
printf 'Final Phase 002 Android milestone completed; see %s\n' \
  "${EVIDENCE_PATH}"
