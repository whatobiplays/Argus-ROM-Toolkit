#!/usr/bin/env bash
set -euo pipefail

# Runs the repository-owned desktop Library lifecycle qualification against a
# test-owned native data directory and records the outcome for the verification
# record.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_EVIDENCE_DIR="${ROOT_DIR}/build/library-desktop-qualification"
HOST_EVIDENCE_PATH="${HOST_EVIDENCE_DIR}/qualification.txt"
BUILD_LOG="${HOST_EVIDENCE_DIR}/bridge-build.log"
INTEGRATION_LOG="${HOST_EVIDENCE_DIR}/integration.log"

mkdir -p "${HOST_EVIDENCE_DIR}"
: > "${HOST_EVIDENCE_PATH}"

record() {
  printf '%s\n' "$1" >> "${HOST_EVIDENCE_PATH}"
}

data_dir=''
# ShellCheck 0.9 cannot follow this function's indirect EXIT-trap invocation.
# shellcheck disable=SC2329,SC2317
cleanup() {
  local status=$?
  if [[ -n "${data_dir}" && -d "${data_dir}" ]]; then
    rm -rf "${data_dir}"
  fi
  exit "${status}"
}
trap cleanup EXIT

if [[ "$(uname -s)" != Darwin ]]; then
  record 'result=NOT RUN'
  record 'reason=Desktop native qualification requires macOS'
  exit 2
fi
if ! command -v fvm >/dev/null 2>&1; then
  record 'result=NOT RUN'
  record 'reason=Required developer tool is missing: fvm'
  exit 2
fi
if ! command -v rustup >/dev/null 2>&1; then
  record 'result=NOT RUN'
  record 'reason=Required developer tool is missing: rustup'
  exit 2
fi

app_container_dir="${HOME}/Library/Containers/dev.argusromtoolkit.argus/Data"
if ! mkdir -p "${app_container_dir}"; then
  record 'result=NOT RUN'
  record 'reason=Could not create the test-owned desktop app container'
  exit 2
fi
if ! data_dir="$(mktemp -d "${app_container_dir}/argus-library-qualification.XXXXXX")"; then
  record 'result=NOT RUN'
  record 'reason=Could not create the test-owned desktop data directory'
  exit 2
fi
record 'data_directory=test-owned-macos-application-container'

if ! bash "${ROOT_DIR}/scripts/run_rust.sh" cargo build \
  --manifest-path "${ROOT_DIR}/rust/Cargo.toml" \
  --package argus-bridge --locked > "${BUILD_LOG}" 2>&1; then
  record 'result=NOT RUN'
  record 'reason=Locked argus-bridge build was unavailable'
  record 'detail=See bridge-build.log for the bounded tool output'
  exit 2
fi

integration_status=0
(
  cd "${ROOT_DIR}/flutter"
  ARGUS_LIBRARY_DESKTOP_DATA_DIR="${data_dir}" \
    fvm flutter test integration_test/library_lifecycle_qualification_test.dart \
      -d macos
) > "${INTEGRATION_LOG}" 2>&1 || integration_status=$?

if (( integration_status == 0 )); then
  record 'result=PASS'
  exit 0
fi
record "result=FAIL|exit_code=${integration_status}"
record 'reason=See integration.log for the bounded Flutter test output'
exit "${integration_status}"
