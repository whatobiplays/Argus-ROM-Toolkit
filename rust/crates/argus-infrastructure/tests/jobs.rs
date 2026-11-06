//! Slice 002 infrastructure integration tests for job/scan persistence and
//! the LocalFilesystem source access adapter.

mod common;

use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::{Duration, Instant};

use argus_application::LibrarySourceAccess;
use argus_application::{
    ActiveScanOwnership, ApplicationEvent, EventRecorder, EventRecordingError, JobProgress,
    JobRunRepository, JobRunState, LibraryRefreshAdmissionOutcome,
    LibraryRefreshRootOutcomeCoverage, LibraryRefreshTrigger, LibraryRootAvailability,
    LibraryRootId, LibraryRootLastScanStatus, LibraryRootLastScanSummary, LibraryRootRepository,
    LibraryScanAdmissionContextRepository, LibraryScanAdmissionExclusion,
    LibraryScanInvocationKind, LibraryScanTargetExclusionReason, LibraryScanTargetKind,
    LibraryScanTargetRepository, LibrarySourceRepository, NewJobRun, NewLibraryRoot,
    NewLibraryScanAdmissionContext, NewLibraryScanTarget, NewScanRun, NewSourceEntry,
    OperationContext, OperationDetail, OperationName, PersistenceError, RefreshLibraryCommand,
    RefreshMode, RelativeSourceLocator, RetryJobCommand, RetryJobHandler, RootLocator,
    ScanRunRepository, ScanRunStatus, SourceEntryClassification, SourceEntryKind,
    SourceEntryRepository, SourceLocatorKey, StartLibraryScanAllHandler, StartLibraryScanCommand,
    StartLibraryScanHandler, SubsystemName, TraceId, UnitOfWork, UnitOfWorkFactory,
};
use argus_application::{JobsQueries, LibraryRootQueries};
use argus_application::{ObservedEntryKind, SourceAccessError};
use argus_infrastructure::local_filesystem::LocalFilesystemSourceAccess;
use argus_infrastructure::sqlite::{
    SqliteDatabaseExecutor, SqliteJobsQueries, SqliteLibraryRootQueries, SqliteValue,
};
use rusqlite::Connection;

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

#[derive(Clone, Copy)]
struct IgnoreEvents;

impl EventRecorder for IgnoreEvents {
    fn record(&self, _event: ApplicationEvent) -> Result<(), EventRecordingError> {
        Ok(())
    }
}

#[derive(Clone, Copy)]
struct RejectEvents;

impl EventRecorder for RejectEvents {
    fn record(&self, _event: ApplicationEvent) -> Result<(), EventRecordingError> {
        Err(EventRecordingError::CapacityExceeded)
    }
}

fn insert_available_roots(
    executor: &SqliteDatabaseExecutor,
    roots: &[(&str, &str)],
) -> Vec<LibraryRootId> {
    let roots = roots
        .iter()
        .map(|(name, path)| ((*name).to_owned(), (*path).to_owned()))
        .collect::<Vec<_>>();
    executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let mut root_ids = Vec::with_capacity(roots.len());
            for (name, path) in roots {
                root_ids.push(scope.library_roots().insert(NewLibraryRoot::new(
                    source_id,
                    RootLocator::from_provider(path.clone()),
                    name.clone(),
                    path,
                    LibraryRootAvailability::Available,
                    1,
                ))?);
            }
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(root_ids)
        })
        .expect("insert configured roots")
}

fn start_active_scan(
    executor: &SqliteDatabaseExecutor,
    root_id: LibraryRootId,
    display_name: &'static str,
    path: &'static str,
) {
    executor
        .execute(&context(), move |mut scope| {
            let now = 50_000;
            let job_run_id = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", now))?;
            let scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                job_run_id,
                root_id,
                RootLocator::from_provider(path.to_owned()),
                display_name,
                path,
                1,
                1,
                now,
            ))?;
            scope.scan_runs().set_status(
                scan_run_id,
                ScanRunStatus::Running,
                Some(now + 1),
                None,
            )?;
            scope
                .job_runs()
                .set_state(job_run_id, JobRunState::Running, now + 1)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("start active scan");
}

#[derive(Clone, Copy)]
struct RefreshFixture {
    job_run_id: argus_application::JobRunId,
    admitted_root_id: LibraryRootId,
    excluded_root_id: LibraryRootId,
    scan_run_id: argus_application::ScanRunId,
}

fn seed_refresh_with_admitted_and_excluded_roots(
    executor: &SqliteDatabaseExecutor,
    now: i64,
) -> RefreshFixture {
    let fixture = executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let admitted_root_id = scope.library_roots().insert(NewLibraryRoot::new(
                source_id,
                RootLocator::from_provider("/library/Admitted".to_owned()),
                "Admitted".to_owned(),
                "/library/Admitted".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let excluded_root_id = scope.library_roots().insert(NewLibraryRoot::new(
                source_id,
                RootLocator::from_provider("/library/Excluded".to_owned()),
                "Excluded".to_owned(),
                "/library/Excluded".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let job_run_id = scope
                .job_runs()
                .insert(NewJobRun::new("library_refresh", now))?;
            scope.job_runs().insert_library_refresh_intent(
                job_run_id,
                LibraryRefreshTrigger::Manual,
                RefreshMode::EligibleOnly,
                &[admitted_root_id, excluded_root_id],
            )?;
            scope
                .library_scan_admission_context()
                .insert(NewLibraryScanAdmissionContext::new(
                    job_run_id,
                    LibraryScanInvocationKind::InitialLibraryRefresh,
                    None,
                ))?;
            let scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                job_run_id,
                admitted_root_id,
                RootLocator::from_provider("/library/Admitted".to_owned()),
                "Admitted",
                "/library/Admitted",
                1,
                1,
                now,
            ))?;
            scope.scan_runs().set_status(
                scan_run_id,
                ScanRunStatus::Running,
                Some(now + 1),
                None,
            )?;
            for (root_id, display_name, path) in [
                (admitted_root_id, "Admitted", "/library/Admitted"),
                (excluded_root_id, "Excluded", "/library/Excluded"),
            ] {
                scope
                    .library_scan_targets()
                    .insert(NewLibraryScanTarget::new(
                        job_run_id,
                        LibraryScanTargetKind::Requested,
                        root_id,
                        display_name,
                        path,
                        None,
                        None,
                    ))?;
            }
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job_run_id,
                    LibraryScanTargetKind::Admitted,
                    admitted_root_id,
                    "Admitted",
                    "/library/Admitted",
                    Some(scan_run_id),
                    None,
                ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job_run_id,
                    LibraryScanTargetKind::Excluded,
                    excluded_root_id,
                    "Excluded",
                    "/library/Excluded",
                    None,
                    Some(LibraryScanAdmissionExclusion::new(
                        excluded_root_id,
                        LibraryScanTargetExclusionReason::NoLongerConfigured,
                        None,
                        None,
                    )),
                ))?;
            scope
                .job_runs()
                .set_state(job_run_id, JobRunState::Running, now + 1)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(RefreshFixture {
                job_run_id,
                admitted_root_id,
                excluded_root_id,
                scan_run_id,
            })
        })
        .expect("seed Library refresh");
    fixture
}

fn delete_refresh_target(
    executor: &SqliteDatabaseExecutor,
    fixture: RefreshFixture,
    root_id: LibraryRootId,
    kind: &'static str,
) {
    let changed = executor
        .with_connection_for_tests(context(), move |connection| {
            connection.execute_with_values(
                "DELETE FROM library_scan_target
                 WHERE job_run_id = ?1 AND target_kind = ?2
                   AND historical_library_root_id = ?3",
                &[
                    SqliteValue::Text(fixture.job_run_id.to_string()),
                    SqliteValue::Text(kind.to_owned()),
                    SqliteValue::Text(root_id.to_string()),
                ],
            )
        })
        .expect("delete test target");
    assert_eq!(changed, 1, "expected one {kind} target row to be deleted");
}

fn persist_added_root_trigger_for_integrity_test(
    database: &Path,
    fixture: RefreshFixture,
    trigger_root_id: LibraryRootId,
) {
    let connection = Connection::open(database).expect("open integrity fixture");
    connection
        .execute_batch("DROP TRIGGER library_refresh_scope_manifest_immutable_update;")
        .expect("disable immutable-intent guard for corruption fixture");
    connection
        .execute(
            "UPDATE library_refresh_intent
             SET trigger_kind = 'added_root', trigger_root_id = ?1
             WHERE job_run_id = ?2",
            rusqlite::params![trigger_root_id.to_string(), fixture.job_run_id.to_string()],
        )
        .expect("write contradictory trigger evidence");
}

#[test]
fn job_scan_target_and_entry_records_persist_and_survive_restart() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let now = 1_000;

    let (configured_root_id, job_run_id, scan_run_id) = executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let configured_root_id = scope.library_roots().insert(NewLibraryRoot::new(
                source_id,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games".to_owned(),
                "/library/Games".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let job_run_id = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", now))?;
            let scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                job_run_id,
                configured_root_id,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                now,
            ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job_run_id,
                    LibraryScanTargetKind::Requested,
                    configured_root_id,
                    "Games",
                    "/library/Games",
                    None,
                    None,
                ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    job_run_id,
                    LibraryScanTargetKind::Admitted,
                    configured_root_id,
                    "Games",
                    "/library/Games",
                    Some(scan_run_id),
                    None,
                ))?;
            scope
                .job_runs()
                .set_state(job_run_id, JobRunState::Running, now + 1)?;
            let progress = JobProgress::new(
                job_run_id,
                "discovering",
                Some(1),
                None,
                Some("library_scan.discovering"),
                now + 2,
            )
            .expect("progress");
            scope.job_runs().set_progress(job_run_id, &progress)?;
            scope.source_entries().upsert(NewSourceEntry::new(
                configured_root_id,
                None,
                RelativeSourceLocator::from_provider("rom.bin".to_owned()),
                SourceLocatorKey::from_provider("rom.bin".to_owned()),
                "rom.bin",
                "rom.bin",
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                None,
                None,
                scan_run_id,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((
                configured_root_id,
                job_run_id,
                scan_run_id,
            ))
        })
        .expect("admission transaction");

    let ownership = executor
        .execute(&context(), move |mut scope| {
            let ownership = scope
                .scan_runs()
                .find_active_ownership(configured_root_id)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(ownership)
        })
        .expect("ownership read")
        .expect("active ownership");
    assert_eq!(
        ownership,
        ActiveScanOwnership::new(job_run_id, scan_run_id, 1)
    );

    let active_detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job_run_id)
        .expect("get active job")
        .expect("active job detail");
    assert!(active_detail.job().controls().can_cancel());

    executor
        .execute(&context(), move |mut scope| {
            scope.scan_runs().set_status(
                scan_run_id,
                ScanRunStatus::Complete,
                Some(now + 3),
                None,
            )?;
            scope
                .job_runs()
                .set_state(job_run_id, JobRunState::Completed, now + 3)?;
            scope.library_roots().set_last_scan(
                configured_root_id,
                Some(LibraryRootLastScanSummary::new(
                    scan_run_id.to_string(),
                    job_run_id.to_string(),
                    LibraryRootLastScanStatus::Complete,
                    now,
                    Some(now + 3),
                )),
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("terminalization");
    executor.shutdown().expect("shutdown");

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopened");
    let detail = SqliteJobsQueries::new(reopened.clone())
        .get_job(&context(), job_run_id)
        .expect("get job")
        .expect("job detail");
    assert_eq!(detail.job().state(), JobRunState::Completed);
    assert_eq!(detail.job().completed_units(), Some(1));
    assert!(!detail.job().controls().can_cancel());
    let OperationDetail::LibraryScan(scan_detail) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(scan_detail.scan_runs().len(), 1);
    assert_eq!(scan_detail.requested_roots().len(), 1);
    assert_eq!(scan_detail.admitted_roots().len(), 1);

    let active = SqliteJobsQueries::new(reopened.clone())
        .list_active(&context())
        .expect("active list");
    assert!(active.is_empty());
    let recent = SqliteJobsQueries::new(reopened.clone())
        .list_recent_terminal(&context(), 0, 20)
        .expect("recent list");
    assert_eq!(recent.total_count(), 1);
    assert_eq!(recent.items()[0].job_run_id(), job_run_id);
    assert_eq!(recent.next_offset(), None);

    let root_projection = SqliteLibraryRootQueries::new(reopened.clone())
        .get(&context(), configured_root_id)
        .expect("root projection")
        .expect("configured");
    let last_scan = root_projection.last_scan().expect("last scan");
    assert_eq!(last_scan.status(), LibraryRootLastScanStatus::Complete);
    reopened.shutdown().expect("shutdown");
}

#[test]
fn failed_library_refresh_child_reasons_survive_reopen_in_job_detail_projection() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let now = 2_000;

    let (job_run_id, mut expected_scans) = executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let job_run_id = scope
                .job_runs()
                .insert(NewJobRun::new("library_refresh", now))?;

            let mut expected_scans = Vec::new();
            for (display_name, safe_location, status, reason) in [
                (
                    "Games",
                    "/library/Games",
                    ScanRunStatus::Failed,
                    Some("execution_host_timeout"),
                ),
                (
                    "ROMs",
                    "/library/ROMs",
                    ScanRunStatus::Partial,
                    Some("incomplete_scope"),
                ),
                ("BIOS", "/library/BIOS", ScanRunStatus::Failed, None),
                (
                    "Extras",
                    "/library/Extras",
                    ScanRunStatus::Failed,
                    Some("/private/test/path SELECT * FROM credentials"),
                ),
            ] {
                let root_id = scope.library_roots().insert(NewLibraryRoot::new(
                    source_id,
                    RootLocator::from_provider(safe_location.to_owned()),
                    display_name.to_owned(),
                    safe_location.to_owned(),
                    LibraryRootAvailability::Available,
                    1,
                ))?;
                let scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                    job_run_id,
                    root_id,
                    RootLocator::from_provider(safe_location.to_owned()),
                    display_name,
                    safe_location,
                    1,
                    1,
                    now,
                ))?;
                scope
                    .library_scan_targets()
                    .insert(NewLibraryScanTarget::new(
                        job_run_id,
                        LibraryScanTargetKind::Requested,
                        root_id,
                        display_name,
                        safe_location,
                        None,
                        None,
                    ))?;
                scope
                    .library_scan_targets()
                    .insert(NewLibraryScanTarget::new(
                        job_run_id,
                        LibraryScanTargetKind::Admitted,
                        root_id,
                        display_name,
                        safe_location,
                        Some(scan_run_id),
                        None,
                    ))?;
                expected_scans.push((
                    root_id,
                    scan_run_id,
                    display_name.to_owned(),
                    status,
                    reason.map(str::to_owned),
                ));
            }

            let requested_root_ids = expected_scans
                .iter()
                .map(|(root_id, _, _, _, _)| *root_id)
                .collect::<Vec<_>>();
            scope.job_runs().insert_library_refresh_intent(
                job_run_id,
                LibraryRefreshTrigger::Manual,
                RefreshMode::EligibleOnly,
                &requested_root_ids,
            )?;

            scope
                .job_runs()
                .set_state(job_run_id, JobRunState::Running, now + 1)?;
            let progress = JobProgress::new(
                job_run_id,
                "library_refresh.completed",
                Some(4),
                Some(4),
                Some("library_refresh.completed"),
                now + 2,
            )
            .expect("refresh progress");
            scope.job_runs().set_progress(job_run_id, &progress)?;
            for (_, scan_run_id, _, status, reason) in &expected_scans {
                scope.scan_runs().set_status(
                    *scan_run_id,
                    *status,
                    Some(now + 2),
                    reason.clone(),
                )?;
            }
            scope.job_runs().set_terminal_failure(
                job_run_id,
                JobRunState::Failed,
                Some("ARGUS.V1.RUNTIME.STALE_INSTANCE".to_owned()),
                Some("parent bounded failure context".to_owned()),
                now + 3,
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((job_run_id, expected_scans))
        })
        .expect("failed historical scan");
    executor.shutdown().expect("shutdown");
    expected_scans.sort_by_key(|(root_id, _, _, _, _)| root_id.to_string());

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopened");
    let detail = SqliteJobsQueries::new(reopened.clone())
        .get_job(&context(), job_run_id)
        .expect("get job")
        .expect("job detail");
    assert_eq!(detail.job().state(), JobRunState::Failed);
    assert_eq!(
        detail.job().terminal_error_code(),
        Some("ARGUS.V1.RUNTIME.STALE_INSTANCE")
    );
    assert_eq!(
        detail.job().terminal_safe_context(),
        Some("parent bounded failure context")
    );
    assert_eq!(detail.job().phase(), Some("library_refresh.completed"));
    assert_eq!(detail.job().status_key(), Some("library_refresh.completed"));
    assert!(!detail.job().controls().can_retry());
    let OperationDetail::LibraryRefresh(refresh_detail) = detail.operation_detail() else {
        panic!("expected library refresh operation detail");
    };
    assert_eq!(
        refresh_detail.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::Complete
    );
    assert_eq!(refresh_detail.scan_runs().len(), expected_scans.len());
    for (scan, expected) in refresh_detail.scan_runs().iter().zip(expected_scans) {
        assert_eq!(scan.library_root_id(), expected.0);
        assert_eq!(scan.scan_run_id(), expected.1);
        assert_eq!(scan.display_name(), expected.2);
        assert_eq!(scan.status(), expected.3);
        assert_eq!(scan.failure_reason(), expected.4.as_deref());
    }
    reopened.shutdown().expect("shutdown");
}

#[test]
fn historical_library_refresh_does_not_advertise_retry() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let old = SqliteDatabaseExecutor::open_with_registry(&database, common::registry_through(18))
        .expect("v18 database");
    let root_id = insert_available_roots(&old, &[("Legacy", "/library/Legacy")])[0];
    old.shutdown().expect("shutdown v18 database");

    let job_run_id = argus_application::JobRunId::try_from("11111111111111111111111111111111")
        .expect("historical job id");
    let scan_run_id = argus_application::ScanRunId::try_from("22222222222222222222222222222222")
        .expect("historical scan id");
    let connection = Connection::open(&database).expect("seed v18 history");
    connection
        .execute(
            "INSERT INTO job_run
                (job_run_id, operation_type, state, created_at, queued_at,
                 started_at, completed_at, current_phase)
             VALUES (?1, 'library_refresh', 'failed', 10000, 10000,
                     10000, 10001, 'library_refresh.failed')",
            [job_run_id.to_string()],
        )
        .expect("insert v18 refresh job");
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
                 root_config_revision, status, started_at, completed_at)
             VALUES (?1, ?2, ?3, '/library/Legacy', 'Legacy', '/library/Legacy',
                     1, 1, 'failed', 10000, 10001)",
            rusqlite::params![
                scan_run_id.to_string(),
                job_run_id.to_string(),
                root_id.to_string()
            ],
        )
        .expect("insert v18 scan run");
    for (kind, target_scan_run_id) in [
        ("requested", None),
        ("admitted", Some(scan_run_id.to_string())),
    ] {
        connection
            .execute(
                "INSERT INTO library_scan_target
                    (job_run_id, target_kind, historical_library_root_id,
                     display_name, safe_location_display, scan_run_id,
                     exclusion_reason, related_job_run_id, related_scan_run_id)
                 VALUES (?1, ?2, ?3, 'Legacy', '/library/Legacy', ?4, NULL, NULL, NULL)",
                rusqlite::params![
                    job_run_id.to_string(),
                    kind,
                    root_id.to_string(),
                    target_scan_run_id,
                ],
            )
            .expect("insert v18 scan target");
    }
    drop(connection);

    let upgraded = SqliteDatabaseExecutor::open(&database).expect("upgrade to v19");
    let detail = SqliteJobsQueries::new(upgraded.clone())
        .get_job(&context(), job_run_id)
        .expect("get legacy refresh")
        .expect("legacy refresh detail");
    assert_eq!(detail.job().state(), JobRunState::Failed);
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected LibraryRefresh detail");
    };
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::HistoricalUnavailable
    );
    assert_eq!(refresh.requested_root_ids(), &[root_id]);
    assert!(
        !detail.job().controls().can_retry(),
        "legacy refresh with surviving eligible targets cannot advertise Retry"
    );
    upgraded.shutdown().expect("shutdown");
}

#[test]
fn concrete_sqlite_adapter_does_not_admit_library_refresh_retry() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 3_500);
    let active_detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), fixture.job_run_id)
        .expect("get active refresh")
        .expect("active refresh detail");
    assert!(active_detail.job().controls().can_cancel());
    executor
        .execute(&context(), move |mut scope| {
            scope.scan_runs().set_status(
                fixture.scan_run_id,
                ScanRunStatus::Failed,
                Some(3_601),
                None,
            )?;
            scope.job_runs().set_terminal_failure(
                fixture.job_run_id,
                JobRunState::Failed,
                Some("ARGUS.V1.RUNTIME.STALE_INSTANCE".to_owned()),
                Some("refresh failed".to_owned()),
                3_602,
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("fail refresh job");

    let queries = SqliteJobsQueries::new(executor.clone());
    let detail = queries
        .get_job(&context(), fixture.job_run_id)
        .expect("get complete refresh")
        .expect("complete refresh detail");
    assert!(!detail.job().controls().can_cancel());
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected LibraryRefresh detail");
    };
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::Complete
    );
    assert!(!detail.job().controls().can_retry());
    assert_eq!(
        queries
            .list_requested_library_scan_targets(&context(), fixture.job_run_id)
            .expect("query refresh retry targets"),
        None
    );

    let job_run_count = || {
        Connection::open(&database)
            .expect("open database for job count")
            .query_row("SELECT COUNT(*) FROM job_run", [], |row| {
                row.get::<_, i64>(0)
            })
            .expect("count job runs")
    };
    let before_retry = job_run_count();
    let result = RetryJobHandler::new(queries.clone(), executor.clone()).handle(
        RetryJobCommand::new(fixture.job_run_id),
        context(),
        IgnoreEvents,
    );
    assert!(result.is_err(), "unsupported refresh Retry is not admitted");
    assert_eq!(
        queries
            .find_retry_successor(&context(), fixture.job_run_id)
            .expect("read refresh successor"),
        None
    );
    assert_eq!(job_run_count(), before_retry);
    executor.shutdown().expect("shutdown");
}

#[test]
fn library_refresh_detail_preserves_known_exclusions_with_complete_scope() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 3_000);

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), fixture.job_run_id)
        .expect("get job")
        .expect("job detail");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected Library refresh detail");
    };

    assert!(
        refresh
            .requested_root_ids()
            .contains(&fixture.admitted_root_id)
    );
    assert!(
        refresh
            .requested_root_ids()
            .contains(&fixture.excluded_root_id)
    );
    assert_eq!(refresh.scan_runs().len(), 1);
    assert_eq!(refresh.scan_runs()[0].scan_run_id(), fixture.scan_run_id);
    assert_eq!(refresh.exclusions().len(), 1);
    assert_eq!(
        refresh.exclusions()[0].library_root_id(),
        fixture.excluded_root_id
    );
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::Complete
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn library_refresh_manifest_rejects_a_root_missing_both_requested_and_excluded_rows() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 4_000);
    delete_refresh_target(&executor, fixture, fixture.excluded_root_id, "requested");
    delete_refresh_target(&executor, fixture, fixture.excluded_root_id, "excluded");

    let result = SqliteJobsQueries::new(executor.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    executor.shutdown().expect("shutdown");
}

#[test]
fn admitted_single_root_refresh_has_complete_scope_coverage() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let [root_id] = insert_available_roots(&executor, &[("Added", "/library/Added")])[..] else {
        panic!("one root was inserted");
    };

    let admission = StartLibraryScanHandler::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        executor.clone(),
    )
    .handle_with_operation_type(
        StartLibraryScanCommand::new(root_id),
        context(),
        IgnoreEvents,
        "library_refresh",
    )
    .expect("admit single-root refresh");
    let job_run_id = admission
        .admitted_scan()
        .expect("refresh job is admitted")
        .job_run_id();

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job_run_id)
        .expect("get job")
        .expect("job detail");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected Library refresh detail");
    };
    assert_eq!(refresh.requested_root_ids(), &[root_id]);
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::Complete
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn missing_manifest_for_new_refresh_is_a_typed_integrity_error() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let [root_id] = insert_available_roots(&executor, &[("Added", "/library/Added")])[..] else {
        panic!("one root was inserted");
    };
    let admission = StartLibraryScanHandler::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        executor.clone(),
    )
    .handle_with_operation_type(
        StartLibraryScanCommand::new(root_id),
        context(),
        IgnoreEvents,
        "library_refresh",
    )
    .expect("admit single-root refresh");
    let job_run_id = admission
        .admitted_scan()
        .expect("refresh job is admitted")
        .job_run_id();
    executor
        .shutdown()
        .expect("shutdown before corruption fixture");

    let connection = Connection::open(&database).expect("open corruption fixture");
    connection
        .execute(
            "DROP TRIGGER IF EXISTS library_refresh_scope_manifest_prevent_delete",
            [],
        )
        .expect("remove manifest protection for corruption fixture");
    connection
        .execute(
            "DELETE FROM library_refresh_intent WHERE job_run_id = ?1",
            [job_run_id.to_string()],
        )
        .expect("remove required manifest to simulate corruption");
    drop(connection);

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopen corrupted database");
    let result = SqliteJobsQueries::new(reopened.clone()).get_job(&context(), job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    reopened.shutdown().expect("shutdown");
}

#[test]
fn duplicate_manifest_id_is_rejected_as_corrupt_scope() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 4_500);
    executor
        .shutdown()
        .expect("shutdown before corruption fixture");

    let connection = Connection::open(&database).expect("open corruption fixture");
    connection
        .execute(
            "DROP TRIGGER library_refresh_scope_manifest_immutable_update",
            [],
        )
        .expect("remove manifest protection for corruption fixture");
    connection
        .execute(
            "UPDATE library_refresh_intent
             SET requested_root_ids_json = ?1
             WHERE job_run_id = ?2",
            rusqlite::params![
                format!(
                    "[\"{}\",\"{}\"]",
                    fixture.admitted_root_id, fixture.admitted_root_id,
                ),
                fixture.job_run_id.to_string(),
            ],
        )
        .expect("write duplicate IDs to corruption fixture");
    drop(connection);

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopen corrupted database");
    let result = SqliteJobsQueries::new(reopened.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    reopened.shutdown().expect("shutdown");
}

#[test]
fn overlapping_admitted_and_excluded_outcomes_are_rejected() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 4_750);
    executor
        .execute(&context(), move |mut scope| {
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    fixture.job_run_id,
                    LibraryScanTargetKind::Excluded,
                    fixture.admitted_root_id,
                    "Admitted",
                    "/library/Admitted",
                    None,
                    Some(LibraryScanAdmissionExclusion::new(
                        fixture.admitted_root_id,
                        LibraryScanTargetExclusionReason::NoLongerConfigured,
                        None,
                        None,
                    )),
                ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("insert contradictory overlapping outcome");

    let result = SqliteJobsQueries::new(executor.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    executor.shutdown().expect("shutdown");
}

#[test]
fn out_of_scope_requested_and_outcome_rows_are_rejected() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 4_900);
    let foreign_root_id = root_id("dddddddddddddddddddddddddddddddd");
    executor
        .execute(&context(), move |mut scope| {
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    fixture.job_run_id,
                    LibraryScanTargetKind::Requested,
                    foreign_root_id,
                    "Foreign",
                    "/library/Foreign",
                    None,
                    None,
                ))?;
            scope
                .library_scan_targets()
                .insert(NewLibraryScanTarget::new(
                    fixture.job_run_id,
                    LibraryScanTargetKind::Excluded,
                    foreign_root_id,
                    "Foreign",
                    "/library/Foreign",
                    None,
                    Some(LibraryScanAdmissionExclusion::new(
                        foreign_root_id,
                        LibraryScanTargetExclusionReason::NoLongerConfigured,
                        None,
                        None,
                    )),
                ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("insert out-of-scope target rows");

    let result = SqliteJobsQueries::new(executor.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    executor.shutdown().expect("shutdown");
}

#[test]
fn admitted_target_cannot_reference_a_scan_run_from_another_parent_job() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 4_950);
    let foreign_scan_run_id = executor
        .execute(&context(), move |mut scope| {
            scope.scan_runs().set_status(
                fixture.scan_run_id,
                ScanRunStatus::Complete,
                Some(4_952),
                None,
            )?;
            scope
                .job_runs()
                .set_state(fixture.job_run_id, JobRunState::Completed, 4_952)?;
            let foreign_job_id = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 4_953))?;
            let foreign_scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                foreign_job_id,
                fixture.admitted_root_id,
                RootLocator::from_provider("/library/Admitted".to_owned()),
                "Admitted",
                "/library/Admitted",
                1,
                1,
                4_953,
            ))?;
            scope.scan_runs().set_status(
                foreign_scan_run_id,
                ScanRunStatus::Complete,
                Some(4_954),
                None,
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(foreign_scan_run_id)
        })
        .expect("seed foreign parent scan run");
    executor
        .shutdown()
        .expect("shutdown before corruption fixture");

    let connection = Connection::open(&database).expect("open corruption fixture");
    let changed = connection
        .execute(
            "UPDATE library_scan_target SET scan_run_id = ?1
             WHERE job_run_id = ?2 AND target_kind = 'admitted'
               AND historical_library_root_id = ?3",
            rusqlite::params![
                foreign_scan_run_id.to_string(),
                fixture.job_run_id.to_string(),
                fixture.admitted_root_id.to_string(),
            ],
        )
        .expect("point the admitted target at another job's scan run");
    assert_eq!(changed, 1);
    drop(connection);

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopen corrupted database");
    let result = SqliteJobsQueries::new(reopened.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    reopened.shutdown().expect("shutdown");
}

#[test]
fn failed_refresh_admission_rolls_back_manifest_and_all_job_records() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let [root_id] = insert_available_roots(&executor, &[("Added", "/library/Added")])[..] else {
        panic!("one root was inserted");
    };

    let result = StartLibraryScanHandler::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        executor.clone(),
    )
    .handle_with_operation_type(
        StartLibraryScanCommand::new(root_id),
        context(),
        RejectEvents,
        "library_refresh",
    );
    assert!(result.is_err(), "event failure must reject admission");
    executor
        .shutdown()
        .expect("shutdown before rollback checks");

    let connection = Connection::open(&database).expect("inspect rolled-back database");
    for (table, predicate) in [
        ("job_run", "operation_type = 'library_refresh'"),
        ("library_refresh_intent", "1 = 1"),
        ("scan_run", "1 = 1"),
        ("library_scan_target", "1 = 1"),
    ] {
        let count: i64 = connection
            .query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE {predicate}"),
                [],
                |row| row.get(0),
            )
            .expect("count rolled-back rows");
        assert_eq!(count, 0, "{table} rows must roll back with admission");
    }
    let has_version_marker: bool = connection
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM pragma_table_info('job_run')
                WHERE name = 'library_refresh_scope_version'
            )",
            [],
            |row| row.get(0),
        )
        .expect("inspect scope-version schema");
    assert!(
        has_version_marker,
        "new admissions need a durable version marker"
    );
}

#[test]
fn admitted_multi_root_refresh_has_complete_scope_coverage() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let root_ids = insert_available_roots(
        &executor,
        &[("First", "/library/First"), ("Second", "/library/Second")],
    );

    let admission = StartLibraryScanAllHandler::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        executor.clone(),
    )
    .handle_library_refresh(
        RefreshLibraryCommand::new(RefreshMode::EligibleOnly),
        context(),
        IgnoreEvents,
        LibraryRefreshTrigger::Manual,
    )
    .expect("admit multi-root refresh");
    let job_run_id = match admission.outcome() {
        LibraryRefreshAdmissionOutcome::Admitted(handle) => handle.job_run_id(),
        LibraryRefreshAdmissionOutcome::NothingEligible { .. } => {
            panic!("configured roots are eligible")
        }
    };

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job_run_id)
        .expect("get job")
        .expect("job detail");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected Library refresh detail");
    };
    let mut expected_root_ids = root_ids;
    expected_root_ids.sort();
    assert_eq!(refresh.requested_root_ids(), expected_root_ids);
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::Complete
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn admitted_multi_root_refresh_partitions_admitted_and_excluded_scope() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let root_ids = insert_available_roots(
        &executor,
        &[("First", "/library/First"), ("Second", "/library/Second")],
    );
    let excluded_root_id = root_ids[0];
    start_active_scan(&executor, excluded_root_id, "First", "/library/First");

    let admission = StartLibraryScanAllHandler::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        executor.clone(),
    )
    .handle_library_refresh(
        RefreshLibraryCommand::new(RefreshMode::EligibleOnly),
        context(),
        IgnoreEvents,
        LibraryRefreshTrigger::Manual,
    )
    .expect("admit multi-root refresh");
    let job_run_id = match admission.outcome() {
        LibraryRefreshAdmissionOutcome::Admitted(handle) => handle.job_run_id(),
        LibraryRefreshAdmissionOutcome::NothingEligible { .. } => {
            panic!("one configured root remains eligible")
        }
    };

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job_run_id)
        .expect("get job")
        .expect("job detail");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected Library refresh detail");
    };
    let mut expected_root_ids = root_ids.clone();
    expected_root_ids.sort();
    assert_eq!(refresh.requested_root_ids(), expected_root_ids);
    assert_eq!(refresh.scan_runs().len(), 1);
    assert_eq!(refresh.exclusions().len(), 1);
    assert_eq!(refresh.exclusions()[0].library_root_id(), excluded_root_id);
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::Complete
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn added_root_refresh_admits_its_trigger_with_complete_multi_root_outcomes() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let roots = insert_available_roots(
        &executor,
        &[
            ("First", "/library/First"),
            ("Added", "/library/Added"),
            ("Busy", "/library/Busy"),
        ],
    );
    let added_root_id = roots[1];
    let excluded_root_id = roots[2];
    start_active_scan(&executor, excluded_root_id, "Busy", "/library/Busy");

    let admission = StartLibraryScanAllHandler::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        executor.clone(),
    )
    .handle_library_refresh(
        RefreshLibraryCommand::new(RefreshMode::EligibleOnly),
        context(),
        IgnoreEvents,
        LibraryRefreshTrigger::AddedRoot(added_root_id),
    )
    .expect("admit AddedRoot refresh");
    let job_run_id = match admission.outcome() {
        LibraryRefreshAdmissionOutcome::Admitted(handle) => handle.job_run_id(),
        LibraryRefreshAdmissionOutcome::NothingEligible { .. } => {
            panic!("AddedRoot and another root are eligible")
        }
    };

    let detail = SqliteJobsQueries::new(executor.clone())
        .get_job(&context(), job_run_id)
        .expect("get AddedRoot refresh")
        .expect("refresh detail");
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        panic!("expected Library refresh detail");
    };
    let mut expected_root_ids = roots.clone();
    expected_root_ids.sort();
    assert_eq!(
        refresh.trigger(),
        LibraryRefreshTrigger::AddedRoot(added_root_id)
    );
    assert_eq!(refresh.requested_root_ids(), expected_root_ids);
    assert_eq!(refresh.scan_runs().len(), 2);
    let mut scanned_root_ids = refresh
        .scan_runs()
        .iter()
        .map(|scan_run| {
            assert_eq!(scan_run.job_run_id(), job_run_id);
            scan_run.library_root_id()
        })
        .collect::<Vec<_>>();
    scanned_root_ids.sort();
    let mut expected_scanned_root_ids = vec![roots[0], added_root_id];
    expected_scanned_root_ids.sort();
    assert_eq!(scanned_root_ids, expected_scanned_root_ids);
    assert_ne!(
        refresh.scan_runs()[0].scan_run_id(),
        refresh.scan_runs()[1].scan_run_id()
    );
    assert_eq!(refresh.exclusions().len(), 1);
    assert_eq!(refresh.exclusions()[0].library_root_id(), excluded_root_id);
    assert_eq!(
        refresh.root_outcome_coverage(),
        LibraryRefreshRootOutcomeCoverage::Complete
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn v1_added_root_trigger_missing_from_manifest_is_typed_corruption() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 5_000);
    executor
        .shutdown()
        .expect("close before corruption fixture");
    persist_added_root_trigger_for_integrity_test(
        &database,
        fixture,
        root_id("cccccccccccccccccccccccccccccccc"),
    );

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopen corrupted database");
    let result = SqliteJobsQueries::new(reopened.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    reopened.shutdown().expect("shutdown");
}

#[test]
fn v1_added_root_trigger_without_admitted_scan_is_typed_corruption() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 6_000);
    executor
        .shutdown()
        .expect("close before corruption fixture");
    persist_added_root_trigger_for_integrity_test(&database, fixture, fixture.excluded_root_id);

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopen corrupted database");
    let result = SqliteJobsQueries::new(reopened.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    reopened.shutdown().expect("shutdown");
}

#[test]
fn no_eligible_refresh_targets_does_not_admit_a_job() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let [root_id] = insert_available_roots(&executor, &[("Busy", "/library/Busy")])[..] else {
        panic!("one root was inserted");
    };
    start_active_scan(&executor, root_id, "Busy", "/library/Busy");
    let queries = SqliteJobsQueries::new(executor.clone());
    let active_before = queries.list_active(&context()).expect("active jobs before");

    let admission = StartLibraryScanAllHandler::new(
        SqliteLibraryRootQueries::new(executor.clone()),
        executor.clone(),
    )
    .handle_library_refresh(
        RefreshLibraryCommand::new(RefreshMode::EligibleOnly),
        context(),
        IgnoreEvents,
        LibraryRefreshTrigger::Manual,
    )
    .expect("return no-eligible outcome");

    assert!(matches!(
        admission.outcome(),
        LibraryRefreshAdmissionOutcome::NothingEligible { .. }
    ));
    assert_eq!(
        queries.list_active(&context()).expect("active jobs after"),
        active_before
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn get_job_rejects_an_admission_outcome_without_its_requested_target() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 5_000);
    delete_refresh_target(&executor, fixture, fixture.admitted_root_id, "requested");

    let queries = SqliteJobsQueries::new(executor.clone());
    let result = queries.get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    let repeated_result = queries.get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        repeated_result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    executor.shutdown().expect("shutdown");
}

#[test]
fn get_job_rejects_a_scan_run_without_its_admitted_target() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 6_000);
    delete_refresh_target(&executor, fixture, fixture.admitted_root_id, "admitted");

    let result = SqliteJobsQueries::new(executor.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    executor.shutdown().expect("shutdown");
}

#[test]
fn get_job_rejects_an_admitted_target_when_its_scan_run_is_missing() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 6_250);
    executor
        .shutdown()
        .expect("shutdown before corruption fixture");

    let connection = Connection::open(&database).expect("open corruption fixture");
    let changed = connection
        .execute(
            "DELETE FROM scan_run WHERE scan_run_id = ?1",
            [fixture.scan_run_id.to_string()],
        )
        .expect("delete scan row while foreign-key enforcement is disabled");
    assert_eq!(changed, 1);
    drop(connection);

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopen corrupted database");
    let result = SqliteJobsQueries::new(reopened.clone()).get_job(&context(), fixture.job_run_id);
    assert!(matches!(
        result,
        Err(PersistenceError::CorruptOrIncompatible)
    ));
    reopened.shutdown().expect("shutdown");
}

#[test]
fn get_job_missing_job_early_return_closes_its_read_snapshot() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&executor, 6_500);
    let missing_job_id =
        argus_application::JobRunId::from_bytes([99; 16]).expect("non-zero missing job id");
    let queries = SqliteJobsQueries::new(executor.clone());

    assert!(
        queries
            .get_job(&context(), missing_job_id)
            .expect("unknown job")
            .is_none()
    );
    assert!(
        queries
            .get_job(&context(), fixture.job_run_id)
            .expect("subsequent known job")
            .is_some()
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn get_job_reads_parent_and_scan_run_from_one_deferred_snapshot() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let seed_executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let fixture = seed_refresh_with_admitted_and_excluded_roots(&seed_executor, 7_000);
    seed_executor.shutdown().expect("shutdown seed executor");

    let reader_executor = SqliteDatabaseExecutor::open(&database).expect("reader executor");
    let writer_executor = SqliteDatabaseExecutor::open(&database).expect("writer executor");
    // Channel events control ordering; one shared deadline only guards test liveness.
    const TEST_LIVENESS_TIMEOUT: Duration = Duration::from_secs(15);
    let deadline = Instant::now() + TEST_LIVENESS_TIMEOUT;
    let (read_started_tx, read_started_rx) = mpsc::sync_channel(1);
    let (writer_result_tx, writer_result_rx) = mpsc::sync_channel::<Result<(), String>>(1);
    let writer_result_rx = Arc::new(Mutex::new(writer_result_rx));
    let wait_for_writer = Arc::clone(&writer_result_rx);
    let reader = SqliteJobsQueries::new(reader_executor.clone())
        .with_get_job_after_parent_read_hook_for_tests(move || {
            read_started_tx.send(()).expect("signal first parent read");
            let writer_result = wait_for_writer
                .lock()
                .expect("reader hook lock")
                .recv_timeout(deadline.saturating_duration_since(Instant::now()))
                .unwrap_or_else(|error| match error {
                    mpsc::RecvTimeoutError::Timeout => {
                        panic!("writer completion exceeds the test liveness deadline")
                    }
                    mpsc::RecvTimeoutError::Disconnected => {
                        panic!("writer completion channel disconnected")
                    }
                });
            writer_result.expect("writer commits before reader continues");
        });
    let read_thread = thread::spawn(move || reader.get_job(&context(), fixture.job_run_id));
    if let Err(error) =
        read_started_rx.recv_timeout(deadline.saturating_duration_since(Instant::now()))
    {
        let release_result = writer_result_tx.send(Err(format!(
            "reader did not establish its snapshot before the test liveness deadline: {error}"
        )));
        let reader_failure = match read_thread.join() {
            Ok(Ok(Some(_))) => "reader returned before the snapshot hook".to_owned(),
            Ok(Ok(None)) => "reader did not find the requested job".to_owned(),
            Ok(Err(error)) => format!("GetJob failed: {error:?}"),
            Err(_) => "reader thread panicked".to_owned(),
        };
        let reader_shutdown = reader_executor.shutdown();
        let writer_shutdown = writer_executor.shutdown();
        panic!(
            "reader failed to establish its snapshot; release={release_result:?}, reader={reader_failure}, reader_shutdown={reader_shutdown:?}, writer_shutdown={writer_shutdown:?}"
        );
    }

    let writer_result = writer_executor.execute(&context(), move |mut scope| {
        scope.scan_runs().set_status(
            fixture.scan_run_id,
            ScanRunStatus::Complete,
            Some(7_003),
            None,
        )?;
        scope
            .job_runs()
            .set_state(fixture.job_run_id, JobRunState::Completed, 7_003)?;
        scope.commit()?;
        Ok::<_, argus_application::ApplicationPortError>(())
    });
    let writer_signal = writer_result
        .as_ref()
        .map(|_| ())
        .map_err(|error| format!("writer failed before commit: {error:?}"));
    let reader_release = writer_result_tx.send(writer_signal);

    let before_commit_result = read_thread.join();
    let after_commit_result =
        SqliteJobsQueries::new(reader_executor.clone()).get_job(&context(), fixture.job_run_id);
    let reader_shutdown = reader_executor.shutdown();
    let writer_shutdown = writer_executor.shutdown();

    assert!(
        reader_shutdown.is_ok() && writer_shutdown.is_ok(),
        "database executors shut down cleanly: reader={reader_shutdown:?}, writer={writer_shutdown:?}"
    );
    reader_release.expect("reader receives writer completion result");
    writer_result.expect("commit parent and child update on independent executor");
    let before_commit = before_commit_result
        .expect("reader thread does not panic")
        .expect("first GetJob");
    let before_commit = before_commit.expect("job detail");
    assert_eq!(before_commit.job().state(), JobRunState::Running);
    let OperationDetail::LibraryRefresh(refresh) = before_commit.operation_detail() else {
        panic!("expected Library refresh detail");
    };
    assert_eq!(refresh.scan_runs()[0].status(), ScanRunStatus::Running);

    let after_commit = after_commit_result
        .expect("subsequent GetJob")
        .expect("job detail");
    assert_eq!(after_commit.job().state(), JobRunState::Completed);
    let OperationDetail::LibraryRefresh(refresh) = after_commit.operation_detail() else {
        panic!("expected Library refresh detail");
    };
    assert_eq!(refresh.scan_runs()[0].status(), ScanRunStatus::Complete);
}

#[test]
fn active_scan_blocks_a_second_scan_run_for_the_same_root() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let root = root_id("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    let now = 100;
    executor
        .execute(&context(), move |mut scope| {
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", now))?;
            scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                now,
            ))?;
            let second = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                now,
            ));
            assert_eq!(second, Err(PersistenceError::ConstraintViolation));
            scope.rollback()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("constraint transaction");
    executor.shutdown().expect("shutdown");
}

fn make_tree(root: &Path) {
    fs::create_dir_all(root.join("Sub")).expect("subdir");
    fs::write(root.join("rom.bin"), b"rom").expect("file");
    fs::write(root.join("Sub/nested.txt"), b"nested").expect("nested");
    #[cfg(unix)]
    std::os::unix::fs::symlink(root.join("rom.bin"), root.join("link")).expect("symlink");
}

#[test]
fn local_filesystem_access_enumerates_nested_scopes_without_following_links() {
    let directory = tempfile::tempdir().expect("tempdir");
    let root = directory.path().join("Library");
    make_tree(&root);
    let access = common::access(&root);
    let resolved = access.resolve_root().expect("resolve");
    let root_scope = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("root scope");
    assert_eq!(
        root_scope.outcome(),
        argus_application::EnumerationOutcome::Complete
    );
    let names: Vec<&str> = root_scope
        .observations()
        .iter()
        .map(|observation| observation.display_name())
        .collect();
    assert!(names.contains(&"Sub"));
    assert!(names.contains(&"rom.bin"));
    #[cfg(unix)]
    {
        let link = root_scope
            .observations()
            .iter()
            .find(|observation| observation.display_name() == "link")
            .expect("link observation");
        assert_eq!(link.observed_kind(), ObservedEntryKind::LinkLike);
        assert!(link.provider_native_identity().is_some());
    }

    let sub = root_scope
        .observations()
        .iter()
        .find(|observation| observation.display_name() == "Sub")
        .expect("sub directory");
    let nested = access
        .enumerate_direct_children(&resolved, sub.relative_locator(), &|| false)
        .expect("nested scope");
    assert_eq!(nested.observations().len(), 1);
    assert_eq!(nested.observations()[0].display_name(), "nested.txt");

    // Locator keys are deterministic for unchanged locations.
    let again = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("second root scope");
    let sub_again = again
        .observations()
        .iter()
        .find(|observation| observation.display_name() == "Sub")
        .expect("sub again");
    assert_eq!(sub.locator_key(), sub_again.locator_key());

    // Namespace escape is rejected.
    let escape = access.enumerate_direct_children(
        &resolved,
        &RelativeSourceLocator::from_provider("../outside".to_owned()),
        &|| false,
    );
    assert_eq!(escape, Err(SourceAccessError::InvalidLocator));
    access.resolve_root().expect("re-resolve");
    access
        .enumerate_root_direct_children(&resolved, &|| true)
        .expect_err("cancellation is surfaced");
}

#[test]
fn link_like_entry_with_outside_root_target_is_retained_and_scope_stays_complete() {
    let directory = tempfile::tempdir().expect("tempdir");
    let outside = directory.path().join("outside-target.bin");
    fs::write(&outside, b"outside").expect("outside target");
    let root = directory.path().join("Library");
    fs::create_dir(&root).expect("library root");
    fs::write(root.join("rom.bin"), b"rom").expect("file");
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(&outside, root.join("escape")).expect("symlink");
    }
    #[cfg(windows)]
    {
        // Symlink creation requires developer mode on Windows; skip link
        // creation there and assert only the ordinary-entry behavior.
    }

    let access = common::access(&root);
    let resolved = access.resolve_root().expect("resolve");
    let scope = access
        .enumerate_root_direct_children(&resolved, &|| false)
        .expect("root scope");
    assert_eq!(
        scope.outcome(),
        argus_application::EnumerationOutcome::Complete,
        "an outside-target link must not fail the containing scope"
    );
    #[cfg(unix)]
    {
        let escape = scope
            .observations()
            .iter()
            .find(|observation| observation.display_name() == "escape")
            .expect("link observation retained");
        assert_eq!(escape.observed_kind(), ObservedEntryKind::LinkLike);
        assert!(escape.provider_native_identity().is_some());
    }
}

#[test]
fn actual_traversal_through_an_outside_target_link_is_rejected() {
    let directory = tempfile::tempdir().expect("tempdir");
    let outside = directory.path().join("outside-target.bin");
    fs::write(&outside, b"outside").expect("outside target");
    let root = directory.path().join("Library");
    fs::create_dir(&root).expect("library root");
    #[cfg(unix)]
    std::os::unix::fs::symlink(&outside, root.join("escape")).expect("symlink");

    let access = common::access(&root);
    let resolved = access.resolve_root().expect("resolve");
    #[cfg(unix)]
    {
        let escape = access.enumerate_direct_children(
            &resolved,
            &RelativeSourceLocator::from_provider("escape".to_owned()),
            &|| false,
        );
        assert_eq!(
            escape,
            Err(SourceAccessError::InvalidLocator),
            "traversal requests that resolve outside the root are rejected"
        );
    }
}

#[test]
fn root_resolution_rejects_a_missing_or_link_like_root() {
    let directory = tempfile::tempdir().expect("tempdir");
    let missing_path = directory.path().join("missing");
    fs::create_dir(&missing_path).expect("missing fixture root");
    let missing_locator = common::locator(&missing_path);
    fs::remove_dir(&missing_path).expect("remove fixture root");
    let missing = LocalFilesystemSourceAccess::new(&missing_locator);
    let missing_result = missing.resolve_root();
    #[cfg(target_os = "macos")]
    assert_eq!(
        missing_result,
        Err(SourceAccessError::AuthorizationUnavailable)
    );
    #[cfg(not(target_os = "macos"))]
    assert_eq!(missing_result, Err(SourceAccessError::SourceUnavailable));

    #[cfg(unix)]
    {
        let target = directory.path().join("target");
        fs::create_dir(&target).expect("target");
        let link_path = directory.path().join("link-root");
        std::os::unix::fs::symlink(&target, &link_path).expect("symlink");
        let link = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
            link_path.to_string_lossy().into_owned(),
        ));
        let result = link.resolve_root();
        #[cfg(target_os = "macos")]
        assert_eq!(result, Err(SourceAccessError::AuthorizationUnavailable));
        #[cfg(not(target_os = "macos"))]
        assert_eq!(result, Err(SourceAccessError::InvalidLocator));
    }
}
