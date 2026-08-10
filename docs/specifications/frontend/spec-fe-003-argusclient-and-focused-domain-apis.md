# ArgusClient and Focused Domain APIs

**Document ID:** SPEC-FE-003  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-10  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-007, SPEC-BE-008, SPEC-BE-009, SPEC-FE-001, SPEC-FE-002, SPEC-X-001, CONV-REPO-001, CONV-FLUTTER-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the Flutter-side backend client boundary for Argus ROM Toolkit.

It translates the bridge, runtime, error, application-service, frontend-structure, and frontend-state contracts into one typed Dart anti-corruption layer composed of:

- one application-lifetime root `ArgusClient`;
- narrow focused application APIs;
- immutable frontend read models;
- typed frontend identifiers;
- typed application and transport failures;
- one mapped runtime-event stream;
- centralized runtime-generation, transport, mapping, and connectivity policy;
- focused API test seams independent of generated bridge bindings.

The client boundary exists so Flutter application and feature code can reason entirely in Argus-owned frontend concepts without depending on `flutter_rust_bridge`, bridge DTOs, generated transport result types, Rust implementation structure, or native communication mechanics.

The central invariant is:

> **The Argus Flutter client is a typed anti-corruption boundary around the native backend: one root owns connectivity and cross-cutting transport policy, focused APIs expose stable application capabilities, all transport representations are translated before feature use, runtime/event generations remain explicit, and neither failures nor uncertain command outcomes are silently reinterpreted into false frontend state.**

## 2. Responsibilities

This specification owns frontend rules for:

- the root `ArgusClient` role;
- focused API boundaries and naming;
- Phase 000 focused API scope;
- client and focused-API lifetimes;
- client initialization semantics;
- root versus feature dependency responsibilities;
- bridge DTO to frontend model mapping;
- typed identifier conversion;
- focused API query and mutation semantics;
- future long-running operation-handle semantics;
- typed frontend application failures;
- typed frontend transport failures;
- preservation of backend error dimensions;
- runtime snapshot mapping;
- runtime-generation identity handling;
- runtime-bound recovery invocation;
- the single client-owned native event connection;
- typed frontend runtime-event mapping;
- stream sequencing and runtime replacement preservation;
- event transport/reconnect semantics;
- timeout and cancellation ownership;
- automatic retry restrictions;
- Riverpod-independent client contracts;
- focused API provider projection;
- test fakes and adapter verification;
- generated bridge leakage prevention.

## 3. Non-Responsibilities

This specification does not define:

- the Flutter project directory architecture, owned by SPEC-FE-001;
- Riverpod provider syntax, controller state, or feature async-state ownership, owned by SPEC-FE-002;
- Rust application-service semantics, owned by SPEC-BE-009;
- bridge DTO serialization contracts, owned by SPEC-BE-008;
- backend error-code meaning, logging, diagnostics, or trace creation, owned by SPEC-BE-003;
- backend runtime scheduling, operation admission, event queueing, or cancellation semantics, owned by SPEC-BE-004;
- startup/recovery backend semantics, owned by SPEC-BE-007;
- exact route paths or shell navigation, owned by SPEC-FE-004;
- startup/recovery screen presentation, owned by SPEC-FE-005;
- exact appearance-settings controller/presentation behavior, owned by SPEC-FE-006;
- design-system components or accessibility presentation, owned by SPEC-FE-007;
- exact `flutter_rust_bridge` package version or generated API syntax;
- a frontend persistence/cache subsystem;
- speculative APIs for capabilities not yet implemented by the backend.

The specification preserves backend contracts; it does not redefine them.

## 4. Governing Principles

The client boundary follows these rules:

1. Flutter has exactly one production backend-connectivity root.
2. Features depend on the smallest focused API they need rather than the root client by convenience.
3. Generated bridge bindings, DTOs, and transport results remain private infrastructure.
4. Focused APIs use application-oriented Dart contracts.
5. Client contracts are independent of Riverpod and Flutter widgets.
6. Queries return immutable snapshots, not live backend objects.
7. Mutations do not fabricate authoritative response state that the backend did not return.
8. Typed identifiers replace serialization-friendly bridge primitives before feature use.
9. Application and transport failures remain distinct.
10. Backend `ApplicationError` dimensions are preserved rather than reinterpreted.
11. Startup failure remains inspectable runtime state when transport is functioning.
12. Runtime identity remains explicit across recovery and event operations.
13. Runtime-bound actions are never silently retargeted to a replacement runtime.
14. One native event connection is mapped into one typed frontend runtime-event stream.
15. Events remain best-effort notifications rather than authoritative state storage.
16. Sequence gaps and runtime replacement remain observable after mapping.
17. Transport reconnection does not erase uncertainty about missed state changes.
18. Mutations are never blindly retried after an ambiguous transport outcome.
19. Focused APIs are the ordinary frontend test substitution boundary.
20. The client surface grows only when backend application capabilities exist.

## 5. Layer Position

The client boundary sits between feature/application state and bridge transport:

```text
Flutter feature/controller
        ↓
focused API interface
        ↓
ArgusClient / bridge-backed API implementation
        ↓
bridge mapper / invocation infrastructure
        ↓
generated flutter_rust_bridge bindings
        ↓
Rust bridge services
        ↓
Rust application services/runtime
```

No layer above the client boundary requires generated bridge knowledge.

## 6. Root Client Architecture

Flutter has one root backend gateway:

```text
ArgusClient
```

The root owns shared backend-connectivity concerns that would otherwise be duplicated across feature APIs.

It is primarily a composition/infrastructure object rather than a feature-facing service locator.

## 7. Root-Owned Responsibilities

The root client owns or coordinates:

- generated binding access;
- native/backend host initialization;
- matched-contract compatibility validation required by SPEC-X-001;
- current runtime-generation identity awareness;
- common bridge invocation infrastructure;
- common application-failure mapping;
- common transport-failure mapping;
- shared typed-identifier/value mapping primitives;
- single native runtime-event connection;
- event-stream replacement across runtime generations;
- tracing/diagnostic correlation propagation available to Flutter;
- cross-cutting transport timeout policy where applicable;
- cross-cutting transport reconnect policy where applicable;
- safe retention of internal diagnostic context;
- focused API construction/composition.

The root does not own feature presentation state.

## 8. Focused API Architecture

The broader architecture defines focused APIs conceptually as:

```text
ArgusClient
├── runtime
├── library
├── games
├── jobs
├── settings
├── sources
├── diagnostics
└── events
```

Focused APIs represent stable application capabilities, not implementation modules.

## 9. Phase 000 Focused API Surface

Phase 000 implements only capabilities required by the foundation milestone:

```text
ArgusClient
├── runtime: RuntimeApi
├── settings: SettingsApi
├── diagnostics: DiagnosticsApi
└── events: EventsApi
```

The future `library`, `games`, `jobs`, and `sources` APIs are architectural reservations, not Phase 000 empty scaffolding requirements.

## 10. Why `RuntimeApi` Is Explicit

Runtime/startup/recovery is a real application capability in SPEC-BE-004, SPEC-BE-007, and SPEC-BE-008.

Therefore the Flutter client gives it an explicit `RuntimeApi` owner even though ARCH-001's shorthand focused-API list originally emphasized user-domain capabilities.

This does not create a new runtime abstraction. It is the frontend contract for existing runtime operations.

## 11. Focused APIs Are Not One Method Each

Do not create interfaces such as:

```text
GetSettingsApi
UpdateSettingsApi
RetryStartupApi
ExportDiagnosticsApi
```

A focused API groups cohesive operations that share vocabulary, models, identities, ownership, and test seams.

Likewise, do not combine unrelated capabilities into one giant miscellaneous client.

## 12. Capability Grouping Rule

An operation belongs to an existing focused API when:

- it is part of the same stable application capability;
- it uses that capability's primary vocabulary/models;
- its callers would reasonably substitute the same test seam;
- adding it does not turn the API into a generic cross-domain bucket.

Otherwise a new focused API or different owner is considered.

## 13. Feature Dependency Rule

Ordinary feature/application controllers depend on focused APIs:

```text
AppearanceSettingsController → SettingsApi
StartupController            → RuntimeApi
Recovery diagnostics         → DiagnosticsApi
Event coordinator            → EventsApi
```

They do not receive `ArgusClient` merely so they can retrieve a nested API.

## 14. Root Client Is Not a Service Locator

This is discouraged:

```text
SettingsController
    ↓
ArgusClient
    ↓
client.settings
```

Preferred:

```text
SettingsController
    ↓
SettingsApi
```

`app/bootstrap` and composition providers may know the full root client because composition is their responsibility.

## 15. Riverpod Independence

The following are ordinary Dart contracts:

```text
ArgusClient
RuntimeApi
SettingsApi
DiagnosticsApi
EventsApi
RuntimeState
AppearanceSettings
ClientFailure
```

They do not depend on:

- `Provider`;
- `Ref`;
- `AsyncValue`;
- widget types;
- `BuildContext`.

Riverpod exposes these contracts to application/feature code but does not define them.

## 16. Production Provider Projection

SPEC-FE-002 provider composition conceptually exposes:

```text
argusClientProvider
    ├── runtimeApiProvider
    ├── settingsApiProvider
    ├── diagnosticsApiProvider
    └── eventsApiProvider
```

Focused API providers are narrow projections from the root client.

They do not add hidden caching, retries, business behavior, or feature state.

## 17. Client Lifetime

The production `ArgusClient` is application-lifetime.

Its focused API objects normally share that lifetime because they are lightweight capability views/adapters over one backend connection.

This does not make feature controller state application-lifetime.

```text
application lifetime
→ ArgusClient / focused APIs

feature/route lifetime
→ feature controllers and presentation state
```

## 18. Root Construction vs Initialization

Object construction and backend initialization are separate concepts.

Construction creates the frontend client infrastructure.

Initialization establishes a usable native/backend transport and obtains the initial runtime contract.

A constructor must not hide significant asynchronous startup work.

## 19. Initialization Contract

Conceptually:

```text
ArgusClient.initialize()
    → Future<RuntimeState>
```

Exact Dart naming may differ if the implementation has a dedicated factory/bootstrap method, but semantics are fixed.

Initialization performs the minimum root work required to:

1. make generated/native bridge transport usable;
2. validate required matched contract compatibility;
3. initialize/start the backend host through the root bridge entry point;
4. establish client infrastructure required for Phase 000 correctness;
5. return an authoritative mapped runtime snapshot.

## 20. Initialization Success Does Not Mean Runtime Ready

A successful client initialization means Flutter can use the returned runtime contract.

It does not imply the Rust runtime reached `Ready`.

Valid result:

```text
initialize()
→ RuntimeState.startupFailed(...)
```

This is an expected inspectable backend runtime outcome, not automatically a transport failure.

## 21. Initialization Transport Failure

If Flutter cannot establish or reliably use the native/backend transport, initialization fails with a typed transport failure.

Examples include:

- native library unavailable;
- generated binding unavailable/incompatible;
- unrecoverable marshalling failure;
- communication channel unusable;
- bridge contract cannot be interpreted safely.

This is distinct from a successfully reported `StartupFailed` runtime.

## 22. Focused API Async Contract

Focused asynchronous methods use normal Dart `Future<T>` semantics.

Conceptually:

```text
Future<AppearanceSettings> getAppearanceSettings()
Future<void> updateAppearanceSettings(AppearanceSettings settings)
Future<RuntimeState> getRuntimeState()
```

Failures use typed Dart asynchronous failure/error channels.

## 23. No Client `Result<T, E>` Layer

Argus does not introduce a parallel frontend result monad solely for focused client calls.

The client does not return:

```text
Future<Result<T, ClientFailure>>
```

by default.

This avoids nesting a second result abstraction inside `Future`, streams, and Riverpod `AsyncValue` while retaining typed failure values.

## 24. `BridgeResult` Never Leaves the Bridge Boundary

Generated or bridge-specific result contracts such as:

```text
BridgeResult<T>
```

are infrastructure details.

The bridge-backed client unwraps and maps them before any focused API result reaches feature/application code.

## 25. Query Semantics

Queries return immutable frontend snapshots.

A returned read model represents the authoritative result of that successful query at that moment.

It is not:

- a live backend object;
- a mutable proxy;
- a subscription;
- a backend entity reference;
- an automatically synchronized cache entry.

## 26. Mutation Semantics

A successful focused mutation means the backend mutation contract completed successfully according to its application semantics.

The client does not strengthen that contract by inventing response state.

If the backend returns no authoritative updated snapshot, the client must not fabricate one from the request.

## 27. Appearance Settings Example

SPEC-BE-008 defines:

```text
GetAppearanceSettings()
    → AppearanceSettingsDto

UpdateAppearanceSettings(...)
    → success/failure only
```

Therefore the focused API conceptually exposes:

```text
SettingsApi.getAppearanceSettings()
    → AppearanceSettings

SettingsApi.updateAppearanceSettings(settings)
    → void success
```

A successful update does not make the request object a new authoritative read snapshot by client fiat.

## 28. Authoritative Reconciliation After Mutation

Where the owning feature contract requires an authoritative refresh after mutation, the caller uses the focused read/event semantics defined for that capability.

For appearance settings, event-driven reconciliation and focused read behavior are owned by SPEC-FE-006 on top of this client contract.

## 29. Long-Running Operation Admission

Future long-running backend work follows SPEC-BE-004/SPEC-BE-008 admission semantics.

A focused operation that admits background work returns a typed frontend operation handle:

```text
startImport(...)
    → OperationHandle
```

The returned handle means the operation was admitted, not that work completed.

## 30. No Client-Side Await-Until-Finished Wrapper

A focused API must not turn a background admission contract into a single `Future` that waits for backend job completion merely for screen convenience.

Completion is observed through the jobs/query/event capability defined by the relevant specifications.

## 31. Model Mapping Pipeline

The canonical mapping direction is:

```text
Bridge DTO
    ↓
bridge/client mapper
    ↓
frontend client read model
    ↓ optional
feature presentation mapper
    ↓
UI model/widget
```

Bridge DTOs never enter feature code.

## 32. Mapping Responsibility

Client mapping may perform:

- representation conversion;
- typed identifier construction;
- enum/value mapping;
- scalar normalization required by the published contract;
- structural validation required to interpret a DTO safely;
- composition of bridge concepts into one client concept where semantics justify it.

It must not perform backend business rules.

## 33. Mapping Does Not Require Mechanical Duplication

Argus does not require an intermediate class for every transport class.

Avoid ceremonial chains such as:

```text
Dto
→ TransportModel
→ ClientModel
```

when the middle representation changes no semantics or ownership.

The transport/client separation is mandatory; additional mapping layers are semantic, not ceremonial.

## 34. Read Model Ownership

A read model is owned by the focused API that naturally produces it by default.

A model moves to a broader `core` owner only when:

- multiple focused APIs truly share the same stable concept; and
- no one API remains its natural semantic owner.

Do not create a global model bucket.

## 35. Typed Identifier Boundary

Serialization-friendly bridge identifiers stop at the client boundary.

Example:

```text
BridgeGameDto.gameId: String
    ↓
client mapper
    ↓
GameId
    ↓
feature/controller/widget
```

## 36. Required Typed Identifier Categories

When their backend capability exists, ordinary frontend code uses typed values such as:

```text
GameId
JobRunId
LibraryRootId
SourceEntryId
PlatformId
RuntimeInstanceId
```

Additional Argus identities follow the same rule.

## 37. Invalid Identifier Mapping

If a bridge value cannot be interpreted as a required typed frontend identifier, the client does not substitute an empty/default ID.

The mapping fails through the typed contract-mismatch/transport failure path because the transport representation cannot be interpreted safely.

## 38. Runtime Identity

`runtimeInstanceId` maps to a typed frontend:

```text
RuntimeInstanceId
```

The root client maintains awareness of the active runtime generation required for transport/event coordination.

Focused APIs do not keep independent competing runtime-generation authorities.

## 39. Runtime Snapshot Model

`RuntimeStateDto` maps to one immutable frontend runtime snapshot concept.

Conceptually:

```text
RuntimeState
- lifecycle
- runtimeInstanceId
- startupFailure
- availableRecoveryActions
- capabilities
```

The exact Freezed structure may use unions to encode valid lifecycle combinations more safely.

## 40. Runtime Lifecycle Values

The frontend preserves the backend lifecycle vocabulary:

```text
Uninitialized
Starting
Ready
StartupFailed
ShuttingDown
Stopped
```

Flutter must not derive lifecycle from incidental field presence.

## 41. Structural Runtime Modeling

A Freezed union is preferred when it materially prevents invalid combinations.

For example, a `startupFailed` variant may require the failure/recovery context that only exists in that phase.

However, the frontend structure must still preserve the backend lifecycle semantics rather than create a new frontend lifecycle taxonomy.

## 42. Startup Failure Model

Frontend startup failure composes the mapped application failure and typed startup/recovery context.

It does not duplicate:

- runtime identity owned by `RuntimeState`;
- backend application-error fields already owned by `ApplicationFailure`.

## 43. Recovery Actions Are Declarative

Mapped recovery actions describe currently available backend capabilities.

They do not include:

- localized UI text;
- icons;
- SQL;
- filesystem commands;
- executable closures;
- free-form implementation instructions.

Presentation maps recovery kinds to appropriate UI later in SPEC-FE-005.

## 44. Runtime-Bound Recovery

A recovery action exposed for runtime generation A remains bound to A.

Conceptually:

```text
RuntimeState(A)
    ↓
user selects action
    ↓
RuntimeApi operation(expectedRuntimeInstanceId: A)
```

If the active runtime has become B, the stale action must not be silently applied to B.

## 45. No Silent Retargeting

The client must never replace an expected runtime ID with the current runtime ID merely to make a recovery call succeed.

A stale action produces a typed rejection/application failure or triggers authoritative refresh according to the owning operation semantics.

## 46. Phase 000 `RuntimeApi`

Conceptually, Phase 000 requires runtime capabilities equivalent to:

```text
getRuntimeState()
    → RuntimeState

retryStartup(expectedRuntimeInstanceId)
    → RuntimeState

resetAppearanceSettings(expectedRuntimeInstanceId)
    → completion / authoritative runtime follow-up as required

shutdown()
    → completion
```

Exact method factoring may reflect strongly typed bridge operations while preserving these semantics.

## 47. Retry Returns an Authoritative Snapshot

The focused frontend semantic contract for startup retry is:

```text
retryStartup(expectedRuntimeInstanceId)
    → Future<RuntimeState>
```

If the bridge operation itself returns only acknowledgement, the bridge-backed adapter performs the required follow-up runtime read.

This keeps Flutter independent of minor bridge operation factoring.

## 48. Runtime Replacement Remains Visible

`retryStartup` does not hide runtime replacement.

The returned `RuntimeState` contains the new `RuntimeInstanceId` when a fresh runtime generation is created.

No frontend object may pretend retry restarted the same failed runtime.

## 49. Capability-Specific Recovery APIs

Argus avoids a stringly typed client method such as:

```text
executeRecoveryAction(String kind, Map payload)
```

Where a recovery capability has real semantics, expose a typed operation or typed request.

This preserves generation binding and compile-time discoverability.

## 50. Diagnostics Ownership

Non-mutating diagnostic/recovery capabilities belong to `DiagnosticsApi` when their semantics are diagnostic rather than runtime lifecycle mutation.

Phase 000 includes conceptually:

```text
exportDiagnostics(...)
getTechnicalDetails()
openDataDirectory()
```

Availability remains governed by the current runtime capability/recovery snapshot.

## 51. Existence of Method Does Not Mean Current Availability

A Dart method may exist because the application supports that capability in some runtime states.

The current authoritative `RuntimeState` determines whether the UI should offer it.

The backend validates the action again when invoked.

The client does not weaken that backend validation.

## 52. Typed Frontend Failure Hierarchy

Expected failures crossing a focused API use one sealed immutable frontend hierarchy:

```text
ClientFailure
├── ApplicationFailure
└── TransportFailure
```

The exact Freezed/sealed syntax follows SPEC-FE-002 and the pinned Dart toolchain.

## 53. Why Failures Are Separate

The distinction preserves SPEC-BE-008:

```text
ApplicationFailure
→ transport worked and Rust returned a structured application failure

TransportFailure
→ a reliable application result could not be delivered/interpreted
```

Feature code must be able to distinguish these cases without parsing text.

## 54. Application Failure Contract

`ApplicationErrorDto` maps to an immutable `ApplicationFailure` preserving:

```text
code
category
severity
recoverability
retryPolicy
messageKey
traceId
safeContext
```

No field is silently reinterpreted by the client.

## 55. Error Code Representation

Published backend error codes are extensible stable identifiers.

The frontend represents them as a typed value object conceptually named:

```text
ErrorCode
```

rather than a closed Dart enum containing the entire backend error catalog.

## 56. Why Error Codes Are Not a Giant Enum

This avoids creating a second authoritative copy of the backend error registry and permits compatible new codes to remain representable.

Features branch on specific codes only when the feature contract requires code-specific behavior.

Unknown codes still retain their broader typed error dimensions.

## 57. Typed Error Dimensions

Stable bounded error dimensions use typed Dart values/enums as appropriate:

```text
ErrorCategory
ApplicationSeverity
Recoverability
RetryPolicy
```

`TraceId` and `MessageKey` are also typed value concepts rather than interchangeable arbitrary strings in ordinary feature code.

## 58. Message Localization Boundary

The backend's `MessageKey` is preserved.

The client does not convert it into localized user-facing text.

Presentation/localization chooses the final message using the key and permitted safe context according to frontend presentation specifications.

## 59. Safe Context

Frontend safe context remains bounded.

It must not become a general:

```text
Map<String, dynamic>
```

transport for arbitrary backend data.

The frontend representation permits only the scalar/value classes allowed by SPEC-BE-003.

## 60. Safe Context Use

Feature/presentation code should use safe-context fields only when the backend error contract explicitly makes them relevant to presentation or diagnostics.

Safe context is not a hidden extension point for feature payloads.

## 61. Transport Failure Contract

Transport failures have their own frontend taxonomy.

Conceptually:

```text
TransportFailureKind
├── bridgeUnavailable
├── communicationFailed
├── serializationFailed
├── contractMismatch
└── unexpectedTransportFailure
```

The exact minimum distinguishable set may follow the pinned bridge integration while preserving the semantic separation from `ApplicationFailure`.

## 62. No Fabricated Application Error

A native/transport failure must not receive an invented backend `ErrorCode` or fabricated `ApplicationFailure` merely to unify presentation.

Transport uncertainty remains visible as transport uncertainty.

## 63. Raw Technical Errors Stay Internal

Focused API failures must not expose:

- raw FRB exception strings;
- native stack traces;
- channel implementation names;
- serialization payload dumps;
- raw Rust source chains;
- SQL;
- unsafe filesystem paths.

Internal diagnostic context may be retained inside approved client/observability infrastructure where safe.

## 64. No `toString()` Error Contract

This is prohibited:

```text
catch error
→ feature state = error.toString()
```

Raw/generated failures are translated at the bridge/client boundary into typed frontend failures.

## 65. Unexpected Client Adapter Failures

An unexpected adapter/programming failure must not be converted into fabricated success, empty state, or a backend application failure.

The client maps defensively to a typed transport/client fallback failure while recording appropriate internal diagnostics.

Programming defects still remain defects and should be test-detectable.

## 66. Defensive DTO Mapping

The matched generated bridge is trusted as part of one application distribution, but mapping still fails safely on representations the frontend cannot interpret.

Examples:

- invalid required ID;
- impossible required enum value;
- structurally inconsistent runtime snapshot;
- malformed required operation handle;
- incompatible generated-contract semantics.

## 67. Contract Mismatch Failure

A representation that cannot be interpreted safely becomes a typed contract/transport failure.

It is not silently defaulted.

Prohibited examples:

```text
unknown lifecycle → Ready
invalid ID → empty ID
invalid enum → first enum value
missing required state → fabricated default
```

## 68. Compatible Additive Information

Defensive mapping must preserve SPEC-X-001 compatibility rules.

Unknown information explicitly defined as compatible may be ignored when the generated contract/tooling supports that safely.

The distinction is:

```text
unknown compatible additive information
→ tolerate

information required to interpret known semantics safely but unreadable
→ typed failure
```

## 69. Client Compatibility Ownership

SPEC-X-001 owns bridge compatibility/version rules.

The client owns whatever matched-build validation is needed on Flutter startup to detect an unusable bridge contract before feature code begins consuming it.

The client does not invent runtime version negotiation beyond SPEC-X-001.

## 70. One Native Runtime Event Connection

SPEC-BE-008 exposes exactly one runtime event stream per runtime generation.

Production Flutter infrastructure therefore has:

```text
generated native runtime event stream
        ↓
ArgusClient
        ↓
EventsApi
        ↓
app-level event coordinator / derived consumers
```

There are no separate native streams for settings, startup, jobs, or future feature domains.

## 71. Focused Event Fan-Out Happens After Mapping

Multiple Dart consumers may observe projections/filters of the mapped frontend event stream.

That fan-out occurs after the one client-owned native subscription.

Feature providers do not open their own FRB event subscriptions.

## 72. `EventsApi` Contract

Conceptually:

```text
EventsApi.events
    → Stream<RuntimeEvent>
```

`RuntimeEvent` is an Argus-owned immutable frontend event type.

The stream is not a bridge DTO stream.

## 73. Frontend Runtime Event Envelope

The mapped frontend event preserves:

```text
RuntimeEvent
- runtimeInstanceId: RuntimeInstanceId
- sequence
- occurredAt
- payload: RuntimeEventPayload
```

These fields retain the backend semantics from SPEC-BE-004/SPEC-BE-008.

## 74. Frontend Event Payload Hierarchy

Conceptually:

```text
RuntimeEventPayload
├── runtimeStateChanged
├── startupFailed
├── operationStarted
├── operationProgress
├── operationCompleted
├── operationFailed
├── operationCancelled
├── appearanceSettingsChanged
└── future typed variants
```

The exact Phase 000 generated/client variants match implemented bridge events.

## 75. No Stringly Typed Event Bus

The client must not flatten event payloads into:

```text
eventName: String
payload: Map<String, dynamic>
```

Strongly typed event semantics remain available to Dart consumers.

## 76. Events Remain Notification-First

Mapped events do not become a competing authoritative state store.

When the backend event contract says a notification requires re-querying authoritative state, the focused APIs preserve that semantic.

Example:

```text
AppearanceSettingsChanged
    ↓
SettingsApi.getAppearanceSettings()
```

when the owning settings feature performs reconciliation.

## 77. Event Stream Is Best-Effort

The frontend event stream preserves the backend event-delivery contract:

- bounded;
- best effort;
- no guaranteed replay;
- compatible notifications may be coalesced;
- sequence gaps expose loss;
- authoritative correctness never depends on complete delivery.

The client must not promise stronger delivery semantics than Rust provides.

## 78. New Subscriber Semantics

A newly created consumer does not assume `EventsApi` replays all state needed to initialize itself.

Current authoritative state comes from focused query APIs.

Events provide notification/synchronization after that baseline.

## 79. Runtime Replacement and Event Stream Replacement

A replacement backend runtime creates a new runtime generation and a new sequence domain.

The root client owns replacing/rebinding native event infrastructure as needed.

Consumers must not retain hidden dependencies on obsolete generated stream objects.

## 80. Event Sequence Preservation

The client must preserve sequence numbers exactly enough for application coordination to detect:

```text
N → N+1
normal

N → N+3
gap
```

No mapper may renumber, compress, or fabricate events for convenience.

## 81. Runtime Replacement Preservation

When event runtime identity changes:

```text
RuntimeInstanceId A
→ RuntimeInstanceId B
```

the frontend can recognize the new generation and reset sequence tracking/reconcile runtime-sensitive state.

## 82. Sequence Gap Recovery

After a detectable gap, frontend coordination re-queries the smallest relevant authoritative state.

The client does not reconstruct missing events.

It also does not pretend reconnecting the stream proves no state changed while disconnected.

## 83. Event Stream Failures

Raw native stream failures are translated into typed transport-failure semantics before they reach app/feature coordination.

The event coordinator does not branch on generated exception class names or formatted strings.

## 84. Reconnection Policy

Native event reconnection/backoff policy is centralized in the root client because the root owns transport connectivity.

Feature code does not run independent native reconnect loops.

## 85. Reconnection Is Not Reconciliation

A re-established stream only restores future notification connectivity.

If delivery may have been lost, correctness requires authoritative reconciliation where applicable.

```text
reconnect
+
query authoritative state
```

are distinct responsibilities.

## 86. Timeout Ownership

Cross-cutting client-side transport timeouts, when needed, are root-client/operation-class policy.

Feature code should not routinely add arbitrary `.timeout(...)` wrappers around focused API calls.

## 87. Timeout Does Not Prove Mutation Failure

For a dispatched mutation, a transport timeout or disconnect may leave completion ambiguous.

The frontend must not assume the backend rolled back simply because Flutter did not receive the result.

The owning feature reconciles authoritative state according to its contract.

## 88. Cancellation Ownership

Cancellation is capability-specific.

A generic cancellation token is not attached to every focused API method.

Long-running operation cancellation is exposed through the capability that owns the operation identity, such as a future `JobsApi`.

## 89. Controller Disposal vs Backend Cancellation

SPEC-FE-002 controller disposal prevents obsolete frontend publication.

It does not automatically cancel authoritative Rust work.

Backend cancellation occurs only through an explicit supported application capability.

## 90. Automatic Query Retry

A future root transport policy may retry a query only when:

- retry semantics are safe;
- SPEC-BE-003/SPEC-BE-004 policy permits it;
- the implementation preserves trace/runtime semantics appropriately;
- authoritative behavior is not changed.

No Phase 000 speculative retry framework is required.

## 91. Automatic Mutation Retry Is Prohibited by Default

Mutations are not blindly resubmitted after ambiguous transport failure.

Example:

```text
mutation dispatched
    ↓
response transport lost
    ↓
completion unknown
```

The client must not interpret this as proof the mutation did not execute.

## 92. Idempotency Can Refine Retry Later

A future operation may permit retry only if its backend contract explicitly defines safe idempotency/deduplication semantics.

That capability-specific rule must be documented before automatic mutation retry is enabled.

## 93. Phase 000 `SettingsApi`

Phase 000 `SettingsApi` conceptually provides:

```text
getAppearanceSettings()
    → Future<AppearanceSettings>

updateAppearanceSettings(AppearanceSettings settings)
    → Future<void>
```

The exact immutable settings model is refined by SPEC-FE-006 without changing this client ownership boundary.

## 94. Phase 000 `DiagnosticsApi`

Phase 000 `DiagnosticsApi` conceptually provides:

```text
exportDiagnostics(...)
    → Future<DiagnosticsExport>

getTechnicalDetails()
    → Future<TechnicalDetails>

openDataDirectory()
    → Future<void>
```

Exact request/result fields mirror the backend bridge/application capability while remaining DTO-free in feature code.

## 95. Phase 000 `EventsApi`

Phase 000 `EventsApi` exposes the one mapped runtime-event stream:

```text
Stream<RuntimeEvent> get events
```

It does not expose generated stream handles, callbacks, or transport subscription objects.

## 96. Phase 000 `RuntimeApi`

Phase 000 `RuntimeApi` exposes runtime snapshot, typed recovery, replacement, and shutdown capabilities required by SPEC-FE-005.

It does not expose backend runtime internals, task executors, or generic command dispatch.

## 97. Recovery/Diagnostics Separation

Runtime mutation/replacement operations remain under `RuntimeApi`.

Diagnostic inspection/export operations remain under `DiagnosticsApi`.

This prevents `RuntimeApi` from becoming a catch-all failed-startup service.

## 98. Public Method Naming

Focused API methods use application intent:

```text
getAppearanceSettings
updateAppearanceSettings
getRuntimeState
retryStartup
exportDiagnostics
cancelOperation
```

Avoid transport implementation terminology such as:

```text
callRust
invokeBridge
executeDto
sendNativeRequest
```

## 99. No Generic Dispatch Surface

Focused APIs must not expose:

```text
execute(String method, Object payload)
```

or another generic dynamic dispatch surface.

Application capabilities remain statically typed.

## 100. API Models Are Not Widget Models

Focused client APIs do not return:

- widgets;
- colors;
- icons;
- localized display strings chosen by presentation;
- `BuildContext`-dependent types;
- layout state.

Feature presentation may map client models to UI-specific models when semantics differ.

## 101. No Client Feature Convenience Logic

Do not add a core client method solely because one screen wants a convenience transformation.

If behavior is presentation/application composition, it belongs to the feature/app layer.

The client remains an application capability boundary.

## 102. Future API Evolution

New backend capabilities may:

- add operations to an existing cohesive focused API; or
- add a new focused API when ownership is distinct.

Unrelated focused APIs should not change merely because another capability grows.

## 103. No Speculative Empty APIs

Phase 000 does not require files/classes/providers for `LibraryApi`, `GamesApi`, `JobsApi`, or `SourcesApi` unless a current slice genuinely consumes them.

Architecture reserves names/responsibilities without forcing empty scaffolding.

## 104. Shared Bridge Infrastructure

Production implementation may use a private shared bridge infrastructure object for:

- generated binding access;
- invocation helpers;
- failure mapping;
- compatibility state;
- runtime identity coordination;
- event connection;
- tracing/transport metadata.

That infrastructure is not a public feature dependency.

## 105. Prefer Small Capability Adapters

The implementation should avoid one giant class containing every future API method.

A likely shape is:

```text
BridgeArgusClient
    ├── BridgeRuntimeApi
    ├── BridgeSettingsApi
    ├── BridgeDiagnosticsApi
    └── BridgeEventsApi
           ↓
    shared private bridge infrastructure
```

Exact class names are implementation decisions.

## 106. Shared Infrastructure Must Not Become Generic Service Locator

A private bridge infrastructure object may centralize transport mechanics.

It must not become an untyped registry through which capabilities locate arbitrary application dependencies.

Dependencies remain explicit and typed.

## 107. File Ownership

SPEC-FE-001 owns exact project structure, but conceptually:

```text
core/client/
→ public client/focused API contracts, read models, typed failures

core/bridge/
→ generated bindings, bridge adapters, DTO mappers, production implementations
```

Features depend on `core/client`, not `core/bridge`.

## 108. Public Entry Points

Client public entry points should expose only stable Argus-owned contracts required by consumers.

Generated transport modules and bridge adapter implementation files remain private to the bridge boundary.

Do not export internals merely to simplify tests.

## 109. Focused API Test Seam

Feature/controller tests substitute the focused interface they consume.

Example:

```text
FakeSettingsApi implements SettingsApi
```

The fake does not need generated bridge DTOs.

## 110. Focused API Fake Capabilities

A useful focused fake can deterministically control:

- returned read models;
- application failures;
- transport failures;
- pending futures;
- completion ordering;
- call arguments/interactions where behavior requires it.

Keep fakes simple and scenario-oriented.

## 111. Root Client Tests

Root/client integration tests verify transport-level composition such as:

- one initialization path;
- compatibility handling;
- one native event connection;
- runtime replacement rebinding;
- transport failure translation;
- focused API adapter wiring.

They do not replace focused feature tests.

## 112. Mapper Tests

Mapper unit tests verify:

- DTO to client model conversion;
- typed identifier conversion;
- enum/value mapping;
- invalid required representation rejection;
- application-error mapping;
- event envelope/payload mapping;
- operation-handle mapping.

## 113. Application Failure Mapping Tests

Tests verify every stable application-error field survives mapping without semantic reinterpretation:

```text
code
category
severity
recoverability
retryPolicy
messageKey
traceId
safeContext
```

No test relies on formatted exception strings.

## 114. Transport Failure Tests

Tests use controlled bridge failures to verify:

- application failure is not mistaken for transport failure;
- native/communication failure is not fabricated as application failure;
- contract mismatch is typed;
- unsafe raw technical text does not leak into feature-facing contracts.

## 115. Runtime Mapping Tests

Tests verify:

- every lifecycle value;
- runtime identity preservation;
- startup failure composition;
- recovery action mapping;
- capabilities mapping;
- structurally impossible snapshots are rejected rather than defaulted.

## 116. Runtime Replacement Tests

Tests verify:

```text
Runtime A startup failed
    ↓ retry A
Runtime B returned
```

and that:

- `RuntimeInstanceId` changes as expected;
- stale A recovery actions are not silently retargeted;
- event-stream generation follows B;
- old generated stream handles are not leaked to consumers.

## 117. Event Mapping Tests

Tests verify:

- runtime identity preservation;
- exact sequence preservation;
- occurrence-time preservation;
- typed payload mapping;
- unknown incompatible payload handling;
- notification-first payload semantics.

## 118. Sequence-Gap Tests

Using controlled frontend event inputs:

```text
sequence 10
sequence 12
```

must remain observable as a gap after mapping.

The client must not synthesize sequence 11.

## 119. Event Reconnect Tests

Controlled tests verify:

- transport failure is typed;
- root reconnect policy acts as designed;
- reconnect does not imply events were fully delivered;
- runtime identity/sequence information is still available for authoritative reconciliation.

## 120. No Automatic Mutation Retry Test

At minimum, Phase 000 client tests should prove:

```text
updateAppearanceSettings(Dark)
    ↓
mutation dispatch occurs
    ↓
response transport becomes ambiguous
    ↓
no automatic second mutation dispatch
```

The owning controller/feature handles reconciliation.

## 121. Focused API Contract Tests

Where a focused API has both production and fake implementations, tests should preserve behavioral expectations common to the interface rather than duplicating bridge internals.

Examples include:

- read result semantics;
- typed failure semantics;
- expected identifier types;
- mutation completion semantics.

## 122. Feature Test Boundary

Ordinary feature tests run:

```text
feature/controller
    ↓
FakeFocusedApi
```

They do not require:

- Rust backend;
- native library;
- FRB initialization;
- DTO construction;
- generated stream handles.

## 123. Rust-Flutter Integration Coverage

Broader integration tests are reserved for behavior that genuinely crosses the native boundary according to CONV-TEST-001.

Examples include:

- generated bridge smoke compatibility;
- real Phase 000 settings round trip;
- runtime initialization DTO/client mapping;
- one event crossing Rust → bridge → client.

These do not replace deterministic client adapter tests.

## 124. Architecture Verification

Mechanically enforce where practical:

- feature code does not import generated bridge source;
- feature code does not import bridge DTO types;
- focused API signatures do not expose generated transport types;
- `core/client` does not depend on Riverpod/widgets/features;
- typed frontend identifiers are used beyond bridge mapping boundaries;
- client public entry points do not export generated implementation types.

These checks integrate with SPEC-FE-001 and canonical `just check` verification.

## 125. Generated Source

Generated FRB Dart source follows CONV-REPO-001.

It is committed/generated/verified according to repository policy and never hand-edited.

The client boundary adapts generated source rather than treating generated source as the public frontend architecture.

## 126. Client Observability

The client may record frontend-side transport/connectivity diagnostics through approved observability mechanisms.

It must preserve backend `TraceId` values on mapped application failures and operation context where exposed.

It must not duplicate backend error logging as though it were a second backend source of truth.

## 127. Sanitization

Client observability must not record:

- raw credentials;
- provider tokens;
- raw user paths beyond approved sanitization;
- ROM contents;
- arbitrary raw DTO payload dumps;
- backend source chains supplied only for internal native diagnostics.

SPEC-BE-003 and future frontend diagnostics conventions govern sanitization.

## 128. Unsupported/Unknown Error Code Behavior

A frontend version receiving a representable but unfamiliar application `ErrorCode` still has:

- category;
- severity;
- recoverability;
- retry policy;
- message key;
- trace ID;
- safe context.

The client does not crash solely because the code is not in a frontend constant list.

## 129. Unknown Enum/Variant Behavior

A closed transport enum/variant required for correct semantic interpretation must be understood by the matched generated frontend contract.

If it is not, the client rejects the representation as contract mismatch rather than guessing.

This is distinct from ignoring compatible additive fields.

## 130. API Availability and Runtime Readiness

The existence of a focused API object does not mean every operation is legal in every runtime lifecycle state.

Backend application/runtime admission remains authoritative.

The client may perform obvious local generation/precondition checks that preserve backend semantics, but it must not invent a separate inconsistent readiness policy.

## 131. Runtime State Is Authoritative for Recovery Presentation

`SPEC-FE-005` consumes mapped runtime snapshot data to decide what recovery UI is available.

The client does not infer available recovery actions from error strings or hard-coded UI tables independent of the runtime snapshot.

## 132. Transport Failure During Failed-Startup Inspection

If a runtime was previously known as `StartupFailed` but transport becomes unavailable, the client surfaces transport uncertainty.

Flutter must not assume the previously cached recovery capabilities remain executable until authoritative communication is restored.

Presentation policy belongs to SPEC-FE-005.

## 133. Technical Details and Clipboard

`DiagnosticsApi.getTechnicalDetails()` returns sanitized frontend-readable data.

The client does not copy to the clipboard itself.

Clipboard interaction remains a presentation/platform side effect according to CONV-FLUTTER-001.

## 134. Open Data Directory

`DiagnosticsApi.openDataDirectory()` invokes the backend/native capability when available.

The client does not expose raw filesystem commands or paths as a replacement for the typed capability.

## 135. Diagnostic Export

Diagnostic export returns an immutable result concept such as an exported-path/success descriptor defined by the backend bridge/application contract.

The client does not assemble the diagnostic bundle itself.

Rust remains authoritative for sanitized diagnostic assembly.

## 136. App-Level Event Coordinator Boundary

The root client/`EventsApi` owns event connectivity and typed mapping.

The app-level event coordinator owns application synchronization decisions such as:

- sequence tracking;
- deciding which authoritative projections require refresh;
- coordinating cross-feature reaction;
- handling runtime replacement implications.

Do not merge all app synchronization policy into the transport client.

## 137. Client vs Event Coordinator Responsibilities

Client:

```text
connect
map
preserve identity/sequence
translate stream failures
reconnect transport policy
```

Coordinator:

```text
track continuity
interpret notification relevance
request authoritative refresh
coordinate application projections
```

This keeps transport replaceable and application state explicit.

## 138. Client vs Feature Controller Responsibilities

Client:

```text
invoke typed application capability
map result/failure
preserve transport/application semantics
```

Controller:

```text
own feature state
choose concurrency policy
show pending state
preserve loaded data
reconcile after feature operations
```

SPEC-FE-002 remains authoritative for controller behavior.

## 139. Client vs Backend Responsibilities

The client does not own:

- business validation;
- persistence;
- transaction policy;
- runtime scheduling;
- provider rules;
- job lifecycle authority;
- recovery eligibility authority;
- backend error-code creation.

Those remain in Rust.

## 140. Phase 000 Data Flow: Settings Read

```text
AppearanceSettingsController
    ↓
SettingsApi.getAppearanceSettings()
    ↓
bridge-backed SettingsApi
    ↓
GetAppearanceSettings bridge call
    ↓
BridgeResult<AppearanceSettingsDto>
    ↓
client result/error mapping
    ↓
AppearanceSettings
    ↓
controller state
```

No DTO enters the controller.

## 141. Phase 000 Data Flow: Settings Mutation

```text
AppearanceSettingsController
    ↓
SettingsApi.updateAppearanceSettings(desired)
    ↓
client request mapping
    ↓
UpdateAppearanceSettings bridge call
    ↓
application success/failure
    ↓
typed Dart completion/failure
```

The client does not fabricate a returned authoritative settings snapshot.

## 142. Phase 000 Data Flow: Startup

```text
app/bootstrap
    ↓
ArgusClient.initialize()
    ↓
native/bridge setup
    ↓
backend host initialization
    ↓
RuntimeStateDto
    ↓
client mapping
    ↓
RuntimeState
```

A mapped `StartupFailed` state remains a successful client-transport result.

## 143. Phase 000 Data Flow: Recovery Retry

```text
Recovery UI/controller holds RuntimeInstanceId A
    ↓
RuntimeApi.retryStartup(A)
    ↓
backend validates generation
    ↓
failed runtime A retired
    ↓
new runtime B constructed
    ↓
RuntimeState(B)
```

The client returns the new authoritative mapped runtime snapshot.

## 144. Phase 000 Data Flow: Event

```text
Rust runtime event
    ↓
RuntimeEventDto
    ↓
single native event stream
    ↓
client event mapper
    ↓
RuntimeEvent
    ↓
app event coordinator
    ↓
focused authoritative refresh when required
```

## 145. Phase 000 Data Flow: Diagnostics

```text
Recovery presentation
    ↓
DiagnosticsApi
    ↓
bridge diagnostics capability
    ↓
Rust sanitized diagnostics service
    ↓
client read model
    ↓
presentation side effect / status
```

## 146. Prohibited Patterns

The following are prohibited unless an owning architecture specification explicitly changes the contract:

- feature/widget direct generated FRB calls;
- bridge DTOs in feature code;
- `BridgeResult<T>` in focused API signatures;
- raw generated exception classes in feature contracts;
- raw backend technical strings as UI error contracts;
- one monolithic client injected into every feature by convenience;
- completely independent domain clients each owning their own native bridge lifecycle;
- separate native event streams per feature;
- stringly typed generic API dispatch;
- stringly typed generic recovery execution;
- `AsyncValue` returned by focused client APIs;
- `BuildContext` in client contracts;
- widget/presentation models returned by client APIs;
- raw ID strings used throughout frontend after typed ID concepts exist;
- invalid bridge values silently converted to defaults;
- stale runtime recovery actions silently retargeted;
- event sequence renumbering or missing-event reconstruction;
- treating events as authoritative state snapshots when the backend contract is notification-first;
- feature-owned native reconnect loops;
- arbitrary feature-owned transport timeouts;
- blind automatic retry of mutations after ambiguous transport outcomes;
- hand-edited generated bridge source;
- test-only branches inside production client behavior.

## 147. Acceptance Criteria

An implementation conforming to SPEC-FE-003 satisfies all of the following:

1. Exactly one production Flutter-side backend gateway owns native bridge connectivity.
2. The root client owns common transport, lifecycle, mapping, failure, event, tracing, and cross-cutting policy.
3. Features depend on focused APIs rather than generated bindings or the root client by convenience.
4. Phase 000 exposes only implemented runtime, settings, diagnostics, and event capabilities.
5. Future capability names do not require empty Phase 000 scaffolding.
6. Focused API contracts are ordinary typed Dart and independent of Riverpod/widgets.
7. Focused API providers are narrow projections from the root client.
8. Generated bridge DTOs never cross into feature/controller code.
9. `BridgeResult` never appears in feature-facing signatures.
10. Queries return immutable frontend snapshots.
11. Mutations do not invent authoritative return state not supplied by the backend contract.
12. Future long-running admission returns typed operation handles rather than waiting for completion.
13. Typed frontend identifiers replace bridge string/primitives before ordinary feature use.
14. Runtime identity is represented by a typed `RuntimeInstanceId`.
15. Runtime lifecycle values preserve backend semantics.
16. Startup failure remains inspectable runtime state when transport succeeds.
17. Inability to communicate reliably with Rust remains a transport failure.
18. Application and transport failures remain separate typed contracts.
19. `ApplicationFailure` preserves all published backend error dimensions without reinterpretation.
20. Error codes remain representable even when not known by a closed frontend catalog.
21. Safe context remains bounded rather than becoming arbitrary dynamic JSON.
22. Raw FRB/native/technical exception text does not become a feature contract.
23. Invalid required DTO representations fail typed rather than silently defaulting.
24. Compatible additive bridge information is tolerated according to SPEC-X-001.
25. Runtime-bound recovery operations preserve expected runtime identity.
26. Stale runtime actions are never silently retargeted to a replacement runtime.
27. Startup retry returns an authoritative mapped runtime snapshot to Flutter.
28. The new runtime generation remains visible after retry/replacement.
29. Recovery operations are typed rather than free-form generic dispatch.
30. Diagnostics and runtime recovery responsibilities remain separated by capability.
31. Exactly one logical native runtime-event connection exists per active runtime generation.
32. Frontend event mapping preserves runtime identity, sequence, occurrence time, and typed payload semantics.
33. Event payloads are not flattened into string/map contracts.
34. Events remain best-effort notifications rather than a replay or authoritative state store.
35. Sequence gaps remain detectable after mapping.
36. Runtime replacement establishes a distinct sequence domain.
37. Reconnection policy is centralized in the root client.
38. Reconnection does not replace authoritative reconciliation after uncertain delivery.
39. Feature code does not invent arbitrary transport timeout policy.
40. Controller disposal is not misrepresented as backend cancellation.
41. Mutations are not automatically retried after ambiguous transport failure without explicit safe backend semantics.
42. Focused API fakes are the ordinary feature/controller test seam.
43. Feature tests do not require generated DTOs or the real Rust backend when a focused API seam exists.
44. Mapper tests cover DTO, identifier, error, runtime, event, and handle conversion.
45. Root/client integration tests cover initialization, event connectivity, runtime replacement, and transport failure translation.
46. A controlled test proves ambiguous settings mutation transport failure does not trigger duplicate automatic dispatch.
47. Architecture verification prevents generated bridge/client implementation types from leaking upward.
48. Generated source remains unmodified and passes canonical drift verification.

## 148. Phase 000 Minimum Implementation Contract

Phase 000 requires the smallest client implementation that proves the architecture:

```text
ArgusClient
├── initialize
├── runtime: RuntimeApi
├── settings: SettingsApi
├── diagnostics: DiagnosticsApi
└── events: EventsApi
```

with:

- one shared generated bridge owner;
- one typed application/transport failure mapping path;
- one runtime snapshot mapping path;
- one settings mapping path;
- one diagnostics mapping path;
- one typed runtime-event mapping path;
- one native event subscription per runtime generation;
- focused API provider/fake seams.

No library, games, jobs, sources, provider, metadata, or ROM-management API implementation is required by this specification during Phase 000.

## 149. Out of Scope

This specification intentionally leaves later specifications to define:

- exact `go_router` route ownership and route-driven client requests;
- startup/recovery UI variants and presentation policy;
- exact appearance-settings state/control semantics;
- library/game/job/source API operation catalogs beyond the generic client rules here;
- persistent frontend caching/offline synchronization;
- future provider/account authentication UX;
- future streaming media/artwork transport needs;
- final release packaging/native library discovery details.

It does not define a generic RPC framework, plugin API, frontend repository layer, or second backend client implementation architecture.

## 150. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](../backend/spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](../backend/spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-009 — Application Service Contracts](../backend/spec-be-009-application-service-contracts.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [CONV-DOC-001 — Documentation and Codex Result Conventions](../../conventions/conv-doc-001-documentation-and-codex-result-conventions.md)
- [Frontend Specifications Index](README.md)
- [Subsystem Specification Template](../../templates/subsystem-specification.md)
