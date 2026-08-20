# P02-006 Adaptive Android UX and Platform Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Argus Android presentation across phones, tablets, foldables, split-screen windows, and handhelds while preserving the existing shared Flutter navigation, controller, runtime, provider, job, and persistence authorities.

**Architecture:** Extend the existing width-driven Flutter presentation and Android platform boundary rather than adding Android-specific feature forks. Standard Flutter navigator/pop behavior owns Back and predictive Back, existing application-scoped controllers retain valid process-lifetime state through Activity/presentation changes, and Android-native code is limited to genuine system UI/lifecycle integration and qualification support.

**Tech Stack:** Flutter/Dart, Riverpod, go_router, Material 3, Android/Kotlin API 36 qualification tooling, existing Flutter Rust Bridge/Rust runtime without new backend contracts.

**Spec:** `docs/superpowers/specs/2026-08-19-phase-002-slice-006-adaptive-android-ux-and-platform-integration-design.md`

## Global Constraints

- Global size classes remain exactly Compact `<600`, Medium `600–839`, Expanded `840–1199`, and Large `>=1200` logical pixels.
- Global application structure is width-driven; do not branch on Android device category, orientation name, hardware model, or pointer presence.
- Shared adaptive/accessibility defects are fixed in shared Flutter presentation rather than hidden behind Android-specific wrappers.
- `go_router` remains the sole routed-navigation authority; do not add an app-level Back coordinator or duplicate route state.
- Android Back/predictive Back uses the supported Flutter navigator/pop pipeline; feature-local state consumes Back only for a meaningful topmost local action.
- Rotation, Activity recreation, resize, split-screen, fold/unfold, and temporary backgrounding must not create a second Flutter/Rust composition, SQLite authority, or runtime shutdown/replacement.
- Preserve valid process-lifetime picker/hierarchy/controller state; do not add durable persistence for transient presentation state.
- P02-004 remains authoritative for foreground execution, timeout, cancellation, host-loss, process-death, and recovery semantics.
- P02-005 remains authoritative for permission regrant, removable-volume availability/remount, multi-root, and reconciliation semantics.
- Preserve provider-owned opaque browse locations/cursors; raw paths/URIs do not become Flutter state authority.
- Android uses modern edge-to-edge presentation and normal Flutter inset APIs; do not globally wrap the app in `SafeArea` or hard-code device padding.
- Accessibility is correctness: practical touch targets, semantics, logical traversal, visible focus, non-color state communication, and usable 2x text scaling are required.
- `just check` remains deterministic/platform-neutral; Android native qualification remains a separate repository-owned milestone.
- P02-007 retains Android CI wiring, signing/distribution, final desktop regression closure, applicability guards, and final physical ARM64 evidence.
- If implementation requires changing Rust/application authority, persistence, provider identity contracts, foreground-execution semantics, or job lifecycle semantics, stop and request a scope amendment.
- Do not stage, commit, push, restore, or discard unrelated owner worktree changes during implementation. The agent implementing this repository plan must follow the repository's existing delegation/result conventions.

---

## File Structure and Ownership Map

Implementation must inspect current code before editing and keep changes focused. Expected ownership is:

- `flutter/lib/core/responsive/window_size_class.dart` — canonical global width classification only.
- `flutter/lib/app/shell/application_shell.dart` — adaptive navigation projection and shell-level presentation.
- `flutter/lib/app/routing/app_routes.dart` — canonical route composition/pop behavior only if existing route integration requires adjustment.
- `flutter/lib/app/platform/**` — genuinely Android-specific lifecycle/system-UI seams; no feature policy.
- `flutter/android/app/src/main/**` — Android edge-to-edge/predictive-Back/native lifecycle configuration only when Flutter integration requires native host changes.
- `flutter/lib/features/sources/presentation/**` — picker, hierarchy, root/detail, inspector, and Sources adaptive hardening.
- `flutter/lib/features/jobs/presentation/**` — Jobs adaptive/accessibility hardening.
- `flutter/lib/features/settings/presentation/**` — Settings adaptive/accessibility hardening.
- `flutter/lib/features/startup/presentation/**` and `flutter/lib/app/platform/presentation/**` — startup/readiness adaptive/accessibility/inset hardening.
- Existing feature application controllers may change only when a concrete test proves process-lifetime state is currently owned at the wrong lifetime; do not introduce persistence or platform concepts into controllers.
- Existing Flutter tests under `flutter/test/**` and Android native milestone/test infrastructure are extended rather than replaced.
- `flutter/integration_test/**` is also an authorized canonical location for P02-006 Android integration qualification that coordinates production Flutter/runtime assertions with the real Android host; it must remain qualification-only and must not become product authority.

Do not pre-emptively create abstraction files. Introduce a new shared presentation primitive only when at least two concrete call sites need identical behavior and the existing design-system/responsive boundary is the correct owner.

---

### Task 1: Establish Adaptive, Accessibility, and State-Preservation Baselines

**Files:**
- Inspect: `flutter/lib/core/responsive/window_size_class.dart`
- Inspect: `flutter/lib/app/shell/application_shell.dart`
- Inspect: `flutter/lib/features/sources/presentation/**`
- Inspect: `flutter/lib/features/jobs/presentation/**`
- Inspect: `flutter/lib/features/settings/presentation/**`
- Inspect: `flutter/lib/features/startup/presentation/**`
- Test: existing responsive/shell/feature widget tests under `flutter/test/**`

**Interfaces:**
- Consumes: existing `WindowSizeClass`, route/destination catalog, Sources/Jobs/Settings/startup presentation APIs.
- Produces: failing regression tests that define P02-006 behavior before production edits.

- [ ] **Step 1: Inventory the exact existing widget/integration tests and production seams for size classes, shell navigation, Sources hierarchy/picker, Jobs, Settings, startup/readiness, semantics, focus, and text scaling.** Record only paths needed by later tasks in the implementation run evidence; do not refactor while inventorying.

- [ ] **Step 2: Add/extend canonical width-boundary tests.** Assert exact classifications for widths `599`, `600`, `839`, `840`, `1199`, and `1200`, plus representative values inside each class. The test must prove one canonical classifier is used rather than reproducing breakpoint arithmetic in the test harness.

- [ ] **Step 3: Add failing live-resize shell tests.** Pump the same routed application through Compact -> Medium -> Expanded -> Large -> Compact constraints and assert canonical URI/destination identity and branch history remain unchanged while navigation presentation changes.

- [ ] **Step 4: Add failing representative 1x/2x text-scale and semantics tests.** Cover at least shell navigation, Sources root/hierarchy actions, Jobs primary actions/status, Settings theme control, startup/readiness primary actions, and picker confirmation/navigation. Assert required actions remain reachable and semantics expose meaningful labels/state; do not use golden pixel identity as the acceptance criterion.

- [ ] **Step 5: Add failing process-lifetime state-preservation tests around existing controller/provider scopes.** Rebuild/recreate presentation around the surviving application/provider composition and prove selected Sources context and picker location remain valid rather than being recreated from widget-local defaults.

- [ ] **Step 6: Run only the new/modified Flutter tests and confirm they fail for concrete P02-006 gaps rather than harness mistakes.** Use the repository's pinned Flutter invocation/Just targets discovered from existing test conventions. Capture the failing test names in run evidence.

---

### Task 2: Harden Shared Adaptive Shell and Navigation

**Files:**
- Modify: `flutter/lib/app/shell/application_shell.dart`
- Modify only if required: `flutter/lib/core/responsive/window_size_class.dart`
- Modify only if required: `flutter/lib/app/routing/app_routes.dart`
- Test: shell/routing/responsive tests identified in Task 1

**Interfaces:**
- Consumes: canonical `WindowSizeClass`, existing `AppDestination` catalog and go_router stateful shell branches.
- Produces: one route-authoritative adaptive shell whose Compact/Medium/Expanded/Large projections survive live constraint changes.

- [ ] **Step 1: Make the Task 1 live-resize tests the focused red gate for this task.** Verify they fail before production edits.

- [ ] **Step 2: Remove any shell behavior that derives structural presentation from platform/device/orientation rather than available width.** Keep the exact canonical breakpoints and existing destination catalog.

- [ ] **Step 3: Harden Compact bottom navigation, Medium rail, and Expanded/Large sidebar projection.** Sources, Jobs, and Settings remain direct Compact destinations; Jobs active-count badge semantics remain equivalent across presentations; selected destination is derived from route state rather than duplicate mutable state.

- [ ] **Step 4: Ensure live width changes do not recreate branch-local route history or replace canonical route identity.** If a widget key/lifetime currently causes state loss, fix the narrow ownership problem rather than adding restoration persistence.

- [ ] **Step 5: Make navigation surfaces practical for touch and keyboard/pointer.** Preserve Material-sized hit areas, meaningful semantics, logical focus traversal, and visible focus without changing layout authority based on input device.

- [ ] **Step 6: Run focused shell/routing/responsive tests at all six boundary widths and live transitions.** Expected: PASS with unchanged canonical URIs and branch histories.

---

### Task 3: Implement Standard Android Back and Predictive-Back Semantics

**Files:**
- Modify as required: `flutter/lib/app/routing/app_routes.dart`
- Modify as required: `flutter/lib/app/shell/application_shell.dart`
- Modify: `flutter/lib/features/sources/presentation/local_filesystem_browser.dart`
- Modify: `flutter/lib/features/sources/presentation/hierarchy_drill_down_view.dart`
- Modify as required: transient Sources inspector/dialog presentation files
- Modify Android host/config only if required by the supported Flutter predictive-Back integration
- Test: routing/Back/picker/hierarchy widget tests and Android native milestone tests

**Interfaces:**
- Consumes: existing navigator/go_router pop pipeline and feature-local transient state.
- Produces: semantic Back ordering: topmost transient dismissal -> picker/hierarchy parent -> routed pop -> Android Activity exit/background.

- [ ] **Step 1: Add failing tests for Back ordering.** Cover picker at nested location, picker at root, Compact hierarchy at nested node, active transient inspector/modal, routed root detail, and shell root with no meaningful in-app pop.

- [ ] **Step 2: Integrate feature-local Back consumption using Flutter's supported pop APIs at the narrow presentation boundary that owns the transient state.** Do not create a global Back controller, Riverpod Back state, or Android-only route model.

- [ ] **Step 3: Ensure picker Back navigates to the parent before dismissal and Compact hierarchy Back retreats before routed navigation.** At local root, allow the normal navigator/router pipeline to continue.

- [ ] **Step 4: Ensure transient inspector/dialog dismissal remains topmost when it is the meaningful current surface.** Preserve focus restoration to the originating/surviving control where practical.

- [ ] **Step 5: Enable/configure predictive Back only through the Flutter/Android mechanism supported by the repository's pinned Flutter/Android versions.** The predictive gesture must drive the same pop authority as ordinary Back; do not implement a parallel native navigation decision tree.

  Acceptance note: if the pinned Flutter version exposes no supported predictive-progress API for nested local `PopScope` state, preserve ordinary Back semantics and routed predictive integration, record the exact framework/tooling limitation in native evidence, and do not create a second Back authority merely to manufacture progress evidence.

- [ ] **Step 6: Run focused Flutter Back tests.** Expected: PASS for semantic ordering with no route identity changes caused by local hierarchy movement.

---

### Task 4: Harden Sources Adaptive Hierarchy and Process-Lifetime State

**Files:**
- Modify: `flutter/lib/features/sources/presentation/sources_page.dart`
- Modify: `flutter/lib/features/sources/presentation/root_detail_page.dart`
- Modify: `flutter/lib/features/sources/presentation/source_hierarchy_browser.dart`
- Modify: `flutter/lib/features/sources/presentation/hierarchy_drill_down_view.dart`
- Modify: `flutter/lib/features/sources/presentation/hierarchy_tree_view.dart`
- Modify: `flutter/lib/features/sources/presentation/source_entry_inspector.dart`
- Modify application controller/state files only if a failing test proves incorrect ownership
- Test: Sources widget/controller tests identified in Task 1

**Interfaces:**
- Consumes: existing stable source/root IDs, hierarchy controller state, selected-entry projection, route root identity.
- Produces: adaptive Sources presentation that preserves valid semantic context through width and Activity/presentation changes.

- [ ] **Step 1: Add failing tests for Compact <-> Medium <-> Expanded/Large transitions while a root and hierarchy context are active.** Assert selected root and valid entry context survive presentation changes.

- [ ] **Step 2: Add failing tests for authoritative invalidation while adaptive state is active.** Removed selected entry clears selection; disappeared Compact current node retreats to nearest valid ancestor/root; stale expansion state is removed without resetting unrelated valid context.

- [ ] **Step 3: Harden root list/detail structure for narrow and large widths.** Avoid overflow and preserve canonical `/sources` and `/sources/roots/:rootId` route identity; local layout changes must not create alternate URIs.

- [ ] **Step 4: Harden Compact drill-down, Medium local adaptation, and Expanded/Large tree rendering.** Keep one controller/state model and avoid eager recursive materialization.

- [ ] **Step 5: Harden inspector presentation and focus behavior.** Compact/transient and wider persistent/secondary presentation may differ structurally, but selected entry identity remains semantic feature state and dismissal returns focus sensibly when the origin survives.

- [ ] **Step 6: Run focused Sources tests at representative widths and 2x text scale.** Expected: PASS with no state reset caused solely by layout changes.

---

### Task 5: Harden the Existing Argus Folder Picker

**Files:**
- Modify: `flutter/lib/features/sources/presentation/library_folder_picker.dart`
- Modify: `flutter/lib/features/sources/presentation/local_filesystem_browser.dart`
- Modify only if required: `flutter/lib/features/sources/application/local_filesystem_browser_controller.dart`
- Modify only if required: `flutter/lib/features/sources/presentation/add_library_folder_flow.dart`
- Test: picker/browser/controller tests and native milestone picker scenario

**Interfaces:**
- Consumes: existing opaque browse location/cursor/page projections and platform/provider availability refresh.
- Produces: same picker selection contract with hardened hierarchy, paging, environmental-loss, adaptive, accessibility, and lifecycle behavior.

- [ ] **Step 1: Add failing picker tests for nested Back, root dismissal, current-location preservation across presentation recreation, and resize while browsing.** Assert opaque location identity is retained; do not assert raw paths/URIs.

- [ ] **Step 2: Add failing tests for loading, empty, typed failure, unavailable volume, remount/recovery, long display names, and multi-page directory results.** Ensure retry/refresh uses existing controller/provider APIs rather than reconstructing locations in presentation.

- [ ] **Step 3: Harden list/layout behavior for narrow widths, large text, long names, and large paged directories.** Required navigation and selection actions remain reachable; truncation may protect layout but must not remove accessible full meaning.

- [ ] **Step 4: Harden environmental transitions.** Unavailable removable storage shows authoritative unavailability and retains safe context; reappearance follows existing refresh/reconciliation contracts. Do not treat disappearance as empty content or destructive absence.

- [ ] **Step 5: Harden touch, semantics, keyboard/pointer traversal, and focus restoration.** Folder rows and navigation/confirm controls expose meaningful semantics and practical hit areas.

- [ ] **Step 6: Run focused picker/browser tests at Compact and wider constraints plus 2x text scale.** Expected: PASS with unchanged provider selection contract.

---

### Task 6: Harden Jobs, Settings, Startup, and Readiness Presentation

**Files:**
- Modify as required: `flutter/lib/features/jobs/presentation/jobs_page.dart`
- Modify as required: `flutter/lib/features/jobs/presentation/job_detail_page.dart`
- Modify as required: `flutter/lib/features/settings/presentation/settings_page.dart`
- Modify as required: `flutter/lib/features/settings/presentation/theme_mode_control.dart`
- Modify as required: `flutter/lib/features/startup/presentation/**`
- Modify as required: `flutter/lib/app/platform/presentation/platform_readiness_gate.dart`
- Test: corresponding widget/accessibility tests

**Interfaces:**
- Consumes: existing authoritative controllers and typed presentation states.
- Produces: Android-applicable shared presentation that remains usable under narrow width, 2x text, focus traversal, and lifecycle reconstruction without changing controller authority.

- [ ] **Step 1: Add failing representative narrow-width and 2x-text tests for Jobs list/detail, Settings/theme controls, startup failure/recovery, loading, and platform readiness/permission surfaces.** Assert required actions remain reachable and text does not make functionality inaccessible.

- [ ] **Step 2: Add semantics/focus assertions for primary actions and meaningful status.** Busy/failure/selected/disabled state must not rely on color alone.

- [ ] **Step 3: Apply minimal shared layout fixes.** Prefer flexible/wrapping/scrolling local layout over reduced touch targets or platform-specific branches.

- [ ] **Step 4: Verify presentation reconstruction around the surviving provider composition does not reset authoritative Jobs, Settings appearance, startup, or readiness controller state.** Fix only concrete lifetime bugs discovered by tests.

- [ ] **Step 5: Run focused Jobs/Settings/startup/readiness tests at Compact and representative wide widths, at 1x and 2x text scale.** Expected: PASS.

---

### Task 7: Implement Android Edge-to-Edge, Insets, IME, and Lifecycle Integration Hardening

**Files:**
- Inspect/modify: `flutter/lib/app/platform/**`
- Inspect/modify: `flutter/android/app/src/main/**`
- Modify shared presentation only at local inset-sensitive boundaries identified by failing tests
- Test: Flutter inset/IME tests plus Android native qualification scenarios

**Interfaces:**
- Consumes: existing application-scoped cached engine/runtime host, platform readiness lifecycle, Flutter `MediaQuery`/view inset/padding APIs.
- Produces: modern Android edge-to-edge behavior without a new lifecycle or presentation authority.

- [ ] **Step 1: Add failing deterministic presentation tests for representative system padding/viewInsets.** Cover shell content, picker, dialog/transient controls, readiness surfaces, and at least one text-entry/IME-sensitive path if the current product exposes one. Assert required controls are not obscured.

  Acceptance note: when no P02-006 product workflow exposes a text-input surface, deterministic `MediaQuery`/`viewInsets` coverage plus native system-bar/inset qualification satisfies the IME applicability requirement; do not add a fake text field solely for qualification.

- [ ] **Step 2: Inspect current Android theme/Activity/window configuration and pinned Flutter behavior.** Choose the minimal supported edge-to-edge configuration; do not add device/API heuristics beyond what Android/Flutter compatibility requires.

- [ ] **Step 3: Configure modern edge-to-edge presentation and local Flutter inset handling.** Avoid a global `SafeArea`; apply padding/scroll avoidance only at boundaries that actually need safe/system/IME space.

- [ ] **Step 4: Verify rotation, Activity recreation, split-screen/resize, fold/unfold-equivalent constraint changes, permission-overlay return, and temporary backgrounding do not trigger general shutdown or duplicate runtime/client composition.** Reuse P02-004/P02-005 lifecycle/readiness seams; do not add a second lifecycle controller.

- [ ] **Step 5: Run focused Flutter inset/lifecycle tests.** Expected: PASS with stable controller/runtime identity in deterministic seams.

---

### Task 8: Add and Run the P02-006 Android Native Qualification Milestone

**Files:**
- Modify: existing repository-owned Android native milestone scripts/tests discovered from P02-003/P02-004/P02-005
- Modify: Android test fixtures/helpers only as needed for P02-006 scenarios
- Update: `docs/implementation/**` P02-006 verification record if repository conventions require a slice verification document
- Evidence: Delegation/result artifacts according to repository conventions

**Interfaces:**
- Consumes: production Android APK/app, existing emulator orchestration, API 36 ARM64-compatible local environment as currently supported by the repository, existing P02-004/P02-005 native qualification helpers.
- Produces: recorded native evidence for P02-006 platform behavior; no CI wiring.

- [ ] **Step 1: Extend the existing native milestone rather than creating a parallel harness.** Add explicit P02-006 assertions/scenarios for rotation/Activity recreation, background/foreground, live window/size changes where tooling permits, ordinary Back, predictive Back where supported, picker parent navigation/dismissal, permission-overlay return, system bars/insets, IME interaction where applicable, and single-runtime/composition preservation.

- [ ] **Step 2: Make every scenario independently diagnosable.** Evidence must identify device/API/ABI, scenario, expected state transition, and observed pass/fail/unverified result. Do not infer native behavior solely from Flutter widget tests.

- [ ] **Step 3: Run the native milestone on the repository's supported API 36 emulator setup.** If emulator/tooling cannot exercise a required scenario, record that scenario as `unverified` with the concrete tooling limitation; do not mark it passed.

- [ ] **Step 4: Confirm the milestone does not absorb P02-007 responsibilities.** Do not add CI workflow wiring, release signing, final physical ARM64 evidence, or distribution packaging beyond what is already necessary to launch the qualification app.

- [ ] **Step 5: Preserve exact native evidence in the implementation result/verification record.** Include commands/outcomes and any unverified scenario rationale according to repository conventions.

---

### Task 9: Full Regression, Architecture Guards, Documentation, and Completion Evidence

**Files:**
- Modify: architecture/spec guard tests only where P02-006 introduces a newly enforceable invariant
- Modify: owning specifications only if implementation exposes an ambiguity that must be clarified without changing approved scope
- Update: Phase/slice implementation verification documentation as required by repository conventions
- Evidence: Delegation v3 `RESULT.json`/result artifacts

**Interfaces:**
- Consumes: all P02-006 production/test changes.
- Produces: green deterministic gate, recorded native qualification, preserved desktop behavior, and evidence that P02-007 is the only remaining Phase 002 implementation slice.

- [ ] **Step 1: Add/extend architecture guards for concrete regression risks introduced by this work.** At minimum prevent feature packages from acquiring Android platform imports/device-category layout authority, prevent duplicate breakpoint definitions if not already guarded, and prevent a new app-level Back state authority if a stable structural guard is feasible.

- [ ] **Step 2: Run generated-source verification/generation only through canonical repository commands if production edits require generated output.** Never hand-edit generated Riverpod/go_router/FRB files.

- [ ] **Step 3: Run Flutter formatting, analysis, and the complete Flutter test suite through repository-standard commands.** Resolve all P02-006 regressions without weakening tests.

- [ ] **Step 4: Run `just check`.** Expected: PASS. This remains the deterministic platform-neutral gate and must preserve desktop/shared behavior.

- [ ] **Step 5: Re-run the P02-006 Android native qualification milestone after the final production state.** Expected: all exercisable required scenarios PASS; any genuinely tooling-blocked scenario remains explicitly unverified with rationale.

- [ ] **Step 6: Perform a final scope audit.** Confirm no durable transient-state persistence, Android-specific feature UI fork, second route/Back authority, provider identity leak, runtime/job authority change, CI wiring, signing/distribution work, or final physical-device evidence was introduced.

- [ ] **Step 7: Write completion evidence according to repository Delegation v3 conventions.** Record exact validation commands/outcomes, touched paths, native API/ABI/device facts, adaptive/Back/inset/accessibility/state-preservation evidence, any unverified native scenario, and confirmation that P02-007 remains the final Phase 002 implementation slice.

- [ ] **Step 8: Leave implementation changes uncommitted for owner review unless the owner explicitly requests repository integration.** Do not stage, commit, or push as part of normal delegated implementation.

---

## Plan Self-Review

- **Spec coverage:** Tasks 2-7 cover adaptive shell, Back/predictive Back, Sources, picker, other feature surfaces, accessibility, edge-to-edge/insets, and process-lifetime lifecycle preservation. Task 8 supplies the required native milestone. Task 9 supplies architecture/regression/completion evidence.
- **Authority preservation:** No task creates backend/domain contracts, persistence for transient state, a second route/Back authority, Android feature forks, or a new lifecycle scheduler.
- **P02-007 boundary:** CI wiring, signed distribution, final desktop regression closure, applicability guards beyond concrete P02-006 architecture risks, and final physical ARM64 evidence remain excluded.
- **TDD:** Every production-hardening task begins from focused failing regression coverage and ends with focused validation before broader gates.
