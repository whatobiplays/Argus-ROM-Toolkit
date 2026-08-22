# P02-007 Android CI, Distribution, and First-Class Platform Hardening Design

**Date:** 2026-08-21
**Status:** Approved design; pending owner review of written specification

## 1. Purpose

SLICE-P02-007 closes Phase 002 by hardening Android CI and direct distribution around the Android product implemented in P02-001 through P02-006. It does not add a second Android architecture or new product authority. It makes the supported Android contract mechanically true: Android is ARM64-only, the permanent application identity is `com.argusromtoolkit.argus`, hosted CI validates the artifact that Argus actually ships, repository-owned ARM64 native qualification exercises the real Android runtime, and final physical-device evidence closes the phase.

This slice also removes live x86_64 Android support that was introduced earlier for emulator convenience. Historical plans, Codex runs, RESULT files, and execution evidence remain historical records and must not be rewritten merely because the supported product contract changed.

## 2. Decisions

1. Android support is ARM64 (`arm64-v8a`) only for production, emulator, CI build/package verification, and native qualification.
2. GitHub-hosted CI does not claim ARM64 emulator execution. Current hosted ARM64 Linux runners do not provide the KVM/nested-virtualization environment needed for a reliable full Argus Android emulator milestone.
3. Hosted CI builds and inspects the ARM64 Android artifact. The repository-owned API 36 ARM64 native harness remains the real emulator/native qualification path and is structured so it can move to a suitable self-hosted or future hosted ARM64 runner without creating another test path.
4. A physical ARM64 Android phone or retro handheld remains required Phase 002 completion evidence.
5. The permanent Android application ID is `com.argusromtoolkit.argus`. The existing `dev.argusromtoolkit.argus` identity was explicitly temporary, so no migration or upgrade compatibility between those package identities is required.
6. Direct distribution uses one repository-owned release path with externally supplied signing credentials. Production signing material is never committed.
7. A release build with missing production signing material fails clearly and never falls back to the debug signing key.
8. Debug builds may continue using normal developer/debug signing.

## 3. Architecture

P02-007 wraps the completed shared product/runtime rather than changing it:

```text
shared Flutter -> ArgusClient -> FRB -> Rust/application -> SQLite/providers/jobs
                              |
                              v
                    Android ARM64 build
                       /             \
                      /               \
        debug/native qualification   signed direct-distribution APK
                  |                         |
                  v                         v
       API 36 ARM64 harness        repository artifact checks
```

Rust/application remains authoritative for sources, roots, jobs, admission, reconciliation, persistence, and diagnostics. Flutter and Android remain presentation and platform-integration layers. P02-007 introduces no Android-specific database, scheduler, job model, durable product state, or competing runtime authority.

## 4. Hosted CI

GitHub-hosted CI validates the supported ARM64 product without pretending that hosted infrastructure provides a suitable ARM64 emulator runtime.

The Android CI job must:

- build Android for `android-arm64` only;
- use the repository-owned Rust/FRB Android bridge build path;
- verify `lib/arm64-v8a/libargus_bridge.so` is present in the produced APK;
- fail if `lib/x86_64/` or any other unsupported Android ABI library is present;
- verify the expected permanent package identity and relevant Android build metadata;
- keep `just check` platform-neutral and independent of Android SDK/NDK prerequisites;
- preserve existing Windows, Linux, macOS, Phase 000, and Phase 001 verification rather than reducing desktop coverage to fund Android CI.

Hosted CI records build/package verification only. It must not label that result as Android emulator/native qualification.

## 5. ARM64 Native Qualification

P02-007 adds one final repository-owned Phase 002 Android milestone command that composes the existing scenario harnesses rather than duplicating their logic.

The final native milestone requires:

- Android API 36;
- device ABI exactly `arm64-v8a`;
- the production Flutter -> ArgusClient -> FRB -> Rust -> SQLite -> Android platform path;
- the same ARM64 build topology used by the supported product.

The milestone covers the applicable completed Phase 002 capabilities: readiness/startup, LocalFilesystem/root selection, scanning and hierarchy, foreground job lifecycle behavior, multi-root and applicable-feature coverage, permission reconciliation, removable-volume behavior where the environment supports it, diagnostics, and P02-006 adaptive Android UX/platform integration.

Environment- or hardware-dependent scenarios must report an explicit result such as NOT APPLICABLE or NOT RUN with a reason. They must not be converted into success merely because the environment cannot exercise them. Command exit status alone is insufficient final evidence; the final record captures scenario outcomes and relevant environment facts.

The command must be suitable for execution on Apple Silicon today and on a future suitable self-hosted or hosted ARM64 runner without creating a separate CI-only implementation.

## 6. Permanent Android Identity

P02-007 replaces the temporary Android package identity with:

`com.argusromtoolkit.argus`

The change is atomic across the live Android product and qualification surface. Android application configuration, manifests or generated package configuration where applicable, Kotlin package assumptions, ADB/native harness package references, integration tests, package assertions, and current implementation documentation must agree on the permanent identity.

No compatibility path from `dev.argusromtoolkit.argus` is required because that identity was an explicitly temporary development scaffold rather than a released product identity.

## 7. Direct Distribution and Signing

The repository owns one release-build topology. CI validation and actual direct distribution must not diverge into unrelated build implementations.

Production release signing is supplied externally through environment variables or CI/release secrets. The repository may define variable names, expected keystore location/input mechanics, Gradle signing configuration, validation, and documentation, but it must not contain a production keystore, passwords, encoded secrets, private keys, or other signing material.

Release behavior must satisfy these invariants:

- a signed ARM64 APK can be produced for `com.argusromtoolkit.argus` when valid signing material is supplied;
- missing or incomplete production signing configuration fails explicitly;
- release builds never silently use debug signing;
- debug builds remain usable for local development and native qualification;
- signing affects packaging only and cannot become runtime or application authority.

The signed direct-distribution artifact is verified for package identity, release signature presence, ARM64 bridge presence, absence of unsupported ABI libraries, minimum SDK 30, and expected version metadata.

Generated signed binaries are not committed unless a separate repository policy explicitly requires them.

## 8. Removal of Live x86_64 Android Support

P02-007 removes x86_64 Android support from current executable and configuration paths. This includes, as applicable:

- Rust Android target installation/build lists;
- `cargo-ndk` target lists;
- Flutter `--target-platform` arguments;
- JNI output management;
- shared Android scenario ABI acceptance;
- Android native milestone and package assertions;
- current build/release/CI configuration;
- current implementation documentation that still describes dual-ABI behavior as a live requirement.

The shared Android scenario tooling requires `arm64-v8a` unconditionally after this cleanup. Compatibility branches that accepted x86_64 solely because earlier slices packaged it are removed.

A deterministic repository guard prevents future changes from silently restoring Android x86_64 support. The guard covers live Android build/configuration/test surfaces and artifact contents. It must be scoped narrowly enough that legitimate desktop/Linux x86_64 support is unaffected.

Historical plans, `.chatgpt` Codex runs, RESULT files, completed execution evidence, and other historical records that truthfully describe earlier dual-ABI work are excluded from this cleanup and guard. They remain accurate records of what happened at that time.

## 9. Physical ARM64 Evidence

Phase 002 completion requires a critical-path run on at least one physical ARM64 Android phone or retro-emulation handheld running Android API 30 or newer.

Required physical-device coverage includes:

- readiness/startup;
- Argus folder selection;
- Add & Scan;
- hierarchy inspection;
- Jobs visibility and applicable control;
- restart persistence/recovery;
- Settings and platform integration.

Removable-storage behavior is required when the selected physical device/environment exposes applicable removable storage. Lack of such hardware is recorded as not applicable rather than fabricated coverage.

The evidence records at minimum device model, Android API level, reported ABI, Argus app version/build identity, and exact scenario outcomes.

## 10. Final Phase 002 Evidence

P02-007 owns the final Phase 002 verification record. It clearly separates four evidence classes:

1. hosted CI and deterministic repository validation;
2. ARM64 API 36 emulator/native qualification;
3. physical ARM64 device qualification;
4. signed direct-distribution artifact verification.

Phase 002 is complete only when every required gate passes. Environmental limitations remain explicit NOT RUN/NOT APPLICABLE evidence and cannot be rewritten as success.

`just check` remains the canonical platform-neutral gate. Existing Phase 000/001 native regressions remain required and Android support must not reduce their coverage.

## 11. Scope Boundaries

P02-007 does not add:

- Android 10/API 29 compatibility;
- Google Play distribution, Play policy work, or Play-specific compromises;
- non-ARM64 Android ABI support;
- SAF/content-provider library sources;
- WorkManager or automatic significant-work resumption;
- new product functionality solely to simplify qualification;
- a second Android-specific runtime, database, scheduler, event authority, or job model;
- migration compatibility from the temporary development package identity.

Desktop x86_64 support is explicitly unaffected.

## 12. Acceptance Summary

P02-007 is complete when:

1. all live Android build and qualification paths are ARM64-only and a scoped guard prevents unsupported Android ABI regression;
2. the permanent Android package identity is `com.argusromtoolkit.argus` everywhere in the live product/qualification surface;
3. GitHub-hosted CI builds and inspects the ARM64 Android artifact without claiming unavailable hosted ARM64 emulator coverage;
4. production release signing is external, required for release, and cannot silently fall back to debug signing;
5. a signed ARM64 direct-distribution APK can be produced and its identity, signature, SDK/version metadata, ARM64 bridge, and absence of unsupported ABI libraries are verified;
6. one repository-owned API 36 ARM64 final native milestone composes the existing Phase 002 scenarios and reports truthful per-scenario evidence;
7. the required physical ARM64 critical-path evidence is recorded;
8. `just check`, applicable desktop/native regressions, Android package verification, ARM64 native qualification, and release verification are green as required;
9. historical dual-ABI records remain historically accurate rather than being rewritten;
10. the final Phase 002 record distinguishes hosted CI, native ARM64, physical-device, and signed-artifact evidence and contains no false-success claims.
