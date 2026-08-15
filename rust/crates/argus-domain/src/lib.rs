//! Stable Argus domain vocabulary and business rules.

mod appearance;
mod jobs;
mod sources;

pub use appearance::{AppearanceSettings, ThemeMode, ThemeModeParseError};
pub use jobs::{
    JobRunId, JobRunIdError, ScanRunId, ScanRunIdError, SourceEntryId, SourceEntryIdError,
};
pub use sources::{LibraryRootId, LibraryRootIdError, LibrarySourceId, LibrarySourceIdError};
