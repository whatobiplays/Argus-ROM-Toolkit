#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION_SQL_PATH="${ROOT_DIR}/rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0001_initial.sql"
PACKAGE_ID="com.argusromtoolkit.argus"
STAGING_DB_PATH="/data/local/tmp/ArgusP02005Diagnostics.sqlite3"
fixture_root=''

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/run_phase_002_android_scenario_common.sh"
argus_android_require_device
argus_android_build_and_install "${ROOT_DIR}"
command -v sqlite3 >/dev/null 2>&1 || {
  printf 'Required developer tool is missing: sqlite3\n' >&2
  exit 1
}

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/argus-p02005-diagnostics.XXXXXX")"
fixture_db="${fixture_root}/argus.sqlite3"
cleanup() {
  rm -rf "${fixture_root}"
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell rm -f "${STAGING_DB_PATH}" >/dev/null 2>&1 || true
  "${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
    shell run-as "${PACKAGE_ID}" rm -f files/argus/argus.sqlite3 >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -f "${MIGRATION_SQL_PATH}" ]]; then
  printf 'Required migration fixture is missing: %s\n' "${MIGRATION_SQL_PATH}" >&2
  exit 1
fi
migration_sql="$(<"${MIGRATION_SQL_PATH}")"
migration_sha256="$(shasum -a 256 "${MIGRATION_SQL_PATH}" | awk '{print $1}')"
{
  cat <<SQL
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  checksum TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  app_version TEXT NOT NULL
);
INSERT INTO schema_migrations (version, name, kind, checksum, applied_at, app_version)
VALUES (1, '0001_initial', 'sql', '${migration_sha256}', '1720000000', '0.1.0');
SQL
  printf '%s\n' "${migration_sql}"
  printf 'DELETE FROM appearance_settings WHERE singleton_key = 1;\n'
} | sqlite3 "${fixture_db}"

"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  push "${fixture_db}" "${STAGING_DB_PATH}" >/dev/null
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell run-as "${PACKAGE_ID}" mkdir -p files/argus
"${ARGUS_ANDROID_SCENARIO_ADB}" -s "${ARGUS_ANDROID_SCENARIO_DEVICE}" \
  shell run-as "${PACKAGE_ID}" cp "${STAGING_DB_PATH}" files/argus/argus.sqlite3

printf 'Running focused backend-export and Android share-sheet scenario\n'
argus_android_run_integration \
  "${ROOT_DIR}" \
  phase_002_android_diagnostics_share_test.dart

printf 'P02-005 Android diagnostics publication scenario passed on %s\n' \
  "${ARGUS_ANDROID_SCENARIO_DEVICE}"
