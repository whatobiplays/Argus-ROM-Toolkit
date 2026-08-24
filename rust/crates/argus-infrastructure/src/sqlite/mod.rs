//! Single-threaded SQLite persistence kernel.
//!
//! The executor is deliberately synchronous at the SQLite boundary. Work is
//! serialized through one bounded standard-library channel and one worker-owned
//! connection. This keeps transaction lifetimes and SQLite values on the worker
//! thread while the application-facing API remains callback based.

mod appearance;
mod artwork;
mod connection;
mod errors;
mod executor;
mod jobs;
mod logical;
mod metadata;
mod migrations;
mod source_entries;
mod sources;
mod unit_of_work;

pub use appearance::{SqliteAppearanceSettingsQueries, SqliteAppearanceSettingsRepository};
pub use artwork::SqliteArtworkRepository;
#[cfg(feature = "test-support")]
#[doc(hidden)]
pub use connection::{SqliteConnection, SqliteValue};
pub use errors::{MigrationError, SqliteExecutorError, SqliteOperationError};
pub use executor::{DEFAULT_QUEUE_CAPACITY, SqliteDatabaseExecutor};
pub use jobs::{
    SqliteJobRunRepository, SqliteJobsQueries, SqliteLibraryScanAdmissionContextRepository,
    SqliteLibraryScanTargetRepository, SqliteScanRunRepository, SqliteSourceEntryRepository,
};
pub use logical::SqliteLogicalContentRepository;
pub use metadata::SqliteMetadataRepository;
pub use migrations::{
    Migration, MigrationKind, MigrationOutcome, MigrationRegistry, MigrationSummary,
};
pub use source_entries::SqliteSourceEntryQueries;
pub use sources::{
    SqliteLibraryRootQueries, SqliteLibraryRootRepository, SqliteLibrarySourceRepository,
};
pub use unit_of_work::SqliteUnitOfWork;
