# Phase 000 Slice 007 — Immediate Theme Persistence Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the real Phase 000 appearance workflow so Argus loads authoritative appearance settings before first-shell presentation, persists Theme Mode changes immediately through `SettingsApi`, and applies only query-confirmed theme state at the root.

**Architecture:** The Settings feature owns one keep-alive `AppearanceSettingsController` whose outer `AsyncValue` represents whether usable appearance authority exists and whose loaded state separates `confirmed`, `presented`, save-operation, and synchronization semantics. App composition injects only the focused `SettingsApi` plus a typed ready-runtime context into that feature; app-owned derived providers combine backend readiness with appearance authority and project only `confirmed.themeMode` into `MaterialApp.themeMode`. The existing startup gate remains the FE-005 backend gate, while a separate nested appearance gate blocks the routed shell only until the first authoritative appearance snapshot exists.

**Tech Stack:** Flutter 3.44.7, Dart 3.12.x, flutter_riverpod 3.3.2, riverpod_annotation 4.0.3 / riverpod_generator 4.0.4, Freezed 3.2.6-dev.1, Material 3, existing pure-Dart `SettingsApi` / `AppearanceSettings` / `ThemeMode` / `ClientFailure` contracts, flutter_test, FVM, build_runner, and the existing `just` / `rtk` workflow.

**Re-evaluation baseline:** Revalidated on 2026-08-13 against clean `main` at HEAD `e24c2886a9ccdbaa260bcdc2dcbc5249feaabfe5` after Slice 006 lifecycle teardown completion. `PHASE-000` and `SPEC-FE-006` are already **Ready for Implementation** and contain the approved design.

## Global Constraints

- Implement only `SLICE-P00-007 — Immediate Theme Persistence Workflow`.
- **Defer to Slice 008:** `AppearanceSettingsChanged` consumption, event-triggered refresh/coalescing, event-during-read/save handling, sequence-gap recovery, and reconnect recovery. Slice 007 must not subscribe to `EventsApi`.
- **Defer to Slice 009:** real process-restart restoration proof, final Phase 000 canonical demonstration, and restart hardening.
- Do not modify Rust crates, bridge DTO/API shape, SQLite persistence, or `ArgusClient` request semantics. Slice 005 already exposes the required focused `SettingsApi`.
- Rust remains authoritative. Submitted mutation objects and event payloads never become frontend authority.
- Backend `Ready` is necessary but not sufficient for first-shell presentation. Initial `getAppearanceSettings()` must succeed first.
- Initial read failure never fabricates `System`. Bootstrap `ThemeMode.system` is presentation scaffolding only while the normal shell is gated.
- One application-lifetime appearance controller owns frontend appearance state. Do not add a mutable root theme cache or widget-local persisted authority.
- `confirmed` changes only from successful authoritative reads. `presented` may differ only for an explicit local pending selection.
- Root `MaterialApp.themeMode` derives only from `confirmed.themeMode`.
- Writes are single-flight. New mutation is admitted only while synchronization is proven `synchronized`.
- Successful update acknowledgement always requires an authoritative read before promotion.
- `ApplicationFailure` is definite: rollback `presented` to `confirmed`, preserve root theme, expose local failure, and do not replay automatically.
- `TransportFailure` is ambiguous: never replay automatically; reconcile through focused read. If the read fails, retain last-known confirmed rendering, mark synchronization uncertain, and block new mutation.
- Update success followed by read failure is `committedButUnreconciled`; never promote the requested value without a confirming query.
- Runtime-generation replacement invalidates synchronization confidence. Runtime A completions cannot publish after Runtime B becomes current.
- A loaded last-known theme remains renderable while runtime/appearance synchronization is being re-established; later uncertainty does not itself revoke an already admitted shell.
- `ThemeMode.system` follows platform brightness without settings I/O caused solely by brightness changes.
- Settings exposes exactly one Phase 000 Appearance section with System / Light / Dark and no Save/Apply button.
- Feature application code may import public `core/client/client.dart` but not `app/`, Startup internals, generated bridge code, FRB, SQLite, `BuildContext`, or `go_router`.
- Cross-feature/runtime composition occurs in `app/bootstrap`; Settings receives injected typed seams instead of importing Startup state/controllers.
- Do not add dependencies.
- Async/race tests use controlled completers/provider transitions and state listeners, never elapsed-time sleeps.
- Generated output stays generator-owned and must be added to the existing strict generated-file registry.
- Preserve Slice 001–006 behavior, especially `StartupGate` semantics: it remains the backend gate and still exposes its direct child at backend `Ready`.
- Do not stage, commit, amend, reset, restore, clean, or push unless Daniel explicitly authorizes that Git operation.

---

## File Map

### Production source

- Modify `flutter/lib/app/bootstrap/app_bootstrap.dart` — inject Settings API/runtime-context seams from app composition.
- Modify `flutter/lib/app/bootstrap/argus_app.dart` — apply confirmed root theme and nest appearance admission inside `StartupGate`.
- Create `flutter/lib/app/bootstrap/application_presentation.dart` + generated `.g.dart` — combined presentation readiness and root-theme projection.
- Create `flutter/lib/app/bootstrap/application_presentation_gate.dart` — appearance initialization/failure/ready gate.
- Modify `flutter/lib/features/startup/application/app_readiness.dart` + generated `.g.dart` — add narrow ready-runtime identity projection without changing `AppReadiness`.
- Modify `flutter/lib/features/startup/startup.dart` — export that projection for app composition.
- Create `flutter/lib/features/settings/settings_composition.dart` — narrow app-composition entry point.
- Create `flutter/lib/features/settings/application/appearance_settings_dependencies.dart` + generated `.g.dart` — focused injected dependencies.
- Create `flutter/lib/features/settings/application/appearance_settings_state.dart` + generated `.freezed.dart` — runtime/save/synchronization state vocabulary.
- Create `flutter/lib/features/settings/application/appearance_settings_controller.dart` + generated `.g.dart` — one authoritative state machine.
- Move `flutter/lib/features/settings/src/settings_page.dart` to `flutter/lib/features/settings/presentation/settings_page.dart`.
- Create `flutter/lib/features/settings/presentation/appearance_initialization_view.dart`.
- Create `flutter/lib/features/settings/presentation/appearance_messages.dart`.
- Create `flutter/lib/features/settings/presentation/theme_mode_control.dart`.
- Modify `flutter/lib/features/settings/settings.dart`.
- Modify `justfile` to register only the new generated outputs.

### Tests

- Create `flutter/test/features/settings/appearance_settings_state_test.dart`.
- Create `flutter/test/features/settings/appearance_settings_test_fakes.dart`.
- Create `flutter/test/features/settings/appearance_settings_controller_test.dart`.
- Replace/extend `flutter/test/features/settings/settings_page_test.dart`.
- Create `flutter/test/app/bootstrap/application_presentation_test.dart`.
- Modify `flutter/test/app/bootstrap/app_bootstrap_test.dart`.
- Extend the existing startup readiness/provider tests for ready-runtime identity.
- Modify `flutter/test/architecture/architecture_boundaries_test.dart`.

No Cargo, Rust source, bridge source, `pubspec`, route graph, platform runner, or governed-specification change is expected.

---

### Task 1: Add Appearance State Vocabulary and Feature Dependency Seams

**Files:**
- Create: `flutter/lib/features/settings/application/appearance_settings_state.dart`
- Generate: `flutter/lib/features/settings/application/appearance_settings_state.freezed.dart`
- Create: `flutter/lib/features/settings/application/appearance_settings_dependencies.dart`
- Generate: `flutter/lib/features/settings/application/appearance_settings_dependencies.g.dart`
- Create: `flutter/test/features/settings/appearance_settings_state_test.dart`

**Interfaces:**
- Consumes public client types only.
- Produces `AppearanceRuntimeContext`, `AppearanceSettingsState`, `AppearanceSaveOperation`, `AppearanceSynchronization`, `appearanceSettingsApiProvider`, and `appearanceRuntimeContextProvider`.

- [ ] **Step 1: Write the failing immutable-state tests**

```dart
const confirmed = AppearanceSettings(themeMode: ThemeMode.light);
const presented = AppearanceSettings(themeMode: ThemeMode.dark);
const state = AppearanceSettingsState.ready(
  confirmed: confirmed,
  presented: presented,
  saveOperation: AppearanceSaveOperation.saving(requested: presented),
  synchronization: AppearanceSynchronization.synchronized(),
);
expect(state.confirmed, confirmed);
expect(state.presented, presented);
expect(
  const AppearanceRuntimeContext.ready(
    runtimeInstanceId: RuntimeInstanceId('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
  ),
  isA<AppearanceRuntimeContextReady>(),
);
```

- [ ] **Step 2: Run the focused test and confirm RED**

From `flutter/`:

```bash
rtk test fvm flutter test --no-pub test/features/settings/appearance_settings_state_test.dart
```

Expected: missing production types.

- [ ] **Step 3: Implement the exact state vocabulary**

```dart
@freezed
sealed class AppearanceRuntimeContext with _$AppearanceRuntimeContext {
  const factory AppearanceRuntimeContext.preReady() =
      AppearanceRuntimeContextPreReady;
  const factory AppearanceRuntimeContext.ready({
    required RuntimeInstanceId runtimeInstanceId,
  }) = AppearanceRuntimeContextReady;
}

@freezed
sealed class AppearanceSaveOperation with _$AppearanceSaveOperation {
  const factory AppearanceSaveOperation.idle() = AppearanceSaveOperationIdle;
  const factory AppearanceSaveOperation.saving({
    required AppearanceSettings requested,
  }) = AppearanceSaveOperationSaving;
  const factory AppearanceSaveOperation.failed({
    required ApplicationFailure failure,
  }) = AppearanceSaveOperationFailed;
  const factory AppearanceSaveOperation.outcomeUnknown({
    required TransportFailure failure,
  }) = AppearanceSaveOperationOutcomeUnknown;
  const factory AppearanceSaveOperation.committedButUnreconciled({
    required ClientFailure failure,
  }) = AppearanceSaveOperationCommittedButUnreconciled;
}

@freezed
sealed class AppearanceSynchronization with _$AppearanceSynchronization {
  const factory AppearanceSynchronization.synchronized() =
      AppearanceSynchronizationSynchronized;
  const factory AppearanceSynchronization.refreshing() =
      AppearanceSynchronizationRefreshing;
  const factory AppearanceSynchronization.uncertain({
    required ClientFailure failure,
  }) = AppearanceSynchronizationUncertain;
}

@freezed
sealed class AppearanceSettingsState with _$AppearanceSettingsState {
  const factory AppearanceSettingsState.ready({
    required AppearanceSettings confirmed,
    required AppearanceSettings presented,
    required AppearanceSaveOperation saveOperation,
    required AppearanceSynchronization synchronization,
  }) = AppearanceSettingsStateReady;
}
```

Do not add persistence IDs, timestamps, wire strings, event sequence values, or a duplicate theme model.

- [ ] **Step 4: Add the feature-owned injectable dependencies**

```dart
@Riverpod(keepAlive: true)
SettingsApi appearanceSettingsApi(Ref ref) {
  throw StateError(
    'appearanceSettingsApiProvider must be supplied by app composition',
  );
}

@Riverpod(keepAlive: true)
AppearanceRuntimeContext appearanceRuntimeContext(Ref ref) =>
    const AppearanceRuntimeContext.preReady();
```

These are DI seams only; they contain no root-client construction, retries, caching, or workflow.

- [ ] **Step 5: Generate and rerun the state test GREEN**

```bash
rtk proxy just generate
cd flutter
rtk test fvm flutter test --no-pub test/features/settings/appearance_settings_state_test.dart
```

`check-generated` is deferred until Task 6 registers the complete new generated set.

---

### Task 2: Implement Initial Authoritative Loading and Runtime-Generation Safety

**Files:**
- Create: `flutter/lib/features/settings/application/appearance_settings_controller.dart`
- Generate: `flutter/lib/features/settings/application/appearance_settings_controller.g.dart`
- Create: `flutter/test/features/settings/appearance_settings_test_fakes.dart`
- Create: `flutter/test/features/settings/appearance_settings_controller_test.dart`

**Interfaces:**
- Consumes only the two injected feature dependency providers.
- Produces keep-alive `appearanceSettingsControllerProvider` with outer type `AsyncValue<AppearanceSettingsState>` and read-only recovery action `retryAuthoritativeRead()`.

- [ ] **Step 1: Create deterministic focused fakes**

`FakeSettingsApi` queues a new `Completer<AppearanceSettings>` for every read and records `{settings, Completer<void>}` for each update. Add `appearanceTestId(String fill) => RuntimeInstanceId(fill * 32)` and a test-only Riverpod notifier that can transition the injected `AppearanceRuntimeContext` synchronously.

```dart
@override
Future<AppearanceSettings> getAppearanceSettings() {
  final completer = Completer<AppearanceSettings>();
  readRequests.add(completer);
  return completer.future;
}

@override
Future<void> updateAppearanceSettings(AppearanceSettings settings) {
  final completer = Completer<void>();
  updateRequests.add((settings: settings, completer: completer));
  return completer.future;
}
```

- [ ] **Step 2: Write failing initial-load tests**

Cover separately:

```text
preReady → zero reads
Runtime A ready → exactly one read + AsyncLoading
read System/Light/Dark → AsyncData; confirmed == presented == query result; idle; synchronized
initial ApplicationFailure/TransportFailure → AsyncError with same typed ClientFailure; no fabricated System
```

Use a provider subscription/completer to await semantic state transitions; no timing delay.

- [ ] **Step 3: Write failing Runtime A/B stale-completion tests**

```text
A ready → read A starts
B ready before A completes → read B starts
A returns Dark → ignored
B returns Light → confirmed/presented Light
```

Also cover replacement after a loaded Dark snapshot: retain Dark renderability, mark synchronization refreshing, block mutation, read B, then adopt B's result.

- [ ] **Step 4: Run focused controller tests and confirm RED**

```bash
rtk test fvm flutter test --no-pub test/features/settings/appearance_settings_controller_test.dart
```

- [ ] **Step 5: Implement the controller's initial read/generation core**

Use a synchronous Riverpod notifier that returns `const AsyncLoading()` from `build()`, listens to `appearanceRuntimeContextProvider`, and privately tracks active runtime ID plus read/mutation tokens/in-flight flags.

```dart
@Riverpod(keepAlive: true)
class AppearanceSettingsController extends _$AppearanceSettingsController {
  RuntimeInstanceId? _activeRuntimeInstanceId;
  int _readToken = 0;
  int _mutationToken = 0;
  bool _readInFlight = false;
  bool _mutationInFlight = false;

  @override
  AsyncValue<AppearanceSettingsState> build() {
    ref.listen<AppearanceRuntimeContext>(
      appearanceRuntimeContextProvider,
      (previous, next) => unawaited(_adoptRuntimeContext(next)),
    );
    unawaited(_adoptRuntimeContext(ref.read(appearanceRuntimeContextProvider)));
    return const AsyncLoading();
  }
}
```

`preReady` invalidates current operation tokens. If no loaded snapshot exists, remain loading. If a loaded snapshot exists, retain `confirmed`, set `presented = confirmed`, reset save to idle, and mark synchronization `refreshing` so writes remain blocked until a current runtime exists.

A changed ready runtime ID invalidates all old completions and starts exactly one authoritative read. Initial read failure becomes outer `AsyncError(ClientFailure)`; replacement read failure after a loaded snapshot preserves the loaded state and becomes `uncertain(failure)`. Every completion checks captured runtime ID and token before publishing.

A successful authoritative read always publishes:

```dart
AppearanceSettingsState.ready(
  confirmed: authoritative,
  presented: authoritative,
  saveOperation: const AppearanceSaveOperation.idle(),
  synchronization: const AppearanceSynchronization.synchronized(),
)
```

- [ ] **Step 6: Add read-only retry**

`retryAuthoritativeRead()` issues no request without a ready runtime, coalesces with an existing read, maps outer error → loading → read, maps loaded uncertain → refreshing → read, and never calls `updateAppearanceSettings`.

- [ ] **Step 7: Generate and run initial/race coverage GREEN**

```bash
rtk proxy just generate
cd flutter
rtk test fvm flutter test --no-pub test/features/settings/appearance_settings_controller_test.dart
```

---

### Task 3: Add Immediate Single-Flight Mutation and Authoritative Reconciliation

**Files:**
- Modify: `flutter/lib/features/settings/application/appearance_settings_controller.dart`
- Extend: `flutter/test/features/settings/appearance_settings_controller_test.dart`

**Interfaces:**
- Produces `Future<void> selectThemeMode(ThemeMode value)` as the only Phase 000 appearance mutation intent.
- Mutation plus its required post-command read is one single-flight operation.

- [ ] **Step 1: Add failing pending/single-flight tests**

From confirmed Light, select Dark and hold the update open. Assert `presented = Dark`, `confirmed = Light`, save is `saving(Dark)`, synchronization remains synchronized, exactly one complete aggregate `AppearanceSettings(themeMode: dark)` is sent, and a second selection creates no second update. Selecting already-confirmed Light while idle performs no write.

- [ ] **Step 2: Add failing successful reconciliation tests**

```text
confirmed Light
select Dark
update success → Dark still not confirmed; exactly one read begins
read returns Dark → confirmed/presented Dark; idle; synchronized
```

Also submit Dark but return Light from the post-update read; Light must win.

- [ ] **Step 3: Add failing definite `ApplicationFailure` tests**

Assert rollback to confirmed Light, local `failed(applicationFailure)`, synchronized authority, no automatic read/retry, and a later different user selection remains admissible.

- [ ] **Step 4: Add failing ambiguous `TransportFailure` tests**

Assert no replay, presented returns to last-known confirmed, save becomes `outcomeUnknown(originalFailure)`, synchronization becomes refreshing, and exactly one read begins. A successful read adopts whatever it returns. A failed read retains last-known confirmed/presented, preserves the original ambiguous save failure, marks synchronization uncertain with the read failure, and blocks new mutation. Retry is read-only.

- [ ] **Step 5: Add failing update-success/read-failure tests**

Assert last-known confirmed/presented, `committedButUnreconciled(readFailure)`, synchronization uncertain, mutation blocked, and later read-only retry adopts only its returned value.

- [ ] **Step 6: Add a failing mutation/runtime-replacement race**

Start a Dark mutation under Runtime A, make Runtime B current before A's update or reconciliation settles, and prove all A-era completions are ignored. B must complete a fresh authoritative read before mutation is safe again.

- [ ] **Step 7: Run the expanded controller test and confirm RED**

```bash
rtk test fvm flutter test --no-pub test/features/settings/appearance_settings_controller_test.dart
```

- [ ] **Step 8: Implement explicit mutation admission/outcome branches**

Admission starts with:

```dart
final current = state.value;
if (current is! AppearanceSettingsStateReady ||
    _mutationInFlight ||
    _readInFlight ||
    current.synchronization is! AppearanceSynchronizationSynchronized) {
  return;
}
```

For a changed value, create the full desired aggregate from `current.confirmed.copyWith(themeMode: value)`, set `presented` to desired, mark `saving`, and invoke one update. Keep `_mutationInFlight` true through post-command reconciliation.

Outcome table:

| Outcome | Confirmed | Presented | Save | Sync | Next I/O |
|---|---|---|---|---|---|
| update success | unchanged | requested pending | saving | synchronized | mandatory read |
| update `ApplicationFailure` | unchanged | rollback confirmed | failed | synchronized | none |
| update `TransportFailure` | unchanged | rollback confirmed | outcomeUnknown | refreshing | mandatory read, never replay |
| success + read failure | last-known | last-known | committedButUnreconciled | uncertain | user read-only retry |
| ambiguous + read failure | last-known | last-known | outcomeUnknown(original mutation failure) | uncertain(read failure) | user read-only retry |
| reconciliation success | query result | query result | idle | synchronized | none |

- [ ] **Step 9: Run controller coverage GREEN**

Run Step 7 again. Every mutation, rollback, ambiguity, reconciliation, blocking, and stale-generation case must pass deterministically.

---

### Task 4: Compose Runtime Identity, First-Shell Appearance Admission, and Root Theme

**Files:**
- Modify: `flutter/lib/features/startup/application/app_readiness.dart`
- Regenerate: `flutter/lib/features/startup/application/app_readiness.g.dart`
- Modify: `flutter/lib/features/startup/startup.dart`
- Create: `flutter/lib/features/settings/settings_composition.dart`
- Create: `flutter/lib/features/settings/presentation/appearance_messages.dart`
- Create: `flutter/lib/features/settings/presentation/appearance_initialization_view.dart`
- Create: `flutter/lib/app/bootstrap/application_presentation.dart`
- Generate: `flutter/lib/app/bootstrap/application_presentation.g.dart`
- Create: `flutter/lib/app/bootstrap/application_presentation_gate.dart`
- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart`
- Modify: `flutter/lib/app/bootstrap/argus_app.dart`
- Create: `flutter/test/app/bootstrap/application_presentation_test.dart`
- Modify: `flutter/test/app/bootstrap/app_bootstrap_test.dart`
- Extend the existing startup readiness/provider test owner

**Interfaces:**
- Produces `readyRuntimeInstanceIdProvider`, `ApplicationPresentationReadiness`, `applicationPresentationReadinessProvider`, `rootThemeModeProvider`, and `ApplicationPresentationGate`.
- App composition supplies the Settings feature with the current root client's `settings` capability and a narrow typed runtime context. Settings never imports Startup or `app/`.

- [ ] **Step 1: Add failing ready-runtime identity tests**

Verify the startup projection exactly:

```text
Uninitialized / Starting / StartupFailed / RuntimeUnavailable / ShuttingDown / Stopped
→ readyRuntimeInstanceIdProvider == null

Ready(runtimeInstanceId: A)
→ readyRuntimeInstanceIdProvider == A
```

This does not change `AppReadiness` or `StartupGate` behavior.

- [ ] **Step 2: Implement and export `readyRuntimeInstanceIdProvider`**

Add alongside the existing app-readiness projection:

```dart
@Riverpod(keepAlive: true)
RuntimeInstanceId? readyRuntimeInstanceId(Ref ref) {
  final value = ref.watch(startupControllerProvider).value;
  return switch (value) {
    StartupStateReady(:final runtimeInstanceId) => runtimeInstanceId,
    _ => null,
  };
}
```

Export the provider from `features/startup/startup.dart`. Do not expose Startup internals to Settings.

- [ ] **Step 3: Create the narrow Settings composition entry point**

`features/settings/settings_composition.dart` exports only app-composition contracts:

```dart
export 'application/appearance_settings_controller.dart'
    show AppearanceSettingsController, appearanceSettingsControllerProvider;
export 'application/appearance_settings_dependencies.dart'
    show appearanceRuntimeContextProvider, appearanceSettingsApiProvider;
export 'application/appearance_settings_state.dart'
    show
        AppearanceRuntimeContext,
        AppearanceRuntimeContextPreReady,
        AppearanceRuntimeContextReady,
        AppearanceSettingsState,
        AppearanceSettingsStateReady;
export 'presentation/appearance_initialization_view.dart'
    show AppearanceInitializationFailureView, AppearanceInitializationView;
```

Do not export `ThemeModeControl` or feature-private save/synchronization UI details through this composition entry point.

- [ ] **Step 4: Write failing app-presentation admission tests**

Using controlled fake backend/bootstrap and focused Settings dependencies, prove:

```text
backend not Ready → preReady
backend Ready + appearance read pending → appearanceInitializing; shell absent
backend Ready + initial appearance read failure → appearanceUnavailable; shell absent
backend Ready + authoritative appearance snapshot → ready; shell present
```

Also prove intended `/settings` remains the router location throughout appearance initialization/failure/retry; the gate creates no route/history entry.

- [ ] **Step 5: Add the first-normal-shell Dark regression test**

Hold the initial appearance read pending and assert the normal Settings shell is absent. Complete it with authoritative Dark. On the first frame where the normal Settings page becomes visible:

```dart
expect(
  Theme.of(tester.element(find.text('Settings'))).brightness,
  Brightness.dark,
);
```

A normal-shell frame rendered under the bootstrap System theme is a failure.

- [ ] **Step 6: Add the pending-root-authority regression test**

After authoritative Light admits the shell, begin a pending Dark mutation and hold the update/reconciliation. The Settings control may present Dark, but the root theme must remain Light. Only a post-mutation authoritative read returning Dark may change root theme to Dark.

- [ ] **Step 7: Add initial appearance failure Retry/Exit tests**

The initial appearance failure surface must:

- use bounded user-safe copy from typed `ClientFailure`, never `toString()`/raw backend text;
- call only `retryAuthoritativeRead()` for Retry;
- perform no startup retry/reset and no appearance mutation for Retry;
- receive Exit from app composition through the existing application termination seam;
- keep `RuntimeApi` out of the appearance controller.

- [ ] **Step 8: Implement Settings-owned initialization/failure views**

Use safe local copy, for example:

```dart
String appearanceLoadFailureMessage(ClientFailure failure) => switch (failure) {
  TransportFailure() =>
    'Argus could not reach its runtime to load appearance settings.',
  ApplicationFailure() => 'Argus could not load appearance settings.',
};
```

`AppearanceInitializationView` is a stable centered progress surface. `AppearanceInitializationFailureView` receives `ClientFailure failure`, `VoidCallback onRetry`, and `VoidCallback onExit`; it owns no client or lifecycle dependency.

- [ ] **Step 9: Implement pure combined presentation/root-theme providers**

Create `application_presentation.dart`:

```dart
import 'package:argus/core/client/client.dart' as client;
import 'package:argus/features/settings/settings_composition.dart';
import 'package:argus/features/startup/startup.dart';
import 'package:flutter/material.dart' as material;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'application_presentation.g.dart';

enum ApplicationPresentationReadiness {
  preReady,
  appearanceInitializing,
  appearanceUnavailable,
  ready,
}

@Riverpod(keepAlive: true)
ApplicationPresentationReadiness applicationPresentationReadiness(Ref ref) {
  if (ref.watch(appReadinessProvider) != AppReadiness.ready) {
    return ApplicationPresentationReadiness.preReady;
  }
  return ref.watch(appearanceSettingsControllerProvider).when(
    data: (_) => ApplicationPresentationReadiness.ready,
    error: (_, _) => ApplicationPresentationReadiness.appearanceUnavailable,
    loading: () => ApplicationPresentationReadiness.appearanceInitializing,
  );
}

@Riverpod(keepAlive: true)
material.ThemeMode? rootThemeMode(Ref ref) {
  final loaded = ref.watch(appearanceSettingsControllerProvider).value;
  final mode = switch (loaded) {
    AppearanceSettingsStateReady(:final confirmed) => confirmed.themeMode,
    _ => null,
  };
  return switch (mode) {
    client.ThemeMode.system => material.ThemeMode.system,
    client.ThemeMode.light => material.ThemeMode.light,
    client.ThemeMode.dark => material.ThemeMode.dark,
    null => null,
  };
}
```

These providers own no mutable theme state.

- [ ] **Step 10: Inject production dependencies at the existing single root scope**

Modify `ArgusBootstrap` so its existing `ProviderScope` overrides:

```dart
appearanceSettingsApiProvider.overrideWith(
  (ref) => ref.watch(argusClientProvider).settings,
),
appearanceRuntimeContextProvider.overrideWith((ref) {
  final runtimeInstanceId = ref.watch(readyRuntimeInstanceIdProvider);
  return runtimeInstanceId == null
      ? const AppearanceRuntimeContext.preReady()
      : AppearanceRuntimeContext.ready(
          runtimeInstanceId: runtimeInstanceId,
        );
}),
```

Use the pinned Riverpod override type/API. Do not create another root scope or service locator.

- [ ] **Step 11: Implement the nested appearance gate and root theme**

`ApplicationPresentationGate` maps:

```text
preReady → no routed child; outer StartupGate owns visible backend surface
appearanceInitializing → AppearanceInitializationView
appearanceUnavailable → typed AppearanceInitializationFailureView
ready → routed child
```

Update `ArgusApp` semantically to:

```dart
final authoritativeThemeMode = ref.watch(rootThemeModeProvider);

MaterialApp.router(
  theme: ArgusTheme.light,
  darkTheme: ArgusTheme.dark,
  themeMode: authoritativeThemeMode ?? ThemeMode.system,
  builder: (context, child) => StartupGate(
    child: ApplicationPresentationGate(child: child!),
  ),
  routerConfig: router,
)
```

The fallback `ThemeMode.system` is bootstrap presentation only because the normal child remains gated until authority exists.

- [ ] **Step 12: Run focused app/startup integration GREEN**

Update the current app-bootstrap test so backend Ready plus an authoritative appearance read are both required before Settings appears. Then run:

```bash
cd flutter
rtk test fvm flutter test --no-pub \
  test/app/bootstrap/app_bootstrap_test.dart \
  test/app/bootstrap/application_presentation_test.dart \
  test/features/startup/startup_gate_test.dart
```

Expected: app-level shell waits for appearance; `StartupGate`'s own child-at-Ready contract still passes; first normal Dark shell is Dark.

---

### Task 5: Replace the Static Settings Placeholder with the Real Accessible Theme Control

**Files:**
- Move: `flutter/lib/features/settings/src/settings_page.dart` → `flutter/lib/features/settings/presentation/settings_page.dart`
- Create: `flutter/lib/features/settings/presentation/theme_mode_control.dart`
- Modify: `flutter/lib/features/settings/settings.dart`
- Replace/extend: `flutter/test/features/settings/settings_page_test.dart`

**Interfaces:**
- Presentation watches `appearanceSettingsControllerProvider` and invokes only `selectThemeMode` / `retryAuthoritativeRead`.
- `ThemeModeControl` consumes loaded feature state and callbacks; it never calls client/bridge APIs directly.

- [ ] **Step 1: Rewrite the existing Settings test for the real Phase 000 screen and confirm RED**

After an authoritative Light load, assert:

```text
Settings heading
Appearance section
Theme Mode group
System / Light / Dark exactly once
Light selected
System helper explains OS-following behavior
old placeholder sentence absent
no Apply button
no Save button
```

Run:

```bash
rtk test fvm flutter test --no-pub test/features/settings/settings_page_test.dart
```

Expected: RED against the current Slice 004 static page.

- [ ] **Step 2: Add failing optimistic pending/single-flight widget tests**

Tap Dark and keep the fake update unresolved. Assert Dark is immediately presented selected, a visible/semantic `Saving appearance settings…` status exists, further selection cannot dispatch a second mutation, and no success-toast behavior is required. Complete update + authoritative read Dark and assert pending status clears.

- [ ] **Step 3: Add failing definite-failure rollback tests**

From Light, select Dark and fail update with `ApplicationFailure`. Assert Light is selected again, local save error is associated with Theme Mode, raw exception/code/trace text is absent, and another selection is possible because authority remains synchronized.

- [ ] **Step 4: Add failing synchronization-uncertain tests**

Drive either ambiguous-update/read-failure or success/read-failure. Assert last-known confirmed selection is shown, durable text states that the current value cannot be confirmed, mutations are blocked, a visible Retry/Refresh action is keyboard reachable, the action issues only a read, and successful refresh re-enables mutation.

- [ ] **Step 5: Add failing accessibility/responsive tests**

Cover keyboard focus/selection, selected-state semantics, discoverable System explanation, non-color pending/failure/uncertainty feedback, practical standard Material targets, and Compact `480` plus Large `1440` rendering at text scale `2.0` without overflow.

- [ ] **Step 6: Move the Settings page into `presentation/` and update the public page barrel**

`features/settings/settings.dart` becomes:

```dart
export 'presentation/settings_page.dart' show SettingsPage;
```

Do not retain the old `src/settings_page.dart` duplicate.

- [ ] **Step 7: Implement the real page and Theme Mode control**

Preserve existing responsive gutter/readable-width behavior. Replace the temporary paragraph with one Appearance section. Use standard Material single-selection controls from the pinned Flutter SDK; do not build a pointer-only custom control.

Required user-facing labels/copy include:

```text
Theme Mode
System
Follows your operating system appearance.
Light
Dark
Saving appearance settings…
```

When synchronization is uncertain, show durable local copy equivalent to:

```text
Argus could not confirm the current appearance setting. The displayed selection is the last known value.
```

and a read-only recovery action.

- [ ] **Step 8: Wire user intent only through the controller**

Admitted selection calls:

```dart
ref
    .read(appearanceSettingsControllerProvider.notifier)
    .selectThemeMode(value);
```

Presentation never calls `SettingsApi` directly and never mutates root theme state.

- [ ] **Step 9: Run Settings widget coverage GREEN**

```bash
rtk test fvm flutter test --no-pub test/features/settings/settings_page_test.dart
```

Expected: selection, pending, rollback, uncertainty, keyboard, semantics, responsive layout, and 200% text-scale cases all pass.

---

### Task 6: Prove System Brightness Semantics and Harden Architecture/Generated Boundaries

**Files:**
- Extend: `flutter/test/app/bootstrap/application_presentation_test.dart`
- Modify: `flutter/test/architecture/architecture_boundaries_test.dart`
- Modify: `justfile`
- Regenerate all Slice 007 generated output canonically

**Interfaces:**
- Proves System follows platform brightness without settings traffic, generated output is fully registered, routing remains workflow-free, and Slice 008/009 behavior did not leak into this slice.

- [ ] **Step 1: Add the System platform-brightness test**

Load authoritative `ThemeMode.system`, admit the shell, record fake Settings API counts, change test platform brightness Light → Dark through Flutter's test platform-dispatcher seam, then assert:

```text
controller preference remains ThemeMode.system
effective Theme.of(shellContext).brightness follows platform brightness
update count unchanged
read count unchanged solely because brightness changed
```

Restore the platform-brightness test value in test teardown.

- [ ] **Step 2: Add the explicit Dark brightness test**

Load authoritative Dark, change test platform brightness, and prove selected app mode/effective shell remain Dark with no settings I/O caused by the platform change.

- [ ] **Step 3: Register the exact new generated paths**

Append these files to `registered_generated_files` while preserving every current entry:

```text
flutter/lib/app/bootstrap/application_presentation.g.dart
flutter/lib/features/settings/application/appearance_settings_controller.g.dart
flutter/lib/features/settings/application/appearance_settings_dependencies.g.dart
flutter/lib/features/settings/application/appearance_settings_state.freezed.dart
```

`flutter/lib/features/startup/application/app_readiness.g.dart` is already registered. Do not weaken the registry into a wildcard.

- [ ] **Step 4: Extend architecture tests**

Update exact generated-provider/source lists for the new files and the Settings page move. Add deterministic rules proving:

1. `features/settings/application/**` imports no `app/`, `features/startup/`, sibling-feature private paths, `core/bridge/`, `core/client/src/`, FRB, SQLite, `BuildContext`, `go_router`, or platform I/O.
2. `features/settings/presentation/**` contains no generated/bridge dependency and no direct `getAppearanceSettings(` / `updateAppearanceSettings(` call.
3. `app/routing/**` contains no `SettingsApi`, appearance read/update, controller, or presentation-gate workflow.
4. root theme is assigned in `app/bootstrap/argus_app.dart` from the derived provider, with no separately mutable root theme owner.
5. Settings feature state uses typed `ThemeMode`; lowercase wire strings are not used as state/transport representation.
6. production Settings/app appearance source does not consume `RuntimeEventPayloadAppearanceSettingsChanged`, `EventsApi`, event sequence/gap, or reconnect concepts.
7. the Slice 007 source/test set contains no process-restart persistence proof.
8. `settings.dart` remains the page entry point, `settings_composition.dart` is the deliberate app-composition entry point, and consumers do not import Settings private implementation paths.

Preserve all existing Slice 001–006 architecture checks.

- [ ] **Step 5: Run canonical generation and strict drift verification**

From repository root:

```bash
rtk proxy just generate
rtk proxy just check-generated
```

Expected: all registered outputs exist and are byte-stable after regeneration; no unexpected generated output exists.

- [ ] **Step 6: Run focused architecture/appearance coverage**

From `flutter/`:

```bash
rtk test fvm flutter test --no-pub \
  test/architecture/architecture_boundaries_test.dart \
  test/features/settings/appearance_settings_state_test.dart \
  test/features/settings/appearance_settings_controller_test.dart \
  test/features/settings/settings_page_test.dart \
  test/app/bootstrap/application_presentation_test.dart \
  test/app/bootstrap/app_bootstrap_test.dart
```

Expected: GREEN with no event-driven or restart-only implementation introduced.

---

### Task 7: Execute the Slice 007 Acceptance Gate

**Files:**
- No new production files expected.
- Fix only already-authorized Slice 007 owners if a verification command proves a real defect.

**Interfaces:**
- Produces completion evidence for active Slice 007 only; it does not claim Slice 008 event reconciliation or Slice 009 restart restoration.

- [ ] **Step 1: Run Flutter format and static analysis**

From `flutter/`:

```bash
rtk proxy fvm dart format --output=none --set-exit-if-changed .
rtk proxy fvm flutter analyze --no-pub
```

Expected: exit 0 with no formatting drift or analyzer diagnostics.

- [ ] **Step 2: Run the complete deterministic Flutter suite**

```bash
rtk test fvm flutter test --no-pub
```

Expected: all Slice 001–007 Flutter tests pass, including inherited Startup, client, and bridge tests.

- [ ] **Step 3: Run generated-source verification again**

From repository root:

```bash
rtk proxy just check-generated
```

Expected: exit 0.

- [ ] **Step 4: Run the complete repository quality gate**

```bash
rtk test just check
```

Expected: Rust format/clippy/tests, Flutter format/analyze/tests, ShellCheck, generated-source freshness, and architecture/dependency checks all pass without a Rust behavior change.

- [ ] **Step 5: Run final hygiene/scope checks**

```bash
rtk git diff --check
rtk git status --short --branch
rtk proxy rg -n \
  'AppearanceSettingsChanged|RuntimeEventPayloadAppearanceSettingsChanged|sequence gap|reconnect' \
  flutter/lib/features/settings flutter/lib/app/bootstrap
```

Expected: no whitespace failures, only intended Slice 007 changes, and no event-driven Settings implementation. Comments that merely document the later-slice boundary are not runtime behavior.

- [ ] **Step 6: Map fresh evidence to every active-slice acceptance item**

Before claiming completion, verify all of these explicitly:

1. backend Ready alone does not reveal the normal shell;
2. authoritative initial appearance read admits it;
3. initial read failure does not fabricate System or become backend StartupFailed;
4. persisted Dark returned by initial read is the theme on the first normal-shell frame;
5. Settings shows exactly System / Light / Dark with no Apply/Save workflow;
6. selection presents optimistically while root theme stays confirmed;
7. writes are single-flight complete-aggregate mutations;
8. update success does not promote the requested state;
9. successful mutation reconciles through focused read;
10. a query result different from the submitted value wins;
11. definite application failure rolls presentation back while root never moved;
12. transport-ambiguous mutation is never replayed and reconciles by read;
13. ambiguous mutation + failed read retains last-known theme and blocks writes;
14. update success + failed read becomes committed-but-unreconciled without fabricated authority;
15. recovery from uncertainty is read-only;
16. Runtime A completions cannot publish after Runtime B becomes current;
17. loaded last-known theme remains renderable while new-runtime synchronization is pending/uncertain;
18. System follows platform brightness without persistence traffic;
19. explicit Light/Dark ignore platform brightness changes;
20. Theme Mode is keyboard operable with selected semantics, non-color pending/failure/uncertainty feedback, and representative 200% text-scale usability;
21. Settings controller/application code has no bridge/generated/root-client/app/startup dependency leakage;
22. routing owns no settings workflow;
23. Slice 008 event reconciliation remains absent;
24. Slice 009 restart proof remains absent.

A failed item is an open Slice 007 defect; do not weaken tests or widen scope to hide it.

- [ ] **Step 7: Record evidence under the actual execution/delegation contract**

If this plan is executed through a durable Codex/Delegation run, write that run's required result artifact using its actual run ID/schema and report required commands as `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED`. Do not invent a run ID here and do not claim manual/native/restart evidence that was not executed.

Suggested commit message after review, **only if Daniel explicitly authorizes staging/commit**:

```text
feat: implement immediate theme persistence workflow
```

---

## Plan Self-Review

1. **Spec coverage:** Active Slice 007 portions of SPEC-FE-006 are covered: one app-lifetime authority, initial authoritative load, first-shell gate, bootstrap-theme non-authority, confirmed-only root theme, immediate persistence, optimistic presentation, single-flight admission, same-value no-op, success reconciliation, definite rollback, ambiguous transport reconciliation, command-success/read-failure uncertainty, read-only recovery, runtime-generation stale-result protection, System brightness semantics, Settings UX/accessibility, provider composition, deterministic tests, and architecture checks.
2. **Slice boundary:** Event-driven reconciliation is reserved for SLICE-P00-008; restart restoration/canonical demonstration are reserved for SLICE-P00-009. Ready end-state requirements do not authorize those implementations early.
3. **Authority invariant:** No task assigns `confirmed` from `presented`, a submitted mutation, an event, a timer, or a guessed default. Every confirmed change is sourced from `getAppearanceSettings()`.
4. **Failure invariant:** `ApplicationFailure` and `TransportFailure` stay semantically distinct. Ambiguity never causes mutation replay, and failed reconciliation never fabricates the requested value.
5. **Generation invariant:** Async settings work is runtime/token guarded. Runtime replacement retains safe last-known rendering while blocking writes until current-runtime authority is re-established.
6. **Dependency-direction check:** Settings application depends on public client contracts plus feature-owned injected seams, not `app/`, Startup internals, bridge/generated code, or root client. App bootstrap owns cross-feature wiring.
7. **Startup invariant:** `StartupGate` keeps its Slice 006 meaning. Slice 007 composes a separate nested appearance gate instead of redefining backend readiness.
8. **Theme invariant:** `MaterialApp.themeMode` has no mutable authority and never consumes pending `presented` state. Pre-authority System exists only behind the shell gate.
9. **Test-boundary check:** Controller tests use focused `SettingsApi` fakes and controlled runtime transitions; widget tests use the real controller with focused fakes; no ordinary feature test requires Rust, FRB, SQLite, public network, or elapsed-time sleeps.
10. **Generated-source check:** The four newly introduced generated paths are added to the strict registry; the already-registered startup generated file remains in place.
11. **Placeholder scan:** No unresolved implementation decision or delegated “similar” step remains. Later-slice work appears only as an explicit exclusion/boundary.
12. **Type consistency:** `AppearanceRuntimeContext`, `AppearanceSettingsState`, `AppearanceSaveOperation`, `AppearanceSynchronization`, `appearanceSettingsApiProvider`, `appearanceRuntimeContextProvider`, `appearanceSettingsControllerProvider`, `readyRuntimeInstanceIdProvider`, `ApplicationPresentationReadiness`, `applicationPresentationReadinessProvider`, and `rootThemeModeProvider` have consistent names/owners throughout the plan.
13. **Scope check:** No dependency, Rust, bridge DTO, FRB API, SQLite, route-graph, future-settings, event-reconciliation, or process-restart implementation is authorized.
14. **Git check:** No unconditional stage/commit/push operation appears. The suggested commit remains contingent on Daniel's explicit authorization.

## Next Slice Boundary

After Slice 007 is implemented, reviewed, and accepted, the next implementation slice is **SLICE-P00-008 — Event-Driven Theme Reconciliation**. It will connect the existing shared runtime-event stream to this controller's authoritative refresh mechanism, add event coalescing/follow-up semantics and gap/reconnect recovery, while preserving the Slice 007 rule that event payloads never become settings authority.
