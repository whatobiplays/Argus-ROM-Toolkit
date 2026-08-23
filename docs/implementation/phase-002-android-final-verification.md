# Phase 002 final Android verification record

This record separates the four Phase 002 evidence classes and maps them to the
phase exit criteria. Outcomes use only PASS, FAIL, NOT RUN, or NOT APPLICABLE
with concrete evidence; nothing is inferred from host command success alone.

## 1. Repository validation and hosted CI

- `just check` (generated sources, format, lint, architecture, Rust workspace
  tests, 518 Flutter tests): PASS on 2026-08-21.
- `just check-android-contract` and `just check-android-package`: PASS. The
  debug APK has package `com.argusromtoolkit.argus`, minSdk 30, and
  `lib/arm64-v8a/libargus_bridge.so` only.
- Hosted GitHub CI: PASS on 2026-08-22. The "Android ARM64 build and package
  verification" job in `.github/workflows/ci.yml` completed successfully on a
  GitHub-hosted runner. The job performs build/package verification only and
  does not claim emulator/native execution.

## 2. ARM64 API 36 native qualification

Device: `emulator-5554`, Android API 36, ABI `arm64-v8a`, package
`com.argusromtoolkit.argus` (debug APK, version 0.1.0). Run
`just test-phase-002-android-final` completed 2026-08-21T22:50:30Z with:

| Scenario | Result | Evidence |
| --- | --- | --- |
| Bootstrap/readiness | PASS | exit 0 |
| LocalFilesystem/root management | PASS | exit 0 |
| Scan, reconciliation, hierarchy, cancel, retry | PASS | exit 0 |
| Foreground execution/lifecycle | PASS | exit 0 |
| Applicable features | PASS | exit 0 |
| Multi-root/Scan All | PASS | exit 0 |
| Permission reconciliation | PASS | exit 0 |
| Removable volume | PASS | exit 0 (virtual-disk provider remount) |
| Diagnostics publication | PASS | exit 0 |
| Adaptive UX/platform integration | PASS | exit 0; see sub-scenario evidence below |

Full per-scenario evidence: `build/phase-002-android-final/native-qualification.txt`.
Adaptive-UX sub-scenarios (from `build/phase-002-android-adaptive-ux/native-qualification.txt`):
live resize, rotation/Activity recreation, background/foreground,
ordinary Back, permission-overlay return, picker parent
navigation/dismissal, system bars/insets, and single-runtime composition PASS.
Predictive Back is UNVERIFIED (Flutter 3.44.7 exposes no progress API for the
nested local `PopScope` surface and adb cannot assert the native callback);
IME is NOT APPLICABLE (the product exposes no text-input surface).

## 3. Physical ARM64 device qualification

PASS on 2026-08-21 using the signed release APK on an AYANEO Pocket Air Mini.
Android-reported device facts: manufacturer `ARBOR`, model `GT78-VN`, API 30,
ABI `arm64-v8a`; installed Argus package `com.argusromtoolkit.argus`,
versionCode 1, versionName 0.1.0, minSdk 30, targetSdk 36.

The owner physically exercised the required critical path and reported PASS for
readiness/All-files-access onboarding, Argus folder selection, Add & Scan,
hierarchy inspection, Jobs visibility/control, force-stop/relaunch persistence
and recovery, Settings/platform integration, and applicable removable-storage
behavior.

## 4. Signed direct-distribution artifact verification

PASS on 2026-08-21. With external release signing configuration supplied and
`ANDROID_NDK_HOME` pinned to Flutter's NDK 28.2.13676358, `just
build-android-release` produced
`flutter/build/app/outputs/flutter-apk/app-release.apk` (25.7 MB).
`scripts/check_android_package.sh` verified package
`com.argusromtoolkit.argus`, minSdk 30, and ARM64-only bridge packaging; the
release wrapper then verified the APK signature with `apksigner`. Signing
material and signing values remained external to the repository.

## 5. Desktop/native regression evidence

- `just test-local-filesystem-native`: PASS (workspace Rust tests).
- `just test-phase-000-native`: PASS.
- `just test-phase-001-native`: PASS on a fresh re-run, including the milestone,
  restart seed, and restart verification.

## Phase 002 exit-criteria mapping

1. All seven slices complete: P02-001..P02-006 complete; P02-007 implemented
   (this record).
2. Android-applicable Phase 000/001 capabilities implemented or excluded:
   PASS per prior slices and this milestone.
3. ARM64 Android native gate green through the real stack: PASS (API 36
   arm64-v8a, ten scenarios).
4. Desktop regression gates green: PASS, including fresh Phase 000 and Phase
   001 native milestones.
5. Physical ARM64 milestone recorded: PASS on AYANEO Pocket Air Mini (ARBOR
   GT78-VN), API 30, `arm64-v8a`, signed release build 0.1.0 (1).
6. Signed installable APK through the repository-owned release path: PASS;
   package/metadata/ARM64 contents and release signature verified.
7. Architecture/specifications/templates treat Android as first-class and
   enforce applicability: PASS.
8. No known MVP blocker hidden behind undocumented exclusion: PASS. Predictive
   Back remains explicitly UNVERIFIED because the current Flutter/native test
   surfaces cannot assert the nested callback; IME remains NOT APPLICABLE
   because the product exposes no text-input surface.
9. Android 10/Google Play/non-local providers deferred; non-ARM64 Android
   ABIs explicitly unsupported: PASS.

## Blocker summary

No Phase 002 exit-criteria blockers remain. Repository validation, hosted
Android ARM64 build/package CI, ARM64 API 36 native qualification, physical
ARM64 device qualification, signed direct-distribution verification, and
desktop regression evidence are recorded above.
