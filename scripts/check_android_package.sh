#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_PACKAGE_ID="com.argusromtoolkit.argus"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/android_sdk_common.sh"

fail() {
  printf 'Android package contract failed: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s <apk-path> [expected-package-id]\n' "$0" >&2
  printf '       %s --source-contract-only\n' "$0" >&2
  printf '       %s --require-metadata <apk-path> [expected-package-id]\n' "$0" >&2
}

scan_live_sources() {
  local pattern
  pattern='android-x64|android-x86|x86_64-linux-android|i686-linux-android|armv7-linux-androideabi|ARGUS_ANDROID_DEVICE_REQUIRE_ARM64|lib/x86_64/|lib/armeabi-v7a/|lib/x86/|-t x86_64|-t x86|-t armeabi-v7a'
  local paths=(
    "$ROOT_DIR/justfile"
    "$ROOT_DIR/scripts/build_android_bridge.sh"
    "$ROOT_DIR/scripts/build_android_release.sh"
    "$ROOT_DIR/scripts/android_sdk_common.sh"
    "$ROOT_DIR/scripts/bootstrap.sh"
    "$ROOT_DIR/scripts/run_phase_002_android_scenario_common.sh"
    "$ROOT_DIR/scripts"/run_phase_002_android_*tests.sh
    "$ROOT_DIR/scripts/android_notification_cancel"
    "$ROOT_DIR/flutter/android"
    "$ROOT_DIR/.github/workflows/ci.yml"
  )
  local matches
  matches="$(rg -n -i -e "${pattern}" "${paths[@]}" 2>/dev/null || true)"
  if [[ -n "${matches}" ]]; then
    printf 'Unsupported Android ABI support found in live paths:\n%s\n' \
      "${matches}" >&2
    return 1
  fi
}

resolve_badging_tool() {
  local tool=""
  if tool="$(argus_resolve_build_tool aapt2)"; then
    printf '%s\n' "${tool}"
    return 0
  fi
  if tool="$(argus_resolve_build_tool aapt)"; then
    printf '%s\n' "${tool}"
    return 0
  fi
  return 1
}

check_apk() {
  local apk_path="$1"
  local expected_package_id="${2:-${DEFAULT_PACKAGE_ID}}"
  local require_metadata="$3"
  local entries
  local unsupported
  local badging_tool=""
  local badging=""
  local actual_package=""

  [[ -f "${apk_path}" && -r "${apk_path}" ]] ||
    fail "APK is missing or unreadable: ${apk_path}"
  command -v unzip >/dev/null 2>&1 ||
    fail "Required developer tool is missing: unzip"

  entries="$(unzip -Z1 "${apk_path}")"
  printf '%s\n' "${entries}" | grep -qx 'lib/arm64-v8a/libargus_bridge.so' ||
    fail "APK is missing lib/arm64-v8a/libargus_bridge.so"
  printf '%s\n' "${entries}" | grep -qx 'lib/arm64-v8a/libandroid_native_keyring_store.so' ||
    fail "APK is missing lib/arm64-v8a/libandroid_native_keyring_store.so"
  unsupported="$(printf '%s\n' "${entries}" | awk -F/ '
    NF >= 3 && $1 == "lib" && $2 != "arm64-v8a" {
      print $1 "/" $2 "/"
      exit
    }
  ')"
  if [[ -n "${unsupported}" ]]; then
    fail "unsupported Android ABI packaging present: ${unsupported}"
  fi

  if badging_tool="$(resolve_badging_tool)"; then
    badging="$("${badging_tool}" dump badging "${apk_path}" 2>/dev/null || true)"
  fi
  if [[ -z "${badging_tool}" ]]; then
    if [[ "${require_metadata}" == 1 ]]; then
      fail "no Android metadata tooling (aapt2/aapt) is available"
    fi
    printf 'Android package contract passed (metadata skipped: no aapt2/aapt)\n'
    return 0
  fi
  actual_package="$(printf '%s\n' "${badging}" |
    awk -F"'" '/^package: name=/{print $2; exit}')"
  if [[ "${actual_package}" != "${expected_package_id}" ]]; then
    fail "APK package identity is not ${expected_package_id}"
  fi
  printf '%s\n' "${badging}" |
    grep -Eq "sdkVersion:'30'|minSdkVersion:'30'" ||
    fail "APK minSdk is not 30"
  printf 'Android package contract passed: %s (%s)\n' \
    "${expected_package_id}" "$(basename "${badging_tool}")"
}

if [[ "${1:-}" == "--source-contract-only" ]]; then
  scan_live_sources
  printf 'Android source contract passed: live paths are ARM64-only\n'
  exit 0
fi

require_metadata=0
if [[ "${1:-}" == "--require-metadata" ]]; then
  require_metadata=1
  shift
fi
if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi
check_apk "$1" "${2:-${DEFAULT_PACKAGE_ID}}" "${require_metadata}"
