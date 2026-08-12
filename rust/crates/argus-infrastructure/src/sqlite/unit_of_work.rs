//! Transaction-scoped SQLite Unit of Work implementation.

use rusqlite::Transaction;

use argus_application::{ApplicationPortError, OperationContext, PersistenceError, UnitOfWork};

use super::connection::SqliteValue;
use super::errors::{SqliteOperationError, operation_error};

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

impl UnitOfWork for SqliteUnitOfWork<'_> {
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
    ApplicationPortError::Persistence(match operation_error(&error) {
        SqliteOperationError::Constraint => PersistenceError::ConstraintViolation,
        SqliteOperationError::Locked => PersistenceError::Unavailable,
        SqliteOperationError::Failed => PersistenceError::Internal,
    })
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
