//! Slice 006 application-contract tests for multi-root Scan All admission.

use std::collections::HashMap;
use std::marker::PhantomData;
use std::sync::{Arc, Mutex};

mod common;

use argus_application::{
    ActiveScanOwnership, ApplicationEvent, ApplicationPortError, ErrorCode, EventRecorder,
    EventRecordingError, FailureRole, JobRunId, JobRunRepository, JobRunState, LibraryRootId,
    LibraryRootLastScanSummary, LibraryRootQueries, LibraryRootRepository,
    LibraryRootScanConfiguration, LibraryScanAdmissionContextRepository,
    LibraryScanAllRequestIdentity, LibraryScanAllRequestLookup, LibraryScanInvocationKind,
    LibraryScanTargetExclusionReason, LibraryScanTargetKind, LibraryScanTargetRepository,
    NewJobRun, NewLibraryScanAdmissionContext, NewLibraryScanTarget, NewScanRun, OperationContext,
    OperationName, PersistenceError, RootLocator, SafeContextField, SafeContextValue, ScanRunId,
    ScanRunRepository, ScanRunStatus, SourceEntryId, SourceEntryRecord, SourceEntryRepository,
    SourceLocatorKey, StartLibraryScanAllCommand, StartLibraryScanAllHandler,
    StartLibraryScanAllResult, SubsystemName, TechnicalClass, TraceId, UnitOfWork,
    UnitOfWorkFactory,
};

const ROOT_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const ROOT_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const ROOT_C: &str = "cccccccccccccccccccccccccccccccc";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("non-zero trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("scan_all").expect("operation"),
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

fn request_identity(value: &str) -> LibraryScanAllRequestIdentity {
    LibraryScanAllRequestIdentity::try_from(value).expect("request identity")
}

#[derive(Clone, Default)]
struct Store {
    configured: Vec<LibraryRootId>,
    locators: HashMap<LibraryRootId, String>,
    configurations: HashMap<LibraryRootId, LibraryRootScanConfiguration>,
    active: HashMap<LibraryRootId, ActiveScanOwnership>,
    job_runs: Vec<JobRunId>,
    scan_runs: Vec<ScanRunId>,
    targets: Vec<NewLibraryScanTarget>,
    admission_contexts: Vec<NewLibraryScanAdmissionContext>,
    events: Vec<ApplicationEvent>,
}

#[derive(Clone)]
struct FakeQueries {
    store: Arc<Mutex<Store>>,
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
        let store = self.store.lock().unwrap();
        Ok(store
            .configured
            .iter()
            .map(|root_id| {
                argus_application::LibraryRootConfiguration::new(
                    *root_id,
                    RootLocator::from_provider(store.locators[root_id].clone()),
                )
            })
            .collect())
    }

    fn get_scan_configuration(
        &self,
        _context: &OperationContext,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        Ok(self
            .store
            .lock()
            .unwrap()
            .configurations
            .get(&root_id)
            .cloned())
    }
}

#[derive(Clone)]
struct FakeRecorder {
    store: Arc<Mutex<Store>>,
}

impl EventRecorder for FakeRecorder {
    fn record(&self, event: ApplicationEvent) -> Result<(), EventRecordingError> {
        self.store.lock().unwrap().events.push(event);
        Ok(())
    }
}

struct FakeJobRunRepository<'scope> {
    store: Arc<Mutex<Store>>,
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
        _progress: &argus_application::JobProgress,
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

struct FakeScanRunRepository<'scope> {
    store: Arc<Mutex<Store>>,
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
        Err(PersistenceError::Unavailable)
    }

    fn set_progress_facts(
        &mut self,
        _scan_run_id: ScanRunId,
        _entries_observed: u64,
        _entries_committed: u64,
        _issue_count: u64,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_active_ownership(
        &mut self,
        library_root_id: LibraryRootId,
    ) -> Result<Option<ActiveScanOwnership>, PersistenceError> {
        Ok(self
            .store
            .lock()
            .unwrap()
            .active
            .get(&library_root_id)
            .copied())
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
    ) -> Result<Vec<argus_application::ScanRunProjection>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

struct FakeSourceEntryRepository<'scope> {
    marker: PhantomData<&'scope mut ()>,
}

impl SourceEntryRepository for FakeSourceEntryRepository<'_> {
    fn upsert(
        &mut self,
        _entry: argus_application::NewSourceEntry,
    ) -> Result<SourceEntryId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_by_locator_key(
        &mut self,
        _library_root_id: LibraryRootId,
        _locator_key: &SourceLocatorKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_native_identity(
        &mut self,
        _library_root_id: LibraryRootId,
        _provider_native_identity: &str,
    ) -> Result<argus_application::NativeIdentityMatch, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn reconcile_move(
        &mut self,
        _entry: argus_application::NewSourceEntry,
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
        Err(PersistenceError::Unavailable)
    }

    fn delete_subtree(
        &mut self,
        _library_root_id: LibraryRootId,
        _source_entry_id: SourceEntryId,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn finalize_absent_scope(
        &mut self,
        _library_root_id: LibraryRootId,
        _parent_source_entry_id: Option<SourceEntryId>,
        _observed_scan_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete_for_root(&mut self, _library_root_id: LibraryRootId) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

struct FakeLibraryScanTargetRepository<'scope> {
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl LibraryScanTargetRepository for FakeLibraryScanTargetRepository<'_> {
    fn insert(&mut self, target: NewLibraryScanTarget) -> Result<(), PersistenceError> {
        self.store.lock().unwrap().targets.push(target);
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
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl LibraryRootRepository for FakeLibraryRootRepository<'_> {
    fn insert(
        &mut self,
        _root: argus_application::NewLibraryRoot,
    ) -> Result<LibraryRootId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete(&mut self, _root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn exists(&mut self, root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        Ok(self.store.lock().unwrap().configured.contains(&root_id))
    }

    fn set_availability(
        &mut self,
        _root_id: LibraryRootId,
        _availability: argus_application::LibraryRootAvailability,
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

    fn get_scan_authority(
        &mut self,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        Ok(self
            .store
            .lock()
            .unwrap()
            .configurations
            .get(&root_id)
            .cloned())
    }
}

struct FakeLibraryScanAdmissionContextRepository<'scope> {
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl LibraryScanAdmissionContextRepository for FakeLibraryScanAdmissionContextRepository<'_> {
    fn insert(&mut self, new: NewLibraryScanAdmissionContext) -> Result<(), PersistenceError> {
        self.store.lock().unwrap().admission_contexts.push(new);
        Ok(())
    }

    fn get_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Option<argus_application::LibraryScanAdmissionContext>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

struct FakeUnitOfWork<'scope> {
    store: Arc<Mutex<Store>>,
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
        = FakeLibraryScanAdmissionContextRepository<'scope>
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
        FakeLibraryScanAdmissionContextRepository {
            store: Arc::clone(&self.store),
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
    store: Arc<Mutex<Store>>,
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

#[derive(Clone)]
struct NoopLookup;

impl LibraryScanAllRequestLookup for NoopLookup {
    fn find_existing(
        &self,
        _context: &OperationContext,
        _request_identity: &LibraryScanAllRequestIdentity,
    ) -> Result<Option<StartLibraryScanAllResult>, argus_application::ApplicationError> {
        Ok(None)
    }
}

fn scan_configuration(root_id: LibraryRootId) -> LibraryRootScanConfiguration {
    LibraryRootScanConfiguration::new(
        root_id,
        RootLocator::from_provider(format!("/library/{}", root_id)),
        root_id.to_string(),
        format!("/library/{}", root_id),
        1,
        1,
        1,
    )
}

fn fixture(configured: &[&str]) -> (Arc<Mutex<Store>>, FakeQueries, FakeFactory, FakeRecorder) {
    let mut store = Store {
        configured: configured.iter().map(|value| root_id(value)).collect(),
        ..Store::default()
    };
    for value in configured {
        let id = root_id(value);
        store.locators.insert(id, format!("/library/{id}"));
        store.configurations.insert(id, scan_configuration(id));
    }
    let store = Arc::new(Mutex::new(store));
    (
        Arc::clone(&store),
        FakeQueries {
            store: Arc::clone(&store),
        },
        FakeFactory {
            store: Arc::clone(&store),
        },
        FakeRecorder {
            store: Arc::clone(&store),
        },
    )
}

#[test]
fn scan_all_admits_all_eligible_roots_in_canonical_order() {
    let (store, queries, factory, recorder) = fixture(&[ROOT_C, ROOT_A, ROOT_B]);
    let result = StartLibraryScanAllHandler::new(queries, factory)
        .handle(
            StartLibraryScanAllCommand::new(request_identity("request-1")),
            context(),
            &NoopLookup,
            recorder,
        )
        .expect("admission");

    let outcome = result.outcome();
    assert!(matches!(
        outcome,
        StartLibraryScanAllResult::Admitted { .. }
    ));
    assert_eq!(
        outcome.admitted_roots(),
        &[root_id(ROOT_A), root_id(ROOT_B), root_id(ROOT_C)]
    );
    assert!(outcome.exclusions().is_empty());

    let admitted = result.admitted_job().expect("fresh payload");
    let plans = admitted.plans();
    assert_eq!(plans.len(), 3);
    assert_eq!(plans[0].library_root_id(), root_id(ROOT_A));
    assert_eq!(plans[1].library_root_id(), root_id(ROOT_B));
    assert_eq!(plans[2].library_root_id(), root_id(ROOT_C));

    let store = store.lock().unwrap();
    assert_eq!(store.job_runs.len(), 1);
    assert_eq!(store.scan_runs.len(), 3);
    assert_eq!(store.admission_contexts.len(), 1);
    assert_eq!(
        store.admission_contexts[0].invocation_kind(),
        LibraryScanInvocationKind::InitialScanAll
    );
    assert_eq!(store.targets.len(), 6);
}

#[test]
fn scan_all_preserves_typed_exclusions_and_partial_admission() {
    let (store, queries, factory, recorder) = fixture(&[ROOT_A, ROOT_B]);
    {
        let mut store = store.lock().unwrap();
        store.active.insert(
            root_id(ROOT_B),
            ActiveScanOwnership::new(job_id(7), scan_id(8), 1),
        );
    }

    let result = StartLibraryScanAllHandler::new(queries, factory)
        .handle(
            StartLibraryScanAllCommand::new(request_identity("request-2")),
            context(),
            &NoopLookup,
            recorder,
        )
        .expect("admission");

    let outcome = result.outcome();
    assert_eq!(outcome.admitted_roots(), &[root_id(ROOT_A)]);
    let exclusions = outcome.exclusions();
    assert_eq!(exclusions.len(), 1);
    assert_eq!(exclusions[0].library_root_id(), root_id(ROOT_B));
    assert_eq!(
        exclusions[0].reason(),
        LibraryScanTargetExclusionReason::AlreadyScanning
    );
    assert_eq!(exclusions[0].active_job_run_id(), Some(job_id(7)));
    assert_eq!(exclusions[0].active_scan_run_id(), Some(scan_id(8)));
    assert!(exclusions[0].application_error().is_none());

    let store = store.lock().unwrap();
    assert_eq!(store.targets.len(), 4);
    assert_eq!(store.targets[0].kind(), LibraryScanTargetKind::Requested);
    assert_eq!(store.targets[0].library_root_id(), root_id(ROOT_A));
    assert_eq!(store.targets[1].kind(), LibraryScanTargetKind::Admitted);
    assert_eq!(store.targets[1].library_root_id(), root_id(ROOT_A));
    assert_eq!(store.targets[2].kind(), LibraryScanTargetKind::Requested);
    assert_eq!(store.targets[2].library_root_id(), root_id(ROOT_B));
    assert_eq!(store.targets[3].kind(), LibraryScanTargetKind::Excluded);
    assert_eq!(store.targets[3].library_root_id(), root_id(ROOT_B));
}

#[test]
fn scan_all_invalid_configuration_carries_bounded_application_error() {
    let (store, queries, factory, recorder) = fixture(&[ROOT_A]);
    {
        let mut store = store.lock().unwrap();
        store.configurations.remove(&root_id(ROOT_A));
    }

    let result = StartLibraryScanAllHandler::new(queries, factory)
        .handle(
            StartLibraryScanAllCommand::new(request_identity("request-3")),
            context(),
            &NoopLookup,
            recorder,
        )
        .expect("typed admission outcome");

    let outcome = result.outcome();
    assert!(matches!(
        outcome,
        StartLibraryScanAllResult::NothingEligible { .. }
    ));
    let exclusions = outcome.exclusions();
    assert_eq!(exclusions.len(), 1);
    let error = exclusions[0]
        .application_error()
        .expect("invalid configuration error");
    assert_eq!(error.code, ErrorCode::ConfigurationInvalid);
    assert_eq!(error.message_key.as_str(), "errors.configuration.invalid");
    assert_eq!(
        error.safe_context.get(&SafeContextField::TechnicalClass),
        Some(&SafeContextValue::TechnicalClass(
            TechnicalClass::ConfigurationInvalid
        ))
    );
    assert_eq!(
        error.safe_context.get(&SafeContextField::FailureRole),
        Some(&SafeContextValue::FailureRole(FailureRole::Primary))
    );
    assert_eq!(store.lock().unwrap().job_runs.len(), 0);
}

#[test]
fn scan_all_nothing_eligible_creates_no_job() {
    let (store, queries, factory, recorder) = fixture(&[ROOT_A]);
    {
        let mut store = store.lock().unwrap();
        store.active.insert(
            root_id(ROOT_A),
            ActiveScanOwnership::new(job_id(3), scan_id(4), 1),
        );
    }

    let result = StartLibraryScanAllHandler::new(queries, factory)
        .handle(
            StartLibraryScanAllCommand::new(request_identity("request-4")),
            context(),
            &NoopLookup,
            recorder,
        )
        .expect("admission");

    assert!(matches!(
        result.outcome(),
        StartLibraryScanAllResult::NothingEligible { .. }
    ));
    let store = store.lock().unwrap();
    assert!(store.job_runs.is_empty());
    assert!(store.scan_runs.is_empty());
    assert!(store.targets.is_empty());
}

#[derive(Clone)]
struct ReplayLookup {
    outcome: StartLibraryScanAllResult,
}

impl LibraryScanAllRequestLookup for ReplayLookup {
    fn find_existing(
        &self,
        _context: &OperationContext,
        _request_identity: &LibraryScanAllRequestIdentity,
    ) -> Result<Option<StartLibraryScanAllResult>, argus_application::ApplicationError> {
        Ok(Some(self.outcome.clone()))
    }
}

#[test]
fn scan_all_replay_returns_existing_outcome_without_allocating_a_job() {
    let (store, queries, factory, recorder) = fixture(&[ROOT_A]);
    let replay = StartLibraryScanAllResult::Admitted {
        operation_handle: argus_application::OperationHandle::new(job_id(9), "library_scan"),
        admitted_roots: vec![root_id(ROOT_A)],
        exclusions: Vec::new(),
    };
    let lookup = ReplayLookup {
        outcome: replay.clone(),
    };

    let result = StartLibraryScanAllHandler::new(queries, factory)
        .handle(
            StartLibraryScanAllCommand::new(request_identity("request-5")),
            context(),
            &lookup,
            recorder,
        )
        .expect("replay");

    assert_eq!(result.outcome(), &replay);
    assert!(result.admitted_job().is_none());
    let store = store.lock().unwrap();
    assert!(store.job_runs.is_empty());
    assert!(store.scan_runs.is_empty());
    assert!(store.targets.is_empty());
}

#[test]
fn scan_all_request_identity_rejects_empty_and_invalid_values() {
    assert_eq!(
        LibraryScanAllRequestIdentity::try_from(""),
        Err(argus_application::LibraryScanAllRequestIdentityError::Empty)
    );
    assert_eq!(
        LibraryScanAllRequestIdentity::try_from("contains spaces"),
        Err(argus_application::LibraryScanAllRequestIdentityError::InvalidCharacter)
    );
    assert_eq!(
        LibraryScanAllRequestIdentity::try_from("request-1")
            .unwrap()
            .as_str(),
        "request-1"
    );
}

#[test]
fn library_scan_invocation_kind_round_trips_scan_all_values() {
    for (kind, value) in [
        (
            LibraryScanInvocationKind::InitialSingleRoot,
            "initial_single_root",
        ),
        (
            LibraryScanInvocationKind::RetrySingleRoot,
            "retry_single_root",
        ),
        (
            LibraryScanInvocationKind::InitialScanAll,
            "initial_scan_all",
        ),
        (LibraryScanInvocationKind::RetryScanAll, "retry_scan_all"),
    ] {
        assert_eq!(kind.as_str(), value);
        assert_eq!(LibraryScanInvocationKind::try_from(value), Ok(kind));
    }
    assert_eq!(
        LibraryScanInvocationKind::try_from("unknown"),
        Err(argus_application::LibraryScanInvocationKindParseError)
    );
}

#[test]
fn aggregate_full_clean_admission_is_completed() {
    use argus_application::{LibraryScanChildCompletion, aggregate_library_scan_state};
    assert_eq!(
        aggregate_library_scan_state(
            2,
            2,
            &[
                LibraryScanChildCompletion::Complete,
                LibraryScanChildCompletion::Complete,
            ],
        ),
        JobRunState::Completed
    );
}

#[test]
fn aggregate_partial_admission_is_completed_with_issues() {
    use argus_application::{LibraryScanChildCompletion, aggregate_library_scan_state};
    assert_eq!(
        aggregate_library_scan_state(
            3,
            2,
            &[
                LibraryScanChildCompletion::Complete,
                LibraryScanChildCompletion::Complete,
            ],
        ),
        JobRunState::CompletedWithIssues
    );
}

#[test]
fn aggregate_mixed_and_partial_children_are_completed_with_issues() {
    use argus_application::{LibraryScanChildCompletion, aggregate_library_scan_state};
    assert_eq!(
        aggregate_library_scan_state(
            2,
            2,
            &[
                LibraryScanChildCompletion::Complete,
                LibraryScanChildCompletion::Failed,
            ],
        ),
        JobRunState::CompletedWithIssues
    );
    assert_eq!(
        aggregate_library_scan_state(
            2,
            2,
            &[
                LibraryScanChildCompletion::Partial,
                LibraryScanChildCompletion::Partial,
            ],
        ),
        JobRunState::CompletedWithIssues
    );
}

#[test]
fn aggregate_no_meaningful_success_is_failed() {
    use argus_application::{LibraryScanChildCompletion, aggregate_library_scan_state};
    assert_eq!(
        aggregate_library_scan_state(
            2,
            2,
            &[
                LibraryScanChildCompletion::Failed,
                LibraryScanChildCompletion::Failed,
            ],
        ),
        JobRunState::Failed
    );
    assert_eq!(aggregate_library_scan_state(1, 1, &[]), JobRunState::Failed);
}

#[test]
fn aggregate_cancelled_and_abandoned_children_dominate() {
    use argus_application::{LibraryScanChildCompletion, aggregate_library_scan_state};
    assert_eq!(
        aggregate_library_scan_state(
            2,
            2,
            &[
                LibraryScanChildCompletion::Complete,
                LibraryScanChildCompletion::Cancelled,
            ],
        ),
        JobRunState::Cancelled
    );
    assert_eq!(
        aggregate_library_scan_state(
            2,
            2,
            &[
                LibraryScanChildCompletion::Complete,
                LibraryScanChildCompletion::Abandoned,
            ],
        ),
        JobRunState::Abandoned
    );
}
