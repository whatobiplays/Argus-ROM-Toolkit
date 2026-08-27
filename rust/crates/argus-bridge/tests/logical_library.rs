use argus_application::{
    ArtworkType, AvailabilityState, ContentIdentitySummary, ContentProvenanceSummary, ContentType,
    GameContentPresence, GameContentSourceSummary, GameContentSummary, GameDetail, GameId,
    GameLibraryPage, GameLibraryRow, GameLifecycle, GameListCursor, GameMembershipSummary,
    GroupingBasis, HydrationState, IdentificationState, IdentityDigest, LibraryRootId,
    LibrarySourceId, MembershipRelationship, MetadataFieldProvenance, PlatformId, ResolvedArtwork,
    ResolvedMetadata, ScanRunId, SourceEntryId,
};
use argus_bridge::{game_detail_dto, game_library_row_dto, game_page_dto};

fn game_id(value: u8) -> GameId {
    GameId::from_bytes([value; 16]).expect("non-zero game id")
}

fn content_id(value: u8) -> argus_application::GameContentId {
    argus_application::GameContentId::from_bytes([value; 16]).expect("non-zero content id")
}

#[test]
fn logical_library_bridge_dtos_preserve_bounded_projection_fields() {
    let game_id = game_id(1);
    let content_id = content_id(2);
    let source_id = SourceEntryId::from_bytes([3; 16]).expect("source id");
    let scan_id = ScanRunId::from_bytes([4; 16]).expect("scan id");
    let library_source_id = LibrarySourceId::from_bytes([5; 16]).expect("library source id");
    let library_root_id = LibraryRootId::from_bytes([6; 16]).expect("library root id");
    let identity = ContentIdentitySummary::new(
        "argus.content.identity.nintendo-gba.cartridge.v1",
        1,
        IdentityDigest::from_bytes([0x09; 32]),
    );
    let provenance =
        ContentProvenanceSummary::new(source_id, "raw", Some("v1:32:1".to_owned()), scan_id);
    let summary = GameContentSummary::with_identity(
        content_id,
        PlatformId::NintendoGba,
        ContentType::CartridgeImage,
        GameContentPresence::Available,
        IdentificationState::Identified,
        2,
        Some(identity),
        Some(provenance),
    )
    .with_sources(vec![GameContentSourceSummary::new(
        source_id,
        library_source_id,
        "Local source",
        library_root_id,
        "Games",
        "NES/Example.nes",
    )]);
    let detail = GameDetail::new(
        game_id,
        PlatformId::NintendoGba,
        GameLifecycle::Active,
        HydrationState::PartiallyHydrated,
        "Fallback GBA",
        vec![GameMembershipSummary::new(
            content_id,
            MembershipRelationship::PrimaryContent,
            GroupingBasis::Provisional,
            1,
        )],
        vec![summary],
        AvailabilityState::Available,
    );

    let dto = game_detail_dto(&detail);
    assert_eq!(dto.game_id, game_id.to_string());
    assert_eq!(dto.platform_id, argus_bridge::PlatformIdDto::NintendoGba);
    assert_eq!(
        dto.hydration_state,
        argus_bridge::HydrationStateDto::PartiallyHydrated
    );
    assert_eq!(dto.memberships.len(), 1);
    assert_eq!(dto.content.len(), 1);
    let content = &dto.content[0];
    assert_eq!(content.source_count, 2);
    assert_eq!(
        content.identification,
        argus_bridge::IdentificationStateDto::Identified
    );
    assert_eq!(
        content.identity.as_ref().expect("identity").digest,
        "09".repeat(32)
    );
    assert_eq!(
        content
            .provenance
            .as_ref()
            .expect("provenance")
            .source_entry_id,
        source_id.to_string()
    );
    let source = &content.sources[0];
    assert_eq!(source.source_entry_id, source_id.to_string());
    assert_eq!(source.library_source_id, library_source_id.to_string());
    assert_eq!(source.library_root_id, library_root_id.to_string());
    assert_eq!(source.safe_location_presentation, "NES/Example.nes");

    let row = GameLibraryRow::from_persisted(
        game_id,
        "Fallback GBA",
        PlatformId::NintendoGba,
        HydrationState::PartiallyHydrated,
        AvailabilityState::Available,
        1,
        2,
        1000,
    );
    let row_dto = game_library_row_dto(&row);
    assert_eq!(row_dto.game_id, game_id.to_string());
    assert_eq!(row_dto.content_count, 1);
    assert_eq!(row_dto.source_count, 2);
    assert_eq!(row_dto.updated_at_ms, 1000);

    let enriched_row = GameLibraryRow::from_persisted_with_presentation(
        game_id,
        "Fallback GBA",
        PlatformId::NintendoGba,
        Some("us".to_owned()),
        None,
        Some("1990-01-01".to_owned()),
        HydrationState::PartiallyHydrated,
        AvailabilityState::Available,
        1,
        2,
        1000,
    );
    let enriched_row_dto = game_library_row_dto(&enriched_row);
    assert_eq!(enriched_row_dto.presentation_region, Some("us".to_owned()));
    assert_eq!(enriched_row_dto.selected_cover_asset_id, None);

    let page = game_page_dto(&GameLibraryPage::new(
        vec![row],
        Some(GameListCursor::from_paging_keys("Fallback GBA", game_id).expect("cursor")),
    ));
    assert_eq!(page.items.len(), 1);
    assert!(
        page.next_cursor
            .as_deref()
            .is_some_and(|value| value.starts_with("v1:"))
    );
}

#[test]
fn enriched_game_bridge_dto_contains_provenance_without_provider_locators() {
    let game_id = game_id(8);
    let content_id = content_id(9);
    let detail = GameDetail::new(
        game_id,
        PlatformId::NintendoGb,
        GameLifecycle::Active,
        HydrationState::PartiallyHydrated,
        "Fallback",
        vec![GameMembershipSummary::new(
            content_id,
            MembershipRelationship::PrimaryContent,
            GroupingBasis::ExactContentIdentity,
            1,
        )],
        Vec::new(),
        AvailabilityState::Available,
    )
    .with_enrichment(
        Some(ResolvedMetadata::from_persisted(
            Some("Resolved".to_owned()),
            Some("resolved".to_owned()),
            Some("description".to_owned()),
            None,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            Some("us".to_owned()),
            vec!["en".to_owned()],
            vec![MetadataFieldProvenance::new(
                "display_title",
                Some(argus_application::ProviderId::GameTdb),
                Some("tdb-1".to_owned()),
                "fixture:gametdb",
            )],
            2,
            100,
            Some(argus_application::ProviderId::GameTdb),
        )),
        vec![ResolvedArtwork::new(
            game_id,
            ArtworkType::CoverFront,
            "gametdb:tdb-1:cover",
            None,
            0,
            "deterministic_policy",
            1,
            100,
        )],
    );

    let dto = game_detail_dto(&detail);
    assert_eq!(
        dto.resolved_metadata
            .as_ref()
            .expect("metadata")
            .display_title,
        Some("Resolved".to_owned())
    );
    assert_eq!(dto.resolved_artwork.as_ref().expect("artwork").len(), 1);
    assert_eq!(
        dto.resolved_artwork.as_ref().expect("artwork")[0].asset_id,
        None
    );
    assert!(!format!("{:?}", dto).contains("https://"));
}
