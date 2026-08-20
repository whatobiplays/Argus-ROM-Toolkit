# Phase 002 Slice 002 — Android LocalFilesystem and Argus Folder Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Use TDD and preserve the task order.

**Goal:** Add Android mounted-storage discovery, an Argus-owned folder browser, stable removable-volume root identity, root-only admission/removal, and authoritative availability reconciliation using the existing `LocalFilesystem` provider family. Android scan execution remains deliberately inactive until P02-003.

**Architecture:** Kotlin supplies bounded Android mounted-volume facts only. Those facts are synchronized into one transient registry owned by the concrete Rust `LocalFilesystem` provider. Rust remains filesystem authority: it creates opaque browse identities, performs bounded direct-child directory enumeration, validates final selections, persists a versioned root locator built from stable volume identity plus root-relative location, resolves that locator against current mounts, and owns overlap/availability semantics. Flutter renders safe typed projections and transports opaque identities; it never parses filesystem paths, volume identities, or provider locators. Desktop continues to use the existing `file_selector` path picker and current path-backed LocalFilesystem behavior.

## Binding authority

- `docs/phases/phase-002-android-first-class-platform-support.md`, Slice P02-002.
- `docs/specifications/cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md`.
- `docs/specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md`.
- `docs/specifications/backend/spec-be-011-source-provider-and-indexing-contract.md`, especially §61.
- `docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md`.
- `docs/specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md`.
- `docs/specifications/frontend/spec-fe-008-sources-and-library-folder-management.md`.
- `docs/superpowers/specs/2026-08-15-phase-002-android-first-class-platform-support-design.md` as approved supporting rationale.

## Global constraints

- Keep `SourceProviderType::LocalFilesystem`; do not add an Android-only persisted source family.
- No SAF fallback: no `ACTION_OPEN_DOCUMENT_TREE`, `DocumentFile`, persisted URI grants, content-provider traversal, cloud/virtual document trees, or Android `file_selector` root selection.
- Kotlin owns Android OS mount discovery. Rust provider infrastructure owns canonical root locators, browse identity, bounded enumeration, relationships, resolution, availability, stat/open behavior, native identity, and boundary safety.
- Flutter must never canonicalize paths, infer overlap/ancestry, construct a `RootLocator`, interpret provider volume identity, or enumerate storage with `dart:io`.
- A transient mount path is never durable root identity. Android roots persist stable volume identity plus provider-owned root-relative location.
- Primary shared storage uses a provider/native stable sentinel. A non-primary removable volume is eligible only when Android supplies a non-empty stable UUID. Never fabricate removable identity from mount path, label, size, timestamps, or filenames.
- Missing media means `Unavailable`, not deleted. A trustworthy remount of the same stable volume/root restores availability under the same `LibraryRootId`.
- Global All files access loss remains an outer platform-readiness condition. Do not translate revoked global authorization into fabricated per-root disappearance evidence.
- Browse data is bounded, direct-child, directory-only, deterministic, and no-follow. Link-like entries are never traversed or offered as selectable directories.
- Existing duplicate/overlap semantics remain authoritative: Same => AlreadyConfigured; Ancestor/Descendant => OverlapsExisting; Disjoint => allow; Unknown => conservatively allow.
- Root removal never changes user files.
- Android P02-002 exposes root-only add. Hide Add & Scan, Scan, Scan Again, and Scan All on Android until P02-003. Do not delete or change desktop scan APIs/behavior.
- No foreground service, WorkManager, wake lock, background execution host, Android diagnostic export, signing/release, API 29, 32-bit ABI, or permanent Android CI work.
- `just check` stays deterministic/platform-neutral and must not require Android SDK/NDK/adb/emulator.
- Generate FRB/Freezed/Riverpod output only through repository generation commands.
- Do not stage, commit, push, rewrite history, or restore unrelated changes. Leave implementation uncommitted for owner review.
- P02-001's deferred x86_64 emulator proof remains a later Phase 002 gate; do not falsely claim ARM64 evidence satisfies it.

---

## Task 1 — Extend provider-facing contracts for mounted browsing and opaque provider selections

**Files:**
- `rust/crates/argus-application/src/sources/provider.rs`
- `rust/crates/argus-application/src/sources/mod.rs`
- `rust/crates/argus-application/src/lib.rs`
- focused `argus-application` tests

- [ ] **1.1 Write RED tests for a closed root-selection union.** Replace the path-only request with:

```rust
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LocalFilesystemRootSelection {
    Path { selected_folder_path: String },
    ProviderSelection { selection_identity: String },
}
```

Provide constructors/accessors that reveal the raw path only for the `Path` variant and the opaque provider selection identity only for transport back to the provider. Generic application code must not decode the provider selection identity.

- [ ] **1.2 Add transient mounted-volume facts.** Introduce provider-facing input:

```rust
pub struct MountedLocalFilesystemVolume {
    provider_volume_id: String,
    mount_path: String,
    display_name: String,
    is_primary: bool,
    is_removable: bool,
}
```

Hard bound the snapshot to 32 records.

- [ ] **1.3 Add opaque browse coordinates and safe projections.** Introduce:

```rust
pub struct LocalFilesystemBrowseLocation(String);
pub struct LocalFilesystemBrowseCursor(String);

pub struct LocalFilesystemBrowseRoot {
    location: LocalFilesystemBrowseLocation,
    display_name: String,
    safe_location_presentation: String,
}

pub struct LocalFilesystemBrowseBreadcrumb {
    location: LocalFilesystemBrowseLocation,
    display_name: String,
}

pub struct LocalFilesystemBrowseDirectory {
    location: LocalFilesystemBrowseLocation,
    display_name: String,
}

pub struct LocalFilesystemBrowsePage {
    current: LocalFilesystemBrowseRoot,
    breadcrumbs: Vec<LocalFilesystemBrowseBreadcrumb>,
    directories: Vec<LocalFilesystemBrowseDirectory>,
    next_cursor: Option<LocalFilesystemBrowseCursor>,
}
```

The browse projection never exposes `mount_path` or `provider_volume_id`.

- [ ] **1.4 Add an additive browse-provider port rather than widening every existing fake.** Keep `LocalFilesystemProvider` intact for current validation/comparison/access tests and add:

```rust
pub trait LocalFilesystemBrowseProvider: LocalFilesystemProvider {
    fn replace_mounted_volumes(
        &self,
        volumes: &[MountedLocalFilesystemVolume],
    ) -> Result<(), ProviderError>;

    fn list_browse_roots(
        &self,
    ) -> Result<Vec<LocalFilesystemBrowseRoot>, ProviderError>;

    fn list_browse_directories(
        &self,
        location: &LocalFilesystemBrowseLocation,
        cursor: Option<&LocalFilesystemBrowseCursor>,
        page_size: u32,
    ) -> Result<LocalFilesystemBrowsePage, ProviderError>;
}
```

Add `ProviderError::InvalidBrowseRequest`. Max page size is 200; bridge/client default page size is 100.

- [ ] **1.5 Run focused application contract tests GREEN.** Existing providers/fakes that only implement `LocalFilesystemProvider` must continue compiling unchanged unless they participate in the new browse path.

---

## Task 2 — Implement the Rust mount registry, stable Android locators, and bounded folder browsing

**Files:**
- `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs`
- focused LocalFilesystem infrastructure tests

- [ ] **2.1 Write RED tests for transient registry and durable locator behavior.** Change the concrete provider from a zero-sized `Copy` value to a cloneable provider sharing one process-transient registry:

```rust
#[derive(Clone, Debug, Default)]
pub struct LocalFilesystemProvider {
    mounted_volumes: Arc<RwLock<MountedVolumeRegistry>>,
}
```

Provider clones used by root admission, browse, and later source access must observe the same registry.

- [ ] **2.2 Use provider-owned versioned encodings.** Keep encoding private to `local_filesystem`. Use distinct version markers for browse coordinates and durable Android root locators. The encoded coordinate contains exactly stable provider volume identity plus root-relative location; it never persists the transient mount prefix.

Tests assert round-trip/rejection semantics rather than parsing the internal encoding from application code.

- [ ] **2.3 Make mounted-volume replacement atomic.** Validate the entire snapshot before replacing registry state:

```text
count <= 32
non-empty unique provider volume IDs
exactly one primary volume
absolute mount paths
non-empty safe display names
no duplicate canonical mount roots
```

Invalid input returns `InvalidBrowseRequest` and leaves the previous registry untouched.

- [ ] **2.4 Implement browse roots.** Return only registered mount roots that are currently non-link-like directories and can be opened with `read_dir`. Primary sorts first; remaining roots sort deterministically by safe display then provider identity internally. The outward safe location is the safe volume label, never `/storage/...`.

- [ ] **2.5 Implement bounded deterministic direct-child paging.** For one opaque browse location:

```text
decode provider coordinate
resolve stable volume through current registry
confine candidate to current mount root
reject absolute/traversal/boundary escapes
use symlink_metadata/no-follow
return directories only
skip/reject link-like entries
translate missing media/root to Unavailable
enforce page size 1..=200
keep memory O(page_size)
return provider-generated opaque cursor for additional rows
```

A valid implementation may scan the direct native directory on each page while retaining only the next `page_size + 1` deterministic directory keys after the cursor. This keeps memory bounded without relying on unspecified `read_dir` ordering.

Breadcrumbs are generated by the provider from its decoded coordinate; Flutter never constructs parent locations.

- [ ] **2.6 Preserve desktop validation and add provider-selection validation.** `Path` executes the current desktop logic unchanged. `ProviderSelection` resolves its stable volume/root-relative coordinate through the current registry, proves boundary + non-link directory + enumerability, and returns `ValidatedLocalRoot` whose durable `RootLocator` contains stable volume identity/root-relative location only.

Safe location presentation should be provider-produced (for example `Internal storage / ROMs / SNES`) and must not expose transient mount prefixes.

- [ ] **2.7 Implement Android locator relationships without requiring the volume to be mounted.** For two versioned Android root locators:

```text
same volume + same coordinate => Same
same volume + proper left ancestor => Ancestor
same volume + proper right ancestor => Descendant
different trustworthy volume IDs => Disjoint
mixed/malformed encodings => Unknown
```

- [ ] **2.8 Make `open_access` resolve Android locators against the current registry.** After resolution, reuse the existing no-follow/canonical boundary enforcement. Tests must prove a root added when one stable removable ID is mounted at path A becomes unavailable when absent and resolves at path B when that same ID remounts there, without changing the persisted locator.

- [ ] **2.9 Run `just test-local-filesystem-native` GREEN.** Preserve Phase 001 Windows/Linux/macOS path semantics.

---

## Task 3 — Synchronize mounted facts and reconcile authoritative root availability without scans

**Files:**
- `rust/crates/argus-application/src/sources/library.rs`
- existing SQLite root-query mapping where needed
- `rust/crates/argus-runtime/src/runtime.rs` and current kernel/runtime composition
- focused application/runtime tests

- [ ] **3.1 Extend `LibraryRootConfiguration` with current `LibraryRootAvailability`.** Update query mapping/test constructors only. Do not add a migration: existing opaque `root_locator` and availability columns are sufficient for P02-002.

- [ ] **3.2 Add `SyncLocalFilesystemMountedVolumesCommand`.** Tests must prove:

```text
valid snapshot + resolvable Unknown/Unavailable root => Available + LibraryRootChanged
valid snapshot missing a configured Android volume => Unavailable + LibraryRootChanged
no availability change => no root-change event
registry replacement failure => no availability mutation
permission/authorization ambiguity => operation fails rather than mass-marking roots unavailable
no JobRun/ScanRun creation
```

- [ ] **3.3 Implement provider-I/O-before-UoW reconciliation.** Sequence exactly:

```text
provider.replace_mounted_volumes(snapshot)
queries.list_root_configurations()
for each root outside write transaction:
    provider.open_access(locator) + resolve_root()
    classify success as Available
    classify definite SourceUnavailable as Unavailable
    propagate PermissionDenied/AuthorizationUnavailable/ambiguous internal errors
one bounded UoW persists changed availability rows + root-change events
```

Do not recursively enumerate roots and do not infer source-entry absence.

- [ ] **3.4 Add application browse query methods.** Add focused service calls for `list_local_filesystem_browse_roots` and `list_local_filesystem_browse_directories`. They delegate provider authority only; they do not inspect source entries or scan policy.

- [ ] **3.5 Expose sync/browse through the existing runtime/kernel and operation context.** Use the same provider instance already owned by the runtime's `LibraryService`; do not instantiate a second provider for browse. Synchronization publishes collected root-change events through the existing event publisher.

- [ ] **3.6 Add restart/remount integration coverage with SQLite.** Persist a root from a provider selection, reconstruct the runtime/provider with an empty transient registry, synchronize the same stable volume at another temporary mount path, and prove the same `LibraryRootId` becomes Available with no replacement root and no scan history.

---

## Task 4 — Add focused FRB/client browse APIs and internal pre-operation mount synchronization

**Files:**
- `rust/crates/argus-bridge/src/lib.rs`
- generated FRB output via `just generate`
- `flutter/lib/core/client/src/models.dart`
- `flutter/lib/core/client/src/ports.dart`
- `flutter/lib/core/client/src/argus_client.dart`
- `flutter/lib/core/bridge/src/frb_argus_client_gateway.dart`
- focused bridge/client/gateway tests

- [ ] **4.1 Add bridge DTOs.** Add a mounted-volume sync input DTO with provider volume ID, transient mount path, safe display, primary/removable flags. It is ingress-only and never returned through Sources presentation APIs.

Change root selection DTO to the same closed `Path` / `ProviderSelection` shape as the application type. Add safe browse DTOs matching Task 1.

- [ ] **4.2 Add bridge endpoints.** Add focused functions for mounted-volume synchronization, browse-root listing, and bounded child-directory browse. The bridge validates required strings/bounds by constructing typed application/provider values; it never decodes provider coordinates itself.

- [ ] **4.3 Add pure-Dart models.** Model `LocalFilesystemRootSelection` as a closed path/provider-selection union. Add an opaque `LocalFilesystemBrowseLocation` wrapper plus browse root/breadcrumb/directory/page models. No model exposes provider volume identity or transient mount path to Sources UI.

- [ ] **4.4 Extend `SourcesGateway`/`SourcesApi` only with browse reads:**

```dart
Future<List<LocalFilesystemBrowseRoot>> listLocalFilesystemBrowseRoots();

Future<LocalFilesystemBrowsePage> listLocalFilesystemBrowseDirectories({
  required LocalFilesystemBrowseLocation location,
  String? cursor,
  required int pageSize,
});
```

Do not expose mounted-volume synchronization on `SourcesApi`.

- [ ] **4.5 Add an injected framework-neutral mounted-volume reader to `FrbArgusClientGateway`.** The gateway owns a nullable callback supplied by app composition. When absent (desktop), behavior/call counts stay unchanged.

Before Android provider-dependent Sources operations, serialize one refresh sequence:

```text
native mounted-volume reader
-> bridge sync operation
-> requested Sources operation
```

Apply it before root list/get/add and browse operations. Also apply it before existing scan-start methods so P02-003 can rely on current mounts later, but do not add any Android UI that invokes scans in this slice.

Concurrent Sources requests share one in-flight synchronization instead of racing registry replacement. If native discovery or synchronization fails, fail the requested operation; do not proceed with known-stale mount facts.

- [ ] **4.6 Run `just generate` and focused transport/client tests.** Generated types remain private to `core/bridge`; malformed wire values map to contract mismatch; browse projections contain no raw Android paths.

---

## Task 5 — Add Android `StorageManager` discovery behind a dedicated app-platform channel

**Files:**
- create `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusLocalFilesystemBridge.kt`
- modify `ArgusApplication.kt`
- create `flutter/lib/app/platform/application/local_filesystem_platform_api.dart`
- create `flutter/lib/app/platform/native/android_local_filesystem_platform_api.dart`
- modify `platform_host_factory.dart`, `platform_host.dart`, `client_bootstrap.dart`, and focused tests

- [ ] **5.1 Add pure-Dart platform fact/failure types and RED MethodChannel tests.** `LocalFilesystemPlatformApi.readMountedVolumes()` returns bounded `PlatformMountedVolume` records with provider ID, mount path, safe display, primary/removable flags. Native error text never becomes UI copy.

- [ ] **5.2 Implement a separate channel named `argus/local_filesystem_platform` with method `readMountedVolumes`.** Do not add storage discovery methods to the existing readiness channel.

For each `StorageVolume` on API 30+:

```text
require directory != null
require state == MEDIA_MOUNTED or MEDIA_MOUNTED_READ_ONLY
if primary: provider ID = stable primary sentinel
else require non-empty StorageVolume UUID and normalize it
otherwise skip as lacking trustworthy durable removable identity
```

Use `getDescription(application)` only as safe display. Never use display/mount path as identity fallback. Return at most 32 records and require exactly one primary record in a successful snapshot.

- [ ] **5.3 Register the new bridge on the existing application-scoped Flutter engine before Dart starts.** It does not require Activity attachment and must not create another engine/channel authority path.

- [ ] **5.4 Extend `PlatformHostComposition` with nullable mounted-storage capability selected only in the existing native platform factory.** Android supplies the MethodChannel implementation; desktop supplies no reader. `client_bootstrap.dart` converts platform facts into the bridge callback for each production gateway generation.

- [ ] **5.5 Test malformed/duplicate/missing-primary/oversize snapshots and architecture boundaries.** No Sources feature file may import Flutter services or `dart:io` for storage traversal.

---

## Task 6 — Build the Argus-owned folder browser and suppress Android scan controls

**Files:**
- `flutter/lib/features/sources/presentation/library_folder_picker.dart`
- create `flutter/lib/features/sources/application/local_filesystem_browser_controller.dart` (+ generated/state files as appropriate)
- create `flutter/lib/features/sources/presentation/local_filesystem_browser.dart`
- create/modify a Sources presentation capability seam
- modify `add_library_folder_flow.dart`, `sources_page.dart`, `root_detail_page.dart`, `sources.dart`
- focused Sources tests

- [ ] **6.1 Make the picker return backend selection plus safe presentation.** Introduce feature-local `SelectedLibraryFolder { selection, displayName, safeLocationPresentation }` and change the picker seam so an injected Flutter browser can receive `BuildContext` and `WidgetRef`. Desktop still calls `getDirectoryPath`, returning a `Path` selection and desktop-safe presentation.

- [ ] **6.2 Write browser controller tests RED.** Required states/actions:

```text
load mounted browse roots
open a volume root
open a child directory
use backend-provided breadcrumbs for Up
Back inside child => Up
Back at volume root => volume list
Back at volume list => caller may dismiss
load next page using backend cursor only
retry the exact failed browse request
```

The controller never synthesizes paths, parent identities, browse locations, or cursors.

- [ ] **6.3 Implement the browser UI.** Render safe volume list, current location, breadcrumbs/up, directory rows, load-more/retry, Cancel, and explicit **Select this folder**. Use touch-sized Material controls and `PopScope` so ordinary Android Back moves up before dismissing. P02-006 owns later predictive-Back hardening.

Selecting the current location returns a `ProviderSelection` containing only the opaque provider browse identity. Confirmation presentation uses the backend's safe current display fields.

- [ ] **6.4 Add `SourcesPresentationCapabilities(scanExecution: bool)`.** Default is true so desktop is unchanged. When false:

```text
SourcesPage hides Scan All
SourcesRootDetailPage hides Scan / Scan Again
Add Library Folder confirmation offers root-only Add and Cancel; it never calls addAndScan
```

Do not remove scan methods/controllers/backend APIs.

- [ ] **6.5 Remove raw-path assumptions from confirmation UI.** Stop deriving folder name/location from `selectedFolderPath`; display only `SelectedLibraryFolder.displayName` and `.safeLocationPresentation`, then submit its typed backend selection.

- [ ] **6.6 Run Sources controller/widget tests GREEN.** Cover browse roots, child navigation, breadcrumb/up/back, pagination, retry, select/cancel, duplicate/overlap handling, scan-control suppression, and unchanged desktop Add & Scan behavior under default capabilities.

---

## Task 7 — Compose Android root selection and prove durable root-only behavior

**Files:**
- `flutter/lib/app/bootstrap/app_bootstrap.dart`
- app/bootstrap/platform tests
- concrete provider/SQLite integration tests

- [ ] **7.1 Replace P02-001's `_androidRootSelectionUnavailable` override.** Android app composition injects the Argus local-filesystem browser and `SourcesPresentationCapabilities(scanExecution: false)`. Do not add `Platform.isAndroid` inside Sources.

- [ ] **7.2 Add one real-stack remount/root-management integration scenario:**

```text
sync primary + removable stable ID at mount A
browse/select removable/Games
add root-only; capture ID; Available
restart against same SQLite with fresh empty provider registry
sync only primary; same root => Unavailable
sync same removable stable ID at mount B; same root => Available
reselect same root => AlreadyConfigured(same ID)
select child/parent overlap => OverlapsExisting(same ID, governed relationship)
remove root; fixture files still exist
assert no JobRun/ScanRun was created
```

- [ ] **7.3 Preserve query-authoritative Sources state.** Mounted volumes are ephemeral browser/provider facts, never an alternate Flutter root cache. Existing root-change reconciliation continues to re-query authoritative roots.

- [ ] **7.4 Run desktop regressions.** Existing desktop file picker, Add & Scan, Scan/Scan Again/Scan All, Jobs, hierarchy, and Phase 000/001 native contracts must remain unchanged.

---

## Task 8 — Add a repository-owned Android P02-002 native milestone and finish verification

**Files:**
- create `flutter/integration_test/phase_002_android_local_filesystem_test.dart`
- create `scripts/run_phase_002_android_local_filesystem_tests.sh`
- modify `justfile`
- architecture tests as required

- [ ] **8.1 Add a real Android integration scenario.** The harness prepares a primary-shared-storage fixture (for example `/sdcard/ArgusP02002Fixture/Child` plus a sentinel file) using adb/test setup. The app must:

```text
reach Ready with All files access granted
open Add Library Folder and show Argus browser, not SAF/file_selector
show primary volume from real StorageManager discovery
navigate provider-backed directories
show breadcrumbs/up + explicit Select this folder
show no Add & Scan / Scan / Scan Again / Scan All
add root-only and show Available
preserve same root ID across process restart
reselect duplicate without second root
reject/redirect overlap through existing typed outcome
remove root and prove sentinel remains on disk
create no scan job in the scenario
```

- [ ] **8.2 Add `just test-phase-002-android-local-filesystem`.** Keep it separate from `just check`. It may reuse P02-001 Android build/provision helpers and must work with a compatible ARM64 emulator/device. Keep x86_64 ABI build compatibility, but do not claim Apple Silicon can boot the x86_64 emulator.

- [ ] **8.3 Run final gates in order:**

```bash
just generate
just check-generated
just format
just check
just test-local-filesystem-native
just test-phase-000-native
just test-phase-001-native
just test-phase-002-android-local-filesystem   # compatible device/emulator
```

Also build the Android debug APK with both configured ABIs.

- [ ] **8.4 Perform an explicit exclusion search.** Confirm the diff contains no SAF tree selection, content-provider traversal, foreground service/WorkManager/wake lock, Android scan activation, API 29/32-bit work, Play/signing work, feature-layer filesystem traversal, or Flutter locator/volume-identity interpretation.

- [ ] **8.5 Write truthful completion evidence.** Report platform-neutral gate, real host LocalFilesystem tests, Android ARM64 native milestone, x86_64 packaging, and the still-deferred P02-001 x86_64 emulator gate separately. Do not claim physical SD/USB eject/remount evidence unless actually run; P02-005 owns broader permission-regrant/removable lifecycle evidence.

## Self-review invariants

1. No new provider family or SAF fallback exists.
2. Native mount path is transient and never persisted as Android root identity.
3. Stable volume identity + root-relative coordinate preserves root ID across trustworthy remount.
4. Flutter never parses filesystem/provider identities and never traverses Android storage directly.
5. Provider I/O occurs outside SQLite write transactions; availability persistence is a bounded follow-up mutation.
6. Global permission loss never masquerades as root deletion/unavailability evidence.
7. P02-002 creates roots only and activates no Android scans.
8. Desktop path-picker and Phase 001 behavior remain unchanged.
9. No schema migration is expected; if implementation proves one is required, stop and request a scope amendment rather than adding it silently.
10. Generated output is tool-owned and verification remains truthful about the deferred x86_64 emulator proof.
