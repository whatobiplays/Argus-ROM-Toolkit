//! Single-threaded SQLite persistence kernel.
//!
//! The executor is deliberately synchronous at the SQLite boundary. Work is
//! serialized through one bounded standard-library channel and one worker-owned
//! connection. This keeps transaction lifetimes and SQLite values on the worker
//! thread while the application-facing API remains callback based.

mod connection;
mod errors;
mod executor;
mod migrations;
mod unit_of_work;

#[cfg(feature = "test-support")]
#[doc(hidden)]
pub use connection::{SqliteConnection, SqliteValue};
pub use errors::{MigrationError, SqliteExecutorError, SqliteOperationError};
pub use executor::{DEFAULT_QUEUE_CAPACITY, SqliteDatabaseExecutor};
pub use migrations::{
    Migration, MigrationKind, MigrationOutcome, MigrationRegistry, MigrationSummary,
};
pub use unit_of_work::SqliteUnitOfWork;
