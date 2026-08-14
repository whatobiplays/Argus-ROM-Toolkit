# Rust-to-Flutter Bridge DTO Contract Specification

**Document ID:** SPEC-BE-008  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-14  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-001, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-006, SPEC-BE-007, SPEC-BE-009, SPEC-BE-011, SPEC-BE-013, SPEC-X-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative Rust-to-Flutter bridge contract for Argus ROM Toolkit.

It defines the stable application-facing operations, immutable Data Transfer Objects (DTOs), result envelope, runtime event stream, error projection, startup/recovery projection, appearance-settings projection, background-operation handles, compatibility rules, and bridge ownership boundaries used between the Rust backend and Flutter frontend.

The bridge is a translation boundary. It exposes application capabilities and immutable application snapshots while hiding backend execution strategy, domain ownership, persistence, runtime implementation, and `flutter_rust_bridge` generated details.

## 2. Scope

This specification covers:

- service-oriented bridge organization
- application-intent bridge operations
- `BridgeResult<T>`
- `ApplicationErrorDto`
- canonical concept-owned DTOs
- immutable snapshot semantics
- semantically append-only DTO evolution
- stable identity projection
- `RuntimeStateDto`
- `StartupFailureDto`
- `RecoveryActionDto`
- `AppearanceSettingsDto`
- appearance-settings request DTOs
- minimal `OperationHandleDto`
- one unified runtime event stream
- runtime event envelope and sequencing metadata
- runtime, operation, and domain event DTO families
- notification-first event payload rules
- transport-failure vs application-failure separation
- crate ownership and dependency rules
- Phase 000 bridge service contracts
- compatibility and testing requirements

## 3. Non-Responsibilities

This specification does not define:

- Flutter widget structure
- Riverpod provider/controller design
- Flutter navigation
- generated `flutter_rust_bridge` source layout
- exact FFI ABI mechanics
- backend command/query/background execution internals
- application error semantics already owned by SPEC-BE-003
- runtime lifecycle semantics already owned by SPEC-BE-004
- appearance-settings domain semantics already owned by SPEC-BE-005
- application event bus semantics already owned by SPEC-BE-006
- startup/recovery orchestration already owned by SPEC-BE-007
- complete future feature DTO catalogs
- network protocols
- remote API compatibility
- multi-process client negotiation

Those concerns belong to frontend, runtime, feature, generated-binding, or future compatibility specifications.

## 4. Architectural Principles

1. Bridge contracts expose application capabilities, not backend implementation structure.
2. Bridge service boundaries mirror stable application capabilities, not crate boundaries.
3. Bridge operations describe application intent, not execution strategy.
4. Flutter does not need to know whether backend work is a Query, Immediate Command, or Background Operation.
5. Domain models never cross the bridge directly.
6. Infrastructure objects never cross the bridge directly.
7. Repositories, Units of Work, gateways, executors, and runtime internals never cross the bridge.
8. Every DTO is immutable.
9. Every canonical DTO represents one application concept.
10. DTOs are snapshots, never live backend objects.
11. Relationships use stable application identifiers rather than navigable backend object graphs.
12. Published DTO fields are semantically immutable.
13. Published bridge contracts evolve additively whenever possible.
14. Every application operation returns one consistent application-level result shape.
15. `ApplicationErrorDto` is the bridge projection of `ApplicationError`, not a separate error taxonomy.
16. Transport failures are distinct from application failures.
17. There is exactly one push-based runtime event stream per runtime generation.
18. All other bridge interactions are request/response.
19. Runtime events are notification-first and do not become an alternate authoritative state channel.
20. Queries/application operations remain the authoritative mechanism for current state.
21. Bridge contracts remain technology-neutral even though implementation currently uses `flutter_rust_bridge`.

## 5. Bridge Layer Position

Conceptually:

```text
Flutter
    ↓
Bridge service contracts
    ↓
Bridge mapping/adapters
    ↓
Application/runtime contracts
    ↓
Domain / Runtime / Infrastructure
```

The bridge layer:

- translates bridge request DTOs to application inputs
- invokes stable application capabilities
- translates application outputs into canonical DTOs
- projects `ApplicationError` into `ApplicationErrorDto`
- projects runtime/application notifications into `RuntimeEventDto`

The bridge layer does not own business rules.

## 6. Service-Oriented Bridge

Flutter interacts with a small set of capability-oriented bridge services.

Conceptually:

```text
RuntimeBridge
SettingsBridge
DiagnosticsBridge
```

Future phases may add:

```text
LibraryBridge
MetadataProviderBridge
MetadataBridge
```

Bridge service boundaries follow application capabilities rather than Rust crate organization.

Refactoring backend modules or crates must not require changing a bridge service merely because implementation ownership moved internally.

## 7. Application-Oriented Bridge Operations

Each bridge method corresponds to one application capability.

Preferred:

```text
GetAppearanceSettings()
UpdateAppearanceSettings(request)
GetRuntimeState()
ExportDiagnostics(request)
RetryStartup(expectedRuntimeInstanceId)
ResetAppearanceSettings(expectedRuntimeInstanceId)
```

Prohibited generic bridge entry points include:

```text
ExecuteQuery(...)
ExecuteCommand(...)
StartBackgroundOperation(...)
Invoke("operation_name", payload)
```

Flutter consumes application intent, not CQRS/runtime implementation categories.

The backend may change internal execution strategy without changing the bridge contract provided observable application semantics remain compatible.

## 8. Bridge Asynchrony

All bridge operations are asynchronous from Flutter's perspective.

This does not imply that all backend operations are background jobs.

Examples:

- `GetAppearanceSettings()` returns asynchronously with its final result.
- `UpdateAppearanceSettings()` returns asynchronously after the immediate command completes.
- A future long-running import call returns asynchronously after background operation admission with an `OperationHandleDto`.

The bridge must not expose blocking assumptions about Rust implementation threads or executors.

## 9. Unified `BridgeResult<T>`

Every application operation returns conceptually:

```text
BridgeResult<T>
├── Success(T)
└── Failure(ApplicationErrorDto)
```

The exact generated Rust/Dart representation is an implementation detail.

Required semantics:

1. `Success(T)` means the bridge transport worked and the application operation succeeded.
2. `Failure(ApplicationErrorDto)` means the bridge transport worked and the application operation produced a structured application failure.
3. All bridge services use the same result contract.
4. Operation-specific application failure unions are prohibited unless a future specification proves a need beyond `ApplicationError`.
5. Void-success operations use an explicit bridge-compatible unit/empty success representation chosen during implementation, not `null` as an overloaded failure signal.

## 10. Transport Failures vs Application Failures

Transport failure and application failure are distinct.

### Transport failure

Examples include:

- generated bridge binding unavailable
- native library unavailable
- serialization/marshalling failure
- underlying channel/process communication failure

A transport failure means the application-level result could not be delivered reliably.

It is not represented by inventing an `ApplicationErrorDto` unless a real backend `ApplicationError` was produced.

### Application failure

Examples include:

- invalid argument
- persistence failure
- runtime not ready
- startup failure
- settings integrity failure

These are represented by:

```text
BridgeResult<T>::Failure(ApplicationErrorDto)
```

Flutter handling must preserve this distinction so bridge connectivity failures are not confused with normal application error policy.

## 11. `ApplicationErrorDto`

`ApplicationErrorDto` is the sole canonical bridge projection of SPEC-BE-003 `ApplicationError`.

Conceptually:

```text
ApplicationErrorDto
- code
- category
- severity
- recoverability
- retryPolicy
- messageKey
- traceId
- safeContext
```

Field names may follow project Dart/Rust serialization conventions, but field semantics are fixed.

Rules:

1. Every field maps directly from the corresponding stable application contract.
2. The bridge does not reinterpret severity, recoverability, or retry policy.
3. The bridge does not create independent error codes.
4. Raw Rust error strings, source chains, SQL, provider bodies, or unsanitized paths never appear in `ApplicationErrorDto`.
5. `safeContext` includes only values permitted by the backend error catalog.
6. `traceId` remains the operation trace identifier from SPEC-BE-003.

## 12. Canonical Concept-Owned DTOs

Each application concept has exactly one canonical bridge DTO.

Examples:

```text
ApplicationErrorDto
RuntimeStateDto
StartupFailureDto
RecoveryActionDto
AppearanceSettingsDto
OperationHandleDto
```

Operations compose canonical DTOs rather than redefining the same concept in operation-specific response objects.

Avoid redundant contracts such as:

```text
GetAppearanceSettingsResponseDto
AppearanceSettingsSnapshotDto
SettingsScreenAppearanceDto
```

when they represent the same application concept.

Request DTOs may be operation-specific because they represent application intent rather than canonical state concepts.

## 13. DTO Immutability

Every bridge DTO is immutable after construction.

Consequences:

- Flutter receives snapshots, not backend references.
- Rust cannot mutate a DTO after crossing the bridge.
- Flutter cannot mutate backend authoritative state by mutating a DTO locally.
- updates require a new bridge operation/request.
- events contain immutable notification data.

Generated mutable implementation classes, if unavoidable, must be treated as immutable contracts by all application/frontend code.

## 14. Snapshot Semantics

A bridge DTO is an immutable snapshot of one application concept at one point in time.

A DTO is not:

- a live object
- an ORM entity
- a repository handle
- a synchronized proxy
- a subscription
- a domain aggregate reference

Flutter may derive UI-specific models from canonical DTO snapshots.

The backend does not construct screen-specific view-model graphs solely to match Flutter layout.

## 15. Stable Identifiers and Relationships

Bridge relationships use stable application identifiers once those identifiers exist.

Example future projection:

```text
LibraryRootDto
- libraryRootId
- librarySourceId
```

rather than embedding a complete mutable `LibrarySourceDto` graph inside every root snapshot. Metadata-provider relationships, when exposed by later features, use the separate metadata-provider `ProviderId` identity defined by SPEC-BE-010 and must not be conflated with `LibrarySourceId` or `SourceProviderType`.

Rules:

1. Typed backend IDs map to stable bridge-compatible scalar/string representations.
2. Identifier semantics are documented per concept.
3. Flutter treats identifiers as opaque unless the contract explicitly defines structure.
4. Backend object pointers, memory addresses, database row IDs, and persistence-local singleton keys never cross the bridge.
5. Singleton concepts with no domain identity do not receive artificial IDs merely for transport.

## 16. Semantically Append-Only Evolution

Bridge contracts evolve additively whenever practical.

Published fields are semantically immutable.

Once a field is published, its following characteristics do not change silently:

- meaning
- units
- valid range
- identity semantics
- lifecycle meaning
- nullability semantics
- interpretation

Examples of prohibited semantic mutation include:

```text
progress: 0..100
```

later being reinterpreted as:

```text
progress: 0.0..1.0
```

or reusing an existing enum variant for different meaning.

If semantics must change incompatibly, introduce:

- a new field
- a new DTO
- a new operation
- or a new compatibility-major contract where required

Existing fields are not removed while their contract version remains supported.

## 17. Unknown Additive Fields and Variants

DTO consumers must tolerate additive compatible fields they do not use.

For closed/sealed event or enum representations, adding a new semantic variant may require coordinated generated-client update depending on bridge tooling. Such a tooling limitation does not permit reusing an existing variant with new semantics.

Versioning and compatibility mechanics beyond the Phase 000 single-application distribution model are finalized by SPEC-X-001.

## 18. DTO Naming Convention

The examples in this naming catalog include both active Phase 000 types and reserved later-MVP types. Naming examples do not override the activation guards and Phase 000 exclusions in this specification.

All concrete transport objects use the `Dto` suffix.

### Request DTOs

```text
UpdateAppearanceSettingsRequestDto
DiagnosticsExportRequestDto
```

### Canonical state/snapshot DTOs

```text
AppearanceSettingsDto
RuntimeStateDto
StartupFailureDto
```

### Event DTOs

```text
RuntimeStateChangedDto
JobProgressDto
AppearanceSettingsChangedDto
```

### Error DTO

```text
ApplicationErrorDto
```

### Handle DTO

```text
OperationHandleDto
```

`BridgeResult<T>` is the generic result envelope and intentionally does not use the `Dto` suffix.

## 19. Runtime State Enum

The bridge exposes the canonical SPEC-BE-004 runtime lifecycle values:

```text
Uninitialized
Starting
Ready
StartupFailed
ShuttingDown
Stopped
```

The serialized representation is stable and implementation-neutral.

Flutter must not derive lifecycle state from incidental field presence or generated bridge object type names.

## 20. `RuntimeStateDto`

`RuntimeStateDto` is the canonical immutable snapshot of one runtime generation at one lifecycle point.

Conceptually:

```text
RuntimeStateDto
- runtimeInstanceId
- lifecycleState
- startupPhase nullable
- startupFailure nullable
```

Rules:

1. `runtimeInstanceId` is always present for a constructed runtime generation.
2. `lifecycleState` is authoritative for runtime lifecycle.
3. `startupPhase` is present only when startup progress or terminal failure attribution requires it.
4. `startupFailure` is present only when `lifecycleState` is `StartupFailed`.
5. Failure-state actions are available only through `startupFailure.recoveryActions`; `RuntimeStateDto` does not store a second recovery-action list or capability bag.
6. Flutter uses `runtimeInstanceId` to detect runtime replacement.

## 21. No Generic Runtime Capability Bag

Phase 000 publishes no sibling runtime capability bag. Runtime lifecycle authority comes from `RuntimeStateDto.lifecycleState`; failed-runtime action availability comes exclusively from `StartupFailureDto.recoveryActions`; named bridge APIs define the supported operation surface.

A boolean map or typed DTO that repeats recovery-action availability would create a second writable truth and is prohibited.

If a later active capability genuinely requires dynamic optional availability outside startup recovery, it must add one narrowly typed projection through an explicit additive contract update, identify its single authority, and avoid duplicating lifecycle or recovery-action semantics.

## 22. `StartupFailureDto`

`StartupFailureDto` is the canonical bridge projection of SPEC-BE-007 startup failure context.

Conceptually:

```text
StartupFailureDto
- phase
- error: ApplicationErrorDto
- recoveryActions: [RecoveryActionDto]
```

Rules:

1. `phase` identifies the responsibility-oriented startup phase in which startup became terminal.
2. `error` contains the canonical underlying application failure.
3. `recoveryActions` contains only actions valid for this failure/runtime generation.
4. `StartupFailureDto` does not duplicate severity, message key, trace ID, or other fields already owned by `ApplicationErrorDto`.
5. `StartupFailureDto` does not include `runtimeInstanceId`; runtime identity belongs to the parent `RuntimeStateDto`.

## 23. Startup Phase Projection

The bridge must support the responsibility-oriented startup phase identities from SPEC-BE-007, including Phase 000:

```text
EnvironmentInitialization
ObservabilityInitialization
ConfigurationInitialization
PersistenceInitialization
SettingsInitialization
CoreServicesInitialization
EventInfrastructureInitialization
ReadinessValidation
```

These values remain technology-neutral.

The bridge does not expose implementation steps such as SQLite open or migration SQL as startup phase enum values.

## 24. `RecoveryActionDto`

`RecoveryActionDto` represents one currently available recovery capability.

Conceptually:

```text
RecoveryActionDto
- kind: RecoveryActionKind
- constraints: RecoveryActionConstraintsDto?
```

Phase 000 recovery kinds include:

```text
RetryStartup
ResetAppearanceSettings
ExportDiagnostics
CopyTechnicalDetails
OpenDataDirectory
Exit
```

Rules:

1. `kind` is the stable action discriminator.
2. DTOs contain no localized button title, description, confirmation message, or icon name.
3. DTOs contain no SQL, filesystem command, executable instruction, or implementation procedure.
4. Constraints, when needed, are typed and additive.
5. The absence of an action means it is unavailable.
6. Actions are valid only for the runtime generation/failure that exposed them.

## 25. Recovery Request Binding

Recovery actions must not be executable accidentally against a replacement runtime generation.

The bridge request for a runtime-bound recovery action must include or otherwise be bound to the expected `runtimeInstanceId`.

If the active runtime generation differs, the action is rejected with a stable application error rather than applied to the new runtime.

This binding applies to every operation invoked because a `RecoveryActionDto` advertised it for a failed runtime, including non-mutating diagnostics and `Exit`. Generic diagnostics or shutdown capabilities used outside that failed-runtime recovery context may have their own lifecycle scope, but they must not be used to bypass stale recovery-action validation.

The exact request DTO shape is implementation-planned, but stale-action prevention is mandatory.

Failure-state recovery actions have exactly one authoritative source: `StartupFailureDto.recoveryActions`. `RuntimeStateDto` does not store or serialize a second recovery-action list.

Retry startup, reset appearance settings, exit the failed runtime, failure-screen diagnostics export, technical-detail copy, and open-data-directory requests are generation-bound. A mismatched expected runtime generation maps to `ARGUS.V1.RUNTIME.STALE_INSTANCE`; Flutter refreshes authoritative runtime state and does not replay the stale request automatically.

## 26. `AppearanceSettingsDto`

The canonical bridge projection of SPEC-BE-005 is:

```text
AppearanceSettingsDto
- themeMode
```

Allowed theme values are exactly:

```text
System
Light
Dark
```

Rules:

1. The DTO contains no persistence-local singleton ID.
2. The DTO contains no schema revision.
3. The DTO contains no persistence timestamp.
4. The DTO is immutable.
5. Flutter treats the returned DTO as authoritative for that read operation.
6. Future appearance fields are added through the semantically append-only contract rules.

## 27. `UpdateAppearanceSettingsRequestDto`

The update request conceptually contains the complete desired appearance settings aggregate:

```text
UpdateAppearanceSettingsRequestDto
- settings: AppearanceSettingsDto
```

The bridge maps this into the application-level `UpdateAppearanceSettingsCommand`.

Rules:

1. Flutter does not submit persistence metadata.
2. Flutter does not submit optimistic-concurrency metadata during MVP.
3. Backend validation remains authoritative.
4. The update operation returns application success/failure rather than echoing the updated settings snapshot.

## 28. Settings Bridge Contract

Phase 000 `SettingsBridge` exposes conceptually:

```text
GetAppearanceSettings()
    -> BridgeResult<AppearanceSettingsDto>

UpdateAppearanceSettings(UpdateAppearanceSettingsRequestDto)
    -> BridgeResult<Unit>
```

Flutter retrieves authoritative state through `GetAppearanceSettings()`.

A successful update does not imply Flutter should treat a returned copy as authoritative because no copy is returned. Event-driven reconciliation uses `AppearanceSettingsChangedDto` followed by the focused read when needed.

## 29. Operation Completion Model

Bridge completion behavior follows the application capability while hiding runtime classification.

### Immediate result operations

Queries return final immutable result snapshots:

```text
BridgeResult<T>
```

Immediate mutation operations return terminal application success/failure:

```text
BridgeResult<Unit>
```

The following long-running-operation contract is inactive during Phase 000. Phase 000 MUST NOT generate or implement `OperationHandleDto`, job query DTOs, job event variants, mappers, bindings, fakes, or tests. Phase 001 activates the bounded Sources/Jobs subset defined by Section 66.

### Long-running operations

A future long-running bridge operation returns after successful background admission with:

```text
BridgeResult<OperationHandleDto>
```

The handle does not mean the background operation completed.

## 30. `OperationHandleDto`

`OperationHandleDto` is intentionally minimal.

Conceptually:

```text
OperationHandleDto
- jobRunId
- operationType
```

It contains identity only.

It does not contain:

- current progress
- current state
- completion percentage
- error
- timestamps
- cancellation state
- estimated duration

Those observations belong to events or authoritative operation-state queries where such queries exist.

## 31. Operation Identity Mapping

Where SPEC-BE-004 uses `JobRunId` as the canonical identity of a background execution attempt, `OperationHandleDto.jobRunId` is the bridge projection of that same identity.

The bridge must not invent a second independent operation identifier for the same execution merely for transport convenience. Phase 001 activates persisted background operations and therefore resolves the earlier naming reservation in favor of canonical `jobRunId` terminology.

## 32. One Unified Runtime Event Stream

There is exactly one bridge push stream per runtime generation.

Conceptually:

```text
RuntimeBridge.subscribeEvents()
    -> Stream<RuntimeEventDto>
```

All bridge push notifications use this stream.

There are no separate:

```text
settingsEvents
operationEvents
startupEvents
metadataProviderEvents
```

streams.

There are no feature-level native callbacks or direct native event subscriptions.

Flutter's app-level event coordinator owns the single stream, as required by SPEC-BE-004.

## 33. Runtime Event Envelope

Every bridge runtime event carries the lifecycle sequencing metadata defined by SPEC-BE-004.

Conceptually:

```text
RuntimeEventDto
- runtimeInstanceId
- sequence
- occurredAt
- payload: RuntimeEventPayloadDto
```

The concrete generated representation may model this as a sealed union with common envelope fields, but semantic requirements are fixed.

Rules:

1. `runtimeInstanceId` identifies the runtime generation.
2. `sequence` increases strictly within that runtime generation.
3. `occurredAt` is an event occurrence timestamp suitable for diagnostics/UI ordering, not authoritative domain state.
4. `payload` is exactly one strongly typed event variant.
5. A replacement runtime begins a new sequence under a new `runtimeInstanceId`.

## 34. Closed Strongly Typed Event Hierarchy

`RuntimeEventDto` uses a closed, strongly typed event hierarchy for each generated contract version.

Prohibited event payload representations include:

```text
Object
Map<String, dynamic>
Map<String, String>
JSON string
(eventName, arbitraryPayload)
```

Flutter must be able to exhaustively or explicitly handle generated event variants using normal typed language constructs.

Event routing does not rely on stringly typed event names.

## 35. Runtime Event Taxonomy

All events share one stream, but are organized conceptually into three families.

```text
RuntimeEventDto
├── Runtime Events
├── Operation Events
└── Domain Events
```

The families are organizational/documentation concepts only. They do not create separate streams, ordering domains, or delivery policies.

## 36. Runtime Event Family

Runtime events concern runtime lifecycle and startup/recovery state.

Phase 000 includes at least:

```text
RuntimeStateChangedDto
StartupFailedDto
```

The exact need for both variants during Phase 000 may be implemented without duplication: `StartupFailedDto` may carry only failure-transition notification context while authoritative failed-runtime details remain available through `GetRuntimeState()`.

Runtime events remain notification-first.

## 37. `RuntimeStateChangedDto`

Conceptually:

```text
RuntimeStateChangedDto
- lifecycleState
```

It announces that the runtime lifecycle state changed.

It does not contain the complete authoritative `RuntimeStateDto` snapshot.

Flutter may call `GetRuntimeState()` when it requires the current full runtime snapshot.

`runtimeInstanceId` is already present in the common runtime event envelope and is not duplicated inside this payload.

## 38. `StartupFailedDto`

`StartupFailedDto` is a notification that startup reached a terminal failure state.

It must not duplicate the complete authoritative `StartupFailureDto` if that creates a competing snapshot channel.

The minimal Phase 000 projection should contain only context required to identify the notification; Flutter obtains the authoritative failure/recovery snapshot through `GetRuntimeState()`.

This preserves the notification-first event rule.

## 39. Job Event Family

Phase 001 is the first active phase with persisted background jobs. The previously reserved per-transition `OperationStartedDto` / `OperationCompletedDto` / `OperationFailedDto` / `OperationCancelledDto` family was never part of the Phase 000 generated contract and is replaced before first activation by two generic job notification variants:

```text
JobStateChangedDto
JobProgressDto
```

This avoids duplicating the complete generic job lifecycle vocabulary in the event schema while preserving focused progress responsiveness.

## 40. `JobStateChangedDto`

Conceptually:

```text
JobStateChangedDto
- jobRunId
```

`JobStateChangedDto` announces that authoritative lifecycle, terminal, cancellation-request, or control-availability facts for the identified `JobRun` may have changed.

It does not state the new lifecycle value and does not carry a `JobRunDto` snapshot. Consumers reconcile through `GetJob(jobRunId)` or the relevant bounded `ListJobs` projection.

The same event covers changes involving any generic state owned by SPEC-BE-004, including `Queued`, `Preparing`, `Running`, `Completed`, `CompletedWithIssues`, `Failed`, `Cancelled`, `Interrupted`, and `Abandoned`.

## 41. `JobProgressDto`

Progress follows SPEC-BE-004 structured, phase-local semantics.

Conceptually:

```text
JobProgressDto
- jobRunId
- phase
- completedUnits?
- totalUnits?
- statusKey?
```

Rules:

1. The backend publishes no percentage field.
2. Unknown totals remain absent rather than guessed.
3. Flutter may derive a phase-local percentage only when determinate counts make that interpretation truthful.
4. No weighted overall percentage exists.
5. Progress event payload is ephemeral observation data and may be coalesced or dropped.
6. Flutter does not accumulate progress deltas as authoritative state.
7. Operation-specific facts beyond this generic bounded progress shape are obtained through authoritative typed job detail.

Progress remains the explicit responsiveness exception to the smallest-ID-only notification style established by SPEC-BE-004.

## 42. Authoritative Job Reconciliation

Job notifications answer that something relevant changed; they do not answer what is true now.

Representative flow:

```text
JobStateChangedDto(jobRunId)
    ↓
GetJob(jobRunId)
    ↓
JobDetailDto
```

List and shell consumers may instead refresh the relevant `ListJobs` scope when list membership or aggregate active count is what they need.

## 43. Job Failure Information

`JobStateChangedDto` does not embed `ApplicationErrorDto` when a job becomes `Failed`.

The generic job detail projection owns bounded terminal failure information. This keeps failed-job notification semantics consistent with all other lifecycle invalidations and avoids creating an event-only failure snapshot channel.

Transport or subscription failures remain separate from backend application/job failure as required by Sections 9–10.

## 44. Job and Feature Notification Separation

A background operation may produce both generic job notifications and feature/domain invalidations because those notifications identify different authoritative projections.

For Phase 001 LibraryScan, generic lifecycle/progress changes use `JobStateChangedDto` / `JobProgressDto`; root/source graph changes use the Phase 001 domain-event DTOs defined later in this specification.

Flutter must not infer feature state from generic job events or reconstruct generic job lifecycle from feature invalidation events.

## 45. Domain Event Family

Domain event DTOs are bridge projections of application events from SPEC-BE-006.

Phase 000 includes:

```text
AppearanceSettingsChangedDto
```

Phase 001 additionally activates notification-first Sources invalidations:

```text
LibraryRootsChangedDto
LibraryRootChangedDto
SourceEntriesChangedDto
```

Future phases may add further typed domain notifications such as metadata-provider health changes when their owning capabilities become active.

Every bridge domain event maps to one owned application event semantic. The bridge does not invent business events independently.

## 46. Notification-First Event Payload Rule

Runtime event payloads contain the minimum immutable context necessary to interpret the notification.

They do not carry complete snapshots of mutable authoritative application state merely for convenience.

The runtime event stream answers:

> What happened?

Application operations answer:

> What is true now?

Identity fields are permitted when required to identify the affected concept.

Terminal/error facts are permitted when they are intrinsic to the event meaning.

## 47. `AppearanceSettingsChangedDto`

The Phase 000 DTO is intentionally payload-minimal:

```text
AppearanceSettingsChangedDto
```

It contains no `AppearanceSettingsDto` snapshot.

Flutter handling is:

```text
AppearanceSettingsChangedDto
    ↓
GetAppearanceSettings()
    ↓
AppearanceSettingsDto
```

This preserves SPEC-BE-005 and SPEC-BE-006 authority boundaries.

## 48. Event Sequence Handling Contract

Flutter consumes runtime event envelope metadata according to SPEC-BE-004:

### Normal event

If runtime generation matches and:

```text
sequence == lastSequence + 1
```

process normally.

### Gap

If sequence skips values, Flutter treats notifications as lost and performs the smallest relevant authoritative refresh.

### Duplicate/stale

If:

```text
sequence <= lastSequence
```

ignore.

### Runtime replacement

If `runtimeInstanceId` changes, Flutter invalidates event-derived assumptions and refreshes appropriate authoritative state.

The bridge DTO contract exposes the data required for this behavior but does not move sequence policy out of SPEC-BE-004.

## 49. Event Backpressure Boundary

The bridge DTO contract must remain compatible with SPEC-BE-004 bounded, best-effort event delivery.

Consequences:

- DTO consumers cannot assume every notification arrives.
- DTO consumers cannot depend on event replay.
- compatible progress/state notifications may be coalesced before Flutter receives them.
- dropped notifications remain detectable through sequence gaps.
- terminal authoritative correctness never depends on stream delivery.

## 50. Runtime Bridge Contract

Phase 000 `RuntimeBridge` conceptually exposes:

```text
GetRuntimeState()
    -> BridgeResult<RuntimeStateDto>

SubscribeEvents()
    -> RuntimeEvent stream

RetryStartup(expectedRuntimeInstanceId)
    -> BridgeResult<RuntimeStateDto>

ResetAppearanceSettings(expectedRuntimeInstanceId)
    -> BridgeResult<RuntimeStateDto>

ExitFailedRuntime(expectedRuntimeInstanceId)
    -> BridgeResult<RuntimeStateDto>

Shutdown()
    -> BridgeResult<Unit>
```

Recovery operations are typed rather than routed through a generic executor. Each validates the expected runtime generation and returns the authoritative resulting `RuntimeStateDto`. `RetryStartup` and successful reset recovery ultimately create or expose the fresh runtime generation through SPEC-BE-007 rather than restarting the failed runtime in place.

The unscoped `Shutdown()` entry point is a normal lifecycle operation, not the generation-bound `Exit` recovery action, and must not bypass stale-action validation.

Failure-screen diagnostics export, technical-detail retrieval, and open-data-directory operations are likewise bound to the expected failed runtime generation when invoked because that failure advertised them.

## 51. Diagnostics Bridge Contract

Failure-screen diagnostics capabilities are generation-bound because they are offered by one failed runtime snapshot:

```text
ExportStartupDiagnostics(expectedRuntimeInstanceId, DiagnosticsExportRequestDto)
    -> BridgeResult<DiagnosticsExportDto>

GetStartupTechnicalDetails(expectedRuntimeInstanceId)
    -> BridgeResult<TechnicalDetailsDto>

OpenStartupDataDirectory(expectedRuntimeInstanceId)
    -> BridgeResult<Unit>
```

A stale expected generation maps to `ARGUS.V1.RUNTIME.STALE_INSTANCE`; the bridge does not silently retarget the request. General ready-state diagnostics may be added as separately named capabilities when an active phase requires them.

Only actions currently advertised by `StartupFailureDto.recoveryActions` are presented in a failed-runtime UI. Diagnostic DTOs contain sanitized application-level information only. Platform save-dialog ownership must not weaken SPEC-BE-003 path and privacy rules.

## 52. `DiagnosticsExportDto`

The export result is an immutable terminal summary, not the diagnostic bundle contents.

Conceptually it may include safe fields such as:

```text
DiagnosticsExportDto
- outcome
- destinationClassification or safe user-selected result token
```

Exact fields are implementation-planned according to platform save-dialog ownership.

The DTO must never return archive bytes by default, database contents, credentials, or unrestricted paths solely for convenience.

## 53. `TechnicalDetailsDto`

`TechnicalDetailsDto` is the bridge representation used for user-copyable startup/runtime technical details.

It must be constructed from sanitized structured data under SPEC-BE-003, not raw Rust error formatting.

It may contain bounded display-ready technical text if the dedicated diagnostics contract intentionally defines that text as safe copy output; such text is diagnostic output, not an error-control-flow contract.

## 54. Bridge Mapping Rules

Mapping must be explicit at the bridge boundary.

Required direction:

```text
bridge request DTO
    -> application command/query input

application result
    -> canonical response DTO

ApplicationError
    -> ApplicationErrorDto

application/runtime event
    -> runtime event DTO variant
```

Rules:

1. No domain type is serialized directly simply because the bridge tooling can derive serialization for it.
2. No infrastructure type is serialized directly.
3. Mapping code is deterministic and side-effect free.
4. Mapping does not perform persistence reads.
5. Mapping does not reinterpret application policy.
6. Mapping failures are treated as internal/transport defects according to the point at which they occur.

## 55. No Generated-Binding Leakage

Generated `flutter_rust_bridge` types are internal bridge infrastructure.

Flutter feature/application code must consume project-owned abstractions and models rather than generated bindings directly except inside the dedicated bridge/client adapter layer.

Backend application/domain crates must not depend on generated bridge code.

Regenerating bridge bindings must not alter domain/application APIs.

## 56. Privacy and Security

All bridge DTOs follow SPEC-BE-003 safe-context and redaction requirements.

Never expose through DTOs unless an explicit later contract requires and sanitizes them:

- credentials
- tokens
- passwords
- authorization headers
- provider secret material
- raw database rows
- SQL
- unrestricted source chains
- arbitrary ROM content
- unsanitized filesystem paths

Once Argus identity exists, prefer Argus-owned identifiers over names, paths, hashes, and provider-native identifiers.

## 57. Technology-Neutral Contracts

Public bridge concepts must not be named after generated or transport technology.

Avoid application-facing concepts such as:

```text
FlutterRustBridgeSettingsDto
FrbRuntimeEvent
RustStreamHandle
DartCallbackEvent
SerdeBridgeResult
```

Preferred concepts are application-oriented:

```text
AppearanceSettingsDto
RuntimeStateDto
RuntimeEventDto
BridgeResult<T>
```

Technology remains replaceable behind the bridge contract.

## 58. Crate Ownership

Ownership follows SPEC-BE-001.

### `argus-domain`

Owns domain models and value objects only. It does not depend on DTOs.

### `argus-application`

Owns application contracts consumed by the bridge, including `ApplicationError`, settings operations, application events, and future feature operations.

It does not depend on bridge DTOs.

### `argus-runtime`

Owns runtime lifecycle, operation execution, event sequencing/backpressure, startup/recovery integration, and runtime instance identity.

It does not own bridge DTO mapping.

### `argus-bridge`

Owns:

- bridge service façades/adapters
- all `*Dto` transport contracts
- `BridgeResult<T>` transport projection
- application-to-DTO mapping
- request DTO-to-application input mapping
- runtime event DTO projection
- generated binding integration

### `argus-infrastructure`

Owns no bridge DTOs unless an implementation-local adapter type is strictly private and not exported as the public bridge contract.

## 59. Dependency Rules

Required dependency direction:

```text
Flutter adapter/client
        ↓
argus-bridge DTO/service contract
        ↓
argus-application / argus-runtime
        ↓
domain / infrastructure ports
```

Forbidden dependencies include:

- domain -> bridge DTOs
- application -> generated FRB bindings
- persistence -> bridge DTOs
- repository -> bridge result types
- bridge mapping -> direct SQLite APIs
- Flutter feature code -> raw infrastructure/domain Rust representations

Architecture tests should enforce these rules where practical.

## 60. Testing Requirements

### 60.1 DTO contract tests

Verify:

- canonical DTO names and required fields
- DTO immutability expectations
- stable enum serialization
- no persistence/infrastructure fields leak into DTOs
- concept-owned DTOs are not duplicated per operation

### 60.2 Error projection tests

Verify every Phase 000 application error projection preserves:

- code
- category
- severity
- recoverability
- retry policy
- message key
- trace ID
- allowed safe context

Verify raw internal errors do not cross.

### 60.3 Runtime state tests

Verify:

- every lifecycle state maps correctly
- `runtimeInstanceId` is present
- `startupFailure` is only populated for `StartupFailed`
- recovery actions match current failure eligibility
- capabilities represent currently safe operations

### 60.4 Startup failure tests

Verify:

- startup phase projection
- nested `ApplicationErrorDto`
- no duplicated runtime identity
- recovery action projection
- stale runtime-bound recovery request rejection

### 60.5 Appearance settings tests

Verify:

- System/Light/Dark mapping
- no singleton persistence ID
- no schema/timestamp metadata
- complete update request mapping
- update success returns no authoritative settings echo

### 60.6 `BridgeResult` tests

Verify:

- success mapping
- application failure mapping
- void/unit success
- application error is not confused with transport failure

### 60.7 Runtime event tests

Verify:

- one unified event stream
- envelope contains runtime instance ID, sequence, occurrence time, and typed payload
- sequence mapping is monotonic within one runtime
- replacement runtime starts new sequence identity
- payload variant mapping is strongly typed
- unknown string event routing is absent

### 60.8 Notification-first tests

Verify:

- `AppearanceSettingsChangedDto` does not carry settings snapshot
- `RuntimeStateChangedDto` does not carry full runtime snapshot
- domain events carry only minimum interpretation context
- Flutter recovery path can re-query authoritative state after a sequence gap

### 60.9 Phase 001 job event tests

When persisted jobs are active, verify:

- `JobStateChangedDto` and `JobProgressDto` are the active generic job variants
- canonical `jobRunId` is present
- `JobStateChangedDto` carries no full job or terminal-error snapshot
- `JobProgressDto` has no percentage field
- progress supports determinate and indeterminate phase facts
- authoritative job detail remains recoverable after event loss

### 60.10 Generated-binding boundary tests

Verify:

- generated FRB types remain inside bridge/client adapter layers
- application/domain crates do not import generated bindings
- Flutter feature controllers can be tested against project-owned API abstractions/fakes

### 60.11 Compatibility tests

Snapshot or equivalent contract tests must detect:

- field removal
- field renaming
- enum representation changes
- semantic-unit changes represented structurally where testable
- accidental DTO duplication
- application error projection drift

## 61. Phase 000 Minimum DTO Catalog

Phase 000 requires at least:

```text
BridgeResult<T>
ApplicationErrorDto
RuntimeStateDto
RuntimeCapabilitiesDto
StartupFailureDto
RecoveryActionDto
AppearanceSettingsDto
UpdateAppearanceSettingsRequestDto
RuntimeEventDto
RuntimeStateChangedDto
StartupFailedDto
AppearanceSettingsChangedDto
```

Persisted-job DTO semantics are intentionally absent from the Phase 000 minimum catalog. Phase 001 activates only the bounded Sources/Jobs DTO and event surface defined by Section 66.

Diagnostics DTOs required by the Phase 000 recovery experience include the minimum safe forms of:

```text
DiagnosticsExportRequestDto
DiagnosticsExportDto
TechnicalDetailsDto
```

## 62. Phase 000 Minimum Bridge Operations

Phase 000 exposes application capabilities sufficient for:

### Runtime/startup/recovery

- initialize/start backend through one root host entry point
- get runtime state
- subscribe to unified runtime events
- retry startup through fresh runtime replacement
- execute supported typed recovery actions
- shutdown

### Settings

- get appearance settings
- update appearance settings

### Diagnostics

- export diagnostics
- retrieve/copy-safe technical details
- open data directory where supported

Exact generated method names may follow coding conventions, but capability and semantic boundaries are fixed.

## 63. Acceptance Criteria

SPEC-BE-008 is satisfied when:

1. Bridge services are organized by application capability rather than crate boundaries.
2. Every bridge method expresses application intent rather than CQRS/runtime strategy.
3. All bridge operations are asynchronous from Flutter's perspective.
4. Application operations use one `BridgeResult<T>` success/failure contract.
5. Application failures use `ApplicationErrorDto` derived from `ApplicationError`.
6. Transport failures remain distinct from application failures.
7. Domain and infrastructure types never cross the bridge directly.
8. Every canonical application concept has exactly one canonical bridge DTO.
9. DTOs are immutable snapshots rather than live backend objects.
10. Relationships use stable identifiers instead of backend object graphs.
11. Published DTO fields are semantically immutable.
12. DTO evolution is additive whenever possible.
13. Incompatible semantics require a new field/DTO/operation rather than reinterpretation.
14. Concrete transport objects use the `Dto` suffix.
15. `RuntimeStateDto` is the canonical runtime-generation snapshot.
16. `RuntimeStateDto` owns `runtimeInstanceId`.
17. `StartupFailureDto` composes rather than duplicates `ApplicationErrorDto`.
18. `StartupFailureDto` does not duplicate runtime identity.
19. `RecoveryActionDto` is typed, declarative, non-presentational, generation-bound, and the sole failed-runtime action-availability authority; `RuntimeStateDto` has no sibling capability bag.
20. `AppearanceSettingsDto` contains only application-visible appearance state.
21. Update appearance requests contain the complete desired aggregate without persistence metadata.
22. Immediate settings update does not return an authoritative state echo.
23. When persisted background operations are active, `OperationHandleDto` contains identity only; Phase 000 does not implement it, and Phase 001 uses canonical `jobRunId`.
24. There is exactly one runtime push stream per runtime generation.
25. All other bridge communication is request/response.
26. Runtime events use common runtime instance/sequence metadata.
27. Runtime event payloads are strongly typed rather than arbitrary maps/JSON.
28. Runtime event families remain organizational only and do not create multiple streams.
29. Phase 001 job notifications use typed `JobStateChangedDto` and `JobProgressDto`; the earlier per-transition operation-event reservation never enters the generated contract.
30. Operation progress contains no backend percentage field.
31. Domain/runtime events are notification-first.
32. `AppearanceSettingsChangedDto` carries no authoritative settings snapshot.
33. Sequence gaps and runtime replacement provide enough data for Flutter to trigger authoritative refresh.
34. Generated `flutter_rust_bridge` bindings remain internal infrastructure.
35. Bridge mappings do not perform business logic or persistence reads.
36. DTOs and mappings follow SPEC-BE-003 privacy/redaction requirements.
37. Bridge/application contracts expose no FRB, SQLite, async-runtime, or infrastructure implementation types.
38. DTO, error, runtime, settings, event, compatibility, and architecture tests cover the contracts implemented by the active phase, slice, and task; Phase 001 coverage additionally satisfies Section 66, while still-reserved future capabilities require no scaffolding.

## 64. Prohibited Patterns

- one giant untyped `Invoke` bridge API
- exposing generic `ExecuteCommand` / `ExecuteQuery` to Flutter
- bridge service boundaries based solely on Rust crates
- serializing domain models directly as the public DTO contract
- serializing repository/infrastructure types
- live backend object handles as DTOs
- backend object graphs embedded recursively into DTOs
- multiple canonical DTOs for the same application concept
- mutable shared DTO state
- field meaning changes under an existing published name
- changing units/ranges without a new field
- independent bridge error taxonomy
- raw Rust errors crossing the bridge
- treating transport failures as `ApplicationErrorDto` without a backend application failure
- service-specific native event streams
- feature-level callbacks replacing the unified event stream
- `Map<String, dynamic>` runtime event payloads
- stringly typed event routing
- full mutable state snapshots embedded in ordinary change notifications
- appearance settings payload inside `AppearanceSettingsChangedDto`
- backend progress percentage
- generated FRB types leaking into application/domain or Flutter feature logic
- bridge DTO fields exposing SQLite/Tokio/FRB implementation terminology

## 65. Out of Scope

This specification does not finalize:

- exact generated Dart/Rust syntax
- exact file/module layout inside `argus-bridge`
- exact `flutter_rust_bridge` annotations
- exact serialization casing
- exact save-dialog implementation
- background-job query/filter DTOs beyond the bounded Phase 001 Jobs contract in Section 66
- logical game-library, provider-metadata, and metadata feature DTOs beyond the Phase 001 Sources contract
- remote API version negotiation
- backward compatibility across independently deployed frontend/backend versions
- frontend model mapping conventions
- Riverpod event coordination implementation

## 66. Phase 001 Activation Amendment — Sources and Jobs

### 66.1 Activation scope

Phase 001 activates the bridge surface required by PHASE-001, SPEC-BE-013, SPEC-FE-008, and SPEC-FE-009 without reopening the bridge architecture established by the preceding sections. The amendment maps application capabilities from SPEC-BE-009 (application service contracts), SPEC-BE-011 (source provider and indexing), and SPEC-BE-013 (library source management, scan operations, and source projections).

The active bridge service set becomes:

```text
RuntimeBridge
SettingsBridge
DiagnosticsBridge
SourcesBridge
JobsBridge
```

`SourcesBridge` is the product/application-facing bridge capability for Phase 001 local-source configuration, hierarchy inspection, and scan admission. It may adapt SPEC-BE-013 `LibraryService` internally; bridge service names are not required to mirror Rust application-service type names.

`JobsBridge` is the capability-neutral bridge for durable job observation and lifecycle controls.

The future logical game-library capability remains distinct. Phase 001 does not activate `LibraryBridge` merely because SPEC-BE-013's application service is named `LibraryService`.

### 66.2 Canonical background execution identity

Phase 001 activates persisted background operations and resolves the previously reserved handle naming:

```text
OperationHandleDto
- jobRunId
- operationType
```

Rules:

1. `jobRunId` is the bridge projection of SPEC-BE-004 `JobRunId`.
2. The bridge does not publish a second `operationId` for the same execution attempt.
3. Scan-admission results, job queries, job controls, job events, Flutter models, and stable Jobs routes use the same opaque execution identity.
4. `operationType` is the stable logical operation type, not a Rust class/type name.
5. The handle means durable admission succeeded; it does not mean the background work completed.

### 66.3 Phase 001 Sources projection DTOs

SPEC-BE-013 authoritative projections cross the bridge as focused immutable snapshots rather than screen-specific aggregate graphs.

Conceptually:

```text
LibraryRootDto
- libraryRootId
- displayName
- safeLocationPresentation
- availability
- lastScan nullable
- activeScan nullable
```

The root dimensions remain independent. The bridge must not collapse `availability`, `lastScan`, and `activeScan` into one synthetic status enum.

`lastScan`, when present, carries only the bounded terminal summary owned by SPEC-BE-013, including the relevant scan/job identities, status, and timestamps required by the consumer contract.

Its status is the closed Phase 001 `LibraryRootLastScanStatusDto` vocabulary: `Complete`, `Partial`, `Unavailable`, `Cancelled`, `Failed`, or `Abandoned`; `lastScan = null` represents `NeverScanned`. This summary remains independent from root `availability`, so `Cancelled` and `Abandoned` do not imply an availability change.

`activeScan`, when present, carries only the bounded current ownership/job summary required by the root projection. It does not replace `GetJob` as generic job authority.

Source hierarchy browsing uses a row/detail split:

```text
SourceEntryDto
- sourceEntryId
- parentSourceEntryId nullable
- displayName
- displayLocation
- kind
- classification
- boundedStatusSummary
```

```text
SourceEntryDetailDto
- sourceEntryId
- parentSourceEntryId nullable
- displayName
- displayLocation
- kind
- classification
- boundedObservationStatusDetail
```

`SourceEntryDetailDto` may contain additional bounded safe observation/status facts required by the FE-008 inspector. It does not expose provider or persistence internals.

Neither source-entry DTO exposes:

- `RootLocator`;
- `RelativeSourceLocator`;
- `SourceLocatorKey`;
- provider-native filesystem identities;
- source fingerprints used as backend identity/equality machinery;
- persistence row IDs or singleton keys;
- raw provider metadata or native handles.

### 66.4 Native local-folder selection request

Folder selection crosses the bridge only as request input:

```text
LocalFilesystemRootSelectionDto
- selectedFolderPath
```

Rules:

1. The value originates from the focused native folder-picker seam governed by SPEC-FE-008.
2. It is untrusted provider input, not Argus source identity.
3. Flutter does not normalize, canonicalize, split, compare, or derive overlap/identity semantics from the path.
4. `SourcesBridge` transports the request into the LocalFilesystem application/provider boundary, which owns validation and provider-owned locator construction.
5. The selected path is not echoed into root projections, source-entry projections, runtime events, application errors, or durable job history merely because it was bridge input.
6. User-facing persisted/history location text comes from backend-produced safe presentation projections/snapshots.

### 66.5 Explicit pagination DTOs

The bridge preserves each governed application paging model rather than weakening them into one nullable-field page abstraction.

Root administration uses bounded offset pagination:

```text
LibraryRootPageDto
- items: LibraryRootDto[]
- offset
- pageSize
- totalCount
```

Source hierarchy children use opaque cursor pagination:

```text
SourceEntryChildrenPageDto
- items: SourceEntryDto[]
- nextCursor nullable
```

Recent terminal Jobs history uses bounded offset pagination through:

```text
JobSummaryPageDto
- items: JobSummaryDto[]
- totalCount
- nextOffset nullable
```

Rules:

1. Cursor tokens are opaque to Flutter and are never parsed or synthesized there.
2. The bridge does not translate cursor semantics into offset semantics or vice versa.
3. `nextOffset` is meaningful for the `RecentTerminal` Jobs scope; the bounded `Active` scope may return the complete active set under backend policy with no continuation.
4. Backend ordering remains authoritative and deterministic as required by the owning application query.
5. Flutter does not reorder a partial source-entry page and claim it represents the complete sibling set.

### 66.6 No screen-shaped bridge snapshots

The bridge must not introduce DTOs such as:

```text
SourcesPageDto
JobsScreenDto
SelectedRootWithHierarchyDto
RootAndAllChildrenDto
```

Flutter composes presentation state from focused authoritative snapshots. Bridge contracts remain application-oriented and reusable across responsive layouts.

### 66.7 `SourcesBridge` operations

Phase 001 `SourcesBridge` conceptually exposes:

```text
ListLibraryRoots(request)
GetLibraryRoot(libraryRootId)

AddLocalLibraryRoot(selection)
AddLocalLibraryRootAndScan(selection)
RemoveLibraryRoot(libraryRootId)

ListSourceEntryChildren(request)
GetSourceEntry(sourceEntryId)

StartLibraryScan(libraryRootId)
StartLibraryScanAll()
```

Every application operation returns `BridgeResult<T>` according to Sections 9–10. Expected workflow/domain outcomes remain typed `Success(T)` values; unexpected application failures remain `Failure(ApplicationErrorDto)`.

### 66.8 Root queries

Conceptually:

```text
ListLibraryRoots(ListLibraryRootsRequestDto)
    -> BridgeResult<LibraryRootPageDto>

GetLibraryRoot(libraryRootId)
    -> BridgeResult<LibraryRootDto>
```

`ListLibraryRootsRequestDto` contains only governed bounded offset/page-size input. Phase 001 does not publish arbitrary sort/filter expressions.

### 66.9 Add local library root

Conceptually:

```text
AddLocalLibraryRoot(LocalFilesystemRootSelectionDto)
    -> BridgeResult<AddLocalLibraryRootResultDto>
```

Typed successful outcomes are equivalent to:

```text
Added(root: LibraryRootDto)
AlreadyConfigured(existingLibraryRootId)
OverlapsExisting(existingLibraryRootId, relationship)
```

`relationship` projects the provider/application-owned overlap vocabulary from SPEC-BE-011/SPEC-BE-013. Flutter never derives this relation by comparing selected path strings.

`AlreadyConfigured` and `OverlapsExisting` are expected non-mutating outcomes, not infrastructure/application failures.

Repeating the exact same validated selection is replay-safe: it returns `AlreadyConfigured(existingLibraryRootId)` without creating a duplicate root, mutating the existing root, or reporting a second creation.

### 66.10 Add local library root and scan

Conceptually:

```text
AddLocalLibraryRootAndScan(LocalFilesystemRootSelectionDto)
    -> BridgeResult<AddLocalLibraryRootAndScanResultDto>
```

Typed successful outcomes are equivalent to:

```text
AddedAndScanAdmitted(
    root: LibraryRootDto,
    operationHandle: OperationHandleDto
)

AddedButScanNotAdmitted(
    root: LibraryRootDto,
    childIssue: LibraryScanChildAdmissionIssueDto
)

AlreadyConfigured(existingLibraryRootId)

OverlapsExisting(
    existingLibraryRootId,
    relationship
)
```

The DTO union preserves SPEC-BE-013's two durable boundaries:

```text
root commit
    ↓
child scan admission attempt
```

`AddedButScanNotAdmitted` therefore includes the committed root and must not be translated into a failure shape suggesting root creation rolled back.

The child issue is the closed typed union:

```text
LibraryScanChildAdmissionIssueDto
├── AlreadyScanning(activeJobRunId, activeScanRunId)
└── AdmissionFailure(applicationError: ApplicationErrorDto)
```

It is never a free-form reason string or raw runtime/provider failure.

After a transport-ambiguous `AddLocalLibraryRootAndScan` result, Flutter must not blindly replay the composite workflow. It may replay only `AddLocalLibraryRoot` with the exact same selection to establish the authoritative root identity, then query Sources and Jobs. Only when authoritative state shows no child admission may it issue an explicit `StartLibraryScan` request.

### 66.11 Single-root scan admission

Conceptually:

```text
StartLibraryScan(libraryRootId)
    -> BridgeResult<StartLibraryScanResultDto>
```

Typed successful outcomes:

```text
Admitted(operationHandle: OperationHandleDto)

AlreadyScanning(
    libraryRootId,
    activeJobRunId,
    activeScanRunId
)
```

`AlreadyScanning` creates no second `JobRun` or `ScanRun`.

### 66.12 Scan All admission

Conceptually:

```text
StartLibraryScanAll()
    -> BridgeResult<StartLibraryScanAllResultDto>
```

Typed successful outcomes:

```text
Admitted(
    operationHandle: OperationHandleDto,
    admittedRoots,
    exclusions
)

NothingEligible(exclusions)
```

Rules:

1. Admitted-root and exclusion entries are strongly typed and bounded.
2. Partial admission is still successful admission.
3. Exclusions that affect the accepted job are durable operation facts and therefore also appear in authoritative `LibraryScanJobDetailDto`; the command response is not their sole record.
4. `NothingEligible` creates no empty job.
5. Existing scans are not silently queued behind or absorbed into a new Scan All job.

The admitted/excluded target vocabulary is:

```text
LibraryScanTargetExclusionDto
├── AlreadyScanning(libraryRootId, activeJobRunId, activeScanRunId)
├── NoLongerConfigured(libraryRootId)
└── InvalidConfiguration(libraryRootId, applicationError: ApplicationErrorDto)
```

Initial Scan All normally uses `AlreadyScanning` and `InvalidConfiguration`; retry revalidation may additionally use `NoLongerConfigured`.

### 66.13 Root removal result

Conceptually:

```text
RemoveLibraryRoot(libraryRootId)
    -> BridgeResult<RemoveLibraryRootResultDto>
```

Typed successful outcomes:

```text
Removed

RootHasActiveScan(
    libraryRootId,
    jobRunId,
    scanRunId,
    owningJobRootCount
)
```

`Removed` means Argus configuration/current indexed state was removed. It never means user filesystem content was deleted or modified.

`RootHasActiveScan` is an expected non-mutating coordination outcome used by the FE-008 Cancel Scan & Remove workflow.

`owningJobRootCount` is the bounded authoritative size of the owning LibraryScan scope. A value greater than one allows the UI to disclose that job-scoped cancellation may stop work for other roots; the bridge does not imply nonexistent root-scoped cancellation.

The mutation response does not include an updated root-list snapshot; Flutter reconciles through authoritative Sources queries.

### 66.14 Source hierarchy queries

Conceptually:

```text
ListSourceEntryChildren(ListSourceEntryChildrenRequestDto)
    -> BridgeResult<SourceEntryChildrenPageDto>
```

The request contains:

```text
libraryRootId
parentSourceEntryId nullable
cursor nullable
pageSize
```

`parentSourceEntryId = null` addresses direct root children as governed by SPEC-BE-013.

One entry detail query is exposed:

```text
GetSourceEntry(sourceEntryId)
    -> BridgeResult<SourceEntryDetailDto>
```

Phase 001 exposes no whole-tree materialization query, source-entry search, or arbitrary hierarchy filter API.

### 66.15 Sources expected-outcome boundary

The following expected states are represented through typed successful result unions rather than automatically becoming `ApplicationErrorDto`:

- already configured root;
- provider-verifiable overlap;
- already scanning;
- Scan All with no eligible roots;
- scan admission not accepted after an Add & Scan root commit;
- root removal blocked by current scan ownership.

Actual validation, runtime, persistence, stale-identity, provider, or internal failures continue through canonical application-error semantics where the owning backend contract defines them as failures.

### 66.16 `JobsBridge` operations

Phase 001 `JobsBridge` conceptually exposes:

```text
ListJobs(request)
GetJob(jobRunId)
CancelJob(jobRunId)
RetryJob(jobRunId)
```

`ResumeJob` remains available to the generic backend `JobsService` when supported by an operation, but Phase 001 does not expose it through the bridge because no bridged Phase 001 operation is resumable.

A future phase may activate `ResumeJob` additively when a real resumable product workflow exists.

### 66.17 Jobs list query

Conceptually:

```text
ListJobs(ListJobsRequestDto)
    -> BridgeResult<JobSummaryPageDto>
```

The request contains one closed Phase 001 scope union:

```text
ListJobsScopeDto
- Active
- RecentTerminal(offset, pageSize)
```

The bridge does not publish arbitrary operation filters, lifecycle filters, text search, caller-selected sorting, or generic expression objects.

### 66.18 `JobSummaryDto`

A bounded list-row projection is separate from full detail:

```text
JobSummaryDto
- jobRunId
- operationType
- state
- phase nullable
- createdAt
- startedAt nullable
- terminalAt nullable
- cancellationRequested
- safeContextSummary nullable
```

This projection is sufficient for:

- Jobs Active rows;
- Recent terminal history rows;
- the shell active-job indicator.

`ListJobs` does not eagerly return full operation-specific job detail for every row.

For shell behavior, `totalCount` plus the bounded Active items are sufficient to distinguish zero, exactly one, and multiple active jobs without defining a second backend authority solely for shell presentation.

### 66.19 Authoritative job detail

Conceptually:

```text
GetJob(jobRunId)
    -> BridgeResult<JobDetailDto>
```

Composition:

```text
JobDetailDto
- job: JobRunDto
- operationDetail: OperationDetailDto
```

Generic execution projection:

```text
JobRunDto
- jobRunId
- operationType
- state
- phase nullable
- completedUnits nullable
- totalUnits nullable
- statusKey nullable
- createdAt
- queuedAt nullable
- startedAt nullable
- terminalAt nullable
- cancellationRequested
- controls: JobControlAvailabilityDto
- boundedTerminalFailure nullable
```

Exact timestamp field grouping is an implementation representation choice; the semantic facts above are fixed.

`boundedTerminalFailure`, when present, is constructed from sanitized application-level failure information. Raw Rust/native/provider error chains do not cross.

### 66.20 Job control availability

Phase 001 projects explicit backend-authoritative control availability:

```text
JobControlAvailabilityDto
- canCancel
- canRetry
```

Rules:

1. Flutter does not infer control availability from `state` or `operationType`.
2. `canCancel` becomes false when cancellation has already been durably requested or cancellation is otherwise no longer available.
3. `canRetry` reflects the operation capability plus current authoritative retry constraints.
4. For LibraryScan, a historical run that already has its one direct retry successor has `canRetry = false`.
5. Phase 001 publishes no `canResume` because no bridged operation is resumable.
6. A future resumable capability may add `canResume` append-only together with an activated `ResumeJob` bridge operation.

### 66.21 Typed operation-specific job detail

Generic job detail composes one closed typed operation-detail union:

```text
OperationDetailDto
- LibraryScan(LibraryScanJobDetailDto)
- future typed variants
```

The Phase 001 LibraryScan variant includes typed projections for:

```text
requested root summaries
admitted root summaries
typed admission exclusions
per-root ScanRun projections
scan-specific structured progress
historical root display snapshots containing `displayName` and bounded `safeLocationDisplay`
retrySourceJobRunId nullable
retrySuccessorJobRunId nullable
```

No arbitrary JSON/map extension bag is permitted as the primary extensibility mechanism.

Historical LibraryScan detail must remain intelligible after current root removal and therefore consumes the durable historical display snapshots owned by SPEC-BE-013 instead of requiring live Sources entities.

### 66.22 Linear retry relationship

SPEC-BE-013 owns the Phase 001 LibraryScan rule that one execution attempt may have at most one direct retry successor.

The bridge projects that authoritative relationship through:

```text
LibraryScanJobDetailDto.retrySourceJobRunId?
LibraryScanJobDetailDto.retrySuccessorJobRunId?
```

Rules:

1. Retry never reopens or mutates the historical source `JobRun`.
2. A source run has zero or one direct retry successor, never multiple branches.
3. A later Retry is initiated from the latest attempt, producing a linear attempt chain.
4. The source/successor relationship uses ordinary `JobRunId` identities; no logical `JobId` is introduced.
5. The successor link is durable authoritative history and is queryable after a lost mutation response.

### 66.23 Cancel control result

Conceptually:

```text
CancelJob(jobRunId)
    -> BridgeResult<CancelJobResultDto>
```

Typed successful outcomes:

```text
CancellationRequested
NoLongerCancellable
```

`CancellationRequested` means durable cancellation intent was accepted. It does not mean the execution has reached terminal `Cancelled`.

`NoLongerCancellable` is the expected race where current authoritative state changed after the UI rendered the control.

Neither outcome returns a replacement `JobDetailDto`; Flutter reconciles current lifecycle truth through `GetJob` / `ListJobs`.

### 66.24 Retry control result

Conceptually:

```text
RetryJob(jobRunId)
    -> BridgeResult<RetryJobResultDto>
```

Typed successful outcomes:

```text
Admitted(operationHandle: OperationHandleDto)
AlreadyRetried(existingJobRunId)
NotAdmitted(reason: RetryNotAdmittedReasonDto)

RetryNotAdmittedReasonDto
├── SourceRunNotTerminal
├── OperationNotRetryable
└── NoEligibleTargets(exclusions: LibraryScanTargetExclusionDto[])
```

Rules:

1. `Admitted` returns the new canonical execution identity.
2. `AlreadyRetried` reports the existing direct successor and creates no second branch.
3. `NotAdmitted` means no new `JobRun` was created.
4. Retry reasons/exclusions are strongly typed and bounded; they are not arbitrary strings/maps.
5. Partial target admission is `Admitted`; durable exclusions belong to the new `LibraryScanJobDetailDto`.
6. Unexpected application failures still use `BridgeResult.Failure(ApplicationErrorDto)`.

### 66.25 Ambiguous Retry recovery

Retry has identity consequences, so the bridge/frontend contract must support recovery without blind mutation replay.

If the mutation transport outcome is unknown:

```text
RetryJob(oldJobRunId)
    ↓ response lost/uncertain
GetJob(oldJobRunId)
    ↓
retrySuccessorJobRunId present
    -> new execution identity established

retrySuccessorJobRunId absent
    -> no admission is yet established by that query
```

If a deliberate subsequent `RetryJob(oldJobRunId)` races with an already-created successor, the typed `AlreadyRetried(existingJobRunId)` outcome returns the same authoritative identity rather than creating another execution branch.

This design uses existing Argus execution identities and does not add client-generated idempotency tokens solely for Phase 001 retry transport.

### 66.26 Mutation/query authority

Sources and Jobs mutation responses establish only the explicit result facts defined by their result unions.

They do not become competing mutable snapshot channels.

Representative authoritative reconciliation remains:

```text
mutation accepted / expected outcome
    ↓
focused query
    ↓
authoritative current snapshot
```

Examples:

- Add/remove root -> `ListLibraryRoots` / `GetLibraryRoot` as needed;
- Cancel -> `GetJob` / `ListJobs`;
- Retry -> new identity from the result, followed by `GetJob(newJobRunId)`;
- ambiguous Retry -> old `GetJob` relationship reconciliation first.

### 66.27 Phase 001 runtime event payloads

All Phase 001 notifications continue through the one unified runtime event stream from Section 32.

The active new payload variants are:

```text
JobStateChangedDto
JobProgressDto
LibraryRootsChangedDto
LibraryRootChangedDto
SourceEntriesChangedDto
```

No Sources-specific or Jobs-specific native stream is created.

### 66.28 `LibraryRootsChangedDto`

Conceptually:

```text
LibraryRootsChangedDto
```

No feature snapshot payload is carried.

It announces that configured root-list membership or authoritative ordering may have changed. Consumers reconcile through `ListLibraryRoots`.

### 66.29 `LibraryRootChangedDto`

Conceptually:

```text
LibraryRootChangedDto
- libraryRootId
```

It announces that one root projection may have changed, including availability, last-scan, active-scan ownership, or another exposed root-projection fact.

It does not include `LibraryRootDto`.

### 66.30 `SourceEntriesChangedDto`

Conceptually:

```text
SourceEntriesChangedDto
- libraryRootId
- scope: SourceEntriesChangeScopeDto

SourceEntriesChangeScopeDto
├── RootChildren
├── EntryChildren(parentSourceEntryId)
└── EntireRootHierarchy
```

Rules:

1. `RootChildren` invalidates the direct configured-root child page.
2. `EntryChildren` invalidates the direct child page of exactly one source entry.
3. `EntireRootHierarchy` requires broader loaded-hierarchy reconciliation for the root.
4. Coalescing may broaden narrow invalidations to `EntireRootHierarchy`; it must never narrow or misrepresent affected scope.
5. The event carries no `SourceEntryDto` collection or complete tree snapshot.

### 66.31 Job and Sources event authority separation

A LibraryScan can emit/record notifications for distinct authoritative projections:

```text
job lifecycle/control state changed
    -> JobStateChangedDto

job generic progress changed
    -> JobProgressDto

root projection changed
    -> LibraryRootChangedDto

source graph changed
    -> SourceEntriesChangedDto
```

These are not competing state channels.

Sources must not infer generic job lifecycle from `LibraryRootChangedDto`. Jobs must not reconstruct root/source state from `JobStateChangedDto`.

### 66.32 Sequence gaps and runtime replacement

The sequencing contract from Sections 48–49 remains unchanged.

On a detected gap, consumers perform the smallest safe authoritative refresh rather than attempting to replay or reconstruct missing state transitions.

Representative Phase 001 refreshes are:

```text
open job detail
    -> GetJob(jobRunId)

Jobs landing / shell active summary
    -> relevant ListJobs scope

root list
    -> ListLibraryRoots

root detail
    -> GetLibraryRoot(libraryRootId)

hierarchy
    -> relevant child query, or broader loaded hierarchy refresh when narrow scope is not reliable
```

A changed `runtimeInstanceId` invalidates event-continuity assumptions entirely. Sequence numbers are never compared across runtime generations.

### 66.33 Backpressure and progress semantics

Phase 001 remains compatible with bounded best-effort event delivery.

Consequences:

- compatible progress events may be coalesced;
- repeated invalidations may be coalesced;
- consumers do not assume one event per source entry, persistence commit, or lifecycle transition;
- `JobProgressDto` publishes no backend percentage;
- unknown totals remain unknown;
- no weighted cross-phase or cross-root percentage exists;
- terminal correctness depends on authoritative queries, never final-event delivery.

LibraryScan-specific root/entry counters and per-root progress facts belong to typed authoritative `LibraryScanJobDetailDto`, not to a growing generic event union.

### 66.34 Explicit mapping rules

Phase 001 mappings remain deterministic boundary translations:

```text
LibraryRootProjection
    -> LibraryRootDto

SourceEntryProjection
    -> SourceEntryDto / SourceEntryDetailDto

JobRun / JobDetail
    -> JobRunDto / JobDetailDto

OperationDetail::LibraryScan
    -> OperationDetailDto::LibraryScan(...)

application typed workflow result
    -> corresponding typed bridge result union
```

Bridge mapping must not:

- perform overlap detection;
- canonicalize filesystem paths into source identity;
- calculate root availability;
- derive job control availability;
- derive job terminal aggregation;
- derive retry eligibility or retry-chain semantics;
- rebuild source hierarchy;
- query SQLite directly;
- reinterpret provider/native failures.

Those facts come from their owning application/runtime/provider contracts.

### 66.35 Privacy and security activation rules

In addition to Section 56, Phase 001 bridge DTO/event tests must prove that no response/event leaks:

- provider-owned root locators;
- source locator keys;
- native filesystem identity;
- canonicalization internals;
- source fingerprints used for backend identity;
- SQL/database identifiers;
- raw native/provider errors;
- arbitrary persisted absolute paths;
- ROM/file contents.

The native picker-selected path is permitted only as request input in `LocalFilesystemRootSelectionDto` because the backend requires the selected native location to validate/access the user-authorized root.

Historical presentation uses bounded backend-produced safe display snapshots.

### 66.36 Active Phase 001 DTO catalog

Phase 001 requires at least the concrete transport concepts below, plus focused supporting enums/value DTOs required by their fields and typed result variants:

```text
OperationHandleDto

LocalFilesystemRootSelectionDto

LibraryRootDto
LibraryRootPageDto
LibraryRootLastScanStatusDto
LibraryScanChildAdmissionIssueDto
LibraryScanTargetExclusionDto
SourceEntryDto
SourceEntryDetailDto
SourceEntryChildrenPageDto

AddLocalLibraryRootResultDto
AddLocalLibraryRootAndScanResultDto
StartLibraryScanResultDto
StartLibraryScanAllResultDto
RemoveLibraryRootResultDto

JobSummaryDto
JobSummaryPageDto
JobRunDto
JobDetailDto
JobControlAvailabilityDto
OperationDetailDto
LibraryScanJobDetailDto

CancelJobResultDto
RetryJobResultDto
RetryNotAdmittedReasonDto

JobStateChangedDto
JobProgressDto
LibraryRootsChangedDto
LibraryRootChangedDto
SourceEntriesChangedDto
SourceEntriesChangeScopeDto
```

Phase 001 does not generate empty DTO/API families for future games, metadata, hashing, artwork, verification, or resumable-operation functionality.

### 66.37 DTO contract tests

Required bridge contract coverage includes:

- stable `JobRunId`, `LibraryRootId`, `SourceEntryId`, and `ScanRunId` projection;
- `OperationHandleDto.jobRunId` maps exactly to canonical `JobRunId`;
- no second background-operation identity exists;
- root availability/last-scan/active-scan dimensions retain their independent semantics/nullability;
- root last-scan mapping covers `Complete`, `Partial`, `Unavailable`, `Cancelled`, `Failed`, `Abandoned`, and nullable `NeverScanned` semantics without deriving availability;
- source row/detail DTO separation;
- source cursors remain opaque;
- all typed workflow-result variants map exhaustively;
- Add-and-Scan child issues, Scan All/retry exclusions, and retry-not-admitted reasons map exhaustively without free-form strings;
- active-root removal maps `owningJobRootCount` without implying root-scoped cancellation;
- every generic job lifecycle state maps correctly, including `CompletedWithIssues`, `Interrupted`, and `Abandoned`;
- control availability is mapped from backend authority rather than recomputed in the bridge;
- typed `OperationDetailDto` mapping has no arbitrary extension bag;
- terminal failure projection remains sanitized and bounded.

### 66.38 Sources workflow-result tests

Bridge-level tests cover at least:

```text
AddLocalLibraryRoot
- Added
- AlreadyConfigured
- OverlapsExisting

AddLocalLibraryRootAndScan
- AddedAndScanAdmitted
- AddedButScanNotAdmitted
- AlreadyConfigured
- OverlapsExisting

StartLibraryScan
- Admitted
- AlreadyScanning

StartLibraryScanAll
- admitted all
- partial admission
- NothingEligible

RemoveLibraryRoot
- Removed
- RootHasActiveScan
```

Tests must prove these expected typed outcomes remain distinct from `ApplicationErrorDto` failure.

### 66.39 Job-control and retry tests

Bridge-level tests cover at least:

```text
CancelJob
- CancellationRequested
- NoLongerCancellable

RetryJob
- Admitted
- AlreadyRetried
- NotAdmitted
```

Retry-specific contract evidence must prove:

1. an admitted Retry creates a new `JobRunId`;
2. source and successor identities are linked authoritatively;
3. one source run cannot acquire two direct retry successors;
4. repeated Retry against the same source reports the existing successor;
5. querying the source detail after a lost response exposes the same successor;
6. further Retry is initiated from the latest attempt and creates the next link in the linear chain;
7. removed/ineligible original targets continue to obey SPEC-BE-013 revalidation/exclusion rules.

### 66.40 Runtime event tests

The unified runtime event contract must prove:

- every Phase 001 variant retains common `runtimeInstanceId`, `sequence`, and `occurredAt` envelope metadata;
- `JobStateChangedDto` carries no full job snapshot or terminal error snapshot;
- `JobProgressDto` carries no percentage;
- `LibraryRootsChangedDto` carries no root list snapshot;
- `LibraryRootChangedDto` carries no root snapshot;
- `SourceEntriesChangedDto` carries no source-entry collection;
- `SourceEntriesChangedDto` maps `RootChildren`, `EntryChildren`, and `EntireRootHierarchy` exactly and coalescing only broadens scope;
- sequence gaps remain observable;
- runtime replacement resets sequence interpretation;
- dropped/coalesced notifications do not affect authoritative query correctness.

### 66.41 Architecture tests

Phase 001 must continue to enforce the dependency direction from Sections 58–59.

In particular:

```text
argus-domain          !-> argus-bridge
argus-application     !-> argus-bridge
argus-infrastructure  !-> public bridge DTO contracts

argus-bridge
    -> application/runtime contracts
    -> explicit DTO mapping
```

Flutter feature code remains isolated from generated FRB bindings behind the project-owned client/adapter boundary governed by SPEC-FE-003.

### 66.42 Phase 001 acceptance criteria

The Phase 001 amendment is satisfied when:

1. `SourcesBridge` and `JobsBridge` are the only new capability-oriented bridge façades required by Phase 001.
2. `LibraryBridge` remains unactivated until logical game-library capability exists.
3. `OperationHandleDto` uses canonical `jobRunId` and no second operation identity is published.
4. Native local-folder selection is request-only and Flutter never constructs provider-owned locator identity.
5. Root/source DTOs preserve SPEC-BE-013 authoritative projection boundaries without screen-shaped aggregate DTOs.
6. Root, source-child, and Jobs paging preserve their distinct governed semantics.
7. Expected Sources workflow states map to typed successful unions rather than generic application failure.
8. `AddLocalLibraryRootAndScan` preserves the committed-root/typed-child-admission split, and ambiguous composite outcomes reconcile through replay-safe root creation plus authoritative queries rather than blind composite replay.
9. root removal exposes `RootHasActiveScan` with owning-job scope as an expected non-mutating outcome, supports whole-job cancellation disclosure, and never implies filesystem deletion.
10. `ListJobs` uses only the closed `Active` and `RecentTerminal` scopes required by Phase 001.
11. `GetJob` returns generic `JobRunDto` plus typed `OperationDetailDto`.
12. LibraryScan is the only active operation-detail variant and no arbitrary JSON extension bag is introduced.
13. control availability is backend-authoritative and Phase 001 exposes `canCancel` / `canRetry` but no `canResume`.
14. Phase 001 `JobsBridge` does not expose unused `ResumeJob`.
15. Cancel distinguishes durable cancellation request from terminal cancellation.
16. Retry creates new execution identity and returns typed `Admitted`, `AlreadyRetried`, or `NotAdmitted` outcomes with the exact Phase 001 reason/exclusion vocabulary.
17. one LibraryScan execution has at most one direct retry successor and retry chains remain linear.
18. ambiguous Retry recovery can establish the successor through authoritative job detail without blind duplicate replay.
19. the inactive Phase 000 per-transition operation-event reservation is replaced before first activation by `JobStateChangedDto` plus `JobProgressDto`.
20. Sources adds only the minimal typed invalidations `LibraryRootsChangedDto`, `LibraryRootChangedDto`, and explicitly scoped `SourceEntriesChangedDto`; generic job lifecycle/progress remains runtime-owned.
21. all Phase 001 notifications remain on the one unified runtime event stream.
22. events remain notification-first; queries repair dropped/coalesced event uncertainty.
23. no backend progress percentage or weighted overall LibraryScan percentage is published.
24. request/response DTOs and events obey SPEC-BE-003 privacy/redaction rules.
25. generated binding details remain confined to the bridge/client adapter boundary.
26. no speculative games, metadata, hashing, artwork, verification, Resume, search/filter, or whole-tree bridge surface is added.

### 66.43 Explicit Phase 001 exclusions

This amendment does not activate:

- logical `LibraryBridge`;
- game/library-content DTOs;
- metadata-provider or metadata-resolution DTOs;
- hashing/transformation DTOs beyond any already governed cross-cutting bridge need;
- artwork DTOs;
- RetroAchievements/verification DTOs;
- source-entry search/filter;
- arbitrary Jobs filtering/sorting/search;
- `ResumeJob` or `canResume`;
- generic arbitrary-JSON operation detail;
- separate Sources/Jobs native streams;
- backend-generated progress percentages;
- whole source-tree snapshots;
- job-history deletion/retention UI contracts;
- client-generated retry idempotency identities.

## 67. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [PHASE-001 — Local Sources and Indexing](../../phases/phase-001-local-sources-and-indexing.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-006 — Minimal Domain Event Bus](spec-be-006-minimal-domain-event-bus.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-009 — Application Service Contracts](spec-be-009-application-service-contracts.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-BE-013 — Library Source Management, Scan Operations, and Source Projections](spec-be-013-library-source-management-scan-operations-and-source-projections.md)
- [SPEC-FE-008 — Sources and Library Folder Management](../frontend/spec-fe-008-sources-and-library-folder-management.md)
- [SPEC-FE-009 — Jobs and Background Operation Presentation](../frontend/spec-fe-009-jobs-and-background-operation-presentation.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
- [Backend Specifications Index](README.md)
