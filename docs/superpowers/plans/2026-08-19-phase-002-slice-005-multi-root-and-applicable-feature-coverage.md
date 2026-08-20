# Phase 002 Slice 005: Multi-Root and Applicable Feature Coverage Implementation Plan

> **For agentic workers:** Execute this plan task-by-task with TDD. Preserve the existing branch and do not stage, commit, or push changes.

**Goal:** Activate the existing Phase 001 multi-root, Scan All, safe-removal, job-recovery, permission-loss, removable-volume, and diagnostics capabilities on Android without moving authority into Flutter or Android.

**Architecture:** Reuse the existing Rust/application Sources and Jobs contracts. Android composition enables the existing workflows. Platform readiness continues to gate presentation, while a narrowly scoped storage-readiness demand refreshes Sources only when a relevant readiness/storage transition requires an authoritative availability read; Jobs remains event/recovery-authoritative unless a concrete job-state event requires its existing reconciliation. Android diagnostics use one backend-owned relative artifact contract and a native FileProvider publication bridge.

**Tech Stack:** Flutter/Riverpod, Rust/FRB, SQLite, Kotlin/Android API 36, AndroidX FileProvider, existing foreground-service and mounted-volume bridges.

## Global Constraints

- Create this plan before production changes; do not stage, commit, or push.
- Preserve P02-004 foreground-service ownership, cancellation, timeout, host-loss, and restart semantics.
- Rust/application remains authoritative for roots, jobs, admission, reconciliation, persistence, and terminal states.
- Android is limited to readiness facts, mounted-volume facts, and diagnostic publication.
- Do not add SAF/content-provider libraries, WorkManager, Android 10 support, Google Play support, P02-006 UX, or P02-007 physical-device scope.
- Run a focused failing test before every production behavior change.
- Generated FRB, Riverpod, and Freezed files are refreshed only through their generators.
- Preserve unrelated existing untracked artifacts in `docs/superpowers/`.

## Task 1: Correct the binding plan and establish the baseline

**Files:**

- Modify: this plan file.
- Read: `docs/superpowers/specs/2026-08-19-phase-002-slice-005-multi-root-and-applicable-feature-coverage-design.md`.
- Test: existing focused Flutter and Rust suites.

- [x] Record the seven required corrections in this plan before production edits.
- [x] Run the focused baseline tests and record their actual result in the implementation notes.
- [x] Do not run repository commands that rewrite generated files until the implementation reaches the generation step.

## Task 2: Activate Android Sources workflows with transition-scoped storage refresh

**Files:**

- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart`.
- Modify: `flutter/lib/features/sources/sources_composition.dart`.
- Modify: `flutter/lib/app/platform/application/platform_readiness_controller.dart` only if the existing state transition cannot expose the required signal without changing authority.
- Modify: `flutter/lib/app/bootstrap/sources_event_coordinator.dart`.
- Preserve: `flutter/lib/app/bootstrap/jobs_event_coordinator.dart` unless a concrete job-state transition test proves its existing event/recovery demand is insufficient.
- Test: `flutter/test/app/bootstrap/app_bootstrap_test.dart`, `flutter/test/app/platform/platform_readiness_*_test.dart`, and Sources coordinator/controller tests.

**Required behavior:**

1. Android composition enables `singleRootScanExecution`, `scanAllExecution`, and `activeRootCancelAndRemove`, while retaining `localFilesystemBrowser`.
2. Android enables diagnostics export but keeps `openDataDirectory` disabled.
3. A regrant transition from `RequiresAllFilesAccess` to `Ready` emits exactly one Sources roots-changed demand. The existing Sources authoritative read then refreshes mounted-volume facts and root availability.
4. A removable-volume/storage-fact re-evaluation emits a Sources refresh only through an explicit storage/readiness transition signal. An unchanged lifecycle resume does not automatically refresh Sources or Jobs merely because the app resumed.
5. Jobs continues to refresh through its existing runtime event stream and restart/recovery reconciliation. Do not add a platform-resume Jobs refresh. Add a Jobs demand only when a concrete job-state event or recovery boundary already requires it.
6. Repeated readiness notifications are coalesced so one transition cannot cause duplicate root reads or a refresh loop. No scan, retry, resume, or client replacement is triggered.

**TDD order:**

- [x] Add a failing test for Android capability activation.
- [x] Add failing readiness tests for one regrant-triggered Sources refresh, no refresh on unchanged resume, no duplicate refresh loop, and no Jobs refresh from unchanged resume.
- [x] Run the focused tests and verify the failures identify the missing composition behavior.
- [x] Implement the smallest composition/readiness demand change.
- [x] Regenerate Riverpod sources and run the focused suites.

## Task 3: Qualify existing shared Phase 001 semantics before changing them

**Files:**

- Test: existing Rust scan/admission/reconciliation/job suites under `rust/crates/argus-application`, `rust/crates/argus-runtime/tests`, and `rust/crates/argus-bridge/tests`.
- Test: `flutter/test/features/sources/slice_006_scan_all_and_remove_test.dart` and related Sources/Jobs tests.

- [x] Add or strengthen tests for partial Scan All eligibility, typed exclusions, `NothingEligible` with no job, aggregate terminalization, job-scoped cancellation, and retry with a new job ID.
- [x] Add a multi-root Cancel Scan & Remove test that proves the disclosure names the other owned roots, cancellation targets the owning multi-root job, settled ownership is re-read before removal, and only Argus-managed root/index state changes.
- [x] Add permission-loss/removable-loss tests proving configured roots, index, history, and unrelated roots remain durable and that absence is not treated as deletion authority.
- [x] Run the tests before changing shared production code. The intended implementation result is reuse of the current Phase 001 semantics; only a concrete failing test may justify a minimal shared fix.

## Task 4: Add an additive Android diagnostics sharing operation

**Files:**

- Modify: `rust/crates/argus-runtime/src/runtime.rs` and the existing diagnostics writer module.
- Modify: `rust/crates/argus-bridge/src/lib.rs`.
- Modify: `flutter/lib/core/client/src/ports.dart`, client implementation, and `flutter/lib/core/bridge/src/frb_argus_client_gateway.dart`.
- Generate: FRB outputs under `rust/crates/argus-bridge/src/frb_generated.rs` and `flutter/lib/core/bridge/generated/`.
- Test: Rust diagnostics tests, bridge contract tests, client tests, gateway tests, and updated fakes.

**Public contract:** Preserve the desktop API exactly:

```dart
Future<DiagnosticsExport> exportStartupDiagnostics(
  RuntimeInstanceId expected,
  String destination,
);
```

Add an Android-only additive operation:

```dart
Future<DiagnosticsExport> exportStartupDiagnosticsForSharing(
  RuntimeInstanceId expected,
);
```

**Single artifact-location contract:**

- Rust owns the relative contract `diagnostics/startup-diagnostics-v1.zip` beneath the already-authoritative runtime data directory supplied during Android bootstrap.
- Rust creates, sanitizes, bounds, validates, and atomically publishes the archive; the backend never exposes the absolute path.
- Kotlin receives no path and does not independently choose another “equivalent” root. It resolves the same relative contract beneath the Android application data directory that is already supplied as the runtime standard data directory.
- Kotlin validates only publication concerns: exact confined location, regular-file/existence, bounded size, Activity availability, FileProvider confinement, and share-intent construction. It does not parse or semantically validate ZIP contents.
- Flutter receives only the existing safe `DiagnosticsExport` summary. No filesystem path or content URI crosses into Flutter state, errors, logs, safe context, or the diagnostic manifest.

**TDD order:**

- [x] Add failing Rust tests for runtime-bound export, sanitized output, atomic completion, and absence of raw path/auth fields.
- [x] Add failing bridge/client tests for the additive no-destination operation while retaining desktop destination tests.
- [x] Run the red tests.
- [x] Implement the backend operation and regenerate FRB sources.
- [x] Run Rust, bridge, client, and generated-source checks.

## Task 5: Compose presentation flow without moving export authority

**Files:**

- Create: a pure startup application port for `StartupDiagnosticsExporter`.
- Modify: `flutter/lib/features/startup/application/startup_controller.dart`.
- Modify: `flutter/lib/features/startup/presentation/startup_failure_view.dart` and existing presentation seams.
- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart`.
- Test: startup controller/view tests and desktop/Android composition tests.

- [x] Add failing tests proving desktop still invokes the destination-based API and Android invokes backend export followed by native publication without a picker.
- [x] Implement the exporter abstraction as presentation-flow composition only; Rust remains the export authority.
- [x] Preserve desktop cancellation behavior and safe destination classification.
- [x] Make Android success/failure copy use only safe classifications and typed platform errors.

## Task 6: Implement the bounded Android publication bridge

**Files:**

- Create: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusDiagnosticsShareBridge.kt`.
- Modify: `ArgusApplication.kt` and `MainActivity.kt` for registration and Activity attach/detach.
- Modify: `AndroidManifest.xml`.
- Create: `res/xml/argus_file_paths.xml` restricted to `argus/diagnostics/`.
- Test: Kotlin unit/instrumentation tests for bridge validation and intent construction.

- [x] Add failing native tests for no Activity, missing artifact, path traversal, non-regular artifact, oversized artifact, and unrestricted FileProvider paths.
- [x] Implement `argus/diagnostics_share` with `shareCompletedStartupDiagnostics` only.
- [x] Publish the completed backend artifact through a non-exported AndroidX FileProvider and `ACTION_SEND` chooser with read permission.
- [x] Return stable bounded error codes; never include path or URI data in errors/logs/results.
- [x] Run native tests and Android debug compilation with the Rust Android packaging task isolated; full packaging remains environment-dependent on an installed Android NDK.

## Task 7: Build independently diagnosable Android qualification scenarios

**Files:**

- Create focused integration tests under `flutter/integration_test/`.
- Create focused scripts under `scripts/run_phase_002_android_*`.
- Add focused `justfile` targets.

Use separate scenario invocations rather than one long sequential harness:

1. `multi_root_scan_all`: two roots, independent child work, aggregate job, and Jobs history.
2. `partial_eligibility`: one unavailable configured root, typed exclusion, then all unavailable with no job.
3. `cancel_and_remove`: active multi-root Scan All, disclosure, job-scoped cancel, settled ownership proof, root-only Argus cleanup.
4. `permission_loss`: deterministic active-work window, reversible `appops` revoke/regrant, truthful affected terminal state, durable index/history, no auto-resume.
5. `removable_volume`: explicit real-volume qualification described below.
6. `diagnostics_share`: backend export plus native share publication and safe channel result.
7. Reuse the existing P02-004 foreground/restart scenario as a separate regression command.

Do not inflate fixtures or runtime merely to create lifecycle windows; use deterministic coordination already present in the test harness and bounded fixture sizes.

**Removable-volume mechanism:**

- The script first records mounted public volumes, adoptable disks, and `dumpsys mount` metadata, then reuses an already-mounted SD/USB-backed public volume when one exists.
- If none exists, it validates the connected `sm help` surface, enables `sm set-virtual-disk true`, polls for one unique new adoptable disk, partitions only that disk as public, and mounts the new public volume. No fixed vold ID is assumed.
- The harness records the public volume ID, provider UUID, removable classification, and native mount path; the Flutter test independently confirms StorageManager facts, opaque browsing, and the durable `LibraryRootId`.
- It makes the exact volume unavailable with `sm unmount`, polls the unavailable state, restores it with `sm mount`, and proves the same provider identity, same root ID, no duplicate, and no auto-resumed job.
- Cleanup remounts a volume left unavailable, removes only scoped evidence, and disables/forgets virtual storage only when the baseline proved this run owned the virtual-disk delta.
- If supported provisioning or same-identity remount cannot be proved, the script reports `UNVERIFIED` rather than claiming success or injecting an identity.

## Task 8: Documentation, verification, and result contract

**Files:**

- Create: `docs/implementation/phase-002-slice-005-multi-root-and-applicable-feature-coverage.md`.
- Modify: stale capability comments and relevant command documentation.
- Create only at completion: `.chatgpt/codex-runs/2026-08-19T193200Z-phase-002-slice-005-multi-root-and-applicable-feature-coverage/RESULT.json`.

- [x] Document the transition-scoped readiness behavior, single artifact-location contract, native publication boundary, removable-volume evidence split, and scenario commands.
- [x] Run focused Flutter tests, Rust package tests, Kotlin tests, generated-source checks, formatting, analysis, and `just check` after generation.
- [x] Run the applicable-feature, multi-root, permission-loss, diagnostics, existing P02-004 foreground/restart, and self-provisioned removable-volume scenarios independently. The removable run created one virtual public volume, proved same-provider/same-`LibraryRootId` remount semantics, and cleaned back to the recorded empty baseline. Partial eligibility and job-scoped cancel/remove remain covered by the deterministic Rust/Flutter semantic scenarios rather than claiming an additional native lifecycle window.
- [x] Review `git diff` and `git status`; confirm no forbidden scope changes, no staged files, and no accidental generated artifacts.
- [x] Write strict JSON `RESULT.json` mapping PAC-1 through PAC-7 and TAC-1 through TAC-12 to `passed`, `failed`, or `unverified`, with evidence and no alternate result artifact. The result is completed after fresh same-volume removable-media evidence.

## Implementation notes

- Baseline focused Flutter tests passed before behavior changes: 36 tests.
- Baseline pinned Rust runtime tests passed before behavior changes: 8 tests.
- The transition-scoped readiness, Android composition, multi-root cancellation, startup controller, client, bridge, and Android publication contract tests are now green in their focused suites.
- Full Android dual-ABI APK/native qualification passed with `ANDROID_NDK_HOME=/Users/daniel/Library/Android/sdk/ndk/28.2.13676358` on the API 36 ARM64 emulator. The removable-volume run self-provisioned `disk:7,424` and `public:7,425`, observed provider UUID `8362-1B15`, proved same-volume remount and root continuity, and left no adoptable disk, public volume, or evidence directory after cleanup.
