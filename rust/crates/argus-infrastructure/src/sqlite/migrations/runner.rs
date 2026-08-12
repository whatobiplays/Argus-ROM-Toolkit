//! Migration execution and history validation. All mutation occurs in one
//! startup-owned `BEGIN IMMEDIATE` transaction.

use rusqlite::{Connection, Transaction};

use super::{MigrationKind, MigrationOutcome, MigrationRegistry, MigrationSummary, timestamp};
use crate::sqlite::errors::{MigrationError, SqliteExecutorError, operation_error};

pub(crate) fn apply_migrations(
    connection: &mut Connection,
    registry: &MigrationRegistry,
) -> Result<MigrationSummary, SqliteExecutorError> {
    validate_existing_schema(connection, registry).map_err(map_migration_error)?;
    let transaction = connection
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(|error| map_sql_error(&error))?;
    let applied = ensure_history_and_apply(transaction, registry).map_err(map_migration_error)?;
    Ok(applied)
}

fn ensure_history_and_apply(
    transaction: Transaction<'_>,
    registry: &MigrationRegistry,
) -> Result<MigrationSummary, MigrationError> {
    transaction
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS schema_migrations (\n                version INTEGER PRIMARY KEY,\n                name TEXT NOT NULL,\n                kind TEXT NOT NULL,\n                checksum TEXT NOT NULL,\n                applied_at TEXT NOT NULL,\n                app_version TEXT NOT NULL\n            );",
        )
        .map_err(|_| MigrationError::SqlExecution)?;
    validate_history_schema(&transaction)?;
    let history = read_history(&transaction)?;
    validate_history_rows(&history, registry)?;
    let mut applied_count = 0;
    for migration in registry.as_slice().iter().skip(history.len()) {
        if migration.kind != MigrationKind::Sql {
            return Err(MigrationError::SqlExecution);
        }
        let sql = std::str::from_utf8(&migration.bytes).map_err(|_| MigrationError::InvalidSql)?;
        transaction
            .execute_batch(sql)
            .map_err(|_| MigrationError::SqlExecution)?;
        transaction
            .execute(
                "INSERT INTO schema_migrations (version, name, kind, checksum, applied_at, app_version) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                rusqlite::params![
                    migration.version,
                    migration.name,
                    migration.kind.as_str(),
                    migration.checksum(),
                    timestamp(),
                    env!("CARGO_PKG_VERSION"),
                ],
            )
            .map_err(|_| MigrationError::SqlExecution)?;
        applied_count += 1;
    }
    // Validate both the complete history and the resulting SQLite schema
    // while the same transaction is still open. Any failure here must abort
    // the entire pending batch rather than leaving a partially applied DB.
    validate_history_schema(&transaction)?;
    let resulting_history = read_history(&transaction)?;
    validate_history_rows(&resulting_history, registry)?;
    validate_resulting_schema(&transaction)?;
    #[cfg(feature = "test-support")]
    if registry.final_validation_should_fail() {
        return Err(MigrationError::MalformedHistory);
    }
    let current_version = registry
        .as_slice()
        .last()
        .map(|migration| migration.version)
        .unwrap_or(0);
    transaction
        .commit()
        .map_err(|_| MigrationError::SqlExecution)?;
    Ok(MigrationSummary {
        applied_count,
        current_version,
        outcome: if applied_count == 0 {
            MigrationOutcome::AlreadyCurrent
        } else {
            MigrationOutcome::Applied
        },
    })
}

fn validate_existing_schema(
    connection: &Connection,
    registry: &MigrationRegistry,
) -> Result<(), MigrationError> {
    let history_exists: bool = connection
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='schema_migrations')",
            [],
            |row| row.get(0),
        )
        .map_err(|_| MigrationError::MalformedHistory)?;
    if history_exists {
        validate_history_schema(connection)?;
        let history = read_history(connection)?;
        validate_history_rows(&history, registry)?;
        return Ok(());
    }

    let mut statement = connection
        .prepare("SELECT type, name FROM sqlite_master WHERE type IN ('table', 'view', 'trigger', 'index') AND name NOT LIKE 'sqlite_%'")
        .map_err(|_| MigrationError::MalformedHistory)?;
    let names = statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|_| MigrationError::MalformedHistory)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| MigrationError::MalformedHistory)?;
    if !names.is_empty() {
        return Err(MigrationError::MissingHistoricalVersion(
            registry.as_slice().first().map(|m| m.version).unwrap_or(1),
        ));
    }
    Ok(())
}

fn validate_history_schema(connection: &Connection) -> Result<(), MigrationError> {
    let mut statement = connection
        .prepare("PRAGMA table_info(schema_migrations)")
        .map_err(|_| MigrationError::MalformedHistory)?;
    let columns = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, i64>(5)?,
            ))
        })
        .map_err(|_| MigrationError::MalformedHistory)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| MigrationError::MalformedHistory)?;
    let names: Vec<&str> = columns
        .iter()
        .map(|(name, _, _, _)| name.as_str())
        .collect();
    if names
        != [
            "version",
            "name",
            "kind",
            "checksum",
            "applied_at",
            "app_version",
        ]
    {
        return Err(MigrationError::MalformedHistory);
    }
    if columns.first().is_none_or(|first| first.3 != 1)
        || columns.iter().skip(1).any(|column| column.3 != 0)
        || columns
            .iter()
            .zip(["INTEGER", "TEXT", "TEXT", "TEXT", "TEXT", "TEXT"])
            .any(|((_, actual, _, _), expected)| !actual.eq_ignore_ascii_case(expected))
        || columns.iter().skip(1).any(|column| column.2 != 1)
    {
        return Err(MigrationError::MalformedHistory);
    }
    Ok(())
}

type HistoryRow = (u32, String, String, String, String, String);

fn read_history(connection: &Connection) -> Result<Vec<HistoryRow>, MigrationError> {
    let mut statement = connection
        .prepare("SELECT version, name, kind, checksum, applied_at, app_version FROM schema_migrations ORDER BY version")
        .map_err(|_| MigrationError::MalformedHistory)?;
    statement
        .query_map([], |row| {
            Ok((
                row.get(0)?,
                row.get(1)?,
                row.get(2)?,
                row.get(3)?,
                row.get(4)?,
                row.get(5)?,
            ))
        })
        .map_err(|_| MigrationError::MalformedHistory)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| MigrationError::MalformedHistory)
}

fn validate_history_rows(
    history: &[HistoryRow],
    registry: &MigrationRegistry,
) -> Result<(), MigrationError> {
    for (index, (version, name, kind, checksum, applied_at, app_version)) in
        history.iter().enumerate()
    {
        let Some(migration) = registry.as_slice().get(index) else {
            return Err(MigrationError::UnknownAppliedVersion(*version));
        };
        if *version != migration.version {
            if registry
                .as_slice()
                .iter()
                .any(|candidate| candidate.version == *version)
            {
                return Err(MigrationError::MissingHistoricalVersion(migration.version));
            }
            return Err(MigrationError::UnknownAppliedVersion(*version));
        }
        if name != &migration.name {
            return Err(MigrationError::NameMismatch(*version));
        }
        if kind != migration.kind.as_str() {
            return Err(MigrationError::KindMismatch(*version));
        }
        if checksum != &migration.checksum() {
            return Err(MigrationError::ChecksumMismatch(*version));
        }
        if !valid_applied_at(applied_at) || !valid_app_version(app_version) {
            return Err(MigrationError::MalformedHistory);
        }
    }
    Ok(())
}

fn valid_applied_at(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

fn valid_app_version(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'+' | b'-' | b'_'))
}

fn validate_resulting_schema(connection: &Connection) -> Result<(), MigrationError> {
    let integrity: String = connection
        .query_row("PRAGMA integrity_check", [], |row| row.get(0))
        .map_err(|_| MigrationError::MalformedHistory)?;
    if !integrity.eq_ignore_ascii_case("ok") {
        return Err(MigrationError::MalformedHistory);
    }
    let history_exists: bool = connection
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations')",
            [],
            |row| row.get(0),
        )
        .map_err(|_| MigrationError::MalformedHistory)?;
    if !history_exists {
        return Err(MigrationError::MalformedHistory);
    }
    Ok(())
}

fn map_migration_error(error: MigrationError) -> SqliteExecutorError {
    match error {
        MigrationError::UnknownAppliedVersion(_)
        | MigrationError::MissingHistoricalVersion(_)
        | MigrationError::MalformedHistory
        | MigrationError::NameMismatch(_)
        | MigrationError::KindMismatch(_)
        | MigrationError::ChecksumMismatch(_)
        | MigrationError::InvalidOrdering
        | MigrationError::Duplicate
        | MigrationError::InvalidSql => SqliteExecutorError::IncompatibleSchema,
        MigrationError::SqlExecution => SqliteExecutorError::MigrationFailed { version: None },
    }
}

fn map_sql_error(error: &rusqlite::Error) -> SqliteExecutorError {
    if matches!(
        operation_error(error),
        crate::sqlite::errors::SqliteOperationError::Locked
    ) {
        SqliteExecutorError::DatabaseLocked
    } else {
        SqliteExecutorError::MigrationFailed { version: None }
    }
}
