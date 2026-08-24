use std::collections::{BTreeMap, BTreeSet};

use argus_domain::{ArtworkAssetId, GameId};

use crate::PersistenceError;
use crate::ProviderId;

/// Canonical artwork taxonomy used by resolver policy.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum ArtworkType {
    /// Front cover artwork.
    CoverFront,
    /// Back cover artwork.
    CoverBack,
    /// Spine artwork.
    CoverSpine,
    /// In-game screenshot.
    Screenshot,
    /// Title-screen artwork.
    TitleScreen,
    /// Provider logo artwork.
    Logo,
    /// Small application icon artwork.
    Icon,
    /// Background artwork.
    Background,
    /// Wide banner artwork.
    Banner,
    /// Manual or booklet artwork.
    Manual,
}

impl ArtworkType {
    /// Returns the stable persisted artwork type identifier.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::CoverFront => "cover_front",
            Self::CoverBack => "cover_back",
            Self::CoverSpine => "cover_spine",
            Self::Screenshot => "screenshot",
            Self::TitleScreen => "title_screen",
            Self::Logo => "logo",
            Self::Icon => "icon",
            Self::Background => "background",
            Self::Banner => "banner",
            Self::Manual => "manual",
        }
    }
}

/// Normalized provider artwork discovery result.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtworkCandidate {
    provider_id: ProviderId,
    external_asset_id: String,
    artwork_type: ArtworkType,
    source: String,
    provider_revision: u64,
    region: Option<String>,
    language: Option<String>,
    width: Option<u32>,
    height: Option<u32>,
    quality: u8,
    discovered_at: i64,
}

/// Durable artwork source location kind.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ArtworkSource {
    /// URL safe to retain without credentials or signed query material.
    CredentialFreeUrl(String),
    /// Opaque provider-native locator resolved only by a transient session.
    ProviderAssetLocator(String),
}

impl ArtworkSource {
    /// Returns the persisted source kind and value without resolving it.
    pub fn kind_and_value(&self) -> (&'static str, &str) {
        match self {
            Self::CredentialFreeUrl(value) => ("credential_free_url", value),
            Self::ProviderAssetLocator(value) => ("provider_asset_locator", value),
        }
    }
}

/// Durable normalized artwork discovery reference.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtworkReference {
    reference_id: String,
    provider_id: ProviderId,
    external_game_id: String,
    artwork_type: ArtworkType,
    source: ArtworkSource,
    width: Option<u32>,
    height: Option<u32>,
    format: Option<String>,
    mime_type: Option<String>,
    region: Option<String>,
    language: Option<String>,
    provider_revision: u64,
    quality: u8,
    discovered_at: i64,
}

impl ArtworkReference {
    /// Creates one durable reference without exposing transient transport URLs.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        reference_id: impl Into<String>,
        provider_id: ProviderId,
        external_game_id: impl Into<String>,
        artwork_type: ArtworkType,
        source: ArtworkSource,
        width: Option<u32>,
        height: Option<u32>,
        format: Option<String>,
        mime_type: Option<String>,
        region: Option<String>,
        language: Option<String>,
        provider_revision: u64,
    ) -> Self {
        Self {
            reference_id: reference_id.into(),
            provider_id,
            external_game_id: external_game_id.into(),
            artwork_type,
            source,
            width,
            height,
            format,
            mime_type,
            region,
            language,
            provider_revision,
            quality: 0,
            discovered_at: 0,
        }
    }

    /// Returns the durable reference identity.
    pub fn reference_id(&self) -> &str {
        &self.reference_id
    }

    /// Returns the provider identity.
    pub const fn provider_id(&self) -> ProviderId {
        self.provider_id
    }

    /// Returns the native game identity.
    pub fn external_game_id(&self) -> &str {
        &self.external_game_id
    }

    /// Returns the canonical artwork type.
    pub const fn artwork_type(&self) -> ArtworkType {
        self.artwork_type
    }

    /// Returns the durable source locator kind.
    pub fn source(&self) -> &ArtworkSource {
        &self.source
    }

    /// Returns the provider revision.
    pub const fn provider_revision(&self) -> u64 {
        self.provider_revision
    }

    /// Returns optional discovered width.
    pub const fn width(&self) -> Option<u32> {
        self.width
    }

    /// Returns optional discovered height.
    pub const fn height(&self) -> Option<u32> {
        self.height
    }

    /// Returns optional declared media type.
    pub fn mime_type(&self) -> Option<&str> {
        self.mime_type.as_deref()
    }

    /// Returns the optional declared format.
    pub fn format(&self) -> Option<&str> {
        self.format.as_deref()
    }

    /// Returns the optional region.
    pub fn region(&self) -> Option<&str> {
        self.region.as_deref()
    }

    /// Returns the optional language.
    pub fn language(&self) -> Option<&str> {
        self.language.as_deref()
    }

    /// Adds an adapter-understood quality/completeness score.
    pub fn with_quality(mut self, quality: u8) -> Self {
        self.quality = quality;
        self
    }

    /// Returns the adapter-understood quality/completeness score.
    pub const fn quality(&self) -> u8 {
        self.quality
    }

    /// Returns the durable provider observation timestamp.
    pub const fn discovered_at(&self) -> i64 {
        self.discovered_at
    }

    /// Adds the provider observation timestamp used for deterministic freshness.
    pub const fn with_discovered_at(mut self, discovered_at: i64) -> Self {
        self.discovered_at = discovered_at;
        self
    }
}

/// Game-level selected artwork relationship.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedArtwork {
    game_id: GameId,
    artwork_type: ArtworkType,
    reference_id: String,
    asset_id: Option<ArtworkAssetId>,
    ordering: u32,
    selection_reason: String,
    resolution_revision: u64,
    resolved_at: i64,
}

impl ResolvedArtwork {
    /// Creates one selected artwork relationship.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        game_id: GameId,
        artwork_type: ArtworkType,
        reference_id: impl Into<String>,
        asset_id: Option<ArtworkAssetId>,
        ordering: u32,
        selection_reason: impl Into<String>,
        resolution_revision: u64,
        resolved_at: i64,
    ) -> Self {
        Self {
            game_id,
            artwork_type,
            reference_id: reference_id.into(),
            asset_id,
            ordering,
            selection_reason: selection_reason.into(),
            resolution_revision,
            resolved_at,
        }
    }

    /// Returns the owning Game.
    pub const fn game_id(&self) -> GameId {
        self.game_id
    }

    /// Returns the canonical artwork type.
    pub const fn artwork_type(&self) -> ArtworkType {
        self.artwork_type
    }

    /// Returns the selected reference.
    pub fn reference_id(&self) -> &str {
        &self.reference_id
    }

    /// Returns the immutable local asset, if downloaded.
    pub const fn asset_id(&self) -> Option<ArtworkAssetId> {
        self.asset_id
    }

    /// Returns the ordered gallery position.
    pub const fn ordering(&self) -> u32 {
        self.ordering
    }

    /// Returns the deterministic policy explanation retained with the choice.
    pub fn selection_reason(&self) -> &str {
        &self.selection_reason
    }

    /// Returns the artwork-resolution policy revision.
    pub const fn resolution_revision(&self) -> u64 {
        self.resolution_revision
    }

    /// Returns the resolution timestamp supplied by the caller.
    pub const fn resolved_at(&self) -> i64 {
        self.resolved_at
    }
}

/// Immutable content-addressed artwork asset metadata.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtworkAsset {
    asset_id: ArtworkAssetId,
    width: u32,
    height: u32,
    mime_type: String,
    byte_size: u64,
}

impl ArtworkAsset {
    /// Creates metadata for bytes already persisted by the object store.
    pub fn new(
        asset_id: ArtworkAssetId,
        width: u32,
        height: u32,
        mime_type: impl Into<String>,
        byte_size: u64,
    ) -> Self {
        Self {
            asset_id,
            width,
            height,
            mime_type: mime_type.into(),
            byte_size,
        }
    }

    /// Returns the BLAKE3-derived identity.
    pub const fn asset_id(&self) -> ArtworkAssetId {
        self.asset_id
    }

    /// Returns the decoded width.
    pub const fn width(&self) -> u32 {
        self.width
    }

    /// Returns the decoded height.
    pub const fn height(&self) -> u32 {
        self.height
    }

    /// Returns the safe MIME type.
    pub fn mime_type(&self) -> &str {
        &self.mime_type
    }

    /// Returns the exact byte size.
    pub const fn byte_size(&self) -> u64 {
        self.byte_size
    }
}

/// Transaction-bound artwork persistence port.
pub trait ArtworkRepository {
    /// Persists one discovered artwork reference.
    fn save_reference(&mut self, reference: &ArtworkReference) -> Result<(), PersistenceError>;

    /// Persists one Game-level artwork selection.
    fn save_resolved_artwork(&mut self, resolved: &ResolvedArtwork)
    -> Result<(), PersistenceError>;

    /// Replaces the complete current Game-level artwork selection in one
    /// transaction. An empty slice deliberately removes all prior selections
    /// so disabled providers or changed preferences cannot leave stale rows.
    fn replace_resolved_artwork_for_game(
        &mut self,
        game_id: GameId,
        resolved: &[ResolvedArtwork],
    ) -> Result<(), PersistenceError>;

    /// Persists one immutable artwork asset metadata row.
    fn save_asset(&mut self, asset: &ArtworkAsset) -> Result<(), PersistenceError>;

    /// Reads references for one provider-native game identity for local-only
    /// artwork resolution after external work has committed.
    fn references_for_external_game(
        &mut self,
        _provider_id: ProviderId,
        _external_game_id: &str,
    ) -> Result<Vec<ArtworkReference>, PersistenceError> {
        Err(PersistenceError::Internal)
    }

    /// Reads the latest Game-level artwork selections.
    fn resolved_artwork_for_game(
        &mut self,
        _game_id: GameId,
    ) -> Result<Vec<ResolvedArtwork>, PersistenceError> {
        Ok(Vec::new())
    }
}

impl ArtworkCandidate {
    /// Creates one candidate with an opaque provider source locator.
    pub fn new(
        provider_id: ProviderId,
        external_asset_id: impl Into<String>,
        artwork_type: ArtworkType,
        source: impl Into<String>,
        provider_revision: u64,
    ) -> Self {
        Self {
            provider_id,
            external_asset_id: external_asset_id.into(),
            artwork_type,
            source: source.into(),
            provider_revision,
            region: None,
            language: None,
            width: None,
            height: None,
            quality: 0,
            discovered_at: 0,
        }
    }

    /// Adds provider-understood locale, dimension, and quality facts.
    pub fn with_details(
        mut self,
        region: Option<impl Into<String>>,
        language: Option<impl Into<String>>,
        width: Option<u32>,
        height: Option<u32>,
        quality: u8,
    ) -> Self {
        self.region = region.map(Into::into);
        self.language = language.map(Into::into);
        self.width = width;
        self.height = height;
        self.quality = quality;
        self
    }

    /// Returns the provider identity.
    pub const fn provider_id(&self) -> ProviderId {
        self.provider_id
    }

    /// Returns the provider-native asset identity.
    pub fn external_asset_id(&self) -> &str {
        &self.external_asset_id
    }

    /// Returns the canonical artwork type.
    pub const fn artwork_type(&self) -> ArtworkType {
        self.artwork_type
    }

    /// Returns the opaque source locator for infrastructure download.
    pub fn source(&self) -> &str {
        &self.source
    }

    /// Returns the provider record revision.
    pub const fn provider_revision(&self) -> u64 {
        self.provider_revision
    }

    /// Returns the provider-declared region, if any.
    pub fn region(&self) -> Option<&str> {
        self.region.as_deref()
    }

    /// Returns the provider-declared language, if any.
    pub fn language(&self) -> Option<&str> {
        self.language.as_deref()
    }

    /// Returns the provider-declared width, if any.
    pub const fn width(&self) -> Option<u32> {
        self.width
    }

    /// Returns the provider-declared height, if any.
    pub const fn height(&self) -> Option<u32> {
        self.height
    }

    /// Returns the adapter-understood quality/completeness score.
    pub const fn quality(&self) -> u8 {
        self.quality
    }

    /// Returns the provider observation timestamp used for freshness.
    pub const fn discovered_at(&self) -> i64 {
        self.discovered_at
    }

    /// Adds the provider observation timestamp used for deterministic freshness.
    pub const fn with_discovered_at(mut self, discovered_at: i64) -> Self {
        self.discovered_at = discovered_at;
        self
    }
}

/// Local-only artwork resolver settings.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtworkResolutionPolicy {
    enabled_providers: BTreeSet<ProviderId>,
    max_screenshots: usize,
    preferred_regions: Vec<String>,
    preferred_languages: Vec<String>,
}

impl Default for ArtworkResolutionPolicy {
    fn default() -> Self {
        Self {
            enabled_providers: [
                ProviderId::Playmatch,
                ProviderId::GameTdb,
                ProviderId::SteamGridDb,
            ]
            .into_iter()
            .collect(),
            max_screenshots: 12,
            preferred_regions: Vec::new(),
            preferred_languages: Vec::new(),
        }
    }
}

impl ArtworkResolutionPolicy {
    /// Disables one provider for subsequent local resolution.
    pub fn set_enabled(&mut self, provider_id: ProviderId, enabled: bool) {
        if enabled {
            self.enabled_providers.insert(provider_id);
        } else {
            self.enabled_providers.remove(&provider_id);
        }
    }

    /// Sets the ordered locale preferences used by artwork resolution.
    pub fn set_locale_preferences<R, L>(&mut self, regions: R, languages: L)
    where
        R: IntoIterator,
        R::Item: Into<String>,
        L: IntoIterator,
        L::Item: Into<String>,
    {
        self.preferred_regions = regions.into_iter().map(Into::into).collect();
        self.preferred_languages = languages.into_iter().map(Into::into).collect();
    }
}

/// Selected artwork grouped by canonical type.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedArtworkSet {
    selections: BTreeMap<ArtworkType, Vec<ArtworkCandidate>>,
}

impl ResolvedArtworkSet {
    /// Returns the winning candidate for one artwork type.
    pub fn selected(&self, artwork_type: ArtworkType) -> Option<&ArtworkCandidate> {
        self.selections
            .get(&artwork_type)
            .and_then(|items| items.first())
    }

    /// Returns the bounded ordered gallery for one artwork type.
    pub fn gallery(&self, artwork_type: ArtworkType) -> &[ArtworkCandidate] {
        self.selections
            .get(&artwork_type)
            .map_or(&[], Vec::as_slice)
    }

    /// Returns artwork types with at least one selected candidate.
    pub fn artwork_types(&self) -> impl Iterator<Item = ArtworkType> + '_ {
        self.selections.keys().copied()
    }
}

/// Resolves artwork locally without provider or filesystem I/O.
pub fn resolve_artwork(
    candidates: &[ArtworkCandidate],
    policy: &ArtworkResolutionPolicy,
) -> ResolvedArtworkSet {
    let mut grouped = BTreeMap::<ArtworkType, Vec<ArtworkCandidate>>::new();
    let mut seen_sources = BTreeSet::new();
    for candidate in candidates {
        if !policy.enabled_providers.contains(&candidate.provider_id) {
            continue;
        }
        let source_key = if candidate.source.starts_with("http://")
            || candidate.source.starts_with("https://")
        {
            format!("url:{}", candidate.source)
        } else {
            format!("{}:{}", candidate.provider_id.as_str(), candidate.source)
        };
        if !seen_sources.insert(source_key) {
            continue;
        }
        let values = grouped.entry(candidate.artwork_type).or_default();
        if values.iter().any(|value| {
            value.provider_id == candidate.provider_id
                && value.external_asset_id == candidate.external_asset_id
        }) {
            continue;
        }
        values.push(candidate.clone());
    }

    for (artwork_type, values) in &mut grouped {
        values.sort_by_key(|candidate| {
            std::cmp::Reverse((
                locale_preference(&policy.preferred_regions, candidate.region()),
                locale_preference(&policy.preferred_languages, candidate.language()),
                provider_preference(*artwork_type, candidate.provider_id),
                aspect_suitability(*artwork_type, candidate.width, candidate.height),
                dimension_score(candidate.width, candidate.height),
                candidate.quality,
                candidate.discovered_at,
                candidate.provider_revision,
                std::cmp::Reverse(candidate.provider_id),
                std::cmp::Reverse(candidate.external_asset_id.clone()),
            ))
        });
        if *artwork_type == ArtworkType::Screenshot {
            let mut selected = Vec::with_capacity(policy.max_screenshots);
            let mut providers = BTreeSet::new();
            for candidate in values.iter() {
                if selected.len() == policy.max_screenshots {
                    break;
                }
                if providers.insert(candidate.provider_id) {
                    selected.push(candidate.clone());
                }
            }
            for candidate in values.iter() {
                if selected.len() == policy.max_screenshots {
                    break;
                }
                if !selected.contains(candidate) {
                    selected.push(candidate.clone());
                }
            }
            *values = selected;
        } else {
            values.truncate(1);
        }
    }
    ResolvedArtworkSet {
        selections: grouped,
    }
}

fn provider_preference(artwork_type: ArtworkType, provider_id: ProviderId) -> u8 {
    let preferred = match artwork_type {
        ArtworkType::CoverFront
        | ArtworkType::CoverBack
        | ArtworkType::CoverSpine
        | ArtworkType::Screenshot
        | ArtworkType::TitleScreen
        | ArtworkType::Manual => [
            ProviderId::GameTdb,
            ProviderId::SteamGridDb,
            ProviderId::Playmatch,
        ],
        ArtworkType::Logo | ArtworkType::Icon | ArtworkType::Background | ArtworkType::Banner => [
            ProviderId::SteamGridDb,
            ProviderId::GameTdb,
            ProviderId::Playmatch,
        ],
    };
    match preferred
        .iter()
        .position(|candidate| *candidate == provider_id)
    {
        Some(0) => 3,
        Some(1) => 2,
        Some(2) => 1,
        _ => 0,
    }
}

fn locale_preference(preferences: &[String], value: Option<&str>) -> usize {
    preferences
        .iter()
        .position(|preferred| Some(preferred.as_str()) == value)
        .map_or(0, |position| preferences.len() - position)
}

fn aspect_suitability(artwork_type: ArtworkType, width: Option<u32>, height: Option<u32>) -> u32 {
    let (Some(width), Some(height)) = (width, height) else {
        return 0;
    };
    if height == 0 || width == 0 {
        return 0;
    }
    let (target_width, target_height) = match artwork_type {
        ArtworkType::CoverFront
        | ArtworkType::CoverBack
        | ArtworkType::CoverSpine
        | ArtworkType::Manual
        | ArtworkType::TitleScreen
        | ArtworkType::Icon => (2_u64, 3_u64),
        ArtworkType::Logo | ArtworkType::Banner => (3, 1),
        ArtworkType::Background | ArtworkType::Screenshot => (16, 9),
    };
    let expected = u64::from(width) * target_height;
    let actual = u64::from(height) * target_width;
    let difference = expected.abs_diff(actual);
    let scale = expected.max(actual).max(1);
    u32::try_from(1_000_u64.saturating_sub(difference.saturating_mul(1_000) / scale)).unwrap_or(0)
}

fn dimension_score(width: Option<u32>, height: Option<u32>) -> u64 {
    match (width, height) {
        (Some(width), Some(height)) => u64::from(width).saturating_mul(u64::from(height)),
        _ => 0,
    }
}
