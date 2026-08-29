//! Focused Phase 003 product contracts shared by Library, onboarding, and
//! settings clients.
//!
//! These values describe durable intent and command outcomes. They do not
//! perform source, provider, or artwork work; those responsibilities remain
//! with the existing focused capabilities and the runtime operation handlers.

use crate::{
    ApplicationError, ApplicationPortError, ArtworkAssetStore, ArtworkResolutionPolicy,
    EnrichmentProviderSession, HydrationReport, HydrationTarget, LibraryRootId,
    MetadataProviderReadinessProjection, MetadataProviderRegistry, MetadataProviderSettings,
    MetadataResolutionPolicy, MetadataSettings, OperationContext, OperationHandle,
    TransformationFailure, UnitOfWorkFactory,
};

/// Maps an infrastructure transformation result to the published application
/// error catalog without exposing decoder-specific error types.
pub const fn map_transformation_failure(failure: TransformationFailure) -> crate::ErrorCode {
    match failure {
        TransformationFailure::NotApplicable | TransformationFailure::UnsupportedFeature => {
            crate::ErrorCode::ValidationContentUnsupportedRepresentation
        }
        TransformationFailure::Malformed => crate::ErrorCode::ValidationContentMalformed,
        TransformationFailure::EncryptedUnsupported => {
            crate::ErrorCode::ValidationContentEncryptedUnsupported
        }
        TransformationFailure::MultiGameUnsupported => {
            crate::ErrorCode::ValidationMultiGameContainerUnsupported
        }
        TransformationFailure::MissingDependency => {
            crate::ErrorCode::FilesystemContentDependencyMissing
        }
        TransformationFailure::AmbiguousRecognition => {
            crate::ErrorCode::ValidationContentRecognitionAmbiguous
        }
        TransformationFailure::ResourceLimitExceeded => {
            crate::ErrorCode::OperationTransformationResourceLimitExceeded
        }
        TransformationFailure::Cancelled => crate::ErrorCode::OperationCancelled,
        TransformationFailure::ReadFailure => {
            crate::ErrorCode::FilesystemSourceValidationIndeterminate
        }
        TransformationFailure::SourceChanged => {
            crate::ErrorCode::OperationSourceChangedDuringProcessing
        }
    }
}

/// The privacy-terms version currently required before provider work.
pub const CURRENT_PRIVACY_TERMS_VERSION: &str = "phase-003-v1";

/// Safe privacy-consent projection owned by Settings.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PrivacyConsent {
    accepted_terms_version: Option<String>,
    accepted_at_ms: Option<i64>,
    required_terms_version: String,
}

impl PrivacyConsent {
    /// Builds the projection from the one durable consent authority.
    pub fn new(
        accepted_terms_version: Option<String>,
        accepted_at_ms: Option<i64>,
        required_terms_version: impl Into<String>,
    ) -> Self {
        let required_terms_version = required_terms_version.into();
        Self {
            accepted_terms_version,
            accepted_at_ms,
            required_terms_version,
        }
    }

    /// Returns the accepted terms version, if one is stored.
    pub fn accepted_terms_version(&self) -> Option<&str> {
        self.accepted_terms_version.as_deref()
    }

    /// Returns the acceptance timestamp, if one is stored.
    pub const fn accepted_at_ms(&self) -> Option<i64> {
        self.accepted_at_ms
    }

    /// Returns the current backend-advertised terms version.
    pub fn required_terms_version(&self) -> &str {
        &self.required_terms_version
    }

    /// Returns whether the stored consent satisfies the current version.
    pub fn satisfies_current_required_terms(&self) -> bool {
        self.accepted_terms_version.as_deref() == Some(self.required_terms_version.as_str())
    }
}

/// Closed provider setup outcome stored by product onboarding.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryProviderSetupOutcome {
    /// The user has not completed the provider step.
    Pending,
    /// The user elected to configure the credentialed provider.
    Configured,
    /// The user explicitly skipped provider setup.
    Skipped,
}

impl LibraryProviderSetupOutcome {
    /// Returns the stable serialized value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Configured => "configured",
            Self::Skipped => "skipped",
        }
    }
}

impl TryFrom<&str> for LibraryProviderSetupOutcome {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "pending" => Ok(Self::Pending),
            "configured" => Ok(Self::Configured),
            "skipped" => Ok(Self::Skipped),
            _ => Err(()),
        }
    }
}

/// Closed command vocabulary for the provider setup step.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryProviderSetupDecision {
    /// Record the configured outcome after credential authority is checked.
    Configured,
    /// Record the skipped outcome after confirming no credential is stored.
    Skipped,
}

/// Durable product-onboarding facts. Root count and current credential
/// readiness are supplied by their owning capabilities when projected.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryOnboardingProgress {
    accepted_privacy_terms_version: Option<String>,
    accepted_privacy_at_ms: Option<i64>,
    metadata_preferences_confirmed: bool,
    provider_setup_outcome: LibraryProviderSetupOutcome,
    completed_at_ms: Option<i64>,
}

impl Default for LibraryOnboardingProgress {
    fn default() -> Self {
        Self {
            accepted_privacy_terms_version: None,
            accepted_privacy_at_ms: None,
            metadata_preferences_confirmed: false,
            provider_setup_outcome: LibraryProviderSetupOutcome::Pending,
            completed_at_ms: None,
        }
    }
}

impl LibraryOnboardingProgress {
    /// Creates an incomplete onboarding record.
    pub fn new() -> Self {
        Self::default()
    }

    /// Creates a persisted progress record from storage values.
    pub fn from_persisted(
        accepted_privacy_terms_version: Option<String>,
        accepted_privacy_at_ms: Option<i64>,
        metadata_preferences_confirmed: bool,
        provider_setup_outcome: LibraryProviderSetupOutcome,
        completed_at_ms: Option<i64>,
    ) -> Self {
        Self {
            accepted_privacy_terms_version,
            accepted_privacy_at_ms,
            metadata_preferences_confirmed,
            provider_setup_outcome,
            completed_at_ms,
        }
    }

    /// Returns the accepted terms version, if any.
    pub fn accepted_privacy_terms_version(&self) -> Option<&str> {
        self.accepted_privacy_terms_version.as_deref()
    }

    /// Returns the acceptance timestamp, if any.
    pub const fn accepted_privacy_at_ms(&self) -> Option<i64> {
        self.accepted_privacy_at_ms
    }

    /// Returns whether metadata preferences were confirmed.
    pub const fn metadata_preferences_confirmed(&self) -> bool {
        self.metadata_preferences_confirmed
    }

    /// Returns the provider setup outcome.
    pub const fn provider_setup_outcome(&self) -> LibraryProviderSetupOutcome {
        self.provider_setup_outcome
    }

    /// Returns the completion timestamp, if onboarding has completed.
    pub const fn completed_at_ms(&self) -> Option<i64> {
        self.completed_at_ms
    }

    /// Accepts the current terms version.
    pub fn accept_privacy_terms(&mut self, version: impl Into<String>, accepted_at_ms: i64) {
        self.accepted_privacy_terms_version = Some(version.into());
        self.accepted_privacy_at_ms = Some(accepted_at_ms);
    }

    /// Marks the preference step confirmed.
    pub const fn confirm_metadata_preferences(&mut self) {
        self.metadata_preferences_confirmed = true;
    }

    /// Records one validated provider setup decision.
    pub const fn record_provider_setup(&mut self, decision: LibraryProviderSetupDecision) {
        self.provider_setup_outcome = match decision {
            LibraryProviderSetupDecision::Configured => LibraryProviderSetupOutcome::Configured,
            LibraryProviderSetupDecision::Skipped => LibraryProviderSetupOutcome::Skipped,
        };
    }

    /// Commits onboarding completion after all prerequisites have been checked.
    pub const fn complete(&mut self, completed_at_ms: i64) {
        self.completed_at_ms = Some(completed_at_ms);
    }
}

/// Query projection of durable onboarding plus current prerequisite facts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryOnboardingState {
    progress: LibraryOnboardingProgress,
    required_privacy_terms_version: String,
    requires_root_selection: bool,
    credential_configured: bool,
}

impl LibraryOnboardingState {
    /// Builds a projection without persisting or performing provider I/O.
    pub fn new(
        progress: LibraryOnboardingProgress,
        required_privacy_terms_version: impl Into<String>,
        requires_root_selection: bool,
        credential_configured: bool,
    ) -> Self {
        Self {
            progress,
            required_privacy_terms_version: required_privacy_terms_version.into(),
            requires_root_selection,
            credential_configured,
        }
    }

    /// Returns the persisted progress facts.
    pub const fn progress(&self) -> &LibraryOnboardingProgress {
        &self.progress
    }

    /// Returns the current required privacy-terms version.
    pub fn required_privacy_terms_version(&self) -> &str {
        &self.required_privacy_terms_version
    }

    /// Returns whether current consent is missing or obsolete.
    pub fn requires_privacy_acceptance(&self) -> bool {
        self.progress.accepted_privacy_terms_version()
            != Some(self.required_privacy_terms_version())
    }

    /// Returns whether a root is still required for completion.
    pub const fn requires_root_selection(&self) -> bool {
        self.requires_root_selection
    }

    /// Returns the current credential-presence fact.
    pub const fn credential_configured(&self) -> bool {
        self.credential_configured
    }

    /// Returns whether the durable completion fact is present and current.
    pub fn complete(&self) -> bool {
        self.progress.completed_at_ms().is_some()
            && !self.requires_privacy_acceptance()
            && self.progress.metadata_preferences_confirmed()
            && matches!(
                self.progress.provider_setup_outcome(),
                LibraryProviderSetupOutcome::Configured | LibraryProviderSetupOutcome::Skipped
            )
    }
}

/// Result of adding a root and admitting its composed refresh independently.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AddLibraryRootAndRefreshResult {
    /// Root persistence and refresh admission both succeeded.
    AddedAndRefreshAdmitted(crate::LibraryRootProjection, OperationHandle),
    /// Root persistence succeeded; refresh admission failed independently.
    AddedButRefreshNotAdmitted(crate::LibraryRootProjection, ApplicationError),
    /// The exact root was already configured; no refresh was admitted.
    AlreadyConfigured(LibraryRootId),
    /// The selection overlaps an existing root.
    OverlapsExisting(LibraryRootId, crate::RootRelationship),
}

/// Result of committing onboarding completion and then trying to admit refresh.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CompleteLibraryOnboardingAndRefreshResult {
    /// Completion and initial refresh admission both succeeded.
    OnboardingCompletedAndRefreshAdmitted(LibraryOnboardingState, OperationHandle),
    /// Completion committed but refresh admission failed independently.
    OnboardingCompletedButRefreshNotAdmitted(LibraryOnboardingState, ApplicationError),
}

/// Result of a metadata-preference update.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MetadataSettingsUpdateResult {
    /// Settings changed without a resolution job being needed.
    CommittedNoResolutionWork(MetadataSettings),
    /// Settings changed and a local-only resolution job was admitted.
    CommittedAndResolutionAdmitted(MetadataSettings, OperationHandle),
    /// Settings changed but later resolution admission failed.
    CommittedButResolutionNotAdmitted(MetadataSettings, ApplicationError),
}

/// Result of a provider-enablement update.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MetadataProviderSettingsUpdateResult {
    /// Settings changed without a resolution job being needed.
    CommittedNoResolutionWork(MetadataProviderSettings),
    /// Settings changed and a local-only resolution job was admitted.
    CommittedAndResolutionAdmitted(MetadataProviderSettings, OperationHandle),
    /// Settings changed but later resolution admission failed.
    CommittedButResolutionNotAdmitted(MetadataProviderSettings, ApplicationError),
}

/// Thin Phase 003 composition point for one already-admitted enrichment pass.
///
/// Scan planning, canonical identity, grouping, provider eligibility, metadata
/// resolution, and artwork policy remain owned by their focused capabilities.
/// This type only gives the Library refresh boundary a stable place to compose
/// the existing hydration capability without owning JobRun scheduling.
pub struct LibraryRefreshCoordinator<F> {
    hydration: crate::HydrationCoordinator<F>,
}

impl<F> LibraryRefreshCoordinator<F>
where
    F: UnitOfWorkFactory,
    for<'scope> F::Scope<'scope>: crate::EnrichmentUnitOfWork,
{
    /// Creates a coordinator over the existing transaction factory.
    pub const fn new(unit_of_work: F) -> Self {
        Self {
            hydration: crate::HydrationCoordinator::new(unit_of_work),
        }
    }

    /// Delegates one identified target to the existing hydration policy.
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
        self.hydration.hydrate(
            context,
            target,
            metadata_policy,
            artwork_policy,
            registry,
            readiness,
            sessions,
            asset_store,
            now,
        )
    }

    /// Delegates one identified target to local resolution of committed data.
    ///
    /// The coordinator does not discover mappings, contact providers, or
    /// download artwork. Those responsibilities stay with the focused
    /// hydration and persistence capabilities.
    pub fn resolve_existing(
        &self,
        context: &OperationContext,
        target: HydrationTarget,
        metadata_policy: MetadataResolutionPolicy,
        artwork_policy: ArtworkResolutionPolicy,
        now: i64,
    ) -> Result<HydrationReport, ApplicationPortError> {
        self.hydration
            .resolve_existing(context, target, metadata_policy, artwork_policy, now)
    }
}
