//! Stable Argus domain vocabulary and business rules.

mod appearance;
mod sources;

pub use appearance::{AppearanceSettings, ThemeMode, ThemeModeParseError};
pub use sources::{LibraryRootId, LibraryRootIdError, LibrarySourceId, LibrarySourceIdError};
