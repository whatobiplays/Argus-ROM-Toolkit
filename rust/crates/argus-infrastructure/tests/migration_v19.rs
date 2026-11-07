//! Forward migration coverage for durable Library refresh root manifests.

mod common;

use argus_application::{
    JobRunId, JobRunRepository, JobRunState, JobsQueries, LibraryRefreshRootOutcomeCoverage,
    LibraryRefreshTrigger, LibraryRootId, OperationContext, OperationDetail, OperationName,
    ScanRunId, SubsystemName, TraceId, UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{SqliteDatabaseExecutor, SqliteJobsQueries};
use rusqlite::Connection;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("infrastructure").expect("operation"),
    )
}

#[test]
fn job_run_operation_type_is_immutable_for_legacy_and_versioned_rows() {
    const LEGACY_REFRESH_JOB: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const LEGACY_SCAN_JOB: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const VERSIONED_REFRESH_JOB: &str = "cccccccccccccccccccccccccccccccc";

    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let v18 = SqliteDatabaseExecutor::open_with_registry(&database, common::registry_through(18))
        .expect("v18 database");
    v18.shutdown().expect("shutdown v18 database");

    let connection = Connection::open(&database).expect("seed v18 job history");
    connection
        .execute(
            "INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, queued_at)
             VALUES (?1, 'library_refresh', 'queued', 1, 1)",
            [LEGACY_REFRESH_JOB],
        )
        .expect("insert v18 LibraryRefresh job");
    connection
        .execute(
            "INSERT INTO library_refresh_intent
                (job_run_id, trigger_kind, trigger_root_id, mode)
             VALUES (?1, 'manual', NULL, 'eligible_only')",
            [LEGACY_REFRESH_JOB],
        )
        .expect("insert v18 refresh intent");
    connection
        .execute(
            "INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, queued_at)
             VALUES (?1, 'library_scan', 'queued', 1, 1)",
            [LEGACY_SCAN_JOB],
        )
        .expect("insert v18 LibraryScan job");
    drop(connection);

    let executor = SqliteDatabaseExecutor::open(&database).expect("upgrade to v19");
    let connection = Connection::open(&database).expect("inspect upgraded job history");
    connection
        .execute(
            "INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, queued_at,
                 library_refresh_scope_version)
             VALUES (?1, 'library_refresh', 'queued', 1, 1, 1)",
            [VERSIONED_REFRESH_JOB],
        )
        .expect("insert versioned refresh job");
    connection
        .execute(
            "INSERT INTO library_refresh_intent
                (job_run_id, trigger_kind, trigger_root_id, mode, requested_root_ids_json)
             VALUES (?1, 'manual', NULL, 'eligible_only', ?2)",
            rusqlite::params![
                VERSIONED_REFRESH_JOB,
                "[\"dddddddddddddddddddddddddddddddd\"]",
            ],
        )
        .expect("insert versioned refresh intent");

    for (job_run_id, replacement_operation) in [
        (LEGACY_SCAN_JOB, "library_refresh"),
        (LEGACY_REFRESH_JOB, "library_scan"),
        (VERSIONED_REFRESH_JOB, "library_scan"),
    ] {
        let update = connection.execute(
            "UPDATE job_run SET operation_type = ?1 WHERE job_run_id = ?2",
            rusqlite::params![replacement_operation, job_run_id],
        );
        assert!(
            update.is_err(),
            "operation type change for {job_run_id} must be rejected"
        );
    }

    for (job_run_id, expected_operation, expected_scope_version) in [
        (LEGACY_SCAN_JOB, "library_scan", 0),
        (LEGACY_REFRESH_JOB, "library_refresh", 0),
        (VERSIONED_REFRESH_JOB, "library_refresh", 1),
    ] {
        let row: (String, String, i64) = connection
            .query_row(
                "SELECT operation_type, state, library_refresh_scope_version
                 FROM job_run WHERE job_run_id = ?1",
                [job_run_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("read unchanged job identity");
        assert_eq!(row.0, expected_operation);
        assert_eq!(row.1, "queued");
        assert_eq!(row.2, expected_scope_version);

        let intent_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM library_refresh_intent WHERE job_run_id = ?1",
                [job_run_id],
                |row| row.get(0),
            )
            .expect("read unchanged refresh intent count");
        assert_eq!(
            intent_count,
            if expected_operation == "library_refresh" {
                1
            } else {
                0
            }
        );
    }
    let legacy_manifest: Option<String> = connection
        .query_row(
            "SELECT requested_root_ids_json FROM library_refresh_intent
             WHERE job_run_id = ?1",
            [LEGACY_REFRESH_JOB],
            |row| row.get(0),
        )
        .expect("read unchanged historical intent");
    assert_eq!(legacy_manifest, None);
    let versioned_manifest: Option<String> = connection
        .query_row(
            "SELECT requested_root_ids_json FROM library_refresh_intent
             WHERE job_run_id = ?1",
            [VERSIONED_REFRESH_JOB],
            |row| row.get(0),
        )
        .expect("read unchanged versioned intent");
    assert_eq!(
        versioned_manifest.as_deref(),
        Some("[\"dddddddddddddddddddddddddddddddd\"]")
    );
    drop(connection);

    executor
        .execute(&context(), move |mut scope| {
            let legacy_scan_job = JobRunId::try_from(LEGACY_SCAN_JOB).expect("legacy scan job id");
            let versioned_refresh_job =
                JobRunId::try_from(VERSIONED_REFRESH_JOB).expect("versioned refresh job id");
            assert!(
                scope
                    .job_runs()
                    .set_state(legacy_scan_job, JobRunState::Running, 2)?
            );
            assert!(
                scope
                    .job_runs()
                    .set_state(versioned_refresh_job, JobRunState::Running, 2)?
            );
            assert!(scope.job_runs().set_state(
                versioned_refresh_job,
                JobRunState::Completed,
                3
            )?);
            assert_eq!(
                scope.job_runs().request_cancellation(legacy_scan_job)?,
                Some(true)
            );
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("legitimate lifecycle update remains available");

    let connection = Connection::open(database).expect("verify lifecycle update");
    let legacy_state: (String, i64) = connection
        .query_row(
            "SELECT state, cancellation_requested FROM job_run WHERE job_run_id = ?1",
            [LEGACY_SCAN_JOB],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read legacy lifecycle state");
    assert_eq!(legacy_state, ("running".to_owned(), 1));
    let versioned_state: String = connection
        .query_row(
            "SELECT state FROM job_run WHERE job_run_id = ?1",
            [VERSIONED_REFRESH_JOB],
            |row| row.get(0),
        )
        .expect("read versioned terminal state");
    assert_eq!(versioned_state, "completed");
    executor.shutdown().expect("shutdown upgraded database");
}

#[test]
fn fresh_database_applies_v19_scope_schema() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("fresh database");
    executor.shutdown().expect("shutdown");

    let connection = Connection::open(database).expect("inspect database");
    let latest_migration: i64 = connection
        .query_row("SELECT MAX(version) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .expect("latest migration");
    assert_eq!(latest_migration, 19);
    for (table, column) in [
        ("job_run", "library_refresh_scope_version"),
        ("library_refresh_intent", "requested_root_ids_json"),
    ] {
        let present: bool = connection
            .query_row(
                "SELECT EXISTS(
                    SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2
                )",
                rusqlite::params![table, column],
                |row| row.get(0),
            )
            .expect("inspect migrated columns");
        assert!(present, "{table}.{column} is required by migration 19");
    }
}

#[test]
fn committed_scope_manifest_rejects_ordinary_update_and_delete() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("fresh database");
    executor.shutdown().expect("shutdown");

    let connection = Connection::open(database).expect("inspect database");
    connection
        .execute(
            "INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, queued_at,
                 library_refresh_scope_version)
             VALUES (?1, 'library_refresh', 'queued', 1, 1, 1)",
            ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
        )
        .expect("insert new-version refresh job");
    connection
        .execute(
            "INSERT INTO library_refresh_intent
                (job_run_id, trigger_kind, trigger_root_id, mode, requested_root_ids_json)
             VALUES (?1, 'manual', NULL, 'eligible_only', ?2)",
            rusqlite::params![
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "[\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"]",
            ],
        )
        .expect("insert committed scope manifest");

    let update = connection.execute(
        "UPDATE library_refresh_intent
         SET requested_root_ids_json = '[\"cccccccccccccccccccccccccccccccc\"]'
         WHERE job_run_id = ?1",
        ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
    );
    assert!(update.is_err(), "committed scope must reject updates");
    let delete = connection.execute(
        "DELETE FROM library_refresh_intent WHERE job_run_id = ?1",
        ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
    );
    assert!(delete.is_err(), "committed scope must reject deletion");
}

#[test]
fn new_scope_manifests_require_nonempty_sorted_unique_canonical_ids() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("fresh database");
    executor.shutdown().expect("shutdown");

    let connection = Connection::open(database).expect("inspect database");
    let invalid_manifests = [
        ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1", "[]"),
        (
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2",
            "[\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"]",
        ),
        (
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa3",
            "[\"cccccccccccccccccccccccccccccccc\",\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"]",
        ),
        (
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa4",
            "[\"not-a-canonical-root-id\"]",
        ),
        (
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa5",
            "[ \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\" ]",
        ),
        (
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa6",
            "[\"00000000000000000000000000000000\"]",
        ),
    ];
    for (job_run_id, manifest) in invalid_manifests {
        connection
            .execute(
                "INSERT INTO job_run
                    (job_run_id, operation_type, state, created_at, queued_at,
                     library_refresh_scope_version)
                 VALUES (?1, 'library_refresh', 'queued', 1, 1, 1)",
                [job_run_id],
            )
            .expect("insert versioned refresh parent");
        let insert = connection.execute(
            "INSERT INTO library_refresh_intent
                (job_run_id, trigger_kind, trigger_root_id, mode, requested_root_ids_json)
             VALUES (?1, 'manual', NULL, 'eligible_only', ?2)",
            rusqlite::params![job_run_id, manifest],
        );
        assert!(insert.is_err(), "manifest {manifest} must be rejected");
        let intent_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM library_refresh_intent WHERE job_run_id = ?1",
                [job_run_id],
                |row| row.get(0),
            )
            .expect("count rejected refresh intents");
        assert_eq!(intent_count, 0, "rejected manifest must not persist");
    }

    const VALID_JOB_RUN_ID: &str = "ffffffffffffffffffffffffffffffff";
    const VALID_MANIFEST: &str = "[\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"]";
    connection
        .execute(
            "INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, queued_at,
                 library_refresh_scope_version)
             VALUES (?1, 'library_refresh', 'queued', 1, 1, 1)",
            [VALID_JOB_RUN_ID],
        )
        .expect("insert versioned parent with nonzero job id");
    connection
        .execute(
            "INSERT INTO library_refresh_intent
                (job_run_id, trigger_kind, trigger_root_id, mode, requested_root_ids_json)
             VALUES (?1, 'manual', NULL, 'eligible_only', ?2)",
            rusqlite::params![VALID_JOB_RUN_ID, VALID_MANIFEST],
        )
        .expect("accept a valid nonzero root id");
    let persisted_manifest: String = connection
        .query_row(
            "SELECT requested_root_ids_json FROM library_refresh_intent WHERE job_run_id = ?1",
            [VALID_JOB_RUN_ID],
            |row| row.get(0),
        )
        .expect("read accepted manifest");
    assert_eq!(persisted_manifest, VALID_MANIFEST);
}

#[test]
fn upgrading_v18_preserves_job_facts_without_inventing_scope() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, common::registry_through(18))
        .expect("v18 database");
    old.shutdown().expect("shutdown v18 database");

    let job_run_id =
        JobRunId::try_from("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").expect("historical job id");
    let root_id =
        LibraryRootId::try_from("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb").expect("historical root id");
    let scan_run_id =
        ScanRunId::try_from("cccccccccccccccccccccccccccccccc").expect("historical scan id");
    let connection = Connection::open(&database).expect("seed v18 history");
    connection
        .execute(
            "INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, queued_at,
                 started_at, completed_at, current_phase)
             VALUES (?1, 'library_refresh', 'completed', 10000, 10000,
                     10000, 10001, 'library_refresh.completed')",
            [job_run_id.to_string()],
        )
        .expect("insert v18 parent job");
    connection
        .execute(
            "INSERT INTO library_refresh_intent
                (job_run_id, trigger_kind, trigger_root_id, mode)
             VALUES (?1, 'manual', NULL, 'eligible_only')",
            [job_run_id.to_string()],
        )
        .expect("insert v18 refresh intent");
    connection
        .execute(
            "INSERT INTO library_scan_admission_context
                (job_run_id, invocation_kind, retry_source_job_run_id,
                 scan_all_request_identity)
             VALUES (?1, 'initial_library_refresh', NULL, NULL)",
            [job_run_id.to_string()],
        )
        .expect("insert v18 admission context");
    connection
        .execute(
            "INSERT INTO scan_run
                (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                 root_display_name, safe_location_display, source_config_revision,
                 root_config_revision, status, started_at, completed_at,
                 entries_observed, entries_committed, issue_count)
             VALUES (?1, ?2, ?3, '/library/Legacy', 'Legacy', '/library/Legacy',
                     1, 1, 'complete', 10000, 10001, 1, 1, 0)",
            rusqlite::params![
                scan_run_id.to_string(),
                job_run_id.to_string(),
                root_id.to_string(),
            ],
        )
        .expect("insert v18 scan run");
    for (kind, scan_id) in [
        ("requested", None),
        ("admitted", Some(scan_run_id.to_string())),
    ] {
        connection
            .execute(
                "INSERT INTO library_scan_target
                    (job_run_id, target_kind, historical_library_root_id,
                     display_name, safe_location_display, scan_run_id,
                     exclusion_reason, related_job_run_id, related_scan_run_id,
                     exclusion_error_code, exclusion_error_trace_id,
                     exclusion_error_safe_context)
                 VALUES (?1, ?2, ?3, 'Legacy', '/library/Legacy', ?4,
                         NULL, NULL, NULL, NULL, NULL, NULL)",
                rusqlite::params![job_run_id.to_string(), kind, root_id.to_string(), scan_id,],
            )
            .expect("insert v18 scan target");
    }
    drop(connection);

    let upgraded = SqliteDatabaseExecutor::open(&database).expect("upgrade to v19");
    let detail = SqliteJobsQueries::new(upgraded.clone())
        .get_job(&context(), job_run_id)
        .expect("read upgraded historical detail")
        .expect("historical job remains present");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected Library refresh detail after migration");
    };
    assert_eq!(
        detail.job().state(),
        argus_application::JobRunState::Completed
    );
    assert_eq!(refresh.requested_root_ids(), &[root_id]);
    assert_eq!(refresh.scan_runs().len(), 1);
    assert_eq!(refresh.scan_runs()[0].scan_run_id(), scan_run_id);
    assert_eq!(refresh.trigger(), LibraryRefreshTrigger::Manual);
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::HistoricalUnavailable
    );
    upgraded.shutdown().expect("shutdown upgraded database");
}
