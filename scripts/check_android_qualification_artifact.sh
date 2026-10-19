#!/usr/bin/env bash
set -euo pipefail

# Thin host-only entrypoint for independent qualification APK inspection. The
# Python verifier owns the checks; this wrapper resolves the Android SDK tools
# through the same search order used by the other repository scripts.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/android_sdk_common.sh"

aapt2_binary="$(argus_resolve_build_tool aapt2 || true)"
apksigner_binary="$(argus_resolve_build_tool apksigner || true)"
zipalign_binary="$(argus_resolve_build_tool zipalign || true)"
if [[ -n "$aapt2_binary" ]]; then
  export AAPT2="$aapt2_binary"
fi
if [[ -n "$apksigner_binary" ]]; then
  export APKSIGNER="$apksigner_binary"
fi
if [[ -n "$zipalign_binary" ]]; then
  export ZIPALIGN="$zipalign_binary"
fi

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ROOT_DIR" exec python3 \
  -m scripts.android_qualification.packaging verify --root "$ROOT_DIR" "$@"
