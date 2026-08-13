#![cfg(feature = "test-support")]

use std::path::Path;

use argus_application::{
    AppearanceSettings, AppearanceSettingsQueries, AppearanceSettingsRepository, ApplicationEvent,
    ApplicationPortError, ErrorCode, EventRecorder, EventRecordingError, OperationContext,
    OperationName, PersistenceError, SettingsService, SubsystemName, ThemeMode, TraceId,
    UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{SqliteAppearanceSettingsQueries, SqliteDatabaseExecutor};
use rusqlite::Connection;
use std::time::Duration;
use tempfile::tempdir;

fn context(operation: &str) -> OperationContext {
    OperationContext::new(
        TraceId::try_from(9_u128).expect("trace"),
        SubsystemName::try_from("settings").expect("subsystem"),
        OperationName::try_from(operation).expect("operation"),
    )
}

fn open(path: &Path) -> SqliteDatabaseExecutor {
    SqliteDatabaseExecutor::open(path).expect("database")
}

fn query(executor: &SqliteDatabaseExecutor) -> SqliteAppearanceSettingsQueries {
    SqliteAppearanceSettingsQueries::new(executor.clone())
}

fn read(executor: &SqliteDatabaseExecutor) -> AppearanceSettings {
    query(executor)
        .get(&context("read"))
        .expect("appearance read")
}

#[test]
fn fresh_migration_reads_the_materialized_system_default() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));

    assert_eq!(read(&executor), AppearanceSettings::new(ThemeMode::System));
    executor.shutdown().expect("shutdown");
}

#[test]
fn repository_round_trips_each_supported_theme_mode() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));

    for mode in [ThemeMode::System, ThemeMode::Light, ThemeMode::Dark] {
        let requested = AppearanceSettings::new(mode);
        executor
            .execute(&context("update"), move |mut work| {
                {
                    let mut repository = work.appearance_settings();
                    repository.save(&requested)?;
                }
                work.commit()
            })
            .expect("save");
        assert_eq!(read(&executor), requested);
    }
    executor.shutdown().expect("shutdown");
}

#[test]
fn persisted_theme_survives_executor_recreation() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("appearance.sqlite3");
    let first = open(&path);
    first
        .execute(&context("update"), |mut work| {
            {
                let mut repository = work.appearance_settings();
                repository.save(&AppearanceSettings::new(ThemeMode::Dark))?;
            }
            work.commit()
        })
        .expect("save");
    first.shutdown().expect("first shutdown");

    let second = open(&path);
    assert_eq!(read(&second), AppearanceSettings::new(ThemeMode::Dark));
    second.shutdown().expect("second shutdown");
}

#[test]
fn every_supported_theme_mode_survives_executor_recreation() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("appearance.sqlite3");

    for mode in [ThemeMode::System, ThemeMode::Light, ThemeMode::Dark] {
        let executor = open(&path);
        let requested = AppearanceSettings::new(mode);
        executor
            .execute(&context("update"), move |mut work| {
                {
                    let mut repository = work.appearance_settings();
                    repository.save(&requested)?;
                }
                work.commit()
            })
            .expect("save");
        executor.shutdown().expect("shutdown");

        let reopened = open(&path);
        assert_eq!(read(&reopened), requested);
        reopened.shutdown().expect("reopened shutdown");
    }
}

#[test]
fn missing_required_row_is_an_integrity_error_without_default_repair() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));
    executor
        .with_connection_for_tests(context("corrupt"), |connection| {
            connection.execute("DELETE FROM appearance_settings")
        })
        .expect("delete row");

    let error = query(&executor)
        .get(&context("read"))
        .expect_err("missing row");
    assert_eq!(
        error,
        PersistenceError::PersistedSettingsInvalid(
            argus_application::PersistedSettingsReason::Missing
        )
    );
    let row_count = executor
        .with_connection_for_tests(context("verify"), |connection| {
            connection.scalar_i64("SELECT COUNT(*) FROM appearance_settings")
        })
        .expect("verify missing row remains missing");
    assert_eq!(row_count, 0);
    executor.shutdown().expect("shutdown");
}

#[test]
fn invalid_persisted_theme_is_an_integrity_error_without_raw_value_leakage() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));
    executor
        .with_connection_for_tests(context("corrupt"), |connection| {
            connection.execute("PRAGMA ignore_check_constraints = ON")?;
            connection.execute(
                "UPDATE appearance_settings SET theme_mode = 'sepia' WHERE singleton_key = 1",
            )
        })
        .expect("inject invalid value");

    let error = query(&executor)
        .get(&context("read"))
        .expect_err("invalid value");
    assert_eq!(
        error,
        PersistenceError::PersistedSettingsInvalid(
            argus_application::PersistedSettingsReason::InvalidValue
        )
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn missing_appearance_table_keeps_the_broader_persistence_failure_mapping() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));
    executor
        .with_connection_for_tests(context("corrupt"), |connection| {
            connection.execute("DROP TABLE appearance_settings")
        })
        .expect("drop table");

    let error = query(&executor)
        .get(&context("read"))
        .expect_err("missing table");
    assert_eq!(error, PersistenceError::Internal);
    executor.shutdown().expect("shutdown");
}

#[test]
fn dropping_an_uncommitted_repository_scope_rolls_back_the_replacement() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));
    executor
        .execute(&context("rollback"), |mut work| {
            let mut repository = work.appearance_settings();
            repository.save(&AppearanceSettings::new(ThemeMode::Dark))?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("callback result");

    assert_eq!(read(&executor), AppearanceSettings::new(ThemeMode::System));
    executor.shutdown().expect("shutdown");
}

#[test]
fn injected_save_failure_preserves_the_prior_theme() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));
    executor
        .with_connection_for_tests(context("inject"), |connection| {
            connection.execute(
                "CREATE TRIGGER fail_appearance_update BEFORE UPDATE ON appearance_settings BEGIN SELECT RAISE(ABORT, 'test'); END",
            )
        })
        .expect("install test trigger");

    let result = executor.execute(&context("update"), |mut work| {
        let mut repository = work.appearance_settings();
        Ok::<_, ApplicationPortError>(repository.save(&AppearanceSettings::new(ThemeMode::Dark))?)
    });
    assert_eq!(
        result,
        Err(ApplicationPortError::Persistence(
            PersistenceError::ConstraintViolation
        ))
    );
    assert_eq!(read(&executor), AppearanceSettings::new(ThemeMode::System));
    executor.shutdown().expect("shutdown");
}

#[derive(Clone, Copy)]
struct NoopRecorder;

impl EventRecorder for NoopRecorder {
    fn record(&self, _event: ApplicationEvent) -> Result<(), EventRecordingError> {
        Ok(())
    }
}

#[test]
fn semantic_noop_does_not_mutate_persistence_metadata() {
    let directory = tempdir().expect("temporary directory");
    let executor = open(&directory.path().join("appearance.sqlite3"));
    executor
        .with_connection_for_tests(context("seed"), |connection| {
            connection.execute(
                "UPDATE appearance_settings SET updated_at = 'before-noop' WHERE singleton_key = 1",
            )
        })
        .expect("seed deterministic metadata");

    let service = SettingsService::new(query(&executor), executor.clone());
    service
        .update_appearance_settings(
            argus_application::UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(
                ThemeMode::System,
            )),
            context("noop"),
            NoopRecorder,
            std::sync::Arc::new(|| false),
        )
        .expect("no-op");
    let metadata = executor
        .with_connection_for_tests(context("verify"), |connection| {
            connection
                .scalar_text("SELECT updated_at FROM appearance_settings WHERE singleton_key = 1")
        })
        .expect("read metadata");
    assert_eq!(metadata, "before-noop");
    executor.shutdown().expect("shutdown");
}

#[test]
fn database_locked_appearance_update_maps_to_database_locked() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("appearance.sqlite3");
    let executor = open(&path);
    executor
        .with_connection_for_tests(context("configure"), |connection| {
            connection.execute_batch("PRAGMA busy_timeout = 0;")
        })
        .expect("disable worker busy wait for deterministic lock mapping");

    let blocker = Connection::open(&path).expect("blocking connection");
    blocker
        .busy_timeout(Duration::ZERO)
        .expect("disable blocker busy wait");
    blocker
        .execute_batch("BEGIN IMMEDIATE")
        .expect("acquire SQLite writer lock");

    let service = SettingsService::new(query(&executor), executor.clone());
    let error = service
        .update_appearance_settings(
            argus_application::UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(
                ThemeMode::Dark,
            )),
            context("locked"),
            NoopRecorder,
            std::sync::Arc::new(|| false),
        )
        .expect_err("locked update");
    assert_eq!(error.code, ErrorCode::PersistenceDatabaseLocked);

    drop(blocker);
    executor.shutdown().expect("shutdown");
}

#[test]
fn save_rejects_more_than_one_matching_singleton_and_rolls_back() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("appearance.sqlite3");
    let executor = open(&path);
    executor
        .with_connection_for_tests(context("corrupt"), |connection| {
            connection.execute_batch(
                "DROP TABLE appearance_settings;
                 CREATE TABLE appearance_settings (
                     singleton_key INTEGER NOT NULL,
                     theme_mode TEXT NOT NULL,
                     updated_at TEXT NOT NULL
                 );
                 INSERT INTO appearance_settings (singleton_key, theme_mode, updated_at)
                     VALUES (1, 'system', 'first');
                 INSERT INTO appearance_settings (singleton_key, theme_mode, updated_at)
                     VALUES (1, 'light', 'second');",
            )
        })
        .expect("create duplicate singleton rows");

    let result = executor.execute(&context("update"), |mut work| {
        {
            let mut repository = work.appearance_settings();
            repository.save(&AppearanceSettings::new(ThemeMode::Dark))?;
        }
        work.commit()
    });
    assert_eq!(
        result,
        Err(ApplicationPortError::Persistence(
            PersistenceError::CorruptOrIncompatible
        ))
    );

    let rows = executor
        .with_connection_for_tests(context("verify"), |connection| {
            Ok::<_, _>(
                (
                    connection.scalar_i64(
                        "SELECT COUNT(*) FROM appearance_settings WHERE singleton_key = 1",
                    )?,
                    connection.scalar_text(
                        "SELECT theme_mode FROM appearance_settings WHERE singleton_key = 1 ORDER BY rowid LIMIT 1 OFFSET 0",
                    )?,
                    connection.scalar_text(
                        "SELECT theme_mode FROM appearance_settings WHERE singleton_key = 1 ORDER BY rowid LIMIT 1 OFFSET 1",
                    )?,
                )
            )
        })
        .expect("verify duplicate rows remained unchanged");
    assert_eq!(rows, (2, "system".to_owned(), "light".to_owned()));
    executor.shutdown().expect("shutdown");
}
