#!/usr/bin/env bash
set -euo pipefail

# Runs the opt-in provider qualification against production sessions. Probe
# identifiers are intentionally read by the Rust test from the process
# environment; no provider secret is accepted, copied, or displayed here.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="${ROOT_DIR}/build/live-provider-qualification"
EVIDENCE_PATH="${EVIDENCE_DIR}/qualification.txt"
TEST_LOG="${EVIDENCE_DIR}/test.log"

mkdir -p "${EVIDENCE_DIR}"
: > "${EVIDENCE_PATH}"

record() {
  printf '%s\n' "$1" >> "${EVIDENCE_PATH}"
}

for command_name in bash rg rustup; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    for provider in playmatch gametdb steamgriddb; do
      record "provider=${provider}|result=NOT RUN|reason=Required developer tool is missing: ${command_name}"
    done
    exit 2
  fi
done

if ! bash "${ROOT_DIR}/scripts/run_rust.sh" cargo --version >/dev/null 2>&1; then
  for provider in playmatch gametdb steamgriddb; do
    record "provider=${provider}|result=NOT RUN|reason=pinned Rust toolchain or Cargo is unavailable"
  done
  exit 2
fi

test_status=0
if bash "${ROOT_DIR}/scripts/run_rust.sh" cargo test \
  --manifest-path "${ROOT_DIR}/rust/Cargo.toml" \
  -p argus-infrastructure \
  --test provider_live_qualification \
  --all-features \
  --locked \
  -- \
  --ignored \
  --nocapture > "${TEST_LOG}" 2>&1; then
  :
else
  test_status=$?
fi

result_status=0
not_run_count=0
for provider in playmatch gametdb steamgriddb; do
  case "${provider}" in
    playmatch|steamgriddb) platform="nintendo.gb" ;;
    gametdb) platform="nintendo.nds" ;;
  esac
  result_lines="$(rg "^LIVE_PROVIDER ${provider}: (PASS|NOT RUN) platform=[^[:space:]]+" "${TEST_LOG}" || true)"
  result_count=0
  if [[ -n "${result_lines}" ]]; then
    result_count="$(printf '%s\n' "${result_lines}" | wc -l | tr -d ' ')"
  fi
  if [[ "${result_count}" != 1 ]]; then
    record "provider=${provider}|platform=${platform}|result=FAIL|reason=The live qualification did not emit exactly one explicit result"
    result_status=1
    continue
  fi

  if [[ "${result_lines}" =~ ^LIVE_PROVIDER\ ${provider}:\ (PASS|NOT\ RUN)\ platform=([^[:space:]]+)(.*)$ ]]; then
    provider_result="${BASH_REMATCH[1]}"
    platform="${BASH_REMATCH[2]}"
  else
    record "provider=${provider}|platform=${platform}|result=FAIL|reason=The live qualification result format was invalid"
    result_status=1
    continue
  fi

  if [[ "${provider_result}" == "PASS" ]]; then
    record "provider=${provider}|platform=${platform}|result=PASS"
  else
    reason="${result_lines#* (}"
    reason="${reason%)}"
    record "provider=${provider}|platform=${platform}|result=NOT RUN|reason=${reason}"
    not_run_count=$((not_run_count + 1))
  fi
done

if (( test_status != 0 )); then
  record "runner=result=FAIL|exit_code=${test_status}|reason=See test.log for bounded test output"
  result_status=1
fi

if (( result_status != 0 )); then
  exit 1
fi
if (( not_run_count != 0 )); then
  exit 2
fi
exit 0
