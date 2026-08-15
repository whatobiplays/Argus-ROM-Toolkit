//! Slice 004 typed SQLite adapter for authoritative source-entry hierarchy
//! reads.
//!
//! This read adapter is separate from the transaction-scoped reconciliation
//! repository. It performs bounded deterministic keyset paging and never
//! materializes the whole tree.

use argus_application::{
    ApplicationPortError, ListSourceEntryChildrenQuery, OperationContext, PersistenceError,
    SourceEntryChildrenPage, SourceEntryClassification, SourceEntryCursor,
    SourceEntryDetailProjection, SourceEntryId, SourceEntryKind, SourceEntryProjection,
    SourceEntryQueries,
};
use rusqlite::OptionalExtension;

use super::appearance::map_executor_error;
use super::connection::SqliteConnection;
use super::errors::operation_error;
use super::executor::SqliteDatabaseExecutor;

type RowRaw = (String, Option<String>, String, String, String, String, i64);

type DetailRaw = (String, Option<String>, String, String, String, String);

/// Independent authoritative source-entry hierarchy query adapter.
#[derive(Clone)]
pub struct SqliteSourceEntryQueries {
    executor: SqliteDatabaseExecutor,
}

impl SqliteSourceEntryQueries {
    /// Creates a query adapter over an existing shared SQLite executor.
    pub const fn new(executor: SqliteDatabaseExecutor) -> Self {
        Self { executor }
    }
}

impl SourceEntryQueries for SqliteSourceEntryQueries {
    fn list_children(
        &self,
        context: &OperationContext,
        query: &ListSourceEntryChildrenQuery,
    ) -> Result<SourceEntryChildrenPage, PersistenceError> {
        let library_root_id = query.library_root_id();
        let parent_source_entry_id = query.parent_source_entry_id();
        let cursor = query.cursor().cloned();
        let page_size = query.page_size();
        self.executor
            .with_connection(context.clone(), move |connection| {
                let rows = read_children_page(
                    connection,
                    library_root_id,
                    parent_source_entry_id,
                    cursor.as_ref(),
                    page_size,
                )?;
                let mut rows = rows.into_iter();
                let mut items = Vec::with_capacity(rows.len());
                let mut last_item: Option<RowRaw> = None;
                for raw in rows.by_ref().take(page_size as usize) {
                    last_item = Some(raw.clone());
                    items.push(source_entry_projection_from_raw(raw).map_err(persistence_error)?);
                }
                let next_cursor = if rows.next().is_some() {
                    let last = last_item.expect("clamped page size is at least one row");
                    Some(SourceEntryCursor::from_paging_keys(
                        last.6,
                        parse_source_entry_id(last.0).map_err(persistence_error)?,
                    ))
                } else {
                    None
                };
                Ok(SourceEntryChildrenPage::new(items, next_cursor))
            })
            .map_err(map_executor_error)
    }

    fn get(
        &self,
        context: &OperationContext,
        source_entry_id: SourceEntryId,
    ) -> Result<Option<SourceEntryDetailProjection>, PersistenceError> {
        let source_entry_id = source_entry_id.to_string();
        self.executor
            .with_connection(context.clone(), move |connection| {
                let raw = connection
                    .connection
                    .query_row(
                        "SELECT source_entry_id, parent_source_entry_id, display_name,
                                display_location, kind, classification
                         FROM source_entry
                         WHERE source_entry_id = ?1",
                        [source_entry_id],
                        |row| {
                            Ok((
                                row.get::<_, String>(0)?,
                                row.get::<_, Option<String>>(1)?,
                                row.get::<_, String>(2)?,
                                row.get::<_, String>(3)?,
                                row.get::<_, String>(4)?,
                                row.get::<_, String>(5)?,
                            ))
                        },
                    )
                    .optional()
                    .map_err(|error| operation_error(&error))?;
                raw.map(source_entry_detail_from_raw)
                    .transpose()
                    .map_err(persistence_error)
            })
            .map_err(map_executor_error)
    }
}

fn persistence_error(error: PersistenceError) -> super::errors::SqliteOperationError {
    super::errors::SqliteOperationError::Application(ApplicationPortError::Persistence(error))
}

fn read_children_page(
    connection: &mut SqliteConnection<'_>,
    library_root_id: argus_application::LibraryRootId,
    parent_source_entry_id: Option<SourceEntryId>,
    cursor: Option<&SourceEntryCursor>,
    page_size: u32,
) -> Result<Vec<RowRaw>, super::errors::SqliteOperationError> {
    let mut statement = connection
        .connection
        .prepare(
            "SELECT source_entry_id, parent_source_entry_id, display_name,
                    display_location, kind, classification, created_at
             FROM source_entry
             WHERE library_root_id = ?1 AND parent_source_entry_id IS ?2
               AND (?3 IS NULL OR (created_at, source_entry_id) > (?3, ?4))
             ORDER BY created_at ASC, source_entry_id ASC
             LIMIT ?5",
        )
        .map_err(|error| operation_error(&error))?;
    let rows = statement
        .query_map(
            rusqlite::params![
                library_root_id.to_string(),
                parent_source_entry_id.map(|id| id.to_string()),
                cursor.map(|value| value.created_at_seconds()),
                cursor.map(|value| value.source_entry_id().to_string()),
                i64::from(page_size) + 1,
            ],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<String>>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, i64>(6)?,
                ))
            },
        )
        .map_err(|error| operation_error(&error))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| operation_error(&error))
}

fn source_entry_projection_from_raw(
    raw: RowRaw,
) -> Result<SourceEntryProjection, PersistenceError> {
    let (id, parent, display, location, kind, classification, _created_at) = raw;
    let source_entry_id = parse_source_entry_id(id)?;
    let parent_source_entry_id = parent.map(parse_source_entry_id).transpose()?;
    Ok(SourceEntryProjection::new(
        source_entry_id,
        parent_source_entry_id,
        display,
        location,
        parse_kind(kind)?,
        parse_classification(classification)?,
    ))
}

fn source_entry_detail_from_raw(
    raw: DetailRaw,
) -> Result<SourceEntryDetailProjection, PersistenceError> {
    let (id, parent, display, location, kind, classification) = raw;
    let source_entry_id = parse_source_entry_id(id)?;
    let parent_source_entry_id = parent.map(parse_source_entry_id).transpose()?;
    Ok(SourceEntryDetailProjection::new(
        source_entry_id,
        parent_source_entry_id,
        display,
        location,
        parse_kind(kind)?,
        parse_classification(classification)?,
    ))
}

fn parse_source_entry_id(value: String) -> Result<SourceEntryId, PersistenceError> {
    SourceEntryId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_kind(value: String) -> Result<SourceEntryKind, PersistenceError> {
    match value.as_str() {
        "directory" => Ok(SourceEntryKind::Directory),
        "file" => Ok(SourceEntryKind::File),
        "link_like" => Ok(SourceEntryKind::LinkLike),
        "unknown" => Ok(SourceEntryKind::Unknown),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_classification(value: String) -> Result<SourceEntryClassification, PersistenceError> {
    match value.as_str() {
        "container" => Ok(SourceEntryClassification::Container),
        "content_candidate" => Ok(SourceEntryClassification::ContentCandidate),
        "supporting_entry" => Ok(SourceEntryClassification::SupportingEntry),
        "ignored" => Ok(SourceEntryClassification::Ignored),
        "unknown" => Ok(SourceEntryClassification::Unknown),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}
