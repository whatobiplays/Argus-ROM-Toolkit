//! Runtime contract tests for the Slice 001 library-root workflow.

use std::fs;
use std::sync::{Arc, Mutex};

use argus_application::{
    AddLocalLibraryRootResult, EventSubscriberError, LibraryRootChanged, LibraryRootsChanged,
    LibraryRootsSubscriber, ListLibraryRootsQuery, LocalFilesystemRootSelection,
};
use argus_runtime::{
    ApplicationHost, EventBus, KernelBootstrapOptions, bootstrap_kernel_with_event_bus,
};
use tempfile::tempdir;

#[derive(Clone)]
struct CountingSourcesSubscriber {
    calls: Arc<Mutex<Vec<String>>>,
}

impl LibraryRootsSubscriber for CountingSourcesSubscriber {
    fn library_roots_changed(
        &self,
        _event: LibraryRootsChanged,
    ) -> Result<(), EventSubscriberError> {
        self.calls
            .lock()
            .expect("subscriber lock")
            .push("roots".to_owned());
        Ok(())
    }

    fn library_root_changed(&self, event: LibraryRootChanged) -> Result<(), EventSubscriberError> {
        self.calls
            .lock()
            .expect("subscriber lock")
            .push(format!("root:{}", event.library_root_id));
        Ok(())
    }
}

fn selection(path: &std::path::Path) -> LocalFilesystemRootSelection {
    LocalFilesystemRootSelection::new(path.to_string_lossy().into_owned())
}

fn list_all() -> ListLibraryRootsQuery {
    ListLibraryRootsQuery::new(0, 100)
}

#[test]
fn host_round_trips_configured_roots_through_the_authoritative_backend() {
    let directory = tempdir().expect("temporary directory");
    let library = directory.path().join("Games");
    fs::create_dir(&library).expect("library directory");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path(),
    ));
    host.initialize().expect("ready runtime");

    let added = host
        .add_local_library_root(selection(&library))
        .expect("added");
    let AddLocalLibraryRootResult::Added(root) = added else {
        panic!("expected Added outcome");
    };
    assert_eq!(root.display_name(), "Games");
    assert_eq!(root.safe_location_presentation(), library.to_string_lossy());
    assert_eq!(
        host.get_library_root(root.root_id())
            .expect("authoritative root")
            .root_id(),
        root.root_id()
    );
    let page = host.list_library_roots(list_all()).expect("root list");
    assert_eq!(page.total_count(), 1);
    assert_eq!(page.items()[0].root_id(), root.root_id());

    assert_eq!(
        host.remove_library_root(root.root_id()).expect("removed"),
        argus_application::RemoveLibraryRootResult::Removed
    );
    assert_eq!(
        host.list_library_roots(list_all())
            .expect("empty list")
            .total_count(),
        0
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn configured_roots_survive_restart() {
    let directory = tempdir().expect("temporary directory");
    let library = directory.path().join("Games");
    fs::create_dir(&library).expect("library directory");
    let options = KernelBootstrapOptions::with_data_directory(directory.path());

    let seed = ApplicationHost::new(options.clone());
    seed.initialize().expect("seed runtime");
    let added = seed
        .add_local_library_root(selection(&library))
        .expect("added");
    let root_id = match added {
        AddLocalLibraryRootResult::Added(root) => root.root_id(),
        _ => panic!("expected Added"),
    };
    seed.general_shutdown().expect("seed shutdown");

    let host = ApplicationHost::new(options);
    host.initialize().expect("reopened runtime");
    let page = host.list_library_roots(list_all()).expect("root list");
    assert_eq!(page.total_count(), 1);
    assert_eq!(page.items()[0].root_id(), root_id);
    assert_eq!(
        host.get_library_root(root_id).expect("root").root_id(),
        root_id
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn add_validation_failures_are_typed_and_sanitized() {
    let directory = tempdir().expect("temporary directory");
    let file = directory.path().join("rom.bin");
    fs::write(&file, b"rom").expect("file");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path(),
    ));
    host.initialize().expect("ready runtime");

    let error = host
        .add_local_library_root(selection(&file))
        .expect_err("file is not a root");
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.FILESYSTEM.INVALID_ROOT_SELECTION"
    );

    let error = host
        .add_local_library_root(LocalFilesystemRootSelection::new("relative".to_owned()))
        .expect_err("relative path");
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.FILESYSTEM.INVALID_ROOT_SELECTION"
    );

    let error = host
        .add_local_library_root(selection(&directory.path().join("Missing")))
        .expect_err("missing path");
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.FILESYSTEM.INVALID_ROOT_SELECTION"
    );
    assert_eq!(
        host.list_library_roots(list_all())
            .expect("empty list")
            .total_count(),
        0
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn missing_root_is_a_typed_configuration_failure() {
    let directory = tempdir().expect("temporary directory");
    let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
        directory.path(),
    ));
    host.initialize().expect("ready runtime");
    let id = argus_application::LibraryRootId::try_from("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        .expect("fixture id");

    let error = host.get_library_root(id).expect_err("missing root");

    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND"
    );
    host.general_shutdown().expect("shutdown");
}

#[test]
fn duplicate_add_is_idempotent_and_emits_no_second_creation() {
    let directory = tempdir().expect("temporary directory");
    let library = directory.path().join("Games");
    fs::create_dir(&library).expect("library directory");
    let calls = Arc::new(Mutex::new(Vec::new()));
    let bus = EventBus::new(
        Vec::new(),
        vec![Box::new(CountingSourcesSubscriber {
            calls: Arc::clone(&calls),
        })],
    );
    let kernel = bootstrap_kernel_with_event_bus(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        bus,
    )
    .expect("kernel");
    let selection = selection(&library);

    let first = kernel
        .add_local_library_root(selection.clone())
        .expect("first add");
    let first_id = match &first {
        AddLocalLibraryRootResult::Added(root) => root.root_id(),
        _ => panic!("expected Added"),
    };
    assert_eq!(
        kernel
            .add_local_library_root(selection)
            .expect("repeated add"),
        AddLocalLibraryRootResult::AlreadyConfigured(first_id)
    );
    assert_eq!(
        kernel
            .list_library_roots(list_all())
            .expect("list")
            .total_count(),
        1
    );
    assert_eq!(
        &*calls.lock().expect("events"),
        &["roots".to_owned(), format!("root:{first_id}")]
    );

    assert_eq!(
        kernel.remove_library_root(first_id).expect("removed"),
        argus_application::RemoveLibraryRootResult::Removed
    );
    assert_eq!(
        &*calls.lock().expect("events"),
        &[
            "roots".to_owned(),
            format!("root:{first_id}"),
            "roots".to_owned(),
            format!("root:{first_id}"),
        ]
    );
    kernel.shutdown().expect("shutdown");
}

#[test]
fn removing_a_missing_root_is_idempotent_without_events() {
    let directory = tempdir().expect("temporary directory");
    let calls = Arc::new(Mutex::new(Vec::new()));
    let bus = EventBus::new(
        Vec::new(),
        vec![Box::new(CountingSourcesSubscriber {
            calls: Arc::clone(&calls),
        })],
    );
    let kernel = bootstrap_kernel_with_event_bus(
        KernelBootstrapOptions::with_data_directory(directory.path()),
        bus,
    )
    .expect("kernel");
    let id = argus_application::LibraryRootId::try_from("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        .expect("fixture id");

    assert_eq!(
        kernel.remove_library_root(id).expect("removed"),
        argus_application::RemoveLibraryRootResult::Removed
    );
    assert!(calls.lock().expect("events").is_empty());
    kernel.shutdown().expect("shutdown");
}
