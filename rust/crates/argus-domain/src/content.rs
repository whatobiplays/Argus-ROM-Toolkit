//! Stable vocabulary for canonical cartridge content.

use std::fmt;

use crate::jobs::{GameContentId, GameId, ScanRunId, SourceEntryId};

/// Supported native platform identity established by validated cartridge bytes.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum PlatformId {
    /// Nintendo Entertainment System and Famicom cartridge content.
    NintendoNes,
    /// Nintendo Famicom Disk System disk content.
    NintendoFds,
    /// Super Nintendo Entertainment System and Super Famicom cartridge content.
    NintendoSnes,
    /// Nintendo Game Boy monochrome-compatible cartridge content.
    NintendoGb,
    /// Nintendo Game Boy Color cartridge content.
    NintendoGbc,
    /// Nintendo Game Boy Advance cartridge content.
    NintendoGba,
    /// Nintendo 64 cartridge content.
    NintendoN64,
    /// Nintendo DS cartridge content.
    NintendoNds,
    /// Nintendo 3DS key-free NCSD/NCCH cartridge content.
    Nintendo3ds,
    /// Sega Master System cartridge content.
    SegaSms,
    /// Sega Game Gear cartridge content.
    SegaGameGear,
    /// Sega Genesis and Mega Drive cartridge content.
    SegaGenesis,
    /// Sega 32X cartridge content.
    Sega32x,
}

impl PlatformId {
    /// Returns the stable persisted platform identifier.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::NintendoNes => "nintendo.nes",
            Self::NintendoFds => "nintendo.fds",
            Self::NintendoSnes => "nintendo.snes",
            Self::NintendoGb => "nintendo.gb",
            Self::NintendoGbc => "nintendo.gbc",
            Self::NintendoGba => "nintendo.gba",
            Self::NintendoN64 => "nintendo.n64",
            Self::NintendoNds => "nintendo.nds",
            Self::Nintendo3ds => "nintendo.3ds",
            Self::SegaSms => "sega.sms",
            Self::SegaGameGear => "sega.gamegear",
            Self::SegaGenesis => "sega.genesis",
            Self::Sega32x => "sega.32x",
        }
    }
}

impl fmt::Display for PlatformId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl TryFrom<&str> for PlatformId {
    type Error = InvalidPlatformId;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "nintendo.nes" => Ok(Self::NintendoNes),
            "nintendo.fds" => Ok(Self::NintendoFds),
            "nintendo.snes" => Ok(Self::NintendoSnes),
            "nintendo.gb" => Ok(Self::NintendoGb),
            "nintendo.gbc" => Ok(Self::NintendoGbc),
            "nintendo.gba" => Ok(Self::NintendoGba),
            "nintendo.n64" => Ok(Self::NintendoN64),
            "nintendo.nds" => Ok(Self::NintendoNds),
            "nintendo.3ds" => Ok(Self::Nintendo3ds),
            "sega.sms" => Ok(Self::SegaSms),
            "sega.gamegear" => Ok(Self::SegaGameGear),
            "sega.genesis" => Ok(Self::SegaGenesis),
            "sega.32x" => Ok(Self::Sega32x),
            _ => Err(InvalidPlatformId),
        }
    }
}

/// Failure while parsing a platform identifier.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidPlatformId;

impl fmt::Display for InvalidPlatformId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("invalid platform identifier")
    }
}

impl std::error::Error for InvalidPlatformId {}

/// Content kind represented by one canonical identity.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum ContentType {
    /// A complete cartridge image.
    CartridgeImage,
    /// A validated Famicom Disk System disk image.
    MagneticDiskImage,
}

impl ContentType {
    /// Returns the stable persisted content-type identifier.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::CartridgeImage => "CartridgeImage",
            Self::MagneticDiskImage => "MagneticDiskImage",
        }
    }
}

impl fmt::Display for ContentType {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl TryFrom<&str> for ContentType {
    type Error = InvalidContentType;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "CartridgeImage" => Ok(Self::CartridgeImage),
            "MagneticDiskImage" => Ok(Self::MagneticDiskImage),
            _ => Err(InvalidContentType),
        }
    }
}

/// Failure while parsing a content type.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidContentType;

impl fmt::Display for InvalidContentType {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("invalid content type")
    }
}

impl std::error::Error for InvalidContentType {}

/// Availability/presence facts for canonical content.
///
/// This is deliberately separate from [`IdentificationState`]. A content row
/// may be orphaned and require re-identification at the same time.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum GameContentPresence {
    /// At least one current source is available.
    Available,
    /// Some current sources are unavailable while another remains available.
    PartiallyUnavailable,
    /// Current sources exist but none are available at the moment.
    Unavailable,
    /// No authoritative current source remains.
    Orphaned,
}

/// Current identity proof state for canonical content.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum IdentificationState {
    /// A current identity and proving provenance basis are present.
    Identified,
    /// Identity proof was removed and independent re-identification is needed.
    NeedsReidentification,
    /// No identity has ever been established.
    Unidentified,
}

/// Lifecycle state of one logical game aggregate.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum GameLifecycle {
    /// The game has at least one non-orphaned current member.
    Active,
    /// All current members are orphaned, but the durable game is retained.
    InactiveOrphan,
    /// The game has been merged into another canonical game identity.
    Redirected,
}

/// Membership role within one game aggregate.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum MembershipRelationship {
    /// The deterministic continuity anchor for the game.
    Primary,
    /// An additional exact-content member.
    Secondary,
}

/// Evidence basis for one current membership.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum GroupingBasis {
    /// Exact canonical content identity convergence.
    ExactContentIdentity,
    /// Initial one-content provisional grouping.
    Provisional,
}

/// Provider-independent hydration state used by the local library projection.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum HydrationState {
    /// A match-capable provider has supplied an accepted mapping.
    Hydrated,
    /// No match-capable provider has completed evaluation yet.
    PartiallyHydrated,
    /// A current-revision matching attempt ended without an accepted mapping.
    Unmatched,
    /// A provider-backed refresh is in progress.
    Refreshing,
}

/// Availability projection derived from source and content presence facts.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum AvailabilityState {
    /// All current sources are available.
    Available,
    /// At least one, but not all, current sources are available.
    PartiallyUnavailable,
    /// Current sources exist but none are available.
    Unavailable,
    /// The aggregate has no current non-orphaned content.
    InactiveOrphan,
}

/// Durable logical content independent from any one physical source copy.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameContent {
    id: GameContentId,
    platform_id: PlatformId,
    content_type: ContentType,
    presence: GameContentPresence,
    identification: IdentificationState,
}

impl GameContent {
    /// Creates one content aggregate with independent presence and identity
    /// states.
    pub const fn new(
        id: GameContentId,
        platform_id: PlatformId,
        content_type: ContentType,
        presence: GameContentPresence,
        identification: IdentificationState,
    ) -> Self {
        Self {
            id,
            platform_id,
            content_type,
            presence,
            identification,
        }
    }

    /// Returns the logical content identity.
    pub const fn id(&self) -> GameContentId {
        self.id
    }

    /// Returns the authoritative platform.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns the represented content type.
    pub const fn content_type(&self) -> ContentType {
        self.content_type
    }

    /// Returns the independent source-presence state.
    pub const fn presence(&self) -> GameContentPresence {
        self.presence
    }

    /// Returns the independent identity-proof state.
    pub const fn identification(&self) -> IdentificationState {
        self.identification
    }
}

/// One physical/source observation associated with a derived logical unit.
///
/// `association_key` is intentionally part of the relationship identity. A
/// future container or multi-file transformation may associate one source
/// observation with more than one derived content unit without imposing a
/// global one-source/one-content uniqueness rule.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameContentSource {
    game_content_id: GameContentId,
    source_entry_id: SourceEntryId,
    association_key: String,
    current: bool,
    source_fingerprint: Option<String>,
    last_observed_scan_id: ScanRunId,
}

impl GameContentSource {
    /// Creates one content/source provenance association.
    pub fn new(
        game_content_id: GameContentId,
        source_entry_id: SourceEntryId,
        association_key: impl Into<String>,
        current: bool,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self {
            game_content_id,
            source_entry_id,
            association_key: association_key.into(),
            current,
            source_fingerprint,
            last_observed_scan_id,
        }
    }

    /// Returns the logical content unit.
    pub const fn game_content_id(&self) -> GameContentId {
        self.game_content_id
    }

    /// Returns the physical source observation.
    pub const fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the derived-unit association discriminator.
    pub fn association_key(&self) -> &str {
        &self.association_key
    }

    /// Returns whether this association is current provenance.
    pub const fn is_current(&self) -> bool {
        self.current
    }

    /// Returns the bounded source-version fingerprint.
    pub fn source_fingerprint(&self) -> Option<&str> {
        self.source_fingerprint.as_deref()
    }

    /// Returns the scan observation that produced this association.
    pub const fn last_observed_scan_id(&self) -> ScanRunId {
        self.last_observed_scan_id
    }
}

/// Durable logical game aggregate.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Game {
    id: GameId,
    platform_id: PlatformId,
    lifecycle: GameLifecycle,
    grouping_revision: u32,
}

impl Game {
    /// Creates one game aggregate at a known grouping revision.
    pub const fn new(
        id: GameId,
        platform_id: PlatformId,
        lifecycle: GameLifecycle,
        grouping_revision: u32,
    ) -> Self {
        Self {
            id,
            platform_id,
            lifecycle,
            grouping_revision,
        }
    }

    /// Returns the durable game identity.
    pub const fn id(&self) -> GameId {
        self.id
    }

    /// Returns the game's authoritative platform.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns the durable lifecycle.
    pub const fn lifecycle(&self) -> GameLifecycle {
        self.lifecycle
    }

    /// Returns the grouping revision.
    pub const fn grouping_revision(&self) -> u32 {
        self.grouping_revision
    }
}

/// One current membership of logical content in a game.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameMembership {
    game_id: GameId,
    game_content_id: GameContentId,
    relationship: MembershipRelationship,
    grouping_basis: GroupingBasis,
    grouping_revision: u32,
}

impl GameMembership {
    /// Creates one membership. Primary membership is the continuity anchor.
    pub const fn new(
        game_id: GameId,
        game_content_id: GameContentId,
        relationship: MembershipRelationship,
        grouping_basis: GroupingBasis,
        grouping_revision: u32,
    ) -> Self {
        Self {
            game_id,
            game_content_id,
            relationship,
            grouping_basis,
            grouping_revision,
        }
    }

    /// Returns the owning game.
    pub const fn game_id(&self) -> GameId {
        self.game_id
    }

    /// Returns the member content.
    pub const fn game_content_id(&self) -> GameContentId {
        self.game_content_id
    }

    /// Returns the membership role.
    pub const fn relationship(&self) -> MembershipRelationship {
        self.relationship
    }

    /// Returns the grouping evidence basis.
    pub const fn grouping_basis(&self) -> GroupingBasis {
        self.grouping_basis
    }

    /// Returns the grouping revision.
    pub const fn grouping_revision(&self) -> u32 {
        self.grouping_revision
    }
}

/// One redirect from a historical game identity to its canonical game.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct GameRedirect {
    game_id: GameId,
    canonical_game_id: GameId,
}

impl GameRedirect {
    /// Creates a redirect edge. Self-redirect rejection belongs to the
    /// application transaction validator.
    pub const fn new(game_id: GameId, canonical_game_id: GameId) -> Self {
        Self {
            game_id,
            canonical_game_id,
        }
    }

    /// Returns the redirected identity.
    pub const fn game_id(self) -> GameId {
        self.game_id
    }

    /// Returns the canonical target.
    pub const fn canonical_game_id(self) -> GameId {
        self.canonical_game_id
    }
}
