//! Sole Rust composition and translation boundary for the Flutter bridge.
//!
//! The DTOs in this module are immutable transport projections. They do not
//! read persistence or contain application policy; all authority remains in
//! `argus-runtime` and `argus-application`.

#![allow(unexpected_cfgs)]

use std::fmt;
use std::sync::{Arc, Mutex, OnceLock};

use argus_application::{
    AddLocalLibraryRootResult, ApplicationError, ApplicationSeverity, ArchitectureClass,
    DiagnosticStage, ErrorCategory, ErrorCode, FailureRole, LibraryRootAvailability, LibraryRootId,
    LibraryRootLastScanStatus, LibraryRootPage, LibraryRootProjection, ListLibraryRootsQuery,
    LocalFilesystemRootSelection, MigrationOutcome, PathClass, PersistedSettingsReason,
    PlatformClass, Recoverability, RemoveLibraryRootResult, RetryPolicy, RootRelationship,
    SafeContext, SafeContextField, SafeContextValue, SettingsDomain, TechnicalClass, ThemeMode,
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
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RemoveLibraryRootResultDto {
    Removed,
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
    RuntimeStateChanged { lifecycle: RuntimeLifecycleDto },
    StartupFailed { phase: StartupPhaseDto },
    AppearanceSettingsChanged,
    LibraryRootsChanged,
    LibraryRootChanged { library_root_id: String },
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

/// Maps one root-removal outcome into its typed transport union.
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
pub fn remove_library_root_dto(result: &RemoveLibraryRootResult) -> RemoveLibraryRootResultDto {
    match result {
        RemoveLibraryRootResult::Removed => RemoveLibraryRootResultDto::Removed,
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
