# Phase 000 Slice 009 — Restart Restoration and Phase Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that the persisted Phase 000 appearance preference survives a real native Flutter process restart and complete the Phase 000 hardening/milestone verification without adding new product capability.

**Architecture:** Keep Rust/SQLite as the only persisted appearance authority. Add one narrow app-composition test seam so native integration tests can point the real bootstrap at a test-owned data directory, then orchestrate two separate macOS Flutter integration-test processes against that same directory: process one persists Dark through the real Settings workflow and shuts down normally; process two relaunches and proves the first normal shell is already Dark after backend `Ready` plus authoritative appearance loading. Stable native milestone verification remains separate from platform-neutral `just check`.

**Tech Stack:** Flutter/Dart, Riverpod, `integration_test`, existing `ArgusClient`/FRB bridge, Rust/SQLite, Bash, `just`.

## Global Constraints

- Implement only `SLICE-P00-009 — Restart Restoration and Phase Hardening` from `docs/phases/phase-000-foundation.md`.
- A real restart means two distinct native Flutter application/test-runner processes; recreating an `ArgusClient`, Riverpod container, runtime generation, or widget tree in one Dart process is insufficient.
- Both process phases must use the same test-owned temporary Argus data directory. Never use or mutate the developer's normal Argus data directory.
- Persisted appearance authority remains Rust/SQLite. Do not add frontend persistence, cached restart snapshots, event-payload authority, or copied in-memory state as restart evidence.
- The second process must prove that no normal shell is rendered under bootstrap/System appearance before authoritative Dark is known.
- Keep the native/E2E milestone workflow outside `just check`; `just check` remains deterministic, platform-neutral, offline verification.
- Preserve Slice 008 event reconciliation, one-root-client/one-native-event-connection lifecycle guarantees, startup recovery, immediate theme persistence, and confirmed-only root-theme authority.
- Do not add restart-required-settings UX, generic self-restart APIs, additional settings domains, Phase 001+ product work, or new external dependencies.
- Canonical generated output may change only through `just generate`; `just check-generated` must remain clean.
- Do not weaken or delete existing Slice 001–008 tests to make Slice 009 pass. If the new proof exposes a defect, fix the owning production layer and add a focused regression.
- Do not stage, commit, push, or rewrite Git history unless Daniel separately authorizes it.

---

### Task 1: Add a narrow real-bootstrap data-directory test seam

**Files:**
- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart`
- Modify: `flutter/test/app/bootstrap/app_bootstrap_test.dart`

**Interfaces:**
- Consumes: existing `argusClientGatewayFactoryProvider` and `ArgusClientGateway` contract.
- Produces: `ArgusBootstrap({ArgusClientGateway Function()? clientGatewayFactory})`; production `bootstrapArgus()` continues constructing `const ArgusBootstrap()` with no override.

- [ ] **Step 1: Write the failing bootstrap test**

Add a widget test that constructs `ArgusBootstrap(clientGatewayFactory: fakeFactory)`, reads the root `ProviderContainer`, and proves `argusClientGatewayFactoryProvider` resolves to the supplied factory while the existing app-owned Settings/runtime/event overrides remain active. Keep the existing assertion that exactly one root `ProviderScope` exists.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd flutter && fvm flutter test test/app/bootstrap/app_bootstrap_test.dart
```

Expected: FAIL because `ArgusBootstrap` does not yet accept the narrow gateway-factory seam.

- [ ] **Step 3: Implement the minimal bootstrap seam**

In `app_bootstrap.dart`, import the public client contract as needed and change the widget shape conceptually to:

```dart
class ArgusBootstrap extends StatelessWidget {
  const ArgusBootstrap({this.clientGatewayFactory, super.key});

  final ArgusClientGateway Function()? clientGatewayFactory;

  @override
  Widget build(BuildContext context) {
    final factory = clientGatewayFactory;
    return ProviderScope(
      overrides: [
        if (factory != null)
          argusClientGatewayFactoryProvider.overrideWithValue(factory),
        // existing app-owned overrides remain unchanged
      ],
      child: const ArgusApp(),
    );
  }
}
```

Do not add environment-variable behavior to production bootstrap and do not expose a generic arbitrary override list.

- [ ] **Step 4: Run the focused bootstrap test GREEN**

```bash
cd flutter && fvm flutter test test/app/bootstrap/app_bootstrap_test.dart
```

Expected: PASS.

---

### Task 2: Add the two-phase real native restart integration test

**Files:**
- Create: `flutter/integration_test/phase_000_restart_restoration_test.dart`
- Modify only if a proven defect requires it: owners under `flutter/lib/app/bootstrap/**`, `flutter/lib/features/settings/**`, `flutter/lib/features/startup/**`, `flutter/lib/core/client/**`, or `flutter/lib/core/bridge/**`

**Interfaces:**
- Consumes: `ArgusBootstrap.clientGatewayFactory`, `FrbArgusClientGateway(dataDirectoryOverride: ...)`, public `argusClientProvider`, Settings UI, root `MaterialApp.themeMode`, and `RuntimeApi.generalShutdown()`.
- Produces: one integration-test target with two externally selected phases: `seed` and `verify`.

- [ ] **Step 1: Write the restart test target with explicit process-phase input**

Read only these test-owned environment values with `dart:io` inside the integration test:

```text
ARGUS_PHASE_000_RESTART_MODE=seed|verify
ARGUS_PHASE_000_DATA_DIR=<absolute temporary directory>
```

Fail immediately when either is missing or invalid. Never infer or fall back to a normal application data directory.

Create the real app using:

```dart
ArgusBootstrap(
  clientGatewayFactory: () => FrbArgusClientGateway(
    dataDirectoryOverride: dataDirectory,
  ),
)
```

Use the existing production app composition below that seam; do not recreate Settings/startup/event providers in the integration test.

- [ ] **Step 2: Implement the `seed` phase assertions**

The `seed` phase must:

1. Pump the real `ArgusBootstrap` until the normal Settings shell is visibly admitted.
2. Assert the fresh database presents authoritative `System` before mutation.
3. Select **Dark** through the actual Theme Mode UI rather than calling `SettingsApi.updateAppearanceSettings()` directly.
4. Wait on meaningful UI/provider state, not an arbitrary sleep, until pending mutation/reconciliation completes.
5. Assert the root `MaterialApp.themeMode` is `ThemeMode.dark`.
6. Read `argusClientProvider.settings.getAppearanceSettings()` and assert the authoritative backend result is Dark.
7. Call `argusClientProvider.runtime.generalShutdown()` and dispose the client/widget tree cleanly before the test process exits.

A bounded pump helper may use a timeout only as failure protection; its success condition must be an explicit shell/state predicate.

- [ ] **Step 3: Implement the `verify` phase first-shell invariant**

The `verify` phase must launch the same real app against the same directory and pump frame-by-frame until the normal Settings shell first becomes visible. On the **first frame where the normal shell exists**, assert all of the following immediately:

```text
MaterialApp.themeMode == dark
Theme.of(Settings surface).brightness == dark
```

Before that first shell frame, the test may observe startup/loading UI, but it must never observe a normal shell under `system` or `light` root theme mode. After admission, read `SettingsApi.getAppearanceSettings()` through the root client and assert Dark, then shut down/dispose normally.

This is the regression proof for:

```text
persist Dark
-> process exit
-> new native process
-> backend Ready
-> initial authoritative appearance read = Dark
-> first normal shell = Dark
```

- [ ] **Step 4: Run each phase manually against one shared directory**

After rebuilding the bridge, run two distinct commands from separate Flutter test invocations using one manually created temporary directory. Expected: both PASS; process two must not depend on memory from process one.

---

### Task 3: Add a stable Phase 000 native milestone harness

**Files:**
- Create: `scripts/run_phase_000_native_tests.sh`
- Modify: `justfile`

**Interfaces:**
- Consumes: existing bridge build command, `native_bridge_smoke_test.dart`, `startup_recovery_smoke_test.dart`, and the new two-phase restart target.
- Produces: root recipe `just test-phase-000-native` that is intentionally **not** a dependency of `just test` or `just check`.

- [ ] **Step 1: Write the failing recipe expectation**

Add the `justfile` recipe name first and verify invoking it fails because the script does not exist yet.

- [ ] **Step 2: Implement the macOS native milestone script**

The script must use `set -euo pipefail`, resolve the repository root independently of caller cwd, require Darwin/macOS for the current primary-development-platform proof, and create one temporary directory with `mktemp -d`. Install a `trap` that recursively deletes only that exact owned directory.

The execution order must be:

```text
1. rebuild argus-bridge with locked Cargo inputs
2. run native_bridge_smoke_test.dart on macOS
3. run startup_recovery_smoke_test.dart on macOS
4. run phase_000_restart_restoration_test.dart with mode=seed and shared temp directory
5. run phase_000_restart_restoration_test.dart again in a distinct Flutter invocation with mode=verify and the same temp directory
```

Use commands equivalent to:

```bash
bash scripts/run_rust.sh cargo build --manifest-path rust/Cargo.toml --package argus-bridge --locked
(
  cd flutter
  fvm flutter test integration_test/native_bridge_smoke_test.dart -d macos
  fvm flutter test integration_test/startup_recovery_smoke_test.dart -d macos
  ARGUS_PHASE_000_RESTART_MODE=seed \
  ARGUS_PHASE_000_DATA_DIR="$data_dir" \
    fvm flutter test integration_test/phase_000_restart_restoration_test.dart -d macos
  ARGUS_PHASE_000_RESTART_MODE=verify \
  ARGUS_PHASE_000_DATA_DIR="$data_dir" \
    fvm flutter test integration_test/phase_000_restart_restoration_test.dart -d macos
)
```

Do not combine seed and verify into one Flutter invocation.

- [ ] **Step 3: Wire the stable recipe outside platform-neutral gates**

Add:

```make
# conceptual name; preserve justfile syntax/style
test-phase-000-native:
    bash scripts/run_phase_000_native_tests.sh
```

Confirm `check:` remains unchanged and does not depend on this recipe.

- [ ] **Step 4: Run the full native milestone recipe**

```bash
just test-phase-000-native
```

Expected: PASS on the primary macOS development platform.

---

### Task 4: Retire the earlier-slice restart prohibition without weakening architecture

**Files:**
- Modify: `flutter/test/architecture/architecture_boundaries_test.dart`

**Interfaces:**
- Consumes: existing source-map architecture-test fixture.
- Produces: a durable invariant that production appearance code does not own process orchestration or restart persistence even though Slice 009 integration tests now prove restart behavior.

- [ ] **Step 1: Replace the obsolete Slice 007 guard**

Remove/reframe the test named `appearance sources contain no process-restart persistence proof`. It was intentionally a temporary slice-boundary assertion and would conflict with Slice 009 evidence.

Replace it with a production-boundary assertion whose intent is:

```text
settings/app appearance production sources may describe restart restoration,
but they must not launch child processes, inspect the Slice 009 test environment,
or add a second persistence mechanism.
```

At minimum, assert the bounded production sources do not contain/import process orchestration or test-harness concepts such as `dart:io`, `Process.run`, `ARGUS_PHASE_000_RESTART_MODE`, or `ARGUS_PHASE_000_DATA_DIR`. Preserve the existing tests that root theme authority is derived, Settings has no bridge implementation dependency, and event continuity is interpreted only by the app coordinator.

- [ ] **Step 2: Run architecture tests**

```bash
cd flutter && fvm flutter test test/architecture/architecture_boundaries_test.dart
```

Expected: PASS.

---

### Task 5: Record reproducible Phase 000 completion verification

**Files:**
- Create: `docs/implementation/phase-000-foundation-verification.md`

**Interfaces:**
- Consumes: Phase 000 Sections 3, 12.6, and 13; canonical repository commands.
- Produces: reproducible automated/manual completion procedure without fabricating evidence.

- [ ] **Step 1: Document the automated gates**

Document these commands and what each proves:

```bash
just generate
just check-generated
just check
just test-phase-000-native
```

State explicitly that `just test-phase-000-native` performs the real two-process restart proof and native startup/recovery/bridge checks and is intentionally outside `just check`.

- [ ] **Step 2: Document remaining manual milestone checks as evidence slots, not claims**

Include the Phase 000 manual requirements that cannot be honestly automated in this slice, including keyboard walkthrough, screen-reader smoke, reviewed visual/golden evidence where required, large text/display scaling, reduced/disabled animation, and clean-checkout instructions. Each item must be recorded as `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED` when executed; the document must not pre-mark unexecuted checks as passing.

- [ ] **Step 3: Keep governed specs unchanged**

Do not edit `docs/phases/**`, `docs/specifications/**`, `docs/conventions/**`, or `docs/architecture/**` merely to report completion. They are binding inputs for this slice.

---

### Task 6: Final generation, regression, native, and scope verification

**Files:**
- No new production files expected beyond defects proven by earlier tasks.
- Update the actual Delegation v3 `RESULT.json` only after commands have genuinely executed.

**Interfaces:**
- Consumes: all Slice 009 work and inherited Slice 001–008 gates.
- Produces: truthful completion evidence for the final Phase 000 slice.

- [ ] **Step 1: Regenerate canonically**

```bash
just generate
just check-generated
```

Expected: PASS. No generated file may be hand-edited and no machine-local absolute path may appear in registered generated output.

- [ ] **Step 2: Run platform-neutral completion gate**

```bash
just check
```

Expected: PASS.

- [ ] **Step 3: Run the native Phase 000 milestone gate**

```bash
just test-phase-000-native
```

Expected: PASS on macOS. The restart test must execute seed and verify as separate Flutter invocations.

- [ ] **Step 4: Run Git hygiene checks**

Run `git diff --check` and inspect the changed-path set. No change may escape the delegation authorization scope. No generated/cache/build output from `.dart_tool`, `build`, Rust `target`, temporary databases, or diagnostics archives may be added.

- [ ] **Step 5: Record result evidence accurately**

In the bound run's `RESULT.json`, report each command as `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED`. Do not claim manual accessibility, screen-reader, visual-review, or clean-checkout evidence unless it was actually executed. A failed required automated gate leaves Slice 009 incomplete.

## Plan Self-Review

1. **Spec coverage:** The plan proves SPEC-FE-006 Section 120's real restart chain, Phase 000 canonical theme-restart scenario, native startup/recovery/bridge continuity, generated freshness, architecture enforcement, and milestone evidence separation.
2. **Authority invariant:** The second process obtains Dark through normal Rust/SQLite startup plus focused authoritative read; no in-memory state crosses the process boundary.
3. **Presentation invariant:** Startup/bootstrap presentation may use System behind the gate, but the first *normal shell* in process two must already be Dark.
4. **Process invariant:** Seed and verify are separate `flutter test ... -d macos` invocations. One integration-test invocation with two widget resets is explicitly insufficient.
5. **Test-seam invariant:** Production bootstrap gains only a narrow optional gateway-factory seam. No production environment-variable parsing or generic arbitrary provider-override surface is introduced.
6. **Gate invariant:** `just check` remains platform-neutral. Native milestone proof has its own stable recipe.
7. **Earlier-slice guard:** The temporary no-restart-proof assertion is replaced by a durable no-production-process-orchestration/no-second-persistence assertion rather than simply deleted.
8. **Scope:** No new settings behavior, restart-required UX, self-restart API, schema/domain vocabulary, or Phase 001 functionality is planned.
9. **Evidence integrity:** Manual requirements are documented but never automatically marked passing.
10. **Git:** This plan authorizes implementation paths, not staging, commit, push, or history mutation.
