#!/usr/bin/env bash

# Shared Android SDK build-tools discovery for repository shell tooling.
# PATH wins, then the first SDK root with build-tools among ANDROID_SDK_ROOT,
# ANDROID_HOME, and the default macOS SDK location.

argus_resolve_sdk_root() {
  local candidate=""
  for candidate in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" \
    "${HOME:-}/Library/Android/sdk"; do
    if [[ -n "${candidate}" && -d "${candidate}/build-tools" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

argus_resolve_build_tool() {
  local tool_name="$1"
  local sdk_root=""
  local tool=""
  if command -v "${tool_name}" >/dev/null 2>&1; then
    command -v "${tool_name}"
    return 0
  fi
  if sdk_root="$(argus_resolve_sdk_root)"; then
    tool="$(find "${sdk_root}/build-tools" -mindepth 2 -maxdepth 2 \
      -type f -name "${tool_name}" -print 2>/dev/null | sort | tail -n 1 || true)"
    if [[ -n "${tool}" ]]; then
      printf '%s\n' "${tool}"
      return 0
    fi
  fi
  return 1
}

# Resolve the NDK version pinned by the repository's Flutter SDK. Repositories
# with several installed NDKs cannot safely choose one by directory order, so
# callers use this before falling back to an unambiguous single installation.
argus_resolve_pinned_ndk_home() {
  local repository_root="$1"
  local local_properties="${repository_root}/flutter/android/local.properties"
  local flutter_sdk=""
  local sdk_root=""
  local ndk_version=""
  local flutter_extension=""
  local candidate=""

  [[ -f "${local_properties}" ]] || return 1
  flutter_sdk="$(sed -n 's/^flutter.sdk=//p' "${local_properties}" | head -n 1)"
  [[ -n "${flutter_sdk}" ]] || return 1
  flutter_extension="${flutter_sdk}/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
  [[ -f "${flutter_extension}" ]] || return 1
  ndk_version="$(sed -n \
    's/.*val ndkVersion: String = "\([^"]*\)".*/\1/p' \
    "${flutter_extension}" | head -n 1)"
  [[ -n "${ndk_version}" ]] || return 1
  sdk_root="$(argus_resolve_sdk_root)" || return 1
  candidate="${sdk_root}/ndk/${ndk_version}"
  [[ -d "${candidate}" ]] || return 1
  printf '%s\n' "${candidate}"
}
