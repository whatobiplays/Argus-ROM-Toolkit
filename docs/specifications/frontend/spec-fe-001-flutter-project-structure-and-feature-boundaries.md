# Flutter Project Structure and Feature Boundaries

**Document ID:** SPEC-FE-001  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-09  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-008, CONV-REPO-001, CONV-FLUTTER-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative Flutter project structure and source-dependency boundaries for Argus ROM Toolkit.

It translates the feature-first frontend architecture established by ARCH-001 into concrete ownership rules for `flutter/lib`, application composition, shared frontend infrastructure, feature internals, public feature APIs, generated bridge isolation, test placement, and mechanically verifiable import boundaries.

The structure exists to make architectural ownership visible in both the filesystem and the Dart dependency graph. It is not a folder template for its own sake.

The central invariant is:

> **The Flutter project structure must make ownership visible in both the filesystem and dependency graph: features remain independently understandable, shared code has an explicit semantic owner, application composition flows downward, and transport/generated implementation details remain isolated behind Argus-owned boundaries.**

## 2. Responsibilities

This specification owns frontend rules for:

- the top-level `flutter/lib` source shape;
- ownership of `main.dart`;
- `app`, `core`, and `features` responsibilities;
- feature-first organization inside one Flutter package;
- feature public entry points;
- feature-private implementation boundaries;
- cross-feature dependency direction;
- cross-feature composition ownership;
- admission of code into `core`;
- `core/domain` purity requirements;
- bridge/generated-code containment;
- frontend model ownership and promotion;
- import-boundary conventions;
- bootstrap composition ownership;
- test-source ownership and mirroring;
- architecture-verification requirements;
- initial Phase 000 frontend source footprint;
- criteria for later Dart package extraction.

It defines structural ownership rather than the detailed state-management, API, routing, theme, or design-system behavior owned by later frontend specifications.

## 3. Non-Responsibilities

This specification does not define:

- Riverpod provider-generation syntax or notifier/controller state conventions;
- Freezed model syntax or generator configuration;
- the detailed `ArgusClient` focused API catalog;
- the exact `go_router` route table;
- adaptive shell presentation behavior;
- startup/recovery UI behavior;
- appearance/theme workflow behavior;
- design tokens or accessibility rules;
- generated `flutter_rust_bridge` annotations or code shape;
- native platform runner layout;
- release packaging;
- backend domain or workflow ownership;
- a multi-package Dart workspace for feature packages.

Those concerns are owned by their applicable frontend/backend specifications, conventions, or later architecture decisions.

## 4. Governing Principles

Argus Flutter source follows these principles:

1. The Flutter application is one feature-first Dart package during the current architecture.
2. `app` owns composition, not reusable business capability.
3. `core` owns stable cross-feature primitives and infrastructure, not convenient shared dumping grounds.
4. `features` own user-facing capability internals.
5. Feature internals are private by default.
6. Features expose small purpose-specific public entry points.
7. Cross-feature dependencies are acyclic and uncommon.
8. Cross-feature orchestration belongs in `app` when no feature is the natural owner.
9. `core/domain` remains independent of Flutter, Riverpod, features, and generated bridge code.
10. Generated bridge source remains behind an Argus-owned bridge/client boundary.
11. Models live with their semantic owner rather than in a global model bucket.
12. Directory structure grows with demonstrated responsibility; empty template layers are not created.
13. Tests mirror semantic ownership and use the narrowest useful seam.
14. Enforceable dependency rules are checked mechanically where practical.
15. Feature removal and growth should remain local enough to preserve maintainability.

## 5. Top-Level Flutter Source Shape

The conceptual source structure is:

```text
flutter/
└── lib/
    ├── main.dart
    ├── app/
    │   ├── bootstrap/
    │   ├── routing/
    │   ├── shell/
    │   └── actions/
    ├── core/
    │   ├── bridge/
    │   ├── client/
    │   ├── domain/
    │   ├── events/
    │   ├── errors/
    │   ├── responsive/
    │   └── design_system/
    └── features/
        ├── startup/
        ├── settings/
        ├── diagnostics/
        ├── library/
        ├── game_detail/
        ├── jobs/
        └── sources/
```

This is an ownership map, not an instruction to create every directory on day one.

Directories are created only when an implemented slice has code with that responsibility.

Future features are added under `features/` when their owning slices begin.

## 6. `main.dart`

`main.dart` is a thin process/application entry point.

Its responsibilities are limited to the smallest setup required to enter application bootstrap and run Flutter.

Conceptually:

```text
main
  ↓
bootstrap frontend composition
  ↓
construct root application widget
  ↓
runApp
```

`main.dart` must not become:

- a service locator;
- a provider registry for unrelated features;
- a bridge DTO mapper;
- a business-workflow coordinator;
- a route catalog;
- a settings or startup controller;
- a generic error-handling bucket.

If initialization becomes substantial, the work moves into `app/bootstrap` or the narrower owner rather than expanding `main.dart`.

## 7. `app/` Ownership

`app/` owns frontend composition that exists because independently understandable parts must be assembled into one Argus application.

Allowed responsibilities include:

- root bootstrap composition;
- root Riverpod/container composition;
- top-level routing assembly;
- application-shell composition;
- application lifecycle wiring;
- cross-feature frontend actions;
- root startup/readiness presentation coordination;
- route-to-feature registration;
- application-wide chrome composition.

`app/` does not own backend business rules or a second application-service layer parallel to Rust.

The conceptual dependency direction is:

```text
main
 ↓
app
 ├───────────────┐
 ↓               ↓
feature A      feature B
   \             /
    \           /
        core
```

`features` and `core` must not import upward from `app`.

## 8. `app/bootstrap/`

`app/bootstrap/` owns frontend dependency composition required to create the root application.

It may:

- construct or expose the root Riverpod scope/container;
- construct the bridge/client adapter;
- compose root providers;
- initialize frontend lifecycle/event connections;
- provide the assembled application root to Flutter.

It must not:

- execute feature business workflows;
- contain persistence implementation;
- expose generated bridge DTOs to features;
- interpret feature presentation models;
- become a generic dependency registry.

Detailed Riverpod mechanics are owned by SPEC-FE-002.

## 9. `app/routing/`

`app/routing/` owns composition of the application route graph.

Feature-specific route definitions remain owned by the applicable feature when practical. `app/routing` imports their intentional public route entry points and assembles the global router.

It must not reach into feature-private implementation files merely to construct routes.

Detailed route semantics are owned by SPEC-FE-004.

## 10. `app/shell/`

`app/shell/` owns the persistent application shell and the composition points required to display routed feature content within that shell.

The shell may depend on feature public destinations or public indicators when those are deliberately exported for application composition.

It does not own the internal state of those features.

Detailed adaptive navigation and shell behavior are owned by SPEC-FE-004.

## 11. `app/actions/`

`app/actions/` is reserved for frontend actions whose semantic responsibility is application-level coordination rather than one feature.

Examples include conceptually:

```text
open game
→ establish route scope
→ navigate to game detail
```

or:

```text
startup recovery succeeded
→ refresh root readiness
→ transition to normal shell presentation
```

An app action may coordinate:

- focused frontend APIs;
- navigation;
- presentation side effects;
- cross-feature refresh/invalidation where the owning API contracts permit it.

It must not recreate Rust-owned workflow policy or become a generic command bus.

## 12. `core/` Admission Rule

Code belongs in `core` only when it has a stable cross-feature responsibility and no single feature remains its natural semantic owner.

The admission question is not:

> Is this used more than once?

The admission question is:

> Does this concept have durable cross-feature ownership?

A small amount of duplication is preferable to premature generic abstraction when semantic ownership is still feature-specific.

## 13. `core/domain/`

`core/domain` owns stable frontend-domain primitives that are shared by more than one feature and are not transport- or presentation-specific.

Examples include typed identifiers and other small value concepts such as:

```text
GameId
JobRunId
LibraryRootId
SourceEntryId
PlatformId
Pagination
shared time/value primitives
```

`core/domain` may depend on:

- the Dart SDK;
- narrowly justified pure-Dart packages.

`core/domain` must not depend on:

- Flutter widgets or rendering libraries;
- `BuildContext`;
- Riverpod;
- features;
- `app`;
- generated FRB source;
- bridge DTOs;
- platform runner APIs.

The boundary is intentionally pure enough that it could be extracted into a separate Dart package later without redesigning its semantics. Extraction is not required now.

## 14. `core/client/`

`core/client` owns Argus-owned frontend client abstractions and stable read-model/error contracts exposed toward features.

It may contain:

- the root `ArgusClient` contract;
- focused domain API contracts;
- client-facing immutable read models;
- typed client errors;
- mappers from bridge-owned representations into client-owned representations when the mapper belongs to the focused API boundary.

It may depend on appropriate `core/domain` and `core/errors` concepts.

It must not expose generated FRB types through feature-facing APIs.

Detailed client/API design is owned by SPEC-FE-003.

## 15. `core/bridge/`

`core/bridge` owns the Flutter-side transport boundary to Rust.

It may contain:

```text
core/bridge/
├── generated/
├── mappers/
├── adapters/
└── bridge-specific lifecycle plumbing
```

Exact subdirectories are created only when needed.

Generated FRB code belongs within this boundary or another explicitly bridge-owned generated boundary approved by CONV-REPO-001.

`core/bridge` may depend on:

- generated bridge code;
- client/domain/error models needed for translation;
- bridge lifecycle infrastructure.

Feature code must never import generated bridge code directly.

## 16. `core/errors/`

`core/errors` owns frontend-wide typed error primitives that have genuinely cross-feature meaning.

It does not own backend error taxonomy, which remains governed by SPEC-BE-003 and its bridge/client projections.

Feature-specific presentation/error state remains with the feature unless promoted by a durable shared contract.

## 17. `core/events/`

`core/events` owns frontend event plumbing shared across multiple features, such as common connection, sequencing, or dispatch abstractions when those abstractions are not naturally owned by `core/client`.

It does not become a second backend event bus or a global mutable feature-state container.

Event consumers remain with the semantic owner of the behavior they drive.

## 18. `core/responsive/`

`core/responsive` owns application-wide responsive primitives used consistently across feature presentation.

Examples include size-class concepts and narrowly shared responsive helpers.

Detailed size classes, shell behavior, and adaptive presentation are owned by SPEC-FE-004 and SPEC-FE-007 as applicable.

## 19. `core/design_system/`

`core/design_system` owns reusable Argus presentation primitives and design-system foundations that are genuinely cross-feature.

It may depend on Flutter and appropriate presentation-oriented core primitives.

It must not depend on business features.

Feature-specific widgets do not move into the design system merely because two screens look similar.

Detailed design-system and accessibility requirements are owned by SPEC-FE-007.

## 20. Generic Buckets Are Not Default Architecture

The following directories or modules are generally prohibited as default organizational buckets:

```text
common/
shared/
helpers/
misc/
services/
managers/
utils/
```

A similarly named narrowly scoped module may exist only when it has a precise responsibility that cannot be named more accurately.

Prefer semantic ownership such as:

```text
core/errors/
core/responsive/
core/domain/
features/settings/application/
```

rather than broad technical categories.

## 21. Feature Ownership

Each directory under `features/` owns one user-facing capability area or cohesive frontend capability boundary.

A feature may own:

- feature application/controller state;
- feature-owned immutable models;
- feature presentation;
- feature-specific routes;
- feature actions that do not require cross-feature composition;
- feature-specific test support.

A feature must not own:

- generated transport code;
- backend workflow policy;
- another feature's private implementation;
- application-root composition;
- generic shared infrastructure with no feature-specific semantic owner.

## 22. Feature Internal Shape

A substantial feature may use:

```text
features/library/
├── library.dart
├── application/
├── models/
├── presentation/
├── routing/
└── src/
```

These are conceptual responsibility areas, not mandatory layers.

A smaller feature may remain flatter:

```text
features/diagnostics/
├── diagnostics.dart
├── diagnostics_page.dart
└── diagnostics_controller.dart
```

or may use only the subset of subdirectories justified by current code.

Empty architectural directories must not be created merely to match a template.

## 23. `application/` Inside a Feature

A feature's `application/` area owns frontend feature orchestration and feature state transitions.

Examples include:

- Riverpod controllers/notifiers;
- application-facing state models;
- coordination of focused client API calls for the feature;
- operation-state transitions;
- refresh/invalidation logic owned by the feature.

It must not contain:

- Flutter widget rendering;
- `BuildContext` dependencies;
- generated bridge DTO interpretation;
- persistence implementation;
- Rust-owned domain rules.

Detailed Riverpod/controller rules are owned by SPEC-FE-002.

## 24. `models/` Inside a Feature

A feature's `models/` area owns models whose semantics are specific to that feature.

Examples include:

- feature presentation models;
- feature-local filter/view-state value objects;
- feature-local immutable state components.

It must not duplicate a stable client/read model simply to satisfy superficial layering.

If no separate model type adds semantic value, the feature may use an appropriate client/domain model directly.

## 25. `presentation/` Inside a Feature

A feature's `presentation/` area owns pages, widgets, dialogs, menus, focus/keyboard behavior, and other user-interface composition specific to the feature.

Presentation code may watch feature state and initiate approved actions.

It must not:

- call generated bridge bindings;
- perform persistence;
- implement backend validation rules;
- infer transport semantics;
- trigger backend commands merely because a widget builds.

CONV-FLUTTER-001 remains authoritative for widget and `BuildContext` conventions.

## 26. `routing/` Inside a Feature

A feature's `routing/` area owns route/destination definitions specific to the feature when those definitions are substantial enough to deserve an owner.

Public route contracts intended for app composition are exported through a feature public entry point.

The global route graph remains composed by `app/routing`.

Detailed routing semantics are owned by SPEC-FE-004.

## 27. Feature-Private `src/`

A feature may use `src/` to identify implementation that must not be consumed outside the feature.

For example:

```text
features/library/
├── library.dart
├── library_routes.dart
└── src/
    ├── internal_controller.dart
    ├── private_mapper.dart
    └── internal_widgets/
```

Consumers must not import another feature's `src/` files.

Because sibling directories in one Dart package are not fully isolated by Dart's package-level `src` convention, Argus must supplement convention with deterministic architecture verification where ordinary analyzer rules are insufficient.

## 28. Feature Public Entry Points

Features expose deliberately small, purpose-specific root entry points.

Examples include:

```text
library.dart
library_routes.dart
library_actions.dart
library_models.dart
```

A consumer imports the narrowest public entry point appropriate to its role.

Example:

```dart
import 'package:argus/features/library/library_routes.dart';
```

A feature public entry point may export:

- stable feature-facing models;
- feature destinations/routes intended for composition;
- public actions intended for external invocation;
- widgets explicitly intended as public feature composition surfaces.

It must not export implementation indiscriminately.

## 29. Barrel File Discipline

Public root files are curated API surfaces, not automatic barrels.

Prohibited behavior includes exporting an entire feature tree merely to shorten imports.

Do not expose:

- private controllers;
- implementation-only providers;
- internal widgets;
- test utilities;
- bridge/generated types;
- internal mappers;
- transitive dependencies that consumers should not know about.

A public API that becomes broad enough to obscure ownership should be split into purpose-specific entry points.

## 30. Cross-Feature Dependency Direction

The default feature dependency is:

```text
feature
  ↓
core
```

A direct feature-to-feature dependency is allowed only when all of the following are true:

1. the semantic dependency is real;
2. the consumer uses the producer feature's public entry point;
3. the dependency remains acyclic;
4. moving the concept to `core` would create worse semantic ownership;
5. the dependency is narrow and reviewable.

Cross-feature imports should remain uncommon.

## 31. Prohibited Dependency Directions

The following are prohibited:

```text
core → feature
feature → app
core → app
feature A → feature B → feature A
feature A → feature B/src
feature → generated bridge source
```

Tests do not receive a special exemption from architectural visibility merely for convenience.

Test support should use public/test-specific seams owned by the appropriate boundary.

## 32. Cross-Feature Composition

When two independent features need coordination rather than semantic ownership, `app` owns the composition.

Prefer:

```text
feature A ← app composition → feature B
```

rather than creating direct feature cycles or controller-to-controller dependencies.

Examples of composition concerns include:

- application-level navigation between features;
- shell integration;
- startup transition into the normal application;
- cross-feature actions that have no natural feature owner.

## 33. Shared State Is Not a Reason for Feature Coupling

When multiple features observe the same backend concept, they should normally consume the same focused client API, shared read model, or event contract.

Prefer:

```text
        focused API / event
          ↓         ↓
     feature A   feature B
```

rather than:

```text
feature A controller
        ↓
feature B controller
```

Feature controllers should not become a hidden cross-feature service graph.

## 34. Dependency Injection Does Not Determine Ownership

Riverpod is the approved dependency-injection and state-management mechanism, but provider placement follows semantic ownership.

Conceptually:

```text
core/client/
→ ArgusClient and focused API providers

features/settings/application/
→ settings controller providers

app/bootstrap/
→ root composition/lifecycle providers
```

Argus does not create one global `providers/` directory containing unrelated providers from all subsystems.

SPEC-FE-002 defines exact provider/controller conventions.

## 35. No Global Service Locator

Argus must not use a generic service-locator module as the primary way to access frontend dependencies.

Prohibited broad patterns include conceptually:

```text
service_locator.dart
global_services.dart
dependencies.dart
```

when they expose arbitrary components through generic lookup.

Root composition may wire dependencies, but consumers depend on typed providers or focused interfaces.

## 36. Model Ownership

Argus does not maintain a single application-wide `models/` directory.

Model ownership follows semantics.

Conceptually:

```text
core/domain/
→ stable shared identifiers/value primitives

core/client/<area>/
→ focused API read models

features/settings/models/
→ settings-specific presentation models
```

A model remains with one natural owner until a real cross-feature contract justifies promotion.

## 37. Model Promotion

Use this decision sequence when a concept appears in multiple places:

```text
Who semantically owns this?
        ↓
one feature still owns it?
    yes → keep it there
        ↓ no
stable cross-feature concept?
    yes → promote to core
        ↓ no
composition concern?
    yes → own in app
        ↓ no
reconsider the abstraction
```

Two call sites alone are not sufficient evidence for promotion.

## 38. Bridge DTO to Feature Data Flow

The architectural data flow is:

```text
Bridge DTO
    ↓
core/bridge translation
    ↓
focused client API/read model
    ↓
feature application mapping when needed
    ↓
feature presentation/UI model when needed
```

Bridge DTOs never enter feature code.

Feature models do not leak backward into bridge transport contracts.

SPEC-BE-008 and SPEC-FE-003 own the detailed transport/client contracts.

## 39. Generated Code Placement

Generated files follow CONV-REPO-001 and the generator's native conventions.

For adjacent Dart code generation:

```text
appearance_settings.dart
appearance_settings.freezed.dart
appearance_settings.g.dart
```

Generated `part` files remain adjacent to the authored owner.

For large FRB-generated surfaces:

```text
core/bridge/generated/
```

or another explicitly bridge-owned generated boundary may be used.

Generated source must not become the architectural API merely because Dart visibility technically permits importing it.

## 40. Import Style and Boundary Visibility

Imports should make architectural ownership understandable.

Across meaningful ownership boundaries, package imports are preferred where they make the boundary clearer:

```dart
import 'package:argus/core/domain/domain_ids.dart';
import 'package:argus/features/settings/settings.dart';
```

Inside a cohesive implementation area, normal relative imports are acceptable when clearer.

The project does not require package imports for every local file.

Generated `part` directives follow generator-native syntax and placement.

## 41. Import Enforcement

The strongest practical enforcement mechanism should be used in this order:

```text
Dart language/analyzer/package rules
        ↓
repository architecture/static check
        ↓
focused architecture test
        ↓
review-only rule
```

Argus should not introduce a complex custom analyzer plugin solely to enforce a small set of dependency rules when a deterministic lightweight repository check is sufficient.

## 42. Required Architecture Rules

At minimum, repository verification must detect or prevent:

1. imports from `features/<A>` into `features/<B>/src`;
2. feature imports of generated bridge source;
3. feature imports of `app`;
4. `core` imports of `app`;
5. `core/domain` imports of Flutter;
6. `core/domain` imports of Riverpod;
7. `core/domain` imports of any feature;
8. `core/domain` imports of bridge/generated source;
9. feature dependency cycles;
10. generated bridge types leaking into feature-facing source where mechanically detectable.

These checks become part of the canonical verification surface defined by CONV-TEST-001 and CONV-REPO-001.

## 43. Boundary Violations

A forbidden dependency is an architectural problem, not a lint inconvenience.

When implementation wants a prohibited import, use the following resolution sequence:

```text
consumer needs private implementation
→ expose a narrow public contract if legitimate

multiple features need one stable concept
→ promote the semantic owner to core if justified

features require coordination
→ compose in app

generated DTO appears necessary in feature
→ add bridge/client mapping

dependency cycle appears
→ redesign ownership
```

Do not suppress the architectural rule simply to make an implementation compile.

## 44. Error Flow Ownership

Frontend errors follow the same structural boundaries as successful data.

Conceptually:

```text
bridge failure
   ↓
core/bridge translation
   ↓
core/client typed error
   ↓
feature application state
   ↓
presentation/localized UI
```

Features must not inspect raw FRB exceptions or Rust implementation-specific error representations.

CONV-FLUTTER-001 and SPEC-FE-003 own the detailed frontend error projection conventions.

## 45. Test Structure

Tests mirror source ownership conceptually:

```text
test/
├── app/
├── core/
└── features/
    ├── startup/
    ├── settings/
    └── diagnostics/
```

Additional feature test directories appear when the feature is implemented.

Test paths need not reproduce every source subdirectory mechanically; they should preserve the same semantic owner.

## 46. Feature Test Independence

A healthy feature can be tested without constructing the entire application.

Ordinary feature tests may use:

- focused API fakes;
- Riverpod provider overrides;
- feature model fixtures;
- local router/test composition when routing behavior is under test.

Ordinary feature tests should not require:

- the real Rust backend;
- FRB runtime initialization;
- a native desktop runner;
- unrelated feature startup;
- a full application bootstrap.

## 47. Preferred Test Seams

The preferred test substitution boundary is:

```text
feature
   ↓
focused Argus API
   ↓
fake in test
```

not:

```text
feature
   ↓
generated FRB mock
```

This ensures feature tests prove application behavior without coupling to transport implementation.

## 48. Test Responsibilities by Area

The expected test mapping is:

| Area | Primary test concern |
|---|---|
| `core/domain` | pure value/invariant tests |
| `core/client` | API/read-model/error semantics |
| `core/bridge` | transport mapping and containment |
| feature `application` | controller/provider behavior against focused API fakes |
| feature `presentation` | widget interaction, semantics, adaptive behavior as applicable |
| `app/routing` | route composition and restoration |
| `app/shell` | shell composition and navigation integration |
| `app/bootstrap` | root dependency/lifecycle composition |

CONV-TEST-001 remains authoritative for test pyramid, fixtures, determinism, and canonical verification.

## 49. Feature Removal Property

A healthy feature boundary should make removal mostly local.

Removing a feature should primarily require deleting:

```text
features/<feature>/
```

and updating its intentional composition points such as:

```text
app/routing/
app/shell/
app/actions/
```

plus any shared contract that was deliberately promoted out of the feature.

If removing one feature routinely requires editing unrelated feature internals, the ownership boundary must be reconsidered.

## 50. Feature Growth Property

A feature becoming large does not automatically justify package extraction.

Continue using focused files and responsibility-based subdirectories inside the single Flutter package while the package boundary remains effective.

Size alone is not an architecture decision.

## 51. Future Package Extraction

Extracting a feature or core area into a separate Dart package requires a material reason such as:

- independent reuse;
- stronger separately enforced dependency boundaries;
- independent build/release needs;
- demonstrated compilation/tooling value;
- a stable API mature enough to justify package ownership.

Package extraction is an architecture change and requires updating the applicable architecture/specification documents.

The current architecture does not create one package per feature.

## 52. Phase 000 Initial Source Footprint

Phase 000 is expected to require only the frontend areas necessary for the startup/settings/diagnostics vertical slice.

Conceptually:

```text
flutter/lib/
├── main.dart
├── app/
│   ├── bootstrap/
│   ├── routing/
│   └── shell/
├── core/
│   ├── bridge/
│   ├── client/
│   ├── domain/
│   ├── errors/
│   ├── events/
│   ├── responsive/
│   └── design_system/
└── features/
    ├── startup/
    ├── settings/
    └── diagnostics/
```

Even within this list, an empty directory is omitted until an implementation slice requires code with that ownership.

`library`, `game_detail`, `jobs`, and `sources` should not be scaffolded merely because ARCH-001 names them as future feature areas.

## 53. Phase 000 Bootstrap Boundary

The first Flutter workspace/bootstrap slice must establish enough structure to prove the dependency rules without prematurely implementing later feature contracts.

It should establish only the actual owners needed by the Phase 000 vertical slice.

Architecture verification may be introduced with the initial structure so later slices cannot silently erode the boundary.

## 54. Responsive and Design-System Ownership

`core/responsive` and `core/design_system` are shared frontend presentation infrastructure, but their detailed contracts are intentionally not finalized here.

This specification requires only that:

- their ownership remains cross-feature;
- they do not depend on business features;
- feature-specific presentation stays with the feature;
- their public APIs remain narrow enough for independent testing.

SPEC-FE-004 and SPEC-FE-007 define detailed behavior.

## 55. Routing Ownership

This specification distinguishes route ownership from route composition:

```text
feature routing contract
       ↓
app/routing composition
       ↓
application router
```

A feature may expose a route/destination API without owning the global router.

Routes must not be used as an excuse for `app` to import private feature implementation.

SPEC-FE-004 defines the actual route model and adaptive shell integration.

## 56. State Ownership Boundary

This specification does not prescribe exact provider types, but it fixes the ownership rule:

- feature state is defined with the feature;
- shared client/infrastructure providers live with the shared owner;
- root composition providers live under `app/bootstrap`;
- no global provider bucket replaces semantic ownership.

SPEC-FE-002 defines generated providers, controller state, `AsyncValue`, Freezed, and lifecycle conventions.

## 57. Backend Authority Boundary

Frontend structure must preserve the architecture in which Rust owns authoritative business behavior.

No folder arrangement may justify moving into Flutter:

- persistence rules;
- indexing/planning policy;
- authoritative job state;
- provider behavior;
- domain validation;
- transactional workflow decisions.

Flutter owns presentation, interaction, navigation, and frontend application-state coordination as established by ARCH-001.

## 58. Generated Bridge Boundary

Generated bridge source is implementation infrastructure.

It must remain replaceable without requiring feature-source rewrites beyond the Argus-owned client boundary.

A feature import graph containing FRB-generated source is a structural defect even if the generated API is convenient.

## 59. Public API Stability Inside the Repository

Feature public entry points are architectural boundaries, but they are not independently versioned public SDKs.

Internal refactoring may change a feature public entry point when all repository consumers are updated in the same reviewed change and no higher-level durable contract is violated.

The purpose of the boundary is ownership and dependency control, not artificial internal backward compatibility.

## 60. Cycles

Circular feature dependencies are prohibited.

If feature dependency analysis discovers:

```text
A → B → C → A
```

the change must be redesigned before acceptance.

Typical remedies are:

- move a truly shared primitive to `core`;
- move composition to `app`;
- reverse an incorrectly modeled dependency;
- introduce a narrow neutral contract at the correct owner.

A cycle must not be hidden behind re-export files or generic service locators.

## 61. Architecture Verification Characteristics

Frontend architecture checks must be:

- deterministic;
- offline;
- platform-neutral where possible;
- fast enough for routine `just check` execution;
- based on repository source, not developer-machine state;
- explicit about the violated dependency rule.

A failure should identify the offending importer/imported path or cycle clearly enough to fix without reverse-engineering the checker.

## 62. Architecture Check Implementation Freedom

This specification does not mandate a particular checker implementation.

Acceptable mechanisms include:

- analyzer-supported restrictions;
- a small repository-owned Dart script;
- a small repository-owned language-neutral source graph checker;
- focused architecture tests.

A heavy third-party architecture framework should not be introduced without demonstrated value.

CONV-REPO-001 governs script/tool placement and canonical command integration.

## 63. Source Naming

Dart source naming follows CONV-FLUTTER-001 and Effective Dart.

Structural source files should use responsibility-specific names such as:

```text
settings.dart
settings_routes.dart
appearance_settings_controller.dart
argus_client.dart
runtime_events.dart
```

Avoid filenames such as:

```text
helpers.dart
common.dart
stuff.dart
misc.dart
```

unless the name is genuinely precise in context.

## 64. Generated File Visibility

Generated code may be committed according to CONV-REPO-001, but committed status does not grant it architectural visibility.

The same import boundaries apply regardless of whether a file is handwritten or generated.

Generator-specific `part` relationships are the narrow exception required by the owning source file.

## 65. Documentation Ownership

When implementation requires a durable structural exception, update this specification or the higher-level architecture that owns the rule before or with the implementation.

A task/result note alone does not authorize a new dependency direction.

CONV-DOC-001 governs how implementation discoveries are promoted into durable documentation.

## 66. Security and Privacy

Project structure itself is not a security boundary, but it must not encourage sensitive data leakage across layers.

Feature/public entry points must not expose:

- raw credentials;
- raw provider secrets;
- unrestricted diagnostic payloads;
- unsanitized filesystem detail merely because bridge DTOs contain transport data.

Security/privacy semantics remain governed by the owning backend/client specifications.

## 67. Performance

The feature-first structure must not introduce unnecessary runtime indirection merely to preserve folders.

Boundary abstractions exist for semantic ownership and testability, not for mandatory wrapper layers around every function.

Performance-sensitive UI code may remain locally optimized inside its semantic owner while preserving dependency direction.

Any optimization that bypasses the bridge/client boundary requires architectural review rather than being accepted as a performance shortcut.

## 68. Concurrency and Cancellation

Directory ownership does not change the concurrency contract.

Feature application code may coordinate asynchronous frontend operations through the approved controller/client abstractions, but authoritative backend operation lifecycle and cancellation semantics remain Rust-owned.

The feature must not invent a second authoritative operation state machine to compensate for poor placement.

SPEC-FE-002 and SPEC-FE-003 own the detailed frontend async/controller/client contracts.

## 69. Failure and Recovery Behavior

A structural-boundary failure discovered during development or CI fails verification rather than being tolerated until runtime.

At runtime, transport and application failures flow through the Argus-owned client/error boundary before reaching features.

Startup/recovery routing and presentation are owned by SPEC-FE-005.

## 70. Events and Observability

Shared event plumbing belongs in `core/events` or the focused client boundary as defined by later specifications.

Feature-specific event interpretation remains with the consuming feature.

Observability should preserve ownership in diagnostic labels and logs where useful, but this specification does not define frontend telemetry schemas.

## 71. Accessibility

Accessibility implementation remains presentation-owned and is governed by SPEC-FE-007.

Feature-first organization must not isolate accessibility into one feature or generic helper. Feature presentation remains responsible for correct semantics and interaction, using shared design-system/accessibility primitives where appropriate.

## 72. Localization

If localization infrastructure is introduced, shared localization plumbing may live under an appropriate cross-feature core/application owner.

Feature-specific localized messages remain semantically owned by the feature or centralized generated localization catalog according to the eventual localization convention.

This specification does not create a localization subsystem prematurely.

## 73. Example: Settings Feature

A Phase 000 settings feature may evolve toward:

```text
features/settings/
├── settings.dart
├── application/
│   └── appearance_settings_controller.dart
├── models/
│   └── appearance_settings_view_state.dart
└── presentation/
    ├── settings_page.dart
    └── appearance_selector.dart
```

If the separate `models` area is unnecessary, the model may remain adjacent to the controller or be omitted when a client model is sufficient.

The feature consumes a focused settings API rather than FRB-generated calls.

## 74. Example: Startup Feature

A startup feature may own:

```text
features/startup/
├── startup.dart
├── application/
└── presentation/
```

It consumes root/runtime client state and renders startup/recovery UI according to SPEC-FE-005.

Application transition from startup into the normal routed shell remains an `app` composition concern when it crosses feature boundaries.

## 75. Example: Diagnostics Feature

A diagnostics feature may remain flat initially if its Phase 000 responsibility is small.

It may later introduce application/presentation subareas as behavior grows.

The presence of future complexity is not justification for creating empty architecture today.

## 76. Example: Feature-to-Feature Dependency

Suppose `game_detail` needs a stable identity type already owned by `core/domain`:

```text
game_detail
    ↓
core/domain/GameId
```

Do not import `library/src` merely because the library also uses `GameId`.

If `game_detail` truly needs a library-owned public concept, it may import a narrow library public entry point if the dependency remains acyclic and semantically correct.

## 77. Example: Cross-Feature Coordination

Suppose selecting a game in library causes navigation to game detail.

Preferred ownership:

```text
library user action
      ↓
public destination/action contract
      ↓
app routing/action composition
      ↓
game detail route
```

Avoid wiring the library controller directly to a game-detail controller.

## 78. Example: Rejected Core Promotion

Two features each contain a small date-formatting presentation helper.

That alone does not justify:

```text
core/utils/date_helpers.dart
```

First determine whether the formatting rule is a stable application-wide presentation contract. If not, keep the logic with its feature until a real shared owner exists.

## 79. Example: Generated Bridge Containment

Compliant:

```text
feature
  ↓
focused client API
  ↓
core/bridge adapter
  ↓
generated FRB
```

Non-compliant:

```text
feature
  ↓
generated FRB method
```

The latter bypasses transport translation, typed frontend models, test seams, and architectural ownership.

## 80. Prohibited Patterns

The following patterns are prohibited unless an approved architecture revision explicitly replaces this contract:

- layer-first global source organization as the primary project model;
- one global `models/` directory for unrelated features;
- one global `providers/` directory for unrelated providers;
- generic service-locator access to application dependencies;
- cross-feature imports into `src/`;
- circular feature dependencies;
- feature imports from `app`;
- `core` imports from `app`;
- generated FRB imports in features;
- bridge DTOs entering feature code;
- Flutter/Riverpod dependencies in `core/domain`;
- empty feature-layer scaffolding created only to satisfy a template;
- one Dart package per feature without an approved extraction decision;
- generic `common`/`helpers`/`misc` buckets used as default ownership;
- giant public barrel files exposing feature internals;
- tests reaching through private boundaries because public seams are inconvenient.

## 81. Testing Requirements

Implementation of this specification must include deterministic evidence appropriate to the implemented slice.

Required architecture evidence grows with the source tree and must include the rules in Section 42 once the relevant boundaries exist.

Feature tests must demonstrate that ordinary feature logic can run against focused API fakes without the real Rust backend.

Bridge containment tests/checks must demonstrate that generated transport source does not leak into feature code.

`core/domain` tests/checks must demonstrate framework/transport independence.

## 82. Architecture Verification Requirements

The canonical repository verification must eventually include a focused frontend architecture check invoked by `just check` or a canonical subcommand used by it.

The check must fail on at least:

- sibling-feature private imports;
- feature-to-app imports;
- core-to-app imports;
- forbidden `core/domain` dependencies;
- feature dependency cycles;
- generated bridge imports from feature source.

The exact command name and script implementation are owned by implementation slices and CONV-REPO-001, provided the canonical verification contract remains clear.

## 83. Phase 000 Acceptance Properties

For the Phase 000 frontend foundation, the implementation must demonstrate:

1. Flutter remains one application package.
2. `main.dart` is a thin entry point.
3. implemented source has clear `app`, `core`, and `features` ownership.
4. only directories required by implemented capabilities are created.
5. startup, settings, and diagnostics remain separate feature owners where implemented.
6. root composition remains in `app`.
7. generated bridge source remains isolated behind the bridge/client boundary.
8. feature code consumes Argus-owned client abstractions.
9. feature/private import boundaries are mechanically checked where applicable.
10. ordinary feature tests do not require the real backend.

## 84. General Acceptance Criteria

An implementation conforming to this specification satisfies all of the following:

1. Flutter uses a feature-first single-package organization.
2. `app`, `core`, and `features` have distinct responsibilities.
3. `main.dart` remains thin.
4. Features expose narrow purpose-specific public entry points.
5. Feature-private `src` implementation is not consumed by sibling features.
6. Feature dependency cycles are prohibited and mechanically detected.
7. Cross-feature orchestration is composed in `app` when appropriate.
8. Stable cross-feature concepts are deliberately promoted to `core` rather than copied or globally dumped.
9. `core/domain` remains Flutter-, Riverpod-, feature-, and generated-bridge-free.
10. Generated FRB source remains inside the bridge boundary.
11. Feature code consumes focused Argus APIs rather than generated bindings.
12. Models remain with their semantic owner.
13. Source/test organization mirrors semantic ownership.
14. Generic dumping-ground directories are avoided.
15. Architecture verification checks the enforceable dependency rules.
16. Ordinary feature tests can execute without the real Rust backend.
17. Feature growth does not automatically trigger package extraction.
18. Durable exceptions update the governing documentation rather than silently weakening the boundary.

## 85. Out of Scope

This specification intentionally leaves the following to later frontend specifications:

- generated Riverpod provider conventions;
- `AsyncValue<State>` controller lifecycle semantics;
- Freezed model conventions beyond ownership;
- focused `ArgusClient` API signatures;
- route paths and redirect behavior;
- adaptive navigation breakpoints;
- startup/recovery screen state machines;
- appearance theme mapping and rollback behavior;
- design-system tokens/components;
- accessibility baselines and keyboard/focus specifics.

It also does not define post-MVP multi-package extraction or plugin architecture.

## 86. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](spec-fe-004-routing-and-adaptive-application-shell.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [CONV-DOC-001 — Documentation and Codex Result Conventions](../../conventions/conv-doc-001-documentation-and-codex-result-conventions.md)
- [Frontend Specifications Index](README.md)
- [Subsystem Specification Template](../../templates/subsystem-specification.md)
