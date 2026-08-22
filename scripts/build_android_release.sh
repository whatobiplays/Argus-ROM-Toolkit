#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_FIELDS=(
  ARGUS_RELEASE_KEYSTORE
  ARGUS_RELEASE_STORE_PASSWORD
  ARGUS_RELEASE_KEY_ALIAS
  ARGUS_RELEASE_KEY_PASSWORD
)

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/android_sdk_common.sh"

missing_fields=0
for name in "${SIGNING_FIELDS[@]}"; do
if [[ -z "${!name:-}" ]]; then
    printf 'Release signing configuration is missing: %s\n' "${name}" >&2
    missing_fields=1
  fi
done
if (( missing_fields != 0 )); then
  printf 'Set the required release signing environment variables before building.\n' >&2
  exit 1
fi
case "${ARGUS_RELEASE_KEYSTORE}" in
  /*|[A-Za-z]:[\\/]*) ;;
  *)
    printf 'Release signing configuration is invalid: ARGUS_RELEASE_KEYSTORE must be an absolute path\n' >&2
    exit 1
    ;;
esac
if [[ ! -f "${ARGUS_RELEASE_KEYSTORE}" || ! -r "${ARGUS_RELEASE_KEYSTORE}" ]]; then
  printf 'Release signing configuration is invalid: %s is missing or unreadable\n' \
    'ARGUS_RELEASE_KEYSTORE' >&2
  exit 1
fi

(
  cd "${ROOT_DIR}/flutter"
  fvm flutter build apk --release --target-platform android-arm64
)

apk_path="${ROOT_DIR}/flutter/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "${apk_path}" ]]; then
  printf 'Expected release APK was not produced: %s\n' "${apk_path}" >&2
  exit 1
fi

bash "${ROOT_DIR}/scripts/check_android_package.sh" \
  --require-metadata "${apk_path}"

version_line="$(sed -n 's/^version: //p' \
  "${ROOT_DIR}/flutter/pubspec.yaml" | head -n 1)"
expected_version_name="${version_line%+*}"
expected_version_code="${version_line##*+}"
if [[ -z "${expected_version_name}" || -z "${expected_version_code}" || \
  ! "${expected_version_code}" =~ ^[0-9]+$ ]]; then
  printf 'Release verification could not read flutter/pubspec.yaml version\n' >&2
  exit 1
fi

badging_tool_binary="$(argus_resolve_build_tool aapt2 || true)"
if [[ -z "${badging_tool_binary}" ]]; then
  badging_tool_binary="$(argus_resolve_build_tool aapt || true)"
fi
if [[ -z "${badging_tool_binary}" || ! -x "${badging_tool_binary}" ]]; then
  printf 'Release verification requires Android aapt2/aapt\n' >&2
  exit 1
fi
badging="$("${badging_tool_binary}" dump badging "${apk_path}" 2>/dev/null || true)"
actual_version_code="$(printf '%s\n' "${badging}" |
  sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -n 1)"
actual_version_name="$(printf '%s\n' "${badging}" |
  sed -n "s/.*versionName='\([^']*\)'.*/\1/p" | head -n 1)"
if [[ "${actual_version_code}" != "${expected_version_code}" || \
  "${actual_version_name}" != "${expected_version_name}" ]]; then
  printf 'Release APK version metadata mismatch: expected versionCode=%s versionName=%s\n' \
    "${expected_version_code}" "${expected_version_name}" >&2
  exit 1
fi

apksigner_binary="$(argus_resolve_build_tool apksigner || true)"
if [[ -z "${apksigner_binary}" || ! -x "${apksigner_binary}" ]]; then
  printf 'Release verification requires Android apksigner\n' >&2
  exit 1
fi
if ! "${apksigner_binary}" verify --min-sdk-version 30 "${apk_path}" \
  >/dev/null 2>&1; then
  printf 'Release APK signature verification failed\n' >&2
  exit 1
fi

printf 'Signed ARM64 release APK verified: %s\n' "${apk_path}"
