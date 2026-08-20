#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"
argus_android_require_device
argus_android_build_and_install "${ROOT_DIR}"
argus_android_run_integration \
  "${ROOT_DIR}" \
  phase_002_android_applicable_features_test.dart

printf 'P02-005 applicable-feature composition scenario passed on %s\n' \
  "${ARGUS_ANDROID_SCENARIO_DEVICE}"
