//! Slice 004 runtime integration tests: the ready host exposes bounded
//! authoritative source-entry hierarchy reads over committed scan state.

use std::fs;
use std::path::Path;
use std::time::Duration;

use argus_application::{
    ErrorCode, LibraryRootId, ListSourceEntryChildrenQuery, SourceEntryClassification,
    SourceEntryKind, StartLibraryScanResult,
};
use argus_runtime::{ApplicationHost, KernelBootstrapOptions, test_support};

fn add_root(host: &ApplicationHost, path: &Path) -> LibraryRootId {
    let result = host
        .add_local_library_root(test_support::local_filesystem_root_selection(path))
        .expect("add root");
    match result {
        argus_application::AddLocalLibraryRootResult::Added(root) => root.root_id(),
        _ => panic!("expected added root"),
    }
}

fn start_scan(host: &ApplicationHost, root_id: LibraryRootId) {
    match host.start_library_scan(root_id).expect("start scan") {
        StartLibraryScanResult::Admitted(_) => {}
        StartLibraryScanResult::AlreadyScanning { .. } => panic!("expected admitted"),
    }
}

fn wait_terminal(host: &ApplicationHost, root_id: LibraryRootId) {
    let deadline = std::time::Instant::now() + Duration::from_secs(15);
    loop {
        let root = host.get_library_root(root_id).expect("root projection");
        if let Some(last) = root.last_scan()
            && last.status() == argus_application::LibraryRootLastScanStatus::Complete
        {
            return;
        }
        assert!(
            std::time::Instant::now() < deadline,
            "timed out waiting for scan completion"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn hierarchy_queries_read_committed_source_entries_through_the_host() {
    let data = tempfile::tempdir().expect("tempdir");
    let library = data.path().join("library");
    fs::create_dir_all(library.join("Sub")).expect("create library");
    fs::write(library.join("a.bin"), b"a").expect("write a");
    fs::write(library.join("Sub/b.bin"), b"b").expect("write b");

    let options = KernelBootstrapOptions::with_data_directory(data.path().to_path_buf());
    let host = ApplicationHost::new(options);
    host.initialize().expect("initialize");
    let root_id = add_root(&host, &library);
    start_scan(&host, root_id);
    wait_terminal(&host, root_id);

    let page = host
        .list_source_entry_children(ListSourceEntryChildrenQuery::new(root_id, None, None, 100))
        .expect("root children");
    let rows = page.items();
    let names: Vec<&str> = rows.iter().map(|row| row.display_name()).collect();
    assert!(names.contains(&"a.bin"), "missing file row: {names:?}");
    assert!(names.contains(&"Sub"), "missing directory row: {names:?}");
    assert!(page.next_cursor().is_none());

    let file_id = rows
        .iter()
        .find(|row| row.display_name() == "a.bin")
        .expect("file row")
        .source_entry_id();
    let dir_id = rows
        .iter()
        .find(|row| row.display_name() == "Sub")
        .expect("directory row")
        .source_entry_id();

    let file = host.get_source_entry(file_id).expect("file detail");
    assert_eq!(file.display_name(), "a.bin");
    assert_eq!(file.kind(), SourceEntryKind::File);
    assert_eq!(file.classification(), SourceEntryClassification::Unknown);
    assert_eq!(file.parent_source_entry_id(), None);

    let dir = host.get_source_entry(dir_id).expect("dir detail");
    assert_eq!(dir.kind(), SourceEntryKind::Directory);
    assert_eq!(dir.classification(), SourceEntryClassification::Container);

    let children = host
        .list_source_entry_children(ListSourceEntryChildrenQuery::new(
            root_id,
            Some(dir_id),
            None,
            100,
        ))
        .expect("dir children");
    assert_eq!(children.items().len(), 1);
    assert_eq!(children.items()[0].display_name(), "b.bin");

    let missing = host
        .get_source_entry(
            argus_application::SourceEntryId::try_from("99999999999999999999999999999999")
                .expect("missing id fixture"),
        )
        .expect_err("missing entry is a typed failure");
    assert_eq!(missing.code, ErrorCode::ConfigurationSourceEntryNotFound);

    host.general_shutdown().expect("shutdown");
}
