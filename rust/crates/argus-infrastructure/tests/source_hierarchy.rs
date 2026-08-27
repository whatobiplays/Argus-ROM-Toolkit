//! Slice 004 infrastructure integration tests: bounded keyset-paged
//! source-entry hierarchy queries and the additive paging index.

use argus_application::{
    ApplicationPortError, JobRunId, JobRunRepository, LibraryRootAvailability, LibraryRootId,
    LibraryRootRepository, LibrarySourceRepository, NewJobRun, NewLibraryRoot, NewScanRun,
    NewSourceEntry, OperationContext, OperationName, RelativeSourceLocator, RootLocator, ScanRunId,
    ScanRunRepository, SourceEntryClassification, SourceEntryId, SourceEntryKind,
    SourceEntryQueries, SourceEntryRepository, SourceLocatorKey, SubsystemName, TraceId,
    UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::{
    Migration, MigrationRegistry, SqliteDatabaseExecutor, SqliteSourceEntryQueries, SqliteValue,
};
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("source_hierarchy").expect("operation"),
    )
}

fn entry_id(value: &str) -> SourceEntryId {
    SourceEntryId::try_from(value).expect("entry id")
}

fn seed(executor: &SqliteDatabaseExecutor) -> (LibraryRootId, JobRunId, ScanRunId) {
    executor
        .execute(&context(), move |mut scope| {
            let source_id = scope.library_source().ensure_local_filesystem_source()?;
            let root = scope.library_roots().insert(NewLibraryRoot::new(
                source_id,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games".to_owned(),
                "/library/Games".to_owned(),
                LibraryRootAvailability::Available,
                1,
            ))?;
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", 1_000))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                1_000,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((root, job, scan))
        })
        .expect("seed")
}

fn insert_entry(
    executor: &SqliteDatabaseExecutor,
    root: LibraryRootId,
    scan: ScanRunId,
    name: &str,
    parent: Option<SourceEntryId>,
) -> SourceEntryId {
    let name = name.to_owned();
    let parent = parent.map(|id| id.to_string());
    executor
        .execute(&context(), move |mut scope| {
            let parent_id = parent
                .as_deref()
                .map(SourceEntryId::try_from)
                .transpose()
                .expect("parent id");
            let inserted = scope.source_entries().upsert(NewSourceEntry::new(
                root,
                parent_id,
                RelativeSourceLocator::from_provider(name.clone()),
                SourceLocatorKey::from_provider(name.clone()),
                name.clone(),
                name.clone(),
                SourceEntryKind::File,
                SourceEntryClassification::Unknown,
                None,
                Some(format!("fp:{name}")),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>(inserted)
        })
        .expect("insert entry")
}

fn set_created_at(executor: &SqliteDatabaseExecutor, id: SourceEntryId, created_at: i64) {
    let changed = executor
        .with_connection_for_tests(context(), move |connection| {
            connection.execute_with_values(
                "UPDATE source_entry SET created_at = ?1 WHERE source_entry_id = ?2",
                &[
                    SqliteValue::Integer(created_at),
                    SqliteValue::Text(id.to_string()),
                ],
            )
        })
        .expect("set created_at");
    assert_eq!(changed, 1, "created_at update affected {changed} row(s)");
}

#[test]
fn root_children_page_with_deterministic_keyset_continuation() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let (root, _, scan) = seed(&executor);
    let ids: Vec<SourceEntryId> = ["e1", "e2", "e3", "e4", "e5"]
        .iter()
        .map(|name| insert_entry(&executor, root, scan, name, None))
        .collect();
    for (index, id) in ids.iter().enumerate() {
        set_created_at(&executor, *id, 100 + (index as i64) * 100);
    }
    let queries = SqliteSourceEntryQueries::new(executor.clone());

    let first = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, None, None, 2),
        )
        .expect("first page");
    assert_eq!(
        first
            .items()
            .iter()
            .map(|row| row.source_entry_id())
            .collect::<Vec<_>>(),
        vec![ids[0], ids[1]]
    );
    let cursor = first.next_cursor().expect("continuation").clone();

    let second = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, None, Some(cursor), 2),
        )
        .expect("second page");
    assert_eq!(
        second
            .items()
            .iter()
            .map(|row| row.source_entry_id())
            .collect::<Vec<_>>(),
        vec![ids[2], ids[3]]
    );
    let cursor = second.next_cursor().expect("continuation").clone();

    let third = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, None, Some(cursor), 2),
        )
        .expect("third page");
    assert_eq!(
        third
            .items()
            .iter()
            .map(|row| row.source_entry_id())
            .collect::<Vec<_>>(),
        vec![ids[4]]
    );
    assert!(third.next_cursor().is_none());

    let all = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, None, None, 100),
        )
        .expect("all in one page");
    assert_eq!(all.items().len(), 5);
    assert!(all.next_cursor().is_none());
    executor.shutdown().expect("shutdown");
}

#[test]
fn parent_scopes_page_independently_without_cross_talk() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let (root, _, scan) = seed(&executor);

    let dir_a = insert_dir(&executor, root, scan, "dir_a");
    let dir_b = insert_dir(&executor, root, scan, "dir_b");
    let c1 = insert_entry(&executor, root, scan, "c1", Some(dir_a));
    let c2 = insert_entry(&executor, root, scan, "c2", Some(dir_a));
    let c3 = insert_entry(&executor, root, scan, "c3", Some(dir_a));
    let d1 = insert_entry(&executor, root, scan, "d1", Some(dir_b));
    set_created_at(&executor, dir_a, 100);
    set_created_at(&executor, dir_b, 200);
    set_created_at(&executor, c1, 300);
    set_created_at(&executor, c2, 400);
    set_created_at(&executor, c3, 500);
    set_created_at(&executor, d1, 600);
    let queries = SqliteSourceEntryQueries::new(executor.clone());

    let root_page = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, None, None, 10),
        )
        .expect("root page");
    assert_eq!(
        root_page
            .items()
            .iter()
            .map(|row| row.source_entry_id())
            .collect::<Vec<_>>(),
        vec![dir_a, dir_b]
    );

    let a_first = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, Some(dir_a), None, 2),
        )
        .expect("dir_a first page");
    assert_eq!(
        a_first
            .items()
            .iter()
            .map(|row| row.source_entry_id())
            .collect::<Vec<_>>(),
        vec![c1, c2]
    );
    let a_second = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(
                root,
                Some(dir_a),
                a_first.next_cursor().cloned(),
                2,
            ),
        )
        .expect("dir_a second page");
    assert_eq!(
        a_second
            .items()
            .iter()
            .map(|row| row.source_entry_id())
            .collect::<Vec<_>>(),
        vec![c3]
    );
    assert!(a_second.next_cursor().is_none());

    let b_page = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, Some(dir_b), None, 10),
        )
        .expect("dir_b page");
    assert_eq!(
        b_page
            .items()
            .iter()
            .map(|row| row.source_entry_id())
            .collect::<Vec<_>>(),
        vec![d1]
    );
    executor.shutdown().expect("shutdown");
}

fn insert_dir(
    executor: &SqliteDatabaseExecutor,
    root: LibraryRootId,
    scan: ScanRunId,
    name: &str,
) -> SourceEntryId {
    let name = name.to_owned();
    executor
        .execute(&context(), move |mut scope| {
            let inserted = scope.source_entries().upsert(NewSourceEntry::new(
                root,
                None,
                RelativeSourceLocator::from_provider(name.clone()),
                SourceLocatorKey::from_provider(name.clone()),
                name.clone(),
                name.clone(),
                SourceEntryKind::Directory,
                SourceEntryClassification::Container,
                None,
                Some(format!("fp:{name}")),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>(inserted)
        })
        .expect("insert dir")
}

#[test]
fn get_source_entry_returns_safe_detail_or_none() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let (root, _, scan) = seed(&executor);
    let dir = insert_dir(&executor, root, scan, "dir_a");
    let queries = SqliteSourceEntryQueries::new(executor.clone());

    let detail = queries
        .get(&context(), dir)
        .expect("detail")
        .expect("known entry");
    assert_eq!(detail.source_entry_id(), dir);
    assert_eq!(detail.parent_source_entry_id(), None);
    assert_eq!(detail.display_name(), "dir_a");
    assert_eq!(detail.display_location(), "dir_a");
    assert_eq!(detail.kind(), SourceEntryKind::Directory);
    assert_eq!(
        detail.classification(),
        SourceEntryClassification::Container
    );

    assert_eq!(
        queries
            .get(&context(), entry_id("99999999999999999999999999999999"))
            .expect("query"),
        None
    );
    executor.shutdown().expect("shutdown");
}

#[test]
fn projection_exposes_only_safe_application_facts() {
    let directory = tempdir().expect("tempdir");
    let database = directory.path().join("argus.sqlite3");
    let executor = SqliteDatabaseExecutor::open(&database).expect("database");
    let (root, _, scan) = seed(&executor);
    let dir = insert_dir(&executor, root, scan, "dir_a");
    let queries = SqliteSourceEntryQueries::new(executor.clone());
    let page = queries
        .list_children(
            &context(),
            &argus_application::ListSourceEntryChildrenQuery::new(root, None, None, 10),
        )
        .expect("page");

    let row = &page.items()[0];
    assert_eq!(row.source_entry_id(), dir);
    assert_eq!(row.parent_source_entry_id(), None);
    assert_eq!(row.display_name(), "dir_a");
    assert_eq!(row.display_location(), "dir_a");
    assert_eq!(row.kind(), SourceEntryKind::Directory);
    assert_eq!(row.classification(), SourceEntryClassification::Container);
    executor.shutdown().expect("shutdown");
}

#[test]
fn migration_latest_applies_fresh_and_upgrades_version_four() {
    let directory = tempdir().expect("tempdir");
    let path = directory.path().join("upgrade.sqlite3");
    let old_registry = MigrationRegistry::new(vec![
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
        Migration::sql(
            4,
            "0004_source_reconciliation",
            include_bytes!("../src/sqlite/migrations/sql/0004_source_reconciliation.sql"),
        ),
    ])
    .expect("old registry");
    let old = SqliteDatabaseExecutor::open_with_registry(&path, old_registry).expect("old open");
    assert_eq!(old.migration_summary().current_version, 4);
    old.shutdown().expect("old shutdown");

    let fresh = SqliteDatabaseExecutor::open(&path).expect("upgraded open");
    assert_eq!(fresh.migration_summary().current_version, 14);
    assert_eq!(fresh.migration_summary().applied_count, 10);
    let index = fresh
        .with_connection_for_tests(context(), |connection| {
            connection.scalar_i64(
                "SELECT COUNT(*) FROM sqlite_master
                 WHERE type = 'index' AND name = 'idx_source_entry_root_parent_created_id'",
            )
        })
        .expect("index check");
    assert_eq!(index, 1);
    fresh.shutdown().expect("fresh shutdown");
}
