# Flutter Bootstrap and Static Shell Design

**Slice:** SLICE-P00-004 — Flutter Bootstrap and Static Shell  
**Status:** Approved for implementation  
**Date:** 2026-08-12

## 1. Purpose

This design establishes the first real Flutter composition root, typed route
graph, persistent adaptive shell, responsive authority, Material 3 theme
foundation, and genuine Settings destination. The implementation remains
fully independent of Rust, generated FRB bindings, `ArgusClient`, SQLite, and
later startup or appearance workflows.

The design follows the approved minimal generated composition approach. It
adds only the production behavior needed by Slice 004 and deliberately avoids
future feature routes, stateful branch semantics, backend readiness models,
and speculative design-system abstractions.

## 2. Governing invariants

1. Compact Settings is available through More, not as a direct bottom
   destination. More is transient presentation state; Settings remains the
   canonical `/settings` route.
2. Settings is the only production semantic destination. Any additional
   destinations needed to exercise shell behavior are test fixtures and never
   enter the production route graph.
3. The generated Riverpod router provider is a dependency/composition seam.
   It does not mirror location, selected destination, or navigation history.
   `go_router` remains the sole authority for those values.
4. `/` redirects deterministically to `/settings`. No Library landing route or
   other fake default is introduced.
5. Slice 004 uses a typed `ShellRoute`, not `StatefulShellRoute`. Independent
   branch history has no meaning while only one genuine destination exists.
6. `just generate` regenerates every registered Dart generated-source family.
   `just check-generated` snapshots the explicitly registered generated files,
   regenerates them, compares bytes and existence against that snapshot, and
   rejects any generated output outside the registered set. It never stages or
   otherwise mutates Git state.
7. Slice 004 introduces no startup/readiness state model. The shell is the
   current static presentation arrangement and remains structurally compatible
   with later app-owned readiness gating.

## 3. Architecture

The production composition is:

```text
main()
  -> bootstrapArgus()
  -> ArgusBootstrap
  -> one root ProviderScope
  -> ArgusApp
  -> generated appRouterProvider
  -> MaterialApp.router
  -> typed ShellRoute
  -> ApplicationShell
  -> SettingsPage
```

Ownership is divided as follows:

- `app/bootstrap` owns process-to-widget composition and the single root
  `ProviderScope`.
- `app/routing` owns the `GoRouter`, typed route topology, canonical root
  redirect, typed route-to-destination mapping, and not-found presentation.
- `app/shell` owns adaptive navigation chrome and the routed child host.
- `core/responsive` owns global width classification and page gutters.
- `core/design_system` owns both production `ThemeData` values.
- `features/settings` owns the public Settings feature surface and keeps its
  implementation private under `src`.

No provider bucket, service locator, second router, or mutable selected-index
authority is introduced.

## 4. Bootstrap and provider composition

`main.dart` contains only a call into `app/bootstrap`. `ArgusBootstrap` creates
the sole production `ProviderScope` and hosts `ArgusApp`.

`ArgusApp` is a `ConsumerWidget`. It watches one generated, application-lifetime
router provider and passes that router to `MaterialApp.router`. The provider
creates and disposes the app-owned `GoRouter`; it stores no navigation value of
its own. Location changes continue to flow only through `go_router`.

No additional provider is manufactured merely to demonstrate Riverpod code
generation. Every Argus provider authored by this slice uses
`riverpod_annotation` and committed generated output.

## 5. Routing

The typed route graph contains only:

```text
Typed root route `/`
  -> pure redirect to SettingsRoute().location

Typed application ShellRoute
  -> typed SettingsRoute `/settings`
```

`SettingsRoute` builds the feature’s public `SettingsPage`. The typed shell
wraps the routed child in `ApplicationShell`. The router uses an app-owned
error builder for unknown or malformed locations, producing a controlled
not-found page rather than an exception or fabricated redirect. The builder
passes only `state.uri.path`; the not-found page bounds and sanitizes that path
before displaying it. Query parameters, fragments, router exceptions, and
generated details never become user-facing copy.

The semantic destination catalog contains exactly `AppDestination.settings`.
The typed route layer compares the current router URI with
`SettingsRoute().location`, maps it to this semantic value, and passes it to
the shell. The shell never maintains a selected index in mutable state.
Navigation callbacks use generated typed route helpers.

`StatefulShellRoute` is intentionally excluded. When later slices introduce
multiple real destinations with meaningful independent histories, the route
topology may be upgraded without changing the feature-owned Settings route or
shell presentation contract.

## 6. Adaptive shell

One `ApplicationShell` adapts from the width available at the application
root:

| Size class | Navigation presentation |
|---|---|
| Compact | `BottomAppBar` with a standard More action; More opens a modal sheet containing Settings |
| Medium | Icon-oriented `NavigationRail` |
| Expanded | Extended, labeled `NavigationRail` used as the persistent sidebar |
| Large | The same full labeled sidebar structure as Expanded |

A Material 3 `NavigationBar` is not used for Compact because it requires two
or more destinations. Adding a second item would violate the single genuine
production-destination constraint. `BottomAppBar` provides the governed bottom
navigation placement without inventing a semantic destination.

More open/closed state belongs to Flutter’s modal presentation only. Opening
More does not change the URI. Choosing Settings invokes the generated typed
`SettingsRoute` helper and leaves the canonical URI at `/settings`.

Medium and wide navigation receive the route-derived semantic destination and
use it to calculate their selected presentation. Resizing rebuilds only the
chrome; the router and routed child remain the same, preserving `/settings`.

## 7. Responsive foundation

`core/responsive` defines exactly:

```text
WindowSizeClass.compact   width < 600
WindowSizeClass.medium    600 <= width < 840
WindowSizeClass.expanded  840 <= width < 1200
WindowSizeClass.large     width >= 1200
```

One pure function classifies a supplied logical width. The same owner contains
the exact `600`, `840`, and `1200` thresholds. No platform, device, hardware,
or operating-system classification participates.

Page gutters are derived from the same typed size class:

```text
Compact 16, Medium 24, Expanded 32, Large 32
```

Shell and Settings code consume the typed classification and do not repeat
breakpoint literals.

## 8. Design-system foundation

`core/design_system` exposes one production theme owner with Light and Dark
`ThemeData`. Both use official Material 3, a centralized replaceable seed
palette through `ColorScheme.fromSeed`, platform-resolved Material typography,
and standard visual density.

Only component configuration used by the shell or Settings may be added. The
slice adds no custom font, dynamic OS accent authority, permanent brand claim,
custom icon pack, illustration assets, theme adapter, broad component wrapper
family, or component showcase. Feature widgets consume `Theme.of(context)`
semantic roles rather than app-wide color literals.

## 9. Settings surface

`features/settings/settings.dart` is the narrow public entry point. It exports
the Settings page while keeping implementation files private under `src`.

The page is genuine routed content, not a fake destination. It contains a
Settings heading and concise explanatory content stating that appearance
controls become available after application services are connected. It
contains no selector, save action, persisted value, pending state, backend
read, or claim of authoritative mutation.

Content uses a scrolling layout, semantic text roles, responsive page gutters,
and a readable maximum width. This keeps the surface usable at Compact and
wide sizes under 1.0x and 2.0x text scaling.

## 10. Accessibility and interaction

The implementation relies on standard Material keyboard, focus, semantics,
modal, rail, and list-item behavior. The Compact More action has an explicit
accessible label. Navigation labels identify Settings, and route selection is
not communicated by color alone.

Standard Material controls preserve the normal 48 by 48 logical-pixel target
baseline. Tests exercise keyboard activation of Compact More and Settings,
logical dismissal without a trap, representative semantics, and text scaling.
No custom focus manager or shortcut system is introduced.

## 11. Testing strategy

The implementation uses focused red-green cycles at the lowest faithful
boundary:

1. Pure unit tests cover the four-value enum and exact breakpoint boundaries.
2. Theme tests construct both production themes and verify Material 3.
3. Routing/widget tests cover `/` to `/settings`, typed Settings location,
   unknown-route presentation, and the absence of fake production routes.
4. Bootstrap tests prove one root `ProviderScope`, thin `main.dart`, and
   backend-independent root construction.
5. Shell widget tests cover Compact, Medium, Expanded, and Large structure;
   route preservation on resize; transient More behavior; keyboard operation;
   semantics; target size; and 1.0x/2.0x text scaling.
6. Focused architecture checks enforce import direction, generated-provider
   style, theme/breakpoint ownership, absence of bridge/backend leakage, and
   the sparse production route graph.
7. Canonical generation commands reproduce Riverpod and typed-route `.g.dart`
   files and fail for registered byte/existence drift or unregistered generated
   output.

Ordinary tests instantiate only Dart/Flutter code and never initialize Rust or
FRB.

## 12. Generated-source workflow

The Flutter package adds only the Riverpod and `go_router` runtime, annotation,
builder, and `build_runner` dependencies required by this slice. Dependency
versions are resolved by the pinned Flutter/Dart toolchain and recorded by
normal package tooling in `pubspec.lock`.

`just generate` runs one build-runner sequence from `flutter/` with the pinned
FVM Dart toolchain. This sequence generates both the Riverpod provider part and
the typed-route part.

`just check-generated` registers these Slice 004 outputs explicitly:

```text
flutter/lib/app/routing/app_routes.g.dart
flutter/lib/app/routing/app_router.g.dart
```

The recipe snapshots each registered file's bytes and existence state in a
temporary directory, runs `just generate`, and compares the regenerated bytes
and existence state with the snapshot. A changed, deleted, missing, or newly
created registered file fails the check. It also enumerates generated Dart output
before and after generation and fails if any `.g.dart` or `.freezed.dart` file
falls outside the registered set, including an untracked generator probe. The
temporary snapshot is removed on exit; no Git index, staging area, or Git
metadata is changed. `just check` continues to depend on this recipe.

## 13. Failure behavior

- Unknown locations render an app-owned not-found page with a bounded,
  sanitized path-only summary and a typed action back to Settings. Query,
  fragment, exception, and generated implementation details are omitted.
- Responsive classification has no external failure path because it is pure.
- Settings performs no asynchronous or backend operation and therefore
  fabricates no operational error state.
- Generator failures stop the canonical recipe with the underlying tool error.
- Generated drift fails explicitly and reports registered byte/existence drift
  and unexpected generated paths.

## 14. Deferred work

Slice 005 or later owns all FRB bindings, native loading, `ArgusClient`,
focused APIs, actual runtime readiness, startup/recovery routes, authoritative
appearance state, theme-mode mutation, event synchronization, diagnostics,
restart restoration, and multi-destination branch history. This slice creates
no placeholder state or interfaces for those behaviors.

## 15. Documentation impact

The design implements the existing governed contracts without changing their
durable meaning. No governed architecture, phase, specification, or convention
document requires modification. The task’s required `RESULT.md` will record
the final implementation and verification evidence.
