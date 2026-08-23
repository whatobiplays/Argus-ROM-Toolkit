use argus_application::{
    AvailabilityState, ContentIdentitySummary, ContentProvenanceSummary, ContentType,
    GameContentPresence, GameContentSummary, GameDetail, GameId, GameLibraryPage, GameLibraryRow,
    GameLifecycle, GameListCursor, GameMembershipSummary, GroupingBasis, HydrationState,
    IdentificationState, IdentityDigest, MembershipRelationship, PlatformId, ScanRunId,
    SourceEntryId,
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
    );
    let detail = GameDetail::new(
        game_id,
        PlatformId::NintendoGba,
        GameLifecycle::Active,
        HydrationState::PartiallyHydrated,
        "Fallback GBA",
        vec![GameMembershipSummary::new(
            content_id,
            MembershipRelationship::Primary,
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

    let page = game_page_dto(&GameLibraryPage::new(
        vec![row],
        Some(GameListCursor::from_paging_keys("Fallback GBA", game_id)),
    ));
    assert_eq!(page.items.len(), 1);
    assert!(
        page.next_cursor
            .as_deref()
            .is_some_and(|value| value.starts_with("v1:"))
    );
}
