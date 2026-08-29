//! Slice 003 infrastructure integration tests: additive reconciliation schema,
//! bounded source-entry lookups, identity-preserving relocation, coherent
//! subtree/absence mutation, authority reads, and restart durability.

use argus_application::{
    DerivedEntryKey, DerivedFingerprint, DerivedLocator, JobRunId, JobRunRepository, JobRunState,
    JobsQueries, LibraryRootAvailability, LibraryRootId, LibraryRootLastScanStatus,
    LibraryRootLastScanSummary, LibraryRootQueries, LibraryRootRepository, LibrarySourceRepository,
    NativeIdentityMatch, NewJobRun, NewLibraryRoot, NewScanRun, NewSourceEntry, OperationContext,
    OperationName, PersistenceError, RelativeSourceLocator, RootLocator, ScanRunId,
    ScanRunRepository, ScanRunStatus, SourceEntryClassification, SourceEntryId, SourceEntryKind,
    SourceEntryRecord, SourceEntryRepository, SourceLocatorKey, SubsystemName, TraceId, UnitOfWork,
    UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{
    Migration, MigrationRegistry, SqliteDatabaseExecutor, SqliteValue,
};

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("reconciliation").expect("operation"),
    )
}

fn root_id(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("root id")
}

fn entry(root: LibraryRootId, name: &str, scan: ScanRunId) -> NewSourceEntry {
    entry_with_parent(root, name, None, scan)
}

#[allow(clippy::too_many_arguments)]
fn entry_with_parts(
    root: LibraryRootId,
    name: &str,
    parent: Option<SourceEntryId>,
    scan: ScanRunId,
    kind: SourceEntryKind,
    classification: SourceEntryClassification,
    native_identity: Option<&str>,
) -> NewSourceEntry {
    NewSourceEntry::new(
        root,
        parent,
        RelativeSourceLocator::from_provider(name.to_owned()),
        SourceLocatorKey::from_provider(name.to_owned()),
        name,
        name,
        kind,
        classification,
        native_identity.map(str::to_owned),
        Some(format!("fp:{name}")),
        scan,
    )
}

fn entry_with_parent(
    root: LibraryRootId,
    name: &str,
    parent: Option<SourceEntryId>,
    scan: ScanRunId,
) -> NewSourceEntry {
    entry_with_parts(
        root,
        name,
        parent,
        scan,
        SourceEntryKind::File,
        SourceEntryClassification::Unknown,
        None,
    )
}

fn derived_entry(
    root: LibraryRootId,
    source_entry_id: SourceEntryId,
    parent: SourceEntryId,
    name: &str,
    transformation_id: &str,
    scan: ScanRunId,
) -> NewSourceEntry {
    NewSourceEntry::new_derived(
        source_entry_id,
        root,
        parent,
        name.to_owned(),
        name.to_owned(),
        SourceEntryKind::File,
        SourceEntryClassification::ContentCandidate,
        DerivedLocator::from_transformation(format!("locator:{name}")),
        DerivedEntryKey::from_transformation(format!("key:{name}")),
        DerivedFingerprint::from_transformation(format!("fingerprint:{name}")),
        transformation_id.to_owned(),
        1,
        scan,
        1,
        1,
    )
}

fn seed_source_root_and_job(
    executor: &SqliteDatabaseExecutor,
) -> (LibraryRootId, JobRunId, ScanRunId) {
    seed_root_with_locator(executor, "/library/Games")
}

fn seed_root_with_locator(
    executor: &SqliteDatabaseExecutor,
    locator: &str,
) -> (LibraryRootId, JobRunId, ScanRunId) {
    let locator = locator.to_owned();
    executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let root = scope.library_roots().insert(NewLibraryRoot::new(
                source_id,
                RootLocator::from_provider(locator.clone()),
                "Games".to_owned(),
                locator.clone(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider(locator.clone()),
                "Games",
                locator.as_str(),
                1,
                1,
                1_000,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((root, job, scan))
        })
        .expect("seed")
}

fn terminalize_scan(executor: &SqliteDatabaseExecutor, scan: ScanRunId, job: JobRunId) {
    executor
        .execute(&context(), move |mut scope| {
            scope
                .scan_runs()
                .set_status(scan, ScanRunStatus::Complete, Some(1_100), None)?;
            scope
                .job_runs()
                .set_state(job, JobRunState::Completed, 1_100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("terminalize scan");
}

fn read_locator_via_scope(
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
            Ok::<_, argus_application::ApplicationPortError>(found)
        })
        .expect("locator read")
}

#[test]
fn migration_0004_upgrades_0003_rows_and_keeps_native_identity_non_unique() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let registry_0003 = MigrationRegistry::new(vec![
        Migration::sql(
            1,
            "0001_initial",
            include_bytes!("../src/sqlite/migrations/sql/0001_initial.sql"),
        ),
        Migration::sql(
            2,
            "0002_sources",
            include_bytes!("../src/sqlite/migrations/sql/0002_sources.sql"),
        ),
        Migration::sql(
            3,
            "0003_jobs_scans",
            include_bytes!("../src/sqlite/migrations/sql/0003_jobs_scans.sql"),
        ),
    ])
    .expect("0003 registry");
    let (root, scan) = {
        let seeded = SqliteDatabaseExecutor::open_with_registry(&database, registry_0003)
            .expect("0003 database");
        let seeded_values = seed_source_root_and_job(&seeded);
        let (root, _, scan) = seeded_values;
        // This fixture deliberately writes the pre-reconciliation schema. The
        // current source-entry repository targets the migrated coordinate
        // family, so raw SQL keeps the migration test's old-schema boundary
        // explicit without adding a production compatibility branch.
        seeded
            .with_connection_for_tests(context(), move |connection| {
                for (id, name, native_identity) in [
                    ("11111111111111111111111111111111", "a.bin", Some("same")),
                    ("22222222222222222222222222222222", "b.bin", Some("same")),
                    ("33333333333333333333333333333333", "plain.bin", None),
                ] {
                    connection.execute_with_values(
                        "INSERT INTO source_entry
                            (source_entry_id, library_root_id, parent_source_entry_id,
                             relative_locator, locator_key, display_name, display_location,
                             kind, classification, provider_native_identity, source_fingerprint,
                             last_observed_scan_id, created_at, updated_at)
                         VALUES (?1, ?2, NULL, ?3, ?3, ?4, ?4, 'file', 'unknown',
                                 ?5, ?6, ?7, 1, 1)",
                        &[
                            SqliteValue::Text(id.to_owned()),
                            SqliteValue::Text(root.to_string()),
                            SqliteValue::Text(name.to_owned()),
                            SqliteValue::Text(name.to_owned()),
                            native_identity.map_or(SqliteValue::Null, |value| {
                                SqliteValue::Text(value.to_owned())
                            }),
                            SqliteValue::Text(format!("fp:{name}")),
                            SqliteValue::Text(scan.to_string()),
                        ],
                    )?;
                }
                Ok(())
            })
            .expect("seed 0003 rows");
        seeded.shutdown().expect("seeded shutdown");
        (root, scan)
    };

    let upgraded = SqliteDatabaseExecutor::open(&database).expect("upgraded database");
    {
        let connection = rusqlite::Connection::open(&database).expect("raw connection");
        let index_count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master
                 WHERE type = 'index' AND name = 'idx_source_entry_root_native_identity'",
                [],
                |row| row.get(0),
            )
            .expect("index lookup");
        assert_eq!(
            index_count, 1,
            "migration 0004 adds the identity lookup index"
        );
    }

    // Existing 0003 rows survive the upgrade, including two entries sharing
    // one provider-native identity (proving the lookup stays non-unique).
    let identity = upgraded
        .execute(&context(), move |mut scope| {
            let identity = scope.source_entries().find_native_identity(root, "same")?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(identity)
        })
        .expect("identity lookup");
    assert_eq!(identity, NativeIdentityMatch::Ambiguous);

    let plain = upgraded
        .execute(&context(), move |mut scope| {
            let found = scope.source_entries().find_by_locator_key(
                root,
                &SourceLocatorKey::from_provider("plain.bin".to_owned()),
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(found)
        })
        .expect("locator lookup");
    assert_eq!(plain.expect("row survives").display_name(), "plain.bin");

    // A fresh duplicate insert still succeeds after the migration.
    upgraded
        .execute(&context(), move |mut scope| {
            scope.source_entries().upsert(entry_with_parts(
                root,
                "c.bin",
                None,
                scan,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                Some("same"),
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("duplicate identity insert");
    upgraded.shutdown().expect("upgraded shutdown");
}

#[test]
fn native_identity_lookup_is_none_unique_or_ambiguous_with_stable_order() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, _, scan) = seed_source_root_and_job(&executor);
    executor
        .execute(&context(), move |mut scope| {
            scope.source_entries().upsert(entry_with_parts(
                root,
                "only.bin",
                None,
                scan,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                Some("unique"),
            ))?;
            scope.source_entries().upsert(entry_with_parts(
                root,
                "first.bin",
                None,
                scan,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                Some("dupe"),
            ))?;
            scope.source_entries().upsert(entry_with_parts(
                root,
                "second.bin",
                None,
                scan,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                Some("dupe"),
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("seed");

    let unique = executor
        .execute(&context(), move |mut scope| {
            let unique = scope
                .source_entries()
                .find_native_identity(root, "unique")?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(unique)
        })
        .expect("unique lookup");
    match unique {
        NativeIdentityMatch::Unique(record) => assert_eq!(record.display_name(), "only.bin"),
        other => panic!("expected unique match, got {other:?}"),
    }

    let ambiguous = executor
        .execute(&context(), move |mut scope| {
            let ambiguous = scope.source_entries().find_native_identity(root, "dupe")?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(ambiguous)
        })
        .expect("ambiguous lookup");
    assert_eq!(ambiguous, NativeIdentityMatch::Ambiguous);

    let none = executor
        .execute(&context(), move |mut scope| {
            let none = scope
                .source_entries()
                .find_native_identity(root, "missing")?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(none)
        })
        .expect("none lookup");
    assert_eq!(none, NativeIdentityMatch::None);
    executor.shutdown().expect("shutdown");
}

#[test]
fn reconcile_move_preserves_identity_and_refreshes_location_facts() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, job, scan_one) = seed_source_root_and_job(&executor);
    terminalize_scan(&executor, scan_one, job);
    let scan_two = executor
        .execute(&context(), move |mut scope| {
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 2_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                2_000,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(scan)
        })
        .expect("second scan");
    let created = executor
        .execute(&context(), move |mut scope| {
            let id = scope
                .source_entries()
                .upsert(entry(root, "old.bin", scan_one))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(id)
        })
        .expect("seed entry");

    let relocated = executor
        .execute(&context(), move |mut scope| {
            let moved = entry_with_parts(
                root,
                "new.bin",
                None,
                scan_two,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                Some("native-new"),
            );
            let id = scope.source_entries().reconcile_move(moved, created)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(id)
        })
        .expect("relocate");
    assert_eq!(relocated, created, "relocation preserves SourceEntryId");

    let current = executor
        .execute(&context(), move |mut scope| {
            let found = scope.source_entries().find_by_locator_key(
                root,
                &SourceLocatorKey::from_provider("new.bin".to_owned()),
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(found)
        })
        .expect("current lookup")
        .expect("relocated row");
    assert_eq!(current.source_entry_id(), created);
    assert_eq!(current.display_name(), "new.bin");
    assert_eq!(current.kind(), SourceEntryKind::Directory);
    assert_eq!(
        current.classification(),
        SourceEntryClassification::Container
    );
    assert_eq!(current.provider_native_identity(), Some("native-new"));
    assert_eq!(current.last_observed_scan_id(), scan_two);
    assert_eq!(
        executor
            .execute(&context(), move |mut scope| {
                let found = scope.source_entries().find_by_locator_key(
                    root,
                    &SourceLocatorKey::from_provider("old.bin".to_owned()),
                )?;
                scope.commit()?;
                Ok::<_, argus_application::ApplicationPortError>(found)
            })
            .expect("old lookup"),
        None,
        "old locator no longer resolves"
    );

    let conflict = executor
        .execute(&context(), move |mut scope| {
            let result = scope.source_entries().reconcile_move(
                entry(root, "other.bin", scan_two),
                SourceEntryId::from_bytes([0xee; 16]).expect("fixture id"),
            );
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(result)
        })
        .expect("cross-root/missing relocate");
    assert_eq!(conflict, Err(PersistenceError::Conflict));
    executor.shutdown().expect("shutdown");
}

#[test]
fn exact_scope_child_lookup_is_bounded_paged_and_direct_only() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, _, scan) = seed_source_root_and_job(&executor);
    let (dir_id, _) = executor
        .execute(&context(), move |mut scope| {
            let dir = entry_with_parts(
                root,
                "Dir",
                None,
                scan,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let dir_id = scope.source_entries().upsert(dir)?;
            for name in ["a.bin", "b.bin", "c.bin"] {
                scope
                    .source_entries()
                    .upsert(entry_with_parent(root, name, Some(dir_id), scan))?;
            }
            scope.source_entries().upsert(entry_with_parent(
                root,
                "nested.bin",
                Some(dir_id),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((dir_id, scan))
        })
        .expect("seed tree");

    let first_page = executor
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root, None, 0, 2)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("first page");
    assert_eq!(
        first_page.len(),
        1,
        "only the root-scope direct child exists"
    );
    assert_eq!(first_page[0].source_entry_id(), dir_id);

    let children = executor
        .execute(&context(), move |mut scope| {
            let page = scope
                .source_entries()
                .list_children(root, Some(dir_id), 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("children page");
    assert_eq!(children.len(), 4, "direct children only, never descendants");
    assert!(
        children
            .iter()
            .all(|record| record.parent_source_entry_id() == Some(dir_id))
    );

    let small = executor
        .execute(&context(), move |mut scope| {
            let page = scope
                .source_entries()
                .list_children(root, Some(dir_id), 1, 2)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("bounded page");
    assert_eq!(
        small.len(),
        2,
        "bounded page materializes at most limit rows"
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn delete_subtree_removes_only_the_authoritative_subtree() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, _, scan) = seed_source_root_and_job(&executor);
    let (dir_id, sibling_id) = executor
        .execute(&context(), move |mut scope| {
            let dir = entry_with_parts(
                root,
                "Dir",
                None,
                scan,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let dir_id = scope.source_entries().upsert(dir)?;
            let sibling = entry_with_parts(
                root,
                "sibling.bin",
                None,
                scan,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                None,
            );
            let sibling_id = scope.source_entries().upsert(sibling)?;
            let child = entry_with_parent(root, "child.bin", Some(dir_id), scan);
            let child_id = scope.source_entries().upsert(child)?;
            scope.source_entries().upsert(entry_with_parent(
                root,
                "grandchild.bin",
                Some(child_id),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((dir_id, sibling_id))
        })
        .expect("seed tree");

    let deleted = executor
        .execute(&context(), move |mut scope| {
            let deleted = scope.source_entries().delete_subtree(root, dir_id)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(deleted)
        })
        .expect("delete subtree");
    assert!(deleted);

    let remaining = executor
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root, None, 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("remaining children");
    assert_eq!(remaining.len(), 1, "sibling untouched");
    assert_eq!(remaining[0].source_entry_id(), sibling_id);

    let missing = executor
        .execute(&context(), move |mut scope| {
            let deleted = scope.source_entries().delete_subtree(
                root,
                SourceEntryId::from_bytes([0xdd; 16]).expect("fixture id"),
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(deleted)
        })
        .expect("missing subtree");
    assert!(!missing);
    executor.shutdown().expect("shutdown");
}

#[test]
fn finalize_absent_scope_deletes_only_unobserved_children_and_descendants() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, job, scan_one) = seed_source_root_and_job(&executor);
    terminalize_scan(&executor, scan_one, job);
    let scan_two = executor
        .execute(&context(), move |mut scope| {
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 2_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                2_000,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(scan)
        })
        .expect("second scan");
    executor
        .execute(&context(), move |mut scope| {
            let absent_dir = entry_with_parts(
                root,
                "AbsentDir",
                None,
                scan_one,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let absent_dir_id = scope.source_entries().upsert(absent_dir)?;
            scope.source_entries().upsert(entry_with_parent(
                root,
                "absent-child.bin",
                Some(absent_dir_id),
                scan_one,
            ))?;
            scope
                .source_entries()
                .upsert(entry_with_parent(root, "absent.bin", None, scan_one))?;
            scope
                .source_entries()
                .upsert(entry_with_parent(root, "kept.bin", None, scan_two))?;
            scope.source_entries().upsert(entry_with_parent(
                root,
                "also-gone.bin",
                None,
                scan_one,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(())
        })
        .expect("seed prior state");

    let deleted = executor
        .execute(&context(), move |mut scope| {
            let deleted = scope
                .source_entries()
                .finalize_absent_scope(root, None, scan_two)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(deleted)
        })
        .expect("finalize root scope");
    assert_eq!(
        deleted, 4,
        "absent.bin, also-gone.bin, and the AbsentDir subtree rows"
    );

    let remaining = executor
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root, None, 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("remaining root children");
    let names: Vec<&str> = remaining
        .iter()
        .map(SourceEntryRecord::display_name)
        .collect();
    assert_eq!(names, vec!["kept.bin"]);
    executor.shutdown().expect("shutdown");
}

#[test]
fn finalize_absent_derived_scope_deletes_stale_roots_and_all_descendants() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, job, scan_one) = seed_source_root_and_job(&executor);
    terminalize_scan(&executor, scan_one, job);
    let scan_two = executor
        .execute(&context(), move |mut scope| {
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 2_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                2_000,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(scan)
        })
        .expect("second scan");

    let parent = executor
        .execute(&context(), move |mut scope| {
            let parent = scope.source_entries().upsert(entry_with_parts(
                root,
                "archive.bin",
                None,
                scan_two,
                SourceEntryKind::File,
                SourceEntryClassification::ContentCandidate,
                None,
            ))?;
            let stale_root = SourceEntryId::from_bytes([0xa1; 16]).expect("stale root id");
            let stale_child = SourceEntryId::from_bytes([0xa2; 16]).expect("stale child id");
            let current_sibling = SourceEntryId::from_bytes([0xa3; 16]).expect("sibling id");
            scope.source_entries().upsert_derived(derived_entry(
                root,
                stale_root,
                parent,
                "stale-root",
                "test.outer",
                scan_one,
            ))?;
            scope.source_entries().upsert_derived(derived_entry(
                root,
                stale_child,
                stale_root,
                "stale-child",
                "test.inner",
                scan_one,
            ))?;
            scope.source_entries().upsert_derived(derived_entry(
                root,
                current_sibling,
                parent,
                "current-sibling",
                "test.outer",
                scan_two,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((
                parent,
                stale_root,
                stale_child,
                current_sibling,
            ))
        })
        .expect("seed derived tree");
    let (parent, stale_root, stale_child, current_sibling) = parent;

    let deleted = executor
        .execute(&context(), move |mut scope| {
            let deleted = scope.source_entries().finalize_absent_derived_scope(
                parent,
                "test.outer",
                1,
                scan_two,
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(deleted)
        })
        .expect("finalize derived scope");
    assert_eq!(deleted, 2);

    let remaining = executor
        .execute(&context(), move |mut scope| {
            let root_children = scope
                .source_entries()
                .list_children(root, Some(parent), 0, 100)?;
            let nested = scope
                .source_entries()
                .list_children(root, Some(stale_root), 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((root_children, nested))
        })
        .expect("read derived tree");
    assert_eq!(remaining.0.len(), 1);
    assert_eq!(remaining.0[0].source_entry_id(), current_sibling);
    assert!(remaining.1.is_empty());
    let _ = stale_child;
    executor.shutdown().expect("shutdown");
}

#[test]
fn scan_authority_reads_current_revisions_and_absent_root() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, _, _) = seed_source_root_and_job(&executor);
    let authority = executor
        .execute(&context(), move |mut scope| {
            let authority = scope.library_roots().get_scan_authority(root)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(authority)
        })
        .expect("authority read");
    let authority = authority.expect("configured root");
    assert_eq!(authority.root_id(), root);
    assert_eq!(authority.config_revision(), 1);
    assert_eq!(authority.source_config_revision(), 1);
    assert_eq!(authority.discovery_policy_revision(), 1);

    let missing = executor
        .execute(&context(), move |mut scope| {
            let missing = scope
                .library_roots()
                .get_scan_authority(root_id("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(missing)
        })
        .expect("missing root");
    assert_eq!(missing, None);
    executor.shutdown().expect("shutdown");
}

#[test]
fn reconciled_graph_and_terminal_history_survive_database_recreation() {
    let directory = tempfile::tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let (root, job, scan_one) = seed_source_root_and_job(&executor);
    terminalize_scan(&executor, scan_one, job);
    let scan_two = executor
        .execute(&context(), move |mut scope| {
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 2_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                2_000,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(scan)
        })
        .expect("second scan");
    let (moved_id, dir_id) = executor
        .execute(&context(), move |mut scope| {
            let dir = entry_with_parts(
                root,
                "Dir",
                None,
                scan_one,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let dir_id = scope.source_entries().upsert(dir)?;
            scope.source_entries().upsert(entry_with_parts(
                root,
                "Dir",
                None,
                scan_two,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            ))?;
            let old = entry_with_parts(
                root,
                "old.bin",
                None,
                scan_one,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                Some("native"),
            );
            let old_id = scope.source_entries().upsert(old)?;
            scope
                .source_entries()
                .upsert(entry_with_parent(root, "gone.bin", None, scan_one))?;
            let moved = entry_with_parts(
                root,
                "moved.bin",
                Some(dir_id),
                scan_two,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                Some("native"),
            );
            let moved_id = scope.source_entries().reconcile_move(moved, old_id)?;
            let deleted = scope
                .source_entries()
                .finalize_absent_scope(root, None, scan_two)?;
            assert_eq!(deleted, 1, "gone.bin removed by finalization");
            scope
                .scan_runs()
                .set_status(scan_two, ScanRunStatus::Complete, Some(3_000), None)?;
            scope
                .job_runs()
                .set_state(job, JobRunState::Completed, 3_000)?;
            scope.library_roots().set_last_scan(
                root,
                Some(LibraryRootLastScanSummary::new(
                    scan_two.to_string(),
                    job.to_string(),
                    LibraryRootLastScanStatus::Complete,
                    2_000,
                    Some(3_000),
                )),
            )?;
            scope
                .library_roots()
                .set_availability(root, LibraryRootAvailability::Available)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((moved_id, dir_id))
        })
        .expect("reconciled state");
    executor.shutdown().expect("shutdown");

    let reopened = SqliteDatabaseExecutor::open(&database).expect("reopened");
    let current = reopened
        .execute(&context(), move |mut scope| {
            let found = scope.source_entries().find_by_locator_key(
                root,
                &SourceLocatorKey::from_provider("moved.bin".to_owned()),
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(found)
        })
        .expect("current lookup")
        .expect("moved row survives recreation");
    assert_eq!(current.source_entry_id(), moved_id);
    assert_eq!(current.parent_source_entry_id(), Some(dir_id));
    assert_eq!(current.last_observed_scan_id(), scan_two);

    let children = reopened
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root, None, 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("root children");
    let names: Vec<&str> = children
        .iter()
        .map(SourceEntryRecord::display_name)
        .collect();
    assert_eq!(
        names,
        vec!["Dir"],
        "gone.bin stays deleted after recreation"
    );

    let root_projection =
        argus_infrastructure::sqlite::SqliteLibraryRootQueries::new(reopened.clone())
            .get(&context(), root)
            .expect("root projection")
            .expect("configured root");
    assert_eq!(
        root_projection.last_scan().expect("last scan").status(),
        LibraryRootLastScanStatus::Complete
    );
    assert_eq!(
        root_projection.availability(),
        LibraryRootAvailability::Available
    );
    let job_detail = argus_infrastructure::sqlite::SqliteJobsQueries::new(reopened.clone())
        .get_job(&context(), job)
        .expect("job detail")
        .expect("job survives recreation");
    assert_eq!(job_detail.job().state(), JobRunState::Completed);
    reopened.shutdown().expect("reopened shutdown");
}

#[test]
fn upsert_with_exact_locator_conflict_refreshes_relative_locator_and_current_facts() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, _, scan) = seed_source_root_and_job(&executor);

    let first_id = executor
        .execute(&context(), move |mut scope| {
            let id = scope.source_entries().upsert(NewSourceEntry::new(
                root,
                None,
                RelativeSourceLocator::from_provider("old-location".to_owned()),
                SourceLocatorKey::from_provider("same-key".to_owned()),
                "old.bin",
                "old.bin",
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                None,
                Some("fp1".to_owned()),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(id)
        })
        .expect("first upsert");

    let second_id = executor
        .execute(&context(), move |mut scope| {
            let id = scope.source_entries().upsert(NewSourceEntry::new(
                root,
                None,
                RelativeSourceLocator::from_provider("new-location".to_owned()),
                SourceLocatorKey::from_provider("same-key".to_owned()),
                "new.bin",
                "new.bin",
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                Some("native-new".to_owned()),
                Some("fp2".to_owned()),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(id)
        })
        .expect("second upsert");
    assert_eq!(
        second_id, first_id,
        "exact locator conflict preserves SourceEntryId"
    );

    let current = executor
        .execute(&context(), move |mut scope| {
            let found = scope.source_entries().find_by_locator_key(
                root,
                &SourceLocatorKey::from_provider("same-key".to_owned()),
            )?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(found)
        })
        .expect("current lookup")
        .expect("row exists");
    assert_eq!(current.source_entry_id(), first_id);
    assert_eq!(
        current
            .relative_locator()
            .expect("reconciled provider row has a locator")
            .as_provider_value(),
        "new-location",
        "upsert must refresh relative_locator"
    );
    assert_eq!(current.display_name(), "new.bin");
    assert_eq!(current.kind(), SourceEntryKind::Directory);
    assert_eq!(
        current.classification(),
        SourceEntryClassification::Container
    );
    assert_eq!(current.provider_native_identity(), Some("native-new"));
    assert_eq!(current.source_fingerprint(), Some("fp2"));
    assert_eq!(current.last_observed_scan_id(), scan);
    executor.shutdown().expect("shutdown");
}

#[test]
fn delete_subtree_never_traverses_into_another_root() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root_a, _, scan_a) = seed_root_with_locator(&executor, "/library/Games-A");
    let (root_b, _, scan_b) = seed_root_with_locator(&executor, "/library/Games-B");
    let (a_dir_id, b_dir_id, b_child_id, b_grandchild_id) = executor
        .execute(&context(), move |mut scope| {
            let a_dir = entry_with_parts(
                root_a,
                "a-dir",
                None,
                scan_a,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let a_dir_id = scope.source_entries().upsert(a_dir)?;
            scope.source_entries().upsert(entry_with_parent(
                root_a,
                "a-child.bin",
                Some(a_dir_id),
                scan_a,
            ))?;
            let b_dir = entry_with_parts(
                root_b,
                "b-dir",
                None,
                scan_b,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let b_dir_id = scope.source_entries().upsert(b_dir)?;
            let b_child = entry_with_parts(
                root_b,
                "b-child.bin",
                Some(b_dir_id),
                scan_b,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                None,
            );
            let b_child_id = scope.source_entries().upsert(b_child)?;
            let b_grandchild_id = scope.source_entries().upsert(entry_with_parent(
                root_b,
                "b-grandchild.bin",
                Some(b_child_id),
                scan_b,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((
                a_dir_id,
                b_dir_id,
                b_child_id,
                b_grandchild_id,
            ))
        })
        .expect("seed two roots");

    // Intentionally corrupt one persisted graph: root_b's grandchild claims
    // root_a's directory as its parent. Destructive root-scoped operations
    // must not follow that reference into root_b.
    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.execute_with_values(
                "UPDATE source_entry SET parent_source_entry_id = ?1 WHERE source_entry_id = ?2",
                &[
                    SqliteValue::Text(a_dir_id.to_string()),
                    SqliteValue::Text(b_grandchild_id.to_string()),
                ],
            )
        })
        .expect("malformed cross-root reference");

    let deleted = executor
        .execute(&context(), move |mut scope| {
            let deleted = scope.source_entries().delete_subtree(root_a, a_dir_id)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(deleted)
        })
        .expect("delete subtree");
    assert!(deleted);

    let root_a_children = executor
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root_a, None, 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("root_a children");
    assert!(root_a_children.is_empty(), "root_a subtree removed");
    assert_eq!(
        read_locator_via_scope(&executor, root_a, "a-child.bin"),
        None,
        "legitimate root_a descendant removed"
    );

    let b_top = executor
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root_b, None, 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("root_b top children");
    assert_eq!(b_top.len(), 1, "root_b top child untouched");
    assert_eq!(b_top[0].source_entry_id(), b_dir_id);
    let b_middle = executor
        .execute(&context(), move |mut scope| {
            let page = scope
                .source_entries()
                .list_children(root_b, Some(b_dir_id), 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("root_b middle children");
    assert_eq!(b_middle.len(), 1, "root_b child untouched");
    assert_eq!(b_middle[0].source_entry_id(), b_child_id);
    assert_eq!(
        read_locator_via_scope(&executor, root_b, "b-grandchild.bin")
            .expect("malformed row survives")
            .source_entry_id(),
        b_grandchild_id,
        "malformed cross-root row is never deleted by root_a work"
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn finalize_absent_scope_never_traverses_into_another_root() {
    let directory = tempfile::tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root_a, job_a, scan_a) = seed_root_with_locator(&executor, "/library/Games-A");
    let (root_b, _, scan_b) = seed_root_with_locator(&executor, "/library/Games-B");
    let (a_dir_id, b_dir_id, b_child_id, b_grandchild_id) = executor
        .execute(&context(), move |mut scope| {
            let a_dir = entry_with_parts(
                root_a,
                "a-dir",
                None,
                scan_a,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let a_dir_id = scope.source_entries().upsert(a_dir)?;
            scope.source_entries().upsert(entry_with_parent(
                root_a,
                "a-child.bin",
                Some(a_dir_id),
                scan_a,
            ))?;
            let b_dir = entry_with_parts(
                root_b,
                "b-dir",
                None,
                scan_b,
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
            );
            let b_dir_id = scope.source_entries().upsert(b_dir)?;
            let b_child = entry_with_parts(
                root_b,
                "b-child.bin",
                Some(b_dir_id),
                scan_b,
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                None,
            );
            let b_child_id = scope.source_entries().upsert(b_child)?;
            let b_grandchild_id = scope.source_entries().upsert(entry_with_parent(
                root_b,
                "b-grandchild.bin",
                Some(b_child_id),
                scan_b,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>((
                a_dir_id,
                b_dir_id,
                b_child_id,
                b_grandchild_id,
            ))
        })
        .expect("seed two roots");

    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.execute_with_values(
                "UPDATE source_entry SET parent_source_entry_id = ?1 WHERE source_entry_id = ?2",
                &[
                    SqliteValue::Text(a_dir_id.to_string()),
                    SqliteValue::Text(b_grandchild_id.to_string()),
                ],
            )
        })
        .expect("malformed cross-root reference");

    // A fresh scan on root_a provides the absence-authority token.
    terminalize_scan(&executor, scan_a, job_a);
    let scan_c = executor
        .execute(&context(), move |mut scope| {
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 3_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root_a,
                RootLocator::from_provider("/library/Games-A".to_owned()),
                "Games",
                "/library/Games-A",
                1,
                1,
                3_000,
            ))?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(scan)
        })
        .expect("third scan");

    let deleted = executor
        .execute(&context(), move |mut scope| {
            let deleted = scope
                .source_entries()
                .finalize_absent_scope(root_a, None, scan_c)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(deleted)
        })
        .expect("finalize root_a scope");
    assert_eq!(deleted, 2, "a-dir and its legitimate root_a child removed");

    let root_a_children = executor
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root_a, None, 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("root_a children");
    assert!(root_a_children.is_empty());
    assert_eq!(
        read_locator_via_scope(&executor, root_a, "a-child.bin"),
        None,
        "legitimate root_a descendant removed"
    );

    let b_top = executor
        .execute(&context(), move |mut scope| {
            let page = scope.source_entries().list_children(root_b, None, 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("root_b top children");
    assert_eq!(b_top.len(), 1);
    assert_eq!(b_top[0].source_entry_id(), b_dir_id);
    let b_middle = executor
        .execute(&context(), move |mut scope| {
            let page = scope
                .source_entries()
                .list_children(root_b, Some(b_dir_id), 0, 100)?;
            scope.commit()?;
            Ok::<_, argus_application::ApplicationPortError>(page)
        })
        .expect("root_b middle children");
    assert_eq!(b_middle.len(), 1);
    assert_eq!(b_middle[0].source_entry_id(), b_child_id);
    assert_eq!(
        read_locator_via_scope(&executor, root_b, "b-grandchild.bin")
            .expect("malformed row survives")
            .source_entry_id(),
        b_grandchild_id,
        "malformed cross-root row is never deleted by root_a work"
    );
    executor.shutdown().expect("shutdown");
}
