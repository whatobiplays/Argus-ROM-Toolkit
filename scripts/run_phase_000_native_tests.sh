#!/usr/bin/env bash
set -euo pipefail

# Phase 000 native milestone proof.
#
# This harness is intentionally separate from the platform-neutral `just check`
# gate: it rebuilds the real Rust bridge, launches native Flutter integration
# tests on macOS, and proves the canonical persisted-appearance restart chain
# with two distinct Flutter application processes sharing one test-owned
# temporary Argus data directory.
#
# Execution order:
#   1. rebuild argus-bridge with locked Cargo inputs
#   2. native bridge smoke test
#   3. native startup-failure/recovery/diagnostics smoke test
#   4. restart restoration seed phase (process one)
#   5. restart restoration verify phase (process two, same data directory)
#
# The temporary data directory is created here and removed by the EXIT trap;
# the integration tests never delete it themselves.
#
# macOS sandboxes the app processes without a file-access exception, so a
# directory under /tmp or the user TMPDIR is unreachable from the app. Both
# Flutter launches share the same app container, so the test-owned directory
# lives there and is removed by the trap after verification.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'test-phase-000-native requires macOS (Darwin); got %s\n' \
    "$(uname -s)" >&2
  exit 1
fi

app_container_dir="$HOME/Library/Containers/dev.argusromtoolkit.argus/Data"
if [[ ! -d "$app_container_dir" ]]; then
  mkdir -p "$app_container_dir"
fi
data_dir="$(mktemp -d "$app_container_dir/argus-phase-000.XXXXXX")"
trap 'rm -rf "$data_dir"' EXIT

printf 'Rebuilding argus-bridge with locked inputs\n'
bash "$ROOT_DIR/scripts/run_rust.sh" cargo build \
  --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
  --package argus-bridge --locked

(
  cd "$ROOT_DIR/flutter"
  # macOS desktop tests run with the app container as the working directory, so
  # tests that locate repository fixtures must receive the repo root through
  # their documented environment seam.
  export ARGUS_REPO_ROOT="$ROOT_DIR"
  # The sandboxed macOS app process cannot read repository files outside its
  # container, so the startup-recovery fixture is passed through the smoke
  # test's documented content/checksum environment seams.
  migration_sql="$ROOT_DIR/rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0001_initial.sql"
  ARGUS_MIGRATION_SQL="$(<"$migration_sql")"
  export ARGUS_MIGRATION_SQL
  ARGUS_MIGRATION_SHA256="$(shasum -a 256 "$migration_sql" | awk '{print $1}')"
  export ARGUS_MIGRATION_SHA256

  printf 'Running native bridge smoke test\n'
  fvm flutter test integration_test/native_bridge_smoke_test.dart -d macos

  printf 'Running startup recovery smoke test\n'
  fvm flutter test integration_test/startup_recovery_smoke_test.dart -d macos

  printf 'Running restart restoration seed phase\n'
  ARGUS_PHASE_000_RESTART_MODE=seed \
  ARGUS_PHASE_000_DATA_DIR="$data_dir" \
    fvm flutter test integration_test/phase_000_restart_restoration_test.dart \
      -d macos

  printf 'Running restart restoration verify phase\n'
  ARGUS_PHASE_000_RESTART_MODE=verify \
  ARGUS_PHASE_000_DATA_DIR="$data_dir" \
    fvm flutter test integration_test/phase_000_restart_restoration_test.dart \
      -d macos
)

printf 'Phase 000 native milestone proof passed\n'
