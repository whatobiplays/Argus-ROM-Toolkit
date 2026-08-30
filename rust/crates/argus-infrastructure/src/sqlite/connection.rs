//! Safe, bounded operations over a worker-owned SQLite connection.

#![cfg_attr(not(feature = "test-support"), allow(dead_code))]

use argus_application::OperationContext;
#[cfg(feature = "test-support")]
use rusqlite::StatementStatus;
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

/// SQLite execution counters captured for a test-owned representative query.
///
/// This type is intentionally available only with `test-support`; production
/// callers receive no query-profiler surface or associated overhead.
#[cfg(feature = "test-support")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SqliteQueryMetrics {
    row_count: usize,
    vm_steps: i64,
    full_scan_steps: i64,
    sort_operations: i64,
}

#[cfg(feature = "test-support")]
impl SqliteQueryMetrics {
    /// Returns the number of rows consumed by the statement.
    pub const fn row_count(self) -> usize {
        self.row_count
    }

    /// Returns SQLite virtual-machine steps consumed by the statement.
    pub const fn vm_steps(self) -> i64 {
        self.vm_steps
    }

    /// Returns full-table scan steps reported by SQLite.
    pub const fn full_scan_steps(self) -> i64 {
        self.full_scan_steps
    }

    /// Returns temporary sort operations reported by SQLite.
    pub const fn sort_operations(self) -> i64 {
        self.sort_operations
    }
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

    /// Measures one parameter-free, test-owned query without exposing the
    /// SQLite statement or connection outside infrastructure tests.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn query_metrics_for_tests(
        &mut self,
        sql: &str,
    ) -> Result<SqliteQueryMetrics, SqliteOperationError> {
        let mut statement = self
            .connection
            .prepare(sql)
            .map_err(|error| operation_error(&error))?;
        let row_count = {
            let mut rows = statement
                .query([])
                .map_err(|error| operation_error(&error))?;
            let mut row_count = 0_usize;
            while rows
                .next()
                .map_err(|error| operation_error(&error))?
                .is_some()
            {
                row_count = row_count.saturating_add(1);
            }
            row_count
        };
        Ok(SqliteQueryMetrics {
            row_count,
            vm_steps: i64::from(statement.get_status(StatementStatus::VmStep)),
            full_scan_steps: i64::from(statement.get_status(StatementStatus::FullscanStep)),
            sort_operations: i64::from(statement.get_status(StatementStatus::Sort)),
        })
    }

    /// Returns stable SQLite query-plan detail for one parameter-free,
    /// test-owned query. Plans are used to assert index selection and avoid
    /// making wall-clock timing a qualification gate.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn explain_query_plan_for_tests(
        &mut self,
        sql: &str,
    ) -> Result<Vec<String>, SqliteOperationError> {
        let explain_sql = format!("EXPLAIN QUERY PLAN {sql}");
        let mut statement = self
            .connection
            .prepare(&explain_sql)
            .map_err(|error| operation_error(&error))?;
        let rows = statement
            .query_map([], |row| row.get::<_, String>(3))
            .map_err(|error| operation_error(&error))?;
        rows.map(|row| row.map_err(|error| operation_error(&error)))
            .collect()
    }
}
