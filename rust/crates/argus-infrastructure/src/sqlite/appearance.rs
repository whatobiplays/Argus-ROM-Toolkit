//! Typed SQLite adapters for the Phase 000 appearance aggregate.

use argus_application::{
    AppearanceSettings, AppearanceSettingsQueries, AppearanceSettingsRepository, OperationContext,
    PersistedSettingsReason, PersistenceError, ThemeMode,
};
use argus_domain::ThemeModeParseError;
use rusqlite::{OptionalExtension, types::Value};

use super::connection::SqliteConnection;
use super::errors::{SqliteExecutorError, SqliteOperationError, operation_error};
use super::executor::SqliteDatabaseExecutor;
use super::unit_of_work::SqliteUnitOfWork;

/// Independent authoritative appearance-settings query adapter.
#[derive(Clone)]
pub struct SqliteAppearanceSettingsQueries {
    executor: SqliteDatabaseExecutor,
}

impl SqliteAppearanceSettingsQueries {
    /// Creates a query adapter over an existing shared SQLite executor handle.
    pub const fn new(executor: SqliteDatabaseExecutor) -> Self {
        Self { executor }
    }
}

impl AppearanceSettingsQueries for SqliteAppearanceSettingsQueries {
    fn get(&self, context: &OperationContext) -> Result<AppearanceSettings, PersistenceError> {
        self.executor
            .with_connection(context.clone(), read_appearance)
            .map_err(map_executor_error)
    }
}

/// Ephemeral transaction-bound appearance-settings repository adapter.
pub struct SqliteAppearanceSettingsRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteAppearanceSettingsRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl AppearanceSettingsRepository for SqliteAppearanceSettingsRepository<'_, '_> {
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
        self.work
            .appearance_theme_mode()
            .and_then(map_theme_mode_value)
    }

    fn save(&mut self, settings: &AppearanceSettings) -> Result<(), PersistenceError> {
        self.work
            .save_appearance_theme_mode(settings.theme_mode.as_str())
    }
}

fn read_appearance(
    connection: &mut SqliteConnection<'_>,
) -> Result<AppearanceSettings, SqliteOperationError> {
    let value = connection
        .connection
        .query_row(
            "SELECT theme_mode FROM appearance_settings WHERE singleton_key = 1",
            [],
            |row| row.get::<_, Value>(0),
        )
        .optional()
        .map_err(|error| operation_error(&error))?;
    map_theme_mode_value(value).map_err(|error| SqliteOperationError::Application(error.into()))
}

fn map_theme_mode_value(value: Option<Value>) -> Result<AppearanceSettings, PersistenceError> {
    let value = value.ok_or(PersistenceError::PersistedSettingsInvalid(
        PersistedSettingsReason::Missing,
    ))?;
    let Value::Text(value) = value else {
        return Err(PersistenceError::PersistedSettingsInvalid(
            PersistedSettingsReason::MappingFailed,
        ));
    };
    let theme_mode = ThemeMode::parse(&value).map_err(|_: ThemeModeParseError| {
        PersistenceError::PersistedSettingsInvalid(PersistedSettingsReason::InvalidValue)
    })?;
    Ok(AppearanceSettings::new(theme_mode))
}

pub(crate) fn map_executor_error(error: SqliteExecutorError) -> PersistenceError {
    match error {
        SqliteExecutorError::ApplicationCallback(error) => match error {
            argus_application::ApplicationPortError::Persistence(error) => error,
            argus_application::ApplicationPortError::EventRecording => PersistenceError::Internal,
        },
        SqliteExecutorError::DatabaseLocked => PersistenceError::DatabaseLocked,
        SqliteExecutorError::DatabaseOpenFailed
        | SqliteExecutorError::Shutdown
        | SqliteExecutorError::Poisoned
        | SqliteExecutorError::Disconnected => PersistenceError::Unavailable,
        SqliteExecutorError::MigrationFailed { .. } => PersistenceError::MigrationFailed,
        SqliteExecutorError::IncompatibleSchema => PersistenceError::CorruptOrIncompatible,
        SqliteExecutorError::ReentrantSubmission | SqliteExecutorError::Internal => {
            PersistenceError::Internal
        }
    }
}
