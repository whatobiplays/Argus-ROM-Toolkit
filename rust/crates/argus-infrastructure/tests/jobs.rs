//! Slice 002 infrastructure integration tests for job/scan persistence and
//! the LocalFilesystem source access adapter.

use std::fs;
use std::path::Path;

use argus_application::LibrarySourceAccess;
use argus_application::{
    ActiveScanOwnership, JobProgress, JobRunRepository, JobRunState, LibraryRootAvailability,
    LibraryRootId, LibraryRootLastScanStatus, LibraryRootLastScanSummary, LibraryRootRepository,
    LibraryScanTargetKind, LibraryScanTargetRepository, LibrarySourceRepository, NewJobRun,
    NewLibraryRoot, NewLibraryScanTarget, NewScanRun, NewSourceEntry, ObservedEntryKind,
    OperationContext, OperationName, PersistenceError, RelativeSourceLocator, RootLocator,
    ScanRunRepository, ScanRunStatus, SourceAccessError, SourceEntryClassification,
    SourceEntryKind, SourceEntryRepository, SourceLocatorKey, SubsystemName, TraceId, UnitOfWork,
    UnitOfWorkFactory,
};
use argus_application::{JobsQueries, LibraryRootQueries, OperationDetail};
use argus_infrastructure::local_filesystem::LocalFilesystemSourceAccess;
use argus_infrastructure::sqlite::{
    SqliteDatabaseExecutor, SqliteJobsQueries, SqliteLibraryRootQueries,
};

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
    let OperationDetail::LibraryScan(scan_detail) = detail.operation_detail();
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
    let access = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        root.to_string_lossy().into_owned(),
    ));
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
fn root_resolution_rejects_a_missing_or_link_like_root() {
    let directory = tempfile::tempdir().expect("tempdir");
    let missing = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
        directory
            .path()
            .join("missing")
            .to_string_lossy()
            .into_owned(),
    ));
    assert_eq!(
        missing.resolve_root(),
        Err(SourceAccessError::SourceUnavailable)
    );

    #[cfg(unix)]
    {
        let target = directory.path().join("target");
        fs::create_dir(&target).expect("target");
        let link_path = directory.path().join("link-root");
        std::os::unix::fs::symlink(&target, &link_path).expect("symlink");
        let link = LocalFilesystemSourceAccess::new(&RootLocator::from_provider(
            link_path.to_string_lossy().into_owned(),
        ));
        assert_eq!(link.resolve_root(), Err(SourceAccessError::InvalidLocator));
    }
}
