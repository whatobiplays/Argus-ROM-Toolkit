#![cfg(feature = "test-support")]

use argus_application::{
    ApplicationPortError, OperationContext, OperationName, PersistenceError, SubsystemName,
    TraceId, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{
    Migration, MigrationRegistry, SqliteDatabaseExecutor, SqliteExecutorError,
};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Barrier, mpsc};
use std::thread;
use std::time::Duration;
use tempfile::tempdir;

const TEST_WAIT_TIMEOUT: Duration = Duration::from_secs(2);

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("non-zero trace"),
        SubsystemName::try_from("test").expect("valid subsystem"),
        OperationName::try_from("sqlite").expect("valid operation"),
    )
}

#[cfg(feature = "test-support")]
fn wait_for_admitted(executor: &SqliteDatabaseExecutor, expected: usize) {
    assert!(
        executor.wait_for_admitted_for_tests(expected, TEST_WAIT_TIMEOUT),
        "timed out waiting for {expected} admitted work items"
    );
}

#[cfg(feature = "test-support")]
fn wait_for_attempted(executor: &SqliteDatabaseExecutor, expected: usize) {
    assert!(
        executor.wait_for_attempted_for_tests(expected, TEST_WAIT_TIMEOUT),
        "timed out waiting for {expected} attempted work items"
    );
}

#[cfg(feature = "test-support")]
fn wait_for_admission_closed(executor: &SqliteDatabaseExecutor) {
    assert!(
        executor.wait_for_admission_closed_for_tests(TEST_WAIT_TIMEOUT),
        "timed out waiting for shutdown admission closure"
    );
}

#[test]
fn fresh_database_configures_pragmas_and_seeds_one_system_row() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");

    let values = executor
        .with_connection_for_tests(context(), |connection| {
            Ok::<_, _>((
                connection.scalar_i64("PRAGMA foreign_keys")?,
                connection.scalar_text("PRAGMA journal_mode")?,
                connection.scalar_i64("PRAGMA busy_timeout")?,
                connection.scalar_i64("SELECT COUNT(*) FROM appearance_settings")?,
                connection.scalar_text(
                    "SELECT theme_mode FROM appearance_settings WHERE singleton_key = 1",
                )?,
            ))
        })
        .expect("query configured database");

    assert_eq!(values.0, 1);
    assert_eq!(values.1.to_ascii_lowercase(), "wal");
    assert_eq!(values.2, 5_000);
    assert_eq!(values.3, 1);
    assert_eq!(values.4, "system");
    executor.shutdown().expect("shutdown");
}

#[test]
fn reopening_current_database_preserves_migration_and_default() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("argus.sqlite3");
    let first = SqliteDatabaseExecutor::open(&path).expect("first open");
    first
        .with_connection_for_tests(context(), |connection| {
            connection.execute(
                "UPDATE appearance_settings SET theme_mode = 'dark' WHERE singleton_key = 1",
            )
        })
        .expect("update setting");
    first.shutdown().expect("first shutdown");

    let second = SqliteDatabaseExecutor::open(&path).expect("second open");
    let values = second
        .with_connection_for_tests(context(), |connection| {
            Ok::<_, _>((
                connection.scalar_i64("SELECT COUNT(*) FROM schema_migrations")?,
                connection.scalar_i64("SELECT COUNT(*) FROM appearance_settings")?,
                connection.scalar_text(
                    "SELECT theme_mode FROM appearance_settings WHERE singleton_key = 1",
                )?,
            ))
        })
        .expect("query reopened database");
    assert_eq!(values, (15, 1, "dark".to_owned()));
    second.shutdown().expect("second shutdown");
}

#[test]
fn serialized_work_runs_on_one_worker_and_reentrant_submission_is_rejected() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    let executor_for_callback = executor.clone();
    let expected_trace = context().trace_id();
    let nested = executor
        .with_connection_for_tests(context(), move |connection| {
            assert_eq!(connection.operation_context().trace_id(), expected_trace);
            executor_for_callback
                .with_connection_for_tests(context(), |_connection| Ok::<_, _>(()))
                .expect_err("worker re-entry must be rejected");
            assert_eq!(
                executor_for_callback.shutdown(),
                Err(SqliteExecutorError::ReentrantSubmission)
            );
            Ok::<_, _>(thread::current().id())
        })
        .expect("outer work");
    let later = executor
        .with_connection_for_tests(context(), |_connection| Ok::<_, _>(thread::current().id()))
        .expect("later work");
    assert_eq!(nested, later);
    executor.shutdown().expect("shutdown");
}

#[test]
fn nested_top_level_unit_of_work_is_rejected() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("nested-uow.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    let nested_executor = executor.clone();
    executor
        .with_unit_of_work(context(), move |_work| {
            assert_eq!(
                nested_executor
                    .with_unit_of_work(context(), |_nested| { Ok::<_, ApplicationPortError>(()) }),
                Err(SqliteExecutorError::ReentrantSubmission)
            );
            Ok::<_, ApplicationPortError>(())
        })
        .expect("outer unit of work");
    executor.shutdown().expect("shutdown");
}

#[test]
fn panic_poison_and_shutdown_reject_later_work() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    let panic_result = executor
        .with_connection_for_tests(context(), |_connection| -> Result<(), _> {
            panic!("test callback panic")
        });
    assert_eq!(panic_result, Err(SqliteExecutorError::Poisoned));
    assert_eq!(
        executor.with_connection_for_tests(context(), |_connection| Ok::<_, _>(())),
        Err(SqliteExecutorError::Poisoned)
    );
    executor.shutdown().expect("poisoned shutdown");
    assert_eq!(
        executor.with_connection_for_tests(context(), |_connection| Ok::<_, _>(())),
        Err(SqliteExecutorError::Poisoned)
    );
}

#[test]
fn queued_work_receives_stable_poison_result_after_worker_panic() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("queued-poison.sqlite3");
    let executor = SqliteDatabaseExecutor::open_with_capacity(&path, 1).expect("open database");
    let release = Arc::new(Barrier::new(2));
    let (first_started_sender, first_started_receiver) = mpsc::channel();
    let first = executor.clone();
    let release_first = release.clone();
    let first_thread = thread::spawn(move || {
        first.with_connection_for_tests::<(), _>(context(), move |_connection| {
            first_started_sender.send(()).expect("first started");
            release_first.wait();
            panic!("poison worker")
        })
    });
    first_started_receiver
        .recv()
        .expect("first callback started");

    let (second_started_sender, second_started_receiver) = mpsc::channel();
    let callback_ran = Arc::new(AtomicBool::new(false));
    let callback_ran_for_second = callback_ran.clone();
    let second = executor.clone();
    let second_thread = thread::spawn(move || {
        second_started_sender.send(()).expect("second submitted");
        second.with_connection_for_tests(context(), move |_connection| {
            callback_ran_for_second.store(true, Ordering::Release);
            Ok::<_, _>(())
        })
    });
    second_started_receiver
        .recv()
        .expect("second caller started");
    release.wait();

    assert_eq!(
        first_thread.join().expect("first caller"),
        Err(SqliteExecutorError::Poisoned)
    );
    assert_eq!(
        second_thread.join().expect("second caller"),
        Err(SqliteExecutorError::Poisoned)
    );
    assert!(!callback_ran.load(Ordering::Acquire));
    executor.shutdown().expect("poisoned shutdown");
}

#[test]
fn pending_migrations_are_atomic_when_a_later_migration_fails() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("atomic.sqlite3");
    let registry = MigrationRegistry::new(vec![
        Migration::sql(1, "first", b"CREATE TABLE first (id INTEGER PRIMARY KEY);"),
        Migration::sql(2, "fails", b"CREATE TABLE first (id INTEGER PRIMARY KEY);"),
    ])
    .expect("valid registry");
    let error = match SqliteDatabaseExecutor::open_with_registry(&path, registry) {
        Ok(executor) => {
            let _ = executor.shutdown();
            panic!("duplicate table unexpectedly opened")
        }
        Err(error) => error,
    };
    assert!(matches!(error, SqliteExecutorError::MigrationFailed { .. }));

    let check = rusqlite::Connection::open(&path).expect("reopen failed database");
    assert!(
        check
            .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='first'")
            .expect("prepare")
            .query([])
            .expect("query")
            .next()
            .expect("row result")
            .is_none()
    );
}

#[cfg(feature = "test-support")]
#[test]
fn bounded_queue_uses_blocking_backpressure_and_drains_in_order() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("queue.sqlite3");
    let executor = SqliteDatabaseExecutor::open_with_capacity(&path, 1).expect("open database");
    let release = Arc::new(Barrier::new(2));
    let (started_sender, started_receiver) = mpsc::channel();
    let order = Arc::new(std::sync::Mutex::new(Vec::new()));
    let first = executor.clone();
    let release_first = release.clone();
    let order_first = order.clone();
    let first_thread = thread::spawn(move || {
        first.with_connection_for_tests(context(), move |_connection| {
            started_sender.send(()).expect("started receiver");
            release_first.wait();
            order_first.lock().expect("order lock").push(1_u8);
            Ok::<_, _>(())
        })
    });
    started_receiver.recv().expect("first callback started");
    wait_for_admitted(&executor, 1);

    let second_finished = Arc::new(AtomicBool::new(false));
    let third_finished = Arc::new(AtomicBool::new(false));
    let second = executor.clone();
    let second_finished_flag = second_finished.clone();
    let order_second = order.clone();
    let second_thread = thread::spawn(move || {
        let result = second.with_connection_for_tests(context(), move |_connection| {
            order_second.lock().expect("order lock").push(2_u8);
            Ok::<_, _>(2_u8)
        });
        second_finished_flag.store(true, Ordering::Release);
        result
    });
    wait_for_admitted(&executor, 2);

    let (third_started_sender, third_started_receiver) = mpsc::channel();
    let third = executor.clone();
    let third_finished_flag = third_finished.clone();
    let order_third = order.clone();
    let third_thread = thread::spawn(move || {
        third_started_sender.send(()).expect("third caller started");
        let result = third.with_connection_for_tests(context(), move |_connection| {
            order_third.lock().expect("order lock").push(3_u8);
            Ok::<_, _>(3_u8)
        });
        third_finished_flag.store(true, Ordering::Release);
        result
    });
    third_started_receiver.recv().expect("third caller started");
    wait_for_attempted(&executor, 3);
    assert!(!second_finished.load(Ordering::Acquire));
    assert!(!third_finished.load(Ordering::Acquire));

    release.wait();
    first_thread
        .join()
        .expect("first caller")
        .expect("first work");
    assert_eq!(
        second_thread
            .join()
            .expect("second caller")
            .expect("second work"),
        2
    );
    assert_eq!(
        third_thread
            .join()
            .expect("third caller")
            .expect("third work"),
        3
    );
    assert_eq!(*order.lock().expect("order lock"), vec![1, 2, 3]);
    executor.shutdown().expect("shutdown");
}

#[cfg(feature = "test-support")]
#[test]
fn shutdown_drains_accepted_work_in_order_and_rejects_new_submissions() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("shutdown-drain.sqlite3");
    let executor = SqliteDatabaseExecutor::open_with_capacity(&path, 1).expect("open database");
    let release = Arc::new(Barrier::new(2));
    let (started_sender, started_receiver) = mpsc::channel();
    let order = Arc::new(std::sync::Mutex::new(Vec::new()));
    let first = executor.clone();
    let release_first = release.clone();
    let order_first = order.clone();
    let first_thread = thread::spawn(move || {
        first.with_connection_for_tests(context(), move |_connection| {
            started_sender.send(()).expect("first started");
            release_first.wait();
            order_first.lock().expect("order lock").push(1_u8);
            Ok::<_, _>(1_u8)
        })
    });
    started_receiver.recv().expect("first callback started");
    wait_for_admitted(&executor, 1);

    let second = executor.clone();
    let order_second = order.clone();
    let second_thread = thread::spawn(move || {
        second.with_connection_for_tests(context(), move |_connection| {
            order_second.lock().expect("order lock").push(2_u8);
            Ok::<_, _>(2_u8)
        })
    });
    wait_for_admitted(&executor, 2);

    let shutdown_executor = executor.clone();
    let shutdown_thread = thread::spawn(move || shutdown_executor.shutdown());
    wait_for_admission_closed(&executor);
    assert_eq!(
        executor.with_connection_for_tests(context(), |_connection| Ok::<_, _>(3_u8)),
        Err(SqliteExecutorError::Shutdown)
    );
    release.wait();

    assert_eq!(
        first_thread
            .join()
            .expect("first caller")
            .expect("first work"),
        1
    );
    assert_eq!(
        second_thread
            .join()
            .expect("second caller")
            .expect("second work"),
        2
    );
    shutdown_thread
        .join()
        .expect("shutdown caller")
        .expect("shutdown");
    executor.shutdown().expect("repeated shutdown");
    assert_eq!(*order.lock().expect("order lock"), vec![1, 2]);
    assert_eq!(
        executor.with_connection_for_tests(context(), |_connection| Ok::<_, _>(())),
        Err(SqliteExecutorError::Shutdown)
    );
}

#[test]
fn unit_of_work_commit_consumes_scope_and_preserves_context() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("uow.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    executor
        .with_unit_of_work(context(), |work| {
            assert_eq!(work.operation_context().trace_id(), context().trace_id());
            work.commit()?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("committed unit of work");
    executor.shutdown().expect("shutdown");
}

#[test]
fn unit_of_work_explicit_rollback_and_ok_without_commit_are_terminally_safe() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("uow-rollback.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    executor
        .with_unit_of_work(context(), |work| {
            work.rollback()?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("explicit rollback");
    executor
        .with_unit_of_work(context(), |_work| Ok::<_, ApplicationPortError>(()))
        .expect("uncommitted callback result");
    executor.shutdown().expect("shutdown");
}

#[test]
fn unit_of_work_callback_error_is_returned_without_implicit_commit() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("uow-error.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    let result = executor.with_unit_of_work(context(), |_work| {
        Err::<(), _>(ApplicationPortError::Persistence(
            PersistenceError::Conflict,
        ))
    });
    assert_eq!(
        result,
        Err(SqliteExecutorError::ApplicationCallback(
            ApplicationPortError::Persistence(PersistenceError::Conflict)
        ))
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn checksum_mismatch_unknown_version_and_malformed_history_are_rejected() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("history.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("initial open");
    executor.shutdown().expect("initial shutdown");
    let connection = rusqlite::Connection::open(&path).expect("reopen database");
    connection
        .execute(
            "UPDATE schema_migrations SET checksum = 'bad' WHERE version = 1",
            [],
        )
        .expect("tamper checksum");
    drop(connection);
    assert!(matches!(
        SqliteDatabaseExecutor::open(&path),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));

    let unknown_path = directory.path().join("unknown.sqlite3");
    let connection = rusqlite::Connection::open(&unknown_path).expect("unknown database");
    connection
        .execute_batch("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, checksum TEXT NOT NULL, applied_at TEXT NOT NULL, app_version TEXT NOT NULL); INSERT INTO schema_migrations VALUES (99, 'unknown', 'sql', 'bad', 'now', '0.1.0');")
        .expect("unknown history");
    drop(connection);
    assert!(matches!(
        SqliteDatabaseExecutor::open(&unknown_path),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));

    let malformed_path = directory.path().join("malformed.sqlite3");
    let connection = rusqlite::Connection::open(&malformed_path).expect("malformed database");
    connection
        .execute_batch("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, checksum TEXT NOT NULL, applied_at TEXT NOT NULL, app_version TEXT NOT NULL);")
        .expect("malformed history");
    drop(connection);
    assert!(matches!(
        SqliteDatabaseExecutor::open(&malformed_path),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));
}

#[test]
fn missing_historical_migration_is_rejected() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("missing.sqlite3");
    let connection = rusqlite::Connection::open(&path).expect("missing database");
    connection
        .execute_batch("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL, checksum TEXT NOT NULL, applied_at TEXT NOT NULL, app_version TEXT NOT NULL); INSERT INTO schema_migrations VALUES (2, 'second', 'sql', 'bad', 'now', '0.1.0');")
        .expect("history row");
    drop(connection);
    let registry = MigrationRegistry::new(vec![
        Migration::sql(1, "first", b"CREATE TABLE first (id INTEGER PRIMARY KEY);"),
        Migration::sql(
            2,
            "second",
            b"CREATE TABLE second (id INTEGER PRIMARY KEY);",
        ),
    ])
    .expect("registry");
    assert!(matches!(
        SqliteDatabaseExecutor::open_with_registry(&path, registry),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));
}

#[test]
fn migration_kind_mismatch_is_rejected() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("kind-mismatch.sqlite3");
    let sql_registry = MigrationRegistry::new(vec![Migration::sql(
        1,
        "first",
        b"CREATE TABLE first (id INTEGER PRIMARY KEY);",
    )])
    .expect("sql registry");
    let first = SqliteDatabaseExecutor::open_with_registry(&path, sql_registry).expect("open");
    first.shutdown().expect("first shutdown");
    let rust_registry = MigrationRegistry::new(vec![Migration::rust(
        1,
        "first",
        b"CREATE TABLE first (id INTEGER PRIMARY KEY);",
    )])
    .expect("rust registry");
    assert!(matches!(
        SqliteDatabaseExecutor::open_with_registry(&path, rust_registry),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));
}

#[test]
fn migration_name_mismatch_and_invalid_history_metadata_are_rejected() {
    let directory = tempdir().expect("temporary directory");
    let name_path = directory.path().join("name-mismatch.sqlite3");
    let registry = MigrationRegistry::new(vec![Migration::sql(
        1,
        "first",
        b"CREATE TABLE first (id INTEGER PRIMARY KEY);",
    )])
    .expect("registry");
    let executor = SqliteDatabaseExecutor::open_with_registry(&name_path, registry).expect("open");
    executor.shutdown().expect("shutdown");
    let connection = rusqlite::Connection::open(&name_path).expect("reopen");
    connection
        .execute(
            "UPDATE schema_migrations SET name = 'renamed' WHERE version = 1",
            [],
        )
        .expect("tamper name");
    drop(connection);
    assert!(matches!(
        SqliteDatabaseExecutor::open(&name_path),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));

    let metadata_path = directory.path().join("metadata.sqlite3");
    let initial = SqliteDatabaseExecutor::open(&metadata_path).expect("database");
    initial.shutdown().expect("shutdown");
    let connection = rusqlite::Connection::open(&metadata_path).expect("reopen");
    connection
        .execute_batch(
            "UPDATE schema_migrations SET applied_at = '', app_version = '' WHERE version = 1;",
        )
        .expect("tamper metadata");
    drop(connection);
    assert!(matches!(
        SqliteDatabaseExecutor::open(&metadata_path),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));
}

#[test]
fn infrastructure_implements_application_unit_of_work_factory() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("factory.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    let value = executor
        .execute(&context(), |work| {
            work.commit()?;
            Ok::<_, ApplicationPortError>(42_u32)
        })
        .expect("application callback");
    assert_eq!(value, 42);
    let failure = executor.execute(&context(), |_work| {
        Err::<(), _>(ApplicationPortError::Persistence(
            PersistenceError::Conflict,
        ))
    });
    assert_eq!(
        failure,
        Err(ApplicationPortError::Persistence(
            PersistenceError::Conflict
        ))
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn fresh_database_rejects_non_table_schema_objects() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("foreign-schema.sqlite3");
    let connection = rusqlite::Connection::open(&path).expect("database");
    connection
        .execute_batch(
            "CREATE TABLE foreign_table (id INTEGER PRIMARY KEY); CREATE VIEW foreign_view AS SELECT id FROM foreign_table; CREATE TRIGGER foreign_trigger AFTER INSERT ON foreign_table BEGIN SELECT 1; END;",
        )
        .expect("schema objects");
    drop(connection);
    assert!(matches!(
        SqliteDatabaseExecutor::open(&path),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));
}

#[test]
fn fresh_database_rejects_standalone_view_without_user_table() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("standalone-view.sqlite3");
    let connection = rusqlite::Connection::open(&path).expect("database");
    connection
        .execute_batch("CREATE VIEW foreign_view AS SELECT 1;")
        .expect("standalone view");
    drop(connection);
    assert!(matches!(
        SqliteDatabaseExecutor::open(&path),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));
}

#[cfg(feature = "test-support")]
#[test]
fn unexpected_worker_disconnect_maps_to_disconnected() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("disconnected.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&path).expect("open database");
    executor.disconnect_worker_for_tests();
    assert_eq!(
        executor.with_connection_for_tests(context(), |_connection| Ok::<_, _>(())),
        Err(SqliteExecutorError::Disconnected)
    );
    assert!(executor.wait_for_disconnected_for_tests(TEST_WAIT_TIMEOUT));
    assert_eq!(
        executor.with_connection_for_tests(context(), |_connection| Ok::<_, _>(())),
        Err(SqliteExecutorError::Disconnected)
    );
    executor.shutdown().expect("shutdown disconnected worker");
    assert_eq!(
        executor.with_connection_for_tests(context(), |_connection| Ok::<_, _>(())),
        Err(SqliteExecutorError::Shutdown)
    );
}

#[cfg(feature = "test-support")]
#[test]
fn final_migration_validation_failure_rolls_back_schema_and_history() {
    let directory = tempdir().expect("temporary directory");
    let path = directory.path().join("final-validation.sqlite3");
    let registry = MigrationRegistry::new(vec![Migration::sql(
        1,
        "pending",
        b"CREATE TABLE pending_table (id INTEGER PRIMARY KEY);",
    )])
    .expect("registry")
    .with_final_validation_failure_for_tests();
    assert!(matches!(
        SqliteDatabaseExecutor::open_with_registry(&path, registry),
        Err(SqliteExecutorError::IncompatibleSchema)
    ));
    let connection = rusqlite::Connection::open(&path).expect("reopen database");
    assert!(!connection
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'pending_table')",
            [],
            |row| row.get::<_, bool>(0),
        )
        .expect("pending table check"));
    assert!(!connection
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations')",
            [],
            |row| row.get::<_, bool>(0),
        )
        .expect("history table check"));
}
