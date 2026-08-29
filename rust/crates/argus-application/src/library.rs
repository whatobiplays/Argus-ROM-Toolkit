//! Focused logical-library query contracts for the initial backend seam.

use argus_domain::{
    ArtworkAssetId, AvailabilityState, ContentProvenanceRole, ContentType, GameContentPresence,
    GameId, GameLifecycle, GroupingBasis, HydrationState, IdentificationState, LibraryRootId,
    LibrarySourceId, MembershipRelationship, PlatformId,
};
use sha2::{Digest, Sha256};

use crate::{
    ErrorCode, GameContentId, IdentityDigest, PersistenceError, ResolvedArtwork, ResolvedMetadata,
    ScanRunId, SourceEntryId,
};

const MAX_CURSOR_WIRE_BYTES: usize = 4096;
/// Maximum UTF-8 byte length retained for a Library display title and cursor key.
pub const MAX_LIBRARY_DISPLAY_TITLE_BYTES: usize = 1024;
/// Maximum UTF-8 byte length retained for a Library release-date sort key.
pub const MAX_LIBRARY_RELEASE_DATE_BYTES: usize = 64;
const MAX_CURSOR_DISPLAY_TITLE_BYTES: usize = MAX_LIBRARY_DISPLAY_TITLE_BYTES;
const MAX_CURSOR_PLATFORM_ID_BYTES: usize = 64;
const MAX_CURSOR_RELEASE_DATE_BYTES: usize = MAX_LIBRARY_RELEASE_DATE_BYTES;

/// Truncates a UTF-8 Library presentation value without splitting a code point.
fn truncate_utf8_prefix(value: &str, max_bytes: usize) -> String {
    if value.len() <= max_bytes {
        return value.to_owned();
    }
    let mut end = max_bytes;
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    value[..end].to_owned()
}

/// Applies the bounded display-title projection policy used by Library rows.
pub fn bounded_library_display_title(value: &str) -> String {
    truncate_utf8_prefix(value, MAX_LIBRARY_DISPLAY_TITLE_BYTES)
}

/// Applies the bounded release-date projection policy used by Library sort keys.
pub fn bounded_library_release_date(value: &str) -> String {
    truncate_utf8_prefix(value, MAX_LIBRARY_RELEASE_DATE_BYTES)
}

/// Closed scope vocabulary for backend-owned logical-library queries.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum LibraryScope {
    /// All active logical games.
    All,
    /// Games with at least one current content association on a platform.
    Platform(PlatformId),
    /// Games with at least one current content association in a logical source.
    Source(LibrarySourceId),
    /// Games with at least one current content association in a configured root.
    LibraryRoot(LibraryRootId),
}

/// Closed primary sort-field vocabulary for logical-library pages.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum LibrarySortField {
    /// Sort by the resolved display title or local fallback title.
    DisplayTitle,
    /// Sort by the authoritative platform identifier.
    Platform,
    /// Sort by the resolved release date, with nulls always last.
    ReleaseDate,
    /// Sort by the durable projection update timestamp.
    UpdatedAt,
}

/// Explicit direction for a logical-library sort.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum LibrarySortDirection {
    /// Lowest values first, except null release dates which remain last.
    Ascending,
    /// Highest values first, except null release dates which remain last.
    Descending,
}

/// A closed field/direction pair used by backend query execution.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct LibrarySort {
    field: LibrarySortField,
    direction: LibrarySortDirection,
}

impl LibrarySort {
    /// The original baseline ordering retained for existing callers.
    #[allow(non_upper_case_globals)]
    pub const DisplayTitleAscending: Self = Self {
        field: LibrarySortField::DisplayTitle,
        direction: LibrarySortDirection::Ascending,
    };

    /// Display title descending.
    #[allow(non_upper_case_globals)]
    pub const DisplayTitleDescending: Self = Self {
        field: LibrarySortField::DisplayTitle,
        direction: LibrarySortDirection::Descending,
    };

    /// Creates one explicit sort.
    pub const fn new(field: LibrarySortField, direction: LibrarySortDirection) -> Self {
        Self { field, direction }
    }

    /// Returns the selected field.
    pub const fn field(self) -> LibrarySortField {
        self.field
    }

    /// Returns the selected direction.
    pub const fn direction(self) -> LibrarySortDirection {
        self.direction
    }
}

/// Normalized application-owned filter sets.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct LibraryFilter {
    platform_ids: Vec<PlatformId>,
    regions: Vec<String>,
    hydration_states: Vec<HydrationState>,
    availability_states: Vec<AvailabilityState>,
}

impl LibraryFilter {
    /// Validates and normalizes the four closed filter categories.
    pub fn new(
        platform_ids: Vec<PlatformId>,
        regions: Vec<String>,
        hydration_states: Vec<HydrationState>,
        availability_states: Vec<AvailabilityState>,
    ) -> Result<Self, QueryValidationError> {
        let mut platform_ids = platform_ids;
        platform_ids.sort();
        platform_ids.dedup();

        let mut normalized_regions = Vec::with_capacity(regions.len());
        for region in regions {
            let region = normalize_region(region)?;
            if !normalized_regions.contains(&region) {
                normalized_regions.push(region);
            }
        }
        normalized_regions.sort();

        let mut hydration_states = hydration_states;
        hydration_states.sort_by_key(|state| hydration_sort_key(*state));
        hydration_states.dedup();

        let mut availability_states = availability_states;
        availability_states.sort_by_key(|state| availability_sort_key(*state));
        availability_states.dedup();

        Ok(Self {
            platform_ids,
            regions: normalized_regions,
            hydration_states,
            availability_states,
        })
    }

    /// Alias that makes the value-oriented construction explicit at call sites.
    pub fn from_parts(
        platform_ids: Vec<PlatformId>,
        regions: Vec<String>,
        hydration_states: Vec<HydrationState>,
        availability_states: Vec<AvailabilityState>,
    ) -> Result<Self, QueryValidationError> {
        Self::new(platform_ids, regions, hydration_states, availability_states)
    }

    /// Returns an empty filter set.
    pub const fn empty() -> Self {
        Self {
            platform_ids: Vec::new(),
            regions: Vec::new(),
            hydration_states: Vec::new(),
            availability_states: Vec::new(),
        }
    }

    /// Returns the normalized platform filter values.
    pub fn platform_ids(&self) -> &[PlatformId] {
        &self.platform_ids
    }

    /// Returns normalized region codes.
    pub fn regions(&self) -> &[String] {
        &self.regions
    }

    /// Returns normalized hydration-state values.
    pub fn hydration_states(&self) -> &[HydrationState] {
        &self.hydration_states
    }

    /// Returns normalized availability-state values.
    pub fn availability_states(&self) -> &[AvailabilityState] {
        &self.availability_states
    }

    /// Returns whether all filter categories are empty.
    pub fn is_empty(&self) -> bool {
        self.platform_ids.is_empty()
            && self.regions.is_empty()
            && self.hydration_states.is_empty()
            && self.availability_states.is_empty()
    }
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
    query_fingerprint: String,
    sort_field: LibrarySortField,
    sort_direction: LibrarySortDirection,
    display_title: String,
    platform_id: PlatformId,
    release_date: Option<String>,
    updated_at_ms: i64,
    game_id: GameId,
}

impl GameListCursor {
    /// Builds a legacy-compatible cursor for the default title ordering.
    ///
    /// The wire value remains opaque and is accepted only for the default
    /// normalized query. New query shapes use the versioned position format
    /// produced by [`Self::from_query_position`].
    ///
    /// Cursor keys use the same bounded projection values enforced by
    /// external cursor decoding. Values supplied by a persistence adapter are
    /// reduced to those bounds before the opaque wire value is created.
    pub fn from_paging_keys(
        display_title: impl Into<String>,
        game_id: GameId,
    ) -> Result<Self, QueryValidationError> {
        let display_title = bounded_library_display_title(&display_title.into());
        let value = format!(
            "v1:{}:{}",
            encode_bounded_string(&display_title, MAX_CURSOR_DISPLAY_TITLE_BYTES)?,
            game_id
        );
        Ok(Self {
            value,
            query_fingerprint: default_query_fingerprint(),
            sort_field: LibrarySortField::DisplayTitle,
            sort_direction: LibrarySortDirection::Ascending,
            display_title,
            platform_id: PlatformId::NintendoGb,
            release_date: None,
            updated_at_ms: 0,
            game_id,
        })
    }

    /// Builds a query-bound cursor from the final row's stable sort keys.
    ///
    /// Database-backed sort keys are reduced to the same bounds accepted by
    /// [`Self::try_from_external`] before the cursor is emitted.
    #[allow(clippy::too_many_arguments)]
    pub fn from_query_position(
        query: &ListGamesQuery,
        display_title: impl Into<String>,
        platform_id: PlatformId,
        release_date: Option<String>,
        updated_at_ms: i64,
        game_id: GameId,
    ) -> Result<Self, QueryValidationError> {
        let display_title = bounded_library_display_title(&display_title.into());
        let release_date = release_date.map(|value| bounded_library_release_date(&value));
        if query.scope() == LibraryScope::All
            && query.search().is_none()
            && query.filters().is_empty()
            && query.sort() == LibrarySort::DisplayTitleAscending
        {
            return Self::from_paging_keys(display_title, game_id);
        }
        let fingerprint = query.query_fingerprint().to_owned();
        let sort_field = query.sort().field();
        let sort_direction = query.sort().direction();
        let encoded_display_title =
            encode_bounded_string(&display_title, MAX_CURSOR_DISPLAY_TITLE_BYTES)?;
        let encoded_platform_id =
            encode_bounded_string(platform_id.as_str(), MAX_CURSOR_PLATFORM_ID_BYTES)?;
        let encoded_release_date = encode_optional_string(release_date.as_deref())?;
        let value = format!(
            "v2:{}:{}:{}:{}:{}:{}:{}:{}",
            hex_encode(fingerprint.as_bytes()),
            sort_field_code(sort_field),
            sort_direction_code(sort_direction),
            encoded_display_title,
            encoded_platform_id,
            encoded_release_date,
            hex_encode(&updated_at_ms.to_be_bytes()),
            game_id,
        );
        Ok(Self {
            value,
            query_fingerprint: fingerprint,
            sort_field,
            sort_direction,
            display_title,
            platform_id,
            release_date,
            updated_at_ms,
            game_id,
        })
    }

    /// Validates an externally supplied opaque cursor without exposing its keys.
    pub fn try_from_external(value: impl Into<String>) -> Result<Self, QueryValidationError> {
        let value = value.into();
        if value.len() > MAX_CURSOR_WIRE_BYTES {
            return Err(invalid_cursor());
        }
        let Some((version, rest)) = value.split_once(':') else {
            return Err(invalid_cursor());
        };
        if version == "v1" {
            let rest = rest.to_owned();
            return Self::parse_legacy(value, &rest);
        }
        if version != "v2" {
            return Err(invalid_cursor());
        }
        let parts: Vec<&str> = rest.split(':').collect();
        if parts.len() != 8 {
            return Err(invalid_cursor());
        }
        let query_fingerprint = decode_bounded_string(parts[0], 64)?;
        if query_fingerprint.len() != 64
            || !query_fingerprint
                .bytes()
                .all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(invalid_cursor());
        }
        let sort_field = parse_sort_field_code(parts[1])?;
        let sort_direction = parse_sort_direction_code(parts[2])?;
        let display_title = decode_bounded_string(parts[3], MAX_CURSOR_DISPLAY_TITLE_BYTES)?;
        let platform = decode_bounded_string(parts[4], MAX_CURSOR_PLATFORM_ID_BYTES)?;
        let platform_id = PlatformId::try_from(platform.as_str()).map_err(|_| invalid_cursor())?;
        let release_date = decode_optional_string(parts[5])?;
        let updated_bytes = hex_decode(parts[6]).ok_or(QueryValidationError::Application(
            ErrorCode::ValidationInvalidArgument,
        ))?;
        let updated_at_ms = i64::from_be_bytes(updated_bytes.try_into().map_err(|_| {
            QueryValidationError::Application(ErrorCode::ValidationInvalidArgument)
        })?);
        let game_id = GameId::try_from(parts[7]).map_err(|_| invalid_cursor())?;
        Ok(Self {
            value,
            query_fingerprint,
            sort_field,
            sort_direction,
            display_title,
            platform_id,
            release_date,
            updated_at_ms,
            game_id,
        })
    }

    fn parse_legacy(value: String, rest: &str) -> Result<Self, QueryValidationError> {
        let Some((title_hex, id)) = rest.split_once(':') else {
            return Err(invalid_cursor());
        };
        let display_title = decode_bounded_string(title_hex, MAX_CURSOR_DISPLAY_TITLE_BYTES)?;
        let game_id = GameId::try_from(id).map_err(|_| invalid_cursor())?;
        Ok(Self {
            value,
            query_fingerprint: default_query_fingerprint(),
            sort_field: LibrarySortField::DisplayTitle,
            sort_direction: LibrarySortDirection::Ascending,
            display_title,
            platform_id: PlatformId::NintendoGb,
            release_date: None,
            updated_at_ms: 0,
            game_id,
        })
    }

    /// Returns the normalized query fingerprint embedded in this cursor.
    pub fn query_fingerprint(&self) -> &str {
        &self.query_fingerprint
    }

    /// Returns the field used to create this cursor.
    pub const fn sort_field(&self) -> LibrarySortField {
        self.sort_field
    }

    /// Returns the direction used to create this cursor.
    pub const fn sort_direction(&self) -> LibrarySortDirection {
        self.sort_direction
    }

    /// Returns the platform sort key.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns the optional release-date sort key.
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }

    /// Returns the update-time sort key.
    pub const fn updated_at_ms(&self) -> i64 {
        self.updated_at_ms
    }
}

/// Safe row projection used by the focused logical-library list.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameLibraryRow {
    game_id: GameId,
    display_title: String,
    platform_id: PlatformId,
    presentation_region: Option<String>,
    selected_cover_asset_id: Option<ArtworkAssetId>,
    release_date: Option<String>,
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
            display_title: bounded_library_display_title(&display_title.into()),
            platform_id,
            presentation_region: None,
            selected_cover_asset_id: None,
            release_date: None,
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
        Self::from_persisted_with_presentation(
            game_id,
            display_title,
            platform_id,
            None,
            None,
            None,
            hydration_state,
            availability_state,
            content_count,
            source_count,
            updated_at_ms,
        )
    }

    /// Creates a row with all card/list presentation facts from persistence.
    #[allow(clippy::too_many_arguments)]
    pub fn from_persisted_with_presentation(
        game_id: GameId,
        display_title: impl Into<String>,
        platform_id: PlatformId,
        presentation_region: Option<String>,
        selected_cover_asset_id: Option<ArtworkAssetId>,
        release_date: Option<String>,
        hydration_state: HydrationState,
        availability_state: AvailabilityState,
        content_count: u32,
        source_count: u32,
        updated_at_ms: i64,
    ) -> Self {
        let display_title = bounded_library_display_title(&display_title.into());
        let release_date = release_date.map(|value| bounded_library_release_date(&value));
        Self {
            game_id,
            display_title,
            platform_id,
            presentation_region,
            selected_cover_asset_id,
            release_date,
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

    /// Returns the selected presentation region, if one is available.
    pub fn presentation_region(&self) -> Option<&str> {
        self.presentation_region.as_deref()
    }

    /// Returns the selected cover asset identity, if one is available.
    pub const fn selected_cover_asset_id(&self) -> Option<ArtworkAssetId> {
        self.selected_cover_asset_id
    }

    /// Returns the resolved release date used by the backend sort projection.
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }

    /// Returns the release-date key without exposing it through bridge DTOs.
    pub fn release_date_for_cursor(&self) -> Option<String> {
        self.release_date.clone()
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
    sources: Vec<GameContentSourceSummary>,
}

/// Safe context for one current physical copy of a logical content member.
///
/// The projection intentionally carries display facts and stable identities
/// only. Provider locators and raw filesystem paths remain infrastructure
/// concerns and are never part of a Game detail response.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameContentSourceSummary {
    source_entry_id: SourceEntryId,
    library_source_id: LibrarySourceId,
    source_display_name: String,
    library_root_id: LibraryRootId,
    root_display_name: String,
    safe_location_presentation: String,
}

impl GameContentSourceSummary {
    /// Creates one safe source/root display projection.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        source_entry_id: SourceEntryId,
        library_source_id: LibrarySourceId,
        source_display_name: impl Into<String>,
        library_root_id: LibraryRootId,
        root_display_name: impl Into<String>,
        safe_location_presentation: impl Into<String>,
    ) -> Self {
        Self {
            source_entry_id,
            library_source_id,
            source_display_name: source_display_name.into(),
            library_root_id,
            root_display_name: root_display_name.into(),
            safe_location_presentation: safe_location_presentation.into(),
        }
    }

    /// Returns the stable physical source-entry identity.
    pub const fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the logical source identity.
    pub const fn library_source_id(&self) -> LibrarySourceId {
        self.library_source_id
    }

    /// Returns the safe source display name.
    pub fn source_display_name(&self) -> &str {
        &self.source_display_name
    }

    /// Returns the configured root identity.
    pub const fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the safe root display name.
    pub fn root_display_name(&self) -> &str {
        &self.root_display_name
    }

    /// Returns the backend-produced safe location presentation.
    pub fn safe_location_presentation(&self) -> &str {
        &self.safe_location_presentation
    }
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

/// Rejects a provenance projection that mixes provider and derived evidence.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProvenanceVersionError {
    /// Both provider-native and derived fingerprints were supplied.
    BothFingerprintsPresent,
}

/// Exact proving provenance without exposing filesystem locations.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentProvenanceSummary {
    source_entry_id: SourceEntryId,
    association_key: String,
    source_fingerprint: Option<String>,
    derived_fingerprint: Option<String>,
    last_observed_scan_id: ScanRunId,
    members: Vec<ContentProvenanceMemberSummary>,
}

impl ContentProvenanceSummary {
    /// Creates one exact persisted provenance summary.
    pub fn new(
        source_entry_id: SourceEntryId,
        association_key: impl Into<String>,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self::new_with_version(
            source_entry_id,
            association_key,
            source_fingerprint,
            None,
            last_observed_scan_id,
        )
        .expect("provider-only provenance is always valid")
    }

    /// Creates one exact persisted provenance summary with either provider or
    /// derived version evidence.
    pub fn new_with_version(
        source_entry_id: SourceEntryId,
        association_key: impl Into<String>,
        source_fingerprint: Option<String>,
        derived_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Result<Self, ProvenanceVersionError> {
        if source_fingerprint.is_some() && derived_fingerprint.is_some() {
            return Err(ProvenanceVersionError::BothFingerprintsPresent);
        }
        let association_key = association_key.into();
        Ok(Self {
            source_entry_id,
            association_key: association_key.clone(),
            source_fingerprint: source_fingerprint.clone(),
            derived_fingerprint: derived_fingerprint.clone(),
            last_observed_scan_id,
            members: vec![
                ContentProvenanceMemberSummary::new_with_version(
                    ContentProvenanceRole::Primary,
                    Some(association_key),
                    source_entry_id,
                    source_fingerprint,
                    derived_fingerprint,
                    last_observed_scan_id,
                )
                .expect("summary validates mutually exclusive provenance"),
            ],
        })
    }

    /// Creates a projection from every normalized exact provenance member.
    ///
    /// The scalar accessors remain backed by the primary member so existing
    /// consumers can upgrade without losing the older projection shape.
    pub fn from_members(members: Vec<ContentProvenanceMemberSummary>) -> Option<Self> {
        let primary = members
            .iter()
            .find(|member| member.role() == ContentProvenanceRole::Primary)
            .or_else(|| members.first())?;
        Some(Self {
            source_entry_id: primary.source_entry_id(),
            association_key: primary.association_key().unwrap_or("").to_owned(),
            source_fingerprint: primary.source_fingerprint().map(str::to_owned),
            derived_fingerprint: primary.derived_fingerprint().map(str::to_owned),
            last_observed_scan_id: primary.last_observed_scan_id(),
            members,
        })
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

    /// Returns the derived source-version fingerprint, if this proof is derived.
    pub fn derived_fingerprint(&self) -> Option<&str> {
        self.derived_fingerprint.as_deref()
    }

    /// Returns the scan observation version.
    pub const fn last_observed_scan_id(&self) -> ScanRunId {
        self.last_observed_scan_id
    }

    /// Returns all exact provenance members in persistence order.
    pub fn members(&self) -> &[ContentProvenanceMemberSummary] {
        &self.members
    }
}

/// Safe read projection for one normalized identity-provenance member.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentProvenanceMemberSummary {
    role: ContentProvenanceRole,
    association_key: Option<String>,
    source_entry_id: SourceEntryId,
    source_fingerprint: Option<String>,
    derived_fingerprint: Option<String>,
    last_observed_scan_id: ScanRunId,
}

impl ContentProvenanceMemberSummary {
    /// Creates one bounded provenance-member projection.
    pub fn new(
        role: ContentProvenanceRole,
        association_key: Option<String>,
        source_entry_id: SourceEntryId,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self::new_with_version(
            role,
            association_key,
            source_entry_id,
            source_fingerprint,
            None,
            last_observed_scan_id,
        )
        .expect("provider-only provenance member is always valid")
    }

    /// Creates one bounded provenance-member projection with either provider
    /// or derived version evidence.
    pub fn new_with_version(
        role: ContentProvenanceRole,
        association_key: Option<String>,
        source_entry_id: SourceEntryId,
        source_fingerprint: Option<String>,
        derived_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Result<Self, ProvenanceVersionError> {
        if source_fingerprint.is_some() && derived_fingerprint.is_some() {
            return Err(ProvenanceVersionError::BothFingerprintsPresent);
        }
        Ok(Self {
            role,
            association_key,
            source_entry_id,
            source_fingerprint,
            derived_fingerprint,
            last_observed_scan_id,
        })
    }

    /// Returns the exact provenance role.
    pub const fn role(&self) -> ContentProvenanceRole {
        self.role
    }

    /// Returns the optional derived-unit association key.
    pub fn association_key(&self) -> Option<&str> {
        self.association_key.as_deref()
    }

    /// Returns the proving source identity.
    pub const fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the observed source fingerprint.
    pub fn source_fingerprint(&self) -> Option<&str> {
        self.source_fingerprint.as_deref()
    }

    /// Returns the derived source-version fingerprint, if this member is derived.
    pub fn derived_fingerprint(&self) -> Option<&str> {
        self.derived_fingerprint.as_deref()
    }

    /// Returns the scan observation used by the proof.
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
            sources: Vec::new(),
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
            sources: Vec::new(),
        }
    }

    /// Attaches current safe source/root display context.
    pub fn with_sources(mut self, sources: Vec<GameContentSourceSummary>) -> Self {
        self.sources = sources;
        self
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

    /// Returns current physical-copy source context.
    pub fn sources(&self) -> &[GameContentSourceSummary] {
        &self.sources
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
    /// Lists one bounded page using backend-owned query semantics.
    fn list_games(&mut self, query: &ListGamesQuery) -> Result<GameLibraryPage, PersistenceError>;

    /// Returns facet counts for the query scope/search/filter shape.
    fn get_library_facets(
        &mut self,
        query: &LibraryFacetQuery,
    ) -> Result<LibraryFacets, PersistenceError>;

    /// Retrieves one focused logical game result.
    fn get_game(&mut self, game_id: GameId) -> Result<GetGameResult, PersistenceError>;
}

/// One platform facet bucket.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlatformFacetBucket {
    platform_id: PlatformId,
    count: u32,
}

impl PlatformFacetBucket {
    /// Creates one platform facet bucket.
    pub const fn new(platform_id: PlatformId, count: u32) -> Self {
        Self { platform_id, count }
    }

    /// Returns the platform value.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns the bounded count.
    pub const fn count(&self) -> u32 {
        self.count
    }
}

/// One normalized region facet bucket.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RegionFacetBucket {
    region: String,
    count: u32,
}

impl RegionFacetBucket {
    /// Creates one region facet bucket.
    pub fn new(region: impl Into<String>, count: u32) -> Self {
        Self {
            region: region.into(),
            count,
        }
    }

    /// Returns the region code.
    pub fn region(&self) -> &str {
        &self.region
    }

    /// Returns the bounded count.
    pub const fn count(&self) -> u32 {
        self.count
    }
}

/// One hydration-state facet bucket.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HydrationStateFacetBucket {
    hydration_state: HydrationState,
    count: u32,
}

impl HydrationStateFacetBucket {
    /// Creates one hydration-state facet bucket.
    pub const fn new(hydration_state: HydrationState, count: u32) -> Self {
        Self {
            hydration_state,
            count,
        }
    }

    /// Returns the hydration state.
    pub const fn hydration_state(&self) -> HydrationState {
        self.hydration_state
    }

    /// Returns the bounded count.
    pub const fn count(&self) -> u32 {
        self.count
    }
}

/// One availability-state facet bucket.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AvailabilityStateFacetBucket {
    availability_state: AvailabilityState,
    count: u32,
}

impl AvailabilityStateFacetBucket {
    /// Creates one availability-state facet bucket.
    pub const fn new(availability_state: AvailabilityState, count: u32) -> Self {
        Self {
            availability_state,
            count,
        }
    }

    /// Returns the availability state.
    pub const fn availability_state(&self) -> AvailabilityState {
        self.availability_state
    }

    /// Returns the bounded count.
    pub const fn count(&self) -> u32 {
        self.count
    }
}

/// All facet categories for one normalized Library scope/search/filter shape.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryFacets {
    platforms: Vec<PlatformFacetBucket>,
    regions: Vec<RegionFacetBucket>,
    hydration_states: Vec<HydrationStateFacetBucket>,
    availability_states: Vec<AvailabilityStateFacetBucket>,
}

impl LibraryFacets {
    /// Creates a complete facet projection.
    pub fn new(
        platforms: Vec<PlatformFacetBucket>,
        regions: Vec<RegionFacetBucket>,
        hydration_states: Vec<HydrationStateFacetBucket>,
        availability_states: Vec<AvailabilityStateFacetBucket>,
    ) -> Self {
        Self {
            platforms,
            regions,
            hydration_states,
            availability_states,
        }
    }

    /// Returns platform buckets in deterministic order.
    pub fn platforms(&self) -> &[PlatformFacetBucket] {
        &self.platforms
    }

    /// Returns region buckets in deterministic order.
    pub fn regions(&self) -> &[RegionFacetBucket] {
        &self.regions
    }

    /// Returns hydration-state buckets in deterministic order.
    pub fn hydration_states(&self) -> &[HydrationStateFacetBucket] {
        &self.hydration_states
    }

    /// Returns availability-state buckets in deterministic order.
    pub fn availability_states(&self) -> &[AvailabilityStateFacetBucket] {
        &self.availability_states
    }
}

/// Scope/search/filter input for facet counts. It deliberately has no cursor,
/// page size, or sort because those concepts do not affect facet counts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryFacetQuery {
    scope: LibraryScope,
    search: Option<String>,
    filters: LibraryFilter,
    query_fingerprint: String,
}

impl LibraryFacetQuery {
    /// Validates and normalizes one facet query.
    pub fn new(
        scope: LibraryScope,
        search: Option<String>,
        filters: LibraryFilter,
    ) -> Result<Self, QueryValidationError> {
        let search = normalize_search(search)?;
        let query_fingerprint = facet_query_fingerprint(scope, search.as_deref(), &filters);
        Ok(Self {
            scope,
            search,
            filters,
            query_fingerprint,
        })
    }

    /// Returns the scope.
    pub const fn scope(&self) -> LibraryScope {
        self.scope
    }

    /// Returns the normalized search value.
    pub fn search(&self) -> Option<&str> {
        self.search.as_deref()
    }

    /// Returns normalized filters.
    pub fn filters(&self) -> &LibraryFilter {
        &self.filters
    }

    /// Returns the stable facet query fingerprint.
    pub fn query_fingerprint(&self) -> &str {
        &self.query_fingerprint
    }
}

/// Normalized application-owned logical-library list request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ListGamesQuery {
    scope: LibraryScope,
    search: Option<String>,
    filters: LibraryFilter,
    sort: LibrarySort,
    cursor: Option<GameListCursor>,
    page_size: u32,
    query_fingerprint: String,
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

fn normalize_region(value: String) -> Result<String, QueryValidationError> {
    let value = value.trim().to_ascii_lowercase();
    if value.is_empty()
        || value.len() > 32
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err(QueryValidationError::Application(
            ErrorCode::ValidationInvalidArgument,
        ));
    }
    Ok(value)
}

fn normalize_search(value: Option<String>) -> Result<Option<String>, QueryValidationError> {
    let Some(value) = value else {
        return Ok(None);
    };
    let value = value.trim().to_owned();
    if value.is_empty() {
        return Ok(None);
    }
    if value.len() > 256 || value.chars().any(char::is_control) {
        return Err(QueryValidationError::Application(
            ErrorCode::ValidationInvalidArgument,
        ));
    }
    Ok(Some(value.to_ascii_lowercase()))
}

fn hydration_sort_key(value: HydrationState) -> u8 {
    match value {
        HydrationState::Hydrated => 0,
        HydrationState::PartiallyHydrated => 1,
        HydrationState::Unmatched => 2,
        HydrationState::Refreshing => 3,
    }
}

fn availability_sort_key(value: AvailabilityState) -> u8 {
    match value {
        AvailabilityState::Available => 0,
        AvailabilityState::PartiallyUnavailable => 1,
        AvailabilityState::Unavailable => 2,
        AvailabilityState::InactiveOrphan => 3,
    }
}

fn sort_field_code(value: LibrarySortField) -> &'static str {
    match value {
        LibrarySortField::DisplayTitle => "01",
        LibrarySortField::Platform => "02",
        LibrarySortField::ReleaseDate => "03",
        LibrarySortField::UpdatedAt => "04",
    }
}

fn parse_sort_field_code(value: &str) -> Result<LibrarySortField, QueryValidationError> {
    match value {
        "01" => Ok(LibrarySortField::DisplayTitle),
        "02" => Ok(LibrarySortField::Platform),
        "03" => Ok(LibrarySortField::ReleaseDate),
        "04" => Ok(LibrarySortField::UpdatedAt),
        _ => Err(QueryValidationError::Application(
            ErrorCode::ValidationInvalidArgument,
        )),
    }
}

fn sort_direction_code(value: LibrarySortDirection) -> &'static str {
    match value {
        LibrarySortDirection::Ascending => "01",
        LibrarySortDirection::Descending => "02",
    }
}

fn parse_sort_direction_code(value: &str) -> Result<LibrarySortDirection, QueryValidationError> {
    match value {
        "01" => Ok(LibrarySortDirection::Ascending),
        "02" => Ok(LibrarySortDirection::Descending),
        _ => Err(QueryValidationError::Application(
            ErrorCode::ValidationInvalidArgument,
        )),
    }
}

const fn invalid_cursor() -> QueryValidationError {
    QueryValidationError::Application(ErrorCode::ValidationInvalidArgument)
}

fn decode_bounded_string(value: &str, max_bytes: usize) -> Result<String, QueryValidationError> {
    if value.len() > max_bytes.saturating_mul(2) {
        return Err(invalid_cursor());
    }
    let bytes = hex_decode(value).ok_or(invalid_cursor())?;
    if bytes.len() > max_bytes {
        return Err(invalid_cursor());
    }
    String::from_utf8(bytes).map_err(|_| invalid_cursor())
}

fn encode_bounded_string(value: &str, max_bytes: usize) -> Result<String, QueryValidationError> {
    if value.len() > max_bytes {
        return Err(invalid_cursor());
    }
    Ok(hex_encode(value.as_bytes()))
}

fn encode_optional_string(value: Option<&str>) -> Result<String, QueryValidationError> {
    match value {
        Some(value) => Ok(format!(
            "01{}",
            encode_bounded_string(value, MAX_CURSOR_RELEASE_DATE_BYTES)?
        )),
        None => Ok("00".to_owned()),
    }
}

fn decode_optional_string(value: &str) -> Result<Option<String>, QueryValidationError> {
    if value == "00" {
        return Ok(None);
    }
    let Some(value) = value.strip_prefix("01") else {
        return Err(invalid_cursor());
    };
    decode_bounded_string(value, MAX_CURSOR_RELEASE_DATE_BYTES).map(Some)
}

fn scope_key(scope: LibraryScope) -> String {
    match scope {
        LibraryScope::All => "all".to_owned(),
        LibraryScope::Platform(platform) => format!("platform:{}", platform.as_str()),
        LibraryScope::Source(source) => format!("source:{source}"),
        LibraryScope::LibraryRoot(root) => format!("root:{root}"),
    }
}

fn filter_key(filters: &LibraryFilter) -> String {
    let platforms = filters
        .platform_ids()
        .iter()
        .map(|value| value.as_str())
        .collect::<Vec<_>>()
        .join(",");
    let regions = filters.regions().join(",");
    let hydration = filters
        .hydration_states()
        .iter()
        .map(|value| hydration_sort_key(*value).to_string())
        .collect::<Vec<_>>()
        .join(",");
    let availability = filters
        .availability_states()
        .iter()
        .map(|value| availability_sort_key(*value).to_string())
        .collect::<Vec<_>>()
        .join(",");
    format!(
        "platform={platforms}|region={regions}|hydration={hydration}|availability={availability}"
    )
}

fn list_query_fingerprint(
    scope: LibraryScope,
    search: Option<&str>,
    filters: &LibraryFilter,
    sort: LibrarySort,
) -> String {
    fingerprint(&format!(
        "list|scope={}|search={}|{}|sort={}:{}",
        scope_key(scope),
        search.unwrap_or_default(),
        filter_key(filters),
        sort_field_code(sort.field()),
        sort_direction_code(sort.direction()),
    ))
}

fn facet_query_fingerprint(
    scope: LibraryScope,
    search: Option<&str>,
    filters: &LibraryFilter,
) -> String {
    fingerprint(&format!(
        "facets|scope={}|search={}|{}",
        scope_key(scope),
        search.unwrap_or_default(),
        filter_key(filters),
    ))
}

fn fingerprint(value: &str) -> String {
    hex_encode(Sha256::digest(value.as_bytes()).as_slice())
}

fn default_query_fingerprint() -> String {
    list_query_fingerprint(
        LibraryScope::All,
        None,
        &LibraryFilter::empty(),
        LibrarySort::DisplayTitleAscending,
    )
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

    /// Returns the normalized filter set.
    pub fn filters(&self) -> &LibraryFilter {
        &self.filters
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
    pub fn filters_empty(&self) -> bool {
        self.filters.is_empty()
    }

    /// Returns the normalized query fingerprint used for cursor binding.
    pub fn query_fingerprint(&self) -> &str {
        &self.query_fingerprint
    }
}

/// Builder for the normalized logical-library list request.
pub struct ListGamesQueryBuilder {
    scope: Option<LibraryScope>,
    search: Option<String>,
    filters: LibraryFilter,
    legacy_filters_nonempty: bool,
    sort: Option<LibrarySort>,
    cursor: Option<GameListCursor>,
    page_size: Option<u32>,
}

impl Default for ListGamesQueryBuilder {
    fn default() -> Self {
        Self {
            scope: None,
            search: None,
            filters: LibraryFilter::empty(),
            legacy_filters_nonempty: false,
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

    /// Supplies a search term.
    pub fn search(mut self, search: Option<String>) -> Self {
        self.search = search;
        self
    }

    /// Supplies the four closed filter categories.
    pub fn filters(mut self, filters: LibraryFilter) -> Self {
        self.legacy_filters_nonempty = false;
        self.filters = filters;
        self
    }

    /// Retains the old structural marker for callers compiled against the
    /// baseline query API. A false marker without actual values is invalid.
    pub fn filters_empty(mut self, filters_empty: bool) -> Self {
        self.legacy_filters_nonempty = !filters_empty;
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

    /// Validates and builds a normalized query shape.
    pub fn build(self) -> Result<ListGamesQuery, QueryValidationError> {
        if self.legacy_filters_nonempty && self.filters.is_empty() {
            return Err(QueryValidationError::Application(
                ErrorCode::ValidationInvalidArgument,
            ));
        }
        let scope = self.scope.unwrap_or(LibraryScope::All);
        let search = normalize_search(self.search)?;
        let filters = self.filters;
        let sort = self.sort.unwrap_or(LibrarySort::DisplayTitleAscending);
        let query_fingerprint = list_query_fingerprint(scope, search.as_deref(), &filters, sort);
        if self
            .cursor
            .as_ref()
            .is_some_and(|cursor| cursor.query_fingerprint() != query_fingerprint)
        {
            return Err(QueryValidationError::Application(
                ErrorCode::ValidationInvalidArgument,
            ));
        }

        Ok(ListGamesQuery {
            scope,
            search,
            filters,
            sort,
            cursor: self.cursor,
            page_size: self.page_size.unwrap_or(50).clamp(1, 500),
            query_fingerprint,
        })
    }
}
