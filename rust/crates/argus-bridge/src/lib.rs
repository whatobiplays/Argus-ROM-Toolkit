//! Sole Rust composition and translation boundary for the Flutter bridge.
//!
//! The DTOs in this module are immutable transport projections. They do not
//! read persistence or contain application policy; all authority remains in
//! `argus-runtime` and `argus-application`.

#![allow(unexpected_cfgs)]

use std::fmt;
use std::sync::{Arc, Mutex, OnceLock};

use argus_application::{
    AddLibraryRootAndRefreshResult, AddLocalLibraryRootAndScanResult, AddLocalLibraryRootResult,
    ApplicationError, ApplicationSeverity, ArchitectureClass, AvailabilityState,
    BackgroundOperationStopReason, CompleteLibraryOnboardingAndRefreshResult,
    ContentIdentitySummary, ContentProvenanceSummary, ContentType, DiagnosticStage, ErrorCategory,
    ErrorCode, FailureRole, GameContentPresence, GameContentSummary, GameDetail, GameId,
    GameLibraryPage, GameLibraryRow, GameLifecycle, GameListCursor, GameMembershipSummary,
    GetGameResult, GroupingBasis, HydrationState, IdentificationState, IdentityDigest, JobDetail,
    JobRunId, JobRunProjection, JobRunState, JobSummary, JobSummaryPage, LibraryOnboardingProgress,
    LibraryOnboardingState, LibraryProviderSetupDecision, LibraryRefreshJobDetail,
    LibraryResolutionRefreshJobDetail, LibraryRootAvailability, LibraryRootId,
    LibraryRootLastScanStatus, LibraryRootPage, LibraryRootProjection,
    LibraryScanAdmissionExclusion, LibraryScanAllRequestIdentity, LibraryScanChildAdmissionIssue,
    LibraryScanJobDetail, LibraryScanRootSummary, LibraryScope, LibrarySort, ListGamesQuery,
    ListJobsQuery, ListJobsScope, ListLibraryRootsQuery, ListSourceEntryChildrenQuery,
    LocalFilesystemBrowseCursor, LocalFilesystemBrowseLocation, LocalFilesystemBrowsePage,
    LocalFilesystemBrowseRoot, LocalFilesystemRootSelection, MembershipRelationship,
    MetadataFieldProvenance, MetadataProviderReadiness, MetadataProviderReadinessProjection,
    MetadataProviderSettings, MetadataProviderSettingsUpdateResult, MetadataSettings,
    MetadataSettingsUpdateResult, MigrationOutcome, MountedLocalFilesystemVolume, OperationDetail,
    PathClass, PersistedSettingsReason, PlatformClass, PlatformId, PrivacyConsent,
    ProviderCapability, ProviderCapabilityReadiness, ProviderId, ProviderReadinessState,
    Recoverability, RefreshMode, RefreshProgressFacts, RemoveLibraryRootResult, ResolvedArtwork,
    ResolvedMetadata, RetryJobResult, RetryNotAdmittedReason, RetryPolicy, RootRelationship,
    SafeContext, SafeContextField, SafeContextValue, ScanProgressFacts, ScanRunProjection,
    ScanRunStatus, SettingsDomain, SourceEntriesChangeScope, SourceEntryChildrenPage,
    SourceEntryClassification, SourceEntryCursor, SourceEntryDetailProjection, SourceEntryId,
    SourceEntryKind, SourceEntryProjection, StartLibraryScanAllResult, StartLibraryScanResult,
    SyncLocalFilesystemMountedVolumesCommand, TechnicalClass, ThemeMode,
};
use argus_runtime::{
    ApplicationHost, DiagnosticsExportOutcome, NotificationSinkError, RecoveryActionKind,
    RuntimeEvent, RuntimeEventPayload, RuntimeEventPublisher, RuntimeEventStreamError,
    RuntimeEventSubscription, RuntimeInstanceId, RuntimeLifecycle, RuntimeNotificationSink,
    RuntimeState, StartupFailure, StartupPhase,
};

#[allow(unsafe_code, clippy::result_large_err)]
mod frb_generated;
use crate::frb_generated::StreamSink;

/// First major version of the application bridge contract.
pub const BRIDGE_CONTRACT_MAJOR: u32 = 1;

/// Application-result envelope retained for request/response operations.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum BridgeResult<T> {
    /// The application operation completed successfully.
    Success(T),
    /// Rust returned a structured application failure.
    ApplicationFailure(ApplicationErrorDto),
}

/// Stable application error projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ApplicationErrorDto {
    pub code: String,
    pub category: String,
    pub severity: String,
    pub recoverability: String,
    pub retry_policy: String,
    pub message_key: String,
    pub trace_id: String,
    pub safe_context: Vec<SafeContextEntryDto>,
}

/// Execution-host stop reason accepted across the bridge boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExecutionHostStopReasonDto {
    /// The foreground host exceeded its live execution deadline.
    Timeout,
    /// The foreground host stopped without a durable user cancellation.
    HostLost,
}

/// Bounded report of foreground-host stops for already-admitted runs.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ReportExecutionHostStopRequestDto {
    /// Durable job-run identities whose live host stopped.
    pub job_run_ids: Vec<String>,
    /// The live host condition observed by the native host.
    pub reason: ExecutionHostStopReasonDto,
}

/// One allowlisted structured diagnostic field.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SafeContextEntryDto {
    pub field: String,
    pub value: String,
}

/// Wire lifecycle projection.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RuntimeLifecycleDto {
    Uninitialized,
    Starting,
    Ready,
    StartupFailed,
    ShuttingDown,
    Stopped,
}

/// Wire startup phase projection.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StartupPhaseDto {
    EnvironmentInitialization,
    ObservabilityInitialization,
    ConfigurationInitialization,
    PersistenceInitialization,
    SettingsInitialization,
    CoreServicesInitialization,
    EventInfrastructureInitialization,
    ReadinessValidation,
}

/// Wire recovery action discriminator.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecoveryActionKindDto {
    RetryStartup,
    ResetAppearanceSettings,
    ExportDiagnostics,
    CopyTechnicalDetails,
    OpenDataDirectory,
    Exit,
}

/// One declarative failed-startup action.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RecoveryActionDto {
    pub kind: RecoveryActionKindDto,
}

/// Canonical startup failure projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StartupFailureDto {
    pub phase: StartupPhaseDto,
    pub error: ApplicationErrorDto,
    pub recovery_actions: Vec<RecoveryActionDto>,
}

/// Canonical runtime snapshot.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimeStateDto {
    pub runtime_instance_id: String,
    pub lifecycle_state: RuntimeLifecycleDto,
    pub startup_phase: Option<StartupPhaseDto>,
    pub startup_failure: Option<StartupFailureDto>,
}

/// Canonical theme mode projection.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ThemeModeDto {
    System,
    Light,
    Dark,
}

/// Complete appearance aggregate projection.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AppearanceSettingsDto {
    pub theme_mode: ThemeModeDto,
}

/// Complete appearance update request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct UpdateAppearanceSettingsRequestDto {
    pub theme_mode: ThemeModeDto,
}

/// Safe Settings-owned privacy-consent projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PrivacyConsentDto {
    pub accepted_terms_version: Option<String>,
    pub accepted_at_ms: Option<i64>,
    pub required_terms_version: String,
    pub satisfies_current_required_terms: bool,
}

/// Versioned privacy-consent mutation request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AcceptPrivacyTermsRequestDto {
    pub terms_version: String,
}

/// Local metadata preferences owned by the settings capability.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataSettingsDto {
    pub preferred_regions: Vec<String>,
    pub preferred_languages: Vec<String>,
}

/// Provider enablement preferences owned by the metadata capability.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataProviderSettingsDto {
    pub enabled_providers: Vec<String>,
}

/// Closed onboarding provider decision.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryProviderSetupDecisionDto {
    Configured,
    Skipped,
}

/// Durable onboarding progress facts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryOnboardingProgressDto {
    pub accepted_privacy_terms_version: Option<String>,
    pub accepted_privacy_at_ms: Option<i64>,
    pub metadata_preferences_confirmed: bool,
    pub provider_setup_outcome: String,
    pub completed_at_ms: Option<i64>,
}

/// Query-authoritative onboarding projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryOnboardingStateDto {
    pub progress: LibraryOnboardingProgressDto,
    pub required_privacy_terms_version: String,
    pub requires_privacy_acceptance: bool,
    pub requires_root_selection: bool,
    pub credential_configured: bool,
    pub complete: bool,
}

/// Closed refresh freshness policy.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RefreshModeDto {
    EligibleOnly,
    Force,
}

/// Bounded Game refresh admission request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StartGameRefreshRequestDto {
    pub game_ids: Vec<String>,
    pub mode: RefreshModeDto,
}

/// Result of committing metadata settings and independently admitting local
/// resolution work.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MetadataSettingsUpdateResultDto {
    CommittedNoResolutionWork(MetadataSettingsDto),
    CommittedAndResolutionAdmitted(MetadataSettingsDto, OperationHandleDto),
    CommittedButResolutionNotAdmitted(MetadataSettingsDto, ApplicationErrorDto),
}

/// Result of committing provider enablement and independently admitting local
/// resolution work.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MetadataProviderSettingsUpdateResultDto {
    CommittedNoResolutionWork(MetadataProviderSettingsDto),
    CommittedAndResolutionAdmitted(MetadataProviderSettingsDto, OperationHandleDto),
    CommittedButResolutionNotAdmitted(MetadataProviderSettingsDto, ApplicationErrorDto),
}

/// Result of committing onboarding completion and independently admitting the
/// initial refresh.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CompleteLibraryOnboardingAndRefreshResultDto {
    OnboardingCompletedAndRefreshAdmitted(LibraryOnboardingStateDto, OperationHandleDto),
    OnboardingCompletedButRefreshNotAdmitted(LibraryOnboardingStateDto, ApplicationErrorDto),
}

/// Result of adding the first onboarding root and independently admitting its
/// composed refresh.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AddLibraryRootAndRefreshResultDto {
    AddedAndRefreshAdmitted(LibraryRootDto, OperationHandleDto),
    AddedButRefreshNotAdmitted(LibraryRootDto, ApplicationErrorDto),
    AlreadyConfigured(String),
    OverlapsExisting(String, RootRelationshipDto),
}

/// Untrusted typed local-folder selection supplied by the native picker seam.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LocalFilesystemRootSelectionDto {
    /// A desktop/native picker path that the provider validates before use.
    Path { selected_folder_path: String },
    /// An opaque provider browse identity returned by a prior browse query.
    ProviderSelection { selection_identity: String },
}

/// One native mounted-volume fact supplied only to the synchronization ingress.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MountedLocalFilesystemVolumeDto {
    pub provider_volume_id: String,
    pub transient_mount_path: String,
    pub safe_display_name: String,
    pub is_primary: bool,
    pub is_removable: bool,
}

/// Bounded mounted-volume synchronization request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SyncLocalFilesystemMountedVolumesRequestDto {
    pub volumes: Vec<MountedLocalFilesystemVolumeDto>,
}

/// Safe browse-root projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowseRootDto {
    pub location: String,
    pub display_name: String,
    pub safe_location_presentation: String,
}

/// Safe browse breadcrumb projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowseBreadcrumbDto {
    pub location: String,
    pub display_name: String,
}

/// Safe browse direct-child directory projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowseDirectoryDto {
    pub location: String,
    pub display_name: String,
}

/// Safe bounded browse page projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowsePageDto {
    pub current: LocalFilesystemBrowseRootDto,
    pub breadcrumbs: Vec<LocalFilesystemBrowseBreadcrumbDto>,
    pub directories: Vec<LocalFilesystemBrowseDirectoryDto>,
    pub next_cursor: Option<String>,
}

/// Bounded direct-child browse request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ListLocalFilesystemBrowseDirectoriesRequestDto {
    pub location: String,
    pub cursor: Option<String>,
    pub page_size: u32,
}

/// Bounded root-list request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ListLibraryRootsRequestDto {
    pub offset: u32,
    pub page_size: u32,
}

/// Application-owned root availability vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryRootAvailabilityDto {
    Available,
    Unavailable,
    Unknown,
}

/// Closed historical root last-scan status vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryRootLastScanStatusDto {
    Complete,
    Partial,
    Unavailable,
    Cancelled,
    Failed,
    Abandoned,
}

/// Bounded terminal scan-history summary carried by a root projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootLastScanDto {
    pub scan_run_id: String,
    pub job_run_id: String,
    pub status: LibraryRootLastScanStatusDto,
    pub started_at_ms: i64,
    pub completed_at_ms: Option<i64>,
}

/// Bounded active scan-ownership summary carried by a root projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootActiveScanDto {
    pub scan_run_id: String,
    pub job_run_id: String,
    pub owning_job_root_count: u32,
}

/// Authoritative immutable root projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootDto {
    pub library_root_id: String,
    pub display_name: String,
    pub safe_location_presentation: String,
    pub availability: LibraryRootAvailabilityDto,
    pub last_scan: Option<LibraryRootLastScanDto>,
    pub active_scan: Option<LibraryRootActiveScanDto>,
}

/// Bounded authoritative root-list page.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootPageDto {
    pub items: Vec<LibraryRootDto>,
    pub offset: u32,
    pub page_size: u32,
    pub total_count: u32,
}

/// Closed logical-library scope vocabulary from BE-008.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LibraryScopeDto {
    All,
    Platform { platform_id: String },
    Source { source_id: String },
    LibraryRoot { library_root_id: String },
}

/// Closed logical-library hydration filter vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryHydrationStateDto {
    Hydrated,
    PartiallyHydrated,
    Unmatched,
    Refreshing,
}

/// Closed logical-library availability filter vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryAvailabilityStateDto {
    Available,
    PartiallyUnavailable,
    Unavailable,
    InactiveOrphan,
}

/// Structurally valid BE-008 library filters. P03-001 accepts only empty
/// filters; non-empty values are rejected as INVALID_ARGUMENT.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryFilterDto {
    pub platform_ids: Vec<String>,
    pub regions: Vec<String>,
    pub hydration_states: Vec<LibraryHydrationStateDto>,
    pub availability_states: Vec<LibraryAvailabilityStateDto>,
}

/// Closed logical-library sort field vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibrarySortFieldDto {
    DisplayTitle,
    Platform,
    ReleaseDate,
    UpdatedAt,
}

/// Closed logical-library sort direction vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibrarySortDirectionDto {
    Ascending,
    Descending,
}

/// Structurally valid BE-008 sort request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LibrarySortDto {
    pub field: LibrarySortFieldDto,
    pub direction: LibrarySortDirectionDto,
}

/// Baseline logical-library request. The bridge validates this full query
/// shape and activates only All/empty/default/opaque-cursor paging.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ListGamesRequestDto {
    pub scope: LibraryScopeDto,
    pub search_text: Option<String>,
    pub filters: LibraryFilterDto,
    pub sort: LibrarySortDto,
    pub cursor: Option<String>,
    pub page_size: u32,
}

/// Stable platform vocabulary in logical-library projections.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlatformIdDto {
    NintendoGb,
    NintendoGbc,
    NintendoGba,
}

/// Stable content-type vocabulary in logical-library projections.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ContentTypeDto {
    CartridgeImage,
}

/// Independent content presence state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ContentPresenceDto {
    Available,
    PartiallyUnavailable,
    Unavailable,
    Orphaned,
}

/// Independent content identification state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum IdentificationStateDto {
    Identified,
    NeedsReidentification,
    Unidentified,
}

/// Durable game lifecycle state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GameLifecycleDto {
    Active,
    InactiveOrphan,
    Redirected,
}

/// Local logical-library hydration state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HydrationStateDto {
    Hydrated,
    PartiallyHydrated,
    Unmatched,
    Refreshing,
}

/// Local logical-library availability state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GameAvailabilityStateDto {
    Available,
    PartiallyUnavailable,
    Unavailable,
    InactiveOrphan,
}

/// Membership role in a durable game aggregate.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MembershipRelationshipDto {
    Primary,
    Secondary,
}

/// Grouping evidence basis for one durable membership.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GroupingBasisDto {
    ExactContentIdentity,
    Provisional,
}

/// Safe current identity summary.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentIdentitySummaryDto {
    pub scheme_id: String,
    pub revision: u32,
    pub digest: String,
}

/// Safe exact proving-provenance summary. Raw locations and parser details
/// remain private to infrastructure.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentProvenanceSummaryDto {
    pub source_entry_id: String,
    pub association_key: String,
    pub source_fingerprint: Option<String>,
    pub last_observed_scan_id: String,
}

/// Focused current logical-content detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentSummaryDto {
    pub game_content_id: String,
    pub platform_id: PlatformIdDto,
    pub content_type: ContentTypeDto,
    pub presence: ContentPresenceDto,
    pub identification: IdentificationStateDto,
    pub source_count: u32,
    pub identity: Option<ContentIdentitySummaryDto>,
    pub provenance: Option<ContentProvenanceSummaryDto>,
}

/// Focused current membership detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameMembershipSummaryDto {
    pub game_content_id: String,
    pub relationship: MembershipRelationshipDto,
    pub grouping_basis: GroupingBasisDto,
    pub grouping_revision: u32,
}

/// Bounded logical-library list row.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameLibraryRowDto {
    pub game_id: String,
    pub display_title: String,
    pub platform_id: PlatformIdDto,
    pub hydration_state: HydrationStateDto,
    pub content_count: u32,
    pub source_count: u32,
    pub availability_state: GameAvailabilityStateDto,
    pub updated_at_ms: i64,
}

/// Bounded logical-library page with an opaque continuation cursor.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GamePageDto {
    pub items: Vec<GameLibraryRowDto>,
    pub next_cursor: Option<String>,
}

/// Focused durable logical-game detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameDetailDto {
    pub game_id: String,
    pub platform_id: PlatformIdDto,
    pub lifecycle: GameLifecycleDto,
    pub hydration_state: HydrationStateDto,
    pub fallback_title: String,
    pub memberships: Vec<GameMembershipSummaryDto>,
    pub content: Vec<ContentSummaryDto>,
    pub availability_state: GameAvailabilityStateDto,
    pub resolved_metadata: Option<ResolvedMetadataDto>,
    pub resolved_artwork: Option<Vec<ResolvedArtworkDto>>,
}

/// Safe field-level provenance for resolved Game metadata.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataFieldProvenanceDto {
    pub field: String,
    pub provider_id: Option<String>,
    pub external_game_id: Option<String>,
    pub source: String,
}

/// Game-level derived metadata without provider transport details.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedMetadataDto {
    pub display_title: Option<String>,
    pub sort_title: Option<String>,
    pub description: Option<String>,
    pub release_date: Option<String>,
    pub developers: Vec<String>,
    pub publishers: Vec<String>,
    pub genres: Vec<String>,
    pub presentation_region: Option<String>,
    pub presentation_languages: Vec<String>,
    pub field_provenance: Vec<MetadataFieldProvenanceDto>,
    pub resolution_revision: u64,
    pub resolved_at: i64,
    pub provider_id: Option<String>,
}

/// Game-level artwork selection with an optional local asset identity.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedArtworkDto {
    pub artwork_type: String,
    pub reference_id: String,
    pub asset_id: Option<String>,
    pub ordering: u32,
    pub selection_reason: String,
    pub resolution_revision: u64,
    pub resolved_at: i64,
}

/// Safe provider capability readiness projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderCapabilityReadinessDto {
    pub capability: String,
    pub state: String,
}

/// Safe provider readiness projection used by the focused readiness query.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MetadataProviderReadinessDto {
    pub provider_id: String,
    pub enabled: bool,
    pub capability_readiness: Vec<ProviderCapabilityReadinessDto>,
    pub credential_configured: bool,
}

/// Safe credential mutation result. It contains no secret-bearing field.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProviderCredentialReadinessDto {
    pub provider_id: String,
    pub state: String,
    pub credential_configured: bool,
}

/// Write-only provider credential command input.
///
/// `credential_input` is a transient bridge value. Rust consumes it on a
/// backend worker and delegates it immediately to the application secure
/// credential gateway; it is never returned in a DTO or persisted by the
/// bridge.
#[derive(Clone, Eq, PartialEq)]
pub struct SetMetadataProviderCredentialRequestDto {
    pub provider_id: String,
    pub credential_input: Vec<u8>,
}

impl fmt::Debug for SetMetadataProviderCredentialRequestDto {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SetMetadataProviderCredentialRequestDto")
            .field("provider_id", &self.provider_id)
            .field("credential_input_len", &self.credential_input.len())
            .finish()
    }
}

/// Write-only provider credential removal command input.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RemoveMetadataProviderCredentialRequestDto {
    pub provider_id: String,
}

/// Bounded original artwork bytes and validated media metadata.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ArtworkAssetBytesDto {
    pub asset_id: String,
    pub bytes: Vec<u8>,
    pub mime_type: String,
    pub width: u32,
    pub height: u32,
}

/// Focused lookup result. A missing game is returned as the published
/// GAME_NOT_FOUND application error rather than a nullable DTO.
#[derive(Clone, Debug, Eq, PartialEq)]
#[allow(clippy::large_enum_variant)]
pub enum GetGameResultDto {
    /// The value-owned enriched game projection preserves the established
    /// bridge contract without introducing an indirection in the wire DTO.
    Found(GameDetailDto),
    Redirected {
        canonical_game_id: String,
    },
}

/// Application-owned source-entry kind vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceEntryKindDto {
    Directory,
    File,
    LinkLike,
    Unknown,
}

/// Application-owned source-entry classification vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceEntryClassificationDto {
    Container,
    ContentCandidate,
    SupportingEntry,
    Ignored,
    Unknown,
}

/// Safe authoritative row projection for one source entry.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryDto {
    pub source_entry_id: String,
    pub parent_source_entry_id: Option<String>,
    pub display_name: String,
    pub display_location: String,
    pub kind: SourceEntryKindDto,
    pub classification: SourceEntryClassificationDto,
    /// Reserved BE-008 status field. Always `None` in Slice 004: current
    /// authoritative data has no user-meaningful status fact, and provenance
    /// is never relabeled as status.
    pub bounded_status_summary: Option<String>,
}

/// Safe authoritative detail projection for one source entry.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryDetailDto {
    pub source_entry_id: String,
    pub parent_source_entry_id: Option<String>,
    pub display_name: String,
    pub display_location: String,
    pub kind: SourceEntryKindDto,
    pub classification: SourceEntryClassificationDto,
    /// Reserved BE-008 status field. Always `None` in Slice 004.
    pub bounded_status_summary: Option<String>,
    /// Reserved BE-008 detail status field. Always `None` in Slice 004.
    pub bounded_observation_status_detail: Option<String>,
}

/// One bounded authoritative direct-child page.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryChildrenPageDto {
    pub items: Vec<SourceEntryDto>,
    /// Opaque continuation token; Flutter never parses or synthesizes it.
    pub next_cursor: Option<String>,
}

/// One bounded direct-child paging request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ListSourceEntryChildrenRequestDto {
    pub library_root_id: String,
    pub parent_source_entry_id: Option<String>,
    /// Untrusted external cursor text; validated at this bridge boundary.
    pub cursor: Option<String>,
    pub page_size: u32,
}

/// Provider-owned overlap vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RootRelationshipDto {
    Same,
    Ancestor,
    Descendant,
    Disjoint,
    Unknown,
}

/// Typed outcome of one root-only add operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AddLocalLibraryRootResultDto {
    Added(LibraryRootDto),
    AlreadyConfigured(String),
    OverlapsExisting(String, RootRelationshipDto),
}

/// Typed outcome of one root-removal operation for the active slice.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RemoveLibraryRootResultDto {
    Removed,
    RootHasActiveScan {
        library_root_id: String,
        job_run_id: String,
        scan_run_id: String,
        owning_job_root_count: u32,
    },
}

/// Minimal identity-only handle returned by successful background admission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationHandleDto {
    pub job_run_id: String,
    pub operation_type: String,
}

/// Canonical persisted job lifecycle vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum JobRunStateDto {
    Queued,
    Preparing,
    Running,
    Completed,
    CompletedWithIssues,
    Failed,
    Cancelled,
    Interrupted,
    Abandoned,
}

/// Canonical per-root scan status.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ScanRunStatusDto {
    Running,
    Complete,
    Partial,
    Failed,
    Cancelled,
    Abandoned,
}

/// Backend-authoritative control availability.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct JobControlAvailabilityDto {
    pub can_cancel: bool,
    pub can_retry: bool,
}

/// Bounded list-row projection for Jobs landing and shell summaries.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobSummaryDto {
    pub job_run_id: String,
    pub operation_type: String,
    pub state: JobRunStateDto,
    pub phase: Option<String>,
    pub created_at_ms: i64,
    pub started_at_ms: Option<i64>,
    pub terminal_at_ms: Option<i64>,
    pub cancellation_requested: bool,
    pub safe_context_summary: Option<String>,
}

/// Bounded terminal failure projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BoundedTerminalFailureDto {
    pub error_code: Option<String>,
    pub safe_context: Option<String>,
}

/// Capability-neutral generic execution projection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobRunDto {
    pub job_run_id: String,
    pub operation_type: String,
    pub state: JobRunStateDto,
    pub phase: Option<String>,
    pub completed_units: Option<u64>,
    pub total_units: Option<u64>,
    pub status_key: Option<String>,
    pub created_at_ms: i64,
    pub queued_at_ms: Option<i64>,
    pub started_at_ms: Option<i64>,
    pub terminal_at_ms: Option<i64>,
    pub cancellation_requested: bool,
    pub controls: JobControlAvailabilityDto,
    pub bounded_terminal_failure: Option<BoundedTerminalFailureDto>,
}

/// One per-root scan projection with its historical display snapshot.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ScanRunDto {
    pub scan_run_id: String,
    pub job_run_id: String,
    pub library_root_id: String,
    pub display_name: String,
    pub safe_location_display: String,
    pub status: ScanRunStatusDto,
    pub started_at_ms: i64,
    pub completed_at_ms: Option<i64>,
}

/// Bounded historical root display summary.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanRootSummaryDto {
    pub library_root_id: String,
    pub display_name: String,
    pub safe_location_display: String,
}

/// One durable typed admission exclusion.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanAdmissionExclusionDto {
    pub library_root_id: String,
    pub reason: String,
    pub active_job_run_id: Option<String>,
    pub active_scan_run_id: Option<String>,
    pub application_error: Option<ApplicationErrorDto>,
}

/// Scan-specific structured progress facts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ScanProgressFactsDto {
    pub phase: Option<String>,
    pub completed_units: Option<u64>,
    pub total_units: Option<u64>,
    pub status_key: Option<String>,
    pub roots_requested: u32,
    pub roots_admitted: u32,
    pub roots_terminal: u32,
    pub entries_observed: Option<u64>,
    pub entries_committed: Option<u64>,
    pub issue_count: Option<u64>,
}

/// Typed LibraryScan operation detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanJobDetailDto {
    pub requested_roots: Vec<LibraryScanRootSummaryDto>,
    pub admitted_roots: Vec<LibraryScanRootSummaryDto>,
    pub exclusions: Vec<LibraryScanAdmissionExclusionDto>,
    pub scan_runs: Vec<ScanRunDto>,
    pub progress: ScanProgressFactsDto,
    pub retry_source_job_run_id: Option<String>,
    pub retry_successor_job_run_id: Option<String>,
}

/// Shared progress facts for a composed refresh operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RefreshProgressFactsDto {
    pub phase: Option<String>,
    pub completed_units: Option<u64>,
    pub total_units: Option<u64>,
    pub status_key: Option<String>,
    pub issue_count: Option<u64>,
}

/// Typed composed Library refresh detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRefreshJobDetailDto {
    pub trigger: String,
    pub trigger_root_id: Option<String>,
    pub mode: String,
    pub requested_root_ids: Vec<String>,
    pub scan_runs: Vec<ScanRunDto>,
    pub progress: RefreshProgressFactsDto,
    pub retry_source_job_run_id: Option<String>,
    pub retry_successor_job_run_id: Option<String>,
}

/// Typed bounded Game refresh detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameRefreshJobDetailDto {
    pub game_ids: Vec<String>,
    pub mode: String,
    pub progress: RefreshProgressFactsDto,
    pub retry_source_job_run_id: Option<String>,
    pub retry_successor_job_run_id: Option<String>,
}

/// Typed local-only Library resolution refresh detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryResolutionRefreshJobDetailDto {
    pub job_run_id: String,
    pub settings_revision: u64,
    pub progress: RefreshProgressFactsDto,
    pub retry_source_job_run_id: Option<String>,
    pub retry_successor_job_run_id: Option<String>,
}

/// Closed typed operation-detail union.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum OperationDetailDto {
    LibraryScan(LibraryScanJobDetailDto),
    LibraryRefresh(LibraryRefreshJobDetailDto),
    GameRefresh(GameRefreshJobDetailDto),
    LibraryResolutionRefresh(LibraryResolutionRefreshJobDetailDto),
}

/// Authoritative job detail with typed operation detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobDetailDto {
    pub job: JobRunDto,
    pub operation_detail: OperationDetailDto,
}

/// Closed Jobs list scope union.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ListJobsScopeDto {
    Active,
    RecentTerminal { offset: u32, page_size: u32 },
}

/// One bounded Jobs list request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ListJobsRequestDto {
    pub scope: ListJobsScopeDto,
}

/// Bounded authoritative job-row page.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobSummaryPageDto {
    pub items: Vec<JobSummaryDto>,
    pub total_count: u32,
    pub next_offset: Option<u32>,
}

/// Typed outcome of one single-root scan admission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum StartLibraryScanResultDto {
    Admitted(OperationHandleDto),
    AlreadyScanning {
        library_root_id: String,
        active_job_run_id: String,
        active_scan_run_id: String,
    },
}

/// Typed outcome of one multi-root Scan All admission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum StartLibraryScanAllResultDto {
    /// One durable job was admitted for all eligible roots.
    Admitted {
        operation_handle: OperationHandleDto,
        admitted_roots: Vec<String>,
        exclusions: Vec<LibraryScanAdmissionExclusionDto>,
    },
    /// No configured root was eligible, so no job was created.
    NothingEligible {
        exclusions: Vec<LibraryScanAdmissionExclusionDto>,
    },
}

/// Authoritative resolution of one Scan All request identity after
/// transport ambiguity.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LibraryScanAllRequestResolutionDto {
    /// The request identity was durably accepted for one Scan All job.
    Admitted {
        operation_handle: OperationHandleDto,
        admitted_roots: Vec<String>,
        exclusions: Vec<LibraryScanAdmissionExclusionDto>,
    },
    /// The request identity has no durable admission.
    NothingAdmitted,
}

/// Typed outcome of one cancel request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CancelJobResultDto {
    CancellationRequested,
    NoLongerCancellable,
}

/// Typed child LibraryScan admission issue for an Add & Scan workflow.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LibraryScanChildAdmissionIssueDto {
    AlreadyScanning {
        library_root_id: String,
        active_job_run_id: String,
        active_scan_run_id: String,
    },
    AdmissionFailure(ApplicationErrorDto),
}

/// Typed outcome of one Add & Scan composite workflow.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AddLocalLibraryRootAndScanResultDto {
    AddedAndScanAdmitted(LibraryRootDto, OperationHandleDto),
    AddedButScanNotAdmitted(LibraryRootDto, LibraryScanChildAdmissionIssueDto),
    AlreadyConfigured(String),
    OverlapsExisting(String, RootRelationshipDto),
}

/// Typed reason one retry request was not admitted.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RetryNotAdmittedReasonDto {
    SourceRunNotTerminal,
    OperationNotRetryable,
    NoEligibleTargets(Vec<LibraryScanAdmissionExclusionDto>),
}

/// Typed outcome of one retry request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RetryJobResultDto {
    Admitted(OperationHandleDto),
    AlreadyRetried(String),
    NotAdmitted(RetryNotAdmittedReasonDto),
}

/// One authoritative scan-run admission reference for a historical root.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRootScanAdmissionReferenceDto {
    pub job_run_id: String,
    pub scan_run_id: String,
}

/// Explicit source-graph invalidation scope union.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SourceEntriesChangeScopeDto {
    RootChildren,
    EntryChildren(String),
    EntireRootHierarchy,
}

/// User-selected diagnostic export destination.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DiagnosticsExportRequestDto {
    pub destination: String,
}

/// Safe terminal export summary; archive bytes never cross the bridge.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DiagnosticsExportDto {
    pub outcome: DiagnosticsExportOutcomeDto,
    pub destination_classification: String,
}

/// Diagnostic export outcome.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticsExportOutcomeDto {
    Created,
    Partial,
}

/// Copy-safe startup technical details.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TechnicalDetailsDto {
    pub text: String,
}

/// Typed outward event payloads. Stream items are never wrapped in
/// `BridgeResult`; stream transport failure is represented by the stream's
/// error channel and translated to Flutter `TransportFailure`.
#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeEventPayloadDto {
    RuntimeStateChanged {
        lifecycle: RuntimeLifecycleDto,
    },
    StartupFailed {
        phase: StartupPhaseDto,
    },
    AppearanceSettingsChanged,
    LibraryRootsChanged,
    LibraryRootChanged {
        library_root_id: String,
    },
    JobStateChanged {
        job_run_id: String,
    },
    JobProgress {
        job_run_id: String,
        phase: String,
        completed_units: Option<u64>,
        total_units: Option<u64>,
        status_key: Option<String>,
    },
    SourceEntriesChanged {
        library_root_id: String,
        scope: SourceEntriesChangeScopeDto,
    },
}

/// Unified runtime event envelope.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimeEventDto {
    pub runtime_instance_id: String,
    pub sequence: u64,
    pub occurred_at_ms: u64,
    pub payload: RuntimeEventPayloadDto,
}

/// Transport failure for a native event stream.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeTransportError {
    EventStreamClosed,
}

impl fmt::Display for BridgeTransportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::EventStreamClosed => "runtime event stream closed",
        })
    }
}

impl std::error::Error for BridgeTransportError {}

/// Maps a backend application error without changing any stable field.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn application_error_dto(error: &ApplicationError) -> ApplicationErrorDto {
    ApplicationErrorDto {
        code: error.code.as_str().to_owned(),
        category: category_name(error.category).to_owned(),
        severity: severity_name(error.severity).to_owned(),
        recoverability: recoverability_name(error.recoverability).to_owned(),
        retry_policy: retry_policy_name(error.retry_policy).to_owned(),
        message_key: error.message_key.as_str().to_owned(),
        trace_id: error.trace_id.to_string(),
        safe_context: safe_context_entries(&error.safe_context),
    }
}

/// Maps one runtime snapshot into its canonical DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn runtime_state_dto(state: &RuntimeState) -> RuntimeStateDto {
    RuntimeStateDto {
        runtime_instance_id: state.runtime_instance_id().to_string(),
        lifecycle_state: lifecycle_dto(state.lifecycle()),
        startup_phase: state.startup_phase().map(startup_phase_dto),
        startup_failure: state.startup_failure().map(startup_failure_dto),
    }
}

/// Maps one outward runtime event into its canonical DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn runtime_event_dto(event: &RuntimeEvent) -> RuntimeEventDto {
    RuntimeEventDto {
        runtime_instance_id: event.runtime_instance_id.to_string(),
        sequence: event.sequence,
        occurred_at_ms: event.occurred_at_ms,
        payload: match &event.payload {
            RuntimeEventPayload::RuntimeStateChanged { lifecycle } => {
                RuntimeEventPayloadDto::RuntimeStateChanged {
                    lifecycle: lifecycle_dto(*lifecycle),
                }
            }
            RuntimeEventPayload::StartupFailed { phase } => RuntimeEventPayloadDto::StartupFailed {
                phase: startup_phase_dto(*phase),
            },
            RuntimeEventPayload::AppearanceSettingsChanged => {
                RuntimeEventPayloadDto::AppearanceSettingsChanged
            }
            RuntimeEventPayload::LibraryRootsChanged => RuntimeEventPayloadDto::LibraryRootsChanged,
            RuntimeEventPayload::LibraryRootChanged { library_root_id } => {
                RuntimeEventPayloadDto::LibraryRootChanged {
                    library_root_id: library_root_id.to_string(),
                }
            }
            RuntimeEventPayload::JobStateChanged { job_run_id } => {
                RuntimeEventPayloadDto::JobStateChanged {
                    job_run_id: job_run_id.to_string(),
                }
            }
            RuntimeEventPayload::JobProgress {
                job_run_id,
                phase,
                completed_units,
                total_units,
                status_key,
            } => RuntimeEventPayloadDto::JobProgress {
                job_run_id: job_run_id.to_string(),
                phase: phase.clone(),
                completed_units: *completed_units,
                total_units: *total_units,
                status_key: status_key.clone(),
            },
            RuntimeEventPayload::SourceEntriesChanged {
                library_root_id,
                scope,
            } => RuntimeEventPayloadDto::SourceEntriesChanged {
                library_root_id: library_root_id.to_string(),
                scope: source_entries_scope_dto(*scope),
            },
        },
    }
}

/// Converts the closed bridge selection union into the application-owned
/// selection without interpreting provider identities in the bridge layer.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn local_filesystem_root_selection_from_dto(
    selection: LocalFilesystemRootSelectionDto,
) -> LocalFilesystemRootSelection {
    match selection {
        LocalFilesystemRootSelectionDto::Path {
            selected_folder_path,
        } => LocalFilesystemRootSelection::Path {
            selected_folder_path,
        },
        LocalFilesystemRootSelectionDto::ProviderSelection { selection_identity } => {
            LocalFilesystemRootSelection::ProviderSelection { selection_identity }
        }
    }
}

/// Converts native mounted-volume facts into the application synchronization
/// command. Mount paths remain transient ingress data and are never returned
/// by browse projections.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn sync_local_filesystem_mounted_volumes_command_from_dto(
    request: SyncLocalFilesystemMountedVolumesRequestDto,
) -> SyncLocalFilesystemMountedVolumesCommand {
    SyncLocalFilesystemMountedVolumesCommand::new(
        request
            .volumes
            .into_iter()
            .map(|volume| {
                MountedLocalFilesystemVolume::new(
                    volume.provider_volume_id,
                    volume.transient_mount_path,
                    volume.safe_display_name,
                    volume.is_primary,
                    volume.is_removable,
                )
            })
            .collect(),
    )
}

/// Maps one provider browse root into a safe transport projection.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn local_filesystem_browse_root_dto(
    root: &LocalFilesystemBrowseRoot,
) -> LocalFilesystemBrowseRootDto {
    LocalFilesystemBrowseRootDto {
        location: root.location().as_provider_value().to_owned(),
        display_name: root.display_name().to_owned(),
        safe_location_presentation: root.safe_location_presentation().to_owned(),
    }
}

/// Maps one provider browse page into a safe transport projection.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn local_filesystem_browse_page_dto(
    page: &LocalFilesystemBrowsePage,
) -> LocalFilesystemBrowsePageDto {
    LocalFilesystemBrowsePageDto {
        current: local_filesystem_browse_root_dto(page.current()),
        breadcrumbs: page
            .breadcrumbs()
            .iter()
            .map(|breadcrumb| LocalFilesystemBrowseBreadcrumbDto {
                location: breadcrumb.location().as_provider_value().to_owned(),
                display_name: breadcrumb.display_name().to_owned(),
            })
            .collect(),
        directories: page
            .directories()
            .iter()
            .map(|directory| LocalFilesystemBrowseDirectoryDto {
                location: directory.location().as_provider_value().to_owned(),
                display_name: directory.display_name().to_owned(),
            })
            .collect(),
        next_cursor: page
            .next_cursor()
            .map(|cursor| cursor.as_provider_value().to_owned()),
    }
}

/// Maps one authoritative runtime state through the current host.
#[allow(clippy::result_large_err)]
pub fn get_runtime_state() -> Result<RuntimeStateDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "get_runtime_state")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .try_current_state_with_context(&context)
        .map(|state| runtime_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Initializes the one application-lifetime host.
#[allow(clippy::result_large_err)]
pub fn initialize() -> Result<RuntimeStateDto, ApplicationErrorDto> {
    initialize_with_options(argus_runtime::KernelBootstrapOptions::default())
}

/// Initializes the host with an explicit embedding data directory.
#[allow(clippy::result_large_err)]
pub fn initialize_with_data_directory(
    data_directory: String,
) -> Result<RuntimeStateDto, ApplicationErrorDto> {
    initialize_with_options(argus_runtime::KernelBootstrapOptions::with_data_directory(
        data_directory,
    ))
}

/// Initializes the host with a host-supplied standard application-data root.
#[allow(clippy::result_large_err)]
pub fn initialize_with_standard_data_directory(
    data_directory: String,
) -> Result<RuntimeStateDto, ApplicationErrorDto> {
    initialize_with_options(
        argus_runtime::KernelBootstrapOptions::with_standard_data_directory(data_directory),
    )
}

#[allow(clippy::result_large_err)]
fn initialize_with_options(
    options: argus_runtime::KernelBootstrapOptions,
) -> Result<RuntimeStateDto, ApplicationErrorDto> {
    host_with_options(options)
        .initialize()
        .map(|state| runtime_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Retries startup against the caller's expected runtime generation.
#[allow(clippy::result_large_err)]
pub fn retry_startup(
    expected_runtime_instance_id: String,
) -> Result<RuntimeStateDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "retry_startup")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_runtime_id(&expected_runtime_instance_id, context.trace_id())?;
    host()
        .retry_startup_with_context(id, &context)
        .map(|state| runtime_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Performs generation-bound targeted appearance recovery.
#[allow(clippy::result_large_err)]
pub fn reset_appearance_settings(
    expected_runtime_instance_id: String,
) -> Result<RuntimeStateDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "reset_appearance_settings")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_runtime_id(&expected_runtime_instance_id, context.trace_id())?;
    host()
        .reset_appearance_settings_with_context(id, &context)
        .map(|state| runtime_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Exits a generation-bound failed runtime.
#[allow(clippy::result_large_err)]
pub fn exit_failed_runtime(
    expected_runtime_instance_id: String,
) -> Result<RuntimeStateDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "exit_failed_runtime")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_runtime_id(&expected_runtime_instance_id, context.trace_id())?;
    host()
        .exit_failed_runtime_with_context(id, &context)
        .map(|state| runtime_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Shuts down the current runtime generation.
#[allow(clippy::result_large_err)]
pub fn general_shutdown() -> Result<(), ApplicationErrorDto> {
    let (context, guard) = host()
        .begin_operation("runtime", "general_shutdown")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .general_shutdown_with_context(&context, &guard)
        .map_err(|error| application_error_dto(&error))
}

/// Closes the active native event connection without changing lifecycle
/// state. Client teardown uses this so a parked subscription can return
/// deterministically before local disposal.
#[allow(clippy::result_large_err)]
pub fn close_event_connection() -> Result<(), ApplicationErrorDto> {
    *pending_event_subscription() = None;
    host()
        .close_active_event_connection()
        .map_err(|error| application_error_dto(&error))
}

/// Returns the current event-connection admission epoch for the active
/// generation. Clients read this before subscribing so a fresh subscription
/// after teardown uses the current admission epoch.
#[allow(clippy::result_large_err)]
pub fn get_event_attach_epoch() -> Result<u64, ApplicationErrorDto> {
    host()
        .event_attach_epoch()
        .map_err(|error| application_error_dto(&error))
}

/// Reads the authoritative appearance aggregate.
#[allow(clippy::result_large_err)]
pub fn get_appearance_settings() -> Result<AppearanceSettingsDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("settings", "get_appearance_settings")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .get_appearance_settings_with_context(&context)
        .map(appearance_settings_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Updates the complete appearance aggregate and returns terminal success only.
#[allow(clippy::result_large_err)]
pub fn update_appearance_settings(
    request: UpdateAppearanceSettingsRequestDto,
) -> Result<(), ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("settings", "update_appearance_settings")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .update_appearance_settings_with_context(
            &context,
            appearance_settings_from_dto(request.theme_mode),
        )
        .map_err(|error| application_error_dto(&error))
}

/// Reads the query-authoritative Library onboarding projection.
#[allow(clippy::result_large_err)]
pub fn get_library_onboarding_state() -> Result<LibraryOnboardingStateDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "get_library_onboarding_state")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .library_onboarding_state_with_context(&context)
        .map(|state| library_onboarding_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Reads the Settings-owned privacy-consent projection.
#[allow(clippy::result_large_err)]
pub fn get_privacy_consent() -> Result<PrivacyConsentDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("settings", "get_privacy_consent")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .privacy_consent_with_context(&context)
        .map(|consent| privacy_consent_dto(&consent))
        .map_err(|error| application_error_dto(&error))
}

/// Accepts the backend-advertised current privacy-terms version.
#[allow(clippy::result_large_err)]
pub fn accept_privacy_terms(
    request: AcceptPrivacyTermsRequestDto,
) -> Result<PrivacyConsentDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("settings", "accept_privacy_terms")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .accept_privacy_terms_with_context(&context, request.terms_version)
        .map(|consent| privacy_consent_dto(&consent))
        .map_err(|error| application_error_dto(&error))
}

/// Commits onboarding metadata preferences.
#[allow(clippy::result_large_err)]
pub fn confirm_library_metadata_preferences(
    settings: MetadataSettingsDto,
) -> Result<LibraryOnboardingStateDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "confirm_library_metadata_preferences")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .confirm_library_metadata_preferences_with_context(
            &context,
            metadata_settings_from_dto(settings),
        )
        .map(|state| library_onboarding_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Records the onboarding provider setup decision.
#[allow(clippy::result_large_err)]
pub fn record_library_provider_setup(
    decision: LibraryProviderSetupDecisionDto,
) -> Result<LibraryOnboardingStateDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "record_library_provider_setup")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .record_library_provider_setup_with_context(
            &context,
            library_provider_setup_decision_from_dto(decision),
        )
        .map(|state| library_onboarding_state_dto(&state))
        .map_err(|error| application_error_dto(&error))
}

/// Commits onboarding completion and independently admits the initial refresh.
#[allow(clippy::result_large_err)]
pub fn complete_library_onboarding_and_refresh()
-> Result<CompleteLibraryOnboardingAndRefreshResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "complete_library_onboarding_and_refresh")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .complete_library_onboarding_and_refresh_with_context(&context)
        .map(|result| complete_library_onboarding_and_refresh_dto(&result))
        .map_err(|error| application_error_dto(&error))
}

/// Adds the first onboarding root and independently admits its initial
/// composed refresh.
#[allow(clippy::result_large_err)]
pub fn add_library_root_and_refresh(
    selection: LocalFilesystemRootSelectionDto,
) -> Result<AddLibraryRootAndRefreshResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "add_library_root_and_refresh")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .add_library_root_and_refresh_with_context(
            &context,
            local_filesystem_root_selection_from_dto(selection),
        )
        .map(add_library_root_and_refresh_result_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Reads local metadata preferences.
#[allow(clippy::result_large_err)]
pub fn get_metadata_settings() -> Result<MetadataSettingsDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("metadata", "get_metadata_settings")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .metadata_settings_with_context(&context)
        .map(metadata_settings_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Reads provider enablement preferences.
#[allow(clippy::result_large_err)]
pub fn get_metadata_provider_settings() -> Result<MetadataProviderSettingsDto, ApplicationErrorDto>
{
    let (context, _guard) = host()
        .begin_operation("metadata", "get_metadata_provider_settings")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .metadata_provider_settings_with_context(&context)
        .map(metadata_provider_settings_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Commits metadata preferences and reports independent local-resolution
/// admission.
#[allow(clippy::result_large_err)]
pub fn update_metadata_settings(
    settings: MetadataSettingsDto,
) -> Result<MetadataSettingsUpdateResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("metadata", "update_metadata_settings")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .update_metadata_settings_with_context(&context, metadata_settings_from_dto(settings))
        .map(metadata_settings_update_result_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Commits provider enablement and reports independent local-resolution
/// admission.
#[allow(clippy::result_large_err)]
pub fn update_metadata_provider_settings(
    settings: MetadataProviderSettingsDto,
) -> Result<MetadataProviderSettingsUpdateResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("metadata", "update_metadata_provider_settings")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .update_metadata_provider_settings_with_context(
            &context,
            metadata_provider_settings_from_dto(settings, context.trace_id())?,
        )
        .map(metadata_provider_settings_update_result_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Admits one bounded Game refresh.
#[allow(clippy::result_large_err)]
pub fn start_game_refresh(
    request: StartGameRefreshRequestDto,
) -> Result<OperationHandleDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "start_game_refresh")
        .map_err(|error| application_error_dto(&error))?;
    let game_ids = request
        .game_ids
        .iter()
        .map(|value| {
            GameId::try_from(value.as_str()).map_err(|_| validation_failure(context.trace_id()))
        })
        .collect::<Result<Vec<_>, _>>()?;
    host()
        .start_game_refresh_with_context(game_ids, refresh_mode_from_dto(request.mode), &context)
        .map(|handle| OperationHandleDto {
            job_run_id: handle.job_run_id().to_string(),
            operation_type: handle.operation_type().to_owned(),
        })
        .map_err(|error| application_error_dto(&error))
}

/// Admits one normal composed Library refresh.
#[allow(clippy::result_large_err)]
pub fn refresh_library() -> Result<OperationHandleDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "refresh_library")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .refresh_library_with_context(&context)
        .map(|handle| OperationHandleDto {
            job_run_id: handle.job_run_id().to_string(),
            operation_type: handle.operation_type().to_owned(),
        })
        .map_err(|error| application_error_dto(&error))
}

/// Lists a bounded authoritative configured-root page.
#[allow(clippy::result_large_err)]
pub fn list_library_roots(
    request: ListLibraryRootsRequestDto,
) -> Result<LibraryRootPageDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "list_library_roots")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .list_library_roots_with_context(
            &ListLibraryRootsQuery::new(request.offset, request.page_size),
            &context,
        )
        .map(|page| library_root_page_dto(&page))
        .map_err(|error| application_error_dto(&error))
}

/// Reads one authoritative configured root.
#[allow(clippy::result_large_err)]
pub fn get_library_root(library_root_id: String) -> Result<LibraryRootDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "get_library_root")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_library_root_id(&library_root_id, context.trace_id())?;
    host()
        .get_library_root_with_context(id, &context)
        .map(|root| library_root_dto(&root))
        .map_err(|error| application_error_dto(&error))
}

/// Lists the baseline logical-library page. Structurally valid BE-008 query
/// concepts outside the P03-001 activation subset are rejected as
/// `ARGUS.V1.VALIDATION.INVALID_ARGUMENT`.
#[allow(clippy::result_large_err)]
pub fn list_games(request: ListGamesRequestDto) -> Result<GamePageDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "list_games")
        .map_err(|error| application_error_dto(&error))?;
    let query = list_games_query_from_dto(request, context.trace_id())?;
    host()
        .list_games_with_context(query, &context)
        .map(|page| game_page_dto(&page))
        .map_err(|error| application_error_dto(&error))
}

/// Reads one focused logical game. Redirects are represented explicitly;
/// missing canonical games use the published typed application error.
#[allow(clippy::result_large_err)]
pub fn get_game(game_id: String) -> Result<GetGameResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("library", "get_game")
        .map_err(|error| application_error_dto(&error))?;
    let game_id = parse_game_id(&game_id, context.trace_id())?;
    let result = host()
        .get_game_with_context(game_id, &context)
        .map_err(|error| application_error_dto(&error))?;
    match result {
        GetGameResult::Found(detail) => Ok(GetGameResultDto::Found(game_detail_dto(&detail))),
        GetGameResult::Redirected(canonical_game_id) => Ok(GetGameResultDto::Redirected {
            canonical_game_id: canonical_game_id.to_string(),
        }),
        GetGameResult::NotFound => Err(application_error_dto(
            &ApplicationError::from_code(
                ErrorCode::ConfigurationGameNotFound,
                context.trace_id(),
                SafeContext::new(),
            )
            .expect("game-not-found error uses an allowlisted empty context"),
        )),
    }
}

/// Reads provider enablement and safe readiness without starting hydration.
#[allow(clippy::result_large_err)]
pub fn list_metadata_provider_readiness()
-> Result<Vec<MetadataProviderReadinessDto>, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("metadata", "provider_readiness")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .metadata_provider_readiness_with_context(&context)
        .map(|values| values.iter().map(metadata_provider_readiness_dto).collect())
        .map_err(|error| application_error_dto(&error))
}

/// Writes and validates a provider credential without returning its bytes.
#[allow(clippy::result_large_err)]
pub fn set_metadata_provider_credential(
    request: SetMetadataProviderCredentialRequestDto,
) -> Result<ProviderCredentialReadinessDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("metadata", "set_provider_credential")
        .map_err(|error| application_error_dto(&error))?;
    let provider_id = ProviderId::try_from(request.provider_id.as_str())
        .map_err(|_| validation_failure(context.trace_id()))?;
    host()
        .set_metadata_provider_credential_with_context(
            provider_id,
            request.credential_input,
            &context,
        )
        .map(provider_credential_readiness_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Removes a provider credential without exposing prior secret state.
#[allow(clippy::result_large_err)]
pub fn remove_metadata_provider_credential(
    request: RemoveMetadataProviderCredentialRequestDto,
) -> Result<ProviderCredentialReadinessDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("metadata", "remove_provider_credential")
        .map_err(|error| application_error_dto(&error))?;
    let provider_id = ProviderId::try_from(request.provider_id.as_str())
        .map_err(|_| validation_failure(context.trace_id()))?;
    host()
        .remove_metadata_provider_credential_with_context(provider_id, &context)
        .map(provider_credential_readiness_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Reads one bounded immutable artwork object by content address.
#[allow(clippy::result_large_err)]
pub fn get_artwork_asset_bytes(
    asset_id: String,
) -> Result<ArtworkAssetBytesDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("artwork", "get_asset_bytes")
        .map_err(|error| application_error_dto(&error))?;
    let asset_id = argus_application::ArtworkAssetId::try_from(asset_id.as_str())
        .map_err(|_| validation_failure(context.trace_id()))?;
    host()
        .get_artwork_asset_bytes_with_context(asset_id, &context)
        .map(artwork_asset_bytes_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Replaces the transient native mounted-volume registry and reconciles
/// persisted root availability. Native mount facts are ingress-only.
#[allow(clippy::result_large_err)]
pub fn sync_local_filesystem_mounted_volumes(
    request: SyncLocalFilesystemMountedVolumesRequestDto,
) -> Result<(), ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "sync_local_filesystem_mounted_volumes")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .sync_local_filesystem_mounted_volumes_with_context(
            &context,
            sync_local_filesystem_mounted_volumes_command_from_dto(request),
        )
        .map_err(|error| application_error_dto(&error))
}

/// Lists currently mounted safe browse roots.
#[allow(clippy::result_large_err)]
pub fn list_local_filesystem_browse_roots()
-> Result<Vec<LocalFilesystemBrowseRootDto>, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "list_local_filesystem_browse_roots")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .list_local_filesystem_browse_roots_with_context(&context)
        .map(|roots| roots.iter().map(local_filesystem_browse_root_dto).collect())
        .map_err(|error| application_error_dto(&error))
}

/// Lists one bounded page of safe direct-child browse directories.
#[allow(clippy::result_large_err)]
pub fn list_local_filesystem_browse_directories(
    request: ListLocalFilesystemBrowseDirectoriesRequestDto,
) -> Result<LocalFilesystemBrowsePageDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "list_local_filesystem_browse_directories")
        .map_err(|error| application_error_dto(&error))?;
    let location = LocalFilesystemBrowseLocation::from_provider(request.location);
    let cursor = request
        .cursor
        .map(LocalFilesystemBrowseCursor::from_provider);
    host()
        .list_local_filesystem_browse_directories_with_context(
            &context,
            &location,
            cursor.as_ref(),
            request.page_size,
        )
        .map(|page| local_filesystem_browse_page_dto(&page))
        .map_err(|error| application_error_dto(&error))
}

/// Configures one root-only local library folder.
#[allow(clippy::result_large_err)]
pub fn add_local_library_root(
    selection: LocalFilesystemRootSelectionDto,
) -> Result<AddLocalLibraryRootResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "add_local_library_root")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .add_local_library_root_with_context(
            &context,
            local_filesystem_root_selection_from_dto(selection),
        )
        .map(|result| add_local_library_root_dto(&result))
        .map_err(|error| application_error_dto(&error))
}

/// Executes the Add & Scan composite workflow: commit the root, then request
/// child LibraryScan admission, then assemble the typed committed result.
#[allow(clippy::result_large_err)]
pub fn add_local_library_root_and_scan(
    selection: LocalFilesystemRootSelectionDto,
) -> Result<AddLocalLibraryRootAndScanResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "add_local_library_root_and_scan")
        .map_err(|error| application_error_dto(&error))?;
    host()
        .add_local_library_root_and_scan_with_context(
            &context,
            local_filesystem_root_selection_from_dto(selection),
        )
        .map(|result| add_local_library_root_and_scan_dto(&result))
        .map_err(|error| application_error_dto(&error))
}

/// Removes one configured root. User filesystem content is never modified.
#[allow(clippy::result_large_err)]
pub fn remove_library_root(
    library_root_id: String,
) -> Result<RemoveLibraryRootResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "remove_library_root")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_library_root_id(&library_root_id, context.trace_id())?;
    host()
        .remove_library_root_with_context(&context, id)
        .map(|result| remove_library_root_dto(&result))
        .map_err(|error| application_error_dto(&error))
}

/// Admits one durable single-root library scan.
#[allow(clippy::result_large_err)]
pub fn start_library_scan(
    library_root_id: String,
) -> Result<StartLibraryScanResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "start_library_scan")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_library_root_id(&library_root_id, context.trace_id())?;
    host()
        .start_library_scan_with_context(id, &context)
        .map(|result| start_library_scan_result_dto(&result))
        .map_err(|error| application_error_dto(&error))
}

/// Admits one durable multi-root Scan All over all configured roots.
#[allow(clippy::result_large_err)]
pub fn start_library_scan_all(
    request_identity: String,
) -> Result<StartLibraryScanAllResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "start_library_scan_all")
        .map_err(|error| application_error_dto(&error))?;
    let identity = parse_scan_all_request_identity(&request_identity, context.trace_id())?;
    host()
        .start_library_scan_all_with_context(identity, &context)
        .map(|result| start_library_scan_all_result_dto(&result))
        .map_err(|error| application_error_dto(&error))
}

/// Resolves one Scan All request identity to its accepted admission or
/// authoritative no-admission proof after transport ambiguity.
#[allow(clippy::result_large_err)]
pub fn resolve_scan_all_request(
    request_identity: String,
) -> Result<LibraryScanAllRequestResolutionDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("jobs", "resolve_scan_all_request")
        .map_err(|error| application_error_dto(&error))?;
    let identity = parse_scan_all_request_identity(&request_identity, context.trace_id())?;
    host()
        .resolve_scan_all_request_with_context(identity, &context)
        .map(library_scan_all_request_resolution_dto)
        .map_err(|error| application_error_dto(&error))
}

/// Lists one bounded authoritative direct-child page.
#[allow(clippy::result_large_err)]
pub fn list_source_entry_children(
    request: ListSourceEntryChildrenRequestDto,
) -> Result<SourceEntryChildrenPageDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "list_source_entry_children")
        .map_err(|error| application_error_dto(&error))?;
    let query = ListSourceEntryChildrenQuery::new(
        parse_library_root_id(&request.library_root_id, context.trace_id())?,
        match request.parent_source_entry_id {
            Some(parent) => Some(parse_source_entry_id(&parent, context.trace_id())?),
            None => None,
        },
        parse_source_entry_cursor(request.cursor, context.trace_id())?,
        request.page_size,
    );
    host()
        .list_source_entry_children_with_context(&query, &context)
        .map(|page| source_entry_children_page_dto(&page))
        .map_err(|error| application_error_dto(&error))
}

/// Reads one authoritative source-entry detail.
#[allow(clippy::result_large_err)]
pub fn get_source_entry(
    source_entry_id: String,
) -> Result<SourceEntryDetailDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("sources", "get_source_entry")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_source_entry_id(&source_entry_id, context.trace_id())?;
    host()
        .get_source_entry_with_context(id, &context)
        .map(|detail| source_entry_detail_projection_dto(&detail))
        .map_err(|error| application_error_dto(&error))
}

/// Lists one closed authoritative Jobs scope.
#[allow(clippy::result_large_err)]
pub fn list_jobs(request: ListJobsRequestDto) -> Result<JobSummaryPageDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("jobs", "list_jobs")
        .map_err(|error| application_error_dto(&error))?;
    let scope = match request.scope {
        ListJobsScopeDto::Active => ListJobsScope::Active,
        ListJobsScopeDto::RecentTerminal { offset, page_size } => {
            ListJobsScope::RecentTerminal { offset, page_size }
        }
    };
    host()
        .list_jobs_with_context(ListJobsQuery::new(scope), &context)
        .map(|page| job_summary_page_dto(&page))
        .map_err(|error| application_error_dto(&error))
}

/// Reads one authoritative job detail.
#[allow(clippy::result_large_err)]
pub fn get_job(job_run_id: String) -> Result<JobDetailDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("jobs", "get_job")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_job_run_id(&job_run_id, context.trace_id())?;
    host()
        .get_job_with_context(id, &context)
        .map(|detail| job_detail_dto(&detail))
        .map_err(|error| application_error_dto(&error))
}

/// Requests durable cancellation for one job.
#[allow(clippy::result_large_err)]
pub fn cancel_job(job_run_id: String) -> Result<CancelJobResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("jobs", "cancel_job")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_job_run_id(&job_run_id, context.trace_id())?;
    host()
        .cancel_job_with_context(id, &context)
        .map(|result| match result {
            argus_application::CancelJobResult::CancellationRequested => {
                CancelJobResultDto::CancellationRequested
            }
            argus_application::CancelJobResult::NoLongerCancellable => {
                CancelJobResultDto::NoLongerCancellable
            }
        })
        .map_err(|error| application_error_dto(&error))
}

/// Reports a live execution-host stop without entering durable cancellation.
#[allow(clippy::result_large_err)]
pub fn report_execution_host_stop(
    request: ReportExecutionHostStopRequestDto,
) -> Result<(), ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "report_execution_host_stop")
        .map_err(|error| application_error_dto(&error))?;
    let (job_run_ids, reason) = parse_execution_host_stop_request(request, context.trace_id())?;
    host()
        .report_execution_host_stop_with_context(&job_run_ids, reason, &context)
        .map_err(|error| application_error_dto(&error))
}

/// Retries one eligible historical LibraryScan into a new durable run.
#[allow(clippy::result_large_err)]
pub fn retry_job(job_run_id: String) -> Result<RetryJobResultDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("jobs", "retry_job")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_job_run_id(&job_run_id, context.trace_id())?;
    host()
        .retry_job_with_context(id, &context)
        .map(|result| retry_job_result_dto(result.outcome()))
        .map_err(|error| application_error_dto(&error))
}

/// Reads the newest scan-run admission (active or terminal) for one root.
///
/// This focused query supplies Jobs-authoritative Add & Scan ambiguity
/// reconciliation; callers must never infer admission from root `lastScan`.
#[allow(clippy::result_large_err)]
pub fn get_root_scan_admission(
    library_root_id: String,
) -> Result<Option<LibraryRootScanAdmissionReferenceDto>, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("jobs", "get_root_scan_admission")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_library_root_id(&library_root_id, context.trace_id())?;
    host()
        .get_root_scan_admission_with_context(id, &context)
        .map(|reference| {
            reference.map(|reference| LibraryRootScanAdmissionReferenceDto {
                job_run_id: reference.job_run_id().to_string(),
                scan_run_id: reference.scan_run_id().to_string(),
            })
        })
        .map_err(|error| application_error_dto(&error))
}

/// Writes sanitized startup diagnostics to the embedding-selected path.
#[allow(clippy::result_large_err)]
pub fn export_startup_diagnostics(
    expected_runtime_instance_id: String,
    request: DiagnosticsExportRequestDto,
) -> Result<DiagnosticsExportDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "export_startup_diagnostics")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_runtime_id(&expected_runtime_instance_id, context.trace_id())?;
    host()
        .export_startup_diagnostics_with_context(
            id,
            std::path::Path::new(&request.destination),
            &context,
        )
        .map(|export| DiagnosticsExportDto {
            outcome: match export.outcome {
                DiagnosticsExportOutcome::Created => DiagnosticsExportOutcomeDto::Created,
                DiagnosticsExportOutcome::Partial => DiagnosticsExportOutcomeDto::Partial,
            },
            destination_classification: export.destination_classification.to_owned(),
        })
        .map_err(|error| application_error_dto(&error))
}

/// Creates the backend-owned diagnostics artifact without accepting a
/// destination from the embedding layer. Android publishes the completed
/// artifact through its scoped native share boundary.
#[allow(clippy::result_large_err)]
pub fn export_startup_diagnostics_for_sharing(
    expected_runtime_instance_id: String,
) -> Result<DiagnosticsExportDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "export_startup_diagnostics_for_sharing")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_runtime_id(&expected_runtime_instance_id, context.trace_id())?;
    host()
        .export_startup_diagnostics_for_sharing_with_context(id, &context)
        .map(|export| DiagnosticsExportDto {
            outcome: match export.outcome {
                DiagnosticsExportOutcome::Created => DiagnosticsExportOutcomeDto::Created,
                DiagnosticsExportOutcome::Partial => DiagnosticsExportOutcomeDto::Partial,
            },
            destination_classification: export.destination_classification.to_owned(),
        })
        .map_err(|error| application_error_dto(&error))
}

/// Returns copy-safe technical details for a failed startup generation.
#[allow(clippy::result_large_err)]
pub fn startup_technical_details(
    expected_runtime_instance_id: String,
) -> Result<TechnicalDetailsDto, ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "startup_technical_details")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_runtime_id(&expected_runtime_instance_id, context.trace_id())?;
    host()
        .startup_technical_details_with_context(id, &context)
        .map(|details| TechnicalDetailsDto { text: details.text })
        .map_err(|error| application_error_dto(&error))
}

/// Opens a failed generation's data directory through the host shell.
#[allow(clippy::result_large_err)]
pub fn open_startup_data_directory(
    expected_runtime_instance_id: String,
) -> Result<(), ApplicationErrorDto> {
    let (context, _guard) = host()
        .begin_operation("runtime", "open_startup_data_directory")
        .map_err(|error| application_error_dto(&error))?;
    let id = parse_runtime_id(&expected_runtime_instance_id, context.trace_id())?;
    host()
        .open_startup_data_directory_with_context(id, &context)
        .map_err(|error| application_error_dto(&error))
}

/// Bridge-private holder for the one attached native event subscription
/// awaiting its receive loop.
struct PendingEventSubscription {
    attach_epoch: u64,
    subscription: RuntimeEventSubscription,
}

static PENDING_EVENT_SUBSCRIPTION: Mutex<Option<PendingEventSubscription>> = Mutex::new(None);

fn pending_event_subscription() -> std::sync::MutexGuard<'static, Option<PendingEventSubscription>>
{
    PENDING_EVENT_SUBSCRIPTION
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
}

/// Bridge-private: attaches the one native event connection for the current
/// admission epoch and stores it for the subsequent receive call. Completing
/// this FRB call is the native-attachment acknowledgement the Dart client
/// awaits before reporting event binding usable.
pub fn attach_event_subscription(attach_epoch: u64) -> Result<bool, BridgeTransportError> {
    let subscription = match host().subscribe_events_with_epoch(attach_epoch) {
        Ok(subscription) => subscription,
        Err(error) => {
            *pending_event_subscription() = None;
            if let Some(transport_error) = classify_subscribe_error(&error) {
                return Err(transport_error);
            }
            // Lifecycle-expected rejection (stale epoch or closed boundary):
            // the receive call completes normally, matching the existing
            // subscribe_events contract.
            return Ok(false);
        }
    };
    *pending_event_subscription() = Some(PendingEventSubscription {
        attach_epoch,
        subscription,
    });
    Ok(true)
}

/// Starts the single unified runtime event stream. Each item is a
/// `RuntimeEventDto`, never a `BridgeResult<RuntimeEventDto>`. Consumes the
/// subscription attached by [attach_event_subscription] for the same epoch;
/// falls back to attaching directly so the receive call remains usable on its
/// own.
pub fn subscribe_events(
    attach_epoch: u64,
    sink: StreamSink<RuntimeEventDto>,
) -> Result<(), BridgeTransportError> {
    let subscription = match pending_event_subscription()
        .take_if(|pending| pending.attach_epoch == attach_epoch)
    {
        Some(pending) => pending.subscription,
        None => match host().subscribe_events_with_epoch(attach_epoch) {
            Ok(subscription) => subscription,
            Err(error) => {
                if let Some(transport_error) = classify_subscribe_error(&error) {
                    return Err(transport_error);
                }
                // A subscription carrying a stale admission epoch or attaching
                // to an already-closed boundary is an expected lifecycle
                // outcome (generation replacement, shutdown, or client
                // teardown racing the attach). Complete the stream normally
                // instead of surfacing a transport error after client
                // teardown.
                return Ok(());
            }
        },
    };
    // Event forwarding runs on a dedicated thread rather than occupying the
    // FRB handler executor. FRB sizes its pool from the host CPU count, so a
    // blocking subscription loop on the handler thread would starve every
    // later bridge call on low-core Android devices.
    std::thread::Builder::new()
        .name("argus-event-forward".to_owned())
        .spawn(move || {
            loop {
                match subscription.recv() {
                    Ok(event) => {
                        if sink.add(runtime_event_dto(&event)).is_err() {
                            // The Dart side closed or cancelled the stream;
                            // stop forwarding and let the subscription drop.
                            return;
                        }
                    }
                    Err(RuntimeEventStreamError::Closed) => {
                        // A closed runtime connection is an expected lifecycle
                        // outcome (shutdown or generation replacement).
                        return;
                    }
                    Err(RuntimeEventStreamError::Internal) => {
                        // Poisoned internal synchronization state cannot be
                        // recovered; stop forwarding.
                        return;
                    }
                }
            }
        })
        .expect("event forwarding thread spawn");
    Ok(())
}

/// Maps a subscription-establishment failure to its transport projection.
/// Only the stale-generation/closed-boundary attach race is treated as a
/// normal stream completion; every genuine failure stays observable.
fn classify_subscribe_error(error: &ApplicationError) -> Option<BridgeTransportError> {
    match error.code {
        ErrorCode::RuntimeStaleInstance => None,
        _ => Some(BridgeTransportError::EventStreamClosed),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        ExecutionHostStopReasonDto, ReportExecutionHostStopRequestDto,
        SetMetadataProviderCredentialRequestDto, classify_subscribe_error,
    };
    use argus_application::{
        ApplicationError, BackgroundOperationStopReason, ErrorCode, SafeContext,
    };

    fn subscribe_error(code: ErrorCode) -> ApplicationError {
        ApplicationError::from_code(code, argus_runtime::new_trace_id(), SafeContext::new())
            .expect("error code has a published policy")
    }

    #[test]
    fn stale_generation_attach_race_completes_normally() {
        let error = subscribe_error(ErrorCode::RuntimeStaleInstance);

        assert!(classify_subscribe_error(&error).is_none());
    }

    #[test]
    fn genuine_subscribe_failures_remain_transport_errors() {
        let error = subscribe_error(ErrorCode::InternalUnexpected);

        assert!(classify_subscribe_error(&error).is_some());
    }

    #[test]
    fn android_platform_safe_context_serializes_to_android() {
        use argus_application::{PlatformClass, SafeContextField, SafeContextValue};

        let mut context = SafeContext::new();
        context
            .try_insert(
                SafeContextField::Platform,
                SafeContextValue::Platform(PlatformClass::Android),
            )
            .expect("android platform field");

        let entries = super::safe_context_entries(&context);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].field, "platform");
        assert_eq!(entries[0].value, "android");
    }

    #[test]
    fn execution_host_stop_request_maps_only_supported_host_reasons() {
        let trace_id = argus_runtime::new_trace_id();
        let request = ReportExecutionHostStopRequestDto {
            job_run_ids: vec!["11111111111111111111111111111111".to_owned()],
            reason: ExecutionHostStopReasonDto::Timeout,
        };
        let (ids, reason) = super::parse_execution_host_stop_request(request, trace_id)
            .expect("valid timeout request");
        assert_eq!(ids.len(), 1);
        assert_eq!(reason, BackgroundOperationStopReason::ExecutionHostTimeout);

        let request = ReportExecutionHostStopRequestDto {
            job_run_ids: vec!["22222222222222222222222222222222".to_owned()],
            reason: ExecutionHostStopReasonDto::HostLost,
        };
        let (_, reason) = super::parse_execution_host_stop_request(request, trace_id)
            .expect("valid host-loss request");
        assert_eq!(reason, BackgroundOperationStopReason::ExecutionHostLost);
    }

    #[test]
    fn execution_host_stop_request_rejects_empty_oversized_and_malformed_ids() {
        let trace_id = argus_runtime::new_trace_id();
        let empty = ReportExecutionHostStopRequestDto {
            job_run_ids: Vec::new(),
            reason: ExecutionHostStopReasonDto::Timeout,
        };
        assert_eq!(
            super::parse_execution_host_stop_request(empty, trace_id)
                .expect_err("empty request rejected")
                .code,
            ErrorCode::ValidationInvalidArgument.as_str()
        );

        let oversized = ReportExecutionHostStopRequestDto {
            job_run_ids: (0..17)
                .map(|_| "11111111111111111111111111111111".to_owned())
                .collect(),
            reason: ExecutionHostStopReasonDto::Timeout,
        };
        assert_eq!(
            super::parse_execution_host_stop_request(oversized, trace_id)
                .expect_err("oversized request rejected")
                .code,
            ErrorCode::ValidationInvalidArgument.as_str()
        );

        let malformed = ReportExecutionHostStopRequestDto {
            job_run_ids: vec!["not-a-job-id".to_owned()],
            reason: ExecutionHostStopReasonDto::HostLost,
        };
        assert_eq!(
            super::parse_execution_host_stop_request(malformed, trace_id)
                .expect_err("malformed id rejected")
                .code,
            ErrorCode::ValidationInvalidArgument.as_str()
        );
    }

    #[test]
    fn credential_request_debug_reports_only_provider_and_input_length() {
        let request = SetMetadataProviderCredentialRequestDto {
            provider_id: "steamgriddb".to_owned(),
            credential_input: b"secret".to_vec(),
        };

        let debug = format!("{request:?}");

        assert!(debug.contains("steamgriddb"));
        assert!(debug.contains("credential_input_len"));
        assert!(!debug.contains("secret"));
    }
}

fn host() -> &'static ApplicationHost {
    host_with_options(argus_runtime::KernelBootstrapOptions::default())
}

fn host_with_options(options: argus_runtime::KernelBootstrapOptions) -> &'static ApplicationHost {
    static HOST: OnceLock<ApplicationHost> = OnceLock::new();
    HOST.get_or_init(|| {
        ApplicationHost::with_notification_sink(
            options,
            Arc::new(BridgeNotificationSink::default()),
        )
    })
}

/// Bridge-owned adapter for the inward notification sink port. The unified
/// outward transport remains the runtime event boundary consumed by
/// `SubscribeEvents`; this adapter only proves registration/readiness.
#[flutter_rust_bridge::frb(ignore)]
struct BridgeNotificationSink {
    publisher: Mutex<Option<Arc<RuntimeEventPublisher>>>,
}

impl Default for BridgeNotificationSink {
    fn default() -> Self {
        Self {
            publisher: Mutex::new(None),
        }
    }
}

impl RuntimeNotificationSink for BridgeNotificationSink {
    fn bind(&self, publisher: Arc<RuntimeEventPublisher>) -> Result<(), NotificationSinkError> {
        *self
            .publisher
            .lock()
            .map_err(|_| NotificationSinkError::Unavailable)? = Some(publisher);
        Ok(())
    }

    fn validate(&self) -> Result<(), NotificationSinkError> {
        match self
            .publisher
            .lock()
            .map_err(|_| NotificationSinkError::Unavailable)?
            .as_ref()
        {
            Some(publisher) if publisher.is_open() => Ok(()),
            _ => Err(NotificationSinkError::Unavailable),
        }
    }

    fn publish(&self, event: RuntimeEventPayload) -> Result<(), NotificationSinkError> {
        let publisher = self
            .publisher
            .lock()
            .map_err(|_| NotificationSinkError::Unavailable)?;
        publisher
            .as_ref()
            .ok_or(NotificationSinkError::Unavailable)?
            .emit(event)
    }
}

#[allow(clippy::result_large_err)]
fn parse_runtime_id(
    value: &str,
    trace_id: argus_application::TraceId,
) -> Result<RuntimeInstanceId, ApplicationErrorDto> {
    RuntimeInstanceId::from_hex(value).map_err(|_| {
        application_error_dto(
            &ApplicationError::from_code(
                argus_application::ErrorCode::ValidationInvalidArgument,
                trace_id,
                SafeContext::new(),
            )
            .expect("validation error"),
        )
    })
}

/// Parses one bridge-supplied root identity with typed validation.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn parse_library_root_id(
    value: &str,
    trace_id: argus_application::TraceId,
) -> Result<LibraryRootId, ApplicationErrorDto> {
    LibraryRootId::try_from(value).map_err(|_| {
        application_error_dto(
            &ApplicationError::from_code(
                argus_application::ErrorCode::ValidationInvalidArgument,
                trace_id,
                SafeContext::new(),
            )
            .expect("validation error"),
        )
    })
}

/// Parses one bridge-supplied logical-game identity with typed validation.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn parse_game_id(
    value: &str,
    trace_id: argus_application::TraceId,
) -> Result<GameId, ApplicationErrorDto> {
    GameId::try_from(value).map_err(|_| validation_failure(trace_id))
}

/// Parses one bridge-supplied Scan All request identity with typed
/// validation.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn parse_scan_all_request_identity(
    value: &str,
    trace_id: argus_application::TraceId,
) -> Result<LibraryScanAllRequestIdentity, ApplicationErrorDto> {
    LibraryScanAllRequestIdentity::try_from(value).map_err(|_| {
        application_error_dto(
            &ApplicationError::from_code(
                argus_application::ErrorCode::ValidationInvalidArgument,
                trace_id,
                SafeContext::new(),
            )
            .expect("validation error"),
        )
    })
}

/// Parses one bridge-supplied source-entry identity with typed validation.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn parse_source_entry_id(
    value: &str,
    trace_id: argus_application::TraceId,
) -> Result<SourceEntryId, ApplicationErrorDto> {
    SourceEntryId::try_from(value).map_err(|_| validation_failure(trace_id))
}

/// Validates one externally supplied opaque cursor at the bridge boundary.
///
/// Malformed external cursor text is a validation/application failure, never
/// a persistence failure. The returned cursor is the structured
/// application-owned value consumed by persistence.
#[allow(unexpected_cfgs)]
#[allow(clippy::result_large_err)]
#[flutter_rust_bridge::frb(ignore)]
pub fn parse_source_entry_cursor(
    value: Option<String>,
    trace_id: argus_application::TraceId,
) -> Result<Option<SourceEntryCursor>, ApplicationErrorDto> {
    value
        .map(|value| {
            SourceEntryCursor::try_from(value.as_str()).map_err(|_| validation_failure(trace_id))
        })
        .transpose()
}

#[allow(clippy::result_large_err)]
fn list_games_query_from_dto(
    request: ListGamesRequestDto,
    trace_id: argus_application::TraceId,
) -> Result<ListGamesQuery, ApplicationErrorDto> {
    if !matches!(request.scope, LibraryScopeDto::All)
        || request.search_text.is_some()
        || !request.filters.platform_ids.is_empty()
        || !request.filters.regions.is_empty()
        || !request.filters.hydration_states.is_empty()
        || !request.filters.availability_states.is_empty()
        || request.sort.field != LibrarySortFieldDto::DisplayTitle
        || request.sort.direction != LibrarySortDirectionDto::Ascending
    {
        return Err(validation_failure(trace_id));
    }

    let cursor = request
        .cursor
        .map(|value| {
            GameListCursor::try_from_external(value).map_err(|_| validation_failure(trace_id))
        })
        .transpose()?;
    ListGamesQuery::builder()
        .scope(LibraryScope::All)
        .search(None)
        .filters_empty(true)
        .sort(LibrarySort::DisplayTitleAscending)
        .cursor(cursor)
        .page_size(request.page_size)
        .build()
        .map_err(|_| validation_failure(trace_id))
}

fn validation_failure(trace_id: argus_application::TraceId) -> ApplicationErrorDto {
    application_error_dto(
        &ApplicationError::from_code(
            argus_application::ErrorCode::ValidationInvalidArgument,
            trace_id,
            SafeContext::new(),
        )
        .expect("validation error"),
    )
}

fn appearance_settings_dto(
    settings: argus_application::AppearanceSettings,
) -> AppearanceSettingsDto {
    AppearanceSettingsDto {
        theme_mode: match settings.theme_mode {
            ThemeMode::System => ThemeModeDto::System,
            ThemeMode::Light => ThemeModeDto::Light,
            ThemeMode::Dark => ThemeModeDto::Dark,
        },
    }
}

fn appearance_settings_from_dto(mode: ThemeModeDto) -> argus_application::AppearanceSettings {
    argus_application::AppearanceSettings::new(match mode {
        ThemeModeDto::System => ThemeMode::System,
        ThemeModeDto::Light => ThemeMode::Light,
        ThemeModeDto::Dark => ThemeMode::Dark,
    })
}

/// Maps one authoritative root projection into its canonical DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn library_root_dto(root: &LibraryRootProjection) -> LibraryRootDto {
    LibraryRootDto {
        library_root_id: root.root_id().to_string(),
        display_name: root.display_name().to_owned(),
        safe_location_presentation: root.safe_location_presentation().to_owned(),
        availability: match root.availability() {
            LibraryRootAvailability::Available => LibraryRootAvailabilityDto::Available,
            LibraryRootAvailability::Unavailable => LibraryRootAvailabilityDto::Unavailable,
            LibraryRootAvailability::Unknown => LibraryRootAvailabilityDto::Unknown,
        },
        last_scan: root.last_scan().map(|summary| LibraryRootLastScanDto {
            scan_run_id: summary.scan_run_id().to_owned(),
            job_run_id: summary.job_run_id().to_owned(),
            status: match summary.status() {
                LibraryRootLastScanStatus::Complete => LibraryRootLastScanStatusDto::Complete,
                LibraryRootLastScanStatus::Partial => LibraryRootLastScanStatusDto::Partial,
                LibraryRootLastScanStatus::Unavailable => LibraryRootLastScanStatusDto::Unavailable,
                LibraryRootLastScanStatus::Cancelled => LibraryRootLastScanStatusDto::Cancelled,
                LibraryRootLastScanStatus::Failed => LibraryRootLastScanStatusDto::Failed,
                LibraryRootLastScanStatus::Abandoned => LibraryRootLastScanStatusDto::Abandoned,
            },
            started_at_ms: summary.started_at_ms(),
            completed_at_ms: summary.completed_at_ms(),
        }),
        active_scan: root.active_scan().map(|summary| LibraryRootActiveScanDto {
            scan_run_id: summary.scan_run_id().to_owned(),
            job_run_id: summary.job_run_id().to_owned(),
            owning_job_root_count: summary.owning_job_root_count(),
        }),
    }
}

/// Maps one authoritative root page into its canonical DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn library_root_page_dto(page: &LibraryRootPage) -> LibraryRootPageDto {
    LibraryRootPageDto {
        items: page.items().iter().map(library_root_dto).collect(),
        offset: page.offset(),
        page_size: page.page_size(),
        total_count: page.total_count(),
    }
}

/// Maps one baseline logical-library page into its safe transport DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn game_page_dto(page: &GameLibraryPage) -> GamePageDto {
    GamePageDto {
        items: page.items().iter().map(game_library_row_dto).collect(),
        next_cursor: page.next_cursor().map(|cursor| cursor.as_str().to_owned()),
    }
}

/// Maps one bounded logical-library row.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn game_library_row_dto(row: &GameLibraryRow) -> GameLibraryRowDto {
    GameLibraryRowDto {
        game_id: row.game_id().to_string(),
        display_title: row.display_title().to_owned(),
        platform_id: platform_id_dto(row.platform_id()),
        hydration_state: hydration_state_dto(row.hydration_state()),
        content_count: row.content_count(),
        source_count: row.source_count(),
        availability_state: game_availability_state_dto(row.availability_state()),
        updated_at_ms: row.updated_at_ms(),
    }
}

/// Maps one focused logical-game detail.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn game_detail_dto(detail: &GameDetail) -> GameDetailDto {
    GameDetailDto {
        game_id: detail.game_id().to_string(),
        platform_id: platform_id_dto(detail.platform_id()),
        lifecycle: game_lifecycle_dto(detail.lifecycle()),
        hydration_state: hydration_state_dto(detail.hydration_state()),
        fallback_title: detail.fallback_title().to_owned(),
        memberships: detail
            .memberships()
            .iter()
            .map(game_membership_summary_dto)
            .collect(),
        content: detail.content().iter().map(content_summary_dto).collect(),
        availability_state: game_availability_state_dto(detail.availability_state()),
        resolved_metadata: detail.resolved_metadata().map(resolved_metadata_dto),
        resolved_artwork: Some(
            detail
                .resolved_artwork()
                .iter()
                .map(resolved_artwork_dto)
                .collect(),
        ),
    }
}

fn operation_handle_dto(handle: &argus_application::OperationHandle) -> OperationHandleDto {
    OperationHandleDto {
        job_run_id: handle.job_run_id().to_string(),
        operation_type: handle.operation_type().to_owned(),
    }
}

fn root_relationship_dto(relationship: RootRelationship) -> RootRelationshipDto {
    match relationship {
        RootRelationship::Same => RootRelationshipDto::Same,
        RootRelationship::Ancestor => RootRelationshipDto::Ancestor,
        RootRelationship::Descendant => RootRelationshipDto::Descendant,
        RootRelationship::Disjoint => RootRelationshipDto::Disjoint,
        RootRelationship::Unknown => RootRelationshipDto::Unknown,
    }
}

fn metadata_settings_dto(settings: MetadataSettings) -> MetadataSettingsDto {
    MetadataSettingsDto {
        preferred_regions: settings.preferred_regions().to_vec(),
        preferred_languages: settings.preferred_languages().to_vec(),
    }
}

fn metadata_settings_from_dto(settings: MetadataSettingsDto) -> MetadataSettings {
    MetadataSettings::new(settings.preferred_regions, settings.preferred_languages)
}

fn metadata_provider_settings_dto(
    settings: MetadataProviderSettings,
) -> MetadataProviderSettingsDto {
    MetadataProviderSettingsDto {
        enabled_providers: settings
            .enabled()
            .iter()
            .map(|provider| provider.as_str().to_owned())
            .collect(),
    }
}

#[allow(clippy::result_large_err)]
fn metadata_provider_settings_from_dto(
    settings: MetadataProviderSettingsDto,
    trace_id: argus_application::TraceId,
) -> Result<MetadataProviderSettings, ApplicationErrorDto> {
    for provider in &settings.enabled_providers {
        if ProviderId::try_from(provider.as_str()).is_err() {
            return Err(validation_failure(trace_id));
        }
    }
    Ok(MetadataProviderSettings::from_enabled(
        settings.enabled_providers,
    ))
}

fn library_provider_setup_decision_from_dto(
    decision: LibraryProviderSetupDecisionDto,
) -> argus_application::LibraryProviderSetupDecision {
    match decision {
        LibraryProviderSetupDecisionDto::Configured => LibraryProviderSetupDecision::Configured,
        LibraryProviderSetupDecisionDto::Skipped => LibraryProviderSetupDecision::Skipped,
    }
}

fn library_onboarding_progress_dto(
    progress: &LibraryOnboardingProgress,
) -> LibraryOnboardingProgressDto {
    LibraryOnboardingProgressDto {
        accepted_privacy_terms_version: progress
            .accepted_privacy_terms_version()
            .map(str::to_owned),
        accepted_privacy_at_ms: progress.accepted_privacy_at_ms(),
        metadata_preferences_confirmed: progress.metadata_preferences_confirmed(),
        provider_setup_outcome: progress.provider_setup_outcome().as_str().to_owned(),
        completed_at_ms: progress.completed_at_ms(),
    }
}

fn privacy_consent_dto(consent: &PrivacyConsent) -> PrivacyConsentDto {
    PrivacyConsentDto {
        accepted_terms_version: consent.accepted_terms_version().map(str::to_owned),
        accepted_at_ms: consent.accepted_at_ms(),
        required_terms_version: consent.required_terms_version().to_owned(),
        satisfies_current_required_terms: consent.satisfies_current_required_terms(),
    }
}

fn library_onboarding_state_dto(state: &LibraryOnboardingState) -> LibraryOnboardingStateDto {
    LibraryOnboardingStateDto {
        progress: library_onboarding_progress_dto(state.progress()),
        required_privacy_terms_version: state.required_privacy_terms_version().to_owned(),
        requires_privacy_acceptance: state.requires_privacy_acceptance(),
        requires_root_selection: state.requires_root_selection(),
        credential_configured: state.credential_configured(),
        complete: state.complete(),
    }
}

fn complete_library_onboarding_and_refresh_dto(
    result: &CompleteLibraryOnboardingAndRefreshResult,
) -> CompleteLibraryOnboardingAndRefreshResultDto {
    match result {
        CompleteLibraryOnboardingAndRefreshResult::OnboardingCompletedAndRefreshAdmitted(
            state,
            handle,
        ) => CompleteLibraryOnboardingAndRefreshResultDto::OnboardingCompletedAndRefreshAdmitted(
            library_onboarding_state_dto(state),
            operation_handle_dto(handle),
        ),
        CompleteLibraryOnboardingAndRefreshResult::OnboardingCompletedButRefreshNotAdmitted(
            state,
            error,
        ) => {
            CompleteLibraryOnboardingAndRefreshResultDto::OnboardingCompletedButRefreshNotAdmitted(
                library_onboarding_state_dto(state),
                application_error_dto(error),
            )
        }
    }
}

fn add_library_root_and_refresh_result_dto(
    result: AddLibraryRootAndRefreshResult,
) -> AddLibraryRootAndRefreshResultDto {
    match result {
        AddLibraryRootAndRefreshResult::AddedAndRefreshAdmitted(root, handle) => {
            AddLibraryRootAndRefreshResultDto::AddedAndRefreshAdmitted(
                library_root_dto(&root),
                operation_handle_dto(&handle),
            )
        }
        AddLibraryRootAndRefreshResult::AddedButRefreshNotAdmitted(root, error) => {
            AddLibraryRootAndRefreshResultDto::AddedButRefreshNotAdmitted(
                library_root_dto(&root),
                application_error_dto(&error),
            )
        }
        AddLibraryRootAndRefreshResult::AlreadyConfigured(root_id) => {
            AddLibraryRootAndRefreshResultDto::AlreadyConfigured(root_id.to_string())
        }
        AddLibraryRootAndRefreshResult::OverlapsExisting(root_id, relationship) => {
            AddLibraryRootAndRefreshResultDto::OverlapsExisting(
                root_id.to_string(),
                root_relationship_dto(relationship),
            )
        }
    }
}

fn metadata_settings_update_result_dto(
    result: MetadataSettingsUpdateResult,
) -> MetadataSettingsUpdateResultDto {
    match result {
        MetadataSettingsUpdateResult::CommittedNoResolutionWork(settings) => {
            MetadataSettingsUpdateResultDto::CommittedNoResolutionWork(metadata_settings_dto(
                settings,
            ))
        }
        MetadataSettingsUpdateResult::CommittedAndResolutionAdmitted(settings, handle) => {
            MetadataSettingsUpdateResultDto::CommittedAndResolutionAdmitted(
                metadata_settings_dto(settings),
                operation_handle_dto(&handle),
            )
        }
        MetadataSettingsUpdateResult::CommittedButResolutionNotAdmitted(settings, error) => {
            MetadataSettingsUpdateResultDto::CommittedButResolutionNotAdmitted(
                metadata_settings_dto(settings),
                application_error_dto(&error),
            )
        }
    }
}

fn metadata_provider_settings_update_result_dto(
    result: MetadataProviderSettingsUpdateResult,
) -> MetadataProviderSettingsUpdateResultDto {
    match result {
        MetadataProviderSettingsUpdateResult::CommittedNoResolutionWork(settings) => {
            MetadataProviderSettingsUpdateResultDto::CommittedNoResolutionWork(
                metadata_provider_settings_dto(settings),
            )
        }
        MetadataProviderSettingsUpdateResult::CommittedAndResolutionAdmitted(settings, handle) => {
            MetadataProviderSettingsUpdateResultDto::CommittedAndResolutionAdmitted(
                metadata_provider_settings_dto(settings),
                operation_handle_dto(&handle),
            )
        }
        MetadataProviderSettingsUpdateResult::CommittedButResolutionNotAdmitted(
            settings,
            error,
        ) => MetadataProviderSettingsUpdateResultDto::CommittedButResolutionNotAdmitted(
            metadata_provider_settings_dto(settings),
            application_error_dto(&error),
        ),
    }
}

fn refresh_mode_from_dto(mode: RefreshModeDto) -> RefreshMode {
    match mode {
        RefreshModeDto::EligibleOnly => RefreshMode::EligibleOnly,
        RefreshModeDto::Force => RefreshMode::Force,
    }
}

fn metadata_provider_readiness_dto(
    readiness: &MetadataProviderReadinessProjection,
) -> MetadataProviderReadinessDto {
    MetadataProviderReadinessDto {
        provider_id: readiness.provider_id().as_str().to_owned(),
        enabled: readiness.enabled(),
        capability_readiness: readiness
            .capability_readiness()
            .iter()
            .map(provider_capability_readiness_dto)
            .collect(),
        credential_configured: readiness.credential_configured(),
    }
}

fn provider_credential_readiness_dto(
    readiness: MetadataProviderReadiness,
) -> ProviderCredentialReadinessDto {
    ProviderCredentialReadinessDto {
        provider_id: readiness.provider_id().as_str().to_owned(),
        state: provider_readiness_state_str(readiness.state()).to_owned(),
        credential_configured: readiness.credential_configured(),
    }
}

fn provider_capability_readiness_dto(
    readiness: &ProviderCapabilityReadiness,
) -> ProviderCapabilityReadinessDto {
    ProviderCapabilityReadinessDto {
        capability: provider_capability_str(readiness.capability()).to_owned(),
        state: provider_readiness_state_str(readiness.state()).to_owned(),
    }
}

fn resolved_metadata_dto(metadata: &ResolvedMetadata) -> ResolvedMetadataDto {
    ResolvedMetadataDto {
        display_title: metadata.display_title().map(str::to_owned),
        sort_title: metadata.sort_title().map(str::to_owned),
        description: metadata.description().map(str::to_owned),
        release_date: metadata.release_date().map(str::to_owned),
        developers: metadata.developers().to_vec(),
        publishers: metadata.publishers().to_vec(),
        genres: metadata.genres().to_vec(),
        presentation_region: metadata.presentation_region().map(str::to_owned),
        presentation_languages: metadata.presentation_languages().to_vec(),
        field_provenance: metadata
            .field_provenance()
            .iter()
            .map(metadata_field_provenance_dto)
            .collect(),
        resolution_revision: metadata.resolution_revision(),
        resolved_at: metadata.resolved_at(),
        provider_id: metadata
            .provider_id()
            .map(|value| value.as_str().to_owned()),
    }
}

fn metadata_field_provenance_dto(
    provenance: &MetadataFieldProvenance,
) -> MetadataFieldProvenanceDto {
    MetadataFieldProvenanceDto {
        field: provenance.field().to_owned(),
        provider_id: provenance
            .provider_id()
            .map(|value| value.as_str().to_owned()),
        external_game_id: provenance.external_game_id().map(str::to_owned),
        source: provenance.source().to_owned(),
    }
}

fn resolved_artwork_dto(artwork: &ResolvedArtwork) -> ResolvedArtworkDto {
    ResolvedArtworkDto {
        artwork_type: artwork.artwork_type().as_str().to_owned(),
        reference_id: artwork.reference_id().to_owned(),
        asset_id: artwork.asset_id().map(|value| value.to_string()),
        ordering: artwork.ordering(),
        selection_reason: artwork.selection_reason().to_owned(),
        resolution_revision: artwork.resolution_revision(),
        resolved_at: artwork.resolved_at(),
    }
}

fn artwork_asset_bytes_dto(bytes: argus_runtime::ArtworkAssetBytes) -> ArtworkAssetBytesDto {
    ArtworkAssetBytesDto {
        asset_id: bytes.asset_id().to_string(),
        bytes: bytes.bytes().to_vec(),
        mime_type: bytes.mime_type().to_owned(),
        width: bytes.width(),
        height: bytes.height(),
    }
}

fn provider_capability_str(capability: ProviderCapability) -> &'static str {
    match capability {
        ProviderCapability::ContentMatching => "content_matching",
        ProviderCapability::MetadataRefresh => "metadata_refresh",
        ProviderCapability::ArtworkDiscovery => "artwork_discovery",
    }
}

fn provider_readiness_state_str(state: ProviderReadinessState) -> &'static str {
    match state {
        ProviderReadinessState::Ready => "ready",
        ProviderReadinessState::Disabled => "disabled",
        ProviderReadinessState::MissingCredentials => "missing_credentials",
        ProviderReadinessState::InvalidCredentials => "invalid_credentials",
        ProviderReadinessState::Misconfigured => "misconfigured",
        ProviderReadinessState::Unavailable => "unavailable",
    }
}

fn content_summary_dto(summary: &GameContentSummary) -> ContentSummaryDto {
    ContentSummaryDto {
        game_content_id: summary.game_content_id().to_string(),
        platform_id: platform_id_dto(summary.platform_id()),
        content_type: content_type_dto(summary.content_type()),
        presence: content_presence_dto(summary.presence()),
        identification: identification_state_dto(summary.identification()),
        source_count: summary.source_count(),
        identity: summary.identity().map(content_identity_summary_dto),
        provenance: summary.provenance().map(content_provenance_summary_dto),
    }
}

fn content_identity_summary_dto(summary: &ContentIdentitySummary) -> ContentIdentitySummaryDto {
    ContentIdentitySummaryDto {
        scheme_id: summary.scheme_id().to_owned(),
        revision: summary.revision(),
        digest: digest_hex(summary.digest()),
    }
}

fn content_provenance_summary_dto(
    summary: &ContentProvenanceSummary,
) -> ContentProvenanceSummaryDto {
    ContentProvenanceSummaryDto {
        source_entry_id: summary.source_entry_id().to_string(),
        association_key: summary.association_key().to_owned(),
        source_fingerprint: summary.source_fingerprint().map(str::to_owned),
        last_observed_scan_id: summary.last_observed_scan_id().to_string(),
    }
}

fn game_membership_summary_dto(summary: &GameMembershipSummary) -> GameMembershipSummaryDto {
    GameMembershipSummaryDto {
        game_content_id: summary.game_content_id().to_string(),
        relationship: membership_relationship_dto(summary.relationship()),
        grouping_basis: grouping_basis_dto(summary.grouping_basis()),
        grouping_revision: summary.grouping_revision(),
    }
}

fn platform_id_dto(platform: PlatformId) -> PlatformIdDto {
    match platform {
        PlatformId::NintendoGb => PlatformIdDto::NintendoGb,
        PlatformId::NintendoGbc => PlatformIdDto::NintendoGbc,
        PlatformId::NintendoGba => PlatformIdDto::NintendoGba,
    }
}

fn content_type_dto(content_type: ContentType) -> ContentTypeDto {
    match content_type {
        ContentType::CartridgeImage => ContentTypeDto::CartridgeImage,
    }
}

fn content_presence_dto(presence: GameContentPresence) -> ContentPresenceDto {
    match presence {
        GameContentPresence::Available => ContentPresenceDto::Available,
        GameContentPresence::PartiallyUnavailable => ContentPresenceDto::PartiallyUnavailable,
        GameContentPresence::Unavailable => ContentPresenceDto::Unavailable,
        GameContentPresence::Orphaned => ContentPresenceDto::Orphaned,
    }
}

fn identification_state_dto(state: IdentificationState) -> IdentificationStateDto {
    match state {
        IdentificationState::Identified => IdentificationStateDto::Identified,
        IdentificationState::NeedsReidentification => IdentificationStateDto::NeedsReidentification,
        IdentificationState::Unidentified => IdentificationStateDto::Unidentified,
    }
}

fn game_lifecycle_dto(lifecycle: GameLifecycle) -> GameLifecycleDto {
    match lifecycle {
        GameLifecycle::Active => GameLifecycleDto::Active,
        GameLifecycle::InactiveOrphan => GameLifecycleDto::InactiveOrphan,
        GameLifecycle::Redirected => GameLifecycleDto::Redirected,
    }
}

fn hydration_state_dto(state: HydrationState) -> HydrationStateDto {
    match state {
        HydrationState::Hydrated => HydrationStateDto::Hydrated,
        HydrationState::PartiallyHydrated => HydrationStateDto::PartiallyHydrated,
        HydrationState::Unmatched => HydrationStateDto::Unmatched,
        HydrationState::Refreshing => HydrationStateDto::Refreshing,
    }
}

fn game_availability_state_dto(state: AvailabilityState) -> GameAvailabilityStateDto {
    match state {
        AvailabilityState::Available => GameAvailabilityStateDto::Available,
        AvailabilityState::PartiallyUnavailable => GameAvailabilityStateDto::PartiallyUnavailable,
        AvailabilityState::Unavailable => GameAvailabilityStateDto::Unavailable,
        AvailabilityState::InactiveOrphan => GameAvailabilityStateDto::InactiveOrphan,
    }
}

fn membership_relationship_dto(relationship: MembershipRelationship) -> MembershipRelationshipDto {
    match relationship {
        MembershipRelationship::Primary => MembershipRelationshipDto::Primary,
        MembershipRelationship::Secondary => MembershipRelationshipDto::Secondary,
    }
}

fn grouping_basis_dto(basis: GroupingBasis) -> GroupingBasisDto {
    match basis {
        GroupingBasis::ExactContentIdentity => GroupingBasisDto::ExactContentIdentity,
        GroupingBasis::Provisional => GroupingBasisDto::Provisional,
    }
}

fn digest_hex(digest: IdentityDigest) -> String {
    digest
        .as_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// Maps one safe source-entry row projection into its canonical DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn source_entry_projection_dto(projection: &SourceEntryProjection) -> SourceEntryDto {
    SourceEntryDto {
        source_entry_id: projection.source_entry_id().to_string(),
        parent_source_entry_id: projection.parent_source_entry_id().map(|id| id.to_string()),
        display_name: projection.display_name().to_owned(),
        display_location: projection.display_location().to_owned(),
        kind: source_entry_kind_dto(projection.kind()),
        classification: source_entry_classification_dto(projection.classification()),
        bounded_status_summary: None,
    }
}

/// Maps one safe source-entry detail projection into its canonical DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn source_entry_detail_projection_dto(
    projection: &SourceEntryDetailProjection,
) -> SourceEntryDetailDto {
    SourceEntryDetailDto {
        source_entry_id: projection.source_entry_id().to_string(),
        parent_source_entry_id: projection.parent_source_entry_id().map(|id| id.to_string()),
        display_name: projection.display_name().to_owned(),
        display_location: projection.display_location().to_owned(),
        kind: source_entry_kind_dto(projection.kind()),
        classification: source_entry_classification_dto(projection.classification()),
        bounded_status_summary: None,
        bounded_observation_status_detail: None,
    }
}

fn source_entry_kind_dto(kind: SourceEntryKind) -> SourceEntryKindDto {
    match kind {
        SourceEntryKind::Directory => SourceEntryKindDto::Directory,
        SourceEntryKind::File => SourceEntryKindDto::File,
        SourceEntryKind::LinkLike => SourceEntryKindDto::LinkLike,
        SourceEntryKind::Unknown => SourceEntryKindDto::Unknown,
    }
}

fn source_entry_classification_dto(
    classification: SourceEntryClassification,
) -> SourceEntryClassificationDto {
    match classification {
        SourceEntryClassification::Container => SourceEntryClassificationDto::Container,
        SourceEntryClassification::ContentCandidate => {
            SourceEntryClassificationDto::ContentCandidate
        }
        SourceEntryClassification::SupportingEntry => SourceEntryClassificationDto::SupportingEntry,
        SourceEntryClassification::Ignored => SourceEntryClassificationDto::Ignored,
        SourceEntryClassification::Unknown => SourceEntryClassificationDto::Unknown,
    }
}

/// Maps one bounded direct-child page into its canonical DTO.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn source_entry_children_page_dto(
    page: &SourceEntryChildrenPage,
) -> SourceEntryChildrenPageDto {
    SourceEntryChildrenPageDto {
        items: page
            .items()
            .iter()
            .map(source_entry_projection_dto)
            .collect(),
        next_cursor: page.next_cursor().map(ToString::to_string),
    }
}

/// Maps one root-only add outcome into its typed transport union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn add_local_library_root_dto(
    result: &AddLocalLibraryRootResult,
) -> AddLocalLibraryRootResultDto {
    match result {
        AddLocalLibraryRootResult::Added(root) => {
            AddLocalLibraryRootResultDto::Added(library_root_dto(root))
        }
        AddLocalLibraryRootResult::AlreadyConfigured(id) => {
            AddLocalLibraryRootResultDto::AlreadyConfigured(id.to_string())
        }
        AddLocalLibraryRootResult::OverlapsExisting(id, relationship) => {
            AddLocalLibraryRootResultDto::OverlapsExisting(
                id.to_string(),
                match relationship {
                    RootRelationship::Same => RootRelationshipDto::Same,
                    RootRelationship::Ancestor => RootRelationshipDto::Ancestor,
                    RootRelationship::Descendant => RootRelationshipDto::Descendant,
                    RootRelationship::Disjoint => RootRelationshipDto::Disjoint,
                    RootRelationship::Unknown => RootRelationshipDto::Unknown,
                },
            )
        }
    }
}

/// Maps one Add & Scan composite outcome into its typed transport union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn add_local_library_root_and_scan_dto(
    result: &AddLocalLibraryRootAndScanResult,
) -> AddLocalLibraryRootAndScanResultDto {
    match result {
        AddLocalLibraryRootAndScanResult::AddedAndScanAdmitted(root, handle) => {
            AddLocalLibraryRootAndScanResultDto::AddedAndScanAdmitted(
                library_root_dto(root),
                OperationHandleDto {
                    job_run_id: handle.job_run_id().to_string(),
                    operation_type: handle.operation_type().to_owned(),
                },
            )
        }
        AddLocalLibraryRootAndScanResult::AddedButScanNotAdmitted(root, issue) => {
            AddLocalLibraryRootAndScanResultDto::AddedButScanNotAdmitted(
                library_root_dto(root),
                match issue {
                    LibraryScanChildAdmissionIssue::AlreadyScanning {
                        library_root_id,
                        active_job_run_id,
                        active_scan_run_id,
                    } => LibraryScanChildAdmissionIssueDto::AlreadyScanning {
                        library_root_id: library_root_id.to_string(),
                        active_job_run_id: active_job_run_id.to_string(),
                        active_scan_run_id: active_scan_run_id.to_string(),
                    },
                    LibraryScanChildAdmissionIssue::AdmissionFailure(error) => {
                        LibraryScanChildAdmissionIssueDto::AdmissionFailure(application_error_dto(
                            error,
                        ))
                    }
                },
            )
        }
        AddLocalLibraryRootAndScanResult::AlreadyConfigured(root_id) => {
            AddLocalLibraryRootAndScanResultDto::AlreadyConfigured(root_id.to_string())
        }
        AddLocalLibraryRootAndScanResult::OverlapsExisting(root_id, relationship) => {
            AddLocalLibraryRootAndScanResultDto::OverlapsExisting(
                root_id.to_string(),
                match relationship {
                    RootRelationship::Same => RootRelationshipDto::Same,
                    RootRelationship::Ancestor => RootRelationshipDto::Ancestor,
                    RootRelationship::Descendant => RootRelationshipDto::Descendant,
                    RootRelationship::Disjoint => RootRelationshipDto::Disjoint,
                    RootRelationship::Unknown => RootRelationshipDto::Unknown,
                },
            )
        }
    }
}

/// Maps one root-removal outcome into its typed transport union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn remove_library_root_dto(result: &RemoveLibraryRootResult) -> RemoveLibraryRootResultDto {
    match result {
        RemoveLibraryRootResult::Removed => RemoveLibraryRootResultDto::Removed,
        RemoveLibraryRootResult::RootHasActiveScan {
            library_root_id,
            job_run_id,
            scan_run_id,
            owning_job_root_count,
        } => RemoveLibraryRootResultDto::RootHasActiveScan {
            library_root_id: library_root_id.to_string(),
            job_run_id: job_run_id.to_string(),
            scan_run_id: scan_run_id.to_string(),
            owning_job_root_count: *owning_job_root_count,
        },
    }
}

/// Parses one bridge-supplied job-run identity with typed validation.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn parse_job_run_id(
    value: &str,
    trace_id: argus_application::TraceId,
) -> Result<JobRunId, ApplicationErrorDto> {
    JobRunId::try_from(value).map_err(|_| {
        application_error_dto(
            &ApplicationError::from_code(
                argus_application::ErrorCode::ValidationInvalidArgument,
                trace_id,
                SafeContext::new(),
            )
            .expect("validation error"),
        )
    })
}

/// Parses the bounded bridge request for live execution-host stops.
#[allow(unexpected_cfgs)]
#[allow(clippy::result_large_err)]
#[flutter_rust_bridge::frb(ignore)]
pub fn parse_execution_host_stop_request(
    request: ReportExecutionHostStopRequestDto,
    trace_id: argus_application::TraceId,
) -> Result<(Vec<JobRunId>, BackgroundOperationStopReason), ApplicationErrorDto> {
    if request.job_run_ids.is_empty()
        || request.job_run_ids.len() > argus_runtime::background::MAX_EXECUTION_HOST_STOP_JOB_RUNS
    {
        return Err(validation_failure(trace_id));
    }
    let job_run_ids = request
        .job_run_ids
        .iter()
        .map(|value| parse_job_run_id(value, trace_id))
        .collect::<Result<Vec<_>, _>>()?;
    let reason = match request.reason {
        ExecutionHostStopReasonDto::Timeout => BackgroundOperationStopReason::ExecutionHostTimeout,
        ExecutionHostStopReasonDto::HostLost => BackgroundOperationStopReason::ExecutionHostLost,
    };
    Ok((job_run_ids, reason))
}

/// Maps one scan admission outcome into its typed transport union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn start_library_scan_result_dto(result: &StartLibraryScanResult) -> StartLibraryScanResultDto {
    match result {
        StartLibraryScanResult::Admitted(handle) => {
            StartLibraryScanResultDto::Admitted(OperationHandleDto {
                job_run_id: handle.job_run_id().to_string(),
                operation_type: handle.operation_type().to_owned(),
            })
        }
        StartLibraryScanResult::AlreadyScanning {
            library_root_id,
            active_job_run_id,
            active_scan_run_id,
        } => StartLibraryScanResultDto::AlreadyScanning {
            library_root_id: library_root_id.to_string(),
            active_job_run_id: active_job_run_id.to_string(),
            active_scan_run_id: active_scan_run_id.to_string(),
        },
    }
}

/// Maps one retry outcome into its typed transport union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn retry_job_result_dto(result: &RetryJobResult) -> RetryJobResultDto {
    match result {
        RetryJobResult::Admitted(handle) => RetryJobResultDto::Admitted(OperationHandleDto {
            job_run_id: handle.job_run_id().to_string(),
            operation_type: handle.operation_type().to_owned(),
        }),
        RetryJobResult::AlreadyRetried(job_run_id) => {
            RetryJobResultDto::AlreadyRetried(job_run_id.to_string())
        }
        RetryJobResult::NotAdmitted(reason) => RetryJobResultDto::NotAdmitted(match reason {
            RetryNotAdmittedReason::SourceRunNotTerminal => {
                RetryNotAdmittedReasonDto::SourceRunNotTerminal
            }
            RetryNotAdmittedReason::OperationNotRetryable => {
                RetryNotAdmittedReasonDto::OperationNotRetryable
            }
            RetryNotAdmittedReason::NoEligibleTargets(exclusions) => {
                RetryNotAdmittedReasonDto::NoEligibleTargets(
                    exclusions.iter().map(exclusion_dto).collect(),
                )
            }
        }),
    }
}

/// Maps one authoritative job-row page into its transport projection.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn job_summary_page_dto(page: &JobSummaryPage) -> JobSummaryPageDto {
    JobSummaryPageDto {
        items: page.items().iter().map(job_summary_dto).collect(),
        total_count: page.total_count(),
        next_offset: page.next_offset(),
    }
}

/// Maps one authoritative job detail into its transport projection.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn job_detail_dto(detail: &JobDetail) -> JobDetailDto {
    JobDetailDto {
        job: job_run_dto(detail.job()),
        operation_detail: match detail.operation_detail() {
            OperationDetail::LibraryScan(scan_detail) => {
                OperationDetailDto::LibraryScan(library_scan_job_detail_dto(scan_detail))
            }
            OperationDetail::LibraryRefresh(refresh_detail) => {
                OperationDetailDto::LibraryRefresh(library_refresh_job_detail_dto(refresh_detail))
            }
            OperationDetail::GameRefresh(refresh_detail) => {
                OperationDetailDto::GameRefresh(game_refresh_job_detail_dto(refresh_detail))
            }
            OperationDetail::LibraryResolutionRefresh(refresh_detail) => {
                OperationDetailDto::LibraryResolutionRefresh(
                    library_resolution_refresh_job_detail_dto(refresh_detail),
                )
            }
        },
    }
}

fn job_summary_dto(summary: &JobSummary) -> JobSummaryDto {
    JobSummaryDto {
        job_run_id: summary.job_run_id().to_string(),
        operation_type: summary.operation_type().to_owned(),
        state: job_state_dto(summary.state()),
        phase: summary.phase().map(str::to_owned),
        created_at_ms: summary.created_at_ms(),
        started_at_ms: summary.started_at_ms(),
        terminal_at_ms: summary.terminal_at_ms(),
        cancellation_requested: summary.cancellation_requested(),
        safe_context_summary: summary.safe_context_summary().map(str::to_owned),
    }
}

fn job_run_dto(job: &JobRunProjection) -> JobRunDto {
    JobRunDto {
        job_run_id: job.job_run_id().to_string(),
        operation_type: job.operation_type().to_owned(),
        state: job_state_dto(job.state()),
        phase: job.phase().map(str::to_owned),
        completed_units: job.completed_units(),
        total_units: job.total_units(),
        status_key: job.status_key().map(str::to_owned),
        created_at_ms: job.created_at_ms(),
        queued_at_ms: job.queued_at_ms(),
        started_at_ms: job.started_at_ms(),
        terminal_at_ms: job.terminal_at_ms(),
        cancellation_requested: job.cancellation_requested(),
        controls: JobControlAvailabilityDto {
            can_cancel: job.controls().can_cancel(),
            can_retry: job.controls().can_retry(),
        },
        bounded_terminal_failure: match (job.terminal_error_code(), job.terminal_safe_context()) {
            (None, None) => None,
            (code, context) => Some(BoundedTerminalFailureDto {
                error_code: code.map(str::to_owned),
                safe_context: context.map(str::to_owned),
            }),
        },
    }
}

fn library_scan_job_detail_dto(detail: &LibraryScanJobDetail) -> LibraryScanJobDetailDto {
    LibraryScanJobDetailDto {
        requested_roots: detail
            .requested_roots()
            .iter()
            .map(root_summary_dto)
            .collect(),
        admitted_roots: detail
            .admitted_roots()
            .iter()
            .map(root_summary_dto)
            .collect(),
        exclusions: detail.exclusions().iter().map(exclusion_dto).collect(),
        scan_runs: detail.scan_runs().iter().map(scan_run_dto).collect(),
        progress: scan_progress_dto(detail.progress()),
        retry_source_job_run_id: detail.retry_source_job_run_id().map(|id| id.to_string()),
        retry_successor_job_run_id: detail.retry_successor_job_run_id().map(|id| id.to_string()),
    }
}

fn refresh_progress_facts_dto(progress: &RefreshProgressFacts) -> RefreshProgressFactsDto {
    RefreshProgressFactsDto {
        phase: progress.phase().map(str::to_owned),
        completed_units: progress.completed_units(),
        total_units: progress.total_units(),
        status_key: progress.status_key().map(str::to_owned),
        issue_count: progress.issue_count(),
    }
}

fn library_refresh_job_detail_dto(detail: &LibraryRefreshJobDetail) -> LibraryRefreshJobDetailDto {
    LibraryRefreshJobDetailDto {
        trigger: detail.trigger().kind().to_owned(),
        trigger_root_id: detail.trigger().root_id().map(|id| id.to_string()),
        mode: detail.mode().as_str().to_owned(),
        requested_root_ids: detail
            .requested_root_ids()
            .iter()
            .map(ToString::to_string)
            .collect(),
        scan_runs: detail.scan_runs().iter().map(scan_run_dto).collect(),
        progress: refresh_progress_facts_dto(detail.progress()),
        retry_source_job_run_id: detail.retry_source_job_run_id().map(|id| id.to_string()),
        retry_successor_job_run_id: detail.retry_successor_job_run_id().map(|id| id.to_string()),
    }
}

fn game_refresh_job_detail_dto(
    detail: &argus_application::GameRefreshJobDetail,
) -> GameRefreshJobDetailDto {
    GameRefreshJobDetailDto {
        game_ids: detail.game_ids().iter().map(ToString::to_string).collect(),
        mode: detail.mode().as_str().to_owned(),
        progress: refresh_progress_facts_dto(detail.progress()),
        retry_source_job_run_id: detail.retry_source_job_run_id().map(|id| id.to_string()),
        retry_successor_job_run_id: detail.retry_successor_job_run_id().map(|id| id.to_string()),
    }
}

fn library_resolution_refresh_job_detail_dto(
    detail: &LibraryResolutionRefreshJobDetail,
) -> LibraryResolutionRefreshJobDetailDto {
    LibraryResolutionRefreshJobDetailDto {
        job_run_id: detail.job_run_id().to_string(),
        settings_revision: detail.settings_revision(),
        progress: refresh_progress_facts_dto(detail.progress()),
        retry_source_job_run_id: detail.retry_source_job_run_id().map(|id| id.to_string()),
        retry_successor_job_run_id: detail.retry_successor_job_run_id().map(|id| id.to_string()),
    }
}

fn root_summary_dto(summary: &LibraryScanRootSummary) -> LibraryScanRootSummaryDto {
    LibraryScanRootSummaryDto {
        library_root_id: summary.library_root_id().to_string(),
        display_name: summary.display_name().to_owned(),
        safe_location_display: summary.safe_location_display().to_owned(),
    }
}

fn exclusion_dto(exclusion: &LibraryScanAdmissionExclusion) -> LibraryScanAdmissionExclusionDto {
    LibraryScanAdmissionExclusionDto {
        library_root_id: exclusion.library_root_id().to_string(),
        reason: exclusion.reason().as_str().to_owned(),
        active_job_run_id: exclusion.active_job_run_id().map(|id| id.to_string()),
        active_scan_run_id: exclusion.active_scan_run_id().map(|id| id.to_string()),
        application_error: exclusion.application_error().map(application_error_dto),
    }
}

/// Maps one multi-root Scan All admission outcome into its typed transport
/// union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn start_library_scan_all_result_dto(
    result: &StartLibraryScanAllResult,
) -> StartLibraryScanAllResultDto {
    match result {
        StartLibraryScanAllResult::Admitted {
            operation_handle,
            admitted_roots,
            exclusions,
        } => StartLibraryScanAllResultDto::Admitted {
            operation_handle: OperationHandleDto {
                job_run_id: operation_handle.job_run_id().to_string(),
                operation_type: operation_handle.operation_type().to_owned(),
            },
            admitted_roots: admitted_roots.iter().map(ToString::to_string).collect(),
            exclusions: exclusions.iter().map(exclusion_dto).collect(),
        },
        StartLibraryScanAllResult::NothingEligible { exclusions } => {
            StartLibraryScanAllResultDto::NothingEligible {
                exclusions: exclusions.iter().map(exclusion_dto).collect(),
            }
        }
    }
}

/// Maps one authoritative Scan All request resolution into its transport
/// union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn library_scan_all_request_resolution_dto(
    resolution: Option<StartLibraryScanAllResult>,
) -> LibraryScanAllRequestResolutionDto {
    match resolution {
        Some(StartLibraryScanAllResult::Admitted {
            operation_handle,
            admitted_roots,
            exclusions,
        }) => LibraryScanAllRequestResolutionDto::Admitted {
            operation_handle: OperationHandleDto {
                job_run_id: operation_handle.job_run_id().to_string(),
                operation_type: operation_handle.operation_type().to_owned(),
            },
            admitted_roots: admitted_roots.iter().map(ToString::to_string).collect(),
            exclusions: exclusions.iter().map(exclusion_dto).collect(),
        },
        Some(StartLibraryScanAllResult::NothingEligible { .. }) | None => {
            LibraryScanAllRequestResolutionDto::NothingAdmitted
        }
    }
}

fn scan_run_dto(scan: &ScanRunProjection) -> ScanRunDto {
    ScanRunDto {
        scan_run_id: scan.scan_run_id().to_string(),
        job_run_id: scan.job_run_id().to_string(),
        library_root_id: scan.library_root_id().to_string(),
        display_name: scan.display_name().to_owned(),
        safe_location_display: scan.safe_location_display().to_owned(),
        status: match scan.status() {
            ScanRunStatus::Running => ScanRunStatusDto::Running,
            ScanRunStatus::Complete => ScanRunStatusDto::Complete,
            ScanRunStatus::Partial => ScanRunStatusDto::Partial,
            ScanRunStatus::Failed => ScanRunStatusDto::Failed,
            ScanRunStatus::Cancelled => ScanRunStatusDto::Cancelled,
            ScanRunStatus::Abandoned => ScanRunStatusDto::Abandoned,
        },
        started_at_ms: scan.started_at_ms(),
        completed_at_ms: scan.completed_at_ms(),
    }
}

fn scan_progress_dto(progress: &ScanProgressFacts) -> ScanProgressFactsDto {
    ScanProgressFactsDto {
        phase: progress.phase().map(str::to_owned),
        completed_units: progress.completed_units(),
        total_units: progress.total_units(),
        status_key: progress.status_key().map(str::to_owned),
        roots_requested: progress.roots_requested(),
        roots_admitted: progress.roots_admitted(),
        roots_terminal: progress.roots_terminal(),
        entries_observed: progress.entries_observed(),
        entries_committed: progress.entries_committed(),
        issue_count: progress.issue_count(),
    }
}

fn job_state_dto(state: JobRunState) -> JobRunStateDto {
    match state {
        JobRunState::Queued => JobRunStateDto::Queued,
        JobRunState::Preparing => JobRunStateDto::Preparing,
        JobRunState::Running => JobRunStateDto::Running,
        JobRunState::Completed => JobRunStateDto::Completed,
        JobRunState::CompletedWithIssues => JobRunStateDto::CompletedWithIssues,
        JobRunState::Failed => JobRunStateDto::Failed,
        JobRunState::Cancelled => JobRunStateDto::Cancelled,
        JobRunState::Interrupted => JobRunStateDto::Interrupted,
        JobRunState::Abandoned => JobRunStateDto::Abandoned,
    }
}

fn source_entries_scope_dto(scope: SourceEntriesChangeScope) -> SourceEntriesChangeScopeDto {
    match scope {
        SourceEntriesChangeScope::RootChildren => SourceEntriesChangeScopeDto::RootChildren,
        SourceEntriesChangeScope::EntryChildren(id) => {
            SourceEntriesChangeScopeDto::EntryChildren(id.to_string())
        }
        SourceEntriesChangeScope::EntireRootHierarchy => {
            SourceEntriesChangeScopeDto::EntireRootHierarchy
        }
    }
}

fn startup_failure_dto(failure: &StartupFailure) -> StartupFailureDto {
    StartupFailureDto {
        phase: startup_phase_dto(failure.phase),
        error: application_error_dto(&failure.error),
        recovery_actions: failure
            .recovery_actions
            .iter()
            .map(|action| RecoveryActionDto {
                kind: recovery_action_kind_dto(action.kind),
            })
            .collect(),
    }
}

fn lifecycle_dto(lifecycle: RuntimeLifecycle) -> RuntimeLifecycleDto {
    match lifecycle {
        RuntimeLifecycle::Uninitialized => RuntimeLifecycleDto::Uninitialized,
        RuntimeLifecycle::Starting => RuntimeLifecycleDto::Starting,
        RuntimeLifecycle::Ready => RuntimeLifecycleDto::Ready,
        RuntimeLifecycle::StartupFailed => RuntimeLifecycleDto::StartupFailed,
        RuntimeLifecycle::ShuttingDown => RuntimeLifecycleDto::ShuttingDown,
        RuntimeLifecycle::Stopped => RuntimeLifecycleDto::Stopped,
    }
}

fn startup_phase_dto(phase: StartupPhase) -> StartupPhaseDto {
    match phase {
        StartupPhase::EnvironmentInitialization => StartupPhaseDto::EnvironmentInitialization,
        StartupPhase::ObservabilityInitialization => StartupPhaseDto::ObservabilityInitialization,
        StartupPhase::ConfigurationInitialization => StartupPhaseDto::ConfigurationInitialization,
        StartupPhase::PersistenceInitialization => StartupPhaseDto::PersistenceInitialization,
        StartupPhase::SettingsInitialization => StartupPhaseDto::SettingsInitialization,
        StartupPhase::CoreServicesInitialization => StartupPhaseDto::CoreServicesInitialization,
        StartupPhase::EventInfrastructureInitialization => {
            StartupPhaseDto::EventInfrastructureInitialization
        }
        StartupPhase::ReadinessValidation => StartupPhaseDto::ReadinessValidation,
    }
}

fn recovery_action_kind_dto(kind: RecoveryActionKind) -> RecoveryActionKindDto {
    match kind {
        RecoveryActionKind::RetryStartup => RecoveryActionKindDto::RetryStartup,
        RecoveryActionKind::ResetAppearanceSettings => {
            RecoveryActionKindDto::ResetAppearanceSettings
        }
        RecoveryActionKind::ExportDiagnostics => RecoveryActionKindDto::ExportDiagnostics,
        RecoveryActionKind::CopyTechnicalDetails => RecoveryActionKindDto::CopyTechnicalDetails,
        RecoveryActionKind::OpenDataDirectory => RecoveryActionKindDto::OpenDataDirectory,
        RecoveryActionKind::Exit => RecoveryActionKindDto::Exit,
    }
}

fn category_name(value: ErrorCategory) -> &'static str {
    match value {
        ErrorCategory::Validation => "validation",
        ErrorCategory::Configuration => "configuration",
        ErrorCategory::Filesystem => "filesystem",
        ErrorCategory::Persistence => "persistence",
        ErrorCategory::Provider => "provider",
        ErrorCategory::Runtime => "runtime",
        ErrorCategory::Operation => "operation",
        ErrorCategory::Internal => "internal",
    }
}

fn severity_name(value: ApplicationSeverity) -> &'static str {
    match value {
        ApplicationSeverity::Info => "Info",
        ApplicationSeverity::Warning => "Warning",
        ApplicationSeverity::Error => "Error",
        ApplicationSeverity::Fatal => "Fatal",
    }
}

fn recoverability_name(value: Recoverability) -> &'static str {
    match value {
        Recoverability::None => "None",
        Recoverability::Retry => "Retry",
        Recoverability::UserAction => "UserAction",
        Recoverability::RestartRequired => "RestartRequired",
        Recoverability::ManualIntervention => "ManualIntervention",
    }
}

fn retry_policy_name(value: RetryPolicy) -> &'static str {
    match value {
        RetryPolicy::Never => "Never",
        RetryPolicy::Immediate => "Immediate",
        RetryPolicy::Backoff => "Backoff",
        RetryPolicy::UserInitiated => "UserInitiated",
    }
}

fn safe_context_entries(context: &SafeContext) -> Vec<SafeContextEntryDto> {
    context
        .iter()
        .map(|(field, value)| SafeContextEntryDto {
            field: safe_context_field_name(*field).to_owned(),
            value: safe_context_value_name(value),
        })
        .collect()
}

fn safe_context_field_name(field: SafeContextField) -> &'static str {
    match field {
        SafeContextField::Stage => "stage",
        SafeContextField::PathClass => "path_class",
        SafeContextField::MigrationCount => "migration_count",
        SafeContextField::SchemaVersion => "schema_version",
        SafeContextField::MigrationOutcome => "migration_outcome",
        SafeContextField::ApplicationVersion => "application_version",
        SafeContextField::BackendVersion => "backend_version",
        SafeContextField::Platform => "platform",
        SafeContextField::Architecture => "architecture",
        SafeContextField::TechnicalClass => "technical_class",
        SafeContextField::FailureRole => "failure_role",
        SafeContextField::SettingsDomain => "settings_domain",
        SafeContextField::PersistedSettingsReason => "persisted_settings_reason",
    }
}

fn safe_context_value_name(value: &SafeContextValue) -> String {
    match value {
        SafeContextValue::Stage(stage) => match stage {
            DiagnosticStage::Environment => "environment".to_owned(),
            DiagnosticStage::Observability => "observability".to_owned(),
            DiagnosticStage::Persistence => "persistence".to_owned(),
        },
        SafeContextValue::PathClass(path_class) => match path_class {
            PathClass::StandardApplicationData => "standard_application_data".to_owned(),
            PathClass::ExplicitOverride => "explicit_override".to_owned(),
        },
        SafeContextValue::MigrationCount(count) => count.to_string(),
        SafeContextValue::SchemaVersion(version) => version.to_string(),
        SafeContextValue::MigrationOutcome(outcome) => match outcome {
            MigrationOutcome::Applied => "applied".to_owned(),
            MigrationOutcome::AlreadyCurrent => "already_current".to_owned(),
        },
        SafeContextValue::ApplicationVersion(version) => version.as_str().to_owned(),
        SafeContextValue::BackendVersion(version) => version.as_str().to_owned(),
        SafeContextValue::Platform(platform) => match platform {
            PlatformClass::Windows => "windows".to_owned(),
            PlatformClass::MacOs => "macos".to_owned(),
            PlatformClass::Unix => "unix".to_owned(),
            PlatformClass::Android => "android".to_owned(),
        },
        SafeContextValue::Architecture(architecture) => match architecture {
            ArchitectureClass::X8664 => "x86_64".to_owned(),
            ArchitectureClass::Aarch64 => "aarch64".to_owned(),
            ArchitectureClass::X86 => "x86".to_owned(),
            ArchitectureClass::Arm => "arm".to_owned(),
            ArchitectureClass::Unknown => "unknown".to_owned(),
        },
        SafeContextValue::TechnicalClass(technical) => match technical {
            TechnicalClass::ConfigurationInvalid => "configuration_invalid".to_owned(),
            TechnicalClass::FilesystemPermissionDenied => "filesystem_permission_denied".to_owned(),
            TechnicalClass::DatabaseOpenFailed => "database_open_failed".to_owned(),
            TechnicalClass::DatabaseLocked => "database_locked".to_owned(),
            TechnicalClass::MigrationFailed => "migration_failed".to_owned(),
            TechnicalClass::IncompatibleSchema => "incompatible_schema".to_owned(),
            TechnicalClass::Internal => "internal".to_owned(),
        },
        SafeContextValue::FailureRole(role) => match role {
            FailureRole::Primary => "primary".to_owned(),
            FailureRole::Secondary => "secondary".to_owned(),
        },
        SafeContextValue::SettingsDomain(domain) => match domain {
            SettingsDomain::Appearance => "appearance".to_owned(),
        },
        SafeContextValue::PersistedSettingsReason(reason) => match reason {
            PersistedSettingsReason::Missing => "missing".to_owned(),
            PersistedSettingsReason::InvalidValue => "invalid_value".to_owned(),
            PersistedSettingsReason::MappingFailed => "mapping_failed".to_owned(),
        },
    }
}
