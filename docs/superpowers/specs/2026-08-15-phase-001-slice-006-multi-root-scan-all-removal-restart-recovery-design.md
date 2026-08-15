# SLICE-P01-006 — Multi-Root Scan All, Removal, and Restart Recovery

## 1. Outcome

Complete the remaining Phase 001 operational lifecycle before cross-platform hardening: multiple configured roots can participate in one durable Scan All job with independent per-root outcomes; root removal coordinates safely with active job ownership; terminal Jobs history remains intelligible after root removal; and stale active LibraryScan execution is reconciled before runtime readiness after restart without automatic resume.

This slice extends the existing Slice 005 single-root admission, retry, Jobs detail, Sources controllers, runtime background manager, and SQLite authority. It must not create parallel runtime, persistence, event, scan, or frontend authority paths.

## 2. Binding contracts

The design is governed by:

- `docs/phases/phase-001-local-sources-and-indexing.md`, especially Sections 4.6, 8.5, 8.6, 8.7, and Slice P01-006;
- `SPEC-BE-013`, especially Scan All admission, durable admission context, terminal aggregation, cancellation, removal, retry, and restart recovery;
- `SPEC-BE-008` for Scan All and root-removal bridge result vocabulary;
- `SPEC-BE-004` for generic background-operation lifecycle, resource admission, cancellation, and terminal-state authority;
- `SPEC-BE-007` for mandatory startup reconciliation before `Ready`;
- `SPEC-FE-008` for Scan All and cancel-and-remove Sources behavior;
- `SPEC-FE-009` for Jobs detail, mixed per-root outcomes, retry, and historical root snapshots;
- all Slice 001–005 implemented behavior, including authoritative source-graph reconciliation, event-driven query reconciliation, linear retry identity, and backend-derived control availability.

Where an implementation detail is not fixed below, the governed specifications remain authoritative.

## 3. Approved design decisions

### 3.1 Sequential root execution

One Scan All request creates one durable `LibraryScan` `JobRun` with one child `ScanRun` per admitted root. The job executes admitted roots sequentially in Phase 001.

Sequential execution is chosen because the product contract does not require parallel root enumeration, while the existing `BackgroundOperationManager` already owns top-level scheduling/resource admission. This keeps cancellation, aggregation, persistence, and recovery centered on one job execution without introducing speculative intra-job scheduling infrastructure.

The persisted contract must not encode "sequential" as a permanent product invariant. Future bounded parallelism may change execution policy without changing Scan All identity, child-run, retry, removal, or recovery semantics.

### 3.2 Stay on Sources after Scan All admission

After Scan All admission, `/sources` remains the active destination. It presents concise typed admission feedback and a `View Job` action rather than automatically navigating to Jobs.

Sources remains the launch/root-local operational surface. Jobs remains the authoritative full execution-detail surface.

### 3.3 Active-root removal enters Cancel Scan & Remove directly

If the current authoritative root projection already reports active ownership, selecting removal opens the `Cancel Scan & Remove` confirmation directly instead of first issuing a knowingly blocked `RemoveLibraryRoot` request.

`RemoveLibraryRoot -> RootHasActiveScan` remains the required race fallback when ownership changed after the UI last reconciled.

## 4. Scan All durable admission

### 4.1 Requested scope

`StartLibraryScanAll` snapshots the complete configured-root set that forms the user-requested scope at admission time. Flutter never derives this scope from the currently loaded root page.

For each requested root, admission independently evaluates current configuration validity and active ownership.

Each requested root becomes exactly one of:

- admitted: a new durable `ScanRun` is created and root ownership is acquired;
- excluded as `AlreadyScanning` with the existing owning job/scan identity;
- excluded as `InvalidConfiguration` with the canonical bounded `ApplicationError`.

`NoLongerConfigured` remains part of the shared exclusion vocabulary for retry revalidation, not a normal initial Scan All result after the authoritative configured-root snapshot is acquired coherently.

If no root is eligible, the result is `NothingEligible(exclusions)` and no empty `JobRun` is created.

### 4.2 Coherent accepted admission

An accepted Scan All admission is durable only when one coherent boundary owns:

- the generic `JobRun`;
- immutable LibraryScan admission context;
- every requested-root historical display snapshot;
- every admitted `ScanRun` and frozen execution plan;
- every typed admission exclusion;
- root ownership for every admitted child;
- enough runtime handoff state to establish `BackgroundOperationManager` responsibility or coherently terminalize an admitted execution if registration fails.

The operation handler must consume these persisted/frozen child identities and plans. It must not rebuild the requested root set from mutable configuration after admission.

### 4.3 Invocation vocabulary

Extend the existing operation-specific `LibraryScanInvocationKind` with:

- `InitialScanAll` / persisted `initial_scan_all`;
- `RetryScanAll` / persisted `retry_scan_all`.

The generic `JobRun` remains capability-neutral. Scan All identity stays in `library_scan_admission_context` and the existing target rows.

A migration must preserve all existing Slice 005 history and extend the admission-context check constraint without rewriting prior invocation meaning.

## 5. Multi-root operation handler

### 5.1 One job-level handler

A Scan All job is registered exactly once with `BackgroundOperationManager` and consumes the normal LibraryScan resource classes.

The job-level LibraryScan handler owns an ordered collection of the admitted child plans. It executes each plan through the existing per-root traversal/reconciliation semantics rather than introducing another indexing implementation.

The per-root logic must retain all Slice 003–005 guarantees:

- provider I/O outside write transactions;
- incremental positive-observation durability;
- exact-scope absence authority only after complete fresh authority;
- conservative move preservation;
- root availability semantics;
- cancellation only at governed safe checkpoints;
- truthful `Complete`, `Partial`, `Failed`, `Cancelled`, and `Abandoned` child outcomes.

### 5.2 Root ordering

The job uses a deterministic order derived from the durable admitted-target order. No product meaning is assigned to that order; it exists only for reproducible sequential execution and testing.

Later root additions never enter an already-admitted job.

### 5.3 Failure isolation

An ordinary root-level `Partial`, `Failed`, or `Unavailable` result does not abort later admitted roots. The handler continues with the next child unless job-scoped cancellation or an unrecoverable job-level infrastructure failure prevents safe continuation.

A child that has become terminal is never rewritten because of a later child's result.

## 6. Multi-root terminal aggregation

The parent `JobRun` terminal result is derived from durable requested/admitted/excluded facts plus durable child outcomes.

Required mapping:

- all requested roots admitted and every child `Complete` -> `Completed`;
- meaningful successful work exists but requested scope was not fully satisfied -> `CompletedWithIssues`;
- no meaningful indexing result exists across admitted work -> `Failed`;
- accepted cancellation determines termination -> `Cancelled`;
- restart reconciliation without accepted cancellation intent leaves stale active children -> `Abandoned`.

`CompletedWithIssues` includes partial admission, `Partial` children, and mixed successful/failed child outcomes where meaningful durable success exists.

The aggregation function must be application-owned and shared by normal multi-root completion and restart recovery so the two paths cannot drift.

## 7. Job-scoped cancellation

Cancellation continues to target the owning `JobRun`, never an individual child root.

During sequential execution:

1. a child already terminal before cancellation remains unchanged;
2. the currently executing child observes cancellation at its existing safe checkpoints and terminalizes `Cancelled` if cancellation determines its termination;
3. admitted children that have not begun must be terminalized `Cancelled` without provider traversal;
4. committed positive observations from interrupted work remain valid;
5. cancellation grants no absence authority;
6. the parent becomes `Cancelled` when cancellation determines the job's termination.

The multi-root job handler therefore needs an operation-owned before-execution/remaining-child terminalization path, not fake execution of children solely to mark them cancelled.

## 8. Registration failure after durable admission

If Scan All application admission commits but runtime registration with `BackgroundOperationManager` fails, Argus must preserve the accepted job and child identities and coherently terminalize all admitted child runs plus the parent.

The caller receives a definite canonical application error. It must never receive `NothingEligible` or another result implying no execution identity was created.

This generalizes the Slice 005 `fail_unregistered_scan` invariant from one child to all admitted children owned by the job.

## 9. Retry of multi-root jobs

Retry continues the existing linear attempt-chain contract.

For an original Scan All attempt, retry reconstructs only the original requested roots from durable history, revalidates each current target, and creates a new Scan All attempt when at least one target remains eligible.

The successor records:

- invocation kind `RetryScanAll`;
- `retry_source_job_run_id` pointing at the immediately preceding attempt;
- requested historical root snapshots for the inherited original scope;
- new admitted children for currently eligible roots;
- typed exclusions for removed, invalid, or actively owned targets.

Retry never broadens to roots added after the original Scan All request.

If no target is eligible, no successor job is created. `AlreadyRetried` remains idempotent and the retry graph remains linear.

The same shared eligibility evaluation continues to drive backend `canRetry` and retry admission.

## 10. Root removal

### 10.1 Removal without active ownership

`RemoveLibraryRoot(root_id)` remains an application-owned configuration/current-index mutation only.

Successful removal coherently:

- removes the current `LibraryRoot` configuration;
- removes the root's current Argus-managed `SourceEntry` graph and current dependent source provenance required by the existing contracts;
- leaves the internal LocalFilesystem source reusable;
- preserves terminal `JobRun`, `ScanRun`, target, retry-link, and historical root snapshot data;
- never touches user filesystem content.

A current root route canonicalizes to `/sources` after authoritative removal is observed. Root-keyed transient hierarchy/detail state is discarded only after authoritative proof that the root no longer exists.

### 10.2 Removal with active ownership

If the current root projection already exposes an active owner, Sources opens `Cancel Scan & Remove` directly.

The confirmation must state both destructive boundaries:

- Argus configuration/index state will be removed;
- files on disk remain untouched.

When `owningJobRootCount > 1`, it must also state that cancelling the owning Scan All job stops work for the other roots in that job. The UI must never imply root-scoped cancellation.

The required mutation sequence is:

```text
user confirms Cancel Scan & Remove
    -> JobsApi.cancelJob(jobRunId)
    -> authoritative job + root reconciliation
    -> prove root has no active owner
    -> SourcesApi.removeLibraryRoot(rootId)
    -> authoritative Sources reconciliation
```

### 10.3 Race and ambiguity behavior

If `RemoveLibraryRoot` returns `RootHasActiveScan`, the UI enters the same guided cancel-and-remove flow rather than reporting a generic failure.

If cancellation fails definitely, removal stops.

If cancellation has an ambiguous transport result, removal also stops until authoritative job/root reads prove ownership ended. The cancel request must not be blindly replayed and destructive removal must not be inferred safe from transport failure.

If ownership changes to another job before removal, the new typed owner result is authoritative and the UI must not delete through stale assumptions.

## 11. Historical Jobs behavior after removal

Jobs detail remains intelligible without querying current Sources state.

Requested/admitted/excluded root display uses the durable bounded historical snapshots already stored with LibraryScan target/run history. Removing a root must not blank, relabel, or invalidate old job detail.

A removed root's historical identity remains historical only. Re-adding the same physical folder creates a new `LibraryRootId`; it must not retroactively satisfy old retry targets.

## 12. Mandatory restart reconciliation

### 12.1 Startup position

During `CoreServicesInitialization`, after Phase 001 persistence/services are composed and before event-infrastructure initialization and `Ready`, startup runs one bounded mandatory LibraryScan stale-execution reconciler.

Failure of this reconciler fails `CoreServicesInitialization` and prevents readiness.

### 12.2 Recovery restrictions

The reconciler performs only persistence reads/writes. It performs no:

- LocalFilesystem/provider access;
- directory enumeration;
- source-entry discovery;
- new scan admission;
- retry admission;
- Resume;
- automatic restart of significant work.

No synthetic pre-ready feature event is required because normal frontend consumers are not connected before `Ready`; post-ready authoritative queries observe reconciled state.

### 12.3 Child recovery

For every stale LibraryScan job from a prior runtime generation:

1. already-terminal child `ScanRun`s remain unchanged;
2. a stale `Running` child becomes `Cancelled` when durable cancellation intent had already been accepted for the parent job;
3. otherwise a stale `Running` child becomes recovery-only `Abandoned`;
4. stale root ownership is therefore cleared by terminalizing the child record;
5. each recovered child updates the current root's last-scan summary if that root still exists;
6. recovered `Cancelled` and `Abandoned` outcomes do not change root availability merely because execution stopped;
7. committed positive observations remain untouched and no recovered incomplete child gains absence authority.

Removed roots are not recreated merely to receive a recovery summary.

### 12.4 Parent recovery

If every child was already terminal when startup begins, derive the still-active parent using the normal shared LibraryScan aggregation function plus durable admission exclusions.

Otherwise:

- any recovery-cancelled stale child under accepted job cancellation yields parent `Cancelled`;
- stale active children without accepted cancellation become `Abandoned`, and the parent becomes `Abandoned`.

The reconciler must not overwrite already-terminal children to force parent consistency.

## 13. Flutter Sources behavior

### 13.1 Scan All control

`/sources` shows one global `Scan All` action when authoritative root-list `totalCount > 0` and the normal runtime/read-admission guard allows interaction.

Flutter must not inspect only loaded root rows to predict eligibility. Backend admission remains the authority.

While Scan All admission is unresolved, only conflicting Scan All initiation is disabled. Existing confirmed root state remains usable.

### 13.2 Admission results

For `Admitted`, Sources remains on `/sources` and shows concise operation-local feedback:

- scan admitted;
- admitted-root count;
- whether exclusions exist;
- `View Job` for durable details.

For `NothingEligible`, Sources remains in place and presents the typed bounded reasons. No empty job card or fabricated execution is shown.

Partial admission is success with exclusions, not a generic error.

A transport-ambiguous Scan All result has execution-identity consequences and must not be blindly replayed. The Sources controller enters synchronization-uncertain state and reconciles authoritative Jobs/Sources state before allowing another conflicting Scan All submission. Because existing Slice 005 projections do not identify a newly admitted Scan All attempt independently of a returned `JobRunId`, Slice 006 adds one narrowly focused authoritative Jobs query keyed by a client-generated request identity carried only for Scan All admission ambiguity reconciliation. That request identity is durable operation metadata, not a second logical Job identity. Repeating the same request identity after transport ambiguity is an idempotent lookup of the already-established admission outcome and must never create a second job. Flutter must not infer admission from root `lastScan` fields or from coincidence across multiple root histories.

## 14. Flutter cancel-and-remove state

Root removal coordination belongs to the existing Sources feature/controller layer, not Jobs UI and not a new global workflow authority.

The controller preserves the last confirmed root/list/hierarchy while cancellation, ownership reconciliation, or removal is pending.

The local workflow state must distinguish at least:

- ordinary remove confirmation;
- cancel-and-remove confirmation with owner identity and owning-root count;
- cancellation pending;
- authoritative ownership reconciliation;
- removal pending;
- synchronization uncertain / retryable reconciliation failure.

Stale async completions must not remove a newly selected/recreated root or overwrite a newer workflow generation.

## 15. Flutter Jobs behavior

The existing Jobs detail architecture expands naturally to multi-root Scan All jobs.

It renders:

- requested/admitted counts;
- typed exclusions;
- independent per-root `ScanRun` rows/cards and outcomes;
- `CompletedWithIssues` distinctly from clean completion and failure;
- historical root display snapshots after current root removal;
- factual aggregate progress without invented percentages;
- job-scoped cancellation and linear retry using existing backend-derived control availability.

Sources must not duplicate this detailed multi-root presentation.

## 16. Bridge and pure-Dart client surface

Activate the already governed focused Scan All contract:

```text
StartLibraryScanAll()
    -> Admitted(operationHandle, admittedRoots, exclusions)
     | NothingEligible(exclusions)
```

The bridge/client must preserve typed target exclusions and identities exactly and must not collapse partial admission into generic success/failure strings.

Root removal continues to map:

```text
Removed
RootHasActiveScan(libraryRootId, jobRunId, scanRunId, owningJobRootCount)
```

Restart reconciliation is startup-internal and requires no new frontend command.

The Scan All ambiguity-reconciliation query is narrow, authoritative, and typed: it resolves the durable client request identity to either the accepted Scan All `JobRunId`/admission outcome or proof that no admission exists. It must not expose raw persistence models or provider-native data.

## 17. Persistence evolution

A Slice 006 migration may extend LibraryScan-specific persistence only as required for the governed contracts.

Required schema behavior:

- extend `library_scan_admission_context.invocation_kind` to accept `initial_scan_all` and `retry_scan_all` while preserving existing rows;
- preserve historical root display snapshots and target rows after `LibraryRoot` deletion;
- preserve retry-link integrity and one-successor/one-predecessor constraints;
- keep the active-root uniqueness invariant across all single-root and multi-root jobs;
- support bounded queries for stale active LibraryScan recovery;
- persist the Scan All client request identity with a uniqueness constraint sufficient for idempotent ambiguity lookup without changing generic `JobRun` identity semantics;
- preserve the full Phase 000 -> Slice 006 migration chain and representative upgrade data.

Do not add a separate logical Job identity, a root-scoped cancellation table, or persistence that encodes frontend transient workflow state.

## 18. Testing strategy

Implementation must be test-driven and cover at minimum:

### 18.1 Application and persistence

- Scan All full admission with multiple roots;
- partial admission with typed exclusions;
- zero eligible roots creates no `JobRun`;
- deterministic requested/admitted target snapshots;
- active-root uniqueness under concurrent/racing admission;
- multi-root retry preserving original requested scope;
- retry exclusions for removed/invalid/active roots;
- registration failure terminalizes parent and every admitted child coherently;
- removal preserves historical job/scan/target/retry data;
- re-add creates a new root identity;
- migration upgrade from Slice 005 schema/data.

### 18.2 Execution and cancellation

- sequential root execution;
- one root failure does not prevent later roots from running;
- mixed outcomes aggregate to `CompletedWithIssues` when meaningful success exists;
- all-complete aggregates to `Completed`;
- no-meaningful-success aggregates to `Failed`;
- cancellation after one completed child preserves that child;
- active child and never-started remaining children become `Cancelled` without granting absence authority;
- per-root positive observations survive parent cancellation.

### 18.3 Restart recovery

- stale active child + accepted cancellation intent -> child and parent `Cancelled`;
- stale active child without cancellation intent -> child and parent `Abandoned`;
- already-terminal children remain unchanged;
- all children terminal but parent stale -> parent derived through normal aggregation;
- root summaries repaired for still-configured roots;
- removed roots are not recreated;
- `Cancelled`/`Abandoned` recovery does not alter availability;
- no provider I/O, enumeration, retry, Resume, or new admission occurs;
- reconciliation failure prevents `Ready`.

### 18.4 Bridge/client and Flutter

- exact Scan All DTO/model mapping;
- partial and `NothingEligible` presentation;
- Sources stays on the current destination after successful admission;
- `View Job` targets the admitted identity;
- ambiguous Scan All transport reconciles without blind replay;
- active-root removal opens the guided flow directly;
- race `RootHasActiveScan` enters the same flow;
- multi-root confirmation discloses whole-job cancellation impact;
- cancellation ambiguity never proceeds destructively;
- removal occurs only after authoritative no-owner proof;
- historical Jobs detail remains useful after removal;
- stale async completion and runtime-replacement reconciliation remain safe;
- responsive, keyboard, focus, and accessibility behavior remains compliant.

## 19. Verification

The implementation must leave generated output current and pass the repository's canonical automated quality gates, including focused Rust/Flutter tests, generated-code verification, and `just check` through the approved validation workflow.

Any native restart/E2E proof introduced specifically for Slice 006 must use isolated test-owned application data and filesystem roots and must never operate on the developer's real library.

## 20. Explicit exclusions

Slice 006 does not add:

- parallel root enumeration or a configurable intra-job scheduler;
- root-scoped cancellation;
- Resume;
- automatic restart continuation or retry;
- changes to Phase 001 discovery policy, reconciliation authority, or move semantics;
- new source providers;
- game-oriented Library semantics;
- Phase 002 transformation/content capabilities;
- a second Jobs/Sources authority path;
- speculative generic workflow infrastructure not required by Scan All, removal, or restart recovery.

## 21. Invariants to preserve

1. Rust/SQLite remains the sole durable authority.
2. One root has at most one active scan owner across all LibraryScan jobs.
3. One Scan All invocation owns one durable `JobRun` and independent durable child `ScanRun`s.
4. Already-terminal child outcomes are immutable.
5. Positive observations survive partial, failed, cancelled, and abandoned attempts.
6. Incomplete work never gains absence authority.
7. Cancellation is job-scoped and never represented as root-scoped.
8. Removing a root never modifies user files.
9. Root removal never destroys terminal job history needed to understand prior work.
10. Retry creates fresh execution identities, preserves original requested intent, and remains a linear chain.
11. Restart recovery is mandatory before `Ready`, persistence-only, and never automatically resumes significant work.
12. Events remain invalidations/notifications; authoritative queries remain the source of truth.
