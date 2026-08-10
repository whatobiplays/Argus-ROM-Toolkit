# Flutter/Dart Coding and Test Conventions

**Document ID:** CONV-FLUTTER-001  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-09  
**Depends On:** ARCH-001, PHASE-000, SPEC-BE-003, SPEC-BE-004, SPEC-BE-008, CONV-REPO-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This convention defines repeatable Dart/Flutter coding, state-management, bridge-isolation, async/error-handling, dependency, and Flutter-test-writing rules for handwritten Argus frontend code.

It exists to keep frontend implementation predictable across human and Codex-authored changes while preserving the architecture defined by ARCH-001 and the backend/bridge contracts.

Argus deliberately relies on established Dart/Flutter ecosystem conventions for ordinary language style. This document therefore focuses on rules that materially affect Argus architecture, maintainability, correctness, and testability rather than duplicating a general Flutter style guide.

This convention does not redefine:

- the detailed Flutter project/feature layout owned by SPEC-FE-001;
- the detailed Riverpod/Freezed/controller-state contract owned by SPEC-FE-002;
- the focused `ArgusClient` API contract owned by SPEC-FE-003;
- routed shell behavior owned by SPEC-FE-004;
- startup/recovery presentation owned by SPEC-FE-005;
- appearance/theme behavior owned by SPEC-FE-006;
- design-system and accessibility requirements owned by SPEC-FE-007;
- backend error semantics owned by SPEC-BE-003;
- backend runtime/operation semantics owned by SPEC-BE-004;
- bridge DTO semantics owned by SPEC-BE-008;
- generated-file policy and root developer workflows owned by CONV-REPO-001;
- the repository-wide test pyramid, fixture taxonomy, and verification matrix owned by CONV-TEST-001.

More specific frontend specifications may refine this convention without weakening its architectural boundaries.

## 2. Governing Invariant

> **Argus Flutter code should keep transport, application state, presentation state, and widgets visibly separated; preserve strong typing across those boundaries; and remain independently testable without requiring the real Rust backend for ordinary feature tests.**

## 3. Dart and Flutter Baseline

Handwritten frontend source follows current stable Dart and Flutter conventions supported by the repository-pinned Flutter SDK.

The baseline includes:

- `dart format` as the formatting authority;
- `flutter_lints` as the starting lint set;
- a small curated Argus-specific lint extension where a rule provides durable value;
- Dart analyzer strict modes for casts, inference, and raw generic types unless an approved generated/third-party boundary requires a narrow exception;
- Effective Dart naming, API, import-ordering, and documentation conventions;
- null-safe Dart throughout authored source.

The project does not maintain a competing formatting or naming style guide.

Exact package/tool versions are pinned by the repository bootstrap/lockfiles and are not hard-coded into this convention.

## 4. Formatting, Analysis, and Lints

Canonical Flutter verification includes the equivalent of:

```text
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

These checks execute through the root `just` workflows defined by CONV-REPO-001.

Rules:

1. `dart format` owns whitespace and formatting.
2. Analyzer errors and warnings fail canonical verification.
3. Enabled lint violations fail canonical verification.
4. `analysis_options.yaml` should enable `strict-casts`, `strict-inference`, and `strict-raw-types` for authored code unless the pinned toolchain makes a specific mode impractical.
5. Additional lint rules are curated for demonstrated project value rather than enabling every available lint.
6. A lint/analyzer suppression is scoped as narrowly as practical.
7. A non-obvious suppression includes a reason.
8. Broad file/package suppression must not conceal an architecture violation, untyped transport leakage, lifecycle error, or speculative dead code.
9. Generated source may receive generator-specific analysis treatment according to CONV-REPO-001.

## 5. Naming and Source Organization

Use Effective Dart naming conventions and choose names that expose feature/domain meaning.

Rules:

- types, models, controllers, routes, APIs, and widgets use names that identify their actual responsibility;
- source filenames use Dart's conventional lowercase-with-underscores form;
- functions/methods describe their action or returned meaning rather than implementation mechanics;
- Boolean names read naturally as conditions;
- abbreviations follow established project/ecosystem terminology and otherwise favor readability;
- avoid vague buckets such as `helpers`, `misc`, or `utils` when a narrower owner exists.

The detailed feature-first directory layout is owned by SPEC-FE-001. This convention requires only that source organization preserve the dependency boundaries defined by ARCH-001.

## 6. Import and Dependency Boundaries

Imports should make architectural ownership visible.

Rules:

1. Feature code may depend on its own internals and approved `core`/client/application entry points.
2. A feature must not import another feature's private `src/` implementation.
3. Circular feature dependencies are prohibited.
4. Stable shared concepts move to a justified `core` owner only when no feature remains their natural owner.
5. Cross-feature orchestration belongs in `app` rather than creating feature cycles.
6. Bridge-generated source remains behind the bridge/client infrastructure boundary.
7. `core/domain` remains independent of Flutter widgets, Riverpod, features, and generated bridge bindings as required by ARCH-001.
8. Across architectural boundaries, package/public entry-point imports are preferred when they make ownership clearer; cohesive local implementation may use normal relative imports.
9. Generated `part` directives follow the generator's native Dart layout.

Public entry points should be intentionally small. Do not export internal files merely to make tests or wiring convenient.

## 7. Widgets and Presentation Responsibility

Flutter widgets own rendering and interaction, not authoritative business behavior.

Widgets may own:

- layout and rendering;
- user interaction wiring;
- local focus/hover/animation mechanics;
- presentation adaptation;
- navigation/dialog/toast initiation at presentation boundaries;
- watching feature state and rendering its current state.

Widgets must not own:

- Rust-domain validation rules;
- persistence behavior;
- backend workflow decisions;
- bridge DTO interpretation;
- application retry policy;
- authoritative job/runtime state;
- provider behavior;
- cross-feature business orchestration.

A widget `build()` method must not trigger backend commands merely because rendering occurred.

Extract a widget/component when a piece has its own responsibility, semantics, adaptive behavior, reuse, or focused test need. Do not split solely to satisfy an arbitrary line-count limit.

## 8. `BuildContext` and Presentation Side Effects

`BuildContext` is a presentation-layer dependency.

It must not become a dependency of:

- frontend domain primitives;
- client/read models;
- `ArgusClient` focused APIs;
- Riverpod controllers/notifiers;
- transport/bridge mappers;
- feature application logic.

Context-dependent concerns such as navigation, dialogs, localization lookup, theming, focus, and platform UI remain at widget/presentation/composition boundaries.

Presentation side effects react to explicit user actions or state transitions through intentional listeners/effects. They are not hidden inside pure state mapping or model construction.

Normal Flutter lifecycle rules apply when using `BuildContext` after asynchronous gaps; stale/unmounted contexts must not be used.

## 9. State Ownership

Every piece of frontend state has one clear owner.

Use widget-local state when the state is truly local to one widget instance and represents short-lived presentation mechanics such as:

```text
hover state
focus state
animation controller state
temporary expansion
drag interaction
```

Use Riverpod/controller state when information:

- survives widget reconstruction;
- is shared across widgets;
- represents backend/read-model state;
- represents an asynchronous operation;
- affects feature behavior;
- participates in selection/filter/sort/pagination behavior;
- needs deterministic testing independent of one widget instance.

Do not promote state globally merely because it might someday be shared.

Do not duplicate the same authoritative value independently across multiple providers/controllers/widgets.

## 10. Riverpod Discipline

ARCH-001 requires Riverpod for dependency injection and state exposure and requires generated providers.

Rules:

1. Authored Argus providers use Riverpod code generation.
2. Widgets consume the narrowest feature-local provider that represents their need.
3. Providers/controllers depend on focused APIs or other intentional providers, not generated FRB bindings.
4. Provider lifetime matches the state/resource it owns.
5. `keepAlive` or equivalent long-lived behavior is an explicit lifecycle decision, not a default.
6. Provider invalidation/refetch is deliberate and must not be used as a generic state-reset mechanism when a clearer state transition exists.
7. A provider should not become a global service locator for unrelated dependencies.
8. Related state that forms one behavioral state machine should normally have one cohesive controller/state owner rather than several independently synchronized mutable sources.
9. Unrelated state should not be combined merely to reduce provider count.

SPEC-FE-002 owns the exact provider categories, controller state shapes, and lifecycle policies.

## 11. Immutable Models and Freezed

ARCH-001 requires Freezed for immutable Dart model types, including read models, UI models, controller states, drafts, validation results, route state, operational-state unions, settings models, and event models.

Rules:

1. Model state is immutable from the consumer's perspective.
2. State transitions produce new model values rather than mutating shared model state in place.
3. Mutable collections do not leak through model APIs.
4. Union/sealed-state modeling is preferred when the valid states are meaningfully distinct.
5. Freezed is used where the architecture requires immutable model generation; do not duplicate its generated equality/copy/union machinery manually without a concrete reason.
6. JSON serialization is added only where an actual serialization boundary requires it.
7. Generated `.freezed.dart`/`.g.dart` output is never hand-edited.

## 12. Types, Nullability, and `dynamic`

Preserve static type information throughout application and feature code.

Rules:

- `dynamic` is avoided in authored application/feature code when a real type can be expressed;
- raw generic types are avoided;
- untyped JSON/maps are interpreted at the boundary that owns them rather than propagated through the application;
- prefer `Object?`/explicit decoding at genuinely untyped boundaries over spreading `dynamic` downstream;
- nullable values represent genuine semantic absence;
- do not use nullable fields merely to avoid modeling distinct application states;
- avoid force-unwrapping with `!` unless the invariant is structurally guaranteed and evident;
- recoverable/user-controlled absence is handled explicitly;
- `late` is not used merely to bypass unclear initialization/lifecycle ownership.

When a value has distinct loading/ready/failed phases, model the phases rather than using a cluster of loosely related nullable fields.

## 13. Typed Identifiers

Bridge DTOs may use serialization-friendly strings or primitives for identifiers according to SPEC-BE-008.

`ArgusClient` converts those values into typed Dart identifiers before they enter ordinary application/feature code.

Representative types include:

```text
GameId
JobRunId
LibraryRootId
SourceEntryId
PlatformId
```

Rules:

1. Feature/application code uses typed identifiers.
2. Do not pass interchangeable raw ID strings through the frontend merely because they originated that way at the bridge.
3. ID parsing/validation occurs at the client/mapping boundary.
4. Widgets do not construct backend identifiers by ad hoc string manipulation.

## 14. Bridge and Transport Isolation

Generated `flutter_rust_bridge` bindings and transport DTOs are infrastructure details.

They may appear inside the bridge/client implementation boundary but must not appear in:

- feature widgets;
- feature controllers;
- feature models;
- route state;
- shared frontend domain primitives;
- design-system components.

The mapping direction is:

```text
FRB/generated transport DTO
    ↓
bridge/client mapper
    ↓
typed frontend read model
    ↓
optional feature presentation mapper
    ↓
UI model/widget
```

Rules:

1. Widgets never call generated bridge bindings directly.
2. Features depend on narrow focused APIs rather than the concrete root bridge/client implementation.
3. Bridge DTOs never enter feature code.
4. Client APIs do not return widget-specific presentation models.
5. Bridge mappings perform translation/validation only; they do not implement business rules that belong to Rust.
6. Transport failures remain distinct from application failures where SPEC-BE-008 requires that distinction.
7. Backend technical/transport implementation types do not become frontend public contracts.

## 15. `ArgusClient` Boundary

ARCH-001 defines one root backend gateway with focused APIs such as:

```text
ArgusClient
- library
- games
- jobs
- settings
- sources
- diagnostics
- events
```

The root client owns bridge-facing infrastructure such as generated bindings, lifecycle/readiness, shared mapping, common error translation, event connection, tracing, and cross-cutting transport policy.

Feature code depends on the focused API it needs.

Do not:

- inject the concrete root client everywhere by convenience;
- create feature-local wrappers that duplicate focused client semantics without a real adaptation need;
- bypass the focused API to access generated bindings;
- reinterpret backend error/event contracts independently in multiple features.

SPEC-FE-003 owns exact Dart API shapes.

## 16. Controller and Async State

Controller methods express feature/user intent rather than low-level transport invocation.

Representative names include:

```text
refresh
save
retry
loadNextPage
select
cancel
```

The architecture distinguishes initial readiness from subsequent operations.

Conceptually:

```text
initial state
    -> loading / error / ready

ready state
    -> usable data + explicit refresh/save/pagination/command state
```

Rules:

1. Initial readiness may use `AsyncValue<State>` according to ARCH-001/SPEC-FE-002.
2. Once usable data is loaded, a background refresh/pagination/save/command does not replace the whole feature with a global loading state.
3. Recoverable background failures preserve usable data where the owning feature contract permits continued use.
4. Async controller methods handle expected failure explicitly.
5. A disposed controller/provider must not publish obsolete state.
6. Stale operation completions must not overwrite a newer authoritative result.
7. Concurrent operations are either intentionally supported or deliberately guarded by the owning feature contract.
8. Do not coordinate correctness through guessed timing delays.
9. Cancellation/replacement behavior follows the underlying application/runtime operation contract when available.

Exact controller-state unions and operation policies belong to SPEC-FE-002 and feature specifications.

## 17. Routes Versus Transient State

ARCH-001 defines the ownership split:

- routes represent durable location and scope;
- Riverpod owns transient interaction/application state.

Examples of durable routed state include:

```text
/library
/library/platforms/:platformId
/games/:gameId
/settings
```

Examples of transient state include selection mechanics, temporary operational status, focus/hover state, and feature-controller state.

Query parameters may represent user-visible temporary browsing state when SPEC-FE-004 intentionally makes that state addressable/shareable.

Do not maintain independent authoritative copies of the same state in both router and Riverpod. Define one owner and derive the other representation when needed.

## 18. Error Handling and User Presentation

Flutter consumes the structured failure contract mapped from the backend/client boundary.

Feature/widget code must not use the following as its normal error model:

```text
Exception.toString()
raw FRB exceptions
raw transport exceptions
Map<String, dynamic>
backend technical messages
```

Rules:

1. Stable backend application errors are mapped centrally into typed frontend failure/error models.
2. Transport failures remain distinguishable when SPEC-BE-008 requires it.
3. User-facing messages are selected/presented at the frontend presentation/localization layer rather than treating backend technical text as UI copy.
4. Technical details remain available only through approved diagnostic presentation paths.
5. Controllers preserve usable state after recoverable background-operation failure where appropriate.
6. Local draft/validation errors may remain feature-local when their semantics are purely frontend/presentation concerns.
7. Unexpected programming failures are not silently converted into fabricated success, empty collections, or default state.
8. Catch blocks do not swallow failures merely to keep the UI moving.

## 19. Side Effects and Event Reactions

State computation and presentation side effects remain distinct.

Controllers may initiate application operations through focused APIs. Presentation-only effects such as navigation, dialogs, toasts/snackbars, focus changes, clipboard operations, and platform UI are triggered at widget/presentation/composition boundaries.

Runtime/domain event notifications follow the unified event-stream architecture. Features react by refreshing authoritative state rather than treating notification payloads as mutable authoritative state unless the owning contract explicitly says otherwise.

Event listeners must respect runtime-generation/lifecycle semantics defined by SPEC-BE-004 and SPEC-BE-008.

## 20. Responsive and Adaptive Code

ARCH-001 requires layout adaptation based on available width/constraints rather than hardware category.

Coding rules:

1. Use centralized window size classes for application-shell structure when defined by the design system.
2. Components adapt to their local constraints when nested layout width may differ from the window width.
3. Avoid platform/device-name checks to choose layouts when available constraints are the real requirement.
4. Keep the same route/controller state across compact and wide presentations when the owning feature contract defines one semantic screen.
5. Responsive branches change presentation, not business semantics.

Exact breakpoints and design-system primitives belong to SPEC-FE-007.

## 21. Accessibility and Input

SPEC-FE-007 owns the accessibility baseline. Handwritten Flutter code must not undermine it.

At minimum:

- use semantic Flutter controls before custom gesture-only substitutes when practical;
- preserve keyboard/focus operation for desktop interactions that require it;
- provide semantics/labels where visual presentation alone is insufficient;
- do not encode state solely through color when the design-system specification requires another cue;
- custom interactive components require an accessibility/focus story proportional to their importance.

Detailed accessibility acceptance criteria remain in SPEC-FE-007 and CONV-TEST-001.

## 22. Dependencies

New Flutter/Dart dependencies require a concrete maintenance, correctness, accessibility, or productivity benefit.

Guidelines:

1. Prefer Flutter/Dart SDK capabilities when they provide a clear maintainable solution.
2. Prefer mature focused packages over bespoke infrastructure for well-solved problems when adoption reduces maintenance risk.
3. Avoid introducing a second state-management framework, router, immutable-model framework, or bridge abstraction without an explicit architecture revision.
4. Avoid broad convenience packages for one trivial helper.
5. Consider maintenance activity, ecosystem adoption, platform support, license compatibility, transitive dependency impact, and API stability when a dependency is material.
6. Generated-code dependencies required by Riverpod/Freezed/JSON/FRB are evaluated as part of those approved architecture choices.
7. Dependency/lockfile changes follow CONV-REPO-001.

A dependency is not rejected merely because equivalent code could be written manually.

## 23. Generated Source

Generated frontend source follows CONV-REPO-001.

Examples include:

- Riverpod provider output;
- Freezed model output;
- JSON serialization output;
- generated `flutter_rust_bridge` Dart source.

Rules:

1. Deterministic generated source required by the repository source/build contract is committed.
2. Generated files are not hand-edited.
3. Dart `part` output stays adjacent to authored source when required by the generator model.
4. Large FRB generated surfaces may use an explicit bridge-owned generated boundary when supported by tooling/configuration.
5. Generation runs through `just generate`.
6. Canonical verification detects generated-source drift through `just check-generated`/`just check`.
7. Generator-specific analyzer/lint exclusions are scoped to generated boundaries rather than weakening authored-code checks.

## 24. Production Source Hygiene

Completed frontend production code must not contain accidental development artifacts.

Prohibited in completed implementation slices:

- committed `print()`/`debugPrint()` diagnostics used instead of the Argus observability path;
- unresolved placeholder implementations;
- commented-out obsolete implementations;
- fabricated empty/default state used to hide a real failure;
- raw backend/transport exception text presented directly to users;
- temporary direct FRB access outside the client/bridge boundary;
- arbitrary `Future.delayed`/timers used to make synchronization "work";
- broad analyzer/lint disabling used to suppress authored-code problems;
- speculative public entry points kept for hypothetical future use;
- mutable global state bypassing Riverpod/owned state transitions.

A semantic delay such as a documented debounce, animation timing, or deliberate UX timeout is not prohibited; guessed timing used as a correctness mechanism is.

## 25. Flutter/Dart Test Placement

CONV-TEST-001 owns the repository-wide test pyramid. Within Flutter/Dart, tests live at the narrowest useful boundary that verifies observable behavior.

Use:

- Dart unit tests for pure models, identifiers, validators, and mappers;
- provider/controller tests for Riverpod state transitions and async behavior;
- widget tests for component rendering, interaction, focus, semantics, and adaptive behavior;
- focused routing/shell tests for route-to-presentation behavior;
- broader Rust↔Flutter/system integration tests only when the behavior genuinely crosses the native boundary, as defined by CONV-TEST-001.

A bug fix should normally include a regression test at the lowest boundary that reproduces the defect and protects the intended contract.

## 26. Test Seams and Doubles

Frontend tests use existing architecture boundaries as substitution seams.

Conceptually:

```text
Widget
    ↓
Riverpod controller/provider
    ↓
focused API interface
    ↓
ArgusClient
    ↓
bridge
```

Rules:

1. A feature test normally substitutes the narrow focused API/provider it consumes rather than mocking generated FRB calls.
2. Prefer simple fakes/stubs over a mocking framework when they communicate the scenario clearly.
3. Introduce a mocking framework only when repeated interaction assertions/test-double boilerplate create demonstrated maintenance value.
4. Production API shape must not be distorted solely to satisfy a mocking framework.
5. Shared test support has a clear owner and does not become an unrestricted `helpers`/`utils` dumping ground.

## 27. Test Determinism

Tests must be repeatable and independent of incidental developer-machine state.

Avoid unnecessary dependence on:

- wall-clock timing;
- execution order;
- public network availability;
- real external provider accounts/credentials;
- developer filesystem layout;
- shared mutable global state;
- arbitrary sleeps/delays;
- the real Rust backend for ordinary feature/controller/widget tests.

Use provider overrides, focused API fakes, controlled clocks/timers where appropriate, deterministic test data, and explicit synchronization/state transitions.

Async tests wait for meaningful completion/state changes rather than sleeping for a guessed duration.

## 28. Widget and Interaction Tests

Widget tests assert user-visible behavior and semantics rather than private widget-tree implementation where practical.

Prefer assertions about:

- visible content/state;
- enabled/disabled actions;
- navigation result;
- focus/keyboard behavior;
- error/progress presentation;
- semantics/accessibility behavior;
- adaptive presentation at representative constraints.

Avoid brittle assertions that depend on incidental nesting/order of private widgets when that structure is not part of the contract.

Golden/snapshot testing is optional and introduced only where visual regression value exceeds update noise. It is not a substitute for semantic interaction tests.

## 29. Controller and Error Tests

Controller/provider tests should verify explicit state transitions and stale/concurrent operation behavior where relevant.

Error-path tests assert typed frontend failure/application semantics rather than matching arbitrary formatted exception strings.

Examples of useful regression placement:

```text
bridge/read-model mapping bug
    -> mapper unit test

controller race or refresh-state bug
    -> controller/provider test

responsive interaction bug
    -> widget test

route restoration bug
    -> routing/widget integration test
```

## 30. Performance and Rebuild Discipline

Do not complicate ordinary Flutter code for speculative performance gains.

Rules:

1. Keep expensive domain/processing work in Rust according to ARCH-001 rather than moving it into widget builds/UI-isolate logic.
2. Do not initiate bridge calls or heavy mapping in `build()`.
3. Use lazy/virtualized Flutter collection primitives for large lists/grids where the feature requires scalable rendering.
4. Optimize rebuild scope only when state ownership or profiling demonstrates a real issue; do not fragment providers/widgets solely to chase hypothetical rebuild counts.
5. Cache only when ownership, invalidation, and memory cost are clear.
6. Preserve correctness/accessibility while optimizing.
7. Use repeatable profiling/benchmarks when performance becomes an acceptance requirement.

## 31. Prohibited Patterns

The following are prohibited unless an owning specification explicitly requires and justifies an exception:

- widgets calling generated FRB bindings directly;
- bridge DTOs/generated transport types in feature code;
- raw transport/application exceptions as widget state;
- backend technical error strings used directly as user-facing UI copy;
- `BuildContext` in controllers, client APIs, read models, or frontend domain primitives;
- business/persistence/provider rules implemented in widgets;
- backend commands triggered by widget `build()` execution;
- circular feature dependencies;
- importing another feature's private `src/` implementation;
- untyped JSON/maps propagated beyond their decoding boundary;
- habitual `dynamic`/raw generic types in authored feature/application code;
- nullable-field clusters used instead of meaningful state phases;
- force-unwrapping user/runtime-controlled absence;
- duplicated authoritative state independently owned by router and Riverpod;
- global providers introduced without a real shared lifecycle/ownership need;
- arbitrary delay-based async synchronization;
- stale async completions overwriting newer authoritative state;
- mutable model collections escaping to consumers;
- a second frontend state-management/router/model framework without architecture revision;
- hand-editing generated Dart/FRB source;
- broad analyzer/lint disables;
- committed diagnostic `print()`/`debugPrint()` usage instead of approved observability;
- performance complexity without evidence.

## 32. Examples

### 32.1 Compliant: Feature consumes focused API

```text
SettingsWidget
    ↓
appearanceSettingsControllerProvider
    ↓
SettingsApi
    ↓
ArgusClient
```

The widget does not know about FRB-generated operations or DTOs.

### 32.2 Non-Compliant: Direct bridge call

```text
SettingsWidget
    ↓
generated FRB bindings
```

This bypasses frontend application/client boundaries and couples presentation to transport generation.

### 32.3 Compliant: Preserve loaded state during refresh

```text
ready(items)
    ↓ refresh
ready(items, refresh = inProgress)
    ↓ success
ready(newItems)
```

### 32.4 Non-Compliant: Background refresh blanks screen

```text
ready(items)
    ↓ refresh
loading
    ↓
whole screen disappears
```

unless the owning feature contract explicitly requires blocking use of stale data.

### 32.5 Compliant: Typed ID mapping

```text
BridgeGameDto.gameId: String
    ↓ client mapper
GameId
    ↓
feature/controller/widget
```

### 32.6 Non-Compliant: Raw ID everywhere

```text
String gameId
    ↓
controller
    ↓
route
    ↓
widget
```

when `GameId` is the established frontend concept.

### 32.7 Compliant: Deterministic controller test

```text
create provider container with fake SettingsApi
invoke save
complete fake operation explicitly
assert state transition
```

### 32.8 Non-Compliant: Timing guess

```text
invoke save
Future.delayed(500 ms)
assert that it probably completed
```

## 33. Enforcement

The convention is enforced through the strongest practical mechanism for each rule.

### 33.1 Formatting

Canonical formatting verification runs `dart format` in check mode through the root `just` workflow.

### 33.2 Analyzer and Lints

`flutter analyze` runs under the repository `analysis_options.yaml` with the approved baseline/strictness. Authored-code warnings/lint violations fail canonical verification.

### 33.3 Generated-Source Drift

`just check-generated`/`just check` regenerates or validates committed Riverpod/Freezed/JSON/FRB source according to CONV-REPO-001 and fails on drift.

### 33.4 Architecture Checks

Mechanically enforceable boundaries should be tested where practical, including:

- feature-private `src/` imports;
- bridge/generated imports outside approved boundaries;
- prohibited dependency direction;
- other frontend boundary rules defined by SPEC-FE-001/SPEC-FE-003.

### 33.5 Unit, Provider, and Widget Tests

`flutter test` is part of canonical frontend verification unless CONV-TEST-001 later defines a more precise equivalent command matrix while preserving coverage.

### 33.6 Review

Review covers requirements that are difficult to enforce mechanically, including:

- whether state has the correct owner;
- whether a widget contains application/business logic;
- whether `BuildContext` has leaked below presentation;
- whether `dynamic`, nullable state, or force-unwrapping hides weak modeling;
- whether provider lifetime is broader than necessary;
- whether async completion can overwrite newer state;
- whether an additional dependency is justified;
- whether tests sit at the narrowest useful boundary;
- whether optimization complexity is evidence-driven.

## 34. Exceptions

Exceptions use the lightest durable mechanism that preserves architectural clarity.

1. A local lint/analyzer exception is allowed when code is clearer/correct and the suppression is narrowly scoped.
2. Non-obvious suppressions include a reason.
3. Generated-code exceptions follow CONV-REPO-001.
4. A third-party/generated incompatibility with strict analyzer modes is isolated to the narrowest boundary possible before weakening project-wide analysis.
5. A durable exception that changes bridge isolation, feature dependency direction, state ownership philosophy, routing ownership, or client boundaries requires updating this convention or the owning architecture/frontend specification.
6. A local implementation exception may be documented in the implementation slice/task when it does not alter a durable repository rule.

## 35. Acceptance Criteria

CONV-FLUTTER-001 is satisfied by an applicable implementation slice when:

1. Authored Dart source is `dart format` compliant.
2. `flutter analyze` is clean under the project analysis configuration.
3. Strict Dart analyzer modes are enabled or any narrow incompatibility is explicitly documented/scoped.
4. Lint/analyzer suppressions are narrow and justified where non-obvious.
5. Source/import dependency direction follows ARCH-001 and applicable frontend specifications.
6. No feature imports another feature's private implementation.
7. Widgets remain presentation/interaction focused and do not implement Rust-owned business semantics.
8. `BuildContext` remains at presentation/composition boundaries.
9. Riverpod is used for shared/feature/application state and providers use code generation.
10. State has one clear owner and is not duplicated independently across router/providers/widgets.
11. Immutable models/controller state follow the Freezed requirement where applicable.
12. Mutable model collections do not leak to consumers.
13. Authored application/feature code preserves strong typing and avoids unnecessary `dynamic`/raw types.
14. Genuine state phases are modeled explicitly rather than through ambiguous nullable-field clusters.
15. Bridge identifier primitives are converted to typed Dart IDs before ordinary feature use.
16. Generated FRB bindings/DTOs do not leak into feature/widgets/controllers/models.
17. Features consume focused client APIs rather than direct bridge infrastructure.
18. Initial loading is distinguished from subsequent background operational state.
19. Loaded usable data is preserved during non-blocking background operations where the feature contract permits it.
20. Stale async completions cannot overwrite newer authoritative state.
21. Frontend errors remain typed and backend technical/transport strings are not used directly as UI copy.
22. Route-owned durable state and Riverpod-owned transient state are not independently duplicated.
23. Generated source is unmodified and generated-source drift checks pass.
24. Completed production source contains no accidental diagnostic/scaffolding artifacts prohibited by this convention.
25. Dart/model/client/controller tests use the narrowest useful deterministic boundary.
26. Ordinary feature tests do not require the real Rust backend when a focused API seam exists.
27. Widget tests favor observable behavior/semantics over private tree structure.
28. Performance work is evidence-driven and does not move Rust-owned heavy processing into widget/UI-isolate code.
29. Canonical Flutter format, analysis, generation-drift, and test verification passes for the supported slice configuration.

## 36. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../architecture/architecture-overview.md)
- [PHASE-000 — Foundation](../phases/phase-000-foundation.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](../specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-RUST-001 — Rust Coding and Test Conventions](conv-rust-001-rust-coding-and-test-conventions.md)
- [Effective Dart](https://dart.dev/effective-dart)
- [Dart — Customizing Static Analysis](https://dart.dev/tools/analysis)
- [Flutter — `pubspec.yaml` / `flutter_lints`](https://docs.flutter.dev/tools/pubspec)
- [Riverpod — About Code Generation](https://riverpod.dev/docs/concepts/about_code_generation)
- [Convention Template](../templates/convention.md)
