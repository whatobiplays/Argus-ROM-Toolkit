//! Stable infrastructure failure categories. Technical SQLite details stay
//! private and are used only for local diagnostics and classification.

use std::fmt;

use argus_application::ApplicationPortError;

/// A sanitized failure from a SQLite operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SqliteOperationError {
    /// The database rejected a statement because the schema/data is invalid.
    Constraint,
    /// The database is temporarily locked or busy.
    Locked,
    /// The database could not complete the requested operation.
    Failed,
    /// A focused infrastructure adapter returned an application-port error.
    Application(ApplicationPortError),
}

/// Failure categories for executor lifecycle and startup work.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SqliteExecutorError {
    /// The database file could not be opened.
    DatabaseOpenFailed,
    /// The database is locked during startup or operation.
    DatabaseLocked,
    /// A migration failed and the pending batch was rolled back.
    MigrationFailed { version: Option<u32> },
    /// Existing schema/history is not compatible with the embedded registry.
    IncompatibleSchema,
    /// A callback panicked; this executor generation is permanently poisoned.
    Poisoned,
    /// The worker is shutting down or has already shut down.
    Shutdown,
    /// A callback attempted to submit work from the database worker.
    ReentrantSubmission,
    /// The worker unexpectedly disconnected.
    Disconnected,
    /// An unclassified internal failure occurred.
    Internal,
    /// The application callback rejected its transactional operation.
    ApplicationCallback(ApplicationPortError),
}

/// Validation failure while constructing or applying migrations.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MigrationError {
    /// Embedded versions are not a strict contiguous sequence.
    InvalidOrdering,
    /// A version or name is duplicated.
    Duplicate,
    /// Migration bytes are not valid UTF-8 SQL.
    InvalidSql,
    /// The history table schema is not the required schema.
    MalformedHistory,
    /// History contains an applied version that is not embedded.
    UnknownAppliedVersion(u32),
    /// An embedded historical migration is absent from the database history.
    MissingHistoricalVersion(u32),
    /// A recorded migration name differs from its embedded definition.
    NameMismatch(u32),
    /// A recorded migration kind differs from its embedded definition.
    KindMismatch(u32),
    /// A recorded migration checksum differs from its embedded definition.
    ChecksumMismatch(u32),
    /// SQLite rejected migration SQL.
    SqlExecution,
}

impl fmt::Display for SqliteExecutorError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DatabaseOpenFailed => formatter.write_str("database open failed"),
            Self::DatabaseLocked => formatter.write_str("database locked"),
            Self::MigrationFailed { .. } => formatter.write_str("migration failed"),
            Self::IncompatibleSchema => formatter.write_str("incompatible schema"),
            Self::Poisoned => formatter.write_str("database executor poisoned"),
            Self::Shutdown => formatter.write_str("database executor shut down"),
            Self::ReentrantSubmission => formatter.write_str("re-entrant database submission"),
            Self::Disconnected => formatter.write_str("database worker disconnected"),
            Self::Internal => formatter.write_str("internal database executor failure"),
            Self::ApplicationCallback(_) => formatter.write_str("application callback failed"),
        }
    }
}

impl std::error::Error for SqliteExecutorError {}

impl fmt::Display for SqliteOperationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Constraint => "database constraint violation",
            Self::Locked => "database locked",
            Self::Failed => "database operation failed",
            Self::Application(_) => "application persistence operation failed",
        })
    }
}

impl std::error::Error for SqliteOperationError {}

impl fmt::Display for MigrationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidOrdering => formatter.write_str("invalid migration ordering"),
            Self::Duplicate => formatter.write_str("duplicate migration definition"),
            Self::InvalidSql => formatter.write_str("invalid migration SQL"),
            Self::MalformedHistory => formatter.write_str("malformed migration history"),
            Self::UnknownAppliedVersion(version) => {
                write!(formatter, "unknown applied migration version {version}")
            }
            Self::MissingHistoricalVersion(version) => {
                write!(formatter, "missing historical migration version {version}")
            }
            Self::NameMismatch(version) => {
                write!(formatter, "migration name mismatch for version {version}")
            }
            Self::KindMismatch(version) => {
                write!(formatter, "migration kind mismatch for version {version}")
            }
            Self::ChecksumMismatch(version) => write!(
                formatter,
                "migration checksum mismatch for version {version}"
            ),
            Self::SqlExecution => formatter.write_str("migration SQL execution failed"),
        }
    }
}

impl std::error::Error for MigrationError {}

pub(crate) fn operation_error(error: &rusqlite::Error) -> SqliteOperationError {
    match error {
        rusqlite::Error::SqliteFailure(code, _) => match code.code {
            rusqlite::ErrorCode::DatabaseBusy | rusqlite::ErrorCode::DatabaseLocked => {
                SqliteOperationError::Locked
            }
            rusqlite::ErrorCode::ConstraintViolation => SqliteOperationError::Constraint,
            _ => SqliteOperationError::Failed,
        },
        _ => SqliteOperationError::Failed,
    }
}
