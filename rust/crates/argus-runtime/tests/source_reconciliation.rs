//! Slice 003 runtime integration tests: repeat LibraryScan execution through
//! the host must durably reconcile the source graph, survive runtime and
//! database recreation, keep availability evidence truthful, and never mutate
//! user files.

use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

use argus_application::{
    ApplicationPortError, JobRunId, JobRunState, JobsQueries, LibraryRootAvailability,
    LibraryRootId, LibraryRootLastScanStatus, LibraryRootQueries, LocalFilesystemRootSelection,
    SourceEntryId, SourceEntryKind, SourceEntryRecord, SourceEntryRepository, SourceLocatorKey,
    StartLibraryScanResult, UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use argus_runtime::{ApplicationHost, KernelBootstrapOptions};

fn context() -> argus_application::OperationContext {
    argus_application::OperationContext::new(
        argus_application::TraceId::try_from(1).expect("trace"),
        argus_application::SubsystemName::try_from("test").expect("subsystem"),
        argus_application::OperationName::try_from("source_reconciliation").expect("operation"),
    )
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
        argus_application::AddLocalLibraryRootResult::Added(root) => root.root_id(),
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

fn open_executor(data: &Path) -> SqliteDatabaseExecutor {
    SqliteDatabaseExecutor::open(data.join("argus.sqlite3")).expect("database")
}

fn read_locator(
    executor: &SqliteDatabaseExecutor,
    root: LibraryRootId,
    locator: &str,
) -> Option<SourceEntryRecord> {
    let locator = locator.to_owned();
    executor
        .execute(&context(), move |mut scope| {
            let found = scope
                .source_entries()
                .find_by_locator_key(root, &SourceLocatorKey::from_provider(locator))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>(found)
        })
        .expect("read locator")
}

fn read_children(
    executor: &SqliteDatabaseExecutor,
    root: LibraryRootId,
    parent: Option<SourceEntryId>,
) -> Vec<SourceEntryRecord> {
    executor
        .execute(&context(), move |mut scope| {
            let children = scope
                .source_entries()
                .list_children(root, parent, 0, 1_000)?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>(children)
        })
        .expect("read children")
}

#[test]
#[cfg(unix)]
fn rescan_preserves_unique_native_move_and_removes_absences_across_recreation() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data = directory.path().join("data");
    let library = directory.path().join("Library");
    fs::create_dir_all(library.join("Sub")).expect("sub");
    fs::write(library.join("a.bin"), b"a").expect("a");
    fs::write(library.join("b.bin"), b"b").expect("b");
    fs::write(library.join("Sub/nested.txt"), b"n").expect("nested");
    let options = KernelBootstrapOptions::with_data_directory(data.clone());

    let first = ApplicationHost::new(options.clone());
    first.initialize().expect("first initialize");
    let root_id = add_root(&first, &library);
    assert_eq!(
        terminal_state(&first, start_scan(&first, root_id)),
        JobRunState::Completed
    );
    first.general_shutdown().expect("first shutdown");

    let (_a_id, b_id, sub_id) = {
        let executor = open_executor(&data);
        let a = read_locator(&executor, root_id, "a.bin").expect("a row");
        let b = read_locator(&executor, root_id, "b.bin").expect("b row");
        let sub = read_locator(&executor, root_id, "Sub").expect("Sub row");
        let ids = (
            a.source_entry_id(),
            b.source_entry_id(),
            sub.source_entry_id(),
        );
        executor.shutdown().expect("executor shutdown");
        ids
    };

    fs::remove_file(library.join("a.bin")).expect("remove a");
    fs::rename(library.join("b.bin"), library.join("Sub/b.bin")).expect("move b");

    let second = ApplicationHost::new(options);
    second.initialize().expect("second initialize");
    assert_eq!(
        terminal_state(&second, start_scan(&second, root_id)),
        JobRunState::Completed
    );
    second.general_shutdown().expect("second shutdown");

    let executor = open_executor(&data);
    assert_eq!(read_locator(&executor, root_id, "a.bin"), None);
    assert_eq!(read_locator(&executor, root_id, "b.bin"), None);
    let moved = read_locator(&executor, root_id, "Sub/b.bin").expect("moved row");
    assert_eq!(
        moved.source_entry_id(),
        b_id,
        "identity survives runtime recreation"
    );
    assert_eq!(moved.parent_source_entry_id(), Some(sub_id));
    assert_eq!(
        read_children(&executor, root_id, None)
            .iter()
            .map(SourceEntryRecord::display_name)
            .collect::<Vec<_>>(),
        vec!["Sub"]
    );

    let root = argus_infrastructure::sqlite::SqliteLibraryRootQueries::new(executor.clone())
        .get(&context(), root_id)
        .expect("root projection")
        .expect("configured root");
    assert_eq!(root.availability(), LibraryRootAvailability::Available);
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Complete
    );
    let jobs = argus_infrastructure::sqlite::SqliteJobsQueries::new(executor.clone())
        .list_recent_terminal(&context(), 0, 20)
        .expect("recent jobs");
    assert_eq!(jobs.total_count(), 2, "both scans remain terminal history");
    executor.shutdown().expect("executor shutdown");
}

#[test]
fn rescan_removes_absent_entries_and_keeps_graph_durable() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data = directory.path().join("data");
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library");
    fs::write(library.join("a.bin"), b"a").expect("a");
    fs::write(library.join("b.bin"), b"b").expect("b");
    let options = KernelBootstrapOptions::with_data_directory(data.clone());

    let first = ApplicationHost::new(options.clone());
    first.initialize().expect("first initialize");
    let root_id = add_root(&first, &library);
    assert_eq!(
        terminal_state(&first, start_scan(&first, root_id)),
        JobRunState::Completed
    );
    first.general_shutdown().expect("first shutdown");

    fs::remove_file(library.join("a.bin")).expect("remove a");
    fs::rename(library.join("b.bin"), library.join("c.bin")).expect("rename b");

    let second = ApplicationHost::new(options);
    second.initialize().expect("second initialize");
    assert_eq!(
        terminal_state(&second, start_scan(&second, root_id)),
        JobRunState::Completed
    );
    second.general_shutdown().expect("second shutdown");

    let executor = open_executor(&data);
    assert_eq!(read_locator(&executor, root_id, "a.bin"), None);
    assert_eq!(read_locator(&executor, root_id, "b.bin"), None);
    assert!(read_locator(&executor, root_id, "c.bin").is_some());
    assert_eq!(read_children(&executor, root_id, None).len(), 1);
    executor.shutdown().expect("executor shutdown");
}

#[test]
fn runtime_scans_never_mutate_user_files() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data = directory.path().join("data");
    let library = directory.path().join("Library");
    fs::create_dir_all(library.join("Sub")).expect("sub");
    fs::write(library.join("a.bin"), b"alpha").expect("a");
    fs::write(library.join("b.bin"), b"beta").expect("b");
    fs::write(library.join("Sub/nested.txt"), b"nested").expect("nested");

    let snapshot = |library: &Path| {
        let mut files = Vec::new();
        fn visit(root: &Path, relative: &Path, files: &mut Vec<String>) {
            for entry in fs::read_dir(root).expect("read dir") {
                let entry = entry.expect("entry");
                let name = entry.file_name().to_string_lossy().into_owned();
                let child = relative.join(&name);
                let metadata = fs::symlink_metadata(entry.path()).expect("metadata");
                if metadata.is_dir() {
                    visit(&entry.path(), &child, files);
                } else if metadata.file_type().is_symlink() {
                    files.push(format!("{}:link", child.to_string_lossy()));
                } else {
                    let bytes = fs::read(entry.path()).expect("read file");
                    files.push(format!(
                        "{}:file:{}",
                        child.to_string_lossy(),
                        bytes
                            .iter()
                            .map(|byte| format!("{byte:02x}"))
                            .collect::<String>()
                    ));
                }
            }
        }
        visit(library, Path::new(""), &mut files);
        files.sort();
        files
    };

    let options = KernelBootstrapOptions::with_data_directory(data.clone());
    let host = ApplicationHost::new(options.clone());
    host.initialize().expect("initialize");
    let root_id = add_root(&host, &library);
    let original = snapshot(&library);
    assert_eq!(
        terminal_state(&host, start_scan(&host, root_id)),
        JobRunState::Completed
    );
    assert_eq!(
        snapshot(&library),
        original,
        "first scan leaves user files untouched"
    );

    fs::remove_file(library.join("b.bin")).expect("remove b");
    let after_removal = snapshot(&library);
    assert_eq!(
        terminal_state(&host, start_scan(&host, root_id)),
        JobRunState::Completed
    );
    assert_eq!(
        snapshot(&library),
        after_removal,
        "second scan leaves user files untouched"
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
#[cfg(unix)]
fn runtime_scan_retains_outside_target_link_without_failing() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data = directory.path().join("data");
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library");
    fs::write(library.join("rom.bin"), b"rom").expect("rom");
    let outside = directory.path().join("outside.bin");
    fs::write(&outside, b"outside").expect("outside");
    std::os::unix::fs::symlink(&outside, library.join("escape")).expect("symlink");

    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(data.clone()));
    host.initialize().expect("initialize");
    let root_id = add_root(&host, &library);
    assert_eq!(
        terminal_state(&host, start_scan(&host, root_id)),
        JobRunState::Completed
    );
    host.general_shutdown().expect("shutdown");

    let executor = open_executor(&data);
    let children = read_children(&executor, root_id, None);
    let escape = children
        .iter()
        .find(|record| record.display_name() == "escape")
        .expect("link-like entry retained");
    assert_eq!(escape.kind(), SourceEntryKind::LinkLike);
    executor.shutdown().expect("executor shutdown");
}

#[test]
fn missing_root_directory_reports_unavailable_terminal_state() {
    let directory = tempfile::tempdir().expect("tempdir");
    let data = directory.path().join("data");
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library");

    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(data));
    host.initialize().expect("initialize");
    let root_id = add_root(&host, &library);
    fs::remove_dir_all(&library).expect("remove library");
    let job_run_id = start_scan(&host, root_id);
    assert_eq!(terminal_state(&host, job_run_id), JobRunState::Failed);
    let root = host.get_library_root(root_id).expect("root projection");
    assert_eq!(
        root.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Unavailable
    );
    assert_eq!(root.availability(), LibraryRootAvailability::Unavailable);
    host.general_shutdown().expect("shutdown");
}
