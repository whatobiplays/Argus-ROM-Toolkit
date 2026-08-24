use argus_application::{
    ArtworkAsset, ArtworkCandidate, ArtworkReference, ArtworkResolutionPolicy, ArtworkSource,
    ArtworkType, ProviderId, resolve_artwork,
};
use argus_domain::ArtworkAssetId;

#[test]
fn artwork_resolution_uses_type_policy_and_bounds_screenshot_gallery() {
    let mut candidates = vec![
        ArtworkCandidate::new(
            ProviderId::Playmatch,
            "pm-cover",
            ArtworkType::CoverFront,
            "https://example.test/cover.png",
            1_000,
        ),
        ArtworkCandidate::new(
            ProviderId::GameTdb,
            "tdb-cover",
            ArtworkType::CoverFront,
            "https://example.test/better-cover.png",
            2_000,
        ),
    ];
    for index in 0..20 {
        candidates.push(ArtworkCandidate::new(
            ProviderId::GameTdb,
            format!("screenshot-{index}"),
            ArtworkType::Screenshot,
            format!("https://example.test/{index}.png"),
            index,
        ));
    }

    let resolved = resolve_artwork(&candidates, &ArtworkResolutionPolicy::default());

    assert_eq!(
        resolved
            .selected(ArtworkType::CoverFront)
            .unwrap()
            .provider_id(),
        ProviderId::GameTdb
    );
    assert_eq!(resolved.gallery(ArtworkType::Screenshot).len(), 12);
}

#[test]
fn artwork_resolution_uses_locale_dimensions_quality_and_source_deduplication() {
    let mut policy = ArtworkResolutionPolicy::default();
    policy.set_locale_preferences(["jp"], ["ja"]);
    let candidates = vec![
        ArtworkCandidate::new(
            ProviderId::GameTdb,
            "cover-wrong-locale",
            ArtworkType::CoverFront,
            "asset:wrong-locale",
            4,
        )
        .with_details(Some("us"), Some("en"), Some(100), Some(100), 100),
        ArtworkCandidate::new(
            ProviderId::SteamGridDb,
            "cover-jp-small",
            ArtworkType::CoverFront,
            "asset:jp-small",
            4,
        )
        .with_details(Some("jp"), Some("ja"), Some(200), Some(200), 50),
        ArtworkCandidate::new(
            ProviderId::GameTdb,
            "cover-jp-large",
            ArtworkType::CoverFront,
            "asset:jp-large",
            4,
        )
        .with_details(Some("jp"), Some("ja"), Some(600), Some(900), 100),
        ArtworkCandidate::new(
            ProviderId::Playmatch,
            "same-bytes",
            ArtworkType::Screenshot,
            "https://fixture.invalid/same.png",
            2,
        )
        .with_details(Some("jp"), Some("ja"), Some(640), Some(360), 90),
        ArtworkCandidate::new(
            ProviderId::GameTdb,
            "same-source",
            ArtworkType::Screenshot,
            "https://fixture.invalid/same.png",
            2,
        )
        .with_details(Some("jp"), Some("ja"), Some(640), Some(360), 90),
    ];

    let resolved = resolve_artwork(&candidates, &policy);

    assert_eq!(
        resolved
            .selected(ArtworkType::CoverFront)
            .expect("cover winner")
            .external_asset_id(),
        "cover-jp-large"
    );
    assert_eq!(resolved.gallery(ArtworkType::Screenshot).len(), 1);
}

#[test]
fn artwork_asset_projection_contains_only_safe_metadata() {
    let asset = ArtworkAsset::new(
        ArtworkAssetId::from_bytes([7; 32]).expect("asset id"),
        32,
        64,
        "image/png",
        128,
    );

    assert_eq!(asset.width(), 32);
    assert_eq!(asset.height(), 64);
    assert_eq!(asset.mime_type(), "image/png");
    assert_eq!(asset.byte_size(), 128);
}

#[test]
fn artwork_reference_retains_adapter_quality_for_local_resolution() {
    let reference = ArtworkReference::new(
        "reference-1",
        ProviderId::GameTdb,
        "game-1",
        ArtworkType::CoverFront,
        ArtworkSource::ProviderAssetLocator("asset:cover".to_owned()),
        Some(600),
        Some(900),
        Some("png".to_owned()),
        Some("image/png".to_owned()),
        Some("jp".to_owned()),
        Some("ja".to_owned()),
        4,
    )
    .with_quality(92)
    .with_discovered_at(42);

    assert_eq!(reference.quality(), 92);
    assert_eq!(reference.discovered_at(), 42);
}

#[test]
fn artwork_resolution_prefers_freshness_before_stable_reference_id() {
    let candidates = vec![
        ArtworkCandidate::new(
            ProviderId::SteamGridDb,
            "a-stable-id",
            ArtworkType::Logo,
            "asset:a-stable-id",
            4,
        )
        .with_details(None::<String>, None::<String>, Some(300), Some(100), 90)
        .with_discovered_at(10),
        ArtworkCandidate::new(
            ProviderId::SteamGridDb,
            "z-fresh-id",
            ArtworkType::Logo,
            "asset:z-fresh-id",
            4,
        )
        .with_details(None::<String>, None::<String>, Some(300), Some(100), 90)
        .with_discovered_at(20),
    ];

    let resolved = resolve_artwork(&candidates, &ArtworkResolutionPolicy::default());

    assert_eq!(
        resolved
            .selected(ArtworkType::Logo)
            .expect("logo winner")
            .external_asset_id(),
        "z-fresh-id"
    );
}
