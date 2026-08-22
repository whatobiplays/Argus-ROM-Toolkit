#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="com.argusromtoolkit.argus"
FIXTURE_ROOT="/sdcard/ArgusP02006Fixture"
DEVICE_EVIDENCE_ROOT="/sdcard/ArgusP02006Evidence"
DEVICE_EVIDENCE_PATH="${DEVICE_EVIDENCE_ROOT}/adaptive-ux.txt"
DEVICE_CONTINUE_PATH="${DEVICE_EVIDENCE_ROOT}/continue"
HOST_EVIDENCE_DIR="${ROOT_DIR}/build/phase-002-android-adaptive-ux"
HOST_EVIDENCE_PATH="${HOST_EVIDENCE_DIR}/native-qualification.txt"
INTEGRATION_LOG="${HOST_EVIDENCE_DIR}/integration.log"

mkdir -p "${HOST_EVIDENCE_DIR}"
: > "${HOST_EVIDENCE_PATH}"

record() {
  printf '%s\n' "$1" >> "${HOST_EVIDENCE_PATH}"
}

record_unverified_scenarios() {
  local reason="$1"
  local scenario
  for scenario in \
    rotation_activity_recreation \
    background_foreground \
    live_window_resize \
    ordinary_back \
    predictive_back \
    picker_parent_navigation_and_dismissal \
    permission_overlay_return \
    system_bars_insets \
    ime \
    single_runtime_composition; do
    record "scenario=${scenario}|result=unverified|reason=${reason}"
  done
}

# Preserve a complete per-scenario evidence record when the integration test
# fails after some host actions have already completed. This appends only
# scenarios that have not been recorded yet; it never changes a recorded
# pass, failure, or unverified outcome.
record_missing_unverified_scenarios() {
  local reason="$1"
  local scenario
  for scenario in \
    rotation_activity_recreation \
    background_foreground \
    live_window_resize \
    ordinary_back \
    predictive_back \
    picker_parent_navigation_and_dismissal \
    permission_overlay_return \
    system_bars_insets \
    ime \
    single_runtime_composition; do
    if ! grep -Eq "^(flutter=)?scenario=${scenario}\|result=" \
      "${HOST_EVIDENCE_PATH}"; then
      record "scenario=${scenario}|result=unverified|reason=${reason}"
    fi
  done
}

record "run=phase-002-slice-006|started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

adb_command="${ARGUS_ANDROID_ADB:-$(command -v adb || true)}"
if [[ -z "${adb_command}" || ! -x "${adb_command}" ]]; then
  record 'device_id=unavailable|api=unavailable|abi=unavailable'
  record_unverified_scenarios 'adb is not installed or is not executable'
  exit 2
fi
if ! command -v fvm >/dev/null 2>&1; then
  record 'device_id=unavailable|api=unavailable|abi=unavailable'
  record_unverified_scenarios 'fvm is not installed'
  exit 2
fi

# shellcheck disable=SC1091
if ! source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"; then
  record 'device_id=unavailable|api=unavailable|abi=unavailable'
  record_unverified_scenarios 'shared Android scenario helper could not be sourced'
  exit 2
fi
if ! argus_android_require_device; then
  record "device_id=${ARGUS_ANDROID_SCENARIO_DEVICE:-unavailable}|api=${ARGUS_ANDROID_SCENARIO_API:-unavailable}|abi=${ARGUS_ANDROID_SCENARIO_ABI:-unavailable}"
  record_unverified_scenarios 'no supported online API 36 device or emulator'
  exit 2
fi

record "device_id=${ARGUS_ANDROID_SCENARIO_DEVICE}|api=${ARGUS_ANDROID_SCENARIO_API}|abi=${ARGUS_ANDROID_SCENARIO_ABI}"
record 'apk_target_platforms=android-arm64'

restore_host_state() {
  if [[ -n "${ARGUS_ANDROID_SCENARIO_DEVICE:-}" && "${device_state_captured:-0}" == 1 ]]; then
    if [[ "${accelerometer_before}" =~ ^[0-9]+$ ]]; then
      "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell settings put system accelerometer_rotation "${accelerometer_before}" >/dev/null 2>&1 || true
    fi
    if [[ "${rotation_before}" =~ ^[0-9]+$ ]]; then
      "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell settings put system user_rotation "${rotation_before}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${wm_override_before}" ]]; then
      "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell wm size "${wm_override_before}" >/dev/null 2>&1 || true
    else
      "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell wm size reset >/dev/null 2>&1 || true
    fi
    if [[ -n "${error_dialogs_before}" && "${error_dialogs_before}" != null ]]; then
      "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell settings put global hide_error_dialogs \
        "${error_dialogs_before}" >/dev/null 2>&1 || true
    else
      "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell settings delete global hide_error_dialogs >/dev/null 2>&1 || true
    fi
  fi
}

cleanup() {
  local status=$?
  restore_host_state
  if [[ -n "${ARGUS_ANDROID_SCENARIO_DEVICE:-}" ]]; then
    "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
      shell rm -rf "${FIXTURE_ROOT}" "${DEVICE_EVIDENCE_ROOT}" >/dev/null 2>&1 || true
  fi
  exit "${status}"
}
trap cleanup EXIT

if ! argus_android_build_and_install "${ROOT_DIR}" >"${HOST_EVIDENCE_DIR}/build.log" 2>&1; then
  record 'scenario=apk_build_and_install|result=unverified|reason=repository Android build failed; see build.log'
  record_unverified_scenarios 'APK build/install was unavailable'
  exit 2
fi

"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell mkdir -p "${FIXTURE_ROOT}/Nested" "${DEVICE_EVIDENCE_ROOT}"
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" shell \
  "printf 'P02-006 fixture\\n' > '${FIXTURE_ROOT}/Nested/sentinel.bin'"

wm_size_before="$(
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell wm size | tr -d '\r'
)"
wm_override_before="$(awk -F': ' '/^Override size:/ {print $2; exit}' <<<"${wm_size_before}")"
rotation_before="$(
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell settings get system user_rotation | tr -d '\r'
)"
accelerometer_before="$(
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell settings get system accelerometer_rotation | tr -d '\r'
)"
error_dialogs_before="$(
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell settings get global hide_error_dialogs | tr -d '\r'
)"
navigation_mode="$(
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell settings get secure navigation_mode | tr -d '\r'
)"
device_state_captured=1
record "window_before=$(tr '\n' ';' <<<"${wm_size_before}")|rotation_before=${rotation_before}|navigation_mode=${navigation_mode}"

# The first launch after a fresh install performs asset extraction and cold
# runtime initialization and can exceed the emulator's input-response window.
# Warm the app once and hide error dialogs so the qualification launch does
# not race the cold-start ANR window; both are restored in cleanup.
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell settings put global hide_error_dialogs 1 >/dev/null 2>&1 || true
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell am start -W -n "${PACKAGE_ID}/.MainActivity" >/dev/null 2>&1 || true
sleep 10
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell am force-stop "${PACKAGE_ID}" >/dev/null 2>&1 || true

reset_device_evidence() {
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell rm -rf "${DEVICE_EVIDENCE_ROOT}" >/dev/null 2>&1 || true
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell mkdir -p "${DEVICE_CONTINUE_PATH}" >/dev/null 2>&1 || true
}

wait_for_device_file() {
  local path="$1"
  local deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
      shell test -f "${path}" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "${integration_pid}" >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
  done
  return 1
}

write_device_control() {
  local path="$1"
  local contents="$2"
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell "printf '%s' '${contents}' > '${path}'"
}

begin_host_scenario() {
  local command="$1"
  write_device_control "${DEVICE_CONTINUE_PATH}.${command}.begin" begin
  wait_for_device_file "${DEVICE_CONTINUE_PATH}.${command}.baseline"
}

finish_host_scenario() {
  local command="$1"
  local result="$2"
  write_device_control "${DEVICE_CONTINUE_PATH}.${command}.done" "${result}"
  wait_for_device_file "${DEVICE_CONTINUE_PATH}.${command}.ack"
}

abort_integration_scenario() {
  local scenario="$1"
  local reason="$2"
  record "attempt=${CURRENT_ATTEMPT}|scenario=${scenario}|result=unverified|reason=${reason}"
  local device_evidence
  device_evidence="$(${ARGUS_ANDROID_SCENARIO_ADB} -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell cat "${DEVICE_EVIDENCE_PATH}" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "${device_evidence}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && record "flutter=${line}"
    done <<<"${device_evidence}"
  fi
  kill "${integration_pid}" >/dev/null 2>&1 || true
  wait "${integration_pid}" >/dev/null 2>&1 || true
  # The caller decides the attempt failure status; returning zero keeps this
  # reporting routine safe under `set -e`.
  return 0
}

run_integration_attempt() {
  CURRENT_ATTEMPT="$1"
  # A failed attempt may have left host state rotated/resized; the next
  # attempt starts from the captured baseline again.
  restore_host_state
  reset_device_evidence

  set +e
  argus_android_run_integration \
    "${ROOT_DIR}" \
    phase_002_android_adaptive_ux_test.dart \
    --dart-define=ARGUS_PHASE_002_ADAPTIVE_EVIDENCE_PATH="${DEVICE_EVIDENCE_PATH}" \
    --dart-define=ARGUS_PHASE_002_ADAPTIVE_CONTINUE_PATH="${DEVICE_CONTINUE_PATH}" \
    >"${INTEGRATION_LOG}" 2>&1 &
  integration_pid=$!
  set -e

  if ! wait_for_device_file "${DEVICE_CONTINUE_PATH}.ready"; then
    record "attempt=${CURRENT_ATTEMPT}|scenario=integration_start|result=unverified|reason=integration test did not reach its ready marker; see integration.log"
    kill "${integration_pid}" >/dev/null 2>&1 || true
    wait "${integration_pid}" >/dev/null 2>&1 || true
    return 1
  fi

  # Exercise host-owned Activity/window transitions while the Flutter test
  # holds the application-scoped runtime open. Each host action has a Flutter
  # baseline, completion marker, and UI/lifecycle assertion before it can be
  # recorded as passed. Every mutation is restored for the next attempt and in
  # cleanup.
  if ! begin_host_scenario resize; then
    abort_integration_scenario live_window_resize 'Flutter scenario did not acknowledge the resize baseline'
    return 2
  fi
  if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell wm size 720x1280 >/dev/null 2>&1; then
    finish_host_scenario resize 'command=passed|action=adb_shell_wm_size_720x1280' ||
      { abort_integration_scenario live_window_resize 'Flutter scenario did not acknowledge resize completion'; return 2; }
  else
    finish_host_scenario resize 'command=unverified|reason=wm_size_command_unavailable' ||
      { abort_integration_scenario live_window_resize 'Flutter scenario did not acknowledge resize failure'; return 2; }
  fi

  rotation_target=1
  if [[ "${rotation_before}" =~ ^[0-9]+$ ]]; then
    rotation_target=$(( (rotation_before + 1) % 4 ))
  fi
  if ! begin_host_scenario rotation; then
    abort_integration_scenario rotation_activity_recreation 'Flutter scenario did not acknowledge the rotation baseline'
    return 2
  fi
  if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell settings put system accelerometer_rotation 0 >/dev/null 2>&1 &&
    "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell settings put system user_rotation "${rotation_target}" >/dev/null 2>&1; then
    finish_host_scenario rotation 'command=passed|action=system_user_rotation' ||
      { abort_integration_scenario rotation_activity_recreation 'Flutter scenario did not acknowledge rotation completion'; return 2; }
  else
    finish_host_scenario rotation 'command=unverified|reason=rotation_settings_unavailable' ||
      { abort_integration_scenario rotation_activity_recreation 'Flutter scenario did not acknowledge rotation failure'; return 2; }
  fi

  if ! begin_host_scenario background; then
    abort_integration_scenario background_foreground 'Flutter scenario did not acknowledge the background baseline'
    return 2
  fi
  if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell input keyevent KEYCODE_HOME >/dev/null 2>&1 &&
    sleep 2 &&
    "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell am start -W --activity-reorder-to-front --activity-single-top \
      -n "${PACKAGE_ID}/.MainActivity" >/dev/null 2>&1 &&
    sleep 2; then
    finish_host_scenario background 'command=passed|action=home_then_activity_reorder_to_front' ||
      { abort_integration_scenario background_foreground 'Flutter scenario did not acknowledge background completion'; return 2; }
  else
    finish_host_scenario background 'command=unverified|reason=Activity_foreground_command_unavailable' ||
      { abort_integration_scenario background_foreground 'Flutter scenario did not acknowledge background failure'; return 2; }
  fi

  if ! begin_host_scenario ordinary_back; then
    abort_integration_scenario ordinary_back 'Flutter scenario did not acknowledge the Back baseline'
    return 2
  fi
  if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell input keyevent KEYCODE_BACK >/dev/null 2>&1 &&
    "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell am start -n "${PACKAGE_ID}/.MainActivity" >/dev/null 2>&1; then
    finish_host_scenario ordinary_back 'command=passed|action=keyevent_back_then_activity_relaunch' ||
      { abort_integration_scenario ordinary_back 'Flutter scenario did not acknowledge Back completion'; return 2; }
  else
    finish_host_scenario ordinary_back 'command=unverified|reason=Back_relaunch_command_unavailable' ||
      { abort_integration_scenario ordinary_back 'Flutter scenario did not acknowledge Back failure'; return 2; }
  fi

  if ! begin_host_scenario permission_overlay; then
    abort_integration_scenario permission_overlay_return 'Flutter scenario did not acknowledge the permission-overlay baseline'
    return 2
  fi
  permission_result='command=unverified|reason=settings_overlay_command_unavailable'
  if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell am start -W -a android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION \
    -d "package:${PACKAGE_ID}" >/dev/null 2>&1; then
    settings_overlay_visible=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell dumpsys activity activities 2>/dev/null |
        grep -Eq 'topResumedActivity=.*com\.android\.settings|mCurrentFocus=.*com\.android\.settings'; then
        settings_overlay_visible=1
        break
      fi
      sleep 1
    done
    if (( settings_overlay_visible == 1 )) &&
      "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell input keyevent KEYCODE_BACK >/dev/null 2>&1; then
      permission_result='command=passed|action=all_files_settings_then_back'
    else
      permission_result='command=unverified|reason=settings_overlay_not_foreground'
    fi
  fi
  finish_host_scenario permission_overlay "${permission_result}" ||
    { abort_integration_scenario permission_overlay_return 'Flutter scenario did not acknowledge overlay completion'; return 2; }
  record "attempt=${CURRENT_ATTEMPT}|host=permission_overlay|${permission_result}"

  if [[ "${navigation_mode}" == 2 ]]; then
    record 'host=predictive_back|result=unverified|reason=adb cannot assert predictive progress and Flutter 3.44.7 exposes no progress API for nested local PopScope state'
  else
    record 'host=predictive_back|result=unverified|reason=device is not configured for gesture navigation'
  fi

  if wait_for_device_file "${DEVICE_CONTINUE_PATH}.picker.ready"; then
    for index in 1 2 3; do
      if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
        shell input keyevent KEYCODE_BACK >/dev/null 2>&1; then
        write_device_control "${DEVICE_CONTINUE_PATH}.picker.back${index}.done" \
          'command=passed|action=keyevent_back'
      else
        write_device_control "${DEVICE_CONTINUE_PATH}.picker.back${index}.done" \
          'command=unverified|reason=Back_keyevent_unavailable'
      fi
      if ! wait_for_device_file "${DEVICE_CONTINUE_PATH}.picker.back${index}.ack"; then
        abort_integration_scenario picker_parent_navigation_and_dismissal \
          "Flutter scenario did not acknowledge picker Back ${index}"
        return 2
      fi
    done
  fi

  set +e
  wait "${integration_pid}"
  integration_status=$?
  set -e

  device_evidence="$(${ARGUS_ANDROID_SCENARIO_ADB} -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell cat "${DEVICE_EVIDENCE_PATH}" 2>/dev/null | tr -d '\r' || true)"
  if [[ -n "${device_evidence}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && record "flutter=${line}"
    done <<<"${device_evidence}"
  fi

  return "${integration_status}"
}

final_status=2
for CURRENT_ATTEMPT in 1 2 3; do
  record "integration_attempt=${CURRENT_ATTEMPT}|started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if run_integration_attempt "${CURRENT_ATTEMPT}"; then
    final_status=0
    break
  else
    final_status=$?
  fi
  record "integration_attempt=${CURRENT_ATTEMPT}|result=failed|exit_code=${final_status}"
done

if (( final_status != 0 )); then
  record_missing_unverified_scenarios \
    'integration test failed before this scenario completed; see integration.log'
  record "scenario=integration_test|result=failed|exit_code=${final_status}|see=integration.log"
  exit "${final_status}"
fi

record "status=completed_with_unverified_scenarios|finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
