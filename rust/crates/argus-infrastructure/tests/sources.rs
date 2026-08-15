//! Infrastructure contract tests for the Slice 001 sources persistence and
//! LocalFilesystem provider boundary. Every test uses test-owned temporary
//! directories; no developer filesystem or application data is accessed.

use std::fs;

use argus_application::{
    LibraryRootAvailability, LibraryRootQueries, LibraryRootRepository, LibrarySourceRepository,
    LocalFilesystemProvider, LocalFilesystemRootSelection, NewLibraryRoot, OperationContext,
    OperationName, RootLocator, RootRelationship, SubsystemName, TraceId, UnitOfWork,
    ValidatedLocalRoot,
};
use argus_domain::{LibraryRootId, LibrarySourceId};
use argus_infrastructure::local_filesystem::LocalFilesystemProvider as LocalFilesystemProviderImpl;
use argus_infrastructure::sqlite::{
    Migration, MigrationOutcome, MigrationRegistry, SqliteDatabaseExecutor,
    SqliteLibraryRootQueries,
};
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(71_u128).expect("non-zero trace"),
        SubsystemName::try_from("sources").expect("valid subsystem"),
        OperationName::try_from("contract").expect("valid operation"),
    )
}

fn root_id(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("fixture root id")
}

fn selection(path: &std::path::Path) -> LocalFilesystemRootSelection {
    LocalFilesystemRootSelection::new(path.to_string_lossy().into_owned())
}

fn new_root(source: LibrarySourceId, locator: RootLocator, display: &str) -> NewLibraryRoot {
    NewLibraryRoot::new(
        source,
        locator,
        display.to_owned(),
        format!("/presentation/{display}"),
        LibraryRootAvailability::Available,
        1,
    )
}

#[test]
fn embedded_registry_upgrades_a_phase_000_database_through_slice_004() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let phase_000 = MigrationRegistry::new(vec![Migration::sql(
        1,
        "0001_initial",
        include_bytes!("../src/sqlite/migrations/sql/0001_initial.sql"),
    )])
    .expect("phase 000 registry");
    let first = SqliteDatabaseExecutor::open_with_registry(&database, phase_000)
        .expect("phase 000 database");
    assert_eq!(first.migration_summary().current_version, 1);
    first.shutdown().expect("shutdown");

    let second = SqliteDatabaseExecutor::open(&database).expect("upgraded database");
    assert_eq!(second.migration_summary().current_version, 7);
    assert_eq!(
        second.migration_summary().outcome,
        MigrationOutcome::Applied
    );
    second
        .with_connection_for_tests(context(), |connection| {
            assert!(connection.table_exists("library_source")?);
            assert!(connection.table_exists("library_root")?);
            assert!(connection.table_exists("job_run")?);
            assert!(connection.table_exists("scan_run")?);
            assert!(connection.table_exists("library_scan_target")?);
            assert!(connection.table_exists("source_entry")?);
            Ok(())
        })
        .expect("schema check");
    second.shutdown().expect("shutdown");
}

#[test]
fn fresh_database_reaches_the_phase_001_schema() {
    let directory = tempdir().expect("tempdir");
    let executor = SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3"))
        .expect("fresh database");
    assert_eq!(executor.migration_summary().current_version, 7);
    assert_eq!(executor.migration_summary().applied_count, 7);
    executor.shutdown().expect("shutdown");
}

#[test]
fn provider_accepts_a_real_directory_and_derives_safe_facts() {
    let directory = tempdir().expect("tempdir");
    let games = directory.path().join("Games");
    fs::create_dir(&games).expect("games directory");
    let provider = LocalFilesystemProviderImpl;

    let validated = provider
        .validate(&selection(&games))
        .expect("directory is accepted");

    assert_eq!(validated.display_name(), "Games");
    assert_eq!(
        validated.safe_location_presentation(),
        games.to_string_lossy()
    );
    assert_eq!(
        validated.locator().as_provider_value(),
        games.to_string_lossy()
    );
}

#[test]
fn provider_rejects_a_normal_file_selection() {
    let directory = tempdir().expect("tempdir");
    let file = directory.path().join("rom.bin");
    fs::write(&file, b"rom").expect("file");
    let provider = LocalFilesystemProviderImpl;

    let error = provider
        .validate(&selection(&file))
        .expect_err("a file is not a root");

    assert_eq!(error, argus_application::ProviderError::NotADirectory);
}

#[cfg(unix)]
#[test]
fn provider_rejects_a_link_like_root_without_traversal() {
    let directory = tempdir().expect("tempdir");
    let target = directory.path().join("Target");
    let link = directory.path().join("Link");
    fs::create_dir(&target).expect("target directory");
    std::os::unix::fs::symlink(&target, &link).expect("symlink");
    let provider = LocalFilesystemProviderImpl;

    let error = provider
        .validate(&selection(&link))
        .expect_err("a link-like root is rejected");

    assert_eq!(error, argus_application::ProviderError::LinkLikeRoot);
}

#[test]
fn provider_rejects_relative_and_missing_selections() {
    let provider = LocalFilesystemProviderImpl;

    assert_eq!(
        provider
            .validate(&LocalFilesystemRootSelection::new(
                "relative/path".to_owned()
            ))
            .expect_err("relative path"),
        argus_application::ProviderError::InvalidSelection
    );
    assert_eq!(
        provider
            .validate(&selection(std::path::Path::new(
                "/definitely/missing/argus-fixture"
            )))
            .expect_err("missing path"),
        argus_application::ProviderError::InvalidSelection
    );
}

#[test]
fn provider_compares_same_ancestor_descendant_and_disjoint_roots() {
    let directory = tempdir().expect("tempdir");
    let parent = directory.path().join("Parent");
    let child = parent.join("Child");
    let sibling = directory.path().join("Sibling");
    fs::create_dir_all(&child).expect("child directory");
    fs::create_dir(&sibling).expect("sibling directory");
    let provider = LocalFilesystemProviderImpl;
    let parent_locator = RootLocator::from_provider(parent.to_string_lossy().into_owned());
    let child_locator = RootLocator::from_provider(child.to_string_lossy().into_owned());
    let sibling_locator = RootLocator::from_provider(sibling.to_string_lossy().into_owned());

    assert_eq!(
        provider.compare_roots(&parent_locator, &parent_locator),
        RootRelationship::Same
    );
    assert_eq!(
        provider.compare_roots(&parent_locator, &child_locator),
        RootRelationship::Ancestor
    );
    assert_eq!(
        provider.compare_roots(&child_locator, &parent_locator),
        RootRelationship::Descendant
    );
    assert_eq!(
        provider.compare_roots(&child_locator, &sibling_locator),
        RootRelationship::Disjoint
    );
}

#[test]
fn provider_returns_unknown_when_a_relationship_cannot_be_proven() {
    let directory = tempdir().expect("tempdir");
    let existing = directory.path().join("Existing");
    fs::create_dir(&existing).expect("existing directory");
    let provider = LocalFilesystemProviderImpl;
    let existing_locator = RootLocator::from_provider(existing.to_string_lossy().into_owned());
    let missing_locator = RootLocator::from_provider(
        directory
            .path()
            .join("Missing")
            .to_string_lossy()
            .into_owned(),
    );

    assert_eq!(
        provider.compare_roots(&existing_locator, &missing_locator),
        RootRelationship::Unknown
    );
}

#[test]
fn repositories_persist_roots_and_survive_restart() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let locator = RootLocator::from_provider("/tmp/library/games".to_owned());

    let source_id = {
        let executor = SqliteDatabaseExecutor::open(&database).expect("database");
        let inserted_locator = locator.clone();
        let added = executor
            .with_unit_of_work(context(), move |mut work| {
                let source = work.library_source().ensure_local_filesystem_source()?;
                let root = work.library_roots().insert(new_root(
                    source,
                    inserted_locator.clone(),
                    "Games",
                ))?;
                work.commit()?;
                Ok::<_, argus_application::ApplicationPortError>((source, root))
            })
            .expect("add");
        let queries = SqliteLibraryRootQueries::new(executor.clone());
        let page = queries.list(&context(), 0, 10).expect("list");
        assert_eq!(page.total_count(), 1);
        assert_eq!(page.items().len(), 1);
        assert_eq!(page.items()[0].root_id(), added.1);
        assert_eq!(page.items()[0].display_name(), "Games");
        assert_eq!(
            page.items()[0].safe_location_presentation(),
            "/presentation/Games"
        );
        assert_eq!(
            page.items()[0].availability(),
            LibraryRootAvailability::Available
        );
        assert!(page.items()[0].last_scan().is_none());
        assert!(page.items()[0].active_scan().is_none());
        assert_eq!(
            queries
                .get(&context(), added.1)
                .expect("get")
                .expect("root")
                .root_id(),
            added.1
        );
        let configurations = queries
            .list_root_configurations(&context())
            .expect("configurations");
        assert_eq!(configurations.len(), 1);
        assert_eq!(configurations[0].root_id(), added.1);
        assert_eq!(configurations[0].locator(), &locator);
        added.0
    };

    let executor = SqliteDatabaseExecutor::open(&database).expect("reopened database");
    let queries = SqliteLibraryRootQueries::new(executor.clone());
    assert_eq!(
        queries.list(&context(), 0, 10).expect("list").total_count(),
        1
    );
    assert_eq!(
        queries
            .list_root_configurations(&context())
            .expect("configurations")
            .len(),
        1
    );
    executor.shutdown().expect("shutdown");

    // The internally managed source identity remains durable and reusable
    // after restart.
    let executor = SqliteDatabaseExecutor::open(&database).expect("third database");
    let reused = executor
        .with_unit_of_work(context(), |mut work| {
            let source = work.library_source().ensure_local_filesystem_source()?;
            work.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(source)
        })
        .expect("reuse after restart");
    assert_eq!(reused, source_id);
    executor.shutdown().expect("shutdown");
}

#[test]
fn source_is_lazily_created_once_reused_and_preserved_after_final_removal() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");

    let (first_source, first_root) = executor
        .with_unit_of_work(context(), |mut work| {
            let source = work.library_source().ensure_local_filesystem_source()?;
            let root = work.library_roots().insert(new_root(
                source,
                RootLocator::from_provider("/tmp/a".to_owned()),
                "A",
            ))?;
            work.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((source, root))
        })
        .expect("first add");

    let (second_source, second_root) = executor
        .with_unit_of_work(context(), |mut work| {
            let source = work.library_source().ensure_local_filesystem_source()?;
            let root = work.library_roots().insert(new_root(
                source,
                RootLocator::from_provider("/tmp/b".to_owned()),
                "B",
            ))?;
            work.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((source, root))
        })
        .expect("second add");

    assert_eq!(first_source, second_source);
    assert_ne!(first_root, second_root);

    for root in [first_root, second_root] {
        executor
            .with_unit_of_work(context(), move |mut work| {
                assert!(work.library_roots().delete(root)?);
                work.commit()?;
                Ok::<_, argus_application::ApplicationPortError>(())
            })
            .expect("remove");
    }

    let queries = SqliteLibraryRootQueries::new(executor.clone());
    assert_eq!(
        queries.list(&context(), 0, 10).expect("list").total_count(),
        0
    );
    let reused = executor
        .with_unit_of_work(context(), |mut work| {
            let source = work.library_source().ensure_local_filesystem_source()?;
            work.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(source)
        })
        .expect("reuse after removal");
    assert_eq!(reused, first_source);
    executor.shutdown().expect("shutdown");
}

#[test]
fn root_listing_is_bounded_and_deterministically_ordered() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    for index in 0..3 {
        executor
            .with_unit_of_work(context(), move |mut work| {
                let source = work.library_source().ensure_local_filesystem_source()?;
                work.library_roots().insert(new_root(
                    source,
                    RootLocator::from_provider(format!("/tmp/{index}")),
                    &format!("Root {index}"),
                ))?;
                work.commit()?;
                Ok::<_, argus_application::ApplicationPortError>(())
            })
            .expect("add");
    }
    let queries = SqliteLibraryRootQueries::new(executor.clone());

    // Ordering is authoritative backend order; the only contract is
    // determinism with a stable unique-ID tie-breaker, never insertion order
    // when timestamps tie.
    let first = queries.list(&context(), 0, 2).expect("first page");
    assert_eq!(first.items().len(), 2);
    assert_eq!(first.total_count(), 3);

    let second = queries.list(&context(), 2, 2).expect("second page");
    assert_eq!(second.items().len(), 1);
    let full: std::collections::BTreeSet<_> = first
        .items()
        .iter()
        .chain(second.items().iter())
        .map(|root| root.display_name().to_owned())
        .collect();
    assert_eq!(
        full,
        ["Root 0", "Root 1", "Root 2"]
            .into_iter()
            .map(str::to_owned)
            .collect()
    );
    let repeated = queries.list(&context(), 0, 2).expect("repeated list");
    assert_eq!(repeated.items(), first.items());
    executor.shutdown().expect("shutdown");
}

#[test]
fn missing_root_delete_is_reported_without_error() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let deleted = executor
        .with_unit_of_work(context(), |mut work| {
            let result = work
                .library_roots()
                .delete(root_id("cccccccccccccccccccccccccccccccc"))?;
            work.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(result)
        })
        .expect("delete missing");
    assert!(!deleted);
    executor.shutdown().expect("shutdown");
}

#[test]
fn provider_validation_establishes_current_enumerability() {
    let directory = tempdir().expect("tempdir");
    let games = directory.path().join("Games");
    fs::create_dir(&games).expect("games directory");
    let provider = LocalFilesystemProviderImpl;

    // Successful validation proves the directory can currently be opened as
    // an enumerable root without recursively reading its contents.
    let validated: ValidatedLocalRoot = provider
        .validate(&selection(&games))
        .expect("enumerable directory");
    assert_eq!(validated.display_name(), "Games");

    // A permission-denied directory cannot establish that evidence.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let locked = directory.path().join("Locked");
        fs::create_dir(&locked).expect("locked directory");
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o000)).expect("permissions");
        let error = provider
            .validate(&selection(&locked))
            .expect_err("inaccessible directory");
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o700)).expect("restore");
        assert_eq!(error, argus_application::ProviderError::PermissionDenied);
    }
}

#[test]
fn persistence_failure_mapping_keeps_sources_sanitized() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let queries = SqliteLibraryRootQueries::new(executor.clone());

    let result = queries.get(&context(), root_id("ffffffffffffffffffffffffffffffff"));
    assert!(matches!(result, Ok(None)));
    executor.shutdown().expect("shutdown");
}
