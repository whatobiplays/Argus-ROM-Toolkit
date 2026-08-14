# Jobs and Background Operation Presentation Specification

**Document ID:** SPEC-FE-009  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-14  
**Depends On:** ARCH-001, ARCH-002, PHASE-001, SPEC-BE-004, SPEC-BE-008, SPEC-BE-013, SPEC-FE-001, SPEC-FE-002, SPEC-FE-003, SPEC-FE-004, SPEC-FE-005, SPEC-FE-006, SPEC-FE-007, SPEC-FE-008  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative Flutter product contract for Phase 001 Jobs and reusable background-operation presentation.

It activates the previously reserved Jobs frontend capability and turns the durable background-operation contracts from SPEC-BE-004 and SPEC-BE-013 into one coherent user-facing experience for:

- navigating to a genuine Jobs destination;
- seeing active work and recent terminal history;
- opening one durable execution attempt through a stable job route;
- viewing capability-neutral lifecycle facts plus typed operation-specific detail;
- presenting structured progress without fabricating percentages;
- cancelling active work through backend-authoritative controls;
- retrying eligible work as a new immutable execution attempt;
- representing terminal states, including `CompletedWithIssues`, truthfully;
- providing the application shell with a narrow active-job indicator;
- reconciling authoritative state after backend events, event gaps, transport ambiguity, runtime replacement, cancellation, retry, and restart;
- adapting the same route identities and Jobs state across Compact, Medium, Expanded, and Large layouts.

The central invariant is:

> **Jobs is the durable, query-authoritative presentation of background execution attempts. `JobRunId` identifies one immutable attempt; lifecycle controls act through backend capability, events only trigger reconciliation, and operation-specific detail extends a generic Jobs shell through typed variants rather than arbitrary payloads.**

Phase 001 supplies one real operation type: `LibraryScan`. The Jobs architecture must remain generic without fabricating future operation implementations.

## 2. Responsibilities

SPEC-FE-009 owns:

- the Jobs semantic application destination;
- the canonical Jobs route catalog;
- placement of Jobs in the adaptive application shell;
- the Jobs empty state;
- the Active and Recent landing-page sections;
- incremental recent-history presentation;
- durable job-detail navigation;
- the generic job-detail presentation shell;
- typed `LibraryScan` operation-detail presentation;
- structured progress presentation;
- truthful generic terminal-state presentation;
- backend-authoritative Cancel, Retry, and future Resume affordance rules;
- Retry navigation from a historical run to the newly admitted run;
- the application-shell active-job indicator contract;
- feature-owned Riverpod/controller state for Jobs list/detail;
- the app/shell-safe active-job summary projection;
- event-driven authoritative reconciliation;
- failure, stale-state, synchronization-uncertainty, and transport-ambiguity presentation for Jobs;
- historical-detail behavior after current source/root configuration changes;
- accessibility, keyboard, focus, responsive, text-scale, privacy, security, and performance rules for Jobs;
- deterministic frontend test requirements for the Phase 001 Jobs experience.

## 3. Non-Responsibilities

SPEC-FE-009 does not own:

- generic backend `JobRun` lifecycle transitions;
- background scheduling or resource admission;
- operation-specific execution business logic;
- `LibraryScan` traversal, reconciliation, absence authority, source observation, or root admission semantics;
- source/root configuration management;
- Sources hierarchy presentation;
- backend persistence or retry reconstruction;
- bridge DTO serialization layout;
- generated FRB source;
- retention/pruning policy for terminal job history;
- job deletion;
- job search or arbitrary filtering;
- bulk lifecycle controls;
- local percentage estimation when total work is unknown;
- notification-center behavior;
- future metadata, artwork, hashing, verification, import, or other operation-type UI before those operations are active product scope.

Those responsibilities remain with SPEC-BE-004, SPEC-BE-013, SPEC-FE-008, later focused contracts, or later phases.

## 4. Architectural Principles

1. Jobs is a genuine semantic destination and remains present regardless of current job count.
2. Routes represent durable job location; route identity never depends on adaptive layout.
3. `JobRunId` identifies exactly one execution attempt and historical terminal attempts are never reopened as active work.
4. Queries remain authoritative; events are invalidation/responsiveness signals only.
5. The Jobs feature does not derive backend lifecycle transitions locally.
6. The application shell does not depend on private Jobs feature-controller state.
7. Generic lifecycle facts and typed operation-specific detail remain separate.
8. Arbitrary JSON extension bags are not a frontend extensibility contract.
9. Structured factual progress is preferred to false precision.
10. Unknown totals remain unknown; frontend percentage fabrication is prohibited.
11. Lifecycle-control availability comes from authoritative backend capability, not operation-name string tables.
12. Retry and Resume are distinct concepts; each creates a new execution identity when admitted.
13. Usable confirmed state remains visible during ordinary refreshes and control mutations.
14. Historical job detail must remain intelligible without current Sources state.
15. Accessibility and keyboard support are first-class desktop requirements.
16. Jobs stays bounded as terminal history grows.

## 5. Feature and Client Boundaries

The Jobs feature follows SPEC-FE-001 and consumes narrow frontend/client contracts rather than the root `ArgusClient` facade.

Conceptually:

```text
JobsListController
JobDetailController
    ↓
JobsApi
    ↓
bridge/client mapper
    ↓
JobsService / focused Phase 001 backend contracts
```

Phase 001 activates the `jobs` focused client area previously reserved by SPEC-FE-003. This is a later-phase specialization of that reservation and does not alter the Phase 000 focused API surface.

The shell consumes a narrow Jobs-owned/app-safe summary seam:

```text
Adaptive shell
    ↓
activeJobSummaryProvider
    ↓
JobsApi active-job summary query
```

The shell must not depend on `JobsListController`, `JobDetailController`, Sources state, or locally initiated mutation state.

## 6. Focused `JobsApi`

The Phase 001 frontend contract conceptually includes cohesive operations equivalent to:

```text
JobsApi.getJob(JobRunId)
JobsApi.listJobs(...)
JobsApi.getActiveJobSummary()
JobsApi.cancelJob(JobRunId)
JobsApi.retryJob(JobRunId)
```

Exact Dart syntax and pagination parameter names are implementation details governed by the bridge/client mapping contract.

Rules:

1. `getJob` returns one authoritative typed `JobDetail` projection.
2. `listJobs` returns bounded job-list projections and paging information according to the backend query contract.
3. `getActiveJobSummary` is a frontend-focused capability that returns only the narrow active-job facts needed by the shell and must not require materializing full Jobs history or full job detail. It may be backed by the existing `JobsService.ListJobs(...)` query/projection contract when that contract can supply the required active summary; FE-009 does not require a new backend application-service owner merely for shell presentation.
4. `cancelJob` and `retryJob` preserve backend application semantics.
5. A successful mutation does not authorize Flutter to fabricate the resulting lifecycle state from the request.
6. Retry responses must expose the new execution identity when admission semantics guarantee it, or provide an authoritative reconciliation path capable of establishing that identity after transport ambiguity.
7. `LibraryScan` is retryable and non-resumable; its control availability must reflect that contract.
8. Phase 001 does not require a production frontend `resumeJob` method because no active Phase 001 operation is resumable. A later focused specification may activate that method when a real resumable operation exists.

## 7. Frontend Job Models

Frontend models are immutable Argus-owned Dart models adapted from bridge DTOs. Generated bridge types do not cross into the Jobs feature.

Conceptually:

```text
JobListItem
- jobRunId
- operationType
- operationLabel
- lifecycleState
- phase nullable
- startedAt nullable
- terminalAt nullable
- safeSummary nullable

JobDetail
- job
- operationDetail

OperationDetail
- libraryScan(LibraryScanJobDetail)
- future typed variants

ActiveJobSummary
- activeCount
- soleActiveJob nullable
```

The exact field shape may differ where the focused Phase 001 bridge amendment supplies a more precise equivalent, but it must preserve the semantic separation above.

## 8. Generic Job Lifecycle Vocabulary

Jobs consumes the exact generic lifecycle vocabulary defined by SPEC-BE-004.

Phase 001 normal presentation must support:

```text
Queued
Preparing
Running
Completed
CompletedWithIssues
Failed
Cancelled
Interrupted
Abandoned
```

The frontend must not collapse these states into one simplified success/failure Boolean.

Active/terminal classification follows the backend lifecycle contract. In particular:

- cancellation requested is not terminal;
- `CompletedWithIssues` is terminal and distinct from `Completed` and `Failed`;
- `Interrupted` is distinct from user cancellation;
- `Abandoned` is distinct from user cancellation and clean completion.

## 9. Jobs Destination Placement

Jobs is a lower-frequency semantic destination.

Canonical adaptive placement:

| Size class | Jobs placement |
|---|---|
| Compact | under `More` |
| Medium | navigation rail |
| Expanded | sidebar |
| Large | sidebar |

Jobs remains available when there are zero active jobs and zero history rows.

Job state must never dynamically add/remove the semantic destination itself.

## 10. Canonical Routes

The Phase 001 Jobs route catalog is:

```text
/jobs
/jobs/:jobRunId
```

Rules:

1. `/jobs` is the Jobs landing route.
2. `/jobs/:jobRunId` is one durable execution-attempt route.
3. `jobRunId` is parsed through the typed route/client identity boundary, not handled as an arbitrary string throughout feature code.
4. Route identity is invariant across layout classes.
5. Resizing never rewrites the URI merely because detail changes from full-page to split-view presentation.
6. Sources **View Job** navigates to `/jobs/:jobRunId`.
7. A single-job shell indicator navigates to `/jobs/:jobRunId`.
8. An aggregate multi-job shell indicator navigates to `/jobs`.

SPEC-FE-009 is the later focused contract that refines SPEC-FE-004's reserved Jobs route area.

## 11. Jobs Branch History

Jobs participates in the normal semantic-destination branch-history rules from SPEC-FE-004.

If the user leaves Jobs while viewing `/jobs/:jobRunId`, switching back to Jobs may restore that branch route according to shell navigation policy.

Explicitly reselecting the already active Jobs destination may canonicalize to `/jobs` according to the shell's active-destination reselection behavior.

No second mutable selected-job authority exists beside the route.

## 12. Invalid or Unavailable Job Route

When `/jobs/:jobRunId` cannot be resolved authoritatively:

- Jobs shows a bounded job-not-found/unavailable state;
- it does not synthesize detail from stale list-row data;
- it provides navigation back to `/jobs`;
- on layouts where the list remains visible, the invalid route still must not masquerade as a selected valid row.

Historical jobs are expected to remain durable according to backend policy, so an unavailable identity is treated as an exceptional query outcome rather than normal history expiration unless a future retention contract says otherwise.

## 13. Jobs Landing Structure

The Jobs landing has two ordered sections:

```text
Active
Recent
```

### 13.1 Active

Active contains current non-terminal jobs.

Rules:

- Active is pinned before Recent.
- Ordering follows the backend query contract; Flutter does not invent an independent canonical active ordering.
- Active may update while recent history remains unchanged.
- A cancellation-requested job remains Active until an authoritative terminal lifecycle state is observed.

### 13.2 Recent

Recent contains terminal job history, newest first according to the backend query contract.

Rules:

- recent history is incrementally paged;
- already loaded history remains visible during page fetches;
- page failure does not clear earlier loaded rows;
- Flutter deduplicates by stable `JobRunId` when reconciling page boundaries but does not resort partial pages as though it owns a complete global dataset.

Phase 001 adds no Jobs search, arbitrary filters, operation tabs, state tabs, or user-defined sorting.

## 14. Jobs Empty State

With no active or recent jobs, `/jobs` presents a product-specific empty state explaining that long-running Argus operations appear here.

The empty state:

- does not fabricate example jobs;
- does not imply automatic background work exists when none has been admitted;
- may direct the user back to genuine product capabilities such as Sources where appropriate through normal navigation;
- must not make Sources a dependency of Jobs state ownership.

## 15. Job List Row Contract

A job-list row is a navigation surface, not a miniature job-detail screen.

It may show:

- user-facing operation label;
- generic lifecycle state;
- current phase when active and meaningful;
- started or terminal time where useful;
- concise safe operation context, such as affected library-folder display information.

It must not expose inline Cancel, Retry, Resume, or destructive control actions in Phase 001.

Selecting the row navigates to `/jobs/:jobRunId`.

## 16. Adaptive Jobs Layout

### 16.1 Compact and Medium

Compact and Medium use full routed pages:

```text
/jobs
    ↓ select
/jobs/:jobRunId
    → full-page detail
```

### 16.2 Expanded and Large

Expanded and Large may present a list/detail split:

```text
┌─────────────────────┬─────────────────────────────────┐
│ Active / Recent     │ Selected job detail             │
│ jobs                │                                 │
└─────────────────────┴─────────────────────────────────┘
```

The selected job remains route-authoritative through `/jobs/:jobRunId`.

Unlike SPEC-FE-008 Sources, Jobs introduces no user-controlled collapsible list pane during MVP. The presentation may collapse from split view when local constraints no longer support it, without changing durable route identity.

## 17. Local Constraint Rules

Jobs presentation responds to actual pane width rather than a broad platform/desktop Boolean.

At constrained widths:

- secondary timestamps and metadata wrap or reduce before primary job identity/state becomes unusable;
- operation-specific sections may stack vertically;
- LibraryScan per-root rows/cards may transition to a vertical layout;
- lifecycle controls remain visibly associated with the selected execution;
- factual progress labels and values remain readable without relying on horizontal scrolling where reasonably possible.

## 18. Generic Job Detail Shell

Every `/jobs/:jobRunId` detail begins with capability-neutral execution facts.

The generic detail shell may present:

- user-facing operation label/type;
- lifecycle state;
- current phase where applicable;
- queued/created/started/terminal timestamps where available;
- cancellation-requested state;
- bounded terminal failure information;
- backend-authoritative control availability;
- `JobRunId` where useful for support/troubleshooting, but not as the primary title.

Operation-specific detail appears beneath or alongside this shell through the typed `OperationDetail` variant.

## 19. Typed Operation Detail

Operation-specific Jobs detail is rendered through typed variants.

Conceptually:

```text
JobDetail
    ├── generic job shell
    └── OperationDetail
            ├── LibraryScan(...)
            └── future typed variants
```

Rules:

1. Unknown arbitrary maps are not a normal rendering contract.
2. Future operation types add explicit typed frontend variants when their product scope becomes active.
3. The generic shell remains reusable without absorbing feature-specific fields.
4. Operation-specific renderers consume only frontend/client models, never generated bridge DTOs.

## 20. `LibraryScan` Job Detail

Phase 001 `LibraryScanJobDetail` presents typed scan-specific facts derived from SPEC-BE-013.

Where available, detail includes:

- requested root summary;
- admitted root summary;
- typed admission exclusions;
- per-root `ScanRun` projections/outcomes;
- current/active root context when meaningful;
- historical root display snapshots;
- scan-specific progress facts;
- bounded issue information;
- retry relationship to the source execution where available.

Jobs must remain intelligible if the current `LibraryRoot` has been removed.

It therefore renders durable historical root snapshots from the job detail projection rather than querying Sources for current root identity or display information.

## 21. Structured Progress Principles

Jobs presents authoritative progress facts without strengthening their meaning.

For `LibraryScan`, representative phases include:

```text
Preparing
Discovering
Reconciling
Finalizing
```

Representative facts may include:

```text
roots requested
roots admitted
roots terminal
entries observed
entries committed
current root context
bounded issue count
```

Rules:

1. The frontend must not synthesize an overall percentage when the backend does not supply a trustworthy total/percentage contract.
2. Unknown totals remain unknown, not zero.
3. Omitted counters remain omitted, not zero-filled.
4. Entries observed and entries committed remain semantically distinct when both are shown.
5. Roots and phases are not assumed to carry equal work weight.
6. An indeterminate activity treatment may show that work continues without implying completion percentage.
7. Per-root state may be presented independently from aggregate operation facts.
8. High-frequency progress refreshes may be coalesced.

## 22. Example Active Progress Presentation

A valid factual presentation could resemble:

```text
Phase: Discovering

Roots
3 requested
2 admitted
1 terminal

Entries
12,481 observed
12,203 committed

Issues
2
```

Only facts actually present in the authoritative projection are rendered.

This example is illustrative presentation structure, not a requirement for exact labels, grouping, or formatting.

## 23. Terminal-State Presentation

The generic terminal state remains authoritative.

### 23.1 `Completed`

Represents fully satisfied requested scope according to the operation contract.

### 23.2 `CompletedWithIssues`

Represents meaningful successful work reaching a safe durable terminal boundary while some requested scope remains unsatisfied.

Presentation must not relabel it as clean success or generic failure.

For `LibraryScan`, typed detail may explain causes such as:

- admission exclusions;
- one or more Partial scan outcomes;
- mixed successful and failed root outcomes.

### 23.3 `Failed`

Represents operation-defined failure where generic/typed detail explains safe bounded failure information.

### 23.4 `Cancelled`

Represents authoritative terminal cancellation, not merely a cancellation request.

### 23.5 `Interrupted`

Represents interruption semantics from the backend contract and remains distinct from user cancellation.

### 23.6 `Abandoned`

Represents stale/non-resumable execution recovery or other backend-defined abandonment semantics. It must not be presented as automatically resumed work.

## 24. Control Availability

Lifecycle controls appear only when the backend projection authorizes them.

Conceptually, job detail consumes explicit control availability rather than implementing frontend tables like:

```text
if operationType == LibraryScan && state == Failed then show Retry
```

The feature may still use typed operation detail to explain what a control will do, but the backend remains authoritative for whether that control is legal now.

Phase 001 list rows never expose lifecycle controls.

## 25. Cancel Workflow

Cancel appears only on job detail and only when authorized.

Activation uses a focused confirmation surface identifying the affected operation and explaining that already committed valid work may remain.

Canonical flow:

```text
Cancel
    ↓ confirm
JobsApi.cancelJob(jobRunId)
    ↓
authoritative reconciliation
```

Rules:

1. Flutter does not immediately mark the job `Cancelled` after the mutation returns.
2. The job remains Active until authoritative terminal state is observed.
3. `cancellationRequested` may become true before terminalization.
4. Duplicate Cancel is unavailable while cancellation is pending/requested.
5. Progress facts may continue changing while cooperative cancellation reaches a safe boundary.
6. A definite cancellation failure preserves the last confirmed job projection and surfaces the typed failure.
7. A transport-ambiguous result is reconciled before any conflicting control is attempted.

## 26. Retry Workflow

Retry appears only on job detail and only when authorized.

Retry means a new execution attempt, never reopening the selected historical run.

Canonical successful flow:

```text
/jobs/:oldJobRunId
    ↓ Retry
JobsApi.retryJob(oldJobRunId)
    ↓ new JobRun admitted
/jobs/:newJobRunId
```

Rules:

1. Every successful retry creates a new execution identity according to the backend contract.
2. The old run remains immutable history.
3. Successful admission navigates directly to the new job detail.
4. The new run may show **Retried from** the prior execution when relationship data is available.
5. The old run may show a navigation relationship to the retry-created execution when available.
6. Retry never broadens LibraryScan intent beyond the original requested scope.
7. If no original target remains eligible and no new execution is admitted, the user remains on the historical detail with a typed explanation.
8. Jobs must not fabricate an empty new job.

## 27. Retry Transport Ambiguity

Retry has identity consequences and therefore must never be blindly replayed after an ambiguous transport result.

Required behavior:

```text
retry transport outcome uncertain
    ↓
keep old job detail visible
    ↓
mark synchronization uncertain
    ↓
authoritatively reconcile retry/job relationship
    ↓
new JobRunId established -> navigate to new job
no admission established -> remain on old job
```

The exact backend query/relationship mechanism is supplied by the focused Phase 001 API/bridge contract.

The frontend must not create multiple retries merely because the first response was lost.

## 28. Resume Workflow

The generic Jobs presentation architecture may render Resume for a future operation type that explicitly advertises resumability and current control availability.

`LibraryScan` is non-resumable in Phase 001, and no active Phase 001 operation requires a frontend Resume mutation method.

Therefore:

- LibraryScan detail never presents Resume;
- Phase 001 does not add unused `JobsApi.resumeJob` or Resume widget/controller scaffolding;
- operation-name string matching is not the authority for hiding or later enabling Resume;
- a future focused operation/frontend contract must activate Resume together with the required API surface and authoritative control availability;
- no automatic Resume occurs after restart.

## 29. Control Mutation Concurrency

One unresolved lifecycle-control mutation per selected job is permitted at a time in the Jobs detail controller.

While a control is unresolved:

- last confirmed detail remains visible;
- conflicting controls are unavailable;
- the whole detail screen is not replaced with a spinner;
- unrelated Jobs list updates may continue;
- stale async completions cannot overwrite a newer control/reconciliation generation.

## 30. Jobs State Ownership

Feature-owned generated Riverpod controllers separate list and detail responsibilities.

Conceptually:

```text
JobsListController
- active jobs
- loaded recent pages
- recent paging state
- list reconciliation state

JobDetailController(jobRunId)
- authoritative JobDetail
- lifecycle-control operation state
- synchronization/reconciliation state

activeJobSummaryProvider/controller
- narrow shell-safe authoritative summary
```

The shell summary is intentionally not derived from private Jobs list state.

## 31. Provider Lifetime

Provider lifetime follows SPEC-FE-002.

- `JobDetailController(jobRunId)` is identity-parameterized and normally disposable/recreatable.
- Jobs list state may survive the current Jobs branch observation while needed by shell/navigation composition only if its owner has a concrete lifecycle reason; it is not `keepAlive` merely as a cache convenience.
- shell active-job summary state may be application-lifetime because the shell consumes it independently of the Jobs destination, provided its invalidation contract remains explicit.
- persistent durable authority remains backend state, not Riverpod retention.

## 32. Authoritative Query Model

Queries are the source of truth.

Canonical event response:

```text
job event/invalidation
    ↓
identify affected projection scope
    ↓
JobsApi query
    ↓
publish authoritative state
```

Flutter must not:

- transition lifecycle states directly from event payloads;
- increment progress counters from event deltas;
- create a locally authoritative new job because a mutation was initiated;
- infer completion merely because an active indicator disappeared;
- reconstruct missed transitions from event sequence numbers.

## 33. Focused Event Reconciliation

When event identity/scope is reliable:

- one job changed → refresh the open matching detail if observed;
- active membership changed → refresh the shell active-job summary;
- list state/membership changed → refresh the affected active/recent list projection;
- high-frequency progress notifications → coalesce focused detail/list refresh where safe.

The Jobs landing and an open detail may reconcile independently. Neither is the authority for the other.

## 34. Event Gap and Runtime Replacement

A sequence gap, reconnect uncertainty, or runtime replacement invalidates assumptions about unobserved transitions.

Required response:

```text
event continuity uncertain
    ↓
discard event-derived assumptions
    ↓
refresh authoritative Jobs projections
```

For an open detail, refresh that job directly.

For `/jobs`, refresh active membership and the currently loaded recent-history window as required by the focused query contract.

For the shell, refresh the active-job summary.

No event replay reconstruction is attempted in Flutter.

## 35. Jobs List Reconciliation

Stable row identity is `JobRunId`.

After authoritative refresh:

- an active job that became terminal moves into the Recent projection according to backend ordering;
- a newly discovered active job appears in Active;
- already loaded historical rows remain stable by ID;
- page-boundary duplicates are removed by ID;
- terminal history is not removed because current Sources roots changed;
- partial pages are not globally resorted under a frontend-owned ordering claim.

## 36. Detail Refresh Behavior

Ordinary detail refresh retains last confirmed detail while newer authoritative state is fetched.

This applies to:

- progress refresh;
- cancellation reconciliation;
- retry admission reconciliation;
- event-driven invalidation;
- event-stream/runtime replacement;
- non-blocking background refresh.

Only an initial load with no confirmed detail uses the initial loading state.

A stale/disposed async completion must never publish over a newer authoritative generation.

## 37. Active-Job Shell Indicator

The adaptive shell owns the indicator's presentation location; Jobs owns the focused summary semantics.

The indicator consumes `ActiveJobSummary`, not Jobs private feature state.

Canonical behavior:

```text
activeCount == 0
    → no active-job indicator

activeCount == 1
    → show truthful single-job summary
    → activate → /jobs/:soleJobRunId

activeCount >= 2
    → show aggregate active count
    → activate → /jobs
```

The indicator must not infer active count from Sources or from locally initiated work.

Events may invalidate the summary, but an authoritative query establishes its state.

## 38. Shell Indicator Presentation Limits

The indicator is intentionally compact.

It may show bounded text such as:

```text
Scanning…
```

for one active LibraryScan, or:

```text
2 jobs active
```

for multiple active jobs.

It must not:

- compute or show an aggregate percentage;
- combine unrelated operation phases into one pseudo-progress value;
- expose detailed per-root state;
- become an expandable replacement for the Jobs destination;
- create a second job-control surface.

## 39. Sources Integration

SPEC-FE-008 remains authoritative for Sources-local scan summaries and **View Job** navigation.

Jobs integration rules are:

- Sources may navigate to `/jobs/:jobRunId`;
- Sources may call the generic Cancel capability inside its separately specified **Cancel Scan & Remove** workflow;
- Jobs does not depend on Sources controller/widget lifetime;
- Jobs does not query current Sources state to reconstruct historical LibraryScan detail;
- current Sources root removal does not erase terminal Jobs history.

## 40. Historical Independence

A LibraryScan job must remain intelligible when:

- the original root has been removed;
- its current source graph no longer exists;
- the same physical folder has been added later as a new root;
- current availability differs from historical availability.

Jobs uses the historical root display snapshots and operation detail supplied by the backend.

It must never silently rebind a historical job to a newly created `LibraryRootId` merely because a display path appears equivalent.

## 41. Failure-State Categories

Jobs distinguishes failure by scope.

### 41.1 Initial Jobs list failure

With no confirmed list content, show a scoped Jobs error surface with Retry.

### 41.2 Recent-history page failure

Keep all existing active/recent rows and expose retry for only the failed page request.

### 41.3 Initial job-detail failure

Show a job-scoped error/not-found surface without fabricating detail from list data.

### 41.4 Background reconciliation failure

Keep confirmed content visible and show bounded stale/synchronization state.

### 41.5 Definite lifecycle-control failure

Keep confirmed detail visible and surface the typed frontend/application failure.

### 41.6 Ambiguous lifecycle-control outcome

Do not claim success or failure. Enter synchronization uncertainty and reconcile authoritatively before allowing conflicting replay.

## 42. Bounded Failure Information

Normal Jobs UI may show user-actionable, sanitized failure information supplied through governed application/client contracts.

It must not render:

- raw Rust error chains;
- panic/debug output;
- native exception dumps;
- arbitrary database errors;
- provider-native path/identity data simply because it exists in diagnostics;
- unsanitized bridge payloads.

Trace/job identities may be made available in appropriate support/technical detail surfaces according to existing diagnostics conventions, but they are not the primary user-facing failure message.

## 43. Privacy and Safe Operation Context

Jobs may display user-meaningful safe historical context, including library-folder display information that the backend explicitly projects for presentation.

Jobs must not expose:

- provider-native locators;
- provider-native identities;
- source fingerprints;
- internal database row IDs;
- arbitrary internal operation payloads;
- secrets/tokens;
- raw user paths in logging merely because equivalent safe UI text is visible on screen.

Application identities such as `JobRunId` remain governed typed identifiers, not database metadata.

## 44. Accessibility Requirements

Jobs follows SPEC-FE-007.

Required semantics include:

- lifecycle state is perceivable as text, not color alone;
- `CompletedWithIssues` is distinguishable from `Completed` and `Failed`;
- cancellation requested is distinguishable from terminal `Cancelled`;
- active-job shell indicator exposes a semantic label including active count where applicable;
- indeterminate activity is announced as ongoing, not as an unknown percentage;
- structured counters identify what they count;
- control availability uses actual enabled/disabled semantics;
- Cancel confirmation identifies the affected operation;
- Retry communicates that a new execution attempt will be created;
- per-root outcomes remain distinguishable without relying on color alone.

## 45. Keyboard and Focus Requirements

Desktop Jobs interaction must be fully keyboard-operable.

Required behavior:

- job rows are reachable through normal list navigation and activatable by keyboard;
- routine progress refresh does not unexpectedly move list focus;
- opening job detail establishes sensible focus in the new routed/detail region;
- lifecycle controls are keyboard reachable;
- Cancel/Retry confirmation uses standard modal focus trapping;
- dismissing a modal restores focus to the initiating control when it still exists;
- successful Retry navigation moves focus into the new job detail rather than leaving focus attached to the historical run;
- paging additional history does not reset focus to the start of the list;
- no critical control is hover-only.

## 46. Text Scale and Theme Behavior

Jobs must remain usable at representative 1.0x and 2.0x text scaling and under Light, Dark, and System application theme behavior defined by SPEC-FE-006/SPEC-FE-007.

At larger text scale:

- rows may grow vertically;
- secondary data may wrap;
- control labels must not become clipped into ambiguous abbreviations;
- split-view layouts may collapse based on local constraints before content becomes inaccessible.

## 47. Performance Requirements

Jobs must remain bounded as history grows.

Required rules:

1. `/jobs` materializes active jobs plus only the currently loaded Recent window.
2. Recent terminal history uses backend pagination rather than loading all history.
3. Job detail is queried separately from list-row projection.
4. List rows do not eagerly fetch full typed operation detail.
5. A rapidly updating active job does not force unrelated terminal job detail to refresh.
6. Progress invalidations may be coalesced.
7. The shell summary uses a narrow query/projection and does not load the entire Jobs destination.
8. Normal navigation does not keep every previously opened job-detail controller permanently alive.
9. No Phase 001 client-side archival or retention engine is introduced.

## 48. Recent-History Pagination

Recent history follows the bounded pagination contract supplied by the backend.

Where Phase 001 uses bounded offset pagination as permitted by ARCH-001/SPEC-BE-013:

- the controller records the loaded window and next-page state explicitly;
- a next-page request is independent from active-job refresh;
- duplicate identities at reconciliation boundaries are removed by `JobRunId`;
- if terminal membership changes while paging, a focused refresh may reset/reconcile the loaded window rather than trying to mathematically repair stale offsets locally;
- Flutter does not claim snapshot isolation the backend did not provide.

## 49. Observability

Jobs-related frontend observability may record sanitized interaction/transport facts through approved frontend diagnostics mechanisms.

It must preserve backend `TraceId`/`JobRunId` correlation where those identifiers are part of governed error/operation context.

It must not:

- duplicate backend logs as a second execution source of truth;
- log high-frequency progress payloads without a bounded diagnostic need;
- emit raw source paths/locators;
- infer successful cancellation/retry from UI interaction alone.

## 50. Restart Behavior

After application restart:

- `/jobs` loads authoritative active/recent projections from persisted backend state;
- `/jobs/:jobRunId` re-queries that execution identity;
- stale active LibraryScan executions are expected to have been reconciled by the backend to the governing recovery terminal state;
- Flutter must not display a stale pre-restart job as Running merely because that was the last in-memory value;
- no significant user work automatically resumes in Phase 001;
- the active-job shell indicator derives from the post-recovery authoritative summary.

## 51. `LibraryScan` Restart Presentation

Phase 001 `LibraryScan` is non-resumable.

A stale active scan reconciled to `Abandoned` must be presented as historical terminal work.

The detail may expose Retry when backend control availability permits it, but it must not imply that the original scan continues from its previous execution checkpoint.

Committed positive source observations remain outside Jobs frontend ownership and are not rolled back by presentation logic.

## 52. Controller Test Requirements

Deterministic controller tests must cover at least:

- active/recent initial load;
- Jobs empty state projection;
- recent-history pagination;
- independent page failure/retry;
- active-to-terminal movement;
- stable `JobRunId` deduplication;
- backend-order preservation;
- focused job-event reconciliation;
- high-frequency invalidation coalescing where implemented;
- sequence-gap/runtime-replacement authoritative refresh;
- stale/disposed async result rejection;
- initial detail load;
- detail refresh retaining confirmed content;
- generic terminal states including `CompletedWithIssues`;
- Cancel success followed by authoritative reconciliation;
- Cancel definite failure;
- Cancel ambiguous transport outcome without blind replay;
- cancellation-requested state remaining Active;
- Retry success returning/navigating to a new identity;
- Retry definite failure;
- Retry ambiguous outcome without duplicate replay;
- Retry unavailability when original intent cannot be admitted;
- LibraryScan Resume unavailable;
- historical LibraryScan detail after root removal;
- shell summary with zero active jobs;
- shell summary with one active job;
- shell summary with multiple active jobs.

## 53. Widget Test Requirements

Deterministic widget tests must cover at least:

- Jobs semantic destination presentation at representative size classes;
- Jobs empty state;
- Active and Recent sections;
- job-list navigation;
- Compact/Medium full-page detail;
- Expanded/Large list/detail split;
- generic job-detail shell;
- typed LibraryScan detail;
- factual indeterminate progress;
- absence of fabricated percentage;
- per-root mixed outcomes and admission exclusions;
- `CompletedWithIssues` presentation;
- Cancel confirmation;
- cancellation-requested presentation;
- Retry confirmation/navigation to the new run;
- absence of Resume for LibraryScan;
- shell indicator hidden for zero active jobs;
- shell indicator direct navigation for one active job;
- aggregate shell indicator for multiple active jobs;
- invalid/unavailable job route behavior;
- keyboard/focus behavior;
- accessibility semantics;
- representative 1.0x and 2.0x text scaling;
- Light/Dark/System compatibility.

Normal frontend tests use focused API/provider fakes rather than a real Rust backend.

## 54. Client/Mapper Test Requirements

The Phase 001 focused client/bridge amendment must support mapper tests covering:

- all generic `JobRun` lifecycle states;
- `CompletedWithIssues` preservation;
- typed `JobRunId` mapping;
- job-list projection mapping;
- authoritative control availability mapping;
- active-job summary mapping;
- `JobDetail` mapping;
- typed `LibraryScanJobDetail` mapping;
- progress facts with nullable/unknown totals preserved;
- cancellation-requested state;
- bounded failure mapping;
- Retry/Resume result identity relationships required by the frontend contract;
- historical root display snapshots;
- invalid required representation rejected as contract mismatch rather than defaulted.

## 55. Integration and Native Verification

Phase 001 integration/native verification must prove the real architecture path for Jobs without replacing deterministic frontend tests.

Required milestone evidence includes:

- a real admitted LibraryScan appears in Jobs;
- the shell indicator reflects authoritative active-job state;
- one active job indicator navigates to that job detail;
- active progress changes through authoritative query reconciliation;
- cancellation reaches a durable terminal boundary;
- terminal state persists across process restart;
- Retry creates a new execution identity;
- the old run remains historical;
- stale pre-restart active LibraryScan state does not reappear as resumed active work;
- Jobs remains usable independently of Sources widget/controller lifetime.

Manual verification may be deferred according to current project workflow, but deferred manual evidence must never be recorded as passed automated verification.

## 56. No Duplicate Authority

The following are prohibited:

- a shell-maintained mutable active-job list independent of backend queries;
- a Jobs-controller lifecycle state machine that advances backend state locally;
- progress counters accumulated from events as authority;
- Sources-owned job history used as Jobs data;
- retrying a mutation automatically after ambiguous transport outcome;
- marking Cancelled immediately because the user pressed Cancel;
- reusing the old `JobRunId` for Retry;
- representing `CompletedWithIssues` as generic success/failure Boolean;
- hiding jobs because their current source root was removed.

## 57. No Percentage Fabrication

The frontend must not create progress percentages from combinations such as:

- entries observed divided by an unknown eventual entry count;
- roots terminal divided by roots admitted as a proxy for total execution completion;
- phase ordinal divided by number of phases;
- weighted mixtures of roots and entries without an explicit backend contract;
- arbitrary time estimates.

If a later operation supplies a trustworthy percentage or determinate total through its typed contract, that future specification may define its presentation.

## 58. No Future Operation Scaffolding Requirement

Although the Jobs architecture supports typed operation variants, Phase 001 implementation must not create empty production variants, widgets, providers, routes, or tests for operations not yet active.

The extensibility rule is architectural, not a requirement to populate speculative future types.

## 59. Phase 001 Out of Scope

SPEC-FE-009 intentionally excludes:

- Jobs search;
- arbitrary filters;
- status/type tabs;
- user-defined sort order;
- bulk cancellation;
- bulk retry;
- historical job deletion;
- editable job names;
- pinning/favoriting jobs;
- global notification-center functionality;
- desktop notifications for job completion;
- percentage estimation for unknown work;
- estimated time remaining;
- arbitrary JSON operation detail;
- automatic Retry;
- automatic Resume;
- LibraryScan Resume;
- history retention/pruning settings;
- future operation-type presentation before its governing phase/spec activates it.

## 60. Acceptance Criteria

SPEC-FE-009 is satisfied when:

1. Jobs is a genuine lower-frequency semantic destination presented under More on Compact, rail on Medium, and sidebar on Expanded/Large.
2. Jobs remains available independently of current job count.
3. Canonical routes are `/jobs` and `/jobs/:jobRunId` across all layouts.
4. `JobRunId` route identity identifies one immutable execution attempt.
5. Compact/Medium use full-page detail and Expanded/Large may use list/detail split without URI rewriting.
6. `/jobs` presents Active before Recent.
7. Recent terminal history is incrementally paged without loading unbounded history.
8. Phase 001 adds no Jobs search/filter/tab UI.
9. Job list rows are navigational and do not expose inline lifecycle controls.
10. Generic job detail presents lifecycle facts independently from typed operation detail.
11. LibraryScan detail uses a typed operation-specific projection and remains intelligible after root removal.
12. Jobs renders the exact backend lifecycle vocabulary, including `CompletedWithIssues`, `Interrupted`, and `Abandoned`.
13. `CompletedWithIssues` is not collapsed into clean success or generic failure.
14. LibraryScan progress shows only authoritative phases/counters and never fabricates an overall percentage.
15. Unknown totals remain unknown rather than becoming zero or guessed values.
16. Cancel appears only when backend control availability permits it and uses an explicit confirmation.
17. Cancel does not locally mark a job terminal; Jobs reconciles authoritative state.
18. Cancellation-requested work remains Active until authoritative terminalization.
19. Retry appears only when authorized and creates a new execution identity.
20. Successful Retry navigates directly to `/jobs/:newJobRunId` while the old run remains immutable history.
21. Ambiguous Retry transport outcomes are reconciled without blind replay or duplicate execution creation.
22. LibraryScan never exposes Resume because it is non-resumable.
23. Lifecycle-control availability is backend-authoritative rather than operation-name string logic.
24. The shell active-job indicator uses a narrow authoritative summary independent of Jobs private controller lifetime.
25. Zero active jobs hide the shell indicator.
26. One active job indicator navigates directly to that job detail.
27. Multiple active jobs show an aggregate count and navigate to `/jobs`.
28. The shell indicator never fabricates aggregate percentage/progress.
29. Events trigger authoritative reconciliation rather than direct lifecycle/progress mutation in Flutter.
30. Event gaps/runtime replacement recover through focused authoritative queries.
31. Loaded confirmed Jobs content remains visible during ordinary refreshes and lifecycle-control mutations.
32. Stale async results cannot overwrite newer authoritative state.
33. Active-to-terminal movement and paged history deduplicate by stable `JobRunId` without claiming a frontend-owned global ordering.
34. Historical job presentation does not depend on current Sources controller/widget state.
35. Removing/re-adding a physical folder never silently rebinds old job history to the new root identity.
36. Jobs normal UI does not expose provider-native locators, raw Rust/native failures, or arbitrary internal payloads.
37. Keyboard, focus, accessibility, text-scale, and Light/Dark/System behavior meet FE-007 requirements.
38. Jobs remains bounded as history grows and does not eagerly load full operation detail for list rows.
39. Restart presentation reflects backend-reconciled persistent job state and does not automatically resume LibraryScan.
40. Deterministic controller/widget/client tests cover the approved list, detail, progress, control, uncertainty, shell-indicator, adaptive, and accessibility contracts.
41. Phase 001 integration/native verification exercises a real LibraryScan through Jobs and the shell indicator without treating deferred manual checks as passed.

## 61. References

- `docs/architecture/architecture-overview.md` — ARCH-001
- `docs/architecture/documentation-architecture.md` — ARCH-002
- `docs/phases/phase-001-local-sources-and-indexing.md` — PHASE-001
- `docs/specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md` — SPEC-BE-004
- `docs/specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md` — SPEC-BE-008
- `docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md` — SPEC-BE-013
- `docs/specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md` — SPEC-FE-001
- `docs/specifications/frontend/spec-fe-002-riverpod-freezed-and-controller-state-conventions.md` — SPEC-FE-002
- `docs/specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md` — SPEC-FE-003
- `docs/specifications/frontend/spec-fe-004-routing-and-adaptive-application-shell.md` — SPEC-FE-004
- `docs/specifications/frontend/spec-fe-005-startup-and-recovery-ui.md` — SPEC-FE-005
- `docs/specifications/frontend/spec-fe-006-appearance-settings-and-theme-application.md` — SPEC-FE-006
- `docs/specifications/frontend/spec-fe-007-design-system-foundation-and-accessibility-baseline.md` — SPEC-FE-007
- `docs/specifications/frontend/spec-fe-008-sources-and-library-folder-management.md` — SPEC-FE-008
