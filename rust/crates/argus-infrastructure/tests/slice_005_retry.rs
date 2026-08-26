//! Slice 005 infrastructure tests: retry metadata, admission context,
//! structured progress counters, and migration upgrade integrity.

use argus_application::{JobRunId, JobsQueries, LibraryRootId};
use argus_application::{
    JobRunRepository, JobRunState, LibraryRootAvailability, LibraryRootRepository,
    LibraryScanAdmissionContext, LibraryScanAdmissionContextRepository, LibraryScanInvocationKind,
    LibraryScanTargetKind, LibraryScanTargetRepository, LibrarySourceRepository, NewJobRun,
    NewLibraryRoot, NewLibraryScanAdmissionContext, NewLibraryScanTarget, NewScanRun,
    OperationContext, OperationName, PersistenceError, RootLocator, ScanRunRepository,
    ScanRunStatus, SubsystemName, TraceId, UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{
    Migration, MigrationRegistry, SqliteDatabaseExecutor, SqliteJobsQueries,
};

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("infrastructure").expect("operation"),
    )
}

fn job_id(value: &str) -> JobRunId {
    JobRunId::try_from(value).expect("job id")
}

fn old_registry() -> MigrationRegistry {
    MigrationRegistry::new(vec![
        Migration::sql(
            1,
            "0001_initial",
            include_bytes!("../src/sqlite/migrations/sql/0001_initial.sql"),
        ),
        Migration::sql(
            2,
            "0002_sources",
            include_bytes!("../src/sqlite/migrations/sql/0002_sources.sql"),
        ),
        Migration::sql(
            3,
            "0003_jobs_scans",
            include_bytes!("../src/sqlite/migrations/sql/0003_jobs_scans.sql"),
        ),
        Migration::sql(
            4,
            "0004_source_reconciliation",
            include_bytes!("../src/sqlite/migrations/sql/0004_source_reconciliation.sql"),
        ),
        Migration::sql(
            5,
            "0005_source_hierarchy",
            include_bytes!("../src/sqlite/migrations/sql/0005_source_hierarchy.sql"),
        ),
    ])
    .expect("old registry")
}

#[test]
fn migration_0006_upgrades_a_slice_004_database_with_representative_history() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, old_registry())
        .expect("old schema open");
    assert_eq!(old.migration_summary().current_version, 5);
    old.shutdown().expect("old shutdown");
    let root = LibraryRootId::try_from("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").expect("root id");
    let job = JobRunId::try_from("11111111111111111111111111111111").expect("job id");
    let scan = argus_application::ScanRunId::try_from("44444444444444444444444444444444")
        .expect("scan id");
    let connection = rusqlite::Connection::open(&database).expect("raw old database");
    connection
        .execute_batch(
            "INSERT INTO library_source
                (library_source_id, source_provider_type, display_name, provider_config,
                 config_revision, created_at, updated_at)
             VALUES
                ('33333333333333333333333333333333', 'local_filesystem', 'Local Filesystem',
                 '{\"schema_version\":1,\"config\":{}}', 1, 'now', 'now');
             INSERT INTO library_root
                (library_root_id, library_source_id, root_locator, display_name,
                 safe_location_presentation, availability_status, config_revision,
                 created_at, updated_at, last_scan_status, last_scan_scan_run_id,
                 last_scan_job_run_id, last_scan_started_at, last_scan_completed_at)
             VALUES
                ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '33333333333333333333333333333333',
                 '/library/Games', 'Games', '/library/Games', 'available', 1,
                 'now', 'now', 'complete', '44444444444444444444444444444444',
                 '11111111111111111111111111111111', 1000, 2000);
             INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, started_at, completed_at,
                 cancellation_requested)
             VALUES
                ('11111111111111111111111111111111', 'library_scan', 'completed',
                 1000, 1000, 2000, 0);
             INSERT INTO scan_run
                (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                 root_display_name, safe_location_display, source_config_revision,
                 root_config_revision, status, started_at, completed_at)
             VALUES
                ('44444444444444444444444444444444', '11111111111111111111111111111111',
                 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '/library/Games', 'Games', '/library/Games',
                 1, 1, 'complete', 1000, 2000);
             INSERT INTO library_scan_target
                (job_run_id, target_kind, historical_library_root_id, display_name,
                 safe_location_display, scan_run_id, exclusion_reason,
                 related_job_run_id, related_scan_run_id)
             VALUES
                ('11111111111111111111111111111111', 'requested',
                 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Games', '/library/Games', NULL, NULL, NULL, NULL),
                ('11111111111111111111111111111111', 'admitted',
                 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Games', '/library/Games',
                 '44444444444444444444444444444444', NULL, NULL, NULL);",
        )
        .expect("seed old history");
    drop(connection);

    let fresh = SqliteDatabaseExecutor::open(&database).expect("upgraded open");
    assert_eq!(fresh.migration_summary().current_version, 12);
    assert_eq!(fresh.migration_summary().applied_count, 7);

    fresh
        .execute(&context(), move |mut scope| {
            let context = scope.library_scan_admission_context().get_by_job(job)?;
            assert_eq!(
                context,
                Some(LibraryScanAdmissionContext::new(
                    job,
                    LibraryScanInvocationKind::InitialSingleRoot,
                    None,
                ))
            );
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("upgrade assertions");

    let queries = SqliteJobsQueries::new(fresh.clone());
    let reference = queries
        .find_scan_admission_for_root(&context(), root)
        .expect("scan admission lookup");
    assert_eq!(reference.expect("reference").job_run_id(), job);
    assert_eq!(reference.expect("reference").scan_run_id(), scan);

    let detail = queries
        .get_job(&context(), job)
        .expect("detail")
        .expect("known job");
    assert!(!detail.job().controls().can_cancel());
    assert!(!detail.job().controls().can_retry());
    let argus_application::OperationDetail::LibraryScan(operation) = detail.operation_detail()
    else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(operation.retry_source_job_run_id(), None);
    assert_eq!(operation.retry_successor_job_run_id(), None);
    assert_eq!(operation.progress().entries_observed(), None);
    assert_eq!(operation.progress().entries_committed(), None);
    assert_eq!(operation.progress().issue_count(), None);
    fresh.shutdown().expect("fresh shutdown");
}

#[test]
fn retry_link_and_progress_facts_round_trip_with_integrity() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");

    let (_root, source_job, retry_job, _scan) = executor
        .execute(&context(), move |mut scope| {
            let source = scope.library_source().ensure_local_filesystem_source()?;
            let root = scope.library_roots().insert(NewLibraryRoot::new(
                source,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games".to_owned(),
                "/library/Games".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let source_job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            let retry_job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 2_000))?;
            scope
                .library_scan_admission_context()
                .insert(NewLibraryScanAdmissionContext::new(
                    source_job,
                    LibraryScanInvocationKind::InitialSingleRoot,
                    None,
                ))?;
            scope
                .library_scan_admission_context()
                .insert(NewLibraryScanAdmissionContext::new(
                    retry_job,
                    LibraryScanInvocationKind::RetrySingleRoot,
                    Some(source_job),
                ))?;
            scope.job_runs().insert_retry_link(source_job, retry_job)?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    retry_job,
                    LibraryScanTargetKind::Requested,
                    root,
                    "Games",
                    "/library/Games",
                    None,
                    None,
                ))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                retry_job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                2_000,
            ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    retry_job,
                    LibraryScanTargetKind::Admitted,
                    root,
                    "Games",
                    "/library/Games",
                    Some(scan),
                    None,
                ))?;
            scope.scan_runs().set_progress_facts(scan, 12, 10, 1)?;
            scope
                .job_runs()
                .set_state(source_job, JobRunState::Failed, 1_500)?;
            scope
                .job_runs()
                .set_state(retry_job, JobRunState::Failed, 2_500)?;
            scope
                .scan_runs()
                .set_status(scan, ScanRunStatus::Failed, Some(2_500), None)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((root, source_job, retry_job, scan))
        })
        .expect("retry fixture");

    let queries = SqliteJobsQueries::new(executor.clone());
    assert_eq!(
        queries
            .find_retry_successor(&context(), source_job)
            .expect("successor"),
        Some(retry_job)
    );
    let source_detail = queries
        .get_job(&context(), source_job)
        .expect("source detail")
        .expect("known job");
    assert!(
        !source_detail.job().controls().can_retry(),
        "a source run with a direct successor is not retryable"
    );
    let retry_detail = queries
        .get_job(&context(), retry_job)
        .expect("retry detail")
        .expect("known job");
    assert!(
        retry_detail.job().controls().can_retry(),
        "a terminal failed retry without successor and with an eligible root is retryable"
    );
    let argus_application::OperationDetail::LibraryScan(operation) =
        retry_detail.operation_detail()
    else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(operation.retry_source_job_run_id(), Some(source_job));
    assert_eq!(operation.retry_successor_job_run_id(), None);
    assert_eq!(operation.progress().entries_observed(), Some(12));
    assert_eq!(operation.progress().entries_committed(), Some(10));
    assert_eq!(operation.progress().issue_count(), Some(1));

    let duplicate_source = executor
        .execute(&context(), move |mut scope| {
            let link = scope.job_runs().insert_retry_link(source_job, retry_job);
            let _ = scope.rollback();
            Ok::<_, argus_application::ApplicationPortError>(link)
        })
        .expect("duplicate link attempt");
    assert_eq!(
        duplicate_source,
        Err(PersistenceError::ConstraintViolation),
        "one direct successor per source is enforced"
    );
    let foreign_key = executor
        .execute(&context(), move |mut scope| {
            let link = scope
                .job_runs()
                .insert_retry_link(source_job, job_id("dddddddddddddddddddddddddddddddd"));
            let _ = scope.rollback();
            Ok::<_, argus_application::ApplicationPortError>(link)
        })
        .expect("foreign key attempt");
    assert_eq!(
        foreign_key,
        Err(PersistenceError::ConstraintViolation),
        "successor job identity must reference an existing job run"
    );
    executor.shutdown().expect("shutdown");
}
