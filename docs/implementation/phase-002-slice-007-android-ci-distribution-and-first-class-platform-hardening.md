# Phase 002 Slice 007 implementation record

This slice made Android a hardened, ARM64-only, directly distributable first-class
platform: permanent package identity, deterministic ABI/package guardrails,
external-only release signing, hosted CI package verification, and one final
repository-owned API 36 ARM64 native milestone.

## Implemented behavior

- The live Android identity is `com.argusromtoolkit.argus` everywhere: Gradle
  namespace/application ID, Kotlin package tree, foreground-service action
  constants, ADB/harness package references, integration/unit test fixtures,
  and Rust runtime test fixtures. The old `dev.argusromtoolkit.argus` identity
  has no migration path and is absent from live paths; desktop macOS container
  identity and the macOS product build contract are untouched by this Android
  slice; current macOS architecture and deployment settings are defined by
  BUILD-MACOS-ARM64-DEPLOYMENT-TARGET.
- Android builds are ARM64-only (`aarch64-linux-android`,
  `--target-platform android-arm64`, `arm64-v8a` packaging). The shared native
  harness requires API 36 + `arm64-v8a` unconditionally; the bootstrap and
  notification-cancel harnesses no longer carry x86_64/dual-ABI paths.
- `scripts/check_android_package.sh` verifies an APK contains
  `lib/arm64-v8a/libargus_bridge.so`, rejects every other `lib/<abi>/` entry,
  and (when SDK metadata tooling is available) verifies package ID and minSdk
  30. Its `--source-contract-only` mode rejects Android x86/ARM-v7/x86_64
  tokens across live build/config/harness/CI paths without matching desktop
  x86_64.
- Release signing is external and mandatory: `build.gradle.kts` reads
  `ARGUS_RELEASE_KEYSTORE`, `ARGUS_RELEASE_STORE_PASSWORD`,
  `ARGUS_RELEASE_KEY_ALIAS`, and `ARGUS_RELEASE_KEY_PASSWORD`; release tasks
  fail explicitly on missing configuration and never fall back to debug
  signing. `scripts/build_android_release.sh` validates inputs, builds
  android-arm64, and runs strict package/signature verification without
  printing signing values. No signing material exists in the repository.
- GitHub CI gained one hosted Android job ("Android ARM64 build and package
  verification") that runs the source contract, builds the ARM64 debug APK,
  and verifies the package. It does not run or claim emulator/native
  qualification, and it derives the NDK version from the pinned
  `flutter.ndkVersion` (28.2.13676358 for Flutter 3.44.7) rather than an
  independent Argus NDK contract.
- `scripts/run_phase_002_android_final_tests.sh` (`just
  test-phase-002-android-final`) composes the existing P02-001 through P02-006
  scenario scripts, requires API 36 + `arm64-v8a`, records one result line per
  scenario with device/API/ABI facts, and fails on any failed or not-run
  scenario. Hardware-dependent cases are classified only through bounded
  rules.

## Approved scope amendments

- Amendment 1 authorized the live paths required by the identity/ABI cleanup:
  the Android permission-gate integration test, `scripts/bootstrap.sh`, the
  notification-cancel harness, Flutter unit-test fixtures, `frb_mapper_test.dart`,
  and the Rust runtime unit-test fixtures.
- Amendment 2 authorized correcting stale `sources-scan-all` expectations in
  the P02-002/P02-003 integration tests to the committed presentation contract
  (Scan All is available once a configured root exists), plus a bounded
  test-side scroll fix for the verify-phase primary-volume selection. No
  production UI behavior changed.

Both amendments are recorded as child runs under
`.chatgpt/codex-runs/2026-08-21T111602Z-phase-002-slice-007-android-ci-distribution-and-platform-hardening-scope-amendment-{1,2}/`.

## Verification

- `just check` passes: generated-source checks, Rust/Flutter format, clippy,
  Flutter analyze, ShellCheck, dependency architecture checks, all Rust
  workspace tests, and all 518 Flutter tests.
- `just check-android-contract` and `just check-android-package` pass; the
  debug APK reports `com.argusromtoolkit.argus`, minSdk 30, and
  `lib/arm64-v8a/libargus_bridge.so` with no unsupported ABI entries.
- `just build-android-release` with no signing configuration fails before
  compilation, naming the missing fields without echoing values.
- The final API 36 ARM64 milestone passed all ten scenarios on
  `emulator-5554` (API 36, `arm64-v8a`); see
  `build/phase-002-android-final/native-qualification.txt`.
- Phase 000 native regression passed. Phase 001 native regression passed on a
  fresh re-run, including restart seed and restart verification.
- `just build-android-release` produced and verified a signed ARM64 release APK
  for `com.argusromtoolkit.argus`; package/minSdk/ABI checks and `apksigner`
  signature verification passed.
- Physical qualification passed on an AYANEO Pocket Air Mini (Android-reported
  manufacturer `ARBOR`, model `GT78-VN`, API 30, `arm64-v8a`) using the signed
  release build 0.1.0 (versionCode 1). The required readiness, folder-selection,
  Add & Scan, hierarchy, Jobs, force-stop/relaunch persistence, Settings, and
  applicable removable-storage scenarios passed.

## Limitations

The hosted GitHub job has not executed on GitHub in this uncommitted workspace;
its local equivalent commands are green. The adaptive-UX harness still records
predictive-Back and IME as unverified/not applicable for the documented
tooling/product-surface reasons. Physical ARM64 and signed direct-distribution
evidence are now complete; hosted CI execution remains the final external
integration evidence to observe after the changes are committed and pushed.
