//! Forward migration coverage for revision-fenced Library view state.

mod common;

use argus_application::{OperationContext, OperationName, SubsystemName, TraceId};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use rusqlite::Connection;
use tempfile::tempdir;

const GAME_ID: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(20_u128).expect("trace"),
        SubsystemName::try_from("migration_v20").expect("subsystem"),
        OperationName::try_from("upgrade").expect("operation"),
    )
}

fn migration_history(connection: &Connection) -> Vec<(i64, String, String, String)> {
    let mut statement = connection
        .prepare("SELECT version, name, kind, checksum FROM schema_migrations ORDER BY version")
        .expect("prepare migration history query");
    statement
        .query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })
        .expect("read migration history")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect migration history")
}

#[test]
fn v19_upgrade_preserves_data_and_history_and_initializes_one_view_state_row() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let v19 = SqliteDatabaseExecutor::open_with_registry(&database, common::registry_through(19))
        .expect("open schema v19 database");
    v19.with_connection_for_tests(context(), |connection| {
        connection.execute(
            "INSERT INTO game
                (game_id, platform_id, lifecycle_state, grouping_revision,
                 fallback_title, fallback_title_provenance, hydration_state,
                 created_at, updated_at)
                VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'nintendo.gb', 'active', 1, 'Preserved game',
                    'local_fallback', 'partially_hydrated', '1', '1')",
        )?;
        Ok(())
    })
    .expect("seed schema v19 owner data");
    v19.shutdown().expect("close schema v19 database");

    let before = Connection::open(&database).expect("inspect schema v19 history");
    let prior_history = migration_history(&before);
    assert_eq!(prior_history.len(), 19);
    drop(before);

    let upgraded = SqliteDatabaseExecutor::open(&database).expect("upgrade to schema v20");
    upgraded.shutdown().expect("close upgraded database");

    let connection = Connection::open(database).expect("inspect schema v20 database");
    let history = migration_history(&connection);
    assert_eq!(history.len(), 20);
    assert_eq!(&history[..19], prior_history.as_slice());
    assert_eq!(history[19].0, 20);

    let view_state: (i64, String, i64, i64) = connection
        .query_row(
            "SELECT singleton_key, generation_id, membership_revision,
                    query_contract_version
             FROM library_view_state",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read initialized Library view state");
    assert_eq!(view_state.0, 1);
    assert_eq!(view_state.1.len(), 32);
    assert!(view_state.1.bytes().all(|byte| byte.is_ascii_hexdigit()));
    assert_eq!(view_state.2, 1);
    assert_eq!(view_state.3, 1);

    let row_count: i64 = connection
        .query_row(
            "SELECT COUNT(*) FROM game WHERE game_id = ?1",
            [GAME_ID],
            |row| row.get(0),
        )
        .expect("verify preserved owner data");
    assert_eq!(row_count, 1);
}
