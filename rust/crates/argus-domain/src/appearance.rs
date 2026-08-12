//! Pure appearance settings vocabulary shared by application capabilities.

use std::fmt;

/// The supported application theme modes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ThemeMode {
    /// Follow the operating system appearance preference.
    System,
    /// Use the light application palette.
    Light,
    /// Use the dark application palette.
    Dark,
}

impl ThemeMode {
    /// Parses one canonical persisted/application representation.
    pub fn parse(value: &str) -> Result<Self, ThemeModeParseError> {
        match value {
            "system" => Ok(Self::System),
            "light" => Ok(Self::Light),
            "dark" => Ok(Self::Dark),
            _ => Err(ThemeModeParseError),
        }
    }

    /// Returns the canonical representation used by persistence adapters.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }
}

/// Failure to parse a theme mode outside the domain boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ThemeModeParseError;

impl fmt::Display for ThemeModeParseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("unsupported theme mode")
    }
}

impl std::error::Error for ThemeModeParseError {}

/// The complete Phase 000 appearance settings aggregate.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AppearanceSettings {
    /// The selected application theme mode.
    pub theme_mode: ThemeMode,
}

impl AppearanceSettings {
    /// Creates an aggregate containing the supplied valid theme mode.
    pub const fn new(theme_mode: ThemeMode) -> Self {
        Self { theme_mode }
    }
}
