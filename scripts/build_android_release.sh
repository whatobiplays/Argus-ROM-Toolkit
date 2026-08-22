#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_FIELDS=(
  ARGUS_RELEASE_KEYSTORE
  ARGUS_RELEASE_STORE_PASSWORD
  ARGUS_RELEASE_KEY_ALIAS
  ARGUS_RELEASE_KEY_PASSWORD
)

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

apksigner_binary="$(command -v apksigner || true)"
if [[ -z "${apksigner_binary}" ]]; then
  sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "${sdk_root}" ]]; then
    apksigner_binary="$(find "${sdk_root}/build-tools" -mindepth 2 -maxdepth 2 \
      -type f -name apksigner -print 2>/dev/null | sort | tail -n 1 || true)"
  fi
fi
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
