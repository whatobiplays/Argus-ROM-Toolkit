# Phase 002 Slice 001 — Android Platform Bootstrap and First-Run Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish Android as a real Argus host on API 30+ with the existing Flutter/FRB/Rust/SQLite runtime, mandatory All files access readiness gating, optional notification onboarding, an application-scoped cached Flutter engine, and the shared Compact navigation contract, without implementing Android library-root browsing/scanning or foreground-job execution yet.

**Architecture:** Android extends the existing single-runtime product architecture rather than creating a mobile backend. A native Android `Application` owns one cached `FlutterEngine`; the Dart composition owns one `ArgusClient`; FRB owns the sole Rust boundary; Rust/SQLite remain authoritative. Android platform readiness is checked before `StartupController` is built, so missing All files access prevents Rust initialization rather than becoming a backend startup failure. The Android host supplies its app-private standard data directory to Rust as a standard host location, not as the existing test-only explicit override. Platform-specific Android mechanics stay in the Android host/Dart app-composition boundary; shared domain/application logic stays platform-neutral.

**Tech Stack:** Flutter 3.44.7, Dart 3.12+, Kotlin/Android embedding v2, Android API 30+, Riverpod 3, flutter_rust_bridge 2.12.0, Rust 1.97.1, cargo-ndk 4.1.2, SQLite/rusqlite, Bash, `just`, Flutter `integration_test`.

## Global Constraints

- Implement only `SLICE-P02-001 — Android Platform Bootstrap and First-Run Readiness` from governed `PHASE-002`, under `SPEC-X-002` and the amended owning subsystem specifications. The approved design document remains supporting rationale and must not override governed phase/spec contracts.
- Android MVP minimum is API 30. Do not add an API 29 compatibility path in this slice.
- Production CPU support is ARM64 (`arm64-v8a`); x86_64 exists for emulator/test. Do not add 32-bit Android targets.
- The generated development application identity `dev.argusromtoolkit.argus` is scaffold/test identity only. Do not declare it the permanent public release identity; P02-007 owns final direct-distribution identity/signing.
- `MANAGE_EXTERNAL_STORAGE` is mandatory on Android. `POST_NOTIFICATIONS` is requested on API 33+ but denial must not block Argus readiness.
- The OS state is authoritative for All files access on every launch/relevant resume. Never persist a boolean that can bypass `Environment.isExternalStorageManager()`.
- Persisting one native `SharedPreferences` boolean that the optional notification prompt received a terminal user response is allowed; it is onboarding UX state, not product/storage authority. A dismissed/interrupted notification dialog must not be recorded as completed.
- Android root selection is intentionally **not implemented** in this slice. Do not use `ACTION_OPEN_DOCUMENT_TREE`, Android `file_selector`, SAF, `DocumentFile`, or a path picker as a temporary source implementation. Android's existing library-folder picker seam must be inert until P02-002 replaces it with the approved Argus filesystem picker.
- Do not implement Android LocalFilesystem mount discovery, SD/USB browsing, root identity, source enumeration, Add & Scan, scans, or source hierarchy in this slice.
- Do not implement a foreground service, notification job projection, background execution lease, WorkManager, or job auto-resume in this slice. P02-004 owns those behaviors.
- Do not add Google Play release policy work, signing credentials, keystores, release uploads, or Play-specific behavior.
- `file_selector` 1.1.0 does not provide Android save-location selection. Do not falsely claim Android startup diagnostic export parity in Slice 001. Treat diagnostic export as a required platform-adapted Phase 002 capability to be completed by the applicable-feature/platform-integration work. `Open data directory` is not a meaningful Android user capability because the production database lives in app-private storage; it must not drive a fake Android file-browser feature.
- Preserve all existing Phase 000/001 desktop behavior and verification. No desktop runtime may become dependent on Android SDK/NDK tooling for `just check`.
- `just check` remains deterministic and platform-neutral. Android emulator/native verification is a separate repository-owned command.
- The Android native build may depend on Android SDK/NDK tooling, `adb`, and a running emulator; the platform-neutral suite may not.
- One Android process has exactly one cached Flutter engine, one normal Dart isolate, one root `ProviderScope`, one `ArgusClient`, one FRB runtime host, one SQLite authority, and one native event connection.
- Activity recreation/backgrounding must not call `generalShutdown`, destroy the cached engine, or create a replacement runtime.
- Generated FRB/Riverpod output changes only through `just generate`; never hand-edit generated files.
- Do not weaken tests or architecture guards to accommodate Android. Extend the guards to describe the new allowed platform boundary precisely.
- No implementation task may stage, commit, push, rewrite history, or restore unrelated worktree changes. Keep implementation changes uncommitted for owner review.

---

## File and Responsibility Map

### Documentation authority

- Create: `docs/phases/phase-002-android-first-class-platform-support.md` — phase-level outcome/slice map, referencing owning specs rather than duplicating them.
- Create: `docs/specifications/cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md` — Android-wide API baseline, permission/readiness, engine ownership, ABI/distribution, applicability, and verification policy.
- Modify: `docs/architecture/architecture-overview.md` — Android host/runtime placement and platform-readiness boundary.
- Modify: `docs/phases/README.md`, `docs/specifications/cross-cutting/README.md` — register Phase 002 and SPEC-X-002.
- Modify: `docs/specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md` — add Android to bounded platform diagnostics without exposing app-private paths.
- Modify: `docs/specifications/backend/spec-be-007-startup-coordination-and-recovery-contract.md` — define platform readiness as an outer host prerequisite, not a Rust startup phase.
- Modify: `docs/specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md` — define host-standard-data-directory initialization separately from explicit test/embedding override.
- Modify: `docs/specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md` — define the later Android foreground-execution host without moving lifecycle authority out of the runtime.
- Modify: `docs/specifications/backend/spec-be-011-source-provider-and-indexing-contract.md`, `docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md` — define the Android LocalFilesystem/removable-media/reconciliation contracts used by later slices.
- Modify: `docs/specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md` — register `app/platform` as app-composition infrastructure.
- Modify: `docs/specifications/frontend/spec-fe-004-routing-and-adaptive-application-shell.md` — make Compact navigation directly expose Sources, Jobs, and Settings on every platform.
- Modify: `docs/specifications/frontend/spec-fe-005-startup-and-recovery-ui.md` — define Android platform-readiness gating and capability applicability for diagnostic export/open-data-directory behavior.
- Modify: `docs/specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md`, `docs/specifications/frontend/spec-fe-007-design-system-foundation-and-accessibility-baseline.md`, `docs/specifications/frontend/spec-fe-008-sources-and-library-folder-management.md`, `docs/specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md` — define focused Android browse/client, adaptive/touch, folder-browser, and foreground-job presentation boundaries for the phase.
- Modify: `docs/conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md`, `docs/templates/phase.md`, `docs/templates/implementation-slice.md` — make Android native evidence and platform applicability durable repository workflow requirements.
- Modify: `docs/specifications/cross-cutting/spec-x-001-versioning-and-compatibility-contract.md` — remove desktop-only assumptions from matched Argus release/version language.

### Android host/build

- Create via pinned Flutter scaffold: `flutter/android/**`.
- Modify generated Android host files rather than maintaining a second template.
- Create: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusApplication.kt` — owns the one cached engine and platform channel.
- Create: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/ArgusPlatformBridge.kt` — Android OS permission/data-directory channel only.
- Modify: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/MainActivity.kt` — attaches/detaches the cached engine and forwards notification permission results.
- Modify: `flutter/android/app/src/main/AndroidManifest.xml` — application class plus storage/notification declarations.
- Modify: `flutter/android/app/build.gradle.kts` — `minSdk = 30` and Rust pre-build integration.
- Modify: `flutter/.metadata` only through the Flutter scaffold command.

### Rust/FRB startup

- Modify: `rust/crates/argus-application/src/observability.rs` — add bounded `PlatformClass::Android`.
- Modify: `rust/crates/argus-runtime/src/lib.rs` — Android platform classification and host-supplied standard application-data option.
- Modify: `rust/crates/argus-runtime/src/startup.rs` — consume the standard host data-directory selection without reclassifying it as an explicit test override.
- Modify: `rust/crates/argus-bridge/src/lib.rs` — add the focused standard-data-directory initialization entrypoint.
- Modify generated: `rust/crates/argus-bridge/src/frb_generated.rs`, `flutter/lib/core/bridge/generated/**` through `just generate` only.
- Modify: `flutter/lib/core/bridge/src/frb_argus_client_gateway.dart` — packaged Android library loading and standard-data-directory initialization.

### Flutter app platform boundary

- Create: `flutter/lib/app/platform/platform_host.dart` — narrow public app-composition barrel.
- Create: `flutter/lib/app/platform/application/platform_host_api.dart` — pure-Dart platform facts/port.
- Create: `flutter/lib/app/platform/application/platform_readiness_state.dart` — closed readiness/runtime-configuration vocabulary.
- Create: `flutter/lib/app/platform/application/platform_readiness_controller.dart` — keep-alive authoritative readiness coordinator and DI seam.
- Create: `flutter/lib/app/platform/native/platform_host_factory.dart` — sole production OS selection point.
- Create: `flutter/lib/app/platform/native/android_platform_host_api.dart` — MethodChannel adapter.
- Create: `flutter/lib/app/platform/native/desktop_platform_host_api.dart` — inert desktop host implementation used by the production platform factory when no readiness gate is required.
- Create: `flutter/lib/app/platform/presentation/platform_readiness_gate.dart` — pre-startup Android UI/lifecycle reconciliation gate.
- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart`, `flutter/lib/app/bootstrap/argus_app.dart`, `flutter/lib/app/bootstrap/client_bootstrap.dart` — compose the platform gate/configuration inside MaterialApp while preventing backend-dependent providers from being watched before Android readiness.
- Modify: `flutter/lib/features/startup/presentation/presentation_seams.dart`, `flutter/lib/features/startup/presentation/startup_failure_view.dart`, `flutter/lib/features/startup/startup.dart` — add a platform-neutral startup-presentation capability seam so Android does not expose recovery actions whose platform implementation is absent or explicitly excluded.
- Modify focused startup presentation tests under `flutter/test/features/startup/**` — preserve desktop defaults and prove Android capability filtering.

### Shared adaptive shell

- Modify: `flutter/lib/app/shell/application_shell.dart` — Compact `Sources / Jobs / Settings` `NavigationBar`.
- Modify: `flutter/test/app/shell/application_shell_test.dart` — direct-destination, badge, semantics, keyboard, and branch regressions.

### Tooling/tests

- Create: `scripts/build_android_bridge.sh` — pinned Rust Android library build into ignored `jniLibs` output.
- Create: `scripts/run_phase_002_android_bootstrap_tests.sh` — explicit local/emulator native milestone for this slice.
- Modify: `scripts/bootstrap.sh`, `justfile` — Android prerequisites/commands without changing `just check` semantics.
- Create: `flutter/test/architecture/android_host_contract_test.dart`.
- Modify: `flutter/test/architecture/architecture_boundaries_test.dart` and generated-file registration.
- Create tests under `flutter/test/app/platform/**`.
- Create: `flutter/integration_test/phase_002_android_permission_gate_test.dart`.
- Create: `flutter/integration_test/phase_002_android_bootstrap_test.dart`.

---

### Task 1: Establish Phase 002 specification authority for Slice 001

**Files:** documentation files listed above only.

**Prerequisite status:** Completed before product implementation. Governing Phase 002/specification amendments were applied and the platform-neutral repository gate passed as `validation-2026-08-16T02-56-32-974Z-822fd05d`. Implementation execution starts at Task 2.

- [x] **Step 1: Create SPEC-X-002 with the approved platform-wide contract**

Write `SPEC-X-002 — Android Platform Runtime and Capability Contract` with normative ownership for:

```text
minimum Android API = 30
production ABI = arm64-v8a
emulator/test ABI = x86_64
All files access = mandatory runtime prerequisite
notification permission = optional on API 33+
one application-scoped cached Flutter engine / Dart isolate / Argus runtime
Activity lifecycle != runtime lifecycle
Android direct distribution first; Play and API 29 deferred
Shared / Platform-adapted / Platform-specific / Excluded applicability model
Android-applicable capability coverage required before phase completion
x86_64 emulator verification + physical ARM64 phase milestone
```

Explicitly state that P02-001 does not implement foreground-service execution or Android source-provider semantics.

- [x] **Step 2: Create the Phase 002 phase document**

Create `docs/phases/phase-002-android-first-class-platform-support.md` with the seven approved slices and mark P02-007 as final. Keep detailed subsystem contracts in specs.

- [x] **Step 3: Amend the existing owning specs**

At minimum:

```text
SPEC-BE-003: Android becomes a bounded PlatformClass value; no raw app-private path enters safe context.
SPEC-BE-007: host/platform readiness is an outer prerequisite, not a ninth Rust startup phase.
SPEC-BE-008: define host-standard-data-directory initialization; keep explicit override test/embedding-only.
SPEC-FE-001: register app/platform as app-composition infrastructure, not a feature/domain layer.
SPEC-FE-004: Compact navigation is Sources / Jobs / Settings directly, width-driven on all platforms.
SPEC-FE-005: Android platform readiness gates construction/consumption of StartupController.
SPEC-X-001: one Argus product/version may include desktop and Android artifacts; compatibility language is not desktop-only.
```

Record the newly proven capability applicability:

```text
Startup diagnostic export: Platform-adapted on Android, required later in Phase 002; current desktop getSaveLocation path is not reused.
Open startup data directory: Excluded on Android because app-private storage is an implementation detail, not a user file-management surface.
```

`SPEC-FE-005` must also state that backend-advertised recovery capability is necessary but not sufficient for rendering a platform-inapplicable action: app composition may suppress an advertised action only through an explicit typed platform-capability seam. This does not let Flutter invent backend recovery actions or make runtime state authoritative locally.

- [x] **Step 4: Update documentation indexes and architecture overview**

Register the new phase/spec and add the single-runtime Android host diagram/text. Do not rewrite completed Phase 000/001 history as though Android existed then.

- [x] **Step 5: Run documentation consistency checks available in `just check`**

Do not run Android tooling yet. Resolve only documentation/reference failures introduced by these edits.

---

### Task 2: Scaffold Android and establish reproducible Rust-to-APK build plumbing

**Files:**
- Create/modify `flutter/android/**`, `flutter/.metadata` via Flutter tooling.
- Create `scripts/build_android_bridge.sh`.
- Modify `scripts/bootstrap.sh`, `justfile`.
- Create `flutter/test/architecture/android_host_contract_test.dart`.

- [ ] **Step 1: Write the structural Android-host test RED**

Create `flutter/test/architecture/android_host_contract_test.dart` and initially assert only the scaffold/build contract owned by Task 2:

```dart
test('Android scaffold is API 30+ and repository-owned', () {
  final settings = File('android/settings.gradle.kts').readAsStringSync();
  final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  expect(settings, contains('dev.flutter.flutter-plugin-loader'));
  expect(appBuild, contains('minSdk = 30'));
  expect(manifest, contains('android:name="io.flutter.embedding.android.NormalTheme"'));
  expect(manifest, isNot(contains('<service')));
});
```

Do **not** assert `ArgusApplication`, All files access, or notification wiring yet; Task 4 extends this same structural test before implementing those contracts.

Run:

```bash
cd flutter
fvm flutter test test/architecture/android_host_contract_test.dart --no-pub
```

Confirm RED because the Android host does not exist.

- [ ] **Step 2: Generate the Android scaffold with the pinned Flutter SDK**

From `flutter/` run exactly:

```bash
fvm flutter create --empty --platforms=android --project-name=argus --org=dev.argusromtoolkit .
```

Immediately inspect the diff. Keep the generated Android host and `.metadata` Android registration. Revert any scaffold rewrite of governed Dart/pubspec content that is unrelated to adding Android. Do not hand-edit `.metadata`.

Treat `dev.argusromtoolkit.argus` as development/scaffold identity only.

- [ ] **Step 3: Pin `minSdk = 30` without pinning an independent compile/target cadence**

In `flutter/android/app/build.gradle.kts`, keep Flutter-managed compile/target/NDK defaults and set only:

```kotlin
defaultConfig {
    applicationId = "dev.argusromtoolkit.argus"
    minSdk = 30
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
}
```

Do not add API 29 branches or a release signing configuration.

- [ ] **Step 4: Add the pinned Rust Android build script**

Create `scripts/build_android_bridge.sh` with the repository pin and two approved Rust targets:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_ROOT="$ROOT_DIR/.dart_tool/cargo-ndk"
JNI_DIR="$ROOT_DIR/flutter/android/app/src/main/jniLibs"
CARGO_NDK_VERSION="4.1.2"

rust_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
[[ -n "$rust_channel" ]] || { printf 'Missing Rust toolchain pin\n' >&2; exit 1; }

rustup target add --toolchain "$rust_channel" aarch64-linux-android x86_64-linux-android

if [[ ! -x "$TOOL_ROOT/bin/cargo-ndk" ]]; then
  bash "$ROOT_DIR/scripts/run_rust.sh" cargo install cargo-ndk \
    --version "$CARGO_NDK_VERSION" --locked --root "$TOOL_ROOT"
fi

rm -rf "$JNI_DIR/arm64-v8a" "$JNI_DIR/x86_64"
mkdir -p "$JNI_DIR"

env \
  PATH="$TOOL_ROOT/bin:$PATH" \
  CARGO_NDK_PLATFORM=30 \
  bash "$ROOT_DIR/scripts/run_rust.sh" cargo ndk \
    -t arm64-v8a \
    -t x86_64 \
    -o "$JNI_DIR" \
    build \
    --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
    --package argus-bridge \
    --locked
```

Keep generated `.so` outputs ignored; do not commit native binaries.

- [ ] **Step 5: Make Android Gradle builds depend on the Rust bridge build**

In `flutter/android/app/build.gradle.kts`, add a repository-root `Exec` task and make `preBuild` depend on it:

```kotlin
val repositoryRoot = rootProject.projectDir.parentFile.parentFile
val buildArgusRust by tasks.registering(Exec::class) {
    workingDir(repositoryRoot)
    commandLine("bash", File(repositoryRoot, "scripts/build_android_bridge.sh").absolutePath)
}

tasks.named("preBuild") {
    dependsOn(buildArgusRust)
}
```

The generated Flutter/Gradle Android build remains the packaging owner; Rust only produces the ABI-specific shared libraries Gradle packages.

- [ ] **Step 6: Extend bootstrap/just targets without changing `just check`**

Add repository-owned commands equivalent to:

```make
build-android-bridge:
    bash scripts/build_android_bridge.sh

build-android-debug:
    cd flutter && fvm flutter build apk --debug --target-platform android-arm64,android-x64
```

Extend `scripts/bootstrap.sh` to install the two Rust Android targets with the pinned Rust toolchain and install `cargo-ndk` 4.1.2 into `.dart_tool/cargo-ndk` when missing. It must not attempt to install or mutate the machine's Android SDK/NDK; those remain explicit native-build prerequisites. `just check` must not require Android SDK/NDK.

- [ ] **Step 7: Run the Task-2 scaffold/build structural test GREEN and attempt the focused Android debug build**

Run:

```bash
cd flutter
fvm flutter test test/architecture/android_host_contract_test.dart --no-pub
cd ..
bash scripts/build_android_bridge.sh
cd flutter
fvm flutter build apk --debug --target-platform android-arm64,android-x64 --no-pub
```

If the host lacks Android SDK/NDK prerequisites, record that as an environment blocker; do not weaken build integration.

---

### Task 3: Make Rust startup Android-aware and accept a host-standard app-data directory

**Files:**
- Modify `rust/crates/argus-application/src/observability.rs`.
- Modify `rust/crates/argus-runtime/src/lib.rs`, `rust/crates/argus-runtime/src/startup.rs`.
- Modify `rust/crates/argus-bridge/src/lib.rs`.
- Modify `flutter/lib/core/bridge/src/frb_argus_client_gateway.dart`.
- Regenerate FRB output.

- [ ] **Step 1: Write Rust tests RED for Android platform/data-directory semantics**

Add focused tests proving:

```rust
#[test]
fn android_requires_a_host_standard_data_directory_when_not_explicitly_overridden() {
    assert!(resolve_data_directory(
        Platform::Android,
        Some(PathBuf::from("/home/should-not-be-used").as_path()),
        None,
        Some(PathBuf::from("/tmp/xdg-should-not-be-used").as_path()),
        None,
        None,
    ).is_err());
}

#[test]
fn android_accepts_a_host_standard_data_directory() {
    let standard = PathBuf::from("/data/user/0/dev.argusromtoolkit.argus/files/argus");
    assert_eq!(
        resolve_data_directory(
            Platform::Android,
            None,
            None,
            None,
            Some(standard.clone()),
            None,
        ).unwrap(),
        standard,
    );
}
```

Also test that a host-standard directory produces `PathClass::StandardApplicationData`, while the existing `with_data_directory` path still produces `ExplicitOverride`.

Run the smallest `argus-runtime` test target and confirm RED.

- [ ] **Step 2: Add Android to the bounded platform vocabulary**

In application observability:

```rust
pub enum PlatformClass {
    Windows,
    MacOs,
    Unix,
    Android,
}
```

Update every exhaustive serialization/display/safe-context test so Android serializes to the stable bounded value `android`. Do not expose package names or paths in safe context.

- [ ] **Step 3: Model host-standard data separately from explicit overrides**

Evolve `KernelBootstrapOptions` to keep the two intents distinct:

```rust
#[derive(Clone, Debug, Default)]
pub struct KernelBootstrapOptions {
    pub data_directory_override: Option<PathBuf>,
    pub standard_data_directory: Option<PathBuf>,
}

impl KernelBootstrapOptions {
    pub fn with_data_directory(directory: impl Into<PathBuf>) -> Self {
        Self {
            data_directory_override: Some(directory.into()),
            standard_data_directory: None,
        }
    }

    pub fn with_standard_data_directory(directory: impl Into<PathBuf>) -> Self {
        Self {
            data_directory_override: None,
            standard_data_directory: Some(directory.into()),
        }
    }
}
```

`Platform::current()` must check Android before the generic Unix branch:

```rust
if cfg!(target_os = "android") {
    Self::Android
} else if cfg!(target_os = "windows") {
    Self::Windows
} else if cfg!(target_os = "macos") {
    Self::MacOs
} else {
    Self::Unix
}
```

`resolve_data_directory` precedence is:

```text
1. explicit override (test/embedding) -> ExplicitOverride
2. host-standard directory -> StandardApplicationData
3. desktop platform default resolution
4. Android with no host-standard directory -> error; never HOME/XDG fallback
```

Validate host-standard and explicit roots with the same absolute/no-dot-component safety rules.

- [ ] **Step 4: Update both startup paths to preserve PathClass truthfully**

Both `StartupCoordinator` and the legacy `bootstrap_kernel` path must classify standard host data as `StandardApplicationData`. Do not infer the class solely from `data_directory_override.is_some()` after this change.

Update `platform_class()`:

```rust
Platform::Android => PlatformClass::Android,
```

- [ ] **Step 5: Add the focused bridge initialization entrypoint**

In `argus-bridge`:

```rust
pub fn initialize_with_standard_data_directory(
    data_directory: String,
) -> Result<RuntimeStateDto, ApplicationErrorDto> {
    initialize_with_options(
        argus_runtime::KernelBootstrapOptions::with_standard_data_directory(data_directory),
    )
}
```

Do not change the semantics of existing `initialize()` or `initialize_with_data_directory()`.

- [ ] **Step 6: Regenerate FRB and wire the Dart gateway**

Run:

```bash
just generate
```

Extend `FrbArgusClientGateway` with a production host-standard path distinct from the existing test override:

```dart
FrbArgusClientGateway({
  frb.RustLibApi? api,
  Future<void> Function()? initializeNative,
  String? dataDirectoryOverride,
  String? standardApplicationDataDirectory,
  Stream<dto.RuntimeEventDto> Function()? eventStreamFactory,
}) : _standardApplicationDataDirectory = standardApplicationDataDirectory,
     // existing initialization...
     ;

final String? _standardApplicationDataDirectory;
```

Initialization precedence must be explicit:

```dart
if (_dataDirectoryOverride != null) {
  return _rustApi.crateInitializeWithDataDirectory(
    dataDirectory: _dataDirectoryOverride,
  );
}
if (_standardApplicationDataDirectory != null) {
  return _rustApi.crateInitializeWithStandardDataDirectory(
    dataDirectory: _standardApplicationDataDirectory,
  );
}
return _rustApi.crateInitialize();
```

For Android packaged native libraries, use the generated FRB loader rather than desktop executable-neighbor lookup:

```dart
if (Platform.isAndroid) {
  await frb.RustLib.init();
  return;
}
```

Keep the existing macOS process loader and Windows/Linux sibling-library logic unchanged.

- [ ] **Step 7: Run Rust/bridge tests GREEN and generated-output verification**

Run:

```bash
bash scripts/run_rust.sh cargo test --manifest-path rust/Cargo.toml -p argus-runtime --locked
bash scripts/run_rust.sh cargo test --manifest-path rust/Cargo.toml -p argus-bridge --locked
just check-generated
```

---

### Task 4: Build the application-scoped Android engine and native platform bridge

**Files:** Android Kotlin/manifest files plus structural tests.

- [ ] **Step 1: Extend the Android host contract test RED**

Assert the source tree contains:

```text
ArgusApplication : Application
FlutterEngineCache
one stable engine id
MainActivity provides the application-owned engine
MainActivity does not destroy the engine with the Activity
ArgusPlatformBridge channel name = argus/platform_readiness
MANAGE_EXTERNAL_STORAGE + POST_NOTIFICATIONS declared
no foreground-service class or FOREGROUND_SERVICE permission in this slice
```

Run the architecture test RED before creating the classes.

- [ ] **Step 2: Implement `ArgusApplication` as the one engine owner**

Use this ownership shape:

```kotlin
class ArgusApplication : Application() {
    lateinit var flutterEngine: FlutterEngine
        private set
    lateinit var platformBridge: ArgusPlatformBridge
        private set

    override fun onCreate() {
        super.onCreate()
        flutterEngine = FlutterEngine(this)
        platformBridge = ArgusPlatformBridge(
            application = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
    }

    companion object {
        const val ENGINE_ID = "argus_primary_engine"
    }
}
```

Register the MethodChannel **before** executing Dart so the prewarmed isolate can query readiness immediately. Do not create a headless second engine.

- [ ] **Step 3: Make `MainActivity` attach to the existing engine only**

Use:

```kotlin
class MainActivity : FlutterActivity() {
    private val argusApplication: ArgusApplication
        get() = application as ArgusApplication

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        argusApplication.flutterEngine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onStart() {
        super.onStart()
        argusApplication.platformBridge.attachActivity(this)
    }

    override fun onStop() {
        argusApplication.platformBridge.detachActivity(this)
        super.onStop()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        argusApplication.platformBridge.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults,
        )
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
```

Detachment may remove only the current Activity reference; it must not close the MethodChannel, engine, Dart isolate, FRB host, or SQLite runtime.

- [ ] **Step 4: Implement the narrow Android platform MethodChannel**

`ArgusPlatformBridge` owns exactly these methods in Slice 001:

```text
readSnapshot
openAllFilesAccessSettings
requestNotificationPermission
```

Use channel name:

```kotlin
private const val CHANNEL = "argus/platform_readiness"
```

`readSnapshot` returns only this bounded map:

```kotlin
mapOf(
    "allFilesAccessRequired" to true,
    "allFilesAccessGranted" to Environment.isExternalStorageManager(),
    "notificationAuthorization" to notificationAuthorizationWireValue(),
    "standardApplicationDataDirectory" to File(application.filesDir, "argus").absolutePath,
)
```

`notificationAuthorizationWireValue()` is exactly one of:

```text
notRequired
promptRequired
granted
denied
```

Rules:

```text
API < 33 -> notRequired
POST_NOTIFICATIONS granted -> granted
not granted + terminal prompt-completed preference true -> denied
not granted + prompt not terminally completed -> promptRequired
```

The SharedPreferences key may record only terminal notification prompt completion. If `onRequestPermissionsResult` receives empty arrays/interruption, return `promptRequired` and leave the preference false.

- [ ] **Step 5: Implement All files access settings launch with a bounded fallback**

Primary intent:

```kotlin
Intent(
    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
    Uri.parse("package:${application.packageName}"),
)
```

If no matching activity exists, fall back to:

```kotlin
Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
```

If there is no attached Activity or neither intent resolves, return a typed MethodChannel error code; never report success optimistically. Dart re-reads `Environment.isExternalStorageManager()` on resume and does not trust the launch result as authorization.

- [ ] **Step 6: Implement optional notification request without a dependency package**

On API 33+ use the attached Activity's platform `requestPermissions` for `Manifest.permission.POST_NOTIFICATIONS`. Allow only one in-flight request. Complete the MethodChannel result from `onRequestPermissionsResult` and persist prompt completion only for a non-empty terminal grant/deny result.

On API < 33 return `notRequired`; if already granted return `granted` without opening another dialog.

- [ ] **Step 7: Update the manifest**

Add:

```xml
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Set:

```xml
<application
    android:name=".ArgusApplication"
    ...>
```

Do not add storage legacy flags, SAF declarations, foreground services, WorkManager, or broad package-query permissions.

- [ ] **Step 8: Run structural tests and Android compilation GREEN**

Run the Android host contract test and `fvm flutter build apk --debug --target-platform android-arm64,android-x64 --no-pub`.

---

### Task 5: Add the pure-Dart platform-readiness state machine and pre-startup gate

**Files:** new `flutter/lib/app/platform/**`, focused tests, architecture guards.

- [ ] **Step 1: Write controller tests RED**

Create a fake `PlatformHostApi` and test these exact transitions:

```text
initial read: required + All files denied -> requiresAllFilesAccess
open settings does not itself mark readiness granted
resume/refresh after observed grant + promptRequired -> requiresNotificationPermission
notification request granted -> ready(notification=granted)
notification request denied -> ready(notification=denied)
notification notRequired -> ready
read failure -> unavailable with bounded local failure kind
ready -> refresh observing All files revoked -> requiresAllFilesAccess
ready runtime configuration carries the host-standard data directory
first Ready state latches that runtime configuration for the process lifetime
ready -> revoked -> regranted preserves the same latched runtime configuration
```

Raw `PlatformException` strings must not become UI/domain copy.

- [ ] **Step 2: Define the pure-Dart port and closed models**

Use plain immutable/sealed Dart types, not Android SDK types:

```dart
enum NotificationAuthorization {
  notRequired,
  promptRequired,
  granted,
  denied,
}

enum PlatformReadinessFailureKind {
  snapshotUnavailable,
  settingsLaunchFailed,
  notificationRequestFailed,
}

final class PlatformHostSnapshot {
  const PlatformHostSnapshot({
    required this.allFilesAccessRequired,
    required this.allFilesAccessGranted,
    required this.notificationAuthorization,
    required this.standardApplicationDataDirectory,
  });

  final bool allFilesAccessRequired;
  final bool allFilesAccessGranted;
  final NotificationAuthorization notificationAuthorization;
  final String? standardApplicationDataDirectory;
}

abstract interface class PlatformHostApi {
  Future<PlatformHostSnapshot> readSnapshot();
  Future<void> openAllFilesAccessSettings();
  Future<NotificationAuthorization> requestNotificationPermission();
}
```

Define readiness states:

```dart
sealed class PlatformReadinessState { const PlatformReadinessState(); }
final class PlatformReadinessLoading extends PlatformReadinessState { const PlatformReadinessLoading(); }
final class PlatformReadinessRequiresAllFilesAccess extends PlatformReadinessState {
  const PlatformReadinessRequiresAllFilesAccess({this.failure});
  final PlatformReadinessFailureKind? failure;
}
final class PlatformReadinessRequiresNotificationPermission extends PlatformReadinessState {
  const PlatformReadinessRequiresNotificationPermission({this.failure});
  final PlatformReadinessFailureKind? failure;
}
final class PlatformReadinessReady extends PlatformReadinessState {
  const PlatformReadinessReady({required this.runtimeConfiguration, required this.notificationAuthorization});
  final PlatformRuntimeConfiguration runtimeConfiguration;
  final NotificationAuthorization notificationAuthorization;
}
final class PlatformReadinessUnavailable extends PlatformReadinessState {
  const PlatformReadinessUnavailable(this.failure);
  final PlatformReadinessFailureKind failure;
}

final class PlatformRuntimeConfiguration {
  const PlatformRuntimeConfiguration({this.standardApplicationDataDirectory});
  final String? standardApplicationDataDirectory;
}
```

- [ ] **Step 3: Implement one keep-alive Riverpod controller and one DI seam**

In `platform_readiness_controller.dart`:

```dart
@Riverpod(keepAlive: true)
PlatformHostApi platformHostApi(Ref ref) {
  throw StateError('platformHostApiProvider must be supplied by app composition');
}

@Riverpod(keepAlive: true)
class PlatformReadinessController extends _$PlatformReadinessController {
  bool _refreshing = false;
  PlatformRuntimeConfiguration? _runtimeConfiguration;

  /// Process-lifetime runtime configuration established by the first Ready
  /// platform snapshot. Permission readiness may later regress, but an already
  /// running Argus runtime must not be reconfigured or replaced because of it.
  PlatformRuntimeConfiguration? get runtimeConfiguration =>
      _runtimeConfiguration;

  @override
  PlatformReadinessState build() {
    unawaited(refresh());
    return const PlatformReadinessLoading();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await ref.read(platformHostApiProvider).readSnapshot();
      final classified = classifyPlatformReadiness(snapshot);
      if (classified case PlatformReadinessReady(
        :final runtimeConfiguration,
        :final notificationAuthorization,
      )) {
        _runtimeConfiguration ??= runtimeConfiguration;
        state = PlatformReadinessReady(
          runtimeConfiguration: _runtimeConfiguration!,
          notificationAuthorization: notificationAuthorization,
        );
      } else {
        state = classified;
      }
    } catch (_) {
      state = const PlatformReadinessUnavailable(
        PlatformReadinessFailureKind.snapshotUnavailable,
      );
    } finally {
      _refreshing = false;
    }
  }

  // openAllFilesAccessSettings() and requestNotificationPermission()
  // map only to the bounded failure kinds above and then authoritative re-reads.
}
```

Do not set state to Loading on every resume; retain the current presentation while a refresh is in flight, then replace it with the authoritative result. `_runtimeConfiguration` is deliberately not cleared when live permission readiness regresses: the gate hides normal content, but a previously initialized root client keeps its original app-private data root and runtime identity.

- [ ] **Step 4: Implement the native Dart adapters**

`MethodChannelAndroidPlatformHostApi` uses only `MethodChannel('argus/platform_readiness')`, validates every map field/wire enum, and converts malformed native replies to a bounded failure/typed exception. It never parses or displays the app-data path.

Define the factory result explicitly:

```dart
final class PlatformHostComposition {
  const PlatformHostComposition({
    required this.api,
    required this.requiresReadinessGate,
  });

  final PlatformHostApi api;
  final bool requiresReadinessGate;
}
```

`createPlatformHostComposition()` is the sole production OS-selection point:

```dart
PlatformHostComposition createPlatformHostComposition() {
  if (Platform.isAndroid) {
    return PlatformHostComposition(
      api: const MethodChannelAndroidPlatformHostApi(),
      requiresReadinessGate: true,
    );
  }
  return PlatformHostComposition(
    api: const DesktopPlatformHostApi(),
    requiresReadinessGate: false,
  );
}
```

No feature/controller code may import `dart:io` or branch on Android.

- [ ] **Step 5: Write widget tests RED for the MaterialApp-level platform gate**

Prove:

```text
requiresAllFilesAccess -> child is not built; direct settings action is visible
requiresNotificationPermission -> child is not built; notification explanation/action visible
denied notification result -> child becomes visible
unavailable -> bounded retry UI
WidgetsBinding resumed -> authoritative refresh
ready then revoked on resume -> child hidden by readiness surface without calling backend shutdown
ready then revoked -> latched runtime configuration remains unchanged and no root-client factory replacement occurs
```

Use a sentinel child whose build count is observable to prove the backend subtree is never constructed before platform readiness.

- [ ] **Step 6: Implement `PlatformReadinessGate`**

The gate owns `WidgetsBindingObserver`; its UI copy is bounded and action-oriented. Use a `Scaffold`/`SafeArea`/centered constrained column consistent with existing startup surfaces. The gate is rendered from `ArgusApp`'s `MaterialApp.router.builder`, so it has normal Material, directionality, media-query, and theme context even before backend startup.

Required All files screen:

```text
Title: Storage access required
Body: Argus needs access to manage files on this device so it can work with your local game library. Enable “Allow access to manage all files” in Android settings to continue.
Primary action: Open Android settings
Secondary state/action after launch failure: Retry
```

Optional notification screen:

```text
Title: Background job notifications
Body: Allow notifications so Argus can show progress and controls for long-running work. You can continue if you decline.
Primary action: Continue
```

`Continue` invokes the native permission request; either grant or terminal denial advances to Ready. Dismissal/interruption remains in the notification step.

- [ ] **Step 7: Run controller/gate tests GREEN**

Run:

```bash
cd flutter
fvm flutter test test/app/platform --no-pub
```

---

### Task 6: Compose Android readiness ahead of startup and keep root selection inert

**Files:** `app_bootstrap.dart`, `argus_app.dart`, `client_bootstrap.dart`, `flutter/lib/features/startup/presentation/presentation_seams.dart`, `flutter/lib/features/startup/presentation/startup_failure_view.dart`, `flutter/lib/features/startup/startup.dart`, focused app/startup presentation tests, architecture guards.

- [ ] **Step 1: Add one narrow platform-composition test seam and write composition tests RED**

Extend `ArgusBootstrap` with one optional, typed `PlatformHostComposition? platformHostComposition` constructor parameter. Production leaves it null and calls `createPlatformHostComposition()`; tests may inject only a complete platform-host composition. Do not expose an arbitrary `ProviderOverride` list or raw MethodChannel test hook.

Prove these invariants with test-owned platform/API and gateway fakes:

```text
when Android platform readiness is not Ready, no ArgusClientGateway initialize call occurs
when readiness becomes Ready, exactly one root client initializes
host standard app-data directory is passed only to the production FRB gateway configuration seam
clientGatewayFactory test override still bypasses the production FRB factory cleanly
desktop composition retains the existing startup path and does not require Android readiness
Android libraryFolderPicker production seam is inert in Slice 001
Android startup failure presentation hides Export Diagnostics and Open Data Directory even if the backend advertises them
Android still presents advertised Retry Startup, Reset Appearance Settings, Copy Technical Details, and Exit
Desktop startup failure presentation retains the existing advertised-action behavior by default
```

Do not add an arbitrary ProviderOverride list to `ArgusBootstrap`.

- [ ] **Step 2: Add a narrow standard-data-directory seam to client bootstrap**

Keep `ArgusClientGateway` public contracts unchanged. In `client_bootstrap.dart`, add an app-private provider:

```dart
@Riverpod(keepAlive: true)
String? standardApplicationDataDirectory(Ref ref) => null;

@Riverpod(keepAlive: true)
ArgusClientGateway Function() argusClientGatewayFactory(Ref ref) {
  final standardDirectory = ref.watch(standardApplicationDataDirectoryProvider);
  return () => FrbArgusClientGateway(
    standardApplicationDataDirectory: standardDirectory,
  );
}
```

The existing explicit `clientGatewayFactory` test seam remains authoritative when supplied.

- [ ] **Step 3: Compose platform host/readiness in `ArgusBootstrap`**

Production bootstrap creates one `PlatformHostComposition`; tests may supply the narrow constructor seam from Step 1. Its `PlatformHostApi` is supplied as an override. When `requiresReadinessGate` is true, also override `standardApplicationDataDirectoryProvider` from the **ready** `PlatformRuntimeConfiguration`.

Use this exact composition shape in `ArgusBootstrap`:

```dart
final platform = platformHostComposition ?? createPlatformHostComposition();

return ProviderScope(
  overrides: [
    platformHostApiProvider.overrideWithValue(platform.api),
    if (clientGatewayFactory != null)
      argusClientGatewayFactoryProvider.overrideWithValue(clientGatewayFactory!)
    else if (platform.requiresReadinessGate)
      standardApplicationDataDirectoryProvider.overrideWith((ref) {
        final configuration = ref
            .read(platformReadinessControllerProvider.notifier)
            .runtimeConfiguration;
        if (configuration == null) {
          throw StateError(
            'Android runtime configuration requested before platform readiness',
          );
        }
        return configuration.standardApplicationDataDirectory;
      }),
    // existing settings/sources/jobs composition...
  ],
  child: ArgusApp(
    platformReadinessRequired: platform.requiresReadinessGate,
  ),
);
```

Do **not** wrap `ArgusApp` from outside: the readiness UI needs Material/MediaQuery context. Instead, evolve `ArgusApp` so it conditionally watches backend-dependent presentation state only after platform readiness, then puts the platform gate ahead of `StartupGate` inside `MaterialApp.router.builder`:

```dart
final platformReady =
    !platformReadinessRequired ||
    ref.watch(platformReadinessControllerProvider)
        is PlatformReadinessReady;
final authoritativeThemeMode = platformReady
    ? ref.watch(rootThemeModeProvider)
    : null;

return MaterialApp.router(
  // existing title/themes/router...
  themeMode: authoritativeThemeMode ?? ThemeMode.system,
  builder: (context, child) {
    final startup = StartupGate(
      child: ApplicationPresentationGate(child: child!),
    );
    return platformReadinessRequired
        ? PlatformReadinessGate(child: startup)
        : startup;
  },
  routerConfig: router,
);
```

This conditional watch is required: `rootThemeModeProvider` reaches `appearanceSettingsControllerProvider`, whose runtime-context composition reaches `readyRuntimeInstanceIdProvider` and therefore `StartupController`. While Android readiness is not Ready, `ArgusApp` must not watch that chain. The `StartupGate` widget may be constructed as the platform gate's child, but it is not built until `PlatformReadinessGate` returns it.

The standard-data-directory override intentionally uses `ref.read` of the controller's **latched** runtime configuration rather than watching live readiness. Once the root `ArgusClient` has been created, later permission revocation must hide the application behind `PlatformReadinessGate` without invalidating `argusClientGatewayFactoryProvider`, rebuilding `ArgusClientHost`, closing the event connection, or replacing the Rust runtime.

- [ ] **Step 4: Keep Android Sources root selection intentionally inert**

At app composition, when running Android production and no test picker override is supplied, provide an inert Slice-001 picker:

```dart
Future<LocalFilesystemRootSelection?> androidRootSelectionUnavailable() async => null;
```

This is not the Android picker implementation. It prevents the endorsed Android `file_selector` plugin from accidentally creating a rejected SAF/path source path before P02-002. P02-002 must replace this composition seam with the approved Argus-owned filesystem picker.

Do not add Android checks inside the Sources feature.

- [ ] **Step 5: Filter platform-inapplicable startup recovery actions through a typed presentation seam**

Do not modify `StartupController`, backend recovery-action DTOs, or Rust recovery advertisement merely to hide Android-inapplicable presentation actions. The runtime still truthfully advertises capabilities it owns; presentation combines that authority with explicit platform applicability.

In `presentation_seams.dart`, add a closed immutable capability value with desktop-compatible defaults:

```dart
final class StartupPresentationCapabilities {
  const StartupPresentationCapabilities({
    required this.diagnosticsExport,
    required this.openDataDirectory,
  });

  final bool diagnosticsExport;
  final bool openDataDirectory;
}

@Riverpod(keepAlive: true)
StartupPresentationCapabilities startupPresentationCapabilities(Ref ref) =>
    const StartupPresentationCapabilities(
      diagnosticsExport: true,
      openDataDirectory: true,
    );
```

Export the type/provider from `features/startup/startup.dart` so app composition can override it without importing a private presentation file.

For Android production composition in `ArgusBootstrap`, override it with:

```dart
const StartupPresentationCapabilities(
  diagnosticsExport: false,
  openDataDirectory: false,
)
```

Rationale:

```text
Export Diagnostics -> Platform-adapted; hidden only until the Android exporter is implemented later in Phase 002.
Open Data Directory -> Excluded on Android; app-private storage is not exposed as a user file-management surface.
Retry Startup / Reset Appearance Settings / Copy Technical Details / Exit -> unaffected; render when backend-advertised.
Desktop -> no override; existing behavior remains unchanged.
```

In `StartupFailureView`, compute action visibility from **both** backend advertisement and the typed presentation capability. Keep spacing/primary-action logic based on the final visible action set so suppressing Export/Open cannot leave phantom separators or alter Retry/Reset/Exit priority. Do not add `Platform.isAndroid` or `dart:io` checks to the view/controller.

Add focused widget tests proving:

```text
desktop/default capabilities + advertised Export/Open -> both existing actions remain visible
Android capabilities + advertised Export/Open -> both actions are absent
Android capabilities do not hide advertised Retry/Reset/Copy/Exit
a hidden action cannot be dispatched through the presentation
suppression does not mutate StartupState or the backend recoveryActions list
```

- [ ] **Step 6: Extend architecture guards**

Mechanically enforce:

```text
one root ProviderScope remains in app_bootstrap.dart
Platform.isAndroid/dart:io platform selection stays in app/platform/native (or narrowly app composition), not features
app/platform/application imports no Flutter widgets, core/bridge generated DTOs, or Android classes
Android platform adapter imports MethodChannel but no source/job feature internals
StartupController remains unaware of Android permissions
Sources feature still does not own filesystem traversal/platform permissions
main.dart remains the existing thin bootstrap entrypoint
```

Update the architecture test's exact production/generated file inventory for the new app/platform files/providers.

- [ ] **Step 7: Run bootstrap/startup-presentation/architecture tests GREEN**

Run:

```bash
cd flutter
fvm flutter test test/app/bootstrap test/app/platform test/features/startup test/architecture --no-pub
```

---

### Task 7: Replace Compact Jobs+More with shared direct bottom navigation

**Files:** modify exactly `flutter/lib/app/shell/application_shell.dart` and `flutter/test/app/shell/application_shell_test.dart`. If the focused tests reveal a defect whose owner is outside these two files, stop Task 7 and record the required scope amendment instead of widening this task implicitly.

- [ ] **Step 1: Rewrite Compact shell tests RED**

Replace tests for `compact-more-button` with direct Compact destination assertions:

```text
Sources, Jobs, Settings are all visible without opening a sheet
current destination is selected
Sources tap calls onSourcesSelected
Jobs tap preserves the existing sole-active-job routing behavior through BranchAwareShell
Settings tap calls onSettingsSelected
Jobs shows active-count badge when activeCount > 0
all three destinations expose Material semantics and practical >=48 logical-pixel targets
keyboard navigation remains operable on desktop Compact widths
Medium/Expanded/Large rail behavior is unchanged
branch restoration/reselection behavior remains unchanged
```

Run the focused shell test RED.

- [ ] **Step 2: Implement one shared `NavigationBar` Compact shell**

Replace `_CompactShell` with a direct three-destination bar:

```dart
NavigationBar(
  key: const ValueKey<String>('compact-navigation-bar'),
  selectedIndex: switch (currentDestination) {
    AppDestination.sources => 0,
    AppDestination.jobs => 1,
    AppDestination.settings => 2,
    null => 0,
  },
  onDestinationSelected: (index) {
    switch (index) {
      case 0:
        onSourcesSelected();
      case 1:
        onJobsSelected();
      case 2:
        onSettingsSelected();
    }
  },
  destinations: <NavigationDestination>[
    const NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Sources',
    ),
    jobsNavigationDestination(activeSummary),
    const NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ],
)
```

Pass `currentDestination`, `onSourcesSelected`, and `onSettingsSelected` into `_CompactShell`. Remove `_JobsIndicator`, `_showMore`, and the More bottom sheet.

The Jobs destination helper retains the active-count `Badge`; navigation semantics still come from the semantic destination label.

- [ ] **Step 3: Run Compact + full shell tests GREEN**

Run:

```bash
cd flutter
fvm flutter test test/app/shell/application_shell_test.dart --no-pub
```

No `Platform.isAndroid` branch is permitted in shell/navigation code.

---

### Task 8: Add the P02-001 Android native milestone harness

**Files:** new integration tests, shell harness, `justfile`.

- [ ] **Step 1: Add a denied-permission integration test**

`phase_002_android_permission_gate_test.dart` must pump the real `ArgusBootstrap` and prove, on a clean app-data state with All files access denied:

```text
Storage access required is shown
Settings/normal app shell is not shown
host snapshot reports All files access false
the host-standard argus.sqlite3 file does not exist, proving Rust startup did not run before the gate
```

The test may use `dart:io` because integration-test code is not production authority.

- [ ] **Step 2: Add a granted-readiness real-stack integration test**

`phase_002_android_bootstrap_test.dart` must run with All files access granted (and notification pre-granted on API 33+ by the harness) and prove:

```text
real ArgusBootstrap reaches Settings through the production platform gate
real FRB library loads from the packaged Android .so
real Rust runtime reaches Ready
real SQLite database exists in the host-standard app-private directory
appearance read/write round-trip works through the real Settings UI/API
Compact Sources / Jobs / Settings navigation is present at phone width
exactly one active root ArgusClient/runtime generation is observed during the run
```

Do not add a fake gateway to this native test.

- [ ] **Step 3: Create the repository-owned local Android harness**

Create `scripts/run_phase_002_android_bootstrap_tests.sh` that:

```text
requires adb + pinned FVM Flutter
accepts ARGUS_ANDROID_DEVICE_ID or requires exactly one connected emulator
verifies API >= 30
verifies x86_64 for the Slice-001 emulator milestone
builds the Android debug APK through repository build plumbing
installs/updates the development package
clears app data before each scenario
uses `adb shell appops set --uid dev.argusromtoolkit.argus MANAGE_EXTERNAL_STORAGE deny|allow`
pre-grants POST_NOTIFICATIONS on API 33+ for the successful-startup scenario
runs denied-permission integration test
runs granted/readiness/bootstrap integration test
fails on any command/test failure
```

The package id constant is explicitly the scaffold/test identity and may be changed by P02-007 before release.

- [ ] **Step 4: Add a `just` target, not a `just check` dependency**

Add:

```make
test-phase-002-android-bootstrap:
    bash scripts/run_phase_002_android_bootstrap_tests.sh
```

Do not modify `.github/workflows/ci.yml` in Slice 001. P02-007 owns the permanent emulator CI topology.

- [ ] **Step 5: Run the native milestone GREEN when an emulator is available**

Run:

```bash
just test-phase-002-android-bootstrap
```

If the environment cannot provide an Android emulator/NDK, record the native gate as `NOT RUN` with the exact missing prerequisite; do not substitute widget/unit tests and claim native success.

---

### Task 9: Generated-output, regression, and slice-completion hardening

**Files:** generated FRB/Riverpod outputs produced by `just generate`, `flutter/test/architecture/architecture_boundaries_test.dart`, `justfile` only if generated-output registration requires it, and the implementation/delegation completion evidence owned by the execution workflow. Do not create the final Phase 002 verification record here; P02-007 owns final phase evidence.

- [ ] **Step 1: Regenerate all managed output**

Run:

```bash
just generate
just check-generated
```

Register every new Riverpod-generated production file in the repository's exact generated-output checks. Do not manually patch generated FRB or Riverpod output.

- [ ] **Step 2: Run focused Rust and Flutter suites**

Run:

```bash
bash scripts/run_rust.sh cargo test --manifest-path rust/Cargo.toml --workspace --locked
cd flutter
fvm flutter test test/app/platform test/app/bootstrap test/app/shell test/features/startup test/architecture --no-pub
```

- [ ] **Step 3: Run the full platform-neutral quality gate**

Run:

```bash
just check
```

This must pass without requiring Android SDK, NDK, `adb`, or an emulator.

- [ ] **Step 4: Run existing native desktop regressions on macOS**

On macOS run:

```bash
just test-phase-000-native
just test-phase-001-native
```

On a non-macOS implementation host, record both as `NOT RUN (macOS host required)` rather than substituting another platform. Android changes must not regress the existing native desktop milestones.

- [ ] **Step 5: Run/record the Android Slice-001 native gate**

Run:

```bash
just test-phase-002-android-bootstrap
```

Record actual status truthfully. Do not mark Slice 001 complete if a known implementation defect prevents this gate; environment-only absence may be recorded as `NOT RUN` for local implementation review but must be executed before Phase 002's final native evidence.

- [ ] **Step 6: Verify slice exclusions mechanically**

Review the diff and confirm there is no production implementation of:

```text
Android storage volume/root browser
SAF tree selection
Android root admission/scanning
foreground service
WorkManager
job notification projection
Play signing/distribution
API 29 compatibility
32-bit Android ABI
```

Also confirm the Android Sources folder-picker composition is inert rather than accidentally invoking `file_selector`.

- [ ] **Step 7: Produce completion evidence**

The implementation completion report must state:

```text
platform-neutral checks: PASS/FAIL
Android arm64 bridge build: PASS/FAIL/NOT RUN
Android x86_64 bridge build: PASS/FAIL/NOT RUN
Android debug APK build: PASS/FAIL/NOT RUN
P02-001 emulator native milestone: PASS/FAIL/NOT RUN
Phase 000 native regression: PASS/FAIL/NOT RUN
Phase 001 native regression: PASS/FAIL/NOT RUN
known deferred Phase 002 capabilities: P02-002 through P02-007, including Android-adapted diagnostics export
```

Do not describe Phase 002 as complete. Successful execution completes only `SLICE-P02-001`.
