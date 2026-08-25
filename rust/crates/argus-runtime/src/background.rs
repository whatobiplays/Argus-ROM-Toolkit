//! Generic background-operation manager owned by one runtime generation.
//!
//! The manager owns top-level background admission, bounded pending/active
//! registries, logical resource acquisition/release, persisted lifecycle
//! transitions, cancellation coordination, and shutdown. It contains no
//! operation-specific business logic; registered handlers own execution.

use std::collections::{HashMap, VecDeque};
#[cfg(feature = "test-support")]
use std::sync::atomic::AtomicBool;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use argus_application::{
    ApplicationError, ApplicationEvent, BackgroundOperationHandler, BackgroundOperationStopReason,
    JobProgress, JobProgressReporter, JobRunId, JobRunRepository, JobRunState, OperationContext,
    OperationHandle, OperationName, SubsystemName, UnitOfWork, UnitOfWorkFactory,
};

use crate::events::EventBus;
use crate::new_trace_id;
use crate::operations::ResourceClass;

/// Maximum number of active runs addressable by one execution-host stop.
///
/// The bridge uses the same bound as the manager's default pending capacity so
/// host callbacks stay bounded without introducing a second scheduling policy.
pub const MAX_EXECUTION_HOST_STOP_JOB_RUNS: usize = 16;

/// Failure to register an already-durably-admitted run.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ManagerAdmissionError {
    ShuttingDown,
    CapacityExceeded,
    InvalidOperationType,
    Internal,
}

/// Internal runtime policy for one background manager.
#[derive(Clone, Debug)]
pub struct BackgroundManagerConfig {
    /// Maximum queued + active runs admitted by one manager.
    pub pending_bound: usize,
    /// Per-resource-class capacity.
    pub capacities: HashMap<ResourceClass, usize>,
    /// Bounded shutdown drain deadline for in-flight workers.
    pub drain_deadline: Duration,
}

impl Default for BackgroundManagerConfig {
    fn default() -> Self {
        Self {
            pending_bound: 16,
            capacities: HashMap::from([
                (ResourceClass::FilesystemRead, 1),
                (ResourceClass::MetadataProviderNetwork, 1),
                (ResourceClass::PersistenceWrite, 1),
            ]),
            drain_deadline: Duration::from_secs(5),
        }
    }
}

struct RunningRun {
    handler: Arc<dyn BackgroundOperationHandler>,
    operation: OperationName,
    token: BackgroundStopToken,
    required_resources: Vec<ResourceClass>,
    acquired_resources: Vec<ResourceClass>,
    worker: Option<JoinHandle<()>>,
}

/// Runtime-private stop signal that preserves simultaneous stop requests.
///
/// Cancellation has precedence over host timeout, which has precedence over
/// host loss. Keeping these bits separate avoids losing an accepted
/// cancellation when it races a native host notification.
#[derive(Clone)]
struct BackgroundStopToken {
    bits: Arc<AtomicU8>,
}

impl BackgroundStopToken {
    const CANCELLATION: u8 = 1 << 0;
    const EXECUTION_HOST_TIMEOUT: u8 = 1 << 1;
    const EXECUTION_HOST_LOST: u8 = 1 << 2;

    fn new() -> Self {
        Self {
            bits: Arc::new(AtomicU8::new(0)),
        }
    }

    fn request(&self, reason: BackgroundOperationStopReason) {
        let bit = match reason {
            BackgroundOperationStopReason::CancellationRequested => Self::CANCELLATION,
            BackgroundOperationStopReason::ExecutionHostTimeout => Self::EXECUTION_HOST_TIMEOUT,
            BackgroundOperationStopReason::ExecutionHostLost => Self::EXECUTION_HOST_LOST,
        };
        self.bits.fetch_or(bit, Ordering::SeqCst);
    }

    fn reason(&self) -> Option<BackgroundOperationStopReason> {
        let bits = self.bits.load(Ordering::SeqCst);
        if bits & Self::CANCELLATION != 0 {
            return Some(BackgroundOperationStopReason::CancellationRequested);
        }
        if bits & Self::EXECUTION_HOST_TIMEOUT != 0 {
            return Some(BackgroundOperationStopReason::ExecutionHostTimeout);
        }
        if bits & Self::EXECUTION_HOST_LOST != 0 {
            return Some(BackgroundOperationStopReason::ExecutionHostLost);
        }
        None
    }
}

struct ManagerState {
    pending: VecDeque<JobRunId>,
    active: HashMap<JobRunId, RunningRun>,
    available: HashMap<ResourceClass, usize>,
    shutting_down: bool,
}

/// One runtime-owned generic background-operation manager.
pub struct BackgroundOperationManager<U> {
    state: Arc<Mutex<ManagerState>>,
    wake: Arc<Condvar>,
    unit_of_work: U,
    event_bus: Arc<EventBus>,
    config: BackgroundManagerConfig,
    #[cfg(feature = "test-support")]
    fail_spawn: AtomicBool,
}

impl<U> Clone for BackgroundOperationManager<U>
where
    U: Clone,
{
    fn clone(&self) -> Self {
        Self {
            state: Arc::clone(&self.state),
            wake: Arc::clone(&self.wake),
            unit_of_work: self.unit_of_work.clone(),
            event_bus: Arc::clone(&self.event_bus),
            config: self.config.clone(),
            #[cfg(feature = "test-support")]
            fail_spawn: AtomicBool::new(false),
        }
    }
}

impl<U> BackgroundOperationManager<U>
where
    U: UnitOfWorkFactory + Clone + Send + Sync + 'static,
{
    /// Creates one manager with the supplied persistence, event, and policy.
    pub fn new(unit_of_work: U, event_bus: Arc<EventBus>, config: BackgroundManagerConfig) -> Self {
        let mut available = HashMap::new();
        for (resource, capacity) in &config.capacities {
            available.insert(*resource, *capacity);
        }
        Self {
            state: Arc::new(Mutex::new(ManagerState {
                pending: VecDeque::new(),
                active: HashMap::new(),
                available,
                shutting_down: false,
            })),
            wake: Arc::new(Condvar::new()),
            unit_of_work,
            event_bus,
            config,
            #[cfg(feature = "test-support")]
            fail_spawn: AtomicBool::new(false),
        }
    }

    /// Registers an already-durably-admitted run. On failure the caller must
    /// terminalize the run; the manager never owns an orphan.
    pub fn register(
        &self,
        handle: &OperationHandle,
        handler: Arc<dyn BackgroundOperationHandler>,
        required_resources: &[ResourceClass],
    ) -> Result<(), ManagerAdmissionError> {
        let operation = OperationName::try_from(handle.operation_type())
            .map_err(|_| ManagerAdmissionError::InvalidOperationType)?;
        let mut state = self
            .state
            .lock()
            .map_err(|_| ManagerAdmissionError::Internal)?;
        if state.shutting_down {
            return Err(ManagerAdmissionError::ShuttingDown);
        }
        if state.pending.len() + state.active.len() >= self.config.pending_bound {
            return Err(ManagerAdmissionError::CapacityExceeded);
        }
        state.pending.push_back(handle.job_run_id());
        state.active.insert(
            handle.job_run_id(),
            RunningRun {
                handler,
                operation,
                token: BackgroundStopToken::new(),
                required_resources: required_resources.to_vec(),
                acquired_resources: Vec::new(),
                worker: None,
            },
        );
        drop(state);
        if let Err(error) = self.spawn_worker(handle.job_run_id()) {
            let mut state = self.state.lock().expect("manager state lock");
            state
                .pending
                .retain(|candidate| *candidate != handle.job_run_id());
            if let Some(run) = state.active.remove(&handle.job_run_id())
                && let Some(worker) = run.worker
            {
                drop(worker);
            }
            self.wake.notify_all();
            return Err(error);
        }
        Ok(())
    }

    /// Notifies one active run that durable cancellation intent was accepted.
    pub fn notify_cancellation(&self, job_run_id: JobRunId) {
        let state = self.state.lock().expect("manager state lock");
        if let Some(run) = state.active.get(&job_run_id) {
            run.token
                .request(BackgroundOperationStopReason::CancellationRequested);
        }
        self.wake.notify_all();
    }

    /// Notifies one active run that its live execution host stopped.
    ///
    /// Cancellation remains exclusively owned by the durable Jobs control
    /// path, so a cancellation reason supplied here is intentionally ignored.
    pub fn notify_execution_host_stop(
        &self,
        job_run_id: JobRunId,
        reason: BackgroundOperationStopReason,
    ) {
        if matches!(reason, BackgroundOperationStopReason::CancellationRequested) {
            return;
        }
        let state = self.state.lock().expect("manager state lock");
        if let Some(run) = state.active.get(&job_run_id) {
            run.token.request(reason);
        }
        self.wake.notify_all();
    }

    /// Requests shutdown: closes admission, cancels active work, and drains
    /// within the configured deadline. Returns whether the drain completed.
    pub fn shutdown(&self) -> bool {
        {
            let mut state = self.state.lock().expect("manager state lock");
            state.shutting_down = true;
            for run in state.active.values() {
                run.token
                    .request(BackgroundOperationStopReason::CancellationRequested);
            }
            self.wake.notify_all();
        }
        let deadline = Instant::now() + self.config.drain_deadline;
        loop {
            let mut state = self.state.lock().expect("manager state lock");
            if state.active.is_empty() {
                return true;
            }
            let now = Instant::now();
            if now >= deadline {
                return false;
            }
            let (next, wait_result) = self
                .wake
                .wait_timeout(state, deadline.saturating_duration_since(now))
                .expect("manager state wait");
            state = next;
            if wait_result.timed_out() {
                return state.active.is_empty();
            }
        }
    }

    fn spawn_worker(&self, job_run_id: JobRunId) -> Result<(), ManagerAdmissionError> {
        #[cfg(feature = "test-support")]
        if self.fail_spawn.swap(false, Ordering::SeqCst) {
            return Err(ManagerAdmissionError::Internal);
        }
        let manager = self.clone();
        let worker = std::thread::Builder::new()
            .name(format!("argus-background-{job_run_id}"))
            .spawn(move || manager.worker_loop(job_run_id))
            .map_err(|_| ManagerAdmissionError::Internal)?;
        let mut state = self.state.lock().expect("manager state lock");
        if let Some(run) = state.active.get_mut(&job_run_id) {
            run.worker = Some(worker);
        }
        Ok(())
    }

    fn worker_loop(&self, job_run_id: JobRunId) {
        let (context, handler, required_resources, token) = {
            let mut state = self.state.lock().expect("manager state lock");
            state.pending.retain(|candidate| *candidate != job_run_id);
            let Some(run) = state.active.get_mut(&job_run_id) else {
                return;
            };
            let operation = run.operation.clone();
            let context = OperationContext::new(
                new_trace_id(),
                SubsystemName::try_from("background").expect("static subsystem is valid"),
                operation,
            );
            (
                context,
                Arc::clone(&run.handler),
                run.required_resources.clone(),
                run.token.clone(),
            )
        };

        if !self.acquire_resources(job_run_id, &required_resources, &token) {
            let reason = token
                .reason()
                .unwrap_or(BackgroundOperationStopReason::CancellationRequested);
            self.finish_before_execution(job_run_id, &context, &handler, reason);
            return;
        }

        let now = crate::now_millis();
        let preparing = self.persist_job_transition(job_run_id, JobRunState::Preparing, now);
        if matches!(preparing, Ok(true)) {
            self.publish(ApplicationEvent::JobStateChanged(
                argus_application::JobStateChanged { job_run_id },
            ));
        }

        let now = crate::now_millis();
        let running = self.persist_job_transition(job_run_id, JobRunState::Running, now);
        if matches!(running, Ok(true)) {
            self.publish(ApplicationEvent::JobStateChanged(
                argus_application::JobStateChanged { job_run_id },
            ));
        }
        self.finish_run(job_run_id, &context, &handler);
    }

    /// Terminalizes a run whose handler never executed because cancellation
    /// or shutdown arrived while it was still queued for resources.
    fn finish_before_execution(
        &self,
        job_run_id: JobRunId,
        context: &OperationContext,
        handler: &Arc<dyn BackgroundOperationHandler>,
        reason: BackgroundOperationStopReason,
    ) {
        let now = crate::now_millis();
        let state = match reason {
            BackgroundOperationStopReason::CancellationRequested => JobRunState::Cancelled,
            BackgroundOperationStopReason::ExecutionHostTimeout
            | BackgroundOperationStopReason::ExecutionHostLost => JobRunState::Failed,
        };
        let _ = self.persist_terminal(job_run_id, state, None, None, now);
        // Operation-owned child state (for example ScanRun) is reconciled
        // through the generic cleanup seam without executing business logic.
        let _ = handler.stopped_before_execution(context, reason);
        self.publish(ApplicationEvent::JobStateChanged(
            argus_application::JobStateChanged { job_run_id },
        ));
        self.release_and_remove(job_run_id);
    }

    fn finish_run(
        &self,
        job_run_id: JobRunId,
        context: &OperationContext,
        handler: &Arc<dyn BackgroundOperationHandler>,
    ) {
        let token = {
            let state = self.state.lock().expect("manager state lock");
            state.active.get(&job_run_id).map(|run| run.token.clone())
        };
        let reporter = ManagerProgressReporter {
            job_run_id,
            unit_of_work: self.unit_of_work.clone(),
            event_bus: Arc::clone(&self.event_bus),
        };
        let stop_reason = {
            let token = token.clone();
            move || token.as_ref().and_then(BackgroundStopToken::reason)
        };
        let completion = handler.execute(context, &stop_reason, &reporter);
        let now = crate::now_millis();
        match completion {
            Ok(completion) => {
                let _ = self.persist_terminal(
                    job_run_id,
                    completion.state(),
                    completion.terminal_error_code().map(str::to_owned),
                    completion.terminal_safe_context().map(str::to_owned),
                    now,
                );
            }
            Err(error) => {
                let _ = self.persist_terminal(
                    job_run_id,
                    JobRunState::Failed,
                    Some(error.code.as_str().to_owned()),
                    None,
                    now,
                );
            }
        }
        self.publish(ApplicationEvent::JobStateChanged(
            argus_application::JobStateChanged { job_run_id },
        ));
        self.release_and_remove(job_run_id);
    }

    fn acquire_resources(
        &self,
        job_run_id: JobRunId,
        required_resources: &[ResourceClass],
        token: &BackgroundStopToken,
    ) -> bool {
        let mut state = self.state.lock().expect("manager state lock");
        loop {
            if token.reason().is_some() || state.shutting_down {
                return false;
            }
            if can_acquire(&state, required_resources) {
                if let Some(run) = state.active.get_mut(&job_run_id) {
                    run.acquired_resources = required_resources.to_vec();
                }
                return true;
            }
            state = self.wake.wait(state).expect("manager resource wait");
        }
    }

    fn release_and_remove(&self, job_run_id: JobRunId) {
        let mut state = self.state.lock().expect("manager state lock");
        if let Some(run) = state.active.remove(&job_run_id) {
            drop(run.acquired_resources);
            if let Some(worker) = run.worker {
                drop(worker);
            }
        }
        self.wake.notify_all();
    }

    /// Test-only seam: makes the next worker spawn fail deterministically.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn fail_next_spawn_for_tests(&self) {
        self.fail_spawn.store(true, Ordering::SeqCst);
    }

    /// Test-only active registry size.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn active_len_for_tests(&self) -> usize {
        self.state.lock().expect("manager state lock").active.len()
    }

    /// Test-only pending registry size.
    #[cfg(feature = "test-support")]
    #[doc(hidden)]
    pub fn pending_len_for_tests(&self) -> usize {
        self.state.lock().expect("manager state lock").pending.len()
    }

    fn persist_job_transition(
        &self,
        job_run_id: JobRunId,
        state: JobRunState,
        timestamp_ms: i64,
    ) -> Result<bool, ApplicationError> {
        self.unit_of_work
            .clone()
            .execute(
                &OperationContext::new(
                    new_trace_id(),
                    SubsystemName::try_from("background").expect("subsystem"),
                    OperationName::try_from("job_transition").expect("operation"),
                ),
                move |mut scope| {
                    let changed = scope
                        .job_runs()
                        .set_state(job_run_id, state, timestamp_ms)?;
                    scope.commit()?;
                    Ok::<_, argus_application::ApplicationPortError>(changed)
                },
            )
            .map_err(map_port_error)
    }

    fn persist_terminal(
        &self,
        job_run_id: JobRunId,
        state: JobRunState,
        terminal_error_code: Option<String>,
        terminal_safe_context: Option<String>,
        timestamp_ms: i64,
    ) -> Result<bool, ApplicationError> {
        self.unit_of_work
            .clone()
            .execute(
                &OperationContext::new(
                    new_trace_id(),
                    SubsystemName::try_from("background").expect("subsystem"),
                    OperationName::try_from("job_transition").expect("operation"),
                ),
                move |mut scope| {
                    let changed = scope.job_runs().set_terminal_failure(
                        job_run_id,
                        state,
                        terminal_error_code,
                        terminal_safe_context,
                        timestamp_ms,
                    )?;
                    scope.commit()?;
                    Ok::<_, argus_application::ApplicationPortError>(changed)
                },
            )
            .map_err(map_port_error)
    }

    fn publish(&self, event: ApplicationEvent) {
        self.event_bus.publish(event);
    }
}

fn can_acquire(state: &ManagerState, resources: &[ResourceClass]) -> bool {
    resources.iter().all(|resource| {
        let capacity = state.available.get(resource).copied().unwrap_or(0);
        let used = state
            .active
            .values()
            .filter(|run| run.acquired_resources.contains(resource))
            .count();
        used < capacity
    })
}

struct ManagerProgressReporter<U> {
    job_run_id: JobRunId,
    unit_of_work: U,
    event_bus: Arc<EventBus>,
}

impl<U> JobProgressReporter for ManagerProgressReporter<U>
where
    U: UnitOfWorkFactory + Clone + Send + Sync,
{
    fn report(&self, progress: JobProgress) -> Result<(), ApplicationError> {
        let job_run_id = self.job_run_id;
        let progress_for_commit = progress.clone();
        self.unit_of_work
            .clone()
            .execute(
                &OperationContext::new(
                    new_trace_id(),
                    SubsystemName::try_from("background").expect("subsystem"),
                    OperationName::try_from("job_progress").expect("operation"),
                ),
                move |mut scope| {
                    scope
                        .job_runs()
                        .set_progress(job_run_id, &progress_for_commit)?;
                    scope.commit()?;
                    Ok::<_, argus_application::ApplicationPortError>(())
                },
            )
            .map_err(map_port_error)?;
        self.event_bus.publish(ApplicationEvent::JobProgressChanged(
            argus_application::JobProgressChanged {
                progress: progress.clone(),
            },
        ));
        Ok(())
    }
}

fn map_port_error(error: argus_application::ApplicationPortError) -> ApplicationError {
    match error {
        argus_application::ApplicationPortError::Persistence(error) => {
            let code = match error {
                argus_application::PersistenceError::DatabaseLocked => {
                    argus_application::ErrorCode::PersistenceDatabaseLocked
                }
                argus_application::PersistenceError::Cancelled => {
                    argus_application::ErrorCode::OperationCancelled
                }
                _ => argus_application::ErrorCode::InternalUnexpected,
            };
            ApplicationError::from_code(code, new_trace_id(), argus_application::SafeContext::new())
                .expect("background error context follows the published catalog")
        }
        argus_application::ApplicationPortError::EventRecording => ApplicationError::from_code(
            argus_application::ErrorCode::InternalUnexpected,
            new_trace_id(),
            argus_application::SafeContext::new(),
        )
        .expect("background error context follows the published catalog"),
    }
}
