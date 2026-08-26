//! Slice 006 infrastructure tests for Scan All persistence, request-identity
//! idempotency, bounded exclusion-error reconstruction, and recovery queries.

use argus_application::{
    ApplicationError, ErrorCode, FailureRole, JobRunId, JobRunRepository, JobRunState, JobsQueries,
    LibraryRootAvailability, LibraryRootId, LibraryRootRepository,
    LibraryScanAdmissionContextRepository, LibraryScanAllRequestIdentity,
    LibraryScanAllRequestLookup, LibraryScanInvocationKind, LibraryScanTargetKind,
    LibraryScanTargetRepository, LibrarySourceRepository, NewJobRun, NewLibraryRoot,
    NewLibraryScanAdmissionContext, NewLibraryScanTarget, NewScanRun, OperationContext,
    OperationDetail, OperationName, PersistenceError, RootLocator, SafeContext, SafeContextField,
    SafeContextValue, ScanRunRepository, ScanRunStatus, StaleLibraryScanQueries,
    StartLibraryScanAllResult, SubsystemName, TechnicalClass, TraceId, UnitOfWork,
    UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{
    Migration, MigrationRegistry, SqliteDatabaseExecutor, SqliteJobsQueries,
};

const ROOT_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const ROOT_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const ROOT_C: &str = "cccccccccccccccccccccccccccccccc";
const REMOVED_ROOT: &str = "dddddddddddddddddddddddddddddddd";
const JOB_A: &str = "11111111111111111111111111111111";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("infrastructure").expect("operation"),
    )
}

fn root_id(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("root id")
}

fn job_id(value: &str) -> JobRunId {
    JobRunId::try_from(value).expect("job id")
}

fn request_identity(value: &str) -> LibraryScanAllRequestIdentity {
    LibraryScanAllRequestIdentity::try_from(value).expect("request identity")
}

fn configuration_error(trace_id: TraceId) -> ApplicationError {
    let mut safe_context = SafeContext::new();
    safe_context
        .try_insert(
            SafeContextField::TechnicalClass,
            SafeContextValue::TechnicalClass(TechnicalClass::ConfigurationInvalid),
        )
        .expect("technical class");
    safe_context
        .try_insert(
            SafeContextField::FailureRole,
            SafeContextValue::FailureRole(FailureRole::Primary),
        )
        .expect("failure role");
    ApplicationError::from_code(ErrorCode::ConfigurationInvalid, trace_id, safe_context)
        .expect("configuration error")
}

fn old_registry_through_0006() -> MigrationRegistry {
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
        Migration::sql(
            6,
            "0006_retry_and_progress",
            include_bytes!("../src/sqlite/migrations/sql/0006_retry_and_progress.sql"),
        ),
    ])
    .expect("old registry")
}

#[test]
fn migration_0007_upgrades_0006_history_and_backfills_invalid_configuration_errors() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, old_registry_through_0006())
        .expect("old schema open");
    assert_eq!(old.migration_summary().current_version, 6);
    old.shutdown().expect("old shutdown");

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
                 created_at, updated_at)
             VALUES
                ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '33333333333333333333333333333333',
                 '/library/A', 'A', '/library/A', 'available', 1, 'now', 'now');
             INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, started_at, completed_at,
                 cancellation_requested)
             VALUES
                ('11111111111111111111111111111111', 'library_scan', 'completed',
                 1000, 1001, 2000, 0);
             INSERT INTO library_scan_admission_context
                (job_run_id, invocation_kind, retry_source_job_run_id)
             VALUES ('11111111111111111111111111111111', 'initial_single_root', NULL);
             INSERT INTO scan_run
                (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                 root_display_name, safe_location_display, source_config_revision,
                 root_config_revision, status, started_at, completed_at)
             VALUES
                ('44444444444444444444444444444444', '11111111111111111111111111111111',
                 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '/library/A', 'A', '/library/A',
                 1, 1, 'complete', 1000, 2000);
             INSERT INTO library_scan_target
                (job_run_id, target_kind, historical_library_root_id, display_name,
                 safe_location_display, scan_run_id, exclusion_reason,
                 related_job_run_id, related_scan_run_id)
             VALUES
                ('11111111111111111111111111111111', 'requested',
                 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'A', '/library/A', NULL, NULL, NULL, NULL),
                ('11111111111111111111111111111111', 'admitted',
                 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'A', '/library/A',
                 '44444444444444444444444444444444', NULL, NULL, NULL),
                ('11111111111111111111111111111111', 'requested',
                 'dddddddddddddddddddddddddddddddd', 'Removed', '/library/Removed',
                 NULL, NULL, NULL, NULL),
                ('11111111111111111111111111111111', 'excluded',
                 'dddddddddddddddddddddddddddddddd', 'Removed', '/library/Removed',
                 NULL, 'invalid_configuration', NULL, NULL);",
        )
        .expect("seed old history");
    drop(connection);

    let fresh = SqliteDatabaseExecutor::open(&database).expect("upgraded open");
    assert_eq!(fresh.migration_summary().current_version, 12);
    assert_eq!(fresh.migration_summary().applied_count, 6);

    let detail = SqliteJobsQueries::new(fresh.clone())
        .get_job(&context(), job_id(JOB_A))
        .expect("get job")
        .expect("known job");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(operation.requested_roots().len(), 2);
    assert_eq!(operation.admitted_roots().len(), 1);
    assert_eq!(
        operation.admitted_roots()[0].library_root_id(),
        root_id(ROOT_A)
    );
    assert_eq!(operation.exclusions().len(), 1);
    let exclusion = &operation.exclusions()[0];
    assert_eq!(exclusion.library_root_id(), root_id(REMOVED_ROOT));
    let error = exclusion.application_error().expect("backfilled error");
    assert_eq!(error.code, ErrorCode::ConfigurationInvalid);
    assert_eq!(
        error.safe_context.get(&SafeContextField::TechnicalClass),
        Some(&SafeContextValue::TechnicalClass(
            TechnicalClass::ConfigurationInvalid
        ))
    );
    fresh.shutdown().expect("fresh shutdown");
}

#[test]
fn scan_all_request_identity_lookup_resolves_existing_admission_and_is_unique() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let identity = request_identity("scan-all-1");
    let identity_for_closure = identity.clone();

    let (job, root) = executor
        .execute(&context(), move |mut scope| {
            let source = scope.library_source().ensure_local_filesystem_source()?;
            let root = scope.library_roots().insert(NewLibraryRoot::new(
                source,
                RootLocator::from_provider("/library/A".to_owned()),
                "A".to_owned(),
                "/library/A".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            scope.library_scan_admission_context().insert(
                NewLibraryScanAdmissionContext::with_scan_all_request_identity(
                    job,
                    LibraryScanInvocationKind::InitialScanAll,
                    None,
                    identity_for_closure,
                ),
            )?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/A".to_owned()),
                "A".to_owned(),
                "/library/A".to_owned(),
                1,
                1,
                1_000,
            ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job,
                    LibraryScanTargetKind::Requested,
                    root,
                    "A",
                    "/library/A",
                    None,
                    None,
                ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job,
                    LibraryScanTargetKind::Admitted,
                    root,
                    "A",
                    "/library/A",
                    Some(scan),
                    None,
                ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job,
                    LibraryScanTargetKind::Excluded,
                    root_id(REMOVED_ROOT),
                    "Removed",
                    "/library/Removed",
                    None,
                    Some(
                        argus_application::LibraryScanAdmissionExclusion::invalid_configuration(
                            root_id(REMOVED_ROOT),
                            configuration_error(context().trace_id()),
                        ),
                    ),
                ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((job, root))
        })
        .expect("scan all admission");

    let queries = SqliteJobsQueries::new(executor.clone());
    let found = queries
        .find_existing(&context(), &identity)
        .expect("lookup")
        .expect("accepted admission");
    let StartLibraryScanAllResult::Admitted {
        operation_handle,
        admitted_roots,
        exclusions,
    } = found
    else {
        panic!("expected admitted scan all");
    };
    assert_eq!(operation_handle.job_run_id(), job);
    assert_eq!(admitted_roots, vec![root]);
    assert_eq!(exclusions.len(), 1);
    assert_eq!(
        exclusions[0].application_error().expect("error").code,
        ErrorCode::ConfigurationInvalid
    );

    let duplicate = executor
        .execute(&context(), move |mut scope| {
            let new_job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 2_000))?;
            let result = scope.library_scan_admission_context().insert(
                NewLibraryScanAdmissionContext::with_scan_all_request_identity(
                    new_job,
                    LibraryScanInvocationKind::InitialScanAll,
                    None,
                    identity,
                ),
            );
            scope.rollback()?;
            Ok::<_, argus_application::ApplicationPortError>(result)
        })
        .expect("duplicate attempt");
    assert_eq!(duplicate, Err(PersistenceError::ConstraintViolation));
    executor.shutdown().expect("shutdown");
}

#[test]
fn historical_detail_survives_root_removal_and_orders_children_by_root_id() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");

    let (job, _scans) = executor
        .execute(&context(), move |mut scope| {
            scope.library_source().ensure_local_filesystem_source()?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            scope.library_scan_admission_context().insert(
                NewLibraryScanAdmissionContext::with_scan_all_request_identity(
                    job,
                    LibraryScanInvocationKind::InitialScanAll,
                    None,
                    request_identity("history-scan-all"),
                ),
            )?;
            let mut scans = Vec::new();
            for (id, name) in [(ROOT_C, "C"), (ROOT_A, "A"), (ROOT_B, "B")] {
                let root = root_id(id);
                let scan = scope.scan_runs().insert(NewScanRun::new(
                    job,
                    root,
                    RootLocator::from_provider(format!("/library/{name}")),
                    name,
                    format!("/library/{name}"),
                    1,
                    1,
                    1_000,
                ))?;
                scope
                    .library_scan_targets()
                    .insert(NewLibraryScanTarget::new(
                        job,
                        LibraryScanTargetKind::Requested,
                        root,
                        name,
                        format!("/library/{name}"),
                        None,
                        None,
                    ))?;
                scope
                    .library_scan_targets()
                    .insert(NewLibraryScanTarget::new(
                        job,
                        LibraryScanTargetKind::Admitted,
                        root,
                        name,
                        format!("/library/{name}"),
                        Some(scan),
                        None,
                    ))?;
                scans.push((root, scan));
            }
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((job, scans))
        })
        .expect("multi root admission");

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job)
        .expect("get job")
        .expect("known job");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    let ordered: Vec<LibraryRootId> = operation
        .scan_runs()
        .iter()
        .map(|run| run.library_root_id())
        .collect();
    assert_eq!(
        ordered,
        vec![root_id(ROOT_A), root_id(ROOT_B), root_id(ROOT_C)]
    );
    let admitted: Vec<LibraryRootId> = operation
        .admitted_roots()
        .iter()
        .map(|summary| summary.library_root_id())
        .collect();
    assert_eq!(
        admitted,
        vec![root_id(ROOT_A), root_id(ROOT_B), root_id(ROOT_C)]
    );
    assert!(operation.requested_roots().iter().any(|summary| {
        summary.library_root_id() == root_id(ROOT_A)
            && summary.display_name() == "A"
            && summary.safe_location_display() == "/library/A"
    }));
    executor.shutdown().expect("shutdown");
}

#[test]
fn stale_execution_query_distinguishes_parent_child_and_cancellation_facts() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");

    let (job, _running) = executor
        .execute(&context(), move |mut scope| {
            scope.library_source().ensure_local_filesystem_source()?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            scope
                .job_runs()
                .set_state(job, JobRunState::Running, 1_001)?;
            scope.library_scan_admission_context().insert(
                NewLibraryScanAdmissionContext::with_scan_all_request_identity(
                    job,
                    LibraryScanInvocationKind::InitialScanAll,
                    None,
                    request_identity("stale-scan-all"),
                ),
            )?;
            let running = scope.scan_runs().insert(NewScanRun::new(
                job,
                root_id(ROOT_A),
                RootLocator::from_provider("/library/A".to_owned()),
                "A".to_owned(),
                "/library/A".to_owned(),
                1,
                1,
                1_000,
            ))?;
            let complete = scope.scan_runs().insert(NewScanRun::new(
                job,
                root_id(ROOT_B),
                RootLocator::from_provider("/library/B".to_owned()),
                "B".to_owned(),
                "/library/B".to_owned(),
                1,
                1,
                1_000,
            ))?;
            scope
                .scan_runs()
                .set_status(complete, ScanRunStatus::Complete, Some(1_100), None)?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job,
                    LibraryScanTargetKind::Excluded,
                    root_id(ROOT_C),
                    "C",
                    "/library/C",
                    None,
                    Some(
                        argus_application::LibraryScanAdmissionExclusion::invalid_configuration(
                            root_id(ROOT_C),
                            configuration_error(context().trace_id()),
                        ),
                    ),
                ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((job, running))
        })
        .expect("stale fixture");

    let queries = SqliteJobsQueries::new(executor.clone());
    let stale = queries
        .list_stale_library_scan_jobs(&context())
        .expect("stale query");
    assert_eq!(stale.len(), 1);
    assert_eq!(stale[0].job_run_id(), job);
    assert_eq!(stale[0].state(), JobRunState::Running);
    assert!(!stale[0].cancellation_requested());
    let statuses: Vec<ScanRunStatus> = stale[0]
        .scan_runs()
        .iter()
        .map(|run| run.status())
        .collect();
    assert_eq!(
        statuses,
        vec![ScanRunStatus::Running, ScanRunStatus::Complete]
    );
    assert_eq!(stale[0].exclusions().len(), 1);
    executor.shutdown().expect("shutdown");
}
