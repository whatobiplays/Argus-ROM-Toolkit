//! Focused logical-library query contracts for the initial backend seam.

use argus_domain::{
    AvailabilityState, ContentType, GameContentPresence, GameId, GameLifecycle, GroupingBasis,
    HydrationState, IdentificationState, MembershipRelationship, PlatformId,
};

use crate::{
    ErrorCode, GameContentId, IdentityDigest, PersistenceError, ResolvedArtwork, ResolvedMetadata,
    ScanRunId, SourceEntryId,
};

/// The only library scope activated by the current slice.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryScope {
    /// All active logical games.
    All,
}

/// Stable default ordering activated for the initial library page.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibrarySort {
    /// Display title ascending with game identity as deterministic tie-breaker.
    DisplayTitleAscending,
}

/// Validation failure at the application query boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QueryValidationError {
    /// A published query concept is not active in this slice.
    Application(ErrorCode),
}

/// Opaque continuation token for logical-game paging.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameListCursor {
    value: String,
    display_title: String,
    game_id: GameId,
}

impl GameListCursor {
    /// Builds a cursor from persistence-owned display-title and ID keys.
    pub fn from_paging_keys(display_title: impl Into<String>, game_id: GameId) -> Self {
        let display_title = display_title.into();
        Self {
            value: format!("v1:{}:{}", hex_encode(display_title.as_bytes()), game_id),
            display_title,
            game_id,
        }
    }

    /// Validates an externally supplied opaque cursor without exposing its keys.
    pub fn try_from_external(value: impl Into<String>) -> Result<Self, QueryValidationError> {
        let value = value.into();
        let Some((version, rest)) = value.split_once(':') else {
            return Err(QueryValidationError::Application(
                ErrorCode::ValidationInvalidArgument,
            ));
        };
        if version != "v1" {
            return Err(QueryValidationError::Application(
                ErrorCode::ValidationInvalidArgument,
            ));
        }
        let Some((title_hex, id)) = rest.split_once(':') else {
            return Err(QueryValidationError::Application(
                ErrorCode::ValidationInvalidArgument,
            ));
        };
        let title_bytes = hex_decode(title_hex).ok_or(QueryValidationError::Application(
            ErrorCode::ValidationInvalidArgument,
        ))?;
        let display_title = String::from_utf8(title_bytes)
            .map_err(|_| QueryValidationError::Application(ErrorCode::ValidationInvalidArgument))?;
        let game_id = GameId::try_from(id)
            .map_err(|_| QueryValidationError::Application(ErrorCode::ValidationInvalidArgument))?;
        Ok(Self {
            value,
            display_title,
            game_id,
        })
    }
}

/// Safe row projection used by the focused logical-library list.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameLibraryRow {
    game_id: GameId,
    display_title: String,
    platform_id: PlatformId,
    hydration_state: HydrationState,
    availability_state: AvailabilityState,
    content_count: u32,
    source_count: u32,
    updated_at_ms: i64,
}

impl GameLibraryRow {
    /// Creates the local-fallback projection for a newly identified game.
    pub fn fallback(
        game_id: GameId,
        display_title: impl Into<String>,
        platform_id: PlatformId,
        content_count: u32,
        source_count: u32,
        updated_at_ms: i64,
    ) -> Self {
        Self {
            game_id,
            display_title: display_title.into(),
            platform_id,
            hydration_state: HydrationState::PartiallyHydrated,
            availability_state: AvailabilityState::Available,
            content_count,
            source_count,
            updated_at_ms,
        }
    }

    /// Creates a row from the durable projection, preserving independent
    /// hydration and availability state.
    #[allow(clippy::too_many_arguments)]
    pub fn from_persisted(
        game_id: GameId,
        display_title: impl Into<String>,
        platform_id: PlatformId,
        hydration_state: HydrationState,
        availability_state: AvailabilityState,
        content_count: u32,
        source_count: u32,
        updated_at_ms: i64,
    ) -> Self {
        Self {
            game_id,
            display_title: display_title.into(),
            platform_id,
            hydration_state,
            availability_state,
            content_count,
            source_count,
            updated_at_ms,
        }
    }

    /// Returns the game identity.
    pub const fn game_id(&self) -> GameId {
        self.game_id
    }

    /// Returns the safe presentation title.
    pub fn display_title(&self) -> &str {
        &self.display_title
    }

    /// Returns the authoritative platform.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns hydration state.
    pub const fn hydration_state(&self) -> HydrationState {
        self.hydration_state
    }

    /// Returns availability derived from authoritative source facts.
    pub const fn availability_state(&self) -> AvailabilityState {
        self.availability_state
    }

    /// Returns the current logical-content count.
    pub const fn content_count(&self) -> u32 {
        self.content_count
    }

    /// Returns the physical-copy count.
    pub const fn source_count(&self) -> u32 {
        self.source_count
    }

    /// Returns the authoritative update timestamp.
    pub const fn updated_at_ms(&self) -> i64 {
        self.updated_at_ms
    }
}

/// One bounded page of safe library rows.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameLibraryPage {
    items: Vec<GameLibraryRow>,
    next_cursor: Option<GameListCursor>,
}

impl GameLibraryPage {
    /// Creates one page and its opaque continuation.
    pub fn new(items: Vec<GameLibraryRow>, next_cursor: Option<GameListCursor>) -> Self {
        Self { items, next_cursor }
    }

    /// Returns the rows in canonical order.
    pub fn items(&self) -> &[GameLibraryRow] {
        &self.items
    }

    /// Returns the opaque continuation, if more rows exist.
    pub fn next_cursor(&self) -> Option<&GameListCursor> {
        self.next_cursor.as_ref()
    }
}

/// Durable summary of one current logical content member.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameContentSummary {
    game_content_id: GameContentId,
    platform_id: PlatformId,
    content_type: ContentType,
    presence: GameContentPresence,
    identification: IdentificationState,
    source_count: u32,
    identity: Option<ContentIdentitySummary>,
    provenance: Option<ContentProvenanceSummary>,
}

/// Current identity facts exposed without parser details or raw locators.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentIdentitySummary {
    scheme_id: String,
    revision: u32,
    digest: IdentityDigest,
}

impl ContentIdentitySummary {
    /// Creates a safe current identity summary.
    pub fn new(scheme_id: impl Into<String>, revision: u32, digest: IdentityDigest) -> Self {
        Self {
            scheme_id: scheme_id.into(),
            revision,
            digest,
        }
    }

    /// Returns the production identity scheme.
    pub fn scheme_id(&self) -> &str {
        &self.scheme_id
    }

    /// Returns the identity revision.
    pub const fn revision(&self) -> u32 {
        self.revision
    }

    /// Returns the canonical digest.
    pub const fn digest(&self) -> IdentityDigest {
        self.digest
    }
}

/// Exact proving provenance without exposing filesystem locations.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentProvenanceSummary {
    source_entry_id: SourceEntryId,
    association_key: String,
    source_fingerprint: Option<String>,
    last_observed_scan_id: ScanRunId,
}

impl ContentProvenanceSummary {
    /// Creates one exact persisted provenance summary.
    pub fn new(
        source_entry_id: SourceEntryId,
        association_key: impl Into<String>,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self {
            source_entry_id,
            association_key: association_key.into(),
            source_fingerprint,
            last_observed_scan_id,
        }
    }

    /// Returns the proving source identity.
    pub const fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the derived-unit association discriminator.
    pub fn association_key(&self) -> &str {
        &self.association_key
    }

    /// Returns the cheap source-version fingerprint.
    pub fn source_fingerprint(&self) -> Option<&str> {
        self.source_fingerprint.as_deref()
    }

    /// Returns the scan observation version.
    pub const fn last_observed_scan_id(&self) -> ScanRunId {
        self.last_observed_scan_id
    }
}

impl GameContentSummary {
    /// Creates one safe content summary without paths or parser details.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        game_content_id: GameContentId,
        platform_id: PlatformId,
        content_type: ContentType,
        presence: GameContentPresence,
        identification: IdentificationState,
        source_count: u32,
    ) -> Self {
        Self {
            game_content_id,
            platform_id,
            content_type,
            presence,
            identification,
            source_count,
            identity: None,
            provenance: None,
        }
    }

    /// Creates a summary with current identity and exact proving provenance.
    #[allow(clippy::too_many_arguments)]
    pub fn with_identity(
        game_content_id: GameContentId,
        platform_id: PlatformId,
        content_type: ContentType,
        presence: GameContentPresence,
        identification: IdentificationState,
        source_count: u32,
        identity: Option<ContentIdentitySummary>,
        provenance: Option<ContentProvenanceSummary>,
    ) -> Self {
        Self {
            game_content_id,
            platform_id,
            content_type,
            presence,
            identification,
            source_count,
            identity,
            provenance,
        }
    }

    /// Returns the logical content identity.
    pub const fn game_content_id(&self) -> GameContentId {
        self.game_content_id
    }

    /// Returns the platform.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns the content type.
    pub const fn content_type(&self) -> ContentType {
        self.content_type
    }

    /// Returns independent presence facts.
    pub const fn presence(&self) -> GameContentPresence {
        self.presence
    }

    /// Returns independent identification state.
    pub const fn identification(&self) -> IdentificationState {
        self.identification
    }

    /// Returns the number of associated physical sources.
    pub const fn source_count(&self) -> u32 {
        self.source_count
    }

    /// Returns the current identity summary, if identity proof is current.
    pub fn identity(&self) -> Option<&ContentIdentitySummary> {
        self.identity.as_ref()
    }

    /// Returns the exact current proving provenance, if present.
    pub fn provenance(&self) -> Option<&ContentProvenanceSummary> {
        self.provenance.as_ref()
    }
}

/// Durable membership summary exposed by `GetGame`.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameMembershipSummary {
    game_content_id: GameContentId,
    relationship: MembershipRelationship,
    grouping_basis: GroupingBasis,
    grouping_revision: u32,
}

impl GameMembershipSummary {
    /// Creates one membership summary.
    pub const fn new(
        game_content_id: GameContentId,
        relationship: MembershipRelationship,
        grouping_basis: GroupingBasis,
        grouping_revision: u32,
    ) -> Self {
        Self {
            game_content_id,
            relationship,
            grouping_basis,
            grouping_revision,
        }
    }

    /// Returns the member content.
    pub const fn game_content_id(&self) -> GameContentId {
        self.game_content_id
    }

    /// Returns the relationship role.
    pub const fn relationship(&self) -> MembershipRelationship {
        self.relationship
    }

    /// Returns the grouping evidence basis.
    pub const fn grouping_basis(&self) -> GroupingBasis {
        self.grouping_basis
    }

    /// Returns the grouping revision.
    pub const fn grouping_revision(&self) -> u32 {
        self.grouping_revision
    }
}

/// Focused durable logical-game detail projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameDetail {
    game_id: GameId,
    platform_id: PlatformId,
    lifecycle: GameLifecycle,
    hydration_state: HydrationState,
    fallback_title: String,
    memberships: Vec<GameMembershipSummary>,
    content: Vec<GameContentSummary>,
    availability_state: AvailabilityState,
    resolved_metadata: Option<ResolvedMetadata>,
    resolved_artwork: Vec<ResolvedArtwork>,
}

impl GameDetail {
    /// Creates a provider-free durable detail projection.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        game_id: GameId,
        platform_id: PlatformId,
        lifecycle: GameLifecycle,
        hydration_state: HydrationState,
        fallback_title: impl Into<String>,
        memberships: Vec<GameMembershipSummary>,
        content: Vec<GameContentSummary>,
        availability_state: AvailabilityState,
    ) -> Self {
        Self {
            game_id,
            platform_id,
            lifecycle,
            hydration_state,
            fallback_title: fallback_title.into(),
            memberships,
            content,
            availability_state,
            resolved_metadata: None,
            resolved_artwork: Vec::new(),
        }
    }

    /// Attaches the latest committed Game-level enrichment projection.
    ///
    /// The projection is optional because canonical logical-library reads must
    /// remain useful when no provider has supplied metadata or artwork.
    pub fn with_enrichment(
        mut self,
        resolved_metadata: Option<ResolvedMetadata>,
        resolved_artwork: Vec<ResolvedArtwork>,
    ) -> Self {
        self.resolved_metadata = resolved_metadata;
        self.resolved_artwork = resolved_artwork;
        self
    }

    /// Returns the game identity.
    pub const fn game_id(&self) -> GameId {
        self.game_id
    }

    /// Returns the platform.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns the game lifecycle.
    pub const fn lifecycle(&self) -> GameLifecycle {
        self.lifecycle
    }

    /// Returns hydration state.
    pub const fn hydration_state(&self) -> HydrationState {
        self.hydration_state
    }

    /// Returns the presentation-only fallback title.
    pub fn fallback_title(&self) -> &str {
        &self.fallback_title
    }

    /// Returns current membership summaries.
    pub fn memberships(&self) -> &[GameMembershipSummary] {
        &self.memberships
    }

    /// Returns current content summaries.
    pub fn content(&self) -> &[GameContentSummary] {
        &self.content
    }

    /// Returns availability.
    pub const fn availability_state(&self) -> AvailabilityState {
        self.availability_state
    }

    /// Returns the latest committed Game-level metadata, if available.
    pub fn resolved_metadata(&self) -> Option<&ResolvedMetadata> {
        self.resolved_metadata.as_ref()
    }

    /// Returns committed artwork selections in deterministic ordering.
    pub fn resolved_artwork(&self) -> &[ResolvedArtwork] {
        &self.resolved_artwork
    }
}

/// Result of a focused game lookup.
#[derive(Clone, Debug, Eq, PartialEq)]
#[allow(clippy::large_enum_variant)]
pub enum GetGameResult {
    /// The requested ID is canonical and has durable detail. The value-owned
    /// projection preserves the existing application and bridge contract.
    Found(GameDetail),
    /// The requested ID is redirected to another game.
    Redirected(GameId),
    /// The requested ID is not persisted.
    NotFound,
}

/// Application-owned read port for logical library projections.
pub trait LogicalLibraryQueries {
    /// Lists the bounded baseline library page.
    fn list_games(&mut self, query: &ListGamesQuery) -> Result<GameLibraryPage, PersistenceError>;

    /// Retrieves one focused logical game result.
    fn get_game(&mut self, game_id: GameId) -> Result<GetGameResult, PersistenceError>;
}

/// Baseline published logical-library list request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ListGamesQuery {
    scope: LibraryScope,
    search: Option<String>,
    filters_empty: bool,
    sort: LibrarySort,
    cursor: Option<GameListCursor>,
    page_size: u32,
}

impl GameListCursor {
    /// Returns the opaque wire value.
    pub fn as_str(&self) -> &str {
        &self.value
    }

    /// Returns the persistence-owned title key.
    pub fn display_title(&self) -> &str {
        &self.display_title
    }

    /// Returns the persistence-owned tie-breaker key.
    pub const fn game_id(&self) -> GameId {
        self.game_id
    }
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut value = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        value.push_str(&format!("{byte:02x}"));
    }
    value
}

fn hex_decode(value: &str) -> Option<Vec<u8>> {
    if !value.len().is_multiple_of(2) {
        return None;
    }
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let high = hex_digit(pair[0])?;
            let low = hex_digit(pair[1])?;
            Some((high << 4) | low)
        })
        .collect()
}

fn hex_digit(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

impl ListGamesQuery {
    /// Starts construction of a validated request.
    pub fn builder() -> ListGamesQueryBuilder {
        ListGamesQueryBuilder::default()
    }

    /// Returns the active scope.
    pub const fn scope(&self) -> LibraryScope {
        self.scope
    }

    /// Returns the optional search term.
    pub fn search(&self) -> Option<&str> {
        self.search.as_deref()
    }

    /// Returns the canonical sort.
    pub const fn sort(&self) -> LibrarySort {
        self.sort
    }

    /// Returns the opaque continuation cursor.
    pub fn cursor(&self) -> Option<&GameListCursor> {
        self.cursor.as_ref()
    }

    /// Returns the bounded page size.
    pub const fn page_size(&self) -> u32 {
        self.page_size
    }

    /// Returns whether the request carries no filters.
    pub const fn filters_empty(&self) -> bool {
        self.filters_empty
    }
}

/// Builder for the baseline list request. Unsupported published concepts are
/// rejected instead of being ignored.
pub struct ListGamesQueryBuilder {
    scope: Option<LibraryScope>,
    search: Option<String>,
    filters_empty: bool,
    sort: Option<LibrarySort>,
    cursor: Option<GameListCursor>,
    page_size: Option<u32>,
}

impl Default for ListGamesQueryBuilder {
    fn default() -> Self {
        Self {
            scope: None,
            search: None,
            filters_empty: true,
            sort: None,
            cursor: None,
            page_size: None,
        }
    }
}

impl ListGamesQueryBuilder {
    /// Supplies a scope.
    pub fn scope(mut self, scope: LibraryScope) -> Self {
        self.scope = Some(scope);
        self
    }

    /// Supplies a search term; P03-001 rejects non-null values.
    pub fn search(mut self, search: Option<String>) -> Self {
        self.search = search;
        self
    }

    /// Marks whether the published filter set is empty.
    pub fn filters_empty(mut self, filters_empty: bool) -> Self {
        self.filters_empty = filters_empty;
        self
    }

    /// Supplies a published sort.
    pub fn sort(mut self, sort: LibrarySort) -> Self {
        self.sort = Some(sort);
        self
    }

    /// Supplies an already validated opaque cursor.
    pub fn cursor(mut self, cursor: Option<GameListCursor>) -> Self {
        self.cursor = cursor;
        self
    }

    /// Supplies a requested page size.
    pub fn page_size(mut self, page_size: u32) -> Self {
        self.page_size = Some(page_size);
        self
    }

    /// Validates and builds the currently activated query shape.
    pub fn build(self) -> Result<ListGamesQuery, QueryValidationError> {
        if self.search.is_some() || !self.filters_empty {
            return Err(QueryValidationError::Application(
                ErrorCode::ValidationInvalidArgument,
            ));
        }
        if matches!(self.scope, Some(scope) if scope != LibraryScope::All)
            || matches!(self.sort, Some(sort) if sort != LibrarySort::DisplayTitleAscending)
        {
            return Err(QueryValidationError::Application(
                ErrorCode::ValidationInvalidArgument,
            ));
        }

        Ok(ListGamesQuery {
            scope: self.scope.unwrap_or(LibraryScope::All),
            search: self.search,
            filters_empty: true,
            sort: self.sort.unwrap_or(LibrarySort::DisplayTitleAscending),
            cursor: self.cursor,
            page_size: self.page_size.unwrap_or(50).clamp(1, 500),
        })
    }
}
