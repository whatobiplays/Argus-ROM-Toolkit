//! Slice 006 recovery tests: mandatory persistence-only startup reconciliation.

use std::path::Path;

use argus_application::{
    JobRunId, JobRunRepository, JobRunState, JobsQueries, LibraryRootAvailability, LibraryRootId,
    LibraryRootLastScanStatus, LibraryRootQueries, LibraryRootRepository,
    LibraryScanAdmissionContextRepository, LibraryScanAllRequestIdentity,
    LibraryScanInvocationKind, LibraryScanRecoveryHandler, LibraryScanTargetKind,
    LibraryScanTargetRepository, LibrarySourceRepository, NewJobRun, NewLibraryRoot,
    NewLibraryScanAdmissionContext, NewLibraryScanTarget, NewScanRun, OperationContext,
    OperationDetail, OperationName, RootLocator, ScanRunId, ScanRunRepository, ScanRunStatus,
    StaleLibraryScanQueries, SubsystemName, TraceId, UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{
    SqliteDatabaseExecutor, SqliteJobsQueries, SqliteLibraryRootQueries,
};
use argus_runtime::{ApplicationHost, KernelBootstrapOptions, RuntimeLifecycle};

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("recovery").expect("operation"),
    )
}

fn request_identity(value: &str) -> LibraryScanAllRequestIdentity {
    LibraryScanAllRequestIdentity::try_from(value).expect("request identity")
}

fn open_host(directory: &Path) -> ApplicationHost {
    ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.to_path_buf(),
    ))
}

fn make_active_job(
    executor: &SqliteDatabaseExecutor,
    cancellation: bool,
) -> (LibraryRootId, JobRunId, ScanRunId) {
    executor
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
            scope
                .job_runs()
                .set_state(job, JobRunState::Running, 1_001)?;
            scope.library_scan_admission_context().insert(
                NewLibraryScanAdmissionContext::with_scan_all_request_identity(
                    job,
                    LibraryScanInvocationKind::InitialScanAll,
                    None,
                    request_identity(&format!("recovery-{job}")),
                ),
            )?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/A".to_owned()),
                "A",
                "/library/A",
                1,
                1,
                1_001,
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
            if cancellation {
                scope.job_runs().request_cancellation(job)?;
            }
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((root, job, scan))
        })
        .expect("seed active job")
}

#[test]
fn recovery_abandons_running_children_without_cancellation_and_preserves_completed_work() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, job, _running) = make_active_job(&executor, false);
    executor
        .execute(&context(), move |mut scope| {
            let source = scope.library_source().ensure_local_filesystem_source()?;
            let completed_root = scope.library_roots().insert(NewLibraryRoot::new(
                source,
                RootLocator::from_provider("/library/B".to_owned()),
                "B".to_owned(),
                "/library/B".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let completed = scope.scan_runs().insert(NewScanRun::new(
                job,
                completed_root,
                RootLocator::from_provider("/library/B".to_owned()),
                "B",
                "/library/B",
                1,
                1,
                1_002,
            ))?;
            scope
                .scan_runs()
                .set_status(completed, ScanRunStatus::Complete, Some(1_003), None)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("seed completed child");

    LibraryScanRecoveryHandler::new(SqliteJobsQueries::new(executor.clone()), executor.clone())
        .handle(&context())
        .expect("recovery");

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job)
        .expect("get job")
        .expect("known job");
    assert_eq!(detail.job().state(), JobRunState::Abandoned);
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    let statuses: Vec<ScanRunStatus> = operation
        .scan_runs()
        .iter()
        .map(|run| run.status())
        .collect();
    assert!(statuses.contains(&ScanRunStatus::Abandoned));
    assert!(statuses.contains(&ScanRunStatus::Complete));

    let root_projection = SqliteLibraryRootQueries::new(executor.clone())
        .get(&context(), root)
        .expect("root query")
        .expect("known root");
    assert_eq!(
        root_projection.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Abandoned
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn recovery_honors_accepted_cancellation_and_derives_parent_from_terminal_children() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (_root, job, _running) = make_active_job(&executor, true);

    LibraryScanRecoveryHandler::new(SqliteJobsQueries::new(executor.clone()), executor.clone())
        .handle(&context())
        .expect("recovery");

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job)
        .expect("get job")
        .expect("known job");
    assert_eq!(detail.job().state(), JobRunState::Cancelled);
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    assert!(
        operation
            .scan_runs()
            .iter()
            .all(|run| run.status() == ScanRunStatus::Cancelled)
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn startup_reconciles_stale_scan_all_before_ready_without_provider_work() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = open_host(&directory.path().join("data"));
    host.initialize().expect("initial ready");
    host.general_shutdown().expect("initial shutdown");

    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("data").join("argus.sqlite3"))
            .expect("database");
    let (root, job, _scan) = make_active_job(&executor, false);
    executor.shutdown().expect("seed shutdown");

    let replacement = open_host(&directory.path().join("data"));
    assert_eq!(
        replacement.initialize().expect("ready").lifecycle(),
        RuntimeLifecycle::Ready
    );
    let detail = replacement.get_job(job).expect("recovered job");
    assert_eq!(detail.job().state(), JobRunState::Abandoned);
    let root_projection = replacement.get_library_root(root).expect("root");
    assert_eq!(
        root_projection.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Abandoned
    );
    replacement
        .general_shutdown()
        .expect("replacement shutdown");
}

#[test]
fn startup_recovery_failure_prevents_ready() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = open_host(&directory.path().join("data"));
    host.initialize().expect("initial ready");
    host.general_shutdown().expect("initial shutdown");

    let connection =
        rusqlite::Connection::open(directory.path().join("data").join("argus.sqlite3"))
            .expect("raw database");
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
                (job_run_id, operation_type, state, created_at, cancellation_requested)
             VALUES ('11111111111111111111111111111111', 'library_scan', 'running', 1000, 0);
             INSERT INTO library_scan_admission_context
                (job_run_id, invocation_kind, retry_source_job_run_id, scan_all_request_identity)
             VALUES ('11111111111111111111111111111111', 'initial_scan_all', NULL, 'startup-failure');
             INSERT INTO scan_run
                (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                 root_display_name, safe_location_display, source_config_revision,
                 root_config_revision, status, started_at)
             VALUES ('22222222222222222222222222222222', '11111111111111111111111111111111',
                 'not-a-root-id', '/library/A', 'A', '/library/A', 1, 1, 'running', 1000);",
        )
        .expect("seed corrupt stale job");
    drop(connection);

    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("data").join("argus.sqlite3"))
            .expect("database");
    assert!(
        SqliteJobsQueries::new(executor.clone())
            .list_stale_library_scan_jobs(&context())
            .is_err(),
        "malformed root id must fail the stale query"
    );
    executor.shutdown().expect("shutdown");

    let replacement = open_host(&directory.path().join("data"));
    assert_eq!(
        replacement
            .initialize()
            .expect("startup result")
            .lifecycle(),
        RuntimeLifecycle::StartupFailed
    );
}
