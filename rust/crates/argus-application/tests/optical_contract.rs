use argus_application::{
    OpticalDependencyError, RelativeSourceLocator, ScanRunId, SourceEntryClassification,
    SourceEntryId, SourceEntryKind, SourceEntryRecord, SourceLocatorKey,
    resolve_optical_dependencies,
};

fn id(value: &str) -> SourceEntryId {
    SourceEntryId::try_from(value).expect("source id")
}

fn scan(value: &str) -> ScanRunId {
    ScanRunId::try_from(value).expect("scan id")
}

fn file(id_value: &str, locator: &str) -> SourceEntryRecord {
    SourceEntryRecord::new(
        id(id_value),
        None,
        RelativeSourceLocator::from_provider(locator.to_owned()),
        SourceLocatorKey::from_provider(locator.to_owned()),
        locator.rsplit('/').next().unwrap_or(locator),
        locator,
        SourceEntryKind::File,
        SourceEntryClassification::ContentCandidate,
        None,
        Some("fingerprint".to_owned()),
        scan("11111111111111111111111111111111"),
    )
}

#[test]
fn resolves_descriptor_relative_members_only_against_committed_files() {
    let descriptor = RelativeSourceLocator::from_provider("disc/game.cue".to_owned());
    let candidates = vec![
        file("22222222222222222222222222222222", "disc/game.cue"),
        file("33333333333333333333333333333333", "disc/track.bin"),
    ];

    let resolved =
        resolve_optical_dependencies(&descriptor, &["track.bin".to_owned()], &candidates)
            .expect("dependency");
    assert_eq!(
        resolved[0].source_entry_id(),
        id("33333333333333333333333333333333")
    );
}

#[test]
fn rejects_traversal_missing_ambiguous_and_duplicate_dependencies() {
    let descriptor = RelativeSourceLocator::from_provider("disc/game.cue".to_owned());
    let candidates = vec![
        file("33333333333333333333333333333333", "disc/track.bin"),
        file("44444444444444444444444444444444", "disc/track.bin"),
    ];

    assert_eq!(
        resolve_optical_dependencies(&descriptor, &["../track.bin".to_owned()], &candidates),
        Err(OpticalDependencyError::CrossRoot)
    );
    assert_eq!(
        resolve_optical_dependencies(&descriptor, &["missing.bin".to_owned()], &candidates),
        Err(OpticalDependencyError::Missing)
    );
    assert_eq!(
        resolve_optical_dependencies(&descriptor, &["track.bin".to_owned()], &candidates),
        Err(OpticalDependencyError::Ambiguous)
    );
    assert_eq!(
        resolve_optical_dependencies(
            &descriptor,
            &["track.bin".to_owned(), "track.bin".to_owned()],
            &[candidates[0].clone()],
        ),
        Err(OpticalDependencyError::Duplicate)
    );
}
