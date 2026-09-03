#![cfg(feature = "test-support")]

//! Slice 005 runtime integration tests for the complete single-root scan
//! interaction workflow: Add & Scan, Scan Again, Retry, and Jobs authority.

use std::fs;
use std::path::Path;
use std::time::Duration;

use argus_application::{
    AddLocalLibraryRootAndScanResult, ErrorCode, JobRunState, LibraryRootId,
    LibraryRootLastScanStatus, RetryJobResult, RetryNotAdmittedReason, StartLibraryScanResult,
};
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

fn terminal_state(host: &ApplicationHost, job_run_id: argus_application::JobRunId) -> JobRunState {
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

fn add_root(host: &ApplicationHost, path: &Path) -> LibraryRootId {
    match host
        .add_local_library_root(test_support::local_filesystem_root_selection(path))
        .expect("add root")
    {
        argus_application::AddLocalLibraryRootResult::Added(root) => root.root_id(),
        _ => panic!("expected added root"),
    }
}

fn start_scan(host: &ApplicationHost, root_id: LibraryRootId) -> argus_application::JobRunId {
    match host.start_library_scan(root_id).expect("start scan") {
        StartLibraryScanResult::Admitted(handle) => handle.job_run_id(),
        StartLibraryScanResult::AlreadyScanning { .. } => panic!("expected admitted"),
    }
}

#[test]
fn add_and_scan_commits_root_admits_scan_and_completes() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 300);

    let result = host
        .add_local_library_root_and_scan(test_support::local_filesystem_root_selection(&library))
        .expect("add and scan");
    let (root_id, job_run_id) = match result {
        AddLocalLibraryRootAndScanResult::AddedAndScanAdmitted(root, handle) => {
            (root.root_id(), handle.job_run_id())
        }
        _ => panic!("expected added and admitted"),
    };
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Completed);
    let root = host.get_library_root(root_id).expect("root projection");
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Complete
    );
    let reference = host
        .get_root_scan_admission(root_id)
        .expect("scan admission")
        .expect("reference");
    assert_eq!(reference.job_run_id(), job_run_id);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn add_and_scan_duplicate_returns_already_configured_without_a_new_job() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 50);
    let selection = test_support::local_filesystem_root_selection(&library);
    host.add_local_library_root_and_scan(selection.clone())
        .expect("first add and scan");
    let second = host
        .add_local_library_root_and_scan(selection)
        .expect("second add and scan");
    assert!(matches!(
        second,
        AddLocalLibraryRootAndScanResult::AlreadyConfigured(_)
    ));
    let active = host
        .list_jobs(argus_application::ListJobsQuery::new(
            argus_application::ListJobsScope::Active,
        ))
        .expect("active jobs");
    let recent = host
        .list_jobs(argus_application::ListJobsQuery::new(
            argus_application::ListJobsScope::RecentTerminal {
                offset: 0,
                page_size: 20,
            },
        ))
        .expect("recent jobs");
    assert_eq!(active.total_count() + recent.total_count(), 1);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn failed_scan_retries_into_a_new_identity_with_a_linear_link() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 20);
    let root_id = add_root(&host, &library);
    let original = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, original), JobRunState::Completed);

    // Force a failure by making the provider root unavailable before a retry
    // candidate can be admitted as a fresh scan.
    fs::remove_dir_all(&library).expect("remove library");
    let scan_again = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, scan_again), JobRunState::Failed);

    let retry = host.retry_job(scan_again).expect("retry admission");
    let retry_job_run_id = match retry.outcome() {
        RetryJobResult::Admitted(handle) => handle.job_run_id(),
        _ => panic!("expected admitted retry"),
    };
    assert_ne!(retry_job_run_id, scan_again);
    assert_eq!(terminal_state(&host, retry_job_run_id), JobRunState::Failed);

    let source_detail = host
        .get_job(scan_again)
        .expect("source detail")
        .job()
        .to_owned();
    let source_job_detail = host.get_job(scan_again).expect("source detail");
    let retry_job_detail = host.get_job(retry_job_run_id).expect("retry detail");
    let argus_application::OperationDetail::LibraryScan(source_operation) =
        source_job_detail.operation_detail()
    else {
        panic!("expected library scan operation detail");
    };
    let argus_application::OperationDetail::LibraryScan(retry_operation) =
        retry_job_detail.operation_detail()
    else {
        panic!("expected library scan operation detail");
    };
    assert_eq!(
        source_operation.retry_successor_job_run_id(),
        Some(retry_job_run_id)
    );
    assert_eq!(retry_operation.retry_source_job_run_id(), Some(scan_again));
    assert!(!source_detail.controls().can_retry());

    let already = host.retry_job(scan_again).expect("second retry lookup");
    assert_eq!(
        already.outcome(),
        &RetryJobResult::AlreadyRetried(retry_job_run_id)
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn clean_completed_scan_uses_scan_again_and_is_not_retryable() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 100);
    let root_id = add_root(&host, &library);
    let first = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, first), JobRunState::Completed);

    let retry = host.retry_job(first).expect("retry lookup");
    assert_eq!(
        retry.outcome(),
        &RetryJobResult::NotAdmitted(RetryNotAdmittedReason::OperationNotRetryable)
    );

    let scan_again = start_scan(&host, root_id);
    assert_ne!(scan_again, first);
    assert_eq!(terminal_state(&host, scan_again), JobRunState::Completed);
    host.general_shutdown().expect("shutdown");
}

#[test]
fn retry_after_root_removal_returns_no_eligible_targets_without_creating_a_job() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let library = directory.path().join("Library");
    make_library(&library, 20);
    let root_id = add_root(&host, &library);
    let original = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, original), JobRunState::Completed);
    fs::remove_dir_all(&library).expect("remove library");
    let failed = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, failed), JobRunState::Failed);

    assert!(matches!(
        host.remove_library_root(root_id).expect("remove root"),
        argus_application::RemoveLibraryRootResult::Removed
    ));
    let retry = host.retry_job(failed).expect("retry lookup");
    match retry.outcome() {
        RetryJobResult::NotAdmitted(RetryNotAdmittedReason::NoEligibleTargets(exclusions)) => {
            assert_eq!(exclusions.len(), 1);
            assert_eq!(
                exclusions[0].reason(),
                argus_application::LibraryScanTargetExclusionReason::NoLongerConfigured
            );
        }
        _ => panic!("expected no eligible targets"),
    }
    assert!(retry.admitted_scan().is_none());
    host.general_shutdown().expect("shutdown");
}

#[test]
fn retry_registration_failure_preserves_identity_and_terminalizes_coherently() {
    let directory = tempfile::tempdir().expect("tempdir");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path().join("data"),
    ));
    context_ready(&host);
    let failed_root = directory.path().join("FailedRoot");
    make_library(&failed_root, 10);
    let failed_root_id = add_root(&host, &failed_root);
    let original = start_scan(&host, failed_root_id);
    assert_eq!(terminal_state(&host, original), JobRunState::Completed);
    fs::remove_dir_all(&failed_root).expect("remove library");
    let failed = start_scan(&host, failed_root_id);
    assert_eq!(terminal_state(&host, failed), JobRunState::Failed);

    // Fill the background manager's pending bound so the retry registration
    // fails after the new JobRun/ScanRun was durably admitted.
    let mut busy_roots = Vec::with_capacity(16);
    for index in 0..16 {
        let busy = directory.path().join(format!("Busy-{index}"));
        make_library(&busy, if index == 0 { 20_000 } else { 50 });
        busy_roots.push(add_root(&host, &busy));
    }
    // Start the long scan only after all roots are configured so root
    // validation cannot consume the time that the capacity fixture relies on.
    let first_root = busy_roots.first().copied().expect("busy roots");
    let _ = start_scan(&host, first_root);
    for root_id in busy_roots.into_iter().skip(1) {
        let _ = start_scan(&host, root_id);
    }

    let manager = host.background_manager_for_tests().expect("manager");
    assert!(
        wait_until(
            || manager.active_len_for_tests() >= 16,
            Duration::from_secs(15),
        ),
        "expected all background slots to remain admitted; active={}",
        manager.active_len_for_tests(),
    );

    let error = host.retry_job(failed).expect_err("registration failure");
    assert_eq!(error.code, ErrorCode::OperationCapacityUnavailable);

    let failed_detail = host.get_job(failed).expect("source operation");
    let argus_application::OperationDetail::LibraryScan(source_operation) =
        failed_detail.operation_detail()
    else {
        panic!("expected library scan operation detail");
    };
    let successor = source_operation
        .retry_successor_job_run_id()
        .expect("successor identity preserved");
    let successor_detail = host.get_job(successor).expect("successor detail");
    assert_eq!(
        successor_detail.job().state(),
        JobRunState::Failed,
        "the durably admitted retry is terminalized, never reported as not admitted"
    );
    let root = host
        .get_library_root(failed_root_id)
        .expect("root projection");
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Failed
    );
    host.general_shutdown().expect("shutdown");
}
