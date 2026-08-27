use argus_application::{
    ContentDependencyCandidate, DerivedEntryKey, DerivedFingerprint, DerivedLocator,
    OpticalDependencyError, RelativeSourceLocator, ScanRunId, SourceEntryClassification,
    SourceEntryCoordinates, SourceEntryId, SourceEntryKind, SourceEntryRecord, SourceLocatorKey,
    resolve_content_dependencies, resolve_optical_dependencies,
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

#[test]
fn resolves_provider_neutral_derived_references_without_parsing_derived_locators() {
    let derived = SourceEntryRecord::from_coordinates(
        id("33333333333333333333333333333333"),
        Some(id("44444444444444444444444444444444")),
        "track.bin",
        "archive-member-display/track.bin",
        SourceEntryKind::File,
        SourceEntryClassification::SupportingEntry,
        SourceEntryCoordinates::Derived {
            derived_locator: DerivedLocator::from_transformation(
                "decoder-private-offset:untrusted-to-generic-code".to_owned(),
            ),
            derived_entry_key: DerivedEntryKey::from_transformation("member:track".to_owned()),
            derived_fingerprint: DerivedFingerprint::from_transformation("track-v1".to_owned()),
            transformation_id: "argus.transformation.zip.v1".to_owned(),
            transformation_revision: 1,
        },
        scan("11111111111111111111111111111111"),
    );
    let candidate = ContentDependencyCandidate::new(derived, "disc/track.bin");
    let resolved =
        resolve_content_dependencies("disc/game.cue", &["track.bin".to_owned()], &[candidate])
            .expect("derived dependency");
    assert_eq!(
        resolved[0].source_entry_id(),
        id("33333333333333333333333333333333")
    );
}

#[test]
fn rejects_provider_neutral_cross_root_references() {
    let result = resolve_content_dependencies("disc/game.cue", &["../outside.bin".to_owned()], &[]);
    assert_eq!(result, Err(OpticalDependencyError::CrossRoot));
}
