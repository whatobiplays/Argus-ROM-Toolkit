//! Reusable provider-enrichment orchestration.
//!
//! This module deliberately stops at an explicit application call. It does
//! not admit a JobRun, react to settings mutations, or perform work during
//! startup. Provider sessions perform external I/O before short persistence
//! callbacks, and local resolution is run again from records committed by the
//! first callback.

use std::collections::BTreeSet;

use argus_domain::{GameContentId, GameId, PlatformId};

use crate::artwork::{
    ArtworkCandidate, ArtworkReference, ArtworkRepository, ArtworkResolutionPolicy, ArtworkSource,
    ResolvedArtwork, resolve_artwork,
};
use crate::library::GameDetail;
use crate::metadata::{
    ExactMatchEvidence, ExternalIdentityMapping, MappingState, MatchBasis,
    MetadataProviderReadinessProjection, MetadataProviderRegistry, MetadataResolutionPolicy,
    ProviderCapability, ProviderId, ProviderMetadata, ProviderReadinessState, ResolvedMetadata,
    accept_exact_mappings, resolve_provider_metadata,
};
use crate::unit_of_work::{EnrichmentUnitOfWork, UnitOfWork, UnitOfWorkFactory};
use crate::{ApplicationPortError, MetadataRepository, OperationContext};

/// One already identified GameContent unit eligible for explicit hydration.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HydrationTarget {
    game_id: GameId,
    game_content_id: GameContentId,
    platform_id: PlatformId,
    submitted_identity: String,
    provider_platform_id: String,
    existing_mappings: Vec<ExternalIdentityMapping>,
    observed_at: i64,
}

/// Why an internal hydration request did not match committed logical-library
/// state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HydrationTargetValidationError {
    /// The request names a different Game than the loaded detail.
    GameMismatch,
    /// The requested GameContent is not a current member of the Game.
    ContentNotMember,
    /// The content is not currently identified by the canonical pipeline.
    ContentNotIdentified,
    /// The request platform disagrees with the durable GameContent platform.
    PlatformMismatch,
    /// Durable identity facts are absent.
    IdentityMissing,
    /// Transient provider request facts are incomplete.
    InvalidRequestFacts,
}

impl HydrationTarget {
    /// Creates a target from committed exact-content identity facts.
    pub fn new(
        game_id: GameId,
        game_content_id: GameContentId,
        platform_id: PlatformId,
        submitted_identity: impl Into<String>,
        provider_platform_id: impl Into<String>,
    ) -> Self {
        Self {
            game_id,
            game_content_id,
            platform_id,
            submitted_identity: submitted_identity.into(),
            provider_platform_id: provider_platform_id.into(),
            existing_mappings: Vec::new(),
            observed_at: 0,
        }
    }

    /// Adds mappings already accepted for this content for refresh-only use.
    pub fn with_existing_mappings(mut self, mappings: Vec<ExternalIdentityMapping>) -> Self {
        self.existing_mappings = mappings;
        self
    }

    /// Sets the observation timestamp used for newly retained evidence.
    pub fn with_observed_at(mut self, observed_at: i64) -> Self {
        self.observed_at = observed_at;
        self
    }

    /// Returns the owning Game.
    pub const fn game_id(&self) -> GameId {
        self.game_id
    }

    /// Returns the canonical GameContent identity.
    pub const fn game_content_id(&self) -> GameContentId {
        self.game_content_id
    }

    /// Returns the validated platform.
    pub const fn platform_id(&self) -> PlatformId {
        self.platform_id
    }

    /// Returns the exact identity submitted to a provider adapter.
    pub fn submitted_identity(&self) -> &str {
        &self.submitted_identity
    }

    /// Returns the provider-native platform identity used for exact matching.
    pub fn provider_platform_id(&self) -> &str {
        &self.provider_platform_id
    }

    /// Returns refreshable mappings known before this hydration pass.
    pub fn existing_mappings(&self) -> &[ExternalIdentityMapping] {
        &self.existing_mappings
    }

    /// Validates the transient request against a durable Game detail before
    /// any provider session is constructed or external I/O is attempted.
    pub fn validate_against_game(
        &self,
        detail: &GameDetail,
    ) -> Result<(), HydrationTargetValidationError> {
        if detail.game_id() != self.game_id {
            return Err(HydrationTargetValidationError::GameMismatch);
        }
        if detail.platform_id() != self.platform_id {
            return Err(HydrationTargetValidationError::PlatformMismatch);
        }
        let Some(content) = detail
            .content()
            .iter()
            .find(|content| content.game_content_id() == self.game_content_id)
        else {
            return Err(HydrationTargetValidationError::ContentNotMember);
        };
        if content.identification() != argus_domain::IdentificationState::Identified {
            return Err(HydrationTargetValidationError::ContentNotIdentified);
        }
        if content.platform_id() != self.platform_id {
            return Err(HydrationTargetValidationError::PlatformMismatch);
        }
        if content.identity().is_none() {
            return Err(HydrationTargetValidationError::IdentityMissing);
        }
        if self.submitted_identity.is_empty() || self.provider_platform_id.is_empty() {
            return Err(HydrationTargetValidationError::InvalidRequestFacts);
        }
        if self
            .existing_mappings
            .iter()
            .any(|mapping| mapping.game_content_id() != self.game_content_id)
        {
            return Err(HydrationTargetValidationError::InvalidRequestFacts);
        }
        Ok(())
    }

    /// Returns the observation timestamp for this explicit pass.
    pub const fn observed_at(&self) -> i64 {
        self.observed_at
    }
}

/// One provider result candidate before evidence policy is applied.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HydrationMappingCandidate {
    game_content_id: GameContentId,
    provider_id: ProviderId,
    external_game_id: String,
    external_release_id: Option<String>,
    provider_platform_id: String,
    provider_confidence: Option<u16>,
    evidence: ExactMatchEvidence,
    provider_revision: u64,
    observed_at: i64,
}

impl HydrationMappingCandidate {
    /// Creates one normalized provider evidence candidate.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        game_content_id: GameContentId,
        provider_id: ProviderId,
        external_game_id: impl Into<String>,
        external_release_id: Option<String>,
        provider_platform_id: impl Into<String>,
        provider_confidence: Option<u16>,
        evidence: ExactMatchEvidence,
        provider_revision: u64,
        observed_at: i64,
    ) -> Self {
        Self {
            game_content_id,
            provider_id,
            external_game_id: external_game_id.into(),
            external_release_id,
            provider_platform_id: provider_platform_id.into(),
            provider_confidence,
            evidence,
            provider_revision,
            observed_at,
        }
    }

    /// Returns the provider identity.
    pub const fn provider_id(&self) -> ProviderId {
        self.provider_id
    }

    /// Returns the provider-native game identity.
    pub fn external_game_id(&self) -> &str {
        &self.external_game_id
    }

    /// Returns the evidence class payload.
    pub fn evidence(&self) -> &ExactMatchEvidence {
        &self.evidence
    }
}

/// Converts provider candidates into durable mapping evidence conservatively.
pub struct HydrationPlanner;

impl HydrationPlanner {
    /// Applies exact-evidence policy to every candidate in one provider result.
    ///
    /// A result with multiple candidates is retained as rejected evidence so
    /// ambiguity remains inspectable without becoming grouping authority.
    pub fn build_mappings(
        candidates: &[HydrationMappingCandidate],
    ) -> Vec<ExternalIdentityMapping> {
        let evidence = candidates
            .iter()
            .map(|candidate| candidate.evidence.clone())
            .collect::<Vec<_>>();
        let accepted = accept_exact_mappings(&evidence).is_current();
        candidates
            .iter()
            .map(|candidate| {
                let match_basis = if accepted {
                    match_basis(&candidate.evidence)
                } else {
                    MatchBasis::RejectedByPolicy
                };
                ExternalIdentityMapping::new(
                    candidate.game_content_id,
                    candidate.provider_id,
                    candidate.external_game_id.clone(),
                    candidate.external_release_id.clone(),
                    candidate.provider_platform_id.clone(),
                    candidate.provider_confidence,
                    match_basis,
                    candidate.provider_revision,
                    if accepted {
                        MappingState::Current
                    } else {
                        MappingState::RejectedByPolicy
                    },
                    candidate.observed_at,
                    candidate.observed_at,
                )
            })
            .collect()
    }
}

fn match_basis(evidence: &ExactMatchEvidence) -> MatchBasis {
    match evidence {
        ExactMatchEvidence::Playmatch { .. } => MatchBasis::PlaymatchExactContent,
        ExactMatchEvidence::GameTdb { .. } => MatchBasis::GameTdbExactNativeIdentifier,
        ExactMatchEvidence::TitleOnly { .. } => MatchBasis::RejectedByPolicy,
    }
}

/// Safe normalized failure from a provider session.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HydrationProviderError {
    /// Provider rejected the configured credential.
    AuthenticationFailed,
    /// Provider rejected the request authorization.
    AuthorizationFailed,
    /// Provider configuration is invalid for the requested capability.
    Misconfigured,
    /// Provider asked the caller to rate-limit.
    RateLimited,
    /// Provider request exceeded its time budget.
    Timeout,
    /// Provider or network is unavailable.
    Unavailable,
    /// Provider response violated the normalized contract.
    InvalidResponse,
    /// The session does not implement the requested capability.
    UnsupportedCapability,
}

impl HydrationProviderError {
    /// Returns the stable application-facing issue key.
    pub const fn code(self) -> &'static str {
        match self {
            Self::AuthenticationFailed => "provider_authentication_failed",
            Self::AuthorizationFailed => "provider_authorization_failed",
            Self::Misconfigured => "provider_misconfigured",
            Self::RateLimited => "provider_rate_limited",
            Self::Timeout => "provider_timeout",
            Self::Unavailable => "provider_unavailable",
            Self::InvalidResponse => "provider_invalid_response",
            Self::UnsupportedCapability => "provider_unsupported_capability",
        }
    }
}

/// Provider session port owned by one explicit hydration operation.
pub trait EnrichmentProviderSession {
    /// Returns the immutable provider identity for this session.
    fn provider_id(&self) -> ProviderId;

    /// Performs provider-specific exact matching for one target.
    fn match_exact(
        &mut self,
        _target: &HydrationTarget,
    ) -> Result<Vec<HydrationMappingCandidate>, HydrationProviderError> {
        Err(HydrationProviderError::UnsupportedCapability)
    }

    /// Fetches normalized metadata for one accepted mapping.
    fn fetch_metadata(
        &mut self,
        _target: &HydrationTarget,
        _mapping: &ExternalIdentityMapping,
    ) -> Result<Option<ProviderMetadata>, HydrationProviderError> {
        Err(HydrationProviderError::UnsupportedCapability)
    }

    /// Discovers normalized artwork references for one accepted mapping.
    fn discover_artwork(
        &mut self,
        _mapping: &ExternalIdentityMapping,
    ) -> Result<Vec<ArtworkCandidate>, HydrationProviderError> {
        Err(HydrationProviderError::UnsupportedCapability)
    }

    /// Resolves a reference and downloads original bytes inside the provider
    /// session. Signed or credential-derived URLs remain transient here.
    fn download_artwork(
        &mut self,
        _reference: &ArtworkReference,
    ) -> Result<Vec<u8>, HydrationProviderError> {
        Err(HydrationProviderError::UnsupportedCapability)
    }
}

/// Application port for immutable, validated artwork byte storage.
pub trait ArtworkAssetStore {
    /// Stores original bytes and returns content-addressed safe metadata.
    fn store(&self, bytes: &[u8]) -> Result<crate::ArtworkAsset, ArtworkAssetStoreError>;
}

/// Safe failure vocabulary for the artwork byte-store port.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ArtworkAssetStoreError {
    /// Encoded bytes exceeded the configured bound.
    TooLarge,
    /// Bytes are malformed or not an allowed image.
    InvalidImage,
    /// Image dimensions exceeded the configured bound.
    DimensionsTooLarge,
    /// The application-private store is unavailable.
    Unavailable,
}

/// One bounded issue retained by a hydration result.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HydrationIssueKind {
    /// Exact matching failed or was unavailable.
    Matching,
    /// Provider-native metadata failed.
    Metadata,
    /// Artwork discovery failed.
    ArtworkDiscovery,
    /// Artwork download failed.
    ArtworkDownload,
    /// Local immutable asset persistence failed.
    AssetStore,
}

/// Provider-scoped issue without raw transport or secret payloads.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct HydrationIssue {
    provider_id: Option<ProviderId>,
    kind: HydrationIssueKind,
    code: &'static str,
}

impl HydrationIssue {
    fn provider(
        provider_id: ProviderId,
        kind: HydrationIssueKind,
        error: HydrationProviderError,
    ) -> Self {
        Self {
            provider_id: Some(provider_id),
            kind,
            code: error.code(),
        }
    }

    fn asset_store(error: ArtworkAssetStoreError) -> Self {
        let code = match error {
            ArtworkAssetStoreError::TooLarge => "artwork_asset_too_large",
            ArtworkAssetStoreError::InvalidImage => "artwork_asset_invalid_image",
            ArtworkAssetStoreError::DimensionsTooLarge => "artwork_asset_dimensions_too_large",
            ArtworkAssetStoreError::Unavailable => "artwork_asset_store_unavailable",
        };
        Self {
            provider_id: None,
            kind: HydrationIssueKind::AssetStore,
            code,
        }
    }

    /// Returns the provider that caused the issue, if applicable.
    pub const fn provider_id(self) -> Option<ProviderId> {
        self.provider_id
    }

    /// Returns the issue phase.
    pub const fn kind(self) -> HydrationIssueKind {
        self.kind
    }

    /// Returns the stable issue code.
    pub const fn code(self) -> &'static str {
        self.code
    }
}

/// Summary of one explicit hydration call.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HydrationReport {
    mappings: Vec<ExternalIdentityMapping>,
    resolved_metadata: ResolvedMetadata,
    resolved_artwork: Vec<ResolvedArtwork>,
    issues: Vec<HydrationIssue>,
}

impl HydrationReport {
    /// Returns mapping evidence retained by the pass.
    pub fn mappings(&self) -> &[ExternalIdentityMapping] {
        &self.mappings
    }

    /// Returns the committed local metadata projection.
    pub const fn resolved_metadata(&self) -> &ResolvedMetadata {
        &self.resolved_metadata
    }

    /// Returns the committed artwork selections.
    pub fn resolved_artwork(&self) -> &[ResolvedArtwork] {
        &self.resolved_artwork
    }

    /// Returns bounded provider/store issues.
    pub fn issues(&self) -> &[HydrationIssue] {
        &self.issues
    }
}

/// Explicit provider hydration coordinator with no JobRun admission.
pub struct HydrationCoordinator<F> {
    unit_of_work: F,
}

impl<F> HydrationCoordinator<F>
where
    F: UnitOfWorkFactory,
    for<'scope> F::Scope<'scope>: EnrichmentUnitOfWork,
{
    /// Creates a coordinator over an existing backend transaction factory.
    pub const fn new(unit_of_work: F) -> Self {
        Self { unit_of_work }
    }

    /// Re-resolves only committed provider records for one identified target.
    ///
    /// This is the local half of hydration used by settings-driven refreshes:
    /// it never creates provider sessions, performs network I/O, or downloads
    /// artwork bytes. Selection remains owned by the same metadata and artwork
    /// policy functions used by the full hydration path.
    pub fn resolve_existing(
        &self,
        context: &OperationContext,
        target: HydrationTarget,
        metadata_policy: MetadataResolutionPolicy,
        artwork_policy: ArtworkResolutionPolicy,
        now: i64,
    ) -> Result<HydrationReport, ApplicationPortError> {
        let mappings = target.existing_mappings().to_vec();
        let mappings_for_resolution = mappings.clone();
        let settings_for_resolution = metadata_policy;
        let artwork_policy_for_resolution = artwork_policy;
        let target_for_resolution = target;
        let (resolved_metadata, resolved_artwork) =
            self.unit_of_work.execute(context, move |mut scope| {
                let provider_metadata = {
                    let mut metadata = scope.metadata();
                    metadata
                        .provider_metadata_for_content(target_for_resolution.game_content_id())
                        .map_err(ApplicationPortError::from)?
                };
                let references = {
                    let mut artwork = scope.artwork();
                    let mut references = Vec::new();
                    let mut seen_reference_ids = BTreeSet::new();
                    for mapping in &mappings_for_resolution {
                        if mapping.state() != MappingState::Current {
                            continue;
                        }
                        let providers = [mapping.provider_id(), ProviderId::SteamGridDb];
                        for provider_id in providers {
                            for reference in artwork
                                .references_for_external_game(
                                    provider_id,
                                    mapping.external_game_id(),
                                )
                                .map_err(ApplicationPortError::from)?
                            {
                                if seen_reference_ids.insert(reference.reference_id().to_owned()) {
                                    references.push(reference);
                                }
                            }
                        }
                    }
                    references
                };
                let resolved_metadata =
                    resolve_provider_metadata(&provider_metadata, &settings_for_resolution, now);
                let artwork_candidates = references
                    .iter()
                    .map(artwork_candidate_from_reference)
                    .collect::<Vec<_>>();
                let selected = resolve_artwork(&artwork_candidates, &artwork_policy_for_resolution);
                let mut resolved_artwork = Vec::new();
                {
                    let mut metadata = scope.metadata();
                    metadata
                        .save_resolved_metadata(target_for_resolution.game_id(), &resolved_metadata)
                        .map_err(ApplicationPortError::from)?;
                }
                {
                    let mut artwork = scope.artwork();
                    for artwork_type in selected.artwork_types() {
                        for (ordering, candidate) in
                            selected.gallery(artwork_type).iter().enumerate()
                        {
                            let Some(reference) = references.iter().find(|reference| {
                                reference.provider_id() == candidate.provider_id()
                                    && reference.artwork_type() == artwork_type
                                    && reference.source().kind_and_value().1 == candidate.source()
                            }) else {
                                continue;
                            };
                            resolved_artwork.push(ResolvedArtwork::new(
                                target_for_resolution.game_id(),
                                artwork_type,
                                reference.reference_id(),
                                None,
                                u32::try_from(ordering).unwrap_or(u32::MAX),
                                "deterministic_policy",
                                1,
                                now,
                            ));
                        }
                    }
                    artwork
                        .replace_resolved_artwork_for_game(
                            target_for_resolution.game_id(),
                            &resolved_artwork,
                        )
                        .map_err(ApplicationPortError::from)?;
                }
                scope.commit()?;
                Ok((resolved_metadata, resolved_artwork))
            })?;

        Ok(HydrationReport {
            mappings,
            resolved_metadata,
            resolved_artwork,
            issues: Vec::new(),
        })
    }

    /// Hydrates one identified target through independently eligible sessions.
    ///
    /// The method is intentionally explicit and synchronous at this application
    /// boundary. Runtime callers invoke it from a backend worker, never from a
    /// Flutter/UI thread. All provider calls happen before each database write
    /// transaction begins.
    #[allow(clippy::too_many_arguments)]
    pub fn hydrate(
        &self,
        context: &OperationContext,
        target: HydrationTarget,
        metadata_policy: MetadataResolutionPolicy,
        artwork_policy: ArtworkResolutionPolicy,
        registry: &MetadataProviderRegistry,
        readiness: &[MetadataProviderReadinessProjection],
        sessions: &mut [Box<dyn EnrichmentProviderSession>],
        asset_store: &dyn ArtworkAssetStore,
        now: i64,
    ) -> Result<HydrationReport, ApplicationPortError> {
        let mut mappings = target.existing_mappings().to_vec();
        let mut provider_metadata = Vec::new();
        let mut artwork_references = Vec::new();
        let mut issues = Vec::new();
        let mut seen_mappings = BTreeSet::new();

        for mapping in &mappings {
            seen_mappings.insert(mapping_key(mapping));
        }

        for session in sessions.iter_mut() {
            let provider_id = session.provider_id();
            let descriptor = registry.descriptor(provider_id);

            let mut provider_candidates = Vec::new();
            if let Some(state) =
                capability_state(readiness, provider_id, ProviderCapability::ContentMatching)
            {
                if let Some(error) = readiness_issue(state) {
                    issues.push(HydrationIssue::provider(
                        provider_id,
                        HydrationIssueKind::Matching,
                        error,
                    ));
                } else if state == ProviderReadinessState::Ready
                    && descriptor
                        .capabilities()
                        .contains(&ProviderCapability::ContentMatching)
                {
                    match session.match_exact(&target) {
                        Ok(candidates) => provider_candidates = candidates,
                        Err(error) => issues.push(HydrationIssue::provider(
                            provider_id,
                            HydrationIssueKind::Matching,
                            error,
                        )),
                    }
                }
            } else if descriptor
                .capabilities()
                .contains(&ProviderCapability::ContentMatching)
            {
                issues.push(HydrationIssue::provider(
                    provider_id,
                    HydrationIssueKind::Matching,
                    HydrationProviderError::Misconfigured,
                ));
            }
            for mapping in HydrationPlanner::build_mappings(&provider_candidates) {
                if seen_mappings.insert(mapping_key(&mapping)) {
                    mappings.push(mapping);
                }
            }

            let owned_mappings = mappings
                .iter()
                .filter(|mapping| {
                    mapping.provider_id() == provider_id && mapping.state() == MappingState::Current
                })
                .cloned()
                .collect::<Vec<_>>();

            let metadata_ready =
                capability_state(readiness, provider_id, ProviderCapability::MetadataRefresh);
            if descriptor
                .capabilities()
                .contains(&ProviderCapability::MetadataRefresh)
            {
                if let Some(state) = metadata_ready {
                    if let Some(error) = readiness_issue(state) {
                        issues.push(HydrationIssue::provider(
                            provider_id,
                            HydrationIssueKind::Metadata,
                            error,
                        ));
                    }
                } else {
                    issues.push(HydrationIssue::provider(
                        provider_id,
                        HydrationIssueKind::Metadata,
                        HydrationProviderError::Misconfigured,
                    ));
                }
            }
            if metadata_ready == Some(ProviderReadinessState::Ready) {
                for mapping in &owned_mappings {
                    match session.fetch_metadata(&target, mapping) {
                        Ok(Some(metadata)) => provider_metadata.push(metadata),
                        Ok(None) => {}
                        Err(error) => issues.push(HydrationIssue::provider(
                            provider_id,
                            HydrationIssueKind::Metadata,
                            error,
                        )),
                    }
                }
            }

            let artwork_ready =
                capability_state(readiness, provider_id, ProviderCapability::ArtworkDiscovery);
            if descriptor
                .capabilities()
                .contains(&ProviderCapability::ArtworkDiscovery)
            {
                if let Some(state) = artwork_ready {
                    if let Some(error) = readiness_issue(state) {
                        issues.push(HydrationIssue::provider(
                            provider_id,
                            HydrationIssueKind::ArtworkDiscovery,
                            error,
                        ));
                    }
                } else {
                    issues.push(HydrationIssue::provider(
                        provider_id,
                        HydrationIssueKind::ArtworkDiscovery,
                        HydrationProviderError::Misconfigured,
                    ));
                }
            }
            if artwork_ready == Some(ProviderReadinessState::Ready) {
                // SteamGridDB is artwork-only and intentionally never creates
                // an ExternalIdentityMapping. It can therefore enrich an
                // accepted mapping from another provider; the provider-local
                // artwork session uses that deterministic accepted identity
                // without turning it into Steam grouping authority.
                let artwork_mappings = if provider_id == ProviderId::SteamGridDb {
                    mappings
                        .iter()
                        .filter(|mapping| mapping.state() == MappingState::Current)
                        .cloned()
                        .collect::<Vec<_>>()
                } else {
                    owned_mappings
                };
                for mapping in &artwork_mappings {
                    match session.discover_artwork(mapping) {
                        Ok(candidates) => {
                            artwork_references.extend(candidates.into_iter().map(|candidate| {
                                artwork_reference_from_candidate(mapping, candidate)
                            }))
                        }
                        Err(error) => issues.push(HydrationIssue::provider(
                            provider_id,
                            HydrationIssueKind::ArtworkDiscovery,
                            error,
                        )),
                    }
                }
            }
        }

        let first_batch_mappings = mappings.clone();
        let first_batch_metadata = provider_metadata;
        let first_batch_references = artwork_references;
        self.unit_of_work.execute(context, move |mut scope| {
            {
                let mut metadata = scope.metadata();
                for mapping in &first_batch_mappings {
                    metadata
                        .save_mapping(mapping)
                        .map_err(ApplicationPortError::from)?;
                }
                for provider_metadata in &first_batch_metadata {
                    metadata
                        .save_provider_metadata(provider_metadata)
                        .map_err(ApplicationPortError::from)?;
                }
            }
            {
                let mut artwork = scope.artwork();
                for reference in &first_batch_references {
                    artwork
                        .save_reference(reference)
                        .map_err(ApplicationPortError::from)?;
                }
            }
            scope.commit()
        })?;

        let mappings_for_resolution = mappings.clone();
        let settings_for_resolution = metadata_policy.clone();
        let artwork_policy_for_resolution = artwork_policy.clone();
        let target_for_resolution = target;
        let (resolved_metadata, resolved_artwork, references) =
            self.unit_of_work.execute(context, move |mut scope| {
                let provider_metadata = {
                    let mut metadata = scope.metadata();
                    metadata
                        .provider_metadata_for_content(target_for_resolution.game_content_id())
                        .map_err(ApplicationPortError::from)?
                };
                let references = {
                    let mut artwork = scope.artwork();
                    let mut references = Vec::new();
                    let mut seen_reference_ids = BTreeSet::new();
                    for mapping in &mappings_for_resolution {
                        if mapping.state() != MappingState::Current {
                            continue;
                        }
                        // Artwork-only providers enrich the accepted game
                        // identity without owning its content mapping. Read
                        // both the mapping owner and the artwork-only
                        // provider for the accepted external game identity.
                        let providers = [mapping.provider_id(), ProviderId::SteamGridDb];
                        for provider_id in providers {
                            for reference in artwork
                                .references_for_external_game(
                                    provider_id,
                                    mapping.external_game_id(),
                                )
                                .map_err(ApplicationPortError::from)?
                            {
                                if seen_reference_ids.insert(reference.reference_id().to_owned()) {
                                    references.push(reference);
                                }
                            }
                        }
                    }
                    references
                };
                let resolved_metadata =
                    resolve_provider_metadata(&provider_metadata, &settings_for_resolution, now);
                let artwork_candidates = references
                    .iter()
                    .map(artwork_candidate_from_reference)
                    .collect::<Vec<_>>();
                let selected = resolve_artwork(&artwork_candidates, &artwork_policy_for_resolution);
                let mut resolved_artwork = Vec::new();
                {
                    let mut metadata = scope.metadata();
                    metadata
                        .save_resolved_metadata(target_for_resolution.game_id(), &resolved_metadata)
                        .map_err(ApplicationPortError::from)?;
                }
                {
                    let mut artwork = scope.artwork();
                    for artwork_type in selected.artwork_types() {
                        for (ordering, candidate) in
                            selected.gallery(artwork_type).iter().enumerate()
                        {
                            let Some(reference) = references.iter().find(|reference| {
                                reference.provider_id() == candidate.provider_id()
                                    && reference.artwork_type() == artwork_type
                                    && reference.source().kind_and_value().1 == candidate.source()
                            }) else {
                                continue;
                            };
                            let resolved = ResolvedArtwork::new(
                                target_for_resolution.game_id(),
                                artwork_type,
                                reference.reference_id(),
                                None,
                                u32::try_from(ordering).unwrap_or(u32::MAX),
                                "deterministic_policy",
                                1,
                                now,
                            );
                            resolved_artwork.push(resolved);
                        }
                    }
                    artwork
                        .replace_resolved_artwork_for_game(
                            target_for_resolution.game_id(),
                            &resolved_artwork,
                        )
                        .map_err(ApplicationPortError::from)?;
                }
                scope.commit()?;
                Ok((resolved_metadata, resolved_artwork, references))
            })?;

        let mut asset_updates = Vec::new();
        for resolved in &resolved_artwork {
            let Some(reference) = references
                .iter()
                .find(|reference| reference.reference_id() == resolved.reference_id())
            else {
                continue;
            };
            let Some(session) = sessions
                .iter_mut()
                .find(|session| session.provider_id() == reference.provider_id())
            else {
                continue;
            };
            let bytes = match session.download_artwork(reference) {
                Ok(bytes) => bytes,
                Err(error) => {
                    issues.push(HydrationIssue::provider(
                        reference.provider_id(),
                        HydrationIssueKind::ArtworkDownload,
                        error,
                    ));
                    continue;
                }
            };
            match asset_store.store(&bytes) {
                Ok(asset) => asset_updates.push((resolved.clone(), asset)),
                Err(error) => issues.push(HydrationIssue::asset_store(error)),
            }
        }

        let final_artwork = self.unit_of_work.execute(context, move |mut scope| {
            if asset_updates.is_empty() {
                scope.commit()?;
                return Ok(resolved_artwork);
            }
            {
                let mut artwork = scope.artwork();
                for (resolved, asset) in &asset_updates {
                    artwork
                        .save_asset(asset)
                        .map_err(ApplicationPortError::from)?;
                    let resolved_with_asset = ResolvedArtwork::new(
                        resolved.game_id(),
                        resolved.artwork_type(),
                        resolved.reference_id(),
                        Some(asset.asset_id()),
                        resolved.ordering(),
                        resolved.selection_reason(),
                        resolved.resolution_revision(),
                        resolved.resolved_at(),
                    );
                    artwork
                        .save_resolved_artwork(&resolved_with_asset)
                        .map_err(ApplicationPortError::from)?;
                }
            }
            scope.commit()?;
            Ok(resolved_artwork
                .into_iter()
                .map(|resolved| {
                    asset_updates
                        .iter()
                        .find(|(candidate, _)| candidate.reference_id() == resolved.reference_id())
                        .map_or(resolved.clone(), |(_, asset)| {
                            ResolvedArtwork::new(
                                resolved.game_id(),
                                resolved.artwork_type(),
                                resolved.reference_id(),
                                Some(asset.asset_id()),
                                resolved.ordering(),
                                resolved.selection_reason(),
                                resolved.resolution_revision(),
                                resolved.resolved_at(),
                            )
                        })
                })
                .collect())
        })?;

        Ok(HydrationReport {
            mappings,
            resolved_metadata,
            resolved_artwork: final_artwork,
            issues,
        })
    }
}

fn capability_state(
    readiness: &[MetadataProviderReadinessProjection],
    provider_id: ProviderId,
    capability: ProviderCapability,
) -> Option<ProviderReadinessState> {
    let projection = readiness
        .iter()
        .find(|value| value.provider_id() == provider_id)?;
    if !projection.enabled() {
        return Some(ProviderReadinessState::Disabled);
    }
    projection
        .capability_readiness()
        .iter()
        .find(|value| value.capability() == capability)
        .map(|value| value.state())
}

fn readiness_issue(state: ProviderReadinessState) -> Option<HydrationProviderError> {
    match state {
        ProviderReadinessState::InvalidCredentials => {
            Some(HydrationProviderError::AuthenticationFailed)
        }
        ProviderReadinessState::Misconfigured => Some(HydrationProviderError::Misconfigured),
        ProviderReadinessState::Unavailable => Some(HydrationProviderError::Unavailable),
        ProviderReadinessState::Ready
        | ProviderReadinessState::Disabled
        | ProviderReadinessState::MissingCredentials => None,
    }
}

fn mapping_key(mapping: &ExternalIdentityMapping) -> (ProviderId, String, Option<String>) {
    (
        mapping.provider_id(),
        mapping.external_game_id().to_owned(),
        mapping.external_release_id().map(str::to_owned),
    )
}

fn artwork_reference_from_candidate(
    mapping: &ExternalIdentityMapping,
    candidate: ArtworkCandidate,
) -> ArtworkReference {
    // Provider URLs are transient transport details. Even a URL that looks
    // public can carry a credential or signature in its path, so durable
    // references retain only the adapter-validated opaque asset identity.
    // Provider sessions resolve that identity to a URL for one download.
    let source =
        if is_http_locator(candidate.source()) || !is_valid_opaque_locator(candidate.source()) {
            ArtworkSource::ProviderAssetLocator(format!("asset:{}", candidate.external_asset_id()))
        } else {
            ArtworkSource::ProviderAssetLocator(candidate.source().to_owned())
        };
    ArtworkReference::new(
        format!(
            "{}:{}:{}",
            candidate.provider_id().as_str(),
            mapping.external_game_id(),
            candidate.external_asset_id()
        ),
        candidate.provider_id(),
        mapping.external_game_id(),
        candidate.artwork_type(),
        source,
        candidate.width(),
        candidate.height(),
        None,
        None,
        candidate.region().map(str::to_owned),
        candidate.language().map(str::to_owned),
        candidate.provider_revision(),
    )
    .with_quality(candidate.quality())
    .with_discovered_at(candidate.discovered_at().max(mapping.last_validated_at()))
}

fn is_http_locator(value: &str) -> bool {
    value.starts_with("http://") || value.starts_with("https://")
}

fn is_valid_opaque_locator(value: &str) -> bool {
    let Some(locator) = value.strip_prefix("asset:") else {
        return false;
    };
    !locator.is_empty()
        && locator.len() <= 256
        && locator
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-' | b':'))
}

fn artwork_candidate_from_reference(reference: &ArtworkReference) -> ArtworkCandidate {
    ArtworkCandidate::new(
        reference.provider_id(),
        reference.reference_id(),
        reference.artwork_type(),
        reference.source().kind_and_value().1,
        reference.provider_revision(),
    )
    .with_details(
        reference.region().map(str::to_owned),
        reference.language().map(str::to_owned),
        reference.width(),
        reference.height(),
        reference.quality(),
    )
    .with_discovered_at(reference.discovered_at())
}
