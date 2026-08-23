use argus_application::{
    ContentType, ErrorCode, GameContentPresence, IdentificationState, IdentityDigest,
    IdentitySchemeCatalog, ListGamesQuery, PlatformId, QueryValidationError,
    TransformationRegistry,
};

#[test]
fn production_identity_catalog_maps_each_supported_platform_to_one_scheme() {
    let catalog = IdentitySchemeCatalog::production();

    assert_eq!(
        catalog
            .select(PlatformId::NintendoGb, ContentType::CartridgeImage)
            .expect("GB scheme")
            .id(),
        "argus.content.identity.nintendo-gb.cartridge.v1"
    );
    assert_eq!(
        catalog
            .select(PlatformId::NintendoGbc, ContentType::CartridgeImage)
            .expect("GBC scheme")
            .id(),
        "argus.content.identity.nintendo-gbc.cartridge.v1"
    );
    assert_eq!(
        catalog
            .select(PlatformId::NintendoGba, ContentType::CartridgeImage)
            .expect("GBA scheme")
            .id(),
        "argus.content.identity.nintendo-gba.cartridge.v1"
    );
}

#[test]
fn transformation_registry_is_distinct_from_identity_scheme_catalog() {
    let registry = TransformationRegistry::production();
    let catalog = IdentitySchemeCatalog::production();

    assert_eq!(registry.len(), 3);
    assert_eq!(catalog.len(), 3);
    assert!(
        registry
            .descriptors()
            .iter()
            .all(|descriptor| descriptor.id().starts_with("argus.transformation."))
    );
    assert_ne!(
        registry.descriptors()[0].id(),
        catalog.descriptors()[0].id()
    );
}

#[test]
fn identity_policy_maps_typed_transformation_output_after_recognition() {
    let catalog = IdentitySchemeCatalog::production();
    let identity = catalog
        .select_identity(
            PlatformId::NintendoGba,
            ContentType::CartridgeImage,
            IdentityDigest::from_bytes([7; 32]),
        )
        .expect("active GBA scheme");
    assert_eq!(
        identity.scheme_id(),
        "argus.content.identity.nintendo-gba.cartridge.v1"
    );
    assert_eq!(identity.revision(), 1);
}

#[test]
fn presence_and_identification_states_are_independent() {
    assert_ne!(
        GameContentPresence::Orphaned,
        GameContentPresence::Unavailable
    );
    assert_ne!(
        IdentificationState::NeedsReidentification,
        IdentificationState::Unidentified
    );
}

#[test]
fn list_games_rejects_valid_but_inactive_query_concepts_with_invalid_argument() {
    let query = ListGamesQuery::builder()
        .search(Some("zelda".to_owned()))
        .build()
        .expect_err("search is not active in P03-001");

    assert_eq!(
        query,
        QueryValidationError::Application(ErrorCode::ValidationInvalidArgument)
    );
}
