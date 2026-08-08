# Startup Coordination and Recovery Contract Specification

**Document ID:** SPEC-BE-007  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-07  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-006  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative backend contract for Argus startup orchestration, readiness certification, startup failure reporting, partial-startup cleanup, recovery action discovery, recovery execution, and runtime replacement.

It separates four responsibilities deliberately:

```text
ApplicationHost
├── ApplicationRuntime
├── StartupCoordinator
└── RecoveryCoordinator
```

- `ApplicationHost` owns runtime generations and replacement.
- `ApplicationRuntime` owns lifecycle state, admission, execution, and shutdown.
- `StartupCoordinator` owns ordered mandatory initialization.
- `RecoveryCoordinator` owns explicit recovery actions and fresh-runtime restart.

The design prevents startup logic from becoming embedded in `ApplicationRuntime`, prevents recovery from reusing a failed runtime, and makes readiness a positively verified architectural state rather than merely the absence of an exception.

## 2. Scope

This specification covers:

- `ApplicationHost` ownership of runtime generations
- `StartupCoordinator` responsibilities
- fixed sequential startup phases
- responsibility-oriented phase identities
- startup phase criticality
- startup phase outcomes and failure context
- typed `RecoveryAction` contracts
- active readiness validation
- LIFO partial-startup cleanup
- startup observability and timing
- `StartupFailed` inspection surface
- `RecoveryCoordinator` execution model
- retry through runtime replacement
- targeted `ResetAppearanceSettings` recovery
- diagnostic export and technical-detail recovery actions
- shutdown and cleanup interaction
- architecture and test requirements

## 3. Non-Responsibilities

This specification does not define:

- Flutter startup or recovery widgets
- exact bridge DTO serialization
- SQLite migration internals
- application error catalog mechanics already owned by SPEC-BE-003
- normal command/query/background execution owned by SPEC-BE-004
- appearance settings domain semantics owned by SPEC-BE-005
- event bus implementation owned by SPEC-BE-006
- destructive database repair or reset workflows
- backup/restore
- provider-specific recovery
- cloud recovery
- automatic data repair
- automatic retry loops across runtime generations
- exact startup timeout durations
- exact Rust trait syntax

## 4. Architectural Principles

1. `ApplicationRuntime` owns lifecycle state but not subsystem-specific startup sequencing.
2. `StartupCoordinator` is the single authoritative orchestrator of startup phases.
3. Startup is an explicit fixed sequential pipeline.
4. Startup phase identities describe architectural responsibilities, not implementation technologies.
5. Every startup phase has explicit criticality.
6. Phase 000 startup phases are all mandatory.
7. Startup stops at the first mandatory failure.
8. Successful phases register bounded cleanup where they acquire owned resources.
9. Cleanup executes in reverse successful-initialization order.
10. Cleanup is distinct from recovery.
11. `Ready` is a positive architectural certification.
12. A runtime reaches `Ready` only after active readiness validation succeeds.
13. A `StartupFailed` runtime is never restarted or repaired in place.
14. Recovery actions are typed declarative capabilities, not free-form instructions.
15. Recovery actions are never executed automatically.
16. Recovery execution is owned by `RecoveryCoordinator`.
17. Any new startup attempt creates a fresh `ApplicationRuntime` generation.
18. Runtime replacement is owned above any individual runtime generation by `ApplicationHost`.
19. Startup and recovery contracts remain technology-neutral.
20. Existing data is never silently deleted, reset, or repaired.

## 5. Ownership Model

### 5.1 `ApplicationHost`

`ApplicationHost` owns the current runtime generation and the transition between runtime generations.

Conceptually:

```text
ApplicationHost
- current_runtime
- runtime_factory
- startup_coordinator_factory
- recovery_coordinator
```

Exact composition is an implementation detail, but the ownership semantics are fixed.

`ApplicationHost` owns:

- construction of a new `ApplicationRuntime`
- assignment of a new `RuntimeInstanceId`
- replacement of a failed/stopped runtime
- coordination between failed-runtime retirement and fresh startup
- ensuring stale runtime handles are not reused

`ApplicationHost` does not execute application commands, persistence transactions, or feature business logic.

### 5.2 `ApplicationRuntime`

`ApplicationRuntime` owns the lifecycle defined by SPEC-BE-004:

```text
Uninitialized
Starting
Ready
StartupFailed
ShuttingDown
Stopped
```

It owns:

- lifecycle state
- `RuntimeInstanceId`
- startup `TraceId` creation through SPEC-BE-003
- centralized operation admission
- normal runtime execution after readiness
- shutdown orchestration
- accepting the terminal result from `StartupCoordinator`

It does not own phase-specific startup implementation details.

### 5.3 `StartupCoordinator`

`StartupCoordinator` owns:

- startup phase ordering
- phase execution
- phase criticality policy
- startup phase status
- phase timing
- startup failure attribution
- cleanup registration
- reverse-order cleanup
- readiness validation orchestration
- terminal `StartupResult`

Individual subsystems expose initialization capabilities but never orchestrate global application startup.

### 5.4 `RecoveryCoordinator`

`RecoveryCoordinator` owns:

- validation that a requested recovery action was offered for the current failure
- execution of explicitly selected recovery operations
- use of narrowly scoped recovery infrastructure
- retirement of the failed runtime where required
- requesting a fresh runtime generation through `ApplicationHost`
- fresh startup after recovery or retry

It does not use the failed runtime's normal command/query pipeline for authoritative mutation.

## 6. Startup Lifecycle

The runtime transition remains:

```text
Uninitialized -> Starting
Starting -> Ready
Starting -> StartupFailed
```

`StartupCoordinator` runs only while the owning runtime is in `Starting`.

A runtime cannot transition:

```text
StartupFailed -> Starting
Stopped -> Starting
```

A retry creates a different runtime generation.

## 7. Startup Phase Model

Startup uses a fixed sequential phase pipeline.

Properties:

- explicit ordering
- no runtime-generated dependency graph
- no implicit subsystem self-ordering
- no parallel startup execution during Phase 000
- deterministic phase transitions

A phase is the smallest architecturally observable unit of initialization.

A phase may contain multiple implementation steps internally, but diagnostics, timing, failure attribution, and cleanup ownership operate at the architectural phase boundary.

## 8. Startup Phase Identity

Phase identities describe responsibilities rather than technologies.

Preferred:

```text
PersistenceInitialization
```

Prohibited as architectural phase identities:

```text
OpenSQLite
CreateTokioRuntime
InitializeRusqlite
```

Changing an underlying implementation technology must not require renaming an architectural phase unless its responsibility changes.

## 9. Phase 000 Startup Pipeline

The normative Phase 000 pipeline is:

```text
1. EnvironmentInitialization
        ↓
2. ObservabilityInitialization
        ↓
3. ConfigurationInitialization
        ↓
4. PersistenceInitialization
        ↓
5. SettingsInitialization
        ↓
6. CoreServicesInitialization
        ↓
7. EventInfrastructureInitialization
        ↓
8. ReadinessValidation
        ↓
Ready
```

All eight Phase 000 phases are mandatory.

## 10. `EnvironmentInitialization`

Responsible for establishing required process-local runtime environment prerequisites, including:

- resolving logical Argus data/cache/temp locations
- validating required filesystem accessibility
- constructing sanitized path abstractions needed by later phases
- establishing platform/runtime information needed by startup

It must not initialize persistence, settings, or feature services.

## 11. `ObservabilityInitialization`

Responsible for establishing the observability capability required by later startup phases, including:

- structured logging sinks
- startup trace/event capability
- diagnostic contributor foundation required during startup
- bounded local startup diagnostics

Startup itself already owns a `TraceId`; early bootstrap diagnostics that occur before full sinks are available must be safely buffered or emitted through a minimal bootstrap path and joined to the same startup operation where practical.

Observability initialization failure is mandatory during Phase 000 because subsequent startup failures must remain diagnosable.

## 12. `ConfigurationInitialization`

Responsible for:

- loading application configuration needed for startup
- validating configuration
- materializing typed configuration services
- rejecting invalid mandatory configuration before persistence-dependent application services are constructed

Configuration contracts must not expose implementation-specific storage details.

## 13. `PersistenceInitialization`

Responsible for establishing the persistence capability defined by SPEC-BE-002, including:

- opening the configured application persistence store
- verifying compatibility
- executing required migrations
- constructing persistence executor infrastructure
- constructing repository/query adapter factories
- constructing Unit of Work infrastructure

The phase identity remains `PersistenceInitialization` regardless of the current SQLite implementation.

A migration or schema failure maps through the relevant SPEC-BE-003 persistence error contract.

## 14. `SettingsInitialization`

Responsible for startup requirements owned by SPEC-BE-005, including:

- ensuring required materialized settings records exist after migration
- loading required appearance settings
- validating persisted settings integrity
- constructing the settings application capability needed by the ready runtime

Invalid or missing required appearance settings prevent readiness.

The phase does not silently synthesize or repair invalid persisted settings.

## 15. `CoreServicesInitialization`

Responsible for constructing the mandatory application service graph required by the current phase.

For Phase 000 this includes only the core services required for startup, settings, diagnostics, and bridge operation.

Future phases may add additional mandatory or optional service initialization through explicit specification updates.

This phase must not start hidden business workflows.

## 16. `EventInfrastructureInitialization`

Responsible for:

- constructing the application event bus defined by SPEC-BE-006
- registering required concrete event consumers
- registering the bridge-facing event publication adapter
- completing required event-routing composition

Required registration must complete before readiness.

Event infrastructure initialization must not publish fabricated application events merely to prove wiring.

## 17. `ReadinessValidation`

`ReadinessValidation` performs active verification of the fully assembled runtime composition.

It verifies at least:

- all mandatory phases completed successfully
- all required service capabilities are present
- required runtime entry points exist
- mandatory event registrations are complete
- required persistence/settings capabilities are available
- runtime composition is internally consistent
- the runtime can safely admit normal operations after transition

It performs no application-domain mutation.

It does not repair composition defects.

A runtime is not `Ready` because prior phases happened not to fail; it is `Ready` only because `ReadinessValidation` positively certifies the composition.

## 18. Phase Criticality

Every startup phase has an explicit criticality:

```text
Mandatory
Optional
```

Criticality is owned by startup-pipeline policy, not by the subsystem implementation.

### Mandatory failure

- stop startup
- create `StartupPhaseFailure`
- execute bounded cleanup
- return terminal failure
- runtime transitions to `StartupFailed`

### Optional failure

- record the failure
- mark the capability unavailable/degraded where applicable
- continue startup
- preserve the failure in startup diagnostics

Phase 000 defines all current phases as `Mandatory`.

## 19. Startup Phase Outcome

Conceptually:

```text
StartupPhaseOutcome
├── Success
└── Failure
    └── StartupPhaseFailure
```

A phase returns `Success` only after all responsibilities assigned to that phase have completed and required cleanup ownership has been registered.

## 20. `StartupPhaseFailure`

Conceptually:

```text
StartupPhaseFailure
- phase: StartupPhase
- error: ApplicationError
- recovery_context: RecoveryContext
```

`ApplicationError` answers what failed.

`StartupPhaseFailure` answers where startup became terminal and what typed recovery capabilities apply.

`StartupPhaseFailure` must not contain:

- raw exception strings as UI contracts
- SQL
- unsanitized paths
- arbitrary maps used as recovery logic
- presentation text

## 21. `RecoveryContext`

`RecoveryContext` contains bounded typed recovery capability metadata.

Conceptually:

```text
RecoveryContext
- available_actions: [RecoveryAction]
```

Additional bounded typed constraints may be added where required, but free-form diagnostic maps are not a recovery contract.

Recovery context augments rather than replaces `ApplicationError.safe_context`.

## 22. `RecoveryAction`

Phase 000 must support typed actions sufficient for:

```text
RetryStartup
ResetAppearanceSettings
ExportDiagnostics
CopyTechnicalDetails
OpenDataDirectory
Exit
```

Not every action is valid for every failure.

Recovery actions are declarative capabilities. Their presence means the application may offer the action; it does not mean the backend executes it automatically.

Actions contain no localized text.

## 23. Recovery Action Eligibility

Recovery action availability is determined from:

- startup phase
- published error contract
- proven scope of failure
- available safe recovery capability

Examples:

### `RetryStartup`

May be offered when a fresh startup attempt could plausibly succeed without automatic mutation, including transient database locking or corrected external conditions.

### `ResetAppearanceSettings`

May be offered only when failure is proven to be isolated to `AppearanceSettings`, as required by SPEC-BE-005.

### `ExportDiagnostics`

May be offered when diagnostic infrastructure is sufficiently available to produce a sanitized bundle.

### `OpenDataDirectory`

May be offered only when the platform supports it and the logical application data location is known safely.

### `Exit`

May always be offered when the host can terminate cleanly.

## 24. No Automatic Recovery

The startup coordinator never automatically:

- retries startup
- resets settings
- recreates databases
- deletes files
- rewrites configuration
- changes permissions
- repairs migrations

Recovery requires explicit external selection of a typed recovery action.

## 25. Partial-Startup Cleanup

Every successful phase that acquires resources requiring explicit retirement registers bounded cleanup before reporting success.

If a later mandatory phase fails, cleanup executes in reverse successful-phase order.

Example:

```text
EnvironmentInitialization          ✓
ObservabilityInitialization        ✓
ConfigurationInitialization        ✓
PersistenceInitialization          ✓
SettingsInitialization             ✓
CoreServicesInitialization         ✗
```

Cleanup order:

```text
SettingsInitialization cleanup
PersistenceInitialization cleanup
ConfigurationInitialization cleanup
ObservabilityInitialization cleanup
EnvironmentInitialization cleanup
```

Phases whose resources are pure values requiring no explicit cleanup may register no-op cleanup or rely on normal ownership drop semantics.

The architectural cleanup ordering remains LIFO regardless of exact Rust ownership mechanics.

## 26. Cleanup Failure Policy

Cleanup is best effort and bounded.

Rules:

1. The original startup failure remains the primary failure.
2. Cleanup failures never replace the original `StartupPhaseFailure`.
3. Cleanup failures are logged as secondary failures under SPEC-BE-003.
4. Cleanup continues to earlier successful phases when safe after one cleanup action fails.
5. Cleanup must not wait indefinitely.
6. Cleanup must not perform destructive repair.
7. The runtime still transitions to `StartupFailed` after cleanup attempt completion.

## 27. Cleanup vs Recovery

Cleanup and recovery are different architectural concerns.

**Cleanup**:

- happens automatically after mandatory startup failure
- retires partially initialized resources
- does not change user/domain data as repair
- is internal lifecycle hygiene

**Recovery**:

- happens only after explicit action selection
- may perform a narrowly scoped authoritative mutation when allowed
- is coordinated by `RecoveryCoordinator`
- may lead to a fresh startup generation

## 28. Startup Result

Conceptually:

```text
StartupResult
├── Success
│   └── readiness certification
└── Failure
    └── StartupPhaseFailure
```

`ApplicationRuntime` consumes this terminal result.

On success:

```text
Starting -> Ready
```

On failure:

```text
Starting -> StartupFailed
```

The coordinator itself does not directly mutate runtime lifecycle state outside the runtime-owned transition API.

## 29. `StartupFailed` Runtime Contract

A `StartupFailed` runtime is inspectable but never recoverable in place.

Permitted bounded capabilities may include:

```text
GetStartupFailure
GetRecoveryActions
ExportDiagnostics
CopyTechnicalDetails
GetRuntimeStatus
Shutdown
```

These capabilities must be startup-safe and must not expose the normal application service graph.

A failed runtime must not admit:

- normal feature queries
- normal immediate commands
- background operations
- in-place startup retry
- settings mutation through normal command dispatch

## 30. Recovery Execution Boundary

Recovery actions are executed through `RecoveryCoordinator`, not through ordinary failed-runtime admission.

The coordinator receives only explicitly scoped recovery capabilities required by each action.

It must not depend on the entire partially initialized service graph.

For example, targeted appearance reset may receive a narrowly scoped persistence recovery capability capable of opening a bounded transaction against the existing database without pretending the failed runtime is `Ready`.

## 31. `RetryStartup`

`RetryStartup` means:

```text
retire Runtime A
    ↓
Runtime A -> ShuttingDown -> Stopped
    ↓
ApplicationHost constructs Runtime B
    ↓
Runtime B -> Uninitialized -> Starting
```

It never means:

```text
Runtime A.start_again()
```

The fresh runtime receives:

- new `RuntimeInstanceId`
- new startup `TraceId`
- new `StartupCoordinator`
- new service graph
- new event graph
- new cancellation roots

## 32. `ResetAppearanceSettings`

The targeted recovery behavior from SPEC-BE-005 is incorporated as follows:

```text
Runtime A = StartupFailed
    ↓
user selects ResetAppearanceSettings
    ↓
RecoveryCoordinator validates action eligibility
    ↓
open narrowly scoped recovery Unit of Work
    ↓
replace only AppearanceSettings with canonical System default
    ↓
commit
    ↓
retire Runtime A
    ↓
construct Runtime B
    ↓
normal startup validation
```

Rules:

1. Action is available only for proven isolated appearance-settings failure.
2. Recovery modifies only `AppearanceSettings`.
3. Database is never deleted or recreated.
4. Recovery is atomic.
5. Recovery failure preserves unrelated data.
6. Recovery failure remains in the recovery experience; the failed runtime is not promoted to `Ready`.
7. Successful recovery is followed by a completely fresh startup.

## 33. Non-Mutating Recovery Actions

Actions such as:

- `ExportDiagnostics`
- `CopyTechnicalDetails`
- `OpenDataDirectory`

may execute while the failed runtime remains inspectable, provided the required capability was successfully initialized and can operate safely.

They do not change runtime readiness and do not convert `StartupFailed` to another operational state.

## 34. `Exit`

`Exit` requests normal host/runtime retirement.

The failed runtime transitions through:

```text
StartupFailed -> ShuttingDown -> Stopped
```

Shutdown cleanup follows SPEC-BE-004.

## 35. Recovery Action Freshness

Recovery actions belong to one specific startup failure and runtime generation.

A recovery request must identify or otherwise bind to the current failed runtime generation.

After runtime replacement:

- previously offered actions become stale
- stale actions must not execute against the new runtime
- the new startup result defines a new recovery surface if it fails

Exact bridge identifiers for this binding are defined by SPEC-BE-008.

## 36. Startup Observability

Startup is one top-level operation under SPEC-BE-003.

Required phase-level observability should include stable events such as:

```text
runtime.startup.phase.started
runtime.startup.phase.completed
runtime.startup.phase.failed
runtime.startup.cleanup.started
runtime.startup.cleanup.completed
runtime.startup.cleanup.failed
runtime.readiness.validated
runtime.startup.failed
```

Structured fields include where applicable:

- `startup_phase`
- `phase_criticality`
- `duration_ms`
- `outcome`
- published `error_code`
- bounded recovery action identifiers

Startup logs must not serialize arbitrary `RecoveryContext` payloads.

## 37. Startup Trace Identity

One startup attempt uses one startup `TraceId`.

All startup phase logs, trace events, timing observations, cleanup diagnostics, and terminal startup `ApplicationError` use that same trace.

A fresh runtime startup attempt receives a new `TraceId`.

A targeted recovery action is a separate top-level operation and receives its own `TraceId`.

The subsequent fresh startup receives another new startup `TraceId`.

## 38. Startup Failure Classification

Phase 000 must preserve at least the phase-level failure categories needed to support the existing phase contract, including conditions corresponding to:

```text
BridgeInitialization
DatabaseOpen
DatabaseLocked
MigrationFailed
IncompatibleSchema
ConfigurationInvalid
AppearanceSettingsInvalid
Permissions
CoreServiceInitialization
Unknown
```

These are presentation/bridge classifications derived from the richer backend contracts and do not replace `ApplicationError.code` or `StartupPhase`.

SPEC-BE-008 defines the exact bridge representation.

## 39. Error Contract Integration

SPEC-BE-003 remains authoritative for `ApplicationError`.

Startup-specific metadata must not fork a parallel error taxonomy.

Examples:

- database locked -> persistence error code + `PersistenceInitialization` phase
- invalid required appearance settings -> configuration error code + `SettingsInitialization` phase
- event graph construction defect -> runtime/internal error code + `EventInfrastructureInitialization` phase

This preserves both stable error semantics and precise startup location.

## 40. Startup Cancellation and Host Shutdown

A host shutdown request during `Starting` causes startup cancellation at safe phase boundaries.

Rules:

- startup must not begin new phases after shutdown intent is accepted
- the active phase cooperates with cancellation where safe
- successfully initialized resources are cleaned up in reverse order
- runtime proceeds toward `ShuttingDown`/`Stopped`, not `StartupFailed`, when user/host shutdown is the primary cause
- authoritative persistence transactions obey SPEC-BE-002 rollback/commit guarantees

Exact shutdown deadlines remain runtime policy.

## 41. Readiness and Admission

Normal runtime admission remains closed throughout `Starting`.

Only after successful `ReadinessValidation` and runtime transition to `Ready` may normal:

- queries
- immediate commands
- background admission

be accepted.

No bridge or internal caller may bypass this boundary because a particular subsystem initialized early.

## 42. Technology-Neutral Contracts

Startup/recovery application contracts must not expose:

```text
SqliteStartupPhase
RusqliteRecovery
TokioStartupTask
FlutterRustBridgeStartup
MpscRecoveryChannel
```

Preferred public concepts include:

```text
StartupCoordinator
StartupPhase
StartupPhaseOutcome
StartupPhaseFailure
RecoveryContext
RecoveryAction
RecoveryCoordinator
ApplicationHost
```

Concrete async primitives, channel types, database handles, and platform process APIs remain implementation details.

## 43. Crate Ownership

Ownership follows SPEC-BE-001.

### `argus-application`

May own stable startup/recovery application contracts that must be consumed across runtime/bridge boundaries, including typed phase identifiers, recovery action identifiers, and narrow recovery ports.

### `argus-runtime`

Owns:

- `ApplicationRuntime` integration
- `StartupCoordinator`
- phase execution orchestration
- startup cleanup orchestration
- readiness validation orchestration
- `RecoveryCoordinator`
- runtime replacement coordination interfaces used by `ApplicationHost`

### `argus-infrastructure`

Owns concrete initialization/recovery adapters for:

- persistence
- filesystem/environment
- observability sinks
- diagnostics archive output
- platform data-directory operations

### `argus-bridge`

Maps stable startup/recovery contracts into bridge DTOs under SPEC-BE-008.

It does not own startup sequencing or recovery eligibility logic.

## 44. Dependency Rules

Forbidden dependencies include:

- domain -> `StartupCoordinator`
- domain -> `RecoveryCoordinator`
- persistence adapter -> global startup orchestration
- settings handler -> runtime replacement
- failed runtime normal command dispatcher -> recovery mutation
- Flutter/bridge code -> direct infrastructure recovery adapters

`ApplicationHost` may depend on runtime construction abstractions but must not absorb feature business logic.

## 45. Testing Requirements

### 45.1 Phase sequencing tests

Verify:

- phases execute in exact declared order
- no later phase begins before the prior phase succeeds
- first mandatory failure stops later phases
- phase identities are responsibility-oriented

### 45.2 Criticality tests

Verify:

- mandatory failure terminates startup
- optional failure continues startup when introduced
- criticality belongs to pipeline policy
- all Phase 000 phases are mandatory

### 45.3 Cleanup tests

Verify:

- successful resource-owning phases register cleanup
- cleanup executes LIFO
- failed phase is not treated as successfully initialized
- cleanup failure does not replace primary startup failure
- remaining cleanup continues where safe
- cleanup is bounded

### 45.4 Readiness tests

Verify:

- all prior phase success does not itself transition runtime to `Ready`
- active `ReadinessValidation` is required
- missing required service fails readiness
- missing required event registration fails readiness
- readiness validation performs no authoritative mutation

### 45.5 Startup result tests

Verify:

- success -> `Starting -> Ready`
- mandatory failure -> `Starting -> StartupFailed`
- `StartupPhaseFailure` preserves phase + `ApplicationError`
- recovery context is typed and bounded

### 45.6 Failed runtime tests

Verify:

- normal queries are rejected
- normal commands are rejected
- background admission is rejected
- failure inspection works
- startup retry cannot occur in place
- `StartupFailed` can transition only toward retirement under SPEC-BE-004

### 45.7 Runtime replacement tests

Verify:

- retry retires old runtime
- replacement runtime has new `RuntimeInstanceId`
- replacement runtime has new startup `TraceId`
- event graph and service graph are newly composed
- stale handles/actions cannot operate on replacement runtime

### 45.8 Recovery tests

Verify:

- only offered typed actions may execute
- recovery actions are never automatic
- `ResetAppearanceSettings` is available only for isolated settings failure
- targeted reset changes only appearance settings
- successful targeted recovery creates a fresh runtime
- failed targeted recovery preserves unrelated data

### 45.9 Diagnostic recovery tests

Verify:

- copy details uses sanitized structured startup information
- diagnostic export remains available when required contributors initialized successfully
- unavailable diagnostic capability is not falsely offered
- startup failure details never expose secrets or raw paths

### 45.10 Observability tests

Verify:

- one startup `TraceId` per startup attempt
- phase timing/events use startup trace
- recovery operation receives a distinct trace
- fresh startup receives another distinct trace
- cleanup failures are secondary diagnostics
- one primary startup failure log is produced

### 45.11 Cancellation/shutdown tests

Verify:

- shutdown during startup stops admission of later phases
- active phase cancellation obeys safe boundaries
- cleanup runs for previously successful phases
- user shutdown does not incorrectly become `StartupFailed`

### 45.12 Architecture tests

Verify:

- `ApplicationRuntime` does not contain subsystem-specific startup sequencing
- subsystems do not orchestrate global startup
- recovery mutation cannot use failed runtime's normal command dispatcher
- application contracts contain no concrete database/async/bridge technology types

## 46. Phase 000 Minimum Implementation

Phase 000 implements:

- `ApplicationHost` runtime-generation ownership
- `StartupCoordinator`
- fixed eight-phase startup pipeline
- all Phase 000 phases as mandatory
- phase timing and outcome observability
- `StartupPhaseOutcome`
- `StartupPhaseFailure`
- typed `RecoveryContext`
- typed `RecoveryAction`
- LIFO cleanup
- active readiness validation
- `StartupFailed` bounded inspection surface
- `RecoveryCoordinator`
- fresh-runtime `RetryStartup`
- targeted `ResetAppearanceSettings`
- non-mutating diagnostics/detail recovery actions
- architecture and lifecycle tests required by this specification

Phase 000 does not implement destructive database reset, automatic repair, provider-specific recovery, backup/restore, or cross-runtime automatic retry loops.

## 47. Acceptance Criteria

SPEC-BE-007 is satisfied when:

1. `ApplicationHost` owns runtime generation construction/replacement.
2. `ApplicationRuntime` owns lifecycle but not subsystem-specific startup sequencing.
3. `StartupCoordinator` is the sole global startup orchestrator.
4. Startup uses a fixed sequential phase pipeline.
5. Startup phase identities are responsibility-oriented.
6. Phase 000 phases are exactly the eight defined by this specification unless explicitly revised.
7. All Phase 000 phases are mandatory.
8. Every phase returns a typed outcome.
9. Startup failure preserves both phase identity and stable `ApplicationError`.
10. Recovery context is typed rather than free-form.
11. Recovery actions are declarative and never automatic.
12. Successful resource-owning phases register cleanup.
13. Cleanup executes in reverse successful-initialization order.
14. Cleanup failure cannot replace the original startup failure.
15. `ReadinessValidation` actively certifies the assembled runtime.
16. Runtime cannot transition to `Ready` without readiness certification.
17. Normal admission remains closed throughout `Starting`.
18. `StartupFailed` runtime is never restarted or repaired in place.
19. Failed runtime exposes only bounded startup-safe inspection/recovery capabilities.
20. Recovery mutation does not execute through failed runtime normal command dispatch.
21. `RecoveryCoordinator` owns explicit recovery execution.
22. `RetryStartup` retires the failed runtime and constructs a new generation.
23. Every replacement runtime receives a new `RuntimeInstanceId`.
24. Every replacement startup receives a new startup `TraceId`.
25. `ResetAppearanceSettings` is offered only for proven isolated settings failure.
26. Targeted settings reset does not modify unrelated data.
27. Successful targeted recovery is followed by normal startup on a fresh runtime.
28. Stale recovery actions cannot execute against a replacement runtime.
29. Startup cleanup and recovery are distinct concepts.
30. Startup/recovery contracts expose no concrete persistence, async-runtime, or bridge technology.
31. Startup, cleanup, readiness, replacement, recovery, observability, and architecture tests cover the specified behavior.

## 48. Prohibited Patterns

- subsystem-specific startup logic embedded directly throughout `ApplicationRuntime`
- dynamic startup DAG during Phase 000
- parallel startup phases without a later specification
- technology-named architectural startup phases
- subsystems deciding their own global startup criticality
- transitioning to `Ready` merely because no prior phase failed
- silent missing-settings defaulting during startup
- automatic recovery action execution
- automatic settings reset
- automatic database deletion or recreation
- `StartupFailed -> Starting` on the same runtime instance
- recovery through failed runtime normal command dispatch
- reusing stale runtime/event/service handles after replacement
- cleanup errors masking the original startup failure
- free-form recovery instruction strings as application contracts
- arbitrary recovery metadata maps used for control flow
- raw infrastructure errors crossing startup/bridge boundaries
- startup phase contracts exposing SQLite/Tokio/flutter_rust_bridge types

## 49. Out of Scope

This specification does not finalize:

- exact Rust trait definitions
- exact struct/module file layout
- exact startup timeout values
- exact cleanup timeout values
- bridge DTO field names
- frontend action presentation
- destructive persistence recovery
- backup/restore
- provider-specific startup phases
- plugin startup discovery
- cloud services
- production crash recovery beyond existing persistence/runtime guarantees

## 50. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-006 — Minimal Domain Event Bus](spec-be-006-minimal-domain-event-bus.md)
- [Backend Specifications Index](README.md)
