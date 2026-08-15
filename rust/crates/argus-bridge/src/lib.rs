//! Sole Rust composition and translation boundary for the Flutter bridge.
//!
//! The DTOs in this module are immutable transport projections. They do not
//! read persistence or contain application policy; all authority remains in
//! `argus-runtime` and `argus-application`.

#![allow(unexpected_cfgs)]

use std::fmt;
use std::sync::{Arc, Mutex, OnceLock};

use argus_application::{
    AddLocalLibraryRootAndScanResult, AddLocalLibraryRootResult, ApplicationError,
    ApplicationSeverity, ArchitectureClass, DiagnosticStage, ErrorCategory, ErrorCode, FailureRole,
    JobDetail, JobRunId, JobRunProjection, JobRunState, JobSummary, JobSummaryPage,
    LibraryRootAvailability, LibraryRootId, LibraryRootLastScanStatus, LibraryRootPage,
    LibraryRootProjection, LibraryScanAdmissionExclusion, LibraryScanAllRequestIdentity,
    LibraryScanChildAdmissionIssue, LibraryScanJobDetail, LibraryScanRootSummary, ListJobsQuery,
    ListJobsScope, ListLibraryRootsQuery, ListSourceEntryChildrenQuery,
    LocalFilesystemRootSelection, MigrationOutcome, OperationDetail, PathClass,
    PersistedSettingsReason, PlatformClass, Recoverability, RemoveLibraryRootResult,
    RetryJobResult, RetryNotAdmittedReason, RetryPolicy, RootRelationship, SafeContext,
    SafeContextField, SafeContextValue, ScanProgressFacts, ScanRunProjection, ScanRunStatus,
    SettingsDomain, SourceEntriesChangeScope, SourceEntryChildrenPage, SourceEntryClassification,
    SourceEntryCursor, SourceEntryDetailProjection, SourceEntryId, SourceEntryKind,
    SourceEntryProjection, StartLibraryScanAllResult, StartLibraryScanResult, TechnicalClass,
    ThemeMode,
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

/// Untrusted typed local-folder selection supplied by the native picker seam.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemRootSelectionDto {
    pub selected_folder_path: String,
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

/// Closed typed operation-detail union.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum OperationDetailDto {
    LibraryScan(LibraryScanJobDetailDto),
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
            LocalFilesystemRootSelection::new(selection.selected_folder_path),
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
            LocalFilesystemRootSelection::new(selection.selected_folder_path),
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
    loop {
        match subscription.recv() {
            Ok(event) => sink
                .add(runtime_event_dto(&event))
                .map_err(|_| BridgeTransportError::EventStreamClosed)?,
            Err(RuntimeEventStreamError::Closed) => {
                // A closed runtime connection is an expected lifecycle outcome
                // (shutdown or generation replacement), not a transport
                // failure.
                return Ok(());
            }
            Err(RuntimeEventStreamError::Internal) => {
                // Poisoned internal synchronization state is a genuine
                // transport failure, never a normal completion.
                return Err(BridgeTransportError::EventStreamClosed);
            }
        }
    }
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
    use super::classify_subscribe_error;
    use argus_application::{ApplicationError, ErrorCode, SafeContext};

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
