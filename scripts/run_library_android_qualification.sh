#!/usr/bin/env bash
set -euo pipefail

# Runs the repository-owned Android Library lifecycle qualification. The test
# writes its evidence and synchronization markers to an explicit device path;
# this runner performs the real background/foreground transition and collects
# the bounded result on the host.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ID="com.argusromtoolkit.argus"
DEVICE_EVIDENCE_ROOT="/sdcard/ArgusLibraryAndroidEvidence"
DEVICE_EVIDENCE_PATH="${DEVICE_EVIDENCE_ROOT}/lifecycle.txt"
DEVICE_CONTINUE_PATH="${DEVICE_EVIDENCE_ROOT}/continue"
HOST_EVIDENCE_DIR="${ROOT_DIR}/build/library-android-qualification"
HOST_EVIDENCE_PATH="${HOST_EVIDENCE_DIR}/qualification.txt"
INTEGRATION_LOG="${HOST_EVIDENCE_DIR}/integration.log"
BUILD_LOG="${HOST_EVIDENCE_DIR}/build.log"

mkdir -p "${HOST_EVIDENCE_DIR}"
: > "${HOST_EVIDENCE_PATH}"

record() {
  printf '%s\n' "$1" >> "${HOST_EVIDENCE_PATH}"
}

device_id=''
test_pid=''

# ShellCheck 0.9 cannot follow this function's indirect EXIT-trap invocation.
# shellcheck disable=SC2329,SC2317
cleanup() {
  local status=$?
  if [[ -n "${device_id}" && -n "${ARGUS_ANDROID_SCENARIO_ADB:-}" ]]; then
    "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell rm -rf \
      "${DEVICE_EVIDENCE_ROOT}" >/dev/null 2>&1 || true
  fi
  exit "${status}"
}
trap cleanup EXIT

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"

if ! argus_android_require_device > "${HOST_EVIDENCE_DIR}/device-check.log" 2>&1; then
  cat "${HOST_EVIDENCE_DIR}/device-check.log" >&2
  record 'result=NOT RUN'
  record 'reason=No supported online Android device or required toolchain'
  exit 2
fi

device_id="${ARGUS_ANDROID_SCENARIO_DEVICE}"
# shellcheck disable=SC2153
record "device_id=${device_id}|api=${ARGUS_ANDROID_SCENARIO_API}|abi=${ARGUS_ANDROID_SCENARIO_ABI}"
record 'target_platform=android-arm64'

# The native bridge build deliberately rejects an ambiguous SDK containing
# multiple NDK versions. When the pinned Flutter SDK and its matching NDK are
# installed, provide that explicit selection to the shared build helper.
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  android_sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [[ -z "${android_sdk_root}" && -f "${ROOT_DIR}/flutter/android/local.properties" ]]; then
    android_sdk_root="$(sed -n 's/^sdk\.dir=//p' \
      "${ROOT_DIR}/flutter/android/local.properties" | head -n 1)"
  fi
  flutter_sdk_dir=''
  if [[ -f "${ROOT_DIR}/flutter/android/local.properties" ]]; then
    flutter_sdk_dir="$(sed -n 's/^flutter\.sdk=//p' \
      "${ROOT_DIR}/flutter/android/local.properties" | head -n 1)"
  fi
  flutter_ndk_version=''
  if [[ -n "${flutter_sdk_dir}" ]]; then
    flutter_ndk_version="$(sed -n \
      's/.*ndkVersion: String = "\([^"]*\)".*/\1/p' \
      "${flutter_sdk_dir}/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" \
      | head -n 1)"
  fi
  matching_ndk="${android_sdk_root}/ndk/${flutter_ndk_version}"
  if [[ -n "${flutter_ndk_version}" && -d "${matching_ndk}" ]]; then
    export ANDROID_NDK_HOME="${matching_ndk}"
  fi
fi
if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
  record "ndk_home=${ANDROID_NDK_HOME}"
else
  record 'ndk_home=unresolved'
fi

# The shared helper validates the expected APK path after building. Remove a
# stale artifact first so a failed native build cannot be mistaken for a fresh
# package.
apk_path="${ROOT_DIR}/flutter/build/app/outputs/flutter-apk/app-debug.apk"
rm -f "${apk_path}"

build_output=''
if ! build_output="$(argus_android_build_and_install "${ROOT_DIR}" 2>&1)"; then
  printf '%s\n' "${build_output}" > "${BUILD_LOG}"
  printf '%s\n' "${build_output}" >&2
  record 'result=NOT RUN'
  record 'reason=Android debug package build or installation was unavailable'
  record 'detail=See build.log for the bounded tool output'
  exit 2
fi
printf '%s\n' "${build_output}" > "${BUILD_LOG}"

if ! "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell rm -rf \
  "${DEVICE_EVIDENCE_ROOT}"; then
  record 'result=NOT RUN'
  record 'reason=Could not reset the explicit device evidence directory'
  exit 2
fi
if ! "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell mkdir -p \
  "${DEVICE_CONTINUE_PATH}"; then
  record 'result=NOT RUN'
  record 'reason=Could not create the explicit device evidence directory'
  exit 2
fi

integration_status=0
(
  argus_android_run_integration \
    "${ROOT_DIR}" \
    library_android_lifecycle_qualification_test.dart \
    "--dart-define=ARGUS_LIBRARY_ANDROID_EVIDENCE_PATH=${DEVICE_EVIDENCE_PATH}" \
    "--dart-define=ARGUS_LIBRARY_ANDROID_CONTINUE_PATH=${DEVICE_CONTINUE_PATH}"
) > "${INTEGRATION_LOG}" 2>&1 &
test_pid=$!

wait_for_device_file() {
  local path="$1"
  local deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell test -f \
      "${path}" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "${test_pid}" >/dev/null 2>&1; then
      return 1
    fi
    sleep 1
  done
  return 1
}

if ! wait_for_device_file "${DEVICE_CONTINUE_PATH}.ready"; then
  record 'result=FAIL'
  record 'reason=Android integration test did not reach its transition barrier'
  if kill -0 "${test_pid}" >/dev/null 2>&1; then
    kill "${test_pid}" >/dev/null 2>&1 || true
  fi
  wait "${test_pid}" >/dev/null 2>&1 || true
  test_pid=''
  exit 1
fi

if ! "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell input \
  keyevent KEYCODE_HOME >/dev/null 2>&1; then
  record 'result=FAIL'
  record 'reason=Could not send the Android background transition'
  kill "${test_pid}" >/dev/null 2>&1 || true
  wait "${test_pid}" >/dev/null 2>&1 || true
  test_pid=''
  exit 1
fi
sleep 2
if ! "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell am start -W \
  --activity-reorder-to-front --activity-single-top \
  -n "${PACKAGE_ID}/.MainActivity" \
  > "${HOST_EVIDENCE_DIR}/foreground.log" 2>&1; then
  record 'result=FAIL'
  record 'reason=Could not restore the Android Activity after backgrounding'
  kill "${test_pid}" >/dev/null 2>&1 || true
  wait "${test_pid}" >/dev/null 2>&1 || true
  test_pid=''
  exit 1
fi
sleep 2
if ! "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell touch \
  "${DEVICE_CONTINUE_PATH}.background.done"; then
  record 'result=FAIL'
  record 'reason=Could not publish the Android foreground transition marker'
  kill "${test_pid}" >/dev/null 2>&1 || true
  wait "${test_pid}" >/dev/null 2>&1 || true
  test_pid=''
  exit 1
fi

if wait "${test_pid}"; then
  integration_status=0
else
  integration_status=$?
fi
test_pid=''

if "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" shell test -f \
  "${DEVICE_EVIDENCE_PATH}" >/dev/null 2>&1; then
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${device_id}" pull \
    "${DEVICE_EVIDENCE_PATH}" "${HOST_EVIDENCE_PATH}.device" \
    >/dev/null 2>&1 || true
  if [[ -f "${HOST_EVIDENCE_PATH}.device" ]]; then
    cat "${HOST_EVIDENCE_PATH}.device" >> "${HOST_EVIDENCE_PATH}"
    rm -f "${HOST_EVIDENCE_PATH}.device"
  fi
fi

if (( integration_status == 0 )); then
  record 'result=PASS'
  exit 0
fi
record "result=FAIL|exit_code=${integration_status}"
record 'reason=See integration.log for the bounded Flutter test output'
exit "${integration_status}"
