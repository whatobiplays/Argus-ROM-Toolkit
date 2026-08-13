//! Phase 000 runtime lifecycle, startup, recovery, and outward event boundary.
//!
//! `KernelBootstrap` remains the compatibility surface for Slice 002/003
//! callers. `ApplicationHost` is the only production owner that constructs
//! and replaces runtime generations; it delegates persistence construction to
//! that existing kernel rather than opening a second database path.

use std::collections::VecDeque;
use std::fmt;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, Weak};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use argus_application::{
    AppearanceSettingsSubscriber, ApplicationError, ErrorCode, EventSubscriberError,
    OperationContext, OperationName, SubsystemName, TraceId,
};

use crate::{
    FailedRuntimeRecoveryContext, InProcessNotificationSink, KernelBootstrap,
    KernelBootstrapOptions, RecoveryCoordinator, RuntimeNotificationSink, StartupCoordinator,
    StartupPhaseObserver, StartupResult, SystemClock, new_trace_id,
    operations::{OperationClass, OperationGuard, OperationTracker},
    startup::SettingsReadPort,
};

/// Opaque identity for one runtime generation.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct RuntimeInstanceId([u8; 16]);

impl RuntimeInstanceId {
    /// Creates a non-zero runtime identity.
    pub fn new() -> Self {
        static COUNTER: AtomicU64 = AtomicU64::new(1);
        let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
        let mut bytes = [0_u8; 16];
        bytes[..8].copy_from_slice(b"ARGUS-RI");
        bytes[8..].copy_from_slice(&counter.to_be_bytes());
        Self(bytes)
    }

    /// Returns whether the identity is non-zero.
    pub fn is_nonzero(self) -> bool {
        self.0 != [0; 16]
    }

    /// Returns the fixed-width wire representation.
    pub fn as_bytes(self) -> [u8; 16] {
        self.0
    }

    /// Parses the fixed-width canonical lowercase hexadecimal identity.
    pub fn from_hex(value: &str) -> Result<Self, RuntimeInstanceIdError> {
        if value.len() != 32 {
            return Err(RuntimeInstanceIdError::InvalidLength);
        }
        let mut bytes = [0_u8; 16];
        for (index, pair) in value.as_bytes().chunks_exact(2).enumerate() {
            bytes[index] = (hex(pair[0])? << 4) | hex(pair[1])?;
        }
        let id = Self(bytes);
        if !id.is_nonzero() {
            return Err(RuntimeInstanceIdError::Zero);
        }
        Ok(id)
    }
}

impl Default for RuntimeInstanceId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for RuntimeInstanceId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        for byte in self.0 {
            write!(formatter, "{byte:02x}")?;
        }
        Ok(())
    }
}

fn hex(value: u8) -> Result<u8, RuntimeInstanceIdError> {
    match value {
        b'0'..=b'9' => Ok(value - b'0'),
        b'a'..=b'f' => Ok(value - b'a' + 10),
        _ => Err(RuntimeInstanceIdError::InvalidHex),
    }
}

/// Failure while decoding a runtime identity.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RuntimeInstanceIdError {
    InvalidLength,
    InvalidHex,
    Zero,
}

impl fmt::Display for RuntimeInstanceIdError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::InvalidLength => "runtime instance id must contain 32 hexadecimal characters",
            Self::InvalidHex => "runtime instance id contains a non-hexadecimal character",
            Self::Zero => "runtime instance id must be non-zero",
        })
    }
}

impl std::error::Error for RuntimeInstanceIdError {}

/// Authoritative runtime lifecycle vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RuntimeLifecycle {
    Uninitialized,
    Starting,
    Ready,
    StartupFailed,
    ShuttingDown,
    Stopped,
}

impl RuntimeLifecycle {
    /// Returns the stable serialized lifecycle value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Uninitialized => "Uninitialized",
            Self::Starting => "Starting",
            Self::Ready => "Ready",
            Self::StartupFailed => "StartupFailed",
            Self::ShuttingDown => "ShuttingDown",
            Self::Stopped => "Stopped",
        }
    }
}

/// Responsibility-oriented startup phase identity.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StartupPhase {
    EnvironmentInitialization,
    ObservabilityInitialization,
    ConfigurationInitialization,
    PersistenceInitialization,
    SettingsInitialization,
    CoreServicesInitialization,
    EventInfrastructureInitialization,
    ReadinessValidation,
}

/// Outcome for one mandatory startup phase.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StartupPhaseOutcome {
    Succeeded,
    Failed,
}

/// Typed observability record for one startup phase.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StartupPhaseRecord {
    pub phase: StartupPhase,
    pub outcome: StartupPhaseOutcome,
    pub duration_ms: u64,
}

impl StartupPhase {
    /// Returns the fixed mandatory Phase 000 order.
    pub const fn phase_000() -> &'static [Self; 8] {
        &[
            Self::EnvironmentInitialization,
            Self::ObservabilityInitialization,
            Self::ConfigurationInitialization,
            Self::PersistenceInitialization,
            Self::SettingsInitialization,
            Self::CoreServicesInitialization,
            Self::EventInfrastructureInitialization,
            Self::ReadinessValidation,
        ]
    }

    /// Returns the stable serialized phase value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::EnvironmentInitialization => "EnvironmentInitialization",
            Self::ObservabilityInitialization => "ObservabilityInitialization",
            Self::ConfigurationInitialization => "ConfigurationInitialization",
            Self::PersistenceInitialization => "PersistenceInitialization",
            Self::SettingsInitialization => "SettingsInitialization",
            Self::CoreServicesInitialization => "CoreServicesInitialization",
            Self::EventInfrastructureInitialization => "EventInfrastructureInitialization",
            Self::ReadinessValidation => "ReadinessValidation",
        }
    }
}

/// Declarative failed-startup recovery capability.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecoveryActionKind {
    RetryStartup,
    ResetAppearanceSettings,
    ExportDiagnostics,
    CopyTechnicalDetails,
    OpenDataDirectory,
    Exit,
}

/// One generation-bound declarative recovery action.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RecoveryAction {
    pub kind: RecoveryActionKind,
}

/// Authoritative startup failure context.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StartupFailure {
    pub phase: StartupPhase,
    pub error: ApplicationError,
    pub recovery_actions: Vec<RecoveryAction>,
    /// Whether sanitized diagnostic contributors were initialized safely.
    pub diagnostics_available: bool,
    /// Whether a safe known data-directory location exists.
    pub data_directory_available: bool,
}

/// Immutable snapshot of one runtime generation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeState {
    Uninitialized {
        runtime_instance_id: RuntimeInstanceId,
    },
    Starting {
        runtime_instance_id: RuntimeInstanceId,
        phase: Option<StartupPhase>,
    },
    Ready {
        runtime_instance_id: RuntimeInstanceId,
    },
    StartupFailed {
        runtime_instance_id: RuntimeInstanceId,
        failure: StartupFailure,
    },
    ShuttingDown {
        runtime_instance_id: RuntimeInstanceId,
    },
    Stopped {
        runtime_instance_id: RuntimeInstanceId,
    },
}

impl RuntimeState {
    /// Returns the lifecycle discriminator.
    pub const fn lifecycle(&self) -> RuntimeLifecycle {
        match self {
            Self::Uninitialized { .. } => RuntimeLifecycle::Uninitialized,
            Self::Starting { .. } => RuntimeLifecycle::Starting,
            Self::Ready { .. } => RuntimeLifecycle::Ready,
            Self::StartupFailed { .. } => RuntimeLifecycle::StartupFailed,
            Self::ShuttingDown { .. } => RuntimeLifecycle::ShuttingDown,
            Self::Stopped { .. } => RuntimeLifecycle::Stopped,
        }
    }

    /// Returns the generation identity.
    pub const fn runtime_instance_id(&self) -> RuntimeInstanceId {
        match self {
            Self::Uninitialized {
                runtime_instance_id,
            }
            | Self::Starting {
                runtime_instance_id,
                ..
            }
            | Self::Ready {
                runtime_instance_id,
            }
            | Self::StartupFailed {
                runtime_instance_id,
                ..
            }
            | Self::ShuttingDown {
                runtime_instance_id,
            }
            | Self::Stopped {
                runtime_instance_id,
            } => *runtime_instance_id,
        }
    }

    /// Returns the currently attributed startup phase, if any.
    pub const fn startup_phase(&self) -> Option<StartupPhase> {
        match self {
            Self::Starting { phase, .. } => *phase,
            Self::StartupFailed { failure, .. } => Some(failure.phase),
            _ => None,
        }
    }

    /// Returns failed-startup context, if this is a failed snapshot.
    pub const fn startup_failure(&self) -> Option<&StartupFailure> {
        match self {
            Self::StartupFailed { failure, .. } => Some(failure),
            _ => None,
        }
    }
}

/// Typed outward event payloads active in Phase 000.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeEventPayload {
    RuntimeStateChanged { lifecycle: RuntimeLifecycle },
    StartupFailed { phase: StartupPhase },
    AppearanceSettingsChanged,
}

/// Generation and sequence metadata surrounding one notification.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RuntimeEvent {
    pub runtime_instance_id: RuntimeInstanceId,
    pub sequence: u64,
    pub occurred_at_ms: u64,
    pub payload: RuntimeEventPayload,
}

struct EventStreamState {
    queue: Mutex<VecDeque<RuntimeEvent>>,
    closed: Mutex<bool>,
    wake: Condvar,
}

impl EventStreamState {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            queue: Mutex::new(VecDeque::new()),
            closed: Mutex::new(false),
            wake: Condvar::new(),
        })
    }

    pub(crate) fn close(&self) {
        if let Ok(mut closed) = self.closed.lock() {
            *closed = true;
            self.wake.notify_all();
        }
    }
}

/// One logical native event connection. Reconnecting replaces the previous
/// connection for the same generation and closes its receiver.
pub struct RuntimeEventSubscription {
    state: Arc<EventStreamState>,
    host: Weak<HostInner>,
    connection_id: u64,
}

impl RuntimeEventSubscription {
    /// Waits for the next event or returns an error when the connection closes.
    pub fn recv(&self) -> Result<RuntimeEvent, RuntimeEventStreamError> {
        let mut queue = self
            .state
            .queue
            .lock()
            .map_err(|_| RuntimeEventStreamError::Closed)?;
        loop {
            if let Some(event) = queue.pop_front() {
                return Ok(event);
            }
            let closed = *self
                .state
                .closed
                .lock()
                .map_err(|_| RuntimeEventStreamError::Closed)?;
            if closed {
                return Err(RuntimeEventStreamError::Closed);
            }
            queue = self
                .state
                .wake
                .wait(queue)
                .map_err(|_| RuntimeEventStreamError::Closed)?;
        }
    }

    /// Attempts to retrieve an event without blocking.
    pub fn try_recv(&self) -> Result<Option<RuntimeEvent>, RuntimeEventStreamError> {
        let mut queue = self
            .state
            .queue
            .lock()
            .map_err(|_| RuntimeEventStreamError::Closed)?;
        if let Some(event) = queue.pop_front() {
            return Ok(Some(event));
        }
        if *self
            .state
            .closed
            .lock()
            .map_err(|_| RuntimeEventStreamError::Closed)?
        {
            return Err(RuntimeEventStreamError::Closed);
        }
        Ok(None)
    }
}

impl Drop for RuntimeEventSubscription {
    fn drop(&mut self) {
        if let Some(host) = self.host.upgrade()
            && let Ok(mut active) = host.active_event.lock()
            && active
                .as_ref()
                .is_some_and(|connection| connection.connection_id == self.connection_id)
        {
            active.take();
            self.state.close();
        }
    }
}

/// Failure returned after a native event connection is no longer usable.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RuntimeEventStreamError {
    Closed,
}

pub struct EventBoundary {
    next_sequence: AtomicU64,
    active: Mutex<Option<Arc<EventStreamState>>>,
    closed: AtomicBool,
}

impl EventBoundary {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(Self {
            next_sequence: AtomicU64::new(0),
            active: Mutex::new(None),
            closed: AtomicBool::new(false),
        })
    }

    fn attach(&self) -> Arc<EventStreamState> {
        let state = EventStreamState::new();
        if let Ok(mut active) = self.active.lock()
            && let Some(previous) = active.replace(Arc::clone(&state))
        {
            previous.close();
        }
        state
    }

    pub(crate) fn emit(
        &self,
        runtime_instance_id: RuntimeInstanceId,
        payload: RuntimeEventPayload,
    ) {
        let sequence = self.next_sequence.fetch_add(1, Ordering::SeqCst) + 1;
        let event = RuntimeEvent {
            runtime_instance_id,
            sequence,
            occurred_at_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_millis() as u64)
                .unwrap_or_default(),
            payload,
        };
        if let Ok(active) = self.active.lock()
            && let Some(state) = active.as_ref()
            && let Ok(mut queue) = state.queue.lock()
        {
            if queue.len() == 64 {
                queue.pop_front();
            }
            queue.push_back(event);
            state.wake.notify_one();
        }
    }

    pub(crate) fn close(&self) {
        self.closed.store(true, Ordering::SeqCst);
        if let Ok(mut active) = self.active.lock()
            && let Some(state) = active.take()
        {
            state.close();
        }
    }

    /// Returns whether this boundary can still deliver notifications.
    pub fn is_open(&self) -> bool {
        !self.closed.load(Ordering::SeqCst)
    }
}

pub(crate) struct RuntimeEventSubscriber {
    pub(crate) outward: Option<Arc<dyn RuntimeNotificationSink>>,
}

/// Publishes startup phase transitions into the owning runtime state.
struct StartupPhasePublisher<'a> {
    host: &'a ApplicationHost,
    generation_id: RuntimeInstanceId,
}

impl StartupPhaseObserver for StartupPhasePublisher<'_> {
    fn phase_started(&self, phase: StartupPhase) {
        if let Ok(mut generation) = self.host.lock_generation()
            && generation.state.lifecycle() == RuntimeLifecycle::Starting
            && generation.id == self.generation_id
        {
            generation.state = RuntimeState::Starting {
                runtime_instance_id: generation.id,
                phase: Some(phase),
            };
        }
    }
}

/// Marks startup activity and clears it on drop.
struct StartupActivityGuard<'a> {
    host: &'a ApplicationHost,
}

impl Drop for StartupActivityGuard<'_> {
    fn drop(&mut self) {
        if let Ok(mut active) = self.host.inner.startup_active.lock() {
            *active = false;
            self.host.inner.startup_condvar.notify_all();
        }
    }
}

impl AppearanceSettingsSubscriber for RuntimeEventSubscriber {
    fn appearance_settings_changed(
        &self,
        _event: argus_application::AppearanceSettingsChanged,
    ) -> Result<(), EventSubscriberError> {
        if let Some(sink) = &self.outward
            && sink
                .publish(RuntimeEventPayload::AppearanceSettingsChanged)
                .is_err()
        {
            return Err(EventSubscriberError::Failed);
        }
        Ok(())
    }
}

/// One concrete runtime generation owned by `ApplicationHost`.
pub struct ApplicationRuntime {
    pub(crate) id: RuntimeInstanceId,
    pub(crate) state: RuntimeState,
    kernel: Option<Arc<Mutex<Option<KernelBootstrap>>>>,
    pub(crate) events: Arc<EventBoundary>,
    operations: Arc<Mutex<OperationTracker>>,
    pub(crate) recovery_context: Option<Arc<FailedRuntimeRecoveryContext>>,
}

impl ApplicationRuntime {
    fn new() -> Self {
        let id = RuntimeInstanceId::new();
        Self {
            id,
            state: RuntimeState::Uninitialized {
                runtime_instance_id: id,
            },
            kernel: None,
            events: EventBoundary::new(),
            operations: Arc::new(Mutex::new(OperationTracker::new())),
            recovery_context: None,
        }
    }

    /// Returns this generation's opaque identity.
    pub fn runtime_instance_id(&self) -> RuntimeInstanceId {
        self.id
    }

    /// Returns the authoritative lifecycle snapshot owned by this runtime.
    pub fn state(&self) -> &RuntimeState {
        &self.state
    }

    /// Returns the lifecycle discriminator without exposing implementation
    /// details of persistence or event delivery.
    pub fn lifecycle(&self) -> RuntimeLifecycle {
        self.state.lifecycle()
    }

    /// Returns a shared handle to the generation kernel, if present.
    fn kernel_handle(&self) -> Option<Arc<Mutex<Option<KernelBootstrap>>>> {
        self.kernel.clone()
    }

    /// Removes the kernel from shared storage for consumption.
    pub(crate) fn take_kernel(&mut self) -> Option<KernelBootstrap> {
        self.kernel
            .as_ref()
            .and_then(|handle| handle.lock().ok())
            .and_then(|mut guard| guard.take())
    }

    /// Takes the kernel only when its lock is immediately available.
    pub(crate) fn try_take_kernel(&self) -> Option<KernelBootstrap> {
        self.kernel
            .as_ref()
            .and_then(|handle| handle.try_lock().ok().and_then(|mut guard| guard.take()))
    }

    /// Evaluates the single centralized admission gate for one operation.
    pub fn admit_operation(
        &self,
        class: OperationClass,
        subsystem: &'static str,
        operation: &'static str,
    ) -> Result<(OperationContext, OperationGuard), ApplicationError> {
        let context = OperationContext::new(
            new_trace_id(),
            SubsystemName::try_from(subsystem).expect("static subsystem is valid"),
            OperationName::try_from(operation).expect("static operation is valid"),
        );
        let guard = self.admit_operation_with_context(&context, class)?;
        Ok((context, guard))
    }

    /// Admits one operation under an already-created top-level context.
    pub fn admit_operation_with_context(
        &self,
        context: &OperationContext,
        class: OperationClass,
    ) -> Result<OperationGuard, ApplicationError> {
        let mut tracker = self.operations.lock().map_err(|_| {
            runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
        })?;
        if tracker.is_cancellation_requested() {
            return Err(crate::operations::cancelled_error_with_trace(
                context.trace_id(),
            ));
        }
        match self.state.lifecycle() {
            RuntimeLifecycle::Ready => {}
            RuntimeLifecycle::Uninitialized | RuntimeLifecycle::Starting => {
                return Err(runtime_error_with_trace(
                    ErrorCode::RuntimeNotReady,
                    context.trace_id(),
                ));
            }
            RuntimeLifecycle::StartupFailed => {
                return Err(runtime_error_with_trace(
                    ErrorCode::RuntimeStartupFailed,
                    context.trace_id(),
                ));
            }
            RuntimeLifecycle::ShuttingDown => {
                return Err(runtime_error_with_trace(
                    ErrorCode::RuntimeShuttingDown,
                    context.trace_id(),
                ));
            }
            RuntimeLifecycle::Stopped => {
                return Err(runtime_error_with_trace(
                    ErrorCode::RuntimeStopped,
                    context.trace_id(),
                ));
            }
        }
        let _ = class;
        let Some(token) = tracker.admit() else {
            return Err(crate::operations::cancelled_error_with_trace(
                context.trace_id(),
            ));
        };
        Ok(OperationGuard::new(token, Arc::clone(&self.operations)))
    }
}

struct ActiveEventConnection {
    connection_id: u64,
    state: Arc<EventStreamState>,
}

/// Terminal result of a user-selected diagnostics export.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticsExportOutcome {
    Created,
    Partial,
}

/// Safe summary returned after diagnostics have been written locally.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DiagnosticsExport {
    pub outcome: DiagnosticsExportOutcome,
    pub destination_classification: &'static str,
}

/// Copy-safe technical details for a failed startup generation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TechnicalDetails {
    pub text: String,
}

pub(crate) struct HostInner {
    options: KernelBootstrapOptions,
    notification_sink: Arc<dyn RuntimeNotificationSink>,
    _recovery_coordinator: RecoveryCoordinator,
    current: Mutex<ApplicationRuntime>,
    startup_history: Mutex<Vec<StartupPhaseRecord>>,
    active_event: Mutex<Option<ActiveEventConnection>>,
    next_connection_id: AtomicU64,
    shutdown_incomplete: AtomicBool,
    top_level_operations: Arc<Mutex<OperationTracker>>,
    startup_active: Mutex<bool>,
    startup_condvar: Condvar,
}

/// Application-lifetime owner of one current runtime generation.
#[derive(Clone)]
pub struct ApplicationHost {
    inner: Arc<HostInner>,
}

impl ApplicationHost {
    /// Installs a fresh generation under an existing recovery request trace.
    pub(crate) fn install_fresh_generation_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        self.replace_with_new_generation_with_context(expected_runtime_instance_id, context)?;
        self.initialize()
    }

    /// Creates an uninitialized host with the supplied embedding options.
    pub fn new(options: KernelBootstrapOptions) -> Self {
        Self::with_notification_sink(options, Arc::new(InProcessNotificationSink::new()))
    }

    /// Creates a host with an explicit outward notification sink.
    pub fn with_notification_sink(
        options: KernelBootstrapOptions,
        notification_sink: Arc<dyn RuntimeNotificationSink>,
    ) -> Self {
        Self {
            inner: Arc::new(HostInner {
                options,
                notification_sink,
                _recovery_coordinator: RecoveryCoordinator,
                current: Mutex::new(ApplicationRuntime::new()),
                startup_history: Mutex::new(Vec::new()),
                active_event: Mutex::new(None),
                next_connection_id: AtomicU64::new(1),
                shutdown_incomplete: AtomicBool::new(false),
                top_level_operations: Arc::new(Mutex::new(OperationTracker::new())),
                startup_active: Mutex::new(false),
                startup_condvar: Condvar::new(),
            }),
        }
    }

    /// Returns whether the last bounded shutdown drain timed out.
    pub fn shutdown_was_incomplete(&self) -> bool {
        self.inner.shutdown_incomplete.load(Ordering::SeqCst)
    }

    /// Test-only startup activity accessor.
    #[cfg(test)]
    pub(crate) fn startup_active_for_tests(&self) -> bool {
        *self
            .inner
            .startup_active
            .lock()
            .expect("startup activity lock")
    }

    /// Test-only poison seam for the top-level operation tracker.
    #[cfg(test)]
    pub(crate) fn poison_top_level_tracker_for_tests(&self) {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _guard = self
                .inner
                .top_level_operations
                .lock()
                .expect("tracker lock");
            panic!("poison for shutdown trace test");
        }));
    }

    /// Test-only failed generation whose retained kernel fails shutdown.
    #[cfg(test)]
    pub(crate) fn install_failing_shutdown_generation_for_tests(&self) -> RuntimeInstanceId {
        let directory = Box::leak(Box::new(tempfile::tempdir().expect("tempdir")));
        let kernel = crate::KernelBootstrap::failing_shutdown_kernel_for_tests(directory.path());
        let mut generation = self.lock_generation().expect("generation");
        generation.kernel = Some(Arc::new(Mutex::new(Some(kernel))));
        let id = generation.id;
        generation.state = RuntimeState::StartupFailed {
            runtime_instance_id: id,
            failure: StartupFailure {
                phase: StartupPhase::SettingsInitialization,
                error: ApplicationError::from_code(
                    ErrorCode::ConfigurationPersistedSettingsInvalid,
                    new_trace_id(),
                    argus_application::SafeContext::new(),
                )
                .expect("error"),
                recovery_actions: vec![
                    RecoveryAction {
                        kind: RecoveryActionKind::RetryStartup,
                    },
                    RecoveryAction {
                        kind: RecoveryActionKind::Exit,
                    },
                ],
                diagnostics_available: true,
                data_directory_available: true,
            },
        };
        id
    }

    /// Begins one top-level request/response bridge operation.
    pub fn begin_operation(
        &self,
        subsystem: &'static str,
        operation: &'static str,
    ) -> Result<(OperationContext, OperationGuard), ApplicationError> {
        let mut tracker = self
            .inner
            .top_level_operations
            .lock()
            .map_err(|_| runtime_error(ErrorCode::InternalUnexpected))?;
        if tracker.is_cancellation_requested() {
            return Err(crate::operations::cancelled_error());
        }
        let Some(token) = tracker.admit() else {
            return Err(crate::operations::cancelled_error());
        };
        let context = OperationContext::new(
            new_trace_id(),
            SubsystemName::try_from(subsystem).expect("static subsystem is valid"),
            OperationName::try_from(operation).expect("static operation is valid"),
        );
        Ok((
            context,
            OperationGuard::new(token, Arc::clone(&self.inner.top_level_operations)),
        ))
    }

    /// Publishes one outward runtime payload through the injected sink route.
    pub(crate) fn publish_outward(&self, payload: RuntimeEventPayload) {
        let _ = self.inner.notification_sink.publish(payload);
    }

    /// Starts the current generation. A reported startup failure is returned
    /// as an inspectable `StartupFailed` snapshot, not as a transport error.
    pub fn initialize(&self) -> Result<RuntimeState, ApplicationError> {
        let generation_id = {
            let generation = self.lock_generation()?;
            generation.id
        };
        self.initialize_inner(
            &StartupPhasePublisher {
                host: self,
                generation_id,
            },
            None,
        )
    }

    fn initialize_inner(
        &self,
        observer: &dyn StartupPhaseObserver,
        settings_read: Option<Box<dyn SettingsReadPort>>,
    ) -> Result<RuntimeState, ApplicationError> {
        let (generation_id, boundary) = {
            let mut generation = self.lock_generation()?;
            if generation.state.lifecycle() != RuntimeLifecycle::Uninitialized {
                return Ok(generation.state.clone());
            }
            {
                let mut active = self
                    .inner
                    .startup_active
                    .lock()
                    .map_err(|_| runtime_error(ErrorCode::InternalUnexpected))?;
                *active = true;
            }
            generation.state = RuntimeState::Starting {
                runtime_instance_id: generation.id,
                phase: Some(StartupPhase::EnvironmentInitialization),
            };
            (generation.id, Arc::clone(&generation.events))
        };
        let _activity = StartupActivityGuard { host: self };
        let should_cancel = || {
            self.lock_generation()
                .map(|generation| {
                    generation.state.lifecycle() != RuntimeLifecycle::Starting
                        || generation.id != generation_id
                })
                .unwrap_or(true)
        };
        let result = StartupCoordinator::run(
            self.inner.options.clone(),
            generation_id,
            boundary,
            &SystemClock,
            observer,
            &should_cancel,
            settings_read,
            Some(Arc::clone(&self.inner.notification_sink)),
        );
        self.apply_startup_result(result)
    }

    /// Test-only entry point with an injectable phase observer.
    #[cfg(test)]
    pub(crate) fn initialize_for_tests(
        &self,
        observer: &dyn StartupPhaseObserver,
    ) -> Result<RuntimeState, ApplicationError> {
        self.initialize_inner(observer, None)
    }

    /// Test-only startup with an injectable settings-read port.
    #[cfg(test)]
    pub(crate) fn initialize_with_settings_read_for_tests(
        &self,
        settings_read: Box<dyn SettingsReadPort>,
    ) -> Result<RuntimeState, ApplicationError> {
        self.initialize_inner(
            &StartupPhasePublisher {
                host: self,
                generation_id: self.current_state().runtime_instance_id(),
            },
            Some(settings_read),
        )
    }

    /// Returns the authoritative current snapshot.
    pub fn current_state(&self) -> RuntimeState {
        self.inner
            .current
            .lock()
            .expect("runtime generation lock")
            .state
            .clone()
    }

    /// Returns the authoritative current snapshot without panicking on poison.
    pub fn try_current_state(&self) -> Result<RuntimeState, ApplicationError> {
        Ok(self.lock_generation()?.state.clone())
    }

    /// Returns the current snapshot under an existing top-level context.
    pub fn try_current_state_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        Ok(self.lock_generation_with_context(context)?.state.clone())
    }

    /// Returns the fixed startup phase order.
    pub fn startup_phases(&self) -> &'static [StartupPhase; 8] {
        StartupPhase::phase_000()
    }

    /// Returns the most recent sequential phase outcome records.
    pub fn startup_phase_history(&self) -> Vec<StartupPhaseRecord> {
        self.inner
            .startup_history
            .lock()
            .expect("startup history lock")
            .clone()
    }

    /// Retries a failed generation by constructing a fresh generation.
    pub fn retry_startup(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
    ) -> Result<RuntimeState, ApplicationError> {
        let (context, _guard) = self.begin_operation("runtime", "retry_startup")?;
        self.retry_startup_with_context(expected_runtime_instance_id, &context)
    }

    /// Retries startup under an existing top-level recovery context.
    pub fn retry_startup_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        RecoveryCoordinator::retry_startup(self, expected_runtime_instance_id, context)
    }

    /// Resets only appearance settings, then starts a fresh generation.
    pub fn reset_appearance_settings(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
    ) -> Result<RuntimeState, ApplicationError> {
        let (context, _guard) = self.begin_operation("runtime", "reset_appearance_settings")?;
        self.reset_appearance_settings_with_context(expected_runtime_instance_id, &context)
    }

    /// Resets appearance settings under an existing recovery context.
    pub fn reset_appearance_settings_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        RecoveryCoordinator::reset_appearance_settings(self, expected_runtime_instance_id, context)
    }

    /// Exits a failed generation without starting a replacement.
    pub fn exit_failed_runtime(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
    ) -> Result<RuntimeState, ApplicationError> {
        let (context, _guard) = self.begin_operation("runtime", "exit_failed_runtime")?;
        self.exit_failed_runtime_with_context(expected_runtime_instance_id, &context)
    }

    /// Exits a failed runtime under an existing recovery context.
    pub fn exit_failed_runtime_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<RuntimeState, ApplicationError> {
        RecoveryCoordinator::exit_failed_runtime(self, expected_runtime_instance_id, context)
    }

    /// Shuts down the current generation and closes normal admission.
    pub fn general_shutdown(&self) -> Result<(), ApplicationError> {
        let (context, guard) = self.begin_operation("runtime", "general_shutdown")?;
        self.general_shutdown_with_context(&context, &guard)
    }

    /// Shuts down with an explicit bounded drain deadline.
    #[cfg(test)]
    pub(crate) fn general_shutdown_bounded(
        &self,
        drain_deadline: Duration,
        excluded: Option<&crate::operations::CancellationToken>,
    ) -> Result<(), ApplicationError> {
        let context = OperationContext::new(
            new_trace_id(),
            SubsystemName::try_from("runtime").expect("static subsystem is valid"),
            OperationName::try_from("shutdown").expect("static operation is valid"),
        );
        self.general_shutdown_bounded_with_context(drain_deadline, excluded, &context)
    }

    /// Bounded shutdown carrying a concrete shutdown request trace.
    fn general_shutdown_bounded_with_context(
        &self,
        drain_deadline: Duration,
        excluded: Option<&crate::operations::CancellationToken>,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let tracker = {
            let mut generation = self.lock_generation_with_context(context)?;
            match generation.state.lifecycle() {
                RuntimeLifecycle::Stopped => return Ok(()),
                RuntimeLifecycle::ShuttingDown => return Ok(()),
                _ => {}
            }
            generation.state = RuntimeState::ShuttingDown {
                runtime_instance_id: generation.id,
            };
            self.publish_outward(RuntimeEventPayload::RuntimeStateChanged {
                lifecycle: RuntimeLifecycle::ShuttingDown,
            });
            generation
                .operations
                .lock()
                .map_err(|_| {
                    runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
                })?
                .request_cancellation();
            Arc::clone(&generation.operations)
        };
        {
            let mut top_level = self.inner.top_level_operations.lock().map_err(|_| {
                runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
            })?;
            top_level.request_cancellation();
        }
        let deadline = Instant::now() + drain_deadline;
        let drained = crate::operations::wait_until_empty_until(&tracker, deadline);
        let top_level_drained = crate::operations::wait_until_empty_excluding(
            &self.inner.top_level_operations,
            deadline,
            excluded,
        );
        if !drained || !top_level_drained {
            self.inner.shutdown_incomplete.store(true, Ordering::SeqCst);
        }
        {
            let mut active = self.inner.startup_active.lock().map_err(|_| {
                runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
            })?;
            while *active {
                let now = Instant::now();
                if now >= deadline {
                    break;
                }
                let (guard, wait_result) = self
                    .inner
                    .startup_condvar
                    .wait_timeout(active, deadline.saturating_duration_since(now))
                    .map_err(|_| {
                        runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
                    })?;
                active = guard;
                if wait_result.timed_out() {
                    break;
                }
            }
            if *active {
                self.inner.shutdown_incomplete.store(true, Ordering::SeqCst);
            }
        }
        let kernel = {
            let generation = self.lock_generation_with_context(context)?;
            if generation.kernel_handle().is_some() {
                match generation.try_take_kernel() {
                    Some(kernel) => Some(kernel),
                    None => {
                        self.inner.shutdown_incomplete.store(true, Ordering::SeqCst);
                        None
                    }
                }
            } else {
                None
            }
        };
        if let Some(kernel) = kernel
            && kernel.shutdown().is_err()
        {
            self.inner.shutdown_incomplete.store(true, Ordering::SeqCst);
        }
        let mut generation = self.lock_generation_with_context(context)?;
        generation.state = RuntimeState::Stopped {
            runtime_instance_id: generation.id,
        };
        self.publish_outward(RuntimeEventPayload::RuntimeStateChanged {
            lifecycle: RuntimeLifecycle::Stopped,
        });
        generation.events.close();
        self.clear_active_event();
        Ok(())
    }

    /// Shuts down under an existing top-level context, excluding its own token.
    pub fn general_shutdown_with_context(
        &self,
        context: &OperationContext,
        guard: &OperationGuard,
    ) -> Result<(), ApplicationError> {
        self.general_shutdown_bounded_with_context(
            Duration::from_secs(5),
            Some(guard.token()),
            context,
        )
    }

    /// Exports sanitized startup diagnostics as a ZIP archive selected by the
    /// embedding layer. Raw paths, SQL, and unbounded logs never cross this
    /// API; the archive contains only classified, bounded text.
    pub fn export_startup_diagnostics(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        destination: &Path,
    ) -> Result<DiagnosticsExport, ApplicationError> {
        let (context, _guard) = self.begin_operation("runtime", "export_startup_diagnostics")?;
        self.export_startup_diagnostics_with_context(
            expected_runtime_instance_id,
            destination,
            &context,
        )
    }

    /// Exports diagnostics under an existing top-level context.
    pub fn export_startup_diagnostics_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        destination: &Path,
        context: &OperationContext,
    ) -> Result<DiagnosticsExport, ApplicationError> {
        let (recovery_context, generation_id) = {
            let generation = self.lock_generation_with_context(context)?;
            self.validate_failed_generation_with_context(
                &generation,
                expected_runtime_instance_id,
                context,
            )?;
            let failure = generation.state.startup_failure().ok_or_else(|| {
                runtime_error_with_trace(ErrorCode::RuntimeStartupFailed, context.trace_id())
            })?;
            if !failure
                .recovery_actions
                .iter()
                .any(|action| action.kind == RecoveryActionKind::ExportDiagnostics)
            {
                return Err(runtime_error_with_trace(
                    ErrorCode::RuntimeStartupFailed,
                    context.trace_id(),
                ));
            }
            (generation.recovery_context.clone(), generation.id)
        };
        let Some(recovery_context) = recovery_context else {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        };
        let Some(diagnostics) = recovery_context.diagnostics.as_ref() else {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        };
        crate::diagnostics::export_with_contributors(
            diagnostics,
            generation_id,
            destination,
            context.trace_id(),
            Vec::new(),
        )
    }

    /// Returns safe, copyable startup details without revealing local paths.
    pub fn startup_technical_details(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
    ) -> Result<TechnicalDetails, ApplicationError> {
        let (context, _guard) = self.begin_operation("runtime", "startup_technical_details")?;
        self.startup_technical_details_with_context(expected_runtime_instance_id, &context)
    }

    /// Returns technical details under an existing top-level context.
    pub fn startup_technical_details_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<TechnicalDetails, ApplicationError> {
        let recovery_context = {
            let generation = self.lock_generation_with_context(context)?;
            self.validate_failed_generation_with_context(
                &generation,
                expected_runtime_instance_id,
                context,
            )?;
            let failure = generation.state.startup_failure().ok_or_else(|| {
                runtime_error_with_trace(ErrorCode::RuntimeStartupFailed, context.trace_id())
            })?;
            if !failure
                .recovery_actions
                .iter()
                .any(|action| action.kind == RecoveryActionKind::CopyTechnicalDetails)
            {
                return Err(runtime_error_with_trace(
                    ErrorCode::RuntimeStartupFailed,
                    context.trace_id(),
                ));
            }
            generation.recovery_context.clone()
        };
        let Some(recovery_context) = recovery_context else {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        };
        let Some(diagnostics) = recovery_context.diagnostics.as_ref() else {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        };
        let failure = &diagnostics.failure;
        Ok(TechnicalDetails {
            text: technical_details_text(
                expected_runtime_instance_id,
                failure,
                failure.data_directory_available,
            ),
        })
    }

    /// Opens the failed generation's data directory with the host desktop
    /// shell when a trusted local path is available.
    pub fn open_startup_data_directory(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
    ) -> Result<(), ApplicationError> {
        let (context, _guard) = self.begin_operation("runtime", "open_startup_data_directory")?;
        self.open_startup_data_directory_with_context(expected_runtime_instance_id, &context)
    }

    /// Opens the data directory under an existing top-level context.
    pub fn open_startup_data_directory_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let directory = {
            let generation = self.lock_generation_with_context(context)?;
            self.validate_failed_generation_with_context(
                &generation,
                expected_runtime_instance_id,
                context,
            )?;
            let failure = generation.state.startup_failure().ok_or_else(|| {
                runtime_error_with_trace(ErrorCode::RuntimeStartupFailed, context.trace_id())
            })?;
            if !failure
                .recovery_actions
                .iter()
                .any(|action| action.kind == RecoveryActionKind::OpenDataDirectory)
            {
                return Err(runtime_error_with_trace(
                    ErrorCode::RuntimeStartupFailed,
                    context.trace_id(),
                ));
            }
            generation
                .recovery_context
                .as_ref()
                .and_then(|context| context.data_directory.clone())
                .ok_or_else(|| {
                    runtime_error_with_trace(ErrorCode::RuntimeStartupFailed, context.trace_id())
                })?
        };
        if !directory.is_dir() {
            return Err(runtime_error_with_trace(
                ErrorCode::InternalUnexpected,
                context.trace_id(),
            ));
        }
        argus_infrastructure::diagnostics::open_data_directory(&directory).map_err(|_| {
            runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
        })
    }

    /// Executes the authoritative appearance query through the admitted ready
    /// generation.
    pub fn get_appearance_settings(
        &self,
    ) -> Result<argus_application::AppearanceSettings, ApplicationError> {
        let (context, _guard) = self.begin_operation("settings", "read")?;
        self.get_appearance_settings_with_context(&context)
    }

    /// Executes the appearance query under an existing top-level context.
    pub fn get_appearance_settings_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<argus_application::AppearanceSettings, ApplicationError> {
        let guard = {
            let generation = self.lock_generation_with_context(context)?;
            generation.admit_operation_with_context(context, OperationClass::Query)?
        };
        if guard.token().is_cancelled() {
            return Err(crate::operations::cancelled_error_with_trace(
                context.trace_id(),
            ));
        }
        let handle = {
            let generation = self.lock_generation_with_context(context)?;
            generation.kernel_handle().ok_or_else(|| {
                runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
            })?
        };
        let kernel_guard = handle.lock().map_err(|_| {
            runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
        })?;
        let kernel = kernel_guard.as_ref().ok_or_else(|| {
            runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
        })?;
        kernel.get_appearance_settings_with_context(context)
    }

    /// Executes the complete-aggregate appearance command through the admitted
    /// ready generation. No authoritative state is echoed on success.
    pub fn update_appearance_settings(
        &self,
        settings: argus_application::AppearanceSettings,
    ) -> Result<(), ApplicationError> {
        let (context, _guard) = self.begin_operation("settings", "update")?;
        self.update_appearance_settings_with_context(&context, settings)
    }

    /// Executes the appearance command under an existing top-level context.
    pub fn update_appearance_settings_with_context(
        &self,
        context: &OperationContext,
        settings: argus_application::AppearanceSettings,
    ) -> Result<(), ApplicationError> {
        let guard = {
            let generation = self.lock_generation_with_context(context)?;
            generation.admit_operation_with_context(context, OperationClass::ImmediateCommand)?
        };
        if guard.token().is_cancelled() {
            return Err(crate::operations::cancelled_error_with_trace(
                context.trace_id(),
            ));
        }
        let handle = {
            let generation = self.lock_generation_with_context(context)?;
            generation.kernel_handle().ok_or_else(|| {
                runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
            })?
        };
        let kernel_guard = handle.lock().map_err(|_| {
            runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
        })?;
        let kernel = kernel_guard.as_ref().ok_or_else(|| {
            runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
        })?;
        let token = guard.token().clone();
        let pre_dispatch_token = token.clone();
        let pre_commit_token = token.clone();
        kernel.update_appearance_settings_with_context(
            context,
            settings,
            Arc::new(move || pre_dispatch_token.is_cancelled()),
            Arc::new(move || pre_commit_token.is_cancelled()),
        )
    }

    /// Opens the one active logical event connection for the current generation.
    pub fn subscribe_events(&self) -> Result<RuntimeEventSubscription, ApplicationError> {
        let id = self.current_state().runtime_instance_id();
        self.subscribe_events_for_generation(id)
    }

    /// Reconnects the active event connection for the expected generation.
    pub fn subscribe_events_for_generation(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
    ) -> Result<RuntimeEventSubscription, ApplicationError> {
        let boundary = {
            let generation = self.lock_generation()?;
            if generation.id != expected_runtime_instance_id {
                return Err(runtime_error(ErrorCode::RuntimeStaleInstance));
            }
            Arc::clone(&generation.events)
        };
        let state = boundary.attach();
        let connection_id = self
            .inner
            .next_connection_id
            .fetch_add(1, Ordering::Relaxed);
        let mut active = self
            .inner
            .active_event
            .lock()
            .map_err(|_| runtime_error(ErrorCode::InternalUnexpected))?;
        if let Some(previous) = active.replace(ActiveEventConnection {
            connection_id,
            state: Arc::clone(&state),
        }) {
            previous.state.close();
        }
        Ok(RuntimeEventSubscription {
            state,
            host: Arc::downgrade(&self.inner),
            connection_id,
        })
    }

    /// Returns the number of active logical native connections.
    pub fn active_event_subscription_count(&self) -> usize {
        usize::from(
            self.inner
                .active_event
                .lock()
                .expect("active event lock")
                .is_some(),
        )
    }

    fn apply_startup_result(
        &self,
        result: StartupResult,
    ) -> Result<RuntimeState, ApplicationError> {
        let mut generation = self.lock_generation()?;
        if generation.state.lifecycle() != RuntimeLifecycle::Starting
            || generation.id != result.state.runtime_instance_id()
        {
            return Ok(generation.state.clone());
        }
        generation.state = result.state.clone();
        if let Some(kernel) = result.kernel {
            generation.kernel = Some(Arc::new(Mutex::new(Some(kernel))));
        }
        generation.recovery_context = result.recovery_context.map(Arc::new);
        self.record_history(result.history);
        match &generation.state {
            RuntimeState::Ready {
                runtime_instance_id,
            } => {
                let _ = runtime_instance_id;
                self.publish_outward(RuntimeEventPayload::RuntimeStateChanged {
                    lifecycle: RuntimeLifecycle::Ready,
                });
            }
            RuntimeState::StartupFailed {
                runtime_instance_id,
                failure,
            } => {
                let _ = runtime_instance_id;
                self.publish_outward(RuntimeEventPayload::StartupFailed {
                    phase: failure.phase,
                });
            }
            _ => {}
        }
        Ok(generation.state.clone())
    }

    fn record_history(&self, records: impl IntoIterator<Item = StartupPhaseRecord>) {
        if let Ok(mut history) = self.inner.startup_history.lock() {
            history.clear();
            history.extend(records);
        }
    }

    fn replace_with_new_generation_with_context(
        &self,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        let mut generation = self.lock_generation_with_context(context)?;
        if generation.id != expected_runtime_instance_id {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStaleInstance,
                context.trace_id(),
            ));
        }
        if !matches!(
            generation.state.lifecycle(),
            RuntimeLifecycle::StartupFailed | RuntimeLifecycle::Stopped
        ) {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        }
        generation.events.close();
        self.clear_active_event();
        *generation = ApplicationRuntime::new();
        Ok(())
    }

    pub(crate) fn clear_active_event(&self) {
        if let Ok(mut active) = self.inner.active_event.lock()
            && let Some(connection) = active.take()
        {
            connection.state.close();
        }
    }

    pub(crate) fn lock_generation(
        &self,
    ) -> Result<std::sync::MutexGuard<'_, ApplicationRuntime>, ApplicationError> {
        self.inner
            .current
            .lock()
            .map_err(|_| runtime_error(ErrorCode::InternalUnexpected))
    }

    /// Locks the generation and maps poison to the request trace.
    pub(crate) fn lock_generation_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<std::sync::MutexGuard<'_, ApplicationRuntime>, ApplicationError> {
        self.inner.current.lock().map_err(|_| {
            runtime_error_with_trace(ErrorCode::InternalUnexpected, context.trace_id())
        })
    }

    /// Validates a failed generation and maps errors to the request trace.
    pub(crate) fn validate_failed_generation_with_context(
        &self,
        generation: &ApplicationRuntime,
        expected_runtime_instance_id: RuntimeInstanceId,
        context: &OperationContext,
    ) -> Result<(), ApplicationError> {
        if generation.id != expected_runtime_instance_id {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStaleInstance,
                context.trace_id(),
            ));
        }
        if generation.state.lifecycle() != RuntimeLifecycle::StartupFailed {
            return Err(runtime_error_with_trace(
                ErrorCode::RuntimeStartupFailed,
                context.trace_id(),
            ));
        }
        Ok(())
    }
}

fn runtime_error(code: ErrorCode) -> ApplicationError {
    let trace = new_trace_id();
    runtime_error_with_trace(code, trace)
}

fn runtime_error_with_trace(code: ErrorCode, trace: TraceId) -> ApplicationError {
    ApplicationError::from_code(code, trace, argus_application::SafeContext::new())
        .expect("runtime lifecycle error uses an allowlisted empty context")
}

fn technical_details_text(
    generation_id: RuntimeInstanceId,
    failure: &StartupFailure,
    data_directory_available: bool,
) -> String {
    let actions = failure
        .recovery_actions
        .iter()
        .map(|action| format!("{:?}", action.kind))
        .collect::<Vec<_>>()
        .join(",");
    format!(
        "runtime_instance_id={generation_id}\nlifecycle=StartupFailed\nphase={}\nerror_code={}\nmessage_key={}\ntrace_id={}\nrecovery_actions={actions}\ndata_directory_available={data_directory_available}\n",
        failure.phase.as_str(),
        failure.error.code.as_str(),
        failure.error.message_key.as_str(),
        failure.error.trace_id,
    )
}

#[cfg(test)]
mod tests {
    use std::sync::mpsc;
    use std::sync::{Arc, Barrier};
    use std::thread;
    use std::time::Duration;

    use crate::startup::SettingsReadPort;
    use crate::{
        ApplicationHost, InProcessNotificationSink, KernelBootstrapOptions, RuntimeEventPayload,
        RuntimeInstanceId, RuntimeLifecycle, RuntimeState, StartupFailure, StartupPhase,
        StartupPhaseObserver,
    };
    use argus_application::{
        ApplicationError, ErrorCode, OperationContext, OperationName, SafeContext, SubsystemName,
        TraceId,
    };

    #[test]
    fn shutdown_deadline_is_global_and_does_not_block_on_held_kernel() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let host = Arc::new(ApplicationHost::new(
            KernelBootstrapOptions::with_data_directory(directory.path()),
        ));
        host.initialize().expect("startup");
        let kernel_handle = {
            let generation = host.lock_generation().expect("generation");
            generation.kernel_handle().expect("kernel handle")
        };
        let shutdown_host = Arc::clone(&host);
        let started = Arc::new(Barrier::new(2));
        let test_started = Arc::clone(&started);
        let shutdown = thread::spawn(move || {
            test_started.wait();
            shutdown_host
                .general_shutdown_bounded(Duration::from_millis(50), None)
                .expect("bounded shutdown");
        });

        let _held = kernel_handle.lock().expect("held kernel");
        started.wait();
        shutdown.join().expect("shutdown thread");

        assert!(host.shutdown_was_incomplete());
        assert!(matches!(host.current_state(), RuntimeState::Stopped { .. }));
        assert_eq!(host.current_state().lifecycle(), RuntimeLifecycle::Stopped);
    }

    fn fixed_context(value: u128) -> OperationContext {
        OperationContext::new(
            TraceId::try_from(value).expect("trace"),
            SubsystemName::try_from("test").expect("subsystem"),
            OperationName::try_from("probe").expect("operation"),
        )
    }

    struct FailingSettingsRead;

    impl SettingsReadPort for FailingSettingsRead {
        fn read(
            &self,
            context: &OperationContext,
        ) -> Result<argus_application::AppearanceSettings, ApplicationError> {
            if context.operation().as_str() == "settings_integrity" {
                return Ok(argus_application::AppearanceSettings::new(
                    argus_application::ThemeMode::System,
                ));
            }
            Err(ApplicationError::from_code(
                ErrorCode::RuntimeNotReady,
                TraceId::try_from(9_u128).expect("trace"),
                SafeContext::new(),
            )
            .expect("error"))
        }
    }

    #[test]
    fn settings_admission_uses_request_trace() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
            directory.path(),
        ));
        host.initialize().expect("startup");
        host.general_shutdown().expect("shutdown");
        let context = fixed_context(11);

        let error = host
            .get_appearance_settings_with_context(&context)
            .expect_err("admission closed");
        assert_eq!(error.trace_id, context.trace_id());
    }

    #[test]
    fn recovery_validation_uses_request_trace() {
        let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory("relative"));
        let failed = host.initialize().expect("failed startup");
        let context = fixed_context(12);

        let error = host
            .retry_startup_with_context(failed.runtime_instance_id(), &context)
            .expect_err("action not offered");
        assert_eq!(error.trace_id, context.trace_id());
    }

    #[test]
    fn open_data_directory_uses_request_trace() {
        let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory("relative"));
        let failed = host.initialize().expect("failed startup");
        let context = fixed_context(13);

        let error = host
            .open_startup_data_directory_with_context(failed.runtime_instance_id(), &context)
            .expect_err("action not offered");
        assert_eq!(error.trace_id, context.trace_id());
    }

    #[test]
    fn stale_recovery_uses_request_trace() {
        let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory("relative"));
        let _failed = host.initialize().expect("failed startup");
        let context = fixed_context(14);

        let error = host
            .reset_appearance_settings_with_context(RuntimeInstanceId::new(), &context)
            .expect_err("stale generation");
        assert_eq!(error.code.as_str(), "ARGUS.V1.RUNTIME.STALE_INSTANCE");
        assert_eq!(error.trace_id, context.trace_id());
    }

    #[test]
    fn shutdown_failure_uses_request_trace() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
            directory.path(),
        ));
        host.poison_top_level_tracker_for_tests();
        let context = fixed_context(15);

        let error = host
            .general_shutdown_bounded_with_context(Duration::from_millis(50), None, &context)
            .expect_err("poisoned tracker");
        assert_eq!(error.trace_id, context.trace_id());
    }

    struct BlockingObserver {
        block_phase: StartupPhase,
        entered: mpsc::Sender<()>,
        release: mpsc::Receiver<()>,
    }

    impl StartupPhaseObserver for BlockingObserver {
        fn phase_started(&self, phase: StartupPhase) {
            if phase == self.block_phase {
                let _ = self.entered.send(());
                let _ = self.release.recv();
            }
        }
    }

    #[test]
    fn shutdown_coordinates_inflight_startup_and_prevents_resurrection() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let host = Arc::new(ApplicationHost::new(
            KernelBootstrapOptions::with_data_directory(directory.path()),
        ));
        let (entered_tx, entered_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let observer = BlockingObserver {
            block_phase: StartupPhase::PersistenceInitialization,
            entered: entered_tx,
            release: release_rx,
        };
        let startup_host = Arc::clone(&host);
        let startup = thread::spawn(move || startup_host.initialize_for_tests(&observer));

        entered_rx.recv().expect("startup reached blocked phase");
        host.general_shutdown_bounded(Duration::from_millis(50), None)
            .expect("bounded shutdown");
        assert!(host.shutdown_was_incomplete());
        assert!(matches!(host.current_state(), RuntimeState::Stopped { .. }));

        release_tx.send(()).expect("release startup");
        let late = startup.join().expect("startup thread");
        assert!(late.is_ok(), "late result is still returned to caller");
        assert!(matches!(host.current_state(), RuntimeState::Stopped { .. }));
    }

    #[test]
    fn cooperative_shutdown_waits_for_startup_completion() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let host = Arc::new(ApplicationHost::new(
            KernelBootstrapOptions::with_data_directory(directory.path()),
        ));
        let (entered_tx, entered_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let observer = BlockingObserver {
            block_phase: StartupPhase::PersistenceInitialization,
            entered: entered_tx,
            release: release_rx,
        };
        let startup_host = Arc::clone(&host);
        let startup = thread::spawn(move || startup_host.initialize_for_tests(&observer));
        entered_rx.recv().expect("startup reached blocked phase");

        let (shutdown_started_tx, shutdown_started_rx) = mpsc::channel();
        let shutdown_host = Arc::clone(&host);
        let shutdown = thread::spawn(move || {
            shutdown_started_tx.send(()).expect("started");
            shutdown_host
                .general_shutdown_bounded(Duration::from_secs(5), None)
                .expect("cooperative shutdown")
        });
        shutdown_started_rx.recv().expect("shutdown started");
        release_tx.send(()).expect("release startup");

        let _ = startup.join().expect("startup thread");
        shutdown.join().expect("shutdown thread");
        assert!(!host.shutdown_was_incomplete());
        assert!(!host.startup_active_for_tests());
        assert!(matches!(host.current_state(), RuntimeState::Stopped { .. }));
    }

    #[test]
    fn technical_details_report_data_directory_availability() {
        let context = fixed_context(16);
        let error = ApplicationError::from_code(
            ErrorCode::ConfigurationInvalid,
            context.trace_id(),
            SafeContext::new(),
        )
        .expect("error");
        let mut failure = StartupFailure {
            phase: StartupPhase::EnvironmentInitialization,
            error,
            recovery_actions: vec![],
            diagnostics_available: true,
            data_directory_available: false,
        };
        let unavailable = super::technical_details_text(RuntimeInstanceId::new(), &failure, false);
        assert!(unavailable.contains("data_directory_available=false"));
        failure.data_directory_available = true;
        let available = super::technical_details_text(RuntimeInstanceId::new(), &failure, true);
        assert!(available.contains("data_directory_available=true"));
    }

    #[test]
    fn retry_does_not_start_runtime_b_after_failed_kernel_shutdown() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
            directory.path(),
        ));
        let id = host.install_failing_shutdown_generation_for_tests();
        let context = fixed_context(17);

        let error = host
            .retry_startup_with_context(id, &context)
            .expect_err("failed kernel shutdown");
        assert_eq!(error.code.as_str(), "ARGUS.V1.INTERNAL.UNEXPECTED");
        assert_eq!(error.trace_id, context.trace_id());
        assert_eq!(host.current_state().runtime_instance_id(), id);
    }

    #[test]
    fn exit_after_failed_kernel_shutdown_reports_bounded_failure_and_stays_stopped() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let host = ApplicationHost::new(KernelBootstrapOptions::with_data_directory(
            directory.path(),
        ));
        let id = host.install_failing_shutdown_generation_for_tests();
        let context = fixed_context(18);

        let error = host
            .exit_failed_runtime_with_context(id, &context)
            .expect_err("kernel shutdown failure must be reported");
        assert_eq!(error.code.as_str(), "ARGUS.V1.INTERNAL.UNEXPECTED");
        assert_eq!(error.trace_id, context.trace_id());
        assert!(matches!(host.current_state(), RuntimeState::Stopped { .. }));
    }

    #[test]
    fn recovery_retirement_events_use_injected_sink() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let sink = std::sync::Arc::new(InProcessNotificationSink::new());
        let host = ApplicationHost::with_notification_sink(
            KernelBootstrapOptions::with_data_directory(directory.path()),
            std::sync::Arc::clone(&sink) as std::sync::Arc<dyn crate::RuntimeNotificationSink>,
        );
        let failed = host
            .initialize_with_settings_read_for_tests(Box::new(FailingSettingsRead))
            .expect("failed startup");
        assert!(matches!(failed, RuntimeState::StartupFailed { .. }));
        let subscription = host.subscribe_events().expect("subscription");

        host.exit_failed_runtime(failed.runtime_instance_id())
            .expect("exit");

        let mut transitions = Vec::new();
        while let Ok(Some(event)) = subscription.try_recv() {
            if let RuntimeEventPayload::RuntimeStateChanged { lifecycle } = event.payload {
                transitions.push(lifecycle);
            }
        }
        assert_eq!(
            transitions,
            vec![RuntimeLifecycle::ShuttingDown, RuntimeLifecycle::Stopped,]
        );
    }
}
