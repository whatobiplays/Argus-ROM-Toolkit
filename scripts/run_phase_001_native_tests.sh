#!/usr/bin/env bash
set -euo pipefail

# Phase 001 native milestone proof.
#
# This harness is intentionally separate from the platform-neutral `just check`
# gate: it rebuilds the real Rust bridge, launches native Flutter integration
# tests on macOS, and proves the canonical Phase 001 local-sources workflow
# plus the real two-process restart-recovery chain against test-owned state.
#
# Execution order:
#   1. rebuild argus-bridge with locked Cargo inputs
#   2. Phase 001 milestone (one Flutter process): Add & Scan, hierarchy,
#      Scan Again reconciliation, Scan All, cooperative cancellation,
#      root-removal safety, historical Jobs detail
#   3. restart seed phase (process one): durable Running, then intentional
#      termination without terminalizing the scan
#   4. restart verify phase (process two, same application-data directory):
#      exact Slice 006 Abandoned recovery with no auto-resume, launched with
#      the configured library root made unavailable to prove startup recovery
#      performs no provider resolution/enumeration
#
# All temporary application-data directories and library roots are created
# here and removed by the EXIT trap; the integration tests never delete them.
# macOS sandboxes the app processes without a file-access exception, so the
# test-owned directories live inside the app container where both Flutter
# launches can reach them.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'test-phase-001-native requires macOS (Darwin); got %s\n' \
    "$(uname -s)" >&2
  exit 1
fi

app_container_dir="$HOME/Library/Containers/dev.argusromtoolkit.argus/Data"
if [[ ! -d "$app_container_dir" ]]; then
  mkdir -p "$app_container_dir"
fi

milestone_data_dir="$(mktemp -d "$app_container_dir/argus-phase-001-milestone.XXXXXX")"
restart_data_dir="$(mktemp -d "$app_container_dir/argus-phase-001-restart.XXXXXX")"
root_one_dir="$(mktemp -d "$app_container_dir/argus-phase-001-root-one.XXXXXX")"
root_two_dir="$(mktemp -d "$app_container_dir/argus-phase-001-root-two.XXXXXX")"
root_one_unavailable_dir="${root_one_dir}.unavailable"

cleanup() {
  rm -rf \
    "$milestone_data_dir" \
    "$restart_data_dir" \
    "$root_one_dir" \
    "$root_one_unavailable_dir" \
    "$root_two_dir"
}
trap cleanup EXIT

mkdir -p "$root_one_dir/Sub"
printf 'nested\n' > "$root_one_dir/Sub/nested.txt"
printf 'rom\n' > "$root_one_dir/rom.bin"
printf 'keep\n' > "$root_one_dir/keep.txt"
printf 'remove-me\n' > "$root_one_dir/removed.bin"
printf 'move-me\n' > "$root_one_dir/moved.bin"

mkdir -p "$root_two_dir/Second"
printf 'two\n' > "$root_two_dir/Second/two.txt"
printf 'only-two\n' > "$root_two_dir/only-two.bin"

printf 'Rebuilding argus-bridge with locked inputs\n'
bash "$ROOT_DIR/scripts/run_rust.sh" cargo build \
  --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
  --package argus-bridge --locked

(
  cd "$ROOT_DIR/flutter"

  printf 'Running Phase 001 native milestone\n'
  ARGUS_PHASE_001_DATA_DIR="$milestone_data_dir" \
  ARGUS_PHASE_001_ROOT_ONE="$root_one_dir" \
  ARGUS_PHASE_001_ROOT_TWO="$root_two_dir" \
    fvm flutter test integration_test/phase_001_local_sources_milestone_test.dart \
      -d macos

  printf 'Running restart seed phase\n'
  set +e
  ARGUS_PHASE_001_RESTART_MODE=seed \
  ARGUS_PHASE_001_DATA_DIR="$restart_data_dir" \
  ARGUS_PHASE_001_ROOT_ONE="$root_one_dir" \
    fvm flutter test integration_test/phase_001_restart_recovery_test.dart \
      -d macos
  seed_status=$?
  set -e

  if [[ ! -f "$restart_data_dir/phase-001-restart-seed.sentinel" ]]; then
    printf 'Restart seed failed before proving durable Running\n' >&2
    exit 1
  fi
  if (( seed_status != 0 )); then
    printf 'Restart seed terminated as the expected intentional interruption\n'
  fi

  printf 'Making the configured library root unavailable to the verify process\n'
  mv "$root_one_dir" "$root_one_unavailable_dir"

  printf 'Running restart verify phase\n'
  ARGUS_PHASE_001_RESTART_MODE=verify \
  ARGUS_PHASE_001_DATA_DIR="$restart_data_dir" \
    fvm flutter test integration_test/phase_001_restart_recovery_test.dart \
      -d macos
)

printf 'Phase 001 native milestone proof passed\n'
