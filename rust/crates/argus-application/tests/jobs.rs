//! Slice 002 application-contract tests for jobs, scan admission, and the
//! LibraryScan operation handler.

use std::marker::PhantomData;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

mod common;

use argus_application::{
    ActiveScanOwnership, ApplicationError, ApplicationEvent, ApplicationEventSink,
    ApplicationPortError, BackgroundOperationHandler, DiscoveryPath, DiscoverySegment,
    EnumerationOutcome, EnumerationResult, ErrorCode, EventRecorder, EventRecordingError,
    JobProgress, JobProgressError, JobProgressReporter, JobRunId, JobRunRepository, JobRunState,
    JobRunStateParseError, LibraryRootAvailability, LibraryRootId, LibraryRootLastScanStatus,
    LibraryRootLastScanSummary, LibraryRootQueries, LibraryRootRepository,
    LibraryRootScanConfiguration, LibraryScanExecutionPlan, LibraryScanOperationHandler,
    LibraryScanTargetRepository, LibrarySourceAccess, NativeIdentityMatch, NewJobRun,
    NewLibraryScanTarget, NewScanRun, NewSourceEntry, ObservedEntryKind, OperationCompletion,
    OperationContext, OperationName, PersistenceError, RelativeSourceLocator,
    RemoveLibraryRootCommand, RemoveLibraryRootHandler, RemoveLibraryRootResult, ResolvedRoot,
    RootLocator, ScanRunId, ScanRunRepository, ScanRunStatus, SourceAccessError,
    SourceEntriesChangeScope, SourceEntriesChanged, SourceEntryId, SourceEntryRecord,
    SourceEntryRepository, SourceLocatorKey, SourceObservation, StartLibraryScanCommand,
    StartLibraryScanHandler, StartLibraryScanResult, SubsystemName, TraceId, UnitOfWork,
    UnitOfWorkFactory,
};

const ROOT: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const OTHER: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("non-zero trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("jobs").expect("operation"),
    )
}

fn root_id(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("root id")
}

fn job_id(value: u8) -> JobRunId {
    JobRunId::from_bytes([value; 16]).expect("job id")
}

fn scan_id(value: u8) -> ScanRunId {
    ScanRunId::from_bytes([value; 16]).expect("scan id")
}

#[test]
fn job_progress_rejects_completed_units_above_known_totals() {
    assert_eq!(
        JobProgress::new(
            job_id(1),
            "discovering",
            Some(2),
            Some(1),
            None::<String>,
            1
        ),
        Err(JobProgressError)
    );
    assert!(
        JobProgress::new(
            job_id(1),
            "discovering",
            Some(1),
            Some(1),
            None::<String>,
            1
        )
        .is_ok()
    );
    assert!(JobProgress::new(job_id(1), "discovering", Some(1), None, None::<String>, 1).is_ok());
}

#[test]
fn job_state_vocabulary_round_trips_and_classifies_terminal_states() {
    for state in [
        JobRunState::Queued,
        JobRunState::Preparing,
        JobRunState::Running,
        JobRunState::Completed,
        JobRunState::CompletedWithIssues,
        JobRunState::Failed,
        JobRunState::Cancelled,
        JobRunState::Interrupted,
        JobRunState::Abandoned,
    ] {
        assert_eq!(JobRunState::try_from(state.as_str()), Ok(state));
    }
    assert_eq!(JobRunState::try_from("unknown"), Err(JobRunStateParseError));
    assert!(JobRunState::Completed.is_terminal());
    assert!(!JobRunState::Running.is_terminal());
    assert!(JobRunState::Queued.is_active());
    assert!(!JobRunState::Cancelled.is_active());
    assert!(!ScanRunStatus::Running.is_terminal());
    assert!(ScanRunStatus::Complete.is_terminal());
}

#[derive(Clone, Default)]
struct FakeStore {
    configured: Vec<LibraryRootId>,
    active: Option<ActiveScanOwnership>,
    job_runs: Vec<JobRunId>,
    scan_runs: Vec<ScanRunId>,
    targets: usize,
    entries: usize,
    deleted_roots: Vec<LibraryRootId>,
    deleted_entries: Vec<LibraryRootId>,
    last_scan: Option<LibraryRootLastScanSummary>,
    availability: Option<LibraryRootAvailability>,
    events: Vec<ApplicationEvent>,
}

#[derive(Clone)]
struct FakeQueries {
    store: Arc<Mutex<FakeStore>>,
}

impl LibraryRootQueries for FakeQueries {
    fn list(
        &self,
        _context: &OperationContext,
        _offset: u32,
        _page_size: u32,
    ) -> Result<argus_application::LibraryRootPage, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn get(
        &self,
        _context: &OperationContext,
        _root_id: LibraryRootId,
    ) -> Result<Option<argus_application::LibraryRootProjection>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn list_root_configurations(
        &self,
        _context: &OperationContext,
    ) -> Result<Vec<argus_application::LibraryRootConfiguration>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn get_scan_configuration(
        &self,
        _context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        let store = self.store.lock().unwrap();
        if !store.configured.contains(&root_id) {
            return Ok(None);
        }
        Ok(Some(LibraryRootScanConfiguration::new(
            root_id,
            RootLocator::from_provider("/library/Games".to_owned()),
            "Games",
            "/library/Games",
            1,
            1,
            1,
        )))
    }
}

#[derive(Clone)]
struct FakeRecorder {
    store: Arc<Mutex<FakeStore>>,
}

impl EventRecorder for FakeRecorder {
    fn record(&self, event: ApplicationEvent) -> Result<(), EventRecordingError> {
        self.store.lock().unwrap().events.push(event);
        Ok(())
    }
}

struct FakeJobRunRepository<'scope> {
    store: Arc<Mutex<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl JobRunRepository for FakeJobRunRepository<'_> {
    fn insert(&mut self, _new: NewJobRun) -> Result<JobRunId, PersistenceError> {
        let id = job_id(0x11);
        self.store.lock().unwrap().job_runs.push(id);
        Ok(id)
    }

    fn insert_retry_link(
        &mut self,
        _source_job_run_id: JobRunId,
        _successor_job_run_id: JobRunId,
    ) -> Result<(), PersistenceError> {
        Ok(())
    }

    fn request_cancellation(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Option<bool>, PersistenceError> {
        Ok(Some(true))
    }

    fn set_state(
        &mut self,
        _job_run_id: JobRunId,
        _state: JobRunState,
        _timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        Ok(true)
    }

    fn set_progress(
        &mut self,
        _job_run_id: JobRunId,
        _progress: &JobProgress,
    ) -> Result<bool, PersistenceError> {
        Ok(true)
    }

    fn set_terminal_failure(
        &mut self,
        _job_run_id: JobRunId,
        _state: JobRunState,
        _terminal_error_code: Option<String>,
        _terminal_safe_context: Option<String>,
        _timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        Ok(true)
    }
}

struct FakeScanRunRepository<'scope> {
    store: Arc<Mutex<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl ScanRunRepository for FakeScanRunRepository<'_> {
    fn insert(&mut self, _new: NewScanRun) -> Result<ScanRunId, PersistenceError> {
        let id = scan_id(0x22);
        self.store.lock().unwrap().scan_runs.push(id);
        Ok(id)
    }

    fn set_status(
        &mut self,
        _scan_run_id: ScanRunId,
        _status: ScanRunStatus,
        _completed_at_ms: Option<i64>,
        _failure_reason: Option<String>,
    ) -> Result<bool, PersistenceError> {
        Ok(true)
    }

    fn set_progress_facts(
        &mut self,
        _scan_run_id: ScanRunId,
        _entries_observed: u64,
        _entries_committed: u64,
        _issue_count: u64,
    ) -> Result<bool, PersistenceError> {
        Ok(true)
    }

    fn find_active_ownership(
        &mut self,
        _library_root_id: LibraryRootId,
    ) -> Result<Option<ActiveScanOwnership>, PersistenceError> {
        Ok(self.store.lock().unwrap().active)
    }

    fn find_last_scan(
        &mut self,
        _library_root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootLastScanSummary>, PersistenceError> {
        Ok(self.store.lock().unwrap().last_scan.clone())
    }

    fn list_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Vec<argus_application::ScanRunProjection>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

struct FakeSourceEntryRepository<'scope> {
    store: Arc<Mutex<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl SourceEntryRepository for FakeSourceEntryRepository<'_> {
    fn upsert(&mut self, _entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
        let mut store = self.store.lock().unwrap();
        store.entries += 1;
        SourceEntryId::from_bytes([store.entries as u8; 16]).map_err(|_| PersistenceError::Internal)
    }

    fn find_by_locator_key(
        &mut self,
        _library_root_id: LibraryRootId,
        _locator_key: &SourceLocatorKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        Ok(None)
    }

    fn find_native_identity(
        &mut self,
        _library_root_id: LibraryRootId,
        _provider_native_identity: &str,
    ) -> Result<NativeIdentityMatch, PersistenceError> {
        Ok(NativeIdentityMatch::None)
    }

    fn reconcile_move(
        &mut self,
        _entry: NewSourceEntry,
        _existing_source_entry_id: SourceEntryId,
    ) -> Result<SourceEntryId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn list_children(
        &mut self,
        _library_root_id: LibraryRootId,
        _parent_source_entry_id: Option<SourceEntryId>,
        _offset: u32,
        _limit: u32,
    ) -> Result<Vec<SourceEntryRecord>, PersistenceError> {
        Ok(Vec::new())
    }

    fn delete_subtree(
        &mut self,
        _library_root_id: LibraryRootId,
        _source_entry_id: SourceEntryId,
    ) -> Result<bool, PersistenceError> {
        Ok(false)
    }

    fn finalize_absent_scope(
        &mut self,
        _library_root_id: LibraryRootId,
        _parent_source_entry_id: Option<SourceEntryId>,
        _observed_scan_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        Ok(0)
    }

    fn delete_for_root(&mut self, library_root_id: LibraryRootId) -> Result<(), PersistenceError> {
        self.store
            .lock()
            .unwrap()
            .deleted_entries
            .push(library_root_id);
        Ok(())
    }
}

struct FakeLibraryScanTargetRepository<'scope> {
    store: Arc<Mutex<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl LibraryScanTargetRepository for FakeLibraryScanTargetRepository<'_> {
    fn insert(&mut self, _target: NewLibraryScanTarget) -> Result<(), PersistenceError> {
        self.store.lock().unwrap().targets += 1;
        Ok(())
    }

    fn list_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Vec<argus_application::LibraryScanTarget>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

struct FakeLibraryRootRepository<'scope> {
    store: Arc<Mutex<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl LibraryRootRepository for FakeLibraryRootRepository<'_> {
    fn insert(
        &mut self,
        _root: argus_application::NewLibraryRoot,
    ) -> Result<LibraryRootId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        let mut store = self.store.lock().unwrap();
        let existed = store.configured.contains(&root_id);
        store.deleted_roots.push(root_id);
        Ok(existed)
    }

    fn exists(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        Ok(self.store.lock().unwrap().configured.contains(&root_id))
    }

    fn set_availability(
        &mut self,
        _root_id: LibraryRootId,
        availability: LibraryRootAvailability,
    ) -> Result<bool, PersistenceError> {
        self.store.lock().unwrap().availability = Some(availability);
        Ok(true)
    }

    fn set_last_scan(
        &mut self,
        _root_id: LibraryRootId,
        summary: Option<LibraryRootLastScanSummary>,
    ) -> Result<bool, PersistenceError> {
        self.store.lock().unwrap().last_scan = summary;
        Ok(true)
    }

    fn get_scan_authority(
        &mut self,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        Ok(Some(LibraryRootScanConfiguration::new(
            root_id,
            RootLocator::from_provider("/library/Games".to_owned()),
            "Games",
            "/library/Games",
            1,
            1,
            1,
        )))
    }
}

struct FakeUnitOfWork<'scope> {
    store: Arc<Mutex<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl UnitOfWork for FakeUnitOfWork<'_> {
    type AppearanceSettingsRepository<'scope>
        = common::NoopAppearanceRepository<'scope>
    where
        Self: 'scope;
    type LibrarySourceRepository<'scope>
        = common::NoopLibrarySourceRepository<'scope>
    where
        Self: 'scope;
    type LibraryRootRepository<'scope>
        = FakeLibraryRootRepository<'scope>
    where
        Self: 'scope;
    type JobRunRepository<'scope>
        = FakeJobRunRepository<'scope>
    where
        Self: 'scope;
    type ScanRunRepository<'scope>
        = FakeScanRunRepository<'scope>
    where
        Self: 'scope;
    type SourceEntryRepository<'scope>
        = FakeSourceEntryRepository<'scope>
    where
        Self: 'scope;
    type LibraryScanTargetRepository<'scope>
        = FakeLibraryScanTargetRepository<'scope>
    where
        Self: 'scope;
    type LibraryScanAdmissionContextRepository<'scope>
        = common::NoopLibraryScanAdmissionContextRepository<'scope>
    where
        Self: 'scope;

    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
        common::NoopAppearanceRepository {
            marker: PhantomData,
        }
    }

    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
        common::NoopLibrarySourceRepository {
            marker: PhantomData,
        }
    }

    fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
        FakeLibraryRootRepository {
            store: Arc::clone(&self.store),
            marker: PhantomData,
        }
    }

    fn job_runs(&mut self) -> Self::JobRunRepository<'_> {
        FakeJobRunRepository {
            store: Arc::clone(&self.store),
            marker: PhantomData,
        }
    }

    fn scan_runs(&mut self) -> Self::ScanRunRepository<'_> {
        FakeScanRunRepository {
            store: Arc::clone(&self.store),
            marker: PhantomData,
        }
    }

    fn source_entries(&mut self) -> Self::SourceEntryRepository<'_> {
        FakeSourceEntryRepository {
            store: Arc::clone(&self.store),
            marker: PhantomData,
        }
    }

    fn library_scan_targets(&mut self) -> Self::LibraryScanTargetRepository<'_> {
        FakeLibraryScanTargetRepository {
            store: Arc::clone(&self.store),
            marker: PhantomData,
        }
    }

    fn library_scan_admission_context(
        &mut self,
    ) -> Self::LibraryScanAdmissionContextRepository<'_> {
        common::NoopLibraryScanAdmissionContextRepository {
            marker: PhantomData,
        }
    }

    fn commit(self) -> Result<(), ApplicationPortError> {
        Ok(())
    }

    fn rollback(self) -> Result<(), ApplicationPortError> {
        Ok(())
    }
}

#[derive(Clone)]
struct FakeFactory {
    store: Arc<Mutex<FakeStore>>,
}

impl UnitOfWorkFactory for FakeFactory {
    type Scope<'scope>
        = FakeUnitOfWork<'scope>
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
        operation(FakeUnitOfWork {
            store: Arc::clone(&self.store),
            marker: PhantomData,
        })
    }
}

fn fixture() -> (Arc<Mutex<FakeStore>>, FakeQueries, FakeFactory) {
    let store = FakeStore {
        configured: vec![root_id(ROOT)],
        ..FakeStore::default()
    };
    let store = Arc::new(Mutex::new(store));
    (
        Arc::clone(&store),
        FakeQueries {
            store: Arc::clone(&store),
        },
        FakeFactory {
            store: Arc::clone(&store),
        },
    )
}

fn recorder() -> FakeRecorder {
    FakeRecorder {
        store: Arc::new(Mutex::new(FakeStore::default())),
    }
}

#[test]
fn scan_admission_creates_job_scan_and_targets_atomically() {
    let (store, queries, factory) = fixture();
    let result = StartLibraryScanHandler::new(queries, factory)
        .handle(
            StartLibraryScanCommand::new(root_id(ROOT)),
            context(),
            recorder(),
        )
        .expect("admission");
    match result.outcome() {
        StartLibraryScanResult::Admitted(handle) => {
            assert_eq!(handle.operation_type(), "library_scan");
        }
        _ => panic!("expected admitted"),
    }
    let admitted = result.admitted_scan().expect("admitted payload");
    assert_eq!(admitted.plan().library_root_id(), root_id(ROOT));
    assert_eq!(
        admitted.plan().root_locator().as_provider_value(),
        "/library/Games"
    );
    assert_eq!(store.lock().unwrap().job_runs.len(), 1);
    assert_eq!(store.lock().unwrap().scan_runs.len(), 1);
    assert_eq!(store.lock().unwrap().targets, 2);
}

#[test]
fn scan_admission_returns_already_scanning_without_creating_runs() {
    let (store, queries, factory) = fixture();
    store.lock().unwrap().active = Some(ActiveScanOwnership::new(job_id(7), scan_id(8), 1));
    let result = StartLibraryScanHandler::new(queries, factory)
        .handle(
            StartLibraryScanCommand::new(root_id(ROOT)),
            context(),
            recorder(),
        )
        .expect("typed admission outcome");
    match result.outcome() {
        StartLibraryScanResult::AlreadyScanning {
            library_root_id,
            active_job_run_id,
            active_scan_run_id,
        } => {
            assert_eq!(*library_root_id, root_id(ROOT));
            assert_eq!(*active_job_run_id, job_id(7));
            assert_eq!(*active_scan_run_id, scan_id(8));
        }
        _ => panic!("expected already scanning"),
    }
    assert!(result.admitted_scan().is_none());
    assert_eq!(store.lock().unwrap().job_runs.len(), 0);
    assert_eq!(store.lock().unwrap().scan_runs.len(), 0);
}

#[test]
fn scan_admission_rejects_a_missing_root_with_typed_error() {
    let (_, queries, factory) = fixture();
    let error = StartLibraryScanHandler::new(queries, factory)
        .handle(
            StartLibraryScanCommand::new(root_id(OTHER)),
            context(),
            recorder(),
        )
        .expect_err("missing root is an application error");
    assert_eq!(error.code, ErrorCode::ConfigurationLibraryRootNotFound);
}

#[test]
fn removal_is_blocked_by_an_active_scan_with_owning_scope() {
    let (store, _, factory) = fixture();
    store.lock().unwrap().active = Some(ActiveScanOwnership::new(job_id(3), scan_id(4), 2));
    let result = RemoveLibraryRootHandler::new(factory)
        .handle(
            RemoveLibraryRootCommand::new(root_id(ROOT)),
            context(),
            recorder(),
        )
        .expect("typed removal outcome");
    assert_eq!(
        result,
        RemoveLibraryRootResult::RootHasActiveScan {
            library_root_id: root_id(ROOT),
            job_run_id: job_id(3),
            scan_run_id: scan_id(4),
            owning_job_root_count: 2,
        }
    );
    assert!(store.lock().unwrap().deleted_roots.is_empty());
}

#[derive(Clone)]
struct FakeAccess {
    scopes: Arc<Mutex<Vec<EnumerationResult>>>,
    resolve_error: Option<SourceAccessError>,
    cancel_after_root: Option<Arc<AtomicBool>>,
}

impl FakeAccess {
    fn complete(root: Vec<SourceObservation>, nested: Vec<SourceObservation>) -> Self {
        Self {
            scopes: Arc::new(Mutex::new(vec![
                EnumerationResult::new(root, EnumerationOutcome::Complete),
                EnumerationResult::new(nested, EnumerationOutcome::Complete),
            ])),
            resolve_error: None,
            cancel_after_root: None,
        }
    }
}

impl LibrarySourceAccess for FakeAccess {
    fn resolve_root(&self) -> Result<ResolvedRoot, SourceAccessError> {
        if let Some(error) = self.resolve_error {
            return Err(error);
        }
        Ok(ResolvedRoot::from_provider("root".to_owned()))
    }

    fn enumerate_root_direct_children(
        &self,
        _root: &ResolvedRoot,
        _is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError> {
        let result = self.scopes.lock().unwrap().remove(0);
        if let Some(flag) = &self.cancel_after_root {
            flag.store(true, Ordering::SeqCst);
        }
        Ok(result)
    }

    fn enumerate_direct_children(
        &self,
        _root: &ResolvedRoot,
        _relative: &RelativeSourceLocator,
        _is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError> {
        if self.scopes.lock().unwrap().is_empty() {
            return Ok(EnumerationResult::new(
                Vec::new(),
                EnumerationOutcome::Complete,
            ));
        }
        Ok(self.scopes.lock().unwrap().remove(0))
    }
}

fn observation(name: &str, kind: ObservedEntryKind) -> SourceObservation {
    SourceObservation::new(
        RelativeSourceLocator::from_provider(format!("{name}-locator")),
        SourceLocatorKey::from_provider(format!("{name}-key")),
        DiscoveryPath::new(vec![DiscoverySegment::new(name)]),
        kind,
        name,
        None,
        None,
        None,
        None,
    )
}

struct Sink {
    events: Arc<Mutex<Vec<ApplicationEvent>>>,
}

impl ApplicationEventSink for Sink {
    fn publish(&self, event: ApplicationEvent) {
        self.events.lock().unwrap().push(event);
    }
}

struct Reporter {
    reports: Arc<Mutex<Vec<JobProgress>>>,
}

impl JobProgressReporter for Reporter {
    fn report(&self, progress: JobProgress) -> Result<(), ApplicationError> {
        self.reports.lock().unwrap().push(progress);
        Ok(())
    }
}

fn plan() -> LibraryScanExecutionPlan {
    LibraryScanExecutionPlan::new(
        root_id(ROOT),
        job_id(9),
        scan_id(10),
        RootLocator::from_provider("/library/Games".to_owned()),
        "Games",
        "/library/Games",
        1,
        1,
        1,
        100,
    )
}

fn run_handler(
    store: Arc<Mutex<FakeStore>>,
    access: FakeAccess,
    cancel: Arc<AtomicBool>,
) -> (OperationCompletion, Vec<ApplicationEvent>, Vec<JobProgress>) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let reports = Arc::new(Mutex::new(Vec::new()));
    let handler = LibraryScanOperationHandler::new(
        plan(),
        access,
        FakeFactory {
            store: Arc::clone(&store),
        },
        Sink {
            events: Arc::clone(&events),
        },
        10,
    );
    let completion = handler
        .execute(
            &context(),
            &|| cancel.load(Ordering::SeqCst),
            &Reporter {
                reports: Arc::clone(&reports),
            },
        )
        .expect("handler completion");
    drop(handler);
    (
        completion,
        Arc::try_unwrap(events)
            .ok()
            .and_then(|c| c.into_inner().ok())
            .expect("events"),
        Arc::try_unwrap(reports)
            .ok()
            .and_then(|c| c.into_inner().ok())
            .expect("reports"),
    )
}

#[test]
fn complete_scan_commits_entries_publishes_events_and_reports_progress() {
    let store = Arc::new(Mutex::new(FakeStore::default()));
    let access = FakeAccess::complete(
        vec![observation("sub", ObservedEntryKind::Directory)],
        vec![observation("rom.bin", ObservedEntryKind::File)],
    );
    let (completion, events, reports) =
        run_handler(store.clone(), access, Arc::new(AtomicBool::new(false)));
    assert_eq!(completion.state(), JobRunState::Completed);
    assert_eq!(store.lock().unwrap().entries, 2);
    assert_eq!(
        store.lock().unwrap().last_scan.as_ref().unwrap().status(),
        LibraryRootLastScanStatus::Complete
    );
    assert!(events.iter().any(|event| matches!(
        event,
        ApplicationEvent::SourceEntriesChanged(SourceEntriesChanged {
            scope: SourceEntriesChangeScope::EntireRootHierarchy,
            ..
        })
    )));
    assert!(
        events
            .iter()
            .any(|event| matches!(event, ApplicationEvent::LibraryRootChanged(_)))
    );
    assert!(!reports.is_empty());
}

#[test]
fn cancelled_scan_retains_committed_observations_and_terminates_cancelled() {
    let store = Arc::new(Mutex::new(FakeStore::default()));
    let mut access = FakeAccess::complete(
        vec![observation("rom.bin", ObservedEntryKind::File)],
        Vec::new(),
    );
    let cancel = Arc::new(AtomicBool::new(false));
    access.cancel_after_root = Some(Arc::clone(&cancel));
    let (completion, events, _) = run_handler(store.clone(), access, cancel);
    assert_eq!(completion.state(), JobRunState::Cancelled);
    assert_eq!(store.lock().unwrap().entries, 1);
    assert_eq!(
        store.lock().unwrap().last_scan.as_ref().unwrap().status(),
        LibraryRootLastScanStatus::Cancelled
    );
    assert!(
        events
            .iter()
            .any(|event| matches!(event, ApplicationEvent::LibraryRootChanged(_)))
    );
}

#[test]
fn root_resolution_failure_maps_scan_to_failed_and_root_unavailable() {
    let store = Arc::new(Mutex::new(FakeStore::default()));
    let mut access = FakeAccess::complete(Vec::new(), Vec::new());
    access.resolve_error = Some(SourceAccessError::SourceUnavailable);
    let (completion, _, _) = run_handler(store.clone(), access, Arc::new(AtomicBool::new(false)));
    assert_eq!(completion.state(), JobRunState::Failed);
    assert_eq!(
        store.lock().unwrap().availability,
        Some(LibraryRootAvailability::Unavailable)
    );
    assert_eq!(
        store.lock().unwrap().last_scan.as_ref().unwrap().status(),
        LibraryRootLastScanStatus::Unavailable
    );
}

#[test]
fn link_like_entries_are_retained_but_never_traversed() {
    let store = Arc::new(Mutex::new(FakeStore::default()));
    let access = FakeAccess::complete(
        vec![observation("link", ObservedEntryKind::LinkLike)],
        Vec::new(),
    );
    let (completion, _, _) = run_handler(store.clone(), access, Arc::new(AtomicBool::new(false)));
    assert_eq!(completion.state(), JobRunState::Completed);
    // The link-like entry is retained; no directory exists to schedule
    // traversal, so exactly one entry is committed.
    assert_eq!(store.lock().unwrap().entries, 1);
}
