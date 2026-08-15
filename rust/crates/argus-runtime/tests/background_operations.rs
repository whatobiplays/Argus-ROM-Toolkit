//! Runtime-level Slice 002 background-operation integration tests.

use std::fs;
use std::path::Path;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use argus_application::{
    AddLocalLibraryRootResult, CancelJobResult, ErrorCode, JobRunId, JobRunState, LibraryRootId,
    LibraryRootLastScanStatus, ListJobsQuery, ListJobsScope, LocalFilesystemRootSelection,
    StartLibraryScanResult,
};
use argus_runtime::{
    ApplicationHost, KernelBootstrapOptions, RuntimeEventPayload, RuntimeLifecycle,
};

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
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if predicate() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    predicate()
}

fn add_root(host: &ApplicationHost, path: &Path) -> LibraryRootId {
    let result = host
        .add_local_library_root(LocalFilesystemRootSelection::new(
            path.to_string_lossy().into_owned(),
        ))
        .expect("add root");
    match result {
        AddLocalLibraryRootResult::Added(root) => root.root_id(),
        _ => panic!("expected added root"),
    }
}

fn start_scan(host: &ApplicationHost, root_id: LibraryRootId) -> JobRunId {
    match host.start_library_scan(root_id).expect("start scan") {
        StartLibraryScanResult::Admitted(handle) => handle.job_run_id(),
        StartLibraryScanResult::AlreadyScanning { .. } => panic!("expected admitted"),
    }
}

fn terminal_state(host: &ApplicationHost, job_run_id: JobRunId) -> JobRunState {
    wait_until(
        || {
            host.get_job(job_run_id)
                .map(|detail| detail.job().state().is_terminal())
                .unwrap_or(false)
        },
        Duration::from_secs(15),
    );
    host.get_job(job_run_id).expect("get job").job().state()
}

#[test]
fn library_scan_completes_durably_and_updates_root_projections() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 300);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);

    let detail = host.get_job(job_run_id).expect("job detail during scan");
    assert_eq!(detail.job().state(), JobRunState::Queued);
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);

    let root = host.get_library_root(root_id).expect("root projection");
    assert!(root.active_scan().is_none());
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Complete
    );

    let recent = host
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs");
    assert_eq!(recent.total_count(), 1);
    assert_eq!(recent.items()[0].job_run_id(), job_run_id);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn duplicate_same_root_admission_returns_already_scanning() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 3_000);
    let root_id = add_root(&host, &library);
    let first = start_scan(&host, root_id);
    let second = host.start_library_scan(root_id).expect("second admission");
    match second {
        StartLibraryScanResult::AlreadyScanning {
            library_root_id,
            active_job_run_id,
            active_scan_run_id: _,
        } => {
            assert_eq!(library_root_id, root_id);
            assert_eq!(active_job_run_id, first);
        }
        StartLibraryScanResult::Admitted(_) => panic!("expected already scanning"),
    }
    assert_eq!(terminal_state(&host, first), JobRunState::Completed);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn cancellation_reaches_a_durable_terminal_boundary() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 3_000);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);
    let cancel = host.cancel_job(job_run_id).expect("cancel");
    match cancel {
        CancelJobResult::CancellationRequested => {
            assert_eq!(terminal_state(&host, job_run_id), JobRunState::Cancelled);
            let detail = host.get_job(job_run_id).expect("job detail");
            assert!(detail.job().cancellation_requested());
        }
        CancelJobResult::NoLongerCancellable => {
            assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);
        }
    }
    host.general_shutdown().expect("shutdown");
}

#[test]
fn shutdown_coordinates_active_background_work() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 3_000);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);
    std::thread::sleep(Duration::from_millis(20));
    host.general_shutdown().expect("shutdown");

    // The worker cancels at its next checkpoint, so the durable job must be
    // terminal (Cancelled or Completed) rather than left Running.
    let reopened = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&reopened);
    let state = reopened
        .get_job(job_run_id)
        .expect("job after restart")
        .job()
        .state();
    assert!(
        matches!(state, JobRunState::Cancelled | JobRunState::Completed),
        "unexpected post-shutdown state: {state:?}"
    );
    reopened.general_shutdown().expect("second shutdown");
}

#[test]
fn job_state_events_cross_the_unified_runtime_stream() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let subscription = host.subscribe_events().expect("subscribe");
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        while let Ok(event) = subscription.recv() {
            if matches!(event.payload, RuntimeEventPayload::JobStateChanged { .. }) {
                let _ = sender.send(());
                break;
            }
        }
    });
    let library = directory.path().join("Library");
    make_library(&library, 100);
    let root_id = add_root(&host, &library);
    let job_run_id = start_scan(&host, root_id);
    receiver
        .recv_timeout(Duration::from_secs(15))
        .expect("job state event");
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(feature = "test-support")]
fn registration_spawn_failure_terminalizes_the_admitted_run() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 50);
    let root_id = add_root(&host, &library);

    host.background_manager_for_tests()
        .expect("manager")
        .fail_next_spawn_for_tests();
    let error = host
        .start_library_scan(root_id)
        .expect_err("spawn failure must surface as a registration failure");
    assert_eq!(error.code, ErrorCode::InternalUnexpected);

    let recent = host
        .list_jobs(ListJobsQuery::new(ListJobsScope::RecentTerminal {
            offset: 0,
            page_size: 20,
        }))
        .expect("recent jobs");
    assert_eq!(recent.total_count(), 1, "no orphan nonterminal JobRun");
    assert_eq!(recent.items()[0].state(), JobRunState::Failed);
    let failed_job_run_id = recent.items()[0].job_run_id();
    let failed_detail = host.get_job(failed_job_run_id).expect("failed job detail");
    let argus_application::OperationDetail::LibraryScan(failed_scan) =
        failed_detail.operation_detail();
    assert_eq!(failed_scan.scan_runs().len(), 1);
    assert_eq!(
        failed_scan.scan_runs()[0].status(),
        argus_application::ScanRunStatus::Failed,
        "no orphan active ScanRun"
    );

    let root = host.get_library_root(root_id).expect("root projection");
    assert!(root.active_scan().is_none(), "no orphan active ScanRun");
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Failed
    );

    // A fresh admission proceeds normally after the reconciled failure.
    let second = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, second), JobRunState::Completed);
    host.general_shutdown().expect("shutdown");
}
