//! Runtime-owned pending event collection and concrete notification routing.

use std::sync::{Arc, Mutex};

use argus_application::{
    AppearanceSettingsChanged, AppearanceSettingsSubscriber, ApplicationError, ApplicationEvent,
    ApplicationEventSink, EventName, EventRecorder, EventRecordingError, EventSubscriberError,
    JobProgressChanged, JobStateChanged, JobsSubscriber, LibraryRootChanged, LibraryRootsChanged,
    LibraryRootsSubscriber, LogEvent, LogLevel, ObservabilitySink, ObservabilitySinkError,
    OperationContext, SafeContext, SourceEntriesChanged, SourceEntriesSubscriber, TraceEvent,
};

const MAX_PENDING_EVENTS: usize = 64;
const MAX_PUBLICATION_LOGS: usize = 64;

/// Runtime-owned bounded log storage for post-commit publication diagnostics.
pub(crate) struct PublicationDiagnostics {
    logs: Vec<LogEvent>,
    traces: Vec<TraceEvent>,
}

impl PublicationDiagnostics {
    /// Creates an empty publication diagnostic collector.
    pub(crate) fn new() -> Self {
        Self {
            logs: Vec::new(),
            traces: Vec::new(),
        }
    }

    fn push_log(&mut self, event: LogEvent) -> Result<(), ObservabilitySinkError> {
        if self.logs.len() == MAX_PUBLICATION_LOGS {
            return Err(ObservabilitySinkError::CapacityExceeded);
        }
        self.logs.push(event);
        Ok(())
    }

    /// Returns publication diagnostics in emission order.
    pub(crate) fn logs(&self) -> &[LogEvent] {
        &self.logs
    }
}

impl ObservabilitySink for PublicationDiagnostics {
    fn record_log(&mut self, event: LogEvent) -> Result<(), ObservabilitySinkError> {
        self.push_log(event)
    }

    fn record_trace(&mut self, event: TraceEvent) -> Result<(), ObservabilitySinkError> {
        if self.traces.len() == MAX_PUBLICATION_LOGS {
            return Err(ObservabilitySinkError::CapacityExceeded);
        }
        self.traces.push(event);
        Ok(())
    }
}

/// Delivery counts from one best-effort publication pass.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct EventPublicationReport {
    /// Number of subscribers that accepted the event.
    pub(crate) delivered: usize,
    /// Number of subscribers that returned a failure.
    pub(crate) failed: usize,
}

/// Composition-owned in-process bus for the closed application-event set.
pub struct EventBus {
    appearance_subscribers: Vec<Box<dyn AppearanceSettingsSubscriber>>,
    library_roots_subscribers: Vec<Box<dyn LibraryRootsSubscriber>>,
    jobs_subscribers: Vec<Box<dyn JobsSubscriber>>,
    source_entries_subscribers: Vec<Box<dyn SourceEntriesSubscriber>>,
}

impl EventBus {
    /// Creates a bus with its explicitly composed subscribers.
    pub fn new(
        appearance_subscribers: Vec<Box<dyn AppearanceSettingsSubscriber>>,
        library_roots_subscribers: Vec<Box<dyn LibraryRootsSubscriber>>,
        jobs_subscribers: Vec<Box<dyn JobsSubscriber>>,
        source_entries_subscribers: Vec<Box<dyn SourceEntriesSubscriber>>,
    ) -> Self {
        Self {
            appearance_subscribers,
            library_roots_subscribers,
            jobs_subscribers,
            source_entries_subscribers,
        }
    }

    /// Returns the number of registered appearance subscribers.
    pub(crate) fn subscriber_count(&self) -> usize {
        self.appearance_subscribers.len()
            + self.library_roots_subscribers.len()
            + self.jobs_subscribers.len()
            + self.source_entries_subscribers.len()
    }

    /// Publishes one committed event, isolating each subscriber failure.
    pub(crate) fn publish(&self, event: ApplicationEvent) -> EventPublicationReport {
        match event {
            ApplicationEvent::AppearanceSettingsChanged(_) => {
                let mut report = EventPublicationReport::default();
                for subscriber in &self.appearance_subscribers {
                    match subscriber.appearance_settings_changed(AppearanceSettingsChanged) {
                        Ok(()) => report.delivered += 1,
                        Err(EventSubscriberError::Failed) => report.failed += 1,
                    }
                }
                report
            }
            ApplicationEvent::LibraryRootsChanged(_) => {
                let mut report = EventPublicationReport::default();
                for subscriber in &self.library_roots_subscribers {
                    match subscriber.library_roots_changed(LibraryRootsChanged) {
                        Ok(()) => report.delivered += 1,
                        Err(EventSubscriberError::Failed) => report.failed += 1,
                    }
                }
                report
            }
            ApplicationEvent::LibraryRootChanged(event) => {
                let mut report = EventPublicationReport::default();
                for subscriber in &self.library_roots_subscribers {
                    match subscriber.library_root_changed(LibraryRootChanged {
                        library_root_id: event.library_root_id,
                    }) {
                        Ok(()) => report.delivered += 1,
                        Err(EventSubscriberError::Failed) => report.failed += 1,
                    }
                }
                report
            }
            ApplicationEvent::JobStateChanged(event) => {
                let mut report = EventPublicationReport::default();
                for subscriber in &self.jobs_subscribers {
                    match subscriber.job_state_changed(JobStateChanged {
                        job_run_id: event.job_run_id,
                    }) {
                        Ok(()) => report.delivered += 1,
                        Err(EventSubscriberError::Failed) => report.failed += 1,
                    }
                }
                report
            }
            ApplicationEvent::JobProgressChanged(event) => {
                let mut report = EventPublicationReport::default();
                for subscriber in &self.jobs_subscribers {
                    match subscriber.job_progress_changed(JobProgressChanged {
                        progress: event.progress.clone(),
                    }) {
                        Ok(()) => report.delivered += 1,
                        Err(EventSubscriberError::Failed) => report.failed += 1,
                    }
                }
                report
            }
            ApplicationEvent::SourceEntriesChanged(event) => {
                let mut report = EventPublicationReport::default();
                for subscriber in &self.source_entries_subscribers {
                    match subscriber.source_entries_changed(SourceEntriesChanged {
                        library_root_id: event.library_root_id,
                        scope: event.scope,
                    }) {
                        Ok(()) => report.delivered += 1,
                        Err(EventSubscriberError::Failed) => report.failed += 1,
                    }
                }
                report
            }
        }
    }
}

/// Completes one update's post-commit event lifecycle.
///
/// A failed handler result discards pending events. A successful result drains
/// and publishes only after the handler has committed. Subscriber failures are
/// recorded as bounded structured diagnostics and never alter committed
/// command success.
pub(crate) fn finalize_appearance_update(
    result: Result<(), ApplicationError>,
    context: &OperationContext,
    collector: PendingEventCollector,
    event_bus: &EventBus,
    publication_diagnostics: &Mutex<PublicationDiagnostics>,
) -> Result<(), ApplicationError> {
    match result {
        Ok(()) => {
            for event in collector.take_all() {
                let report = event_bus.publish(event);
                for _ in 0..report.failed {
                    record_subscriber_failure(context, publication_diagnostics);
                }
            }
            Ok(())
        }
        Err(error) => {
            collector.discard();
            Err(error)
        }
    }
}

/// Completes one library-roots mutation's post-commit event lifecycle.
///
/// A failed handler result discards pending events. A successful result
/// drains and publishes only after the handler has committed. Subscriber
/// failures are recorded as bounded structured diagnostics and never alter
/// committed command success.
pub(crate) fn finalize_library_roots_update<T>(
    result: Result<T, ApplicationError>,
    context: &OperationContext,
    collector: PendingEventCollector,
    event_bus: &EventBus,
    publication_diagnostics: &Mutex<PublicationDiagnostics>,
) -> Result<T, ApplicationError> {
    match result {
        Ok(value) => {
            for event in collector.take_all() {
                let report = event_bus.publish(event);
                for _ in 0..report.failed {
                    record_subscriber_failure(context, publication_diagnostics);
                }
            }
            Ok(value)
        }
        Err(error) => {
            collector.discard();
            Err(error)
        }
    }
}

fn record_subscriber_failure(
    context: &OperationContext,
    publication_diagnostics: &Mutex<PublicationDiagnostics>,
) {
    let event_name = EventName::try_from("event.subscriber.failed")
        .expect("static subscriber failure event name is valid");
    let diagnostic = LogEvent::new(
        now_millis(),
        LogLevel::Warn,
        context.clone(),
        event_name,
        SafeContext::new(),
        None,
    );
    if let Ok(mut collector) = publication_diagnostics.lock() {
        let _ = collector.push_log(diagnostic);
    }
}

fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

impl Default for EventBus {
    fn default() -> Self {
        Self::new(Vec::new(), Vec::new(), Vec::new(), Vec::new())
    }
}

/// Best-effort post-commit event sink shared with background workers.
#[derive(Clone)]
pub struct EventBusSink {
    bus: Arc<EventBus>,
}

impl EventBusSink {
    /// Creates a sink over the shared runtime event bus.
    pub fn new(bus: Arc<EventBus>) -> Self {
        Self { bus }
    }
}

impl ApplicationEventSink for EventBusSink {
    fn publish(&self, event: ApplicationEvent) {
        self.bus.publish(event);
    }
}

/// Runtime-owned operation-scoped pending event state.
pub(crate) struct PendingEventCollector {
    events: Arc<Mutex<Vec<ApplicationEvent>>>,
}

impl PendingEventCollector {
    /// Creates an empty collector for one top-level operation.
    pub(crate) fn new() -> Self {
        Self {
            events: Arc::new(Mutex::new(Vec::new())),
        }
    }

    /// Returns a cloneable application-facing recorder handle.
    pub(crate) fn recorder(&self) -> PendingEventRecorder {
        PendingEventRecorder {
            events: Arc::clone(&self.events),
        }
    }

    /// Drains events in recording order after a successful commit.
    pub(crate) fn take_all(&self) -> Vec<ApplicationEvent> {
        self.events
            .lock()
            .expect("pending event collector lock")
            .drain(..)
            .collect()
    }

    /// Discards events for a failed or rolled-back operation.
    pub(crate) fn discard(&self) {
        self.events
            .lock()
            .expect("pending event collector lock")
            .clear();
    }
}

/// Cloneable runtime handle implementing the application recording boundary.
#[derive(Clone)]
pub(crate) struct PendingEventRecorder {
    events: Arc<Mutex<Vec<ApplicationEvent>>>,
}

impl EventRecorder for PendingEventRecorder {
    fn record(&self, event: ApplicationEvent) -> Result<(), EventRecordingError> {
        let mut events = self.events.lock().expect("pending event collector lock");
        if events.len() == MAX_PENDING_EVENTS {
            return Err(EventRecordingError::CapacityExceeded);
        }
        events.push(event);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use argus_application::{
        ActiveScanOwnership, AppearanceSettings, AppearanceSettingsQueries,
        AppearanceSettingsRepository, ApplicationPortError, JobProgress, JobRunId,
        JobRunRepository, JobRunState, LibraryRootAvailability, LibraryRootId,
        LibraryRootLastScanSummary, LibraryRootRepository, LibraryScanTarget,
        LibraryScanTargetRepository, LibrarySourceId, LibrarySourceRepository, NewJobRun,
        NewLibraryRoot, NewLibraryScanTarget, NewScanRun, NewSourceEntry, OperationContext,
        OperationName, PersistenceError, ScanRunId, ScanRunProjection, ScanRunRepository,
        ScanRunStatus, SettingsService, SourceEntryId, SourceEntryRepository, SubsystemName,
        ThemeMode, TraceId, UnitOfWork, UnitOfWorkFactory, UpdateAppearanceSettingsCommand,
    };
    use std::marker::PhantomData;

    #[derive(Clone)]
    struct FakeState {
        current: AppearanceSettings,
    }

    #[derive(Clone)]
    struct FakeQueries;

    impl AppearanceSettingsQueries for FakeQueries {
        fn get(&self, _context: &OperationContext) -> Result<AppearanceSettings, PersistenceError> {
            Ok(AppearanceSettings::new(ThemeMode::System))
        }
    }

    struct NoopLibrarySourceRepository<'scope> {
        marker: PhantomData<&'scope mut ()>,
    }

    impl LibrarySourceRepository for NoopLibrarySourceRepository<'_> {
        fn ensure_local_filesystem_source(&mut self) -> Result<LibrarySourceId, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }
    }

    struct NoopLibraryRootRepository<'scope> {
        marker: PhantomData<&'scope mut ()>,
    }

    impl LibraryRootRepository for NoopLibraryRootRepository<'_> {
        fn insert(&mut self, _root: NewLibraryRoot) -> Result<LibraryRootId, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn delete(&mut self, _root_id: LibraryRootId) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn exists(&mut self, _root_id: LibraryRootId) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn set_availability(
            &mut self,
            _root_id: LibraryRootId,
            _availability: LibraryRootAvailability,
        ) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn set_last_scan(
            &mut self,
            _root_id: LibraryRootId,
            _summary: Option<LibraryRootLastScanSummary>,
        ) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }
    }

    struct NoopJobRunRepository<'scope> {
        marker: PhantomData<&'scope mut ()>,
    }

    impl JobRunRepository for NoopJobRunRepository<'_> {
        fn insert(&mut self, _new: NewJobRun) -> Result<JobRunId, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn request_cancellation(
            &mut self,
            _job_run_id: JobRunId,
        ) -> Result<Option<bool>, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn set_state(
            &mut self,
            _job_run_id: JobRunId,
            _state: JobRunState,
            _timestamp_ms: i64,
        ) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn set_progress(
            &mut self,
            _job_run_id: JobRunId,
            _progress: &JobProgress,
        ) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn set_terminal_failure(
            &mut self,
            _job_run_id: JobRunId,
            _state: JobRunState,
            _terminal_error_code: Option<String>,
            _terminal_safe_context: Option<String>,
            _timestamp_ms: i64,
        ) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }
    }

    struct NoopScanRunRepository<'scope> {
        marker: PhantomData<&'scope mut ()>,
    }

    impl ScanRunRepository for NoopScanRunRepository<'_> {
        fn insert(&mut self, _new: NewScanRun) -> Result<ScanRunId, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn set_status(
            &mut self,
            _scan_run_id: ScanRunId,
            _status: ScanRunStatus,
            _completed_at_ms: Option<i64>,
            _failure_reason: Option<String>,
        ) -> Result<bool, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn find_active_ownership(
            &mut self,
            _library_root_id: LibraryRootId,
        ) -> Result<Option<ActiveScanOwnership>, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn find_last_scan(
            &mut self,
            _library_root_id: LibraryRootId,
        ) -> Result<Option<LibraryRootLastScanSummary>, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn list_by_job(
            &mut self,
            _job_run_id: JobRunId,
        ) -> Result<Vec<ScanRunProjection>, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }
    }

    struct NoopSourceEntryRepository<'scope> {
        marker: PhantomData<&'scope mut ()>,
    }

    impl SourceEntryRepository for NoopSourceEntryRepository<'_> {
        fn upsert(&mut self, _entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn delete_for_root(
            &mut self,
            _library_root_id: LibraryRootId,
        ) -> Result<(), PersistenceError> {
            Err(PersistenceError::Unavailable)
        }
    }

    struct NoopLibraryScanTargetRepository<'scope> {
        marker: PhantomData<&'scope mut ()>,
    }

    impl LibraryScanTargetRepository for NoopLibraryScanTargetRepository<'_> {
        fn insert(&mut self, _target: NewLibraryScanTarget) -> Result<(), PersistenceError> {
            Err(PersistenceError::Unavailable)
        }

        fn list_by_job(
            &mut self,
            _job_run_id: JobRunId,
        ) -> Result<Vec<LibraryScanTarget>, PersistenceError> {
            Err(PersistenceError::Unavailable)
        }
    }

    struct FailingCommitRepository<'scope> {
        state: std::sync::Arc<std::sync::Mutex<FakeState>>,
        marker: PhantomData<&'scope mut ()>,
    }

    impl AppearanceSettingsRepository for FailingCommitRepository<'_> {
        fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
            Ok(self.state.lock().expect("state lock").current)
        }

        fn save(&mut self, settings: &AppearanceSettings) -> Result<(), PersistenceError> {
            self.state.lock().expect("state lock").current = *settings;
            Ok(())
        }
    }

    struct FailingCommitUnitOfWork<'scope> {
        state: std::sync::Arc<std::sync::Mutex<FakeState>>,
        original: AppearanceSettings,
        terminal: bool,
        marker: PhantomData<&'scope mut ()>,
    }

    impl UnitOfWork for FailingCommitUnitOfWork<'_> {
        type AppearanceSettingsRepository<'scope>
            = FailingCommitRepository<'scope>
        where
            Self: 'scope;
        type LibrarySourceRepository<'scope>
            = NoopLibrarySourceRepository<'scope>
        where
            Self: 'scope;
        type LibraryRootRepository<'scope>
            = NoopLibraryRootRepository<'scope>
        where
            Self: 'scope;
        type JobRunRepository<'scope>
            = NoopJobRunRepository<'scope>
        where
            Self: 'scope;
        type ScanRunRepository<'scope>
            = NoopScanRunRepository<'scope>
        where
            Self: 'scope;
        type SourceEntryRepository<'scope>
            = NoopSourceEntryRepository<'scope>
        where
            Self: 'scope;
        type LibraryScanTargetRepository<'scope>
            = NoopLibraryScanTargetRepository<'scope>
        where
            Self: 'scope;

        fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
            FailingCommitRepository {
                state: std::sync::Arc::clone(&self.state),
                marker: PhantomData,
            }
        }

        fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
            NoopLibrarySourceRepository {
                marker: PhantomData,
            }
        }

        fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
            NoopLibraryRootRepository {
                marker: PhantomData,
            }
        }

        fn job_runs(&mut self) -> Self::JobRunRepository<'_> {
            NoopJobRunRepository {
                marker: PhantomData,
            }
        }

        fn scan_runs(&mut self) -> Self::ScanRunRepository<'_> {
            NoopScanRunRepository {
                marker: PhantomData,
            }
        }

        fn source_entries(&mut self) -> Self::SourceEntryRepository<'_> {
            NoopSourceEntryRepository {
                marker: PhantomData,
            }
        }

        fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_> {
            NoopLibraryScanTargetRepository {
                marker: PhantomData,
            }
        }

        fn commit(mut self) -> Result<(), ApplicationPortError> {
            self.state.lock().expect("state lock").current = self.original;
            self.terminal = true;
            Err(ApplicationPortError::Persistence(
                PersistenceError::Internal,
            ))
        }

        fn rollback(mut self) -> Result<(), ApplicationPortError> {
            self.state.lock().expect("state lock").current = self.original;
            self.terminal = true;
            Ok(())
        }
    }

    impl Drop for FailingCommitUnitOfWork<'_> {
        fn drop(&mut self) {
            if !self.terminal {
                self.state.lock().expect("state lock").current = self.original;
            }
        }
    }

    #[derive(Clone)]
    struct FailingCommitFactory {
        state: std::sync::Arc<std::sync::Mutex<FakeState>>,
    }

    impl UnitOfWorkFactory for FailingCommitFactory {
        type Scope<'scope>
            = FailingCommitUnitOfWork<'scope>
        where
            Self: 'scope;

        fn execute<T, F>(
            &self,
            _context: &OperationContext,
            operation: F,
        ) -> Result<T, ApplicationPortError>
        where
            T: Send + 'static,
            F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
                + Send
                + 'static,
        {
            let original = self.state.lock().expect("state lock").current;
            operation(FailingCommitUnitOfWork {
                state: std::sync::Arc::clone(&self.state),
                original,
                terminal: false,
                marker: PhantomData,
            })
        }
    }

    struct SaveFailureRepository<'scope> {
        state: std::sync::Arc<std::sync::Mutex<FakeState>>,
        marker: PhantomData<&'scope mut ()>,
    }

    impl AppearanceSettingsRepository for SaveFailureRepository<'_> {
        fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
            Ok(self.state.lock().expect("state lock").current)
        }

        fn save(&mut self, _settings: &AppearanceSettings) -> Result<(), PersistenceError> {
            Err(PersistenceError::ConstraintViolation)
        }
    }

    struct SaveFailureUnitOfWork<'scope> {
        state: std::sync::Arc<std::sync::Mutex<FakeState>>,
        original: AppearanceSettings,
        terminal: bool,
        marker: PhantomData<&'scope mut ()>,
    }

    impl UnitOfWork for SaveFailureUnitOfWork<'_> {
        type AppearanceSettingsRepository<'scope>
            = SaveFailureRepository<'scope>
        where
            Self: 'scope;
        type LibrarySourceRepository<'scope>
            = NoopLibrarySourceRepository<'scope>
        where
            Self: 'scope;
        type LibraryRootRepository<'scope>
            = NoopLibraryRootRepository<'scope>
        where
            Self: 'scope;
        type JobRunRepository<'scope>
            = NoopJobRunRepository<'scope>
        where
            Self: 'scope;
        type ScanRunRepository<'scope>
            = NoopScanRunRepository<'scope>
        where
            Self: 'scope;
        type SourceEntryRepository<'scope>
            = NoopSourceEntryRepository<'scope>
        where
            Self: 'scope;
        type LibraryScanTargetRepository<'scope>
            = NoopLibraryScanTargetRepository<'scope>
        where
            Self: 'scope;

        fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
            SaveFailureRepository {
                state: std::sync::Arc::clone(&self.state),
                marker: PhantomData,
            }
        }

        fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
            NoopLibrarySourceRepository {
                marker: PhantomData,
            }
        }

        fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
            NoopLibraryRootRepository {
                marker: PhantomData,
            }
        }

        fn job_runs(&mut self) -> Self::JobRunRepository<'_> {
            NoopJobRunRepository {
                marker: PhantomData,
            }
        }

        fn scan_runs(&mut self) -> Self::ScanRunRepository<'_> {
            NoopScanRunRepository {
                marker: PhantomData,
            }
        }

        fn source_entries(&mut self) -> Self::SourceEntryRepository<'_> {
            NoopSourceEntryRepository {
                marker: PhantomData,
            }
        }

        fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_> {
            NoopLibraryScanTargetRepository {
                marker: PhantomData,
            }
        }

        fn commit(mut self) -> Result<(), ApplicationPortError> {
            self.terminal = true;
            Ok(())
        }

        fn rollback(mut self) -> Result<(), ApplicationPortError> {
            self.state.lock().expect("state lock").current = self.original;
            self.terminal = true;
            Ok(())
        }
    }

    impl Drop for SaveFailureUnitOfWork<'_> {
        fn drop(&mut self) {
            if !self.terminal {
                self.state.lock().expect("state lock").current = self.original;
            }
        }
    }

    #[derive(Clone)]
    struct SaveFailureFactory {
        state: std::sync::Arc<std::sync::Mutex<FakeState>>,
    }

    impl UnitOfWorkFactory for SaveFailureFactory {
        type Scope<'scope>
            = SaveFailureUnitOfWork<'scope>
        where
            Self: 'scope;

        fn execute<T, F>(
            &self,
            _context: &OperationContext,
            operation: F,
        ) -> Result<T, ApplicationPortError>
        where
            T: Send + 'static,
            F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
                + Send
                + 'static,
        {
            let original = self.state.lock().expect("state lock").current;
            operation(SaveFailureUnitOfWork {
                state: std::sync::Arc::clone(&self.state),
                original,
                terminal: false,
                marker: PhantomData,
            })
        }
    }

    #[derive(Clone)]
    struct CountingSubscriber {
        calls: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    }

    impl AppearanceSettingsSubscriber for CountingSubscriber {
        fn appearance_settings_changed(
            &self,
            _event: AppearanceSettingsChanged,
        ) -> Result<(), EventSubscriberError> {
            self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Ok(())
        }
    }

    #[derive(Clone)]
    struct FailingSubscriber {
        calls: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    }

    impl AppearanceSettingsSubscriber for FailingSubscriber {
        fn appearance_settings_changed(
            &self,
            _event: AppearanceSettingsChanged,
        ) -> Result<(), EventSubscriberError> {
            self.calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Err(EventSubscriberError::Failed)
        }
    }

    #[derive(Clone)]
    struct OrderedState {
        current: AppearanceSettings,
        order: std::sync::Arc<std::sync::Mutex<Vec<&'static str>>>,
    }

    struct OrderedRepository<'scope> {
        state: std::sync::Arc<std::sync::Mutex<OrderedState>>,
        marker: PhantomData<&'scope mut ()>,
    }

    impl AppearanceSettingsRepository for OrderedRepository<'_> {
        fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
            Ok(self.state.lock().expect("ordered state lock").current)
        }

        fn save(&mut self, settings: &AppearanceSettings) -> Result<(), PersistenceError> {
            self.state.lock().expect("ordered state lock").current = *settings;
            Ok(())
        }
    }

    struct OrderedUnitOfWork<'scope> {
        state: std::sync::Arc<std::sync::Mutex<OrderedState>>,
        original: AppearanceSettings,
        terminal: bool,
        marker: PhantomData<&'scope mut ()>,
    }

    impl UnitOfWork for OrderedUnitOfWork<'_> {
        type AppearanceSettingsRepository<'scope>
            = OrderedRepository<'scope>
        where
            Self: 'scope;
        type LibrarySourceRepository<'scope>
            = NoopLibrarySourceRepository<'scope>
        where
            Self: 'scope;
        type LibraryRootRepository<'scope>
            = NoopLibraryRootRepository<'scope>
        where
            Self: 'scope;
        type JobRunRepository<'scope>
            = NoopJobRunRepository<'scope>
        where
            Self: 'scope;
        type ScanRunRepository<'scope>
            = NoopScanRunRepository<'scope>
        where
            Self: 'scope;
        type SourceEntryRepository<'scope>
            = NoopSourceEntryRepository<'scope>
        where
            Self: 'scope;
        type LibraryScanTargetRepository<'scope>
            = NoopLibraryScanTargetRepository<'scope>
        where
            Self: 'scope;

        fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
            OrderedRepository {
                state: std::sync::Arc::clone(&self.state),
                marker: PhantomData,
            }
        }

        fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
            NoopLibrarySourceRepository {
                marker: PhantomData,
            }
        }

        fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
            NoopLibraryRootRepository {
                marker: PhantomData,
            }
        }

        fn job_runs(&mut self) -> Self::JobRunRepository<'_> {
            NoopJobRunRepository {
                marker: PhantomData,
            }
        }

        fn scan_runs(&mut self) -> Self::ScanRunRepository<'_> {
            NoopScanRunRepository {
                marker: PhantomData,
            }
        }

        fn source_entries(&mut self) -> Self::SourceEntryRepository<'_> {
            NoopSourceEntryRepository {
                marker: PhantomData,
            }
        }

        fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_> {
            NoopLibraryScanTargetRepository {
                marker: PhantomData,
            }
        }

        fn commit(mut self) -> Result<(), ApplicationPortError> {
            self.state
                .lock()
                .expect("ordered state lock")
                .order
                .lock()
                .expect("order lock")
                .push("commit");
            self.terminal = true;
            Ok(())
        }

        fn rollback(mut self) -> Result<(), ApplicationPortError> {
            self.state.lock().expect("ordered state lock").current = self.original;
            self.terminal = true;
            Ok(())
        }
    }

    impl Drop for OrderedUnitOfWork<'_> {
        fn drop(&mut self) {
            if !self.terminal {
                self.state.lock().expect("ordered state lock").current = self.original;
            }
        }
    }

    #[derive(Clone)]
    struct OrderedFactory {
        state: std::sync::Arc<std::sync::Mutex<OrderedState>>,
    }

    impl UnitOfWorkFactory for OrderedFactory {
        type Scope<'scope>
            = OrderedUnitOfWork<'scope>
        where
            Self: 'scope;

        fn execute<T, F>(
            &self,
            _context: &OperationContext,
            operation: F,
        ) -> Result<T, ApplicationPortError>
        where
            T: Send + 'static,
            F: for<'scope> FnOnce(Self::Scope<'scope>) -> Result<T, ApplicationPortError>
                + Send
                + 'static,
        {
            let original = self.state.lock().expect("ordered state lock").current;
            operation(OrderedUnitOfWork {
                state: std::sync::Arc::clone(&self.state),
                original,
                terminal: false,
                marker: PhantomData,
            })
        }
    }

    #[derive(Clone)]
    struct OrderedSubscriber {
        order: std::sync::Arc<std::sync::Mutex<Vec<&'static str>>>,
    }

    impl AppearanceSettingsSubscriber for OrderedSubscriber {
        fn appearance_settings_changed(
            &self,
            _event: AppearanceSettingsChanged,
        ) -> Result<(), EventSubscriberError> {
            self.order.lock().expect("order lock").push("publish");
            Ok(())
        }
    }

    fn context() -> OperationContext {
        OperationContext::new(
            TraceId::try_from(41_u128).expect("trace"),
            SubsystemName::try_from("settings").expect("subsystem"),
            OperationName::try_from("update").expect("operation"),
        )
    }

    #[test]
    fn commit_failure_discards_pending_event_without_publication() {
        let state = std::sync::Arc::new(std::sync::Mutex::new(FakeState {
            current: AppearanceSettings::new(ThemeMode::System),
        }));
        let service = SettingsService::new(
            FakeQueries,
            FailingCommitFactory {
                state: std::sync::Arc::clone(&state),
            },
        );
        let collector = PendingEventCollector::new();
        let result = service.update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::Dark)),
            context(),
            collector.recorder(),
            Arc::new(|| false),
        );

        assert!(result.is_err(), "commit failure must fail the update");
        assert_eq!(
            state.lock().expect("state lock").current,
            AppearanceSettings::new(ThemeMode::System)
        );
        assert_eq!(
            collector.events.lock().expect("collector lock").len(),
            1,
            "semantic change recorded one pending event before commit failed"
        );
        collector.discard();
        let calls = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let bus = EventBus::new(
            vec![Box::new(CountingSubscriber {
                calls: std::sync::Arc::clone(&calls),
            })],
            Vec::new(),
            Vec::new(),
            Vec::new(),
        );
        for event in collector.take_all() {
            let _ = bus.publish(event);
        }
        assert_eq!(calls.load(std::sync::atomic::Ordering::SeqCst), 0);
    }

    #[test]
    fn save_failure_discards_without_publication() {
        let state = std::sync::Arc::new(std::sync::Mutex::new(FakeState {
            current: AppearanceSettings::new(ThemeMode::System),
        }));
        let service = SettingsService::new(
            FakeQueries,
            SaveFailureFactory {
                state: std::sync::Arc::clone(&state),
            },
        );
        let collector = PendingEventCollector::new();
        let result = service.update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::Dark)),
            context(),
            collector.recorder(),
            Arc::new(|| false),
        );

        assert!(result.is_err(), "save failure must fail the update");
        assert_eq!(
            state.lock().expect("state lock").current,
            AppearanceSettings::new(ThemeMode::System)
        );
        let events = collector.take_all();
        assert!(events.is_empty(), "a failed save cannot record an event");
        let calls = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let bus = EventBus::new(
            vec![Box::new(CountingSubscriber {
                calls: std::sync::Arc::clone(&calls),
            })],
            Vec::new(),
            Vec::new(),
            Vec::new(),
        );
        for event in events {
            let _ = bus.publish(event);
        }
        assert_eq!(calls.load(std::sync::atomic::Ordering::SeqCst), 0);
    }

    #[test]
    fn finalization_publishes_only_after_commit() {
        let order = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let state = std::sync::Arc::new(std::sync::Mutex::new(OrderedState {
            current: AppearanceSettings::new(ThemeMode::System),
            order: std::sync::Arc::clone(&order),
        }));
        let service = SettingsService::new(
            FakeQueries,
            OrderedFactory {
                state: std::sync::Arc::clone(&state),
            },
        );
        let collector = PendingEventCollector::new();
        let context = context();
        let result = service.update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::Dark)),
            context.clone(),
            collector.recorder(),
            Arc::new(|| false),
        );
        let bus = EventBus::new(
            vec![Box::new(OrderedSubscriber {
                order: std::sync::Arc::clone(&order),
            })],
            Vec::new(),
            Vec::new(),
            Vec::new(),
        );
        let diagnostics = std::sync::Mutex::new(PublicationDiagnostics::new());

        assert!(
            super::finalize_appearance_update(result, &context, collector, &bus, &diagnostics,)
                .is_ok()
        );
        assert_eq!(
            order.lock().expect("order lock").as_slice(),
            &["commit", "publish"]
        );
    }

    #[test]
    fn subscriber_failure_is_observable_without_retry_or_command_failure() {
        let order = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let state = std::sync::Arc::new(std::sync::Mutex::new(OrderedState {
            current: AppearanceSettings::new(ThemeMode::System),
            order: std::sync::Arc::clone(&order),
        }));
        let service = SettingsService::new(
            FakeQueries,
            OrderedFactory {
                state: std::sync::Arc::clone(&state),
            },
        );
        let collector = PendingEventCollector::new();
        let context = context();
        let result = service.update_appearance_settings(
            UpdateAppearanceSettingsCommand::new(AppearanceSettings::new(ThemeMode::Dark)),
            context.clone(),
            collector.recorder(),
            Arc::new(|| false),
        );
        let failing_calls = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let later_calls = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let bus = EventBus::new(
            vec![
                Box::new(FailingSubscriber {
                    calls: std::sync::Arc::clone(&failing_calls),
                }),
                Box::new(CountingSubscriber {
                    calls: std::sync::Arc::clone(&later_calls),
                }),
            ],
            Vec::new(),
            Vec::new(),
            Vec::new(),
        );
        let diagnostics = std::sync::Mutex::new(PublicationDiagnostics::new());

        assert!(
            super::finalize_appearance_update(result, &context, collector, &bus, &diagnostics,)
                .is_ok()
        );
        assert_eq!(failing_calls.load(std::sync::atomic::Ordering::SeqCst), 1);
        assert_eq!(later_calls.load(std::sync::atomic::Ordering::SeqCst), 1);
        let logs = diagnostics.lock().expect("diagnostic lock").logs().to_vec();
        assert_eq!(logs.len(), 1);
        assert_eq!(logs[0].event_name.as_str(), "event.subscriber.failed");
        assert_eq!(logs[0].context.trace_id(), context.trace_id());
        assert!(logs[0].fields.is_empty());
        assert_eq!(logs[0].application_error, None);
    }
}
