//! Safe, bounded operations over a worker-owned SQLite connection.

#![cfg_attr(not(feature = "test-support"), allow(dead_code))]

use argus_application::OperationContext;
use rusqlite::{Connection, ToSql};

use super::errors::{SqliteOperationError, operation_error};

/// Values accepted by the small SQL operation surface.
#[allow(dead_code)]
#[derive(Clone, Debug, PartialEq)]
pub enum SqliteValue {
    Null,
    Integer(i64),
    Real(f64),
    Text(String),
    Blob(Vec<u8>),
}

impl ToSql for SqliteValue {
    fn to_sql(&self) -> rusqlite::Result<rusqlite::types::ToSqlOutput<'_>> {
        Ok(match self {
            Self::Null => rusqlite::types::ToSqlOutput::Owned(rusqlite::types::Value::Null),
            Self::Integer(value) => {
                rusqlite::types::ToSqlOutput::Owned(rusqlite::types::Value::Integer(*value))
            }
            Self::Real(value) => {
                rusqlite::types::ToSqlOutput::Owned(rusqlite::types::Value::Real(*value))
            }
            Self::Text(value) => {
                rusqlite::types::ToSqlOutput::Owned(rusqlite::types::Value::Text(value.clone()))
            }
            Self::Blob(value) => {
                rusqlite::types::ToSqlOutput::Owned(rusqlite::types::Value::Blob(value.clone()))
            }
        })
    }
}

/// A callback-scoped view of the worker's SQLite connection.
pub struct SqliteConnection<'connection> {
    pub(crate) connection: &'connection mut Connection,
    context: OperationContext,
}

impl<'connection> SqliteConnection<'connection> {
    pub(crate) fn new(connection: &'connection mut Connection, context: OperationContext) -> Self {
        Self {
            connection,
            context,
        }
    }

    /// Returns the operation context carried across the queue boundary.
    pub fn operation_context(&self) -> &OperationContext {
        &self.context
    }

    /// Executes a bounded SQL statement and returns changed-row count.
    pub fn execute(&mut self, sql: &str) -> Result<usize, SqliteOperationError> {
        self.connection
            .execute(sql, [])
            .map_err(|error| operation_error(&error))
    }

    /// Executes a statement with typed bound values.
    pub fn execute_with_values(
        &mut self,
        sql: &str,
        values: &[SqliteValue],
    ) -> Result<usize, SqliteOperationError> {
        let refs: Vec<&dyn ToSql> = values.iter().map(|value| value as &dyn ToSql).collect();
        self.connection
            .execute(sql, refs.as_slice())
            .map_err(|error| operation_error(&error))
    }

    /// Executes a SQL batch. This is intended for infrastructure-owned schema work.
    pub fn execute_batch(&mut self, sql: &str) -> Result<(), SqliteOperationError> {
        self.connection
            .execute_batch(sql)
            .map_err(|error| operation_error(&error))
    }

    /// Reads one integer scalar from a query.
    pub fn scalar_i64(&mut self, sql: &str) -> Result<i64, SqliteOperationError> {
        self.connection
            .query_row(sql, [], |row| row.get(0))
            .map_err(|error| operation_error(&error))
    }

    /// Reads one text scalar from a query.
    pub fn scalar_text(&mut self, sql: &str) -> Result<String, SqliteOperationError> {
        self.connection
            .query_row(sql, [], |row| row.get(0))
            .map_err(|error| operation_error(&error))
    }

    /// Returns whether a named table exists.
    pub fn table_exists(&mut self, name: &str) -> Result<bool, SqliteOperationError> {
        self.connection
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)",
                [name],
                |row| row.get(0),
            )
            .map_err(|error| operation_error(&error))
    }
}
