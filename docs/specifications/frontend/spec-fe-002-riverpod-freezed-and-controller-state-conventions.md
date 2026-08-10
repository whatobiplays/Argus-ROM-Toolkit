# Riverpod, Freezed, and Controller State Conventions

**Document ID:** SPEC-FE-002  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-10  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-004, SPEC-BE-008, SPEC-FE-001, CONV-REPO-001, CONV-FLUTTER-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative Riverpod, Freezed, controller-state, asynchronous-operation, and frontend dependency-injection conventions for Argus ROM Toolkit.

It translates the frontend state-management architecture established by ARCH-001 into concrete rules for provider categories, generated providers, provider lifetimes, controller responsibilities, immutable state, initial readiness, background operations, concurrency, stale-result protection, event-driven synchronization, provider overrides, presentation side effects, and deterministic testing.

This specification does not make Riverpod or Freezed the source of application authority. Rust remains authoritative for backend domain state, persistence, workflows, jobs, provider behavior, and other responsibilities assigned to Rust by ARCH-001. Riverpod owns frontend dependency exposure and frontend application/presentation state; Freezed provides the immutable model representation required by that state.

The central invariant is:

> **Riverpod and Freezed make frontend authority explicit rather than merely reducing boilerplate: each state has one semantic owner, valid transitions are controller-owned, asynchronous results cannot outlive their authority, immutable models encode meaningful states, and production dependencies can be replaced at narrow provider seams without changing application behavior.**

## 2. Responsibilities

This specification owns frontend rules for:

- Riverpod as the sole frontend dependency-injection and state-management framework;
- Riverpod code generation for authored Argus providers;
- provider categories and ownership;
- root and nested provider-scope semantics;
- provider lifetimes and long-lived-provider policy;
- controller responsibilities and public action shape;
- `AsyncValue<State>` initial-readiness semantics;
- explicit operational state after initial readiness;
- immutable controller/read/UI model conventions;
- Freezed data-class and union usage;
- JSON serialization separation from immutability;
- derived-provider purity;
- parameterized-provider identity;
- provider watch/read/listen intent;
- asynchronous concurrency policies;
- stale-result protection;
- disposal and cancellation behavior;
- single-flight operations;
- optimistic updates and rollback baselines;
- backend-event synchronization;
- presentation-side-effect boundaries;
- provider overrides and frontend test composition;
- deterministic controller/provider race testing;
- generated-source verification expectations.

Feature-specific specifications remain authoritative for the exact state fields, actions, error presentation, route semantics, and operation policies of their features when those choices refine this contract.

## 3. Non-Responsibilities

This specification does not define:

- the detailed Flutter project layout, which is owned by SPEC-FE-001;
- exact pinned Riverpod, Riverpod Generator, Freezed, or `build_runner` package versions;
- exact annotation names or generated superclass syntax tied to a specific Riverpod release;
- the detailed `ArgusClient` and focused API catalog, which is owned by SPEC-FE-003;
- generated `flutter_rust_bridge` transport contracts, which are owned by SPEC-BE-008;
- exact route paths, query-state ownership, or shell behavior, which are owned by SPEC-FE-004;
- startup/recovery UI state-machine details, which are owned by SPEC-FE-005;
- exact appearance-settings optimistic-state fields, which are owned by SPEC-FE-006;
- design-system, accessibility, and detailed responsive-presentation contracts, which are owned by SPEC-FE-007;
- backend operation cancellation semantics, which remain owned by the applicable backend specifications;
- persistent caching policy for future feature domains;
- a second frontend state-management framework.

The specification intentionally defines semantic behavior rather than generator-version-specific syntax.

## 4. Governing Principles

Argus frontend state follows these principles:

1. Every frontend state value has one semantic owner.
2. Riverpod is the approved framework for dependency injection and non-widget-local application/feature state.
3. Authored Argus providers use Riverpod code generation.
4. Provider placement follows semantic ownership rather than provider type.
5. `AsyncValue<State>` answers whether usable initial state exists; it is not the universal state model for every later operation.
6. Once usable data exists, non-blocking operations preserve that data unless the owning feature explicitly requires otherwise.
7. Independently meaningful operations use explicit immutable operational state.
8. Freezed represents immutable Dart models and meaningful state unions.
9. JSON serialization is added only for a real serialization boundary.
10. Provider lifetime matches the state or dependency it owns.
11. Long-lived/`keepAlive` behavior is explicit, not defensive by default.
12. Controllers expose intent-oriented actions rather than general mutation.
13. Every asynchronous operation has a defined concurrency policy.
14. A stale or disposed async result cannot publish state.
15. Backend events synchronize frontend projections rather than creating competing authority.
16. Presentation effects remain outside controllers.
17. Derived providers are pure.
18. Tests substitute the narrowest focused provider/API seam and control async completion deterministically.
19. Mutable collections do not leak through immutable model APIs.
20. Generated output is never hand-edited and drift is detected canonically.

## 5. State Ownership

Every piece of frontend state has one clear owner.

A state value may be owned by:

- a widget instance for truly local presentation mechanics;
- a feature controller/provider for feature/application state;
- a route/query representation when SPEC-FE-004 intentionally makes it addressable;
- an application-level provider when the state genuinely spans features/application lifetime;
- Rust when the value is backend-authoritative and Flutter merely projects it.

The same authoritative value must not be independently mutable in multiple owners.

Examples of prohibited duplication include:

```text
router sort state
+
independently mutable controller sort state
```

and:

```text
backend authoritative settings
+
independently authoritative Flutter settings cache
```

One representation may be derived from another when the relationship is explicit.

## 6. Widget-Local State

Widget-local state is appropriate for short-lived presentation mechanics tied to one widget instance.

Examples include:

```text
hover state
focus state
animation controller state
temporary expansion
drag interaction
local text-field mechanics
```

Widget-local state must not become the owner of:

- backend/read-model state;
- persisted settings authority;
- feature workflows;
- shared selection needed across independently rebuilt widgets;
- asynchronous application operations whose behavior needs independent deterministic testing.

When state survives widget reconstruction, affects feature behavior, or is shared across widgets, Riverpod ownership is normally more appropriate.

## 7. Riverpod Provider Categories

Argus uses four conceptual provider categories:

1. dependency providers;
2. derived/read providers;
3. feature/application controllers;
4. parameterized providers whose identity is materially scoped by typed arguments.

These are semantic categories. They do not require separate global directories and do not necessarily correspond one-to-one with Riverpod implementation classes.

Provider files live with the semantic owner established by SPEC-FE-001.

## 8. Dependency Providers

Dependency providers expose stable dependencies to consumers.

Representative dependencies include:

```text
ArgusClient
SettingsApi
EventsApi
DiagnosticsApi
runtime/event coordination infrastructure
controlled clocks or other approved seams when needed
```

Dependency providers do not own arbitrary feature presentation state merely because they are long-lived.

Features should consume the narrowest focused dependency appropriate to their responsibility rather than injecting the concrete root client everywhere.

## 9. Derived Providers

Derived providers compute values from existing authoritative state.

Examples include:

```text
effectiveTheme
canRetry
selectedCount
visibleItems
hasNextPage
```

A derived provider must be pure with respect to application behavior.

Reading or watching it must not:

- initiate backend commands;
- mutate another controller;
- perform persistence;
- navigate;
- display dialogs/toasts/snackbars;
- emit platform side effects.

A provider that is named and consumed as a value must behave like a value.

## 10. Controller Providers

A controller owns one cohesive frontend behavioral state machine.

Representative examples include:

```text
AppearanceSettingsController
StartupController
LibraryController
```

A controller exposes:

```text
state
+
intent-oriented actions
```

Representative actions include:

```text
refresh()
saveAppearance(...)
retry()
loadNextPage()
select(...)
cancel(...)
```

The exact controller class/annotation syntax is determined by the pinned Riverpod version during implementation.

## 11. Parameterized Providers

A provider may be parameterized when identity materially scopes the state or dependency.

Representative identities include:

```text
GameId
LibraryRootId
SourceEntryId
PlatformId
```

Parameterized providers should use strongly typed frontend identities when such types exist.

Avoid broad configuration maps or arbitrary string bundles merely to force unrelated state through one family/provider definition.

Provider arguments must have correct semantic equality/identity behavior.

## 12. Provider Code Generation

All authored Argus providers use Riverpod's supported code-generation model.

The repository should not intentionally maintain two parallel authored-provider styles such as:

```text
generated providers for some features
+
large manually declared provider surface for others
```

An external/generated integration may require narrow generator-specific exceptions, but those do not establish a second general project style.

This specification does not freeze annotation names or generated superclass syntax because those are library-version details.

Generated output follows CONV-REPO-001.

## 13. Provider Placement

Provider placement follows semantic ownership.

Conceptually:

```text
core/client/
→ ArgusClient/focused API dependency providers

features/settings/application/
→ appearance settings controller/derived providers

app/bootstrap/
→ root composition/lifecycle providers
```

Argus does not create a single application-wide `providers/` directory containing unrelated concerns.

Dependency injection is a mechanism; it does not override ownership boundaries defined by SPEC-FE-001.

## 14. Root Provider Scope

Phase 000 uses one root application `ProviderScope` created by the application bootstrap boundary.

Conceptually:

```text
main
  ↓
app/bootstrap
  ↓
ProviderScope
  ↓
Argus application
```

The root scope establishes production dependency composition and application-lifetime provider ownership.

`main.dart` remains thin according to SPEC-FE-001.

## 15. Nested Provider Scopes

Nested provider scopes are allowed only for concrete ownership purposes.

Examples may include:

- a test override boundary;
- a deliberately scoped subtree dependency;
- a detail/feature identity whose lifecycle genuinely follows that subtree.

Nested scopes must not become a routine way to hide global mutable state or bypass clear provider ownership.

A nested scope requires an understandable lifecycle reason.

## 16. Provider Lifetimes

Provider lifetime follows the semantic lifetime of the state/resource it owns.

Default guidance:

- recreatable route/feature state is disposable when no longer observed;
- detail state parameterized by an identity is normally disposable/recreatable;
- root client/runtime/event infrastructure may live for the application lifetime;
- state required across application destinations may live for the application lifetime when its owner justifies that behavior;
- widget mechanics remain widget-local and shorter-lived.

Disposal/reconstruction is not considered data loss when the source of authority can deterministically reconstruct the state.

## 17. Long-Lived Providers and `keepAlive`

`keepAlive` or equivalent long-lived behavior is an explicit lifecycle declaration, not a defensive performance default.

A long-lived provider requires a concrete reason such as:

- application-lifetime infrastructure;
- a shared resource whose teardown/recreation would violate its contract;
- state that intentionally persists across route/widget observation gaps;
- a measured lifecycle/performance need whose ownership and invalidation remain clear.

Do not retain providers indefinitely merely to avoid another focused API read.

## 18. Providers Are Not Implicit Permanent Caches

Riverpod may retain state while it is observed, but this does not make every provider a permanent application cache.

A durable or long-lived cache requires an owning specification to define:

- cached data;
- authority versus cache semantics;
- invalidation;
- lifetime;
- consistency behavior;
- memory implications where material.

Rust remains the persistent-data authority unless an approved architecture revision says otherwise.

## 19. Controller Responsibilities

Controllers may:

- call focused APIs;
- own frontend feature/application state transitions;
- derive feature-level state from typed client models;
- coordinate asynchronous feature operations;
- enforce frontend concurrency policy;
- perform presentation/application-level validation that is genuinely frontend-owned;
- interpret typed frontend/client errors;
- invalidate or refresh intentional dependencies;
- prevent stale async completions from publishing state.

Controllers do not become a second backend application-service layer.

## 20. Controller Non-Responsibilities

Controllers must not:

- retain `BuildContext`;
- call `go_router` as an ordinary state transition;
- display dialogs, snackbars, toasts, or platform UI;
- inspect generated FRB types;
- call generated FRB bindings directly;
- persist data independently of Rust;
- implement backend domain validation or provider behavior;
- expose a generic service-locator API;
- own cross-feature application composition better placed in `app`;
- expose arbitrary state setters to consumers.

## 21. Intent-Oriented Controller Actions

Public controller methods describe feature/user intent.

Prefer:

```text
refresh
save
retry
loadNextPage
select
cancel
```

Avoid public feature APIs such as:

```text
setState
setLoading
setError
invalidateData
callBackend
```

when those names expose implementation mechanics rather than feature intent.

Private helpers may be technical when appropriate.

## 22. State Mutation Is Controller-Owned

Consumers initiate supported actions; the controller owns valid transitions.

Feature consumers do not receive a general-purpose public mutation surface equivalent to:

```text
controller.state = arbitraryState
```

This keeps invariants, concurrency policy, and error transitions in one owner.

## 23. Controller Infrastructure Is Private

A controller must not publicly expose mutable implementation infrastructure such as:

- its Riverpod `Ref`;
- a provider container;
- stream subscription handles;
- cancellation tokens;
- mutable caches;
- concrete client/bridge implementation objects.

The feature-facing contract is state plus meaningful actions.

## 24. Initial Readiness

For a controller requiring asynchronous initial data, the outer readiness contract is conceptually:

```text
AsyncLoading
    ↓
AsyncData(FeatureState)
```

or:

```text
AsyncLoading
    ↓
AsyncError
    ↓ retry
AsyncData(FeatureState)
```

`AsyncValue<State>` communicates whether enough initial authoritative state exists for the feature to be useful.

The initial loading/error boundary is distinct from later operational progress/failure.

## 25. Loaded State Must Remain Usable

Once the outer readiness state is `AsyncData(FeatureState)`, non-blocking work does not normally return it to global `AsyncLoading`.

Default refresh behavior is:

```text
ready(data, refresh = idle)
    ↓ refresh
ready(data, refresh = running)
    ↓ success
ready(newData, refresh = idle)
```

Default recoverable refresh failure is:

```text
ready(data, refresh = running)
    ↓ failure
ready(data, refresh = failed(error))
```

Usable data remains available.

## 26. Returning to a Non-Usable Readiness State

A controller may leave usable readiness only when the owning feature contract determines that the existing state can no longer be safely presented as usable.

This is exceptional compared with ordinary refresh/save/pagination failures.

Examples might include a material identity change that creates a new controller/provider owner or a fatal condition that invalidates the entire current projection.

A routine background error must not blank a loaded screen.

## 27. Explicit Operational State

Independent user-visible operations receive explicit state when progress or failure must coexist with already usable feature data.

Representative operations include:

```text
refresh
save
pagination
command
retry
```

Example conceptual state:

```text
LibraryState
├── items
├── selection
├── filter
├── refreshState
├── paginationState
└── commandState
```

The exact fields are owned by the applicable feature specification.

Do not add speculative operation fields for hypothetical future actions.

## 28. Meaningful Operation Unions

Genuine operation phases should use a meaningful immutable union/state representation.

Prefer conceptually:

```text
OperationState
├── idle
├── running
└── failed(error)
```

and add a success variant only when success itself has durable presentation/state meaning.

Avoid Boolean/null clusters such as:

```text
isSaving
saveFailed
saveSucceeded
saveError
```

that permit impossible combinations.

## 29. Initial Errors Versus Operational Errors

An initial `AsyncError` means the controller cannot yet provide usable feature state.

A loaded operational failure means usable state still exists:

```text
AsyncData(
  usable state
  + failed operation state
)
```

A failed background operation must not automatically be converted into an outer `AsyncError`.

This distinction is required for settings, refresh, pagination, and other non-blocking workflows.

## 30. Operation Error Ownership

An error belongs to the operation that produced it when operations are independently meaningful.

Avoid one ambiguous feature-level `error` field when the feature can simultaneously refresh, save, and paginate.

Prefer conceptually:

```text
refreshState = failed(...)
saveState = idle
paginationState = running
```

Errors are typed frontend/client errors, not raw transport strings.

## 31. Operation Error Lifetime

Operational errors remain available long enough for deterministic presentation and retry but do not accumulate indefinitely as controller-local history.

For example:

```text
save failed
    ↓
saveState = failed(error)
    ↓ retry
saveState = running
```

or an explicit feature acknowledgement may return the operation to idle.

Durable diagnostic history belongs to the diagnostics/observability architecture, not arbitrary feature state.

## 32. Freezed Requirement

All immutable Dart models required by ARCH-001 use Freezed, including:

- shared immutable domain/value models;
- client read models;
- feature/UI models;
- controller states;
- operation-state unions;
- drafts;
- validation results;
- settings models;
- event models;
- route-state models where applicable.

Freezed supplies generated equality/copy/union machinery rather than Argus maintaining duplicate handwritten equivalents without a concrete need.

## 33. Freezed Data Classes Versus Unions

Use a normal immutable Freezed data class when one stable shape accurately represents the model.

Use a Freezed union/sealed-state representation when valid phases are meaningfully distinct and structural modeling prevents invalid combinations.

Do not create a union solely because Freezed supports unions.

The goal is valid semantic state, not maximal type ceremony.

## 34. Nullable Fields

Nullable fields represent genuine optional values.

Appropriate examples include:

```text
selectedGameId?
optionalDescription?
```

Nullable fields must not be used to hide lifecycle phases such as:

```text
data?
loading?
error?
```

when only certain combinations are valid.

Meaningful lifecycle phases should be modeled explicitly.

## 35. Immutable Collections

Mutable collections must not leak through immutable model APIs.

Consumers must not be able to mutate controller state through a retained list/map/set reference.

State transitions conceptually follow:

```text
old immutable state
        ↓
construct new collection/state
        ↓
publish new immutable state
```

rather than mutating a collection behind an immutable-looking wrapper.

## 36. Equality Semantics

Freezed/model equality must reflect semantically relevant state.

Do not remove meaningful values from equality merely to suppress widget rebuilds.

When rebuild optimization is warranted, prefer:

- selective watching;
- derived providers;
- narrower widget dependencies;

rather than weakening state correctness.

## 37. JSON Serialization Is Separate

Freezed usage does not imply JSON serialization.

Add JSON serialization only where a real serialization boundary requires it, such as an approved transport, configuration, durable export/import, or another explicitly serialized contract.

Ordinary controller state does not receive `toJson()` merely because code generation makes it easy.

Generated `.freezed.dart` and `.g.dart` files are never hand-edited.

## 38. Model-Layer Restraint

The frontend mapping pipeline permits:

```text
Bridge DTO
→ client read model
→ feature model
→ UI model
```

but every mapping after the transport/client boundary is optional when it adds no semantic value.

If a client read model already has exactly the semantics a feature needs, direct feature/widget consumption is valid.

Do not create mechanically identical `ReadModel → FeatureModel → ViewModel` chains solely to satisfy a layer diagram.

Mapping exists to change ownership or semantics.

## 39. Provider Dependency Direction

The normal dependency direction is:

```text
widget
   ↓
feature controller / narrow derived provider
   ↓
focused API provider
   ↓
ArgusClient/client implementation
```

Widgets should not normally depend on the concrete root client when a feature controller/focused provider owns the interaction.

Controllers and features never depend on generated FRB bindings.

SPEC-FE-001 remains authoritative for source/import direction.

## 40. Watching, Reading, and Listening

A provider/controller uses dependency modes intentionally:

- **watch** when its state semantically depends on another provider and should react to changes;
- **read** for a command-time dependency when ongoing reactivity is not intended;
- **listen** for explicit effect/event coordination at a suitable application/presentation boundary.

Do not watch every accessible dependency by default.

An accidental watch can broaden lifecycle/rebuild semantics and recreate controllers unexpectedly.

## 41. Controller Reconstruction

If a watched dependency causes a controller to be recreated, that dependency must be part of the controller's semantic identity/readiness.

A controller must not lose meaningful in-progress state because an unrelated command dependency changed.

Dependencies needed only while executing an action should normally be read at action time rather than watched as controller identity inputs.

## 42. Derived State Should Remain Derived

When a value can be reliably computed from authoritative state, derive it instead of storing an independently mutable copy.

Representative derived values include:

```text
canSave
effectiveTheme
hasNextPage
selectedCount
```

Persist or cache derived state only when a demonstrated semantic/performance reason exists and ownership remains explicit.

## 43. Fine-Grained Watching

Widgets may use narrow derived providers or selective watching when it materially improves responsibility clarity, testability, or rebuild scope.

Do not fragment every model field into a separate provider merely for theoretical rebuild optimization.

The behavioral state owner remains cohesive even when consumers observe projections of that state.

## 44. Asynchronous Concurrency Policies

Every asynchronous controller action must have a defined concurrency policy.

The three default policy categories are:

| Policy | Typical use |
|---|---|
| Latest wins | refresh, search-backed fetch, identity-scoped reload |
| Single-flight / duplicate guarded | save, retry, submit, explicit command |
| Concurrent by identity | operations on distinct items/jobs when explicitly supported |

Feature specifications may refine these policies.

Completion timing must never accidentally determine which result becomes authoritative.

## 45. Latest-Wins Operations

For a latest-wins operation:

```text
request A starts
    ↓
request B starts
    ↓
request A finishes
    ↓
A is ignored as stale
    ↓
request B finishes
    ↓
B may publish
```

The controller needs a deterministic generation/request-identity mechanism.

Acceptable implementations include generation counters, request tokens, Riverpod lifecycle/cancellation mechanisms, or an equivalent approach.

The required behavior is semantic, not tied to one implementation trick.

## 46. Stale-Result Rule

> **An asynchronous result may update state only if it still belongs to the controller generation and operation that currently owns that result.**

This rule applies to successful and failed completions.

An obsolete failure must not replace a newer successful result merely because it completed later.

## 47. Single-Flight Operations

Operations for which duplicate execution is semantically wrong or confusing must be guarded by the controller.

Representative operations include:

```text
save
submit
retry startup step
start explicit command
```

The feature contract decides whether a duplicate request is ignored, rejected, coalesced, or replaces the previous operation.

Disabling a UI button is not sufficient correctness protection because controller methods may be called programmatically.

## 48. Concurrent-by-Identity Operations

Concurrency may be supported when distinct identities represent independent work.

For example, future feature contracts may allow operations for separate game/job/item identities to proceed concurrently.

When supported, operation state must be keyed by a typed identity or another explicit semantic owner rather than by ambiguous list position or ad hoc strings.

Concurrent-by-identity behavior is opt-in, not a universal default.

## 49. Disposal and Outstanding Work

When a provider/controller is disposed, outstanding frontend work must not later publish into that disposed owner.

Conceptually:

```text
request starts
    ↓
controller disposed
    ↓
request completes
    ↓
no obsolete state publication
```

This is required even when the underlying backend work itself continues.

## 50. Frontend Disposal Versus Backend Cancellation

Stopping frontend observation is not automatically equivalent to cancelling an authoritative Rust operation.

Conceptually:

```text
stop observing result
≠
necessarily cancel backend operation
```

Where a focused API exposes meaningful cancellation, disposal or user action may request it according to the owning contract.

Where backend work cannot or should not be cancelled, frontend disposal still prevents obsolete publication.

Backend cancellation authority remains outside this specification.

## 51. Optimistic Updates

Optimistic presentation is allowed only when rollback is deterministic and the feature contract explicitly permits optimistic behavior.

The controller must retain or be able to identify the last confirmed authoritative baseline.

Generic pattern:

```text
confirmed = A
presented = A
    ↓ user requests B
confirmed = A
presented = B
operation = running
```

Success confirms B; failure restores the known confirmed value A unless the owning feature defines another authoritative reconciliation path.

## 52. Confirmed Rollback Baseline

Rollback state must not be reconstructed heuristically after a failed optimistic operation.

For appearance settings conceptually:

```text
confirmed = Light
presented = Dark
save = running
```

Failure becomes:

```text
confirmed = Light
presented = Light
save = failed(error)
```

The exact appearance state is owned by SPEC-FE-006, but deterministic confirmed-baseline behavior is cross-feature policy.

## 53. Backend Events

Backend events are synchronization signals, not a second authoritative data store.

A backend event may cause Flutter to:

- refresh an authoritative read model;
- update a projection when the event contract contains sufficient authoritative information;
- mark currently loaded data stale;
- invalidate one focused provider intentionally.

The event stream must not create independently mutable competing truth.

## 54. Event-Driven Synchronization

The conceptual direction is:

```text
Rust authoritative state
        ↓
application event
        ↓
frontend event coordination
        ↓
focused refresh/projection update
        ↓
Riverpod state
```

When an event represents notification-only semantics, Flutter re-queries the authoritative focused API rather than treating the event payload as the durable aggregate.

This matches the Phase 000 appearance-settings event contract.

## 55. Event Subscription Lifetime

An event subscription lives with the semantic owner that needs it.

Preferred patterns include:

```text
shared event stream/provider
       ↓
feature-specific consumer
       ↓
feature controller/read provider
```

or application-level coordination under `app` when the concern truly crosses features.

Avoid one global callback object that directly mutates arbitrary feature controllers.

Disposal ends the feature's observation.

## 56. Invalidation and Refetch

Provider invalidation/refetch is deliberate.

It is appropriate when the provider's authoritative value should be reconstructed from its source.

Example:

```text
settings changed event
    ↓
invalidate/reload authoritative settings projection
```

Do not use broad cascading invalidation as a generic state-reset mechanism.

Avoid:

```text
something happened
→ invalidate everything
```

when explicit transition or focused refresh has clearer semantics.

## 57. Presentation Side Effects

Controllers expose facts/state; they do not execute Flutter presentation behavior.

Prohibited controller state/behavior includes:

```text
BuildContext callback
navigateTo closure
actual dialog function
ScaffoldMessenger invocation
clipboard/platform UI execution
```

Controllers may expose meaningful facts such as:

```text
saveState = failed(error)
restartRequired = true
```

Presentation decides how those facts are rendered.

## 58. One-Shot Presentation Effects

A one-shot presentation effect that cannot reasonably be modeled as durable state must use an explicit presentation/event mechanism at the feature or application composition boundary.

It must not embed `BuildContext` or executable UI callbacks into controller state.

The mechanism must be lifecycle-safe and testable.

Do not introduce a general-purpose global effect bus unless a later design demonstrates that one is necessary.

## 59. Navigation

Feature controllers do not call `go_router` as their ordinary behavior.

Typical flow is:

```text
user action
   ↓
controller operation when needed
   ↓
state/result
   ↓
presentation/app composition
   ↓
navigation
```

Purely presentational navigation may occur directly at the presentation boundary according to SPEC-FE-004.

Cross-feature navigation/composition remains owned by `app` where required by SPEC-FE-001.

## 60. Route Versus Riverpod State

Selection, filtering, sorting, view mode, and similar values have one owner.

Possible owners include:

- route/query state when intentionally addressable;
- Riverpod feature state;
- widget-local state when truly local.

Do not maintain independently mutable duplicates in both router and Riverpod.

SPEC-FE-004 defines which browsing values are intentionally routed/addressable.

## 61. Dependency Overrides

Production dependencies are substituted in tests through Riverpod overrides at approved provider seams.

Conceptually:

```text
SettingsApi provider
       ↓ production
ArgusClient.settings
```

and in test:

```text
SettingsApi provider
       ↓ override
FakeSettingsApi
```

Feature tests do not need FRB runtime initialization or Rust process setup when the focused API seam is sufficient.

## 62. Narrowest Useful Override

Tests override the narrowest dependency necessary for the behavior under test.

Preferred:

```text
settings controller test
→ override SettingsApi
```

rather than replacing the entire root `ArgusClient` when only settings behavior matters.

A pure derived-provider test similarly overrides only its direct authoritative inputs where practical.

This keeps failures diagnostic and test setup small.

## 63. Explicit Test Composition

Provider substitutions should be visible near test-container/scope construction.

Conceptually:

```text
ProviderContainer(
  overrides: [
    settingsApiProvider → fakeSettingsApi
  ]
)
```

Exact syntax follows the pinned Riverpod version.

Avoid global mutable test registries or hidden singleton replacement.

Tests normally own their provider container/scope unless read-only fixture reuse is demonstrably safe.

## 64. No Test-Mode Branching

Production feature/controller behavior must not depend on generic test-mode checks such as:

```text
if (isTest) ...
```

for ordinary dependency substitution.

Testability comes from focused interfaces, provider overrides, deterministic dependencies, and controlled async completion.

Production semantics remain the same under test.

## 65. Fakes Before Broad Mocks

Frontend tests prefer simple focused fakes/stubs when they express the scenario clearly.

Mocking frameworks are optional and require demonstrated value according to CONV-FLUTTER-001 and CONV-TEST-001.

Tests should not force production API design to accommodate a mocking framework.

## 66. Deterministic Async Tests

Controller/provider tests control completion order explicitly.

Prefer:

```text
create fake request A future
create fake request B future
complete B
assert
complete A
assert
```

rather than timing guesses such as:

```text
Future.delayed(...)
```

Arbitrary sleeps/delays are prohibited as correctness mechanisms.

## 67. Required Race Tests

Applicable controllers must test their concurrency policy directly.

Representative latest-wins test:

```text
refresh A starts
refresh B starts
B completes
A completes
→ B remains authoritative
```

Representative single-flight test:

```text
save starts
second save requested
→ duplicate policy enforced
```

Representative disposal test:

```text
request starts
provider disposed
request completes
→ no obsolete publication
```

## 68. Required Loaded-State Tests

Applicable controllers must demonstrate that usable state survives non-blocking work.

Representative refresh failure:

```text
ready(data)
refresh starts
refresh fails
→ data remains usable
→ refresh operation exposes typed failure
```

Representative pagination failure:

```text
existing pages
loadNextPage starts
loadNextPage fails
→ existing pages remain usable
```

## 69. Pagination State

For paginated features, existing accumulated results remain usable while the next page loads.

A next-page failure affects pagination state, not the validity of already loaded pages.

Replacement of the full collection occurs only when feature semantics establish a new authoritative identity/result, such as a changed routed scope or filter contract.

Detailed library behavior is deferred to the later library feature specification.

## 70. State Reset

Avoid generic public `reset()` methods unless “reset” has one unambiguous feature meaning.

State recreation should result from a semantic event such as:

- provider identity changing;
- route/detail scope changing;
- authoritative dependency changing;
- an explicit user/feature action;
- provider lifecycle ending.

Generic reset APIs often bypass the real state machine and should not be a default escape hatch.

## 71. Application-Lifetime Providers

Application-lifetime providers should remain few and intentional.

Expected Phase 000 candidates include conceptually:

- root `ArgusClient`/client infrastructure;
- runtime/readiness infrastructure;
- shared event connection/coordinator;
- application-level appearance/theme authority when required by SPEC-FE-006.

Most feature controller state is not application-lifetime by default.

## 72. Phase 000 Appearance Settings Pattern

The appearance-settings controller follows the general readiness/operational-state contract.

Initial flow:

```text
initial request
    ↓
AsyncValue<AppearanceSettingsState>
    ↓
ready(current confirmed setting)
```

Optimistic save conceptually:

```text
ready(Light confirmed, Light presented, idle)
    ↓ choose Dark
ready(Light confirmed, Dark presented, saving)
```

Success:

```text
ready(Dark confirmed, Dark presented, idle)
```

Failure:

```text
ready(Light confirmed, Light presented, failed(error))
```

SPEC-FE-006 owns the exact data shape and presentation behavior.

## 73. Phase 000 Event Reconciliation

A committed `AppearanceSettingsChanged` event causes the approved smallest authoritative reconciliation rather than establishing a second settings value.

Conceptually:

```text
AppearanceSettingsChanged
    ↓
frontend event coordination
    ↓
focused settings refresh/update
    ↓
Riverpod authoritative projection
    ↓
root theme derivation
```

Duplicate/coalesced notifications must not produce divergent settings truth.

## 74. Phase 000 Startup Pattern

Startup state uses `AsyncValue<State>` for mandatory initial readiness where appropriate.

Startup feature/controller tests must cover:

- initial loading;
- transition to ready;
- typed startup failure;
- retry/recovery transitions as finalized by SPEC-FE-005;
- disposal/stale result behavior when applicable.

A successful ready transition must not be overwritten by completion from an obsolete startup attempt.

## 75. Testing Layers

Frontend state tests use the narrowest useful boundary.

### Pure model tests

Test:

- value/equality semantics;
- Freezed unions;
- state transformations;
- pure invariants;
- derived calculations.

### Provider/derived tests

Test:

- dependencies;
- derivation;
- overrides;
- lifecycle where meaningful.

### Controller tests

Test:

- initial readiness;
- actions/transitions;
- typed failures;
- races;
- disposal/cancellation behavior;
- optimistic rollback;
- refresh/pagination preservation;
- event-driven reconciliation.

### Widget tests

Test observable rendering/interaction against provider overrides rather than retesting controller internals through private widget structure.

## 76. Required Phase 000 State Tests

At minimum, Phase 000 includes deterministic frontend-state evidence for:

### Startup

- initial loading;
- successful ready state;
- injected startup failure;
- retry/recovery state transition as applicable;
- stale attempt cannot overwrite newer readiness.

### Appearance settings

- initial authoritative value load;
- optimistic presentation where required by SPEC-FE-006;
- save running state;
- success confirmation;
- failure rollback to last confirmed value;
- retry;
- duplicate-save policy;
- stale-result protection for overlapping selections if the feature allows them.

### Event synchronization

- settings-change event causes approved authoritative reconciliation;
- no independent duplicate settings authority is created;
- disposed consumers do not publish later event-driven state.

## 77. Generated Source

Riverpod and Freezed generated source follows CONV-REPO-001.

Rules:

1. deterministic generated source required by the source/build contract is committed;
2. generated output is never hand-edited;
3. adjacent `.g.dart`/`.freezed.dart` placement follows generator-native Dart layout;
4. generation executes through the canonical root workflow;
5. generation drift fails canonical verification.

## 78. Canonical Generated-Source Verification

The implementation participates in:

```text
just generate
just check-generated
just check
```

according to CONV-REPO-001 and CONV-TEST-001.

A failed generated-source check is fixed by correcting authored source/generator configuration and regenerating, not by manually patching generated output.

## 79. Static Analysis

Static analysis should enforce mechanically provable rules where practical.

Examples include:

- authored provider style/code-generation expectations where tooling supports it;
- generated-source drift through repository checks;
- strong typing/nullability conventions;
- forbidden source dependency directions through SPEC-FE-001 architecture checks.

Semantic concurrency correctness remains primarily a controller-test/review responsibility when static tooling cannot prove it economically.

## 80. Performance and Rebuild Discipline

State architecture should not be fragmented for speculative rebuild optimization.

Prefer semantically cohesive state and use selective watching/derived providers when profiling or clear ownership demonstrates value.

Do not:

- split one state machine into many independently mutable providers merely to reduce rebuild counts;
- retain every feature provider forever as an unmeasured performance optimization;
- corrupt equality semantics to suppress rebuilds;
- move Rust-owned processing into Flutter state because it appears convenient.

## 81. Security and Privacy

Provider/controller state must not broaden sensitive-data exposure.

Rules include:

- credentials/secrets are not copied into feature state unless an owning secure-input contract explicitly requires transient handling;
- raw backend diagnostic payloads do not become arbitrary feature state;
- overrides/test doubles use synthetic data rather than developer credentials;
- state logging/debugging must follow approved observability/redaction rules.

The detailed security semantics remain with the owning backend/client/provider specifications.

## 82. Failure Behavior

Expected failures are represented explicitly through typed frontend/client errors and the appropriate readiness or operation state.

Do not:

- swallow errors into fabricated success;
- clear usable data merely because a non-blocking operation failed;
- publish raw FRB/backend technical strings as controller UI contracts;
- leave a controller permanently marked running after a handled completion;
- allow an obsolete failure to overwrite newer state.

Unexpected programming failures remain visible to the project's diagnostics/error-handling infrastructure rather than being silently converted to defaults.

## 83. Prohibited Patterns

The following are prohibited unless an approved architecture revision or more specific governing specification explicitly replaces the rule:

- a second frontend state-management/DI framework;
- authored providers routinely bypassing Riverpod code generation;
- one global provider bucket for unrelated concerns;
- global service-locator access hidden behind providers;
- `keepAlive` applied by default to feature state;
- Riverpod providers used as implicit permanent caches without defined cache semantics;
- `AsyncLoading` replacing already usable state during ordinary background work;
- one ambiguous feature error field for multiple independently observable operations;
- Boolean/null clusters that permit impossible lifecycle states;
- mutable collections escaping from immutable models;
- JSON generation on every Freezed model without a serialization boundary;
- controller public APIs exposing arbitrary state mutation;
- controllers retaining `BuildContext`;
- controllers directly navigating, displaying dialogs, snackbars, toasts, or platform UI;
- controllers importing or invoking generated FRB infrastructure;
- stale async completions overwriting newer state;
- disposed controllers publishing late results;
- duplicate-sensitive operations relying only on a disabled UI button for correctness;
- broad cascading invalidation used as generic reset;
- backend events treated as independently authoritative mutable state;
- derived providers with hidden commands/side effects;
- test-only behavior branches in production controllers for ordinary substitution;
- arbitrary sleeps/delays used to coordinate async tests;
- hand-editing Riverpod/Freezed generated output.

## 84. Example: Compliant Readiness and Refresh

```text
AsyncLoading
    ↓
AsyncData(ready(items, refresh = idle))
    ↓ refresh
AsyncData(ready(items, refresh = running))
    ↓ success
AsyncData(ready(newItems, refresh = idle))
```

A refresh failure keeps `items` and exposes the refresh error inside loaded state.

## 85. Example: Non-Compliant Global Reload

```text
AsyncData(ready(items))
    ↓ refresh
AsyncLoading
    ↓
loaded screen disappears
```

This is non-compliant for ordinary non-blocking refresh unless a specific feature contract establishes that old data is unsafe to present.

## 86. Example: Compliant Latest-Wins Race

```text
refresh generation 4 starts
refresh generation 5 starts
4 completes
→ ignored
5 completes
→ publishes
```

Completion order cannot restore generation 4.

## 87. Example: Compliant Focused Override

```text
AppearanceSettingsController
        ↓
SettingsApi provider
        ↓ test override
FakeSettingsApi
```

The test does not initialize FRB or the Rust backend.

## 88. Example: Non-Compliant Direct Transport Test Seam

```text
AppearanceSettingsController test
        ↓
mock generated FRB function
```

This couples feature behavior to transport generation and bypasses the focused API boundary.

## 89. Example: Compliant Derived State

```text
settings state
    ↓
effectiveTheme derived provider
    ↓
MaterialApp
```

Reading `effectiveTheme` performs no command or persistence.

## 90. Example: Non-Compliant Hidden Effect

```text
canSave provider is watched
    ↓
provider silently calls backend save
```

A value provider must not hide an application command.

## 91. Enforcement

The contract is enforced using the strongest practical mechanism for each rule.

### Analyzer/lints

Use strict Dart analysis and approved lints according to CONV-FLUTTER-001.

### Generated-source checks

Use deterministic generation and drift verification through CONV-REPO-001.

### Architecture checks

Use SPEC-FE-001 checks to keep provider/controller source behind correct feature/core/app boundaries and away from generated transport imports.

### Controller/provider tests

Use deterministic fakes and controlled completion to prove transition, race, lifetime, and error behavior.

### Review

Review verifies semantic decisions that static tools cannot economically prove, including whether state has the correct owner, whether a provider lifetime is justified, and whether the chosen concurrency policy matches feature intent.

## 92. Phase 000 Acceptance Properties

For the Phase 000 frontend foundation, implementation must demonstrate:

1. one root Riverpod composition scope;
2. authored providers use Riverpod code generation;
3. focused client/API dependencies are exposed at semantic provider seams;
4. feature state is owned by feature controllers/providers rather than widgets or transport infrastructure;
5. asynchronous initial readiness uses the approved `AsyncValue<State>` pattern where required;
6. settings remains usable while a save is in progress;
7. a failed settings update restores the last confirmed value;
8. backend settings events cause authoritative reconciliation rather than duplicate state ownership;
9. stale/disposed async completions cannot overwrite current state;
10. feature/controller tests execute against focused API fakes without the real Rust backend;
11. generated Riverpod/Freezed source is current and unmodified.

## 93. General Acceptance Criteria

An implementation conforming to this specification satisfies all of the following:

1. Riverpod is the sole frontend DI/state-management framework.
2. Authored Argus providers use Riverpod code generation.
3. Provider placement follows semantic ownership from SPEC-FE-001.
4. Provider categories remain understandable as dependency, derived, controller, or identity-parameterized concerns.
5. One root application provider scope owns production composition.
6. Nested scopes have explicit ownership/lifecycle reasons.
7. Provider lifetime matches owned state/resource lifetime.
8. Long-lived/`keepAlive` behavior is explicit rather than default.
9. Controllers expose intent-oriented actions and own valid transitions.
10. Controllers do not expose `BuildContext`, general state setters, or mutable infrastructure.
11. Initial asynchronous readiness uses `AsyncValue<State>` where applicable.
12. Loaded usable data is preserved during non-blocking operations by default.
13. Independently observable operations use explicit state where needed.
14. Genuine lifecycle phases use meaningful immutable modeling rather than invalid Boolean/null clusters.
15. Immutable Dart models use Freezed according to ARCH-001.
16. JSON generation is limited to actual serialization boundaries.
17. Mutable collections do not leak to consumers.
18. Derived providers are pure and derived values are not independently mutable without reason.
19. Every async controller action has a defined concurrency policy.
20. Stale or disposed completions cannot publish state.
21. Duplicate-sensitive operations enforce controller-level duplicate policy.
22. Optimistic operations retain a deterministic confirmed rollback baseline.
23. Backend events synchronize frontend state without establishing competing authority.
24. Broad invalidation is not used as a generic reset mechanism.
25. Presentation effects and navigation remain at presentation/composition boundaries.
26. Typed provider identities are used for parameterized state where applicable.
27. Tests override the narrowest useful focused provider/API seam.
28. Production code contains no ordinary test-mode branches for substitution.
29. Async tests control completion explicitly and use no guessed timing delays for correctness.
30. Generated Riverpod/Freezed source passes canonical drift verification.
31. Ordinary controller/feature tests do not require the real Rust backend.

## 94. Out of Scope

This specification intentionally leaves the following to later frontend specifications:

- exact focused client/API interfaces and typed frontend error models;
- exact routing/query ownership and navigation contracts;
- startup/recovery UI state variants and recovery actions;
- exact appearance-settings state fields and optimistic interaction presentation;
- design-system loading/progress/error components;
- accessibility semantics for specific controls;
- library/search/filter/pagination feature state beyond the generic rules here.

It also does not define a general frontend cache layer, offline mode, or a persistent frontend state store.

## 95. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](spec-fe-004-routing-and-adaptive-application-shell.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [CONV-DOC-001 — Documentation and Codex Result Conventions](../../conventions/conv-doc-001-documentation-and-codex-result-conventions.md)
- [Frontend Specifications Index](README.md)
- [Subsystem Specification Template](../../templates/subsystem-specification.md)
