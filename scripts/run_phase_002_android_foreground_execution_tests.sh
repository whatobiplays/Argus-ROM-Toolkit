#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="dev.argusromtoolkit.argus"
ANDROID_USER_ID="${ARGUS_ANDROID_USER_ID:-0}"
FGS_COMPAT_CHANGE="FGS_INTRODUCE_TIME_LIMITS"
NOTIFICATION_PERMISSION="android.permission.POST_NOTIFICATIONS"
NOTIFICATION_APPOP="POST_NOTIFICATION"
STORAGE_APPOP="MANAGE_EXTERNAL_STORAGE"
FIXTURE_ROOT="/sdcard/ArgusP02004Fixture"
EVIDENCE_ROOT="/sdcard/ArgusP02004Evidence"
EVIDENCE_PATH="${EVIDENCE_ROOT}/foreground.txt"
NOTIFICATION_PROMPT_MARKER="${EVIDENCE_PATH}.notification-prompt"
CONTINUE_PATH="${EVIDENCE_ROOT}/continue"
CANCEL_MARKER="${EVIDENCE_PATH}.cancel-invoked"
# Keep the transient shell-owned UI capture outside both the app-written
# evidence directory and emulated storage. The latter can add FUSE latency or
# ownership races while the Flutter test is updating its marker files.
UI_XML="/data/local/tmp/ArgusP02004NotificationUi.xml"
# Keep a bounded real filesystem workload in flight long enough for the
# host-driven lifecycle and SystemUI actions without making emulator FUSE
# provisioning dominate the milestone. Six hundred directories with twenty
# files each produce about 12,600 finite filesystem nodes. The fixture is
# archive-packed for one transfer and always removed by unconditional cleanup.
FIXTURE_DIRECTORY_COUNT=600
FIXTURE_FILES_PER_DIRECTORY=20
host_fixture_root=''
fixture_archive=''
notification_events_pid=''
mode_pid=''
# Optional focused-stage stop used when diagnosing one native milestone stage;
# the normal target leaves this empty and runs every required stage.
stop_after_stage="${ARGUS_ANDROID_FOREGROUND_STOP_AFTER:-}"
state_snapshot_ready=0
original_always_finish=''
original_timeout=''
original_compat_override=''
original_notification_permission_state=''
original_notification_permission_flags=''
original_notification_appop_uid_mode=''
original_notification_appop_package_mode=''
original_storage_appop_uid_mode=''
original_storage_appop_package_mode=''
cleanup_restore_failed=0
MANIFEST_PATH="${ROOT_DIR}/flutter/android/app/src/main/AndroidManifest.xml"
LOG_DIR="${ROOT_DIR}/build/phase-002-android-foreground"
UI_CAPTURE_PATH="${LOG_DIR}/notification-ui-last.xml"
UI_DUMP_LOG="${LOG_DIR}/notification-ui-dump.log"
UI_RAW_PATH="${LOG_DIR}/notification-ui-raw.xml"
UI_AUTOMATION_SOURCE_DIR="${ROOT_DIR}/scripts/android_notification_cancel"
ui_automation_build_dir=''

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
command -v rg >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: rg\n' >&2
  exit 1
}
command -v timeout >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: timeout\n' >&2
  exit 1
}
command -v mktemp >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: mktemp\n' >&2
  exit 1
}
command -v zip >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: zip\n' >&2
  exit 1
}

adb_binary_path="$(command -v "${adb_command}" 2>/dev/null || printf '%s' "${adb_command}")"
android_sdk_root="${ARGUS_ANDROID_SDK_ROOT:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}}"
if [[ -z "${android_sdk_root}" ]]; then
  if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    android_sdk_root="$(cd "${ANDROID_NDK_HOME}/../.." && pwd)"
  elif [[ -f "${ROOT_DIR}/flutter/android/local.properties" ]]; then
    android_sdk_root="$(sed -n 's/^sdk\.dir=//p' \
      "${ROOT_DIR}/flutter/android/local.properties" | head -n 1)"
  fi
fi
if [[ -z "${android_sdk_root}" ]]; then
  android_sdk_root="$(cd "$(dirname "${adb_binary_path}")/.." && pwd)"
fi

device_id="${ARGUS_ANDROID_DEVICE_ID:-}"
rg -q 'android.permission.FOREGROUND_SERVICE' "${MANIFEST_PATH}"
rg -q 'android.permission.FOREGROUND_SERVICE_DATA_SYNC' "${MANIFEST_PATH}"
rg -q 'android:name="\.ArgusForegroundExecutionService"' "${MANIFEST_PATH}"
rg -q 'android:exported="false"' "${MANIFEST_PATH}"
rg -q 'android:foregroundServiceType="dataSync"' "${MANIFEST_PATH}"
if rg -q 'BOOT_COMPLETED|WorkManager|AlarmManager|WAKE_LOCK' "${MANIFEST_PATH}"; then
  printf 'Manifest contains an out-of-scope restart/scheduler/wake-lock declaration\n' >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
: > "${UI_DUMP_LOG}"

printf 'Building the repository-owned dual-ABI debug APK\n'
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
grep -q '^lib/arm64-v8a/' <<<"${apk_entries}"
grep -q '^lib/x86_64/' <<<"${apk_entries}"
printf 'Verified dual-ABI packaging: arm64-v8a and x86_64\n'

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
  printf 'P02-004 requires Android API 36; device reports %s\n' "${api_level}" >&2
  exit 1
fi

abi="$(${adb_command} -s "${device_id}" shell getprop ro.product.cpu.abi | tr -d '\r')"
if [[ "${abi}" != arm64-v8a ]]; then
  printf 'P02-004 native execution requires ARM64; device reports %s\n' "${abi}" >&2
  exit 1
fi

settable_permission_flags=(
  review-required
  revoked-compat
  revoke-when-requested
  user-fixed
  user-set
)

read_notification_permission_state() {
  local permission_line=''
  permission_line="$(${adb_command} -s "${device_id}" shell dumpsys package "${PACKAGE_ID}" \
    | tr -d '\r' \
    | awk -v permission="${NOTIFICATION_PERMISSION}" '
        /runtime permissions:/ { in_runtime = 1; next }
        in_runtime && index($0, permission ":") > 0 { print; exit }
      ' || true)"
  if [[ -z "${permission_line}" ]]; then
    printf 'revoked\n'
    return 0
  fi
  if [[ "${permission_line}" == *'granted=true'* ]]; then
    printf 'granted\n'
  else
    printf 'revoked\n'
  fi
}

read_notification_permission_flags() {
  local permission_line=''
  local raw_flags=''
  local flag=''
  local display_flag=''
  permission_line="$(${adb_command} -s "${device_id}" shell dumpsys package "${PACKAGE_ID}" \
    | tr -d '\r' \
    | awk -v permission="${NOTIFICATION_PERMISSION}" '
        /runtime permissions:/ { in_runtime = 1; next }
        in_runtime && index($0, permission ":") > 0 { print; exit }
      ' || true)"
  raw_flags="${permission_line#*flags=[}"
  if [[ "${raw_flags}" == "${permission_line}" ]]; then
    return 0
  fi
  raw_flags="${raw_flags%%]*}"
  for flag in "${settable_permission_flags[@]}"; do
    display_flag="$(printf '%s' "${flag}" | tr '[:lower:]' '[:upper:]')"
    display_flag="${display_flag//-/_}"
    if [[ " ${raw_flags} " == *" ${display_flag} "* ]]; then
      printf '%s\n' "${flag}"
    fi
  done
}

read_appop_mode() {
  local scope="$1"
  local operation="$2"
  local output=''
  if [[ "${scope}" == uid ]]; then
    output="$(${adb_command} -s "${device_id}" shell appops get --uid \
      "${PACKAGE_ID}" "${operation}" | tr -d '\r' || true)"
    printf '%s\n' "${output}" \
      | sed -n -E "s/^Uid mode: ${operation}: (allow|ignore|deny|default).*/\1/p" \
      | head -n 1
  else
    output="$(${adb_command} -s "${device_id}" shell appops get --user \
      "${ANDROID_USER_ID}" "${PACKAGE_ID}" "${operation}" \
      | tr -d '\r' || true)"
    printf '%s\n' "${output}" \
      | sed -n -E "s/^${operation}: (allow|ignore|deny|default).*/\1/p" \
      | head -n 1
  fi
}

read_compat_override() {
  local compat_line=''
  local package_regex=''
  local override=''
  compat_line="$(${adb_command} -s "${device_id}" shell dumpsys platform_compat \
    | tr -d '\r' \
    | awk -v change="${FGS_COMPAT_CHANGE}" \
      'index($0, "name=" change ";") > 0 { print; exit }' || true)"
  if [[ -z "${compat_line}" ]]; then
    printf 'Could not query %s from dumpsys platform_compat\n' \
      "${FGS_COMPAT_CHANGE}" >&2
    return 1
  fi
  package_regex="${PACKAGE_ID//./\\.}"
  override="$(printf '%s\n' "${compat_line}" \
    | sed -n "s/.*packageOverrides={[^}]*${package_regex}=\\([^,}]*\\).*/\\1/p")"
  case "${override}" in
    true|false)
      printf '%s\n' "${override}"
      ;;
    '')
      printf 'default\n'
      ;;
    *)
      printf 'Unsupported %s override value: %s\n' \
        "${FGS_COMPAT_CHANGE}" "${override}" >&2
      return 1
      ;;
  esac
}

snapshot_environment_state() {
  original_always_finish="$(${adb_command} -s "${device_id}" shell settings get \
    global always_finish_activities | tr -d '\r')"
  original_timeout="$(${adb_command} -s "${device_id}" shell device_config get \
    activity_manager data_sync_fgs_timeout_duration | tr -d '\r')"
  original_compat_override="$(read_compat_override)"
  original_notification_permission_state="$(read_notification_permission_state)"
  original_notification_permission_flags="$(read_notification_permission_flags)"
  original_notification_appop_uid_mode="$(read_appop_mode uid "${NOTIFICATION_APPOP}")"
  original_notification_appop_package_mode="$(read_appop_mode package "${NOTIFICATION_APPOP}")"
  original_storage_appop_uid_mode="$(read_appop_mode uid "${STORAGE_APPOP}")"
  original_storage_appop_package_mode="$(read_appop_mode package "${STORAGE_APPOP}")"

  : > "${LOG_DIR}/environment-snapshot.txt"
  {
    printf 'device_id=%s\n' "${device_id}"
    printf 'api_level=%s\n' "${api_level}"
    printf 'abi=%s\n' "${abi}"
    printf 'always_finish_activities=%s\n' "${original_always_finish}"
    printf 'data_sync_fgs_timeout_duration=%s\n' "${original_timeout}"
    printf '%s.package_override=%s\n' "${FGS_COMPAT_CHANGE}" \
      "${original_compat_override}"
    printf '%s.permission_state=%s\n' "${NOTIFICATION_PERMISSION}" \
      "${original_notification_permission_state}"
    printf '%s.permission_flags=%s\n' "${NOTIFICATION_PERMISSION}" \
      "${original_notification_permission_flags//$'\n'/,}"
    printf '%s.uid_mode=%s\n' "${NOTIFICATION_APPOP}" \
      "${original_notification_appop_uid_mode:-default}"
    printf '%s.package_mode=%s\n' "${NOTIFICATION_APPOP}" \
      "${original_notification_appop_package_mode:-default}"
    printf '%s.uid_mode=%s\n' "${STORAGE_APPOP}" \
      "${original_storage_appop_uid_mode:-default}"
    printf '%s.package_mode=%s\n' "${STORAGE_APPOP}" \
      "${original_storage_appop_package_mode:-default}"
  } >> "${LOG_DIR}/environment-snapshot.txt"
  state_snapshot_ready=1
}

restore_notification_permission_flags() {
  local flag=''
  for flag in "${settable_permission_flags[@]}"; do
    ${adb_command} -s "${device_id}" shell pm clear-permission-flags \
      --user "${ANDROID_USER_ID}" "${PACKAGE_ID}" "${NOTIFICATION_PERMISSION}" \
      "${flag}" >/dev/null 2>&1 || true
  done
  while IFS= read -r flag; do
    [[ -z "${flag}" ]] && continue
    ${adb_command} -s "${device_id}" shell pm set-permission-flags \
      --user "${ANDROID_USER_ID}" "${PACKAGE_ID}" "${NOTIFICATION_PERMISSION}" \
      "${flag}" >/dev/null
  done <<< "${original_notification_permission_flags}"
}

restore_notification_permission() {
  if [[ "${original_notification_permission_state}" == granted ]]; then
    ${adb_command} -s "${device_id}" shell pm grant --user "${ANDROID_USER_ID}" \
      "${PACKAGE_ID}" "${NOTIFICATION_PERMISSION}" >/dev/null
  else
    ${adb_command} -s "${device_id}" shell pm revoke --user "${ANDROID_USER_ID}" \
      "${PACKAGE_ID}" "${NOTIFICATION_PERMISSION}" >/dev/null 2>&1 || true
  fi
  restore_notification_permission_flags
}

restore_appop_mode() {
  local operation="$1"
  local uid_mode="$2"
  local package_mode="$3"
  ${adb_command} -s "${device_id}" shell appops set --uid "${PACKAGE_ID}" \
    "${operation}" "${uid_mode:-default}" >/dev/null
  ${adb_command} -s "${device_id}" shell appops set --user "${ANDROID_USER_ID}" \
    "${PACKAGE_ID}" "${operation}" "${package_mode:-default}" >/dev/null
}

restore_compat_override() {
  case "${original_compat_override}" in
    default)
      ${adb_command} -s "${device_id}" shell am compat reset \
        "${FGS_COMPAT_CHANGE}" "${PACKAGE_ID}" >/dev/null
      ;;
    true)
      ${adb_command} -s "${device_id}" shell am compat enable \
        "${FGS_COMPAT_CHANGE}" "${PACKAGE_ID}" >/dev/null
      ;;
    false)
      ${adb_command} -s "${device_id}" shell am compat disable \
        "${FGS_COMPAT_CHANGE}" "${PACKAGE_ID}" >/dev/null
      ;;
    *)
      printf 'Cannot restore unknown compat snapshot: %s\n' \
        "${original_compat_override}" >&2
      return 1
      ;;
  esac
}

enable_timeout_compat_for_api_36() {
  local compat_output=''
  if compat_output="$(${adb_command} -s "${device_id}" shell am compat enable \
    "${FGS_COMPAT_CHANGE}" "${PACKAGE_ID}" 2>&1)"; then
    printf 'Enabled %s package override for timeout stage\n' \
      "${FGS_COMPAT_CHANGE}" >> "${LOG_DIR}/timeout.log"
    return 0
  fi
  if [[ "${compat_output}" == *'targetSdk'*'above the change'* ]] && \
      [[ "$(read_compat_override)" == default ]]; then
    printf '%s is default-effective for targetSdk 36; Android rejected a redundant package override: %s\n' \
      "${FGS_COMPAT_CHANGE}" "${compat_output}" >> "${LOG_DIR}/timeout.log"
    return 0
  fi
  printf 'Could not enable %s for timeout stage: %s\n' \
    "${FGS_COMPAT_CHANGE}" "${compat_output}" >&2
  return 1
}

restore_always_finish_activities() {
  if [[ -z "${original_always_finish}" || "${original_always_finish}" == null ]]; then
    ${adb_command} -s "${device_id}" shell settings delete global \
      always_finish_activities >/dev/null
  else
    ${adb_command} -s "${device_id}" shell settings put global \
      always_finish_activities "${original_always_finish}" >/dev/null
  fi
}

verify_restored_environment_state() {
  local current_always_finish=''
  local current_timeout=''
  local current_permission_state=''
  local current_permission_flags=''
  local current_compat_override=''
  local current_uid_mode=''
  local current_package_mode=''
  current_always_finish="$(${adb_command} -s "${device_id}" shell settings get \
    global always_finish_activities | tr -d '\r')"
  current_timeout="$(${adb_command} -s "${device_id}" shell device_config get \
    activity_manager data_sync_fgs_timeout_duration | tr -d '\r')"
  if [[ "${current_always_finish}" != "${original_always_finish}" ]]; then
    printf 'always_finish_activities was not restored: expected=%s actual=%s\n' \
      "${original_always_finish}" "${current_always_finish}" >&2
    return 1
  fi
  if [[ "${current_timeout}" != "${original_timeout}" ]]; then
    printf 'data_sync_fgs_timeout_duration was not restored: expected=%s actual=%s\n' \
      "${original_timeout}" "${current_timeout}" >&2
    return 1
  fi
  current_permission_state="$(read_notification_permission_state)"
  current_permission_flags="$(read_notification_permission_flags)"
  current_compat_override="$(read_compat_override)"
  if [[ "${current_permission_state}" != "${original_notification_permission_state}" ]]; then
    printf 'POST_NOTIFICATIONS permission state was not restored: expected=%s actual=%s\n' \
      "${original_notification_permission_state}" "${current_permission_state}" >&2
    return 1
  fi
  if [[ "${current_permission_flags}" != "${original_notification_permission_flags}" ]]; then
    printf 'POST_NOTIFICATIONS permission flags were not restored\n' >&2
    return 1
  fi
  if [[ "${current_compat_override}" != "${original_compat_override}" ]]; then
    printf '%s compat state was not restored: expected=%s actual=%s\n' \
      "${FGS_COMPAT_CHANGE}" "${original_compat_override}" \
      "${current_compat_override}" >&2
    return 1
  fi
  current_uid_mode="$(read_appop_mode uid "${NOTIFICATION_APPOP}")"
  current_package_mode="$(read_appop_mode package "${NOTIFICATION_APPOP}")"
  if [[ "${current_uid_mode:-default}" != "${original_notification_appop_uid_mode:-default}" || \
        "${current_package_mode:-default}" != "${original_notification_appop_package_mode:-default}" ]]; then
    printf '%s app-op state was not restored\n' "${NOTIFICATION_APPOP}" >&2
    return 1
  fi
  current_uid_mode="$(read_appop_mode uid "${STORAGE_APPOP}")"
  current_package_mode="$(read_appop_mode package "${STORAGE_APPOP}")"
  if [[ "${current_uid_mode:-default}" != "${original_storage_appop_uid_mode:-default}" || \
        "${current_package_mode:-default}" != "${original_storage_appop_package_mode:-default}" ]]; then
    printf '%s app-op state was not restored\n' "${STORAGE_APPOP}" >&2
    return 1
  fi
}

cleanup() {
  local original_exit_status=$?
  cleanup_restore_failed=0
  if [[ -n "${notification_events_pid}" ]]; then
    kill -TERM "${notification_events_pid}" >/dev/null 2>&1 || true
    wait "${notification_events_pid}" >/dev/null 2>&1 || true
    notification_events_pid=''
  fi
  if [[ -n "${device_id}" ]]; then
    if [[ -n "${mode_pid}" ]] && kill -0 "${mode_pid}" >/dev/null 2>&1; then
      kill -TERM "${mode_pid}" >/dev/null 2>&1 || true
      wait "${mode_pid}" >/dev/null 2>&1 || true
      mode_pid=''
    fi
    if (( state_snapshot_ready > 0 )); then
      restore_always_finish_activities >/dev/null 2>&1 || cleanup_restore_failed=1
      if [[ -z "${original_timeout}" || "${original_timeout}" == null ]]; then
        ${adb_command} -s "${device_id}" shell device_config delete activity_manager \
          data_sync_fgs_timeout_duration >/dev/null 2>&1 || cleanup_restore_failed=1
      else
        ${adb_command} -s "${device_id}" shell device_config put activity_manager \
          data_sync_fgs_timeout_duration "${original_timeout}" \
          >/dev/null 2>&1 || cleanup_restore_failed=1
      fi
      restore_compat_override || cleanup_restore_failed=1
      restore_notification_permission || cleanup_restore_failed=1
      restore_appop_mode "${NOTIFICATION_APPOP}" \
        "${original_notification_appop_uid_mode}" \
        "${original_notification_appop_package_mode}" || cleanup_restore_failed=1
      restore_appop_mode "${STORAGE_APPOP}" \
        "${original_storage_appop_uid_mode}" \
        "${original_storage_appop_package_mode}" || cleanup_restore_failed=1
      # API 36 can synthesize REVOKED_COMPAT when POST_NOTIFICATION is
      # restored to its default UID mode. Reapply the original permission
      # flags after app-op restoration to remove that compatibility bridge
      # state before the exact observable-state verification.
      restore_notification_permission_flags || cleanup_restore_failed=1
      verify_restored_environment_state || cleanup_restore_failed=1
    fi
    timeout --signal=TERM --kill-after=5s 30s \
      "${adb_command}" -s "${device_id}" pull "${UI_XML}" "${UI_CAPTURE_PATH}" \
      >/dev/null 2>&1 || true
    ${adb_command} -s "${device_id}" shell toybox rm -f "${UI_XML}"
    ${adb_command} -s "${device_id}" shell toybox rm -rf "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}" \
      >/dev/null 2>&1 || true
    ${adb_command} -s "${device_id}" shell am force-stop "${PACKAGE_ID}" \
      >/dev/null 2>&1 || true
  fi
  if [[ -n "${fixture_archive}" ]]; then
    rm -f "${fixture_archive}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${host_fixture_root}" ]]; then
    rm -rf "${host_fixture_root}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${ui_automation_build_dir}" ]]; then
    rm -rf "${ui_automation_build_dir}" >/dev/null 2>&1 || true
  fi
  if (( original_exit_status == 0 && cleanup_restore_failed > 0 )); then
    return 1
  fi
  return "${original_exit_status}"
}
trap cleanup EXIT

snapshot_environment_state

printf 'Installing the foreground-execution milestone APK on %s\n' "${device_id}"
# API 36 ARM64 emulator streamed installs can remain blocked after the APK
# transfer completes. Push-installing the same APK keeps package installation
# bounded without changing the application or milestone assertions.
${adb_command} -s "${device_id}" install --no-streaming -r "${apk_path}" >/dev/null
${adb_command} -s "${device_id}" shell pm clear "${PACKAGE_ID}" >/dev/null
${adb_command} -s "${device_id}" shell appops set --uid "${PACKAGE_ID}" \
  "${STORAGE_APPOP}" allow
${adb_command} -s "${device_id}" shell pm grant --user "${ANDROID_USER_ID}" \
  "${PACKAGE_ID}" "${NOTIFICATION_PERMISSION}" >/dev/null 2>&1 || true
${adb_command} -s "${device_id}" shell toybox rm -rf "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}"
${adb_command} -s "${device_id}" shell mkdir -p \
  "${FIXTURE_ROOT}" "${EVIDENCE_ROOT}"

printf 'Preparing a bounded controlled foreground-scan fixture\n'
host_fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/argus-p02004-fixture.XXXXXX")"
fixture_archive="${host_fixture_root}.zip"
directory_index=1
while (( directory_index <= FIXTURE_DIRECTORY_COUNT )); do
  directory_path="${host_fixture_root}/d${directory_index}"
  mkdir -p "${directory_path}"
  file_index=1
  while (( file_index <= FIXTURE_FILES_PER_DIRECTORY )); do
    : > "${directory_path}/f${file_index}.bin"
    file_index=$((file_index + 1))
  done
  directory_index=$((directory_index + 1))
done
(
  cd "${host_fixture_root}"
  zip -q -r "${fixture_archive}" .
)
${adb_command} -s "${device_id}" push "${fixture_archive}" "${FIXTURE_ROOT}.zip" >/dev/null
${adb_command} -s "${device_id}" shell unzip -q -o \
  "${FIXTURE_ROOT}.zip" -d "${FIXTURE_ROOT}"
${adb_command} -s "${device_id}" shell toybox rm -f "${FIXTURE_ROOT}.zip"

wait_remote_file() {
  local path="$1"
  local pid="$2"
  local seconds="$3"
  local deadline=$((SECONDS + seconds))
  while (( SECONDS < deadline )); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      wait "${pid}" || true
      printf 'Integration test exited before marker %s; see %s\n' \
        "${path}" "${LOG_DIR}" >&2
      exit 1
    fi
    if ${adb_command} -s "${device_id}" shell test -s "${path}" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done
  printf 'Timed out waiting for marker %s\n' "${path}" >&2
  exit 1
}

dump_notification_ui() {
  # API 36 can take several seconds to serialize the notification shade while
  # the Flutter process is scanning. Keep the dump bounded, but leave enough
  # time for SystemUI to produce the hierarchy used by the real Cancel proof.
  local dump_output=''
  local dump_status=0
  "${adb_command}" -s "${device_id}" shell toybox rm -f "${UI_XML}" \
    >/dev/null 2>&1 || true
  dump_output="$(timeout --signal=TERM --kill-after=2s 15s \
    "${adb_command}" -s "${device_id}" shell uiautomator dump --compressed "${UI_XML}" \
    2>&1)" || dump_status=$?
  printf 'time=%s status=%s output=%s\n' "$(date '+%H:%M:%S')" \
    "${dump_status}" "${dump_output}" >>"${UI_DUMP_LOG}"
  if (( dump_status != 0 )); then
    return "${dump_status}"
  fi
  if ! timeout --signal=TERM --kill-after=2s 5s \
    "${adb_command}" -s "${device_id}" shell test -s "${UI_XML}"; then
    printf 'time=%s result=missing-or-empty-xml\n' "$(date '+%H:%M:%S')" \
      >>"${UI_DUMP_LOG}"
    return 1
  fi
  return 0
}

wait_for_notification_record() {
  local deadline=$((SECONDS + 15))
  while (( SECONDS < deadline )); do
    if "${adb_command}" -s "${device_id}" shell cmd notification list \
      | tr -d '\r' | grep -Fq "|${PACKAGE_ID}|"; then
      return 0
    fi
    sleep 0.25
  done
  printf 'Timed out waiting for the real Argus notification record\n' >&2
  "${adb_command}" -s "${device_id}" shell cmd notification list >&2 || true
  return 1
}

read_notification_ui_file() {
  if timeout --signal=TERM --kill-after=2s 5s \
    "${adb_command}" -s "${device_id}" pull "${UI_XML}" "${UI_RAW_PATH}" \
    >/dev/null 2>&1; then
    tr -d '\r' <"${UI_RAW_PATH}" | sed 's/></>\n</g'
    return 0
  fi
  local streamed=''
  if streamed="$(timeout --signal=TERM --kill-after=2s 5s \
    "${adb_command}" -s "${device_id}" shell cat "${UI_XML}" \
    2>/dev/null)"; then
    printf '%s\n' "${streamed}" >"${UI_RAW_PATH}"
    printf '%s\n' "${streamed}" | tr -d '\r' | sed 's/></>\n</g'
    return 0
  fi
  return 1
}

start_mode() {
  local mode="$1"
  local marker_cleanup_policy="${2:-clear-evidence}"
  local log_path="${LOG_DIR}/${mode}.log"
  ${adb_command} -s "${device_id}" shell am force-stop "${PACKAGE_ID}" \
    >/dev/null 2>&1 || true
  # A prior UI-diagnostic failure can leave an OS-owned Settings surface on
  # top of the task stack. Return to Home before Flutter launches the next
  # mode so the test driver does not wait behind that unrelated Activity.
  ${adb_command} -s "${device_id}" shell input keyevent KEYCODE_HOME \
    >/dev/null 2>&1 || true
  sleep 1
  # recoveryCheck reads the JobRunId written by recoveryStart, so its
  # relaunch must clear transient markers without deleting that durable proof.
  if [[ "${marker_cleanup_policy}" == preserve-evidence ]]; then
    ${adb_command} -s "${device_id}" shell toybox rm -f \
      "${NOTIFICATION_PROMPT_MARKER}" "${CONTINUE_PATH}" "${CANCEL_MARKER}" \
      "${UI_XML}"
  else
    ${adb_command} -s "${device_id}" shell toybox rm -f \
      "${EVIDENCE_PATH}" "${NOTIFICATION_PROMPT_MARKER}" "${CONTINUE_PATH}" "${CANCEL_MARKER}" \
      "${UI_XML}"
  fi
  (
    cd "${ROOT_DIR}/flutter"
    fvm flutter test integration_test/phase_002_android_foreground_execution_test.dart \
      --dart-define="ARGUS_PHASE_002_FOREGROUND_MODE=${mode}" \
      --dart-define="ARGUS_PHASE_002_FOREGROUND_EVIDENCE_PATH=${EVIDENCE_PATH}" \
      --dart-define="ARGUS_PHASE_002_FOREGROUND_CONTINUE_PATH=${CONTINUE_PATH}" \
      --no-uninstall -d "${device_id}"
  ) >"${log_path}" 2>&1 &
  mode_pid="$!"
}

wait_for_evidence_or_notification_prompt() {
  local pid="$1"
  local seconds="$2"
  local deadline=$((SECONDS + seconds))
  notification_prompt_seen=0
  while (( SECONDS < deadline )); do
    if ! kill -0 "${pid}" >/dev/null 2>&1; then
      wait "${pid}" || true
      printf 'Integration test exited before evidence or notification prompt\n' >&2
      exit 1
    fi
    if "${adb_command}" -s "${device_id}" shell test -s "${EVIDENCE_PATH}" \
      >/dev/null 2>&1; then
      return 0
    fi
    if "${adb_command}" -s "${device_id}" shell test -s "${NOTIFICATION_PROMPT_MARKER}" \
      >/dev/null 2>&1; then
      notification_prompt_seen=1
      return 0
    fi
    sleep 0.1
  done
  printf 'Timed out waiting for evidence or notification prompt\n' >&2
  exit 1
}

tap_notification_permission_action() {
  local action="$1"
  local deadline=$((SECONDS + 90))
  local action_bounds=''
  local ui_snapshot=''
  while (( SECONDS < deadline )); do
    dump_notification_ui >/dev/null 2>&1 || true
    if ! ui_snapshot="$(read_notification_ui_file)"; then
      sleep 1
      continue
    fi
    if [[ "${action}" == allow ]]; then
      action_bounds="$(printf '%s\n' "${ui_snapshot}" \
        | grep -F 'resource-id="com.android.permissioncontroller:id/permission_allow_button"' \
        | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' \
        | head -n 1 || true)"
    else
      action_bounds="$(printf '%s\n' "${ui_snapshot}" \
        | grep -E 'resource-id="com.android.permissioncontroller:id/permission_deny_button"|text="Don.t allow"|text="Deny"' \
        | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' \
        | head -n 1 || true)"
    fi
    printf 'permission-action=%s snapshot-bytes=%s bounds=%s\n' \
      "${action}" "${#ui_snapshot}" "${action_bounds}" >>"${UI_DUMP_LOG}"
    if [[ -n "${action_bounds}" ]]; then
      read -r left top right bottom <<<"${action_bounds}"
      tap_x=$(( (left + right) / 2 ))
      tap_y=$(( (top + bottom) / 2 ))
      if ! "${adb_command}" -s "${device_id}" shell input tap "${tap_x}" "${tap_y}"; then
        printf 'permission-tap-failed x=%s y=%s\n' "${tap_x}" "${tap_y}" \
          >>"${UI_DUMP_LOG}"
        sleep 1
        continue
      fi
      printf 'permission-tap-issued x=%s y=%s\n' "${tap_x}" "${tap_y}" \
        >>"${UI_DUMP_LOG}"
      return 0
    fi
    sleep 1
  done
  printf 'Could not locate the Android notification permission %s action\n' \
    "${action}" >&2
  printf '%s\n' "${ui_snapshot}" >&2
  exit 1
}

service_is_live() {
  ${adb_command} -s "${device_id}" shell dumpsys activity services \
    "${PACKAGE_ID}/.ArgusForegroundExecutionService" \
    | tr -d '\r' | grep -q 'ArgusForegroundExecutionService'
}

wait_for_service_absent() {
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if ! service_is_live; then
      return 0
    fi
    sleep 0.25
  done
  printf 'Foreground service did not disappear from Android service diagnostics\n' >&2
  ${adb_command} -s "${device_id}" shell dumpsys activity services \
    "${PACKAGE_ID}/.ArgusForegroundExecutionService" >&2 || true
  return 1
}

wait_for_foreground_notification() {
  local deadline=$((SECONDS + 30))
  local service_state=''
  while (( SECONDS < deadline )); do
    service_state="$(${adb_command} -s "${device_id}" shell dumpsys activity services \
      "${PACKAGE_ID}/.ArgusForegroundExecutionService" | tr -d '\r')"
    if grep -q 'isForeground=true' <<<"${service_state}" && \
      grep -q 'types=0x00000001' <<<"${service_state}" && \
      grep -q 'foregroundNoti=Notification' <<<"${service_state}"; then
      return 0
    fi
    sleep 0.25
  done
  printf 'Timed out waiting for the live foreground notification projection\n' >&2
  return 1
}

prepare_notification_cancel_automation() {
  local platform_dir="${android_sdk_root}/platforms/android-${api_level}"
  local android_jar="${platform_dir}/android.jar"
  local uiautomator_jar="${platform_dir}/uiautomator.jar"
  local d8_binary=''
  local classes_dir=''
  local dex_dir=''
  local compile_only_jar=''

  command -v javac >/dev/null 2>&1 || {
    printf 'Required developer tool is missing: javac\n' >&2
    return 1
  }
  command -v jar >/dev/null 2>&1 || {
    printf 'Required developer tool is missing: jar\n' >&2
    return 1
  }
  if [[ ! -f "${android_jar}" || ! -f "${uiautomator_jar}" ]]; then
    printf 'API %s SDK platform is missing android.jar or uiautomator.jar\n' \
      "${api_level}" >&2
    return 1
  fi
  d8_binary="$(rg --files "${android_sdk_root}/build-tools" 2>/dev/null \
    | grep '/d8$' | sort | tail -n 1 || true)"
  if [[ -z "${d8_binary}" || ! -x "${d8_binary}" ]]; then
    printf 'Android SDK build-tools d8 is missing\n' >&2
    return 1
  fi

  ui_automation_build_dir="$(mktemp -d \
    "${TMPDIR:-/tmp}/argus-p02004-ui-automation.XXXXXX")"
  classes_dir="${ui_automation_build_dir}/classes"
  dex_dir="${ui_automation_build_dir}/dex"
  mkdir -p "${classes_dir}" "${dex_dir}"
  javac -source 8 -target 8 -Xlint:-options -Xlint:-deprecation \
    -cp "${android_jar}:${uiautomator_jar}" \
    -d "${classes_dir}" \
    "${UI_AUTOMATION_SOURCE_DIR}"/*.java
  compile_only_jar="${ui_automation_build_dir}/compile-only.jar"
  jar cf "${compile_only_jar}" \
    -C "${classes_dir}" junit/framework/TestCase.class
  "${d8_binary}" \
    --min-api 23 \
    --lib "${android_jar}" \
    --lib "${uiautomator_jar}" \
    --lib "${compile_only_jar}" \
    --output "${dex_dir}" \
    "${classes_dir}/dev/argusromtoolkit/androidharness/ArgusNotificationCancelTest.class" \
    "${classes_dir}/android/test/RepetitiveTest.class"
  jar cf "${ui_automation_build_dir}/notification-cancel.jar" \
    -C "${dex_dir}" classes.dex
}

run_notification_cancel_automation() {
  local automation_output=''
  local automation_status=0
  local automation_jar="${ui_automation_build_dir}/notification-cancel.jar"
  if ! ${adb_command} -s "${device_id}" push "${automation_jar}" \
    /data/local/tmp/ArgusP02004NotificationCancel.jar \
    >"${LOG_DIR}/notification-cancel-uiautomator.log" 2>&1; then
    printf 'Could not push the Android UIAutomator notification helper\n' >&2
    return 1
  fi
  automation_output="$(${adb_command} -s "${device_id}" shell \
    uiautomator runtest \
    /data/local/tmp/ArgusP02004NotificationCancel.jar \
    -c dev.argusromtoolkit.androidharness.ArgusNotificationCancelTest#testCancel \
    -e outputFormat simple 2>&1)" || automation_status=$?
  printf '%s\n' "${automation_output}" \
    >>"${LOG_DIR}/notification-cancel-uiautomator.log"
  printf '%s\n' "${automation_output}"
  if (( automation_status != 0 )) || \
      ! grep -Eq 'notification-cancel-bounds=\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' \
        <<<"${automation_output}" || \
      ! grep -Fq 'notification-cancel-clicked' <<<"${automation_output}"; then
    printf 'Android UIAutomator did not complete the real Cancel action; capturing bounded XML diagnostics\n' \
      >&2
    dump_notification_ui >/dev/null 2>&1 || true
    return 1
  fi
}

printf 'Running Activity background/recreate and screen-off continuity proof\n'
start_mode continuity
continuity_pid="${mode_pid}"
wait_remote_file "${EVIDENCE_PATH}" "${continuity_pid}" 180
wait_for_foreground_notification
${adb_command} -s "${device_id}" shell settings put global always_finish_activities 1
${adb_command} -s "${device_id}" shell input keyevent KEYCODE_HOME
sleep 4
${adb_command} -s "${device_id}" shell input keyevent KEYCODE_SLEEP
sleep 5
${adb_command} -s "${device_id}" shell input keyevent KEYCODE_WAKEUP
${adb_command} -s "${device_id}" shell monkey -p "${PACKAGE_ID}" 1 >/dev/null
sleep 4
${adb_command} -s "${device_id}" shell touch "${CONTINUE_PATH}"
wait "${continuity_pid}"
restore_always_finish_activities

printf 'Running notification-denial continuity proof\n'
${adb_command} -s "${device_id}" shell pm revoke --user "${ANDROID_USER_ID}" \
  "${PACKAGE_ID}" "${NOTIFICATION_PERMISSION}" >/dev/null 2>&1 || true
start_mode notificationDenied
denied_pid="${mode_pid}"
wait_remote_file "${NOTIFICATION_PROMPT_MARKER}" "${denied_pid}" 90
notification_deny_bounds=''
for _ in $(seq 1 60); do
  dump_notification_ui >/dev/null 2>&1 || true
  notification_deny_bounds="$(read_notification_ui_file \
    | grep -E 'text="Don.t allow"|text="Deny"' \
    | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p' \
    | head -n 1 || true)"
  if [[ -n "${notification_deny_bounds}" ]]; then break; fi
  sleep 0.1
done
if [[ -z "${notification_deny_bounds}" ]]; then
  printf 'Could not locate the Android notification denial action\n' >&2
  ${adb_command} -s "${device_id}" shell cat "${UI_XML}" >&2 || true
  exit 1
fi
read -r left top right bottom <<<"${notification_deny_bounds}"
tap_x=$(( (left + right) / 2 ))
tap_y=$(( (top + bottom) / 2 ))
${adb_command} -s "${device_id}" shell input tap "${tap_x}" "${tap_y}"
wait_for_foreground_notification
${adb_command} -s "${device_id}" shell input keyevent KEYCODE_HOME
wait "${denied_pid}"
${adb_command} -s "${device_id}" shell pm grant --user "${ANDROID_USER_ID}" \
  "${PACKAGE_ID}" "${NOTIFICATION_PERMISSION}" >/dev/null 2>&1 || true

printf 'Running real notification Cancel action proof\n'
${adb_command} -s "${device_id}" shell cmd statusbar clear-all \
  >/dev/null 2>&1 || true
# The first API 36 UI hierarchy dump can spend its full bounded timeout
# waiting for SystemUI idle. Warm that diagnostic path before the scan starts
# so the real Cancel interaction is not delayed until a finite fixture is
# already terminalizing. The later dumps retain the same timeout and evidence
# files used to stop and diagnose a genuine UI failure.
${adb_command} -s "${device_id}" shell cmd statusbar collapse \
  >/dev/null 2>&1 || true
dump_notification_ui >/dev/null 2>&1 || true
prepare_notification_cancel_automation
start_mode notificationCancel
cancel_pid="${mode_pid}"
wait_for_evidence_or_notification_prompt "${cancel_pid}" 180
if (( notification_prompt_seen > 0 )); then
  tap_notification_permission_action allow
fi
wait_remote_file "${EVIDENCE_PATH}" "${cancel_pid}" 180
wait_for_foreground_notification
if ! run_notification_cancel_automation; then
  printf 'Could not invoke the real foreground notification Cancel action\n' >&2
  exit 1
fi
${adb_command} -s "${device_id}" shell touch "${CANCEL_MARKER}"
wait "${cancel_pid}"
if [[ "${stop_after_stage}" == notificationCancel ]]; then
  printf 'Focused stop requested after notification Cancel action proof\n'
  exit 0
fi
printf 'Running real Android data-sync timeout proof\n'
enable_timeout_compat_for_api_36
# The fixed 600x20 fixture completes in roughly three seconds on the
# repository ARM64/API 36 emulator. Keep the platform control below that
# measured terminalization time so this stage observes Service.onTimeout
# without enlarging the fixture or adding a harness wait.
${adb_command} -s "${device_id}" shell device_config put activity_manager \
  data_sync_fgs_timeout_duration 1000
start_mode timeout
timeout_pid="${mode_pid}"
wait_remote_file "${EVIDENCE_PATH}" "${timeout_pid}" 180
wait_for_foreground_notification
${adb_command} -s "${device_id}" shell input keyevent KEYCODE_HOME
wait "${timeout_pid}"
if [[ "${stop_after_stage}" == timeout ]]; then
  printf 'Focused stop requested after Android data-sync timeout proof\n'
  exit 0
fi

printf 'Running process-death/no-auto-resume recovery proof\n'
start_mode recoveryStart
recovery_start_pid="${mode_pid}"
wait_remote_file "${EVIDENCE_PATH}" "${recovery_start_pid}" 180
wait_for_foreground_notification
# recoveryStart deliberately remains alive on CONTINUE_PATH. This diagnostic
# is the evidence boundary: the service must be present and foreground before
# the package is force-stopped, not merely absent after the kill.
service_is_live
${adb_command} -s "${device_id}" shell dumpsys activity services \
  "${PACKAGE_ID}/.ArgusForegroundExecutionService" \
  >"${LOG_DIR}/recovery-pre-kill-service.txt"
${adb_command} -s "${device_id}" shell touch "${CONTINUE_PATH}"
${adb_command} -s "${device_id}" shell am force-stop "${PACKAGE_ID}"
wait "${recovery_start_pid}" >/dev/null 2>&1 || true
mode_pid=''
wait_for_service_absent
start_mode recoveryCheck preserve-evidence
recovery_check_pid="${mode_pid}"
wait "${recovery_check_pid}"

printf 'P02-004 Android foreground execution milestone passed on %s (API %s, %s)\n' \
  "${device_id}" "${api_level}" "${abi}"
