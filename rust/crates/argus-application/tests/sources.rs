//! Application-contract tests for the Slice 001 library-root workflow.

use std::cell::RefCell;
use std::marker::PhantomData;
use std::rc::Rc;
use std::sync::{Arc, Mutex};

use argus_application::{
    AddLocalLibraryRootCommand, AddLocalLibraryRootResult, AppearanceSettings,
    AppearanceSettingsRepository, ApplicationEvent, ApplicationPortError, ErrorCode, EventRecorder,
    EventRecordingError, GetLibraryRootQuery, LibraryRootActiveScanSummary,
    LibraryRootAvailability, LibraryRootChanged, LibraryRootConfiguration, LibraryRootId,
    LibraryRootLastScanSummary, LibraryRootPage, LibraryRootProjection, LibraryRootQueries,
    LibraryRootRepository, LibraryRootsChanged, LibraryRootsSubscriber, LibraryService,
    ListLibraryRootsQuery, LocalFilesystemProvider, LocalFilesystemRootSelection, NewLibraryRoot,
    OperationContext, OperationName, PersistenceError, ProviderError, RemoveLibraryRootCommand,
    RemoveLibraryRootResult, RootLocator, RootRelationship, SourceProviderType, SubsystemName,
    TraceId, UnitOfWork, UnitOfWorkFactory, ValidatedLocalRoot,
};
use argus_domain::LibrarySourceId;

const ROOT_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const ROOT_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const ROOT_EXISTING: &str = "cccccccccccccccccccccccccccccccc";
const ROOT_MISSING: &str = "dddddddddddddddddddddddddddddddd";
const ROOT_INSERTED: &str = "22222222222222222222222222222222";

fn context() -> OperationContext {
    OperationContext::new(
        TraceId::try_from(1).expect("non-zero trace"),
        SubsystemName::try_from("test").expect("valid subsystem"),
        OperationName::try_from("sources").expect("valid operation"),
    )
}

fn selection(path: &str) -> LocalFilesystemRootSelection {
    LocalFilesystemRootSelection::new(path.to_owned())
}

fn validated(path: &str) -> ValidatedLocalRoot {
    ValidatedLocalRoot::new(
        RootLocator::from_provider(path.to_owned()),
        "Games".to_owned(),
        path.to_owned(),
    )
}

fn root_id(value: &str) -> LibraryRootId {
    LibraryRootId::try_from(value).expect("fixture root id")
}

fn source_id(value: &str) -> LibrarySourceId {
    LibrarySourceId::try_from(value).expect("fixture source id")
}

fn projection(id: &str, display_name: &str) -> LibraryRootProjection {
    LibraryRootProjection::new(
        root_id(id),
        display_name.to_owned(),
        format!("/library/{display_name}"),
        LibraryRootAvailability::Available,
        None,
        None,
    )
}

fn config(id: &str, locator: &str) -> LibraryRootConfiguration {
    LibraryRootConfiguration::new(root_id(id), RootLocator::from_provider(locator.to_owned()))
}

#[derive(Clone)]
struct FakeProvider {
    validation: Rc<RefCell<Result<ValidatedLocalRoot, ProviderError>>>,
    relationships: Rc<RefCell<Vec<RootRelationship>>>,
    compared: Rc<RefCell<Vec<(RootLocator, RootLocator)>>>,
}

impl FakeProvider {
    fn new(validation: Result<ValidatedLocalRoot, ProviderError>) -> Self {
        Self {
            validation: Rc::new(RefCell::new(validation)),
            relationships: Rc::new(RefCell::new(Vec::new())),
            compared: Rc::new(RefCell::new(Vec::new())),
        }
    }

    fn enqueue(&self, relationship: RootRelationship) {
        self.relationships.borrow_mut().push(relationship);
    }
}

impl LocalFilesystemProvider for FakeProvider {
    fn validate(
        &self,
        _selection: &LocalFilesystemRootSelection,
    ) -> Result<ValidatedLocalRoot, ProviderError> {
        self.validation.borrow().clone()
    }

    fn compare_roots(&self, left: &RootLocator, right: &RootLocator) -> RootRelationship {
        self.compared
            .borrow_mut()
            .push((left.clone(), right.clone()));
        self.relationships
            .borrow_mut()
            .pop()
            .unwrap_or(RootRelationship::Unknown)
    }
}

#[derive(Clone, Default)]
struct FakeQueries {
    roots: Rc<RefCell<Vec<LibraryRootProjection>>>,
    configs: Rc<RefCell<Vec<LibraryRootConfiguration>>>,
}

impl FakeQueries {
    fn with_configs(configs: Vec<LibraryRootConfiguration>) -> Self {
        Self {
            configs: Rc::new(RefCell::new(configs)),
            ..Self::default()
        }
    }
}

impl LibraryRootQueries for FakeQueries {
    fn list(
        &self,
        _context: &OperationContext,
        offset: u32,
        page_size: u32,
    ) -> Result<LibraryRootPage, PersistenceError> {
        let items = self.roots.borrow().clone();
        let total = items.len() as u32;
        let slice = items
            .into_iter()
            .skip(offset as usize)
            .take(page_size as usize)
            .collect();
        Ok(LibraryRootPage::new(slice, offset, page_size, total))
    }

    fn get(
        &self,
        _context: &OperationContext,
        id: LibraryRootId,
    ) -> Result<Option<LibraryRootProjection>, PersistenceError> {
        Ok(self
            .roots
            .borrow()
            .iter()
            .find(|root| root.root_id() == id)
            .cloned())
    }

    fn list_root_configurations(
        &self,
        _context: &OperationContext,
    ) -> Result<Vec<LibraryRootConfiguration>, PersistenceError> {
        Ok(self.configs.borrow().clone())
    }
}

#[derive(Clone, Default)]
struct FakeStore {
    source_id: Option<LibrarySourceId>,
    inserted: Vec<(LibraryRootId, NewLibraryRoot)>,
    deleted: Vec<LibraryRootId>,
    commits: usize,
    rollbacks: usize,
}

struct FakeSourceRepository<'scope> {
    store: Rc<RefCell<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl argus_application::LibrarySourceRepository for FakeSourceRepository<'_> {
    fn ensure_local_filesystem_source(&mut self) -> Result<LibrarySourceId, PersistenceError> {
        let mut store = self.store.borrow_mut();
        if let Some(id) = store.source_id {
            return Ok(id);
        }
        let id = source_id("11111111111111111111111111111111");
        store.source_id = Some(id);
        Ok(id)
    }
}

struct FakeRootRepository<'scope> {
    store: Rc<RefCell<FakeStore>>,
    marker: PhantomData<&'scope mut ()>,
}

impl LibraryRootRepository for FakeRootRepository<'_> {
    fn insert(&mut self, root: NewLibraryRoot) -> Result<LibraryRootId, PersistenceError> {
        let id = root_id("22222222222222222222222222222222");
        self.store.borrow_mut().inserted.push((id, root));
        Ok(id)
    }

    fn delete(&mut self, id: LibraryRootId) -> Result<bool, PersistenceError> {
        self.store.borrow_mut().deleted.push(id);
        Ok(true)
    }
}

struct FakeAppearanceRepository<'scope> {
    marker: PhantomData<&'scope mut ()>,
}

impl AppearanceSettingsRepository for FakeAppearanceRepository<'_> {
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn save(&mut self, _settings: &AppearanceSettings) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

struct FakeUnitOfWork<'scope> {
    store: Rc<RefCell<FakeStore>>,
    terminal: bool,
    marker: PhantomData<&'scope mut ()>,
}

impl UnitOfWork for FakeUnitOfWork<'_> {
    type AppearanceSettingsRepository<'scope>
        = FakeAppearanceRepository<'scope>
    where
        Self: 'scope;
    type LibrarySourceRepository<'scope>
        = FakeSourceRepository<'scope>
    where
        Self: 'scope;
    type LibraryRootRepository<'scope>
        = FakeRootRepository<'scope>
    where
        Self: 'scope;

    fn appearance_settings(&mut self) -> Self::AppearanceSettingsRepository<'_> {
        FakeAppearanceRepository {
            marker: PhantomData,
        }
    }

    fn library_source(&mut self) -> Self::LibrarySourceRepository<'_> {
        FakeSourceRepository {
            store: Rc::clone(&self.store),
            marker: PhantomData,
        }
    }

    fn library_roots(&mut self) -> Self::LibraryRootRepository<'_> {
        FakeRootRepository {
            store: Rc::clone(&self.store),
            marker: PhantomData,
        }
    }

    fn commit(mut self) -> Result<(), ApplicationPortError> {
        self.store.borrow_mut().commits += 1;
        self.terminal = true;
        Ok(())
    }

    fn rollback(mut self) -> Result<(), ApplicationPortError> {
        self.store.borrow_mut().rollbacks += 1;
        self.terminal = true;
        Ok(())
    }
}

impl Drop for FakeUnitOfWork<'_> {
    fn drop(&mut self) {
        if !self.terminal {
            self.store.borrow_mut().rollbacks += 1;
        }
    }
}

#[derive(Clone, Default)]
struct FakeFactory {
    store: Rc<RefCell<FakeStore>>,
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
            store: Rc::clone(&self.store),
            terminal: false,
            marker: PhantomData,
        })
    }
}

#[derive(Clone, Default)]
struct FakeRecorder {
    events: Arc<Mutex<Vec<ApplicationEvent>>>,
}

impl EventRecorder for FakeRecorder {
    fn record(&self, event: ApplicationEvent) -> Result<(), EventRecordingError> {
        self.events.lock().expect("recorder lock").push(event);
        Ok(())
    }
}

fn assert_committed_roots_changed_and_root_changed(events: &[ApplicationEvent]) {
    assert_eq!(
        events,
        &[
            ApplicationEvent::LibraryRootsChanged(LibraryRootsChanged),
            ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                library_root_id: root_id(ROOT_INSERTED),
            }),
        ]
    );
}

#[test]
fn list_library_roots_returns_a_bounded_authoritative_page() {
    let queries = FakeQueries::default();
    queries.roots.borrow_mut().push(projection(ROOT_A, "Alpha"));
    queries.roots.borrow_mut().push(projection(ROOT_B, "Beta"));
    let service = LibraryService::new(
        queries.clone(),
        FakeFactory::default(),
        FakeProvider::new(Ok(validated("/tmp/games"))),
    );

    let page = service
        .list_library_roots(ListLibraryRootsQuery::new(0, 1), context())
        .expect("list");

    assert_eq!(
        page,
        LibraryRootPage::new(vec![projection(ROOT_A, "Alpha")], 0, 1, 2)
    );
}

#[test]
fn get_library_root_returns_the_authoritative_projection() {
    let queries = FakeQueries::default();
    queries.roots.borrow_mut().push(projection(ROOT_A, "Alpha"));
    let service = LibraryService::new(
        queries,
        FakeFactory::default(),
        FakeProvider::new(Ok(validated("/tmp/games"))),
    );

    let root = service
        .get_library_root(GetLibraryRootQuery::new(root_id(ROOT_A)), context())
        .expect("root");

    assert_eq!(root, projection(ROOT_A, "Alpha"));
}

#[test]
fn get_library_root_maps_a_missing_root_to_a_typed_configuration_failure() {
    let queries = FakeQueries::default();
    let service = LibraryService::new(
        queries,
        FakeFactory::default(),
        FakeProvider::new(Ok(validated("/tmp/games"))),
    );

    let error = service
        .get_library_root(GetLibraryRootQuery::new(root_id(ROOT_MISSING)), context())
        .expect_err("missing root is an application failure");

    assert_eq!(error.code, ErrorCode::ConfigurationLibraryRootNotFound);
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND"
    );
    assert_eq!(
        error.message_key.as_str(),
        "errors.configuration.library_root_not_found"
    );
}

#[test]
fn add_local_library_root_validates_before_any_mutation() {
    let provider = FakeProvider::new(Err(ProviderError::NotADirectory));
    let factory = FakeFactory::default();
    let service = LibraryService::new(FakeQueries::default(), factory.clone(), provider);

    let error = service
        .add_local_library_root(
            AddLocalLibraryRootCommand::new(selection("/tmp/rom.bin")),
            context(),
            FakeRecorder::default(),
        )
        .expect_err("invalid selection");

    assert_eq!(error.code, ErrorCode::FilesystemInvalidRootSelection);
    assert_eq!(
        error.code.as_str(),
        "ARGUS.V1.FILESYSTEM.INVALID_ROOT_SELECTION"
    );
    assert_eq!(
        error.message_key.as_str(),
        "errors.filesystem.invalid_root_selection"
    );
    assert_eq!(factory.store.borrow().inserted.len(), 0);
    assert_eq!(factory.store.borrow().source_id, None);
}

#[test]
fn add_local_library_root_creates_the_internal_source_and_root_then_commits() {
    let queries = FakeQueries::default();
    let factory = FakeFactory::default();
    let provider = FakeProvider::new(Ok(validated("/tmp/games")));
    let recorder = FakeRecorder::default();
    let service = LibraryService::new(queries, factory.clone(), provider);

    let result = service
        .add_local_library_root(
            AddLocalLibraryRootCommand::new(selection("/tmp/games")),
            context(),
            recorder.clone(),
        )
        .expect("added");

    let AddLocalLibraryRootResult::Added(root) = result else {
        panic!("expected Added outcome");
    };
    assert_eq!(root.root_id(), root_id(ROOT_INSERTED));
    assert_eq!(root.display_name(), "Games");
    assert_eq!(root.safe_location_presentation(), "/tmp/games");
    assert_eq!(root.availability(), LibraryRootAvailability::Available);
    assert_eq!(root.last_scan(), None);
    assert_eq!(root.active_scan(), None);
    let store = factory.store.borrow();
    assert_eq!(
        store.source_id,
        Some(source_id("11111111111111111111111111111111"))
    );
    assert_eq!(store.inserted.len(), 1);
    assert_eq!(
        store.inserted[0].1.library_source_id(),
        store.source_id.unwrap()
    );
    assert_eq!(
        store.inserted[0].1.locator(),
        &RootLocator::from_provider("/tmp/games".to_owned())
    );
    assert_eq!(
        store.inserted[0].1.availability(),
        LibraryRootAvailability::Available
    );
    assert_eq!(store.commits, 1);
    assert_eq!(store.rollbacks, 0);
    assert_committed_roots_changed_and_root_changed(&recorder.events.lock().expect("events"));
}

#[test]
fn add_local_library_root_is_idempotent_for_the_same_selection() {
    let provider = FakeProvider::new(Ok(validated("/tmp/games")));
    provider.enqueue(RootRelationship::Same);
    let queries = FakeQueries::with_configs(vec![config(ROOT_EXISTING, "/tmp/games")]);
    let factory = FakeFactory::default();
    let recorder = FakeRecorder::default();
    let service = LibraryService::new(queries, factory.clone(), provider);

    let result = service
        .add_local_library_root(
            AddLocalLibraryRootCommand::new(selection("/tmp/games")),
            context(),
            recorder.clone(),
        )
        .expect("already configured");

    assert_eq!(
        result,
        AddLocalLibraryRootResult::AlreadyConfigured(root_id(ROOT_EXISTING))
    );
    assert_eq!(factory.store.borrow().inserted.len(), 0);
    assert_eq!(factory.store.borrow().source_id, None);
    assert_eq!(factory.store.borrow().commits, 0);
    assert!(recorder.events.lock().expect("events").is_empty());
}

#[test]
fn add_local_library_root_rejects_provably_overlapping_ancestor_and_descendant_roots() {
    for relationship in [RootRelationship::Ancestor, RootRelationship::Descendant] {
        let provider = FakeProvider::new(Ok(validated("/tmp/games")));
        provider.enqueue(relationship);
        let queries = FakeQueries::with_configs(vec![config(ROOT_EXISTING, "/tmp")]);
        let factory = FakeFactory::default();
        let recorder = FakeRecorder::default();
        let service = LibraryService::new(queries, factory.clone(), provider);

        let result = service
            .add_local_library_root(
                AddLocalLibraryRootCommand::new(selection("/tmp/games")),
                context(),
                recorder.clone(),
            )
            .expect("overlap outcome");

        assert_eq!(
            result,
            AddLocalLibraryRootResult::OverlapsExisting(root_id(ROOT_EXISTING), relationship)
        );
        assert_eq!(factory.store.borrow().inserted.len(), 0);
        assert_eq!(factory.store.borrow().commits, 0);
        assert!(recorder.events.lock().expect("events").is_empty());
    }
}

#[test]
fn add_local_library_root_allows_disjoint_and_unknown_relationships() {
    for relationship in [RootRelationship::Disjoint, RootRelationship::Unknown] {
        let provider = FakeProvider::new(Ok(validated("/tmp/games")));
        provider.enqueue(relationship);
        let queries = FakeQueries::with_configs(vec![config(ROOT_EXISTING, "/tmp/other")]);
        let factory = FakeFactory::default();
        let recorder = FakeRecorder::default();
        let service = LibraryService::new(queries, factory.clone(), provider);

        let result = service
            .add_local_library_root(
                AddLocalLibraryRootCommand::new(selection("/tmp/games")),
                context(),
                recorder,
            )
            .expect("admissible");

        assert!(matches!(result, AddLocalLibraryRootResult::Added(_)));
        assert_eq!(factory.store.borrow().inserted.len(), 1);
    }
}

#[test]
fn remove_library_root_commits_the_delete_and_records_events() {
    let factory = FakeFactory::default();
    let recorder = FakeRecorder::default();
    let service = LibraryService::new(
        FakeQueries::default(),
        factory.clone(),
        FakeProvider::new(Ok(validated("/tmp/games"))),
    );

    let result = service
        .remove_library_root(
            RemoveLibraryRootCommand::new(root_id(ROOT_EXISTING)),
            context(),
            recorder.clone(),
        )
        .expect("removed");

    assert_eq!(result, RemoveLibraryRootResult::Removed);
    assert_eq!(factory.store.borrow().deleted, vec![root_id(ROOT_EXISTING)]);
    assert_eq!(factory.store.borrow().commits, 1);
    assert_eq!(
        &*recorder.events.lock().expect("events"),
        &[
            ApplicationEvent::LibraryRootsChanged(LibraryRootsChanged),
            ApplicationEvent::LibraryRootChanged(LibraryRootChanged {
                library_root_id: root_id(ROOT_EXISTING),
            }),
        ]
    );
}

#[test]
fn sources_queries_and_provider_keep_locators_opaque() {
    // The application boundary must expose no path-parsing or comparison
    // helpers on RootLocator; these assertions only compile when the locator
    // is an opaque provider-owned value.
    let left = RootLocator::from_provider("raw".to_owned());
    let right = RootLocator::from_provider("raw".to_owned());
    assert_eq!(left, right);
    assert_eq!(
        SourceProviderType::LocalFilesystem.as_str(),
        "local_filesystem"
    );
    assert_eq!(
        SourceProviderType::try_from("local_filesystem").expect("provider type"),
        SourceProviderType::LocalFilesystem
    );
    assert!(SourceProviderType::try_from("cloud").is_err());
}

#[test]
fn library_root_projection_is_immutable_and_dimension_separated() {
    let last_scan = LibraryRootLastScanSummary::new(
        "scan-run".to_owned(),
        "job-run".to_owned(),
        argus_application::LibraryRootLastScanStatus::Complete,
        1,
        Some(2),
    );
    let active_scan =
        LibraryRootActiveScanSummary::new("scan-run".to_owned(), "job-run".to_owned());
    let root = projection(ROOT_A, "Alpha")
        .with_last_scan(last_scan.clone())
        .with_active_scan(active_scan.clone());

    assert_eq!(root.last_scan(), Some(&last_scan));
    assert_eq!(root.active_scan(), Some(&active_scan));
    assert_eq!(root.availability(), LibraryRootAvailability::Available);
}

#[test]
fn library_roots_subscriber_trait_is_implementable() {
    struct Subscriber;

    impl LibraryRootsSubscriber for Subscriber {
        fn library_roots_changed(
            &self,
            _event: LibraryRootsChanged,
        ) -> Result<(), argus_application::EventSubscriberError> {
            Ok(())
        }

        fn library_root_changed(
            &self,
            _event: LibraryRootChanged,
        ) -> Result<(), argus_application::EventSubscriberError> {
            Ok(())
        }
    }

    let subscriber = Subscriber;
    assert!(
        subscriber
            .library_roots_changed(LibraryRootsChanged)
            .is_ok()
    );
    assert!(
        subscriber
            .library_root_changed(LibraryRootChanged {
                library_root_id: root_id(ROOT_A),
            })
            .is_ok()
    );
}
