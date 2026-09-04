# Foreground Responsiveness and Routing Admission Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Library, Sources, Jobs, Settings, onboarding reads, and job control responsive while Library refresh work is active, and make application routing synchronous and free of redirect-time backend I/O.

**Architecture:** Extract the long-running Library/Game refresh execution surface from `KernelBootstrap` into one cloneable private `LibraryExecutionContext` built during short admission-time kernel access. Background handlers own that context rather than `Arc<Mutex<Option<KernelBootstrap>>>`. On Flutter, hydrate backend-authoritative onboarding state into one runtime-generation-aware routing projection outside GoRouter redirect evaluation; the router reads only the app-owned presentation-readiness projection synchronously.

**Tech Stack:** Rust, SQLite-backed `KernelUnitOfWorkFactory`, `BackgroundOperationManager`, Flutter 3.44.7, Dart 3.12, Riverpod 3.3.2 / riverpod_annotation 4.0.3, go_router 17.3.0, flutter_rust_bridge 2.12.0.

**Spec:** `docs/superpowers/specs/2026-09-03-phase-003-foreground-responsiveness-and-routing-admission-hardening-design.md`

## Global Constraints

- Preserve exactly one `ApplicationRuntime`, one `BackgroundOperationManager`, one SQLite authority, one root `ArgusClient`, and one authoritative backend onboarding state.
- Do not add a persistence migration or change persisted schema.
- Do not change provider timeout/retry policy, provider roster, provider matching semantics, or artwork policy.
- Do not add a public bridge DTO/API unless implementation proves an unavoidable contract gap; this plan requires none.
- Preserve `library_refresh`, `game_refresh`, and `library_resolution_refresh` operation types, `JobRunId` semantics, progress vocabulary, cancellation/retry/recovery behavior, and Android foreground-hosting behavior.
- Preserve Phase 001 scan/root semantics and the current macOS security-scoped root-locator behavior.
- Runtime/kernel lifecycle synchronization may coordinate runtime generations only; it must not span filesystem traversal, parsing/hashing/transformation, provider/network work, enrichment/artwork loops, waits, or whole-job checkpoint sequences.
- GoRouter redirect evaluation must not call `LibraryOnboardingApi`, a focused `ArgusClient` API, FRB, or native code and must not await backend work.
- Flutter may project authoritative onboarding completion but must not persist or infer a second completion authority from URI, roots, or Library rows.
- Do not use phase/slice identifiers in production API names, production source file names, type names, or runtime operation names. Phase/slice terminology is permitted in documentation and qualification records.
- Use deterministic synchronization for concurrency tests. Timeouts may bound a failed test so it cannot hang, but sleeps must not be the mechanism that establishes ordering.
- Use TDD for every behavior change: observe the focused failure before applying the production correction.

---

## File Structure

### Rust execution boundary

- Modify `rust/crates/argus-runtime/src/lib.rs`
  - define the private cloneable `LibraryExecutionContext` and its execution methods;
  - make publication diagnostics shareable where required by that context;
  - add a `test-support`-only refresh execution hook keyed by the existing test-owned data directory;
  - keep `KernelBootstrap` as the lifecycle/composition authority and use thin delegates where existing callers need the old method surface.
- Modify `rust/crates/argus-runtime/src/runtime.rs`
  - construct `LibraryExecutionContext` during admitted refresh registration;
  - remove kernel-handle ownership and `with_kernel` from long-running refresh handlers.
- Modify `rust/crates/argus-runtime/tests/background_operations.rs`
  - reproduce lifecycle starvation deterministically for Library refresh, Game refresh, and local Library resolution refresh;
  - prove foreground reads/control complete while execution is held at the test seam.

### Flutter routing projection

- Create `flutter/lib/features/library/application/library_onboarding_routing.dart`
  - own the runtime-generation-aware routing projection of authoritative `LibraryOnboardingState`;
  - expose an explicit method for consuming authoritative state returned by onboarding commands.
- Generate `flutter/lib/features/library/application/library_onboarding_routing.g.dart`.
- Modify `flutter/lib/features/library/library.dart`
  - export only the routing projection types/provider needed by app composition and onboarding presentation.
- Modify `flutter/lib/app/bootstrap/application_presentation.dart`
  - combine startup, appearance, Library capability, and onboarding projection into one routing-safe readiness enum.
- Modify `flutter/lib/app/bootstrap/application_presentation_gate.dart`
  - show bounded onboarding-initialization/failure state outside the normal shell;
  - retry the routing projection without routing-side I/O.
- Modify `flutter/lib/app/routing/app_router.dart`
  - listen to readiness projection changes and refresh GoRouter;
  - make global redirect synchronous and projection-only.
- Modify `flutter/lib/app/routing/app_routes.dart`
  - remove the `RootRoute` read of `argusClientProvider`; root routing is decided by the global routing policy.
- Modify `flutter/lib/features/library/presentation/library_onboarding_page.dart`
  - publish every authoritative onboarding snapshot into the routing projection;
  - publish the committed state returned by `completeAndRefresh()` before navigation.
- Modify `justfile`
  - register `library_onboarding_routing.g.dart` in the generated-file allowlist.

### Flutter tests

- Create `flutter/test/features/library/library_onboarding_routing_test.dart`.
- Modify `flutter/test/features/library/library_test_fakes.dart` to provide one reusable onboarding fake.
- Modify `flutter/test/features/library/library_onboarding_page_test.dart` to use the shared fake and assert completion is projected before navigation.
- Modify `flutter/test/app/bootstrap/application_presentation_test.dart` for onboarding initialization/failure/required/ready states.
- Modify `flutter/test/app/routing/app_router_test.dart` for redirect purity and branch switching while a Library read remains deliberately unresolved.
- Modify `flutter/test/features/library/library_page_test.dart` to lock in the existing invariant that usable rows remain rendered during background-triggered reconciliation.

### Native qualification

- Modify `scripts/run_library_desktop_qualification.sh` so the macOS qualification runs the targeted deterministic native runtime responsiveness test before the existing Flutter lifecycle test.
- Modify `flutter/integration_test/library_lifecycle_qualification_test.dart` only if the final routing composition needs an additional native assertion; do not create a timing-based synthetic slow refresh in Flutter.

---

### Task 1: Add deterministic runtime starvation reproduction

**Files:**
- Modify: `rust/crates/argus-runtime/src/lib.rs`
- Modify: `rust/crates/argus-runtime/tests/background_operations.rs`

**Interfaces:**
- Consumes: existing `KernelBootstrapOptions::with_provider_session_factory_for_tests`, `ApplicationHost`, and background refresh operations.
- Produces:
  - `#[cfg(feature = "test-support")] pub enum RefreshExecutionCheckpoint { CommittedRoot, Game, LibraryResolution }`
  - `#[cfg(feature = "test-support")] pub fn KernelBootstrapOptions::with_refresh_execution_hook_for_tests<F>(self, hook: F) -> Self where F: Fn(RefreshExecutionCheckpoint) + Send + Sync + 'static`
  - a test-owned hook invoked inside the real long-running execution methods, so the current implementation blocks while holding the lifecycle mutex and the corrected implementation blocks without it.

- [ ] **Step 1: Add the test-support-only execution hook without changing production behavior**

Use the same data-directory-keyed registration pattern already used by `with_provider_session_factory_for_tests`. Add this closed checkpoint vocabulary and hook type in `argus-runtime/src/lib.rs`:

```rust
#[cfg(feature = "test-support")]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[doc(hidden)]
pub enum RefreshExecutionCheckpoint {
    CommittedRoot,
    Game,
    LibraryResolution,
}

#[cfg(feature = "test-support")]
type RefreshExecutionHook =
    dyn Fn(RefreshExecutionCheckpoint) + Send + Sync + 'static;
```

Store the hook in the existing test-only options registry keyed by `data_directory_override`, and clone the resolved hook into `KernelBootstrap` at startup. Invoke it at the start of these real execution methods, before substantive work but after the caller has entered the method:

```rust
self.call_refresh_execution_hook(RefreshExecutionCheckpoint::CommittedRoot);
```

inside `refresh_committed_root_with_context`,

```rust
self.call_refresh_execution_hook(RefreshExecutionCheckpoint::Game);
```

inside `refresh_game_with_context`, and

```rust
self.call_refresh_execution_hook(RefreshExecutionCheckpoint::LibraryResolution);
```

inside `resolve_game_with_context`.

The helper is a no-op when `test-support` is absent or no hook was registered.

- [ ] **Step 2: Add a deterministic one-shot blocking gate to `background_operations.rs`**

Use a mutex/condvar state machine rather than sleeps:

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum GateState {
    Disarmed,
    Armed,
    Entered,
    Released,
}

struct RefreshExecutionGate {
    checkpoint: RefreshExecutionCheckpoint,
    state: Mutex<GateState>,
    wake: std::sync::Condvar,
}

impl RefreshExecutionGate {
    fn new(checkpoint: RefreshExecutionCheckpoint) -> Arc<Self> {
        Arc::new(Self {
            checkpoint,
            state: Mutex::new(GateState::Disarmed),
            wake: std::sync::Condvar::new(),
        })
    }

    fn arm(&self) {
        *self.state.lock().expect("refresh gate") = GateState::Armed;
    }

    fn hook(&self, checkpoint: RefreshExecutionCheckpoint) {
        if checkpoint != self.checkpoint {
            return;
        }
        let mut state = self.state.lock().expect("refresh gate");
        if *state != GateState::Armed {
            return;
        }
        *state = GateState::Entered;
        self.wake.notify_all();
        while *state != GateState::Released {
            state = self.wake.wait(state).expect("refresh gate wait");
        }
    }

    fn wait_until_entered(&self) {
        let state = self.state.lock().expect("refresh gate");
        let (state, timeout) = self
            .wake
            .wait_timeout_while(state, Duration::from_secs(5), |value| {
                *value != GateState::Entered
            })
            .expect("refresh gate entered wait");
        assert!(!timeout.timed_out(), "refresh execution never reached the gate");
        assert_eq!(*state, GateState::Entered);
    }

    fn release(&self) {
        *self.state.lock().expect("refresh gate") = GateState::Released;
        self.wake.notify_all();
    }
}
```

- [ ] **Step 3: Write the failing Library refresh foreground-responsiveness test**

Create a test named:

```rust
#[test]
fn library_refresh_does_not_starve_foreground_queries_or_job_control()
```

Set up `ApplicationHost` inside `Arc`, register a `CommittedRoot` gate through `KernelBootstrapOptions`, add one fabricated GB fixture root, arm the gate, and admit `refresh_library()`. Wait until the hook reports `Entered`.

While the refresh remains blocked, spawn bounded foreground calls and require each result through a channel before releasing the gate:

```rust
fn assert_foreground_returns<T: Send + 'static>(
    operation: impl FnOnce() -> T + Send + 'static,
) -> T {
    let (sender, receiver) = mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let _ = sender.send(operation());
    });
    receiver
        .recv_timeout(Duration::from_secs(2))
        .expect("foreground operation was starved by background refresh")
}
```

Exercise all of these while the gate is still `Entered`. Build the Library query exactly as the existing composed-refresh test does:

```rust
let games_query = ListGamesQuery::builder()
    .scope(LibraryScope::All)
    .search(None)
    .filters_empty(true)
    .sort(LibrarySort::DisplayTitleAscending)
    .page_size(50)
    .build()
    .expect("bounded Library query");

assert_foreground_returns({
    let host = Arc::clone(&host);
    move || host.list_games(games_query)
})
.expect("Library read while refresh is blocked");

assert_foreground_returns({
    let host = Arc::clone(&host);
    move || host.list_library_roots(ListLibraryRootsQuery::new(0, 100))
})
.expect("Sources read while refresh is blocked");

assert_foreground_returns({
    let host = Arc::clone(&host);
    move || host.list_jobs(ListJobsQuery::new(ListJobsScope::Active))
})
.expect("Jobs read while refresh is blocked");

assert_foreground_returns({
    let host = Arc::clone(&host);
    move || host.get_job(refresh_job_run_id)
})
.expect("Job detail while refresh is blocked");

assert_foreground_returns({
    let host = Arc::clone(&host);
    move || {
        let (context, _guard) = host
            .begin_operation("library", "foreground_onboarding_probe")
            .expect("onboarding probe admission");
        host.library_onboarding_state_with_context(&context)
    }
})
.expect("onboarding read while refresh is blocked");

let cancel = assert_foreground_returns({
    let host = Arc::clone(&host);
    move || host.cancel_job(refresh_job_run_id)
})
.expect("cancel while refresh is blocked");
assert!(matches!(
    cancel,
    CancelJobResult::CancellationRequested | CancelJobResult::NoLongerCancellable
));
```

Do not assert that Library already contains hydrated rows; assert only that each focused operation returns normally and that cancellation returns its existing closed `CancelJobResult` outcome. Release the gate, then assert the job reaches a valid terminal state and shutdown succeeds.

- [ ] **Step 4: Run the focused test and verify the current implementation fails for lifecycle starvation**

Run:

```bash
bash scripts/run_rust.sh cargo test \
  --manifest-path rust/Cargo.toml \
  --package argus-runtime \
  --all-features \
  --locked \
  --test background_operations \
  library_refresh_does_not_starve_foreground_queries_or_job_control \
  -- --exact --nocapture
```

Expected before Task 2: FAIL with `foreground operation was starved by background refresh` while the execution gate is held. The failure must not be a fixture/startup/provider error.

- [ ] **Step 5: Commit the red regression and test-only seam**

```bash
git add rust/crates/argus-runtime/src/lib.rs \
        rust/crates/argus-runtime/tests/background_operations.rs
git commit -m "test: reproduce refresh foreground starvation"
```

---

### Task 2: Extract a cloneable Library execution context and fix `library_refresh`

**Files:**
- Modify: `rust/crates/argus-runtime/src/lib.rs`
- Modify: `rust/crates/argus-runtime/src/runtime.rs`
- Test: `rust/crates/argus-runtime/tests/background_operations.rs`

**Interfaces:**
- Consumes: Task 1 `RefreshExecutionCheckpoint` hook and existing `KernelUnitOfWorkFactory` / provider / artwork / event capabilities.
- Produces:
  - private `LibraryExecutionContext: Clone`;
  - `KernelBootstrap::library_execution_context(&self) -> LibraryExecutionContext`;
  - `LibraryRefreshOperationHandler` owns `LibraryExecutionContext` and no longer owns `Arc<Mutex<Option<KernelBootstrap>>>`.

- [ ] **Step 1: Make publication diagnostics shareable without creating a second authority**

Change the private `KernelBootstrap` field from:

```rust
publication_diagnostics: Mutex<PublicationDiagnostics>,
```

to:

```rust
publication_diagnostics: Arc<Mutex<PublicationDiagnostics>>,
```

Initialize it with:

```rust
publication_diagnostics: Arc::new(Mutex::new(PublicationDiagnostics::new())),
```

Keep all existing event finalization calls pointed at the same shared mutex. Do not copy `PublicationDiagnostics` values.

- [ ] **Step 2: Add the private cloneable execution context**

Define this private runtime-owned type next to `KernelBootstrap` in `argus-runtime/src/lib.rs`:

```rust
#[derive(Clone)]
pub(crate) struct LibraryExecutionContext {
    unit_of_work: KernelUnitOfWorkFactory,
    metadata_provider_registry: MetadataProviderRegistry,
    provider_session_factory: Arc<EnrichmentSessionFactory>,
    credential_service: Arc<Mutex<RuntimeCredentialService>>,
    artwork_store: Arc<ArtworkObjectStore>,
    event_bus: Arc<EventBus>,
    publication_diagnostics: Arc<Mutex<PublicationDiagnostics>>,
    transformation_registry: TransformationRegistry,
    transformation_staging_root: PathBuf,
    #[cfg(feature = "test-support")]
    refresh_execution_hook: Option<Arc<RefreshExecutionHook>>,
}
```

Add this factory on `KernelBootstrap`:

```rust
pub(crate) fn library_execution_context(&self) -> LibraryExecutionContext {
    LibraryExecutionContext {
        unit_of_work: self.unit_of_work.clone(),
        metadata_provider_registry: self.metadata_provider_registry.clone(),
        provider_session_factory: Arc::clone(&self.provider_session_factory),
        credential_service: Arc::clone(&self.credential_service),
        artwork_store: Arc::clone(&self.artwork_store),
        event_bus: Arc::clone(&self.event_bus),
        publication_diagnostics: Arc::clone(&self.publication_diagnostics),
        transformation_registry: self.transformation_registry.clone(),
        transformation_staging_root: self.transformation_staging_root.clone(),
        #[cfg(feature = "test-support")]
        refresh_execution_hook: self.refresh_execution_hook.clone(),
    }
}
```

The type is a capability bundle over the existing shared authorities. It must not own `SqliteDatabaseExecutor` separately from `KernelUnitOfWorkFactory`, construct a second `EventBus`, or create a second credential/artwork store.

- [ ] **Step 3: Move the long-running execution methods onto `LibraryExecutionContext`**

Move the implementation of the execution-only method family used by committed-root identification/hydration and focused refreshes from `impl KernelBootstrap` to `impl LibraryExecutionContext`. The externally used method signatures remain:

```rust
impl LibraryExecutionContext {
    pub(crate) fn create_enrichment_sessions(
        &self,
    ) -> Vec<Box<dyn EnrichmentProviderSession>>;

    pub(crate) fn transformation_staging_root(&self) -> &Path;

    pub(crate) fn refresh_committed_root_with_context(
        &self,
        plan: &LibraryScanExecutionPlan,
        context: &OperationContext,
        sessions: &mut [Box<dyn EnrichmentProviderSession>],
        parsing_session: &mut ParsingSession<'_>,
        timestamps: ContentRefreshTimestamps,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<(usize, u64), ApplicationError>;

    pub(crate) fn refresh_game_with_context(
        &self,
        game_id: GameId,
        context: &OperationContext,
        now: i64,
    ) -> Result<u64, ApplicationError>;

    pub(crate) fn resolve_game_with_context(
        &self,
        game_id: GameId,
        context: &OperationContext,
        now: i64,
    ) -> Result<u64, ApplicationError>;

    pub(crate) fn list_game_ids_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<GameId>, ApplicationError>;

    pub(crate) fn metadata_settings_revision_with_context(
        &self,
        context: &OperationContext,
    ) -> Result<u64, ApplicationError>;
}
```

Relocate this execution helper family onto `LibraryExecutionContext`: `transformation_registry`, `reconcile_derived_scope_with_context`, `process_source_tree`, `recognize_derived_playlist`, `recognize_derived_descriptor`, `recognize_source_reader`, `make_optical_candidate`, `list_committed_scan_files_with_context`, `identify_committed_source_entry_with_context`, `get_game_with_context`, `hydrate_committed_game_with_context`, `hydrate_game_content_with_context`, and `hydrate_game_content_with_sessions_with_context`. The top-level context methods `refresh_committed_root_with_context`, `refresh_game_with_context`, `resolve_game_with_context`, `list_game_ids_with_context`, and `metadata_settings_revision_with_context` must call only these context methods, free functions, and the context's owned/shared fields. Keep existing `KernelBootstrap` public/private compatibility methods as thin delegates when another current caller still uses them:

```rust
pub fn refresh_game_with_context(
    &self,
    game_id: GameId,
    context: &OperationContext,
    now: i64,
) -> Result<u64, ApplicationError> {
    self.library_execution_context()
        .refresh_game_with_context(game_id, context, now)
}
```

Do not duplicate the business algorithm between `KernelBootstrap` and `LibraryExecutionContext`.

- [ ] **Step 4: Change `LibraryRefreshOperationHandler` to own the execution context**

Replace:

```rust
kernel: Arc<Mutex<Option<KernelBootstrap>>>,
```

with:

```rust
execution: LibraryExecutionContext,
```

Delete `LibraryRefreshOperationHandler::with_kernel`.

Construct provider sessions and `ParsingSession` directly:

```rust
let mut sessions = self.execution.create_enrichment_sessions();
let mut parsing_session = ParsingSession::new(
    TransformationBudget::production(),
    self.execution.transformation_staging_root(),
    || stop_reason().is_some(),
)
.map_err(|failure| {
    ApplicationError::from_code(
        argus_application::map_transformation_failure(failure),
        context.trace_id(),
        argus_application::SafeContext::new(),
    )
    .expect("transformation failure uses an allowlisted empty context")
})?;
```

Replace the committed-root call with:

```rust
let is_cancelled = || stop_reason().is_some();
let timestamps = ContentRefreshTimestamps::from_millis(crate::now_millis());
match self.execution.refresh_committed_root_with_context(
    plan,
    context,
    &mut sessions,
    &mut parsing_session,
    timestamps,
    &is_cancelled,
) {
    Ok((_, root_issues)) => {
        issue_count = issue_count.saturating_add(root_issues);
    }
    Err(error) if stop_reason().is_some() => return Err(error),
    Err(_) => {
        issue_count = issue_count.saturating_add(1);
    }
}
```

- [ ] **Step 5: Build the context during registration while the kernel is already available**

Change `register_library_refresh` so it takes `&KernelBootstrap` but no cloned kernel lifecycle handle. Build once:

```rust
let handler = LibraryRefreshOperationHandler::new(
    admitted.plans().to_vec(),
    kernel.unit_of_work_factory().clone(),
    crate::events::EventBusSink::new(kernel.event_bus().clone()),
    kernel.library_execution_context(),
    admitted.job_run_id(),
    100,
    exclusion_count,
);
```

Then change `refresh_library_with_trigger_with_context` to call `register_library_refresh` without `Arc::clone(&handle)`.

- [ ] **Step 6: Run the previously red Library starvation regression**

Run the Task 1 command again.

Expected: PASS while the gate remains held long enough for every foreground query/control assertion to complete, then PASS through terminalization after gate release.

- [ ] **Step 7: Run the existing composed refresh regression**

```bash
bash scripts/run_rust.sh cargo test \
  --manifest-path rust/Cargo.toml \
  --package argus-runtime \
  --all-features \
  --locked \
  --test background_operations \
  manual_library_refresh_composes_committed_scan_identification_grouping_and_hydration \
  -- --exact
```

Expected: PASS with unchanged duplicate convergence, provider isolation, metadata/artwork persistence, JobRun count, and terminal progress.

- [ ] **Step 8: Commit the Library refresh execution-boundary correction**

```bash
git add rust/crates/argus-runtime/src/lib.rs \
        rust/crates/argus-runtime/src/runtime.rs \
        rust/crates/argus-runtime/tests/background_operations.rs
git commit -m "fix: detach library refresh from lifecycle lock"
```

---

### Task 3: Detach Game refresh and local resolution refresh from lifecycle ownership

**Files:**
- Modify: `rust/crates/argus-runtime/src/runtime.rs`
- Modify: `rust/crates/argus-runtime/tests/background_operations.rs`

**Interfaces:**
- Consumes: Task 2 `LibraryExecutionContext`.
- Produces: `Phase003RefreshHandler` is replaced/renamed with a production name that does not carry phase terminology, `LibraryFocusedRefreshHandler`, and owns `LibraryExecutionContext` rather than a kernel handle.

- [ ] **Step 1: Add two failing deterministic regressions before changing the handler**

Add:

```rust
#[test]
fn game_refresh_does_not_starve_foreground_queries()
```

and:

```rust
#[test]
fn library_resolution_refresh_does_not_starve_foreground_queries()
```

For each test:

1. seed one fabricated identified Game with an unblocked Library refresh and obtain its canonical `GameId` through the same `ListGamesQuery::builder()` shape used in Task 1;
2. arm the corresponding `RefreshExecutionCheckpoint`;
3. for Game refresh, create a top-level context with `begin_operation("library", "game_refresh_concurrency")` and call `start_game_refresh_with_context(vec![game_id], RefreshMode::EligibleOnly, &context)`;
4. for local resolution, create a top-level context with `begin_operation("settings", "library_resolution_concurrency")` and call `update_metadata_settings_with_context(&context, MetadataSettings::new(["jp"], ["ja"]))`; extract the admitted handle from `MetadataSettingsUpdateResult::CommittedAndResolutionAdmitted` and fail the test on either other result;
5. wait for `GateState::Entered`;
6. use the exact `assert_foreground_returns` query patterns from Task 1 to execute `list_games`, `list_jobs`, `get_job`, and `library_onboarding_state_with_context` while the gate remains held;
7. release the gate;
8. assert the focused job reaches its existing valid terminal state.

This uses the real production admission paths; neither test constructs a background handler directly.

- [ ] **Step 2: Run both regressions and observe lifecycle-lock failure**

```bash
bash scripts/run_rust.sh cargo test \
  --manifest-path rust/Cargo.toml \
  --package argus-runtime \
  --all-features \
  --locked \
  --test background_operations \
  game_refresh_does_not_starve_foreground_queries \
  -- --exact --nocapture

bash scripts/run_rust.sh cargo test \
  --manifest-path rust/Cargo.toml \
  --package argus-runtime \
  --all-features \
  --locked \
  --test background_operations \
  library_resolution_refresh_does_not_starve_foreground_queries \
  -- --exact --nocapture
```

Expected before the handler correction: each test fails at the bounded foreground-return assertion while its execution gate is held.

- [ ] **Step 3: Rename the private handler and remove its kernel handle**

Rename the private implementation type from the phase-numbered name to:

```rust
struct LibraryFocusedRefreshHandler {
    execution: LibraryExecutionContext,
    job_run_id: JobRunId,
    kind: LibraryFocusedRefreshKind,
}

enum LibraryFocusedRefreshKind {
    Game { game_ids: Vec<GameId> },
    LibraryResolution { settings_revision: u64 },
}
```

Delete its `with_kernel` helper.

The Game loop calls:

```rust
let unit_issues = self
    .execution
    .refresh_game_with_context(game_id, context, crate::now_millis())?;
```

The resolution setup calls:

```rust
let game_ids = self.execution.list_game_ids_with_context(context)?;
let current_settings_revision =
    self.execution.metadata_settings_revision_with_context(context)?;
```

and each local resolution unit calls:

```rust
let unit_issues = self
    .execution
    .resolve_game_with_context(game_id, context, crate::now_millis())?;
```

- [ ] **Step 4: Change focused refresh registration to receive an owned context**

Rename the private registration function to `register_library_focused_refresh` and give it this relevant shape:

```rust
fn register_library_focused_refresh(
    manager: &BackgroundOperationManager<KernelUnitOfWorkFactory>,
    execution: LibraryExecutionContext,
    kernel: &KernelBootstrap,
    context: &OperationContext,
    operation_handle: OperationHandle,
    kind: LibraryFocusedRefreshKind,
) -> Result<(), ApplicationError>
```

`kernel` remains only for registration-failure terminalization that must happen synchronously while admission still has short kernel access. The handler receives `execution` only.

In `start_game_refresh_with_context` and `start_library_resolution_refresh_with_context`, build:

```rust
let execution = kernel.library_execution_context();
```

and pass it to registration. Do not clone the lifecycle `kernel_handle` into either handler.

- [ ] **Step 5: Run the two focused regressions**

Run the Step 2 commands again.

Expected: PASS.

- [ ] **Step 6: Run the complete runtime background-operation integration test target**

```bash
bash scripts/run_rust.sh cargo test \
  --manifest-path rust/Cargo.toml \
  --package argus-runtime \
  --all-features \
  --locked \
  --test background_operations
```

Expected: PASS. Existing scan cancellation, shutdown, event publication, registration-failure terminalization, composed refresh, and new concurrency tests all remain green.

- [ ] **Step 7: Commit the focused refresh correction**

```bash
git add rust/crates/argus-runtime/src/runtime.rs \
        rust/crates/argus-runtime/tests/background_operations.rs
git commit -m "fix: keep focused refreshes query responsive"
```

---

### Task 4: Add a backend-authoritative routing-safe onboarding projection

**Files:**
- Create: `flutter/lib/features/library/application/library_onboarding_routing.dart`
- Generate: `flutter/lib/features/library/application/library_onboarding_routing.g.dart`
- Modify: `flutter/lib/features/library/library.dart`
- Modify: `flutter/test/features/library/library_test_fakes.dart`
- Create: `flutter/test/features/library/library_onboarding_routing_test.dart`
- Modify: `justfile`

**Interfaces:**
- Consumes: `libraryOnboardingApiProvider`, `libraryRuntimeContextProvider`, `LibraryOnboardingState`.
- Produces:
  - `enum LibraryOnboardingRoutingStatus { preReady, required, complete }`
  - immutable `LibraryOnboardingRoutingState` containing `status` and optional `RuntimeInstanceId`;
  - `libraryOnboardingRoutingProvider` (`AsyncNotifierProvider` generated by Riverpod);
  - `LibraryOnboardingRouting.acceptAuthoritative({required RuntimeInstanceId runtimeInstanceId, required LibraryOnboardingState authoritative})`;
  - `LibraryOnboardingRouting.retry()`.

- [ ] **Step 1: Move the reusable onboarding fake into `library_test_fakes.dart`**

Move the current `FakeLibraryOnboardingApi` behavior from `library_onboarding_page_test.dart` into the shared fake file and extend it with:

```dart
int getStateCalls = 0;
Object? getStateFailure;

@override
Future<LibraryOnboardingState> getState() async {
  getStateCalls++;
  final failure = getStateFailure;
  if (failure != null) {
    throw failure;
  }
  return state;
}
```

Keep `confirmMetadataPreferences`, `recordProviderSetup`, and `completeAndRefresh` behavior equivalent to the existing page fake.

- [ ] **Step 2: Write routing-projection tests before production implementation**

Create `library_onboarding_routing_test.dart` with a mutable test runtime-context provider. Cover these exact cases:

```dart
test('pre-ready runtime does not query onboarding authority', () async { ... });
test('ready generation hydrates required state from backend authority', () async { ... });
test('authoritative completion result updates current generation immediately', () async { ... });
test('runtime generation replacement discards projected completion and rehydrates', () async { ... });
test('failed authoritative read publishes AsyncError and retry re-queries', () async { ... });
```

For generation replacement, begin with runtime `aaaaaaaa...`, hydrate incomplete state, publish completion, then change the injected runtime context to `bbbbbbbb...`. Assert the provider no longer exposes the old generation's complete state before the second backend read resolves, and assert the second authoritative result controls the new state.

- [ ] **Step 3: Run the new routing-projection test at the pre-implementation baseline**

```bash
cd flutter && fvm flutter test --no-pub \
  test/features/library/library_onboarding_routing_test.dart
```

Expected on the pre-implementation baseline: FAIL because the routing projection
provider is not yet wired to the runtime-generation and authoritative onboarding
read seams. The completed implementation must pass this test.

- [ ] **Step 4: Implement `library_onboarding_routing.dart`**

Use this state shape:

```dart
import 'package:argus/core/client/client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../library_composition.dart';
import 'library_state.dart';

part 'library_onboarding_routing.g.dart';

enum LibraryOnboardingRoutingStatus { preReady, required, complete }

final class LibraryOnboardingRoutingState {
  const LibraryOnboardingRoutingState._({
    required this.status,
    required this.runtimeInstanceId,
  });

  const LibraryOnboardingRoutingState.preReady()
      : this._(
          status: LibraryOnboardingRoutingStatus.preReady,
          runtimeInstanceId: null,
        );

  const LibraryOnboardingRoutingState.authoritative({
    required RuntimeInstanceId runtimeInstanceId,
    required bool complete,
  }) : this._(
         status: complete
             ? LibraryOnboardingRoutingStatus.complete
             : LibraryOnboardingRoutingStatus.required,
         runtimeInstanceId: runtimeInstanceId,
       );

  final LibraryOnboardingRoutingStatus status;
  final RuntimeInstanceId? runtimeInstanceId;
}

@Riverpod(keepAlive: true)
class LibraryOnboardingRouting extends _$LibraryOnboardingRouting {
  @override
  Future<LibraryOnboardingRoutingState> build() async {
    final runtime = ref.watch(libraryRuntimeContextProvider);
    if (runtime case LibraryRuntimeContextPreReady()) {
      return const LibraryOnboardingRoutingState.preReady();
    }
    final runtimeInstanceId = switch (runtime) {
      LibraryRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
      LibraryRuntimeContextPreReady() => throw StateError('unreachable pre-ready state'),
    };
    final authoritative = await ref.watch(libraryOnboardingApiProvider).getState();
    return LibraryOnboardingRoutingState.authoritative(
      runtimeInstanceId: runtimeInstanceId,
      complete: authoritative.complete,
    );
  }

  void acceptAuthoritative({
    required RuntimeInstanceId runtimeInstanceId,
    required LibraryOnboardingState authoritative,
  }) {
    final runtime = ref.read(libraryRuntimeContextProvider);
    if (runtime case LibraryRuntimeContextReady(
      runtimeInstanceId: final currentRuntimeInstanceId,
    )) {
      if (currentRuntimeInstanceId != runtimeInstanceId) {
        return;
      }
      state = AsyncData(
        LibraryOnboardingRoutingState.authoritative(
          runtimeInstanceId: runtimeInstanceId,
          complete: authoritative.complete,
        ),
      );
    }
  }

  void retry() => ref.invalidateSelf();
}
```

If the generated Riverpod base class requires the pattern-binding syntax to be adjusted for Dart exhaustiveness, preserve these semantics: no API read in pre-ready, generation identity in every authoritative value, and `acceptAuthoritative` publishes only for the currently ready generation.

- [ ] **Step 5: Export the projection and register generated output**

Export from `flutter/lib/features/library/library.dart`:

```dart
export 'application/library_onboarding_routing.dart'
    show
        LibraryOnboardingRouting,
        LibraryOnboardingRoutingState,
        LibraryOnboardingRoutingStatus,
        libraryOnboardingRoutingProvider;
```

Add this exact generated path to `registered_generated_files` in `justfile`:

```text
flutter/lib/features/library/application/library_onboarding_routing.g.dart
```

- [ ] **Step 6: Generate code and run the projection tests**

```bash
just generate
cd flutter && fvm flutter test --no-pub \
  test/features/library/library_onboarding_routing_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the routing projection**

```bash
git add justfile \
        flutter/lib/features/library/application/library_onboarding_routing.dart \
        flutter/lib/features/library/application/library_onboarding_routing.g.dart \
        flutter/lib/features/library/library.dart \
        flutter/test/features/library/library_test_fakes.dart \
        flutter/test/features/library/library_onboarding_routing_test.dart
git commit -m "feat: project onboarding state for routing"
```

---

### Task 5: Make application presentation readiness own onboarding admission

**Files:**
- Modify: `flutter/lib/app/bootstrap/application_presentation.dart`
- Modify: `flutter/lib/app/bootstrap/application_presentation_gate.dart`
- Modify: `flutter/test/app/bootstrap/application_presentation_test.dart`

**Interfaces:**
- Consumes: Task 4 `libraryOnboardingRoutingProvider` and existing `argusClientProvider.supportsLibraryPhase003`.
- Produces the closed readiness vocabulary:

```dart
enum ApplicationPresentationReadiness {
  preReady,
  appearanceInitializing,
  appearanceUnavailable,
  libraryUnavailable,
  onboardingInitializing,
  onboardingUnavailable,
  onboardingRequired,
  ready,
}
```

- [ ] **Step 1: Extend presentation tests first**

Update the test harness so a ready runtime injects a `FakeLibraryOnboardingApi` and `libraryRuntimeContextProvider` derived from `readyRuntimeInstanceIdProvider`.

Add tests that assert:

```text
backend ready + appearance ready + onboarding read pending
  -> onboardingInitializing, normal shell hidden

onboarding read failure
  -> onboardingUnavailable, controlled Retry visible

incomplete authoritative onboarding
  -> onboardingRequired, router child may render onboarding

complete authoritative onboarding
  -> ready, normal router child admitted

client capability does not support Library
  -> libraryUnavailable without querying onboarding API
```

The failure Retry must call `libraryOnboardingRoutingProvider.notifier.retry()` and issue exactly one new authoritative onboarding read. Add a stale-result assertion to the routing-projection test: after switching from runtime generation A to B, `acceptAuthoritative(runtimeInstanceId: A, authoritative: completedState)` must be ignored and must not mark generation B complete.

- [ ] **Step 2: Run the focused presentation tests and observe failure**

```bash
cd flutter && fvm flutter test --no-pub \
  test/app/bootstrap/application_presentation_test.dart
```

Expected: FAIL because current readiness has no onboarding states and the gate admits the routed child immediately after appearance readiness.

- [ ] **Step 3: Extend `applicationPresentationReadiness`**

After existing backend and appearance checks, evaluate in this order:

```dart
if (!ref.watch(argusClientProvider).supportsLibraryPhase003) {
  return ApplicationPresentationReadiness.libraryUnavailable;
}

return ref.watch(libraryOnboardingRoutingProvider).when(
  data: (routing) => switch (routing.status) {
    LibraryOnboardingRoutingStatus.preReady =>
      ApplicationPresentationReadiness.onboardingInitializing,
    LibraryOnboardingRoutingStatus.required =>
      ApplicationPresentationReadiness.onboardingRequired,
    LibraryOnboardingRoutingStatus.complete =>
      ApplicationPresentationReadiness.ready,
  },
  error: (_, _) => ApplicationPresentationReadiness.onboardingUnavailable,
  loading: () => ApplicationPresentationReadiness.onboardingInitializing,
);
```

Do not inspect URI or Library rows here.

- [ ] **Step 4: Extend `ApplicationPresentationGate`**

Keep startup/appearance behavior unchanged. Add:

```dart
ApplicationPresentationReadiness.onboardingInitializing =>
  const Center(child: CircularProgressIndicator()),
ApplicationPresentationReadiness.onboardingUnavailable =>
  _OnboardingInitializationFailureView(
    onRetry: () => ref
        .read(libraryOnboardingRoutingProvider.notifier)
        .retry(),
    onExit: () => ref.read(appTerminatorProvider)(),
  ),
ApplicationPresentationReadiness.libraryUnavailable => child,
ApplicationPresentationReadiness.onboardingRequired => child,
ApplicationPresentationReadiness.ready => child,
```

The failure view text is bounded and non-technical:

```text
Library setup unavailable
Argus could not read the saved Library setup state.
Retry
Exit
```

The gate must not call `LibraryOnboardingApi` directly.

- [ ] **Step 5: Run the focused presentation tests**

Run the Step 2 command again.

Expected: PASS.

- [ ] **Step 6: Commit the combined readiness gate**

```bash
git add flutter/lib/app/bootstrap/application_presentation.dart \
        flutter/lib/app/bootstrap/application_presentation_gate.dart \
        flutter/test/app/bootstrap/application_presentation_test.dart
git commit -m "feat: gate routing on projected onboarding state"
```

---

### Task 6: Remove backend I/O from all routing redirects and prove branch responsiveness

**Files:**
- Modify: `flutter/lib/app/routing/app_router.dart`
- Modify: `flutter/lib/app/routing/app_routes.dart`
- Modify: `flutter/lib/app/bootstrap/application_presentation_gate.dart`
- Modify: `flutter/test/app/routing/app_router_test.dart`

**Interfaces:**
- Consumes: Task 5 `ApplicationPresentationReadiness`.
- Produces: synchronous projection-only global redirect; no `ArgusClient` read in `RootRoute`.

- [ ] **Step 1: Add redirect-purity and active-branch-switching tests**

Add a test with `ApplicationPresentationReadiness.onboardingRequired`, a fake onboarding API, and an initial ready-state route. Pump until `/onboarding/library` renders and assert `getStateCalls == 1`: the single call belongs to `LibraryOnboardingPage._load`; redirect itself must add no call.

Add a second test named:

```dart
testWidgets(
  'ready shell switches branches while the Library initial read is unresolved',
  (tester) async { ... },
);
```

For this test:

1. override `applicationPresentationReadinessProvider` with `ready`;
2. override `libraryRuntimeContextProvider` with a ready runtime ID;
3. provide `FakeLibraryReads.onListGames` returning an unresolved `Completer<GamePage>().future`;
4. provide normal deterministic Sources and Jobs fakes;
5. open `/library` and confirm the Library loading indicator exists;
6. tap Sources, Jobs, Settings, then Library using `tester.pump()` rather than `pumpAndSettle()` while the read remains unresolved;
7. after every tap assert `router.routeInformationProvider.value.uri.path` changes to the requested branch;
8. assert the onboarding fake received no redirect-time read while readiness remained `ready`.

Complete the pending Library future during teardown so no async work leaks across tests.

- [ ] **Step 2: Run router tests and observe current redirect-time I/O/blocking behavior**

```bash
cd flutter && fvm flutter test --no-pub test/app/routing/app_router_test.dart
```

Expected before the router correction: at least the purity assertion fails because `_redirectForLibraryOnboarding` invokes `client.onboarding.getState()`; the unresolved-read branch test may also fail to switch as expected under the old admission path.

- [ ] **Step 3: Replace `_redirectForLibraryOnboarding` with synchronous readiness policy**

In `appRouter`, listen for readiness changes without recreating the router:

```dart
final refresh = _RouterRefresh();
ref.listen<ApplicationPresentationReadiness>(
  applicationPresentationReadinessProvider,
  (previous, next) {
    if (previous != next) {
      refresh.notify();
    }
  },
);
```

Use a synchronous redirect:

```dart
redirect: (context, state) =>
    _redirectForPresentationReadiness(
      ref.read(applicationPresentationReadinessProvider),
      state,
    ),
```

Implement the pure policy with these exact semantics:

```dart
String? _redirectForPresentationReadiness(
  ApplicationPresentationReadiness readiness,
  GoRouterState state,
) {
  final path = state.uri.path;
  final rootPath = const RootRoute().location;
  final onboardingPath = const LibraryOnboardingRoute().location;
  final libraryPath = const LibraryRoute().location;
  final settingsPath = const SettingsRoute().location;
  final isRoot = path == rootPath;
  final isOnboarding = path == onboardingPath;
  final isLibraryDestination =
      destinationForUri(state.uri) == AppDestination.library;

  return switch (readiness) {
    ApplicationPresentationReadiness.libraryUnavailable =>
      isRoot || isOnboarding || isLibraryDestination ? settingsPath : null,
    ApplicationPresentationReadiness.onboardingRequired =>
      isOnboarding ? null : onboardingPath,
    ApplicationPresentationReadiness.ready =>
      isRoot || isOnboarding ? libraryPath : null,
    ApplicationPresentationReadiness.preReady ||
    ApplicationPresentationReadiness.appearanceInitializing ||
    ApplicationPresentationReadiness.appearanceUnavailable ||
    ApplicationPresentationReadiness.onboardingInitializing ||
    ApplicationPresentationReadiness.onboardingUnavailable => null,
  };
}
```

Delete the async redirect function and its `ClientFailure` handling. Backend failures are now represented by `onboardingUnavailable` in the presentation gate.

Now that the router listens to the readiness provider directly, delete the existing readiness listener from `ApplicationPresentationGate` and remove its import of `app_router.dart`. The gate renders readiness states; it no longer owns router invalidation. This prevents duplicate refresh notifications and keeps routing reactions inside the router composition.

- [ ] **Step 4: Remove `RootRoute` client access**

Delete the `argusClientProvider`/client imports from `app_routes.dart` that are used only by `RootRoute.redirect`.

Keep `/` as a forwarding-only route without backend I/O. Because pre-ready routing may temporarily remain at `/` behind `StartupGate`/`ApplicationPresentationGate`, give `RootRoute` a bounded inert builder instead of reading the client:

```dart
@override
Widget build(BuildContext context, GoRouterState state) =>
    const SizedBox.shrink();
```

The global readiness redirect owns `/` -> `/settings`, `/onboarding/library`, or `/library` after its routing-safe state is known.

- [ ] **Step 5: Run router tests**

Run the Step 2 command again.

Expected: PASS, including exactly one onboarding page read in the incomplete case and branch URI changes while the Library read remains unresolved.

- [ ] **Step 6: Commit the pure routing policy**

```bash
git add flutter/lib/app/routing/app_router.dart \
        flutter/lib/app/routing/app_routes.dart \
        flutter/test/app/routing/app_router_test.dart
git commit -m "fix: remove backend reads from routing redirects"
```

---

### Task 7: Reconcile onboarding command results into routing state before navigation

**Files:**
- Modify: `flutter/lib/features/library/presentation/library_onboarding_page.dart`
- Modify: `flutter/test/features/library/library_onboarding_page_test.dart`

**Interfaces:**
- Consumes: Task 4 generation-bound `LibraryOnboardingRouting.acceptAuthoritative`.
- Produces: every authoritative onboarding read/completion result updates the matching runtime generation's routing projection before a navigation callback runs; stale in-flight results from an old generation are ignored.

- [ ] **Step 1: Update onboarding page tests to assert publication ordering**

Use a ready `libraryRuntimeContextProvider` and the real `libraryOnboardingRoutingProvider` in the page-test `ProviderScope`.

In the fresh-folder test and existing-root Finish & Refresh test, make `onOpenLibrary` assert:

```dart
final routing = container.read(libraryOnboardingRoutingProvider).value;
expect(routing?.status, LibraryOnboardingRoutingStatus.complete);
```

before incrementing the navigation counter.

Add a transport-ambiguity/reload test where the authoritative API state becomes complete before `_reload()` finishes; assert the read snapshot updates the routing projection even when completion was not delivered through the command result path.

- [ ] **Step 2: Run the page tests and observe ordering failure**

```bash
cd flutter && fvm flutter test --no-pub \
  test/features/library/library_onboarding_page_test.dart
```

Expected before implementation: FAIL because the page navigates without publishing command/read state into `libraryOnboardingRoutingProvider`.

- [ ] **Step 3: Publish every authoritative read snapshot**

Before starting `_load()`'s authoritative query, capture the current ready runtime identity from `libraryRuntimeContextProvider`. Immediately after:

```dart
final state = await onboarding.getState();
```

publish only against that initiating generation:

```dart
final runtime = ref.read(libraryRuntimeContextProvider);
final runtimeInstanceId = switch (runtime) {
  LibraryRuntimeContextReady(:final runtimeInstanceId) => runtimeInstanceId,
  LibraryRuntimeContextPreReady() => null,
};
if (runtimeInstanceId != null) {
  ref.read(libraryOnboardingRoutingProvider.notifier).acceptAuthoritative(
    runtimeInstanceId: runtimeInstanceId,
    authoritative: state,
  );
}
```

Capture `runtimeInstanceId` before the `await` and pass that captured value after the read completes. `acceptAuthoritative` performs the second current-generation check, so a result from generation A cannot be stamped onto replacement generation B.

- [ ] **Step 4: Publish `completeAndRefresh()` result state before any navigation callback**

Capture the current ready `RuntimeInstanceId` immediately before calling `completeAndRefresh()`. Pattern-match the authoritative `state` in both result variants and publish with that captured generation:

```dart
case CompleteLibraryOnboardingAndRefreshResultAdmitted(
  :final state,
  :final handle,
):
  ref.read(libraryOnboardingRoutingProvider.notifier).acceptAuthoritative(
    runtimeInstanceId: initiatingRuntimeInstanceId,
    authoritative: state,
  );
  widget.onOpenJob(handle.jobRunId);
  widget.onOpenLibrary();

case CompleteLibraryOnboardingAndRefreshResultNotAdmitted(
  :final state,
  :final error,
):
  ref.read(libraryOnboardingRoutingProvider.notifier).acceptAuthoritative(
    runtimeInstanceId: initiatingRuntimeInstanceId,
    authoritative: state,
  );
  // preserve the existing safe snackbar using error.code.value
  widget.onOpenLibrary();
```

If no ready runtime identity exists when the action begins, reject the action through the existing controlled failure path rather than inventing a generation. Apply this to `_completeFreshOnboarding()` and the existing-root `onComplete` callback. Do not issue an extra `getState()` solely to allow routing.

- [ ] **Step 5: Run onboarding page and routing projection tests**

```bash
cd flutter && fvm flutter test --no-pub \
  test/features/library/library_onboarding_page_test.dart \
  test/features/library/library_onboarding_routing_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit onboarding/routing reconciliation**

```bash
git add flutter/lib/features/library/presentation/library_onboarding_page.dart \
        flutter/test/features/library/library_onboarding_page_test.dart
git commit -m "fix: publish onboarding completion before routing"
```

---

### Task 8: Lock in progressive Library presentation and desktop native qualification

**Files:**
- Modify: `flutter/test/features/library/library_page_test.dart`
- Modify: `scripts/run_library_desktop_qualification.sh`

**Interfaces:**
- Consumes: corrected runtime/query concurrency and pure routing.
- Produces: regression evidence that usable Library rows remain visible during reconciliation and macOS native qualification includes the deterministic runtime responsiveness check.

- [ ] **Step 1: Add a Library presentation regression for refresh invalidation**

Construct a `LibraryController`/page with one already returned `GameLibraryRow`. Trigger a `LibraryReconciliationDemandListChanged` while the next `listGames` future remains unresolved.

Assert during that unresolved refresh:

```dart
expect(find.text('Test Game'), findsOneWidget);
expect(find.byType(CircularProgressIndicator), findsNothing);
```

Then complete the request and assert the new backend-owned rows replace/reconcile normally. This locks in the existing `_LibraryBody` rule that the global loading spinner is only valid when `state.games.isEmpty`.

- [ ] **Step 2: Run the Library page test and confirm current presentation behavior remains green**

```bash
cd flutter && fvm flutter test --no-pub \
  test/features/library/library_page_test.dart
```

Expected: PASS. This is a preservation regression; no production Library page change should be needed unless the test reveals a separate defect.

- [ ] **Step 3: Add the deterministic native runtime responsiveness test to the macOS qualification runner**

Before the existing Flutter integration invocation in `run_library_desktop_qualification.sh`, run:

```bash
bash "${ROOT_DIR}/scripts/run_rust.sh" cargo test \
  --manifest-path "${ROOT_DIR}/rust/Cargo.toml" \
  --package argus-runtime \
  --all-features \
  --locked \
  --test background_operations \
  library_refresh_does_not_starve_foreground_queries_or_job_control \
  -- --exact
```

Add:

```bash
RUNTIME_RESPONSIVENESS_LOG="${HOST_EVIDENCE_DIR}/runtime-responsiveness.log"
```

and redirect the targeted Cargo test to that file. If the command fails, record:

```text
result=FAIL
reason=Deterministic native foreground-responsiveness regression failed
 detail=See runtime-responsiveness.log for the bounded tool output
```

then exit nonzero before launching the Flutter integration test.

Do not make this qualification depend on live metadata providers or arbitrary wall-clock slowdowns.

- [ ] **Step 4: Run focused Flutter and desktop qualification**

```bash
cd flutter && fvm flutter test --no-pub \
  test/app/bootstrap/application_presentation_test.dart \
  test/app/routing/app_router_test.dart \
  test/features/library/library_onboarding_routing_test.dart \
  test/features/library/library_onboarding_page_test.dart \
  test/features/library/library_page_test.dart

cd .. && just test-library-desktop-qualification
```

Expected: all Flutter tests PASS and desktop qualification records `result=PASS`.

- [ ] **Step 5: Commit qualification coverage**

```bash
git add flutter/test/features/library/library_page_test.dart \
        scripts/run_library_desktop_qualification.sh
git commit -m "test: qualify foreground refresh responsiveness"
```

Leave `flutter/integration_test/library_lifecycle_qualification_test.dart` unchanged in this task; its existing single-runtime/lifecycle scenario continues to run after the new deterministic native responsiveness check.

---

### Task 9: Generated-source, architecture, regression, and full-repository validation

**Files:**
- Modify generated files only through repository generators.
- No manual qualification result may be marked `PASS` in this task.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: repository-clean implementation evidence suitable for owner macOS MAC-06 retest.

- [ ] **Step 1: Regenerate and verify generated-source registration**

```bash
just generate
just check-generated
```

Expected: PASS and no unregistered `.g.dart`/`.freezed.dart` output.

- [ ] **Step 2: Run formatting and static architecture checks**

```bash
just format
just lint
just _architecture
```

Expected: PASS with no Rust Clippy warnings, Flutter analyzer failures, shellcheck failures, or dependency-boundary violations.

- [ ] **Step 3: Run the full Rust runtime test target**

```bash
bash scripts/run_rust.sh cargo test \
  --manifest-path rust/Cargo.toml \
  --package argus-runtime \
  --all-features \
  --locked
```

Expected: PASS.

- [ ] **Step 4: Run all Flutter tests**

```bash
cd flutter && fvm flutter test --no-pub
```

Expected: PASS.

- [ ] **Step 5: Run deterministic Library qualification**

```bash
just test-deterministic-qualification
```

Expected: PASS without network, real credentials, or copyrighted ROM data.

- [ ] **Step 6: Run macOS native Library qualification**

```bash
just test-library-desktop-qualification
```

Expected: PASS including the new deterministic foreground-responsiveness native check.

- [ ] **Step 7: Run the canonical full repository gate**

```bash
just check
```

Expected: PASS.

- [ ] **Step 8: Validate Android-preservation coverage when the configured API 36 ARM64 environment is available**

```bash
just test-phase-002-android-foreground
just test-library-android-qualification
```

Expected when the required Android environment is available: PASS without a second runtime/database authority. If the environment is unavailable, record these as `NOT RUN`/deferred evidence rather than fabricating success; deterministic and desktop gates remain mandatory for implementation review.

- [ ] **Step 9: Review the diff for contract invariants**

Verify all of these directly from the final diff:

```text
No background handler field has Arc<Mutex<Option<KernelBootstrap>>>.
No long-running refresh method reacquires the kernel lifecycle handle.
No GoRouter redirect calls onboarding.getState() or another focused API.
RootRoute performs no ArgusClient/native read.
No Flutter-only persisted onboarding completion flag exists.
No schema/migration/bridge DTO changed.
No provider timeout/retry behavior changed.
No production source/API name contains P03, Phase003, or slice terminology.
The manual qualification ledger still leaves MAC-06 as NOT RUN for owner execution.
```

- [ ] **Step 10: Require a clean worktree after all committed implementation and generator output**

```bash
git status --short
```

Expected: no output. If formatting or generation changed a tracked file after its owning task was committed, return to that owning task, inspect the exact diff, rerun its focused tests, and amend that task's commit before accepting the final gate. Do not create a catch-all commit that could absorb unrelated files.

---

## Owner Qualification After Implementation

Implementation completion does not close Phase 003. After review and a release/production macOS artifact is available, execute `MAC-06` in `docs/implementation/phase-003-manual-qualification.md` against a representative real Library:

```text
Start or continue an active Library refresh.
While it is still active:
  Library -> Sources -> Jobs -> Settings -> Library
  inspect Jobs and Library state
  exercise a safe available job control when applicable
```

Acceptance is direct observation that navigation and focused reads/control remain usable before refresh terminalization, an already usable Library does not revert to global blocking loading solely because refresh work is active, and the background job remains truthful. Record the result append-only in the manual qualification ledger; do not rewrite historical P03-009 evidence.
