# Phase 002 Slice 006 implementation record

This slice hardens the shared Flutter presentation and the Android host
boundary for adaptive layouts, system Back, accessibility, local insets, and
process-lifetime presentation changes. Existing Rust/application, provider,
route, foreground-execution, and persistence authorities remain unchanged.

## Implemented behavior

- The application shell continues to derive presentation from the canonical
  Compact/Medium/Expanded/Large width classes. Live width changes preserve the
  active route and branch identity.
- Picker and Compact Sources hierarchy Back handling now retreat through their
  provider-owned local hierarchy before allowing routed dismissal. Picker
  failures preserve the last loaded page and expose an exact retry action;
  labels are bounded for narrow/large-text layouts without changing opaque
  provider identities.
- Sources empty-state and local-browser presentation now use bounded local
  scrolling and constraint-derived minimum heights. Deterministic compact 2×
  and rotated compact regression tests cover the native RenderFlex conditions
  that previously overflowed.
- The native picker fixture creates a nested directory on the emulator and the
  integration test selects it from the provider-returned directory projection.
  The subsequent parent Back and dismissal assertion use the opaque provider
  location returned by production code; no raw path or URI is injected into
  Flutter state.
- Jobs detail actions wrap at compact 2× text, loading/busy/failure/status
  states expose live semantics, and readiness presentation scrolls locally
  when narrow 2× text exceeds the viewport. Settings and startup operation
  states expose corresponding status semantics.
- The Android manifest opts into the platform predictive-Back callback path.
  Flutter 3.44.7 already defaults API 36 applications to edge-to-edge; local
  Flutter inset handling is applied only at picker/readiness boundaries and no
  global SafeArea or device padding was added.
- A qualification-only Android host channel (`argus/android_qualification`)
  exposes an opaque per-Activity-instance UUID to the integration-test harness.
  The identity is host evidence only: it is never persisted, never read by
  product code, and carries no runtime, route, or readiness authority. The
  cached engine and single-runtime composition remain the only application
  authorities.

## Deterministic verification

The focused widget and architecture tests cover live shell transitions,
Sources hierarchy/picker Back, picker failure/retry and IME constraints, Jobs
compact 2× wrapping, Settings semantics, startup recovery, readiness resume,
readiness compact 2× scrolling, and the Android single-engine/predictive-Back
host contract. The repository-wide Flutter/Rust gate remains the final
platform-neutral verification command.

## Native qualification

The repository-owned scenario is
`scripts/run_phase_002_android_adaptive_ux_tests.sh`, using the shared
`run_phase_002_android_scenario_common.sh` helper and
`flutter/integration_test/phase_002_android_adaptive_ux_test.dart`. At the time
of the recorded P02-006 qualification, it accepted the packaged `arm64-v8a` or
`x86_64` API 36 emulator ABI and recorded the actual device ID, API, and ABI
before exercising host window/lifecycle actions,
permission-overlay return, native Back key events through picker hierarchy,
system inset facts, and runtime identity preservation. Host actions use
Flutter baseline/completion markers and per-scenario UI or lifecycle
assertions; command success alone is never recorded as a native pass. IME is
explicitly recorded as unverified/not applicable because the product exposes
no text-input surface. Nested local `PopScope` handling remains ordinary Back
semantics; predictive progress is recorded unverified unless a routed pop
boundary and platform tooling can exercise it.

The current PHASE-002/SPEC-X-002 contract supports only `arm64-v8a`. The
recorded ARM64 qualification remains valid, but historical `x86_64` acceptance
in this slice's tooling is not supported product behavior or valid phase
evidence. P02-007 owns removal of residual non-ARM64 build, packaging, harness,
and CI paths.

The final qualification run on 2026-08-20 UTC used `emulator-5554` at API 36
with ABI `arm64-v8a`; the APK built and installed with the pinned NDK
`28.2.13676358`. The run completed without the prior layout or picker failure.
Live resize, background/foreground, ordinary Back, provider-backed picker
parent navigation/dismissal, system bars/insets, and single-runtime/composition
preservation passed. Rotation now records the opaque Activity-instance
identity before and after the host rotation: the repository manifest keeps the
stock Flutter `configChanges` opt-out, so the expected behavior is an in-place
configuration change (Activity instance preserved, `activity_recreated=false`)
with the same runtime identity (`41524755532d52490000000000000001`) still in
use. Permission-overlay return passes with the full lifecycle pair
(`inactive,hidden,paused,hidden,inactive,resumed`) and the same runtime
identity. The earlier unverified outcomes for background/foreground and
permission-overlay return were a qualification-harness race: the Flutter side
read the host `.done` marker in the window where `adb shell` had created the
file but not yet written its payload, so an empty instruction was treated as a
failed host command even though the action completed. The harness now waits
for non-empty completion content, and the host result is also recorded on the
host side. The first launch after a fresh install can exceed the emulator's
input-response window on this environment, so the harness warms the app once
and hides error dialogs during qualification (both restored in cleanup). The
emulator's fresh-install cold start still occasionally exceeds the input
dispatch window and the system force-finishes the app, so the harness runs up
to three integration attempts with per-attempt host-state restoration; every
attempt requires the same per-scenario Flutter assertions, and the evidence
file records each attempt.

IME is unverified/not applicable because the product has no text-input surface;
deterministic MediaQuery/viewInsets coverage retains the layout behavior.
Predictive Back remains unverified as tooling/framework-unverifiable for the
nested local `PopScope` surface: Flutter 3.44.7 exposes predictive progress
only through `WidgetsBindingObserver.handleStartBackGesture` and
`handleUpdateBackGestureProgress`, which the engine dispatches for routed
`PageRoute` transitions built with `PredictiveBackPageTransitionsBuilder` (the
Android default in 3.44.7). A nested local `PopScope` is not a route: it
exposes only the terminal `onPopInvokedWithResult(didPop, result)`, the picker
is a `DialogRoute` (not a `PageRoute`), and adb cannot assert the native
callback. No second Back or navigation authority was introduced. The evidence
file records one outcome for every required scenario and does not infer native
passes from widget tests or host command success.

The bound delegation remains blocked until the exact
`flutter/integration_test/**` scope amendment can be consumed and all required
PAC/TAC evidence is concretely passed or explicitly accepted as tooling-blocked.
