# Application Runtime, Command Pipeline, and Background Operations Specification

**Document ID:** SPEC-BE-004  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-15  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-002, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-X-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative runtime execution model for Argus ROM Toolkit, including runtime lifecycle, centralized operation admission, query and command dispatch, immediate commands, background operations, job identity, progress reporting, cancellation, shutdown, resource-class concurrency, restart recovery, bridge interaction, event sequencing, and runtime ownership boundaries.

The design keeps the runtime focused on orchestration rather than implementation-specific scheduling. Public contracts express application and operational intent instead of technology choices. Queries and commands share one runtime operation lifecycle while retaining distinct execution semantics. Background work is modeled explicitly through independently managed `JobRun` executions rather than by treating every asynchronous call as a generic queued command.

## 2. Scope

This specification covers:

- `ApplicationRuntime` lifecycle and state transitions
- runtime instance identity and replacement
- centralized operation admission
- shared runtime operation lifecycle
- operation classification
- query dispatch
- immediate command dispatch
- background-operation admission and execution
- `BackgroundOperationManager` ownership
- `JobRunId` execution identity
- persisted job lifecycle states
- retry and resume semantics
- structured progress reporting
- resource-class concurrency
- subsystem executor ownership
- cancellation propagation
- shutdown coordination and force-quit safety
- restart recovery and abandoned work reconciliation
- bridge push/pull interaction model
- event sequencing, coalescing, and backpressure
- technology-neutral public contracts
- Phase 000 runtime minimums

## 3. Non-Responsibilities

This specification does not define:

- concrete async-runtime libraries or task primitives
- concrete channel implementations
- concrete thread-pool implementations
- SQLite executor internals already owned by SPEC-BE-002
- provider retry, throttling, or rate-limit algorithms
- filesystem executor implementation
- execution-graph node semantics for later processing subsystems
- Flutter widgets, Riverpod controllers, or UI presentation rules
- exact bridge DTO serialization layouts
- the complete domain-event catalog
- provider-specific background-operation policies
- exact shutdown timeout durations
- exact resource capacity values
- weighted multi-phase progress
- automatic resumption of significant user operations during MVP

Those concerns belong to infrastructure, provider, bridge, frontend, operation-specific, or implementation-level specifications.

## 4. Architectural Principles

1. The runtime orchestrates application execution but does not become a general-purpose scheduler for every subsystem.
2. Every bridge-facing backend operation uses one shared runtime operation lifecycle.
3. Every admitted application operation is statically classified as exactly one of: Query, Immediate Command, or Background Operation.
4. Queries produce no authoritative side effects.
5. Immediate commands execute directly within the initiating runtime operation.
6. Background operations have an independently managed lifecycle after admission.
7. Runtime admission is centralized and evaluated exactly once before dispatch.
8. Subsystems own their own internal execution policies.
9. Background-operation concurrency is controlled through logical resource classes, not implementation technologies or operation names.
10. Runtime contracts express operational intent and must not leak technology-stack implementation details.
11. `JobRunId` is the canonical identity of one background execution attempt.
12. Every retry or resume creates a new `JobRunId`.
13. Structured progress facts are authoritative; percentages are presentation-derived.
14. Graceful shutdown is an efficiency and user-experience mechanism, never a data-integrity requirement.
15. Process termination at any instruction boundary must not corrupt authoritative state.
16. Events are best-effort notifications; authoritative state remains queryable.
17. Runtime replacement is an explicit lifecycle boundary.
18. Adding a new operation should normally require declaring operation behavior and policy, not modifying core runtime lifecycle logic.
19. Generic terminal job state distinguishes clean completion from safely finalized meaningful work whose requested scope was not fully satisfied; operation-specific contracts provide the detailed meaning.

## 5. Technology-Neutral Runtime Contracts

Public application and runtime contracts express domain and operational concepts, never concrete implementation technology.

Preferred vocabulary includes:

```text
PersistenceRead
PersistenceWrite
FilesystemRead
FilesystemWrite
MetadataProviderNetwork
CpuIntensive
BackgroundOperationManager
OperationContext
CancellationToken
RuntimeInstanceId
```

Public runtime contracts must not expose names such as:

```text
SQLiteWrite
RusqliteOperation
TokioTask
TokioScheduler
ThreadPoolWork
ReqwestRequest
ZipWriter
```

Technology-specific names remain inside infrastructure or runtime implementation modules where they accurately identify adapters.

This rule allows Argus to change its database implementation, async runtime, HTTP client, logging backend, archive implementation, filesystem execution strategy, or other technical choices without changing application-facing contracts.

## 6. Runtime Ownership Model

`ApplicationRuntime` is the composition and lifecycle owner of one runtime generation.

Conceptually:

```text
ApplicationRuntime
├── RuntimeAdmission
├── QueryDispatcher
├── CommandDispatcher
├── BackgroundOperationManager
├── event publication infrastructure
├── operation-context creation
├── observability coordination
└── subsystem handles
    ├── persistence
    ├── filesystem/artifact I/O
    ├── source providers
    └── metadata providers
```

The runtime owns:

- lifecycle state
- runtime-instance identity
- operation admission
- operation classification enforcement
- `TraceId` creation through SPEC-BE-003 contracts
- cancellation-root ownership
- dispatcher coordination
- background-operation manager lifecycle
- event sequence ownership
- shutdown orchestration
- runtime replacement coordination

The runtime does not own:

- SQLite transaction scheduling
- metadata-provider request concurrency
- source-provider internal access scheduling
- filesystem/artifact work scheduling
- operation business rules
- domain validation
- provider-specific retry behavior
- operation-specific checkpoint placement

## 7. Subsystem Executor Ownership

Each subsystem owns its execution policy.

Examples:

- Persistence owns database serialization and connection/thread affinity.
- Filesystem/artifact infrastructure owns host-local filesystem work concurrency.
- Source-provider infrastructure owns provider-specific source-access concurrency and pacing where applicable.
- Metadata-provider infrastructure owns external-provider request concurrency, rate limiting, and request retry policy.
- `BackgroundOperationManager` owns top-level background-operation admission and scheduling.

The runtime coordinates these subsystems but does not centrally schedule their internal work items.

Required invariant:

> Every subsystem owns how its work executes. The runtime owns whether an application operation may begin and how top-level operation lifecycles are coordinated.

Double-queueing through a general runtime executor and then a subsystem executor is prohibited unless a concrete implementation requirement is documented and does not alter application semantics.

## 8. Operation Classes

The runtime supports exactly three application execution classes:

```text
Operation
├── Query
├── ImmediateCommand
└── BackgroundOperation
```

No additional runtime execution classes such as `AsyncCommand`, `LongRunningCommand`, `ProviderCommand`, or `ScheduledCommand` are introduced.

Operation-specific behavior is expressed through policy and capability declarations rather than new execution classes.

### 8.1 Query

A query observes application state and produces no authoritative side effects.

Queries may return:

- snapshots
- projections
- current status
- capability information
- health information
- immutable details

Queries may produce incidental runtime effects such as:

- structured logs
- trace events
- metrics
- performance instrumentation
- in-memory cache population or eviction
- ephemeral bookkeeping

These incidental effects do not change authoritative application state and therefore do not make the operation a command.

### 8.2 Immediate Command

An immediate command produces an authoritative side effect and reaches its terminal result before the initiating runtime operation completes.

Examples include:

- updating a setting
- adding or removing a configured root
- enabling a provider
- changing metadata overrides

Immediate commands execute directly through their handler. They are not submitted to a general runtime command queue.

### 8.3 Background Operation

A background operation creates an independently managed execution lifecycle after admission.

A background operation may:

- continue after the initiating bridge request returns
- report progress over time
- support independent cancellation
- require runtime resource admission
- be scheduled or deferred
- survive temporary UI disconnects
- use restart-safe checkpoints
- have persisted job state

Background classification is determined by lifecycle requirements, not elapsed duration.

## 9. Authoritative Side Effects

A query is defined by the absence of authoritative side effects.

Authoritative side effects include:

- persisting application state
- creating, changing, or deleting domain or application records
- publishing domain events as the result of a state transition
- creating, scheduling, cancelling, or modifying background jobs
- writing or publishing user-visible files or exports
- calling external providers when the request itself is part of application behavior
- changing runtime configuration or lifecycle state

Incidental observability and cache maintenance are not authoritative side effects.

Idempotency is not used to classify queries. A command may be idempotent while still modifying authoritative state.

## 10. Shared Runtime Operation Lifecycle

Queries and commands share one runtime operation wrapper.

Conceptually:

```text
request received
    ↓
classify operation
    ↓
central admission
    ↓
create OperationContext and TraceId
    ↓
register cancellation and timeout policy
    ↓
emit started trace event
    ↓
dispatch query / immediate command / background admission
    ↓
map terminal result
    ↓
emit terminal trace event
    ↓
return
```

The shared lifecycle owns:

- admission outcome
- operation context
- `TraceId`
- timing
- panic/error containment
- cancellation registration
- stable error mapping
- terminal observability

Dispatchers must not independently implement different tracing, cancellation, shutdown, or error semantics.

## 11. Centralized Runtime Admission

All operations pass through one runtime admission gate before dispatch.

Admission answers:

> May this operation begin now?

Admission evaluates:

- runtime lifecycle state
- operation class
- whether the operation is permitted in the current state
- shutdown admission closure
- pre-dispatch cancellation
- runtime-wide policy
- background resource availability where applicable

Admission is evaluated exactly once.

Subsystems may still fail after admission because of capability-specific conditions such as database unavailability or provider failure. Those are execution failures, not admission failures.

Subsystems must not reimplement runtime readiness or shutdown admission policy.

## 12. Runtime Lifecycle State Machine

The runtime states are:

```text
Uninitialized
Starting
Ready
StartupFailed
ShuttingDown
Stopped
```

Valid primary transitions:

```text
Uninitialized -> Starting
Starting -> Ready
Starting -> StartupFailed
Ready -> ShuttingDown
StartupFailed -> ShuttingDown
ShuttingDown -> Stopped
```

`Stopped` is terminal.

### 12.1 `Uninitialized`

The runtime instance exists but startup has not begun.

Permitted:

- startup initiation
- immutable lifecycle inspection

Normal queries, commands, and background admission are rejected.

### 12.2 `Starting`

Mandatory startup work is executing.

Permitted operations are limited to startup-safe capabilities such as:

- startup status
- startup-safe diagnostics
- controlled shutdown

Normal application queries, commands, and background operations are rejected.

### 12.3 `Ready`

Normal application operation is permitted.

The runtime accepts:

- queries
- immediate commands
- background-operation admission
- cancellation commands
- runtime health queries
- diagnostic export
- shutdown

### 12.4 `StartupFailed`

Mandatory startup failed before readiness.

The instance remains available only for:

- failure inspection
- startup-safe diagnostics
- health/status inspection
- controlled shutdown and cleanup

The failed runtime instance cannot be started again.

A retry creates a new runtime instance after the failed instance is retired.

### 12.5 `ShuttingDown`

The current runtime instance is being permanently retired.

New normal work is rejected immediately.

Already admitted work follows its declared shutdown policy under a runtime-owned overall shutdown deadline.

Limited status or diagnostics may remain available when safe.

### 12.6 `Stopped`

All runtime-owned lifecycle work is complete or explicitly finalized according to shutdown policy.

The instance cannot restart and accepts no operational work.

## 13. Runtime Instance Replacement

Every runtime instance owns one opaque `RuntimeInstanceId`.

`RuntimeInstanceId` identifies one runtime generation only. It is not a domain identity and must not be used as a business key.

A `StartupFailed` or `Stopped` runtime is never reused for startup.

Replacement flow:

```text
Runtime A
    ↓ StartupFailed or requested retirement
ShuttingDown
    ↓
Stopped
    ↓
construct Runtime B
    ↓
Uninitialized -> Starting -> Ready
```

A new runtime generation owns fresh:

- dispatchers
- background-operation manager
- subsystem handles
- event channels
- cancellation roots
- event sequence
- runtime instance identity

Stale handles from an earlier runtime generation must not remain usable.

## 14. Query Dispatch

The query path is lightweight and read-oriented.

Conceptually:

```text
Bridge/API
    ↓
Runtime admission
    ↓
shared operation lifecycle
    ↓
QueryDispatcher
    ↓
query handler
    ↓
query interface / subsystem
    ↓
immutable result
```

A query must not:

- create a Unit of Work for mutation
- write authoritative application state
- publish domain events as a state transition
- create a `JobRun`
- enter background scheduling
- write user-visible files

Queries may still wait behind subsystem-owned execution constraints. For example, during MVP a persistence query still executes through the database executor defined by SPEC-BE-002.

The split query path therefore avoids command machinery but does not bypass persistence consistency or subsystem execution policy.

## 15. Immediate Command Dispatch

Immediate commands execute directly inside the initiating runtime operation.

Conceptually:

```text
Bridge/API
    ↓
Runtime admission
    ↓
shared operation lifecycle
    ↓
CommandDispatcher
    ↓
command handler
    ↓
Unit of Work / subsystem operations
    ↓
commit
    ↓
publish committed events
    ↓
return result
```

Rules:

- There is no application-wide command queue for immediate commands.
- Blocking technical work may be delegated to the owning subsystem executor.
- The command retains ownership of its operation until terminal completion.
- Cancellation before durable commit may roll back according to SPEC-BE-002.
- Cancellation after durable commit must not turn committed success into cancellation.
- Long-running work requiring an independent lifecycle must be represented as a background operation instead.

## 16. Background Operation Admission

A background command has two distinct top-level operations:

```text
admission command
    TraceId A
    ↓
creates JobRunId
    ↓
background execution
    TraceId B
```

The admission command validates the request, creates the persisted `JobRun`, and requests background admission.

The background execution receives a new `TraceId` because it is independently managed.

The two operations are linked through Argus-owned identities such as:

- `CommandId`
- `JobRunId`
- operation-specific entity IDs

The background execution must not reuse the admission trace indefinitely.

### 16.1 Admission durability boundary

Background admission succeeds only after both of the following are true:

1. the new `JobRun` is durably persisted; and
2. runtime responsibility for executing, queueing, or startup-reconciling that run is durably or deterministically established.

A failed admission must not leave an orphan nonterminal `JobRun` with no manager responsibility. If persistence succeeds and later registration fails, the implementation must either complete registration and return the accepted handle, terminalize or reconcile the run before returning failure, or return acceptance only when startup recovery has enough durable evidence to assume responsibility.

A crash between persistence and in-memory registration is reconciled at startup. The exact transaction, handoff, or reconciliation mechanism is an implementation detail, but the caller-visible boundary and orphan-prevention invariant are mandatory and tested.

## 17. `BackgroundOperationManager`

`ApplicationRuntime` owns the lifecycle of one `BackgroundOperationManager`.

The manager owns:

- background admission
- pending job registry
- active job registry
- top-level scheduling
- resource-class acquisition and release
- progress coordination
- cancellation coordination
- persisted job lifecycle transitions
- retry/resume admission
- shutdown coordination for active jobs
- cleanup of in-memory job execution state

The manager does not own:

- operation business logic
- provider-specific request scheduling
- database execution policy
- filesystem execution policy
- domain validation
- operation-specific checkpoint structure

The manager understands operation policies and resource declarations but must not contain tool-specific or provider-specific behavior.

## 18. Job Identity

`JobRunId` is the canonical identity for one background execution attempt.

It is used for:

- lifecycle state
- progress
- cancellation
- diagnostics
- logs
- event payload identity
- bridge queries
- persisted execution history

Examples:

```text
CancelJob(JobRunId)
GetJob(JobRunId)
ResumeJob(JobRunId)
RetryJob(JobRunId)
```

After assignment, `JobRunId` follows the identity-first observability rules of SPEC-BE-003.

## 19. JobRun Persistence Model

The conceptual persisted model is:

```text
JobRun
- id
- operation_type
- state
- command_id nullable
- resumed_from_job_run_id nullable
- created_at
- queued_at nullable
- started_at nullable
- completed_at nullable
- current_phase nullable
- completed_units nullable
- total_units nullable
- status_key nullable
- cancellation_requested
- terminal_error_code nullable
- terminal_safe_context nullable
```

Exact schema and serialization belong to the persistence implementation plan, but the semantics are fixed.

Rules:

- `operation_type` is a stable logical operation identifier, not an implementation class name.
- A job's `JobRunId` never changes.
- Historical terminal runs are immutable except for explicitly allowed metadata that does not alter execution history.
- Recovery links use `resumed_from_job_run_id` only for genuine resume relationships.
- Retry does not claim checkpoint continuation.

## 20. Persisted Job States

Canonical states are:

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

### 20.1 `Queued`

The job has been accepted and persisted but has not acquired required runtime resources.

### 20.2 `Preparing`

The operation is resolving execution scope, validating prerequisites, building plans, or performing preparation before primary work.

Preparation may be indeterminate.

### 20.3 `Running`

Primary operation execution is active.

### 20.4 `Completed`

All authoritative state and external artifacts required for the requested successful operation scope are durably finalized without operation-specific unresolved issues.

Terminal.

### 20.5 `CompletedWithIssues`

The execution reached a safe and durably finalized terminal boundary and produced meaningful successful work, but the requested operation scope was not fully satisfied.

Operation-specific detail identifies the unsatisfied scope or issues. This state is a durable lifecycle fact, not a transient transport warning or presentation-only label.

Terminal.

### 20.6 `Failed`

The operation terminated because of a non-cancellation failure and did not reach a safe operation-defined completion boundary for the current execution attempt. Durable partial work may exist; partial work alone does not justify `CompletedWithIssues`.

Terminal.

### 20.7 `Cancelled`

The operation acknowledged cancellation and reached a safe terminal boundary.

Terminal.

### 20.8 `Interrupted`

Execution ended unexpectedly but durable recovery checkpoints may permit a future resume as a new execution attempt.

`Interrupted` is terminal for the original `JobRun`. A resume creates a new `JobRunId` linked through `resumed_from_job_run_id`.

`Interrupted` is not resumed automatically during MVP.

### 20.9 `Abandoned`

Execution ended unexpectedly and the execution attempt cannot be resumed from its prior checkpoint state.

A future retry creates a new run from the beginning.

Terminal.

## 21. Job State Transition Authority

`BackgroundOperationManager` is authoritative over persisted job state transitions.

Operation implementations may request transitions or report progress, but cannot directly write arbitrary lifecycle states.

Representative valid transitions include:

```text
Queued -> Preparing
Queued -> Cancelled
Preparing -> Running
Preparing -> Failed
Preparing -> Cancelled
Preparing -> Interrupted
Preparing -> Abandoned
Running -> Completed
Running -> CompletedWithIssues
Running -> Failed
Running -> Cancelled
Running -> Interrupted
Running -> Abandoned
Interrupted -> terminal historical record; resume creates a new JobRun
```

A `Completed`, `CompletedWithIssues`, `Failed`, `Cancelled`, `Interrupted`, or `Abandoned` run never returns to active execution. `Interrupted` differs from the other terminal states only because it may be used as the recovery source for a new resumed `JobRun`.

Operation-specific contracts define the facts that justify `Completed`, `CompletedWithIssues`, or `Failed`. `Completed` is reserved for fully satisfied requested scope; `CompletedWithIssues` requires a safe durable terminal boundary plus meaningful successful work while some requested scope remains unsatisfied. `BackgroundOperationManager` remains authoritative for validating and persisting the generic lifecycle transition.

## 22. Retry and Resume

Retry and resume are distinct concepts.

### 22.1 Retry

Retry:

- creates a new `JobRunId`
- starts the operation from the beginning
- does not depend on prior execution progress
- may reference the previous run only for diagnostics or user history

### 22.2 Resume

Resume:

- creates a new `JobRunId`
- is valid only for operations that explicitly declare resumability
- may consume durable checkpoints from an interrupted run
- sets `resumed_from_job_run_id` to the prior run
- continues from the last declared recoverable checkpoint

### 22.3 No logical Job abstraction during MVP

A separate durable `JobId` or `LogicalJobId` grouping multiple `JobRun` attempts is deferred until a concrete product need exists.

For MVP, each execution attempt stands on its own and may link to the prior interrupted run when resuming.

## 23. Operation Policy Contract

Each operation declares the runtime-relevant policy required to execute it.

Conceptually:

```text
OperationPolicy
- execution_class
- required_resource_classes
- cancellation_policy
- shutdown_policy
- recovery_policy
- progress_policy
```

The exact Rust representation may use traits, associated constants, descriptors, or another typed mechanism.

The runtime owns policy enforcement. Operation implementations own policy declaration.

## 24. Runtime Policy vs. Operation Policy

The runtime owns:

- lifecycle
- admission
- dispatch
- operation context
- `TraceId`
- runtime replacement
- event sequence
- resource admission
- shutdown orchestration

An operation owns:

- business logic
- validation
- required resources
- checkpoint placement
- progress facts
- cancellation checkpoints
- resumability
- retry semantics
- shutdown behavior
- recovery behavior

This separation is normative.

Adding a new operation should normally require registering its handler and policy, not modifying runtime lifecycle rules.

## 25. Logical Resource Classes

Background-operation concurrency is controlled through logical resource classes.

Initial classes are:

```text
PersistenceRead
PersistenceWrite
FilesystemRead
FilesystemWrite
MetadataProviderNetwork
CpuIntensive
```

These names represent architectural resource intent rather than implementation mechanisms.

Resource-class capacity values are runtime policy and are not fixed by this specification.

An operation declares the classes it requires.

Examples:

```text
LibraryScan
- FilesystemRead
- PersistenceWrite
- CpuIntensive

MetadataRefresh
- MetadataProviderNetwork
- PersistenceWrite

DiagnosticExport
- FilesystemWrite
- CpuIntensive
```

Exact declarations are operation-specific and may differ from these examples.

`LibraryScan` shows the MVP local-filesystem resource case only. The source-provider contract defined by SPEC-BE-011 does not expose `FilesystemRead`; future non-filesystem source providers may require different runtime resource declarations without changing indexing or source-access contracts.

## 26. Resource Admission Semantics

`BackgroundOperationManager` uses declared logical resource classes to decide when an admitted background job may start execution.

Rules:

1. Resource capacity is bounded.
2. An operation cannot begin until all required operation-level resource capacity is available.
3. Resource admission prevents top-level oversubscription but does not replace subsystem scheduling.
4. Subsystem internal limits remain authoritative for subsystem work.
5. Resource capacity must not be encoded per operation type unless a later specification demonstrates a real need.
6. Implementation names such as thread pools, connection pools, or runtime tasks do not appear in resource declarations.
7. Resource acquisition and release are observable through SPEC-BE-003 timing and trace contracts where useful.

## 27. Scheduling Policy

The manager schedules only top-level background operations.

Required properties:

- bounded pending work
- deterministic admission decisions under the configured policy
- starvation prevention
- cancellation of queued jobs before execution
- safe resource release on terminal outcome
- no tool-specific or provider-specific scheduling branches

Exact fairness algorithm, queue ordering, and capacity numbers remain runtime policy and implementation-plan decisions.

MVP does not require user-visible priorities.

## 28. Progress Model

Background operations report structured progress facts.

Conceptually:

```text
JobProgress
- job_run_id
- state
- phase
- completed_units nullable
- total_units nullable
- status_key nullable
- updated_at
```

`phase` is a stable operation-defined identifier.

`status_key` is a stable presentation/localization key rather than arbitrary user-facing text.

Rules:

1. The backend does not publish a percentage field.
2. `completed_units` and `total_units` describe the current phase only.
3. `completed_units` must never exceed `total_units` when total is known.
4. Progress is monotonic within a phase unless that phase explicitly restarts and records a new phase occurrence through operation-specific semantics.
5. Indeterminate phases omit `total_units`.
6. Overall multi-phase percentage is not supported.
7. Weighted multi-phase progress is out of scope.
8. Progress facts that imply durability must not advance beyond committed authoritative work.

## 29. Flutter-Derived Percentage

Flutter may derive a phase-local percentage when:

- `completed_units` is present
- `total_units` is present
- `total_units > 0`
- `completed_units <= total_units`
- the current phase is determinate

Flutter must not infer overall job completion percentage by weighting or combining phases.

The backend remains authoritative for state, phase, and work-unit counts. Percentage is presentation data.

## 30. Cancellation Model

Cancellation is cooperative and operation-aware.

### 30.1 Pre-admission cancellation

If cancellation is already requested before admission, the operation is rejected without executing business logic.

### 30.2 Query cancellation

Queries may stop or discard work at safe subsystem boundaries.

No authoritative rollback is required because queries do not create authoritative side effects.

### 30.3 Immediate command cancellation

Immediate commands may acknowledge cancellation before durable commit.

If a Unit of Work is active, cancellation follows SPEC-BE-002 rollback requirements.

After durable commit, success remains authoritative even if cancellation arrives immediately afterward.

### 30.4 Background cancellation

Once background work has been admitted, cancellation is controlled through the job lifecycle, typically by a command such as:

```text
CancelJob(JobRunId)
```

Cancelling the original bridge request after the job is accepted does not implicitly cancel the background job.

The cancellation request is persisted where required so runtime recovery can distinguish user intent from an unexpected process interruption.

## 31. Operation Shutdown Policy

Each operation declares how it reacts when the runtime enters `ShuttingDown`.

Representative policies include:

- finish current immediate command
- cancel before execution
- reach the next safe checkpoint and stop
- finish the current provider request, then stop
- finish the current filesystem artifact, then stop

The runtime does not impose one operation-specific strategy on all work.

The runtime does own:

- closing admission immediately
- broadcasting shutdown intent
- tracking outstanding operations
- enforcing an overall bounded shutdown deadline
- coordinating subsystem shutdown order
- recording operations that did not finish cleanly

## 32. Shutdown Lifecycle

The runtime enters `ShuttingDown` only when the current runtime instance is being permanently retired.

Typical triggers include:

- application quit
- bridge host termination
- controlled restart
- cleanup of a `StartupFailed` instance
- fatal runtime condition where orderly cleanup remains possible
- deterministic test teardown

The following do not trigger runtime shutdown:

- navigating away from a Flutter screen
- cancelling one request
- cancelling one background job
- event-stream reconnect
- provider degradation
- minimizing or backgrounding the application window

Conceptual flow:

```text
shutdown requested
    ↓
state -> ShuttingDown
    ↓
reject new normal work
    ↓
notify admitted operations
    ↓
operations follow shutdown policy
    ↓
drain within runtime deadline
    ↓
close subsystems in dependency order
    ↓
state -> Stopped
```

## 33. Force-Quit Safety

Every operation must remain recoverable if the process terminates at any point, including during `ShuttingDown`.

Required invariant:

> Graceful shutdown improves efficiency and user experience but is never required for authoritative data integrity.

Operations must be safe under:

- user force quit
- process crash
- operating-system termination
- machine restart
- power loss
- debugger termination

## 34. Transaction and Checkpoint Safety

Authoritative persistence follows SPEC-BE-002 atomic transaction semantics.

Long-running operations use bounded coherent checkpoints rather than one transaction spanning the entire operation.

A checkpoint must be:

- internally consistent
- durably committed before being treated as authoritative progress
- safe to repeat or reconcile
- detectable after interruption
- independent of transient event delivery

An interrupted operation may lose its current uncommitted checkpoint but must preserve all earlier committed checkpoints.

Authoritative deletion or destructive finalization must occur only after the operation has sufficient proof that the relevant scope completed successfully.

## 35. External Artifact Publication

User-visible filesystem outputs use staged atomic publication.

Preferred workflow:

```text
create unique temporary artifact
    ↓
write content
    ↓
validate/finalize
    ↓
atomically publish final artifact where supported
```

Rules:

- incomplete temporary artifacts are never presented as completed output
- existing valid artifacts are not incrementally overwritten unless the operation-specific specification defines an equivalent crash-safe mechanism
- abandoned temporary artifacts are detectable and eligible for later cleanup
- final job completion occurs only after required external artifacts are durably published

Diagnostic ZIP export follows this model.

## 36. Cross-System Staged Workflows

Operations spanning persistence and filesystem state cannot assume a distributed transaction.

Such workflows must define explicit intermediate states and recovery behavior.

Representative states may include:

```text
Pending
Prepared
Published
Failed
```

The exact state machine belongs to the operation-specific specification.

At every durable intermediate point, startup recovery must be able to determine whether to:

- continue safely
- roll forward
- clean temporary state
- retry
- abandon
- require user intervention

A boolean `completed` flag is insufficient for multi-system crash recovery.

## 37. Startup Recovery of Background Work

On startup, persisted jobs left in active execution states from a previous runtime are reconciled.

The runtime must not assume that in-memory work survived.

Jobs found in `Queued`, `Preparing`, or `Running` from a prior runtime are reconciled according to the operation's recovery policy and durable execution state, including any accepted cancellation intent:

- `Interrupted` when a prior execution produced a valid durable checkpoint that permits future resume
- `Cancelled` when durable cancellation intent had already been accepted and the operation's recovery policy maps that intent to terminal cancellation
- `Abandoned` when the prior execution cannot resume safely and no accepted cancellation intent maps it to `Cancelled`, including queued work that never established resumable execution state

During MVP:

- significant user work is never resumed automatically
- the user must explicitly choose resume or retry
- resume and retry create new job runs
- stale temporary artifacts are handled according to operation-specific cleanup policy

## 38. Bridge Interaction Model

Bridge interaction uses a hybrid push/pull model.

### 38.1 Pull for authoritative state

Flutter uses focused queries for authoritative state, such as:

```text
GetJob(JobRunId)
ListJobs(...)
GetRuntimeHealth
GetAppearanceSettings
```

Query results remain the source of truth. `GetJob` and `ListJobs` preserve the exact generic `JobRun` lifecycle state, including `CompletedWithIssues`; operation-specific detail contracts explain the scope or issues behind that state without adding feature-specific fields to the generic runtime model.

### 38.2 Push for responsiveness

Rust publishes lightweight application events through one application-level event stream.

Representative events include:

```text
JobStateChanged
JobProgress
RuntimeStateChanged
HealthChanged
AppearanceSettingsChanged
```

Events allow Flutter to update promptly without polling continuously.

Events do not replace authoritative queries.

## 39. Progress Events

High-frequency progress events may carry the structured progress snapshot directly so Flutter does not re-query for every incremental update.

This payload remains ephemeral notification data.

If Flutter detects event loss, reconnect, or runtime replacement, it re-queries authoritative job state.

Rules:

- phase changes publish promptly
- terminal state changes publish promptly
- intermediate progress may be coalesced
- every internal progress increment does not need to cross the bridge

## 40. Event Envelope

Every application event crossing the runtime event stream contains lifecycle metadata conceptually equivalent to:

```text
ApplicationEvent
- runtime_instance_id
- sequence
- occurred_at
- payload
```

`runtime_instance_id` identifies the runtime generation.

`sequence` is strictly increasing within that runtime instance.

A new runtime instance starts a new event sequence.

## 41. Event Sequence Handling

Flutter tracks:

```text
(runtime_instance_id, last_sequence)
```

Rules:

### Normal event

If the runtime instance matches and:

```text
sequence == last_sequence + 1
```

Flutter processes the event normally.

### Sequence gap

If the next event skips one or more sequence numbers, Flutter treats events as lost and re-queries the smallest relevant authoritative state.

Flutter does not reconstruct missing events.

### Duplicate or stale event

If:

```text
sequence <= last_sequence
```

Flutter ignores the event.

### Runtime replacement

If `runtime_instance_id` changes, Flutter invalidates event-derived assumptions and performs a broader authoritative refresh appropriate to the active features.

## 42. Event Subscription Ownership

One application-level bridge event stream exists per runtime instance.

Flutter's app-level event coordinator owns that stream.

Feature controllers subscribe to the coordinator rather than directly to native bridge streams.

Consequences:

- navigation does not reconnect the Rust stream
- screen disposal does not affect backend subscriptions
- runtime replacement reconnects in one place
- sequence-gap recovery remains centralized

## 43. Event Backpressure

Application event delivery is bounded and best effort.

The runtime must not permit a slow Flutter subscriber to create unbounded memory growth or indefinitely block runtime operations.

Rules:

1. The bridge event queue is bounded.
2. Compatible state-update events may be coalesced by Argus identity.
3. High-frequency progress events are primary coalescing candidates.
4. Terminal state events are preferred over stale intermediate progress when relieving queue pressure.
5. If the queue is full and an event cannot be coalesced, the oldest queued event may be dropped so newer information can be retained.
6. Dropped events preserve a detectable sequence gap.
7. Event publication failure never rolls back committed state.
8. Publishers do not wait indefinitely for subscribers.

## 44. Event Correctness Boundary

Event delivery is outside the authoritative correctness boundary.

For example:

```text
database commit
    ↓
process termination
    ↓
event never reaches Flutter
```

The application remains correct because Flutter re-queries authoritative state on reconnect or sequence-gap recovery.

No subsystem may require a transient application event to reconstruct durable state after restart.

## 45. Runtime Errors and Admission Failures

Runtime admission and execution failures map through the published SPEC-BE-003 catalog. Expected caller-visible admission branches use this exact mapping:

| Condition | Error code |
|---|---|
| Normal operation targets `Uninitialized` or `Starting` | `ARGUS.V1.RUNTIME.NOT_READY` |
| Normal operation targets `StartupFailed` | `ARGUS.V1.RUNTIME.STARTUP_FAILED` |
| Operation targets `ShuttingDown` | `ARGUS.V1.RUNTIME.SHUTTING_DOWN` |
| Operation targets `Stopped` | `ARGUS.V1.RUNTIME.STOPPED` |
| Expected runtime generation is stale | `ARGUS.V1.RUNTIME.STALE_INSTANCE` |
| Cancellation is already requested before admission | `ARGUS.V1.OPERATION.CANCELLED` |
| Later-MVP background policy rejects instead of queues because capacity is unavailable | `ARGUS.V1.OPERATION.CAPACITY_UNAVAILABLE` |

Agents must not substitute a generic fallback or implementation-local code. A stale-generation caller refreshes authoritative runtime state and does not replay the action automatically.

Admission failures do not create partial operation state. Once background admission crosses the durable boundary in Section 16.1, the runtime either returns the accepted handle or leaves a deterministically reconcilable or terminalized `JobRun`; it does not report simple rejection while orphaning an active record.

## 46. Observability Integration

SPEC-BE-003 applies to every runtime operation.

Required behavior:

- one `TraceId` per top-level query, immediate command, background admission command, background execution, startup, and shutdown
- automatic retry inside one top-level execution retains its `TraceId`
- user retry or resume creates a new `TraceId`
- `JobRunId` is canonical for background execution observability after assignment
- queue wait and execution duration are measured separately where queues exist
- resource-class wait time may be reported as queue wait or a dedicated bounded field according to implementation
- runtime replacement receives a new `RuntimeInstanceId`

## 47. Persistence Integration

SPEC-BE-002 remains authoritative for persistence execution.

Runtime requirements include:

- immediate commands own Unit of Work lifecycle through application handlers
- background jobs use bounded Units of Work at coherent checkpoints
- transactions are never held while waiting for user input or long external I/O
- events publish only after commit
- cancellation before commit rolls back
- committed success is never converted into cancellation
- persisted job state uses the same database executor during MVP

## 48. Security and Privacy

Runtime execution must preserve SPEC-BE-003 redaction and identity-first observability rules.

Additional requirements:

- operation descriptors contain no secrets
- cancellation and recovery metadata contain only Argus IDs and safe structured context
- `status_key` is not arbitrary provider-returned text
- resource-class declarations contain no user data
- event payloads contain no credentials or authorization material
- temporary artifact names must not expose sensitive user data
- runtime instance identifiers are opaque and non-sensitive

## 49. Performance Requirements

The runtime must:

- avoid application-wide serialization of unrelated immediate commands and queries
- avoid routing lightweight queries through background scheduling
- avoid routing immediate commands through a generic command queue
- bound background pending work
- bound event queues
- coalesce high-frequency progress notifications
- expose queue wait separately from execution time
- prevent one operation class from causing unbounded starvation
- keep the Flutter-sensitive bridge path free from blocking subsystem work

Optimization must preserve operation semantics and technology-neutral contracts.

## 50. Testing Requirements

### 50.1 Runtime lifecycle tests

Test every valid and invalid lifecycle transition:

- `Uninitialized -> Starting`
- `Starting -> Ready`
- `Starting -> StartupFailed`
- `Ready -> ShuttingDown`
- `StartupFailed -> ShuttingDown`
- `ShuttingDown -> Stopped`
- rejection of restart on `StartupFailed`
- rejection of restart on `Stopped`

### 50.2 Admission tests

Test:

- normal query admission in `Ready`
- normal immediate command admission in `Ready`
- background-operation admission in `Ready`
- rejection during `Starting`
- rejection during `ShuttingDown`
- rejection after `Stopped`
- startup-safe exceptions
- pre-admission cancellation
- exactly one admission evaluation per operation

### 50.3 Operation classification tests

Test that:

- queries cannot declare authoritative side effects
- immediate commands cannot be promoted to background execution implicitly
- background operations always create independently managed execution
- no fourth runtime execution class exists through public APIs

### 50.4 Query tests

Test:

- query path bypasses background scheduling
- queries preserve operation context through subsystem calls
- query cancellation
- query errors map through `ApplicationError`
- queries do not create `JobRun` records

### 50.5 Immediate command tests

Test:

- direct handler execution
- Unit of Work commit
- rollback on cancellation before commit
- success preserved after commit despite late cancellation
- committed event publication ordering
- no general command queue involvement

### 50.6 Background manager tests

Test:

- `JobRun` creation and registration
- atomic/deterministic handoff between durable `JobRun` creation and manager responsibility
- no orphan nonterminal run after failed admission or injected crash
- resource-class waiting
- bounded pending work
- resource release
- safe cancellation while queued
- transition from queued to preparing/running
- terminal cleanup
- starvation prevention under the chosen scheduling policy

### 50.7 Job lifecycle tests

Test every allowed and forbidden state transition.

Test persistence and immutable history for:

- Completed
- CompletedWithIssues
- Failed
- Cancelled
- Interrupted
- Abandoned

Test the distinction among `Completed`, `CompletedWithIssues`, and `Failed` using operation-reported completion facts, including rejection of invalid clean-completion requests when requested scope is known to be unsatisfied.

### 50.8 Retry and resume tests

Test:

- retry creates a new `JobRunId`
- retry starts from the beginning
- resume creates a new `JobRunId`
- resume sets `resumed_from_job_run_id`
- resume is rejected for non-resumable operations
- old runs remain historical and unchanged

### 50.9 Progress tests

Test:

- indeterminate progress
- determinate phase progress
- completed units never exceed total
- phase-local monotonicity
- no backend percentage field
- no weighted overall progress
- durable progress does not exceed committed checkpoints

### 50.10 Cancellation tests

Test:

- cancellation before admission
- query cancellation
- immediate command rollback before commit
- cancellation after commit
- background cancellation request persistence
- cancellation at operation-defined checkpoints
- cancellation while waiting for resources

### 50.11 Shutdown tests

Test:

- admission closes immediately
- operations receive shutdown intent
- operation-specific shutdown policies
- overall runtime shutdown deadline
- dependency-ordered subsystem closure
- outstanding-operation reporting
- terminal `Stopped` state

### 50.12 Force-termination recovery tests

Use fault injection around durable boundaries to verify:

- no partial authoritative transactions
- committed checkpoints survive
- uncommitted checkpoint work is safely discarded
- jobs in active states reconcile to `Interrupted`, `Cancelled`, or `Abandoned` according to the operation recovery policy and durable evidence
- temporary artifacts are not mistaken for completed output
- events are not required for recovery

### 50.13 Event tests

Test:

- monotonically increasing sequence within one runtime
- sequence reset on runtime replacement
- `RuntimeInstanceId` change detection
- coalescing of compatible progress events
- bounded queue behavior
- oldest-drop overflow behavior
- terminal event preference
- sequence-gap recovery signal
- publication failure after commit does not change authoritative state

### 50.14 Technology-boundary tests

Architecture tests or compile-time boundaries must ensure public runtime/application contracts do not expose concrete async-runtime, database, HTTP-client, thread-pool, or archive implementation types.

## 51. Phase 000 Minimum Implementation

Phase 000 requires only the runtime behavior needed for startup, appearance settings, diagnostics, and the bridge foundation.

Implement:

- `ApplicationRuntime` lifecycle states
- `RuntimeInstanceId`
- centralized admission
- shared operation lifecycle
- query dispatch for appearance settings and runtime/status reads
- direct immediate command dispatch for appearance-setting updates
- runtime shutdown coordination
- new runtime construction after startup failure
- one application-level event stream with runtime-instance sequence metadata
- bounded/coalescible event delivery sufficient for `AppearanceSettingsChanged`
- cancellation primitives sufficient for bridge request disposal
- technology-neutral interfaces

Phase 000 does not need to expose user-visible persisted background jobs because PHASE-000 explicitly defers long-running job functionality.

However, the runtime structure implemented in Phase 000 must preserve the boundaries defined here so later `BackgroundOperationManager`, persisted `JobRun`, resource-class scheduling, progress, resume, and retry support can be added without replacing the query/command/runtime lifecycle contracts.

## 52. Acceptance Criteria

SPEC-BE-004 is satisfied when:

1. Runtime states are exactly `Uninitialized`, `Starting`, `Ready`, `StartupFailed`, `ShuttingDown`, and `Stopped`.
2. `StartupFailed` runtime instances are never reused for startup.
3. `Stopped` is terminal.
4. Every runtime instance has an opaque `RuntimeInstanceId`.
5. Every bridge-facing operation uses the shared runtime operation lifecycle.
6. Runtime admission is centralized and evaluated exactly once.
7. Operation classes are exactly Query, Immediate Command, and Background Operation.
8. Queries produce no authoritative side effects.
9. Immediate commands execute directly without a general runtime command queue.
10. Background operations have independently managed lifecycles.
11. `BackgroundOperationManager` owns background admission and lifecycle management.
12. Subsystems own their own execution policies.
13. Background concurrency uses logical resource classes.
14. Public runtime contracts expose no technology-stack implementation types.
15. `JobRunId` identifies exactly one execution attempt.
16. Retry creates a new `JobRunId` and starts from the beginning.
17. Resume creates a new `JobRunId` and may use durable checkpoints.
18. Resumability is declared by the operation.
19. Persisted job states include Queued, Preparing, Running, Completed, CompletedWithIssues, Failed, Cancelled, Interrupted, and Abandoned.
20. Completed, CompletedWithIssues, Failed, Cancelled, Interrupted, and Abandoned are terminal for their `JobRun`; `CompletedWithIssues` represents safely finalized meaningful work with incompletely satisfied requested scope, while Interrupted may be the source of a new resumed run.
21. Background progress is structured and phase-local.
22. The backend publishes no progress percentage field.
23. Weighted overall progress is unsupported.
24. Cancellation is cooperative and operation-aware.
25. Runtime shutdown closes new admission immediately.
26. Operations declare their own shutdown behavior.
27. Runtime enforces a bounded overall shutdown lifecycle.
28. Graceful shutdown is not required for data integrity.
29. Force termination cannot corrupt authoritative state.
30. Long-running work uses restart-safe checkpoints.
31. External artifacts are atomically published where supported.
32. Startup reconciles active jobs from a prior runtime to `Interrupted`, `Cancelled`, or `Abandoned` according to the operation recovery policy and durable evidence.
33. MVP does not automatically resume significant background work.
34. Bridge interaction uses push for responsiveness and pull for authoritative state.
35. Event sequences are monotonic within one runtime instance.
36. Runtime replacement begins a new event sequence.
37. Flutter can detect sequence gaps and runtime replacement.
38. The bridge event stream is bounded and best effort.
39. Compatible state-update events may be coalesced.
40. Event loss never compromises authoritative state correctness.
41. Runtime policy and operation policy remain separate.
42. Adding operation types does not require tool-specific branches in core runtime orchestration.
43. Runtime and recovery tests cover forced termination around durable boundaries.
44. Phase 000 can implement its minimal runtime slice without prematurely implementing persisted user-visible jobs.

## 53. Prohibited Patterns

- one global executor for all application and subsystem work
- application-wide command queue for immediate commands
- queries that produce authoritative side effects
- classifying operations by expected elapsed time
- using idempotency as the query/command distinction
- operation-type-specific scheduling branches in core runtime
- technology-specific resource classes
- exposing async-runtime, database, HTTP-client, or thread-pool types in public application contracts
- reusing a `StartupFailed` runtime instance
- restarting a `Stopped` runtime instance
- reusing one `JobRunId` across multiple execution attempts
- automatically resuming significant MVP jobs at startup
- collapsing safely finalized partly satisfied work into clean `Completed` when the operation-specific contract requires `CompletedWithIssues`
- overall weighted progress
- backend-published presentation percentage
- requiring graceful shutdown for consistency
- long-lived transactions spanning entire background jobs
- assuming event delivery for durable recovery
- unbounded bridge event queues
- blocking committed state changes on Flutter event consumption
- feature-level direct native event subscriptions

## 54. Out of Scope

This specification does not finalize:

- exact Rust trait signatures
- exact async runtime
- exact channel types
- exact shutdown timeout values
- exact background resource capacities
- user-visible priority controls
- pause/resume UI
- automatic background-job resume
- logical job grouping across attempts
- full execution-graph scheduler internals
- operation-specific checkpoint schemas
- provider-specific scheduling algorithms
- Flutter event coordinator implementation
- bridge DTO field serialization
- cross-process or distributed job execution
- remote workers

## 55. Phase 002 Android Foreground-Execution Amendment

Android foreground execution is a platform execution lease around the existing runtime, not a new runtime or scheduler. A qualifying user-admitted long-running operation may cause the Android host to start/maintain one foreground service while background execution eligibility is required.

Normative rules:

1. `ApplicationRuntime` and `BackgroundOperationManager` remain authoritative for admission, `JobRun` lifecycle, progress, cancellation, retry, shutdown, and recovery.
2. The foreground service must not initialize a second Rust runtime, open an independent SQLite application authority, create a parallel scheduler, or own an independent job state machine.
3. Activity detach/recreation/backgrounding does not imply `generalShutdown` while the process/runtime remains alive.
4. Native notification cancellation, when exposed, routes into the same authoritative `CancelJob` path used by Flutter Jobs.
5. The service stops when no qualifying active job requires the execution lease.
6. Notification permission affects native presentation only; it does not change `JobRun` state or admission authority.
7. A live Android foreground-service timeout is handled while the process/runtime is still present: the host requests orderly termination through the existing operation path, and the operation records the truthful ordinary terminal result supported by work already committed (`CompletedWithIssues`, `Failed`, or `Cancelled` when accepted cancellation determines termination). A timeout callback does not by itself relabel the live `JobRun` as recovery-only `Abandoned`.
8. Forced process loss or equivalent disappearance of the runtime is reconciled only on a later startup from durable state. The current non-resumable `LibraryScan` then maps stale nonterminal execution to `Cancelled` when accepted durable cancellation intent requires it, otherwise to `Abandoned`; it never uses `Interrupted`.
9. No significant job automatically resumes during MVP. A future operation may use `Interrupted`/resume only when its owning operation contract defines valid durable checkpoint semantics.

Phase 002 tests must prove Activity lifecycle does not duplicate the runtime, Flutter/native cancellation converges on one job, the service tears down after the last qualifying job, and process loss/relaunch preserves existing no-auto-resume recovery.

## 56. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [Backend Specifications Index](README.md)
