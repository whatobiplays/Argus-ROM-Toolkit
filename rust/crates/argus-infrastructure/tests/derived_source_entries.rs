#![cfg(feature = "test-support")]

use argus_application::{
    ApplicationPortError, DerivedEntryKey, DerivedFingerprint, DerivedLocator,
    IdentityConvergenceStore, JobRunRepository, LibraryRootAvailability, LibraryRootId,
    LibraryRootRepository, LibrarySourceRepository, LogicalContentUnitOfWork, NewJobRun,
    NewLibraryRoot, NewScanRun, NewSourceEntry, OperationContext, OperationName,
    RelativeSourceLocator, RootLocator, ScanRunId, ScanRunRepository, SourceEntryClassification,
    SourceEntryId, SourceEntryKind, SourceEntryRepository, SourceLocatorKey, SourceVersionEvidence,
    SubsystemName, TraceId, UnitOfWork, UnitOfWorkFactory,
};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("derived_source_entries").expect("operation"),
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
            let parent = scope.source_entries().upsert(NewSourceEntry::new(
                root,
                None,
                RelativeSourceLocator::from_provider("archive.zip".to_owned()),
                SourceLocatorKey::from_provider("archive.zip".to_owned()),
                "archive.zip",
                "archive.zip",
                SourceEntryKind::File,
                SourceEntryClassification::Container,
                None,
                Some("provider:archive".to_owned()),
                scan,
            ))?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((root, scan, parent))
        })
        .expect("seed")
}

fn derived_entry(root: LibraryRootId, parent: SourceEntryId, scan: ScanRunId) -> NewSourceEntry {
    NewSourceEntry::new_derived(
        SourceEntryId::try_from("33333333333333333333333333333333").expect("derived id"),
        root,
        parent,
        "game.gba".to_owned(),
        "archive.zip/game.gba".to_owned(),
        SourceEntryKind::File,
        SourceEntryClassification::ContentCandidate,
        DerivedLocator::from_transformation("member:game.gba".to_owned()),
        DerivedEntryKey::from_transformation("member:game.gba".to_owned()),
        DerivedFingerprint::from_transformation("member-fingerprint:v1".to_owned()),
        "argus.transformation.zip.v1".to_owned(),
        1,
        scan,
        1_000,
        1_000,
    )
}

#[test]
fn derived_entries_upsert_by_transformation_key_and_keep_provider_coordinates_empty() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("argus.sqlite3")).expect("database");
    let (root, scan, parent) = seed(&executor);

    let (first, second, found) = executor
        .execute(&context(), move |mut scope| {
            let entry = derived_entry(root, parent, scan);
            let first = scope.source_entries().upsert_derived(entry.clone())?;
            let second = scope.source_entries().upsert_derived(entry)?;
            let found = scope.source_entries().find_derived_child(
                parent,
                "argus.transformation.zip.v1",
                1,
                &DerivedEntryKey::from_transformation("member:game.gba".to_owned()),
            )?;
            scope.commit()?;
            Ok::<_, ApplicationPortError>((first, second, found))
        })
        .expect("derived repository operations");

    assert_eq!(first, second);
    let found = found.expect("derived child");
    assert_eq!(found.source_entry_id(), first);
    assert!(found.relative_locator().is_none());
    assert!(found.locator_key().is_none());
    assert!(found.provider_native_identity().is_none());
    assert!(found.source_fingerprint().is_none());
    assert_eq!(
        found
            .derived_locator()
            .expect("derived row has a derived locator")
            .as_transformation_value(),
        "member:game.gba"
    );
    assert_eq!(
        found
            .derived_entry_key()
            .expect("derived row has a derived entry key")
            .as_transformation_value(),
        "member:game.gba"
    );
    assert_eq!(
        found
            .derived_fingerprint()
            .expect("derived row has a derived fingerprint")
            .as_transformation_value(),
        "member-fingerprint:v1"
    );

    let source_id = first;
    let matched = executor
        .execute(&context(), move |mut scope| {
            let evidence = SourceVersionEvidence::derived(
                source_id,
                DerivedFingerprint::from_transformation("member-fingerprint:v1".to_owned()),
                scan,
            );
            let wrong_fingerprint = SourceVersionEvidence::derived(
                source_id,
                DerivedFingerprint::from_transformation("member-fingerprint:v2".to_owned()),
                scan,
            );
            let provider_evidence = SourceVersionEvidence::provider(
                source_id,
                Some("member-fingerprint:v1".to_owned()),
                scan,
            );
            let mut logical = scope.logical_content();
            let result = (
                logical.source_version_matches(&evidence)?,
                logical.source_version_matches(&wrong_fingerprint)?,
                logical.source_version_matches(&provider_evidence)?,
            );
            scope.commit()?;
            Ok::<_, ApplicationPortError>(result)
        })
        .expect("derived source-version checks");
    assert_eq!(matched, (true, false, false));

    executor
        .with_connection_for_tests(context(), |connection| {
            assert_eq!(
                connection.scalar_i64(
                    "SELECT COUNT(*) FROM source_entry
                     WHERE coordinate_kind = 'derived'
                       AND relative_locator IS NULL
                       AND locator_key IS NULL
                       AND provider_native_identity IS NULL
                       AND source_fingerprint IS NULL
                       AND derived_locator = 'member:game.gba'
                       AND derived_entry_key = 'member:game.gba'
                       AND derived_fingerprint = 'member-fingerprint:v1'
                       AND derivation_transformation_id = 'argus.transformation.zip.v1'
                       AND derivation_revision = 1"
                )?,
                1
            );
            Ok(())
        })
        .expect("coordinate invariant");
    executor.shutdown().expect("shutdown");
}
