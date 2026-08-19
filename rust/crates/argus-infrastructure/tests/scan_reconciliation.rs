//! Slice 003 end-to-end integration tests: the real LocalFilesystem provider,
//! real SQLite repositories, and the application scan handler together must
//! preserve identity on unique native moves, remove completed-scope absences,
//! retain outside-target links, and never touch user files.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use argus_application::{
    ApplicationError, ApplicationEvent, ApplicationEventSink, ApplicationPortError,
    BackgroundOperationHandler, JobProgress, JobProgressReporter, JobRunId, JobRunRepository,
    JobRunState, LibraryRootAvailability, LibraryRootId, LibraryRootQueries, LibraryRootRepository,
    LibraryScanExecutionPlan, LibraryScanOperationHandler, LibrarySourceAccess, LibrarySourceId,
    LibrarySourceRepository, LocalFilesystemBrowseProvider, LocalFilesystemProvider,
    LocalFilesystemRootSelection, MountedLocalFilesystemVolume, NewJobRun, NewLibraryRoot,
    NewScanRun, OperationCompletion, OperationContext, OperationName, RootLocator, ScanRunId,
    ScanRunRepository, SourceEntryClassification, SourceEntryId, SourceEntryKind,
    SourceEntryRecord, SourceEntryRepository, SourceLocatorKey, SubsystemName, TraceId, UnitOfWork,
    UnitOfWorkFactory,
};
use argus_infrastructure::local_filesystem::{
    LocalFilesystemProvider as LocalFilesystemProviderImpl, LocalFilesystemSourceAccess,
};
use argus_infrastructure::sqlite::{SqliteDatabaseExecutor, SqliteLibraryRootQueries};

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("scan_reconciliation").expect("operation"),
    )
}

struct TestSink {
    events: Arc<Mutex<Vec<ApplicationEvent>>>,
}

impl ApplicationEventSink for TestSink {
    fn publish(&self, event: ApplicationEvent) {
        self.events.lock().expect("events lock").push(event);
    }
}

struct TestReporter;

impl JobProgressReporter for TestReporter {
    fn report(&self, _progress: JobProgress) -> Result<(), ApplicationError> {
        Ok(())
    }
}

fn seed_root(
    executor: &SqliteDatabaseExecutor,
    locator: &RootLocator,
) -> (LibrarySourceId, LibraryRootId, JobRunId, ScanRunId) {
    seed_root_with_presentation(executor, locator, "Games", locator.as_provider_value())
}

fn seed_root_with_presentation(
    executor: &SqliteDatabaseExecutor,
    locator: &RootLocator,
    display_name: &str,
    safe_location_display: &str,
) -> (LibrarySourceId, LibraryRootId, JobRunId, ScanRunId) {
    let locator = locator.clone();
    let display_name = display_name.to_owned();
    let safe_location_display = safe_location_display.to_owned();
    executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let root_id = scope.library_roots().insert(NewLibraryRoot::new(
                source_id,
                locator.clone(),
                display_name.clone(),
                safe_location_display.clone(),
                LibraryRootAvailability::Unknown,
                1,
            ))?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root_id,
                locator.clone(),
                &display_name,
                &safe_location_display,
                1,
                1,
                1_000,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((source_id, root_id, job, scan))
        })
        .expect("seed root")
}

fn run_scan(
    executor: &SqliteDatabaseExecutor,
    locator: &RootLocator,
    root_id: LibraryRootId,
    job: JobRunId,
    scan: ScanRunId,
) -> OperationCompletion {
    run_scan_with_access(
        executor,
        locator,
        root_id,
        job,
        scan,
        "Games",
        locator.as_provider_value(),
        LocalFilesystemSourceAccess::new(locator),
    )
}

// Keep the execution inputs explicit so provider-backed and local test cases
// exercise the same scan handler setup with only their access implementation
// varying.
#[allow(clippy::too_many_arguments)]
fn run_scan_with_access<A: LibrarySourceAccess>(
    executor: &SqliteDatabaseExecutor,
    locator: &RootLocator,
    root_id: LibraryRootId,
    job: JobRunId,
    scan: ScanRunId,
    display_name: &str,
    safe_location_display: &str,
    access: A,
) -> OperationCompletion {
    let plan = LibraryScanExecutionPlan::new(
        root_id,
        job,
        scan,
        locator.clone(),
        display_name,
        safe_location_display,
        1,
        1,
        1,
        1_000,
    );
    let events = Arc::new(Mutex::new(Vec::new()));
    let handler = LibraryScanOperationHandler::new(
        plan,
        access,
        executor.clone(),
        TestSink {
            events: Arc::clone(&events),
        },
        100,
    );
    handler
        .execute(&context(), &|| None, &TestReporter)
        .expect("scan handler completion")
}

fn terminalize_scan(executor: &SqliteDatabaseExecutor, job: JobRunId, scan: ScanRunId) {
    executor
        .execute(&context(), move |mut scope| {
            scope.scan_runs().set_status(
                scan,
                argus_application::ScanRunStatus::Complete,
                Some(2_000),
                None,
            )?;
            scope
                .job_runs()
                .set_state(job, JobRunState::Completed, 2_000)?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("terminalize");
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

struct MountedScanFixture {
    provider: LocalFilesystemProviderImpl,
    primary_path: PathBuf,
    mount_path: PathBuf,
    locator: RootLocator,
    executor: SqliteDatabaseExecutor,
    root_id: LibraryRootId,
}

impl MountedScanFixture {
    fn new(directory: &Path) -> Self {
        let primary_path = directory.join("primary");
        let mount_path = directory.join("mounted");
        fs::create_dir(&primary_path).expect("primary");
        fs::create_dir_all(mount_path.join("Games")).expect("games");

        let provider = LocalFilesystemProviderImpl::default();
        provider
            .replace_mounted_volumes(&[
                MountedLocalFilesystemVolume::new(
                    "primary".to_owned(),
                    primary_path.to_string_lossy().into_owned(),
                    "Internal storage".to_owned(),
                    true,
                    false,
                ),
                MountedLocalFilesystemVolume::new(
                    "android-volume".to_owned(),
                    mount_path.to_string_lossy().into_owned(),
                    "Game card".to_owned(),
                    false,
                    true,
                ),
            ])
            .expect("mounted snapshot");
        let mounted_root = provider
            .list_browse_roots()
            .expect("browse roots")
            .into_iter()
            .find(|root| root.display_name() == "Game card")
            .expect("mounted browse root");
        let games_page = provider
            .list_browse_directories(mounted_root.location(), None, 10)
            .expect("games page");
        let games = games_page
            .directories()
            .iter()
            .find(|directory| directory.display_name() == "Games")
            .expect("games directory");
        let locator = provider
            .validate(&LocalFilesystemRootSelection::provider_selection(
                games.location().as_provider_value().to_owned(),
            ))
            .expect("provider selection")
            .locator()
            .clone();
        let executor =
            SqliteDatabaseExecutor::open(directory.join("argus.sqlite3")).expect("database");
        let (_, root_id) = seed_configured_root(&executor, &locator, "Games", "Game card/Games");
        Self {
            provider,
            primary_path,
            mount_path,
            locator,
            executor,
            root_id,
        }
    }

    fn admit_scan(&self, started_at: i64) -> (JobRunId, ScanRunId) {
        let (_, _, job, scan) = seed_root_scan_only_with_presentation(
            &self.executor,
            self.root_id,
            &self.locator,
            started_at,
            "Games",
            "Game card/Games",
        );
        (job, scan)
    }

    fn run_scan(&self, job: JobRunId, scan: ScanRunId) -> OperationCompletion {
        let access = self
            .provider
            .open_access(&self.locator)
            .expect("source access");
        run_scan_with_access(
            &self.executor,
            &self.locator,
            self.root_id,
            job,
            scan,
            "Games",
            "Game card/Games",
            access,
        )
    }

    fn unmount_removable_volume(&self) {
        self.provider
            .replace_mounted_volumes(&[MountedLocalFilesystemVolume::new(
                "primary".to_owned(),
                self.primary_path.to_string_lossy().into_owned(),
                "Internal storage".to_owned(),
                true,
                false,
            )])
            .expect("remove removable volume");
    }

    fn shutdown(self) {
        self.executor.shutdown().expect("shutdown");
    }
}

fn seed_configured_root(
    executor: &SqliteDatabaseExecutor,
    locator: &RootLocator,
    display_name: &str,
    safe_location_display: &str,
) -> (LibrarySourceId, LibraryRootId) {
    let locator = locator.clone();
    let display_name = display_name.to_owned();
    let safe_location_display = safe_location_display.to_owned();
    executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let root_id = scope.library_roots().insert(NewLibraryRoot::new(
                source_id,
                locator,
                display_name,
                safe_location_display,
                LibraryRootAvailability::Unknown,
                1,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((source_id, root_id))
        })
        .expect("seed configured root")
}

#[test]
fn provider_locator_scan_indexes_nested_hierarchy_and_safe_root_facts() {
    let directory = tempfile::tempdir().expect("tempdir");
    let fixture = MountedScanFixture::new(directory.path());
    fs::create_dir_all(fixture.mount_path.join("Games/SNES")).expect("nested directory");
    fs::write(fixture.mount_path.join("Games/SNES/game.sfc"), b"game").expect("game");
    fs::write(fixture.mount_path.join("Games/readme.txt"), b"readme").expect("readme");

    let (job, scan) = fixture.admit_scan(1_000);
    let completion = fixture.run_scan(job, scan);
    assert_eq!(completion.state(), JobRunState::Completed);
    assert!(
        fixture
            .locator
            .as_provider_value()
            .find(&fixture.mount_path.to_string_lossy().to_string())
            .is_none()
    );
    assert!(read_locator(&fixture.executor, fixture.root_id, "SNES").is_some());
    assert!(read_locator(&fixture.executor, fixture.root_id, "SNES/game.sfc").is_some());
    assert!(read_locator(&fixture.executor, fixture.root_id, "readme.txt").is_some());

    let projection = SqliteLibraryRootQueries::new(fixture.executor.clone())
        .get(&context(), fixture.root_id)
        .expect("projection")
        .expect("root");
    assert_eq!(
        projection.availability(),
        LibraryRootAvailability::Available
    );
    assert_eq!(projection.safe_location_presentation(), "Game card/Games");
    fixture.shutdown();
}

#[test]
#[cfg(unix)]
fn provider_locator_rescan_preserves_unique_move_and_finalizes_absence() {
    let directory = tempfile::tempdir().expect("tempdir");
    let fixture = MountedScanFixture::new(directory.path());
    fs::create_dir_all(fixture.mount_path.join("Games/Sub")).expect("subdirectory");
    fs::write(fixture.mount_path.join("Games/move.bin"), b"move").expect("move");
    fs::write(fixture.mount_path.join("Games/remove.bin"), b"remove").expect("remove");

    let (job_one, scan_one) = fixture.admit_scan(1_000);
    assert_eq!(
        fixture.run_scan(job_one, scan_one).state(),
        JobRunState::Completed
    );
    let move_id = read_locator(&fixture.executor, fixture.root_id, "move.bin")
        .expect("move row")
        .source_entry_id();
    let sub_id = read_locator(&fixture.executor, fixture.root_id, "Sub")
        .expect("sub row")
        .source_entry_id();
    terminalize_scan(&fixture.executor, job_one, scan_one);

    fs::write(fixture.mount_path.join("Games/new.bin"), b"new").expect("new");
    fs::remove_file(fixture.mount_path.join("Games/remove.bin")).expect("remove");
    fs::rename(
        fixture.mount_path.join("Games/move.bin"),
        fixture.mount_path.join("Games/Sub/move.bin"),
    )
    .expect("move");

    let (job_two, scan_two) = fixture.admit_scan(2_000);
    assert_eq!(
        fixture.run_scan(job_two, scan_two).state(),
        JobRunState::Completed
    );
    assert!(read_locator(&fixture.executor, fixture.root_id, "new.bin").is_some());
    assert_eq!(
        read_locator(&fixture.executor, fixture.root_id, "remove.bin"),
        None
    );
    let moved =
        read_locator(&fixture.executor, fixture.root_id, "Sub/move.bin").expect("moved row");
    assert_eq!(moved.source_entry_id(), move_id);
    assert_eq!(moved.parent_source_entry_id(), Some(sub_id));
    fixture.shutdown();
}

#[test]
fn unavailable_provider_locator_scan_preserves_prior_entries() {
    let directory = tempfile::tempdir().expect("tempdir");
    let fixture = MountedScanFixture::new(directory.path());
    fs::write(fixture.mount_path.join("Games/keep.bin"), b"keep").expect("keep");

    let (job_one, scan_one) = fixture.admit_scan(1_000);
    assert_eq!(
        fixture.run_scan(job_one, scan_one).state(),
        JobRunState::Completed
    );
    terminalize_scan(&fixture.executor, job_one, scan_one);
    fixture.unmount_removable_volume();

    let (job_two, scan_two) = fixture.admit_scan(2_000);
    assert_eq!(
        fixture.run_scan(job_two, scan_two).state(),
        JobRunState::Failed
    );
    let projection = SqliteLibraryRootQueries::new(fixture.executor.clone())
        .get(&context(), fixture.root_id)
        .expect("projection")
        .expect("root");
    assert_eq!(
        projection.availability(),
        LibraryRootAvailability::Unavailable
    );
    assert_eq!(
        projection.last_scan().expect("last scan").status(),
        argus_application::LibraryRootLastScanStatus::Unavailable
    );
    assert!(read_locator(&fixture.executor, fixture.root_id, "keep.bin").is_some());
    fixture.shutdown();
}

#[test]
#[cfg(unix)]
fn real_provider_rescan_preserves_unique_native_move_and_removes_absences() {
    let directory = tempfile::tempdir().expect("tempdir");
    let library = directory.path().join("Library");
    fs::create_dir_all(library.join("Sub")).expect("sub");
    fs::write(library.join("a.bin"), b"a").expect("a");
    fs::write(library.join("b.bin"), b"b").expect("b");
    fs::write(library.join("Sub/nested.txt"), b"n").expect("nested");
    let locator = RootLocator::from_provider(library.to_string_lossy().into_owned());

    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (_, root, job_one, scan_one) = seed_root(&executor, &locator);
    let completion = run_scan(&executor, &locator, root, job_one, scan_one);
    assert_eq!(completion.state(), JobRunState::Completed);
    let _a_id = read_locator(&executor, root, "a.bin")
        .expect("a row")
        .source_entry_id();
    let b_id = read_locator(&executor, root, "b.bin")
        .expect("b row")
        .source_entry_id();
    let sub_id = read_locator(&executor, root, "Sub")
        .expect("Sub row")
        .source_entry_id();

    // The provider reports a stable unix identity, so a rename must preserve
    // SourceEntryId while the old locator disappears from the graph.
    fs::remove_file(library.join("a.bin")).expect("remove a");
    fs::rename(library.join("b.bin"), library.join("Sub/b.bin")).expect("move b");
    terminalize_scan(&executor, job_one, scan_one);
    let (_, _, job_two, scan_two) = seed_root_scan_only(&executor, root, &locator, 2_000);
    let completion = run_scan(&executor, &locator, root, job_two, scan_two);
    assert_eq!(completion.state(), JobRunState::Completed);

    assert_eq!(
        read_locator(&executor, root, "a.bin"),
        None,
        "absent root child removed by finalization"
    );
    assert_eq!(read_locator(&executor, root, "b.bin"), None);
    let moved = read_locator(&executor, root, "Sub/b.bin").expect("moved row");
    assert_eq!(
        moved.source_entry_id(),
        b_id,
        "unique native move preserves identity"
    );
    assert_eq!(moved.parent_source_entry_id(), Some(sub_id));
    assert!(
        read_locator(&executor, root, "Sub/nested.txt").is_some(),
        "unchanged nested entry retained"
    );
    assert_eq!(
        read_children(&executor, root, None).len(),
        1,
        "only Sub remains at root"
    );

    let projection = SqliteLibraryRootQueries::new(executor.clone())
        .get(&context(), root)
        .expect("projection")
        .expect("root");
    assert_eq!(
        projection.availability(),
        LibraryRootAvailability::Available
    );
    assert_eq!(
        projection.last_scan().expect("last scan").status(),
        argus_application::LibraryRootLastScanStatus::Complete
    );
    executor.shutdown().expect("shutdown");
}

fn seed_root_scan_only(
    executor: &SqliteDatabaseExecutor,
    root: LibraryRootId,
    locator: &RootLocator,
    started_at: i64,
) -> (LibrarySourceId, LibraryRootId, JobRunId, ScanRunId) {
    seed_root_scan_only_with_presentation(
        executor,
        root,
        locator,
        started_at,
        "Games",
        locator.as_provider_value(),
    )
}

fn seed_root_scan_only_with_presentation(
    executor: &SqliteDatabaseExecutor,
    root: LibraryRootId,
    locator: &RootLocator,
    started_at: i64,
    display_name: &str,
    safe_location_display: &str,
) -> (LibrarySourceId, LibraryRootId, JobRunId, ScanRunId) {
    let locator = locator.clone();
    let display_name = display_name.to_owned();
    let safe_location_display = safe_location_display.to_owned();
    executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", started_at))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                locator.clone(),
                &display_name,
                &safe_location_display,
                1,
                1,
                started_at,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((source_id, root, job, scan))
        })
        .expect("seed scan")
}

#[test]
#[cfg(unix)]
fn real_provider_outside_target_link_is_retained_without_failing_the_scan() {
    let directory = tempfile::tempdir().expect("tempdir");
    let outside = directory.path().join("outside.bin");
    fs::write(&outside, b"outside").expect("outside");
    let library = directory.path().join("Library");
    fs::create_dir_all(&library).expect("library");
    fs::write(library.join("rom.bin"), b"rom").expect("rom");
    std::os::unix::fs::symlink(&outside, library.join("escape")).expect("symlink");
    let locator = RootLocator::from_provider(library.to_string_lossy().into_owned());

    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (_, root, job, scan) = seed_root(&executor, &locator);
    let completion = run_scan(&executor, &locator, root, job, scan);
    assert_eq!(completion.state(), JobRunState::Completed);
    let children = read_children(&executor, root, None);
    assert!(
        children
            .iter()
            .any(|record| record.display_name() == "rom.bin")
    );
    let escape = children
        .iter()
        .find(|record| record.display_name() == "escape")
        .expect("link-like entry retained");
    assert_eq!(escape.kind(), SourceEntryKind::LinkLike);
    assert_eq!(escape.classification(), SourceEntryClassification::Ignored);
    executor.shutdown().expect("shutdown");
}

#[test]
fn real_provider_scans_never_mutate_user_files() {
    let directory = tempfile::tempdir().expect("tempdir");
    let library = directory.path().join("Library");
    fs::create_dir_all(library.join("Sub")).expect("sub");
    fs::write(library.join("a.bin"), b"alpha").expect("a");
    fs::write(library.join("Sub/nested.txt"), b"nested").expect("nested");
    let locator = RootLocator::from_provider(library.to_string_lossy().into_owned());

    let snapshot = |library: &Path| {
        let mut paths: Vec<String> = Vec::new();
        for entry in walkdir_lite(library) {
            paths.push(entry);
        }
        paths.sort();
        paths
    };
    let before = snapshot(&library);

    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (_, root, job, scan) = seed_root(&executor, &locator);
    assert_eq!(
        run_scan(&executor, &locator, root, job, scan).state(),
        JobRunState::Completed
    );
    assert_eq!(
        snapshot(&library),
        before,
        "scan must not change user files"
    );
    executor.shutdown().expect("shutdown");
}

fn walkdir_lite(root: &Path) -> Vec<String> {
    let mut result = Vec::new();
    fn visit(root: &Path, relative: &Path, result: &mut Vec<String>) {
        for entry in fs::read_dir(root).expect("read dir") {
            let entry = entry.expect("entry");
            let name = entry.file_name().to_string_lossy().into_owned();
            let child_relative = relative.join(&name);
            let metadata = fs::symlink_metadata(entry.path()).expect("metadata");
            let kind = if metadata.is_dir() {
                "dir"
            } else if metadata.file_type().is_symlink() {
                "link"
            } else {
                "file"
            };
            let contents = if kind == "file" {
                fs::read(entry.path())
                    .map(|bytes| format!("{:x?}", bytes))
                    .unwrap_or_else(|_| "unreadable".to_owned())
            } else {
                String::new()
            };
            result.push(format!(
                "{}:{}:{}",
                child_relative.to_string_lossy(),
                kind,
                contents
            ));
            if kind == "dir" {
                visit(&entry.path(), &child_relative, result);
            }
        }
    }
    visit(root, Path::new(""), &mut result);
    result
}
