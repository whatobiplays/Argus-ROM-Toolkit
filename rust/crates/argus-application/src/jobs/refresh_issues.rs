//! Typed, bounded issue accounting for composed Library refresh executions.
//!
//! This module owns refresh issue taxonomy, aggregation, validation, and the
//! application persistence port used to retain issue facts with a job.

use crate::hydration::{
    ArtworkAssetStoreError, HydrationIssue, HydrationIssueKind, HydrationIssueSource,
    HydrationProviderError,
};
use crate::metadata::ProviderId;
use crate::{JobRunId, PersistenceError};
use std::cmp::Ordering;
use std::collections::BTreeMap;

/// Closed broad category of one durable refresh issue.
///
/// The category keeps related reasons grouped for ordering and coarse
/// presentation. The companion [`RefreshIssueReason`] carries the actionable
/// explanation that makes a partial refresh intelligible.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum RefreshIssueKind {
    /// Exact content matching failed or was unavailable.
    Matching,
    /// Provider-native metadata failed.
    Metadata,
    /// Artwork discovery failed.
    ArtworkDiscovery,
    /// Artwork download failed.
    ArtworkDownload,
    /// Local artwork asset persistence failed.
    AssetStore,
    /// Local content processing failed for one admitted source.
    Content,
    /// Requested refresh scope could not be processed by the composed run.
    Scope,
}

impl RefreshIssueKind {
    /// Returns the stable persisted category key.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Matching => "matching",
            Self::Metadata => "metadata",
            Self::ArtworkDiscovery => "artwork_discovery",
            Self::ArtworkDownload => "artwork_download",
            Self::AssetStore => "asset_store",
            Self::Content => "content",
            Self::Scope => "scope",
        }
    }

    /// Decodes one persisted category key.
    pub fn from_persisted(value: &str) -> Result<Self, RefreshIssueError> {
        match value {
            "matching" => Ok(Self::Matching),
            "metadata" => Ok(Self::Metadata),
            "artwork_discovery" => Ok(Self::ArtworkDiscovery),
            "artwork_download" => Ok(Self::ArtworkDownload),
            "asset_store" => Ok(Self::AssetStore),
            "content" => Ok(Self::Content),
            "scope" => Ok(Self::Scope),
            _ => Err(RefreshIssueError),
        }
    }

    /// Maps one hydration category into the refresh category vocabulary.
    pub const fn from_hydration_kind(kind: HydrationIssueKind) -> Self {
        match kind {
            HydrationIssueKind::Matching => Self::Matching,
            HydrationIssueKind::Metadata => Self::Metadata,
            HydrationIssueKind::ArtworkDiscovery => Self::ArtworkDiscovery,
            HydrationIssueKind::ArtworkDownload => Self::ArtworkDownload,
            HydrationIssueKind::AssetStore => Self::AssetStore,
        }
    }
}

/// Closed safe reason vocabulary for one durable refresh issue.
///
/// Every reason maps to a failure the owning subsystem already distinguishes.
/// No raw native error, provider payload, locator, path, URL, or secret is
/// represented here, and no reason is invented where the backend does not
/// possess the distinction.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum RefreshIssueReason {
    /// Configured provider credential was rejected.
    ProviderAuthenticationFailed,
    /// Provider rejected the request authorization.
    ProviderAuthorizationFailed,
    /// Provider configuration is invalid for the requested capability.
    ProviderMisconfigured,
    /// Provider asked the caller to rate-limit.
    ProviderRateLimited,
    /// Provider request exceeded its time budget.
    ProviderTimeout,
    /// Provider or network is unavailable.
    ProviderUnavailable,
    /// Provider response violated the normalized contract.
    ProviderInvalidResponse,
    /// Provider session does not implement the requested capability.
    ProviderUnsupportedCapability,
    /// Downloaded artwork exceeded the configured byte bound.
    ArtworkAssetTooLarge,
    /// Downloaded artwork bytes were malformed or not an allowed image.
    ArtworkAssetInvalidImage,
    /// Downloaded artwork dimensions exceeded the configured bound.
    ArtworkAssetDimensionsTooLarge,
    /// The application-private artwork store is unavailable.
    ArtworkAssetStoreUnavailable,
    /// Admitted content could not be opened or read.
    ContentUnavailable,
    /// Admitted content was malformed or unsupported.
    ContentMalformedOrUnsupported,
    /// Admitted content needs a key or license that is not available.
    ContentEncryptedUnsupported,
    /// Admitted content depends on required data that is missing.
    ContentDependencyMissing,
    /// Admitted content exceeded a transformation resource limit.
    ContentResourceLimitExceeded,
    /// Admitted content changed while the refresh was reading it.
    ContentChangedDuringRefresh,
    /// Admitted content recognition is not represented by the identity catalog.
    ContentIdentityUnsupported,
    /// Admitted content could not be converged into committed identity evidence.
    ContentIdentificationFailed,
    /// Committed playlist or derived grouping could not be applied.
    ContentGroupingFailed,
    /// An admitted item's local refresh step failed without a more specific
    /// normalized provider, artwork, or content cause.
    ContentRefreshFailed,
    /// A requested root was deliberately not admitted to this refresh.
    ScopeRootNotAdmitted,
    /// An admitted root's scan reached only partial source coverage.
    ScopeRootScanIncomplete,
    /// An admitted root's scan failed while other roots retained meaning.
    ScopeRootScanFailed,
}

impl RefreshIssueReason {
    /// Returns the stable persisted reason key.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ProviderAuthenticationFailed => "provider_authentication_failed",
            Self::ProviderAuthorizationFailed => "provider_authorization_failed",
            Self::ProviderMisconfigured => "provider_misconfigured",
            Self::ProviderRateLimited => "provider_rate_limited",
            Self::ProviderTimeout => "provider_timeout",
            Self::ProviderUnavailable => "provider_unavailable",
            Self::ProviderInvalidResponse => "provider_invalid_response",
            Self::ProviderUnsupportedCapability => "provider_unsupported_capability",
            Self::ArtworkAssetTooLarge => "artwork_asset_too_large",
            Self::ArtworkAssetInvalidImage => "artwork_asset_invalid_image",
            Self::ArtworkAssetDimensionsTooLarge => "artwork_asset_dimensions_too_large",
            Self::ArtworkAssetStoreUnavailable => "artwork_asset_store_unavailable",
            Self::ContentUnavailable => "content_unavailable",
            Self::ContentMalformedOrUnsupported => "content_malformed_or_unsupported",
            Self::ContentEncryptedUnsupported => "content_encrypted_unsupported",
            Self::ContentDependencyMissing => "content_dependency_missing",
            Self::ContentResourceLimitExceeded => "content_resource_limit_exceeded",
            Self::ContentChangedDuringRefresh => "content_changed_during_refresh",
            Self::ContentIdentityUnsupported => "content_identity_unsupported",
            Self::ContentIdentificationFailed => "content_identification_failed",
            Self::ContentGroupingFailed => "content_grouping_failed",
            Self::ContentRefreshFailed => "content_refresh_failed",
            Self::ScopeRootNotAdmitted => "scope_root_not_admitted",
            Self::ScopeRootScanIncomplete => "scope_root_scan_incomplete",
            Self::ScopeRootScanFailed => "scope_root_scan_failed",
        }
    }

    /// Decodes one persisted reason key.
    pub fn from_persisted(value: &str) -> Result<Self, RefreshIssueError> {
        match value {
            "provider_authentication_failed" => Ok(Self::ProviderAuthenticationFailed),
            "provider_authorization_failed" => Ok(Self::ProviderAuthorizationFailed),
            "provider_misconfigured" => Ok(Self::ProviderMisconfigured),
            "provider_rate_limited" => Ok(Self::ProviderRateLimited),
            "provider_timeout" => Ok(Self::ProviderTimeout),
            "provider_unavailable" => Ok(Self::ProviderUnavailable),
            "provider_invalid_response" => Ok(Self::ProviderInvalidResponse),
            "provider_unsupported_capability" => Ok(Self::ProviderUnsupportedCapability),
            "artwork_asset_too_large" => Ok(Self::ArtworkAssetTooLarge),
            "artwork_asset_invalid_image" => Ok(Self::ArtworkAssetInvalidImage),
            "artwork_asset_dimensions_too_large" => Ok(Self::ArtworkAssetDimensionsTooLarge),
            "artwork_asset_store_unavailable" => Ok(Self::ArtworkAssetStoreUnavailable),
            "content_unavailable" => Ok(Self::ContentUnavailable),
            "content_malformed_or_unsupported" => Ok(Self::ContentMalformedOrUnsupported),
            "content_encrypted_unsupported" => Ok(Self::ContentEncryptedUnsupported),
            "content_dependency_missing" => Ok(Self::ContentDependencyMissing),
            "content_resource_limit_exceeded" => Ok(Self::ContentResourceLimitExceeded),
            "content_changed_during_refresh" => Ok(Self::ContentChangedDuringRefresh),
            "content_identity_unsupported" => Ok(Self::ContentIdentityUnsupported),
            "content_identification_failed" => Ok(Self::ContentIdentificationFailed),
            "content_grouping_failed" => Ok(Self::ContentGroupingFailed),
            "content_refresh_failed" => Ok(Self::ContentRefreshFailed),
            "scope_root_not_admitted" => Ok(Self::ScopeRootNotAdmitted),
            "scope_root_scan_incomplete" => Ok(Self::ScopeRootScanIncomplete),
            "scope_root_scan_failed" => Ok(Self::ScopeRootScanFailed),
            _ => Err(RefreshIssueError),
        }
    }

    /// Returns whether this reason is compatible with one issue category.
    ///
    /// A reason is only meaningful inside the category that produced it, so an
    /// impossible pairing is rejected instead of being persisted.
    pub const fn is_compatible_with(self, kind: RefreshIssueKind) -> bool {
        match self.category() {
            RefreshIssueReasonCategory::Provider => matches!(
                kind,
                RefreshIssueKind::Matching
                    | RefreshIssueKind::Metadata
                    | RefreshIssueKind::ArtworkDiscovery
                    | RefreshIssueKind::ArtworkDownload
            ),
            RefreshIssueReasonCategory::AssetStore => matches!(kind, RefreshIssueKind::AssetStore),
            RefreshIssueReasonCategory::Content => matches!(kind, RefreshIssueKind::Content),
            RefreshIssueReasonCategory::Scope => matches!(kind, RefreshIssueKind::Scope),
        }
    }

    /// Returns whether this reason can only describe a provider-owned failure.
    ///
    /// Provider-owned reasons are always attributed to the provider session
    /// that produced them. Content, artwork-store, and composed-scope reasons
    /// are local or operation-owned, so they never name a provider.
    pub const fn is_provider_owned(self) -> bool {
        matches!(self.category(), RefreshIssueReasonCategory::Provider)
    }

    const fn category(self) -> RefreshIssueReasonCategory {
        match self {
            Self::ProviderAuthenticationFailed
            | Self::ProviderAuthorizationFailed
            | Self::ProviderMisconfigured
            | Self::ProviderRateLimited
            | Self::ProviderTimeout
            | Self::ProviderUnavailable
            | Self::ProviderInvalidResponse
            | Self::ProviderUnsupportedCapability => RefreshIssueReasonCategory::Provider,
            Self::ArtworkAssetTooLarge
            | Self::ArtworkAssetInvalidImage
            | Self::ArtworkAssetDimensionsTooLarge
            | Self::ArtworkAssetStoreUnavailable => RefreshIssueReasonCategory::AssetStore,
            Self::ContentUnavailable
            | Self::ContentMalformedOrUnsupported
            | Self::ContentEncryptedUnsupported
            | Self::ContentDependencyMissing
            | Self::ContentResourceLimitExceeded
            | Self::ContentChangedDuringRefresh
            | Self::ContentIdentityUnsupported
            | Self::ContentIdentificationFailed
            | Self::ContentGroupingFailed
            | Self::ContentRefreshFailed => RefreshIssueReasonCategory::Content,
            Self::ScopeRootNotAdmitted
            | Self::ScopeRootScanIncomplete
            | Self::ScopeRootScanFailed => RefreshIssueReasonCategory::Scope,
        }
    }
}

/// Owning subsystem of one refresh issue reason.
///
/// The category is not persisted and carries no product meaning of its own;
/// it is only the internal guard that keeps a reason paired with the issue
/// category that could have produced it.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RefreshIssueReasonCategory {
    Provider,
    AssetStore,
    Content,
    Scope,
}

/// Rejected refresh issue projection.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RefreshIssueError;

impl std::fmt::Display for RefreshIssueError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("invalid refresh issue projection")
    }
}

impl std::error::Error for RefreshIssueError {}

/// Returns whether one count is representable in the durable signed domain.
const fn refresh_issue_representation_fits(value: u64) -> bool {
    value <= i64::MAX as u64
}

/// Returns whether one fact identity can describe a real refresh issue.
///
/// The identity is valid only when the reason belongs to the category, and
/// when provider attribution matches the reason: provider-owned reasons name
/// the provider session that failed, while local and composed-scope reasons
/// name no provider at all.
const fn refresh_issue_identity_is_valid(
    kind: RefreshIssueKind,
    reason: RefreshIssueReason,
    provider_id: Option<ProviderId>,
) -> bool {
    reason.is_compatible_with(kind) && reason.is_provider_owned() == provider_id.is_some()
}

/// One bounded durable refresh issue fact.
///
/// Identity is the complete typed tuple `(kind, reason, provider_id)`.
/// `occurrences` is the count for exactly that identity, so two different
/// provider, phase, or reason failures never merge into one fact.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RefreshIssueFact {
    kind: RefreshIssueKind,
    reason: RefreshIssueReason,
    provider_id: Option<ProviderId>,
    occurrences: u64,
}

impl RefreshIssueFact {
    /// Creates one fact with an explicit positive occurrence count.
    ///
    /// A provider-owned reason requires the provider identity that produced
    /// it, and a local or composed-scope reason must not carry one, so a fact
    /// can never lose or invent the attribution its reason implies.
    pub fn new(
        kind: RefreshIssueKind,
        reason: RefreshIssueReason,
        provider_id: Option<ProviderId>,
        occurrences: u64,
    ) -> Result<Self, RefreshIssueError> {
        if occurrences == 0 || !refresh_issue_representation_fits(occurrences) {
            return Err(RefreshIssueError);
        }
        if !refresh_issue_identity_is_valid(kind, reason, provider_id) {
            return Err(RefreshIssueError);
        }
        Ok(Self {
            kind,
            reason,
            provider_id,
            occurrences,
        })
    }

    /// Converts one hydration issue without discarding its typed reason.
    pub fn from_hydration_issue(issue: HydrationIssue) -> Result<Self, RefreshIssueError> {
        Self::from_hydration_parts(issue.kind(), issue.source(), issue.provider_id())
    }

    /// Converts already-normalized hydration issue parts.
    ///
    /// The typed origin is preserved instead of being flattened into a
    /// presentation string, so a durable refresh fact stays as actionable as
    /// the hydration issue that produced it without exposing raw provider
    /// transport detail.
    pub fn from_hydration_parts(
        kind: HydrationIssueKind,
        source: HydrationIssueSource,
        provider_id: Option<ProviderId>,
    ) -> Result<Self, RefreshIssueError> {
        let reason = match source {
            HydrationIssueSource::Provider(error) => match error {
                HydrationProviderError::AuthenticationFailed => {
                    RefreshIssueReason::ProviderAuthenticationFailed
                }
                HydrationProviderError::AuthorizationFailed => {
                    RefreshIssueReason::ProviderAuthorizationFailed
                }
                HydrationProviderError::Misconfigured => RefreshIssueReason::ProviderMisconfigured,
                HydrationProviderError::RateLimited => RefreshIssueReason::ProviderRateLimited,
                HydrationProviderError::Timeout => RefreshIssueReason::ProviderTimeout,
                HydrationProviderError::Unavailable => RefreshIssueReason::ProviderUnavailable,
                HydrationProviderError::InvalidResponse => {
                    RefreshIssueReason::ProviderInvalidResponse
                }
                HydrationProviderError::UnsupportedCapability => {
                    RefreshIssueReason::ProviderUnsupportedCapability
                }
            },
            HydrationIssueSource::AssetStore(error) => match error {
                ArtworkAssetStoreError::TooLarge => RefreshIssueReason::ArtworkAssetTooLarge,
                ArtworkAssetStoreError::InvalidImage => {
                    RefreshIssueReason::ArtworkAssetInvalidImage
                }
                ArtworkAssetStoreError::DimensionsTooLarge => {
                    RefreshIssueReason::ArtworkAssetDimensionsTooLarge
                }
                ArtworkAssetStoreError::Unavailable => {
                    RefreshIssueReason::ArtworkAssetStoreUnavailable
                }
            },
        };
        Self::new(
            RefreshIssueKind::from_hydration_kind(kind),
            reason,
            provider_id,
            1,
        )
    }

    /// Returns the broad issue category.
    pub const fn kind(self) -> RefreshIssueKind {
        self.kind
    }

    /// Returns the actionable issue reason.
    pub const fn reason(self) -> RefreshIssueReason {
        self.reason
    }

    /// Returns the provider that caused the issue, if applicable.
    pub const fn provider_id(self) -> Option<ProviderId> {
        self.provider_id
    }

    /// Returns the occurrence count for this exact fact identity.
    pub const fn occurrences(self) -> u64 {
        self.occurrences
    }

    fn identity_cmp(&self, other: &Self) -> Ordering {
        (self.kind, self.reason, self.provider_id).cmp(&(
            other.kind,
            other.reason,
            other.provider_id,
        ))
    }
}

/// Bounded durable refresh issue summary for one refresh execution.
///
/// The summary is the single authority for both the terminal lifecycle choice
/// and the explanatory detail: `issue_count` is always the checked sum of the
/// fact occurrences it carries.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RefreshIssueSummary {
    issue_count: u64,
    facts: Vec<RefreshIssueFact>,
}

impl RefreshIssueSummary {
    /// Maximum number of distinct facts one summary may retain.
    ///
    /// Every fact identity is the complete typed tuple
    /// `(kind, reason, provider_id)`, and the closed vocabulary admits exactly
    /// 113 of them: 96 provider-owned identities (four provider-facing
    /// categories x eight provider reasons x three provider identities), four
    /// artwork-store identities, ten content identities, and three
    /// composed-scope identities. This bound is therefore unreachable for a
    /// truthfully constructed summary. It still exists as an independent
    /// durable bound so a corrupted or incompatible representation is rejected
    /// before it can be materialized.
    pub const MAX_FACTS: usize = 128;

    /// Creates the canonical empty summary for a clean refresh.
    pub fn empty() -> Self {
        Self {
            issue_count: 0,
            facts: Vec::new(),
        }
    }

    /// Creates one summary from already-aggregated facts.
    ///
    /// Facts must be strictly ascending and unique by their complete typed
    /// identity so the durable representation stays deterministic. Every
    /// occurrence must be positive and representable, and the total uses
    /// checked arithmetic so an invalid projection is rejected instead of
    /// wrapping or saturating.
    pub fn from_facts(facts: Vec<RefreshIssueFact>) -> Result<Self, RefreshIssueError> {
        if facts.len() > Self::MAX_FACTS {
            return Err(RefreshIssueError);
        }
        let mut issue_count = 0_u64;
        let mut previous: Option<&RefreshIssueFact> = None;
        for fact in &facts {
            if fact.occurrences == 0 || !refresh_issue_representation_fits(fact.occurrences) {
                return Err(RefreshIssueError);
            }
            if let Some(previous) = previous
                && previous.identity_cmp(fact) != Ordering::Less
            {
                return Err(RefreshIssueError);
            }
            issue_count = issue_count
                .checked_add(fact.occurrences)
                .ok_or(RefreshIssueError)?;
            previous = Some(fact);
        }
        if !refresh_issue_representation_fits(issue_count) {
            return Err(RefreshIssueError);
        }
        Ok(Self { issue_count, facts })
    }

    /// Returns the checked total issue count.
    pub const fn issue_count(&self) -> u64 {
        self.issue_count
    }

    /// Returns the bounded deterministic issue facts.
    pub fn facts(&self) -> &[RefreshIssueFact] {
        &self.facts
    }
}

/// Deterministic accumulator for one refresh execution's issue facts.
///
/// Only execution branches that already counted toward a partial-success
/// `issue_count` are recorded here. Failures the owning execution path
/// propagates stay propagated and never reach this accumulator.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct RefreshIssueAccumulator {
    counts: BTreeMap<(RefreshIssueKind, RefreshIssueReason, Option<ProviderId>), u64>,
}

impl RefreshIssueAccumulator {
    /// Creates one empty accumulator.
    pub fn new() -> Self {
        Self::default()
    }

    /// Records exactly one occurrence of one typed issue.
    pub fn record(
        &mut self,
        kind: RefreshIssueKind,
        reason: RefreshIssueReason,
        provider_id: Option<ProviderId>,
    ) -> Result<(), RefreshIssueError> {
        self.record_count(kind, reason, provider_id, 1)
    }

    /// Records one hydration issue, preserving its typed reason.
    pub fn record_hydration_issue(
        &mut self,
        issue: HydrationIssue,
    ) -> Result<(), RefreshIssueError> {
        let fact = RefreshIssueFact::from_hydration_issue(issue)?;
        self.record_count(fact.kind, fact.reason, fact.provider_id, fact.occurrences)
    }

    /// Records every hydration issue retained by one report.
    pub fn record_hydration_issues(
        &mut self,
        issues: &[HydrationIssue],
    ) -> Result<(), RefreshIssueError> {
        for issue in issues {
            self.record_hydration_issue(*issue)?;
        }
        Ok(())
    }

    /// Merges another accumulator's occurrences into this one.
    ///
    /// Identical typed identities aggregate, so composing several roots cannot
    /// create duplicate facts or lose the source of any occurrence.
    pub fn merge(&mut self, other: &Self) -> Result<(), RefreshIssueError> {
        for ((kind, reason, provider_id), occurrences) in &other.counts {
            self.record_count(*kind, *reason, *provider_id, *occurrences)?;
        }
        Ok(())
    }

    /// Records several occurrences of one typed issue.
    pub fn record_count(
        &mut self,
        kind: RefreshIssueKind,
        reason: RefreshIssueReason,
        provider_id: Option<ProviderId>,
        occurrences: u64,
    ) -> Result<(), RefreshIssueError> {
        if occurrences == 0 || !refresh_issue_representation_fits(occurrences) {
            return Err(RefreshIssueError);
        }
        if !refresh_issue_identity_is_valid(kind, reason, provider_id) {
            return Err(RefreshIssueError);
        }
        let entry = self
            .counts
            .entry((kind, reason, provider_id))
            .or_insert(0_u64);
        let next = entry.checked_add(occurrences).ok_or(RefreshIssueError)?;
        if !refresh_issue_representation_fits(next) {
            return Err(RefreshIssueError);
        }
        // Assigning only after the complete check keeps a rejected occurrence
        // from leaving a partially updated count behind.
        *entry = next;
        Ok(())
    }

    /// Returns the checked total recorded so far.
    pub fn issue_count(&self) -> Result<u64, RefreshIssueError> {
        let mut total = 0_u64;
        for value in self.counts.values() {
            total = total.checked_add(*value).ok_or(RefreshIssueError)?;
        }
        if !refresh_issue_representation_fits(total) {
            return Err(RefreshIssueError);
        }
        Ok(total)
    }

    /// Converts the accumulated facts into one validated summary.
    pub fn finish(self) -> Result<RefreshIssueSummary, RefreshIssueError> {
        let facts = self
            .counts
            .into_iter()
            .map(|((kind, reason, provider_id), occurrences)| {
                RefreshIssueFact::new(kind, reason, provider_id, occurrences)
            })
            .collect::<Result<Vec<_>, _>>()?;
        RefreshIssueSummary::from_facts(facts)
    }
}

/// Durable refresh-issue persistence owned by one refresh execution.
///
/// This is job/refresh-operation persistence rather than enrichment
/// persistence, so it stays off the shared enrichment scope and only refresh
/// execution acquires it.
pub trait RefreshIssueRepository {
    /// Atomically replaces the durable issue summary and its facts.
    ///
    /// The summary and every one of its facts are written inside the caller's
    /// transaction, so a partially written projection can never be read back.
    fn replace_for_job(
        &mut self,
        job_run_id: JobRunId,
        summary: &RefreshIssueSummary,
    ) -> Result<(), PersistenceError>;
}
