//! Slice 003 application-contract tests for authoritative source-graph
//! reconciliation: conservative identity preservation, deferred exact-scope
//! absence finalization, stale-plan suppression, availability evidence, and
//! terminal aggregation.

use std::collections::VecDeque;
use std::marker::PhantomData;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use argus_application::{
    ActiveScanOwnership, ApplicationError, ApplicationEvent, ApplicationEventSink,
    ApplicationPortError, BackgroundOperationHandler, DiscoveryPath, DiscoverySegment,
    EnumerationOutcome, EnumerationResult, JobProgress, JobProgressReporter, JobRunId,
    JobRunRepository, JobRunState, LibraryRootAvailability, LibraryRootId,
    LibraryRootLastScanStatus, LibraryRootLastScanSummary, LibraryRootRepository,
    LibraryRootScanConfiguration, LibraryScanExecutionPlan, LibraryScanOperationHandler,
    LibrarySourceAccess, NativeIdentityMatch, NewJobRun, NewLibraryRoot, NewScanRun,
    NewSourceEntry, ObservedEntryKind, OperationCompletion, OperationContext, OperationName,
    PersistenceError, RelativeSourceLocator, ResolvedRoot, RootLocator, ScanRunId,
    ScanRunRepository, ScanRunStatus, SourceAccessError, SourceEntriesChangeScope,
    SourceEntriesChanged, SourceEntryClassification, SourceEntryId, SourceEntryKind,
    SourceEntryRecord, SourceEntryRepository, SourceLocatorKey, SourceObservation, SubsystemName,
    TraceId, UnitOfWork, UnitOfWorkFactory,
};

const ROOT: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("non-zero trace"),
        SubsystemName::try_from("test").expect("subsystem"),
        OperationName::try_from("slice003").expect("operation"),
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

fn entry_id(value: u8) -> SourceEntryId {
    SourceEntryId::from_bytes([value; 16]).expect("entry id")
}

/// One persisted entry in the in-memory test store.
#[derive(Clone, Debug, PartialEq, Eq)]
struct StoredEntry {
    id: SourceEntryId,
    root: LibraryRootId,
    parent: Option<SourceEntryId>,
    relative_locator: String,
    locator_key: String,
    display_name: String,
    display_location: String,
    kind: SourceEntryKind,
    classification: SourceEntryClassification,
    provider_native_identity: Option<String>,
    source_fingerprint: Option<String>,
    last_observed_scan_id: Option<ScanRunId>,
    created_order: usize,
}

/// In-memory authoritative store shared across repeated scans.
struct Store {
    entries: Vec<StoredEntry>,
    next_entry_counter: u8,
    created_entries: usize,
    deleted_entries: usize,
    deleted_roots: Vec<LibraryRootId>,
    availability: Option<LibraryRootAvailability>,
    last_scan: Option<LibraryRootLastScanSummary>,
    active: Option<ActiveScanOwnership>,
    job_runs: Vec<JobRunId>,
    scan_runs: Vec<ScanRunId>,
    source_revision: u32,
    root_revision: u32,
    policy_revision: u32,
    commits: usize,
}

impl Default for Store {
    fn default() -> Self {
        Self {
            entries: Vec::new(),
            next_entry_counter: 0,
            created_entries: 0,
            deleted_entries: 0,
            deleted_roots: Vec::new(),
            availability: None,
            last_scan: None,
            active: None,
            job_runs: Vec::new(),
            scan_runs: Vec::new(),
            source_revision: 1,
            root_revision: 1,
            policy_revision: 1,
            commits: 0,
        }
    }
}

impl Store {
    fn entry_by_locator(&self, root: LibraryRootId, locator_key: &str) -> Option<&StoredEntry> {
        self.entries
            .iter()
            .find(|entry| entry.root == root && entry.locator_key == locator_key)
    }

    fn next_id(&mut self) -> SourceEntryId {
        self.next_entry_counter = self.next_entry_counter.wrapping_add(1);
        assert_ne!(self.next_entry_counter, 0, "entry id counter exhausted");
        entry_id(self.next_entry_counter)
    }
}

/// Transaction-scoped fake source-entry repository over [`Store`].
struct FakeSourceEntryRepository<'scope> {
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl SourceEntryRepository for FakeSourceEntryRepository<'_> {
    fn upsert(&mut self, entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
        let mut store = self.store.lock().expect("store lock");
        if let Some(existing) = store.entry_by_locator(
            entry.library_root_id(),
            entry.locator_key().as_provider_value(),
        ) {
            let existing_id = existing.id;
            let order = existing.created_order;
            let index = store
                .entries
                .iter()
                .position(|candidate| candidate.id == existing_id)
                .expect("entry exists");
            store.entries[index] = stored_entry_from(entry, existing_id, order);
            return Ok(existing_id);
        }
        let id = store.next_id();
        let order = store.created_entries;
        store.created_entries += 1;
        store.entries.push(stored_entry_from(entry, id, order));
        Ok(id)
    }

    fn delete_for_root(&mut self, library_root_id: LibraryRootId) -> Result<(), PersistenceError> {
        let mut store = self.store.lock().expect("store lock");
        store.entries.retain(|entry| entry.root != library_root_id);
        store.deleted_roots.push(library_root_id);
        Ok(())
    }

    fn find_by_locator_key(
        &mut self,
        library_root_id: LibraryRootId,
        locator_key: &SourceLocatorKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        let store = self.store.lock().expect("store lock");
        Ok(store
            .entry_by_locator(library_root_id, locator_key.as_provider_value())
            .map(record_from_stored))
    }

    fn find_native_identity(
        &mut self,
        library_root_id: LibraryRootId,
        provider_native_identity: &str,
    ) -> Result<NativeIdentityMatch, PersistenceError> {
        let store = self.store.lock().expect("store lock");
        let mut candidates = store.entries.iter().filter(|entry| {
            entry.root == library_root_id
                && entry.provider_native_identity.as_deref() == Some(provider_native_identity)
        });
        match (candidates.next(), candidates.next()) {
            (Some(only), None) => Ok(NativeIdentityMatch::Unique(record_from_stored(only))),
            (Some(_), Some(_)) => Ok(NativeIdentityMatch::Ambiguous),
            (None, _) => Ok(NativeIdentityMatch::None),
        }
    }

    fn reconcile_move(
        &mut self,
        entry: NewSourceEntry,
        existing_source_entry_id: SourceEntryId,
    ) -> Result<SourceEntryId, PersistenceError> {
        let mut store = self.store.lock().expect("store lock");
        let index = store
            .entries
            .iter()
            .position(|candidate| {
                candidate.id == existing_source_entry_id
                    && candidate.root == entry.library_root_id()
            })
            .ok_or(PersistenceError::Conflict)?;
        let order = store.entries[index].created_order;
        store.entries[index] = stored_entry_from(entry, existing_source_entry_id, order);
        Ok(existing_source_entry_id)
    }

    fn list_children(
        &mut self,
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<SourceEntryRecord>, PersistenceError> {
        let store = self.store.lock().expect("store lock");
        let mut entries: Vec<SourceEntryRecord> = store
            .entries
            .iter()
            .filter(|entry| entry.root == library_root_id && entry.parent == parent_source_entry_id)
            .map(record_from_stored)
            .collect();
        entries.sort_by_key(|entry| entry.source_entry_id().to_string());
        Ok(entries
            .into_iter()
            .skip(offset as usize)
            .take(limit as usize)
            .collect())
    }

    fn delete_subtree(
        &mut self,
        library_root_id: LibraryRootId,
        source_entry_id: SourceEntryId,
    ) -> Result<bool, PersistenceError> {
        let mut store = self.store.lock().expect("store lock");
        let existed = store
            .entries
            .iter()
            .any(|entry| entry.id == source_entry_id && entry.root == library_root_id);
        if existed {
            let ids = subtree_ids(&store.entries, source_entry_id);
            let previous = store.entries.len();
            store
                .entries
                .retain(|entry| entry.root != library_root_id || !ids.contains(&entry.id));
            store.deleted_entries += previous - store.entries.len();
        }
        Ok(existed)
    }

    fn finalize_absent_scope(
        &mut self,
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        observed_scan_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        let mut store = self.store.lock().expect("store lock");
        let mut deleted = 0_u64;
        let absent: Vec<SourceEntryId> = store
            .entries
            .iter()
            .filter(|entry| {
                entry.root == library_root_id
                    && entry.parent == parent_source_entry_id
                    && entry.last_observed_scan_id != Some(observed_scan_id)
            })
            .map(|entry| entry.id)
            .collect();
        for id in absent {
            let ids = subtree_ids(&store.entries, id);
            let previous = store.entries.len();
            store
                .entries
                .retain(|entry| entry.root != library_root_id || !ids.contains(&entry.id));
            deleted += (previous - store.entries.len()) as u64;
        }
        store.deleted_entries += deleted as usize;
        Ok(deleted)
    }
}

fn stored_entry_from(
    entry: NewSourceEntry,
    id: SourceEntryId,
    created_order: usize,
) -> StoredEntry {
    StoredEntry {
        id,
        root: entry.library_root_id(),
        parent: entry.parent_source_entry_id(),
        relative_locator: entry.relative_locator().as_provider_value().to_owned(),
        locator_key: entry.locator_key().as_provider_value().to_owned(),
        display_name: entry.display_name().to_owned(),
        display_location: entry.display_location().to_owned(),
        kind: entry.kind(),
        classification: entry.classification(),
        provider_native_identity: entry.provider_native_identity().map(str::to_owned),
        source_fingerprint: entry.source_fingerprint().map(str::to_owned),
        last_observed_scan_id: Some(entry.last_observed_scan_id()),
        created_order,
    }
}

fn record_from_stored(entry: &StoredEntry) -> SourceEntryRecord {
    SourceEntryRecord::new(
        entry.id,
        entry.parent,
        RelativeSourceLocator::from_provider(entry.relative_locator.clone()),
        SourceLocatorKey::from_provider(entry.locator_key.clone()),
        entry.display_name.clone(),
        entry.display_location.clone(),
        entry.kind,
        entry.classification,
        entry.provider_native_identity.clone(),
        entry.source_fingerprint.clone(),
        entry
            .last_observed_scan_id
            .expect("stored entries are observed"),
    )
}

/// Collects one subtree (root plus current descendants) by stable identity.
fn subtree_ids(entries: &[StoredEntry], root_id: SourceEntryId) -> Vec<SourceEntryId> {
    let mut result = vec![root_id];
    let mut frontier = vec![root_id];
    while let Some(parent) = frontier.pop() {
        for entry in entries.iter().filter(|entry| entry.parent == Some(parent)) {
            result.push(entry.id);
            frontier.push(entry.id);
        }
    }
    result
}

/// Transaction-scoped fake library-root repository over [`Store`].
struct FakeLibraryRootRepository<'scope> {
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl LibraryRootRepository for FakeLibraryRootRepository<'_> {
    fn insert(&mut self, _root: NewLibraryRoot) -> Result<LibraryRootId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete(&mut self, _root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn exists(&mut self, _root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        Ok(true)
    }

    fn set_availability(
        &mut self,
        _root_id: LibraryRootId,
        availability: LibraryRootAvailability,
    ) -> Result<bool, PersistenceError> {
        self.store.lock().expect("store lock").availability = Some(availability);
        Ok(true)
    }

    fn set_last_scan(
        &mut self,
        _root_id: LibraryRootId,
        summary: Option<LibraryRootLastScanSummary>,
    ) -> Result<bool, PersistenceError> {
        self.store.lock().expect("store lock").last_scan = summary;
        Ok(true)
    }

    fn get_scan_authority(
        &mut self,
        root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        let store = self.store.lock().expect("store lock");
        Ok(Some(LibraryRootScanConfiguration::new(
            root_id,
            RootLocator::from_provider("/library/Games".to_owned()),
            "Games",
            "/library/Games",
            store.root_revision,
            store.source_revision,
            store.policy_revision,
        )))
    }
}

/// Transaction-scoped fake job-run repository over [`Store`].
struct FakeJobRunRepository<'scope> {
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl JobRunRepository for FakeJobRunRepository<'_> {
    fn insert(&mut self, _new: NewJobRun) -> Result<JobRunId, PersistenceError> {
        let id = job_id(0x11);
        self.store.lock().expect("store lock").job_runs.push(id);
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

/// Transaction-scoped fake scan-run repository over [`Store`].
struct FakeScanRunRepository<'scope> {
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl ScanRunRepository for FakeScanRunRepository<'_> {
    fn insert(&mut self, _new: NewScanRun) -> Result<ScanRunId, PersistenceError> {
        let id = scan_id(0x22);
        self.store.lock().expect("store lock").scan_runs.push(id);
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
        Ok(self.store.lock().expect("store lock").active)
    }

    fn find_last_scan(
        &mut self,
        _library_root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootLastScanSummary>, PersistenceError> {
        Ok(self.store.lock().expect("store lock").last_scan.clone())
    }

    fn list_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Vec<argus_application::ScanRunProjection>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

struct FakeUnitOfWork<'scope> {
    store: Arc<Mutex<Store>>,
    marker: PhantomData<&'scope mut ()>,
}

impl UnitOfWork for FakeUnitOfWork<'_> {
    type AppearanceSettingsRepository<'scope>
        = NoopAppearanceRepository<'scope>
    where
        Self: 'scope;
    type LibrarySourceRepository<'scope>
        = NoopLibrarySourceRepository<'scope>
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
        = NoopLibraryScanTargetRepository<'scope>
    where
        Self: 'scope;
    type LibraryScanAdmissionContextRepository<'scope>
        = NoopLibraryScanAdmissionContextRepository<'scope>
    where
        Self: 'scope;

    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
        NoopAppearanceRepository {
            marker: PhantomData,
        }
    }

    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
        NoopLibrarySourceRepository {
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
        NoopLibraryScanTargetRepository {
            marker: PhantomData,
        }
    }

    fn library_scan_admission_context(
        &mut self,
    ) -> Self::LibraryScanAdmissionContextRepository<'_> {
        NoopLibraryScanAdmissionContextRepository {
            marker: PhantomData,
        }
    }

    fn commit(self) -> Result<(), ApplicationPortError> {
        self.store.lock().expect("store lock").commits += 1;
        Ok(())
    }

    fn rollback(self) -> Result<(), ApplicationPortError> {
        Ok(())
    }
}

#[derive(Clone, Default)]
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

/// Fake provider access that replays a fixed script of enumeration results.
struct FakeAccess {
    script: Arc<Mutex<VecDeque<EnumerationResult>>>,
    resolve_error: Option<SourceAccessError>,
    cancel_after_root: Option<Arc<AtomicBool>>,
}

impl FakeAccess {
    fn new(scopes: Vec<EnumerationResult>) -> Self {
        Self {
            script: Arc::new(Mutex::new(scopes.into())),
            resolve_error: None,
            cancel_after_root: None,
        }
    }

    fn with_cancel_after_root(mut self, flag: Arc<AtomicBool>) -> Self {
        self.cancel_after_root = Some(flag);
        self
    }

    fn next(&self) -> Result<EnumerationResult, SourceAccessError> {
        self.script
            .lock()
            .expect("script lock")
            .pop_front()
            .ok_or(SourceAccessError::InvalidResponse)
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
        let result = self.next()?;
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
        self.next()
    }
}

/// One normalized observation with controllable weak facts.
#[allow(clippy::too_many_arguments)]
fn observation(
    name: &str,
    locator: &str,
    kind: ObservedEntryKind,
    native_identity: Option<&str>,
    fingerprint: Option<&str>,
) -> SourceObservation {
    SourceObservation::new(
        RelativeSourceLocator::from_provider(locator.to_owned()),
        SourceLocatorKey::from_provider(locator.to_owned()),
        DiscoveryPath::new(vec![DiscoverySegment::new(name)]),
        kind,
        name,
        native_identity.map(str::to_owned),
        fingerprint.map(str::to_owned),
        None,
        None,
    )
}

fn complete(observations: Vec<SourceObservation>) -> EnumerationResult {
    EnumerationResult::new(observations, EnumerationOutcome::Complete)
}

fn outcome(outcome: EnumerationOutcome, observations: Vec<SourceObservation>) -> EnumerationResult {
    EnumerationResult::new(observations, outcome)
}

fn plan(scan_index: u8) -> LibraryScanExecutionPlan {
    LibraryScanExecutionPlan::new(
        root_id(ROOT),
        job_id(9),
        scan_id(10 + scan_index),
        RootLocator::from_provider("/library/Games".to_owned()),
        "Games",
        "/library/Games",
        1,
        1,
        1,
        100,
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

fn run_scan(
    store: Arc<Mutex<Store>>,
    access: FakeAccess,
    scan_index: u8,
    cancel: Arc<AtomicBool>,
) -> (OperationCompletion, Vec<ApplicationEvent>, Vec<JobProgress>) {
    let events = Arc::new(Mutex::new(Vec::new()));
    let reports = Arc::new(Mutex::new(Vec::new()));
    let handler = LibraryScanOperationHandler::new(
        plan(scan_index),
        access,
        FakeFactory {
            store: Arc::clone(&store),
        },
        Sink {
            events: Arc::clone(&events),
        },
        100,
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
            .and_then(|channel| channel.into_inner().ok())
            .expect("events"),
        Arc::try_unwrap(reports)
            .ok()
            .and_then(|channel| channel.into_inner().ok())
            .expect("reports"),
    )
}

fn store_snapshot(store: &Arc<Mutex<Store>>) -> Vec<StoredEntry> {
    store.lock().expect("store lock").entries.clone()
}

#[test]
fn unchanged_rescan_updates_in_place_and_preserves_every_source_entry_id() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "a.bin",
            "a.bin",
            ObservedEntryKind::File,
            Some("native-a"),
            Some("fp"),
        )])]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);
    let first_id = store_snapshot(&store)[0].id;

    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "a.bin",
            "a.bin",
            ObservedEntryKind::File,
            Some("native-a"),
            Some("fp-v2"),
        )])]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::Completed);
    let snapshot = store_snapshot(&store);
    assert_eq!(snapshot.len(), 1, "unchanged scan keeps exactly one entry");
    assert_eq!(
        snapshot[0].id, first_id,
        "exact locator update preserves identity"
    );
    assert_eq!(
        snapshot[0].last_observed_scan_id,
        Some(scan_id(12)),
        "last observed scan refreshes to the second scan"
    );
}

#[test]
fn unique_native_identity_preserves_entry_id_across_a_move_between_scopes() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![
            complete(vec![
                observation(
                    "old.bin",
                    "old.bin",
                    ObservedEntryKind::File,
                    Some("n1"),
                    Some("fp"),
                ),
                observation("Sub", "Sub", ObservedEntryKind::Directory, Some("d1"), None),
            ]),
            complete(vec![observation(
                "nested.txt",
                "Sub/nested.txt",
                ObservedEntryKind::File,
                Some("n2"),
                Some("fp"),
            )]),
        ]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);
    let old_id = store_snapshot(&store)
        .iter()
        .find(|entry| entry.display_name == "old.bin")
        .expect("old entry")
        .id;

    // The file moved from the root scope into Sub; the old locator is absent
    // from the second scan, so the sole native-identity candidate is unique
    // and eligible. Finalization of the completed root scope runs only after
    // the new observation is committed.
    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![
            complete(vec![observation(
                "Sub",
                "Sub",
                ObservedEntryKind::Directory,
                Some("d1"),
                None,
            )]),
            complete(vec![
                observation(
                    "nested.txt",
                    "Sub/nested.txt",
                    ObservedEntryKind::File,
                    Some("n2"),
                    Some("fp"),
                ),
                observation(
                    "old.bin",
                    "Sub/old.bin",
                    ObservedEntryKind::File,
                    Some("n1"),
                    Some("fp"),
                ),
            ]),
        ]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::Completed);
    let snapshot = store_snapshot(&store);
    let moved = snapshot
        .iter()
        .find(|entry| entry.display_name == "old.bin")
        .expect("moved entry retained");
    assert_eq!(
        moved.id, old_id,
        "unique native identity preserves SourceEntryId"
    );
    assert_eq!(moved.relative_locator, "Sub/old.bin");
    let sub = snapshot
        .iter()
        .find(|entry| entry.display_name == "Sub")
        .expect("sub directory");
    assert_eq!(
        moved.parent,
        Some(sub.id),
        "move reparents to the new scope"
    );
    assert_eq!(
        snapshot.len(),
        3,
        "no duplicate or deletion for a unique move"
    );
}

#[test]
fn multiple_persisted_native_identity_candidates_are_ambiguous_and_create() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![
            observation(
                "a.bin",
                "a.bin",
                ObservedEntryKind::File,
                Some("same"),
                Some("fp"),
            ),
            observation(
                "b.bin",
                "b.bin",
                ObservedEntryKind::File,
                Some("same"),
                Some("fp"),
            ),
        ])]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);
    let a_id = store_snapshot(&store)
        .iter()
        .find(|entry| entry.display_name == "a.bin")
        .expect("a")
        .id;
    let b_id = store_snapshot(&store)
        .iter()
        .find(|entry| entry.display_name == "b.bin")
        .expect("b")
        .id;
    assert_ne!(a_id, b_id);

    // A third location shares the identity while b.bin disappears. Two total
    // persisted candidates exist for the identity, so no continuity is
    // guessed: c.bin is a new entry and b.bin is removed by the completed
    // root scope's authoritative finalization.
    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![
            observation(
                "a.bin",
                "a.bin",
                ObservedEntryKind::File,
                Some("same"),
                Some("fp"),
            ),
            observation(
                "c.bin",
                "c.bin",
                ObservedEntryKind::File,
                Some("same"),
                Some("fp"),
            ),
        ])]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::Completed);
    let snapshot = store_snapshot(&store);
    let c = snapshot
        .iter()
        .find(|entry| entry.display_name == "c.bin")
        .expect("c entry");
    assert_ne!(c.id, a_id, "ambiguous identity creates a new entry");
    assert_ne!(c.id, b_id);
    assert!(
        snapshot.iter().all(|entry| entry.display_name != "b.bin"),
        "ambiguous prior entry is removed by authoritative scope finalization"
    );
}

#[test]
fn sole_candidate_already_observed_this_scan_never_gets_reparented() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "a.bin",
            "a.bin",
            ObservedEntryKind::File,
            Some("same"),
            Some("fp"),
        )])]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);
    let a_id = store_snapshot(&store)[0].id;

    // a.bin is observed at its exact locator first, then a second location
    // reports the same identity. The sole candidate was already positively
    // observed by this scan, so it is ineligible; c.bin must be created
    // rather than guessed as a move.
    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![
            observation(
                "a.bin",
                "a.bin",
                ObservedEntryKind::File,
                Some("same"),
                Some("fp"),
            ),
            observation(
                "c.bin",
                "c.bin",
                ObservedEntryKind::File,
                Some("same"),
                Some("fp"),
            ),
        ])]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::Completed);
    let snapshot = store_snapshot(&store);
    let c = snapshot
        .iter()
        .find(|entry| entry.display_name == "c.bin")
        .expect("c entry");
    assert_ne!(c.id, a_id, "already-observed candidate is never reparented");
    assert_eq!(
        snapshot
            .iter()
            .find(|entry| entry.id == a_id)
            .expect("a retained")
            .relative_locator,
        "a.bin"
    );
}

#[test]
fn weak_heuristics_never_preserve_identity() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "game.bin",
            "game.bin",
            ObservedEntryKind::File,
            None,
            Some("v1:file:100:42"),
        )])]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);
    let old_id = store_snapshot(&store)[0].id;

    // Same size/mtime fingerprint and same filename at a new locator, with no
    // provider-native identity: never a move.
    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "game.bin",
            "renamed/game.bin",
            ObservedEntryKind::File,
            None,
            Some("v1:file:100:42"),
        )])]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::Completed);
    let snapshot = store_snapshot(&store);
    let renamed = snapshot
        .iter()
        .find(|entry| entry.relative_locator == "renamed/game.bin")
        .expect("new location entry");
    assert_ne!(renamed.id, old_id, "weak evidence never preserves identity");
    assert!(
        snapshot.iter().all(|entry| entry.id != old_id),
        "old location removed by authoritative scope finalization"
    );
}

#[test]
fn completed_scope_deletes_absent_prior_direct_children_and_their_descendants() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![
            complete(vec![observation(
                "Sub",
                "Sub",
                ObservedEntryKind::Directory,
                Some("d1"),
                None,
            )]),
            complete(vec![
                observation(
                    "kept.txt",
                    "Sub/kept.txt",
                    ObservedEntryKind::File,
                    Some("k"),
                    Some("fp"),
                ),
                observation(
                    "gone.txt",
                    "Sub/gone.txt",
                    ObservedEntryKind::File,
                    Some("g"),
                    Some("fp"),
                ),
            ]),
        ]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);
    assert_eq!(store_snapshot(&store).len(), 3);

    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![
            complete(vec![observation(
                "Sub",
                "Sub",
                ObservedEntryKind::Directory,
                Some("d1"),
                None,
            )]),
            complete(vec![observation(
                "kept.txt",
                "Sub/kept.txt",
                ObservedEntryKind::File,
                Some("k"),
                Some("fp"),
            )]),
        ]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::Completed);
    let snapshot = store_snapshot(&store);
    assert_eq!(snapshot.len(), 2, "absent entry and subtree removed");
    assert!(
        snapshot
            .iter()
            .any(|entry| entry.display_name == "kept.txt")
    );
    assert!(
        snapshot
            .iter()
            .all(|entry| entry.display_name != "gone.txt")
    );
}

#[test]
fn nested_incomplete_scope_preserves_descendants_while_completed_sibling_finalizes() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![
            complete(vec![
                observation(
                    "Good",
                    "Good",
                    ObservedEntryKind::Directory,
                    Some("g"),
                    None,
                ),
                observation("Bad", "Bad", ObservedEntryKind::Directory, Some("b"), None),
            ]),
            // LIFO traversal: Bad is enumerated before Good.
            complete(vec![observation(
                "b1.bin",
                "Bad/b1.bin",
                ObservedEntryKind::File,
                Some("b1"),
                Some("fp"),
            )]),
            complete(vec![
                observation(
                    "g1.bin",
                    "Good/g1.bin",
                    ObservedEntryKind::File,
                    Some("g1"),
                    Some("fp"),
                ),
                observation(
                    "g2.bin",
                    "Good/g2.bin",
                    ObservedEntryKind::File,
                    Some("g2"),
                    Some("fp"),
                ),
            ]),
        ]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);

    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![
            complete(vec![
                observation(
                    "Good",
                    "Good",
                    ObservedEntryKind::Directory,
                    Some("g"),
                    None,
                ),
                observation("Bad", "Bad", ObservedEntryKind::Directory, Some("b"), None),
            ]),
            outcome(EnumerationOutcome::Failed, Vec::new()),
            complete(vec![observation(
                "g1.bin",
                "Good/g1.bin",
                ObservedEntryKind::File,
                Some("g1"),
                Some("fp"),
            )]),
        ]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::CompletedWithIssues);
    let snapshot = store_snapshot(&store);
    assert_eq!(
        snapshot
            .iter()
            .filter(|entry| entry.display_name == "g2.bin")
            .count(),
        0,
        "completed sibling scope finalizes its absences"
    );
    assert!(
        snapshot.iter().any(|entry| entry.display_name == "b1.bin"),
        "failed nested scope preserves its descendants"
    );
    assert_eq!(
        store
            .lock()
            .expect("store lock")
            .last_scan
            .as_ref()
            .unwrap()
            .status(),
        LibraryRootLastScanStatus::Partial
    );
}

#[test]
fn stale_plan_authority_suppresses_destructive_finalization_and_forces_partial() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![
            observation(
                "a.bin",
                "a.bin",
                ObservedEntryKind::File,
                Some("a"),
                Some("fp"),
            ),
            observation(
                "b.bin",
                "b.bin",
                ObservedEntryKind::File,
                Some("b"),
                Some("fp"),
            ),
        ])]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);

    // The root configuration revision advances after the plan was frozen.
    store.lock().expect("store lock").root_revision = 2;
    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "a.bin",
            "a.bin",
            ObservedEntryKind::File,
            Some("a"),
            Some("fp"),
        )])]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(second.0.state(), JobRunState::CompletedWithIssues);
    let snapshot = store_snapshot(&store);
    assert!(
        snapshot.iter().any(|entry| entry.display_name == "b.bin"),
        "stale authority suppresses absence deletion"
    );
    assert_eq!(
        store
            .lock()
            .expect("store lock")
            .last_scan
            .as_ref()
            .unwrap()
            .status(),
        LibraryRootLastScanStatus::Partial
    );
}

#[test]
fn successful_root_resolution_records_available_evidence() {
    let store = Arc::new(Mutex::new(Store::default()));
    let (completion, _, _) = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(Vec::new())]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(completion.state(), JobRunState::Completed);
    assert_eq!(
        store.lock().expect("store lock").availability,
        Some(LibraryRootAvailability::Available)
    );
}

#[test]
fn root_level_unavailable_outcome_maps_to_failed_unavailable() {
    let store = Arc::new(Mutex::new(Store::default()));
    let (completion, _, _) = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![outcome(EnumerationOutcome::Unavailable, Vec::new())]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(completion.state(), JobRunState::Failed);
    assert_eq!(
        store
            .lock()
            .expect("store lock")
            .last_scan
            .as_ref()
            .unwrap()
            .status(),
        LibraryRootLastScanStatus::Unavailable
    );
    assert_eq!(
        store.lock().expect("store lock").availability,
        Some(LibraryRootAvailability::Unavailable)
    );
}

#[test]
fn root_scope_failure_without_committed_work_maps_to_failed() {
    let store = Arc::new(Mutex::new(Store::default()));
    let (completion, _, _) = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![outcome(EnumerationOutcome::Failed, Vec::new())]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(completion.state(), JobRunState::Failed);
    assert_eq!(
        store
            .lock()
            .expect("store lock")
            .last_scan
            .as_ref()
            .unwrap()
            .status(),
        LibraryRootLastScanStatus::Failed
    );
}

#[test]
fn root_scope_incomplete_with_committed_observations_remains_partial() {
    let store = Arc::new(Mutex::new(Store::default()));
    let (completion, _, _) = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![outcome(
            EnumerationOutcome::Partial,
            vec![observation(
                "a.bin",
                "a.bin",
                ObservedEntryKind::File,
                Some("a"),
                Some("fp"),
            )],
        )]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(completion.state(), JobRunState::CompletedWithIssues);
    assert_eq!(
        store
            .lock()
            .expect("store lock")
            .last_scan
            .as_ref()
            .unwrap()
            .status(),
        LibraryRootLastScanStatus::Partial
    );
    assert_eq!(
        store_snapshot(&store).len(),
        1,
        "positive observations retained"
    );
}

#[test]
fn nested_failure_does_not_mark_root_unavailable() {
    let store = Arc::new(Mutex::new(Store::default()));
    let (completion, _, _) = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![
            complete(vec![observation(
                "Sub",
                "Sub",
                ObservedEntryKind::Directory,
                Some("d1"),
                None,
            )]),
            outcome(EnumerationOutcome::Failed, Vec::new()),
        ]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(completion.state(), JobRunState::CompletedWithIssues);
    assert_eq!(
        store.lock().expect("store lock").availability,
        Some(LibraryRootAvailability::Available),
        "nested failure never marks the root unavailable"
    );
}

#[test]
fn cancelled_scan_retains_positives_and_never_finalizes_absences() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![
            observation(
                "a.bin",
                "a.bin",
                ObservedEntryKind::File,
                Some("a"),
                Some("fp"),
            ),
            observation(
                "b.bin",
                "b.bin",
                ObservedEntryKind::File,
                Some("b"),
                Some("fp"),
            ),
        ])]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);

    let cancel = Arc::new(AtomicBool::new(false));
    let second = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "a.bin",
            "a.bin",
            ObservedEntryKind::File,
            Some("a"),
            Some("fp"),
        )])])
        .with_cancel_after_root(Arc::clone(&cancel)),
        2,
        cancel,
    );
    assert_eq!(second.0.state(), JobRunState::Cancelled);
    let snapshot = store_snapshot(&store);
    assert!(
        snapshot.iter().any(|entry| entry.display_name == "b.bin"),
        "cancellation grants no absence authority"
    );
    assert!(
        snapshot.iter().any(|entry| entry.display_name == "a.bin"),
        "committed positive observations remain valid"
    );
}

#[test]
fn source_entry_events_publish_after_checkpoints_and_finalization_only() {
    let store = Arc::new(Mutex::new(Store::default()));
    let first = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![
            observation(
                "a.bin",
                "a.bin",
                ObservedEntryKind::File,
                Some("a"),
                Some("fp"),
            ),
            observation(
                "b.bin",
                "b.bin",
                ObservedEntryKind::File,
                Some("b"),
                Some("fp"),
            ),
        ])]),
        1,
        Arc::new(AtomicBool::new(false)),
    );
    assert_eq!(first.0.state(), JobRunState::Completed);

    let (_, events, _) = run_scan(
        Arc::clone(&store),
        FakeAccess::new(vec![complete(vec![observation(
            "a.bin",
            "a.bin",
            ObservedEntryKind::File,
            Some("a"),
            Some("fp"),
        )])]),
        2,
        Arc::new(AtomicBool::new(false)),
    );
    let source_changed = events
        .iter()
        .filter(|event| {
            matches!(
                event,
                ApplicationEvent::SourceEntriesChanged(SourceEntriesChanged {
                    scope: SourceEntriesChangeScope::EntireRootHierarchy,
                    ..
                })
            )
        })
        .count();
    assert!(
        source_changed >= 2,
        "checkpoint commit plus finalization commit each publish an invalidation"
    );
    assert!(
        events.iter().all(|event| {
            matches!(
                event,
                ApplicationEvent::SourceEntriesChanged(_) | ApplicationEvent::LibraryRootChanged(_)
            )
        }),
        "no competing scan-completed lifecycle event is introduced"
    );
}

/// Shared no-op repositories required by the fake Unit of Work.
pub struct NoopAppearanceRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl argus_application::AppearanceSettingsRepository for NoopAppearanceRepository<'_> {
    fn get(&mut self) -> Result<argus_application::AppearanceSettings, PersistenceError> {
        Ok(argus_application::AppearanceSettings::new(
            argus_application::ThemeMode::System,
        ))
    }

    fn save(
        &mut self,
        _settings: &argus_application::AppearanceSettings,
    ) -> Result<(), PersistenceError> {
        Ok(())
    }
}

pub struct NoopLibrarySourceRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl argus_application::LibrarySourceRepository for NoopLibrarySourceRepository<'_> {
    fn ensure_local_filesystem_source(
        &mut self,
    ) -> Result<argus_application::LibrarySourceId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

pub struct NoopLibraryScanTargetRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl argus_application::LibraryScanTargetRepository for NoopLibraryScanTargetRepository<'_> {
    fn insert(
        &mut self,
        _target: argus_application::NewLibraryScanTarget,
    ) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn list_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Vec<argus_application::LibraryScanTarget>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

pub struct NoopLibraryScanAdmissionContextRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl argus_application::LibraryScanAdmissionContextRepository
    for NoopLibraryScanAdmissionContextRepository<'_>
{
    fn insert(
        &mut self,
        _new: argus_application::NewLibraryScanAdmissionContext,
    ) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn get_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Option<argus_application::LibraryScanAdmissionContext>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}
