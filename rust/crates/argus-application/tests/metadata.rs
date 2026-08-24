use std::collections::BTreeSet;

use argus_application::{
    ExactMatchEvidence, MappingState, MetadataCandidate, MetadataResolutionPolicy, ProviderId,
    ProviderMetadata, accept_exact_mapping, accept_exact_mappings, resolve_metadata,
    resolve_provider_metadata,
};
use argus_domain::{GameContentId, PlatformId};

fn content_id() -> GameContentId {
    GameContentId::from_bytes([1; 16]).expect("test identity is non-zero")
}

#[test]
fn only_exact_provider_evidence_becomes_current_mapping() {
    let exact = accept_exact_mapping(ExactMatchEvidence::Playmatch {
        game_content_id: content_id(),
        platform_id: PlatformId::NintendoGb,
        external_game_id: "playmatch-game".to_owned(),
        submitted_identity: "sha256:0123".to_owned(),
        response_identity: "sha256:0123".to_owned(),
    });
    assert!(exact.is_current());

    let fuzzy = accept_exact_mapping(ExactMatchEvidence::TitleOnly {
        provider_id: ProviderId::GameTdb,
        external_game_id: "gametdb-game".to_owned(),
    });
    assert!(!fuzzy.is_current());
}

#[test]
fn local_resolution_obeys_provider_enablement_and_locale_preferences() {
    let candidates = vec![
        MetadataCandidate::new(
            ProviderId::Playmatch,
            "playmatch-game",
            "Alpha",
            "us",
            "en",
            80,
            10,
        ),
        MetadataCandidate::new(
            ProviderId::GameTdb,
            "gametdb-game",
            "Beta",
            "jp",
            "ja",
            100,
            20,
        ),
    ];
    let mut enabled = BTreeSet::new();
    enabled.insert(ProviderId::GameTdb);
    let policy = MetadataResolutionPolicy::new(enabled, ["jp"], ["ja"]);

    let resolved = resolve_metadata(&candidates, &policy);

    assert_eq!(resolved.display_title(), Some("Beta"));
    assert_eq!(resolved.provider_id(), Some(ProviderId::GameTdb));
}

#[test]
fn legacy_metadata_resolution_prefers_matching_locale_over_missing_locale() {
    let candidates = vec![
        MetadataCandidate::new(
            ProviderId::Playmatch,
            "missing-locale",
            "Missing locale",
            "",
            "",
            100,
            100,
        ),
        MetadataCandidate::new(
            ProviderId::GameTdb,
            "matching-locale",
            "Matching locale",
            "us",
            "en",
            80,
            1,
        ),
    ];
    let policy = MetadataResolutionPolicy::new(
        BTreeSet::from([ProviderId::Playmatch, ProviderId::GameTdb]),
        ["us"],
        ["en"],
    );

    let resolved = resolve_metadata(&candidates, &policy);

    assert_eq!(resolved.display_title(), Some("Matching locale"));
    assert_eq!(resolved.provider_id(), Some(ProviderId::GameTdb));
}

#[test]
fn gametdb_requires_one_exact_native_identifier_and_ambiguity_stays_unmatched() {
    let exact = ExactMatchEvidence::GameTdb {
        game_content_id: content_id(),
        platform_id: PlatformId::NintendoGb,
        external_game_id: "gametdb-game".to_owned(),
        native_identifier: "product:DMG-ABCD".to_owned(),
        validated_identifier: "product:DMG-ABCD".to_owned(),
    };
    assert!(accept_exact_mapping(exact.clone()).is_current());
    assert!(!accept_exact_mappings(&[exact.clone(), exact]).is_current());

    let mismatch = ExactMatchEvidence::GameTdb {
        game_content_id: content_id(),
        platform_id: PlatformId::NintendoGb,
        external_game_id: "gametdb-game".to_owned(),
        native_identifier: "product:DMG-ABCD".to_owned(),
        validated_identifier: "product:DMG-WXYZ".to_owned(),
    };
    assert!(!accept_exact_mapping(mismatch).is_current());
}

#[test]
fn provider_metadata_resolution_is_field_specific_and_excludes_expired_records() {
    let candidates = vec![
        ProviderMetadata::new(
            ProviderId::Playmatch,
            "playmatch-game",
            4,
            Some("us".to_owned()),
            Some("en".to_owned()),
            900,
            Some(2_000),
            Some("Alpha".to_owned()),
            vec![],
            None,
            None,
            vec![],
            vec![],
            vec![],
            vec![],
            70,
            "playmatch-fixture",
        ),
        ProviderMetadata::new(
            ProviderId::GameTdb,
            "gametdb-game",
            9,
            Some("us".to_owned()),
            Some("en".to_owned()),
            950,
            Some(900),
            Some("Expired".to_owned()),
            vec![],
            Some("GameTDB description".to_owned()),
            None,
            vec!["Developer".to_owned()],
            vec![],
            vec![],
            vec!["en".to_owned()],
            100,
            "gametdb-fixture",
        ),
    ];
    let policy = MetadataResolutionPolicy::new(
        [ProviderId::Playmatch, ProviderId::GameTdb]
            .into_iter()
            .collect(),
        ["us"],
        ["en"],
    );

    let resolved = resolve_provider_metadata(&candidates, &policy, 1_000);

    assert_eq!(resolved.display_title(), Some("Alpha"));
    assert_eq!(resolved.description(), None);
    assert_eq!(resolved.provider_id(), Some(ProviderId::Playmatch));
    assert_eq!(resolved.resolved_at(), 1_000);
    assert_eq!(resolved.field_provenance().len(), 2);
}

#[test]
fn provider_metadata_resolution_ignores_stale_mapping_evidence() {
    let stale = ProviderMetadata::new(
        ProviderId::GameTdb,
        "stale-game",
        2,
        Some("us".to_owned()),
        Some("en".to_owned()),
        10,
        None,
        Some("Stale title".to_owned()),
        Vec::new(),
        None,
        None,
        Vec::new(),
        Vec::new(),
        Vec::new(),
        Vec::new(),
        100,
        "fixture",
    )
    .with_mapping_state(MappingState::Stale);
    let policy =
        MetadataResolutionPolicy::new(BTreeSet::from([ProviderId::GameTdb]), ["us"], ["en"]);

    let resolved = resolve_provider_metadata(&[stale], &policy, 100);

    assert_eq!(resolved.display_title(), None);
}

#[test]
fn provider_metadata_resolution_prefers_newer_provider_revision_before_stable_id() {
    let candidates = vec![
        ProviderMetadata::new(
            ProviderId::GameTdb,
            "z-old",
            2,
            Some("us".to_owned()),
            Some("en".to_owned()),
            90,
            Some(1_000),
            Some("Newer revision".to_owned()),
            Vec::new(),
            None,
            None,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
            100,
            "fixture",
        ),
        ProviderMetadata::new(
            ProviderId::GameTdb,
            "a-newer-id",
            1,
            Some("us".to_owned()),
            Some("en".to_owned()),
            90,
            Some(1_000),
            Some("Stable id winner".to_owned()),
            Vec::new(),
            None,
            None,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Vec::new(),
            100,
            "fixture",
        ),
    ];
    let policy =
        MetadataResolutionPolicy::new(BTreeSet::from([ProviderId::GameTdb]), ["us"], ["en"]);

    let resolved = resolve_provider_metadata(&candidates, &policy, 100);

    assert_eq!(resolved.display_title(), Some("Newer revision"));
}
