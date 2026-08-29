#![cfg(feature = "test-support")]

use argus_application::{
    ApplicationPortError, ArchiveAdmissionError, DerivedEntryKey, DerivedEntryObservation,
    DerivedFingerprint, DerivedLocator, DerivedScopeIdentity, DerivedScopeOutcome,
    JobRunRepository, LibraryRootAvailability, LibraryRootId, LibraryRootRepository,
    LibrarySourceRepository, NewJobRun, NewLibraryRoot, NewScanRun, NewSourceEntry,
    OperationContext, OperationName, RelativeSourceLocator, RootLocator, ScanRunId,
    ScanRunRepository, SourceEntryClassification, SourceEntryId, SourceEntryKind,
    SourceEntryRepository, SubsystemName, TraceId, UnitOfWork, UnitOfWorkFactory,
    evaluate_archive_eligibility, reconcile_derived_scope,
};
use argus_infrastructure::sqlite::SqliteDatabaseExecutor;
use tempfile::tempdir;

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(771_u128).expect("trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("archive_library_convergence").expect("operation"),
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
                RelativeSourceLocator::from_provider("collection.7z".to_owned()),
                argus_application::SourceLocatorKey::from_provider("collection.7z".to_owned()),
                "collection.7z",
                "collection.7z",
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

#[test]
fn rejected_multi_game_archive_keeps_derived_truth_but_creates_no_game_content() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("archive.sqlite3")).expect("database");
    let (root, scan, parent) = seed(&executor);
    let scope = DerivedScopeIdentity {
        parent_source_entry_id: parent,
        transformation_id: "argus.transformation.sevenzip.v1",
        transformation_revision: 1,
    };
    let observations = vec![
        observation("mario.nes", "member:mario.nes", "mario-v1"),
        observation("zelda.nes", "member:zelda.nes", "zelda-v1"),
        observation("README.txt", "member:README.txt", "readme-v1"),
    ];

    let reconciled = executor
        .execute(&context(), move |mut work| {
            let ids = reconcile_derived_scope(
                &mut work.source_entries(),
                &scope,
                &observations,
                scan,
                0,
                true,
                DerivedScopeOutcome::Complete,
            )?;
            work.commit()?;
            Ok::<_, ApplicationPortError>(ids)
        })
        .expect("derived scope reconciliation");
    assert_eq!(reconciled.len(), 3);

    let admission = evaluate_archive_eligibility(&["mario", "zelda"]);
    assert_eq!(admission, Err(ArchiveAdmissionError::MultiGameUnsupported));

    executor
        .with_connection_for_tests(context(), move |connection| {
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM source_entry
                     WHERE parent_source_entry_id = '{}' AND coordinate_kind = 'derived'",
                    parent
                ))?,
                3
            );
            assert_eq!(
                connection.scalar_i64("SELECT COUNT(*) FROM game_content")?,
                0
            );
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM source_entry
                     WHERE library_root_id = '{}' AND coordinate_kind = 'derived'
                       AND relative_locator IS NULL
                       AND locator_key IS NULL
                       AND provider_native_identity IS NULL
                       AND source_fingerprint IS NULL",
                    root
                ))?,
                3
            );
            Ok(())
        })
        .expect("archive truth and logical admission state");
    executor.shutdown().expect("shutdown");
}

#[test]
fn nested_scope_reconciliation_uses_parent_root_and_partial_scope_preserves_absence() {
    let directory = tempdir().expect("tempdir");
    let executor =
        SqliteDatabaseExecutor::open(directory.path().join("nested.sqlite3")).expect("database");
    let (_root, first_scan, archive) = seed(&executor);
    let outer_scope = DerivedScopeIdentity {
        parent_source_entry_id: archive,
        transformation_id: "argus.transformation.sevenzip.v1",
        transformation_revision: 1,
    };
    let outer_child = observation("inner.7z", "member:inner.7z", "inner-v1");
    let outer_id = executor
        .execute(&context(), move |mut work| {
            let ids = reconcile_derived_scope(
                &mut work.source_entries(),
                &outer_scope,
                std::slice::from_ref(&outer_child),
                first_scan,
                0,
                true,
                DerivedScopeOutcome::Complete,
            )?;
            work.commit()?;
            Ok::<_, ApplicationPortError>(ids[0])
        })
        .expect("outer scope");

    let inner_scope = DerivedScopeIdentity {
        parent_source_entry_id: outer_id,
        transformation_id: "argus.transformation.zip.v1",
        transformation_revision: 1,
    };
    let inner_observations = vec![
        observation("game.gba", "member:game.gba", "game-v1"),
        observation("cover.png", "member:cover.png", "cover-v1"),
    ];
    let complete_observations = inner_observations.clone();
    executor
        .execute(&context(), move |mut work| {
            reconcile_derived_scope(
                &mut work.source_entries(),
                &inner_scope,
                &complete_observations,
                first_scan,
                0,
                true,
                DerivedScopeOutcome::Complete,
            )?;
            work.commit()?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("inner scope");

    executor
        .execute(&context(), move |mut work| {
            reconcile_derived_scope(
                &mut work.source_entries(),
                &inner_scope,
                std::slice::from_ref(&inner_observations[0]),
                first_scan,
                0,
                true,
                DerivedScopeOutcome::Partial,
            )?;
            work.commit()?;
            Ok::<_, ApplicationPortError>(())
        })
        .expect("partial scope");

    executor
        .with_connection_for_tests(context(), move |connection| {
            assert_eq!(
                connection.scalar_i64(&format!(
                    "SELECT COUNT(*) FROM source_entry
                     WHERE parent_source_entry_id = '{}' AND coordinate_kind = 'derived'",
                    outer_id
                ))?,
                2
            );
            Ok(())
        })
        .expect("partial scope retains absent member");
    executor.shutdown().expect("shutdown");
}
