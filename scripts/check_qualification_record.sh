#!/usr/bin/env bash
set -euo pipefail

# Validates the checked-in qualification record. Every gate is represented by
# one machine-checkable row so a partial run cannot be mistaken for a complete
# release qualification.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECORD_PATH="${ROOT_DIR}/docs/implementation/library-capability-qualification.md"

if [[ ! -f "${RECORD_PATH}" ]]; then
  printf 'Qualification record is missing: %s\n' "${RECORD_PATH}" >&2
  exit 1
fi

failure_count=0

fail() {
  printf 'Qualification record error: %s\n' "$1" >&2
  failure_count=$((failure_count + 1))
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

row_status() {
  local row="$1"
  printf '%s\n' "${row}" | awk -F '|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}'
}

row_evidence() {
  local row="$1"
  printf '%s\n' "${row}" | awk -F '|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4}'
}

check_gate() {
  local gate_id="$1"
  local row_count
  local row
  local gate_status
  local evidence
  row_count="$(rg -F -c "| ${gate_id} |" "${RECORD_PATH}" || true)"
  if [[ "${row_count}" != 1 ]]; then
    fail "${gate_id} must have exactly one record row; found ${row_count}"
    return
  fi
  row="$(rg -F "| ${gate_id} |" "${RECORD_PATH}")"
  gate_status="$(trim "$(row_status "${row}")")"
  evidence="$(row_evidence "${row}")"
  case "${gate_status}" in
    PASS)
      if [[ "${evidence}" != evidence:* ]]; then
        fail "${gate_id} PASS row must begin its evidence with evidence:"
      fi
      ;;
    FAIL)
      if [[ "${evidence}" != failure:* && "${evidence}" != reason:* ]]; then
        fail "${gate_id} FAIL row must include failure: or reason:"
      fi
      ;;
    'NOT RUN')
      if [[ "${evidence}" != prerequisite:* ]]; then
        fail "${gate_id} NOT RUN row must include prerequisite:"
      fi
      ;;
    *)
      fail "${gate_id} has invalid status: ${gate_status}"
      ;;
  esac
}

check_criterion() {
  local criterion_id="$1"
  local row_count
  local row
  local criterion_status
  local evidence
  row_count="$(rg -F -c "| ${criterion_id} |" "${RECORD_PATH}" || true)"
  if [[ "${row_count}" != 1 ]]; then
    fail "${criterion_id} must have exactly one record row; found ${row_count}"
    return
  fi
  row="$(rg -F "| ${criterion_id} |" "${RECORD_PATH}")"
  criterion_status="$(trim "$(row_status "${row}")")"
  evidence="$(row_evidence "${row}")"
  case "${criterion_status}" in
    PASS|FAIL|'NOT RUN') ;;
    *) fail "${criterion_id} has invalid status: ${criterion_status}" ;;
  esac
  if [[ -z "${evidence}" ]]; then
    fail "${criterion_id} must include evidence"
  fi
}

gate_ids=(
  identity-matrix
  deterministic-providers
  live-playmatch
  live-gametdb
  live-steamgriddb
  library-scale
  migration
  security-privacy
  generated-source
  documentation-consistency
  just-check
  desktop-native
  android-api36-arm64
)
for gate_id in "${gate_ids[@]}"; do
  check_gate "${gate_id}"
done

for criterion_id in PAC-1 PAC-2 PAC-3 PAC-4 PAC-5; do
  check_criterion "${criterion_id}"
done
for criterion_id in TAC-1 TAC-2 TAC-3 TAC-4 TAC-5 TAC-6 TAC-7 TAC-8 TAC-9 TAC-10 TAC-11 TAC-12; do
  check_criterion "${criterion_id}"
done

qualification_result_count="$(rg -F -c 'Qualification result:' "${RECORD_PATH}" || true)"
if [[ "${qualification_result_count}" != 1 ]]; then
  fail "Qualification result must appear exactly once; found ${qualification_result_count}"
fi
overall_result="$(rg -F 'Qualification result:' "${RECORD_PATH}" | awk -F ':' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' || true)"
completion_declaration_count="$(rg -F -c 'Completion declaration:' "${RECORD_PATH}" || true)"
if [[ "${completion_declaration_count}" != 1 ]]; then
  fail "Completion declaration must appear exactly once; found ${completion_declaration_count}"
fi
completion_declaration="$(rg -F 'Completion declaration:' "${RECORD_PATH}" | awk -F ':' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' || true)"
non_pass_count=0
for gate_id in "${gate_ids[@]}"; do
  row="$(rg -F "| ${gate_id} |" "${RECORD_PATH}" || true)"
  if [[ "$(row_status "${row}")" != 'PASS' ]]; then
    non_pass_count=$((non_pass_count + 1))
  fi
done
if (( non_pass_count > 0 )) && [[ "${overall_result}" != BLOCKED ]]; then
  fail "qualification result must be BLOCKED while mandatory gates are not all PASS"
fi
if (( non_pass_count > 0 )) && [[ "${completion_declaration}" != 'NOT COMPLETE' ]]; then
  fail "completion declaration must be NOT COMPLETE while mandatory gates are not all PASS"
fi
if (( non_pass_count == 0 )) && [[ "${overall_result}" != COMPLETE ]]; then
  fail "qualification result must be COMPLETE when every mandatory gate is PASS"
fi
if (( non_pass_count == 0 )) && [[ "${completion_declaration}" != COMPLETE ]]; then
  fail "completion declaration must be COMPLETE when every mandatory gate is PASS"
fi

if (( failure_count > 0 )); then
  exit 1
fi
printf 'Qualification record is structurally valid: %s\n' "${RECORD_PATH}"
