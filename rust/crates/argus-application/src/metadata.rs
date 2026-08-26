use std::collections::BTreeSet;

use argus_domain::{GameContentId, PlatformId};

use crate::PersistenceError;

/// Production metadata provider identity.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum ProviderId {
    /// Exact content matching and supported enrichment mappings.
    Playmatch,
    /// Platform metadata and artwork provider.
    GameTdb,
    /// Credentialed artwork provider.
    SteamGridDb,
}

impl ProviderId {
    /// Returns the stable persisted provider identifier.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Playmatch => "playmatch",
            Self::GameTdb => "gametdb",
            Self::SteamGridDb => "steamgriddb",
        }
    }
}

impl TryFrom<&str> for ProviderId {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "playmatch" => Ok(Self::Playmatch),
            "gametdb" => Ok(Self::GameTdb),
            "steamgriddb" => Ok(Self::SteamGridDb),
            _ => Err(()),
        }
    }
}

/// Provider-specific platform mapping outcome.
///
/// A provider may have an explicit native identifier for a platform or may
/// explicitly exclude that platform from a capability. The closed outcome
/// prevents a new `PlatformId` from being silently sent to every provider.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProviderPlatformMapping {
    /// Stable provider platform identifier used by the adapter request.
    Mapped(&'static str),
    /// The provider does not apply to this platform/capability.
    Unsupported,
}

impl ProviderPlatformMapping {
    /// Returns the native mapping when the provider applies.
    pub const fn mapped_id(self) -> Option<&'static str> {
        match self {
            Self::Mapped(value) => Some(value),
            Self::Unsupported => None,
        }
    }
}

impl ProviderId {
    /// Returns the explicit platform mapping for this provider.
    pub const fn platform_mapping(self, platform: PlatformId) -> ProviderPlatformMapping {
        match self {
            Self::Playmatch | Self::GameTdb => match platform {
                PlatformId::NintendoNes => ProviderPlatformMapping::Mapped("nintendo.nes"),
                PlatformId::NintendoFds => ProviderPlatformMapping::Mapped("nintendo.fds"),
                PlatformId::NintendoSnes => ProviderPlatformMapping::Mapped("nintendo.snes"),
                PlatformId::NintendoGb => ProviderPlatformMapping::Mapped("nintendo.gb"),
                PlatformId::NintendoGbc => ProviderPlatformMapping::Mapped("nintendo.gbc"),
                PlatformId::NintendoGba => ProviderPlatformMapping::Mapped("nintendo.gba"),
                PlatformId::NintendoN64 => ProviderPlatformMapping::Mapped("nintendo.n64"),
                PlatformId::NintendoNds => ProviderPlatformMapping::Mapped("nintendo.nds"),
                PlatformId::Nintendo3ds => ProviderPlatformMapping::Mapped("nintendo.3ds"),
                PlatformId::SegaSms => ProviderPlatformMapping::Mapped("sega.sms"),
                PlatformId::SegaGameGear => ProviderPlatformMapping::Mapped("sega.gamegear"),
                PlatformId::SegaGenesis => ProviderPlatformMapping::Mapped("sega.genesis"),
                PlatformId::Sega32x => ProviderPlatformMapping::Mapped("sega.32x"),
                PlatformId::NintendoGameCube => {
                    ProviderPlatformMapping::Mapped("nintendo.gamecube")
                }
                PlatformId::NintendoWii => ProviderPlatformMapping::Mapped("nintendo.wii"),
                PlatformId::SegaCd => ProviderPlatformMapping::Mapped("sega.sega-cd"),
                PlatformId::SegaSaturn => ProviderPlatformMapping::Mapped("sega.saturn"),
                PlatformId::SegaDreamcast => ProviderPlatformMapping::Mapped("sega.dreamcast"),
                PlatformId::SonyPlaystation => ProviderPlatformMapping::Mapped("sony.playstation"),
                PlatformId::SonyPlaystation2 => {
                    ProviderPlatformMapping::Mapped("sony.playstation2")
                }
                PlatformId::SonyPsp => ProviderPlatformMapping::Mapped("sony.psp"),
            },
            Self::SteamGridDb => match platform {
                PlatformId::NintendoNes
                | PlatformId::NintendoFds
                | PlatformId::NintendoSnes
                | PlatformId::NintendoGb
                | PlatformId::NintendoGbc
                | PlatformId::NintendoGba
                | PlatformId::NintendoN64
                | PlatformId::NintendoNds
                | PlatformId::Nintendo3ds
                | PlatformId::SegaSms
                | PlatformId::SegaGameGear
                | PlatformId::SegaGenesis
                | PlatformId::Sega32x
                | PlatformId::NintendoGameCube
                | PlatformId::NintendoWii
                | PlatformId::SegaCd
                | PlatformId::SegaSaturn
                | PlatformId::SegaDreamcast
                | PlatformId::SonyPlaystation
                | PlatformId::SonyPlaystation2
                | PlatformId::SonyPsp => ProviderPlatformMapping::Unsupported,
            },
        }
    }
}

/// Capability exposed by a production provider descriptor.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub enum ProviderCapability {
    /// Exact content/platform matching.
    ContentMatching,
    /// Provider-native metadata refresh.
    MetadataRefresh,
    /// Artwork discovery.
    ArtworkDiscovery,
}

/// Provider readiness state exposed by the application boundary.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ProviderReadinessState {
    /// The provider can be selected for the capability.
    Ready,
    /// The provider is retained but disabled by settings.
    Disabled,
    /// Required credential is absent.
    MissingCredentials,
    /// The configured credential was rejected.
    InvalidCredentials,
    /// Provider configuration is invalid.
    Misconfigured,
    /// Provider or secure storage is temporarily unavailable.
    Unavailable,
}

/// State of one persisted external identity mapping.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MappingState {
    /// The mapping is eligible for provider-native refresh.
    Current,
    /// The mapping is retained but requires revalidation.
    Stale,
    /// Evidence was retained but rejected by automatic policy.
    RejectedByPolicy,
}

impl MappingState {
    /// Returns the stable persisted mapping state.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Current => "current",
            Self::Stale => "stale",
            Self::RejectedByPolicy => "rejected_by_policy",
        }
    }
}

/// Provider-specific evidence class retained with one mapping.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MatchBasis {
    /// Playmatch exact strong-content binding.
    PlaymatchExactContent,
    /// GameTDB exact platform-native identifier.
    GameTdbExactNativeIdentifier,
    /// Refresh of an existing exact mapping.
    ExistingExactMapping,
    /// Evidence retained only for explainability.
    RejectedByPolicy,
}

impl MatchBasis {
    /// Returns the stable persisted evidence class.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::PlaymatchExactContent => "playmatch_exact_content",
            Self::GameTdbExactNativeIdentifier => "gametdb_exact_native_identifier",
            Self::ExistingExactMapping => "existing_exact_mapping",
            Self::RejectedByPolicy => "rejected_by_policy",
        }
    }
}

/// Durable external identity evidence associated with canonical content.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExternalIdentityMapping {
    game_content_id: GameContentId,
    provider_id: ProviderId,
    external_game_id: String,
    external_release_id: Option<String>,
    provider_platform_id: String,
    provider_confidence: Option<u16>,
    match_basis: MatchBasis,
    provider_revision: u64,
    state: MappingState,
    matched_at: i64,
    last_validated_at: i64,
}

impl ExternalIdentityMapping {
    /// Creates one provider mapping record.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        game_content_id: GameContentId,
        provider_id: ProviderId,
        external_game_id: impl Into<String>,
        external_release_id: Option<String>,
        provider_platform_id: impl Into<String>,
        provider_confidence: Option<u16>,
        match_basis: MatchBasis,
        provider_revision: u64,
        state: MappingState,
        matched_at: i64,
        last_validated_at: i64,
    ) -> Self {
        Self {
            game_content_id,
            provider_id,
            external_game_id: external_game_id.into(),
            external_release_id,
            provider_platform_id: provider_platform_id.into(),
            provider_confidence,
            match_basis,
            provider_revision,
            state,
            matched_at,
            last_validated_at,
        }
    }

    /// Returns the canonical content identity.
    pub const fn game_content_id(&self) -> GameContentId {
        self.game_content_id
    }

    /// Returns the provider identity.
    pub const fn provider_id(&self) -> ProviderId {
        self.provider_id
    }

    /// Returns the provider-native game identity.
    pub fn external_game_id(&self) -> &str {
        &self.external_game_id
    }

    /// Returns the optional provider-native release identity.
    pub fn external_release_id(&self) -> Option<&str> {
        self.external_release_id.as_deref()
    }

    /// Returns the mapping evidence class.
    pub const fn match_basis(&self) -> MatchBasis {
        self.match_basis
    }

    /// Returns the current/stale/rejected state.
    pub const fn state(&self) -> MappingState {
        self.state
    }

    /// Returns the provider revision that produced this evidence.
    pub const fn provider_revision(&self) -> u64 {
        self.provider_revision
    }

    /// Returns the provider platform identifier.
    pub fn provider_platform_id(&self) -> &str {
        &self.provider_platform_id
    }

    /// Returns the provider-local confidence, if supplied.
    pub const fn provider_confidence(&self) -> Option<u16> {
        self.provider_confidence
    }

    /// Returns the match timestamp.
    pub const fn matched_at(&self) -> i64 {
        self.matched_at
    }

    /// Returns the last validation timestamp.
    pub const fn last_validated_at(&self) -> i64 {
        self.last_validated_at
    }
}

/// Normalized provider-native metadata retained independently of resolution.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderMetadata {
    provider_id: ProviderId,
    external_game_id: String,
    provider_revision: u64,
    region: Option<String>,
    language: Option<String>,
    fetched_at: i64,
    expires_at: Option<i64>,
    title: Option<String>,
    alternate_titles: Vec<String>,
    description: Option<String>,
    release_date: Option<String>,
    developers: Vec<String>,
    publishers: Vec<String>,
    genres: Vec<String>,
    languages: Vec<String>,
    adapter_quality: u8,
    provenance: String,
    mapping_state: MappingState,
}

impl ProviderMetadata {
    /// Creates normalized provider metadata with bounded scalar fields.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        provider_id: ProviderId,
        external_game_id: impl Into<String>,
        provider_revision: u64,
        region: Option<String>,
        language: Option<String>,
        fetched_at: i64,
        expires_at: Option<i64>,
        title: Option<String>,
        alternate_titles: Vec<String>,
        description: Option<String>,
        release_date: Option<String>,
        developers: Vec<String>,
        publishers: Vec<String>,
        genres: Vec<String>,
        languages: Vec<String>,
        adapter_quality: u8,
        provenance: impl Into<String>,
    ) -> Self {
        Self {
            provider_id,
            external_game_id: external_game_id.into(),
            provider_revision,
            region,
            language,
            fetched_at,
            expires_at,
            title,
            alternate_titles,
            description,
            release_date,
            developers,
            publishers,
            genres,
            languages,
            adapter_quality,
            provenance: provenance.into(),
            mapping_state: MappingState::Current,
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

    /// Returns the stable provider revision.
    pub const fn provider_revision(&self) -> u64 {
        self.provider_revision
    }

    /// Returns the preferred region, if supplied.
    pub fn region(&self) -> Option<&str> {
        self.region.as_deref()
    }

    /// Returns the preferred language, if supplied.
    pub fn language(&self) -> Option<&str> {
        self.language.as_deref()
    }

    /// Returns the normalized title.
    pub fn title(&self) -> Option<&str> {
        self.title.as_deref()
    }

    /// Returns normalized alternate titles.
    pub fn alternate_titles(&self) -> &[String] {
        &self.alternate_titles
    }

    /// Returns the normalized description.
    pub fn description(&self) -> Option<&str> {
        self.description.as_deref()
    }

    /// Returns the normalized release date.
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }

    /// Returns normalized developers.
    pub fn developers(&self) -> &[String] {
        &self.developers
    }

    /// Returns normalized publishers.
    pub fn publishers(&self) -> &[String] {
        &self.publishers
    }

    /// Returns normalized genres.
    pub fn genres(&self) -> &[String] {
        &self.genres
    }

    /// Returns normalized provider languages.
    pub fn languages(&self) -> &[String] {
        &self.languages
    }

    /// Returns the fetch timestamp.
    pub const fn fetched_at(&self) -> i64 {
        self.fetched_at
    }

    /// Returns the optional expiry timestamp.
    pub const fn expires_at(&self) -> Option<i64> {
        self.expires_at
    }

    /// Returns provider-native provenance.
    pub fn provenance(&self) -> &str {
        &self.provenance
    }

    /// Returns whether this record is expired at the supplied timestamp.
    pub fn is_expired(&self, now: i64) -> bool {
        self.expires_at.is_some_and(|expires_at| expires_at <= now)
    }

    /// Returns the adapter-understood quality score.
    pub const fn adapter_quality(&self) -> u8 {
        self.adapter_quality
    }

    /// Associates the native record with the mapping state that admitted it.
    pub fn with_mapping_state(mut self, state: MappingState) -> Self {
        self.mapping_state = state;
        self
    }

    /// Returns the current/stale state of the mapping that admitted the record.
    pub const fn mapping_state(&self) -> MappingState {
        self.mapping_state
    }
}

/// Typed metadata preferences persisted independently from provider readiness.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct MetadataSettings {
    preferred_regions: Vec<String>,
    preferred_languages: Vec<String>,
}

impl MetadataSettings {
    /// Creates local resolution preferences.
    pub fn new<R, L>(preferred_regions: R, preferred_languages: L) -> Self
    where
        R: IntoIterator,
        R::Item: Into<String>,
        L: IntoIterator,
        L::Item: Into<String>,
    {
        Self {
            preferred_regions: preferred_regions.into_iter().map(Into::into).collect(),
            preferred_languages: preferred_languages.into_iter().map(Into::into).collect(),
        }
    }

    /// Returns preferred regions in priority order.
    pub fn preferred_regions(&self) -> &[String] {
        &self.preferred_regions
    }

    /// Returns preferred languages in priority order.
    pub fn preferred_languages(&self) -> &[String] {
        &self.preferred_languages
    }
}

/// Transaction-bound metadata persistence port.
pub trait MetadataRepository {
    /// Persists one external identity mapping.
    fn save_mapping(&mut self, mapping: &ExternalIdentityMapping) -> Result<(), PersistenceError>;

    /// Persists one provider-native metadata record.
    fn save_provider_metadata(
        &mut self,
        metadata: &ProviderMetadata,
    ) -> Result<(), PersistenceError>;

    /// Persists one Game-level resolved metadata projection.
    fn save_resolved_metadata(
        &mut self,
        game_id: argus_domain::GameId,
        metadata: &ResolvedMetadata,
    ) -> Result<(), PersistenceError>;

    /// Persists typed metadata preferences without starting resolution.
    fn save_settings(&mut self, settings: &MetadataSettings) -> Result<(), PersistenceError>;

    /// Reads typed metadata preferences from this transaction.
    fn settings(&mut self) -> Result<MetadataSettings, PersistenceError>;

    /// Reads the monotonic metadata-preference revision captured by settings
    /// commits. Implementations without revisioned storage retain a stable
    /// zero for source compatibility with focused test doubles.
    fn settings_revision(&mut self) -> Result<u64, PersistenceError> {
        Ok(0)
    }

    /// Persists provider enablement without starting local resolution.
    fn save_provider_settings(
        &mut self,
        settings: &MetadataProviderSettings,
    ) -> Result<(), PersistenceError>;

    /// Reads provider enablement from this transaction.
    fn provider_settings(&mut self) -> Result<MetadataProviderSettings, PersistenceError>;

    /// Reads accepted/stale provider metadata joined to one canonical content
    /// identity for a later local-only resolution pass.
    fn provider_metadata_for_content(
        &mut self,
        _game_content_id: GameContentId,
    ) -> Result<Vec<ProviderMetadata>, PersistenceError> {
        Err(PersistenceError::Internal)
    }

    /// Reads durable identity mappings for one canonical content unit. The
    /// local-resolution pass filters these records to current mappings before
    /// consulting already committed provider metadata or artwork references.
    fn mappings_for_content(
        &mut self,
        _game_content_id: GameContentId,
    ) -> Result<Vec<ExternalIdentityMapping>, PersistenceError> {
        Err(PersistenceError::Internal)
    }

    /// Reads the latest Game-level resolved metadata projection.
    fn resolved_metadata_for_game(
        &mut self,
        _game_id: argus_domain::GameId,
    ) -> Result<Option<ResolvedMetadata>, PersistenceError> {
        Ok(None)
    }

    /// Reads durable product-onboarding progress. Implementations that do not
    /// activate Phase 003 return the incomplete default without affecting
    /// existing metadata test doubles.
    fn library_onboarding_progress(
        &mut self,
    ) -> Result<crate::LibraryOnboardingProgress, PersistenceError> {
        Ok(crate::LibraryOnboardingProgress::default())
    }

    /// Persists durable product-onboarding progress in the current transaction.
    fn save_library_onboarding_progress(
        &mut self,
        _progress: &crate::LibraryOnboardingProgress,
    ) -> Result<(), PersistenceError> {
        Ok(())
    }
}

/// Failure while storing or removing a provider credential.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CredentialMutationError {
    /// The secure credential store could not complete the operation.
    StoreUnavailable,
    /// The requested provider does not support credentials in this slice.
    UnsupportedProvider,
}

/// Provider validation result after a secure write.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CredentialValidationError {
    /// The credential was rejected by the provider.
    InvalidCredentials,
    /// Validation could not complete because the provider was unavailable.
    Unavailable,
    /// The provider rejected the request as malformed or misconfigured.
    Misconfigured,
}

/// Rust-owned secure credential boundary.
pub trait SecureCredentialStore {
    /// Writes one credential without exposing storage details.
    fn set(
        &mut self,
        provider_id: ProviderId,
        secret: &[u8],
    ) -> Result<(), CredentialMutationError>;

    /// Removes one credential.
    fn remove(&mut self, provider_id: ProviderId) -> Result<(), CredentialMutationError>;

    /// Returns whether one credential is configured.
    fn is_configured(&mut self, provider_id: ProviderId) -> Result<bool, CredentialMutationError>;

    /// Runs a transient operation over secret bytes without returning them.
    fn with_secret<T>(
        &mut self,
        provider_id: ProviderId,
        operation: &mut dyn FnMut(&[u8]) -> T,
    ) -> Result<T, CredentialMutationError>;
}

/// Provider-specific credential validation port.
pub trait CredentialValidator {
    /// Validates a credential using infrastructure-owned provider I/O.
    fn validate(&self, secret: &[u8]) -> Result<(), CredentialValidationError>;
}

/// Safe readiness projection for one provider credential.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MetadataProviderReadiness {
    provider_id: ProviderId,
    state: ProviderReadinessState,
    credential_configured: bool,
}

impl MetadataProviderReadiness {
    fn new(
        provider_id: ProviderId,
        state: ProviderReadinessState,
        credential_configured: bool,
    ) -> Self {
        Self {
            provider_id,
            state,
            credential_configured,
        }
    }

    /// Returns the provider identity.
    pub const fn provider_id(self) -> ProviderId {
        self.provider_id
    }

    /// Returns the safe readiness state.
    pub const fn state(self) -> ProviderReadinessState {
        self.state
    }

    /// Returns whether secure storage authoritatively contains a credential.
    pub const fn credential_configured(self) -> bool {
        self.credential_configured
    }
}

/// Capability-specific readiness exposed by the provider list query.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ProviderCapabilityReadiness {
    capability: ProviderCapability,
    state: ProviderReadinessState,
}

impl ProviderCapabilityReadiness {
    fn new(capability: ProviderCapability, state: ProviderReadinessState) -> Self {
        Self { capability, state }
    }

    /// Returns the declared capability.
    pub const fn capability(self) -> ProviderCapability {
        self.capability
    }

    /// Returns the current capability readiness.
    pub const fn state(self) -> ProviderReadinessState {
        self.state
    }
}

/// Safe, network-free provider readiness projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataProviderReadinessProjection {
    provider_id: ProviderId,
    enabled: bool,
    capability_readiness: Vec<ProviderCapabilityReadiness>,
    credential_configured: bool,
}

impl MetadataProviderReadinessProjection {
    fn new(
        provider_id: ProviderId,
        enabled: bool,
        capability_readiness: Vec<ProviderCapabilityReadiness>,
        credential_configured: bool,
    ) -> Self {
        Self {
            provider_id,
            enabled,
            capability_readiness,
            credential_configured,
        }
    }

    /// Returns the provider identity.
    pub const fn provider_id(&self) -> ProviderId {
        self.provider_id
    }

    /// Returns whether policy currently enables this provider.
    pub const fn enabled(&self) -> bool {
        self.enabled
    }

    /// Returns capability-specific readiness values in descriptor order.
    pub fn capability_readiness(&self) -> &[ProviderCapabilityReadiness] {
        &self.capability_readiness
    }

    /// Returns whether secure storage contains the provider credential.
    pub const fn credential_configured(&self) -> bool {
        self.credential_configured
    }
}

/// Application-owned write-only credential service.
pub struct MetadataProviderService<S, V> {
    store: S,
    validator: V,
    readiness: MetadataProviderReadiness,
}

impl<S, V> MetadataProviderService<S, V>
where
    S: SecureCredentialStore,
    V: CredentialValidator,
{
    /// Creates a service with no configured SteamGridDB credential projection.
    pub fn new(store: S, validator: V) -> Self {
        Self {
            store,
            validator,
            readiness: MetadataProviderReadiness::new(
                ProviderId::SteamGridDb,
                ProviderReadinessState::MissingCredentials,
                false,
            ),
        }
    }

    /// Securely stores and explicitly validates a SteamGridDB credential.
    pub fn set_steamgriddb_credential(
        &mut self,
        secret: &[u8],
    ) -> Result<MetadataProviderReadiness, CredentialMutationError> {
        if secret.is_empty() {
            return Err(CredentialMutationError::UnsupportedProvider);
        }
        self.store.set(ProviderId::SteamGridDb, secret)?;
        let mut validate = |value: &[u8]| self.validator.validate(value);
        let validation = match self
            .store
            .with_secret(ProviderId::SteamGridDb, &mut validate)
        {
            Ok(validation) => validation,
            Err(error) => {
                self.readiness = MetadataProviderReadiness::new(
                    ProviderId::SteamGridDb,
                    ProviderReadinessState::Unavailable,
                    true,
                );
                return Err(error);
            }
        };
        let state = match validation {
            Ok(()) => ProviderReadinessState::Ready,
            Err(CredentialValidationError::InvalidCredentials) => {
                ProviderReadinessState::InvalidCredentials
            }
            Err(CredentialValidationError::Unavailable) => ProviderReadinessState::Unavailable,
            Err(CredentialValidationError::Misconfigured) => ProviderReadinessState::Misconfigured,
        };
        self.readiness = MetadataProviderReadiness::new(ProviderId::SteamGridDb, state, true);
        Ok(self.readiness)
    }

    /// Stores a credential for a supported credentialed provider.
    ///
    /// Provider identity is validated at this application boundary so the
    /// bridge can remain a typed write-only transport instead of encoding
    /// provider-specific credential authority in Flutter.
    pub fn set_credential(
        &mut self,
        provider_id: ProviderId,
        secret: &[u8],
    ) -> Result<MetadataProviderReadiness, CredentialMutationError> {
        match provider_id {
            ProviderId::SteamGridDb => self.set_steamgriddb_credential(secret),
            ProviderId::Playmatch | ProviderId::GameTdb => {
                Err(CredentialMutationError::UnsupportedProvider)
            }
        }
    }

    /// Removes the SteamGridDB credential and returns missing-credential state.
    pub fn remove_steamgriddb_credential(
        &mut self,
    ) -> Result<MetadataProviderReadiness, CredentialMutationError> {
        self.store.remove(ProviderId::SteamGridDb)?;
        self.readiness = MetadataProviderReadiness::new(
            ProviderId::SteamGridDb,
            ProviderReadinessState::MissingCredentials,
            false,
        );
        Ok(self.readiness)
    }

    /// Removes a credential for a supported credentialed provider.
    pub fn remove_credential(
        &mut self,
        provider_id: ProviderId,
    ) -> Result<MetadataProviderReadiness, CredentialMutationError> {
        match provider_id {
            ProviderId::SteamGridDb => self.remove_steamgriddb_credential(),
            ProviderId::Playmatch | ProviderId::GameTdb => {
                Err(CredentialMutationError::UnsupportedProvider)
            }
        }
    }

    /// Refreshes only the configured/missing fact from secure storage.
    ///
    /// This is deliberately network-free. A configured credential is reported
    /// as ready on a fresh service instance because readiness means that a
    /// request may be attempted; validation failures observed during this
    /// runtime generation remain authoritative until replacement or removal.
    pub fn refresh_readiness_from_store(
        &mut self,
    ) -> Result<MetadataProviderReadiness, CredentialMutationError> {
        let configured = match self.store.is_configured(ProviderId::SteamGridDb) {
            Ok(configured) => configured,
            Err(error) => {
                self.readiness = MetadataProviderReadiness::new(
                    ProviderId::SteamGridDb,
                    ProviderReadinessState::Unavailable,
                    false,
                );
                return Err(error);
            }
        };
        let state = if !configured {
            ProviderReadinessState::MissingCredentials
        } else if self.readiness.state() == ProviderReadinessState::MissingCredentials {
            ProviderReadinessState::Ready
        } else {
            self.readiness.state()
        };
        self.readiness = MetadataProviderReadiness::new(ProviderId::SteamGridDb, state, configured);
        Ok(self.readiness)
    }

    /// Returns the last authoritative safe readiness projection.
    pub const fn readiness(&self) -> MetadataProviderReadiness {
        self.readiness
    }
}

/// Immutable production provider descriptor.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderDescriptor {
    id: ProviderId,
    capabilities: Vec<ProviderCapability>,
    requires_credential: bool,
}

impl ProviderDescriptor {
    /// Creates one immutable provider descriptor.
    pub fn new(
        id: ProviderId,
        capabilities: impl Into<Vec<ProviderCapability>>,
        requires_credential: bool,
    ) -> Self {
        Self {
            id,
            capabilities: capabilities.into(),
            requires_credential,
        }
    }

    /// Returns the provider identity.
    pub const fn id(&self) -> ProviderId {
        self.id
    }

    /// Returns the capabilities declared by the provider.
    pub fn capabilities(&self) -> &[ProviderCapability] {
        &self.capabilities
    }

    /// Returns whether this provider requires a credential.
    pub const fn requires_credential(&self) -> bool {
        self.requires_credential
    }
}

/// Immutable registry of the active production providers.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataProviderRegistry {
    descriptors: Vec<ProviderDescriptor>,
}

impl MetadataProviderRegistry {
    /// Builds the fixed Phase 003 production roster.
    pub fn production() -> Self {
        Self {
            descriptors: vec![
                ProviderDescriptor::new(
                    ProviderId::Playmatch,
                    vec![ProviderCapability::ContentMatching],
                    false,
                ),
                ProviderDescriptor::new(
                    ProviderId::GameTdb,
                    vec![
                        ProviderCapability::ContentMatching,
                        ProviderCapability::MetadataRefresh,
                        ProviderCapability::ArtworkDiscovery,
                    ],
                    false,
                ),
                ProviderDescriptor::new(
                    ProviderId::SteamGridDb,
                    vec![ProviderCapability::ArtworkDiscovery],
                    true,
                ),
            ],
        }
    }

    /// Returns provider IDs in stable roster order.
    pub fn provider_ids(&self) -> Vec<ProviderId> {
        self.descriptors
            .iter()
            .map(ProviderDescriptor::id)
            .collect()
    }

    /// Returns the descriptor for one registered provider.
    pub fn descriptor(&self, id: ProviderId) -> &ProviderDescriptor {
        self.descriptors
            .iter()
            .find(|descriptor| descriptor.id() == id)
            .expect("production provider roster is complete")
    }

    /// Builds the safe readiness projection without network or provider I/O.
    pub fn readiness_projection(
        &self,
        settings: &MetadataProviderSettings,
        credential_readiness: MetadataProviderReadiness,
    ) -> Vec<MetadataProviderReadinessProjection> {
        self.descriptors
            .iter()
            .map(|descriptor| {
                let enabled = settings.enabled().contains(&descriptor.id());
                let credential_configured = descriptor.requires_credential()
                    && credential_readiness.provider_id() == descriptor.id()
                    && credential_readiness.credential_configured();
                let state = if !enabled {
                    ProviderReadinessState::Disabled
                } else if descriptor.requires_credential() {
                    credential_readiness.state()
                } else {
                    ProviderReadinessState::Ready
                };
                let capability_readiness = descriptor
                    .capabilities()
                    .iter()
                    .copied()
                    .map(|capability| ProviderCapabilityReadiness::new(capability, state))
                    .collect();
                MetadataProviderReadinessProjection::new(
                    descriptor.id(),
                    enabled,
                    capability_readiness,
                    credential_configured,
                )
            })
            .collect()
    }
}

/// Persistable provider enablement settings.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataProviderSettings {
    enabled: BTreeSet<ProviderId>,
}

impl Default for MetadataProviderSettings {
    fn default() -> Self {
        Self {
            enabled: [
                ProviderId::Playmatch,
                ProviderId::GameTdb,
                ProviderId::SteamGridDb,
            ]
            .into_iter()
            .collect(),
        }
    }
}

impl MetadataProviderSettings {
    /// Enables or disables one registered provider for future resolution.
    pub fn set_enabled(&mut self, provider_id: ProviderId, enabled: bool) {
        if enabled {
            self.enabled.insert(provider_id);
        } else {
            self.enabled.remove(&provider_id);
        }
    }

    /// Returns the enabled provider set.
    pub fn enabled(&self) -> &BTreeSet<ProviderId> {
        &self.enabled
    }

    /// Creates settings from a persisted provider list, ignoring unknown IDs.
    pub fn from_enabled<I>(providers: I) -> Self
    where
        I: IntoIterator,
        I::Item: AsRef<str>,
    {
        Self {
            enabled: providers
                .into_iter()
                .filter_map(|value| ProviderId::try_from(value.as_ref()).ok())
                .collect(),
        }
    }
}

/// Provider evidence that may or may not satisfy automatic mapping policy.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ExactMatchEvidence {
    /// Playmatch binding for one submitted strong identity and platform.
    Playmatch {
        game_content_id: GameContentId,
        platform_id: PlatformId,
        external_game_id: String,
        submitted_identity: String,
        response_identity: String,
    },
    /// GameTDB binding for one validated platform-native identifier.
    GameTdb {
        game_content_id: GameContentId,
        platform_id: PlatformId,
        external_game_id: String,
        native_identifier: String,
        validated_identifier: String,
    },
    /// Title-only evidence is retained as non-authoritative provider evidence.
    TitleOnly {
        provider_id: ProviderId,
        external_game_id: String,
    },
}

/// Result of provider-specific automatic mapping acceptance.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MappingDecision {
    current: bool,
}

impl MappingDecision {
    /// Returns whether the evidence is accepted as a current mapping.
    pub const fn is_current(self) -> bool {
        self.current
    }
}

/// One provider-native metadata candidate used by local resolution.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataCandidate {
    provider_id: ProviderId,
    external_game_id: String,
    title: String,
    region: String,
    language: String,
    quality: u8,
    freshness: u64,
}

impl MetadataCandidate {
    /// Creates one normalized candidate for deterministic local resolution.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        provider_id: ProviderId,
        external_game_id: impl Into<String>,
        title: impl Into<String>,
        region: impl Into<String>,
        language: impl Into<String>,
        quality: u8,
        freshness: u64,
    ) -> Self {
        Self {
            provider_id,
            external_game_id: external_game_id.into(),
            title: title.into(),
            region: region.into(),
            language: language.into(),
            quality,
            freshness,
        }
    }
}

/// Local-only metadata resolution preferences.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataResolutionPolicy {
    enabled_providers: BTreeSet<ProviderId>,
    preferred_regions: Vec<String>,
    preferred_languages: Vec<String>,
}

impl MetadataResolutionPolicy {
    /// Creates a policy without performing provider or filesystem I/O.
    pub fn new<R, L>(
        enabled_providers: BTreeSet<ProviderId>,
        preferred_regions: R,
        preferred_languages: L,
    ) -> Self
    where
        R: IntoIterator,
        R::Item: Into<String>,
        L: IntoIterator,
        L::Item: Into<String>,
    {
        Self {
            enabled_providers,
            preferred_regions: preferred_regions.into_iter().map(Into::into).collect(),
            preferred_languages: preferred_languages.into_iter().map(Into::into).collect(),
        }
    }
}

/// Provenance for one field in the derived Game-level presentation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataFieldProvenance {
    field: String,
    provider_id: Option<ProviderId>,
    external_game_id: Option<String>,
    source: String,
}

impl MetadataFieldProvenance {
    /// Creates provider or local-fallback provenance for one resolved field.
    pub fn new(
        field: impl Into<String>,
        provider_id: Option<ProviderId>,
        external_game_id: Option<String>,
        source: impl Into<String>,
    ) -> Self {
        Self {
            field: field.into(),
            provider_id,
            external_game_id,
            source: source.into(),
        }
    }

    /// Returns the resolved field name.
    pub fn field(&self) -> &str {
        &self.field
    }

    /// Returns the contributing provider, if any.
    pub const fn provider_id(&self) -> Option<ProviderId> {
        self.provider_id
    }

    /// Returns the contributing provider record identity, if any.
    pub fn external_game_id(&self) -> Option<&str> {
        self.external_game_id.as_deref()
    }

    /// Returns the safe provenance source marker.
    pub fn source(&self) -> &str {
        &self.source
    }
}

/// Game-level metadata selected by local deterministic resolution.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedMetadata {
    display_title: Option<String>,
    sort_title: Option<String>,
    description: Option<String>,
    release_date: Option<String>,
    developers: Vec<String>,
    publishers: Vec<String>,
    genres: Vec<String>,
    presentation_region: Option<String>,
    presentation_languages: Vec<String>,
    field_provenance: Vec<MetadataFieldProvenance>,
    resolution_revision: u64,
    resolved_at: i64,
    provider_id: Option<ProviderId>,
}

impl ResolvedMetadata {
    /// Creates the minimal resolved projection used by compatibility callers.
    pub fn new(display_title: Option<String>, provider_id: Option<ProviderId>) -> Self {
        Self {
            display_title,
            sort_title: None,
            description: None,
            release_date: None,
            developers: Vec::new(),
            publishers: Vec::new(),
            genres: Vec::new(),
            presentation_region: None,
            presentation_languages: Vec::new(),
            field_provenance: Vec::new(),
            resolution_revision: 1,
            resolved_at: 0,
            provider_id,
        }
    }

    /// Reconstructs a complete projection read from the authoritative store.
    ///
    /// This constructor is intentionally value-oriented: persistence adapters
    /// may rebuild the application projection without exposing their row or
    /// serialization types to callers.
    #[allow(clippy::too_many_arguments)]
    pub fn from_persisted(
        display_title: Option<String>,
        sort_title: Option<String>,
        description: Option<String>,
        release_date: Option<String>,
        developers: Vec<String>,
        publishers: Vec<String>,
        genres: Vec<String>,
        presentation_region: Option<String>,
        presentation_languages: Vec<String>,
        field_provenance: Vec<MetadataFieldProvenance>,
        resolution_revision: u64,
        resolved_at: i64,
        provider_id: Option<ProviderId>,
    ) -> Self {
        Self {
            display_title,
            sort_title,
            description,
            release_date,
            developers,
            publishers,
            genres,
            presentation_region,
            presentation_languages,
            field_provenance,
            resolution_revision,
            resolved_at,
            provider_id,
        }
    }

    /// Returns the selected display title, if any candidate supplied one.
    pub fn display_title(&self) -> Option<&str> {
        self.display_title.as_deref()
    }

    /// Returns the normalized sort title, if one was resolved.
    pub fn sort_title(&self) -> Option<&str> {
        self.sort_title.as_deref()
    }

    /// Returns the selected description, if any provider supplied one.
    pub fn description(&self) -> Option<&str> {
        self.description.as_deref()
    }

    /// Returns the selected release date, if any provider supplied one.
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }

    /// Returns selected developers.
    pub fn developers(&self) -> &[String] {
        &self.developers
    }

    /// Returns selected publishers.
    pub fn publishers(&self) -> &[String] {
        &self.publishers
    }

    /// Returns selected genres.
    pub fn genres(&self) -> &[String] {
        &self.genres
    }

    /// Returns the selected presentation region.
    pub fn presentation_region(&self) -> Option<&str> {
        self.presentation_region.as_deref()
    }

    /// Returns the selected presentation languages.
    pub fn presentation_languages(&self) -> &[String] {
        &self.presentation_languages
    }

    /// Returns field-level provenance in deterministic field order.
    pub fn field_provenance(&self) -> &[MetadataFieldProvenance] {
        &self.field_provenance
    }

    /// Returns the application resolution-policy revision.
    pub const fn resolution_revision(&self) -> u64 {
        self.resolution_revision
    }

    /// Returns the resolution timestamp supplied by the caller.
    pub const fn resolved_at(&self) -> i64 {
        self.resolved_at
    }

    /// Returns the provider that supplied the selected title.
    pub const fn provider_id(&self) -> Option<ProviderId> {
        self.provider_id
    }
}

/// Applies the provider-specific exact-evidence acceptance policy.
pub fn accept_exact_mapping(evidence: ExactMatchEvidence) -> MappingDecision {
    let current = match evidence {
        ExactMatchEvidence::Playmatch {
            external_game_id,
            submitted_identity,
            response_identity,
            ..
        } => {
            !external_game_id.is_empty()
                && !submitted_identity.is_empty()
                && submitted_identity == response_identity
        }
        ExactMatchEvidence::GameTdb {
            external_game_id,
            native_identifier,
            validated_identifier,
            ..
        } => {
            !external_game_id.is_empty()
                && !native_identifier.is_empty()
                && native_identifier == validated_identifier
        }
        ExactMatchEvidence::TitleOnly { .. } => false,
    };
    MappingDecision { current }
}

/// Applies automatic mapping only when exactly one evidence candidate exists.
pub fn accept_exact_mappings(evidence: &[ExactMatchEvidence]) -> MappingDecision {
    if evidence.len() != 1 {
        return MappingDecision { current: false };
    }
    accept_exact_mapping(evidence[0].clone())
}

/// Resolves provider candidates locally without network or credential access.
pub fn resolve_metadata(
    candidates: &[MetadataCandidate],
    policy: &MetadataResolutionPolicy,
) -> ResolvedMetadata {
    let selected = candidates
        .iter()
        .filter(|candidate| policy.enabled_providers.contains(&candidate.provider_id))
        .max_by_key(|candidate| {
            (
                locale_preference(&policy.preferred_regions, Some(candidate.region.as_str())),
                locale_preference(
                    &policy.preferred_languages,
                    Some(candidate.language.as_str()),
                ),
                provider_preference(candidate.provider_id),
                candidate.quality,
                candidate.freshness,
                std::cmp::Reverse(candidate.external_game_id.as_str()),
            )
        });

    selected.map_or(ResolvedMetadata::new(None, None), |candidate| {
        let mut resolved =
            ResolvedMetadata::new(Some(candidate.title.clone()), Some(candidate.provider_id));
        resolved.sort_title = Some(candidate.title.to_lowercase());
        resolved.field_provenance.push(MetadataFieldProvenance::new(
            "display_title",
            Some(candidate.provider_id),
            Some(candidate.external_game_id.clone()),
            "provider",
        ));
        resolved
    })
}

/// Resolves normalized provider-native records field by field without I/O.
///
/// Expired records and disabled providers are ignored. The same deterministic
/// ranking is applied independently to each populated field, allowing one
/// provider to supply a title while another supplies a description or genre.
pub fn resolve_provider_metadata(
    candidates: &[ProviderMetadata],
    policy: &MetadataResolutionPolicy,
    now: i64,
) -> ResolvedMetadata {
    let eligible = |candidate: &&ProviderMetadata| {
        policy.enabled_providers.contains(&candidate.provider_id())
            && candidate.mapping_state() == MappingState::Current
            && !candidate.is_expired(now)
    };
    let title = best_provider_metadata(candidates, policy, eligible, |candidate| {
        candidate.title().is_some()
    });
    let description = best_provider_metadata(candidates, policy, eligible, |candidate| {
        candidate.description().is_some()
    });
    let release_date = best_provider_metadata(candidates, policy, eligible, |candidate| {
        candidate.release_date().is_some()
    });
    let developers = best_provider_metadata(candidates, policy, eligible, |candidate| {
        !candidate.developers().is_empty()
    });
    let publishers = best_provider_metadata(candidates, policy, eligible, |candidate| {
        !candidate.publishers().is_empty()
    });
    let genres = best_provider_metadata(candidates, policy, eligible, |candidate| {
        !candidate.genres().is_empty()
    });
    let languages = best_provider_metadata(candidates, policy, eligible, |candidate| {
        !candidate.languages().is_empty()
    });

    let mut resolved = ResolvedMetadata::new(
        title.and_then(|candidate| candidate.title().map(str::to_owned)),
        title.map(ProviderMetadata::provider_id),
    );
    resolved.sort_title = resolved
        .display_title
        .clone()
        .map(|value| value.to_lowercase());
    resolved.description =
        description.and_then(|candidate| candidate.description().map(str::to_owned));
    resolved.release_date =
        release_date.and_then(|candidate| candidate.release_date().map(str::to_owned));
    resolved.developers =
        developers.map_or_else(Vec::new, |candidate| candidate.developers().to_vec());
    resolved.publishers =
        publishers.map_or_else(Vec::new, |candidate| candidate.publishers().to_vec());
    resolved.genres = genres.map_or_else(Vec::new, |candidate| candidate.genres().to_vec());
    resolved.presentation_region =
        title.and_then(|candidate| candidate.region().map(str::to_owned));
    resolved.presentation_languages = languages.map_or_else(
        || title.map_or_else(Vec::new, |candidate| candidate.languages().to_vec()),
        |candidate| candidate.languages().to_vec(),
    );
    resolved.resolved_at = now;

    add_provenance(&mut resolved.field_provenance, "display_title", title);
    add_provenance(&mut resolved.field_provenance, "description", description);
    add_provenance(&mut resolved.field_provenance, "release_date", release_date);
    add_provenance(&mut resolved.field_provenance, "developers", developers);
    add_provenance(&mut resolved.field_provenance, "publishers", publishers);
    add_provenance(&mut resolved.field_provenance, "genres", genres);
    add_provenance(
        &mut resolved.field_provenance,
        "languages",
        languages.or(title),
    );
    resolved
}

fn best_provider_metadata<'a, F, P>(
    candidates: &'a [ProviderMetadata],
    policy: &MetadataResolutionPolicy,
    eligible: F,
    populated: P,
) -> Option<&'a ProviderMetadata>
where
    F: Fn(&&ProviderMetadata) -> bool,
    P: Fn(&ProviderMetadata) -> bool,
{
    candidates
        .iter()
        .filter(eligible)
        .filter(|candidate| populated(candidate))
        .max_by_key(|candidate| {
            (
                locale_preference(&policy.preferred_regions, candidate.region()),
                locale_preference(&policy.preferred_languages, candidate.language()),
                provider_preference(candidate.provider_id()),
                candidate.adapter_quality(),
                candidate.provider_revision(),
                freshness_score(candidate),
                std::cmp::Reverse(candidate.external_game_id()),
            )
        })
}

fn locale_preference(preferences: &[String], value: Option<&str>) -> usize {
    preferences
        .iter()
        .position(|preferred| Some(preferred.as_str()) == value)
        .map_or(0, |position| preferences.len() - position)
}

fn freshness_score(candidate: &ProviderMetadata) -> i64 {
    candidate.fetched_at()
}

fn add_provenance(
    output: &mut Vec<MetadataFieldProvenance>,
    field: &str,
    candidate: Option<&ProviderMetadata>,
) {
    if let Some(candidate) = candidate {
        output.push(MetadataFieldProvenance::new(
            field,
            Some(candidate.provider_id()),
            Some(candidate.external_game_id().to_owned()),
            candidate.provenance(),
        ));
    }
}

fn provider_preference(provider_id: ProviderId) -> u8 {
    match provider_id {
        ProviderId::GameTdb => 3,
        ProviderId::Playmatch => 2,
        ProviderId::SteamGridDb => 1,
    }
}
