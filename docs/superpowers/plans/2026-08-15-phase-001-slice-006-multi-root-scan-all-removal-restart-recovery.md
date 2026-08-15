# SLICE-P01-006 — Multi-Root Scan All, Removal, and Restart Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Phase 001 operational lifecycle with one durable multi-root Scan All job, safe cancel-and-remove root deletion, historical Jobs detail after removal, and mandatory persistence-only restart reconciliation before `Ready`.

**Architecture:** Extend the existing Slice 005 LibraryScan admission/retry/persistence contracts rather than creating a second path. Scan All durably snapshots requested/admitted/excluded roots into one `JobRun`, registers one job-level handler, and executes existing per-root scan plans sequentially. Root removal remains an independent mutation after authoritative no-owner proof; startup recovery reconciles stale persisted LibraryScan state before readiness without provider I/O or automatic resume.

**Tech Stack:** Rust application/runtime/infrastructure crates, SQLite migrations/repositories, flutter_rust_bridge generated bindings, pure-Dart ArgusClient models/APIs, Flutter/Riverpod/Freezed, repository `just` validation.

## Global Constraints

- Binding design: `docs/superpowers/specs/2026-08-15-phase-001-slice-006-multi-root-scan-all-removal-restart-recovery-design.md`.
- Binding governed contracts: Phase 001 roadmap, SPEC-BE-004/007/008/013, SPEC-FE-003/008/009, SPEC-X-001.
- Rust/SQLite remains the sole durable authority; do not create parallel runtime, persistence, event, scan, Jobs, or Sources authority paths.
- One root has at most one active `ScanRun` owner across single-root, Scan All, and retry attempts.
- Scan All executes admitted roots sequentially in Phase 001, but sequential execution must not become a persisted/public compatibility invariant.
- Scan All preserves the full typed exclusion contract: `AlreadyScanning(rootId, activeJobRunId, activeScanRunId)`, `NoLongerConfigured(rootId)`, and `InvalidConfiguration(rootId, canonical bounded ApplicationError)`. The bounded error is reconstructed exactly from persistence through the error catalog; no free-form failure string is substituted.
- Scan All admitted-target order is durable and deterministic: canonical historical `LibraryRootId` ascending. Admission, persisted target reads, execution-plan reconstruction, retry revalidation, recovery, and job-detail projection all use this same order. Never rely on SQLite row order, insertion accident, timestamps, or random `ScanRunId` tie-breaks.
- Cancellation is job-scoped. No root-scoped cancellation exists in Phase 001.
- No automatic Resume or restart continuation. `LibraryScan` remains non-resumable.
- Positive observations already committed by incomplete scans remain valid; cancellation/recovery never grants absence authority.
- Root removal changes only Argus-owned configuration/current indexed state and never modifies user files.
- Historical Jobs detail must remain intelligible after current roots are removed.
- Startup reconciliation performs no provider I/O, enumeration, new admission, retry, Resume, or other significant user work; failure prevents readiness.
- Scan All transport ambiguity must be reconciled idempotently through a durable client request identity and must never create a duplicate job.
- No Phase 002 content/transformation behavior, policy changes, speculative scheduler abstraction, or parallel root enumeration.
- Do not edit governed specification documents as part of implementation unless implementation exposes a true contract defect; report such a defect instead of silently changing scope.
- Do not stage, commit, or push implementation changes unless the delegation explicitly authorizes it. Preserve unrelated user-owned work exactly.

---

## File Structure / Responsibility Map

- `rust/crates/argus-application/src/jobs.rs`: LibraryScan invocation vocabulary, multi-root admitted payload, Scan All/retry admission, aggregate completion/recovery semantics, request-id lookup contract, and the typed `InvalidConfiguration` exclusion carrying a canonical bounded `ApplicationError`.
- `rust/crates/argus-application/src/sources/library.rs`: Scan All application command/result facade only if Sources ownership fits existing service boundaries; root removal remains separate.
- `rust/crates/argus-application/src/sources/scan.rs`: reuse/extract per-root execution so a job-level multi-root handler can sequentially execute child plans without duplicating traversal/reconciliation.
- `rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0007_scan_all_recovery.sql`: additive schema evolution for Scan All invocation kinds/request identity, bounded exclusion-error persistence, deterministic target ordering, and recovery support.
- `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`, `sources.rs`, `unit_of_work.rs`: persistence/query implementations for multi-root admission, request-id lookup, stale-run recovery, and historical projections.
- `rust/crates/argus-runtime/src/runtime.rs`, `startup.rs`, `background.rs`: one job-level registration path, multi-root execution, cancellation cleanup, and mandatory pre-ready reconciliation.
- `rust/crates/argus-bridge/src/lib.rs` plus generated FRB output: governed Scan All DTO/API mapping and ambiguity lookup.
- `flutter/lib/core/client/**`: pure-Dart typed Scan All and request-reconciliation models/methods.
- `flutter/lib/features/sources/**`: global Scan All command state and guided cancel-and-remove flow.
- `flutter/lib/features/jobs/**`: render existing typed multi-root detail/history without acquiring Sources authority.
- Focused tests in each touched layer plus native restart/integration coverage where deterministic.

---

### Task 1: Add durable multi-root Scan All admission contracts

**Files:**
- Modify: `rust/crates/argus-application/src/jobs.rs`
- Modify as needed: `rust/crates/argus-application/src/sources/library.rs`
- Test: `rust/crates/argus-application/tests/jobs.rs`
- Create/Test: `rust/crates/argus-application/tests/slice_006_scan_all.rs`

**Interfaces:**
- Produces `LibraryScanInvocationKind::{InitialScanAll, RetryScanAll}` with persisted values `initial_scan_all` / `retry_scan_all`.
- Produces a multi-root admitted payload carrying one `JobRunId` plus an ordered `Vec<LibraryScanExecutionPlan>`; do not overload the existing single-root `AdmittedScan` with fake semantics if a distinct `AdmittedLibraryScanJob` is clearer.
- Produces `StartLibraryScanAllResult::{Admitted { operation_handle, admitted_roots, exclusions }, NothingEligible { exclusions }}` and application admission data required by runtime registration.
- Produces a typed client request identity value owned by application/bridge semantics, unique for Scan All admission ambiguity reconciliation.
- Extends `LibraryScanAdmissionExclusion` so `InvalidConfiguration` carries the canonical bounded `ApplicationError` (persisted as code + trace id + safe-context entries and reconstructed via `ApplicationError::from_code`); `AlreadyScanning` and `NoLongerConfigured` keep their existing shape byte-compatible.
- Admission snapshots the configured-root set and evaluates/inserts targets in canonical historical `LibraryRootId` ascending order so the admitted-target order is durable and reproducible from `library_scan_target` rows alone.

- [x] **Step 1: Write failing application tests for full, partial, and zero-eligible admission.** Assert one job for all eligible roots, one child run per eligible root, durable requested/admitted/excluded rows, `AlreadyScanning`/`InvalidConfiguration` exclusions, and no job for `NothingEligible`. Assert every `InvalidConfiguration` exclusion carries the canonical bounded `ApplicationError` (code `ConfigurationInvalid`, message key, and safe context preserved) and that admitted targets persist in canonical historical `LibraryRootId` ascending order.
- [x] **Step 2: Run the focused tests and verify they fail for missing Scan All contracts.** Use the repository Rust test wrapper or the exact crate test command established by existing Slice 005 tests.
- [x] **Step 3: Implement the minimal typed Scan All admission model and handler.** Snapshot the configured-root set once via `LibraryRootQueries::list_root_configurations`, sort it by canonical historical `LibraryRootId` ascending, validate every target in that order, construct each `InvalidConfiguration` exclusion with `ApplicationError::from_code(ErrorCode::ConfigurationInvalid, trace_id, bounded safe_context)`, and allocate one `JobRun`, all admitted `ScanRun`s, immutable context, target rows, and events inside one coherent admission transaction.
- [x] **Step 4: Extend invocation-kind parsing/serialization without changing generic `JobRun`.** Existing `InitialSingleRoot`/`RetrySingleRoot` values must remain byte-for-byte compatible.
- [x] **Step 5: Add durable client request identity semantics.** A repeated identical request identity must return the existing accepted Scan All outcome/identity rather than allocate a second job; a fresh identity may create a new independent attempt.
- [x] **Step 6: Run application tests and confirm all Slice 001–005 application tests remain green.**

### Task 2: Persist Scan All metadata and historical/recovery queries

**Files:**
- Create: `rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0007_scan_all_recovery.sql`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/migrations/mod.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/unit_of_work.rs`
- Test: `rust/crates/argus-infrastructure/tests/jobs.rs`
- Create/Test: `rust/crates/argus-infrastructure/tests/slice_006_scan_all_recovery.rs`

**Interfaces:**
- `library_scan_admission_context.invocation_kind` accepts all four LibraryScan invocation values.
- Scan All request identity is persisted under an operation-specific unique constraint; it is not a new logical Job ID and does not change `job_run` generic schema semantics.
- `library_scan_target` persists the bounded `InvalidConfiguration` error (exclusion error code, trace id, and serialized safe-context entries) and reconstructs the exact `ApplicationError` through the error catalog; `AlreadyScanning`/`NoLongerConfigured` rows store no error and keep their existing columns.
- Persisted target reads order by `historical_library_root_id ASC` within each target kind so requested/admitted/excluded reconstruction is deterministic regardless of row order, timestamps, or generated IDs.
- Repository/query ports can: resolve request identity to existing Scan All admission, enumerate stale active LibraryScan jobs/children/exclusions, and rebuild authoritative historical job detail without current root rows.

- [x] **Step 1: Write migration tests for fresh schema and representative 0006 -> 0007 upgrade.** Seed single-root history, retry links, current roots, removed-root historical target snapshots, an `InvalidConfiguration` exclusion with its bounded error, and active scan rows before migration.
- [x] **Step 2: Verify the migration tests fail before schema registration.**
- [x] **Step 3: Implement additive migration and repository mappings.** Extend the `library_scan_admission_context` invocation-kind CHECK via a SQLite table rebuild; add `library_scan_all_request_identity` and the exclusion error columns (`exclusion_error_code`, `exclusion_error_trace_id`, `exclusion_error_safe_context`) with validation that `InvalidConfiguration` rows always carry all three and other reasons never do; order target reads by `historical_library_root_id ASC`; preserve prior invocation values, FK integrity, target snapshots, active-root uniqueness, and nullable progress behavior.
- [x] **Step 4: Add request-identity lookup tests.** Same identity resolves the same job; uniqueness prevents a duplicate accepted Scan All admission.
- [x] **Step 5: Add stale-execution query tests.** Query must distinguish active parent state, cancellation intent, already-terminal children, and stale running children without provider access.
- [x] **Step 6: Add historical-detail tests after deleting current root configuration.** Job detail must still contain display name/safe location from durable scan/target snapshots and reconstruct `InvalidConfiguration` exclusion errors exactly (code, trace id, safe context). Add an ordering regression test with multiple children sharing the same admission timestamp proving detail order comes from canonical root-ID ordering, not timestamps or `ScanRunId`.
- [x] **Step 7: Run infrastructure migration/repository suites and full migration chain.**

### Task 3: Build one sequential job-level LibraryScan handler and runtime registration path

**Files:**
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Modify: `rust/crates/argus-application/src/jobs.rs`
- Modify: `rust/crates/argus-runtime/src/runtime.rs`
- Modify if required: `rust/crates/argus-runtime/src/background.rs`
- Create/Test: `rust/crates/argus-runtime/tests/slice_006_scan_all.rs`

**Interfaces:**
- Runtime registers exactly one background job for one multi-root admission.
- Job-level handler owns child plans ordered by canonical historical `LibraryRootId` ascending and delegates each child to the existing per-root traversal/reconciliation implementation.
- Job-level completion derives parent state from durable requested/admitted/excluded scope plus all child outcomes.
- Job-detail scan-run projection for LibraryScan jobs orders children by canonical historical `LibraryRootId` ascending (replacing the existing `started_at`/`scan_run_id` tie-break) so multi-root presentation matches the durable admitted order.

- [x] **Step 1: Write failing runtime tests proving multiple admitted roots belong to one manager registration/job.** Assert sequential child start order equals canonical historical `LibraryRootId` ascending, including a regression test where all children share the same admission timestamp, under the existing filesystem resource capacity.
- [x] **Step 2: Write mixed-outcome tests.** A failed/unavailable child must not prevent a later eligible child from running; aggregate state must be `CompletedWithIssues` when meaningful successful work exists and requested scope is incompletely satisfied.
- [x] **Step 3: Extract/reuse per-root execution without duplicating indexing code.** The same reconciliation, checkpoints, last-scan updates, source-entry events, and absence-authority rules used by single-root scans must execute for each child plan.
- [x] **Step 4: Implement job-level cancellation semantics.** Completed children remain immutable; active child cooperatively cancels; not-yet-started admitted children are durably terminalized `Cancelled`; parent becomes `Cancelled` when cancellation determines termination.
- [x] **Step 5: Implement registration-failure cleanup for all admitted children.** If manager registration fails after durable admission, terminalize every admitted running child plus parent coherently and return a definite application error, never `NothingEligible`.
- [x] **Step 6: Run focused runtime tests plus existing single-root/retry runtime tests.**

### Task 4: Generalize Retry to preserve original Scan All intent

**Files:**
- Modify: `rust/crates/argus-application/src/jobs.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`
- Test: `rust/crates/argus-application/tests/slice_005_retry_eligibility.rs`
- Create/Test: `rust/crates/argus-application/tests/slice_006_scan_all_retry.rs`
- Test: `rust/crates/argus-infrastructure/tests/slice_005_retry.rs`

**Interfaces:**
- Retry reconstructs all original `Requested` roots for a Scan All source attempt.
- New successor context is `RetryScanAll` and carries the source job identity.
- Existing shared eligibility function remains the single source for `canRetry` and retry target exclusions.
- Retry revalidates original requested targets in canonical historical `LibraryRootId` ascending order and reconstructs `InvalidConfiguration` exclusions with the same bounded `ApplicationError` contract as initial admission.
- Multi-root admitted retry payload is consumable by the job-level runtime registration path from Task 3.

- [x] **Step 1: Write failing tests for multi-root retry with mixed current eligibility.** Include removed root -> `NoLongerConfigured`, active owner -> `AlreadyScanning`, invalid configuration -> `InvalidConfiguration` carrying its canonical bounded `ApplicationError`, plus at least one admitted target, with exclusions in canonical root-ID order.
- [x] **Step 2: Write zero-eligible retry and linear-chain tests.** No empty successor; `AlreadyRetried` returns the existing direct successor; later retry starts from the latest attempt.
- [x] **Step 3: Generalize retry admission from one admitted plan to N plans while preserving single-root behavior.** Do not broaden intent to roots added after the original request.
- [x] **Step 4: Update projection/control tests so `canRetry` remains derived from the same eligibility evaluation used by admission.**
- [x] **Step 5: Run application/infrastructure retry suites for Slice 005 and 006.**

### Task 5: Implement mandatory persistence-only startup recovery

**Files:**
- Modify: `rust/crates/argus-application/src/jobs.rs`
- Modify: `rust/crates/argus-runtime/src/startup.rs`
- Modify: `rust/crates/argus-runtime/src/runtime.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`
- Create/Test: `rust/crates/argus-runtime/tests/slice_006_restart_recovery.rs`
- Extend: `rust/crates/argus-runtime/tests/kernel_bootstrap.rs` or existing startup tests where appropriate.

**Interfaces:**
- A focused application recovery handler receives persistence repositories only; no `LibrarySourceAccess`/provider capability is in its constructor.
- Startup ownership: `StartupCoordinator`/`startup.rs` invokes the mandatory stale-LibraryScan reconciliation inside `CoreServicesInitialization` after core services compose and before `EventInfrastructureInitialization`/`ReadinessValidation`. `runtime.rs` may expose composition/capability plumbing only; `ApplicationRuntime` must not acquire subsystem-specific startup sequencing.
- Recovery returns success/failure only after all stale LibraryScan state is coherent.

- [x] **Step 1: Write failing recovery tests covering stale active child without cancellation -> `Abandoned`, with accepted cancellation intent -> `Cancelled`, and already-terminal children preserved.**
- [x] **Step 2: Add aggregation tests for process death after children terminalized but before parent aggregation.** Parent must derive from durable child outcomes/exclusions instead of defaulting to `Abandoned`.
- [x] **Step 3: Add root-summary/ownership tests.** Recovered child outcome updates last-scan summary; `Cancelled`/`Abandoned` does not change availability; active ownership is cleared; source entries remain.
- [x] **Step 4: Implement bounded persistence-only reconciliation and wire it into `CoreServicesInitialization` at the `StartupCoordinator`/`startup.rs` invocation site.** No provider resolution, scan handler creation, manager registration, retry, or Resume may occur, and reconciliation must complete before `EventInfrastructureInitialization`.
- [x] **Step 5: Add startup-failure test.** A persistence reconciliation failure must prevent `Ready` and surface through the normal startup-failure contract.
- [x] **Step 6: Run startup/runtime suites and verify no automatic work is admitted after recovery.**

### Task 6: Activate bridge and pure-Dart Scan All contracts

**Files:**
- Modify: `rust/crates/argus-bridge/src/lib.rs`
- Generated: `rust/crates/argus-bridge/src/frb_generated.rs` and Flutter FRB output via `just generate`
- Modify: `flutter/lib/core/client/models.dart`
- Modify: `flutter/lib/core/client/ports.dart`
- Modify: `flutter/lib/core/client/argus_client.dart`
- Modify gateway files under `flutter/lib/core/bridge/**` as required by existing Slice 005 composition.
- Test: `rust/crates/argus-bridge/tests/**`
- Test: Flutter core client tests under `flutter/test/core/**`.

**Interfaces:**
- `SourcesApi.startLibraryScanAll(requestId)` returns typed `Admitted`/`NothingEligible` results with admitted-root IDs and typed exclusions.
- `LibraryScanAdmissionExclusionDto` gains `application_error: Option<ApplicationErrorDto>` populated only for `InvalidConfiguration`, mapped with the existing `application_error_dto`; the pure-Dart `LibraryScanAdmissionExclusion` carries the corresponding bounded `ClientApplicationError?` and never exposes generated DTOs.
- Focused lookup/reconciliation API resolves the same Scan All request identity to accepted admission or authoritative no-admission proof.
- `RemoveLibraryRootResult.rootHasActiveScan` continues carrying `owningJobRootCount` exactly.

- [x] **Step 1: Write failing bridge/client mapping tests for full/partial/none Scan All outcomes and every exclusion variant.** Include `InvalidConfiguration` with its canonical bounded `ApplicationError` (code, message key, safe context round-trip exactly) and assert `AlreadyScanning`/`NoLongerConfigured` mapping stays shape-compatible.
- [x] **Step 2: Write request-id contract mismatch/idempotency tests.** Invalid required representations become canonical client contract mismatch; no generated DTO leaks into feature layers.
- [x] **Step 3: Implement bridge DTO/API mappings and pure-Dart models/ports.** Keep restart recovery internal to startup; add no frontend recovery mutation.
- [x] **Step 4: Run `just generate` and never hand-edit generated output.**
- [x] **Step 5: Run bridge/client tests and `just check-generated`.**

### Task 7: Add Sources Scan All and cancel-and-remove workflows

**Files:**
- Modify: `flutter/lib/features/sources/application/root_list_controller.dart`
- Modify: `flutter/lib/features/sources/application/root_detail_controller.dart`
- Modify: `flutter/lib/features/sources/application/sources_state.dart`
- Modify: `flutter/lib/features/sources/sources_composition.dart`
- Modify: `flutter/lib/features/sources/presentation/sources_page.dart`
- Modify: `flutter/lib/features/sources/presentation/root_detail_page.dart`
- Modify: `flutter/lib/features/sources/presentation/remove_root_dialog.dart`
- Modify: `flutter/lib/features/sources/presentation/sources_messages.dart`
- Generated Freezed/Riverpod files via normal generation.
- Test: Sources controller/widget tests under `flutter/test/features/sources/**`.

**Interfaces:**
- Root-list state owns Scan All initiation/synchronization state but not full job detail.
- Successful admission stays on `/sources`, exposes concise admitted/excluded feedback and `View Job` using returned authoritative `JobRunId`.
- `NothingEligible` presentation: because no `JobRun` exists, Sources itself presents the typed bounded exclusion reasons (`AlreadyScanning`, `InvalidConfiguration`, `NoLongerConfigured`) with no fabricated job and no `View Job` action. Exact durable multi-root detail lives in Jobs only for admitted Scan All.
- Cancel-and-remove flow is `cancelJob -> authoritative root/job reconciliation -> prove no active owner -> removeLibraryRoot`.

- [x] **Step 1: Write failing Scan All controller/widget tests.** Control hidden at authoritative `totalCount == 0`, available at `> 0`, does not infer eligibility from loaded page, preserves confirmed roots while pending, and stays on Sources after admission.
- [x] **Step 2: Add partial-admission and NothingEligible presentation tests.** Partial admission shows a concise summary plus `View Job` and delegates exact detail to Jobs. `NothingEligible` shows the typed exclusion reasons directly on Sources (focused coverage for `AlreadyScanning` and `InvalidConfiguration` reasons), with no job card and no `View Job`.
- [x] **Step 3: Add ambiguous transport test using stable request identity.** Controller must reconcile/lookup the original request and must not generate a second request identity or blindly replay a new Scan All mutation.
- [x] **Step 4: Write active removal tests.** Known active owner opens `Cancel Scan & Remove` directly; `owningJobRootCount > 1` explicitly discloses that other roots in the job are stopped.
- [x] **Step 5: Implement authoritative cancellation sequencing.** Definite cancel failure stops removal. Ambiguous cancellation reconciles. Removal occurs only after root reads prove active ownership ended.
- [x] **Step 6: Add removal-race test.** A direct remove returning `RootHasActiveScan` enters the same guided workflow rather than surfacing a generic error.
- [x] **Step 7: Add successful removal navigation/state cleanup tests.** Removed root disappears after authoritative refresh, hierarchy/transient state is pruned, `/sources/roots/:removedId` canonicalizes to `/sources`, and other roots remain usable.
- [x] **Step 8: Run focused Sources controller/widget/accessibility tests.**

### Task 8: Complete Jobs multi-root presentation and restart-visible state

**Files:**
- Modify as required: `flutter/lib/features/jobs/application/job_detail_controller.dart`
- Modify: `flutter/lib/features/jobs/presentation/job_detail_page.dart`
- Modify: `flutter/lib/features/jobs/presentation/jobs_messages.dart`
- Test: `flutter/test/features/jobs/**`

**Interfaces:**
- Jobs consumes only authoritative typed `LibraryScanJobDetail`; it does not query current Sources roots for historical labels.
- Existing Cancel/Retry controls remain backend-authoritative.

- [x] **Step 1: Write failing widget tests for multiple per-root rows, admission exclusions, mixed terminal outcomes, and `CompletedWithIssues`.**
- [x] **Step 2: Add removed-root history test.** Historical display/safe location remains rendered after Sources no longer contains the root.
- [x] **Step 3: Add retry relationship test for Scan All successor/source navigation.**
- [x] **Step 4: Implement only the presentation/controller changes required by those typed models.** Do not create a second Sources-like root authority inside Jobs.
- [x] **Step 5: Run Jobs controller/widget/accessibility tests.**

### Task 9: End-to-end verification and scope audit

**Files:**
- Add or extend deterministic integration tests under `flutter/integration_test/**` and Rust runtime tests only where required by the approved design.
- Update only implementation-owned test support needed for deterministic stale-state setup; do not add production backdoors.

- [x] **Step 1: Exercise one canonical multi-root scenario in automated tests.** Add/configure two test-owned roots, Scan All, observe independent child outcomes, retry where applicable, and verify one job identity per attempt.
- [x] **Step 2: Exercise cancel-and-remove with a multi-root owner.** Confirm whole-job cancellation semantics and prove user filesystem test data remains untouched.
- [x] **Step 3: Exercise restart recovery against the same isolated application-data directory.** Persist an intentionally stale active LibraryScan fixture through governed test seams, start a replacement runtime, and prove reconciliation completes before `Ready` with no automatic scan execution.
- [x] **Step 4: Run `just generate`, `just check-generated`, and `just check`.** If generated inputs did not change after the final generation pass, `just check-generated` must be clean.
- [x] **Step 5: Run repository validation profile `all` through the approved validation workflow when available.** Report any infrastructure blocker truthfully; do not claim deferred/manual evidence passed.
- [x] **Step 6: Perform a final scope audit.** Confirm no parallel root execution, root-scoped cancellation, Resume, auto-restart work, discovery-policy changes, Phase 002 behavior, governed-doc edits, or unrelated refactors were introduced.
- [x] **Step 7: Write the Delegation v3 `RESULT.json` with concrete TAC/PAC evidence and exact validation truth.**

## Self-Review

- **Spec coverage:** Tasks 1–4 cover Scan All admission, execution, aggregation, retry, request-identity ambiguity, and registration failure. Task 5 covers mandatory startup recovery. Tasks 6–8 cover bridge/client/Sources/Jobs behavior, including active removal coordination and removed-root history. Task 9 covers canonical cross-layer behavior and scope gates.
- **Type consistency:** The plan keeps generic `JobRun` capability-neutral, extends operation-specific invocation kinds, uses one multi-root admitted job payload end-to-end, preserves the existing shared retry-eligibility authority, carries the canonical bounded `ApplicationError` for `InvalidConfiguration` end-to-end, and applies canonical historical `LibraryRootId` ascending ordering consistently across admission, persistence, execution, retry, recovery, and Jobs projection.
- **Scope:** Sequential execution is an implementation policy only. No parallel scheduler abstraction, Resume, root-scoped cancellation, or Phase 002 work is introduced.
- **No placeholders:** Every required behavior is assigned to a concrete task and test cycle; implementation naming may follow existing repository naming where exact generated wrapper names are mechanically determined by FRB/Riverpod generation.
