#![cfg(feature = "test-support")]

//! Slice 006 runtime integration tests for one multi-root Scan All job.

use std::fs;
use std::path::Path;
use std::time::Duration;

use argus_application::{
    AddLocalLibraryRootResult, CancelJobResult, JobRunId, JobRunState, LibraryRootAvailability,
    LibraryRootId, LibraryRootLastScanStatus, LibraryScanAllRequestIdentity,
    LocalFilesystemRootSelection, MountedLocalFilesystemVolume, OperationDetail,
    RemoveLibraryRootResult, RetryJobResult, StartLibraryScanAllResult,
    SyncLocalFilesystemMountedVolumesCommand,
};
#[cfg(feature = "test-support")]
use argus_application::{ErrorCode, ListJobsQuery, ListJobsScope};
use argus_runtime::{ApplicationHost, KernelBootstrapOptions, RuntimeLifecycle, test_support};

fn context_ready(host: &ApplicationHost) {
    let state = host.initialize().expect("initialize");
    assert_eq!(state.lifecycle(), RuntimeLifecycle::Ready);
}

fn make_library(root: &Path, file_count: usize) {
    fs::create_dir_all(root).expect("library root");
    for index in 0..file_count {
        fs::write(root.join(format!("rom-{index:05}.bin")), b"rom").expect("file");
    }
    fs::create_dir_all(root.join("Sub")).expect("subdir");
    fs::write(root.join("Sub/nested.txt"), b"nested").expect("nested");
}

fn wait_until<F>(mut predicate: F, timeout: Duration) -> bool
where
    F: FnMut() -> bool,
{
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        if predicate() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    predicate()
}

fn terminal_state(host: &ApplicationHost, job_run_id: JobRunId) -> JobRunState {
    wait_until(
        || {
            host.get_job(job_run_id)
                .map(|detail| detail.job().state().is_terminal())
                .unwrap_or(false)
        },
        Duration::from_secs(20),
    );
    host.get_job(job_run_id).expect("get job").job().state()
}

fn add_root(host: &ApplicationHost, path: &Path) -> LibraryRootId {
    match host
        .add_local_library_root(test_support::local_filesystem_root_selection(path))
        .expect("add root")
    {
        argus_application::AddLocalLibraryRootResult::Added(root) => root.root_id(),
        _ => panic!("expected added root"),
    }
}

fn request_identity(value: &str) -> LibraryScanAllRequestIdentity {
    LibraryScanAllRequestIdentity::try_from(value).expect("request identity")
}

fn sorted(mut values: Vec<LibraryRootId>) -> Vec<LibraryRootId> {
    values.sort_by_key(|value| value.to_string());
    values
}

#[test]
fn scan_all_admits_multiple_roots_in_one_sequential_job() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let first = directory.path().join("First");
    let second = directory.path().join("Second");
    make_library(&first, 120);
    make_library(&second, 80);
    let root_a = add_root(&host, &first);
    let root_b = add_root(&host, &second);
    let canonical = sorted(vec![root_a, root_b]);

    let result = host
        .start_library_scan_all(request_identity("runtime-scan-all-1"))
        .expect("scan all");
    let (job_run_id, admitted_roots) = match result {
        StartLibraryScanAllResult::Admitted {
            operation_handle,
            admitted_roots,
            exclusions,
        } => {
            assert!(exclusions.is_empty());
            (operation_handle.job_run_id(), admitted_roots)
        }
        StartLibraryScanAllResult::NothingEligible { .. } => panic!("expected admitted"),
    };
    assert_eq!(admitted_roots, canonical);
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);

    let detail = host.get_job(job_run_id).expect("job detail");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    let scan_order: Vec<LibraryRootId> = operation
        .scan_runs()
        .iter()
        .map(|run| run.library_root_id())
        .collect();
    assert_eq!(scan_order, canonical);
    assert_eq!(operation.admitted_roots().len(), 2);
    assert_eq!(operation.requested_roots().len(), 2);

    for root_id in canonical {
        let root = host.get_library_root(root_id).expect("root");
        assert_eq!(
            root.last_scan().expect("last scan").status(),
            LibraryRootLastScanStatus::Complete
        );
    }
    host.general_shutdown().expect("shutdown");
}

#[test]
fn scan_all_resolves_provider_root_from_registered_mount() {
    let directory = tempfile::tempdir().expect("tempdir");
    let primary_mount = directory.path().join("primary");
    let removable_mount = directory.path().join("removable");
    let root_path = removable_mount.join("ProviderGames");
    fs::create_dir_all(&primary_mount).expect("primary mount");
    fs::create_dir_all(&root_path).expect("provider root");
    fs::write(root_path.join("fixture.bin"), b"fixture").expect("fixture");

    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    host.sync_local_filesystem_mounted_volumes(SyncLocalFilesystemMountedVolumesCommand::new(
        vec![
            MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                primary_mount.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            ),
            MountedLocalFilesystemVolume::new(
                "provider-volume".to_owned(),
                removable_mount.to_string_lossy().into_owned(),
                "Removable storage".to_owned(),
                false,
                true,
            ),
        ],
    ))
    .expect("registered mount snapshot");
    let browse_root = host
        .list_local_filesystem_browse_roots()
        .expect("browse roots")
        .into_iter()
        .find(|root| root.display_name() == "Removable storage")
        .expect("registered removable root");
    let page = host
        .list_local_filesystem_browse_directories(browse_root.location().clone(), None, 10)
        .expect("browse provider root");
    let selected = page
        .directories()
        .iter()
        .find(|entry| entry.display_name() == "ProviderGames")
        .expect("provider directory");
    let added = host
        .add_local_library_root(LocalFilesystemRootSelection::provider_selection(
            selected.location().as_provider_value().to_owned(),
        ))
        .expect("add provider root");
    let root_id = match added {
        AddLocalLibraryRootResult::Added(root) => root.root_id(),
        other => panic!("expected provider root, got {other:?}"),
    };
    assert_eq!(
        host.get_library_root(root_id)
            .expect("provider root projection")
            .availability(),
        LibraryRootAvailability::Available
    );

    let result = host
        .start_library_scan_all(request_identity("runtime-scan-all-provider-root"))
        .expect("scan all");
    let job_run_id = match result {
        StartLibraryScanAllResult::Admitted {
            operation_handle,
            admitted_roots,
            exclusions,
        } => {
            assert_eq!(admitted_roots, vec![root_id]);
            assert!(exclusions.is_empty());
            operation_handle.job_run_id()
        }
        StartLibraryScanAllResult::NothingEligible { .. } => panic!("expected admitted"),
    };
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);
    let detail = host.get_job(job_run_id).expect("job detail");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(operation.scan_runs().len(), 1);
    assert_eq!(
        operation.scan_runs()[0].status(),
        argus_application::ScanRunStatus::Complete
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn scan_all_continues_after_a_failed_child_and_aggregates_with_issues() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let healthy = directory.path().join("Healthy");
    let missing = directory.path().join("Missing");
    make_library(&healthy, 80);
    make_library(&missing, 5);
    let healthy_root = add_root(&host, &healthy);
    let missing_root = add_root(&host, &missing);
    fs::remove_dir_all(&missing).expect("remove missing root directory");

    let result = host
        .start_library_scan_all(request_identity("runtime-scan-all-2"))
        .expect("scan all");
    let job_run_id = match result {
        StartLibraryScanAllResult::Admitted {
            operation_handle, ..
        } => operation_handle.job_run_id(),
        StartLibraryScanAllResult::NothingEligible { .. } => panic!("expected admitted"),
    };
    assert_eq!(
        terminal_state(&host, job_run_id),
        JobRunState::CompletedWithIssues
    );

    let detail = host.get_job(job_run_id).expect("job detail");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    let statuses: Vec<_> = operation
        .scan_runs()
        .iter()
        .map(|run| run.status())
        .collect();
    assert!(statuses.contains(&argus_application::ScanRunStatus::Complete));
    assert!(statuses.contains(&argus_application::ScanRunStatus::Failed));
    assert_eq!(
        host.get_library_root(healthy_root)
            .expect("healthy root")
            .last_scan()
            .expect("healthy last scan")
            .status(),
        LibraryRootLastScanStatus::Complete
    );
    assert_eq!(
        host.get_library_root(missing_root)
            .expect("missing root")
            .last_scan()
            .expect("missing last scan")
            .status(),
        LibraryRootLastScanStatus::Unavailable
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn scan_all_source_access_failure_terminalizes_child_and_continues_sibling() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let first = directory.path().join("First");
    let second = directory.path().join("Second");
    make_library(&first, 8);
    make_library(&second, 8);
    let first_root = add_root(&host, &first);
    let second_root = add_root(&host, &second);
    assert!(
        host.fail_next_source_open_for_tests(
            argus_application::SourceAccessError::SourceUnavailable,
        )
    );

    let result = host
        .start_library_scan_all(request_identity("runtime-scan-all-open-failure"))
        .expect("Scan All admission");
    let job_run_id = match result {
        StartLibraryScanAllResult::Admitted {
            operation_handle, ..
        } => operation_handle.job_run_id(),
        StartLibraryScanAllResult::NothingEligible { .. } => panic!("expected admitted"),
    };
    assert_eq!(
        terminal_state(&host, job_run_id),
        JobRunState::CompletedWithIssues,
        "a provider-open failure must not abort the parent before sibling execution"
    );

    let detail = host.get_job(job_run_id).expect("Scan All detail");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected Scan All operation detail");
    };
    assert_eq!(operation.scan_runs().len(), 2);
    let failed: Vec<_> = operation
        .scan_runs()
        .iter()
        .filter(|run| run.status() == argus_application::ScanRunStatus::Failed)
        .collect();
    assert_eq!(failed.len(), 1, "only the injected child should fail");
    assert_eq!(failed[0].failure_reason(), Some("source_unavailable"));
    assert_eq!(
        operation
            .scan_runs()
            .iter()
            .filter(|run| run.status() == argus_application::ScanRunStatus::Complete)
            .count(),
        1,
        "the later healthy sibling must execute and complete"
    );
    for root_id in [first_root, second_root] {
        assert!(
            host.get_library_root(root_id)
                .expect("root projection")
                .active_scan()
                .is_none(),
            "terminal parent must release every admitted child root"
        );
    }
    assert_eq!(
        host.get_library_root(failed[0].library_root_id())
            .expect("failed root")
            .last_scan()
            .expect("failed scan projection")
            .status(),
        LibraryRootLastScanStatus::Unavailable
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn scan_all_registration_failure_terminalizes_every_admitted_child_and_parent() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let first = directory.path().join("First");
    let second = directory.path().join("Second");
    make_library(&first, 20);
    make_library(&second, 20);
    add_root(&host, &first);
    add_root(&host, &second);

    host.background_manager_for_tests()
        .expect("manager")
        .fail_next_spawn_for_tests();
    let error = host
        .start_library_scan_all(request_identity("runtime-scan-all-fail"))
        .expect_err("spawn failure must surface as registration failure");
    assert_eq!(error.code, ErrorCode::InternalUnexpected);

    let recent = host
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs");
    assert_eq!(recent.total_count(), 1);
    assert_eq!(recent.items()[0].state(), JobRunState::Failed);
    let job_run_id = recent.items()[0].job_run_id();
    let detail = host.get_job(job_run_id).expect("job detail");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(operation.scan_runs().len(), 2);
    assert!(
        operation
            .scan_runs()
            .iter()
            .all(|run| run.status().is_terminal())
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn scan_all_cancellation_is_job_scoped_and_terminalizes_children() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let first = directory.path().join("First");
    let second = directory.path().join("Second");
    make_library(&first, 4_000);
    make_library(&second, 4_000);
    add_root(&host, &first);
    add_root(&host, &second);

    let result = host
        .start_library_scan_all(request_identity("runtime-scan-all-cancel"))
        .expect("scan all");
    let job_run_id = match result {
        StartLibraryScanAllResult::Admitted {
            operation_handle, ..
        } => operation_handle.job_run_id(),
        StartLibraryScanAllResult::NothingEligible { .. } => panic!("expected admitted"),
    };
    let cancellation = host.cancel_job(job_run_id).expect("cancel job");
    assert_eq!(cancellation, CancelJobResult::CancellationRequested);
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Cancelled);

    let detail = host.get_job(job_run_id).expect("job detail");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    assert!(
        operation
            .scan_runs()
            .iter()
            .all(|run| run.status().is_terminal())
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn scan_all_retry_preserves_multi_root_intent_and_current_exclusions() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let first = directory.path().join("First");
    let second = directory.path().join("Second");
    make_library(&first, 80);
    make_library(&second, 60);
    let root_a = add_root(&host, &first);
    let root_b = add_root(&host, &second);
    fs::remove_dir_all(&first).expect("remove first root directory");

    let initial = host
        .start_library_scan_all(request_identity("runtime-scan-all-retry-source"))
        .expect("initial scan all");
    let source_job = match initial {
        StartLibraryScanAllResult::Admitted {
            operation_handle, ..
        } => operation_handle.job_run_id(),
        StartLibraryScanAllResult::NothingEligible { .. } => panic!("expected admitted"),
    };
    assert_eq!(
        terminal_state(&host, source_job),
        JobRunState::CompletedWithIssues
    );
    assert_eq!(
        host.remove_library_root(root_a).expect("remove root"),
        RemoveLibraryRootResult::Removed
    );

    let retry = host.retry_job(source_job).expect("retry scan all");
    let retry_job = match retry.outcome() {
        RetryJobResult::Admitted(handle) => handle.job_run_id(),
        other => panic!("expected admitted retry, got {other:?}"),
    };
    assert!(retry.admitted_job().is_some());
    assert_eq!(retry.admitted_job_exclusion_count(), 1);
    assert_eq!(
        terminal_state(&host, retry_job),
        JobRunState::CompletedWithIssues
    );

    let detail = host.get_job(retry_job).expect("retry detail");
    let OperationDetail::LibraryScan(operation) = detail.operation_detail() else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(operation.requested_roots().len(), 2);
    assert_eq!(operation.admitted_roots().len(), 1);
    assert_eq!(operation.admitted_roots()[0].library_root_id(), root_b);
    assert_eq!(operation.exclusions().len(), 1);
    assert_eq!(operation.exclusions()[0].library_root_id(), root_a);
    assert_eq!(operation.retry_source_job_run_id(), Some(source_job));
    host.general_shutdown().expect("shutdown");
}
