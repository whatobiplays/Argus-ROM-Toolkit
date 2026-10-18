#!/usr/bin/env bash
set -euo pipefail

# Qualify the unmodified signed Release app on one explicit physical API-30
# ARM64 USB device. This entrypoint does not alter Phase 002 API-36 runners.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT_DIR/scripts/phase_003_android_physical_qualification/runner.py" "$@"
