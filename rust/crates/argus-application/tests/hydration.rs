use argus_application::IdentityDigest;
use argus_application::{
    AvailabilityState, ContentIdentitySummary, ContentType, ExactMatchEvidence,
    GameContentPresence, GameContentSummary, GameDetail, GameLifecycle, HydrationMappingCandidate,
    HydrationPlanner, HydrationState, HydrationTarget, IdentificationState, MappingState,
    MatchBasis, PlatformId, ProviderId,
};
use argus_domain::{GameContentId, GameId};

fn content_id() -> GameContentId {
    GameContentId::from_bytes([4; 16]).expect("test identity is non-zero")
}

fn candidate(external_game_id: &str) -> HydrationMappingCandidate {
    HydrationMappingCandidate::new(
        content_id(),
        ProviderId::Playmatch,
        external_game_id,
        None,
        "gb",
        Some(99),
        ExactMatchEvidence::Playmatch {
            game_content_id: content_id(),
            platform_id: PlatformId::NintendoGb,
            external_game_id: external_game_id.to_owned(),
            submitted_identity: "sha256:abcd".to_owned(),
            response_identity: "sha256:abcd".to_owned(),
        },
        7,
        1_000,
    )
}

#[test]
fn hydration_planner_preserves_exact_ambiguity_as_rejected_evidence() {
    let one = HydrationPlanner::build_mappings(&[candidate("one")]);
    assert_eq!(one.len(), 1);
    assert_eq!(one[0].state(), MappingState::Current);
    assert_eq!(one[0].match_basis(), MatchBasis::PlaymatchExactContent);

    let ambiguous = HydrationPlanner::build_mappings(&[candidate("one"), candidate("two")]);
    assert_eq!(ambiguous.len(), 2);
    assert!(
        ambiguous
            .iter()
            .all(|mapping| mapping.state() == MappingState::RejectedByPolicy)
    );
}

#[test]
fn hydration_target_validation_requires_identified_content_belonging_to_the_game() {
    let game_id = GameId::from_bytes([8; 16]).expect("game id");
    let content_id = GameContentId::from_bytes([9; 16]).expect("content id");
    let detail = GameDetail::new(
        game_id,
        PlatformId::NintendoGb,
        GameLifecycle::Active,
        HydrationState::PartiallyHydrated,
        "Fixture",
        Vec::new(),
        vec![GameContentSummary::with_identity(
            content_id,
            PlatformId::NintendoGb,
            ContentType::CartridgeImage,
            GameContentPresence::Available,
            IdentificationState::Identified,
            1,
            Some(ContentIdentitySummary::new(
                "fixture.identity",
                1,
                IdentityDigest::from_bytes([1; 32]),
            )),
            None,
        )],
        AvailabilityState::Available,
    );
    let target = HydrationTarget::new(
        game_id,
        content_id,
        PlatformId::NintendoGb,
        "sha256:fixture",
        "nintendo.gb",
    );

    assert!(target.validate_against_game(&detail).is_ok());
    assert!(
        HydrationTarget::new(
            game_id,
            GameContentId::from_bytes([10; 16]).expect("other content id"),
            PlatformId::NintendoGb,
            "sha256:fixture",
            "nintendo.gb",
        )
        .validate_against_game(&detail)
        .is_err()
    );
}
