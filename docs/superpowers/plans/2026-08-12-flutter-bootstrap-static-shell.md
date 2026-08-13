# Flutter Bootstrap and Static Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend-independent Slice 004 Flutter composition root,
typed router, adaptive static shell, responsive authority, Material 3 themes,
and genuine Settings destination.

**Architecture:** A thin `main.dart` delegates to an app-owned bootstrap with
one root `ProviderScope`. A generated Riverpod provider creates one app-owned
`GoRouter`; generated typed routes redirect `/` to `/settings` and place the
Settings page inside one non-stateful adaptive shell. Pure responsive and
theme owners live under `core`, while Settings exposes one narrow public
feature surface.

**Tech Stack:** Flutter 3.44.7, Dart 3.12, Material 3, flutter_riverpod,
riverpod_annotation/riverpod_generator, go_router/go_router_builder,
build_runner, flutter_test, FVM, Just, filesystem generated-output drift verification.

## Global Constraints

- Compact Settings is available only through transient More presentation;
  route identity remains `/settings` and `/more` never exists.
- Settings is the only production semantic destination. Additional
  destinations, if any are needed, are test fixtures only.
- The generated router provider is a dependency seam, not navigation state;
  `go_router` owns location and route-derived selection.
- `/` redirects to `/settings`; no fake Library route exists.
- Do not use `StatefulShellRoute` in Slice 004.
- `just check-generated` snapshots explicitly registered generated files before
  regeneration, compares bytes and existence afterward, and rejects any
  generated output outside the registered set without staging or mutating Git.
- Do not introduce startup/readiness state, Rust, FRB, `ArgusClient`, SQLite,
  appearance mutation, events, diagnostics, or later-slice behavior.
- Use test-first red/green cycles for every production behavior.
- Do not modify Flutter platform runner/project files.
- Do not stage, commit, amend, reset, restore, clean, or push Git state.
- Keep human-readable Dart documentation current for public contracts and
  non-obvious ownership decisions.
- No `CONTEXT.md` exists, so no context document update is required.

---

## File map

### Production and generated source

- `flutter/lib/main.dart` — process entry point; delegates only.
- `flutter/lib/app/bootstrap/app_bootstrap.dart` — one root `ProviderScope`
  and `runApp` boundary.
- `flutter/lib/app/bootstrap/argus_app.dart` — `MaterialApp.router`
  composition.
- `flutter/lib/app/routing/app_destination.dart` — the one semantic
  destination value.
- `flutter/lib/app/routing/app_routes.dart` — typed root, shell, and Settings
  routes.
- `flutter/lib/app/routing/app_routes.g.dart` — generated typed route source.
- `flutter/lib/app/routing/app_router.dart` — generated Riverpod router
  provider and router construction.
- `flutter/lib/app/routing/app_router.g.dart` — generated provider source.
- `flutter/lib/app/routing/not_found_page.dart` — controlled app-owned unknown
  route surface.
- `flutter/lib/app/shell/application_shell.dart` — one adaptive shell with
  Compact More, Medium rail, and wide sidebar.
- `flutter/lib/core/responsive/window_size_class.dart` — exact global
  breakpoints, classifier, and page gutters.
- `flutter/lib/core/design_system/argus_theme.dart` — centralized Light/Dark
  Material 3 themes.
- `flutter/lib/features/settings/settings.dart` — narrow public feature entry
  point.
- `flutter/lib/features/settings/src/settings_page.dart` — genuine static
  Settings presentation.

### Tests and workflow

- `flutter/test/core/responsive/window_size_class_test.dart` — pure boundary
  tests.
- `flutter/test/core/design_system/argus_theme_test.dart` — Light/Dark theme
  construction and representative surface contrast guidance.
- `flutter/test/features/settings/settings_page_test.dart` — real Settings,
  text scaling, and backend independence.
- `flutter/test/app/shell/application_shell_test.dart` — four adaptive
  presentations, transient More, keyboard, semantics, targets, and resize.
- `flutter/test/app/routing/app_router_test.dart` — typed canonical routes,
  redirect, not-found behavior, sparse production route graph, and route
  preservation.
- `flutter/test/app/bootstrap/app_bootstrap_test.dart` — single root scope and
  production root construction.
- `flutter/test/architecture/architecture_boundaries_test.dart` — focused
  import/source ownership checks.
- `flutter/pubspec.yaml` and `flutter/pubspec.lock` — focused runtime and
  generator dependencies, with lockfile changed only by package tooling.
- `justfile` — canonical generation and complete generated drift detection.
- `.chatgpt/codex-runs/2026-08-13T002300Z-phase-000-slice-004-flutter-bootstrap-static-shell/RESULT.md`
  — required factual completion report.

---

### Task 1: Register focused dependencies and canonical generators

**Files:**

- Modify: `flutter/pubspec.yaml`
- Modify through Flutter tooling: `flutter/pubspec.lock`
- Modify: `justfile`

**Interfaces:**

- Consumes: pinned Flutter 3.44.7 and Dart 3.12 toolchain from
  `flutter/.fvmrc` and `pubspec.yaml`.
- Produces: one `build_runner` sequence used by Riverpod and `go_router`, plus
  a Git-independent drift check comparing registered generated output to a
  pre-generation byte/existence snapshot and rejecting unregistered output.

- [ ] **Step 1: Add only the required dependency families through package tooling**

Run from `flutter/`:

```bash
rtk proxy fvm flutter pub add flutter_riverpod:3.3.2 riverpod_annotation:4.0.3 go_router:^17.3.0
rtk proxy fvm flutter pub add --dev build_runner:2.15.1 riverpod_generator:4.0.4 go_router_builder:4.4.0
```

The exact Riverpod/generator pins are required because Flutter 3.44.7 pins
`meta`/analyzer compatibility that excludes newer Riverpod generator and
build-runner lines. Expected: `pubspec.yaml` contains those six focused
dependencies and `pubspec.lock` is updated only by `flutter pub add`.

- [ ] **Step 2: Replace the placeholder generation recipes**

Change `justfile` to use this exact behavior. The registry is explicit and
includes every expected Slice 004 generated output, regardless of whether the
files are currently tracked:

```just
registered_generated_files := "flutter/lib/app/routing/app_routes.g.dart flutter/lib/app/routing/app_router.g.dart"

generate:
    cd flutter && fvm dart run build_runner build

check-generated:
    @set -euo pipefail; \
      snapshot_dir="$(mktemp -d)"; \
      trap 'rm -rf "${snapshot_dir}"' EXIT; \
      registered_files=( {{registered_generated_files}} ); \
      before_generated="${snapshot_dir}/before-generated"; \
      mkdir -p "${before_generated}"; \
      for path in "${registered_files[@]}"; do \
        key="$(printf '%s' "${path}" | tr '/' '_')"; \
        if [[ -f "${path}" ]]; then \
          printf 'present\n' > "${before_generated}/${key}.state"; \
          cp "${path}" "${before_generated}/${key}.bytes"; \
        else \
          printf 'absent\n' > "${before_generated}/${key}.state"; \
        fi; \
      done; \
      find flutter/lib -type f \( -name '*.g.dart' -o -name '*.freezed.dart' \) -print | sort > "${snapshot_dir}/before.paths"; \
      just generate; \
      status=0; \
      for path in "${registered_files[@]}"; do \
        key="$(printf '%s' "${path}" | tr '/' '_')"; \
        before_state="$(<"${before_generated}/${key}.state")"; \
        if [[ "${before_state}" == present ]]; then \
          if [[ ! -f "${path}" ]] || ! cmp -s "${before_generated}/${key}.bytes" "${path}"; then \
            echo "Generated output changed: ${path}" >&2; status=1; \
          fi; \
        elif [[ -f "${path}" ]]; then \
          echo "Registered generated output was created: ${path}" >&2; status=1; \
        else \
          echo "Registered generated output is missing: ${path}" >&2; status=1; \
        fi; \
      done; \
      find flutter/lib -type f \( -name '*.g.dart' -o -name '*.freezed.dart' \) -print | sort > "${snapshot_dir}/after.paths"; \
      while IFS= read -r path; do \
        if [[ -z "${path}" ]]; then continue; fi; \
        known=false; \
        for registered in "${registered_files[@]}"; do \
          if [[ "${path}" == "${registered}" ]]; then known=true; break; fi; \
        done; \
        if [[ "${known}" != true ]]; then \
          echo "Unexpected generated output: ${path}" >&2; status=1; \
        fi; \
      done < <(cat "${snapshot_dir}/before.paths" "${snapshot_dir}/after.paths" | sort -u); \
      exit "${status}"
```

Keep `just check` dependent on `check-generated`. Do not change Rust, format,
lint, architecture, or test recipes.

- [ ] **Step 3: Resolve dependencies using the pinned toolchain**

Run:

```bash
rtk proxy fvm flutter pub get
```

Expected: exit 0 with no platform-project regeneration.

- [ ] **Step 4: Verify the existing Flutter smoke baseline remains green**

Run:

```bash
rtk test fvm flutter test --no-pub test/workspace_smoke_test.dart
```

Expected: the existing smoke test passes.

---

### Task 2: Add the pure responsive authority test-first

**Files:**

- Create: `flutter/test/core/responsive/window_size_class_test.dart`
- Create: `flutter/lib/core/responsive/window_size_class.dart`

**Interfaces:**

- Produces: `WindowSizeClass`,
  `WindowSizeClass classifyWindowWidth(double width)`, and
  `double pageGutterFor(WindowSizeClass sizeClass)`.
- Consumes: no Flutter widgets, Riverpod, routing, feature, platform, or
  backend code.

- [ ] **Step 1: Write the failing responsive unit tests**

Create a table-driven test with hand-derived expected values:

```dart
import 'package:argus/core/responsive/window_size_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WindowSizeClass exposes exactly four structural classes', () {
    expect(WindowSizeClass.values, <WindowSizeClass>[
      WindowSizeClass.compact,
      WindowSizeClass.medium,
      WindowSizeClass.expanded,
      WindowSizeClass.large,
    ]);
  });

  for (final testCase in <({double width, WindowSizeClass expected})>[
    (width: 599, expected: WindowSizeClass.compact),
    (width: 600, expected: WindowSizeClass.medium),
    (width: 839, expected: WindowSizeClass.medium),
    (width: 840, expected: WindowSizeClass.expanded),
    (width: 1199, expected: WindowSizeClass.expanded),
    (width: 1200, expected: WindowSizeClass.large),
  ]) {
    test('${testCase.width} classifies as ${testCase.expected.name}', () {
      expect(classifyWindowWidth(testCase.width), testCase.expected);
    });
  }

  test('page gutters derive from the structural size class', () {
    expect(pageGutterFor(WindowSizeClass.compact), 16);
    expect(pageGutterFor(WindowSizeClass.medium), 24);
    expect(pageGutterFor(WindowSizeClass.expanded), 32);
    expect(pageGutterFor(WindowSizeClass.large), 32);
  });
}
```

- [ ] **Step 2: Run the focused test and observe RED**

Run:

```bash
rtk test fvm flutter test --no-pub test/core/responsive/window_size_class_test.dart
```

Expected: failure because the production library does not exist.

- [ ] **Step 3: Implement the minimal pure classifier with documentation**

Create:

```dart
/// Application-wide structural width classes, measured in logical pixels.
enum WindowSizeClass { compact, medium, expanded, large }

const double _mediumWidth = 600;
const double _expandedWidth = 840;
const double _largeWidth = 1200;

/// Classifies available application width without consulting platform or
/// hardware identity.
WindowSizeClass classifyWindowWidth(double width) {
  if (width < _mediumWidth) return WindowSizeClass.compact;
  if (width < _expandedWidth) return WindowSizeClass.medium;
  if (width < _largeWidth) return WindowSizeClass.expanded;
  return WindowSizeClass.large;
}

/// Returns the page-content gutter for an application structural class.
double pageGutterFor(WindowSizeClass sizeClass) => switch (sizeClass) {
  WindowSizeClass.compact => 16,
  WindowSizeClass.medium => 24,
  WindowSizeClass.expanded || WindowSizeClass.large => 32,
};
```

- [ ] **Step 4: Run the focused test and observe GREEN**

Run the Step 2 command again.

Expected: all responsive tests pass.

---

### Task 3: Add centralized themes and the static Settings surface test-first

**Files:**

- Create: `flutter/test/core/design_system/argus_theme_test.dart`
- Create: `flutter/lib/core/design_system/argus_theme.dart`
- Create: `flutter/test/features/settings/settings_page_test.dart`
- Create: `flutter/lib/features/settings/settings.dart`
- Create: `flutter/lib/features/settings/src/settings_page.dart`

**Interfaces:**

- Produces: `ArgusTheme.light`, `ArgusTheme.dark`, and public
  `SettingsPage`.
- Consumes: `WindowSizeClass` classification/gutters and semantic Material
  theme roles only.

- [ ] **Step 1: Write failing theme construction tests**

```dart
import 'package:argus/core/design_system/argus_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light production theme uses Material 3', () {
    final theme = ArgusTheme.light;
    expect(theme.brightness, Brightness.light);
    expect(theme.useMaterial3, isTrue);
    expect(theme.visualDensity, VisualDensity.standard);
  });

  test('dark production theme uses Material 3', () {
    final theme = ArgusTheme.dark;
    expect(theme.brightness, Brightness.dark);
    expect(theme.useMaterial3, isTrue);
    expect(theme.visualDensity, VisualDensity.standard);
  });
}
```

- [ ] **Step 2: Run theme tests and observe RED**

```bash
rtk test fvm flutter test --no-pub test/core/design_system/argus_theme_test.dart
```

Expected: missing production theme owner.

- [ ] **Step 3: Implement the minimal centralized theme owner**

```dart
import 'package:flutter/material.dart';

/// Owns the replaceable Material theme data used by the application root.
abstract final class ArgusTheme {
  static const Color _seedColor = Color(0xff4f6359);

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
```

- [ ] **Step 4: Run theme tests and observe GREEN**

Run Step 2 again. Expected: both tests pass.

- [ ] **Step 5: Write failing Settings widget tests at 1.0x and 2.0x**

Create a helper that pumps `SettingsPage` inside `MaterialApp` with
`ArgusTheme.light`, explicit `MediaQueryData(size: Size(width, 800),
textScaler: TextScaler.linear(scale))`, and a fixed surface size. Add tests for
widths `480` and `1440`, scales `1.0` and `2.0`, asserting:

```dart
expect(find.text('Settings'), findsOneWidget);
expect(find.textContaining('Appearance controls will be available'), findsOneWidget);
expect(tester.takeException(), isNull);
```

Also assert that no `Radio`, `Switch`, `DropdownButton<Object?>`, or
`SegmentedButton<Object?>` appears, preventing a fake persisted appearance
control.

- [ ] **Step 6: Run Settings tests and observe RED**

```bash
rtk test fvm flutter test --no-pub test/features/settings/settings_page_test.dart
```

Expected: missing public Settings feature surface.

- [ ] **Step 7: Implement the genuine static Settings page**

`settings.dart` exports only the page:

```dart
export 'src/settings_page.dart' show SettingsPage;
```

`SettingsPage` must:

- use `MediaQuery.sizeOf(context).width` with `classifyWindowWidth`;
- derive padding with `pageGutterFor`;
- use `SafeArea`, `SingleChildScrollView`, `Align`, and a `ConstrainedBox` with
  maximum readable width `720`;
- mark the `Settings` title as a semantic header;
- use `Theme.of(context).textTheme.headlineMedium` and `bodyLarge`;
- render the exact temporary explanatory sentence
  `Appearance controls will be available after application services are connected.`;
- contain no interactive or backend-facing controls.

- [ ] **Step 8: Run Settings tests and observe GREEN**

Run Step 6 again. Expected: all four width/scale combinations render without
exceptions and the static contract passes.

---

### Task 4: Build the adaptive shell test-first

**Files:**

- Create: `flutter/lib/app/routing/app_destination.dart`
- Create: `flutter/test/app/shell/application_shell_test.dart`
- Create: `flutter/lib/app/shell/application_shell.dart`

**Interfaces:**

- Consumes: `WindowSizeClass`, routed `AppDestination?`, routed child widget,
  and a typed-route callback supplied by routing composition.
- Produces: `AppDestination.settings` and
  `ApplicationShell({required AppDestination? currentDestination, required
  VoidCallback onSettingsSelected, required Widget child})`.

- [ ] **Step 1: Write the failing semantic destination test**

Test that production exposes exactly the one genuine destination:

```dart
expect(AppDestination.values, <AppDestination>[AppDestination.settings]);
```

- [ ] **Step 2: Write failing four-class shell widget tests**

Pump `ApplicationShell` under a production `MaterialApp` at widths `480`,
`720`, `1024`, and `1440`. Use the keys:

```text
compact-more-button
medium-navigation-rail
expanded-navigation-sidebar
large-navigation-sidebar
```

Assert exactly the corresponding structure exists at each width and that the
child marker remains present.

- [ ] **Step 3: Add failing Compact More interaction tests**

Cover these behaviors separately:

1. activating More opens a modal sheet containing `Settings` and does not call
   `onSettingsSelected`;
2. keyboard Tab/Enter can activate More, then keyboard traversal/Enter can
   activate Settings;
3. selecting Settings calls the callback once and closes the modal;
4. Escape dismisses More without calling the callback, demonstrating no
   keyboard trap;
5. the More hit target is at least 48 by 48 logical pixels;
6. More and Settings expose meaningful semantics labels.

Use callback count as a test-fixture observation of the real shell boundary;
do not add production state for testing.

- [ ] **Step 4: Add failing wide navigation tests**

At Medium, Expanded, and Large, assert:

- Settings is the only navigation destination;
- route-derived `AppDestination.settings` selects it;
- activating it calls the supplied callback;
- Medium is not extended;
- Expanded and Large are extended/labeled.

- [ ] **Step 5: Run shell tests and observe RED**

```bash
rtk test fvm flutter test --no-pub test/app/shell/application_shell_test.dart
```

Expected: destination and shell production libraries are missing.

- [ ] **Step 6: Implement the minimal semantic destination catalog**

```dart
/// Durable semantic destinations currently implemented by Argus.
enum AppDestination { settings }
```

- [ ] **Step 7: Implement one structurally adaptive shell**

Use a single `ApplicationShell`, read the application-root width with
`MediaQuery.sizeOf(context).width`, and switch through
`classifyWindowWidth`.

- Compact: `Scaffold` + `BottomAppBar` + standard `IconButton` with
  `Icons.more_horiz`, tooltip/semantics `More`, and key
  `compact-more-button`. `showModalBottomSheet` contains one standard
  `ListTile` for Settings. Pop the modal and invoke `onSettingsSelected`.
- Medium: `Scaffold.body` is a `Row` with non-extended `NavigationRail`, one
  Settings destination, a divider, and `Expanded(child: child)`.
- Expanded/Large: same row shape with `NavigationRail(extended: true)`, one
  labeled Settings destination, divider, and routed child.
- Compute `selectedIndex` only from `currentDestination ==
  AppDestination.settings`; store no selected index in widget state.
- Keep More state entirely inside Flutter’s modal route. Do not add `/more`, a
  provider, or a shell field for open/closed state.

- [ ] **Step 8: Run shell tests and observe GREEN**

Run Step 5 again. Expected: adaptive, keyboard, semantics, target, and callback
tests pass.

---

### Task 5: Add typed routing, generated provider, and bootstrap test-first

**Files:**

- Create: `flutter/test/app/routing/app_router_test.dart`
- Create: `flutter/test/app/bootstrap/app_bootstrap_test.dart`
- Create: `flutter/lib/app/routing/app_routes.dart`
- Generate: `flutter/lib/app/routing/app_routes.g.dart`
- Create: `flutter/lib/app/routing/not_found_page.dart`
- Create: `flutter/lib/app/routing/app_router.dart`
- Generate: `flutter/lib/app/routing/app_router.g.dart`
- Create: `flutter/lib/app/bootstrap/argus_app.dart`
- Create: `flutter/lib/app/bootstrap/app_bootstrap.dart`
- Modify: `flutter/lib/main.dart`

**Interfaces:**

- Consumes: public `SettingsPage`, `ApplicationShell`, `ArgusTheme`, and the
  semantic destination mapper.
- Produces: `RootRoute`, `ApplicationShellRoute`, `SettingsRoute`,
  `appRouterProvider`, `ArgusApp`, `ArgusBootstrap`, and `bootstrapArgus()`.

- [ ] **Step 1: Write failing typed route and canonical routing tests**

Cover these observable contracts:

```dart
expect(const SettingsRoute().location, '/settings');
expect(destinationForUri(Uri.parse('/settings')), AppDestination.settings);
expect(
  destinationForUri(Uri.parse('/settings?source=test')),
  AppDestination.settings,
);
expect(destinationForUri(Uri.parse('/unknown')), isNull);
```

Pump a `MaterialApp.router` with a fresh production router and assert:

1. initial `/` settles at `/settings` and renders Settings;
2. direct `/settings` renders Settings;
3. `/missing` renders the controlled `Page not found` surface;
4. the not-found Settings action navigates to `/settings`;
5. production route definitions contain only the root redirect and Settings
   shell route, with no `/more`, Library, Collections, Jobs, Sources, Game
   Detail, or Diagnostics route.

Use the router’s `routeInformationProvider.value.uri` as the location
assertion; do not mirror location through Riverpod.

- [ ] **Step 2: Write failing root bootstrap tests**

Add widget tests asserting:

```dart
await tester.pumpWidget(const ArgusBootstrap());
expect(find.byType(ProviderScope), findsOneWidget);
await tester.pumpAndSettle();
expect(find.text('Settings'), findsOneWidget);
```

Add a provider override test using a real test-scoped `GoRouter` and
`appRouterProvider.overrideWithValue(testRouter)`, asserting `ArgusApp` renders
the test router’s page. This proves the generated provider is a dependency
seam without turning it into location state.

- [ ] **Step 3: Run focused routing/bootstrap tests and observe RED**

```bash
rtk test fvm flutter test --no-pub test/app/routing/app_router_test.dart test/app/bootstrap/app_bootstrap_test.dart
```

Expected: typed routes, provider, and bootstrap do not exist.

- [ ] **Step 4: Implement typed route source**

`app_routes.dart` uses `part 'app_routes.g.dart';` and defines:

```dart
/// Derives shell selection from the typed route location.
AppDestination? destinationForUri(Uri uri) {
  return uri.path == const SettingsRoute().location
      ? AppDestination.settings
      : null;
}

@TypedGoRoute<RootRoute>(path: '/')
class RootRoute extends GoRouteData with $RootRoute {
  const RootRoute();

  @override
  String? redirect(BuildContext context, GoRouterState state) {
    return const SettingsRoute().location;
  }
}

@TypedShellRoute<ApplicationShellRoute>(
  routes: <TypedRoute<RouteData>>[
    TypedGoRoute<SettingsRoute>(path: '/settings'),
  ],
)
class ApplicationShellRoute extends ShellRouteData {
  const ApplicationShellRoute();

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return ApplicationShell(
      currentDestination: destinationForUri(state.uri),
      onSettingsSelected: () => const SettingsRoute().go(context),
      child: navigator,
    );
  }
}

class SettingsRoute extends GoRouteData with $SettingsRoute {
  const SettingsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) {
    return const SettingsPage();
  }
}
```

Do not use `StatefulShellRoute`, branch data, a `/more` route, or any extra
production route.

- [ ] **Step 5: Implement the not-found surface**

Create a documented `AppNotFoundPage` with:

- `required String path` and `required VoidCallback onReturnToSettings`;
- a bounded, control-character-sanitized path summary (maximum 80 characters)
  with no query, fragment, exception, or generated-detail content;
- a `Scaffold`, semantic heading `Page not found`, safe text identifying the
  unmatched path, and a standard `FilledButton.icon` labeled
  `Go to Settings`;
- no raw exception or stack trace presentation.

- [ ] **Step 6: Implement the generated router provider**

`app_router.dart` uses `part 'app_router.g.dart';` and:

```dart
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    routes: $appRoutes,
    errorBuilder: (context, state) => AppNotFoundPage(
      path: state.uri.path,
      onReturnToSettings: () => const SettingsRoute().go(context),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
}
```

The provider contains no URI, selected index, redirect state, or readiness
state.

- [ ] **Step 7: Generate both source families**

Run from the repository root:

```bash
rtk proxy just generate
```

Expected: `app_routes.g.dart` and `app_router.g.dart` are generated adjacent to
their authored files and contain generator-provided markers.

- [ ] **Step 8: Implement root composition and thin entry point**

`ArgusApp` watches `appRouterProvider` and builds:

```dart
MaterialApp.router(
  title: 'Argus ROM Toolkit',
  theme: ArgusTheme.light,
  darkTheme: ArgusTheme.dark,
  themeMode: ThemeMode.system,
  routerConfig: router,
)
```

`ArgusBootstrap` is exactly one `ProviderScope(child: ArgusApp())`.
`bootstrapArgus()` calls `runApp(const ArgusBootstrap())`.
`main.dart` becomes:

```dart
import 'package:argus/app/bootstrap/app_bootstrap.dart';

void main() => bootstrapArgus();
```

No readiness provider or startup model is added.

- [ ] **Step 9: Run routing/bootstrap tests and observe GREEN**

Run Step 3 again. Expected: all route, sparse-graph, provider override, and
bootstrap tests pass.

---

### Task 6: Prove route identity, accessibility, and architecture boundaries

**Files:**

- Extend: `flutter/test/app/routing/app_router_test.dart`
- Extend: `flutter/test/app/shell/application_shell_test.dart`
- Extend: `flutter/test/core/design_system/argus_theme_test.dart`
- Create: `flutter/test/architecture/architecture_boundaries_test.dart`

**Interfaces:**

- Consumes: the complete production Flutter source graph.
- Produces: deterministic evidence for resize identity, keyboard/semantics/text
  scale, generated provider discipline, and allowed import directions.

- [ ] **Step 1: Add the failing resize identity test**

Pump production `ArgusApp` at width `480`, settle on `/settings`, then resize
the test view successively to `720`, `1024`, and `1440`. After every resize,
assert:

```dart
expect(router.routeInformationProvider.value.uri.path, '/settings');
expect(find.text('Settings'), findsOneWidget);
```

Also assert the correct shell key at every class. The test must reuse the same
router instance throughout.

- [ ] **Step 2: Add representative production-shell text-scale tests**

For Compact `480` and wide `1440`, pump the real routed shell at text scales
`1.0` and `2.0`, assert Settings and required More/wide navigation actions
remain present, and assert `tester.takeException()` is null.

Also pump a real `ApplicationShell` plus `SettingsPage` surface independently
with `ArgusTheme.light` and `ArgusTheme.dark`, enable semantics, and await
Flutter's `meetsGuideline(textContrastGuideline)` for each theme. Dispose each
semantics handle explicitly after the asynchronous guideline evaluation.

- [ ] **Step 3: Run focused tests and confirm any missing behavior fails**

```bash
rtk test fvm flutter test --no-pub test/app/routing/app_router_test.dart test/app/shell/application_shell_test.dart
```

Expected: any uncovered resize or scale defect fails before correction.

- [ ] **Step 4: Make only the minimal layout corrections needed for GREEN**

Allowed corrections include scrollability, flexible layout, safe-area usage,
and semantic Material configuration. Do not add alternate route graphs,
selected state, platform checks, custom focus infrastructure, or production
test seams.

- [ ] **Step 5: Write focused architecture boundary tests**

Use `dart:io` to enumerate authored production `.dart` files under `lib/`,
excluding `.g.dart`. Add deterministic checks that:

1. `main.dart` delegates to `bootstrapArgus` and contains no `ProviderScope`,
   `MaterialApp`, `GoRouter`, or feature import;
2. exactly one authored production file contains `ProviderScope(` and it is
   `app/bootstrap/app_bootstrap.dart`;
3. every authored `@riverpod`/`@Riverpod` file has an adjacent `part
   '<basename>.g.dart'` and generated file;
4. `core/responsive` imports no `app`, `features`, Riverpod, `go_router`,
   bridge, client, Rust, or SQLite concept;
5. `core/design_system` imports no `app`, `features`, bridge, client,
   repository, Riverpod, Rust, or SQLite concept;
6. feature files do not import `app/routing` or own `GoRouter`;
7. no production file outside `app/routing/app_routes.dart` contains raw
   `'/settings'` or any `'/more'` route construction;
8. no production source contains `StatefulShellRoute`, generated FRB imports,
   `ArgusClient`, SQLite, `isDesktop`, `isTablet`, `isPhone`, fake future route
   names, or future-feature directories;
9. exact breakpoint literals `600`, `840`, and `1200` occur only in
   `core/responsive/window_size_class.dart` among production Dart files;
10. `ThemeData(` production construction occurs only in
    `core/design_system/argus_theme.dart`;
11. `features/settings/settings.dart` exports the page without exporting a
    sibling feature-private `src` path to any consumer.

These tests intentionally inspect architecture source boundaries; ordinary
behavior remains covered through real widgets and routers.

- [ ] **Step 6: Run architecture tests and observe RED if a boundary leaks**

```bash
rtk test fvm flutter test --no-pub test/architecture/architecture_boundaries_test.dart
```

Expected: failures identify the exact violating file and rule.

- [ ] **Step 7: Correct only real boundary violations and rerun GREEN**

Run Step 6 again. Expected: all focused architecture rules pass without broad
analyzer exclusions or a third-party architecture framework.

---

### Task 7: Verify generation drift behavior and complete repository checks

**Files:**

- Temporarily modify and restore authored generator input during drift probes.
- Create at completion:
  `.chatgpt/codex-runs/2026-08-13T002300Z-phase-000-slice-004-flutter-bootstrap-static-shell/RESULT.md`

**Interfaces:**

- Consumes: canonical Just recipes and the full Rust and Flutter verification
  suites.
- Produces: direct evidence that generated tracked and untracked drift both
  fail, plus the task result contract.

- [ ] **Step 1: Prove changed registered generated output fails**

Temporarily change the authored `SettingsRoute` path from `/settings` to
`/settings-probe` using `apply_patch`. Run:

```bash
rtk proxy just check-generated
```

Expected: FAIL after generation because `app_routes.g.dart` differs from its
pre-generation snapshot. Restore the authored path to `/settings` with
`apply_patch`, then run `rtk proxy just generate` to restore generated output.
Do not edit the generated file directly.

- [ ] **Step 2: Prove unexpected untracked generated output fails**

Create a temporary authored input
`flutter/lib/app/routing/generated_drift_probe.dart` with a `part` directive
and one `@riverpod` function. Run:

```bash
rtk proxy just check-generated
```

Expected: FAIL and report
`flutter/lib/app/routing/generated_drift_probe.g.dart` as unexpected untracked
generated source. Delete the temporary authored input with `apply_patch`, run
`rtk proxy just generate`, and confirm build_runner removes its generated
output. Do not stage either probe file.

- [ ] **Step 3: Verify the canonical generated state passes**

```bash
rtk proxy just check-generated
```

Expected: PASS because each registered output is byte-identical before and
after regeneration and no unexpected generated output exists. No Git staging or
other Git mutation is performed.

- [ ] **Step 4: Run requested formatting, analysis, and Flutter tests**

Run each independently and record its exact status:

```bash
rtk proxy fvm flutter pub get
rtk proxy just generate
rtk proxy just check-generated
rtk proxy fvm dart format --output=none --set-exit-if-changed .
rtk proxy fvm flutter analyze --no-pub
rtk test fvm flutter test --no-pub
```

The FVM commands run from `flutter/`; Just commands run from repository root.
Expected: every command exits 0 with no analyzer diagnostics, format changes,
or test failures.

- [ ] **Step 5: Run the full repository quality gate**

From the repository root:

```bash
rtk test just check
```

Expected: generated-source verification, Dart/Rust format, Flutter analyze,
Rust clippy, ShellCheck, architecture checks, all Rust tests, and all Flutter
tests pass without modifying Rust behavior.

- [ ] **Step 6: Run final hygiene and Git-state checks**

```bash
rtk git diff --check
rtk git status --short --branch
rtk proxy rg -n 'TODO|todo|debugPrint\(|print\(|StatefulShellRoute|/more|ArgusClient|flutter_rust_bridge' flutter/lib flutter/test
```

Expected: no whitespace failures; no production hygiene violation; no Git
staging or other Git mutation; no unrelated work is modified.

- [ ] **Step 7: Write the required RESULT.md**

Use the prompt’s fifteen numbered sections exactly:

1. Changed paths
2. Implemented behavior
3. Bootstrap/provider contracts
4. Routing contracts
5. Responsive/shell behavior
6. Design-system behavior
7. Settings surface
8. Tests added
9. Generated source
10. Verification
11. Manual verification
12. Deviations
13. Documentation impact
14. Git state
15. Next-slice boundary

Report every requested command as PASS, FAIL, NOT RUN, or BLOCKED with a
factual note. Explicitly report keyboard-only, screen-reader, Light/Dark,
resize, and other manual checks as NOT RUN unless actually performed. State
that Compact uses More, production has only Settings, no test-only extra
destination was needed unless that fact changes, and all Slice 005+ behavior
remains deferred.

- [ ] **Step 8: Apply verification-before-completion**

Re-read this plan, the approved design, and the run prompt acceptance criteria.
Map each implemented requirement to fresh test or inspection evidence. Do not
claim completion for any requirement without the corresponding command output
from this execution turn.

---

## Plan self-review

1. **Spec coverage:** All seven user-preserved invariants, forty prompt test
   requirements, the SPEC-FE-007 Light/Dark representative-surface contrast
   obligation, generated-source behavior, accessibility baseline,
   architecture boundaries, and result-report sections have an implementing
   task or explicit verification step.
2. **Placeholder scan:** The plan contains no `TBD`, unresolved implementation
   instruction, or delegated “similar” step. Temporary generator probes have
   exact creation, expected failure, restoration, and cleanup behavior.
3. **Type consistency:** `AppDestination.settings`, `destinationForUri`,
   `ApplicationShell`, `SettingsRoute`, `appRouterProvider`, `ArgusApp`, and
   `ArgusBootstrap` use the same names and ownership in every task.
4. **Scope check:** No Rust, bridge, client, startup, recovery, diagnostics,
   persisted appearance, future feature, platform runner, script, CI, or
   governed-document implementation is included.
5. **Git check:** No staging, commit, amend, reset, restore, clean, or push
   operation appears. Generated verification uses temporary byte/existence
   snapshots and filesystem enumeration only.
