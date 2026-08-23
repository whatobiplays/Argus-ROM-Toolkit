//! Application-transaction validators for durable game grouping.
//!
//! SQLite constraints protect the local shape of grouping rows, but they
//! cannot prove graph-wide properties such as redirect acyclicity or the
//! continuity of a split/merge operation. These validators are deliberately
//! technology-neutral so a Unit of Work can validate the complete proposed
//! state before committing it.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

use argus_domain::{
    Game, GameContentId, GameId, GameLifecycle, GameMembership, GameRedirect,
    MembershipRelationship,
};

/// Failure while validating one proposed grouping transaction.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum GroupingValidationError {
    /// A game was redirected to itself.
    SelfRedirect { game_id: GameId },
    /// Adding the edge would make the redirect graph cyclic.
    RedirectCycle { game_id: GameId },
    /// A membership belongs to a different game aggregate.
    MembershipBelongsToDifferentGame { expected: GameId, actual: GameId },
    /// One content unit appears more than once in a game's current members.
    DuplicateMembership { game_content_id: GameContentId },
    /// Membership and game grouping revisions disagree.
    GroupingRevisionMismatch { expected: u32, actual: u32 },
    /// A non-empty active game has no primary content.
    MissingPrimary { game_id: GameId },
    /// A game has more than one primary content member.
    MultiplePrimary { game_id: GameId },
    /// A changed or removed primary requires an explicit continuity anchor.
    ContinuityAnchorRequired { previous_primary: GameContentId },
    /// The supplied continuity anchor is not the next primary member.
    InvalidContinuityAnchor {
        expected: GameContentId,
        actual: GameContentId,
    },
}

impl fmt::Display for GroupingValidationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::SelfRedirect { game_id } => {
                write!(formatter, "game {game_id} redirects to itself")
            }
            Self::RedirectCycle { game_id } => {
                write!(formatter, "redirect graph cycles at game {game_id}")
            }
            Self::MembershipBelongsToDifferentGame { expected, actual } => write!(
                formatter,
                "membership belongs to game {actual}, expected {expected}"
            ),
            Self::DuplicateMembership { game_content_id } => {
                write!(
                    formatter,
                    "content {game_content_id} has duplicate membership"
                )
            }
            Self::GroupingRevisionMismatch { expected, actual } => write!(
                formatter,
                "membership grouping revision {actual} does not match game revision {expected}"
            ),
            Self::MissingPrimary { game_id } => {
                write!(formatter, "active game {game_id} has no primary content")
            }
            Self::MultiplePrimary { game_id } => {
                write!(
                    formatter,
                    "game {game_id} has multiple primary content members"
                )
            }
            Self::ContinuityAnchorRequired { previous_primary } => write!(
                formatter,
                "primary content {previous_primary} requires an explicit continuity anchor"
            ),
            Self::InvalidContinuityAnchor { expected, actual } => write!(
                formatter,
                "continuity anchor {actual} does not identify next primary {expected}"
            ),
        }
    }
}

impl std::error::Error for GroupingValidationError {}

/// In-memory redirect graph used to validate and flatten one transaction.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct RedirectGraph {
    targets: BTreeMap<GameId, GameId>,
}

impl RedirectGraph {
    /// Creates an empty redirect graph.
    pub fn new() -> Self {
        Self::default()
    }

    /// Loads existing redirects and validates their graph-wide invariants.
    pub fn from_redirects(redirects: &[GameRedirect]) -> Result<Self, GroupingValidationError> {
        let mut graph = Self::new();
        for redirect in redirects {
            graph.add_redirect(*redirect)?;
        }
        Ok(graph)
    }

    /// Adds a redirect and eagerly flattens every affected predecessor.
    pub fn add_redirect(&mut self, redirect: GameRedirect) -> Result<(), GroupingValidationError> {
        let source = redirect.game_id();
        let target = redirect.canonical_game_id();
        if source == target {
            return Err(GroupingValidationError::SelfRedirect { game_id: source });
        }

        let canonical_target = self.resolve(target)?;
        if canonical_target == source {
            return Err(GroupingValidationError::RedirectCycle { game_id: source });
        }
        self.targets.insert(source, canonical_target);

        // Re-resolve every predecessor after the new edge is installed. This
        // makes stored redirects point directly at the current canonical game
        // rather than leaving a chain for readers to traverse.
        let predecessors: Vec<GameId> = self.targets.keys().copied().collect();
        for predecessor in predecessors {
            if predecessor == canonical_target {
                continue;
            }
            let canonical = self.resolve(predecessor)?;
            self.targets.insert(predecessor, canonical);
        }
        Ok(())
    }

    /// Resolves one game to its canonical non-redirected identity.
    pub fn resolve(&self, game_id: GameId) -> Result<GameId, GroupingValidationError> {
        let mut current = game_id;
        let mut visited = BTreeSet::new();
        while let Some(target) = self.targets.get(&current).copied() {
            if !visited.insert(current) {
                return Err(GroupingValidationError::RedirectCycle { game_id: current });
            }
            current = target;
        }
        Ok(current)
    }

    /// Returns the flattened redirect target, when this game is redirected.
    pub fn target(&self, game_id: GameId) -> Option<GameId> {
        self.targets.get(&game_id).copied()
    }

    /// Returns the flattened redirect edges in deterministic order.
    pub fn redirects(&self) -> Vec<GameRedirect> {
        self.targets
            .iter()
            .map(|(game_id, canonical_game_id)| GameRedirect::new(*game_id, *canonical_game_id))
            .collect()
    }
}

/// Validates all current memberships proposed for one game aggregate.
pub fn validate_memberships(
    game: &Game,
    memberships: &[GameMembership],
) -> Result<(), GroupingValidationError> {
    let mut content_ids = BTreeSet::new();
    let mut primary_count = 0_u8;

    for membership in memberships {
        if membership.game_id() != game.id() {
            return Err(GroupingValidationError::MembershipBelongsToDifferentGame {
                expected: game.id(),
                actual: membership.game_id(),
            });
        }
        if membership.grouping_revision() != game.grouping_revision() {
            return Err(GroupingValidationError::GroupingRevisionMismatch {
                expected: game.grouping_revision(),
                actual: membership.grouping_revision(),
            });
        }
        if !content_ids.insert(membership.game_content_id()) {
            return Err(GroupingValidationError::DuplicateMembership {
                game_content_id: membership.game_content_id(),
            });
        }
        if membership.relationship() == MembershipRelationship::Primary {
            primary_count += 1;
        }
    }

    if primary_count > 1 {
        return Err(GroupingValidationError::MultiplePrimary { game_id: game.id() });
    }
    if game.lifecycle() == GameLifecycle::Active && !memberships.is_empty() && primary_count == 0 {
        return Err(GroupingValidationError::MissingPrimary { game_id: game.id() });
    }
    Ok(())
}

/// Validates the continuity anchor for a split or merge transition.
///
/// If the previous primary remains primary, continuity is implicit. If the
/// primary changes or disappears, the caller must explicitly name the next
/// primary as the continuity anchor. This keeps grouping history auditable
/// without pretending that a database uniqueness constraint can prove intent.
pub fn validate_continuity_anchor(
    previous_primary: Option<GameContentId>,
    next_memberships: &[GameMembership],
    continuity_anchor: Option<GameContentId>,
) -> Result<(), GroupingValidationError> {
    let next_primary = next_memberships
        .iter()
        .filter(|membership| membership.relationship() == MembershipRelationship::Primary)
        .map(GameMembership::game_content_id)
        .next();

    if let Some(anchor) = continuity_anchor
        && Some(anchor) != next_primary
    {
        return Err(GroupingValidationError::InvalidContinuityAnchor {
            expected: next_primary.unwrap_or(anchor),
            actual: anchor,
        });
    }

    let Some(previous_primary) = previous_primary else {
        return Ok(());
    };
    if Some(previous_primary) == next_primary {
        return Ok(());
    }

    match (next_primary, continuity_anchor) {
        (Some(_), Some(_)) => Ok(()),
        _ => Err(GroupingValidationError::ContinuityAnchorRequired { previous_primary }),
    }
}
