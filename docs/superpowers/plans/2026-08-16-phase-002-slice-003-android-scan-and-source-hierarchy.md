# Phase 002 Slice 003 — Android Scan and Source Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use TDD and preserve task order.

**Goal:** Activate the existing Phase 001 single-root Add & Scan, Scan, Scan Again, authoritative reconciliation, hierarchy inspection, and single-root Jobs control workflows on Android through the P02-002 `LocalFilesystem` mounted-volume provider, while keeping Scan All and active-root cancel-and-remove deferred to P02-005 and keeping Android background/foreground-service lifecycle work deferred to P02-004.

**Architecture:** Treat P02-003 as an activation/integration slice. Reuse the existing `LibraryScan`, JobRun/ScanRun, reconciliation, hierarchy, Jobs, bridge, and Flutter controllers without creating Android-specific authorities. Android refreshes mounted-volume facts before provider-dependent Sources operations; the existing `LocalFilesystem` provider resolves the stable volume-relative root locator and supplies ordinary `LibrarySourceAccess` to the existing scan handler. Presentation capabilities independently gate single-root scan execution, Scan All, and active-root cancel-and-remove so Android can expose only the P02-003 subset while desktop remains unchanged.

**Tech Stack:** Rust workspace (`argus-application`, `argus-infrastructure`, existing runtime/bridge stack), SQLite, Flutter/Dart/Riverpod, flutter_rust_bridge 2.12, Android Kotlin/MethodChannel mount discovery already implemented in P02-002, repository-owned Bash/`just` native milestones, Android ARM64 API 36 emulator, dual-ABI APK packaging (`arm64-v8a`, `x86_64`).

## Binding authority

- `docs/superpowers/specs/2026-08-16-phase-002-slice-003-android-scan-and-source-hierarchy-design.md` — approved slice design.
- `docs/phases/phase-002-android-first-class-platform-support.md` — ordered Phase 002 slice ownership.
- `docs/superpowers/specs/2026-08-15-phase-002-android-first-class-platform-support-design.md` — approved phase-level design.
- `docs/specifications/backend/spec-be-011-source-provider-and-indexing-contract.md` — provider, no-follow, native identity, reconciliation authority, Android LocalFilesystem amendment.
- `docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md` — scan admission/terminalization, Android permission/media behavior, Add & Scan boundary.
- `docs/specifications/frontend/spec-fe-008-sources-and-library-folder-management.md` — Sources/Add & Scan/Scan Again/hierarchy authority.
- `docs/specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md` — Jobs query/control authority.
- Completed Phase 001 Slice 003/004/005/006 implementation and tests — shared reconciliation, hierarchy, scan interaction, retry/cancel contracts.
- Completed P02-002 implementation and `docs/superpowers/plans/2026-08-16-phase-002-slice-002-android-localfilesystem-and-argus-folder-picker.md` — mounted-volume registry, stable Android root locator, Argus browser, mount refresh, root-only Android presentation.

## Global Constraints

- Implement **SLICE-P02-003 only**.
- Android enables **Add & Scan**, **Scan**, **Scan Again**, source hierarchy inspection, and applicable existing **single-root Jobs cancel/retry** controls.
- Android **Scan All remains hidden and non-invokable until P02-005** even though the shared Phase 001 backend already supports it.
- Android **active-root Cancel Scan & Remove remains non-invokable until P02-005**. Inactive-root removal remains available and unchanged.
- Do not add an Android-specific scan API, scheduler, background-operation manager, runtime, database, hierarchy cache, JobRun/ScanRun model, or reconciliation path.
- Do not add a foreground service, WorkManager, wake lock, background/screen-off continuity guarantee, Activity detach/reattach execution host, process-death scan continuity, native job notification/control, or auto-resume. Those are P02-004.
- Do not add SAF (`ACTION_OPEN_DOCUMENT_TREE`, `DocumentFile`, persisted URI grants, content-provider traversal) or Android `file_selector` root selection.
- Keep `SourceProviderType::LocalFilesystem`; do not add a persisted Android-only source family.
- A transient Android mount path is never persisted identity or user-facing Sources copy. Stable provider volume identity plus root-relative location remains the Android root identity model.
- Global All files access loss remains an outer readiness condition. Permission/media loss is not deletion and never authorizes absence reconciliation.
- Provider I/O remains outside SQLite write transactions. Positive observations remain incremental. Only a completed authoritative exact scope may finalize absence.
- Move preservation remains conservative: only one trustworthy provider-native identity match may preserve `SourceEntryId`; filename/path/size/timestamp heuristics are forbidden.
- Do not introduce a database migration unless a RED test proves the current schema cannot satisfy the approved contract. If a migration appears necessary, stop and report a bounded scope-extension request instead of adding it silently.
- Desktop behavior must remain unchanged, including Scan All and active-root cancel-and-remove.
- `just check` must remain deterministic/platform-neutral and must not require Android SDK/NDK/adb/emulator.
- Generate FRB/Freezed/Riverpod output only through repository generation commands; never hand-edit generated files.
- Preserve the existing unrelated untracked P02-002 plan and the approved P02-003 design spec exactly unless this plan explicitly names a change to them. Do not restore, delete, stage, or rewrite unrelated worktree state.
- Do not stage, commit, push, rewrite Git history, or restore unrelated changes. Leave implementation uncommitted for owner review.

---

## Task 1 — Split Sources presentation capabilities at the P02-003/P02-005 boundary

**Files:**
- Modify: `flutter/lib/features/sources/sources_composition.dart`
- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart`
- Modify: `flutter/lib/features/sources/presentation/sources_page.dart`
- Modify: `flutter/lib/features/sources/presentation/add_library_folder_flow.dart`
- Modify: `flutter/lib/features/sources/presentation/root_detail_page.dart`
- Modify: `flutter/test/app/bootstrap/app_bootstrap_test.dart`
- Modify: `flutter/test/features/sources/sources_feature_test.dart`
- Modify: `flutter/test/features/sources/slice_006_scan_all_and_remove_test.dart`
- Generated only through `just generate`: `flutter/lib/features/sources/sources_composition.g.dart`

### 1.1 Write RED capability tests

- [ ] Replace the current Android test that expects all scan execution disabled with tests that require four independent presentation facts:

```dart
const SourcesPresentationCapabilities(
  singleRootScanExecution: true,
  scanAllExecution: false,
  activeRootCancelAndRemove: false,
  localFilesystemBrowser: true,
)
```

- [ ] Assert desktop defaults remain:

```dart
const SourcesPresentationCapabilities(
  singleRootScanExecution: true,
  scanAllExecution: true,
  activeRootCancelAndRemove: true,
  localFilesystemBrowser: false,
)
```

- [ ] Add widget RED coverage proving the Android-style capability value:
  - renders **Add & Scan** and **Add Without Scanning** in the add confirmation;
  - renders **Scan** for a never-scanned inactive root;
  - renders **Scan Again** for an inactive root with terminal history;
  - never renders/invokes **Scan All**;
  - keeps inactive-root Remove enabled;
  - when `root.activeScan != null`, the Remove action cannot open the Cancel Scan & Remove workflow or call `JobsApi.cancelJob`/`removeLibraryRoot`.

### 1.2 Implement the split capability model

- [ ] Replace the coarse `scanExecution` flag with explicit presentation-only fields:

```dart
final class SourcesPresentationCapabilities {
  const SourcesPresentationCapabilities({
    this.singleRootScanExecution = true,
    this.scanAllExecution = true,
    this.activeRootCancelAndRemove = true,
    this.localFilesystemBrowser = false,
  });

  final bool singleRootScanExecution;
  final bool scanAllExecution;
  final bool activeRootCancelAndRemove;
  final bool localFilesystemBrowser;
}
```

- [ ] In `ArgusBootstrap`, keep OS selection in app composition and inject the Android values above whenever `platform.requiresReadinessGate` is true. Do not add `Platform.isAndroid` checks inside Sources feature code.
- [ ] `SourcesPage` gates only Scan All with `scanAllExecution`.
- [ ] `runAddLibraryFolderFlow` gates only Add & Scan with `singleRootScanExecution`.
- [ ] `SourcesRootDetailPage` gates Scan/Scan Again with `singleRootScanExecution`.
- [ ] Keep the Remove button available for inactive roots. When a root is actively scanned and `activeRootCancelAndRemove == false`, disable the Remove action rather than entering the shared Slice 006 cancel-and-remove workflow. Do not change the controller contract; the capability is presentation-only.

### 1.3 Make Task 1 GREEN

- [ ] Run the focused Flutter tests:

```bash
cd flutter
fvm flutter test test/app/bootstrap/app_bootstrap_test.dart
fvm flutter test test/features/sources/sources_feature_test.dart
fvm flutter test test/features/sources/slice_006_scan_all_and_remove_test.dart
```

Expected: Android-style capabilities expose only the P02-003 single-root surface; default desktop capability tests still exercise Scan All and cancel-and-remove unchanged.

---

## Task 2 — Prove Android stable locators support ordinary LocalFilesystem scan access and conservative native identity

**Files:**
- Modify if RED tests require it: `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs`
- Modify: `rust/crates/argus-infrastructure/tests/local_filesystem_contract.rs`

The current Unix implementation emits `unix:<dev>:<ino>` native identity and Android is Unix. Do **not** replace that mechanism merely because this is an Android slice. First prove the actual provider-locator behavior; change production identity formatting only if a concrete provider-scoping or continuity defect is demonstrated.

### 2.1 Write RED/characterization tests through a provider selection

- [ ] Build a mounted-volume snapshot with one `primary` test mount, browse to a test `Games` directory, validate the opaque `ProviderSelection`, retain the returned stable root locator, and call `LocalFilesystemProvider::open_access()` on that locator.
- [ ] Prove the stable Android-style locator resolves and enumerates nested files/directories through the existing `LibrarySourceAccess` contract.
- [ ] On Unix, enumerate one file twice and prove the provider-native identity is byte-stable for the unchanged object.
- [ ] On Unix, rename/move that file within the same mounted filesystem and prove the identity remains the same across the rename.
- [ ] Preserve the existing desktop/path-root contract: raw path roots continue to produce the current native identity behavior and no Android locator text leaks into observations.
- [ ] Keep non-Unix behavior conservative (`None` where no trustworthy native identity exists).

### 2.2 Strengthen provider scoping only if the tests expose a real ambiguity

- [ ] If current `dev`/`ino` evidence is already sufficiently provider-scoped for the mounted Android filesystem under the approved contract, make **no production identity-format change**.
- [ ] If the test/native API 36 evidence proves a cross-volume collision or namespace ambiguity, introduce the smallest provider-private namespace needed, using the stable provider volume identity from the decoded root locator. Do not add a new application/domain identity type or database field.
- [ ] If Android storage does not preserve trustworthy identity across an in-filesystem rename, omit/narrow Android native identity rather than fabricate continuity. Never substitute path, filename, size, timestamp, or fingerprint as `ProviderNativeIdentity`.

### 2.3 Preserve no-follow and unavailable behavior

- [ ] Add/retain tests proving Android-style provider locators cannot escape the mounted root, link-like entries are not traversed, and a missing volume resolves to `SourceAccessError::SourceUnavailable`.

### 2.4 Make Task 2 GREEN

```bash
bash scripts/run_rust.sh cargo test --manifest-path rust/Cargo.toml \
  --package argus-infrastructure --test local_filesystem_contract --all-features --locked
```

Expected: provider-selection roots can be scanned with the same `LibrarySourceAccess` contract as path roots, with conservative identity and no Android-specific application model.

---

## Task 3 — Prove the existing LibraryScan reconciliation pipeline against Android provider locators

**Files:**
- Modify: `rust/crates/argus-infrastructure/tests/scan_reconciliation.rs`
- Modify only if a RED test exposes a shared bug: `rust/crates/argus-application/src/sources/scan.rs`
- Modify only if a RED test exposes provider integration defect: `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs`

### 3.1 Add a provider-backed Android-style scan fixture

- [ ] Add a test helper that owns a concrete `LocalFilesystemProviderImpl`, replaces mounted-volume facts, uses browse + `ProviderSelection` validation to obtain the stable root locator, seeds the existing SQLite JobRun/ScanRun/root records, and obtains execution access through `provider.open_access(&locator)`.
- [ ] Do not instantiate a second scan handler or copy reconciliation logic. Feed the access object into the existing `LibraryScanOperationHandler`.

A representative helper shape is:

```rust
struct MountedScanFixture {
    provider: LocalFilesystemProviderImpl,
    locator: RootLocator,
    root_id: LibraryRootId,
    executor: SqliteDatabaseExecutor,
}
```

The exact private test shape may vary; the authority model may not.

### 3.2 RED: initial scan and hierarchy facts

- [ ] Create nested directories/files under the mounted fixture and run one existing `LibraryScanOperationHandler` execution.
- [ ] Assert terminal `Completed`, root availability `Available`, nested source rows committed under the correct parents, and no raw mount path persisted as root identity/display data beyond provider-owned transient resolution.

### 3.3 RED: Scan Again reconciliation and move identity

- [ ] After the first completed scan:
  - create a new file;
  - delete an existing file;
  - move a file into another directory on the same mounted filesystem.
- [ ] Admit/seed a second scan attempt using the **same stable root locator** and current mount registry.
- [ ] Assert:
  - new entry appears;
  - deleted entry disappears only after completed-scope finalization;
  - one unique trustworthy native-identity match preserves the moved entry's `SourceEntryId`;
  - hierarchy parent/locator update is correct.

### 3.4 RED: unavailable media never grants absence authority

- [ ] After a completed baseline scan, replace the provider mount snapshot so the configured provider volume is absent, then execute a fresh admitted scan attempt using the existing stable locator.
- [ ] Assert the scan/root uses the existing unavailable/failure terminal vocabulary, and previously indexed unseen entries remain present. No whole-root or completed-scope absence finalization may occur.
- [ ] This test is about the P02-003 single-root safety contract only. Full permission-regrant/remount feature coverage remains P02-005.

### 3.5 Make Task 3 GREEN without forking scan semantics

```bash
bash scripts/run_rust.sh cargo test --manifest-path rust/Cargo.toml \
  --package argus-infrastructure --test scan_reconciliation --all-features --locked
```

Expected: the current Phase 001 scan/reconciliation implementation passes against stable Android-style provider locators. If it already passes after tests are added, do not edit `argus-application/src/sources/scan.rs`.

---

## Task 4 — Pin mount refresh to Add & Scan and Scan/Scan Again bridge paths

**Files:**
- Modify: `flutter/test/core/bridge/frb_mapper_test.dart`
- Modify only if RED tests fail: `flutter/lib/core/bridge/src/frb_argus_client_gateway.dart`

P02-002 already routes provider-dependent Sources operations through `_sourcesCall()`. P02-003 should prove the scan entrypoints specifically remain behind that boundary.

### 4.1 Extend the recording RustLib test double

- [ ] Teach `_SourcesRecordingRustLibApi` to record and return typed values for:
  - `crateAddLocalLibraryRootAndScan`;
  - `crateStartLibraryScan`.

Use valid bounded DTO identities. Do not load a native library in these mapper tests.

### 4.2 RED: refresh occurs before each scan admission

- [ ] Add tests that call `gateway.addLocalLibraryRootAndScan(...)` and `gateway.startLibraryScan(...)` and assert call order:

```text
sync -> addAndScan
sync -> startScan
```

- [ ] Add a mount-reader failure test for each scan admission path and assert neither Rust scan entrypoint is invoked after the refresh failure.
- [ ] Keep the existing concurrent-refresh serialization test unchanged.

### 4.3 Make Task 4 GREEN

```bash
cd flutter
fvm flutter test test/core/bridge/frb_mapper_test.dart
```

Expected: current production gateway should already satisfy this. Change `_sourcesCall` only if the focused RED tests demonstrate otherwise.

---

## Task 5 — Add Android-focused Flutter behavior coverage without creating an Android Sources fork

**Files:**
- Modify: `flutter/test/app/bootstrap/app_bootstrap_test.dart`
- Modify: `flutter/test/features/sources/sources_feature_test.dart`
- Modify: `flutter/test/features/sources/slice_006_scan_all_and_remove_test.dart`
- Modify if useful for focused coverage: `flutter/test/features/sources/sources_test_fakes.dart`
- Existing shared hierarchy tests remain authoritative: `flutter/test/features/sources/source_hierarchy_controller_test.dart`, `flutter/test/features/sources/source_hierarchy_presentation_test.dart`
- Existing shared Jobs tests remain authoritative: `flutter/test/features/jobs/jobs_feature_test.dart`

### 5.1 Prove the Android composition exposes the exact slice surface

- [ ] Update the bootstrap test to assert:

```dart
expect(capabilities.localFilesystemBrowser, isTrue);
expect(capabilities.singleRootScanExecution, isTrue);
expect(capabilities.scanAllExecution, isFalse);
expect(capabilities.activeRootCancelAndRemove, isFalse);
```

- [ ] In Sources widget tests, use the Android-style capability value directly and prove:
  - Add & Scan is present and calls exactly `addLocalLibraryRootAndScan` once;
  - Add Without Scanning remains present;
  - Scan and Scan Again call existing `startLibraryScan` exactly once;
  - Source hierarchy stays the existing `SourceHierarchyBrowser` and authoritative controller path;
  - Scan All is absent even when authoritative root `totalCount > 0`;
  - active-root Remove is disabled/non-invokable and never calls cancel/remove;
  - inactive-root Remove still uses the existing root-only removal contract.

### 5.2 Preserve shared Jobs authority

- [ ] Do not add a platform capability to Jobs. Existing backend `canCancel`/`canRetry` remains the only control authority.
- [ ] Run the existing Jobs tests to prove cancel/retry presentation remains unchanged:

```bash
cd flutter
fvm flutter test test/features/jobs/jobs_feature_test.dart
```

### 5.3 Preserve hierarchy reconciliation behavior

- [ ] Run existing hierarchy controller/presentation tests without platform-specific branches:

```bash
cd flutter
fvm flutter test test/features/sources/source_hierarchy_controller_test.dart
fvm flutter test test/features/sources/source_hierarchy_presentation_test.dart
```

Expected: no Android-only hierarchy controller/cache is introduced; event gaps/runtime replacement continue to reconcile from authoritative queries.

---

## Task 6 — Add the real ARM64 API 36 Android P02-003 milestone

**Files:**
- Create: `flutter/integration_test/phase_002_android_scan_hierarchy_test.dart`
- Create: `scripts/run_phase_002_android_scan_tests.sh`
- Modify: `justfile`
- Use as provenance: `flutter/integration_test/phase_001_local_sources_milestone_test.dart`
- Use as provenance: `flutter/integration_test/phase_002_android_local_filesystem_test.dart`
- Use as provenance: `scripts/run_phase_002_android_local_filesystem_tests.sh`

### 6.1 Add a repository-owned `just` target

- [ ] Add:

```make
 test-phase-002-android-scan:
     bash scripts/run_phase_002_android_scan_tests.sh
```

Match existing `justfile` indentation/conventions. Do not add this target as a dependency of `just check`.

### 6.2 Build a strict ARM64 API 36 harness

- [ ] The new script must:
  - use `ARGUS_ANDROID_ADB` / `ARGUS_ANDROID_DEVICE_ID` conventions from P02-002 where applicable;
  - require one selected/connected device;
  - require **API 36** for this milestone;
  - require runtime ABI `arm64-v8a`;
  - build the debug APK with `--target-platform android-arm64,android-x64`;
  - install the APK;
  - clear app data once at the beginning;
  - grant `MANAGE_EXTERNAL_STORAGE` and notification permission where applicable;
  - create and clean a dedicated fixture such as `/sdcard/ArgusP02003Fixture`;
  - never use the fixture path as a durable Argus root identity or assert it appears in Sources UI.

### 6.3 Phase `seed`: real Add & Scan and hierarchy

- [ ] Prepare an initial fixture through `adb` with representative root files, a nested directory, a file that will later be moved, and a file that will later be removed.
- [ ] Run the integration test in a `seed` mode using **production `ArgusBootstrap`**, not a fake gateway/provider/picker.
- [ ] Through the Argus browser, select the fixture by safe directory name and tap **Add & Scan**.
- [ ] Wait on authoritative root/job reads until the initial scan is terminal `Complete`; do not use an arbitrary sleep as completion evidence.
- [ ] Prove the real hierarchy renders/queries representative nested entries through:

```text
Flutter -> ArgusClient -> FRB -> Rust -> SQLite -> Android LocalFilesystem
```

- [ ] Prove Scan All is not exposed.

### 6.4 Mutate fixture and verify native rename evidence in the harness

- [ ] After `seed` terminates, use `adb shell stat -c '%d:%i'` (or another deterministic OS-owned equivalent available on the configured emulator) to capture the move candidate's native filesystem identity.
- [ ] Mutate through `adb`:
  - create a new file;
  - remove the designated old file;
  - create a destination directory;
  - rename/move the candidate within the same mounted filesystem.
- [ ] Re-read the OS-owned identity after the rename and require equality. If the configured API 36 emulator does not preserve trustworthy identity for this operation, the provider must not claim move continuity; adjust provider identity conservatively rather than weakening the assertion into a heuristic.

### 6.5 Phase `reconcile`: real Scan Again and authoritative hierarchy reconciliation

- [ ] Run the integration test in `reconcile` mode against the same app data/root configuration.
- [ ] Navigate to the existing root and trigger **Scan Again** through the existing root-detail path/controller.
- [ ] Wait on authoritative root/job state for a new JobRunId and terminal `Complete`.
- [ ] Assert through `SourcesApi`/hierarchy UI:
  - added entry appears;
  - removed entry is absent;
  - moved entry appears under its new parent;
  - moved entry retains its prior `SourceEntryId` only because the real native identity proof is trustworthy;
  - Scan All is still absent.

A process force-stop between **terminal** phases is allowed to prove persisted completed state is readable, but never force-stop an active scan and never claim P02-004 lifecycle continuity.

### 6.6 Phase `cancel`: exercise the existing single-root Jobs cancellation path

- [ ] Have the script create a sufficiently large deterministic fixture subtree before the cancel phase.
- [ ] Start a new single-root Scan Again.
- [ ] Poll authoritative `GetJob` until backend `canCancel == true`; do not sleep for a guessed amount of time and assume the control is available.
- [ ] Exercise the existing Jobs cancellation control path (prefer the real Jobs detail controller/UI where hit-testing is deterministic; using the same `JobsApi.cancelJob` path is acceptable for the native execution proof when UI hit-testing would make the milestone flaky).
- [ ] Wait for terminal `Cancelled` and assert committed positive observations from the prior authoritative scan still remain. Cancellation grants no absence authority.

### 6.7 Phase `retry`: exercise the existing single-root Jobs retry path

- [ ] After the cancelled attempt is terminal, let the script remove the large cancellation-only fixture subtree so retry can complete quickly.
- [ ] Run a separate `retry` mode, load the cancelled historical JobRun, prove backend `canRetry == true`, invoke the existing retry control, and assert:
  - a fresh JobRunId/ScanRunId is admitted;
  - the historical cancelled run is not reopened;
  - the retry reaches its authoritative terminal state;
  - the root/hierarchy remains query-authoritative;
  - Scan All remains absent.

### 6.8 Keep the milestone inside P02-003

- [ ] Do **not** test/claim active scan survival across screen-off, Activity destruction, process death, force-stop, or background execution. Do not add a foreground service or notification behavior to make this milestone pass.
- [ ] Do not activate active-root cancel-and-remove during the milestone.
- [ ] x86_64 emulator execution remains deferred on Apple Silicon; this milestone requires x86_64 **packaging**, not x86_64 execution.

---

## Task 7 — Generate, validate, and produce completion evidence

**Files:**
- Generated outputs registered by `justfile`, if source annotations changed
- Implementation files from Tasks 1–6
- This run's `.chatgpt/codex-runs/<run-id>/RESULT.json` only, per delegation completion contract

### 7.1 Generate first, then verify generated drift

- [ ] Run:

```bash
just generate
just check-generated
```

- [ ] Inspect generated changes. Generated files must correspond only to source annotations/types changed by this slice.

### 7.2 Run deterministic platform-neutral gates

- [ ] Run:

```bash
just format
just check
just test-local-filesystem-native
just test-phase-000-native
just test-phase-001-native
```

- [ ] `just check` must remain Android-independent.

### 7.3 Run existing and new ARM64 Android milestones

- [ ] With the configured ARM64 API 36 emulator selected, run:

```bash
just test-phase-002-android-local-filesystem
just test-phase-002-android-scan
```

- [ ] Build/package evidence must still show both `arm64-v8a` and `x86_64` artifacts in the debug APK/build output.
- [ ] Do not claim `test-phase-002-android-bootstrap` passed on Apple Silicon unless a compatible x86_64 emulator is actually available; its existing x86_64 execution limitation is not replaced by ARM64 evidence.

### 7.4 Final scope review

- [ ] Review `git diff`/changed paths and prove:
  - Android Add & Scan / Scan / Scan Again are active;
  - Android Scan All is not active;
  - Android active-root cancel-and-remove is not active;
  - no foreground service/WorkManager/wake lock/background lifecycle implementation exists;
  - no SAF/content-provider traversal was added;
  - no database migration was added;
  - no raw transient Android mount path became persisted identity or Flutter Sources copy;
  - desktop Scan All and cancel-and-remove remain unchanged;
  - existing Phase 001 reconciliation/Jobs/hierarchy authority was reused rather than forked.

### 7.5 Write truthful `RESULT.json`

- [ ] Record every technical acceptance criterion with concrete file/test/milestone evidence.
- [ ] Record the ARM64 API level/ABI used by the native milestone and the dual-ABI packaging evidence.
- [ ] Record any environmental skip/defer explicitly; do not convert an unavailable x86_64 emulator into a passing claim.
- [ ] Do not stage, commit, or push.

---

## Plan self-review checklist

- **Spec coverage:** Covers every approved P02-003 outcome: Android single-root Add & Scan/Scan/Scan Again, shared `LibraryScan`, reconciliation, hierarchy, native move identity, single-root Jobs cancel/retry, mount refresh, real ARM64 API 36 milestone, and desktop preservation.
- **Slice boundaries:** Scan All and active-root cancel-and-remove stay P02-005; foreground/background lifecycle hosting stays P02-004; adaptive UX stays P02-006.
- **Authority:** No parallel Android scan/hierarchy/jobs authority is introduced. Existing Phase 001 application/runtime/SQLite authority remains canonical.
- **Safety:** Permission/media loss cannot create absence authority; no-follow and root confinement remain provider-owned; no user files are mutated by Argus root management.
- **Type consistency:** Reuses existing `LocalFilesystemRootSelection`, `LibraryScanExecutionPlan`, `LibrarySourceAccess`, `JobRunId`, `ScanRunId`, `SourceEntryId`, `SourcesApi`, and `JobsApi`; only presentation capability fields are split.
- **Persistence:** No schema migration is planned or required.
- **No placeholders:** No `TBD`, `TODO`, speculative fake API, or unresolved implementation choice remains. Production identity changes are explicitly conditional on concrete RED/native evidence rather than assumed necessary.
