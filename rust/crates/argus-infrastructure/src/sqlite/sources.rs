//! Typed SQLite adapters for Slice 001 library-source/root state.

use argus_application::{
    ApplicationPortError, LibraryRootActiveScanSummary, LibraryRootAvailability,
    LibraryRootConfiguration, LibraryRootId, LibraryRootLastScanStatus, LibraryRootLastScanSummary,
    LibraryRootPage, LibraryRootProjection, LibraryRootQueries, LibraryRootRepository,
    LibraryRootScanConfiguration, LibrarySourceId, LibrarySourceRepository, NewLibraryRoot,
    OperationContext, PersistenceError,
};
use rusqlite::OptionalExtension;

use super::appearance::map_executor_error;
use super::connection::SqliteConnection;
use super::errors::{SqliteOperationError, operation_error};
use super::executor::SqliteDatabaseExecutor;
use super::unit_of_work::SqliteUnitOfWork;

type RootProjectionRaw = (
    String,
    String,
    String,
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    Option<i64>,
    Option<i64>,
    Option<String>,
    Option<String>,
);

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

    fn get_scan_configuration(
        &self,
        context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                let raw = connection
                    .connection
                    .query_row(
                        "SELECT library_root_id, root_locator, display_name,
                                safe_location_presentation, config_revision
                         FROM library_root WHERE library_root_id = ?1",
                        [root_id.to_string()],
                        |row| {
                            Ok((
                                row.get::<_, String>(0)?,
                                row.get::<_, String>(1)?,
                                row.get::<_, String>(2)?,
                                row.get::<_, String>(3)?,
                                row.get::<_, i64>(4)?,
                            ))
                        },
                    )
                    .optional()
                    .map_err(|error| operation_error(&error))?;
                raw.map(|(id, locator, display, safe, revision)| {
                    let root_id =
                        LibraryRootId::try_from(id.as_str()).map_err(|_| corrupt_persistence())?;
                    Ok(LibraryRootScanConfiguration::new(
                        root_id,
                        argus_application::RootLocator::from_provider(locator),
                        display,
                        safe,
                        revision as u32,
                    ))
                })
                .transpose()
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
            "SELECT library_root_id, display_name, safe_location_presentation, availability_status,
                    last_scan_status, last_scan_scan_run_id, last_scan_job_run_id,
                    last_scan_started_at, last_scan_completed_at,
                    (SELECT scan_run_id FROM scan_run
                      WHERE historical_library_root_id = library_root.library_root_id
                        AND status = 'running' LIMIT 1),
                    (SELECT job_run_id FROM scan_run
                      WHERE historical_library_root_id = library_root.library_root_id
                        AND status = 'running' LIMIT 1)
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
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<i64>>(7)?,
                    row.get::<_, Option<i64>>(8)?,
                    row.get::<_, Option<String>>(9)?,
                    row.get::<_, Option<String>>(10)?,
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
            "SELECT library_root_id, display_name, safe_location_presentation, availability_status,
                    last_scan_status, last_scan_scan_run_id, last_scan_job_run_id,
                    last_scan_started_at, last_scan_completed_at,
                    (SELECT scan_run_id FROM scan_run
                      WHERE historical_library_root_id = library_root.library_root_id
                        AND status = 'running' LIMIT 1),
                    (SELECT job_run_id FROM scan_run
                      WHERE historical_library_root_id = library_root.library_root_id
                        AND status = 'running' LIMIT 1)
             FROM library_root
             WHERE library_root_id = ?1",
            [root_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, Option<String>>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, Option<i64>>(7)?,
                    row.get::<_, Option<i64>>(8)?,
                    row.get::<_, Option<String>>(9)?,
                    row.get::<_, Option<String>>(10)?,
                ))
            },
        )
        .optional()
        .map_err(|error| operation_error(&error))?;
    raw.map(root_projection_from_raw).transpose()
}

fn root_projection_from_raw(
    (
        id,
        display,
        safe_location,
        availability,
        last_scan_status,
        last_scan_scan_run_id,
        last_scan_job_run_id,
        last_scan_started_at,
        last_scan_completed_at,
        active_scan_run_id,
        active_job_run_id,
    ): RootProjectionRaw,
) -> Result<LibraryRootProjection, SqliteOperationError> {
    let root_id = LibraryRootId::try_from(id.as_str()).map_err(|_| corrupt_persistence())?;
    let availability = match availability.as_str() {
        "available" => LibraryRootAvailability::Available,
        "unavailable" => LibraryRootAvailability::Unavailable,
        "unknown" => LibraryRootAvailability::Unknown,
        _ => return Err(corrupt_persistence()),
    };
    let mut projection =
        LibraryRootProjection::new(root_id, display, safe_location, availability, None, None);
    if let (Some(scan_run_id), Some(job_run_id), Some(status), Some(started_at)) = (
        last_scan_scan_run_id,
        last_scan_job_run_id,
        last_scan_status,
        last_scan_started_at,
    ) {
        let status = match status.as_str() {
            "complete" => LibraryRootLastScanStatus::Complete,
            "partial" => LibraryRootLastScanStatus::Partial,
            "unavailable" => LibraryRootLastScanStatus::Unavailable,
            "cancelled" => LibraryRootLastScanStatus::Cancelled,
            "failed" => LibraryRootLastScanStatus::Failed,
            "abandoned" => LibraryRootLastScanStatus::Abandoned,
            _ => return Err(corrupt_persistence()),
        };
        projection = projection.with_last_scan(LibraryRootLastScanSummary::new(
            scan_run_id,
            job_run_id,
            status,
            started_at,
            last_scan_completed_at,
        ));
    }
    if let (Some(scan_run_id), Some(job_run_id)) = (active_scan_run_id, active_job_run_id) {
        projection =
            projection.with_active_scan(LibraryRootActiveScanSummary::new(scan_run_id, job_run_id));
    }
    Ok(projection)
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

    fn exists(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        self.work
            .transaction_mut()?
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM library_root WHERE library_root_id = ?1)",
                [root_id.to_string()],
                |row| row.get(0),
            )
            .map_err(super::jobs::map_persistence_operation_error)
    }

    fn set_availability(
        &mut self,
        root_id: LibraryRootId,
        availability: LibraryRootAvailability,
    ) -> Result<bool, PersistenceError> {
        let changed = self
            .work
            .transaction_mut()?
            .execute(
                "UPDATE library_root SET availability_status = ?1
                 WHERE library_root_id = ?2",
                rusqlite::params![availability.as_str(), root_id.to_string()],
            )
            .map_err(super::jobs::map_persistence_operation_error)?;
        Ok(changed == 1)
    }

    fn set_last_scan(
        &mut self,
        root_id: LibraryRootId,
        summary: Option<LibraryRootLastScanSummary>,
    ) -> Result<bool, PersistenceError> {
        let changed = match summary {
            Some(summary) => self
                .work
                .transaction_mut()?
                .execute(
                    "UPDATE library_root
                     SET last_scan_status = ?1,
                         last_scan_scan_run_id = ?2,
                         last_scan_job_run_id = ?3,
                         last_scan_started_at = ?4,
                         last_scan_completed_at = ?5
                     WHERE library_root_id = ?6",
                    rusqlite::params![
                        summary.status().as_str(),
                        summary.scan_run_id(),
                        summary.job_run_id(),
                        summary.started_at_ms(),
                        summary.completed_at_ms(),
                        root_id.to_string(),
                    ],
                )
                .map_err(super::jobs::map_persistence_operation_error)?,
            None => self
                .work
                .transaction_mut()?
                .execute(
                    "UPDATE library_root
                     SET last_scan_status = NULL,
                         last_scan_scan_run_id = NULL,
                         last_scan_job_run_id = NULL,
                         last_scan_started_at = NULL,
                         last_scan_completed_at = NULL
                     WHERE library_root_id = ?1",
                    [root_id.to_string()],
                )
                .map_err(super::jobs::map_persistence_operation_error)?,
        };
        Ok(changed == 1)
    }
}
