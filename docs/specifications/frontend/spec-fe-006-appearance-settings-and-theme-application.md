# Appearance Settings and Theme Application

**Document ID:** SPEC-FE-006  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-15  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-007, SPEC-BE-008, SPEC-FE-001, SPEC-FE-002, SPEC-FE-003, SPEC-FE-004, SPEC-FE-005, SPEC-X-001, SPEC-X-002, CONV-REPO-001, CONV-FLUTTER-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the Flutter appearance-settings and root-theme application contract for Argus ROM Toolkit.

It translates the authoritative backend `AppearanceSettings` capability, focused `SettingsApi`, Riverpod state conventions, application routing/readiness rules, and unified runtime-event semantics into one implementation-ready frontend workflow.

Phase 000 exposes one appearance preference:

```text
ThemeMode
├── System
├── Light
└── Dark
```

The frontend must support all three values, persist changes immediately, reconcile through authoritative reads, apply confirmed theme changes without restarting Argus, and restore the persisted preference before the first normal application shell is presented.

The central invariant is:

> **Appearance is an application-lifetime, query-authoritative frontend capability: backend readiness and shell presentation readiness remain distinct, the normal shell never appears before authoritative appearance is known, optimistic input cannot become root theme authority, every mutation resolves through authoritative reconciliation, and event loss, transport ambiguity, or runtime replacement can reduce synchronization confidence without creating a second settings truth or inventing fallback state.**

## 2. Responsibilities

This specification owns frontend rules for:

- appearance-settings feature ownership;
- application-lifetime appearance controller state;
- frontend `AppearanceSettings` and `ThemeMode` semantics;
- initial authoritative appearance loading;
- the frontend presentation-readiness gate required before the normal shell appears;
- bootstrap-theme use before authoritative appearance exists;
- root `MaterialApp` theme-mode derivation;
- Settings destination Theme Mode interaction;
- immediate-persistence behavior;
- optimistic control presentation;
- confirmed versus presented settings state;
- single-flight save behavior;
- authoritative post-mutation reconciliation;
- definite mutation failure rollback;
- ambiguous transport-outcome reconciliation;
- synchronization-uncertainty behavior;
- `AppearanceSettingsChanged` handling;
- event coalescing and follow-up reconciliation;
- event-gap and reconnect handling;
- runtime-generation invalidation of appearance authority;
- system-brightness behavior when Theme Mode is `System`;
- focused appearance accessibility requirements;
- deterministic controller, widget, routing, event, runtime-replacement, and restart verification.

## 3. Non-Responsibilities

This specification does not define:

- backend appearance-settings persistence, validation, Unit of Work behavior, or change-event publication, owned by SPEC-BE-005;
- backend runtime lifecycle or runtime-generation replacement semantics, owned by SPEC-BE-004 and SPEC-BE-007;
- bridge DTO serialization or native transport syntax, owned by SPEC-BE-008;
- client error mapping, transport policy, or focused API signatures, owned by SPEC-FE-003;
- general Riverpod/controller conventions, owned by SPEC-FE-002;
- route graph, branch navigation, route restoration, or shell structure, owned by SPEC-FE-004;
- backend startup/recovery orchestration and presentation, owned by SPEC-FE-005;
- exact color tokens, typography, component styling, focus-ring visuals, theme-data construction, breakpoint values, or comprehensive accessibility baseline, owned by SPEC-FE-007;
- generic settings infrastructure for future settings domains;
- restart-required settings workflow;
- settings import/export;
- cloud synchronization;
- optimistic-concurrency revisions, ETags, or version fields;
- a frontend persistence/cache subsystem.

## 4. Governing Principles

Appearance behavior follows these rules:

1. There is one frontend appearance-settings authority.
2. The Settings destination and root application theme consume that same authority.
3. Rust remains authoritative for persisted appearance settings.
4. Backend `Ready` is necessary but not sufficient for the first normal shell presentation.
5. The first normal shell requires one successful authoritative appearance read.
6. A pre-authority bootstrap presentation theme is not persisted appearance authority.
7. Initial read failure never silently substitutes `System`.
8. The Theme Mode control may present a pending optimistic choice.
9. The root application theme derives only from the last authoritative appearance read.
10. Appearance mutations are single-flight during Phase 000.
11. The frontend submits the complete desired appearance aggregate.
12. Successful mutation acknowledgement does not make the submitted aggregate authoritative.
13. Successful and ambiguous mutations reconcile through `SettingsApi.getAppearanceSettings()`.
14. `AppearanceSettingsChanged` is notification-only and never carries frontend authority.
15. Event loss, gaps, or reconnect uncertainty trigger authoritative refresh rather than event reconstruction.
16. Runtime-generation replacement invalidates appearance synchronization confidence.
17. Stale async completions cannot publish into a newer runtime/controller attempt.
18. Once synchronization is uncertain, further aggregate mutation is blocked until a fresh authoritative read succeeds.
19. `System` remains a persisted preference while effective light/dark rendering follows platform brightness.
20. Platform brightness changes do not generate settings persistence traffic.

## 5. Architectural Position

The appearance feature sits between the focused client API, root composition, and Settings presentation:

```text
SettingsApi
    ↓
features/settings/application
    ↓
AppearanceSettingsController
    ├── authoritative appearance state
    ├── save operation state
    └── synchronization state
    ↓
    ├── features/settings/presentation
    │       ↓
    │   Theme Mode control
    │
    ├── app theme derivation
    │       ↓
    │   MaterialApp.themeMode
    │
    └── app presentation-readiness derivation
            ↓
        routing/shell gate
```

No generated bridge DTO, FRB type, SQLite detail, or backend application object enters the feature.

## 6. Feature Ownership

Appearance settings remain under the Settings feature.

Conceptually:

```text
features/settings/
├── settings.dart
├── application/
│   ├── appearance_settings_controller.dart
│   └── appearance_settings_state.dart
└── presentation/
    ├── settings_screen.dart
    └── appearance/
        └── theme_mode_control.dart
```

Exact filenames are implementation details governed by SPEC-FE-001.

The root application does not duplicate this state in `app/` merely because the selected theme affects `MaterialApp`.

## 7. Application-Lifetime Authority

Appearance settings affect root application presentation and therefore are one of the intentionally application-lifetime state owners allowed by SPEC-FE-002.

The controller may remain alive across route changes.

This does not imply all Settings feature state becomes application-lifetime.

Future settings sections, local form interactions, disclosure state, focus, and route-local presentation remain scoped to their natural owners.

## 8. Focused Dependency Rule

The appearance controller depends on the narrow focused API:

```text
AppearanceSettingsController
    ↓
SettingsApi
```

It does not depend directly on:

- `ArgusClient`;
- `ClientBootstrap`;
- generated bridge bindings;
- bridge DTOs;
- SQLite;
- backend repositories;
- `BuildContext`;
- `go_router`.

Runtime-generation invalidation and event synchronization use approved app-level typed projections/signals rather than retrieving the root client for convenience.

## 9. Frontend Appearance Model

The client layer maps bridge representation into an immutable frontend model conceptually equivalent to:

```text
AppearanceSettings
└── themeMode: ThemeMode
```

Phase 000 `ThemeMode` contains exactly:

```text
system
light
dark
```

The frontend model contains no:

- persistence singleton identifier;
- schema revision;
- timestamp;
- database metadata;
- optimistic-concurrency revision.

## 10. Typed Theme Mode

Application and feature code use a typed `ThemeMode` value.

Raw strings such as:

```text
"system"
"light"
"dark"
```

remain bridge serialization concerns where applicable and are mapped before ordinary feature use.

Invalid required bridge representations follow the typed contract-mismatch behavior from SPEC-FE-003 rather than silently defaulting to `system`.

## 11. Public Controller Envelope

The public appearance controller state is conceptually:

```text
AsyncValue<AppearanceSettingsState>
```

The outer `AsyncValue` represents whether the feature has ever obtained an authoritative usable appearance snapshot for the current required presentation lifecycle.

## 12. Initial Loading

Before the first authoritative appearance snapshot exists:

```text
AsyncLoading
```

is correct.

The controller performs:

```text
SettingsApi.getAppearanceSettings()
```

once backend readiness permits the settings capability to be used.

## 13. Initial Read Failure

If the first appearance read fails before any usable appearance snapshot exists:

```text
AsyncError(ClientFailure)
```

is correct.

The controller must not fabricate:

```text
AppearanceSettings(themeMode: system)
```

merely to enter the shell.

## 14. Loaded Appearance State

After the first authoritative read succeeds, controller state remains loaded.

Conceptually:

```text
AppearanceSettingsState.ready
├── confirmed: AppearanceSettings
├── presented: AppearanceSettings
├── saveOperation
└── synchronization
```

The exact Freezed factoring may use nested immutable unions.

The semantic distinctions are mandatory even if implementation naming differs.

## 15. `confirmed` Meaning

`confirmed` is the most recent appearance aggregate successfully returned by the authoritative focused read for the relevant current runtime generation.

It must never be assigned solely from:

- the object submitted to a mutation;
- an `AppearanceSettingsChanged` notification;
- a widget selection;
- a guessed default;
- elapsed time.

## 16. `presented` Meaning

`presented` is the appearance value currently shown by the editable Settings UI.

When no mutation is pending and synchronization is healthy:

```text
presented == confirmed
```

During optimistic Theme Mode selection, `presented` may temporarily differ from `confirmed`.

## 17. Save Operation State

Save state should represent semantically distinct conditions rather than one boolean.

Conceptually:

```text
AppearanceSaveOperation
├── idle
├── saving(requested)
├── failed(applicationFailure)
├── outcomeUnknown(transportFailure)
└── committedButUnreconciled(readFailure)
```

Exact factoring may differ where equivalent semantics are preserved.

## 18. Synchronization State

Synchronization state describes confidence that the last authoritative snapshot is current.

Conceptually:

```text
AppearanceSynchronization
├── synchronized
├── refreshing
└── uncertain(failure)
```

A value may remain renderable while synchronization is uncertain, but it is explicitly last-known rather than proven current.

## 19. Loaded-State Failure Rule

Once a confirmed snapshot exists, routine save or refresh failure must not replace the controller state with outer:

```text
AsyncError
```

The loaded state remains available and records the specific operation/synchronization failure.

This preserves a usable root theme and avoids turning a preference synchronization issue into application-wide loading/error replacement.

# Application Presentation Readiness

## 20. Backend Readiness Remains Separate

SPEC-FE-005 remains authoritative for backend startup readiness.

Its positive state answers:

> The current Rust runtime is authoritative `Ready`.

It does not imply Flutter has already loaded every root presentation dependency required before showing the normal shell.

## 21. Appearance Presentation Prerequisite

Phase 000 requires the persisted appearance selection to be restored before the main shell is shown.

Therefore:

```text
backend Ready
    ↓
authoritative appearance read
    ↓
appearance authority available
    ↓
normal shell may be presented
```

This is a frontend composition rule, not a ninth backend startup phase.

## 22. Derived Presentation Readiness

App composition derives a narrow state conceptually equivalent to:

```text
ApplicationPresentationReadiness
├── preReady
├── appearanceInitializing
├── appearanceUnavailable
└── ready
```

It is derived from:

```text
StartupController.AppReadiness
+
AppearanceSettingsController state
```

It owns no backend or settings data independently.

## 23. Readiness Evaluation Order

The semantic evaluation order is:

```text
backend not Ready
→ FE-005 startup/recovery surface

backend Ready
+ appearance has no authoritative snapshot yet
→ appearance initialization surface

backend Ready
+ appearance authoritative snapshot available
→ normal ready shell
```

An in-flight appearance completion cannot force shell entry after backend readiness has ceased to be current.

This first-shell presentation gate is not a recurring global blocker. After the normal shell has been admitted from a real authoritative appearance snapshot, later appearance synchronization uncertainty does not by itself revoke shell presentation readiness; the shell retains the last-known theme while Settings exposes the uncertainty and attempts authoritative reconciliation. A new application lifecycle with no usable appearance snapshot must satisfy the gate again.

## 24. Router Consumption

SPEC-FE-004 routing consumes the app-owned presentation-readiness projection for normal-shell admission.

The router does not:

- call `SettingsApi`;
- initialize the appearance controller;
- apply theme mutation;
- interpret `ClientFailure`;
- fabricate fallback readiness.

Routing remains pure composition policy.

## 25. Intended Route Preservation

The additional appearance gate does not change FE-004 intended-route semantics.

Example:

```text
requested /settings
    ↓
backend startup/recovery as needed
    ↓
backend Ready
    ↓
appearance read
    ↓
presentation Ready
    ↓
/settings
```

Startup and appearance initialization surfaces do not become ordinary user navigation history.

## 26. Initial Appearance Failure Surface

When the backend is Ready but the first appearance read fails, app composition displays a Settings-owned root failure surface.

Conceptually:

```text
Argus could not load appearance settings

The surface presents the localized user-safe message derived from the typed `ClientFailure` contract.

Retry
Exit
```

It is not:

- backend `StartupFailed`;
- a normal Settings page inside the shell;
- a router not-found surface.

The Retry action belongs to the appearance controller. Exit remains an app-lifecycle/presentation action using the existing application shutdown policy; the appearance controller does not gain `RuntimeApi` or root-client dependency merely to terminate the application.

## 27. Initial Appearance Retry

Retry performs only:

```text
SettingsApi.getAppearanceSettings()
```

It does not:

- retry backend startup;
- reset persisted appearance settings;
- resubmit a previous mutation;
- substitute `System`.

If persisted appearance data is structurally invalid, backend startup should already have prevented `Ready` under SPEC-BE-005 and exposed the certified recovery path through SPEC-FE-005.

## 28. Bootstrap Presentation Theme

Flutter requires some visual styling before authoritative appearance settings exist.

Startup, recovery, and appearance-initialization surfaces may use a stable bootstrap theme defined by the frontend design-system implementation.

That bootstrap theme:

- is presentation scaffolding only;
- is not an `AppearanceSettings` snapshot;
- is never persisted by FE-006;
- is never reported as the selected Theme Mode;
- does not authorize normal-shell presentation.

## 29. No Wrong-Theme Normal Shell Flash

The ready shell must not appear briefly in a bootstrap/System visual style and then switch after the first authoritative appearance read.

For persisted Dark:

```text
backend Ready
    ↓
appearance read returns Dark
    ↓
root theme derives Dark
    ↓
first normal shell presentation is Dark
```

This behavior is part of the Phase 000 acceptance contract.

# Root Theme Derivation

## 30. Root Theme Is Derived State

The root application theme mode is a pure projection of `confirmed.themeMode` after presentation readiness has been established.

Conceptually:

```text
AppearanceSettingsController.confirmed.themeMode
    ↓
rootThemeModeProvider
    ↓
MaterialApp.themeMode
```

The root provider owns no mutable theme value.

## 31. Root Theme Does Not Use `presented`

While the Settings control optimistically shows a pending selection, root theme remains derived from `confirmed`.

Example:

```text
confirmed = Light
presented = Dark
save = saving
```

produces:

```text
Settings control → Dark (pending)
MaterialApp.themeMode → Light
```

until authoritative reconciliation returns the current aggregate.

## 32. Meaning of Immediate Theme Application

"Immediate" means the confirmed theme applies without application restart as soon as authoritative post-mutation reconciliation establishes the current value.

It does not mean uncommitted user input is applied globally before backend confirmation.

## 33. Root Theme Projection Is Narrow

The root theme derivation watches only the minimum semantic value required to choose the theme mode.

It does not depend on:

- save progress;
- inline save failure;
- synchronization error text;
- event sequence counters;
- pending optimistic choice.

This limits unnecessary root rebuilds.

## 34. Same-Value Reconciliation

If an authoritative refresh returns the same `ThemeMode`, synchronization metadata may change while the root theme remains semantically unchanged.

No artificial theme transition is produced merely because a query completed.

# Settings Destination UX

## 35. Phase 000 Appearance Section

The genuine Settings destination exposes one Appearance section required by Phase 000.

It contains Theme Mode.

Do not create speculative empty settings categories solely to make the page appear complete.

## 36. Theme Mode Control Semantics

Theme Mode is a single-selection control with exactly three choices:

```text
System
Light
Dark
```

Exact widget styling and component selection belong to SPEC-FE-007 and implementation planning.

## 37. No Apply or Save Button

Appearance settings persist immediately when the user selects a different valid Theme Mode.

Do not add an Apply/Save workflow during Phase 000.

There is no separate frontend draft aggregate awaiting form submission.

## 38. User-Intent Controller API

A controller method may express user intent conceptually as:

```text
selectThemeMode(ThemeMode value)
```

The controller then creates the complete desired `AppearanceSettings` aggregate and invokes:

```text
SettingsApi.updateAppearanceSettings(settings)
```

A user-intent method does not create a field-specific backend persistence contract.

## 39. Complete Aggregate Submission

Every mutation sends the complete desired appearance aggregate.

Phase 000 currently has one field, but the frontend must not rely on that fact to create a partial-write architecture that would overwrite future fields incorrectly.

## 40. Frontend Same-Value No-Op

When:

```text
confirmed == presented
save = idle
synchronization = synchronized
```

selecting the already-confirmed Theme Mode may complete as a frontend no-op without sending a mutation.

Backend semantic no-op behavior remains authoritative if a request does reach Rust.

## 41. Optimistic Control Presentation

When the user selects another Theme Mode:

```text
confirmed = Light
presented = Light
```

may transition to:

```text
confirmed = Light
presented = Dark
save = saving(Dark)
```

The control immediately reflects the user's pending selection while making pending state visible.

## 42. Save Single Flight

Only one appearance mutation is admitted at a time during Phase 000.

A second user selection while save is active does not dispatch another backend mutation.

Presentation may disable or otherwise constrain the control, but controller guarding is the correctness mechanism.

## 43. No Mutation While Synchronization Is Uncertain

When the controller cannot prove its last-read aggregate is current:

```text
synchronization = uncertain(...)
```

new aggregate mutation is not admitted.

This prevents a stale complete aggregate from overwriting fields changed elsewhere.

The recovery operation is an authoritative refresh.

# Successful Mutation

## 44. Update Contract

The focused client contract is:

```text
SettingsApi.updateAppearanceSettings(settings)
    → Future<void>
```

Success means the immediate backend command completed successfully.

It does not return an authoritative appearance snapshot.

## 45. No Request Promotion

This is prohibited:

```text
update(Dark) → success
    ↓
confirmed = requested Dark
```

solely because the controller remembers what it sent.

The submitted object remains command input, not authoritative query output.

## 46. Required Post-Success Reconciliation

After update success, the controller obtains authoritative state through:

```text
SettingsApi.getAppearanceSettings()
```

The returned snapshot becomes both:

```text
confirmed
presented
```

and root theme derives from it.

## 47. Mutation Does Not Depend on Event Delivery

The successful local mutation path performs its authoritative read even if `AppearanceSettingsChanged` is never delivered.

Runtime events are best-effort notification infrastructure and cannot be the sole completion mechanism for the user's settings update.

## 48. Returned State May Differ from Request

Under last-successful-commit semantics, the post-mutation authoritative read may return a value different from the submitted request.

The read result wins.

Example:

```text
Flutter submitted Dark
another successful writer later committed Light
authoritative read returns Light
```

Flutter adopts Light.

# Definite Mutation Failure

## 49. Application Failure Is Definite

A typed `ApplicationFailure` from the update operation is treated as a definite command failure according to the client/backend contract.

Given:

```text
confirmed = Light
presented = Dark
save = saving
```

and update failure:

```text
confirmed = Light
presented = Light
save = failed(applicationFailure)
```

provided no independent synchronization signal indicates another committed change may have occurred.

## 50. Root Theme Does Not Roll Back Because It Never Moved

Since root theme derives from `confirmed`, it remained Light during the failed pending Dark mutation.

No global Light → Dark → Light flash occurs.

## 51. Inline Failure

The Theme Mode control presents the typed failure close to the originating interaction.

Raw backend or transport strings are not displayed directly.

The normal typed failure/localization contract remains in force.

## 52. Concurrent Event with Definite Failure

If a relevant appearance-change notification arrived while the failed mutation was active, the controller must still perform authoritative reconciliation.

Its own command failure does not prove no other writer committed a settings change.

# Ambiguous Mutation Outcomes

## 53. Transport Failure May Be Ambiguous

A transport failure after mutation dispatch may occur after the backend has already committed the change.

Therefore:

```text
updateAppearanceSettings(...)
→ TransportFailure
```

must not be interpreted as proof that persistence failed.

## 54. No Automatic Mutation Replay

An ambiguous mutation is never automatically resubmitted.

The next correctness operation is an authoritative read.

## 55. Ambiguous State

Conceptually:

```text
save = outcomeUnknown(transportFailure)
synchronization = refreshing
```

while preserving the last successfully read snapshot for temporary rendering.

## 56. Reconciliation Determines Current Authority

The controller performs:

```text
SettingsApi.getAppearanceSettings()
```

If it returns Dark, Dark becomes current authority.

If it returns Light, Light becomes current authority.

The controller need not establish historical causality for the earlier mutation; it only needs the current aggregate.

## 57. Matching State Does Not Prove Historical Command Outcome

If an ambiguous Dark mutation is followed by an authoritative read of Dark, Flutter may conclude:

> Dark is currently authoritative.

It must not overstate:

> The original Dark command definitely succeeded.

The distinction matters for truthful diagnostics and future concurrency.

## 58. Failed Ambiguity Reconciliation

If the mutation result is ambiguous and the authoritative read also fails:

```text
confirmed = lastKnown
presented = lastKnown
save = outcomeUnknown(...)
synchronization = uncertain(readFailure)
```

Further mutation remains blocked until refresh succeeds.

The root continues rendering the last-known confirmed theme where the already-ready application may safely remain usable.

# Command Success Followed by Read Failure

## 59. Success Still Requires Authoritative Read

Even when update acknowledgement is successful, a failed subsequent read does not authorize the controller to promote the submitted request into `confirmed` state.

## 60. Committed but Unreconciled State

Conceptually:

```text
update(Dark) → success
getAppearanceSettings() → ClientFailure
```

produces:

```text
confirmed = lastKnownLight
presented = Light
save = committedButUnreconciled(readFailure)
synchronization = uncertain(readFailure)
```

The controller knows the command completed but cannot prove the current aggregate after that completion.

## 61. Last-Known Rendering

The last authoritative theme may remain rendered while synchronization is uncertain.

The UI must not label that value as definitely current.

It must not switch to `System` or any fabricated fallback.

## 62. Refresh Is the Only Recovery Required Here

Retry from this state performs:

```text
SettingsApi.getAppearanceSettings()
```

It does not repeat the mutation.

# Event-Driven Reconciliation

## 63. Event Source

The appearance feature consumes an approved typed frontend signal derived from the one shared runtime-event connection defined by SPEC-FE-003.

It does not subscribe directly to FRB/native events.

## 64. `AppearanceSettingsChanged` Meaning

The event means only:

> Authoritative appearance settings committed a semantic change and consumers that need current state should re-query.

It does not carry an authoritative aggregate.

## 65. Event Handling

A relevant event requests:

```text
SettingsApi.getAppearanceSettings()
```

through the controller's reconciliation mechanism.

The event payload itself never sets `confirmed`.

## 66. Event Coalescing

Multiple relevant event notifications received while no refresh is active should not create uncontrolled parallel reads.

One refresh is admitted.

Additional notifications received while it is active record that another reconciliation is required.

## 67. Follow-Up Read Rule

If a relevant appearance event occurs after a read has begun but before that read completes, one follow-up authoritative read is required after the current read finishes.

The in-flight read might have observed state preceding the event's commit.

## 68. Coalescing Goal

A burst such as:

```text
event
event
event
```

should normally result in:

```text
one current refresh
+
at most one necessary follow-up refresh
```

rather than three uncontrolled concurrent queries.

Correctness takes priority over minimizing one additional read.

## 69. Event During Save

A relevant event received while a save is active is retained as synchronization demand.

The controller does not assume it was emitted by the local mutation.

After mutation handling settles, authoritative reconciliation occurs as required.

## 70. Successful Save and Event Coalescing

The required post-success read and an event-triggered refresh may be coalesced where the implementation can prove the resulting read observes the necessary post-event authority.

The implementation must not optimize away the authoritative result required after mutation.

# Event Loss and Connectivity

## 71. Sequence Gap

If shared event coordination detects a sequence gap that may contain an appearance-settings change, appearance synchronization becomes refresh-required.

The controller re-queries authoritative settings.

It does not reconstruct missing event payloads.

## 72. Reconnect Uncertainty

When event connectivity is restored after uncertain delivery, appearance state is reconciled through a focused read.

Absence of an event during disconnection is not evidence that settings did not change.

## 73. Reconciliation Failure After Gap/Reconnect

If the refresh fails after synchronization uncertainty is known:

```text
confirmed = lastKnown
synchronization = uncertain(failure)
```

The Settings UI offers refresh/retry and blocks new aggregate mutation.

The already-ready shell may continue using the last-known theme where safe under SPEC-FE-004.

# Runtime-Generation Interaction

## 74. Generation-Scoped Async Work

Every appearance read/mutation/reconciliation attempt is logically associated with the relevant current runtime generation used by the client infrastructure.

The feature need not expose runtime IDs to the ordinary user.

## 75. Runtime Replacement Invalidates Authority

A settings snapshot read under Runtime A is not automatically authoritative for Runtime B.

Runtime replacement therefore invalidates synchronization confidence until a fresh authoritative appearance read succeeds for the new current runtime context.

## 76. Stale Completion Rejection

If a Runtime A settings read is pending when Runtime B becomes current, the A completion must not publish into B-era controller state.

This remains true even when the returned values happen to be equal.

## 77. Pre-Shell Runtime Replacement

Before shell entry:

```text
new runtime not Ready
→ backend startup gate

new runtime Ready
→ fresh appearance initialization

appearance loaded
→ presentation gate Ready
```

A previous runtime's appearance result cannot bypass the gate.

## 78. Post-Ready Runtime Replacement or Degradation

Once the application has been ready, the last-known theme may remain rendered during safe transient runtime/client degradation.

A fresh read is required before appearance synchronization returns to `synchronized` for the new runtime context.

This does not automatically route the user back through the initial startup screen when FE-004 permits continued application use.

# System Theme Semantics

## 79. Persisted System Preference

When authoritative settings contain:

```text
ThemeMode.system
```

that value remains the persisted application preference.

The controller does not replace it with Light or Dark based on current operating-system brightness.

## 80. Effective Rendering Under System

The root maps authoritative `system` to Flutter's system theme-mode behavior.

The operating system/platform brightness determines the effective light or dark theme data at presentation time.

## 81. Platform Brightness Is Not Settings Mutation

A platform brightness change while mode is System does not trigger:

- `updateAppearanceSettings()`;
- `getAppearanceSettings()` solely because brightness changed;
- `AppearanceSettingsChanged`;
- controller mutation from System to Light/Dark.

The persisted setting has not changed.

## 82. Explicit Light/Dark

When authoritative mode is Light or Dark, platform brightness changes do not change the selected application mode.

# Presentation and Feedback

## 83. Pending State

While a save is active, the Theme Mode control communicates both:

- the user's selected pending value;
- that persistence/reconciliation is in progress.

Pending state must not be represented only by color or opacity.

## 84. Save Failure Placement

Definite save failure is shown near Theme Mode.

A global shell banner is not required for routine appearance save failure.

## 85. Synchronization-Uncertain Placement

When current appearance authority cannot be confirmed, Settings presents a durable local synchronization message and a Retry/Refresh action.

The user should understand that the displayed value is last-known and cannot currently be safely changed.

## 86. No Required Success Toast

Phase 000 does not require a success toast after a normal theme change.

The selected control value and root theme transition already provide direct feedback.

A future design system may define consistent transient success behavior, but it is not required by this contract.

# Accessibility

## 87. Relationship to SPEC-FE-007

SPEC-FE-007 owns the comprehensive design-system and accessibility baseline.

FE-006 nevertheless keeps the appearance workflow's semantic accessibility requirements feature-owned while SPEC-FE-007 supplies the shared measurable baseline and styling defaults.

## 88. Theme Mode Group Semantics

Theme Mode is exposed as one related single-selection group with a meaningful accessible name.

Each option exposes its selected state.

## 89. System Explanation

The System option must communicate that Argus follows the operating-system appearance preference.

It must not appear as an unexplained third visual palette.

## 90. Keyboard Operation

Desktop keyboard users can:

- focus the Theme Mode group;
- determine the selected option;
- select an available option;
- reach Retry/Refresh when synchronization is uncertain.

Pointer-only custom interaction is prohibited.

## 91. Pending Semantics

Saving state has a useful semantic announcement equivalent to:

```text
Saving appearance settings
```

Animation frames or repeated rebuilds must not create continuous accessibility announcements.

## 92. Failure Association

A save failure is semantically associated with the Theme Mode interaction rather than presented as unrelated global text.

Focus remains stable where practical.

## 93. Rollback Perceivability

When a pending selection rolls back after definite failure, the resulting selected state plus associated error must make the rollback understandable without relying on color alone.

# Provider Composition

## 94. Appearance Provider

Production composition exposes one application-lifetime appearance controller/provider backed by `SettingsApi`.

The Settings feature and app composition consume that provider rather than independently calling `SettingsApi` for the same authority.

## 95. Root Theme Projection Provider

Conceptually:

```text
appearanceSettingsProvider
    ↓
rootThemeModeProvider
```

The derived provider:

- performs no bridge/client call;
- stores no independent theme state;
- exposes no mutation command;
- performs no retry logic.

## 96. Presentation-Readiness Projection

Conceptually:

```text
appReadinessProvider
+
appearanceSettingsProvider
    ↓
applicationPresentationReadinessProvider
```

This provider is pure composition.

It does not initialize backend/runtime or appearance state itself.

## 97. Event Coordination Input

Appearance event reconciliation receives the smallest approved typed notification from app-level event coordination.

It does not depend on another feature's private controller.

# Testing Contract

## 98. Focused API Fakes

Ordinary appearance controller tests use a `SettingsApi` fake.

They do not require:

- FRB;
- Rust;
- SQLite;
- real platform theme changes unless the specific test owns platform-brightness behavior.

## 99. Initial Load Tests

Verify:

```text
initial
→ AsyncLoading
→ authoritative System
```

and similarly for Light and Dark.

Also verify:

```text
initial
→ AsyncLoading
→ AsyncError(ClientFailure)
```

No failure path may synthesize System.

## 100. Shell-Gating Test

Required integration behavior:

```text
backend Ready
appearance read pending
→ normal shell absent
```

then:

```text
appearance read returns Dark
→ root derives Dark
→ normal shell appears
```

The first normal shell frame must not use a fabricated System preference.

## 101. Intended-Route Test

Given intended `/settings`:

```text
backend startup
→ appearance initialization
→ presentation ready
```

verify the final route is still `/settings` and the temporary presentation gates are not present in normal back history.

## 102. Initial Appearance Failure Test

Given backend Ready and failed first settings read, verify:

- shell remains absent;
- failure is not relabeled backend `StartupFailed`;
- Retry issues an authoritative settings read;
- no reset or mutation is invoked;
- no System fallback is fabricated.

## 103. Optimistic Selection Test

Given authoritative Light:

```text
select Dark
```

verify while update is pending:

- `presented` is Dark;
- `confirmed` is Light;
- save is running;
- root theme remains Light;
- a second mutation is rejected/not admitted.

## 104. Successful Save Test

Verify:

```text
update Dark → success
```

alone does not make Dark confirmed.

Only:

```text
getAppearanceSettings() → Dark
```

updates:

- confirmed Dark;
- presented Dark;
- root Dark.

## 105. Successful Save with Different Authoritative Value

Given submitted Dark and authoritative post-success read Light, verify Light becomes confirmed/presented/root.

The submitted request does not win over the query result.

## 106. Definite Failure Test

Given authoritative Light and pending Dark, a typed `ApplicationFailure` must produce:

- confirmed Light;
- presented Light;
- local save failure;
- root Light;
- no automatic retry.

## 107. Definite Failure with Concurrent Event

When a relevant change notification occurs during the failed save, verify the controller still performs authoritative reconciliation after rollback rather than assuming the old confirmed value is current.

## 108. Ambiguous Transport Test

Simulate:

```text
update Dark
→ TransportFailure after possible admission
```

Verify:

1. no second update is dispatched automatically;
2. authoritative read occurs;
3. returned state becomes confirmed and presented;
4. root theme follows the returned state.

## 109. Ambiguous Reconciliation Failure Test

If the authoritative read also fails, verify:

- last-known confirmed theme remains rendered;
- synchronization becomes uncertain;
- mutation remains blocked;
- Retry performs read only.

## 110. Command-Success/Read-Failure Test

Required:

```text
update Dark → success
getAppearanceSettings() → TransportFailure
```

Verify:

- Dark is not fabricated as confirmed;
- last-known theme remains rendered;
- save/synchronization represent unreconciled authority;
- new mutation is blocked;
- Retry performs only authoritative read.

## 111. Event Reconciliation Test

Given confirmed Light:

```text
AppearanceSettingsChanged
→ getAppearanceSettings()
→ Dark
```

verify root becomes Dark only after the read returns.

## 112. Event-Coalescing Test

A burst of relevant events during one refresh must not create uncontrolled parallel reads.

Use controlled completers to verify one active refresh plus at most the necessary follow-up reconciliation.

## 113. Event-During-Read Test

If a relevant event arrives after a refresh starts and before it completes, verify one follow-up authoritative read is performed.

The first completion alone cannot mark synchronization current.

## 114. Event-During-Save Test

A relevant event received during save is retained as synchronization demand.

It is not discarded as presumed self-notification.

## 115. Event-Gap Test

When event coordination reports a sequence gap affecting synchronization confidence, verify authoritative appearance refresh occurs.

No missing-event reconstruction is attempted.

## 116. Reconnect Test

After event-delivery uncertainty and reconnect, verify appearance refresh is requested even when no appearance event was observed during disconnection.

## 117. Runtime-Replacement Test

With a settings read pending under Runtime A:

```text
Runtime B becomes current
```

verify the A completion cannot publish.

A fresh current-runtime read is required before synchronization is restored.

## 118. System Mode Platform Test

With authoritative System, simulate platform brightness Light → Dark.

Verify:

- effective presentation follows platform brightness;
- controller confirmed preference remains System;
- no update call occurs;
- no settings refresh occurs solely due to brightness change.

## 119. Explicit Mode Platform Test

With authoritative Dark, simulate platform brightness changes.

Verify selected application mode remains Dark and no backend settings operation is triggered.

## 120. Restart Restoration Integration

Phase 000 must prove:

```text
persist Dark
→ close Argus normally
→ relaunch
→ backend Ready
→ initial authoritative appearance read returns Dark
→ first normal shell presentation uses Dark
```

No intermediate normal shell may be presented under System/bootstrap appearance.

## 121. Widget and Accessibility Tests

Widget tests cover at least:

- System/Light/Dark choices;
- selected-state semantics;
- keyboard selection;
- pending state;
- single-flight interaction restriction;
- definite failure and rollback;
- synchronization uncertainty;
- Retry/Refresh action;
- System helper semantics.

Detailed visual golden requirements remain owned by SPEC-FE-007.

## 122. No Arbitrary Sleep Tests

Async tests use:

- controlled futures/completers;
- explicit runtime-generation changes;
- explicit event synchronization signals;
- fake focused API responses.

Do not use arbitrary delays to make races likely to settle.

# Static and Semantic Verification

## 123. Architecture Verification

Where mechanically practical, repository verification should catch:

- Settings feature importing generated bridge types;
- root theme owning independently mutable appearance state;
- feature controllers receiving the concrete root client for normal settings behavior;
- raw theme strings used outside transport mapping where typed values should exist;
- route code issuing settings reads/mutations;
- normal-shell entry paths that bypass the presentation-readiness gate.

## 124. Semantic Review Obligations

Code review must explicitly verify behaviors that static tooling may not prove completely:

- request objects are never promoted into confirmed state solely from command success;
- optimistic presented state never drives root theme;
- events trigger reads rather than directly setting authority;
- event-during-read follow-up semantics are preserved;
- ambiguous mutation is never retried automatically;
- uncertain authority blocks subsequent aggregate mutation;
- old-runtime completions cannot publish after replacement;
- the first normal shell does not flash a non-authoritative theme.

## 125. Prohibited Patterns

The following are prohibited:

```text
root mutable theme state separate from AppearanceSettingsController
Theme Mode stored as arbitrary string in feature/application code
Settings screen calling FRB directly
router calling SettingsApi
backend Ready used as sole first-shell gate
failed initial appearance read silently mapped to System
MaterialApp.themeMode derived from pending presented value
update success promoting request object into confirmed state
event payload treated as authoritative appearance snapshot
event-only mutation reconciliation
automatic mutation replay after transport failure
multiple concurrent Phase 000 appearance writes
new aggregate mutation while synchronization is uncertain
old runtime read publishing after replacement
platform brightness changing persisted ThemeMode from System
Apply/Save button for Phase 000 immediate appearance persistence
```

# Derived Implementation Decisions

## 126. Derived Decisions

The following are derived implementation choices unless concrete platform constraints require revision:

- use Freezed/immutable state where it materially encodes valid controller states;
- use Riverpod-generated providers according to SPEC-FE-002;
- keep the appearance controller application-lifetime;
- expose root theme as a narrow derived provider;
- use controlled operation/attempt identities for stale-completion protection;
- coalesce event-triggered refresh demand rather than issue uncontrolled parallel reads;
- use the platform's normal theme-mode integration for System behavior;
- keep initial appearance failure outside the ready shell;
- keep routine post-ready synchronization failure local to Settings rather than creating a global shell banner solely for appearance.

## 127. Decisions Requiring Future Specification

Future work may explicitly define:

- additional appearance fields;
- more settings domains;
- restart-required settings;
- multiple simultaneous frontend clients;
- optimistic concurrency/revision contracts;
- user-selectable color themes beyond System/Light/Dark mode;
- high-contrast or accessibility appearance preferences requiring persistence;
- settings import/export;
- cross-device settings synchronization.

These are not justified by Phase 000 and must not be prebuilt speculatively.

# Acceptance Criteria

## 128. Acceptance Properties

An implementation conforming to SPEC-FE-006 satisfies all of the following:

1. Exactly one application-lifetime frontend authority owns appearance settings.
2. The Settings destination and root theme consume that same authority.
3. The appearance controller depends on `SettingsApi`, not bridge/generated infrastructure.
4. Frontend appearance state uses typed `AppearanceSettings` and `ThemeMode` concepts.
5. Phase 000 Theme Mode contains exactly System, Light, and Dark.
6. The root theme is pure derived state rather than independently mutable state.
7. Backend `Ready` remains distinct from frontend shell presentation readiness.
8. The first normal shell does not appear until one authoritative appearance read succeeds.
9. Persisted appearance therefore applies before the first normal shell presentation.
10. Initial appearance-read failure is not relabeled backend `StartupFailed`.
11. Initial appearance-read failure never silently substitutes System.
12. Bootstrap/startup surfaces may use a presentation fallback that is not persisted appearance authority.
13. Initial loading/error use outer `AsyncValue` while later operations retain usable loaded state.
14. `confirmed` means last successfully queried authoritative appearance snapshot.
15. `presented` may differ from `confirmed` only for explicit frontend interaction/operation semantics.
16. Root theme derives from `confirmed`, never pending `presented` state.
17. Appearance mutation persists immediately without an Apply/Save workflow.
18. Frontend user intent is converted into the complete desired appearance aggregate.
19. Appearance mutation is single-flight during Phase 000.
20. New mutations are blocked while appearance synchronization is uncertain.
21. Successful update acknowledgement does not promote the request object into authority.
22. Every successful mutation performs or coalesces an authoritative read.
23. Definite application failure rolls presented state back to the last confirmed value.
24. A transport-ambiguous mutation is never automatically replayed.
25. Ambiguous mutation triggers authoritative reconciliation.
26. Command success followed by read failure remains explicitly unreconciled rather than fabricating confirmed state.
27. Last-known theme may remain rendered during post-ready synchronization uncertainty.
28. Retry from uncertainty performs authoritative read rather than mutation replay.
29. `AppearanceSettingsChanged` is notification-only.
30. Appearance-change notifications trigger authoritative reconciliation.
31. Relevant event bursts are coalesced.
32. A relevant event arriving during an in-flight read causes a necessary follow-up reconciliation.
33. A relevant event arriving during save is retained as synchronization demand.
34. Event sequence gaps trigger authoritative appearance refresh.
35. Reconnect after uncertain event delivery triggers authoritative appearance refresh.
36. Runtime-generation replacement invalidates synchronization confidence.
37. Old-generation async completions cannot publish into the new generation.
38. System mode follows platform brightness without changing persisted Theme Mode.
39. Explicit Light/Dark ignore platform brightness changes.
40. Platform brightness changes do not generate settings persistence or read traffic solely because brightness changed.
41. Theme Mode is keyboard-operable and exposed as an accessible single-selection group.
42. Pending, failure, and uncertainty states are not communicated by color alone.
43. Save failure remains associated with the Theme Mode interaction.
44. Ordinary controller/widget tests use a `SettingsApi` fake rather than real Rust/FRB.
45. Event/race tests use deterministic completion control rather than arbitrary sleeps.
46. Phase 000 restart integration proves persisted theme is present on the first normal-shell render.

# Phase 000 Minimum Implementation

## 129. Minimum Production Surface

Phase 000 implements:

```text
features/settings/application
├── AppearanceSettingsController
├── AppearanceSettingsState
├── save operation state
└── synchronization state

features/settings/presentation
├── Settings destination
└── Theme Mode single-selection control

app composition
├── root theme-mode derivation
└── combined backend + appearance presentation-readiness derivation
```

with only the System/Light/Dark appearance capability required by PHASE-000.

## 130. Minimum Behavior

Phase 000 must demonstrate:

- authoritative initial appearance read after backend Ready;
- no normal shell before that read succeeds;
- persisted theme applied to the first normal shell;
- immediate Theme Mode mutation;
- pending selection without optimistic root-theme mutation;
- post-success authoritative reconciliation;
- definite-failure rollback;
- ambiguous-outcome read reconciliation;
- synchronization uncertainty after failed authoritative refresh;
- mutation blocking while uncertain;
- event-driven authoritative refresh;
- event gap/reconnect refresh;
- runtime-replacement stale-result protection;
- System platform-brightness following;
- persisted theme restoration after process restart.

## 131. Minimum Test Surface

At minimum, deterministic verification covers:

- initial load success/failure;
- presentation gate;
- persisted Dark first-shell rendering;
- optimistic control behavior;
- successful update plus authoritative read;
- definite failure rollback;
- ambiguous update outcome;
- command-success/read-failure;
- event coalescing;
- event-during-read follow-up;
- event-during-save behavior;
- sequence-gap/reconnect reconciliation;
- runtime replacement;
- System and explicit-mode platform brightness behavior;
- keyboard/semantic interaction;
- real Phase 000 restart restoration at the appropriate integration layer.

# Out of Scope

## 132. Explicitly Deferred Work

This specification does not introduce:

- additional appearance preferences;
- application color-palette selection;
- custom user themes;
- font/theme customization;
- generic settings forms;
- a generic settings event bus;
- a frontend settings repository;
- local settings persistence outside Rust;
- optimistic concurrency metadata;
- multi-client conflict resolution UI;
- restart-required settings banners;
- cloud settings sync;
- settings profiles.

# Phase 002 Android Appearance Amendment

## 133. Shared Android Appearance Authority

Android reuses the same application-lifetime `AppearanceSettingsController`, focused `SettingsApi`, persisted backend aggregate, and root-theme derivation as desktop.

- Activity recreation/detach and temporary backgrounding must not instantiate an Android-only appearance controller or reset confirmed appearance authority while the process composition survives.
- All files access revocation/regrant and notification authorization changes are platform-readiness/presentation facts; they do not enter `AppearanceSettings`, change `ThemeMode`, or trigger appearance persistence.
- Platform-readiness overlays may gate backend startup or shell visibility, but they consume the existing root theme/bootstrap presentation rules and do not become a second theme authority.
- After process death, normal startup and the existing first-shell authoritative appearance read restore the persisted setting exactly as on desktop.
- Android widget/integration evidence must cover Activity recreation and permission-overlay transitions without duplicating or mutating appearance authority.

# References

## 134. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [PHASE-002 — Android First-Class Platform Support](../../phases/phase-002-android-first-class-platform-support.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](../backend/spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](../backend/spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](spec-fe-004-routing-and-adaptive-application-shell.md)
- [SPEC-FE-005 — Startup and Recovery UI](spec-fe-005-startup-and-recovery-ui.md)
- [SPEC-FE-007 — Design-System Foundation and Accessibility Baseline](spec-fe-007-design-system-foundation-and-accessibility-baseline.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
- [SPEC-X-002 — Android Platform Runtime and Capability Contract](../cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
