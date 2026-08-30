#!/usr/bin/env bash
set -euo pipefail

# Runs the offline aggregate qualification. The command list is fixed so this
# target cannot accidentally turn a deterministic check into a live-provider
# or hardware-dependent run.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="${ROOT_DIR}/build/deterministic-qualification"
EVIDENCE_PATH="${EVIDENCE_DIR}/qualification.txt"
TEST_LOG="${EVIDENCE_DIR}/test.log"

mkdir -p "${EVIDENCE_DIR}"
: > "${EVIDENCE_PATH}"

record() {
  printf '%s\n' "$1" >> "${EVIDENCE_PATH}"
}

for command_name in rustup fvm; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    record "result=NOT RUN|reason=Required developer tool is missing: ${command_name}"
    exit 2
  fi
done

test_status=0
(
  bash "${ROOT_DIR}/scripts/run_rust.sh" cargo test \
    --manifest-path "${ROOT_DIR}/rust/Cargo.toml" \
    --workspace --all-features --locked
  cd "${ROOT_DIR}/flutter"
  fvm flutter test --no-pub
) > "${TEST_LOG}" 2>&1 || test_status=$?

if (( test_status == 0 )); then
  record 'result=PASS'
  exit 0
fi

record "result=FAIL|exit_code=${test_status}"
record 'reason=See test.log for the bounded deterministic test output'
exit "${test_status}"
