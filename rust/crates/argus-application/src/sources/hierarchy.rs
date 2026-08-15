//! Slice 004 authoritative source-entry hierarchy query boundary.
//!
//! These read projections and queries are the public hierarchy inspection
//! surface. They are deliberately separate from the transaction-scoped
//! reconciliation repository ports in [`crate::jobs::SourceEntryRepository`]:
//! reconciliation support is not a user-facing hierarchy query.

use std::fmt;

use crate::{
    ApplicationError, ErrorCode, LibraryRootId, OperationContext, PersistenceError, SourceEntryId,
};

use super::library::{application_error, map_persistence_error};
use super::provider::{SourceEntryClassification, SourceEntryKind};

/// Safe authoritative row projection for one source entry.
///
/// Exposes only application-owned user-meaningful facts. It deliberately
/// carries no provider locators, native identities, fingerprints, persistence
/// metadata, or scan/provenance identity.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryProjection {
    source_entry_id: SourceEntryId,
    parent_source_entry_id: Option<SourceEntryId>,
    display_name: String,
    display_location: String,
    kind: SourceEntryKind,
    classification: SourceEntryClassification,
}

impl SourceEntryProjection {
    /// Creates one safe row projection.
    pub fn new(
        source_entry_id: SourceEntryId,
        parent_source_entry_id: Option<SourceEntryId>,
        display_name: impl Into<String>,
        display_location: impl Into<String>,
        kind: SourceEntryKind,
        classification: SourceEntryClassification,
    ) -> Self {
        Self {
            source_entry_id,
            parent_source_entry_id,
            display_name: display_name.into(),
            display_location: display_location.into(),
            kind,
            classification,
        }
    }

    /// Returns the stable source identity.
    pub fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the current parent identity, if any.
    pub fn parent_source_entry_id(&self) -> Option<SourceEntryId> {
        self.parent_source_entry_id
    }

    /// Returns the application-owned display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the root-relative safe display location.
    pub fn display_location(&self) -> &str {
        &self.display_location
    }

    /// Returns the persisted source-entry kind.
    pub fn kind(&self) -> SourceEntryKind {
        self.kind
    }

    /// Returns the persisted classification.
    pub fn classification(&self) -> SourceEntryClassification {
        self.classification
    }
}

/// Safe authoritative detail projection for one source entry.
///
/// Structurally identical safe facts for Slice 004; the distinct type
/// preserves the BE-008 row/detail split. Current authoritative data has no
/// user-meaningful status fact, so no status field exists and the reserved
/// bridge status fields map to `None` at the bridge boundary.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryDetailProjection {
    source_entry_id: SourceEntryId,
    parent_source_entry_id: Option<SourceEntryId>,
    display_name: String,
    display_location: String,
    kind: SourceEntryKind,
    classification: SourceEntryClassification,
}

impl SourceEntryDetailProjection {
    /// Creates one safe detail projection.
    pub fn new(
        source_entry_id: SourceEntryId,
        parent_source_entry_id: Option<SourceEntryId>,
        display_name: impl Into<String>,
        display_location: impl Into<String>,
        kind: SourceEntryKind,
        classification: SourceEntryClassification,
    ) -> Self {
        Self {
            source_entry_id,
            parent_source_entry_id,
            display_name: display_name.into(),
            display_location: display_location.into(),
            kind,
            classification,
        }
    }

    /// Returns the stable source identity.
    pub fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the current parent identity, if any.
    pub fn parent_source_entry_id(&self) -> Option<SourceEntryId> {
        self.parent_source_entry_id
    }

    /// Returns the application-owned display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the root-relative safe display location.
    pub fn display_location(&self) -> &str {
        &self.display_location
    }

    /// Returns the persisted source-entry kind.
    pub fn kind(&self) -> SourceEntryKind {
        self.kind
    }

    /// Returns the persisted classification.
    pub fn classification(&self) -> SourceEntryClassification {
        self.classification
    }
}

/// Failure while constructing a cursor from untrusted external text.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SourceEntryCursorError;

impl fmt::Display for SourceEntryCursorError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("invalid source-entry page cursor")
    }
}

impl std::error::Error for SourceEntryCursorError {}

/// Validated, application-owned direct-child page cursor.
///
/// Untrusted external text is parsed exactly once through [`TryFrom<&str>`]
/// at the bridge/application boundary. Persistence receives this validated
/// structured value and reads its keys; it never reinterprets an untrusted
/// string. The textual wire encoding is implementation-private.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryCursor {
    created_at_seconds: i64,
    source_entry_id: SourceEntryId,
}

impl SourceEntryCursor {
    /// Builds one cursor from persistence-owned paging keys.
    ///
    /// This is a backend constructor for the SQLite adapter when it derives
    /// the next cursor from the last returned row. The structured cursor
    /// remains application-owned backend state; its textual encoding stays
    /// opaque to Flutter and ordinary callers.
    pub fn from_paging_keys(created_at_seconds: i64, source_entry_id: SourceEntryId) -> Self {
        Self {
            created_at_seconds,
            source_entry_id,
        }
    }

    /// Returns the paging timestamp key (Unix seconds).
    pub fn created_at_seconds(&self) -> i64 {
        self.created_at_seconds
    }

    /// Returns the unique paging tie-breaker identity.
    pub fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }
}

impl TryFrom<&str> for SourceEntryCursor {
    type Error = SourceEntryCursorError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        let (version, rest) = value.split_once(':').ok_or(SourceEntryCursorError)?;
        if version != "v1" {
            return Err(SourceEntryCursorError);
        }
        let (created_at, id) = rest.rsplit_once(':').ok_or(SourceEntryCursorError)?;
        if created_at.is_empty() || id.is_empty() {
            return Err(SourceEntryCursorError);
        }
        let created_at_seconds = created_at
            .parse::<i64>()
            .map_err(|_| SourceEntryCursorError)?;
        if created_at_seconds < 0 {
            return Err(SourceEntryCursorError);
        }
        let source_entry_id = SourceEntryId::try_from(id).map_err(|_| SourceEntryCursorError)?;
        Ok(Self {
            created_at_seconds,
            source_entry_id,
        })
    }
}

impl fmt::Display for SourceEntryCursor {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "v1:{}:{}",
            self.created_at_seconds, self.source_entry_id
        )
    }
}

/// One bounded authoritative direct-child page.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryChildrenPage {
    items: Vec<SourceEntryProjection>,
    next_cursor: Option<SourceEntryCursor>,
}

impl SourceEntryChildrenPage {
    /// Creates one bounded page with backend-owned ordering.
    pub fn new(items: Vec<SourceEntryProjection>, next_cursor: Option<SourceEntryCursor>) -> Self {
        Self { items, next_cursor }
    }

    /// Returns the page items in authoritative order.
    pub fn items(&self) -> &[SourceEntryProjection] {
        &self.items
    }

    /// Returns the opaque continuation cursor, if another page may exist.
    pub fn next_cursor(&self) -> Option<&SourceEntryCursor> {
        self.next_cursor.as_ref()
    }
}

/// One bounded direct-child paging request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ListSourceEntryChildrenQuery {
    library_root_id: LibraryRootId,
    parent_source_entry_id: Option<SourceEntryId>,
    cursor: Option<SourceEntryCursor>,
    page_size: u32,
}

impl ListSourceEntryChildrenQuery {
    /// Default page size used when the caller supplies no explicit bound.
    pub const DEFAULT_PAGE_SIZE: u32 = 100;

    /// Backend-enforced maximum page size.
    pub const MAX_PAGE_SIZE: u32 = 200;

    /// Creates a bounded query. `parent_source_entry_id = None` addresses
    /// direct configured-root children; `cursor` must already be validated.
    pub fn new(
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        cursor: Option<SourceEntryCursor>,
        page_size: u32,
    ) -> Self {
        Self {
            library_root_id,
            parent_source_entry_id,
            cursor,
            page_size: page_size.clamp(1, Self::MAX_PAGE_SIZE),
        }
    }

    /// Returns the owning root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the parent scope identity; `None` is the root scope.
    pub fn parent_source_entry_id(&self) -> Option<SourceEntryId> {
        self.parent_source_entry_id
    }

    /// Returns the validated continuation cursor, if any.
    pub fn cursor(&self) -> Option<&SourceEntryCursor> {
        self.cursor.as_ref()
    }

    /// Returns the clamped page size.
    pub fn page_size(&self) -> u32 {
        self.page_size
    }
}

/// One authoritative source-entry detail request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct GetSourceEntryQuery {
    source_entry_id: SourceEntryId,
}

impl GetSourceEntryQuery {
    /// Creates a detail request for one stable identity.
    pub const fn new(source_entry_id: SourceEntryId) -> Self {
        Self { source_entry_id }
    }

    /// Returns the requested source identity.
    pub const fn source_entry_id(self) -> SourceEntryId {
        self.source_entry_id
    }
}

/// Independent authoritative source-entry hierarchy reads.
///
/// This is the public read port for hierarchy inspection. It is intentionally
/// separate from the transaction-scoped reconciliation repository.
pub trait SourceEntryQueries {
    /// Lists one bounded direct-child page in backend-owned deterministic
    /// order. `parent = None` addresses direct configured-root children.
    fn list_children(
        &self,
        context: &OperationContext,
        query: &ListSourceEntryChildrenQuery,
    ) -> Result<SourceEntryChildrenPage, PersistenceError>;

    /// Reads one current safe detail projection, or `None` when absent.
    fn get(
        &self,
        context: &OperationContext,
        source_entry_id: SourceEntryId,
    ) -> Result<Option<SourceEntryDetailProjection>, PersistenceError>;
}

impl<Q> SourceEntryQueries for &Q
where
    Q: SourceEntryQueries,
{
    fn list_children(
        &self,
        context: &OperationContext,
        query: &ListSourceEntryChildrenQuery,
    ) -> Result<SourceEntryChildrenPage, PersistenceError> {
        (*self).list_children(context, query)
    }

    fn get(
        &self,
        context: &OperationContext,
        source_entry_id: SourceEntryId,
    ) -> Result<Option<SourceEntryDetailProjection>, PersistenceError> {
        (*self).get(context, source_entry_id)
    }
}

/// Handles one bounded direct-child query.
pub struct ListSourceEntryChildrenHandler<Q> {
    queries: Q,
}

impl<Q> ListSourceEntryChildrenHandler<Q> {
    /// Composes the focused query capability.
    pub const fn new(queries: Q) -> Self {
        Self { queries }
    }
}

impl<Q> ListSourceEntryChildrenHandler<Q>
where
    Q: SourceEntryQueries,
{
    /// Executes the bounded direct-child query.
    pub fn handle(
        &self,
        query: ListSourceEntryChildrenQuery,
        context: OperationContext,
    ) -> Result<SourceEntryChildrenPage, ApplicationError> {
        self.queries
            .list_children(&context, &query)
            .map_err(|error| map_persistence_error(context.trace_id(), error))
    }
}

/// Handles one authoritative source-entry detail query.
pub struct GetSourceEntryHandler<Q> {
    queries: Q,
}

impl<Q> GetSourceEntryHandler<Q> {
    /// Composes the focused query capability.
    pub const fn new(queries: Q) -> Self {
        Self { queries }
    }
}

impl<Q> GetSourceEntryHandler<Q>
where
    Q: SourceEntryQueries,
{
    /// Executes the detail query; a missing entry is a typed configuration
    /// failure so Flutter can clear stale transient identity state.
    pub fn handle(
        &self,
        query: GetSourceEntryQuery,
        context: OperationContext,
    ) -> Result<SourceEntryDetailProjection, ApplicationError> {
        self.queries
            .get(&context, query.source_entry_id())
            .map_err(|error| map_persistence_error(context.trace_id(), error))?
            .ok_or_else(|| {
                application_error(
                    context.trace_id(),
                    ErrorCode::ConfigurationSourceEntryNotFound,
                )
            })
    }
}
