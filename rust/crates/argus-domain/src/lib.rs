//! Stable Argus domain vocabulary and business rules.

mod appearance;
mod content;
mod jobs;
mod sources;

pub use appearance::{AppearanceSettings, ThemeMode, ThemeModeParseError};
pub use content::{
    AvailabilityState, ContentType, Game, GameContent, GameContentPresence, GameContentSource,
    GameLifecycle, GameMembership, GameRedirect, GroupingBasis, HydrationState,
    IdentificationState, InvalidContentType, InvalidPlatformId, MembershipRelationship, PlatformId,
};
pub use jobs::{
    ArtworkAssetId, ArtworkAssetIdError, GameContentId, GameContentIdError, GameId, GameIdError,
    JobRunId, JobRunIdError, ScanRunId, ScanRunIdError, SourceEntryId, SourceEntryIdError,
};
pub use sources::{LibraryRootId, LibraryRootIdError, LibrarySourceId, LibrarySourceIdError};
