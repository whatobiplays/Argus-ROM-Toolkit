# Phase 002 Slice 007 Android CI, Distribution, and First-Class Platform Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Phase 002 by making Android ARM64-only in live repository paths, adopting `com.argusromtoolkit.argus`, adding hosted ARM64 build/package CI, defining secure direct-release signing, composing final ARM64 native qualification, and recording truthful final phase evidence.

**Architecture:** Preserve the completed Flutter -> ArgusClient -> FRB -> Rust/application -> SQLite/provider/job architecture unchanged. P02-007 hardens only Android build, package identity, CI, release signing, native qualification orchestration, and final verification. Hosted GitHub CI validates ARM64 build/package integrity without claiming emulator execution; the existing API 36 ARM64 scenario harness remains the real Android native gate.

**Tech Stack:** Flutter 3.44.7, Android Gradle/Kotlin, Rust + cargo-ndk 4.1.2, Bash/Just, GitHub Actions, Android SDK/NDK/adb, APK inspection tooling.

**Spec:** `docs/superpowers/specs/2026-08-21-phase-002-slice-007-android-ci-distribution-and-first-class-platform-hardening-design.md`

## Global Constraints

- Android support is ARM64 (`arm64-v8a`) only for production, emulator, CI build/package verification, and native qualification.
- Permanent Android application ID is `com.argusromtoolkit.argus`.
- Minimum Android version remains Android 11 / API 30.
- Final repository-owned native qualification requires Android API 36 and device ABI `arm64-v8a`.
- Hosted GitHub CI must not claim ARM64 emulator/native execution.
- Production release signing material is external and must never be committed.
- Release builds with missing/incomplete production signing configuration fail clearly and never use debug signing.
- Debug builds remain usable for local development and native qualification.
- `just check` remains deterministic, platform-neutral, and Android-SDK/NDK-independent.
- Preserve existing Windows/Linux/macOS, Phase 000, and Phase 001 verification.
- Preserve Rust/application authority for sources, roots, jobs, admission, reconciliation, persistence, and diagnostics.
- Do not add Android 10/API 29 compatibility, Google Play work, SAF library sources, WorkManager, auto-resume, non-ARM64 Android ABI support, or a second Android runtime/database/scheduler/job authority.
- Do not globally remove desktop/Linux x86_64 support.
- Historical plans, `.chatgpt` runs, RESULT files, and truthful historical execution evidence are immutable historical records and are excluded from live x86_64 cleanup.
- Leave implementation changes uncommitted for owner review unless the owner explicitly authorizes staging/commit later.

---

### Task 1: Lock the permanent Android identity and ARM64-only build contract

**Files:**
- Modify: `flutter/android/app/build.gradle.kts`
- Move package tree: `flutter/android/app/src/main/kotlin/dev/argusromtoolkit/argus/**` -> `flutter/android/app/src/main/kotlin/com/argusromtoolkit/argus/**`
- Modify moved Kotlin files: package declarations only where required by the namespace move
- Modify: `flutter/test/architecture/android_host_contract_test.dart`
- Modify: `scripts/build_android_bridge.sh`
- Modify: `Justfile`

**Interfaces:**
- Consumes: existing Gradle preBuild -> `scripts/build_android_bridge.sh` integration.
- Produces: one permanent package/namespace `com.argusromtoolkit.argus`; one Android Rust target `aarch64-linux-android`; one Flutter target `android-arm64`.

- [ ] **Step 1: Extend the Android host architecture test to fail on the old package identity or live x86_64 Android configuration**

Add assertions equivalent to:

```dart
expect(appBuild, contains('namespace = "com.argusromtoolkit.argus"'));
expect(appBuild, contains('applicationId = "com.argusromtoolkit.argus"'));
expect(appBuild, isNot(contains('dev.argusromtoolkit.argus')));
expect(appBuild, isNot(contains('x86_64')));
expect(appBuild, isNot(contains('android-x64')));

final buildScript = File('../scripts/build_android_bridge.sh').readAsStringSync();
expect(buildScript, contains('aarch64-linux-android'));
expect(buildScript, contains('-t arm64-v8a'));
expect(buildScript, isNot(contains('x86_64-linux-android')));
expect(buildScript, isNot(contains('-t x86_64')));
```

Update `kotlinRoot` expectations to `android/app/src/main/kotlin/com/argusromtoolkit/argus`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
```

Expected: FAIL because the repository still uses `dev.argusromtoolkit.argus`, `android-x64`, and x86_64 Rust packaging.

- [ ] **Step 3: Move the Kotlin package tree and change namespace/application ID atomically**

Move all existing Android Kotlin product files into:

```text
flutter/android/app/src/main/kotlin/com/argusromtoolkit/argus/
```

Change each file's package declaration to:

```kotlin
package com.argusromtoolkit.argus
```

Change Gradle to use `com.argusromtoolkit.argus` for both namespace and application ID while preserving `minSdk = 30` and the current Flutter-managed target/compile cadence.

Do not change relative Android component names in `AndroidManifest.xml`; `.ArgusApplication`, `.MainActivity`, the foreground service, and FileProvider remain relative to the new namespace/application ID.

- [ ] **Step 4: Make the Rust bridge build ARM64-only**

In `scripts/build_android_bridge.sh`, install only `aarch64-linux-android`, build only `-t arm64-v8a`, remove the x86_64 target and output path, and ensure stale unsupported JNI output cannot leak into a subsequent APK.

- [ ] **Step 5: Make Just Android builds ARM64-only**

Change `build-android-debug` to:

```make
build-android-debug:
    cd flutter && fvm flutter build apk --debug --target-platform android-arm64
```

Add `check-android-package` and `check-android-contract` recipes after Task 3 creates the checker.

- [ ] **Step 6: Run focused static and architecture checks**

Run:

```bash
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
shellcheck scripts/build_android_bridge.sh
```

Expected: PASS.

- [ ] **Step 7: Record checkpoint without committing**

Confirm only intended live product/build files changed. Do not stage or commit.

---

### Task 2: Update all live Android harnesses to the permanent package ID and unconditional ARM64 execution

**Files:**
- Modify: `scripts/run_phase_002_android_scenario_common.sh`
- Modify: `scripts/run_phase_002_android_bootstrap_tests.sh`
- Modify: `scripts/run_phase_002_android_local_filesystem_tests.sh`
- Modify: `scripts/run_phase_002_android_scan_tests.sh`
- Modify: `scripts/run_phase_002_android_foreground_execution_tests.sh`
- Modify: `scripts/run_phase_002_android_applicable_features_tests.sh`
- Modify: `scripts/run_phase_002_android_multi_root_tests.sh`
- Modify: `scripts/run_phase_002_android_permission_reconciliation_tests.sh`
- Modify: `scripts/run_phase_002_android_removable_volume_tests.sh`
- Modify: `scripts/run_phase_002_android_diagnostics_tests.sh`
- Modify: `scripts/run_phase_002_android_adaptive_ux_tests.sh`
- Test: `flutter/test/architecture/android_host_contract_test.dart`

**Interfaces:**
- Consumes: Task 1 package identity and ARM64-only build path.
- Produces: all Phase 002 native scenarios require API 36 + `arm64-v8a`, and all ADB/package operations target `com.argusromtoolkit.argus`.

- [ ] **Step 1: Add architecture assertions for live harness identity/ABI behavior**

Extend `android_host_contract_test.dart` to read the shared scenario helper and representative dedicated harnesses. Assert the permanent package ID is used, the shared helper rejects any ABI other than `arm64-v8a`, and the helper no longer contains `ARGUS_ANDROID_DEVICE_REQUIRE_ARM64`, `android-x64`, or x86_64 compatibility logic.

- [ ] **Step 2: Run focused test and verify RED**

Run:

```bash
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
```

Expected: FAIL on old package IDs and P02-006's dual-ABI compatibility branch.

- [ ] **Step 3: Simplify `argus_android_require_device` to one ABI contract**

Keep device selection and API 36 verification. Replace conditional ABI behavior with a single `arm64-v8a` requirement. Export the actual ABI for evidence. Define the shared package ID once as `com.argusromtoolkit.argus` and use it in `argus_android_build_and_install`.

Build only:

```bash
fvm flutter build apk --debug --target-platform android-arm64
```

- [ ] **Step 4: Update every dedicated harness package reference and package assertion**

Change live `PACKAGE_ID` values to `com.argusromtoolkit.argus`. Remove P02-006's dual-ABI acceptance comments/exports. Change foreground package inspection to require `lib/arm64-v8a/libargus_bridge.so` and explicitly reject unsupported ABI directories.

- [ ] **Step 5: Run shell and architecture validation**

Run:

```bash
shellcheck scripts/*.sh
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
```

Expected: PASS.

- [ ] **Step 6: Verify live-source search is clean without rewriting historical records**

Run a bounded search over `Justfile`, `scripts`, `flutter/android`, `flutter/test`, and `.github` for the old package ID plus Android x86_64 target tokens. Expected: no live Android-support matches, except deliberate negative assertions in tests.

- [ ] **Step 7: Record checkpoint without committing**

Do not edit `.chatgpt/**`, historical RESULT files, or old completed plans merely to eliminate historical text.

---

### Task 3: Add deterministic ARM64 package inspection and x86_64 regression guard

**Files:**
- Create: `scripts/check_android_package.sh`
- Modify: `Justfile`
- Modify: `flutter/test/architecture/android_host_contract_test.dart`

**Interfaces:**
- Consumes: APK path as positional argument, or `--source-contract-only` for live-source enforcement.
- Produces: exit 0 only when the live Android contract and produced APK are ARM64-only and structurally valid.

- [ ] **Step 1: Define the package checker interface**

Support:

```text
scripts/check_android_package.sh <apk-path> [expected-package-id]
scripts/check_android_package.sh --source-contract-only
```

Default expected package ID is `com.argusromtoolkit.argus`.

APK inspection must verify:

```text
APK exists and is readable
lib/arm64-v8a/libargus_bridge.so exists
no lib/x86_64/ entries
no lib/armeabi-v7a/ entries
no lib/x86/ entries
```

When Android metadata tooling is available, verify package ID and minSdk 30. Release verification later invokes metadata/signature checks strictly.

- [ ] **Step 2: Prove ABI inspection with synthetic ZIP/APK-shaped fixtures**

Use temporary directories only. Build one good archive with `lib/arm64-v8a/libargus_bridge.so` and one bad archive that also contains `lib/x86_64/libargus_bridge.so`.

Run the checker against both. Expected: good passes ABI inspection; bad exits nonzero with an explicit unsupported-ABI message.

- [ ] **Step 3: Implement one narrowly scoped active-source guard**

Scan only live Android-support paths (`Justfile`, Android build scripts, Phase 002 Android scripts, `flutter/android/**`, `.github/workflows/**`). Reject active tokens that re-enable Android x86_64 such as `android-x64`, `x86_64-linux-android`, `-t x86_64`, or a packaged `lib/x86_64/` path. Exclude historical plans, `.chatgpt`, RESULT files, and deliberate negative-test assertions.

- [ ] **Step 4: Add Just recipes**

Add:

```make
check-android-contract:
    bash scripts/check_android_package.sh --source-contract-only

check-android-package:
    bash scripts/check_android_package.sh flutter/build/app/outputs/flutter-apk/app-debug.apk
```

Do not add either command as an Android-tooling dependency of `just check`.

- [ ] **Step 5: Run checks**

Run:

```bash
just check-android-contract
shellcheck scripts/check_android_package.sh
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
```

Expected: PASS.

- [ ] **Step 6: Record checkpoint without committing**

Confirm the guard is Android-specific and cannot reject ordinary desktop x86_64 support.

---

### Task 4: Define secure direct-release signing and one ARM64 release path

**Files:**
- Modify: `flutter/android/app/build.gradle.kts`
- Create: `scripts/build_android_release.sh`
- Modify: `Justfile`
- Modify: `flutter/test/architecture/android_host_contract_test.dart`
- Modify ignore rules only if necessary to keep local signing material/output outside source control

**Interfaces:**
- Consumes: four externally supplied signing inputs defined by repository documentation/configuration: keystore location, keystore unlock value, key alias, and key unlock value.
- Produces: signed ARM64 release APK at Flutter's standard release APK output path; fails before build when required signing configuration is incomplete.

- [ ] **Step 1: Add failing architecture assertions for release-signing safety**

Assert `build.gradle.kts` no longer binds the release build to the debug signing configuration. Assert the release path reads only externally supplied signing configuration and `scripts/build_android_release.sh` builds only `android-arm64`.

- [ ] **Step 2: Run focused test and verify RED**

Run:

```bash
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
```

Expected: FAIL because release currently falls back to debug signing.

- [ ] **Step 3: Implement Gradle external signing configuration**

Define one release signing config from external process/environment values. When any required value is absent during a release task, throw a `GradleException` that names the missing configuration fields without echoing their values. Debug tasks must not require release signing configuration.

Bind `buildTypes.release.signingConfig` only to this release signing config. Never fall back to debug signing.

- [ ] **Step 4: Add repository-owned release wrapper**

`scripts/build_android_release.sh` must validate that all required external signing inputs are present and the keystore path exists, invoke:

```bash
cd "$ROOT_DIR/flutter"
fvm flutter build apk --release --target-platform android-arm64
```

then run strict package inspection and Android signature verification on `flutter/build/app/outputs/flutter-apk/app-release.apk` without printing signing values.

- [ ] **Step 5: Add Just recipe**

Add:

```make
build-android-release:
    bash scripts/build_android_release.sh
```

Keep `build-android-debug` credential-free.

- [ ] **Step 6: Verify missing signing configuration fails safely**

Run the release wrapper without signing inputs. Expected: nonzero exit before Gradle compilation, with explicit missing-field names and no signing values printed.

- [ ] **Step 7: Run architecture/lint checks**

Run:

```bash
shellcheck scripts/build_android_release.sh
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
```

Expected: PASS.

- [ ] **Step 8: Record checkpoint without committing**

Do not create or commit real production signing material as part of implementation.

---

### Task 5: Add GitHub-hosted Android ARM64 build/package CI without false native claims

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `flutter/test/architecture/android_host_contract_test.dart`

**Interfaces:**
- Consumes: ARM64-only debug build and package/contract checks.
- Produces: hosted CI evidence that the supported Android artifact builds and packages correctly; no emulator execution claim.

- [ ] **Step 1: Add a failing CI-topology architecture assertion**

Extend `android_host_contract_test.dart` to require a dedicated Android build/package job that invokes `build-android-debug`, `check-android-contract`, and `check-android-package`, while rejecting emulator actions, `avdmanager`, or `test-phase-002-android-final` from that hosted job.

- [ ] **Step 2: Run focused test and verify RED**

Run:

```bash
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
```

Expected: FAIL because no Android hosted package job exists.

- [ ] **Step 3: Add the hosted Android package job**

Use GitHub-hosted Linux for Android ARM64 cross-build/package work only. Install the pinned Flutter/FVM/Rust/Android prerequisites, bootstrap the repository as needed, then run:

```text
just check-android-contract
just build-android-debug
just check-android-package
```

Name the job so it describes build/package verification, not emulator/native qualification.

- [ ] **Step 4: Keep production signing out of ordinary push/PR CI**

Normal CI must not require release signing configuration. Signed release generation remains an explicit release operation using the same ARM64 build topology.

- [ ] **Step 5: Run local CI contract checks**

Run:

```bash
cd flutter && fvm flutter test test/architecture/android_host_contract_test.dart
just check-android-contract
```

Expected: PASS.

- [ ] **Step 6: Record checkpoint without committing**

Ensure existing quality, native-desktop, provider, and Phase 001 jobs remain present.

---

### Task 6: Compose the final Phase 002 ARM64 native milestone from existing scenarios

**Files:**
- Create: `scripts/run_phase_002_android_final_tests.sh`
- Modify: `Justfile`
- Modify existing scenario scripts only if needed to expose structured status without duplicating scenario logic
- Create: `docs/implementation/phase-002-slice-007-android-ci-distribution-and-first-class-platform-hardening.md`

**Interfaces:**
- Consumes: existing P02-001 through P02-006 scenario scripts and shared API 36/ARM64 helper.
- Produces: `just test-phase-002-android-final` plus final native evidence that records device facts and per-scenario result.

- [ ] **Step 1: Define the final runner's bounded scenario list**

Invoke the existing scripts for bootstrap/readiness, LocalFilesystem, scan/hierarchy, foreground execution, applicable features, multi-root, permission reconciliation, removable volume, diagnostics, and adaptive UX. Do not reimplement their internal interactions in the final runner.

- [ ] **Step 2: Implement environment preflight once**

Source `run_phase_002_android_scenario_common.sh`, require API 36 + `arm64-v8a`, and record device ID, API, ABI, and UTC start time.

- [ ] **Step 3: Implement per-scenario execution recording**

For each existing script record a structured result line such as:

```text
scenario=foreground_execution|result=passed|exit_code=0
```

A required scenario returning nonzero makes the final runner fail. Hardware/tooling-dependent cases may be classified `not_applicable` or `not_run` only through explicit bounded rules; do not convert existing predictive-back/IME limitations into a pass.

- [ ] **Step 4: Add the Just command**

Add:

```make
test-phase-002-android-final:
    bash scripts/run_phase_002_android_final_tests.sh
```

- [ ] **Step 5: Shell-validate orchestration before device execution**

Run:

```bash
bash -n scripts/run_phase_002_android_final_tests.sh
shellcheck scripts/run_phase_002_android_final_tests.sh
```

Expected: PASS.

- [ ] **Step 6: Run on the configured API 36 ARM64 emulator**

Run with `ARGUS_ANDROID_DEVICE_ID` and `ANDROID_NDK_HOME` set to the configured ARM64/API-36 environment:

```bash
just test-phase-002-android-final
```

Expected: all required automated Phase 002 scenarios pass; unsupported hardware-dependent cases are explicitly classified.

- [ ] **Step 7: Write P02-007 implementation evidence**

Record exact command, device ID, API, ABI, scenario outcomes, package-contract status, and any explicitly unverified/not-applicable native cases. Do not claim physical-device or signed-release evidence from emulator execution.

- [ ] **Step 8: Record checkpoint without committing**

Leave the implementation record alongside the uncommitted implementation for owner review.

---

### Task 7: Add final physical-device and signed-release evidence contracts

**Files:**
- Create: `docs/implementation/phase-002-android-final-verification.md`
- Modify: `docs/implementation/README.md` if required by the index
- Modify: `docs/phases/phase-002-android-first-class-platform-support.md` only after actual completion evidence justifies a status/evidence update

**Interfaces:**
- Consumes: hosted CI result, final ARM64 native result, signed release artifact verification, and physical ARM64 run.
- Produces: one final Phase 002 verification record that separates those evidence classes.

- [ ] **Step 1: Define the final verification record structure**

Use explicit sections for hosted CI/repository validation, ARM64 API 36 native qualification, physical ARM64 device qualification, signed direct-distribution APK verification, known unverified/not-applicable cases, and Phase 002 exit-criteria mapping.

Each scenario uses `PASS`, `FAIL`, `NOT RUN`, or `NOT APPLICABLE` plus concrete evidence/reason.

- [ ] **Step 2: Record repository and emulator evidence only after commands actually run**

Required evidence includes `just check`, ARM64 package checks, Phase 000/001 native regressions, and `just test-phase-002-android-final`. Hosted GitHub CI is build/package evidence only.

- [ ] **Step 3: Record physical ARM64 evidence only from a real device**

Record device model, API level >= 30, reported ABI `arm64-v8a`, package ID, version/build identity, readiness/startup, folder selection, Add & Scan, hierarchy inspection, Jobs visibility/control, restart persistence/recovery, Settings/platform integration, and removable-storage result when applicable.

If the physical run has not happened during implementation, record `NOT RUN`; do not fabricate evidence. Phase completion remains blocked until the required physical evidence exists.

- [ ] **Step 4: Record signed-release evidence only when external signing configuration is intentionally supplied**

When authorized signing configuration is available, run `just build-android-release` and record package ID, signature verification, minSdk/version metadata, ARM64 bridge presence, and absence of unsupported ABIs. Otherwise record the real signed artifact as `NOT RUN`; debug signing is not substitute evidence.

- [ ] **Step 5: Map every Phase 002 exit criterion to evidence**

Explicitly map all current Phase 002 exit criteria to the four evidence classes and identify any remaining blocker.

- [ ] **Step 6: Record checkpoint without committing**

The phase document may be marked complete only after required physical and signed-release evidence actually exists.

---

### Task 8: Final regression, exclusion, and scope verification

**Files:**
- Review all changed files from Tasks 1-7
- No new production files unless verification exposes a real P02-007 defect

**Interfaces:**
- Consumes: entire P02-007 implementation.
- Produces: owner-reviewable uncommitted implementation with truthful qualification status.

- [ ] **Step 1: Run deterministic repository gates**

Run:

```bash
just generate
just check-generated
just format
just check
just check-android-contract
```

Expected: PASS.

- [ ] **Step 2: Run Android ARM64 package build and inspection**

With the configured NDK:

```bash
just build-android-debug
just check-android-package
```

Expected: APK contains `lib/arm64-v8a/libargus_bridge.so`, no unsupported ABI libraries, and package metadata identifies `com.argusromtoolkit.argus`.

- [ ] **Step 3: Run desktop/native regression gates**

Run where host prerequisites exist:

```bash
just test-local-filesystem-native
just test-phase-000-native
just test-phase-001-native
```

Expected: PASS.

- [ ] **Step 4: Run final ARM64 Android native milestone**

With the configured API 36 ARM64 emulator/device:

```bash
just test-phase-002-android-final
```

Expected: required scenarios pass with explicit evidence; unsupported hardware-only cases are classified truthfully.

- [ ] **Step 5: Perform bounded live x86_64 exclusion search**

Search only live Android build/config/test paths for `android-x64`, `x86_64-linux-android`, `-t x86_64`, and packaged `lib/x86_64/` support. Exclude deliberate negative-test strings and historical evidence.

- [ ] **Step 6: Perform release-signing safety review**

Confirm release configuration contains no committed signing material and no debug-signing fallback.

- [ ] **Step 7: Review final diff against scope**

Confirm no Android 10, Google Play, SAF source engine, WorkManager, auto-resume, new application authority, or desktop x86_64 regression entered the diff.

- [ ] **Step 8: Leave the worktree uncommitted for owner review**

Do not stage, commit, or push. Report exact PASS/FAIL/NOT RUN/NOT APPLICABLE status for hosted-CI-local equivalents, ARM64 emulator qualification, physical-device qualification, and signed-release verification.
