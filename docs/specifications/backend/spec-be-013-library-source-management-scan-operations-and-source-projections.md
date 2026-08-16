# Library Source Management, Scan Operations, and Source Projections Specification

**Document ID:** SPEC-BE-013  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-15  
**Depends On:** ARCH-001, ARCH-002, PHASE-001, PHASE-002, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-006, SPEC-BE-007, SPEC-BE-009, SPEC-BE-011, SPEC-X-001, SPEC-X-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative Phase 001 application contract for local library-folder management, local-library scan admission and execution semantics, durable job/scan projections, source hierarchy queries, retry/cancellation/removal behavior, and user-facing source projections.

It is the first concrete application of the MVP-wide background-work pattern in which feature capabilities own domain-specific work admission and semantics, `BackgroundOperationManager` owns generic execution lifecycle, and `JobsService` owns capability-neutral observation and control.

This specification does not redefine source-provider indexing correctness. `SPEC-BE-011` remains authoritative for source access, traversal, reconciliation, exact-scope authority, move detection, classification boundaries, source-entry identity, availability interpretation, and scan-specific terminal semantics.

## 2. Responsibilities

This specification owns:

- the Phase 001 `LibraryService` capability surface;
- the generic `JobsService` capability surface required by Phase 001;
- one internally managed local-filesystem `LibrarySource` per Argus data store;
- add/list/detail/remove workflows for local library folders;
- the `AddLocalLibraryRootAndScan` composite workflow;
- single-root and multi-root library-scan admission semantics;
- typed admission outcomes and exclusions;
- `LibraryScan` operation-handler responsibilities;
- retry reconstruction and revalidation semantics;
- root-removal coordination with active scan ownership;
- durable `ScanRun` history projections and bounded historical root snapshots;
- root/source-entry/job query projections;
- source hierarchy pagination and ordering requirements;
- LibraryScan-specific structured progress facts;
- LibraryScan mapping to generic `JobRun` terminal states;
- Phase 001 application events and authoritative reconciliation expectations;
- persistence, scalability, security, and testing requirements for these contracts.

## 3. Non-Responsibilities

This specification does not own:

- provider-native filesystem APIs or path parsing;
- `RootLocator`, `RelativeSourceLocator`, `SourceLocatorKey`, provider-native identity, source fingerprints, or source-access algorithms;
- exact source reconciliation rules already defined by `SPEC-BE-011`;
- logical `GameContent` creation or identity;
- parsing, archive expansion, hashing, metadata, artwork, or RetroAchievements workflows;
- filesystem watching or automatic periodic scanning;
- automatic resume of significant user work;
- long-term job/scan-history pruning policy;
- bridge DTO shape or transport mapping, owned by `SPEC-BE-008`;
- Flutter routing, controller, or presentation behavior, owned by focused frontend specifications;
- generic runtime scheduling, lifecycle, recovery, and cancellation mechanics, owned by `SPEC-BE-004`.

## 4. Architectural Principles

1. Feature capabilities own domain-specific background-operation admission and semantics.
2. `BackgroundOperationManager` owns generic `JobRun` lifecycle, scheduling, cancellation coordination, retry/resume admission mechanics, recovery, and resource admission.
3. `JobsService` owns generic persisted job queries and user-requested lifecycle controls without depending on feature services.
4. A feature-specific operation handler owns feature workflow logic, progress facts, retry semantics, and mapping of feature outcomes to generic job terminal-state requests.
5. Application services remain capability-oriented rather than CRUD-oriented.
6. Application services never depend directly on other application services.
7. Durable state is authoritative; events are notification/invalidation aids only.
8. `LibraryRoot` identity, configured location, display label, availability, historical scan outcome, and active scan ownership remain distinct concepts.
9. Provider-owned locators remain opaque to generic application code and Flutter.
10. Source hierarchy APIs remain bounded and scalable for libraries containing hundreds of thousands of entries.
11. Historical execution records must remain understandable after mutable current entities are removed or reconfigured.
12. No background job may falsely report a clean completion when the user-requested operation scope was only partly satisfied.

## 5. Layer and Ownership Model

The canonical background-work path is:

```text
feature capability / workflow coordinator
    ↓
domain-specific background admission
    ↓
OperationHandle(JobRunId)
    ↓
BackgroundOperationManager
    ↓
operation-specific handler
```

For library scanning:

```text
LibraryService / focused workflow handler
    ↓
LibraryScan admission
    ↓
OperationHandle(JobRunId)
    ↓
BackgroundOperationManager
    ↓
LibraryScanOperationHandler
    ↓
source-provider access + reconciliation + persistence
```

The runtime never owns source traversal or reconciliation rules. `LibraryService` never owns generic scheduling or job-state mutation authority.

## 6. Public Application Interfaces

### 6.1 `LibraryService`

`LibraryService` owns the Phase 001 source/library capabilities:

```text
ListLibraryRoots
GetLibraryRoot
AddLocalLibraryRoot
AddLocalLibraryRootAndScan
RemoveLibraryRoot

ListSourceEntryChildren
GetSourceEntry

StartLibraryScan
StartLibraryScanAll
```

Exact Rust trait/method syntax is an implementation detail, but each capability is a distinct application operation with one authoritative owner.

### 6.2 `JobsService`

`JobsService` owns capability-neutral job observation and control:

```text
GetJob(JobRunId)
ListJobs(...)
CancelJob(JobRunId)
RetryJob(JobRunId)
ResumeJob(JobRunId)
```

`ResumeJob` is valid only for operation types that explicitly declare resumability. `LibraryScan` is retryable and non-resumable.

`JobsService` must not contain LibraryScan traversal, root-selection, metadata-refresh, artwork, hashing, or verification logic.

### 6.3 Operation-specific detail

A generic job detail projection contains a capability-neutral `JobRun` projection plus one typed operation-detail variant.

Conceptually:

```text
JobDetail
- job
- operation_detail

OperationDetail
- LibraryScan(LibraryScanJobDetail)
- future typed variants
```

An arbitrary JSON extension bag is prohibited as the primary extensibility mechanism.

## 7. Internal Local-Filesystem `LibrarySource`

Each Argus application-data store has at most one durable Argus-managed `LibrarySource` whose provider type is `LocalFilesystem`.

Rules:

1. It is created lazily when the first local library folder is added.
2. Every Phase 001 local `LibraryRoot` references this same `LibrarySourceId`.
3. Its source-level provider configuration is empty or minimal according to `SPEC-BE-011`; it may include provider-owned opaque platform authorization material where the platform requires it. User-selected folder coordinates belong to each root.
4. It has no user-facing create, rename, configure, or delete operation in Phase 001.
5. Removing the final root does not require deleting the internal local-filesystem source.
6. Later local roots reuse the durable source identity.
7. Future provider types may introduce independently configured `LibrarySource` instances without changing this Phase 001 rule.

## 8. Local Folder Selection and Root Creation

### 8.1 Selection boundary

Flutter/native UI supplies a typed local-filesystem folder selection, not an authoritative serialized `RootLocator`.

Conceptually:

```text
native folder picker
    ↓
LocalFilesystemRootSelection
    ↓
LocalFilesystem provider validation
    ↓
provider-owned RootLocator
```

The LocalFilesystem provider owns validation and construction of the persisted locator. Generic application code may transport the typed value through the relevant port but must not parse, normalize, split, canonicalize, or infer filesystem semantics from it.

### 8.2 Display name

Every `LibraryRoot` persists an application-owned `display_name` distinct from its provider-owned `root_locator`.

The initial display name is derived from provider-supplied safe display information, normally the selected folder name.

Phase 001 requires no rename UI. Display names need not be globally unique.

### 8.3 Overlap and duplicate outcomes

Provider relationship semantics from `SPEC-BE-011` remain authoritative:

```text
Same
Ancestor
Descendant
Disjoint
Unknown
```

`AddLocalLibraryRoot` returns a typed operation-specific outcome equivalent to:

```text
Added(root)
AlreadyConfigured(existing_root_id)
OverlapsExisting(existing_root_id, relationship)
```

Rules:

- `Same` returns `AlreadyConfigured` when it represents the already-configured root;
- provider-verifiable `Ancestor` and `Descendant` relationships return `OverlapsExisting`;
- `Disjoint` is admissible;
- `Unknown` is conservatively admissible;
- no rejected duplicate/overlap mutation becomes authoritative;
- generic application code never derives relationship semantics by comparing locator strings.
- repeating the exact same validated local-folder selection is idempotent and returns `AlreadyConfigured(existing_root_id)` without creating a duplicate root, mutating the existing root, or emitting a second root-created event.

## 9. `AddLocalLibraryRootAndScan`

`AddLocalLibraryRootAndScan` is one explicit application workflow with two durable boundaries.

Conceptually:

```text
validate selection and overlap
    ↓
create/persist LibraryRoot
    ↓
COMMIT ROOT
    ↓
request child LibraryScan background admission
    ↓
return typed committed result
```

The workflow uses a narrow runtime-supplied background-admission capability permitted by `SPEC-BE-009`; it does not depend on `JobsService`.

Representative outcomes are:

```text
AddedAndScanAdmitted(root, operation_handle)
AddedButScanNotAdmitted(root, child_issue)
AlreadyConfigured(existing_root_id)
OverlapsExisting(existing_root_id, relationship)

LibraryScanChildAdmissionIssue
├── AlreadyScanning(active_job_run_id, active_scan_run_id)
└── AdmissionFailure(application_error)
```

`AdmissionFailure` carries the canonical bounded `ApplicationError`; it never substitutes a free-form reason string or raw runtime/provider failure.

After a transport-ambiguous `AddLocalLibraryRootAndScan` result, callers must not blindly replay the composite workflow. They may replay only the idempotent `AddLocalLibraryRoot` step with the exact same typed selection to establish the authoritative root identity, then query the root and Jobs projections. Only after authoritative state shows that no child scan admission was established may the caller issue an explicit `StartLibraryScan` request. This preserves the original folder intent without risking duplicate jobs.

Rules:

1. Root persistence completes before scan admission begins.
2. Scan-admission failure after root commit never rolls back the root.
3. Duplicate/overlap outcomes create neither a new root nor a scan job.
4. Transport ambiguity is reconciled through authoritative root/job queries rather than blind workflow replay.
5. The individual `AddLocalLibraryRoot` and `StartLibraryScan` capabilities remain available for workflows that need them separately.

## 10. Library Scan Admission

Library scan admission has two distinct boundaries:

```text
application admission (LibraryService)
    validates request/ownership, freezes the plan, creates JobRun + ScanRuns, acquires root ownership
    ↓
runtime admission (BackgroundOperationManager)
    registers the run, validates resource/scheduling policy, begins execution
```

A failure before the application admission boundary creates no `JobRun` or `ScanRun`. A failure after durable admission is represented through the normal `JobRun`/`ScanRun` lifecycle (`Failed`, `Partial`, or `Cancelled` as applicable) rather than a phantom rollback of admitted state.

### 10.1 Single-root scan

`StartLibraryScan(root_id)`:

1. verifies the configured root still exists;
2. checks active scan ownership;
3. freezes the effective scan plan/configuration revision required by `SPEC-BE-011`;
4. creates one durable `JobRun`;
5. creates one associated durable `ScanRun` in the active `Running` state;
6. establishes runtime responsibility according to `SPEC-BE-004`;
7. returns `OperationHandle(JobRunId)`.

If the root already has an active scan owner, no competing job or `ScanRun` is created. The typed outcome identifies the existing ownership, equivalent to:

```text
AlreadyScanning
- library_root_id
- active_job_run_id
- active_scan_run_id
```

### 10.2 Scan All

`StartLibraryScanAll` evaluates all configured roots independently at admission.

Rules:

1. Eligible roots are admitted into one new `LibraryScan` `JobRun`.
2. Each admitted root receives one new `ScanRun` in the active `Running` state.
3. Already-owned or otherwise non-admissible roots are excluded with typed reasons.
4. Excluded roots receive no fake `ScanRun`.
5. Existing scans are not queued behind or absorbed into the new job.
6. Eligible roots may proceed even when other requested roots are excluded.
7. If no root is eligible, no empty `JobRun` is created.
8. The admission result includes the operation handle, admitted roots, and typed exclusions.

The shared typed exclusion vocabulary is:

```text
LibraryScanTargetExclusion
├── AlreadyScanning(root_id, active_job_run_id, active_scan_run_id)
├── NoLongerConfigured(root_id)
└── InvalidConfiguration(root_id, application_error)
```

Initial Scan All admission normally uses `AlreadyScanning` and `InvalidConfiguration`; retry revalidation may additionally produce `NoLongerConfigured`. `application_error` is the canonical bounded `ApplicationError`, never a free-form or raw provider failure.

### 10.3 Durable LibraryScan admission context

Every accepted LibraryScan `JobRun` durably captures immutable operation-specific admission context sufficient for history, terminal aggregation, and retry reconstruction.

Conceptually:

```text
LibraryScanAdmissionContext
- job_run_id
- invocation_kind
- requested_roots[]
    - historical_library_root_id
    - bounded root display snapshot
- admitted_roots[]
    - historical_library_root_id
    - scan_run_id
- admission_exclusions[]
    - historical_library_root_id
    - typed reason
    - related active job/scan identity when applicable
- retry_source_job_run_id nullable
```

Rules:

1. A single-root request captures exactly that requested `LibraryRootId` when a job is admitted.
2. Scan All captures the configured root set that formed the user-requested scope at admission time; later root additions do not retroactively become part of that job.
3. Requested/admitted/excluded identity is based on stable `LibraryRootId`, not later provider-locator equivalence.
4. Removing and re-adding the same physical folder creates a new root identity and does not make an old retry target current again.
5. Admission exclusions are durable operation facts, not command-response-only warnings, because they affect job detail and terminal aggregation.
6. Retry reconstructs original intent from this durable context and then revalidates current state.
7. Requested/admission context is immutable after the admission boundary; per-root execution outcome continues to evolve through the associated `ScanRun`s.

### 10.4 Coherent admission durability

LibraryScan admission succeeds only after all state required to identify and recover the accepted execution is durably or deterministically owned.

For an accepted job this includes:

- the generic `JobRun`;
- `LibraryScanAdmissionContext`;
- every newly admitted `ScanRun`;
- the mapping between the job and those scan runs; and
- `BackgroundOperationManager` responsibility according to `SPEC-BE-004`.

An admission failure must not leave an orphan nonterminal `JobRun`, orphan active `ScanRun`, or accepted operation context with no manager responsibility. Exact transaction/handoff mechanics are implementation details, but the caller-visible durability invariant is mandatory.

For `AddLocalLibraryRootAndScan`, this invariant begins only after the independently committed root-creation boundary. Failure of child scan admission may leave the root configured, but must not leave partial background-operation state.

Before enumeration starts, every admitted child `ScanRun` already exists durably in the active `Running` state with its immutable scan plan and root ownership established. No child identity, plan, or ownership is created inside the operation handler.

## 11. `ScanRun` Model and Historical Provenance

One `ScanRun` describes one root scan inside one generic job execution attempt.

Conceptually:

```text
ScanRun
- id
- job_run_id
- historical_library_root_id
- root_display_snapshot
- scan_plan/configuration_provenance
- status
- started_at
- completed_at nullable
- bounded result facts
```

Canonical scan statuses remain governed by `SPEC-BE-011`:

```text
Running
Complete
Partial
Failed
Cancelled
Abandoned
```

`Running` is the only active status and exists from durable admission until terminalization. Terminal statuses are `Complete`, `Partial`, `Failed`, `Cancelled`, and recovery-only `Abandoned`; root last-scan summaries additionally use `NeverScanned` and root-level `Unavailable` according to `SPEC-BE-011`.

`ScanRun` and `JobRun` are deliberately not one-to-one concepts; one multi-root `JobRun` may own multiple `ScanRun`s.

### 11.1 Historical root snapshot

At scan admission, Argus captures bounded immutable user-meaningful root presentation context sufficient to understand the historical run after the current root is removed.

The snapshot:

- retains the historical `LibraryRootId`;
- retains the historical `display_name` and one backend-supplied `safe_location_display` sufficient to disambiguate similarly named roots in Jobs history;
- does not require the live root row to remain present;
- does not preserve provider-native identity, locator equality keys, fingerprints, or unnecessary raw provider configuration;
- does not require indefinite retention of absolute filesystem coordinates.

Terminal historical runs remain immutable except for metadata explicitly allowed by generic job contracts.

## 12. Root Projections

### 12.1 Separate state dimensions

`LibraryRootProjection` exposes independent authoritative dimensions rather than one combined status enum.

Conceptually:

```text
LibraryRootProjection
- root_id
- display_name
- safe_location_presentation
- availability
- last_scan nullable
- active_scan nullable
```

When present, `last_scan.status` uses `Complete`, `Partial`, `Unavailable`, `Cancelled`, `Failed`, or `Abandoned`; absence represents `NeverScanned`. `Cancelled` and `Abandoned` summarize execution history and do not independently change `availability`.

`availability` uses the application-owned evidence vocabulary from `SPEC-BE-011`:

```text
Available
Unavailable
Unknown
```

`last_scan` is an optional historical terminal summary and may include:

```text
scan_run_id
job_run_id
status
started_at
completed_at
```

`active_scan` is an optional current ownership summary and may include:

```text
scan_run_id
job_run_id
job lifecycle/progress summary
```

Flutter may derive user-facing labels from these facts but may not replace them with frontend-owned authority.

### 12.2 Root listing

Root lists are bounded administrative datasets and may use bounded offset pagination according to `ARCH-001`.

Backend ordering is deterministic and appends a stable unique-ID tie-breaker.

## 13. Source Entry Projections

Persisted provider locators remain internal.

The user-facing source projection is equivalent to:

```text
SourceEntryProjection
- source_entry_id
- parent_source_entry_id nullable
- display_name
- display_location
- kind
- classification
- bounded observation/status facts
```

`display_location` is an application-owned provider-neutral presentation projection derived from safe normalized provider facts.

It is:

- relative to the configured root;
- suitable for local user presentation;
- not `RelativeSourceLocator`;
- not `SourceLocatorKey`;
- not source identity;
- not an equality token;
- not a reopen token.

Flutter must not receive or parse opaque provider locators merely to render hierarchy.

## 14. Source Hierarchy Queries

The canonical child query is equivalent to:

```text
ListSourceEntryChildren(
    root_id,
    parent_source_entry_id nullable,
    cursor nullable,
    page_size
)
```

Rules:

1. `parent_source_entry_id = null` addresses direct root children.
2. Child browsing uses cursor pagination.
3. Page size is bounded by backend policy.
4. Ordering is deterministic and ends in a unique-ID tie-breaker.
5. The backend owns ordering needed for stable paging; Flutter must not reorder a partial page as though it were the full set.
6. No query requires materializing the full tree.
7. Phase 001 defines no source-entry search/filter API.
8. `GetSourceEntry` returns one bounded detail projection without exposing provider/persistence internals.
9. `GetSourceEntry` accepts the globally unique `SourceEntryId` only. Requiring both `LibraryRootId` and `SourceEntryId` would create redundant identity authority and inconsistent client signatures.

## 15. LibraryScan Operation Handler

A focused `LibraryScanOperationHandler` owns operation-specific behavior inside an admitted background execution.

It owns:

- execution of immutable scan plans created by admission;
- coordination of the job's already-created `ScanRun`s;
- source traversal orchestration through source-provider ports;
- reconciliation orchestration according to `SPEC-BE-011`;
- bounded persistence checkpoints;
- scan-specific structured progress facts;
- cancellation checkpoints;
- per-root terminal outcome assembly;
- retry reconstruction semantics;
- the operation-specific completion facts reported to the runtime.

Admission owns the immutable execution boundary: it freezes the effective source/root configuration and policy revision, creates the owning `JobRun`, creates every admitted child `ScanRun`, persists the target/exclusion snapshot, and acquires root ownership before execution begins. The handler consumes those identities and plans; it must not reconstruct a new plan from mutable configuration or allocate replacement runs inside the same attempt.

It does not directly write arbitrary generic `JobRun` lifecycle states. `BackgroundOperationManager` remains authoritative for those transitions.

### 15.1 Phase 001 fixed discovery policy

Every Phase 001 LibraryScan freezes the same centrally owned deterministic MVP discovery policy into its immutable scan plan.

Required behavior is:

| Provider observation | Retain | Traverse | Persisted kind | Classification |
|---|---:|---:|---|---|
| Directory | Yes | Yes | `Directory` | `Container` |
| File | Yes | No | `File` | `Unknown` |
| Link-like | Yes | No | `LinkLike` | `Ignored` |
| Other/unsupported structural object | Yes | No | `Unknown` | `Ignored` |

- no filename, extension, include-pattern, exclude-pattern, hidden, or system-attribute rule removes an otherwise provider-visible ordinary entry;
- symlinks, aliases, junctions, and equivalent redirects are retained as non-traversable evidence and are never followed;
- no user-facing include/exclude, hidden/system, or maximum-depth control exists;
- bounded safety/resource limits remain mandatory, but exhausting one makes the affected scope incomplete and yields `Partial` or `Failed` according to committed useful work; it never creates a truncated `Complete` result or absence authority;
- no archive/container expansion or filename-based semantic refinement occurs during Phase 001 indexing.

Potential archives, disc images, playlists, and similar meaningful files remain ordinary provider-observed `File` entries during Phase 001. The scan must not refine them into archive-, playlist-, disc-image-, or transformation-owned semantic kinds. Later transformation work may refine application-owned kind/classification under its own governed contract while preserving source identity where permitted.

Discovery-policy revision is frozen for one `ScanRun`; a later incompatible policy/configuration revision may prevent destructive finalization but does not rewrite the active plan.

## 16. Reconciliation and Transaction Boundaries

Source-graph correctness remains defined by `SPEC-BE-011`.

The application workflow must preserve these requirements:

1. Valid positive observations may be committed incrementally.
2. Short coherent Units of Work persist bounded additions, modifications, moves, and authoritative removals.
3. Filesystem/provider I/O is not held open inside a database write transaction merely for indexing convenience.
4. Committed positive observations remain valid after later partial, failed, cancelled, or abandoned termination.
5. A completed exact scope may perform authorized absence reconciliation.
6. Partial, failed, cancelled, abandoned, unavailable, or otherwise non-authoritative scopes never infer absence from unseen entries.
7. An incompatible current configuration/policy revision suppresses destructive finalization for a stale scan plan.

## 17. Progress Model

`LibraryScan` specializes the phase-local structured progress model from `SPEC-BE-004`.

Representative operation phases are:

```text
Preparing
Discovering
Reconciling
Finalizing
```

Operation-specific progress may expose trustworthy facts such as:

```text
roots_requested
roots_admitted
roots_terminal
entries_observed
entries_committed
active/current root context when meaningful
bounded issue count
```

Rules:

1. The backend publishes no overall percentage.
2. No weighted multi-root or multi-phase percentage is defined.
3. Unknown total work is represented as indeterminate, not guessed.
4. Roots and entries are not assumed to have equal work cost.
5. Counts implying durability never advance beyond committed authoritative state.
6. High-frequency progress notifications may be coalesced according to `SPEC-BE-004`.
7. Progress events may carry bounded snapshots for responsiveness, but authoritative queries remain the source of truth.

## 18. Generic Job Terminal Aggregation

`SPEC-BE-004` defines `CompletedWithIssues` as a generic terminal `JobRun` state.

For `LibraryScan`, aggregation is:

```text
all requested scope admitted and all ScanRuns Complete
    -> Completed

meaningful successful work exists, but requested scope was not fully satisfied
    -> CompletedWithIssues

no meaningful indexing result across admitted work
    -> Failed

cancellation determines operation termination
    -> Cancelled

stale active execution with accepted durable cancellation intent
    -> Cancelled

stale active execution without accepted durable cancellation intent
    -> Abandoned
```

`CompletedWithIssues` includes, where applicable:

- typed admission exclusions;
- one or more `Partial` scan outcomes;
- mixed successful and failed root outcomes;
- other operation-specific conditions where meaningful work was durably produced but the requested scope was not completely satisfied.

A job state describes the whole requested operation intent, not merely whether the admitted subset avoided an infrastructure failure.

## 19. Job and Scan Detail Projections

The generic job projection remains capability-neutral and contains stable lifecycle facts such as:

```text
job_run_id
operation_type
state
phase
completed_units nullable
total_units nullable
status_key nullable
timestamps
cancellation_requested
control availability
bounded terminal failure
```

`LibraryScanJobDetail` supplies typed scan-specific data derived from the durable admission context plus current/terminal scan-run state:

```text
requested_root_summary
admitted_root_summary
typed admission exclusions
per-root ScanRun projections
scan-specific structured progress
historical root display snapshots
retry source identity when applicable
retry successor identity when applicable
```

Jobs history does not depend on the Sources controller or live `LibraryRoot` entities to remain intelligible.

Short recent-job history may use bounded offset pagination according to `ARCH-001`.

## 20. Cancellation

Cancellation is job-scoped. It targets the owning `LibraryScan` background execution, never an individual root inside a multi-root Scan All job; Phase 001 provides no root-scoped cancellation.

User-requested cancellation is performed through:

```text
JobsService.CancelJob(JobRunId)
```

Rules:

1. Cancellation intent is persisted according to `SPEC-BE-004`.
2. `LibraryScan` cooperatively observes cancellation at operation-defined safe checkpoints.
3. If cancellation determines termination, the `JobRun` and active `ScanRun`s reach `Cancelled` according to their respective contracts.
4. Already committed positive source observations remain.
5. Cancellation grants no absence authority.
6. A cancelled historical run is immutable; retry creates new identities.
7. A child `ScanRun` that already reached `Complete` before cancellation keeps that durable outcome; still-active child runs terminate as `Cancelled`. The owning `JobRun` is `Cancelled` when cancellation determines termination, even when some roots completed first.
8. A cancellation request arriving while a coherent mutation or scope finalization is already committing does not interrupt that in-flight transaction. The mutation commits atomically, the finalized scope keeps its `Complete` outcome, and cancellation is observed at the next safe checkpoint.
9. Partial discoveries from interrupted roots remain valid and are never rolled back.
10. After restart, accepted durable cancellation intent maps stale active children to `Cancelled`; unexpected loss maps them to `Abandoned` (Section 23). Neither relabels committed child outcomes as `Interrupted`.

## 21. Root Removal

`RemoveLibraryRoot(root_id)` owns configuration/current-index removal only. It does not own job cancellation.

If an active scan owns the root, removal returns a typed non-mutating outcome equivalent to:

```text
RootHasActiveScan
- root_id
- job_run_id
- scan_run_id
- owning_job_root_count
```

`owning_job_root_count` is a bounded durable projection of the owning LibraryScan scope. Because `CancelJob` is job-scoped, a value greater than one tells the caller that cancelling this owner may stop work for other roots; the application must not imply root-scoped cancellation that does not exist.

The required workflow is:

```text
request removal
    ↓
active owner reported
    ↓
CancelJob(job_run_id)
    ↓
authoritatively observe terminal/no ownership
    ↓
retry RemoveLibraryRoot(root_id)
```

A transport-ambiguous cancellation result must be reconciled through authoritative job/root queries before destructive removal is retried.

Successful removal:

- deletes the current `LibraryRoot` configuration;
- coherently deletes its current `SourceEntry` graph and dependent current provenance required by governing source contracts;
- never deletes, renames, rewrites, or otherwise modifies user filesystem content;
- preserves terminal `JobRun`/`ScanRun` history and historical snapshots;
- leaves the internally managed LocalFilesystem `LibrarySource` reusable.

Re-adding the same physical folder later creates a new `LibraryRootId` and configuration lifecycle.

## 22. Retry and Resume

### 22.1 Retry

`LibraryScan` is retryable.

Retry is available only when the source run is terminal in `CompletedWithIssues`, `Failed`, `Cancelled`, or `Abandoned`, at least one original target remains currently eligible, and no direct retry successor exists. A clean `Completed` LibraryScan is not retryable; the user starts a new independent **Scan Again** job instead. `LibraryScan` is non-resumable and therefore does not use `Interrupted` as a recoverable operation outcome.

Retry reconstructs the original operation intent from durable operation-specific history and then revalidates that intent against current authoritative state.

For a multi-root job:

```text
original requested roots
    ↓
still configured + eligible -> admitted to new job
removed/ineligible/active -> typed exclusions
```

Rules:

1. Every admitted retry creates a new `JobRunId` and new `ScanRunId`s.
2. Historical runs are never reopened or mutated into active state.
3. Retry does not broaden into scanning roots that were not part of the original requested intent.
4. Removed or currently ineligible original targets are reported as typed exclusions where a new job is otherwise admitted.
5. If no original target remains eligible, no empty retry `JobRun` is created.
6. A single-root retry whose original root no longer exists is unavailable.
7. Partial admission of a retry contributes to `CompletedWithIssues` if the new job otherwise produces meaningful successful work.
8. One LibraryScan `JobRun` may have at most one direct retry successor.
9. If a direct retry successor already exists, another `RetryJob` request against the same historical source run returns that existing successor identity and creates no branch.
10. A later retry is initiated from the latest attempt, so LibraryScan retry history forms a linear attempt chain rather than a tree.
11. The direct source/successor relationship is durable operation history. It does not introduce a separate logical `JobId` or reopen the source run.
12. Once a direct retry successor exists, retry control availability for the historical source run is false; the successor remains discoverable through authoritative job detail.

Expected retry-control outcomes are equivalent to:

```text
Admitted(new_operation_handle)
AlreadyRetried(existing_job_run_id)
NotAdmitted(reason)

RetryNotAdmittedReason
├── SourceRunNotTerminal
├── OperationNotRetryable
└── NoEligibleTargets(exclusions)
```

`NoEligibleTargets` carries the typed `LibraryScanTargetExclusion` values established above. `AlreadyRetried` remains a distinct successful lookup of the existing successor rather than being collapsed into a generic admission failure.

The source run's direct successor relation is stored as durable retry-link metadata separate from the immutable admission context, so rule 10.3.7 remains intact. The new run continues to record `retry_source_job_run_id` in its own immutable admission context.

### 22.2 Resume

`LibraryScan` is non-resumable in MVP.

`ResumeJob` must reject LibraryScan according to the generic unsupported-resume contract.

## 23. Restart Recovery

Before the replacement runtime becomes `Ready`, stale LibraryScan execution is reconciled through the mandatory bounded persistence-only step defined by SPEC-BE-007 and SPEC-BE-011.

Rules:

1. Already-terminal `ScanRun`s remain unchanged.
2. A stale `Running` child becomes `Cancelled` when durable cancellation intent had already been accepted for the owning job; otherwise it becomes recovery-only `Abandoned`.
3. When every child was already terminal because the process died before parent aggregation, the `JobRun` is derived through the normal LibraryScan aggregation rules from those child outcomes and durable exclusions.
4. Otherwise a recovery-cancelled child makes the owning job `Cancelled`, while a recovery-abandoned child makes it `Abandoned`. Job-scoped cancellation intent makes these cases mutually consistent across stale children.
5. Root last-scan summaries are updated from recovered child outcomes; `Cancelled` and `Abandoned` do not change root availability merely because execution stopped.
6. Stale root ownership is cleared, committed positive observations survive, and no incomplete scope gains absence authority.
7. Recovery performs no provider I/O, enumeration, new admission, retry, resume, or other significant user work.

No scan is automatically resumed or restarted. The user explicitly chooses Scan Again, Scan All, or Retry afterward, and each admitted action creates new execution identities. Failure of this mandatory reconciliation prevents readiness.

## 24. Events and Authoritative Reconciliation

Committed state changes record/publish application events according to `SPEC-BE-006` and runtime event sequencing according to `SPEC-BE-004`.

Representative notification intent includes changes to:

- root configuration/projection state;
- active scan ownership;
- source-entry graph state;

Source-entry invalidation uses one explicit scope union rather than overloading a nullable parent identifier:

```text
SourceEntriesChangeScope
├── RootChildren
├── EntryChildren(parent_source_entry_id)
└── EntireRootHierarchy
```

Every source-entry invalidation also carries its `LibraryRootId`. Coalescing may broaden multiple narrow invalidations to `EntireRootHierarchy`, but it must not narrow or misrepresent their affected scope. Generic job-state and job-progress notifications remain owned by SPEC-BE-004 rather than a competing LibraryScan-completion event.
- job state;
- LibraryScan progress.

The authoritative flow is:

```text
backend commit
    ↓
application/runtime notification
    ↓
frontend reconciliation demand
    ↓
focused authoritative query
    ↓
confirmed state
```

Dropped/coalesced events, sequence gaps, or runtime replacement must cause authoritative refresh rather than frontend reconstruction from event history.

## 25. Persistence Requirements

Phase 001 persistence must support the semantics of this specification, including:

- one durable internal LocalFilesystem `LibrarySource`;
- configured `LibraryRoot`s;
- root configuration/policy revisions required for scan authority;
- current `SourceEntry` graph;
- generic `JobRun`s;
- per-root `ScanRun`s;
- bounded historical root presentation snapshots;
- immutable LibraryScan requested/admitted/excluded target context required for terminal aggregation and retry reconstruction;
- active-root ownership queries/constraints;
- child-page read projections;
- current root/job/scan projections;
- removal of current root/index state without deleting terminal execution history.

Schema design must preserve the Phase 000 migration path rather than assuming only fresh databases.

Schema and durable contract evolution follow SPEC-X-001: migration compatibility is explicit, additive bridge/model evolution remains compatible, and unsupported compatibility state fails safely rather than being silently rewritten.

Long-term scan/job-history pruning policy remains deferred. This specification requires durable terminal history and bounded per-run payloads but does not define a retention duration.

## 26. Concurrency and Resource Requirements

`LibraryScan` declares logical runtime resource intent rather than concrete executor/thread details.

At minimum its execution requires the logical resource classes:

```text
FilesystemRead
PersistenceWrite
```

Additional bounded resource declarations may be added only when required by the active workflow and consistent with `SPEC-BE-004`.

Rules:

1. One root has at most one active `ScanRun` owner.
2. Different roots may proceed independently when runtime/resource policy permits.
3. Scan All does not require parallel root enumeration.
4. `BackgroundOperationManager` owns top-level scheduling/resource admission.
5. Source infrastructure owns provider-native access behavior.
6. Application indexing owns traversal/reconciliation.
7. Persistence owns database serialization and Unit of Work behavior.
8. No database transaction spans the complete background scan.

## 27. Failure Behavior

Expected domain/application outcomes are represented through typed operation results where appropriate rather than being collapsed into infrastructure failures.

Examples include:

- `AlreadyConfigured`;
- `OverlapsExisting`;
- `AlreadyScanning`;
- `RootHasActiveScan`;
- retry target exclusions;
- zero eligible Scan All/retry scope.

Unexpected or non-domain failures map through the canonical `ApplicationError` contract from `SPEC-BE-003`/`SPEC-BE-009`.

Provider-native failures are translated before crossing infrastructure boundaries. User-facing context remains bounded and sanitized.

## 28. Security and Privacy

1. Filesystem access begins only from explicitly user-selected/configured roots.
2. Provider/root resolution enforces the configured root boundary.
3. Link-like redirects are not followed in MVP.
4. Provider-provable overlaps are rejected rather than creating ambiguous reconciliation authority.
5. Library scans are read-only with respect to user library content.
6. Removing a root never modifies underlying user files.
7. LocalFilesystem selections and provider input are untrusted.
8. Native provider objects and unsanitized native errors never escape infrastructure boundaries.
9. Opaque locators, locator keys, provider-native identities, and source fingerprints are not ordinary UI contracts.
10. The UI may display the explicitly selected folder and safe relative source locations required to operate Sources; that permission does not authorize unsanitized logging/telemetry.
11. Historical run snapshots retain only bounded user-meaningful context needed for history.
12. Phase 001 does not persist ROM bytes merely because a file was indexed.
13. Scanning introduces no network access, credentials, API keys, or telemetry requirement.
14. Tests use only test-owned temporary roots and application data.
15. Platforms that require durable platform authorization (for example a sandboxed macOS application) keep that authorization provider-owned and opaque: it is not a domain type, never crosses bridge/UI/diagnostics contracts, is restored or reacquired before traversal after restart, and a stale/revoked authorization surfaces as a typed source-access failure without deleting the configured root.

## 29. Performance and Scalability Requirements

The architecture must remain viable for hundreds of thousands of source entries.

Required guardrails:

- cursor-paginated source-child queries;
- bounded page sizes;
- deterministic indexed sort keys/tie-breakers;
- no whole-tree query or Flutter materialization requirement;
- bounded event payloads;
- no N+1 query patterns in hierarchy projections;
- bounded persistence batches/scopes;
- appropriate indexes for root, parent-child, active ownership, and job/scan query patterns;
- bounded short administrative root/job lists;
- no requirement for enormous physical filesystem fixtures in everyday CI.

## 30. Testing Requirements

### 30.1 Domain/application tests

Required coverage includes:

- LocalFilesystem source lazy creation and reuse;
- root identity/display-name behavior;
- provider-verifiable overlap handling;
- `Added`, `AlreadyConfigured`, and `OverlapsExisting` outcomes;
- exact-selection replay returns `AlreadyConfigured` without duplicate mutation or duplicate event;
- provider-overlap and child-admission failures use the canonical typed reason vocabularies;
- Add & Scan two-boundary semantics;
- transport-ambiguous Add & Scan reconciles through idempotent root creation plus authoritative root/job queries and never blindly replays the composite workflow;
- scan-admission failure after root commit;
- single-root admission;
- admission atomically freezes the scan plan/target snapshot, creates the owning `JobRun` and child `ScanRun`s, and acquires root ownership before handler execution;
- each admitted child `ScanRun` exists in the active `Running` state before enumeration starts;
- the operation handler consumes those persisted identities and cannot allocate replacement runs or rebuild the plan from mutable configuration;
- duplicate same-root ownership;
- Scan All partial admission;
- zero-eligible-root behavior;
- root projections with independent availability/last-scan/active-scan dimensions;
- removal blocking under active ownership;
- active-owner detail includes the owning job root count so whole-job cancellation impact is observable;
- terminal-history preservation after removal;
- historical root snapshots retain `display_name` plus bounded `safe_location_display` without retaining raw provider locators or identities;
- retry revalidation and new identities;
- retry eligibility for `CompletedWithIssues`, `Failed`, `Cancelled`, and `Abandoned`, with clean `Completed` using a separate Scan Again admission;
- exact retry-not-admitted reasons and `AlreadyRetried` successor idempotency;
- retry exclusions after root removal/ineligibility;
- no retry broadening to newly configured roots;
- one direct retry successor per historical run;
- repeated retry of the same source returning the existing successor rather than branching;
- linear retry-chain continuation from the latest attempt.

### 30.2 Job aggregation tests

Required cases include:

- all requested roots admitted and complete -> `Completed`;
- admission exclusion plus meaningful successful work -> `CompletedWithIssues`;
- single-root `Partial` -> `CompletedWithIssues`;
- mixed complete/partial/failed roots with meaningful success -> `CompletedWithIssues`;
- no meaningful successful result across admitted work -> `Failed`;
- cancellation-determined termination -> `Cancelled`;
- one root completes before another root is cancelled -> completed child keeps `Complete` while the job terminates `Cancelled`;
- cancellation arriving during a coherent commit/finalization checkpoint -> in-flight mutation commits and cancellation is observed at the next safe checkpoint;
- stale child with accepted cancellation intent -> child/job `Cancelled`;
- stale child without accepted cancellation intent -> child/job `Abandoned`;
- already-terminal children remain unchanged and drive normal parent aggregation when all child work had terminalized;
- recovered `Cancelled`/`Abandoned` summaries clear ownership without changing root availability or granting absence authority;
- reconciliation failure prevents readiness and reconciliation performs no provider/new work;
- no eligible targets -> no empty `JobRun`.

### 30.3 Reconciliation tests

Required coverage remains aligned with `SPEC-BE-011`, including:

- new observations;
- unchanged identity;
- trustworthy moves;
- ambiguous move fallback;
- exact-scope authoritative removal;
- incomplete-scope preservation;
- nested failures;
- cancellation;
- stale/incompatible plan finalization suppression;
- root-level unavailability versus nested failure.
- exact Phase 001 observation-to-kind/classification mapping;
- hidden/system ordinary entries retained under the same structural rules;
- bounded resource-limit exhaustion remains incomplete and cannot report a truncated `Complete` result;
- no Phase 001 move preservation uses the inactive strong-content-identity tier.

### 30.4 Persistence/migration tests

Required coverage includes:

- Phase 000 -> Phase 001 upgrade;
- repository recreation/restart persistence;
- one internal LocalFilesystem source;
- root/source/job/scan constraints;
- active-root ownership constraint/query behavior;
- historical root snapshot survival after root deletion;
- current graph deletion without terminal-history deletion;
- child-page indexes/query plans as required by implementation.

### 30.5 Filesystem integration tests

Use real test-owned temporary directory trees to cover:

- nested files/directories;
- root resolution;
- unavailable roots;
- nested access failures where deterministic;
- link-like entries without traversal;
- rename/move behavior where provider/platform guarantees support it;
- case/locator/native-identity semantics where materially different;
- cancellation during enumeration;
- rescan/reconciliation after changes.
- platform authorization restore/reacquire and stale/revoked failure behavior where the platform requires it (for example sandboxed macOS).

Windows, macOS, and Linux receive targeted native provider coverage. macOS remains the primary full native milestone proof for Phase 001.

### 30.6 Runtime/event tests

Required coverage includes:

- durable background admission;
- structured progress;
- cancellation boundaries;
- startup reconciliation;
- no automatic resume;
- resource admission;
- multi-root failure isolation;
- event sequencing/coalescing/gaps;
- source-entry invalidation scope for root children, one entry's children, and the entire root hierarchy, including safe coalescing broadening;
- no competing LibraryScan lifecycle event duplicates generic runtime-owned job state/progress notification authority;
- authoritative reconciliation after event uncertainty/runtime replacement.

### 30.7 Manual verification

Manual verification may remain deferred during the current Phase 001 execution workflow.

Any verification/result artifact must distinguish `PASS`, `FAIL`, and `NOT RUN`; skipped manual work must never be represented as passing.

## 31. Out of Scope

The following remain outside this specification:

- logical game resolution and `GameContent` lifecycle;
- archive/disc-image/playlist semantic expansion during Phase 001 source indexing;
- hashing and content identity;
- metadata/artwork/RetroAchievements operations;
- source-entry search/filtering;
- configurable include/exclude policy UI;
- hidden/system-file preference UI;
- link traversal;
- filesystem watching;
- automatic periodic scans;
- concurrent source-discovery requirement;
- distributed scan leases;
- provider-specific remote source retry policy;
- generic automatic source retry framework;
- long-term job/scan-history retention/pruning policy;
- user management of the internal LocalFilesystem source;
- root rename UI;
- a durable logical-job identity grouping retry attempts;
- automatic resume/restart of significant scans.

## 32. Acceptance Criteria

SPEC-BE-013 is satisfied when:

1. `LibraryService` exposes the focused Phase 001 source/root/scan capabilities without generic CRUD leakage.
2. `JobsService` exposes generic job query/control capabilities without feature-service dependencies.
3. LibraryScan follows the MVP-wide capability-owned-work/background-manager lifecycle pattern.
4. One durable internal LocalFilesystem `LibrarySource` is lazily created and reused by all local roots.
5. Local folder selections are validated/converted to provider-owned locators by the LocalFilesystem boundary rather than Flutter/generic application code.
6. Root display names are independently persisted application presentation facts.
7. Exact duplicate local-folder selection is idempotent and returns the existing root; provider-verifiable overlaps are typed and non-mutating.
8. Add & Scan commits the root before typed child scan admission, preserves the root if admission fails, and requires authoritative reconciliation rather than blind composite replay after ambiguous transport.
9. One root has at most one active scan owner.
10. Scan All admits eligible roots, reports typed exclusions, and creates no empty job when nothing is eligible.
11. Source graph reconciliation obeys exact-scope authority from SPEC-BE-011.
12. Valid committed positive observations survive partial, failed, cancelled, and abandoned scans.
13. Root projections separate availability, last scan, and active scan state.
14. Source-entry projections expose safe display location rather than opaque provider locators.
15. Source hierarchy browsing uses bounded cursor pagination and deterministic backend ordering.
16. Generic job projection remains capability-neutral while LibraryScan supplies typed operation-specific detail.
17. Terminal scan/job history remains intelligible after current root removal without requiring soft-deleted live roots.
18. Root removal is blocked while an active scan owns the root, exposes the owning job scope so whole-job cancellation impact can be disclosed, and never modifies user filesystem content.
19. LibraryScan progress is structured, phase-local, and percentage-free.
20. `CompletedWithIssues` is used when meaningful successful work exists but requested scope was not fully satisfied.
21. Retry is limited to issue/failed/cancelled/abandoned terminal attempts, reconstructs original intent, revalidates current targets, creates new identities, never broadens to unrelated roots, and remains distinct from a clean completed root's independent Scan Again action.
22. Each LibraryScan run has at most one direct retry successor; repeated retry of the same source returns that successor and later retries continue from the latest attempt as a linear chain.
23. LibraryScan is explicitly non-resumable; pre-readiness reconciliation preserves terminal children, maps accepted cancellation to `Cancelled` and unexpected loss to `Abandoned`, derives aggregate job truth deterministically, clears stale ownership, and performs no provider or automatic work.
24. Events remain notification-first, source-entry invalidation uses explicit root-children/entry-children/entire-root scope, generic job lifecycle events remain runtime-owned, and authoritative queries repair uncertainty.
25. Persistence/migrations preserve the Phase 000 upgrade path and current/history separation.
26. Security/privacy rules prevent provider internals and unnecessary sensitive filesystem context from leaking into normal diagnostics/UI contracts.
27. Tests cover application, aggregation, reconciliation, persistence, native filesystem, runtime, and event uncertainty behavior.
28. Cross-platform native filesystem behavior is exercised on Windows, macOS, and Linux, with macOS providing the primary full Phase 001 native milestone proof.
29. Cancellation is job-scoped; completed child outcomes remain durable, in-flight coherent commits complete before the next checkpoint, and accepted cancellation intent maps stale active children to `Cancelled` at restart.
30. Platform-durable authorization is provider-owned opaque configuration; stale/revoked authorization yields a typed source-access failure without deleting the configured root.

## 33. Phase 002 Android Source/Scan Amendment

Android reuses the existing source/root/scan application contracts; platform storage state changes do not create Android-only scan semantics.

1. Global All files access loss preserves configured roots, indexed source entries, scan/job history, and settings. New Android storage scans are not admitted while the platform readiness prerequisite is unmet.
2. Permission loss is not root deletion and cannot be used as fresh absence evidence.
3. Removing/ejecting a configured SD/USB volume makes affected roots unavailable. An active scan terminates through existing failure/interruption semantics without destructive absence finalization.
4. A trustworthy remount of the same provider-native volume/root restores availability under the existing `LibraryRootId`; it does not silently create a replacement configured root.
5. `ScanAllLocalLibraryRoots` excludes unavailable/ineligible roots using existing typed exclusion semantics while allowing other eligible roots to proceed.
6. `AddLocalLibraryRootAndScan` retains the existing committed-root-then-child-admission boundary on Android; root admission is not rolled back because scan admission later fails.
7. Android foreground execution does not change `JobRun`/`ScanRun` authority. Native service/notification state is secondary projection only.
8. Removing an Android root remains configuration/index removal only and never deletes, moves, renames, or modifies user files.

Tests must cover permission loss/regrant, removable-media loss/remount, partial Scan All eligibility, no destructive reconciliation on unavailable evidence, and preserved root identity where provider-native proof is trustworthy.

## 34. References

- `docs/architecture/architecture-overview.md` — ARCH-001
- `docs/architecture/documentation-architecture.md` — ARCH-002
- `docs/phases/phase-001-local-sources-and-indexing.md` — PHASE-001
- `docs/specifications/backend/spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md` — SPEC-BE-002
- `docs/specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md` — SPEC-BE-003
- `docs/specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md` — SPEC-BE-004
- `docs/specifications/backend/spec-be-006-minimal-domain-event-bus.md` — SPEC-BE-006
- `docs/specifications/backend/spec-be-007-startup-coordination-and-recovery-contract.md` — SPEC-BE-007
- `docs/specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md` — SPEC-BE-008
- `docs/specifications/backend/spec-be-009-application-service-contracts.md` — SPEC-BE-009
- `docs/specifications/backend/spec-be-011-source-provider-and-indexing-contract.md` — SPEC-BE-011
- `docs/specifications/frontend/spec-fe-008-sources-and-library-folder-management.md` — SPEC-FE-008
- `docs/specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md` — SPEC-FE-009
- `docs/specifications/cross-cutting/spec-x-001-versioning-and-compatibility-contract.md` — SPEC-X-001
