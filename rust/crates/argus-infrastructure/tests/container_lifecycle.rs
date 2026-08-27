#![cfg(feature = "test-support")]

use argus_application::{
    ApplicationPortError, DerivedEntryKey, DerivedEntryObservation, DerivedFingerprint,
    DerivedLocator, DerivedScopeIdentity, DerivedScopeOutcome, JobRunRepository,
    LibraryRootAvailability, LibraryRootId, LibraryRootRepository, LibrarySourceRepository,
    NewJobRun, NewLibraryRoot, NewScanRun, NewSourceEntry, OperationContext, OperationName,
    RelativeSourceLocator, RootLocator, ScanRunId, ScanRunRepository, ScanRunStatus,
    SourceEntryClassification, SourceEntryId, SourceEntryKind, SourceEntryRepository,
    SourceLocatorKey, SubsystemName, TraceId, UnitOfWork, UnitOfWorkFactory,
    reconcile_derived_scope,
};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(881_u128).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("container_lifecycle").expect("operation"),
    )
}

fn seed(executor: &SqliteDatabaseExecutor) -> (LibraryRootId, ScanRunId, SourceEntryId) {
    executor
        .execute(&context(), move |mut scope| {
            let source = scope.library_source().ensure_local_filesystem_source()?;
            let root = scope.library_roots().insert(NewLibraryRoot::new(
                source,
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
            scope
                .scan_runs()
                .set_status(scan, ScanRunStatus::Complete, Some(1_000), None)?;
            let parent = scope.source_entries().upsert(NewSourceEntry::new(
                root,
                None,
                RelativeSourceLocator::from_provider("collection.zip".to_owned()),
                SourceLocatorKey::from_provider("collection.zip".to_owned()),
                "collection.zip",
                "collection.zip",
                SourceEntryKind::File,
                SourceEntryClassification::Container,
                None,
                Some("provider:collection-v1".to_owned()),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((root, scan, parent))
        })
        .expect("seed")
}

fn next_scan(executor: &SqliteDatabaseExecutor, root: LibraryRootId, sequence: i64) -> ScanRunId {
    executor
        .execute(&context(), move |mut scope| {
            let job = scope
                .job_runs()
                .insert(NewJobRun::new("library_scan", sequence))?;
            let scan = scope.scan_runs().insert(NewScanRun::new(
                job,
                root,
                RootLocator::from_provider("/library/Games".to_owned()),
                "Games",
                "/library/Games",
                1,
                1,
                sequence,
            ))?;
            scope
                .scan_runs()
                .set_status(scan, ScanRunStatus::Complete, Some(sequence), None)?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>(scan)
        })
        .expect("next scan")
}

fn observation(name: &str, key: &str, fingerprint: &str) -> DerivedEntryObservation {
    DerivedEntryObservation::new(
        DerivedLocator::from_transformation(format!("member:{key}")),
        DerivedEntryKey::from_transformation(key.to_owned()),
        name.to_owned(),
        SourceEntryKind::File,
        Some(4),
        DerivedFingerprint::from_transformation(fingerprint.to_owned()),
    )
}

fn reconcile(
    executor: &SqliteDatabaseExecutor,
    parent: SourceEntryId,
    scan: ScanRunId,
    observations: Vec<DerivedEntryObservation>,
    stable_input: bool,
    outcome: DerivedScopeOutcome,
) -> Vec<SourceEntryId> {
    let scope = DerivedScopeIdentity {
        parent_source_entry_id: parent,
        transformation_id: "argus.transformation.zip.v1",
        transformation_revision: 1,
    };
    executor
        .execute(&context(), move |mut work| {
            let ids = reconcile_derived_scope(
                &mut work.source_entries(),
                &scope,
                &observations,
                scan,
                stable_input,
                outcome,
            )?;
            work.commit()?;
            Ok::<_, ApplicationPortError>(ids)
        })
        .expect("scope reconciliation")
}

fn derived_count(executor: &SqliteDatabaseExecutor, parent: SourceEntryId) -> i64 {
    executor
        .with_connection_for_tests(context(), move |connection| {
            connection.scalar_i64(&format!(
                "SELECT COUNT(*) FROM source_entry
                 WHERE parent_source_entry_id = '{parent}' AND coordinate_kind = 'derived'"
            ))
        })
        .expect("derived count")
}

#[test]
fn only_complete_stable_enumeration_can_remove_absent_children() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("container-lifecycle.sqlite3"))
            .expect("database");
    let (root, first_scan, parent) = seed(&executor);
    let game = observation("game.gba", "game.gba", "game-v1");
    let sidecar = observation("cover.png", "cover.png", "cover-v1");

    let first_ids = reconcile(
        &executor,
        parent,
        first_scan,
        vec![game.clone(), sidecar.clone()],
        true,
        DerivedScopeOutcome::Complete,
    );
    assert_eq!(first_ids.len(), 2);
    assert_eq!(derived_count(&executor, parent), 2);

    let partial_scan = next_scan(&executor, root, 2_000);
    let partial_ids = reconcile(
        &executor,
        parent,
        partial_scan,
        vec![game.clone()],
        true,
        DerivedScopeOutcome::Partial,
    );
    assert_eq!(partial_ids, vec![first_ids[0]]);
    assert_eq!(derived_count(&executor, parent), 2);

    let failed_scan = next_scan(&executor, root, 3_000);
    reconcile(
        &executor,
        parent,
        failed_scan,
        Vec::new(),
        true,
        DerivedScopeOutcome::Failed,
    );
    assert_eq!(derived_count(&executor, parent), 2);

    let unstable_scan = next_scan(&executor, root, 4_000);
    reconcile(
        &executor,
        parent,
        unstable_scan,
        Vec::new(),
        false,
        DerivedScopeOutcome::Complete,
    );
    assert_eq!(derived_count(&executor, parent), 2);

    let complete_scan = next_scan(&executor, root, 5_000);
    let final_ids = reconcile(
        &executor,
        parent,
        complete_scan,
        vec![game],
        true,
        DerivedScopeOutcome::Complete,
    );
    assert_eq!(final_ids, vec![first_ids[0]]);
    assert_eq!(derived_count(&executor, parent), 1);
    executor.shutdown().expect("shutdown");
}

#[test]
fn cancelled_scope_keeps_previous_children_until_a_fresh_complete_scan() {
    let directory = tempdir().expect("tempdir");
    let executor = SqliteDatabaseExecutor::open(directory.path().join("cancelled-scope.sqlite3"))
        .expect("database");
    let (root, first_scan, parent) = seed(&executor);
    reconcile(
        &executor,
        parent,
        first_scan,
        vec![observation("game.gba", "game.gba", "game-v1")],
        true,
        DerivedScopeOutcome::Complete,
    );

    let cancelled_scan = next_scan(&executor, root, 2_000);
    reconcile(
        &executor,
        parent,
        cancelled_scan,
        Vec::new(),
        true,
        DerivedScopeOutcome::Cancelled,
    );
    assert_eq!(derived_count(&executor, parent), 1);
    executor.shutdown().expect("shutdown");
}

#[test]
fn removing_an_outer_source_removes_its_subtree_before_reappearance() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("source-reappearance.sqlite3"))
            .expect("database");
    let (root, first_scan, parent) = seed(&executor);
    let first_child = reconcile(
        &executor,
        parent,
        first_scan,
        vec![observation("game.gba", "game.gba", "game-v1")],
        true,
        DerivedScopeOutcome::Complete,
    );
    assert_eq!(first_child.len(), 1);
    assert_eq!(derived_count(&executor, parent), 1);

    executor
        .execute(&context(), move |mut work| {
            let deleted = work.source_entries().delete_subtree(root, parent)?;
            assert!(deleted);
            work.commit()?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("remove outer source");
    assert_eq!(derived_count(&executor, parent), 0);

    let reappearance_scan = next_scan(&executor, root, 2_000);
    let reappeared_parent = executor
        .execute(&context(), move |mut work| {
            let parent = work.source_entries().upsert(NewSourceEntry::new(
                root,
                None,
                RelativeSourceLocator::from_provider("collection.zip".to_owned()),
                SourceLocatorKey::from_provider("collection.zip".to_owned()),
                "collection.zip",
                "collection.zip",
                SourceEntryKind::File,
                SourceEntryClassification::Container,
                None,
                Some("provider:collection-v2".to_owned()),
                reappearance_scan,
            ))?;
            work.commit()?;
            Ok::<_, ApplicationPortError>(parent)
        })
        .expect("reinsert outer source");
    let reappeared_child = reconcile(
        &executor,
        reappeared_parent,
        reappearance_scan,
        vec![observation("game.gba", "game.gba", "game-v2")],
        true,
        DerivedScopeOutcome::Complete,
    );
    assert_eq!(reappeared_child.len(), 1);
    assert_eq!(derived_count(&executor, reappeared_parent), 1);
    assert_ne!(first_child[0], reappeared_child[0]);
    executor.shutdown().expect("shutdown");
}
