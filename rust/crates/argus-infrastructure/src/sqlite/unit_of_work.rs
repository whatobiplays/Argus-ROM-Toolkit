//! Transaction-scoped SQLite Unit of Work implementation.

use rusqlite::{OptionalExtension, Transaction, types::Value};

use argus_application::{
    ApplicationPortError, NewLibraryRoot, OperationContext, PersistenceError, UnitOfWork,
};

use super::appearance::SqliteAppearanceSettingsRepository;
use super::connection::SqliteValue;
use super::errors::{SqliteOperationError, operation_error};
use super::jobs::{
    SqliteJobRunRepository, SqliteLibraryScanTargetRepository, SqliteScanRunRepository,
    SqliteSourceEntryRepository,
};
use super::sources::{SqliteLibraryRootRepository, SqliteLibrarySourceRepository};

/// One top-level transaction that cannot be reused after terminal completion.
pub struct SqliteUnitOfWork<'connection> {
    transaction: Option<Transaction<'connection>>,
    context: OperationContext,
}

#[allow(dead_code)]
impl<'connection> SqliteUnitOfWork<'connection> {
    pub(crate) fn new(transaction: Transaction<'connection>, context: OperationContext) -> Self {
        Self {
            transaction: Some(transaction),
            context,
        }
    }

    /// Returns the operation context carried into this transaction scope.
    pub fn operation_context(&self) -> &OperationContext {
        &self.context
    }

    /// Returns the active transaction for infrastructure-owned repository
    /// adapters. The transaction is never exposed outside the crate.
    pub(crate) fn transaction_mut(
        &mut self,
    ) -> Result<&mut Transaction<'connection>, PersistenceError> {
        self.transaction.as_mut().ok_or(PersistenceError::Conflict)
    }

    /// Executes a statement inside this Unit of Work.
    pub(crate) fn execute(&mut self, sql: &str) -> Result<usize, ApplicationPortError> {
        self.transaction
            .as_mut()
            .ok_or(ApplicationPortError::Persistence(
                PersistenceError::Conflict,
            ))?
            .execute(sql, [])
            .map_err(map_operation_error)
    }

    /// Executes a statement with typed bound values inside this Unit of Work.
    pub(crate) fn execute_with_values(
        &mut self,
        sql: &str,
        values: &[SqliteValue],
    ) -> Result<usize, ApplicationPortError> {
        let refs: Vec<&dyn rusqlite::ToSql> = values
            .iter()
            .map(|value| value as &dyn rusqlite::ToSql)
            .collect();
        self.transaction
            .as_mut()
            .ok_or(ApplicationPortError::Persistence(
                PersistenceError::Conflict,
            ))?
            .execute(sql, refs.as_slice())
            .map_err(map_operation_error)
    }

    /// Executes a SQL batch inside this Unit of Work.
    pub(crate) fn execute_batch(&mut self, sql: &str) -> Result<(), ApplicationPortError> {
        self.transaction
            .as_mut()
            .ok_or(ApplicationPortError::Persistence(
                PersistenceError::Conflict,
            ))?
            .execute_batch(sql)
            .map_err(map_operation_error)
    }

    /// Reads an integer scalar inside this Unit of Work.
    pub(crate) fn scalar_i64(&mut self, sql: &str) -> Result<i64, ApplicationPortError> {
        self.transaction
            .as_mut()
            .ok_or(ApplicationPortError::Persistence(
                PersistenceError::Conflict,
            ))?
            .query_row(sql, [], |row| row.get(0))
            .map_err(map_operation_error)
    }

    /// Reads a text scalar inside this Unit of Work.
    pub(crate) fn scalar_text(&mut self, sql: &str) -> Result<String, ApplicationPortError> {
        self.transaction
            .as_mut()
            .ok_or(ApplicationPortError::Persistence(
                PersistenceError::Conflict,
            ))?
            .query_row(sql, [], |row| row.get(0))
            .map_err(map_operation_error)
    }

    /// Reads the required appearance singleton value inside this transaction.
    pub(crate) fn appearance_theme_mode(&mut self) -> Result<Option<Value>, PersistenceError> {
        self.transaction
            .as_mut()
            .ok_or(PersistenceError::Conflict)?
            .query_row(
                "SELECT theme_mode FROM appearance_settings WHERE singleton_key = 1",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_operation_error)
    }

    /// Replaces the persisted appearance theme inside this transaction.
    pub(crate) fn save_appearance_theme_mode(
        &mut self,
        theme_mode: &str,
    ) -> Result<(), PersistenceError> {
        let changed = self
            .transaction
            .as_mut()
            .ok_or(PersistenceError::Conflict)?
            .execute(
                "UPDATE appearance_settings SET theme_mode = ?1, updated_at = CURRENT_TIMESTAMP WHERE singleton_key = 1",
                [theme_mode],
            )
            .map_err(map_persistence_operation_error)?;
        match changed {
            0 => Err(PersistenceError::PersistedSettingsInvalid(
                argus_application::PersistedSettingsReason::Missing,
            )),
            1 => Ok(()),
            _ => Err(PersistenceError::CorruptOrIncompatible),
        }
    }

    /// Restores the canonical System appearance row with an atomic upsert.
    pub fn reset_appearance_theme_mode(&mut self) -> Result<(), PersistenceError> {
        self.transaction
            .as_mut()
            .ok_or(PersistenceError::Conflict)?
            .execute(
                "INSERT INTO appearance_settings (singleton_key, theme_mode, schema_revision, updated_at)
                 VALUES (1, 'system', 1, CURRENT_TIMESTAMP)
                 ON CONFLICT(singleton_key) DO UPDATE SET
                   theme_mode = excluded.theme_mode,
                   schema_revision = excluded.schema_revision,
                   updated_at = CURRENT_TIMESTAMP",
                [],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(())
    }

    /// Returns the single internal LocalFilesystem source identity, creating
    /// it lazily on first use.
    pub(crate) fn ensure_local_filesystem_source(
        &mut self,
    ) -> Result<argus_application::LibrarySourceId, PersistenceError> {
        let existing: Option<String> = self
            .transaction
            .as_mut()
            .ok_or(PersistenceError::Conflict)?
            .query_row(
                "SELECT library_source_id FROM library_source
                 WHERE source_provider_type = 'local_filesystem'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        if let Some(value) = existing {
            return parse_source_id(value);
        }
        let created: String = self
            .transaction
            .as_mut()
            .ok_or(PersistenceError::Conflict)?
            .query_row(
                "INSERT INTO library_source
                    (library_source_id, source_provider_type, display_name, provider_config,
                     config_revision, created_at, updated_at)
                 VALUES
                    (lower(hex(randomblob(16))), 'local_filesystem', 'Local Filesystem',
                     '{\"schema_version\":1,\"config\":{}}', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                 RETURNING library_source_id",
                [],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;
        parse_source_id(created)
    }

    /// Inserts one configured root and returns its stable identity.
    pub(crate) fn insert_library_root(
        &mut self,
        root: &NewLibraryRoot,
    ) -> Result<argus_application::LibraryRootId, PersistenceError> {
        let created: String = self
            .transaction
            .as_mut()
            .ok_or(PersistenceError::Conflict)?
            .query_row(
                "INSERT INTO library_root
                    (library_root_id, library_source_id, root_locator, display_name,
                     safe_location_presentation, availability_status, config_revision,
                     created_at, updated_at)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, ?6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                 RETURNING library_root_id",
                rusqlite::params![
                    root.library_source_id().to_string(),
                    root.locator().as_provider_value(),
                    root.display_name(),
                    root.safe_location_presentation(),
                    root.availability().as_str(),
                    i64::from(root.config_revision()),
                ],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;
        parse_root_id(created)
    }

    /// Deletes one configured root and reports whether a row was removed.
    pub(crate) fn delete_library_root(
        &mut self,
        root_id: argus_application::LibraryRootId,
    ) -> Result<bool, PersistenceError> {
        let changed = self
            .transaction
            .as_mut()
            .ok_or(PersistenceError::Conflict)?
            .execute(
                "DELETE FROM library_root WHERE library_root_id = ?1",
                [root_id.to_string()],
            )
            .map_err(map_persistence_operation_error)?;
        match changed {
            0 => Ok(false),
            1 => Ok(true),
            _ => Err(PersistenceError::CorruptOrIncompatible),
        }
    }

    /// Commits the transaction and consumes this scope.
    pub fn commit(mut self) -> Result<(), ApplicationPortError> {
        let transaction = self
            .transaction
            .take()
            .ok_or(ApplicationPortError::Persistence(
                PersistenceError::Conflict,
            ))?;
        transaction.commit().map_err(map_operation_error)
    }

    /// Rolls back the transaction and consumes this scope.
    pub fn rollback(mut self) -> Result<(), ApplicationPortError> {
        let transaction = self
            .transaction
            .take()
            .ok_or(ApplicationPortError::Persistence(
                PersistenceError::Conflict,
            ))?;
        transaction.rollback().map_err(map_operation_error)
    }
}

impl<'connection> UnitOfWork for SqliteUnitOfWork<'connection> {
    type AppearanceSettingsRepository<'scope>
        = SqliteAppearanceSettingsRepository<'scope, 'connection>
    where
        Self: 'scope;
    type LibrarySourceRepository<'scope>
        = SqliteLibrarySourceRepository<'scope, 'connection>
    where
        Self: 'scope;
    type LibraryRootRepository<'scope>
        = SqliteLibraryRootRepository<'scope, 'connection>
    where
        Self: 'scope;
    type JobRunRepository<'scope>
        = SqliteJobRunRepository<'scope, 'connection>
    where
        Self: 'scope;
    type ScanRunRepository<'scope>
        = SqliteScanRunRepository<'scope, 'connection>
    where
        Self: 'scope;
    type SourceEntryRepository<'scope>
        = SqliteSourceEntryRepository<'scope, 'connection>
    where
        Self: 'scope;
    type LibraryScanTargetRepository<'scope>
        = SqliteLibraryScanTargetRepository<'scope, 'connection>
    where
        Self: 'scope;

    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
        SqliteAppearanceSettingsRepository::new(self)
    }

    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
        SqliteLibrarySourceRepository::new(self)
    }

    fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
        SqliteLibraryRootRepository::new(self)
    }

    fn job_runs(&mut self) -> Self::JobRunRepository<'_> {
        SqliteJobRunRepository::new(self)
    }

    fn scan_runs(&mut self) -> Self::ScanRunRepository<'_> {
        SqliteScanRunRepository::new(self)
    }

    fn source_entries(&mut self) -> Self::SourceEntryRepository<'_> {
        SqliteSourceEntryRepository::new(self)
    }

    fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_> {
        SqliteLibraryScanTargetRepository::new(self)
    }

    fn commit(self) -> Result<(), ApplicationPortError>
    where
        Self: Sized,
    {
        SqliteUnitOfWork::commit(self)
    }

    fn rollback(self) -> Result<(), ApplicationPortError>
    where
        Self: Sized,
    {
        SqliteUnitOfWork::rollback(self)
    }
}

impl Drop for SqliteUnitOfWork<'_> {
    fn drop(&mut self) {
        if let Some(transaction) = self.transaction.take() {
            let _ = transaction.rollback();
        }
    }
}

fn map_operation_error(error: rusqlite::Error) -> ApplicationPortError {
    match operation_error(&error) {
        SqliteOperationError::Application(error) => error,
        _ => map_persistence_operation_error(error).into(),
    }
}

fn map_persistence_operation_error(error: rusqlite::Error) -> PersistenceError {
    match operation_error(&error) {
        SqliteOperationError::Constraint => PersistenceError::ConstraintViolation,
        SqliteOperationError::Locked => PersistenceError::DatabaseLocked,
        SqliteOperationError::Failed => PersistenceError::Internal,
        SqliteOperationError::Application(_) => PersistenceError::Internal,
    }
}

fn parse_source_id(value: String) -> Result<argus_application::LibrarySourceId, PersistenceError> {
    argus_application::LibrarySourceId::try_from(value.as_str())
        .map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_root_id(value: String) -> Result<argus_application::LibraryRootId, PersistenceError> {
    argus_application::LibraryRootId::try_from(value.as_str())
        .map_err(|_| PersistenceError::CorruptOrIncompatible)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sqlite::connection::SqliteValue;
    use argus_application::{OperationName, SubsystemName, TraceId};
    use rusqlite::Connection;

    fn context() -> OperationContext {
        OperationContext::new(
            TraceId::try_from(1).expect("non-zero trace"),
            SubsystemName::try_from("test").expect("valid subsystem"),
            OperationName::try_from("uow").expect("valid operation"),
        )
    }

    #[test]
    fn internal_sql_helpers_commit_and_preserve_context() {
        let mut connection = Connection::open_in_memory().expect("in-memory database");
        let transaction = connection
            .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
            .expect("transaction");
        let mut work = SqliteUnitOfWork::new(transaction, context());
        assert_eq!(work.operation_context().trace_id(), context().trace_id());
        work.execute_batch(
            "CREATE TABLE values_table (value INTEGER NOT NULL, label TEXT NOT NULL);",
        )
        .expect("schema");
        assert_eq!(
            work.execute_with_values(
                "INSERT INTO values_table (value, label) VALUES (?1, ?2)",
                &[
                    SqliteValue::Integer(7),
                    SqliteValue::Text("ready".to_owned())
                ],
            )
            .expect("insert"),
            1
        );
        assert_eq!(work.scalar_i64("SELECT value FROM values_table"), Ok(7));
        assert_eq!(
            work.scalar_text("SELECT label FROM values_table"),
            Ok("ready".to_owned())
        );
        work.commit().expect("commit");
        assert_eq!(
            connection
                .query_row("SELECT COUNT(*) FROM values_table", [], |row| row
                    .get::<_, i64>(0))
                .expect("count"),
            1
        );
    }

    #[test]
    fn explicit_rollback_and_drop_discard_transaction_changes() {
        let mut connection = Connection::open_in_memory().expect("in-memory database");
        connection
            .execute_batch("CREATE TABLE values_table (value INTEGER NOT NULL);")
            .expect("schema");
        {
            let transaction = connection
                .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
                .expect("transaction");
            let mut work = SqliteUnitOfWork::new(transaction, context());
            work.execute("INSERT INTO values_table (value) VALUES (1)")
                .expect("insert");
            work.rollback().expect("rollback");
        }
        {
            let transaction = connection
                .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
                .expect("transaction");
            let mut work = SqliteUnitOfWork::new(transaction, context());
            work.execute("INSERT INTO values_table (value) VALUES (2)")
                .expect("insert");
            // Dropping an uncommitted scope invokes rollback.
        }
        assert_eq!(
            connection
                .query_row("SELECT COUNT(*) FROM values_table", [], |row| row
                    .get::<_, i64>(0))
                .expect("count"),
            0
        );
    }

    #[test]
    fn callback_sql_errors_map_to_application_persistence_errors() {
        let mut connection = Connection::open_in_memory().expect("in-memory database");
        let transaction = connection
            .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
            .expect("transaction");
        let mut work = SqliteUnitOfWork::new(transaction, context());
        work.execute_batch("CREATE TABLE values_table (value INTEGER UNIQUE NOT NULL);")
            .expect("schema");
        work.execute("INSERT INTO values_table (value) VALUES (1)")
            .expect("first insert");
        assert_eq!(
            work.execute("INSERT INTO values_table (value) VALUES (1)"),
            Err(ApplicationPortError::Persistence(
                PersistenceError::ConstraintViolation
            ))
        );
        work.rollback().expect("rollback");
    }
}
