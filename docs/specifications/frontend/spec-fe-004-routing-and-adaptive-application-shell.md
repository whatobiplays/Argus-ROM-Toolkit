# Routing and Adaptive Application Shell

**Document ID:** SPEC-FE-004  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-09-03  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-001, PHASE-002, PHASE-003, SPEC-BE-004, SPEC-BE-007, SPEC-BE-015, SPEC-FE-001, SPEC-FE-002, SPEC-FE-003, SPEC-X-001, SPEC-X-002, CONV-REPO-001, CONV-FLUTTER-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the Flutter routing and persistent adaptive application-shell contract for Argus ROM Toolkit.

It translates the architectural decisions for `go_router`, durable route identity, feature-first ownership, startup gating, stateful shell navigation, responsive application structure, route restoration, and cross-feature shell presentation into one implementation-ready frontend contract.

The specification exists so routing remains reconstructible and semantic rather than becoming a second mutable state system, and so compact, medium, expanded, and large presentations share one navigation model rather than drifting into independent applications.

The central invariant is:

> **Argus routing is reconstructible and state-safe: durable location lives in typed routes, transient behavior lives outside the router, startup gating preserves rather than destroys navigation intent, branch histories remain independent, and every restored or externally supplied location re-enters the same typed validation and authoritative feature-loading flow as ordinary navigation.**

## 2. Responsibilities

This specification owns frontend rules for:

- `go_router` usage and typed-route expectations;
- application route composition;
- generated route-source policy;
- semantic destination identity;
- stateful shell branches;
- compact, medium, expanded, and large navigation structure;
- compact direct-destination behavior;
- route-to-destination association;
- route path, path-parameter, and query-parameter ownership;
- route canonicalization;
- presentation-readiness gating;
- preservation and revalidation of intended routes;
- redirect purity and convergence;
- branch switching and reselection behavior;
- back-navigation semantics;
- direct-detail fallback behavior;
- route restoration boundaries;
- unknown and malformed route handling;
- distinction between route parsing failure and feature/application failure;
- global shell chrome ownership;
- application-level backend/status presentation;
- active-job summary placement;
- restart-required banner placement;
- transient application-notice hosting;
- adaptive shell behavior across global size classes;
- routing and shell verification expectations.

## 3. Non-Responsibilities

This specification does not define:

- the Flutter filesystem/module boundaries owned by SPEC-FE-001;
- Riverpod controller/state conventions owned by SPEC-FE-002;
- client APIs, transport mapping, runtime-event mapping, or failure translation owned by SPEC-FE-003;
- backend runtime or startup semantics owned by SPEC-BE-004 and SPEC-BE-007;
- startup/recovery screen content and recovery-action presentation owned by SPEC-FE-005;
- appearance settings and theme application owned by SPEC-FE-006;
- exact responsive thresholds, design tokens, navigation styling, typography, focus visuals, or accessibility baselines owned by SPEC-FE-007;
- library browsing behavior beyond generic routing rules;
- exact future feature route catalogs before those features exist;
- operating-system window chrome, title-bar integration, or window-manager behavior;
- a custom navigation framework in parallel with `go_router`.

## 4. Governing Principles

Routing and shell behavior follow these rules:

1. `go_router` is the sole application routing framework.
2. Authored application navigation uses typed route contracts rather than scattered raw path construction.
3. Routes represent durable location and scope.
4. Riverpod and widget state own transient interaction state.
5. One ready-application shell persists across normal application destinations.
6. Major semantic destinations own independent branch histories where stateful shell behavior is useful.
7. Compact, medium, expanded, and large presentations share one route graph and one destination model.
8. Layout changes alter presentation rather than route identity.
9. Startup and recovery surfaces sit outside the normal ready shell.
10. Startup gating preserves the intended ready-state route rather than destroying it.
11. Redirect policy is deterministic, convergent, and side-effect free.
12. Restored and externally supplied locations use the same typed parsing and validation as ordinary navigation.
13. Route identity never carries authoritative backend object graphs.
14. Feature data loading occurs after route activation through normal focused-API/controller ownership.
15. The shell owns cross-feature presentation surfaces, not feature business behavior.
16. Shell-selected destination is derived from routing state rather than independently mutable.
17. Global feedback surfaces never become the sole owner of durable failure or restart state.
18. Phase 000 proves the architecture without fabricating future features.

## 5. Architectural Position

The routing layer belongs to application composition:

```text
app/bootstrap
    ↓ constructs root client/providers
features/startup ── AppReadiness ──┐
features/settings ─ Appearance ────┤
                                  ↓
                    app presentation readiness
                                  ↓
app/routing
    ↓
ready-state shell / pre-shell surfaces
    ↓
feature route
    ↓
feature controller
    ↓
focused API
```

Routing must not invert this dependency direction.

In particular:

```text
feature controller → router internals
```

is prohibited as ordinary behavior.

## 6. Framework Choice

Argus uses `go_router`.

No parallel routing abstraction may own application location, branch history, deep-link parsing, or ready-state route gating.

Thin Argus-owned helpers and typed route data are permitted where they make semantic ownership explicit without duplicating router state.

## 7. Typed Route Model

Application route definitions use the supported `go_router` typed-route generation model available in the pinned implementation version.

Conceptually:

```text
GameRoute(gameId)
LibraryPlatformRoute(platformId)
SettingsRoute()
DiagnosticsRoute()
```

Ordinary authored code should not assemble route strings such as:

```text
"/games/$gameId"
```

when a typed route contract exists.

Exact annotations, generated superclass names, builder APIs, and version-specific syntax remain implementation decisions.

## 8. Generated Routing Source

Typed-route generated source follows CONV-REPO-001.

Required behavior:

```text
authored route source
    ↓
route generation
    ↓
committed deterministic generated source
    ↓
just check-generated
```

Generated route files are never hand-edited.

Generated-source drift participates in the same canonical verification model as Riverpod, Freezed, bridge bindings, and other deterministic source generation.

## 9. Route Ownership

`app/routing` owns the complete application route graph and cross-feature composition.

Features may expose purpose-specific route definitions, route data, or route builders through their approved public surface.

Conceptually:

```text
features/settings public route surface
features/diagnostics public route surface
features/library public route surface
        ↓
app/routing
        ↓
application route tree
```

A feature does not construct or own the root application router.

## 10. Route Composition Must Remain Small

The root router should compose feature-owned route definitions rather than accumulating every route-specific widget and parser in one application file.

The composition layer owns:

- route-tree topology;
- shell branch placement;
- root-versus-shell navigator placement;
- presentation-readiness gating;
- cross-feature destination metadata;
- application-level not-found behavior.

Feature-specific screen construction remains feature-owned.

## 11. Semantic Route Identity

A route identifies durable location or scope.

Representative durable identities include the active Phase 001 canonical routes:

```text
/sources
/sources/roots/:rootId
/jobs
/jobs/:jobRunId
/settings
```

`/diagnostics` remains a reserved route identity and is not an active Phase 001 destination. A later slice may activate it only together with real Diagnostics destination capability; no production route graph contains it in Phase 001.

Future phases may add representative identities such as:

```text
/library
/library/collections/:collectionId
/library/platforms/:platformId
/library/library-roots/:libraryRootId
/games/:gameId
```

Later feature specifications may add routes, but they must preserve the same ownership principles.

## 12. Route Paths Are Application Contracts

Once a route is released and can be restored, bookmarked, linked, or referenced by tests, its semantic meaning is durable application behavior.

Renaming implementation classes does not require changing route paths.

Changing a published route to mean something unrelated is prohibited without an explicit compatibility decision.

## 13. Typed Identifier Parsing

Path parameters representing Argus identifiers are converted at the routing boundary into typed Dart identifiers.

Conceptually:

```text
"abc123"
    ↓ route parser
GameId
    ↓
feature/controller identity
```

Raw serialization-friendly identifier strings must not leak into ordinary feature state merely because the router received a string URI.

## 14. Invalid Identifier Parsing

Malformed path parameters produce a controlled route-level failure.

The router must not:

- substitute an empty/default ID;
- pass an invalid raw string to the feature;
- assert or crash;
- silently redirect to an unrelated screen.

Route parsing and feature loading remain separate phases.

## 15. Valid Identifier but Missing Entity

A syntactically valid identifier whose backend entity does not exist is not a route parsing failure.

Conceptually:

```text
/games/<valid-game-id>
    ↓
GameId parsed successfully
    ↓
GamesApi read
    ↓
application not-found failure
```

That outcome belongs to the routed feature's application/presentation state.

The router must not conflate it with malformed URI syntax.

## 16. Query Parameters

Query parameters represent intentionally addressable browsing configuration whose route identity should survive navigation, restoration, or a copied URI.

Representative later examples include:

- sort mode;
- filter selection;
- view mode;
- search query;
- other small serializable browse configuration.

Exact query contracts belong to the owning feature specification.

## 17. Query-State Ownership

Where a query parameter is authoritative for an addressable setting, Riverpod/controller state derives from that route state rather than maintaining an independently writable duplicate.

Prohibited shape:

```text
route query sort=title
+
controller.sort independently mutable
```

unless one value is explicitly derived from the other with one clear authority.

## 18. Non-Route Interaction State

Do not put ordinary transient UI mechanics into URLs.

Examples that normally remain outside routing include:

- hover;
- focus;
- animation progress;
- open menus;
- drag state;
- pending commands;
- save progress;
- local validation display state;
- short-lived selection gestures.

Addressability, restoration value, and semantic scope determine route ownership, not the mere fact that a value exists.

## 19. Canonical Query Values

Default query values should be omitted from generated canonical locations when omission has identical semantics.

Prefer:

```text
/library
```

over:

```text
/library?view=grid&sort=default&page=1
```

when those explicit values add no semantic distinction.

## 20. Query Parsing

Feature-owned route query parsing must be typed and deterministic.

Known invalid parameter values use a defined feature routing policy:

- reject as route-invalid when the value is required to interpret location safely; or
- fall back to the documented default when the parameter is optional and invalid input is safely recoverable.

The choice must be explicit for each parameter contract.

## 21. Unknown Compatible Query Parameters

Unknown query parameters may be ignored when the route contract defines them as additive/non-semantic for the current version.

Known parameters must never be silently reinterpreted to new meanings.

## 22. URI-Reconstructible Routing

Normal durable application routes must be reconstructible from their URI.

Path and query parameters are preferred over in-memory-only route extras for durable identity.

The canonical route must not require a live Dart object from a previous process.

## 23. Route Extras

Router extras may be used only for genuinely transient navigation assistance that is not required to reconstruct the target location.

They must not be the canonical carrier for:

- entity identity;
- authoritative backend snapshots;
- feature controller state;
- required route configuration.

A route must remain valid when reconstructed without its previous in-memory extras.

## 24. No Backend Object Graphs in Routes

Correct:

```text
GameRoute(GameId)
    ↓
Game controller
    ↓
GamesApi.getGame(GameId)
```

Incorrect as canonical routing:

```text
GameRoute(GameReadModel)
```

Routes identify scope; focused APIs and controllers retrieve current authoritative state.

## 25. Application Destinations

The shell uses one semantic destination catalog for cross-feature navigation.

The Phase 003 active semantic destinations are:

```text
AppDestination.library
AppDestination.sources
AppDestination.jobs
AppDestination.settings
```

`AppDestination.collections` and `AppDestination.diagnostics` remain reserved and inactive. Product onboarding is a root-level gating surface, not an `AppDestination` or shell branch.

Only destinations implemented by the active product scope exist in the production catalog.

## 26. Destination Metadata

A destination descriptor may include routing/presentation-safe metadata such as:

- stable destination identity;
- owning root route or branch;
- navigation role/frequency grouping;
- availability in the current slice;
- presentation label/icon identity when appropriate.

It must not become a backend capability registry or feature business-state container.

## 27. Route-to-Destination Mapping

Every shell-contained route resolves to its owning semantic destination.

Examples:

```text
/sources                   → Sources
/sources/roots/:rootId     → Sources
/jobs                      → Jobs
/jobs/:jobRunId            → Jobs
/settings                  → Settings
/diagnostics               → Diagnostics (reserved; active only when a slice implements the destination)
```

Phase 003 maps `/library/**` and `/games/:gameId` to Library. `/onboarding/library` is outside the shell and therefore maps to no `AppDestination`.

This mapping is centralized.

Scattered string-prefix checks in navigation widgets are prohibited.

## 28. One Ready Application Shell

Once app presentation readiness permits normal application use, Argus renders one persistent ready-state application shell around normal destinations.

Conceptually:

```text
ApplicationShell
├── adaptive primary navigation
├── global toolbar/chrome
├── global status surfaces
├── transient notice host
└── routed destination content
```

## 29. Stateful Branch Model

Major semantic destinations use stateful shell branches where preserving an independent navigation stack is useful.

Conceptually:

```text
Stateful ready shell
├── Library branch
├── Sources branch
├── Jobs branch
└── Settings branch
```

The historical Phase 000 branch set contained only its implemented destinations, and Phase 001 added Sources and Jobs. Phase 003 activates the Library branch alongside Sources, Jobs, and Settings. Diagnostics and Collections remain reserved/inactive and therefore have no production branch.

## 30. Branch History

Each stateful branch retains its own navigation history while inactive.

Example:

```text
Library: /library/platforms/snes
    ↓ switch
Jobs: /jobs
    ↓ switch back
Library: /library/platforms/snes
```

Switching destinations must not flatten branch history.

## 31. Primary Destination Switching

Selecting an inactive primary destination activates its branch.

This is branch activation, not a push onto the current branch.

Prohibited conceptual behavior:

```text
Library navigator
    ↓ push
Jobs page
```

## 32. Active Destination Reselection

Reselecting the currently active primary destination returns that branch to its canonical root.

Example:

```text
Library active at /games/abc
    ↓ select Library again
/library
```

This behavior is intentionally different from switching to an inactive branch, which restores that branch's prior location.

## 33. Compact Direct Destinations

Compact layouts use direct bottom navigation for the currently active primary destination catalog. Compact presentation must not create a semantic `/more` route tree or force implemented primary destinations behind a generic overflow solely because the window is narrow.

For the Phase 002 active product, the direct Compact destinations are:

```text
Sources
Jobs
Settings
```

Each item navigates to the same canonical route/branch used by Medium and Expanded/Large presentation.

## 34. Compact Navigation State

Compact navigation owns presentation selection only. Durable location remains route-authoritative and stateful branch history is shared with every other size class.

No temporary compact-only menu state becomes a persistent shell branch.

## 35. Destination Visibility

Presentation may expose destinations differently by size class without changing route identity.

For the Phase 002 active destination set:

| Destination | Compact | Medium | Expanded/Large |
|---|---|---|---|
| Sources | direct bottom item | rail item | sidebar item |
| Jobs | direct bottom item with active-job badge where applicable | rail item | sidebar item |
| Settings | direct bottom item | rail/secondary area | sidebar/secondary area |

Exact later visual grouping belongs to the implemented destination catalog and SPEC-FE-007 styling rules. Adding future destinations may revise the compact presentation through this specification, but must not change canonical routes or introduce OS-specific route graphs.

## 36. Phase 000 Destination Availability

Phase 000 must not create fake future feature implementations solely to populate navigation.

The shell shows genuine implemented destinations.

A placeholder destination is permitted only when PHASE-000 explicitly requires it to prove shell routing/layout and it is clearly non-authoritative and temporary.

## 37. Root Navigator and Shell Navigators

The application uses intentional navigator placement.

Normal ready-state feature routes live inside the shell/branch navigation model.

Startup/recovery surfaces and required product-onboarding surfaces live outside the ready shell.

Exceptional route-worthy application-level modal surfaces may use the root navigator when they genuinely must appear above the shell.

Root-navigator usage must remain uncommon and explicit.

## 38. Startup, Product-Onboarding, and Recovery Placement

Mandatory startup/startup-failure recovery and incomplete required product onboarding render outside the normal ready application shell.

Conceptually:

```text
application root
├── startup/recovery surface
├── product-onboarding surface
└── ready application shell
```

A failed mandatory startup or incomplete onboarding gate must not reveal a bypassable partially usable normal shell underneath.

## 39. Readiness Authority

The router reacts to one narrow app-owned presentation-readiness projection.

It does not derive backend readiness, appearance authority, product-onboarding completion, or shell eligibility from the URI and does not call focused APIs or FRB/native infrastructure.

Conceptually:

```text
startup AppReadiness
+
appearance initialization/authority
+
query-authoritative LibraryOnboardingState
    ↓
app presentation-readiness projection
    ↓
routing policy
```

SPEC-FE-005 owns backend readiness. SPEC-FE-006 owns the initial authoritative appearance prerequisite. SPEC-FE-010 consumes the backend/client-owned Library onboarding projection and exposes only routing-safe completion state to the pure combined readiness derivation.

For Phase 003, authoritative onboarding state is hydrated/reconciled outside redirect evaluation into this routing-safe projection. Runtime/client generation replacement invalidates the old projection and requires re-hydration against the new authority. An authoritative completion result may update the projection immediately after commit; the router does not issue a confirming focused API call from `redirect`.

## 40. Redirect Purity

Redirect/gating logic is pure routing policy.

It may inspect routing-safe readiness state and requested location.

Redirect evaluation is synchronous with respect to routing policy. It must not await backend work or return a decision whose completion depends on a focused API/FRB/native request.

It must not:

- call focused APIs;
- start or retry the backend;
- mutate feature controllers;
- persist state;
- show dialogs/notices;
- perform arbitrary side-effect workflows.

## 41. Redirect Convergence

For every recognized readiness state and requested location, redirect policy must converge to a stable result.

Redirect cycles are defects.

Representative prohibited cycle:

```text
/startup → /
/ → /startup
```

under the same readiness state.

## 42. Intended Ready-State Location

If an application route is requested before startup or required product onboarding completes, Argus preserves that intended ready-state location.

Example:

```text
requested /settings
    ↓ Starting
startup surface
    ↓ Ready
/settings
```

Startup gating must not permanently replace the user's intended route merely because initialization took time.

## 43. Pending Route Intent

Pending ready-state route intent is frontend routing/application state.

It is not backend state and is not stored in `RuntimeState`.

The implementation may use router-supported redirect behavior or an app-owned routing projection as long as there is only one semantic source of intended location.

## 44. Startup Failure and Route Intent

When startup reaches `StartupFailed`, the intended ready-state route is retained while the recovery surface is shown.

If recovery succeeds into a fresh ready runtime, the intended route is revalidated before activation.

It is never blindly replayed against changed application capability or malformed stale state.

## 45. Revalidation After Recovery

After successful startup retry/runtime replacement:

```text
new ready runtime
    ↓
re-evaluate intended route
```

If the route remains implemented and syntactically valid, activate it.

If it is no longer valid/available, navigate to the canonical ready default.

SPEC-FE-005 owns the recovery interaction; this specification owns routing intent preservation and revalidation.

## 46. Startup/Recovery History

Readiness-driven startup, product-onboarding, and recovery surfaces do not become ordinary ready-shell history entries.

After the application reaches the ready shell, Back must not walk through internal startup/onboarding/recovery gating history.

## 47. Canonical Ready Default

Once ready, `/` resolves deterministically to the canonical implemented default destination.

Phase 003 resolves `/` to `/onboarding/library` while required product onboarding is incomplete and to `/library` after it is complete. A valid preserved deep-link intent takes precedence after all gates are satisfied.

Earlier phases may use their first genuine implemented destination; no phase creates a fake Library feature merely to preserve a future default.

## 48. Navigation During Startup

The normal ready shell cannot be entered merely because a route exists.

A direct request to `/settings`, `/library`, `/games/:gameId`, or another ready-state route remains gated until backend readiness, initial appearance authority, and required Library onboarding are satisfied. `/onboarding/library` itself remains gated behind platform/backend/appearance readiness and cannot bypass them.

## 49. Navigation After Ready-State Degradation

A later transport/runtime degradation after the application has previously been ready is distinct from initial mandatory startup failure.

Where the owning runtime/client contract permits continued UI use, the current shell and route may remain visible while app-level status indicates synchronization uncertainty.

This specification does not define the exact degraded-state UX; it preserves the distinction between initial gating and later shell status.

## 50. Back Within a Branch

Back navigation first pops genuine history in the active branch.

Example:

```text
/library
→ /library/platforms/snes
→ /games/abc
```

Back:

```text
/games/abc
→ /library/platforms/snes
→ /library
```

when that history exists.

## 51. No Cross-Branch Back Stack

Primary destination switching does not create a cross-branch page history.

If the user switches from Library to Jobs, Back inside Jobs does not ordinarily mean "return to Library's previous route."

Each branch owns its own stack.

## 52. Direct Detail Fallback

A directly reconstructed detail route may have no previous in-memory history.

When a detail route cannot pop, it falls back to its defined semantic parent/root.

Representative rule:

```text
direct /games/:gameId
    ↓ back with no prior branch entry
/library
```

A genuine previous route takes precedence when one exists.

## 53. Semantic Parent

Each addressable detail route that needs fallback behavior defines its semantic parent/root in routing-owned metadata or route composition.

Fallback must not be inferred from arbitrary string truncation.

## 54. Root Back Behavior

When the active branch is at its root and nothing can be popped, the routing layer does not invent history.

Outer platform/window behavior may then handle Back/close according to platform conventions and later product requirements.

## 55. Game Detail Adaptation

A game remains route-addressable at one canonical identity regardless of width.

Conceptually:

```text
/games/:gameId
```

may render as:

- a full routed detail page on compact layouts;
- a full detail view by default on medium layouts;
- an inspector/detail pane associated with library browsing on expanded/large layouts.

The route identity does not change with presentation.

## 56. No Duplicate Wide-Layout Selection Route

Do not represent the same durable game selection as:

```text
/games/:gameId
```

on compact and:

```text
/library?selectedGame=:gameId
```

on expanded layouts.

One route identity drives both presentations.

## 57. Window Size Classes

The shell consumes the global responsive classification defined architecturally as:

```text
Compact
Medium
Expanded
Large
```

Exact logical-pixel thresholds are owned by SPEC-FE-007 and centralized implementation constants/tokens.

## 58. Global Size Class Ownership

Application structure uses the current global window size class.

Shell code must not scatter independent breakpoint numbers through bottom-nav, rail, sidebar, toolbar, or routed-content widgets.

## 59. Compact Shell

Compact presentation uses direct bottom navigation for the active primary destination catalog. During Phase 002, Sources, Jobs, and Settings are directly reachable.

The shell content remains routed and route-authoritative. Compact behavior is width-driven and shared across supported platforms; it is not an Android-only shell.

## 60. Medium Shell

Medium presentation uses an icon-oriented navigation rail or equivalent architecture-approved rail presentation.

The route graph and destination identities are unchanged from compact.

## 61. Expanded/Large Shell

Expanded and Large presentations use a full sidebar with icons and labels.

They may differ in spacing, width, pane capacity, or richer layout opportunities, but they do not become separate applications or route graphs.

## 62. One Shell Implementation

Avoid independent application implementations such as:

```text
PhoneApp
TabletApp
DesktopApp
```

with separate routing/chrome behavior.

Prefer one `ApplicationShell` with adaptive structural presentation.

## 63. Size-Class Changes Preserve Location

Changing size class must preserve:

- current route URI;
- typed route identity;
- active semantic destination;
- branch histories;
- path/query parameters.

Window resizing is not navigation.

## 64. Local Layout Constraints

Global size class determines application structure only.

Feature components and nested panes still adapt to their own local constraints using normal Flutter layout mechanisms.

A large application window may contain a narrow child pane that needs compact local arrangement.

## 65. No `isDesktop` Propagation

The shell must not propagate global hardware-category booleans such as:

```text
isMobile
isTablet
isDesktop
```

through the feature tree as layout authority.

Argus adapts from available constraints, not hardware labels.

## 66. Routed Content Ownership

The shell supplies the routed content region.

The routed feature owns its internal presentation and actions.

The shell must not implement feature-specific controller behavior based on route name.

## 67. Global Toolbar

The shell owns genuinely application-level toolbar/chrome concerns.

Examples may include:

- application-level navigation affordances;
- global backend/connectivity status;
- active-job summary;
- other proven cross-feature application actions.

Feature-specific sorting, editing, filtering, settings controls, or domain commands remain feature-owned.

## 68. No Route-to-Toolbar Command Bus

Do not create a generic protocol where every route registers arbitrary callbacks into the global toolbar.

If a later design proves a narrow cross-feature toolbar contract is necessary, it must define typed semantics and ownership explicitly.

## 69. Backend/Runtime Status

The ready shell may show app-level runtime/connectivity status because it affects the application globally.

The status comes from an app-owned projection of SPEC-FE-003 client/runtime state.

The shell never calls FRB or interprets bridge DTOs directly.

## 70. Active-Job Indicator

The shell owns the presentation location for the architecture-required active-job indicator.

It consumes an app-level/focused job-summary projection when the Jobs capability is implemented.

It must not depend on a private Jobs feature controller.

Phase 000 does not fabricate Jobs state solely to populate this surface.

## 71. Restart-Required Banner

The shell owns the persistent presentation location for application-level restart-required state.

The shell does not infer restart need from arbitrary form changes.

The owning backend/feature contract establishes restart-required state; the shell renders the app-level projection.

## 72. Transient Application Notice Host

The shell owns a host for application-level transient notices such as toast/snackbar-style feedback.

This host is a presentation surface, not an application event bus.

## 73. `AppNotice` Contract

A narrow app-level notice concept may contain presentation-safe information such as:

- notice kind/severity;
- message key or already presentation-owned message content according to the localization contract;
- optional typed action identity when a global notice action is justified;
- bounded presentation metadata.

It must not contain:

- arbitrary object payloads;
- executable callbacks;
- `BuildContext`;
- navigation closures;
- bridge DTOs;
- backend event objects.

## 74. Notice Ephemerality

A transient notice never becomes the sole representation of durable application state.

Examples:

- a save failure may produce a notice, but the controller still owns failed operation state;
- restart-required may generate a notice, but persistent restart-required state still owns the banner;
- synchronization uncertainty may produce feedback, but app-level status remains authoritative.

## 75. Feature-Local Feedback

Feature-local feedback stays inside the feature when global shell presentation provides no semantic value.

The presence of a global notice host does not require every success/failure to become a global toast.

## 76. No General Effect Bus

SPEC-FE-004 does not introduce a general-purpose global effect bus.

Cross-feature presentation mechanisms must remain narrow and typed.

## 77. Shell Overlays

Global shell overlays may host proven cross-feature surfaces such as transient notices and application banners.

They must not absorb feature forms, drafts, filters, selected entities, or recovery business logic.

## 78. Dialog Routing

A dialog/modal becomes a route only when it represents a durable location that benefits from reconstruction, Back semantics, or deep linking.

Ordinary confirmations, menus, popovers, and transient dialogs remain presentation state.

## 79. Route-Worthy Modal Surfaces

If an exceptional application-level modal is route-worthy, its root-navigator placement is explicit and tested.

Features must not use root navigator routing as a general escape hatch.

## 80. Route Restoration Scope

Navigation restoration may reconstruct durable location information such as:

- current route;
- path parameters;
- query parameters;
- active branch;
- branch stacks where supported by the approved router/restoration model.

It does not imply restoration of arbitrary feature memory.

## 81. What Restoration Does Not Restore

Route restoration alone does not restore:

- pending backend commands;
- in-flight controller futures;
- stale backend snapshots;
- unsaved transient drafts unless separately specified;
- open menus/popovers;
- hover/focus mechanics;
- arbitrary controller object graphs.

## 82. Restoration Reloads Current State

After process restart:

```text
restored route identity
    ↓
startup gating
    ↓
fresh feature controller
    ↓
focused API read
    ↓
current authoritative state
```

The route does not carry a stale pre-restart backend snapshot as authority.

## 83. Restoration Never Bypasses Startup

A persisted route such as `/settings` remains an intended ready-state location while mandatory startup runs.

It cannot reconstruct ready feature state before startup permits normal application use.

## 84. Restored Parameter Validation

Restored path/query parameters pass through exactly the same typed parsing and validation as newly entered locations.

There is no privileged trusted path for restoration data.

## 85. External Location Validation

Future external/deep-link locations follow the same rule as restoration:

```text
external URI
    ↓
typed route parsing
    ↓
startup gating
    ↓
feature loading
```

No external route bypasses client/readiness architecture.

## 86. Route Activation Before Data Load

Once a route is syntactically valid and application readiness permits it, navigation normally activates before feature data is loaded.

Feature loading belongs to the route's controller/presentation state.

The router must not generally block on backend feature queries.

## 87. Feature Readiness

A feature may render its own loading/error/ready state after route activation according to SPEC-FE-002.

The router is not a substitute for feature controller readiness.

## 88. Route Identity Changes and Controller Identity

Changing an identity-bearing route parameter changes the corresponding parameterized provider/controller identity.

Example:

```text
/games/A
→ /games/B
```

must not allow stale async completion from A to publish into B.

SPEC-FE-002 owns stale-completion protection; this specification ensures route identity feeds the correct provider scope.

## 89. Unknown Routes

An unrecognized location renders a controlled Argus not-found route surface.

It must not silently redirect to `/` by default.

Silent fallback would obscure broken internal links, stale restored routes, and route-generation defects.

## 90. Route Parsing Failures

A recognized route pattern with malformed required route data renders a controlled invalid-location outcome.

The exact UI treatment may share design-system components with not-found handling, but the failure semantics remain distinguishable for diagnostics/tests.

## 91. Presentation-Safe Route Errors

User-facing route error surfaces do not expose:

- stack traces;
- raw router exceptions;
- generated-code internals;
- implementation class names.

Technical diagnostics follow normal sanitized observability conventions.

## 92. Stale Removed Routes

If a previously published feature route no longer exists, the application handles the stale route deliberately.

Options are:

- an explicit compatibility redirect to the new canonical route; or
- the controlled not-found/stale-location surface.

Do not retain empty screens indefinitely without a compatibility requirement.

## 93. Route Migration

When a published route moves but preserves equivalent meaning, define an explicit migration redirect.

Conceptually:

```text
old canonical route
    ↓ explicit compatibility redirect
new canonical route
```

Do not scatter aliases through unrelated feature code.

## 94. Route Meaning Is Not Silently Reused

A published route path is not repurposed later for an unrelated concept merely because implementation code changed.

This follows SPEC-X-001's prohibition against silent reinterpretation of durable compatibility surfaces.

## 95. Router State as Location Authority

The router is authoritative for durable application location.

The shell does not maintain an independently mutable selected-index/navigation-location state.

Conceptually:

```text
navigation tap
    ↓
router branch/location change
    ↓
shell derives active destination
```

## 96. No Duplicate Selected Index

Avoid:

```text
router = Settings
shellSelectedIndex = Jobs
```

as two independently mutable authorities.

Presentation widgets may compute local indices from the semantic destination catalog, but the value remains derived.

## 97. Navigation Surfaces Share One Catalog

Compact bottom navigation, medium rail, and expanded/large sidebar project from one destination catalog.

Do not maintain unrelated lists with duplicated labels, route ownership, or availability logic.

## 98. Navigation Actions Are Typed

Shell navigation surfaces trigger typed destination/route actions rather than carrying raw path literals.

The routing layer translates semantic destination intent into branch activation or canonical route navigation.

## 99. Feature Controllers Do Not Navigate

Feature controllers do not call `go_router` as ordinary behavior.

Typical flow:

```text
user action
    ↓
controller command/state/result
    ↓
presentation/app composition
    ↓
typed route action when navigation is needed
```

This preserves SPEC-FE-002 separation between controller behavior and presentation effects.

## 100. Pure Presentation Navigation

A navigation action that is purely presentation flow and requires no controller transition may be initiated directly by feature presentation through its approved typed route surface.

The controller need not be involved merely to route between screens.

## 101. Navigation Result Ownership

If navigation depends on a controller operation result, the controller exposes a narrow typed outcome/state; presentation interprets that outcome and performs routing.

The controller must not return router objects or `BuildContext` callbacks.

## 102. Feature Route Public API

A feature's routing public surface should expose only the route definitions/helpers required by application composition or external feature navigation.

Feature-internal route implementation details remain private.

## 103. Cross-Feature Navigation

When one feature needs to navigate to another feature's durable destination, it uses the other feature's approved route contract or an app-owned destination abstraction.

It must not import the other feature's private routing implementation.

## 104. Navigation Dependency Direction

Preferred direction:

```text
feature presentation
    ↓
public typed route contract / app destination
    ↓
go_router
```

Prohibited:

```text
feature application/controller
    ↓
other feature private route internals
```

## 105. Shell Lifetime

The ready application shell persists while normal ready-state destinations change.

Route changes must not recreate application-lifetime providers solely because the routed child changed.

Client/event/theme lifetimes remain governed by SPEC-FE-002/003/006.

## 106. Feature Lifetime Independence

Persistent shell lifetime does not imply persistent feature-controller lifetime.

A route-scoped feature controller may still dispose when its owning route/subtree is no longer observed according to SPEC-FE-002.

## 107. Shell State Must Stay Narrow

Valid shell-owned state may include narrow application presentation concerns such as:

- current derived destination;
- transient adaptive-navigation presentation state;
- app-level notice queue/state;
- narrow status/banner projections;
- shell layout presentation mechanics.

It must not duplicate feature/backend authority.

## 108. No Feature-State Aggregator

The shell is not a global state aggregator for all visible feature state.

Feature state remains feature-owned even when a global toolbar or status region is present.

## 109. Local Scroll State

Feature scroll position and view-specific restoration remain feature/presentation concerns unless a feature specification deliberately makes them durable route/restoration state.

The shell does not own library grid/list scroll positions.

## 110. Independent View Restoration

Where ARCH-001 requires independent grid/list restoration for library browsing, SPEC-FE-010 implements it without making the shell a scroll-state owner.

## 111. Accessibility Ownership Boundary

SPEC-FE-004 requires semantic navigation consistency across adaptive presentations.

Exact focus traversal, keyboard shortcuts, target sizes, semantics labels, contrast, and screen-reader behavior are finalized by SPEC-FE-007.

Routing must nevertheless avoid architecture that would prevent those requirements, such as inaccessible custom navigation primitives with no semantic destination model.

## 112. Keyboard/Pointer Navigation

Desktop keyboard and pointer interactions may activate the same typed destination/route actions as touch navigation.

Separate input paths must not create separate route behavior.

Detailed shortcut assignments remain outside this specification unless a later route contract requires one.

## 113. Route Transition Animation

Navigation transition visuals are presentation concerns.

They must not alter route identity, readiness semantics, or branch history.

Exact motion rules belong to the design-system/presentation layer.

## 114. Platform Window Chrome

Native title bars, drag regions, system window controls, and desktop window-manager integration remain separate from application routing semantics.

If customized later, they must consume rather than redefine application location/navigation state.

## 115. Phase 000 Routing Scope

Phase 000 implements the smallest routing surface that proves the architecture:

- typed route definitions and generation;
- one app-owned router;
- presentation-readiness gating;
- one persistent ready shell;
- at least one genuine implemented feature route;
- adaptive navigation across all four size classes;
- semantic destination derivation;
- route preservation across resize;
- controlled route failure handling;
- deterministic routing tests without a real backend.

## 116. Phase 000 Shell Scope

Phase 000 shell behavior demonstrates:

```text
startup/recovery + initial presentation-authority boundary
    ↓
ready shell
    ↓
typed real destination
    ↓
adaptive navigation presentation
```

Phase 000 did not require Library, Collections, Jobs, or Sources merely to make the shell look populated. Later active amendments control the current production catalog: Phase 003 now activates Library/Sources/Jobs/Settings, while Collections and Diagnostics remain absent. Adaptive-shell, branch, and destination-count tests may still use test-only fixtures that are not registered in the shipped route graph.

## 117. Phase 000 Settings Destination

Settings is a genuine Phase 000 routed destination.

The shell must be able to activate Settings through the appropriate presentation for the current size class while retaining the canonical `/settings` semantic route.

Detailed Settings UI/theme semantics belong to SPEC-FE-006.

## 118. Phase 000 Diagnostics Destination

Diagnostics may be exposed where required by the startup/recovery and shell slices using the canonical diagnostics route contract.

Detailed diagnostics data and actions remain governed by the client/backend diagnostics contracts and SPEC-FE-005 where part of recovery.

## 119. Routing Unit Tests

Pure routing tests should verify route data and parsing without requiring widget rendering where practical.

Representative cases:

- typed ID to URI and back;
- malformed typed IDs;
- query defaults;
- query canonicalization;
- route-to-destination mapping;
- semantic parent/fallback metadata.

## 120. Startup Gating Tests

Required tests include:

```text
requested ready route + Starting
→ startup surface

then Ready
→ intended ready route
```

and:

```text
requested ready route + StartupFailed
→ recovery surface

new runtime Ready
→ revalidated intended route
```

## 121. Redirect Convergence Tests

Tests cover every relevant readiness/location combination used by the implemented slice and assert that redirect policy stabilizes without loops.

No test relies on arbitrary timing delays.

Phase 003 tests additionally prove that onboarding projection hydration occurs outside redirect execution, redirect evaluation performs zero onboarding/focused API calls, runtime/client replacement invalidates stale projected completion, and authoritative onboarding completion can enable the ready route without a redirect-time confirmation query.

## 122. Branch Navigation Tests

Required behavioral tests include:

- inactive branch selection restores prior branch location;
- active branch reselection returns to branch root;
- branch switching is not a push;
- nested branch history pops correctly;
- direct detail routes use canonical fallback when no prior history exists.

## 123. Adaptive Shell Tests

The same semantic destination must be exercised under Compact, Medium, Expanded, and Large classifications.

Tests verify that presentation changes do not change route URI, destination identity, or branch history.

Phase 002 tests verify that Sources, Jobs, and Settings are direct Compact bottom items, Jobs retains its active-work badge semantics, and all active destinations retain the same canonical routes and branch history across resize.

## 124. Compact Direct-Navigation Tests

Tests verify:

- Sources, Jobs, and Settings are visible without opening an overflow sheet;
- current destination selection is derived from route state;
- each direct item activates the same canonical branch used at wider sizes;
- Jobs preserves active-count badge semantics;
- resize does not introduce compact-only route state;
- keyboard/pointer activation remains available on desktop Compact windows while touch behavior remains practical on Android.

## 125. Restoration Tests

Routing/widget integration tests should cover:

```text
restored route
    ↓
startup gating
    ↓
Ready
    ↓
fresh feature state load
```

and branch restoration behavior where the pinned router/restoration model supports it.

## 126. Unknown-Route Tests

Tests verify that:

- unknown routes render controlled not-found state;
- malformed typed parameters render controlled invalid-location state;
- neither silently redirects to `/`;
- user-facing text contains no raw router exception details.

## 127. Feature Missing-Entity Tests

Tests verify that a valid typed route whose focused API returns not-found remains a feature-level error state rather than a router parse failure.

## 128. Shell Global-Surface Tests

Where implemented in the current slice, tests verify that:

- global status consumes an app-owned projection rather than FRB;
- transient notices do not replace durable controller error state;
- restart-required banner derives from application state rather than local guesswork;
- global surfaces persist across normal route changes.

## 129. Test Isolation

Ordinary router/shell tests do not require:

- native Rust library startup;
- FRB bindings at runtime;
- SQLite;
- real event streams;
- network/provider services.

Use controlled readiness/app projections and feature route fakes/stubs at Argus-owned seams.

## 130. Routing/Restoration Test Layer

Routing plus restoration behavior belongs primarily to routing/widget integration tests when multiple Flutter layers materially participate, consistent with CONV-TEST-001.

Narrow parsing and destination mapping remain unit-testable below that layer.

## 131. Generated-Source Verification

Route generation participates in:

```text
just generate
just check-generated
just check
```

according to CONV-REPO-001 and CONV-TEST-001.

A generated routing drift failure is a repository verification failure.

## 132. Static Architecture Verification

Where economical, architecture checks should detect:

- raw route construction outside routing-owned code;
- feature controllers importing/calling `go_router`;
- route parameter parsing outside approved route boundaries;
- duplicate shell selected-index authority;
- feature imports of other feature private route internals;
- routing imports of FRB/generated bridge implementation;
- generated route files edited manually or stale.

## 133. Semantic Review Obligations

Some routing defects cannot be proven statically.

Code review and tests must explicitly examine:

- redirect convergence;
- branch history semantics;
- fallback-parent correctness;
- startup intent preservation;
- route canonicalization;
- responsive state preservation;
- root navigator misuse.

## 134. Prohibited Patterns

The following are prohibited by default:

```text
raw route strings scattered through features
custom global navigation state parallel to go_router
feature controllers calling go_router
/more semantic route hierarchy
route identity carried only in $extra
backend read models as canonical route arguments
route parser defaulting malformed IDs silently
router redirect performing API calls
startup/recovery routes retained in normal back history
window resize causing navigation
separate phone/tablet/desktop route graphs
shell importing private feature controllers
feature-specific business logic in global shell
arbitrary callback/effect registry for global notices
```

## 135. Derived Implementation Decisions

The following are implementation details as long as the behavioral contract above is preserved:

- exact typed-route annotation syntax;
- exact generated class names;
- exact navigator key variable names;
- exact router refresh/listenable adapter needed for Riverpod readiness;
- exact widgets used to render bottom navigation, rail, and sidebar;
- exact internal data structure of `AppDestination`;
- exact internal implementation of pending route intent;
- exact transition animation primitives.

## 136. Decisions Requiring Future Specification

Later specs may refine:

- exact library query parameter catalog;
- exact game-detail master/detail composition;
- post-Phase-001 Jobs/Sources route extensions beyond `/jobs`, `/jobs/:jobRunId`, `/sources`, and `/sources/roots/:libraryRootId`;
- release-stable deep-link guarantees beyond local restoration;
- global keyboard navigation shortcuts;
- route-worthy modal catalog;
- post-MVP external URI scheme/protocol handling.

Such refinements must preserve this specification's authority and non-duplication rules unless explicitly superseded.

## 137. Acceptance Criteria

SPEC-FE-004 is satisfied when:

1. `go_router` is the sole application routing framework.
2. Authored navigation uses the approved typed route model.
3. Generated route source is deterministic, committed where required by repository convention, and drift-checked.
4. `app/routing` composes feature route surfaces without owning feature behavior.
5. Routes represent durable location/scope rather than arbitrary transient widget state.
6. Typed identifiers are parsed at the route boundary before feature use.
7. Query parameters have one semantic owner and deterministic canonicalization.
8. Canonical durable routes do not depend on in-memory extras or backend object graphs.
9. One persistent ready application shell owns normal destination composition.
10. Major stateful branches preserve independent history where applicable.
11. Primary destination switching activates branches rather than pushing across branches.
12. Reselecting the active destination returns its branch to the canonical root.
13. Compact navigation directly exposes the active Phase 002 Sources, Jobs, and Settings destinations and does not create compact-only route identity.
14. One semantic destination catalog drives all adaptive navigation surfaces.
15. The active destination is derived from route state rather than duplicate mutable shell state.
16. Compact, Medium, Expanded, and Large presentations share one route graph.
17. Window size changes preserve route identity and branch history.
18. Local feature layout remains based on local constraints rather than propagated hardware-category flags.
19. Startup/recovery surfaces remain outside the normal ready shell.
20. Startup gating preserves intended ready-state routes.
21. Successful recovery revalidates pending route intent against the new runtime/application state.
22. Startup/recovery gating does not pollute normal user history.
23. Redirect policy is side-effect free, deterministic, and convergent.
24. Restored/external route data uses normal typed validation and startup gating.
25. Route restoration reloads current feature state instead of restoring stale backend snapshots.
26. Valid-but-missing backend entities remain feature failures, distinct from route parsing failures.
27. Unknown and malformed locations render controlled route-level outcomes rather than silent arbitrary fallback.
28. Direct detail routes have deterministic semantic-parent fallback when no genuine history exists.
29. Feature controllers do not navigate directly.
30. Cross-feature navigation uses approved typed route/public destination contracts.
31. The shell owns global cross-feature presentation surfaces without becoming a feature-state owner.
32. Global notices are ephemeral and never replace durable operation/restart/error state.
33. Routing/shell tests run deterministically without requiring the real Rust backend for ordinary coverage.
34. Branch, redirect, restoration, route parsing, unknown-route, and adaptive-shell behavior are explicitly tested.
35. Phase 000 registers only genuine implemented destinations; future-feature shell-validation placeholders are test-only and never enter the production route graph.
36. Phase 001 registers genuine Sources and Jobs routes/branches; Jobs is directly reachable on Compact while Sources and Settings use the specified adaptive secondary placements without changing canonical route identity, and Diagnostics remains a reserved non-active destination.
37. Phase 003 product-onboarding gating is driven by one runtime-generation-aware app-owned routing-safe projection hydrated from backend authority outside redirect evaluation; no duplicate Flutter completion authority is persisted or inferred from URI.
38. While the ready shell is admitted, switching Library/Sources/Jobs/Settings branches does not wait for unrelated background refresh work or any redirect-time backend query.

## 138. Phase 000 Minimum Implementation

Phase 000 requires at least:

```text
app/routing
├── typed route definitions
├── router composition
├── presentation-readiness gating
├── route error/not-found handling
└── destination mapping

app/shell
├── persistent ApplicationShell
├── Compact navigation presentation
├── Medium navigation presentation
├── Expanded/Large navigation presentation
├── routed content host
└── narrow global status/notice host as required
```

with one or more genuine Phase 000 routed destinations such as Settings and, where implemented by a slice, Diagnostics.

No future Library, Collections, Jobs, Sources, provider, metadata, or ROM-management behavior is required merely by this specification.

## 139. Out of Scope

This specification intentionally leaves the following to later frontend specifications or feature contracts:

- startup and recovery screen visual/state-machine details beyond routing placement and intent preservation;
- exact theme-setting routing interactions beyond Settings destination identity;
- exact window-size thresholds and visual design-system rules;
- exact accessibility/focus/keyboard implementation;
- detailed Library browse/search/filter route-query schema;
- final game-detail master/detail pane behavior;
- Collections and route catalogs beyond the Phase 003 Library/Game/Jobs/Sources activation;
- external OS protocol/deep-link registration;
- custom native window title bar integration;
- persistent frontend caching/offline navigation behavior.

It does not define a second navigation state framework, custom URL dispatcher, or application-wide feature command bus.

## 140. Phase 002 Android Adaptive/Back Amendment

Android uses the same route graph and width-driven size classes as desktop. No `Platform.isAndroid`, phone/tablet, foldable, or hardware-category Boolean may become global navigation authority.

Argus does not lock orientation. Rotation, split screen, multi-window resize, and fold/unfold may change size class live while preserving canonical route identity and branch history.

Android system Back follows the same route/modal hierarchy and must not exit while a meaningful in-app pop/dismiss action exists. Predictive Back should use the supported Flutter/Android integration without creating separate route state. The Android folder browser defined by SPEC-FE-008 handles Back as hierarchy navigation before dismissal where applicable.

System bars, display cutouts, IME, gesture insets, and safe areas are presentation constraints, not route inputs.

## 141. Phase 003 Library-Destination Activation

PHASE-003 activates the previously reserved `AppDestination.library` and canonical Library/Game routes. Collections remains reserved and inactive.

The production primary destination catalog becomes:

```text
Library
Sources
Jobs
Settings
```

Library is the default ready-state destination after required startup/platform readiness and Phase 003 product onboarding are satisfied.

Active routes include:

```text
/onboarding/library
/library
/library/platforms/:platformId
/library/sources/:sourceId
/library/library-roots/:libraryRootId
/games/:gameId
```

All `/library/**` scope routes and `/games/:gameId` map to `AppDestination.library`. `/sources/**` remains `AppDestination.sources`; logical source-scoped Library browsing does not reuse the operational Sources route family.

`/onboarding/library` is a root-navigator gating route outside the shell. It is entered only from authoritative incomplete onboarding state, cannot be selected from primary navigation, does not create a shell branch, and cannot be dismissed to bypass required consent/setup. Back dismisses transient onboarding surfaces first and otherwise follows platform exit behavior.

The Library branch participates in the same independent branch-history contract as other primary destinations. Compact navigation exposes all four active destinations directly; Medium/Expanded/Large use the existing adaptive rail/sidebar policy. No semantic `More` destination is introduced.

`/library/collections/:collectionId` is not registered in the Phase 003 production route graph.

Game detail route identity is invariant across width classes. Compact/Medium may present a full routed page while Expanded/Large may project the same route as a master-detail inspector. Live resize never changes `GameId`, canonical URI, destination identity, or branch history.

Backend-reported `GameId` redirects are canonicalized through the routing/client boundary without redirect loops or using display-title/provider data as route identity.

The Phase 003 onboarding gate is projected into routing-safe app state before redirect evaluation. GoRouter redirect logic performs no `LibraryOnboardingApi`, focused client, FRB, or native read. Once onboarding is complete and the shell is admitted, an active `library_refresh`, `game_refresh`, or `library_resolution_refresh` cannot make destination switching wait on onboarding re-query or unrelated backend work.

## 142. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [PHASE-001 — Local Sources and Indexing](../../phases/phase-001-local-sources-and-indexing.md)
- [PHASE-003 — Game Identification and Enrichment](../../phases/phase-003-game-identification-and-enrichment.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](../backend/spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-005 — Startup and Recovery UI](spec-fe-005-startup-and-recovery-ui.md)
- [SPEC-FE-006 — Appearance Settings and Theme Application](spec-fe-006-appearance-settings-and-theme-application.md)
- [SPEC-FE-007 — Design-System Foundation and Accessibility Baseline](spec-fe-007-design-system-foundation-and-accessibility-baseline.md)
- [SPEC-FE-010 — Library, Game Detail, and Enrichment UX](spec-fe-010-library-game-detail-and-enrichment-ux.md)
- [SPEC-FE-008 — Sources and Library Folder Management](spec-fe-008-sources-and-library-folder-management.md)
- [SPEC-FE-009 — Jobs and Background Operation Presentation](spec-fe-009-jobs-and-background-operation-presentation.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [CONV-DOC-001 — Documentation and Codex Result Conventions](../../conventions/conv-doc-001-documentation-and-codex-result-conventions.md)
- [Frontend Specifications Index](README.md)
- [Subsystem Specification Template](../../templates/subsystem-specification.md)
