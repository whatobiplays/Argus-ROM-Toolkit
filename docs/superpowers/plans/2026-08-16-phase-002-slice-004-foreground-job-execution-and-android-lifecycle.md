# Phase 002 Slice 004 — Foreground Job Execution and Android Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an Android `LibraryScan` keep executing through Activity detach/background/screen-off by acquiring one Android `dataSync` foreground-service execution lease at direct user admission, while preserving the existing Rust/SQLite Jobs authority, cancellation/retry contracts, and process-death recovery semantics.

**Architecture:** Android OS hosting stays under `flutter/lib/app/platform/**` and the application-scoped Android host. The foreground service never owns business state: Rust/SQLite continue to own admission, JobRun/ScanRun lifecycle, progress, cancellation, retry, terminal aggregation, and recovery. A small app-bootstrap coordinator decorates the existing Sources/Jobs APIs only at composition time so qualifying user admissions acquire a native lease before the durable backend call. Native service callbacks become typed app-host events; cancellation converges on the existing `JobsApi.cancelJob`, while timeout/loss is forwarded through a bridge-only runtime control into the existing background manager. Activity lifecycle is not runtime lifecycle.

**Tech Stack:** Rust (`argus-application`, `argus-runtime`, `argus-bridge`), Flutter/Dart + Riverpod, Flutter Rust Bridge 2.12, Kotlin/Android foreground services, Android `dataSync` foreground-service type, Bash/ADB native milestone harness.

## Binding Authority and Provenance

Implement against the repository state at plan authoring HEAD `180ece43c5b04831ce4e92f5afd1897e90a5b45a` on `agent/phase-002-slice-003-android-scan`.

Binding authority, in order:

1. `docs/phases/phase-002-android-first-class-platform-support.md` — `SLICE-P02-004`.
2. `docs/specifications/cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md`, especially §9 Foreground Execution Host and §12 Verification Contract.
3. `docs/specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md`, especially the Phase 002 Android foreground-execution amendment.
4. `docs/specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md` — Android host control must not become Android-SDK-shaped business DTOs or a second Jobs transport.
5. `docs/specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md` §86 — Android OS integration belongs to app composition; feature packages do not branch on Android or own lifecycle.
6. `docs/specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md` §150 — foreground-service host control stays behind `app/platform`; native cancellation converges on existing Jobs cancellation rather than becoming a new `ArgusClient` business capability.
7. `docs/specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md` — Jobs remains authoritative; notification is a secondary projection.
8. `docs/superpowers/specs/2026-08-15-phase-002-android-first-class-platform-support-design.md`, especially §9.5 and `SLICE-P02-004`.
9. Existing P02-001..003 implementation and tests, especially application-scoped engine ownership, Android mounted-volume refresh, Add & Scan transport-ambiguity reconciliation, and ARM64 API 36 native harness conventions.

At plan authoring, these existing untracked owner files are unrelated prior work and must be preserved byte-for-byte:

- `docs/superpowers/plans/2026-08-16-phase-002-slice-002-android-localfilesystem-and-argus-folder-picker.md`
- `docs/superpowers/plans/2026-08-16-phase-002-slice-003-android-scan-and-source-hierarchy.md`
- `docs/superpowers/specs/2026-08-16-phase-002-slice-003-android-scan-and-source-hierarchy-design.md`

## Global Constraints

- [ ] Use TDD. For every behavior change, add the failing focused test first, observe the expected failure, implement the minimum production behavior, then rerun the focused test.
- [ ] Keep exactly one application-scoped Flutter engine, Dart isolate/root `ProviderScope`, Rust `ApplicationHost`, and SQLite authority per Android process. Do not create a service-owned engine, isolate, runtime, database, client, or event connection.
- [ ] Do not call `generalShutdown` because an Activity detaches, backgrounds, stops, or is recreated. Activity attachment is only a UI/permission surface.
- [ ] Keep Android SDK concepts, MethodChannel/EventChannel plumbing, service lifecycle, notification construction, and native lease state under app/platform/native Android composition. Sources/Jobs feature packages remain platform-neutral.
- [ ] Do not add foreground-service control as a new Sources/Jobs business capability or a second authoritative Jobs model. `ArgusClient` focused product APIs remain authoritative and unchanged in meaning.
- [ ] Acquire the first execution lease before a qualifying durable admission call. If Android rejects foreground-service acquisition, do not invoke the durable admission call.
- [ ] Do not infer durable job state from native lease state, notification state, timers, or runtime events. Reconcile from authoritative Jobs queries. Events are invalidation/demand only.
- [ ] Preserve P01/P02-003 Add & Scan transport-ambiguity semantics exactly: never replay the composite request after an ambiguous transport failure; recover via the existing root/Jobs authority and only issue explicit `StartLibraryScan` when that authority proves no child was admitted.
- [ ] Native notification cancellation must call the same existing `JobsApi.cancelJob` path as Flutter. Do not add a Kotlin-owned cancellation state or a second cancellation RPC.
- [ ] Live Android execution-host timeout/loss is an ordinary cooperative operation stop, not recovery-only `Abandoned` and never `Interrupted`. Accepted durable user cancellation has precedence if cancellation and host stop race.
- [ ] Process death keeps the existing startup-recovery rule: accepted cancellation -> `Cancelled`; otherwise stale non-resumable `LibraryScan` -> `Abandoned`; no automatic resume.
- [ ] Do not add WorkManager, AlarmManager, `BOOT_COMPLETED`, Android-only schedulers, job resurrection, or deferred foreground-service acquisition.
- [ ] Do not activate Scan All on Android, active-root cancel-and-remove, SAF/content-provider sources, Android 10 support, signing/distribution, permanent CI, or P02-005/P02-006 scope.
- [ ] `just check` remains deterministic, offline, platform-neutral, and free of Android SDK/NDK/ADB/emulator requirements. Native Android evidence stays behind an explicit `just` target.
- [ ] Do not add `WAKE_LOCK` or hold a partial wake lock preemptively. Add it only if the real screen-off milestone fails without it and evidence isolates CPU-suspension as the cause. If added, it must be bounded, executing-only, and released on completion/cancel/timeout/service stop/final lease loss.
- [ ] Do not stage, commit, push, rewrite, or clean unrelated working-tree files.

---

## Task 1 — Add typed background stop semantics for live execution-host loss

**Files:**

- Modify: `rust/crates/argus-application/src/jobs.rs`
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Modify: `rust/crates/argus-runtime/src/background.rs`
- Modify as required by host plumbing: `rust/crates/argus-runtime/src/runtime.rs`
- Test: `rust/crates/argus-runtime/tests/background_manager.rs`
- Test: the existing LibraryScan interaction/integration test module that currently exercises cancellation and scan terminalization; create a focused `rust/crates/argus-runtime/tests/android_foreground_execution.rs` only if no existing test owns this cross-layer behavior cleanly.

### Step 1.1 — Write RED tests for stop-reason precedence and queued behavior

- [ ] Extend `background_manager.rs` with deterministic tests proving:
  - queued `CancellationRequested` still never executes the handler and terminalizes `Cancelled`;
  - queued `ExecutionHostTimeout` never executes the handler and terminalizes `Failed` rather than `Cancelled`, `Interrupted`, or `Abandoned`;
  - queued `ExecutionHostLost` follows the same no-useful-work `Failed` contract;
  - if cancellation and host timeout/loss race, accepted cancellation wins;
  - host-stop notification for an unknown/already-terminal JobRun is an idempotent no-op and does not affect another run;
  - resource ownership is released on every new terminal path.
- [ ] Run the focused test and confirm RED because the manager currently exposes only cancellation.

### Step 1.2 — Introduce one closed application-owned stop vocabulary

- [ ] In `argus-application/src/jobs.rs`, add a platform-neutral closed enum:

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BackgroundOperationStopReason {
    CancellationRequested,
    ExecutionHostTimeout,
    ExecutionHostLost,
}
```

- [ ] Change `BackgroundOperationHandler::execute` from a cancellation-only predicate to a stop-reason query:

```rust
fn execute(
    &self,
    context: &OperationContext,
    stop_reason: &dyn Fn() -> Option<BackgroundOperationStopReason>,
    progress: &dyn JobProgressReporter,
) -> Result<OperationCompletion, ApplicationError>;
```

- [ ] Replace the cancellation-only pre-execution hook with a typed hook:

```rust
fn stopped_before_execution(
    &self,
    context: &OperationContext,
    reason: BackgroundOperationStopReason,
) -> Result<(), ApplicationError>;
```

The manager remains the parent JobRun terminalization owner; operation handlers use the hook only to terminalize operation-specific child state such as ScanRun/root last-scan facts.

### Step 1.3 — Give `BackgroundOperationManager` a reason-bearing stop token

- [ ] Do not overload the general runtime `operations::CancellationToken` with Android-specific semantics. Keep a background-manager-private atomic stop token whose bitset can retain simultaneous reasons.
- [ ] Precedence when reading the token is deterministic:
  1. `CancellationRequested`
  2. `ExecutionHostTimeout`
  3. `ExecutionHostLost`
- [ ] Keep `notify_cancellation(job_run_id)` semantics unchanged except that it sets the cancellation bit.
- [ ] Add a targeted manager method such as:

```rust
pub fn notify_execution_host_stop(
    &self,
    job_run_id: JobRunId,
    reason: BackgroundOperationStopReason,
);
```

Reject `CancellationRequested` at this host-stop entrypoint; cancellation continues through `notify_cancellation` after durable `CancelJob` acceptance.
- [ ] `shutdown()` keeps its existing cooperative cancellation behavior; it does not masquerade as Android host timeout.
- [ ] Before handler execution, map host timeout/loss to parent `Failed`; map cancellation to parent `Cancelled`.

### Step 1.4 — Make LibraryScan terminalize from stop reason without destructive finalization

- [ ] Convert the scan handler's local `is_cancelled` use to `should_stop = || stop_reason().is_some()` only at provider/enumeration checkpoints; provider APIs remain boolean and do not learn runtime host concepts.
- [ ] At every scan stop checkpoint, inspect the typed reason:
  - cancellation -> existing `finish_cancelled`;
  - timeout/loss with `entries_committed > 0` -> per-root `Partial`, root last-scan `Partial`, aggregate `CompletedWithIssues`, with stable failure reason `execution_host_timeout` or `execution_host_lost`;
  - timeout/loss with no meaningful committed indexing result -> per-root/root last-scan `Failed`, aggregate `Failed`, with the corresponding stable failure reason.
- [ ] Do not run deferred absence finalization after any stop reason. Earlier committed positive checkpoints remain authoritative; uncommitted work may be lost.
- [ ] In `stopped_before_execution`, cancellation terminalizes the child `Cancelled`; timeout/loss terminalizes the child/root `Failed` because no useful indexing work occurred.
- [ ] Add focused scan tests for partial-on-timeout, failed-without-progress, host-lost, no destructive absence finalization, and cancellation-over-timeout precedence.

### Step 1.5 — Run the Rust-focused gates

- [ ] Run the focused background-manager tests.
- [ ] Run the focused LibraryScan tests.
- [ ] Run the relevant `argus-application`/`argus-runtime` crate suites before moving on.

---

## Task 2 — Expose a bridge-only execution-host stop control without changing product APIs

**Files:**

- Modify: `rust/crates/argus-runtime/src/runtime.rs`
- Modify: `rust/crates/argus-bridge/src/lib.rs`
- Modify generated output only via generator: `rust/crates/argus-bridge/src/frb_generated.rs`, `flutter/lib/core/bridge/generated/**`
- Create: `flutter/lib/core/bridge/src/frb_execution_host_control.dart`
- Modify export if required: `flutter/lib/core/bridge/bridge.dart`
- Test: `rust/crates/argus-bridge/**` existing bridge tests
- Test: `flutter/test/core/bridge/frb_execution_host_control_test.dart`

### Step 2.1 — Write RED bridge/runtime tests

- [ ] Add tests proving a targeted live host timeout reaches only the requested active JobRuns, races safely with terminal completion, rejects malformed IDs at the bridge boundary, and cannot encode cancellation through this path.
- [ ] Add a Dart bridge-adapter test with an injected generated API proving timeout/loss requests are translated without exposing generated DTOs to app/bootstrap or feature code.

### Step 2.2 — Add a bounded runtime host-control entrypoint

- [ ] Add an `ApplicationHost` method that accepts a bounded set of validated `JobRunId`s and one host-stop reason (`ExecutionHostTimeout` or `ExecutionHostLost`) and forwards each still-owned run to `BackgroundOperationManager::notify_execution_host_stop`.
- [ ] A terminal or no-longer-owned ID is a successful no-op; this is a race-safe execution-host control, not a business query result.
- [ ] The method must use the current runtime generation/operation guard conventions and must not create a second manager or persistence connection.

### Step 2.3 — Add a generic bridge request, not an Android DTO family

Use a small transport vocabulary such as:

```rust
pub enum ExecutionHostStopReasonDto {
    Timeout,
    HostLost,
}

pub struct ReportExecutionHostStopRequestDto {
    pub job_run_ids: Vec<String>,
    pub reason: ExecutionHostStopReasonDto,
}
```

- [ ] Bound the request size to the existing background-operation capacity; reject empty/oversized/malformed input as the existing validation error class.
- [ ] Add `report_execution_host_stop(request)` to `argus-bridge` and map only `Timeout`/`HostLost`; do not add cancellation here.
- [ ] Keep the existing Jobs DTOs and `cancel_job` endpoint unchanged.

### Step 2.4 — Add a bridge-only Dart adapter

- [ ] `FrbExecutionHostControl` may depend on generated FRB types internally, but its public method accepts pure client `JobRunId` values plus a closed Dart host-stop reason.
- [ ] Reuse the existing application/transport failure mapping rather than leaking `ApplicationErrorDto` or generated exception classes.
- [ ] Do **not** add this control to `SourcesApi`, `JobsApi`, `RuntimeApi`, or `ArgusClient` focused product capabilities. It is consumed only by app-bootstrap/platform hosting.

### Step 2.5 — Regenerate and run focused gates

- [ ] Run `just generate` after the Rust bridge signature is final; never hand-edit generated Dart/Rust bridge files.
- [ ] Run bridge Rust tests and `flutter/test/core/bridge/frb_execution_host_control_test.dart`.

---

## Task 3 — Implement the application-scoped Android `dataSync` foreground execution host

**Files:**

- Modify: `flutter/android/app/src/main/AndroidManifest.xml`
- Modify: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusApplication.kt`
- Create: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusForegroundExecutionHost.kt`
- Create: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusForegroundExecutionBridge.kt`
- Create: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusForegroundExecutionService.kt`
- Keep `MainActivity.kt` free of runtime/service ownership; modify it only if a test exposes a missing attachment-forwarding requirement.

### Step 3.1 — Declare the exact Android service contract

- [ ] Add `android.permission.FOREGROUND_SERVICE` and `android.permission.FOREGROUND_SERVICE_DATA_SYNC`.
- [ ] Register one non-exported service with `android:foregroundServiceType="dataSync"`.
- [ ] Do not add `BOOT_COMPLETED`, WorkManager, AlarmManager, a restart receiver, or `WAKE_LOCK` at this stage.

### Step 3.2 — Add an application-owned transient lease host

`ArgusApplication` owns the host and bridge alongside the existing cached `FlutterEngine`:

- [ ] Lease IDs are opaque process-local values only; never persist them.
- [ ] First acquisition calls `startForegroundService` while the user-admission call is still in the foreground-eligible path.
- [ ] Acquisition completes back to Dart only after the service has successfully entered foreground state with a minimal “Preparing library scan” notification. If `startForegroundService`/promotion is rejected, remove the provisional lease and return a typed platform error; no backend admission has happened yet.
- [ ] Later acquisitions while the same service is live add process-local leases without creating another service/runtime.
- [ ] Release is idempotent. Releasing the final lease stops the service; no active lease means no service.
- [ ] A short bounded native start-ack watchdog may fail a stuck acquisition, but it must only decide whether acquisition succeeded; it must never invent Jobs state or terminalize work itself.

### Step 3.3 — Make the service a host, not an authority

- [ ] `ArgusForegroundExecutionService` returns `START_NOT_STICKY`.
- [ ] It uses the application-owned host and cached engine; it never initializes Flutter/Rust/SQLite itself.
- [ ] Its notification is a bounded secondary projection. Start with generic scan-in-progress content, active-job count/progress when supplied, and a Cancel action only when Dart supplies one unambiguous cancellable `JobRunId`.
- [ ] The Cancel `PendingIntent` may target the existing service with an explicit action + job ID. Handling it only emits a native host event to Dart; it does not mutate native Jobs state and does not stop the service until authoritative reconciliation releases the final lease.
- [ ] Notification permission state is not a prerequisite for service acquisition. Android still receives the required foreground-service notification object; denied `POST_NOTIFICATIONS` must not reject otherwise-valid foreground execution.

### Step 3.4 — Handle Android timeout and unexpected live host loss

- [ ] On API 35+ `Service.onTimeout(startId, fgsType)`, emit one `ExecutionHostTimeout` event to the application-scoped Dart host and call `stopSelf` within the callback/grace window. Do not restart the service automatically.
- [ ] Distinguish an expected final-lease stop from unexpected service destruction while the process remains alive. Unexpected destruction emits `ExecutionHostLost`; it does not try to reacquire itself.
- [ ] Timeout/loss invalidates native lease hosting state so stale releases remain harmless and a later direct user action may perform a fresh foreground acquisition if Android permits it.
- [ ] Process death needs no callback contract: all native lease state disappears and Rust startup recovery remains the sole durable recovery authority.

### Step 3.5 — Keep Activity lifecycle orthogonal

- [ ] Preserve `MainActivity.shouldDestroyEngineWithHost() == false` and the application cached-engine path.
- [ ] `onStart`/`onStop` may continue to attach/detach only Activity-required readiness surfaces. Neither path acquires/releases foreground leases, shuts down the runtime, or rebuilds app composition.

---

## Task 4 — Add the pure-Dart host port and app-bootstrap foreground execution coordinator

**Files:**

- Create: `flutter/lib/app/platform/application/foreground_execution_host_api.dart`
- Create: `flutter/lib/app/platform/native/android_foreground_execution_host_api.dart`
- Modify: `flutter/lib/app/platform/native/platform_host_factory.dart`
- Modify export: `flutter/lib/app/platform/platform_host.dart`
- Create: `flutter/lib/app/bootstrap/foreground_execution_coordinator.dart`
- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart`
- Modify only if needed for DI/test seams: `flutter/lib/app/bootstrap/client_bootstrap.dart`
- Do not modify feature controllers to know Android/foreground services.

### Step 4.1 — Define a pure Dart OS-host port

Use a closed app-platform model equivalent to:

```dart
abstract interface class ForegroundExecutionHostApi {
  Stream<ForegroundExecutionHostEvent> get events;
  Future<ForegroundExecutionLease> acquireLibraryScanLease();
  Future<void> releaseLease(ForegroundExecutionLease lease);
  Future<void> updateProjection(ForegroundExecutionProjection projection);
}
```

Required event variants:

- `ForegroundExecutionCancelRequested(JobRunId jobRunId)`
- `ForegroundExecutionTimedOut()`
- `ForegroundExecutionHostLost()`

The projection is bounded and non-authoritative: active LibraryScan count, optional completed/total units, optional phase/status key, and at most one unambiguous cancellable `JobRunId`. Do not send raw paths, provider locators, persisted execution snapshots, or Android SDK objects through Dart.

### Step 4.2 — Add the Android MethodChannel/EventChannel adapter

- [ ] Use one command channel (for example `argus/foreground_execution`) for acquire/release/projection and one event channel for host events.
- [ ] Validate every native map/string into the closed Dart types; malformed responses are transport/contract failures.
- [ ] Add the host API as an optional member of `PlatformHostComposition`. Android supplies it; desktop supplies `null` and therefore retains the raw current APIs exactly.
- [ ] Keep `Platform.isAndroid` only in `platform_host_factory.dart`, the existing sole production OS-selection point.

### Step 4.3 — Compose qualifying admission behind API decorators

Create one app-lifetime `ForegroundExecutionCoordinator` that receives:

- raw `SourcesApi` from the current `ArgusClient`;
- raw `JobsApi` from the current `ArgusClient`;
- `EventsApi` for invalidation demand;
- Android `ForegroundExecutionHostApi`;
- bridge-only `FrbExecutionHostControl` (or an injected equivalent test closure).

Expose two forwarding wrappers consumed only by app composition:

1. `ForegroundHostedSourcesApi`
2. `ForegroundHostedJobsApi`

All query/nonqualifying methods delegate unchanged. Qualifying P02-004 calls are:

- `SourcesApi.addLocalLibraryRootAndScan`
- `SourcesApi.startLibraryScan` (including Scan Again)
- `JobsApi.retryJob` **only after an authoritative `getJob` proves the source operation is `LibraryScan` and retry is applicable**.

`startLibraryScanAll` remains a raw pass-through in P02-004 because Android Scan All activation belongs to P02-005.

For each qualifying call:

1. acquire a native lease and await native foreground-start acknowledgement;
2. only then invoke the raw durable admission call exactly once;
3. reconcile retained lease count from authoritative active Jobs after the response or transport ambiguity;
4. rethrow the original typed result/failure to the existing feature controller.

If lease acquisition fails, never call the raw admission API.

### Step 4.4 — Use a count invariant instead of inventing lease-to-job authority

The coordinator owns only transient leases. It does **not** bind business identity into native lease state.

After a qualifying admission attempt or relevant runtime event:

- query `listActiveJobs` and filter authoritative active `library_scan` rows;
- release surplus native leases until retained lease count matches the authoritative active qualifying-job count;
- never acquire a new lease merely because an event/query reports active work — acquisition is permitted only on a direct user admission path;
- if authoritative active qualifying jobs exceed retained leases, treat that as execution-host loss: report `ExecutionHostLost` for the active qualifying JobRun IDs and do not attempt background reacquisition.

This count invariant handles normal admission, AlreadyScanning/AlreadyRetried, and Add & Scan transport ambiguity without replaying a business command or guessing which native token “owns” a job.

If the post-ambiguity Jobs query itself temporarily fails, retain the provisional lease and run at most one in-process authoritative reconciliation retry loop. The loop may retry queries/events; it may not synthesize terminal state, schedule Android work, or release an ambiguous lease solely because a wall-clock timeout elapsed.

### Step 4.5 — Project native notification from Jobs authority

- [ ] Runtime `JobStateChanged`/`JobProgress` events only schedule authoritative reconciliation; do not mutate projection directly from event payloads.
- [ ] After a successful Jobs read, update the native projection with current active LibraryScan count and bounded progress.
- [ ] Supply a native Cancel action only when exactly one target is unambiguous and backend `canCancel` is true. Multi-job ambiguity keeps cancellation in the Flutter Jobs UI rather than guessing.
- [ ] When the final authoritative qualifying active job leaves active state, release every remaining lease and clear the projection.

### Step 4.6 — Route native control back to the existing authorities

- [ ] `CancelRequested(jobRunId)` -> call the **raw existing** `JobsApi.cancelJob(jobRunId)` exactly once; do not fabricate `CancellationRequested` locally. Reconcile from Jobs after result/event.
- [ ] `TimedOut` -> query authoritative active LibraryScan JobRun IDs, call the bridge-only execution-host stop control with reason `Timeout`, invalidate/release local native leases, and let Rust terminalize at its next safe checkpoint.
- [ ] `HostLost` -> same flow with reason `HostLost`.
- [ ] Never convert timeout/loss into `JobsApi.cancelJob`; cancellation has distinct durable user-intent semantics.

### Step 4.7 — Wire app composition without feature branching

- [ ] In Android composition, override `sourcesApiProvider`, `jobsApiProvider`, and `sourcesJobsApiProvider` with coordinator-forwarded APIs; desktop keeps direct `ArgusClient` APIs.
- [ ] Keep the coordinator/application host lazy until platform readiness has admitted normal app startup.
- [ ] Do not add `Platform.isAndroid`, MethodChannel, foreground-service imports, or host-lifecycle state under `features/sources/**` or `features/jobs/**`.

---

## Task 5 — Add deterministic Flutter/architecture regression coverage

**Files:**

- Create: `flutter/test/app/platform/android_foreground_execution_host_api_test.dart`
- Create: `flutter/test/app/bootstrap/foreground_execution_coordinator_test.dart`
- Modify: `flutter/test/app/bootstrap/app_bootstrap_test.dart`
- Modify existing architecture tests under: `flutter/test/architecture/**`
- Modify existing Sources Add & Scan tests only to assert preserved behavior where necessary; do not rewrite their authority model.

### Step 5.1 — Platform adapter tests

- [ ] MethodChannel acquire returns a validated opaque lease; release/projection emit the exact bounded wire shape.
- [ ] EventChannel maps cancel/timeout/host-lost into closed Dart events and rejects malformed job IDs/event payloads.
- [ ] Notification permission state is not accepted as an acquire prerequisite in Dart.

### Step 5.2 — Coordinator admission-order tests

Using fakes that record call order, prove:

- [ ] native acquire completes before raw Add & Scan / Start Scan / qualifying Retry is invoked;
- [ ] acquire failure means raw admission call count remains zero;
- [ ] a successful admitted active scan retains the lease;
- [ ] AlreadyScanning/non-admission/terminal-before-reconcile releases surplus lease authority correctly;
- [ ] Add & Scan transport ambiguity calls the composite exactly once and reconciles lease count from active Jobs; it never replays the composite;
- [ ] when the existing Sources controller subsequently performs its authority-driven explicit `startLibraryScan`, that second direct admission gets its own pre-admission lease normally;
- [ ] `startLibraryScanAll` remains pass-through in P02-004.

### Step 5.3 — Jobs/control tests

- [ ] Retry acquires only for an authoritative retryable LibraryScan and keeps existing `AlreadyRetried` idempotency.
- [ ] Native cancel calls the existing raw `JobsApi.cancelJob` exactly once and never writes local terminal state.
- [ ] Timeout/loss never calls `cancelJob`; it calls bridge-only host stop with the authoritative current active LibraryScan IDs.
- [ ] Cancellation racing timeout remains `Cancelled` once backend cancellation intent is accepted.
- [ ] Relevant runtime events cause Jobs queries/reconciliation rather than direct state mutation.
- [ ] Active-jobs > retained-leases never triggers background lease acquisition; it triggers typed host loss.
- [ ] Terminal authority releases the final lease and clears notification projection.

### Step 5.4 — Composition/architecture tests

- [ ] Android uses the foreground-hosted API decorators after readiness; desktop remains byte-for-behavior compatible with raw APIs.
- [ ] One root ProviderScope/client composition remains intact.
- [ ] Add architecture guards preventing Android SDK concepts/MethodChannel/EventChannel/`Platform.isAndroid` from entering Sources/Jobs feature layers.
- [ ] Preserve existing P02-003 presentation capabilities: single-root scan enabled; Scan All and active-root cancel-and-remove still disabled.

---

## Task 6 — Add the repository-owned real Android P02-004 milestone

**Files:**

- Create: `flutter/integration_test/phase_002_android_foreground_execution_test.dart`
- Create: `scripts/run_phase_002_android_foreground_execution_tests.sh`
- Modify: `justfile`
- Modify native/manifest code for a partial wake lock **only if Step 6.6 produces causal evidence that it is required**.

Add an explicit target such as:

```make
# Native Android prerequisite gate; intentionally not part of `check`.
test-phase-002-android-foreground:
    bash scripts/run_phase_002_android_foreground_execution_tests.sh
```

Reuse P02-003 conventions: Apple Silicon-compatible ARM64 emulator/device, API 36 milestone, repository-owned bridge build, app install, All files access setup, controlled external-storage fixtures, and dual-ABI APK packaging verification.

### Step 6.1 — Dual-ABI/package and service declaration gate

- [ ] Build the Android app and assert both required 64-bit Rust libraries remain packaged (`arm64-v8a` and `x86_64`) even though the real milestone executes on ARM64.
- [ ] Assert manifest/package metadata declares the non-exported `dataSync` service plus `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_DATA_SYNC` and no BOOT receiver/WorkManager path.

### Step 6.2 — Foreground/background continuity with notification permission granted

- [ ] Seed a fixture large enough that a scan remains active long enough for lifecycle operations.
- [ ] Start the scan through the real Android UI/client path while the Activity is visible and capture authoritative `RuntimeInstanceId` + `JobRunId`.
- [ ] Wait until the foreground service is observable through Android service diagnostics, then background the Activity.
- [ ] Re-enter the Activity and prove the same runtime generation and JobRun continue; no second engine/runtime/job is admitted.
- [ ] Verify terminal state/root hierarchy from existing authoritative APIs, not from notification text.

### Step 6.3 — Real Activity detach/recreate without runtime teardown

- [ ] Exercise an OS-owned Activity destruction/recreation path while keeping the application process/foreground service alive (for the controlled emulator, the harness may temporarily enable the platform “Don’t keep activities” behavior, background, then relaunch the Activity; always restore the setting in `trap` cleanup).
- [ ] Prove the Dart isolate/application host remains the same generation and the admitted JobRun is neither duplicated nor abandoned solely because the Activity changed.
- [ ] Assert no `generalShutdown`/startup-replacement lifecycle transition occurred.

### Step 6.4 — Notification denial does not block foreground execution

- [ ] Revoke/deny `POST_NOTIFICATIONS`, then start a new qualifying scan by direct user action.
- [ ] Prove native foreground service acquisition succeeds and the scan continues while the Activity is backgrounded.
- [ ] Prove Jobs/root terminal state is correct. Do not require a notification-drawer action when permission is denied; Android may expose only its system foreground-service/task-manager notice.

### Step 6.5 — Exercise the real notification Cancel action

- [ ] With notification permission granted, run the Flutter integration scenario in a mode that starts a long scan and waits for authoritative cancellation.
- [ ] From the host harness, wait for the real Argus foreground notification, expand the notification shade, locate the visible `Cancel` action through `uiautomator` bounds, and invoke it. Do not call a debug-only cancellation RPC or fabricate a Jobs mutation.
- [ ] The integration scenario must observe the same JobRun transition through durable `CancellationRequested` to terminal `Cancelled`; root/ScanRun cancellation must match the existing Jobs contract and the service must stop after final lease loss.

### Step 6.6 — Screen-off CPU continuity and wake-lock decision

- [ ] Run first with **no** `WAKE_LOCK` permission and no partial wake lock.
- [ ] While a sufficiently long scan and the foreground service are active, record authoritative progress, send the device to sleep/screen-off for a controlled interval, wake it, and prove either the job terminalized or committed progress advanced.
- [ ] If this passes, keep wake-lock code/permission absent.
- [ ] Only if it reproducibly fails and evidence isolates CPU suspension (not fixture exhaustion, provider loss, timeout budget, test-driver loss, or Activity teardown), add a bounded partial wake lock owned by the service host. Then prove it is held only while qualifying work is actually executing and released on completion, cancellation, timeout, service stop, and final lease loss. Record the causal evidence in `RESULT.json`.

### Step 6.7 — Exercise the real Android 15+ `dataSync` timeout

On the API 36 target, use Android's platform test controls rather than an app-only fake:

```bash
adb shell am compat enable FGS_INTRODUCE_TIME_LIMITS dev.argusromtoolkit.argus
adb shell device_config put activity_manager data_sync_fgs_timeout_duration <short-test-duration-ms>
```

- [ ] Start a long scan from visible UI, move the app to background so the `dataSync` budget is consumed, and wait for the platform `Service.onTimeout` callback.
- [ ] Assert the service stops within the platform grace window and does not auto-restart.
- [ ] Assert the live JobRun never becomes `Abandoned`/`Interrupted`: useful committed work -> root `Partial` + aggregate `CompletedWithIssues`; no useful result -> `Failed`. If durable cancellation was accepted first, `Cancelled` wins.
- [ ] Restore/delete the modified `device_config`/compat test setting in the script's unconditional cleanup trap.

### Step 6.8 — Process death and no-auto-resume recovery

- [ ] Start an active hosted scan, confirm the service is live, then kill/force-stop the process before terminalization.
- [ ] Relaunch explicitly. Prove no foreground service/job auto-resumes on startup.
- [ ] Prove existing startup recovery terminalizes stale non-resumable LibraryScan as `Abandoned` when no durable cancellation intent had been accepted.
- [ ] Where existing deterministic recovery coverage already proves accepted cancellation -> `Cancelled`, keep that rule covered; do not invent an Android-specific recovery state.

### Step 6.9 — Native harness cleanup invariants

- [ ] `trap` cleanup restores notification/storage grants as appropriate, screen state, “Don’t keep activities”, timeout `device_config`/compat flags, temporary fixtures, and any test-owned app state.
- [ ] The script fails loudly if the wrong ABI/device/API is selected; it must not silently fall back to an incompatible x86_64 emulator on Apple Silicon.
- [ ] `just check` remains unchanged in dependency graph and never invokes this target.

---

## Task 7 — Full verification, scope audit, and delegation result

### Step 7.1 — Generated-code and static gates

- [ ] Run `just generate` once final bridge signatures are stable.
- [ ] Run focused Rust and Flutter tests from Tasks 1–5.
- [ ] Run `just check` and confirm it remains platform-neutral.
- [ ] Run `just test-phase-002-android-foreground` on the repository-owned ARM64 API 36 environment.

### Step 7.2 — Invariant review before completion

Inspect the final diff and prove all of the following:

- [ ] no second Flutter engine/Dart isolate/Rust runtime/SQLite authority;
- [ ] no Activity-owned runtime lifetime;
- [ ] no foreground-service state persisted as Jobs truth;
- [ ] no feature-layer Android branches or direct channels;
- [ ] no new cancellation authority and no timeout-via-`CancelJob` shortcut;
- [ ] no live timeout/loss -> `Abandoned`/`Interrupted` path;
- [ ] no Add & Scan composite replay regression;
- [ ] no Scan All activation or P02-005+ scope;
- [ ] no WorkManager/BOOT/deferred scheduler;
- [ ] no wake lock unless Step 6.6 produced and recorded causal evidence;
- [ ] final active qualifying job terminalization releases the service;
- [ ] process death still recovers with existing `Cancelled`/`Abandoned`, never auto-resume;
- [ ] all prior unrelated untracked owner files remain byte-identical.

### Step 7.3 — Completion evidence

- [ ] Write the Delegation v3 `RESULT.json` with exact commands/outcomes, touched paths, native device/API/ABI facts, timeout evidence, notification-denial evidence, Activity recreation evidence, process-death recovery evidence, and the wake-lock decision plus rationale.
- [ ] If any required native milestone cannot be run, mark the relevant acceptance criterion unverified/failed rather than claiming completion.
- [ ] Leave implementation changes uncommitted for owner review.
