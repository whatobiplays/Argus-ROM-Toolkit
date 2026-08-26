use argus_application::{
    ContentType, ErrorCode, GameContentPresence, IdentificationState, IdentityDigest,
    IdentitySchemeCatalog, ListGamesQuery, PlatformId, ProviderId, QueryValidationError,
    TransformationRegistry,
};

#[test]
fn production_identity_catalog_maps_each_supported_platform_to_one_scheme() {
    let catalog = IdentitySchemeCatalog::production();

    let expected = [
        (
            PlatformId::NintendoNes,
            ContentType::CartridgeImage,
            &["nes-2", "nes-ines"][..],
            "argus.content.identity.nintendo-nes.cartridge.v1",
        ),
        (
            PlatformId::NintendoFds,
            ContentType::MagneticDiskImage,
            &["fds-fw", "fds-headerless"][..],
            "argus.content.identity.nintendo-fds.disk.v1",
        ),
        (
            PlatformId::NintendoSnes,
            ContentType::CartridgeImage,
            &["snes-linear", "snes-copier-headered"][..],
            "argus.content.identity.nintendo-snes.cartridge.v1",
        ),
        (
            PlatformId::NintendoGb,
            ContentType::CartridgeImage,
            &["raw-cartridge-image"][..],
            "argus.content.identity.nintendo-gb.cartridge.v1",
        ),
        (
            PlatformId::NintendoGbc,
            ContentType::CartridgeImage,
            &["raw-cartridge-image"][..],
            "argus.content.identity.nintendo-gbc.cartridge.v1",
        ),
        (
            PlatformId::NintendoGba,
            ContentType::CartridgeImage,
            &["raw-cartridge-image"][..],
            "argus.content.identity.nintendo-gba.cartridge.v1",
        ),
        (
            PlatformId::NintendoN64,
            ContentType::CartridgeImage,
            &["n64-native", "n64-byteswapped16", "n64-byteswapped32"][..],
            "argus.content.identity.nintendo-n64.cartridge.v1",
        ),
        (
            PlatformId::NintendoNds,
            ContentType::CartridgeImage,
            &["raw-cartridge-image"][..],
            "argus.content.identity.nintendo-nds.cartridge.v1",
        ),
        (
            PlatformId::Nintendo3ds,
            ContentType::CartridgeImage,
            &["ncsd-nocrypto"][..],
            "argus.content.identity.nintendo-3ds.nocrypto-ncsd.v1",
        ),
        (
            PlatformId::SegaSms,
            ContentType::CartridgeImage,
            &["raw-cartridge-image"][..],
            "argus.content.identity.sega-sms.cartridge.v1",
        ),
        (
            PlatformId::SegaGameGear,
            ContentType::CartridgeImage,
            &["raw-cartridge-image"][..],
            "argus.content.identity.sega-gamegear.cartridge.v1",
        ),
        (
            PlatformId::SegaGenesis,
            ContentType::CartridgeImage,
            &["genesis-linear-be", "genesis-smd"][..],
            "argus.content.identity.sega-genesis.cartridge.v1",
        ),
        (
            PlatformId::Sega32x,
            ContentType::CartridgeImage,
            &["genesis-linear-be"][..],
            "argus.content.identity.sega-32x.cartridge.v1",
        ),
    ];

    assert_eq!(catalog.len(), expected.len());
    for (platform, content_type, representations, scheme_id) in expected {
        let descriptor = catalog.select(platform, content_type).expect("catalog row");
        assert_eq!(descriptor.id(), scheme_id);
        assert_eq!(descriptor.representations(), representations);
        for representation in representations {
            assert!(descriptor.accepts_representation(representation));
        }
        assert!(!descriptor.accepts_representation("unsupported"));
    }
}

#[test]
fn transformation_registry_is_distinct_from_identity_scheme_catalog() {
    let registry = TransformationRegistry::production();
    let catalog = IdentitySchemeCatalog::production();

    assert_eq!(registry.len(), 19);
    assert_eq!(catalog.len(), 13);
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
fn provider_platform_coverage_is_explicit_for_every_catalog_platform() {
    let platforms = [
        PlatformId::NintendoNes,
        PlatformId::NintendoFds,
        PlatformId::NintendoSnes,
        PlatformId::NintendoGb,
        PlatformId::NintendoGbc,
        PlatformId::NintendoGba,
        PlatformId::NintendoN64,
        PlatformId::NintendoNds,
        PlatformId::Nintendo3ds,
        PlatformId::SegaSms,
        PlatformId::SegaGameGear,
        PlatformId::SegaGenesis,
        PlatformId::Sega32x,
    ];

    for platform in platforms {
        assert_eq!(
            ProviderId::Playmatch.platform_mapping(platform).mapped_id(),
            Some(platform.as_str())
        );
        assert_eq!(
            ProviderId::GameTdb.platform_mapping(platform).mapped_id(),
            Some(platform.as_str())
        );
        assert_eq!(
            ProviderId::SteamGridDb
                .platform_mapping(platform)
                .mapped_id(),
            None
        );
    }
}

#[test]
fn identity_policy_maps_typed_transformation_output_after_recognition() {
    let catalog = IdentitySchemeCatalog::production();
    let identity = catalog
        .select_identity(
            PlatformId::NintendoGba,
            ContentType::CartridgeImage,
            "raw-cartridge-image",
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
