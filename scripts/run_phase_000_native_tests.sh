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

debug_signing_config="$ROOT_DIR/flutter/macos/Runner/Configs/Debug.local.xcconfig"
debug_app="$ROOT_DIR/flutter/build/macos/Build/Products/Debug/argus.app"

read_xcconfig_value() {
  local key="$1"
  local config_path="$2"
  local value
  value="$(sed -n -E "s|^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$|\1|p" \
    "$config_path" | tail -n 1)"
  printf '%s' "$value" | sed -E \
    's/[[:space:]]*\/\/.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^"(.*)"$/\1/'
}

configure_macos_debug_signing() {
  local identity="${FLUTTER_XCODE_CODE_SIGN_IDENTITY:-}"
  local team="${FLUTTER_XCODE_DEVELOPMENT_TEAM:-}"
  local style="${FLUTTER_XCODE_CODE_SIGN_STYLE:-Automatic}"

  if [[ -f "$debug_signing_config" ]]; then
    identity="$(read_xcconfig_value CODE_SIGN_IDENTITY "$debug_signing_config")"
    team="$(read_xcconfig_value DEVELOPMENT_TEAM "$debug_signing_config")"
    local configured_style
    configured_style="$(read_xcconfig_value CODE_SIGN_STYLE "$debug_signing_config")"
    if [[ -n "$configured_style" ]]; then
      style="$configured_style"
    fi
  fi

  if [[ -z "$identity" || -z "$team" ]]; then
    printf 'Stable macOS Debug signing is required for native qualification.\n' >&2
    printf 'Create the ignored local override at:\n  %s\n' \
      "$debug_signing_config" >&2
    printf 'with owner-local values such as:\n' >&2
    printf '  CODE_SIGN_IDENTITY = Apple Development\n' >&2
    printf '  DEVELOPMENT_TEAM = YOUR_TEAM_IDENTIFIER\n' >&2
    printf '  CODE_SIGN_STYLE = Automatic\n' >&2
    return 1
  fi
  if [[ "$identity" != "Apple Development"* ]]; then
    printf 'Native qualification requires an Apple Development signing identity.\n' >&2
    printf 'Update %s without adding owner-specific values to tracked files.\n' \
      "$debug_signing_config" >&2
    return 1
  fi

  export FLUTTER_XCODE_CODE_SIGN_IDENTITY="$identity"
  export FLUTTER_XCODE_DEVELOPMENT_TEAM="$team"
  export FLUTTER_XCODE_CODE_SIGN_STYLE="$style"
}

verify_macos_debug_signature() {
  local app_path="$1"
  if [[ ! -d "$app_path" ]]; then
    printf 'Expected macOS Debug app was not built: %s\n' "$app_path" >&2
    return 1
  fi

  local signature_details
  if ! signature_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"; then
    printf 'Unable to inspect the macOS Debug app signature.\n' >&2
    return 1
  fi

  local bundle_identifier
  bundle_identifier="$(printf '%s\n' "$signature_details" | sed -n 's/^Identifier=//p')"
  local team_identifier
  team_identifier="$(printf '%s\n' "$signature_details" | sed -n 's/^TeamIdentifier=//p')"
  if [[ "$bundle_identifier" != "dev.argusromtoolkit.argus" ]]; then
    printf 'Unexpected macOS Debug bundle identifier: %s\n' \
      "$bundle_identifier" >&2
    return 1
  fi
  if ! printf '%s\n' "$signature_details" | grep -q '^Authority=Apple Development:'; then
    printf 'macOS Debug app is not Apple Development signed.\n' >&2
    return 1
  fi
  if [[ -z "$team_identifier" || "$team_identifier" == "not set" ]]; then
    printf 'macOS Debug app has no TeamIdentifier; stable signing is required.\n' >&2
    return 1
  fi
  printf 'Verified stable Apple Development signing for macOS native qualification\n'
}

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
onboarding_root="$(mktemp -d "$app_container_dir/argus-phase-000-root.XXXXXX")"
trap 'rm -rf "$data_dir" "$onboarding_root"' EXIT

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

  configure_macos_debug_signing
  printf 'Building macOS Debug app with stable development signing\n'
  fvm flutter build macos --debug --no-pub
  verify_macos_debug_signature "$debug_app"

  printf 'Running native bridge smoke test\n'
  fvm flutter test integration_test/native_bridge_smoke_test.dart -d macos

  printf 'Running startup recovery smoke test\n'
  fvm flutter test integration_test/startup_recovery_smoke_test.dart -d macos

  printf 'Running restart restoration seed phase\n'
  ARGUS_PHASE_000_RESTART_MODE=seed \
  ARGUS_PHASE_000_DATA_DIR="$data_dir" \
  ARGUS_PHASE_000_ONBOARDING_ROOT="$onboarding_root" \
    fvm flutter test integration_test/phase_000_restart_restoration_test.dart \
      -d macos

  printf 'Running restart restoration verify phase\n'
  ARGUS_PHASE_000_RESTART_MODE=verify \
  ARGUS_PHASE_000_DATA_DIR="$data_dir" \
    fvm flutter test integration_test/phase_000_restart_restoration_test.dart \
      -d macos
)

printf 'Phase 000 native milestone proof passed\n'
