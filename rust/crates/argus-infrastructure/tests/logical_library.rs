#![cfg(feature = "test-support")]

use argus_application::{OperationContext, OperationName, SubsystemName, TraceId};
use argus_infrastructure::sqlite::{SqliteDatabaseExecutor, SqliteValue};
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(101_u128).expect("trace"),
        SubsystemName::try_from("logical").expect("subsystem"),
        OperationName::try_from("library").expect("operation"),
    )
}

#[test]
fn logical_schema_is_added_without_backfilling_existing_source_rows() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");

    assert_eq!(executor.migration_summary().current_version, 11);
    executor
        .with_connection_for_tests(context(), |connection| {
            for table in [
                "game_content",
                "content_identity",
                "game_content_source",
                "game",
                "game_membership",
                "game_redirect",
                "game_library_row",
            ] {
                assert!(connection.table_exists(table)?, "missing {table}");
            }
            assert_eq!(
                connection.scalar_i64("SELECT COUNT(*) FROM game_content")?,
                0
            );
            assert_eq!(connection.scalar_i64("SELECT COUNT(*) FROM game")?, 0);
            Ok(())
        })
        .expect("schema query");
    executor.shutdown().expect("shutdown");
}

#[test]
fn current_identity_uniqueness_ignores_revision() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("logical.sqlite3")).expect("database");

    let rejected = executor
        .with_connection_for_tests(context(), |connection| {
            for content_id in [
                "11111111111111111111111111111111",
                "22222222222222222222222222222222",
            ] {
                connection.execute_with_values(
                    "INSERT INTO game_content
                        (game_content_id, platform_id, content_type, presence_state,
                         identification_state, grouping_revision, created_at, updated_at)
                     VALUES (?1, 'nintendo.gb', 'CartridgeImage', 'available',
                             'identified', 1, '1', '1')",
                    &[SqliteValue::Text(content_id.to_owned())],
                )?;
            }

            let identity_values = [
                (
                    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "11111111111111111111111111111111",
                    1_i64,
                ),
                (
                    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "22222222222222222222222222222222",
                    2_i64,
                ),
            ];
            connection.execute_with_values(
                "INSERT INTO content_identity
                    (content_identity_id, game_content_id, scheme_id, identity_revision,
                     identity_value, is_current, created_at, updated_at)
                 VALUES (?1, ?2, 'argus.content.identity.nintendo-gb.cartridge.v1',
                         ?3, ?4, 1, '1', '1')",
                &[
                    SqliteValue::Text(identity_values[0].0.to_owned()),
                    SqliteValue::Text(identity_values[0].1.to_owned()),
                    SqliteValue::Integer(identity_values[0].2),
                    SqliteValue::Text("09".repeat(32)),
                ],
            )?;
            let error = connection.execute_with_values(
                "INSERT INTO content_identity
                    (content_identity_id, game_content_id, scheme_id, identity_revision,
                     identity_value, is_current, created_at, updated_at)
                 VALUES (?1, ?2, 'argus.content.identity.nintendo-gb.cartridge.v1',
                         ?3, ?4, 1, '1', '1')",
                &[
                    SqliteValue::Text(identity_values[1].0.to_owned()),
                    SqliteValue::Text(identity_values[1].1.to_owned()),
                    SqliteValue::Integer(identity_values[1].2),
                    SqliteValue::Text("09".repeat(32)),
                ],
            );
            Ok(error.is_err())
        })
        .expect("current identity uniqueness");
    assert!(rejected, "revision must not partition current ownership");
    executor.shutdown().expect("shutdown");
}
