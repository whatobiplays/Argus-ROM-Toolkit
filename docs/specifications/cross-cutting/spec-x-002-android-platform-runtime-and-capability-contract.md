# Android Platform Runtime and Capability Contract

**Document ID:** SPEC-X-002  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-15  
**Depends On:** ARCH-001, ARCH-002, PHASE-002, SPEC-X-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the Android-wide contract that spans Flutter composition, native Android hosting, Flutter Rust Bridge, Rust runtime ownership, persistence location, platform readiness, long-running execution hosting, distribution, verification, and future platform applicability.

Detailed source-provider behavior remains owned by `SPEC-BE-011`/`SPEC-BE-013`; detailed routing/startup/Jobs presentation remains owned by the focused frontend specifications. This document prevents Android-wide mechanics from leaking independently into those subsystems.

## 2. Supported Baseline

Phase 002 Android MVP uses:

- minimum Android version: Android 11 / API 30;
- production ABI: ARM64 (`arm64-v8a`);
- emulator/test ABI: x86_64;
- no orientation lock;
- direct distribution first;
- a signed installable APK required by phase completion;
- compile/target SDK aligned with the repository's pinned Flutter toolchain unless a required platform capability forces an explicit override.

Android 10/API 29, 32-bit ABIs, Google Play submission/policy work, and arbitrary document-provider execution are post-MVP.

## 3. Platform Applicability Model

Every substantive capability introduced from Phase 002 onward must be classified as exactly one of:

- **Shared** — equivalent product capability is meaningful on desktop and Android and should normally share application/domain contracts.
- **Platform-adapted** — the user outcome is shared but native mechanics or UX differ.
- **Platform-specific** — meaningful only on one platform family; no artificial counterpart is required elsewhere.
- **Excluded** — intentionally unsupported on a platform, with rationale in the owning specification.

A phase is not complete until every Android-applicable capability is implemented and verified. Individual slices may sequence desktop and Android work independently when clean engineering boundaries require it.

## 4. Mandatory All Files Access

On API 30+, Android All files access is a hard Argus platform readiness prerequisite for the direct-distribution MVP.

Requirements:

1. onboarding explains why broad local-storage access is required;
2. Argus launches the app-specific Android settings surface for the special access;
3. the actual OS state is re-read on return/resume;
4. normal Argus backend startup is not admitted until the OS reports the requirement satisfied;
5. no persisted boolean may bypass the live OS state;
6. revocation after startup hides normal storage-dependent product surfaces behind platform readiness and prevents new storage jobs from being admitted;
7. revocation does not delete or rewrite SQLite state, configured roots, indexed entries, settings, or Jobs history;
8. regrant triggers authoritative provider/root availability reconciliation rather than creating new roots.

Platform readiness is an outer host prerequisite. It is not an additional Rust `StartupPhase` and is not represented as a backend startup failure.

## 5. Notification Authorization

On Android versions requiring notification runtime authorization, Argus requests notification permission during onboarding after mandatory storage readiness.

Notification permission is optional:

- denial does not block Argus startup;
- denial does not change authoritative Jobs state;
- denial does not weaken qualifying foreground-service execution into foreground-only Activity execution;
- it degrades notification-drawer projection/actions only;
- Settings may expose a recovery action where appropriate.

A persisted native fact may record only that the optional prompt reached a terminal user response. It is onboarding UX state, not product or runtime authority.

## 6. Single Runtime Ownership

One Android process owns exactly one normal Argus application composition:

```text
Android Application
└── cached FlutterEngine / normal Dart isolate
    └── root ProviderScope
        └── ArgusClient / focused APIs
            └── Flutter Rust Bridge
                └── one Rust ApplicationRuntime
                    └── one SQLite authority
```

The `FlutterActivity` attaches to/detaches from the application-owned engine. Rotation, Activity recreation, resizing, split screen, fold/unfold, temporary backgrounding, and screen-off do not imply `generalShutdown` or runtime replacement.

The Android foreground service must not initialize a second Dart/Rust backend, open an independent SQLite authority, create a parallel scheduler, or establish a competing runtime event stream.

Actual process death remains runtime loss and is handled by the existing durable restart-recovery contract.

## 7. Android Application Data Directory

The Android host supplies an app-private standard application-data directory to Rust before startup.

This directory is distinct from the explicit data-directory override used by tests/embedding:

- host-supplied Android app data is classified as normal `StandardApplicationData`;
- explicit override remains `ExplicitOverride`;
- Android production startup must not derive its database location from Unix `HOME`/`XDG_*` environment assumptions;
- the app-private path is not a user-facing Android file-management capability and must not leak into safe diagnostics context.

The runtime configuration is latched for the process lifetime once the root client is created. Later permission revocation must not invalidate the client factory or replace the running runtime solely because readiness regressed.

## 8. Android `LocalFilesystem` Boundary

Android local library storage remains `SourceProviderType::LocalFilesystem`; no persisted Android-only source type is introduced.

Phase 002 `LocalFilesystem` means actual locally mounted storage accessible under the mandatory platform authorization, including primary shared storage and mounted removable storage where Android exposes usable local filesystem semantics.

Platform/native code owns Android OS facts such as mounted-volume discovery and permission state. Rust provider infrastructure owns canonical root locators, root relationships, root availability, relative locators, bounded traversal, stat/open semantics, native identity policy, provider errors, and boundary safety.

Flutter may render focused browse projections but never becomes filesystem authority.

SAF tree grants and arbitrary virtual/cloud `DocumentsProvider` execution are not part of the Phase 002 `LocalFilesystem` engine.

## 9. Foreground Execution Host

A qualifying user-admitted long-running Android job may acquire one foreground-service execution lease so work can continue when the Activity is not visible. The current `LibraryScan` workload is classified as Android `dataSync` foreground work because it performs long-running local-file processing; the Android manifest and service start use the corresponding foreground-service type and required manifest permissions.

The service is an execution host for the existing runtime only. Rust/SQLite remain authoritative for admission, job lifecycle, progress, cancellation, retry, terminal aggregation, and recovery.

Normative rules:

1. A direct user action that admits qualifying work requests the execution lease while the app is eligible to start a foreground service. Argus does not defer first acquisition until it is already backgrounded, use `BOOT_COMPLETED`, or create an Android-only scheduler to recover missed acquisition.
2. If Android rejects service creation or the `dataSync` execution budget is already exhausted, Argus must not claim background eligibility. Durable job admission still obeys the coherent handoff rule from SPEC-BE-004: the request is rejected before admission or any admitted run is safely terminalized/reconciled; no orphan nonterminal job is permitted.
3. The service exists only while at least one qualifying active job requires the lease and stops after the final qualifying job leaves that state.
4. Notification state is a secondary projection. Notification permission denial does not alter Jobs authority or stop otherwise valid execution; it removes notification-drawer projection/actions while the Flutter Jobs UI remains authoritative.
5. Native cancellation routes into the same `CancelJob` capability used by Flutter and observes the same durable cancellation-request and terminal-state semantics.
6. On Android versions that time-limit `dataSync` work, the service implements the platform timeout callback, reports a typed execution-host timeout to the existing runtime, reaches the next safe checkpoint, and stops within the platform grace period. A live non-resumable `LibraryScan` finalizes through its ordinary operation facts: useful but incomplete work becomes per-root `Partial` and aggregate `CompletedWithIssues` where applicable; no meaningful indexing result becomes `Failed`. A live timeout is not recovery-only `Abandoned`.
7. If the process is killed before terminalization, startup recovery applies the existing durable rule: accepted cancellation intent maps stale active work to `Cancelled`; otherwise current non-resumable `LibraryScan` becomes recovery-only `Abandoned`. No significant work auto-resumes during MVP.
8. A partial wake lock may be used only when measurement or native testing establishes that active screen-off scan execution otherwise loses required CPU continuity. It requires the normal manifest permission, has a bounded timeout, is held only while qualifying work is actually executing, and is released on completion, cancellation, timeout, service stop, or loss of the final lease. Queued/idle work never holds it.
9. Activity detach/recreation/backgrounding does not itself acquire, release, or replace runtime/job authority.

## 10. Adaptive Platform Contract

Argus presentation remains driven by available window geometry, not OS/device-category booleans.

Shared application width classes are Compact, Medium, Expanded, and Large. Android supports live resizing, rotation, split-screen, fold/unfold, tablets, phones, gaming handhelds, and large/desktop-class windows without an orientation lock.

The shared shell uses:

- Compact: direct Sources / Jobs / Settings bottom navigation for the active Phase 002 product;
- Medium: compact navigation rail;
- Expanded/Large: extended rail/sidebar.

Android system Back, predictive Back where supported, system bars, cutouts, IME, and safe insets are platform-adapted presentation concerns; they do not create a second route graph.

## 11. Distribution Contract

Android MVP is direct-distribution first.

Phase completion requires a signed installable APK produced through the repository-owned release path. Signing credentials are externally supplied and never committed. An AAB may also be produced, but it does not substitute for the directly installable artifact.

Google Play submission and policy approval are explicitly post-MVP and must not silently weaken the Phase 002 storage contract.

## 12. Verification Contract

`just check` remains deterministic, offline, and platform-neutral. Android SDK/NDK, `adb`, emulator, and physical-device requirements stay in explicit native gates.

Phase 002 requires:

- reusable shared contract/controller tests in the platform-neutral suite where behavior is platform-neutral;
- an x86_64 Android emulator gate through the real Flutter -> client -> FRB -> Rust -> SQLite stack;
- native tests for permission/readiness, Activity lifecycle, storage/root semantics, foreground execution, process loss/restart, Back/insets, and adaptive presentation as those capabilities become active;
- foreground-execution tests for `dataSync` declaration, direct-user lease acquisition, service-start rejection, Android 15+ timeout callback/finalization, exhausted-budget rejection, notification denial, bounded wake-lock acquisition/release when required, and teardown after the final qualifying job;
- at least one physical ARM64 critical-path milestone before phase completion;
- existing desktop native/regression gates to remain green.

Hardware-dependent removable-media evidence is required when applicable and available, but the phase does not require one exact accessory model.

## 13. Capability Applicability Established by Phase 002

The following classifications are normative:

- Android All files access onboarding: **Platform-specific (Android)**.
- Android notification permission onboarding: **Platform-specific (Android)**.
- Android foreground-service execution host: **Platform-specific (Android)**.
- Local library root selection: **Platform-adapted** — desktop uses its native folder-selection mechanism; Android uses the Argus-owned local filesystem browser.
- Startup diagnostic export: **Platform-adapted** — Android requires an Android-appropriate destination/export mechanism rather than assuming the current desktop save-location flow.
  `SLICE-P02-005` owns activation of that Android publishing mechanism. It is an output/export adaptation and does not create a SAF/content-provider library source.
- Open startup data directory: **Excluded on Android** — app-private storage is an implementation detail, not a user file-management surface.
- Core Sources/Jobs/Settings product capabilities: **Shared or Platform-adapted** according to their focused specifications.

## 14. Prohibited Architectural Drift

Phase 002 must not introduce:

- a second Android business-logic stack;
- a Kotlin-owned Argus backend;
- a second runtime/SQLite authority for background services;
- Android branches inside domain/application logic where provider/platform ports suffice;
- a persisted `AndroidDocumentTree` product source type for local mounted storage;
- Flutter filesystem traversal as source authority;
- WorkManager or another Android scheduler that silently auto-resumes significant Argus jobs;
- OS/device-category booleans as global layout authority;
- Play-policy-driven weakening of the approved direct-distribution MVP contract.

## 15. Acceptance Criteria

SPEC-X-002 is satisfied when:

1. Android API/ABI/distribution baselines are explicit.
2. All files access is a live mandatory platform prerequisite and not a Rust startup phase.
3. Notification authorization is optional and cannot become Jobs authority.
4. Android owns one cached Flutter engine/normal Dart isolate/root Argus runtime per process.
5. Activity lifecycle does not own runtime lifecycle.
6. Android app-private data is host-supplied and classified as standard application data.
7. Android local mounted storage stays in the existing `LocalFilesystem` provider family.
8. Foreground-service execution hosts the existing runtime rather than replacing it.
9. Shared adaptive presentation remains width-driven with no Android route fork.
10. Direct distribution produces a signed installable APK with external credentials.
11. Android native verification is separate from the platform-neutral gate and includes emulator plus physical ARM64 evidence by phase completion.
12. Future phases explicitly classify Android applicability and cannot complete with undocumented Android deferrals.
13. Qualifying `LibraryScan` work uses one `dataSync` foreground execution lease acquired from direct user admission, without creating a second runtime or scheduler.
14. Live foreground-service timeout handling finalizes through ordinary typed operation outcomes, while only stale nonterminal work discovered after process loss uses `Cancelled`/`Abandoned` recovery mapping.
15. Any manual partial wake lock is bounded, execution-scoped, and released on every terminal or lease-loss path.

## 16. References

- [ARCH-001 — Architecture Overview](../../architecture/architecture-overview.md)
- [ARCH-002 — Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-002 — Android First-Class Platform Support](../../phases/phase-002-android-first-class-platform-support.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](spec-x-001-versioning-and-compatibility-contract.md)
- [SPEC-BE-004 — Runtime and Background Operations](../backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-011 — Source Provider and Indexing](../backend/spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](../frontend/spec-fe-004-routing-and-adaptive-application-shell.md)
- [Approved Phase 002 design](../../superpowers/specs/2026-08-15-phase-002-android-first-class-platform-support-design.md)
- [Android foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Android foreground-service background-start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Android 15 foreground-service type changes](https://developer.android.com/about/versions/15/changes/foreground-service-types)
- [Android wake-lock best practices](https://developer.android.com/develop/background-work/background-tasks/awake/wakelock/best-practices)
