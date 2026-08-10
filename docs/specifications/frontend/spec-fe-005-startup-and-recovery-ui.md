# Startup and Recovery UI

**Document ID:** SPEC-FE-005  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-10  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-007, SPEC-BE-008, SPEC-FE-001, SPEC-FE-002, SPEC-FE-003, SPEC-FE-004, SPEC-X-001, CONV-REPO-001, CONV-FLUTTER-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the Flutter startup and recovery user-interface contract for Argus ROM Toolkit.

It translates the backend startup lifecycle, bridge/client runtime contract, Riverpod state conventions, routing readiness rules, diagnostics boundaries, and recovery-generation semantics into one implementation-ready frontend feature contract.

The startup feature exists so Flutter can distinguish:

- client/bootstrap failure before a usable runtime contract exists;
- an inspectable constructed Rust runtime in `Uninitialized` or `Starting`;
- an inspectable Rust runtime in `StartupFailed`;
- a positively certified `Ready` runtime;
- uncertainty after communication is lost during pre-ready startup or generation-changing recovery;
- explicit recovery and diagnostic operations bound to one runtime generation.

The central invariant is:

> **Argus startup UI is a truthful projection of application authority: the startup feature owns one explicit pre-ready state machine, failed-runtime recovery is offered only when backend-certified while pre-runtime bootstrap actions derive only from typed client transport semantics, mutating recovery never guesses or repeats an uncertain outcome, new runtime generations replace all stale failure context, and the application reaches its routed shell only after authoritative readiness has been established.**

## 2. Responsibilities

This specification owns frontend rules for:

- startup feature ownership;
- startup-controller lifetime and provider shape;
- initial `ArgusClient` bootstrap presentation;
- mapping bootstrap failure versus backend startup failure;
- frontend startup-state modeling;
- the routing-safe readiness projection consumed by SPEC-FE-004;
- blocking startup presentation;
- startup progress semantics;
- startup failure presentation hierarchy;
- recovery-action availability and presentation priority;
- runtime-generation binding for recovery actions;
- runtime-changing recovery single-flight behavior;
- targeted appearance-settings recovery confirmation;
- bootstrap retry semantics;
- runtime-state uncertainty and reconciliation;
- ambiguous mutating-recovery transport outcomes;
- diagnostics export interaction;
- technical-details retrieval and copy behavior;
- open-data-directory interaction;
- exit/shutdown interaction while pre-ready;
- stale runtime-generation handling;
- event-assisted startup reconciliation;
- non-event-dependent terminal correctness;
- startup/recovery focus and accessibility behavior;
- startup/recovery controller, widget, routing-integration, and bridge-integration tests.

## 3. Non-Responsibilities

This specification does not define:

- Rust startup ordering, phase execution, cleanup, or runtime replacement, owned by SPEC-BE-007;
- backend runtime scheduling or shutdown internals, owned by SPEC-BE-004;
- backend error taxonomy, logging, trace creation, or diagnostic-bundle contents, owned by SPEC-BE-003;
- appearance settings persistence semantics, owned by SPEC-BE-005 and SPEC-FE-006;
- bridge DTO serialization or native call syntax, owned by SPEC-BE-008;
- root client error/transport mapping or focused API definitions, owned by SPEC-FE-003;
- route graph, route-intent preservation, or startup-history behavior, owned by SPEC-FE-004;
- exact visual tokens, spacing, typography, color, breakpoint values, focus-ring styling, or comprehensive accessibility baseline, owned by SPEC-FE-007;
- post-ready feature loading;
- library scans, metadata, artwork, indexing, or other deferred application work;
- a generic application error center;
- a general recovery framework for arbitrary feature failures.

## 4. Governing Principles

Startup and recovery behavior follows these rules:

1. `app/bootstrap` constructs root dependencies; `features/startup` owns startup/recovery behavior.
2. One startup controller is the frontend authority for pre-ready startup and recovery state.
3. Initial client bootstrap and backend runtime startup are distinct concepts.
4. A reported backend `StartupFailed` runtime is loaded inspectable state, not a Flutter transport error.
5. The normal routed shell becomes available only after authoritative backend `Ready`.
6. Startup blocks only on mandatory startup work.
7. Flutter does not fabricate startup percentages or current startup phases.
8. Failed-runtime recovery actions come only from authoritative current runtime capabilities/actions; pre-runtime bootstrap actions use only typed client transport semantics.
9. Missing actions are absent, not rendered disabled as speculative options.
10. Runtime-changing recovery is generation-bound and single-flight.
11. Recovery never silently retargets a stale runtime action to a replacement generation.
12. A transport failure after a potentially admitted mutation is an uncertain outcome, not proof of failure.
13. Uncertain mutating outcomes are reconciled through authoritative runtime state before any retry decision.
14. Mutating recovery is never automatically replayed after an ambiguous transport outcome.
15. New runtime generations replace all failure/action/diagnostic state from the old generation.
16. Diagnostics remain bounded secondary recovery capabilities.
17. Event delivery may accelerate synchronization but is never the sole source of terminal startup correctness.
18. Startup/recovery state remains outside normal ready-shell route history.
19. Controller state remains UI-framework-independent except for Riverpod ownership conventions.
20. Accessibility and keyboard operation are required even before SPEC-FE-007 adds the full design-system baseline.

## 5. Architectural Position

The startup feature sits between root composition, focused client APIs, and routing readiness:

```text
main.dart
    ↓
app/bootstrap
    ↓ constructs
ArgusClient + ClientBootstrap/focused API providers
    ↓
features/startup/application
    ↓
StartupController
    ├── RuntimeApi
    ├── DiagnosticsApi
    └── ClientBootstrap initialization-only seam
    ↓
StartupState + AppReadiness
    ├── features/startup/presentation
    └── app/routing readiness projection
```

The startup feature does not own the root dependency graph and the router does not own startup commands.

## 6. Root Construction vs Startup Orchestration

`app/bootstrap` owns creation of application-lifetime dependencies.

Examples include:

- root `ArgusClient` infrastructure;
- provider composition required to expose the client and focused APIs;
- application-lifetime event/client infrastructure where required by SPEC-FE-003.

The startup feature owns orchestration after those dependencies exist.

`app/bootstrap` provides an initialization-only Argus-owned client seam backed by the root `ArgusClient`. The startup controller invokes that seam and interprets the resulting typed frontend state; it does not receive the full root client merely to initialize it.

## 7. Startup Feature Ownership

Conceptually:

```text
features/startup/
├── startup.dart
├── application/
│   ├── startup_controller.dart
│   └── startup_state.dart
└── presentation/
    ├── startup_screen.dart
    ├── startup_failure_view.dart
    ├── runtime_unavailable_view.dart
    └── recovery widgets
```

Exact filenames are implementation details.

The feature may publicly expose only the narrow contracts needed by app composition, such as its route/surface builder and readiness projection provider.

## 8. Application-Lifetime Startup Controller

Startup/readiness is application-wide state.

The startup controller may therefore be explicitly application-lifetime rather than auto-disposed when the startup screen stops rendering.

After the runtime becomes `Ready`, its retained responsibilities narrow to application readiness, a projection of the current authoritative runtime identity needed for app coordination, and shutdown coordination. The root `ArgusClient` remains the transport/runtime-generation authority; the startup controller does not create a competing runtime identity source.

It does not become a universal controller for jobs, settings, diagnostics, or feature data.

## 9. Controller API Shape

The controller conceptually exposes operations equivalent to:

```text
initialize()
retryInitialization()
retryStartup()
resetAppearanceSettings()
reconcileRuntime()
exportDiagnostics(...)
loadTechnicalDetails()
openDataDirectory()
requestExit()
```

Exact method names are implementation details.

Each method expresses application intent rather than bridge transport mechanics.

## 10. Controller Dependencies

The startup controller depends on Argus-owned seams such as:

```text
ClientBootstrap initialization-only seam
RuntimeApi
DiagnosticsApi
shared runtime-event projection where useful
```

It must not depend on:

- generated FRB bindings;
- bridge DTOs;
- SQLite;
- backend implementation objects;
- `BuildContext`;
- `go_router`;
- platform clipboard APIs directly where a presentation-owned operation is more appropriate.

## 11. Public State Envelope

The public startup controller state is conceptually:

```text
AsyncValue<StartupState>
```

The outer `AsyncValue` answers whether the initial Flutter client/bootstrap operation established a usable runtime contract.

Once such a contract exists, backend lifecycle states are represented inside `StartupState` rather than repeatedly repurposing `AsyncError`.

## 12. Initial Bootstrap Loading

Before Flutter has a usable runtime contract:

```text
AsyncLoading
```

means the root client initialization path is in progress.

This may include:

- making native transport usable;
- validating matched bridge compatibility;
- initializing/starting the backend host;
- establishing required root client infrastructure;
- obtaining the first authoritative runtime snapshot.

## 13. Initial Bootstrap Failure

If client initialization fails before a trustworthy runtime contract exists:

```text
AsyncError(TransportFailure)
```

This includes failures such as:

- native library unavailable;
- bridge unavailable;
- contract mismatch;
- marshalling/communication failure that prevents a usable runtime contract;
- another typed transport/client failure from SPEC-FE-003.

It is not modeled as `StartupState.startupFailed`.

## 14. Backend Startup Failure Is Loaded State

If client initialization succeeds and returns:

```text
RuntimeState.startupFailed(...)
```

then startup-controller state is:

```text
AsyncData(
    StartupState.startupFailed(...)
)
```

It is not:

```text
AsyncError(...)
```

because the backend remains inspectable and deliberately exposes bounded recovery capabilities.

## 15. Startup-State Union

Conceptually:

```text
StartupState
├── uninitialized
├── starting
├── ready
├── startupFailed
├── runtimeUnavailable
├── shuttingDown
└── stopped
```

A Freezed/sealed representation should encode semantically valid fields per variant rather than rely on globally nullable fields and boolean combinations.

## 16. `uninitialized` and `starting` Variants

The outer `AsyncLoading` state owns the period before any trustworthy runtime snapshot exists. Once a constructed runtime snapshot exists, SPEC-BE-008 guarantees `runtimeInstanceId` is present even while the backend lifecycle is `Uninitialized` or `Starting`.

Conceptually:

```text
StartupState.uninitialized
- runtimeInstanceId

StartupState.starting
- runtimeInstanceId
```

The startup feature preserves the backend lifecycle distinction rather than relabeling `Uninitialized` as `Starting`. Both variants render the blocking pre-ready startup experience in Phase 000, and the ordinary UI need not expose the runtime ID.

## 17. `ready` Variant

Conceptually:

```text
StartupState.ready
- runtimeInstanceId
- capabilities
```

The exact carried fields should be limited to what app-level readiness composition genuinely needs.

The controller must not duplicate complete feature/backend state merely because a `Ready` runtime snapshot contains capabilities.

## 18. `startupFailed` Variant

Conceptually:

```text
StartupState.startupFailed
- runtimeInstanceId
- failure
- availableRecoveryActions
- capabilities
- runtimeRecoveryOperation
- diagnosticOperations
- technicalDetailsState
```

The model may factor operation states into nested immutable types.

The key property is that all failure/recovery state belongs to one known runtime generation.

## 19. `runtimeUnavailable` Variant

`runtimeUnavailable` means:

> Flutter previously established a usable client/runtime contract, but during pre-ready startup or generation-changing recovery it can no longer determine the current authoritative runtime state safely.

Conceptually it may carry:

```text
StartupState.runtimeUnavailable
- transportFailure
- lastKnownRuntimeContext?
- reconciliationOperation
```

Any retained runtime context is explicitly last-known, not current authority.

## 20. `shuttingDown` and `stopped`

These variants model intentional frontend/runtime termination where observable.

Once intentional shutdown reaches terminal `stopped`, the same startup controller does not spontaneously start a new runtime.

A new startup requires a new application/client lifecycle.

## 21. Backend Readiness Projection

The startup feature exposes a narrow backend-readiness projection to app composition.

Conceptually:

```text
AppReadiness
├── preReady
├── startupFailed
└── ready
```

The exact enum/union may include enough distinction for composition without exposing recovery-operation details.

SPEC-FE-006 combines this backend-readiness projection with initial appearance authority into the final app presentation-readiness projection consumed by SPEC-FE-004. The router must not receive the complete `StartupState` merely to decide shell gating.

## 22. Router Does Not Execute Startup

The router may react to the readiness projection.

It must not call:

- `initialize()`;
- `retryStartup()`;
- `resetAppearanceSettings()`;
- diagnostics operations;
- runtime reconciliation.

Routing remains side-effect-free policy under SPEC-FE-004.

## 23. Backend Ready Is a Shell Prerequisite

The startup feature marks backend readiness only when it observes authoritative:

```text
RuntimeState.ready
```

The transition owned here is:

```text
startup/recovery surface
    ↓ authoritative Ready
AppReadiness.ready
```

`AppReadiness.ready` is necessary for normal-shell entry but is not by itself the complete first-shell presentation gate. SPEC-FE-006 requires the initial authoritative appearance read, after which app composition exposes presentation readiness and SPEC-FE-004 revalidates/activates the pending intended route.

## 24. No Derived Readiness

Flutter must not infer readiness from:

- elapsed time;
- database-open indication alone;
- settings-load success alone;
- event-stream connection alone;
- absence of a failure event;
- completion of a subset of known startup phases.

`Ready` remains the positive certification defined by SPEC-BE-007.

## 25. Mandatory Startup Boundary

Phase 000 startup may block on:

- native bridge initialization;
- database path resolution;
- database opening;
- migrations;
- core service construction;
- appearance-settings loading;
- event-stream initialization required for safe readiness;
- final readiness validation.

## 26. Startup Must Not Wait for Deferred Work

Startup must not block on future:

- library loading;
- scanning;
- source indexing;
- metadata lookup;
- artwork;
- ROM verification;
- provider operations;
- background feature queries that are not required for backend readiness.

Those begin after shell entry according to their owning features.

## 27. Blocking Startup Presentation

Before `Ready`, the normal shell is not visible as an interactive background.

The startup feature renders a blocking application-level surface.

The minimum Phase 000 successful-startup presentation includes:

```text
Argus identity
user-safe startup status
indeterminate progress
```

Detailed visual treatment belongs to SPEC-FE-007.

## 28. Indeterminate Progress

Phase 000 does not have an authoritative percentage-progress contract.

The startup UI therefore uses indeterminate progress.

It must not fabricate:

```text
37%
73%
4 of 9 steps
```

from phase count, elapsed time, logs, or heuristics.

## 29. No Fabricated Current Phase

The current contracts expose the phase of a terminal startup failure but do not require a live current-phase stream.

The success-path UI must not infer labels such as:

```text
Opening database…
Running migrations…
Loading settings…
```

from timing or incidental logs.

If a future backend contract explicitly publishes current startup phase, this specification may be extended without changing the authority rule.

## 30. Failure Phase Presentation

A terminal `StartupFailure` may include the typed startup phase where startup became terminal.

Flutter may use that phase to provide responsibility-oriented context.

It must not turn backend implementation internals into UI vocabulary.

For example, a presentation concept such as:

```text
Database initialization failed
```

may be appropriate where derived from the published phase/error contract.

Raw SQL/native exception labels are prohibited.

## 31. User-Facing Error Contract

Primary user-facing error text derives from the typed frontend application failure:

```text
messageKey
+
allowlisted SafeContext
```

Presentation may additionally use:

- startup phase;
- recoverability/retry semantics;
- backend-advertised recovery actions.

It must not display raw Rust, SQLite, FRB, or stack-trace text as primary UI.

## 32. Bootstrap Failure Surface

When outer state is `AsyncError(TransportFailure)`, the startup feature renders a client/bootstrap failure surface.

Conceptually:

```text
Argus could not initialize
Localized user-safe message derived from the typed TransportFailure

Retry Initialization
Exit
```

Additional frontend-safe technical details may be available when supported by the client boundary.

The screen must not pretend a failed Rust runtime exists when no runtime snapshot is trustworthy.

## 33. Bootstrap Failure Actions

Bootstrap failure actions are derived from typed client/transport semantics, not from backend recovery actions that cannot be queried.

Potential actions include:

```text
Retry Initialization
Exit
Copy frontend-safe technical details
```

only where genuinely supported.

## 34. Bootstrap Retry Is Not Runtime Retry

`Retry Initialization` means a fresh client/bootstrap attempt.

It is not:

```text
RuntimeApi.retryStartup(...)
```

and must not invent a `RuntimeInstanceId`.

## 35. Bootstrap Retry Freshness

Conceptually:

```text
bootstrap attempt A
    ↓ TransportFailure
Retry Initialization
    ↓
bootstrap attempt B
```

The controller must ensure completion from attempt A cannot overwrite state produced by attempt B.

A failed partially initialized root client is not assumed reusable unless the client contract explicitly guarantees safe reuse.

Bootstrap initialization/retry is single-flight. While attempt B is in progress, another Retry Initialization request must not start attempt C; controller correctness does not rely only on disabling the button.

## 36. Transport Failure Mapping for Bootstrap UX

Bootstrap presentation may branch on a typed `TransportFailureKind` where that distinction produces meaningful user action.

For example:

- a transient communication failure may allow retry;
- a contract mismatch may require termination/update rather than endless retry.

Raw exception strings are never used as control flow.

## 37. Inspectable Startup-Failure Surface

When state is `StartupState.startupFailed`, render the normal startup recovery surface.

Conceptually:

```text
Argus could not start
Localized user-safe message derived from the typed ApplicationFailure

Primary currently advertised recovery action

Applicable secondary currently advertised recovery actions

Technical details
Exit
```

Only actions actually available for the current failed runtime are shown.

## 38. Recovery Action Source of Truth

Recovery actions come from the authoritative current mapped runtime state/failure contract.

Conceptually:

```text
RuntimeState.startupFailed
    ↓
availableRecoveryActions
    ↓
startup recovery UI
```

Flutter does not infer action availability from:

- error strings;
- category alone;
- failed phase alone;
- hard-coded assumptions about common failures.

## 39. Phase 000 Recovery Kinds

The backend/bridge contract may expose Phase 000 kinds including:

```text
RetryStartup
ResetAppearanceSettings
ExportDiagnostics
CopyTechnicalDetails
OpenDataDirectory
Exit
```

Flutter maps known kinds to presentation semantics while preserving backend authority for availability.

## 40. Missing Actions Are Absent

If a current failed runtime omits a recovery action, the UI does not render a disabled speculative action.

For example, absence of:

```text
ResetAppearanceSettings
```

means the backend has not certified that targeted reset is available for this failure.

The frontend must not imply otherwise.

## 41. Recovery Constraints

Typed recovery constraints from the client model must be preserved and honored.

They must not be flattened into arbitrary maps or ignored because current actions happen to be simple.

The frontend may adapt presentation to known typed constraints while the backend remains authoritative for their meaning.

## 42. Deterministic Recovery Presentation Priority

Phase 000 presentation priority is:

1. `ResetAppearanceSettings` as primary when offered;
2. otherwise `RetryStartup` as primary when offered;
3. `ExportDiagnostics` as secondary;
4. `CopyTechnicalDetails` as secondary;
5. `OpenDataDirectory` as secondary;
6. `Exit` as termination/escape action.

The order returned by the backend DTO is not interpreted as recommendation or priority.

## 43. Targeted Repair Before Generic Retry

If the backend offers both:

```text
ResetAppearanceSettings
RetryStartup
```

then the targeted reset is the primary action because the backend has certified a known repair path for the failure.

Generic retry remains available according to the exposed action set.

## 44. Semantic Recovery Labels

Do not collapse distinct operations into one generic `Try Again` action.

Use semantic frontend labels equivalent to:

```text
Retry Initialization
Retry Startup
Reset Appearance Settings
Reconnect
```

according to the actual operation.

This makes user intent and controller verification explicit.

## 45. Runtime-Generation Binding

Every runtime-bound recovery action belongs to one specific `RuntimeInstanceId`.

Conceptually:

```text
Runtime A failure
    ↓
action offered for A
    ↓
typed focused recovery operation(expectedRuntimeInstanceId: A or equivalent bound scope)
```

The binding rule applies to runtime-changing recovery and to diagnostic/Exit actions when they are being exercised because Runtime A advertised them as recovery capabilities. The client/controller must never substitute the current runtime ID merely to make a stale action succeed.

## 46. Runtime-Changing Recovery Actions

Phase 000 runtime-changing actions include:

```text
RetryStartup
ResetAppearanceSettings
Exit
```

where Exit retires the current failed runtime and the first two may replace it with a fresh generation.

When Exit is offered by a failed runtime, dispatch preserves that failed runtime's generation binding or equivalent recovery validation even if the implementation shares underlying host-shutdown machinery. A stale recovery Exit must not be silently retargeted to a replacement runtime.

These operations have stronger concurrency restrictions than non-mutating diagnostic actions.

## 47. Runtime-Changing Single Flight

Only one runtime-changing recovery action may execute at a time.

Conceptually:

```text
runtimeRecovery = idle
    ↓ RetryStartup
runtimeRecovery = running(retryStartup)
```

A second runtime-changing command is rejected by controller policy even if accidentally dispatched by the UI.

Button disabling is presentation support, not the correctness boundary.

## 48. Recovery While Runtime Change Is Running

Once generation-changing recovery begins, no new failed-runtime diagnostic/recovery action is admitted until the new authoritative runtime state is known.

This Phase 000 rule favors correctness and simplicity over concurrent recovery work.

Existing backend work may complete if already admitted, but stale results cannot overwrite state for a replacement generation.

## 49. Preserve Failure Context During Recovery

While a runtime-changing recovery operation is executing against Runtime A, the original A failure remains visible until either:

- a replacement/current authoritative runtime state is established; or
- the recovery attempt fails without changing authority.

The screen should communicate both what failed and what recovery is being attempted.

## 50. Retry Startup Semantics

`RetryStartup` follows SPEC-BE-007:

```text
Runtime A = StartupFailed
    ↓
RetryStartup(A)
    ↓
A -> ShuttingDown -> Stopped
    ↓
construct Runtime B
    ↓
B -> Uninitialized -> Starting
```

It never means restarting Runtime A in place.

## 51. Retry Result

The focused `RuntimeApi.retryStartup()` contract returns an authoritative `RuntimeState` snapshot to Flutter according to SPEC-FE-003.

The startup controller adopts the returned runtime generation/state directly.

It does not preserve Runtime A identity across a successful replacement.

## 52. New Runtime Starting

If recovery establishes:

```text
Runtime B = Starting
```

the UI transitions to the normal blocking startup presentation for B.

Runtime A's failure/action content is discarded as soon as B becomes authoritative.

## 53. New Runtime Ready

If the new authoritative runtime is:

```text
Runtime B = Ready
```

then:

- startup state becomes `ready` for B;
- the backend-readiness projection becomes ready;
- SPEC-FE-006 invalidates/re-establishes appearance authority for B as required;
- once app presentation readiness is satisfied, SPEC-FE-004 revalidates the pending intended route and activates the normal shell.

## 54. New Runtime Startup Failure

If Runtime B also fails startup, the recovery surface is reconstructed entirely from B.

It receives B's:

- runtime ID;
- startup failure;
- trace ID through the failure contract;
- recovery action set;
- capability information.

No A-specific action/error/diagnostic state is retained.

## 55. Reset Appearance Settings Semantics

`ResetAppearanceSettings` is a dedicated failed-runtime recovery capability.

It is not implemented by the startup feature calling the normal ready-state settings controller or `SettingsApi.updateAppearanceSettings()`.

The failed runtime does not expose the ordinary application service graph for mutation.

## 56. Reset Scope

When offered, the reset operation means:

```text
reset only AppearanceSettings to canonical default
    ↓
commit bounded recovery mutation
    ↓
retire failed runtime
    ↓
construct fresh runtime
    ↓
normal startup validation
```

Flutter does not broaden this into database reset, application reset, or unrelated settings repair.

## 57. Reset Confirmation

Phase 000 requires concise confirmation before `ResetAppearanceSettings` dispatch.

The confirmation must communicate:

- appearance settings will be reset to their canonical default;
- fresh startup follows;
- unrelated application data is not changed by this recovery action.

Exact localized wording and styling belong to presentation/design implementation.

## 58. Confirmation Ownership

Confirmation is presentation-owned.

The controller exposes the typed reset command but does not:

- show dialogs;
- retain `BuildContext`;
- return callback registries;
- own modal focus.

The controller receives the call only after confirmed user intent exists.

## 59. Routine Actions Do Not Need Confirmation

Phase 000 does not require confirmation for:

- Retry Startup;
- Retry Initialization;
- Export Diagnostics;
- Copy Technical Details;
- Open Data Directory.

These actions do not justify additional modal friction under the current contract.

## 60. Recovery-Operation Failure

A recovery operation may fail with a typed `ApplicationFailure` or `TransportFailure`.

That failure is operation state attached to the attempted recovery.

It does not erase the original startup failure unless a new authoritative runtime generation replaces the original context.

## 61. Original Failure Remains Primary Context

Example:

```text
Startup failure:
Appearance settings invalid

Recovery operation:
Reset Appearance Settings failed
```

The UI must not replace this with one context-free generic error.

## 62. Application Failure During Recovery

A typed `ApplicationFailure` from a recovery operation retains the normal frontend error semantics from SPEC-FE-003.

Presentation uses:

```text
messageKey + SafeContext
```

and may use typed recoverability/retry semantics.

Raw backend strings remain prohibited.

## 63. Stale Runtime Rejection

If an action bound to Runtime A is rejected because Runtime B is already current, the controller must treat this as stale-authority evidence.

It must not simply leave A as current and display a generic operation error.

## 64. Stale Runtime Reconciliation

After stale-generation rejection:

```text
RuntimeApi.getRuntimeState()
```

is used to obtain authoritative current runtime state.

The returned runtime replaces stale A state.

No retry command is silently retargeted.

## 65. Ambiguous Mutating Transport Outcome

A transport failure after dispatch of `RetryStartup` or `ResetAppearanceSettings` is an uncertain outcome.

Example:

```text
RetryStartup(A)
    ↓
backend may retire A / create B
    ↓
transport fails before Flutter receives result
```

Flutter cannot know from the transport failure alone whether the backend mutation occurred.

## 66. No Automatic Mutation Replay

After an ambiguous mutating transport outcome, the startup controller must not automatically call the same mutation again.

This applies even when the failure kind would ordinarily be considered retryable at the transport layer.

The previous command's application effect is uncertain.

## 67. Ambiguous-Outcome Reconciliation

The controller attempts authoritative runtime reconciliation:

```text
transport failure after mutation
    ↓
RuntimeApi.getRuntimeState()
```

Possible results determine the next state.

## 68. Reconciliation Finds Runtime B

If reconciliation returns a replacement Runtime B, Flutter adopts B immediately.

Old Runtime A failure/action/operation state is discarded.

## 69. Reconciliation Finds Runtime A Still Failed

If reconciliation confirms the current runtime is still Runtime A in `StartupFailed`, A remains authoritative.

The previous recovery operation may be recorded as failed/uncertain according to its typed result, and the action may become available again if the authoritative action set still permits it.

The controller does not assume the previous mutation was definitely never admitted solely from transport behavior; it relies on the current runtime snapshot.

## 70. Reconciliation Also Fails

If Flutter cannot obtain current runtime state after an ambiguous pre-ready recovery outcome, state becomes:

```text
StartupState.runtimeUnavailable(...)
```

The controller no longer claims Runtime A remains current.

## 71. Runtime-Unavailable Authority Rule

`runtimeUnavailable` means the current backend runtime generation/state is unknown to Flutter.

It must never be presented as if the last known failed runtime is still authoritative.

## 72. Last-Known Runtime Context

The controller may retain bounded last-known context for diagnostic explanation.

The model must explicitly distinguish:

```text
lastKnownRuntimeContext
```

from current authoritative runtime state.

Presentation uses wording equivalent to `Last known...` when showing it.

## 73. Runtime-Unavailable Presentation

Conceptually:

```text
Argus cannot determine backend state
Localized user-safe message derived from the typed transport failure

Reconnect / Check Again
Exit

Optional explicitly last-known startup information
```

Exact copy is localized frontend content.

## 74. Runtime-Unavailable Recovery

The primary action from `runtimeUnavailable` is authoritative reconciliation.

Conceptually:

```text
re-establish communication as required
    ↓
getRuntimeState()
    ↓
adopt authoritative current runtime
```

It is not replay of the previous mutating recovery command.

## 75. No Previous-Mutation Replay After Reconnect

After communication returns, the controller first reads current runtime state.

It never assumes the user still wants or needs the old mutation and never silently reissues it.

Any further mutating recovery requires a new explicit user action against the newly established current runtime state.

## 76. `runtimeUnavailable` Scope

`runtimeUnavailable` is a pre-ready startup/recovery state.

It does not mean every later post-ready transport issue ejects the application from the ready shell.

Once the app has entered `Ready`, later degradation follows the app/shell status rules from SPEC-FE-004 and the owning runtime/client contracts where continued UI use is safe.

## 77. Diagnostic Recovery Actions

Non-mutating diagnostic actions may include:

```text
ExportDiagnostics
CopyTechnicalDetails
OpenDataDirectory
```

These are shown only when currently available according to the failed runtime/client contract.

They do not change runtime readiness.

## 78. Diagnostic Operation State

Diagnostic operations use explicit narrow state rather than one ambiguous global `isBusy` flag.

When these operations originate from the current failed runtime's advertised recovery actions, invocation preserves that runtime generation binding. The existence of a general `DiagnosticsApi` method does not authorize a stale Runtime A recovery action to execute against Runtime B.

Conceptually:

```text
DiagnosticOperations
├── export
├── technicalDetails
└── openDataDirectory
```

Only operation state needed for actual UI behavior should exist.

## 79. Diagnostic Operations During Runtime Change

Once runtime-changing recovery begins, no new failed-runtime diagnostic operation is started.

This prevents new work from being admitted against a runtime being retired/replaced.

## 80. Export Diagnostics Ownership

Diagnostic archive assembly remains backend-owned under SPEC-BE-003 and SPEC-BE-008.

Flutter does not walk logs/database/configuration paths to assemble its own ZIP.

## 81. Export Flow

Conceptually:

```text
user selects Export Diagnostics
    ↓
presentation obtains approved output destination where required
    ↓
startup controller / DiagnosticsApi
    ↓
backend creates sanitized bundle
    ↓
DiagnosticsExport terminal result
    ↓
local recovery-surface success/failure presentation
```

## 82. Destination Selection

The exact save-dialog/file-picker ownership is implementation-specific and may be frontend/platform mediated.

The controller must not retain `BuildContext` to open the dialog.

A presentation-owned destination selection may be passed as a typed safe request to the controller/client layer.

## 83. Export Cancellation

If the user cancels output destination selection before the backend export begins, that is user cancellation, not an application failure.

No recovery error state is produced.

## 84. Export Result Privacy

The frontend consumes only the safe export result defined by the diagnostics/client contract.

It does not require unrestricted absolute path disclosure merely to present success.

If the presentation already knows a user-selected path, that knowledge remains separate from the backend DTO contract.

## 85. Export Does Not Change Readiness

Successful or failed diagnostics export leaves the current startup failure/runtime readiness unchanged.

The original startup failure remains visible throughout.

## 86. Technical Details Source

Copyable technical details come from the dedicated sanitized diagnostics contract.

They must not be assembled from:

- raw exceptions;
- widget state;
- FRB errors;
- independently discovered filesystem paths;
- arbitrary logs scraped by Flutter.

## 87. Technical Details Loading

Technical details are secondary and may be loaded lazily when the user:

- expands the technical details area; or
- chooses Copy Technical Details.

The feature should not fetch additional diagnostic data during ordinary successful startup merely because the recovery screen supports it.

## 88. Technical Details Generation Binding

Cached technical details belong to the failed runtime generation/failure context that produced them.

Runtime replacement clears the cache.

A late details result from Runtime A cannot overwrite state for Runtime B.

## 89. Technical Details Presentation

Displayed technical details should support practical selection/copying on platforms where Flutter supports it.

Users should not need to manually transcribe trace identifiers or diagnostic information from decorative non-selectable text.

## 90. Clipboard Ownership

The backend/client owns obtaining sanitized technical details.

The presentation/platform layer owns the actual clipboard operation.

Conceptually:

```text
controller -> TechnicalDetails
presentation -> clipboard
```

The controller may return a safe copy payload as a caller-owned next action according to the narrow exception allowed by SPEC-FE-002.

## 91. Copy Success Feedback

Copy success may be presented through a transient message local to the startup/recovery surface.

It does not require the ready application's global notice host because the ready shell is not active.

## 92. Technical-Details Failure

Failure to load technical details is attached to the technical-details operation.

It does not replace the original startup failure or hide primary recovery actions.

## 93. Open Data Directory

`OpenDataDirectory` is shown only when the current failed runtime/client contract exposes it.

The frontend does not reconstruct or guess the data-directory path.

It invokes the dedicated capability.

## 94. Open Data Directory Result

Success leaves startup/recovery state unchanged.

Failure is attached to that action and uses typed frontend failure presentation.

## 95. Exit with an Inspectable Failed Runtime

When a usable failed runtime exists, Exit follows the generation-validated failed-runtime recovery path (conceptually `RuntimeApi.exitFailedRuntime(expectedRuntimeInstanceId)` or an equivalent typed bound action):

```text
StartupFailed
    ↓
shutdown request
    ↓
ShuttingDown
    ↓
Stopped
    ↓
frontend process/window termination
```

Exact platform termination mechanics are implementation details.

The recovery intent remains bound to the failed runtime that advertised Exit. If that generation is stale, the action is rejected/reconciled rather than silently applied to a replacement runtime. The general application shutdown capability is distinct and must not be substituted merely to make the stale recovery action succeed; a later explicit window-close/Exit against the now-current lifecycle is a new user intent.

## 96. Exit without a Usable Runtime Contract

If initial bootstrap failed before Flutter obtained a trustworthy runtime contract, frontend termination remains available.

The UI/controller must not pretend backend shutdown succeeded when no usable backend channel exists.

The user must not become trapped because a backend shutdown call cannot be performed.

## 97. Window Close During Startup/Failure

Application window-close behavior should converge on the normal root shutdown path where a usable runtime exists and it is safe to do so.

If no usable client/runtime exists, normal frontend termination remains permitted.

Detailed native window integration is outside this specification.

## 98. Recovery Content Hierarchy

The startup-failure screen should present information in this semantic order:

```text
1. failure heading
2. short user-safe explanation
3. primary recovery action
4. applicable secondary recovery actions
5. current recovery-operation error/status
6. technical details / diagnostics
7. exit
```

Exact layout belongs to SPEC-FE-007.

## 99. Progressive Disclosure

Technical/diagnostic information is secondary.

The initial failure view should first answer:

- what broad problem occurred;
- what the user can safely do next.

Detailed diagnostics are available without overwhelming the primary recovery path.

## 100. Recovery Status Placement

Runtime-changing recovery progress/error is presented near the primary recovery context.

Diagnostic operation progress/error is presented near the corresponding diagnostic action.

Avoid one generic error bucket where the user cannot tell which operation failed.

## 101. Recovery Running State

During runtime-changing recovery, presentation may show text equivalent to:

```text
Retrying startup…
```

or:

```text
Resetting appearance settings and restarting…
```

while preserving the original failure explanation until a new authoritative runtime generation is known.

## 102. Operation Retry

A failed operation may be retried when:

- the current authoritative runtime generation remains the same;
- the action is still advertised/available;
- the owning operation semantics permit retry;
- no other conflicting runtime-changing operation is in flight.

Runtime replacement invalidates the old operation state instead of retrying it.

## 103. Widget-Local Interaction State

The following remain widget/presentation-local unless implementation proves broader ownership is necessary:

- technical-details expanded/collapsed state;
- confirmation-dialog visibility;
- local focus state;
- hover/pressed state.

They are not route state and do not belong in backend/runtime models.

## 104. Startup State Is Not Route State

Do not encode transient recovery state in URI parameters.

Prohibited concepts include:

```text
/startup?retrying=true
/recovery?exporting=true
/recovery?detailsExpanded=true
```

SPEC-FE-004 owns durable routing; FE-005 owns transient startup/recovery operations.

## 105. Route Intent Preservation

The startup feature does not own the user's intended ready-state destination.

SPEC-FE-004 owns preservation and revalidation of that route intent.

FE-005 exposes readiness changes; routing reacts to them.

## 106. Startup/Recovery History

Startup and recovery surfaces do not become ordinary history entries.

After successful readiness, Back must not traverse:

```text
Ready route
→ recovery screen
→ startup screen
```

unless a future explicit navigation contract deliberately makes such screens user-addressable, which Phase 000 does not.

## 107. Runtime Events

The startup feature may consume the shared typed runtime-event projection where it is useful to know that authoritative state may have changed.

It does not establish its own FRB/native event stream.

## 108. Event-Assisted Reconciliation

A relevant runtime event may trigger:

```text
RuntimeApi.getRuntimeState()
```

or another approved authoritative refresh.

The event itself is not treated as the full authoritative runtime snapshot when the backend contract says state-change events are notification-first.

## 109. Terminal Correctness Does Not Depend on Events

Suppressing/dropping the terminal runtime event must not permanently strand startup in `Starting`.

The startup/client orchestration must provide an authoritative non-event-dependent path to terminal:

```text
Ready
```

or:

```text
StartupFailed
```

## 110. Valid Terminal-Observation Strategies

A conforming implementation may use:

```text
initialize/recovery call returns terminal authoritative RuntimeState
```

or:

```text
operation yields Starting
    ↓
bounded authoritative runtime reconciliation
    ↓
terminal RuntimeState
```

or another deterministic client-level mechanism consistent with SPEC-FE-003.

The exact synchronization primitive is implementation-planned.

## 111. No Guessed Delay for Correctness

The controller must not use arbitrary `Future.delayed` sleeps or elapsed-time thresholds as startup authority.

Examples of prohibited correctness logic:

```text
wait 500 ms then query because startup should be done
show spinner five seconds then assume failure
```

Client-owned transport timeout semantics may produce typed failure/uncertainty, but UI timing itself does not decide runtime state.

## 112. Startup Operation Stale-Completion Protection

Every async bootstrap/recovery/diagnostics operation uses the stale-completion safeguards from SPEC-FE-002.

A completion may publish only when it still belongs to:

- the current controller lifecycle;
- the current relevant runtime generation;
- the current operation attempt.

## 113. Controller Disposal

If the startup controller is disposed/replaced during app teardown or tests, pending completions cannot publish obsolete state.

Disposal does not imply an admitted backend recovery command was cancelled unless the backend/client contract explicitly supports that cancellation.

## 114. No Generic Recovery Event Bus

Do not introduce an application-wide effect/recovery bus merely to show startup actions.

The startup feature owns its recovery operations directly through typed client APIs and its own controller state.

## 115. Accessibility Baseline Relationship

SPEC-FE-007 owns the comprehensive design-system/accessibility baseline.

FE-005 nevertheless requires structural startup/recovery accessibility now so the first failure experience is operable before FE-007 supplies detailed tokens/components.

## 116. Failure-State Focus Entry

When the UI transitions from loading to an actionable failure state, focus moves deliberately once to the recovery surface's semantic heading/container or an equivalent appropriate focus target.

The goal is to announce the new context to keyboard/screen-reader users.

Repeated controller rebuilds must not repeatedly steal focus.

## 117. Recovery Operation Focus Stability

Operation transitions such as:

```text
idle -> running -> failed
```

should preserve the user's current focus where practical.

State changes may be announced through semantics/live-region behavior, but focus should not jump merely because a request completed.

## 118. Confirmation Focus

When Reset Appearance Settings opens confirmation:

- modal focus enters the dialog;
- cancel returns focus to the reset action where practical;
- confirm transitions focus according to the active recovery/loading surface.

Exact Flutter focus primitives belong to implementation.

## 119. Keyboard Operation

Every interactive recovery control must be operable through normal keyboard traversal and activation as well as pointer/touch input.

Use semantic Flutter controls rather than gesture-only custom hit targets unless a custom component has an equivalent accessibility implementation.

## 120. Non-Color State Communication

Failure, running, unavailable, and disabled states must have textual/semantic cues.

Color may reinforce state but cannot be the only indicator.

## 121. Progress Semantics

Indeterminate startup progress exposes a stable useful semantic label such as the localized equivalent of:

```text
Starting Argus
```

Animation frames/rebuilds must not produce continuous meaningless accessibility announcements.

## 122. Technical Details Accessibility

The technical-details section must provide:

- meaningful expand/collapse semantics;
- selectable/readable content;
- an explicit Copy action;
- meaningful success/failure feedback;
- labeled controls rather than icon-only ambiguity.

## 123. Responsive Behavior

Startup/recovery surfaces must remain usable across Compact, Medium, Expanded, and Large global size classes.

They do not need separate business-state models per width.

Exact layout, max-width, spacing, and responsive composition belong to SPEC-FE-007.

## 124. No Shell Dependency

The startup/recovery feature must render without the ready `ApplicationShell` being active.

It must not depend on shell-only providers/widgets for critical recovery actions or diagnostic feedback.

## 125. Local Transient Feedback

Startup/recovery may use local transient confirmation for actions such as successful Copy Technical Details or Export Diagnostics.

It does not require the ready shell's global toast host.

Durable/retry-relevant operation errors remain represented in controller/presentation state.

## 126. Controller Tests

Ordinary controller tests use the narrowest Argus-owned fakes available, including as appropriate:

- `ClientBootstrap` fake;
- `RuntimeApi` fake;
- `DiagnosticsApi` fake;
- controlled runtime-event projection.

They do not require real Rust, FRB, SQLite, or platform dialogs.

## 127. Initial Bootstrap Test Matrix

Tests must prove at least:

```text
initial
→ AsyncLoading
→ AsyncData(ready)
```

```text
initial
→ AsyncLoading
→ AsyncData(startupFailed)
```

```text
initial
→ AsyncLoading
→ AsyncError(TransportFailure)
```

The second case prevents regression into collapsing an inspectable failed runtime into transport failure.

## 128. Bootstrap Retry Tests

Given attempt A transport failure:

```text
Retry Initialization
→ attempt B
```

verify:

- a fresh valid bootstrap attempt occurs;
- no runtime generation is fabricated;
- successful B result replaces A failure;
- late A completion cannot overwrite B state;
- a second retry request while B is in flight does not create attempt C.

## 129. Backend Readiness Projection Tests

Verify `AppReadiness` does not become `ready` for:

- initial bootstrap loading;
- `Uninitialized`;
- `Starting`;
- `StartupFailed`;
- `runtimeUnavailable`.

Only authoritative backend `Ready` produces `AppReadiness.ready`. SPEC-FE-006 separately verifies that first-shell presentation still waits for authoritative appearance initialization.

## 130. Recovery-Action Availability Tests

Given backend actions:

```text
[RetryStartup, ExportDiagnostics]
```

verify Reset Appearance Settings is not presented.

Given:

```text
[ResetAppearanceSettings, RetryStartup, ExportDiagnostics]
```

verify targeted reset receives the approved primary presentation priority.

## 131. Runtime-Changing Single-Flight Tests

Dispatch `RetryStartup` twice before first completion.

Verify exactly one backend/client mutation is admitted.

Repeat for `ResetAppearanceSettings`.

Also verify a runtime-changing command prevents newly starting conflicting failed-runtime actions while it is in flight.

## 132. Reset Confirmation Widget Tests

Verify:

```text
activate Reset Appearance Settings
→ confirmation
→ cancel
→ zero controller reset calls
```

and:

```text
activate Reset Appearance Settings
→ confirmation
→ confirm
→ exactly one controller reset call
```

Desktop-capable tests should also verify appropriate focus behavior.

## 133. Runtime-Replacement Tests

Given Runtime A `StartupFailed`:

```text
RetryStartup(A)
→ Runtime B Starting
```

verify all A-specific:

- failure;
- available actions;
- runtime recovery error;
- diagnostic operation state;
- cached technical details;

are removed.

Then verify B may independently reach `Ready` or a new `StartupFailed`.

## 134. Stale-Generation Tests

Given controller state for A while backend is already B:

```text
action(A)
→ stale-generation ApplicationFailure
```

verify authoritative runtime reconciliation occurs and B replaces A.

The test must prove the controller never silently retries the action against B.

This includes stale diagnostic recovery actions and failed-runtime Exit: neither may silently execute against Runtime B merely because their underlying focused/general capability also exists for B.

## 135. Ambiguous Transport-Outcome Tests

Simulate:

```text
RetryStartup(A)
→ backend may have accepted mutation
→ TransportFailure before result
```

Verify:

1. the mutation is not automatically repeated;
2. `getRuntimeState()` is attempted;
3. if B is current, B is adopted;
4. if A remains current in `StartupFailed`, A remains authoritative;
5. if reconciliation fails, state becomes `runtimeUnavailable`.

Repeat the same safety principle for targeted reset.

## 136. Runtime-Unavailable Recovery Tests

From `runtimeUnavailable`, the reconnect/check operation must:

- attempt to re-establish/read authoritative runtime state;
- never replay the previous mutating recovery command;
- replace last-known context when current state becomes known.

## 137. Recovery-Operation Failure Tests

For application failure during Retry/Reset, verify:

- original startup failure remains visible/stateful;
- operation failure is attached to the recovery operation;
- action may be retried only if still valid for the same current generation.

## 138. Diagnostics Export Tests

Verify:

- original startup failure remains authoritative while export runs;
- user cancellation before export produces no error;
- successful export does not change readiness;
- export failure is scoped to export operation state;
- runtime replacement prevents old export completion from publishing into the new generation.

## 139. Technical Details Tests

Verify:

- technical details are lazy unless already present;
- returned data comes through the typed diagnostics/client seam;
- runtime replacement clears cached details;
- failure to load details does not erase the startup failure;
- copy payload remains safe presentation data.

## 140. Open Data Directory Tests

Verify the action is shown only when advertised/available.

Verify success leaves startup readiness unchanged and failure remains local to the action.

## 141. Exit Tests

With a valid failed runtime, verify the controller requests normal shutdown and reaches the observable shutdown states as defined by the client contract.

With initial bootstrap failure and no usable runtime, verify the frontend still has a safe termination path and does not require a fabricated shutdown result.

## 142. Event-Loss Correctness Test

A required controller/client integration test suppresses the terminal runtime event.

Startup/recovery must still reach authoritative `Ready` or `StartupFailed` through the non-event correctness path.

This proves compatibility with the bounded best-effort event contract.

## 143. No Arbitrary Sleep Tests

Async startup/recovery tests use:

- controlled futures/completers;
- explicit runtime snapshots;
- explicit event injection;
- fake API completion control.

Do not use arbitrary delays to make races likely to finish.

## 144. Widget-State Matrix

Startup/recovery widget tests should cover at least:

- initial loading;
- initial bootstrap transport failure;
- runtime `Uninitialized`;
- runtime `Starting`;
- runtime `StartupFailed`;
- targeted recovery available;
- targeted recovery absent;
- runtime-changing recovery running;
- runtime-changing recovery failed;
- diagnostic export running/succeeded/failed;
- technical details collapsed/expanded;
- runtime unavailable;
- representative responsive constraints;
- keyboard traversal/focus;
- progress/failure semantics.

Detailed golden/design-system coverage remains under SPEC-FE-007.

## 145. Routing Integration Tests

Combine FE-004 and FE-005 to verify:

```text
requested /settings
    ↓
startup loading
    ↓
StartupFailed
    ↓
RetryStartup
    ↓
Runtime B Ready
    ↓
/settings
```

Verify:

- intended route survives;
- recovery does not become ordinary history;
- route is revalidated after replacement;
- Back does not traverse startup/recovery surfaces.

## 146. Injected Backend Startup-Failure Integration

Phase 000 requires at least one controlled real bridge/backend startup-failure scenario proving:

```text
injected backend mandatory startup failure
    ↓
typed StartupFailed reaches Flutter
    ↓
applicable recovery actions render
    ↓
technical details can be obtained
    ↓
diagnostics export can be invoked
```

Fake-only widget tests do not replace this cross-boundary evidence.

## 147. Test Isolation

Ordinary startup-controller/widget tests do not require:

- real native Rust library;
- actual database corruption/locking;
- real filesystem permission manipulation;
- network/provider access;
- real diagnostic archive generation.

Use focused fakes for most tests and reserve real cross-boundary cases for the appropriate integration layer under CONV-TEST-001.

## 148. Static Architecture Verification

Where economical, checks should prevent:

- startup presentation importing generated FRB code;
- startup controller calling `go_router`;
- router calling `RuntimeApi`/recovery methods;
- startup controller retaining `BuildContext`;
- startup feature using the normal Settings controller for failed-runtime reset;
- raw exception strings being rendered as user-facing recovery text;
- duplicate native runtime-event subscriptions;
- route parameters encoding transient recovery-operation state.

## 149. Semantic Review Obligations

Code review and tests must explicitly inspect semantic cases that static checks cannot prove fully:

- bootstrap failure vs `StartupFailed` distinction;
- runtime-generation replacement;
- single-flight correctness;
- ambiguous mutation outcome handling;
- no automatic mutation replay;
- stale-action reconciliation;
- event-loss terminal correctness;
- focus not being repeatedly stolen;
- technical details remaining secondary/sanitized;
- absence of unavailable recovery actions.

## 150. Prohibited Patterns

The following are prohibited by default:

```text
StartupFailed represented as generic AsyncError
router invoking startup/recovery APIs
feature calling generated FRB bindings
hard-coded recovery action inferred from error string
showing unavailable recovery actions disabled
RetryStartup without expected runtime identity semantics
automatic mutating recovery retry after transport failure
silent stale-action retargeting
last-known runtime displayed as current after reconciliation loss
fabricated startup percentage
fabricated current startup phase
arbitrary delayed sleep used as readiness authority
normal Settings controller used for startup recovery reset
Flutter assembling diagnostic ZIP itself
raw backend exception used as UI message
recovery operation replacing original startup failure context
old runtime diagnostic/action state retained after replacement
startup/recovery encoded as ordinary route history
```

## 151. Derived Implementation Decisions

The following are implementation details as long as this contract is preserved:

- exact Freezed class/variant names;
- exact Riverpod provider names;
- exact internal operation-state factoring;
- exact production adapter/provider shape implementing `ClientBootstrap` over `ArgusClient.initialize()`;
- exact mechanism that performs bounded authoritative polling/reconciliation when a runtime operation temporarily returns `Starting`;
- exact clipboard abstraction;
- exact file-picker/save-dialog abstraction;
- exact widgets used for progressive disclosure and confirmation;
- exact localized strings;
- exact visual layout and animation.

## 152. Decisions Requiring Future Specification

Future work may refine:

- richer startup phase/progress reporting if the backend deliberately publishes it;
- additional typed recovery actions;
- migration/repair workflows beyond Phase 000;
- destructive database reset/restore UX;
- external support-ticket/report upload flows;
- post-ready fatal-runtime replacement UX;
- platform-specific installer/update UX for contract mismatch.

Any such change must preserve typed authority, runtime-generation binding, and no-guess/no-replay rules unless explicitly superseded.

## 153. Acceptance Criteria

SPEC-FE-005 is satisfied when:

1. `app/bootstrap` owns root client construction and supplies only the initialization-only `ClientBootstrap` seam to `features/startup`, which owns startup/recovery behavior.
2. One startup controller is the frontend authority for pre-ready startup/recovery state.
3. Initial client bootstrap uses an outer `AsyncValue` contract.
4. Initial transport/bootstrap failure remains distinct from backend `StartupFailed`.
5. Backend `StartupFailed` is represented as loaded inspectable state.
6. The startup-state model explicitly represents `uninitialized`, `starting`, `ready`, `startupFailed`, `runtimeUnavailable`, and terminal shutdown states where observable.
7. App composition consumes only a narrow backend-readiness projection from the startup feature.
8. Authoritative backend `Ready` is mandatory for normal-shell entry, while SPEC-FE-006 owns the additional initial appearance-authority prerequisite for first-shell presentation.
9. Mandatory startup does not wait for deferred library/provider/indexing/metadata work.
10. Startup UI uses indeterminate progress unless a future authoritative progress contract exists.
11. Flutter does not fabricate current startup phases or completion percentages.
12. Startup failure text comes from typed application-error semantics rather than raw backend messages.
13. Recovery actions are rendered only when currently advertised by the backend/runtime contract.
14. Missing recovery actions are absent rather than speculative disabled controls.
15. Targeted appearance reset is prioritized over generic retry when both are offered.
16. Runtime-bound recovery carries the expected current `RuntimeInstanceId` semantics.
17. Runtime-changing recovery is controller-enforced single-flight.
18. Reset Appearance Settings uses the dedicated recovery contract, not the normal Settings mutation path.
19. Reset Appearance Settings requires concise confirmation.
20. Successful retry/reset creates/adopts a fresh runtime generation.
21. Old failure/action/diagnostic state is discarded when a replacement runtime becomes authoritative.
22. Recovery-operation failure does not erase the original startup failure.
23. Stale-generation rejection triggers authoritative runtime reconciliation.
24. Ambiguous transport outcome after mutating recovery does not automatically replay the mutation.
25. Ambiguous outcomes trigger authoritative runtime reconciliation.
26. Failed reconciliation produces explicit `runtimeUnavailable` rather than false authority.
27. `runtimeUnavailable` reconnection checks current state and never replays the previous mutation automatically.
28. Last-known runtime context is explicitly modeled/presented as non-authoritative.
29. Post-ready temporary degradation is not automatically forced into this pre-ready recovery state.
30. Diagnostic export remains backend-owned and sanitized.
31. Technical details come from the dedicated sanitized diagnostics contract.
32. Technical details are secondary, lazy where practical, and runtime-generation-bound.
33. Clipboard execution remains presentation/platform-owned.
34. Open Data Directory is exposed only when the current runtime/client contract permits it.
35. Exit remains possible whether or not a usable backend runtime exists.
36. Event delivery can accelerate reconciliation but is not required for terminal startup correctness.
37. Startup correctness does not depend on arbitrary UI delays.
38. Startup/recovery state remains outside normal ready-route history.
39. Intended route preservation/revalidation remains owned by SPEC-FE-004.
40. Failure-state transitions receive deliberate accessible focus without repeated focus stealing.
41. Recovery actions are keyboard-operable semantic controls.
42. Progress/failure state is not communicated by color alone.
43. Ordinary startup/controller/widget tests require no real Rust backend.
44. Bootstrap distinction, single-flight, stale-generation, ambiguous-outcome, runtime-unavailable, diagnostics, and event-loss cases have deterministic tests.
45. Phase 000 contains at least one injected real bridge/backend startup-failure integration scenario.

## 154. Phase 000 Minimum Implementation

Phase 000 requires at least:

```text
features/startup/application
├── StartupController
├── StartupState
├── AppReadiness projection
├── bootstrap retry
├── RuntimeApi recovery
├── runtime reconciliation
└── DiagnosticsApi interaction

features/startup/presentation
├── blocking startup view
├── bootstrap failure view
├── startup recovery view
├── runtime unavailable view
├── Reset Appearance Settings confirmation
├── technical-details disclosure/copy
└── diagnostic export/open-data-directory actions as available
```

with:

- real root client initialization;
- real mapped `RuntimeState` handling;
- generation-bound recovery;
- one real injected startup-failure bridge integration scenario;
- deterministic fake-based controller/widget coverage.

No library, games, jobs, sources, metadata, artwork, scanning, or provider feature work is required by this specification.

## 155. Out of Scope

This specification intentionally leaves the following to later contracts:

- exact design tokens, visual hierarchy, responsive spacing, and final component styling;
- final localized wording catalogs;
- appearance-settings normal ready-state workflow;
- post-ready fatal backend replacement UX beyond the distinction preserved here;
- destructive database reset/restore workflows;
- migration repair tooling beyond current backend-advertised recovery;
- external support/service upload;
- automatic application updating or installer repair;
- advanced diagnostic viewers.

It does not define a generic recovery DSL, generic effect bus, or second runtime authority in Flutter.

## 156. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](../backend/spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](../backend/spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](spec-fe-004-routing-and-adaptive-application-shell.md)
- [SPEC-FE-006 — Appearance Settings and Theme Application](spec-fe-006-appearance-settings-and-theme-application.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [CONV-DOC-001 — Documentation and Codex Result Conventions](../../conventions/conv-doc-001-documentation-and-codex-result-conventions.md)
- [Frontend Specifications Index](README.md)
- [Subsystem Specification Template](../../templates/subsystem-specification.md)
