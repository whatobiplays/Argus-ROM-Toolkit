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
