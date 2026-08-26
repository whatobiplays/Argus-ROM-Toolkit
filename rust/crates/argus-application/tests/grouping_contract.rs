use argus_application::{
    Game, GameContentId, GameId, GameLifecycle, GameMembership, GameRedirect, GroupingBasis,
    GroupingValidationError, MembershipRelationship, PlatformId, RedirectGraph,
    validate_continuity_anchor, validate_memberships,
};

fn game_id(byte: u8) -> GameId {
    GameId::from_bytes([byte; 16]).expect("non-zero game id")
}

fn content_id(byte: u8) -> GameContentId {
    GameContentId::from_bytes([byte; 16]).expect("non-zero content id")
}

fn membership(
    game_id: GameId,
    content_id: GameContentId,
    relationship: MembershipRelationship,
) -> GameMembership {
    GameMembership::new(
        game_id,
        content_id,
        relationship,
        GroupingBasis::ExactContentIdentity,
        1,
    )
}

#[test]
fn redirect_graph_rejects_cycles_and_flattens_targets() {
    let first = game_id(1);
    let second = game_id(2);
    let third = game_id(3);
    let mut graph = RedirectGraph::new();

    graph
        .add_redirect(GameRedirect::new(first, second))
        .expect("first redirect");
    graph
        .add_redirect(GameRedirect::new(second, third))
        .expect("second redirect");

    assert_eq!(graph.target(first), Some(third));
    assert_eq!(graph.resolve(first).expect("canonical target"), third);
    assert_eq!(
        graph.add_redirect(GameRedirect::new(third, first)),
        Err(GroupingValidationError::RedirectCycle { game_id: third })
    );
    assert_eq!(
        graph.add_redirect(GameRedirect::new(first, first)),
        Err(GroupingValidationError::SelfRedirect { game_id: first })
    );
}

#[test]
fn active_nonempty_games_have_one_primary_and_unique_members() {
    let game = Game::new(game_id(1), PlatformId::NintendoGb, GameLifecycle::Active, 1);
    let primary = membership(
        game.id(),
        content_id(2),
        MembershipRelationship::PrimaryContent,
    );
    let secondary = membership(
        game.id(),
        content_id(3),
        MembershipRelationship::EquivalentReleaseRepresentation,
    );

    validate_memberships(&game, &[primary.clone(), secondary.clone()]).expect("valid grouping");
    assert_eq!(
        validate_memberships(&game, &[secondary]),
        Err(GroupingValidationError::MissingPrimary { game_id: game.id() })
    );
    assert_eq!(
        validate_memberships(&game, &[primary.clone(), primary.clone()]),
        Err(GroupingValidationError::DuplicateMembership {
            game_content_id: content_id(2),
        })
    );
}

#[test]
fn changed_primary_requires_the_next_primary_as_continuity_anchor() {
    let previous = content_id(2);
    let next = content_id(3);
    let game = game_id(1);
    let next_primary = membership(game, next, MembershipRelationship::PrimaryContent);

    assert_eq!(
        validate_continuity_anchor(Some(previous), std::slice::from_ref(&next_primary), None),
        Err(GroupingValidationError::ContinuityAnchorRequired {
            previous_primary: previous,
        })
    );
    assert_eq!(
        validate_continuity_anchor(
            Some(previous),
            std::slice::from_ref(&next_primary),
            Some(previous),
        ),
        Err(GroupingValidationError::InvalidContinuityAnchor {
            expected: next,
            actual: previous,
        })
    );
    validate_continuity_anchor(Some(previous), &[next_primary], Some(next))
        .expect("explicit next primary anchor");
}

#[test]
fn membership_relationship_vocabulary_is_closed_and_primary_is_explicit() {
    let relationships = [
        MembershipRelationship::PrimaryContent,
        MembershipRelationship::RegionalVariant,
        MembershipRelationship::LanguageVariant,
        MembershipRelationship::RevisionVariant,
        MembershipRelationship::Disc,
        MembershipRelationship::EquivalentReleaseRepresentation,
    ];

    assert_eq!(relationships.len(), 6);
    assert_eq!(relationships[0], MembershipRelationship::PrimaryContent);
    assert_ne!(relationships[4], relationships[5]);
}
