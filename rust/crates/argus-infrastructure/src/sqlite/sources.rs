//! Typed SQLite adapters for Slice 001 library-source/root state.

use argus_application::{
    ApplicationPortError, LibraryRootAvailability, LibraryRootConfiguration, LibraryRootId,
    LibraryRootPage, LibraryRootProjection, LibraryRootQueries, LibraryRootRepository,
    LibrarySourceId, LibrarySourceRepository, NewLibraryRoot, OperationContext, PersistenceError,
};
use rusqlite::OptionalExtension;

use super::appearance::map_executor_error;
use super::connection::SqliteConnection;
use super::errors::{SqliteOperationError, operation_error};
use super::executor::SqliteDatabaseExecutor;
use super::unit_of_work::SqliteUnitOfWork;

/// Independent authoritative library-root query adapter.
#[derive(Clone)]
pub struct SqliteLibraryRootQueries {
    executor: SqliteDatabaseExecutor,
}

impl SqliteLibraryRootQueries {
    /// Creates a query adapter over an existing shared SQLite executor.
    pub const fn new(executor: SqliteDatabaseExecutor) -> Self {
        Self { executor }
    }
}

impl LibraryRootQueries for SqliteLibraryRootQueries {
    fn list(
        &self,
        context: &OperationContext,
        offset: u32,
        page_size: u32,
    ) -> Result<LibraryRootPage, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                let items = read_root_page(connection, offset, page_size)?;
                let total = connection.scalar_i64("SELECT COUNT(*) FROM library_root")?;
                Ok(LibraryRootPage::new(items, offset, page_size, total as u32))
            })
            .map_err(map_executor_error)
    }

    fn get(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootProjection>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                read_root(connection, &root_id.to_string())
            })
            .map_err(map_executor_error)
    }

    fn list_root_configurations(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<LibraryRootConfiguration>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), |connection| {
                let mut statement = connection
                    .connection
                    .prepare(
                        "SELECT library_root_id, root_locator
                         FROM library_root
                         ORDER BY created_at ASC, library_root_id ASC",
                    )
                    .map_err(|error| operation_error(&error))?;
                let rows = statement
                    .query_map([], |row| {
                        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
                    })
                    .map_err(|error| operation_error(&error))?;
                let raw = rows
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|error| operation_error(&error))?;
                raw.into_iter()
                    .map(|(id, locator)| {
                        let root_id = LibraryRootId::try_from(id.as_str())
                            .map_err(|_| corrupt_persistence())?;
                        Ok(LibraryRootConfiguration::new(
                            root_id,
                            argus_application::RootLocator::from_provider(locator),
                        ))
                    })
                    .collect()
            })
            .map_err(map_executor_error)
    }
}

fn read_root_page(
    connection: &mut SqliteConnection<'_>,
    offset: u32,
    page_size: u32,
) -> Result<Vec<LibraryRootProjection>, SqliteOperationError> {
    let mut statement = connection
        .connection
        .prepare(
            "SELECT library_root_id, display_name, safe_location_presentation, availability_status
             FROM library_root
             ORDER BY created_at ASC, library_root_id ASC
             LIMIT ?1 OFFSET ?2",
        )
        .map_err(|error| operation_error(&error))?;
    let rows = statement
        .query_map(
            rusqlite::params![i64::from(page_size), i64::from(offset)],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                ))
            },
        )
        .map_err(|error| operation_error(&error))?;
    let raw = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| operation_error(&error))?;
    raw.into_iter().map(root_projection_from_raw).collect()
}

fn read_root(
    connection: &mut SqliteConnection<'_>,
    root_id: &str,
) -> Result<Option<LibraryRootProjection>, SqliteOperationError> {
    let raw = connection
        .connection
        .query_row(
            "SELECT library_root_id, display_name, safe_location_presentation, availability_status
             FROM library_root
             WHERE library_root_id = ?1",
            [root_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                ))
            },
        )
        .optional()
        .map_err(|error| operation_error(&error))?;
    raw.map(root_projection_from_raw).transpose()
}

fn root_projection_from_raw(
    (id, display, safe_location, availability): (String, String, String, String),
) -> Result<LibraryRootProjection, SqliteOperationError> {
    let root_id = LibraryRootId::try_from(id.as_str()).map_err(|_| corrupt_persistence())?;
    let availability = match availability.as_str() {
        "available" => LibraryRootAvailability::Available,
        "unavailable" => LibraryRootAvailability::Unavailable,
        "unknown" => LibraryRootAvailability::Unknown,
        _ => return Err(corrupt_persistence()),
    };
    Ok(LibraryRootProjection::new(
        root_id,
        display,
        safe_location,
        availability,
        None,
        None,
    ))
}

fn corrupt_persistence() -> SqliteOperationError {
    SqliteOperationError::Application(ApplicationPortError::Persistence(
        PersistenceError::CorruptOrIncompatible,
    ))
}

/// Ephemeral transaction-bound internal library-source repository.
pub struct SqliteLibrarySourceRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteLibrarySourceRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl LibrarySourceRepository for SqliteLibrarySourceRepository<'_, '_> {
    fn ensure_local_filesystem_source(&mut self) -> Result<LibrarySourceId, PersistenceError> {
        self.work.ensure_local_filesystem_source()
    }
}

/// Ephemeral transaction-bound configured-root repository.
pub struct SqliteLibraryRootRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteLibraryRootRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl LibraryRootRepository for SqliteLibraryRootRepository<'_, '_> {
    fn insert(&mut self, root: NewLibraryRoot) -> Result<LibraryRootId, PersistenceError> {
        self.work.insert_library_root(&root)
    }

    fn delete(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        self.work.delete_library_root(root_id)
    }
}
