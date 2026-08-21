# Phase 002 — Android First-Class Platform Support Design

**Date:** 2026-08-15  
**Status:** Approved design  
**Phase:** 002  
**Scope:** Android platform support for the currently implemented Argus product, plus durable first-class Android treatment in future phases

## 1. Summary

Phase 002 adds Android as a first-class Argus platform without creating a separate mobile product architecture. Android uses the existing Flutter presentation layer, `ArgusClient`, Flutter Rust Bridge, Rust application/runtime, SQLite persistence, source-provider abstractions, job model, and event-driven reconciliation model.

The phase targets **Android 11 / API 30 and newer** for MVP. Android support is **ARM64 (`arm64-v8a`) only**, including production, emulator, CI, and native qualification. Non-ARM64 Android ABIs, including `x86_64`, are outside the Argus product target because they do not represent the intended phone and retro-emulation-handheld hardware. Android 10 / API 29 support is explicitly post-MVP.

Android MVP is **direct-distribution first**. Google Play submission, policy review, and Play-specific packaging are post-MVP concerns. The product therefore treats Android's **All files access** capability (`MANAGE_EXTERNAL_STORAGE`) as a mandatory platform prerequisite rather than weakening the storage model to accommodate Play policy.

Phase 002 does not require pixel-for-pixel or interaction-for-interaction desktop parity. Instead, Argus adopts an applicability model for every capability:

1. **Shared** — required across desktop and Android.
2. **Platform-adapted** — same user/product capability with platform-appropriate implementation or interaction.
3. **Platform-specific** — intentionally present only on a platform where the capability makes sense.
4. **Excluded** — deliberately unsupported on a platform, with rationale documented in the owning spec.

A future phase cannot be considered complete until all **Android-applicable** capabilities in that phase are implemented and verified. It is not required to force desktop-only concepts onto Android or Android-only concepts onto desktop.

## 2. Goals

Phase 002 must deliver the following outcomes:

1. Argus launches and operates natively on supported Android devices.
2. The existing single-runtime architecture remains intact.
3. Users can configure and scan locally mounted Android storage using the existing `LocalFilesystem` provider family.
4. All currently implemented Phase 000 and Phase 001 product capabilities that are meaningful on Android are available through platform-appropriate Android UX.
5. User-started long-running jobs continue when the Flutter Activity leaves the foreground, subject to Android execution limits.
6. Android phone, tablet, foldable, split-screen, and gaming-handheld layouts use the same width-driven adaptive layout architecture as desktop.
7. Android becomes an explicit design, specification, CI, and phase-completion concern for all future work.

## 3. Non-Goals and Explicit Deferrals

Phase 002 does not include:

1. Android 10 / API 29 support. Add it post-MVP with an intentionally designed compatibility path.
2. Non-ARM64 Android ABI support, including `x86_64` and 32-bit ABIs.
3. Google Play distribution, Play policy approval, or Play-specific product compromises.
4. Cloud-backed or virtual Android `DocumentsProvider` sources.
5. A general Storage Access Framework content-provider execution engine.
6. Automatic resumption of abandoned significant work after process death or OS interruption.
7. A separate Android business-logic stack, Android-specific database, or Kotlin-owned Argus backend.
8. Android-only copies of shared controllers, domain services, or source models where shared abstractions already apply.
9. Forcing desktop-only functionality onto Android solely to satisfy a parity checklist.
10. Forcing Android-only platform functionality such as notification permission or foreground services onto desktop.

## 4. Platform Contract

### 4.1 Supported Android Baseline

The MVP platform baseline is:

- Minimum Android version: **Android 11 / API 30**.
- Supported Android ABI: **ARM64 (`arm64-v8a`)** for production, emulator, CI, and native qualification.
- Non-ARM64 Android ABIs, including `x86_64`, are unsupported.
- Orientation: **unlocked**.
- Supported form factors are determined by available window size, not hardware category.
- `compileSdk` and `targetSdk` should follow the repository's pinned Flutter toolchain defaults unless a required Android capability forces an explicit override. `minSdk` is explicitly pinned to 30.

### 4.2 Direct Distribution

Android MVP distribution is repository/release owned rather than Google Play owned. Phase 002 must produce a **signed release APK** suitable for direct installation/distribution; an AAB may also be produced, but it is not a substitute for the directly installable APK. Release signing credentials remain externally supplied through the repository-owned release path rather than committed to the repository. Google Play submission and policy approval are documented post-MVP work.

## 5. Platform Readiness and Permissions

### 5.1 All Files Access Is Mandatory

Android All files access is a hard Argus platform prerequisite on API 30+.

First-run flow:

1. Argus presents a bounded explanation of why broad local-storage access is required.
2. Argus opens the app-specific Android All files access settings surface.
3. On return/resume, Argus re-checks the actual platform authorization state.
4. Normal Argus runtime initialization remains gated until authorization is observed as granted.

The application must not trust a persisted boolean that says onboarding once succeeded. Current platform state is authoritative on every launch and relevant resume/reconciliation boundary.

If All files access is denied or later revoked:

- normal application destinations are not treated as storage-ready;
- existing SQLite state, configured roots, source entries, settings, and Jobs history remain intact;
- no destructive source reconciliation occurs merely because authorization disappeared;
- new scans are not admitted while the readiness requirement is unmet;
- the user receives a direct recovery action back to Android settings;
- after reauthorization, root availability is re-evaluated authoritatively.

### 5.2 Notification Permission Is Optional

On Android versions requiring notification runtime authorization, Argus requests notification permission during first-run onboarding after the mandatory storage step.

Notification denial:

- does not block Argus startup;
- does not disable foreground-service-backed job execution;
- degrades notification-drawer visibility and notification actions only;
- is exposed as a recoverable platform capability in Settings where appropriate.

Future notification-dependent features may define stronger requirements individually if justified by their product behavior.

## 6. Runtime Ownership

Android must preserve the Phase 000 single-runtime invariant.

### 6.1 Application-Scoped Runtime

The Android application owns one cached Flutter engine and one normal Dart isolate for Argus composition.

That isolate owns the existing chain:

`ArgusClient -> Flutter Rust Bridge -> one Rust application runtime -> one SQLite authority`

The Flutter Activity attaches to and detaches from that engine. Activity lifecycle transitions do not create or retire the Argus application runtime.

### 6.2 Lifecycle Rules

The following must not imply `generalShutdown` or runtime replacement:

- Activity recreation;
- rotation;
- window resizing;
- split-screen transitions;
- fold/unfold transitions;
- temporary backgrounding;
- screen-off while an admitted foreground-capable job is executing.

Actual process death remains runtime loss. On the next process launch, existing restart-recovery semantics apply. Significant active work from the dead process is reconciled into the existing interrupted/abandoned model and is not silently auto-resumed.

### 6.3 No Second Backend

The Android foreground service must not:

- initialize a second Rust runtime;
- open a second independent SQLite application authority;
- create a parallel native job scheduler;
- establish a second competing root event stream.

It preserves execution eligibility for the existing application-scoped runtime only.

## 7. Android `LocalFilesystem` Architecture

### 7.1 Provider Identity

`SourceProviderType::LocalFilesystem` remains the persisted source-provider family on Windows, macOS, Linux, and Android.

Android does not introduce a persisted `AndroidDocumentTree` or similar product-level source type. Platform-specific locator, mount, identity, and authorization mechanics remain provider-owned and opaque to generic application/domain consumers.

### 7.2 Meaning of LocalFilesystem on Android

For Phase 002, Android `LocalFilesystem` means **actual locally mounted filesystem storage** accessible under the mandatory platform authorization. Intended locations include:

- primary shared/internal user storage;
- Downloads and ordinary accessible subdirectories;
- mounted removable SD storage;
- mounted USB/OTG storage where Android exposes usable local filesystem access.

The provider must reject locations that cannot satisfy the required local hierarchical filesystem semantics, including unsupported cloud/virtual document providers and protected application-private areas.

### 7.3 Native and Rust Boundaries

Android/Kotlin code owns Android OS mechanics such as:

- storage-volume discovery;
- application/service lifecycle integration;
- permission and special-access state;
- platform notification/service APIs;
- any Android-specific bridge required to expose mount facts safely.

Rust infrastructure owns source semantics such as:

- validation;
- canonical root locator construction;
- root-relationship comparison;
- root resolution and availability;
- bounded directory enumeration;
- relative locators;
- stat/open behavior;
- native identity policy;
- provider error mapping;
- root-boundary safety.

Application/domain layers remain platform-neutral. Flutter owns UX and orchestration but is not filesystem authority.

## 8. Argus-Owned Android Folder Picker

Phase 002 deliberately does **not** use SAF tree selection as its primary root-selection mechanism. Mandatory All files access allows Argus to provide a single filesystem-oriented selection model consistent with the existing `LocalFilesystem` abstraction.

### 8.1 UX Contract

The picker:

1. displays currently available local storage volumes;
2. allows bounded navigation through accessible directories;
3. shows a clear current location and breadcrumb/up-navigation model;
4. supports explicit `Select this folder` confirmation;
5. uses Android-appropriate touch targets and Back behavior;
6. exposes safe display names/locations rather than raw Android storage identifiers;
7. never requires Flutter to construct canonical filesystem locators or infer ancestry.

### 8.2 Browse API Boundary

Flutter receives a focused browse projection sufficient to render the picker. The provider/native infrastructure remains authoritative for enumeration and selection identity.

The picker must not become a second implementation of `LocalFilesystem` in Dart.

### 8.3 Root Admission

Final selection enters the existing LocalFilesystem root-validation and admission flow. The provider owns normalization and overlap semantics and returns the existing typed outcomes:

- Added;
- Already configured;
- Overlaps existing.

`Add & Scan` preserves the existing committed-root-then-child-admission semantics rather than becoming an Android-specific composite transaction.

## 9. Root Persistence, Removable Media, and Safety

### 9.1 Persistence

Android roots use the same durable `LibrarySource` / `LibraryRoot` model as desktop. Provider-owned locator or identity material may vary internally by platform, but generic consumers treat it as opaque. For removable storage, the provider must persist enough stable volume identity plus root-relative location information to re-identify the configured root without treating a transient mount path alone as durable identity.

### 9.2 Removable Storage

Temporarily absent removable media must not cause root deletion or destructive absence reconciliation.

A missing SD/USB volume makes affected roots unavailable. Other roots remain operational. If the same trustworthy volume/root becomes available again, the existing `LibraryRootId` is restored to usable availability rather than creating a new configured root.

### 9.3 Active Scan Loss

If a volume disappears during a scan:

- the scan terminates through existing typed failure/interruption semantics;
- destructive absence finalization is not allowed to interpret volume loss as authoritative proof that every indexed entry was deleted;
- unrelated roots and jobs continue normally;
- Scan All uses existing eligibility/exclusion semantics for unavailable roots.

### 9.4 Removal Safety

Removing a configured Android root removes Argus configuration/index state only. It must never delete, rename, move, modify, or otherwise mutate the user's files.

## 10. Foreground Job Execution

### 10.1 Execution Lease

A user-admitted long-running Android job that must continue outside the visible Activity acquires an Android foreground-service execution lease.

The service is a platform host for the existing Argus runtime. The authoritative job lifecycle remains in Rust/SQLite.

### 10.2 Service Lifetime

- Start/maintain the service while at least one qualifying active job requires background execution eligibility.
- Stop the service when no qualifying job remains.
- Do not create per-feature service-owned schedulers.
- Future long-running Android operations should reuse the same execution-host architecture where applicable.

### 10.3 Notification Projection

The service notification is a secondary projection of authoritative Jobs state.

Where notification capability permits:

- show useful active-work status;
- expose cancellation when appropriate;
- route cancellation through the same authoritative `CancelJob` path used by the Flutter Jobs UI.

The notification never owns job state independently.

### 10.4 Android Execution Limits

Android OS execution limits must preserve database consistency and use the existing BE-004 lifecycle/recovery vocabulary without conflating live timeout handling with restart recovery. A foreground-service timeout callback while the process/runtime still exists requests orderly termination through the existing operation path and records the truthful ordinary terminal result supported by committed work (`CompletedWithIssues`, `Failed`, or `Cancelled` when accepted cancellation determines termination). `Abandoned` is reserved for stale nonterminal execution discovered after forced process/runtime loss. The current non-resumable `LibraryScan` never uses `Interrupted`; a future operation with a valid resumable checkpoint may use `Interrupted` according to its owning recovery policy. No significant work is automatically resumed during MVP.

## 11. Adaptive UI and Navigation

### 11.1 Width-Driven Architecture

Argus continues to classify presentation from currently available window dimensions rather than `Platform.isAndroid`, phone/tablet detection, or fixed hardware categories.

The shared shell contract becomes:

- **Compact:** direct `Sources / Jobs / Settings` bottom navigation.
- **Medium:** compact navigation rail.
- **Expanded/Large:** extended rail/sidebar.

The Compact change is shared across platforms. A narrow desktop window and a Compact Android window receive the same semantic navigation model.

### 11.2 Branch Behavior

Existing stateful branch restoration remains shared:

- inactive destinations remember their durable route;
- selecting an inactive destination restores its branch;
- reselecting the active destination returns that branch to its canonical root;
- Jobs continues to expose active-job status through its navigation destination.

### 11.3 Form Factors and Orientation

Android has no Argus orientation lock. Layout must adapt live across:

- portrait and landscape;
- phone and tablet windows;
- fold/unfold transitions;
- split-screen and multi-window resizing;
- gaming handheld displays;
- large/desktop-class Android windows.

### 11.4 Android Navigation Semantics

Android system Back must follow the product's route/modal hierarchy rather than exiting prematurely. Folder-picker Back navigates up the folder hierarchy before dismissing the picker when appropriate. Predictive Back should be integrated using the supported Flutter/Android mechanism rather than bespoke platform routing.

System bars, cutouts, IME insets, and safe areas are handled through normal Flutter adaptive layout rather than device-specific constants.

## 12. Platform-Appropriate Capability Model

Starting with Phase 002, every new phase and substantive feature must classify platform applicability.

### 12.1 Shared

The capability has meaningful equivalent product value on desktop and Android and should normally share domain/application contracts.

### 12.2 Platform-Adapted

The user outcome is shared but native mechanics or UX differ. Examples include desktop native folder selection versus the Argus Android filesystem browser.

### 12.3 Platform-Specific

The capability only makes sense on one platform family. Android foreground services and Android permission onboarding are valid Android-only functionality and require no artificial desktop equivalent.

### 12.4 Excluded

A capability may be explicitly unsupported on a platform when it is not meaningful or technically appropriate. The owning spec must document the exclusion and rationale.

### 12.5 Phase Completion

A phase is complete only when:

- every capability has had Android applicability considered;
- every Android-applicable capability is implemented and verified;
- deliberate exclusions are documented;
- Android is not deferred wholesale into a generic catch-up slice after desktop architecture is already fixed.

Individual implementation slices may sequence desktop and Android work differently when that produces cleaner engineering boundaries.

## 13. Verification Strategy

### 13.1 Shared Verification

`just check` remains deterministic and platform-neutral. Shared Rust/application/domain/bridge/controller behavior remains covered there.

Android support must not reduce existing Windows/Linux/macOS verification. Android CI and native qualification must exercise the supported ARM64 ABI rather than maintaining an unsupported `x86_64` Android artifact solely for emulator convenience.

### 13.2 Android Native ARM64 Gate

The repository must gain an Android-native verification command analogous to the existing native phase harnesses. CI/native qualification runs it against an **ARM64 Android environment** and exercises the real:

`Flutter -> ArgusClient -> FRB -> Rust -> SQLite -> Android LocalFilesystem`

path.

Native coverage includes, where automation permits:

- readiness-state composition;
- startup and recovery;
- root browsing and admission;
- root persistence;
- scans and source hierarchy;
- Jobs actions and reconciliation;
- Activity detach/reattach behavior;
- foreground-service execution;
- process-death/relaunch recovery;
- adaptive layout and Android Back behavior.

### 13.3 LocalFilesystem Contract Coverage

Android must satisfy the same observable LocalFilesystem behavior as desktop where applicable:

- root validation;
- duplicate/ancestor/descendant/disjoint relationship semantics;
- bounded traversal;
- root availability;
- stat/open/enumeration;
- root-boundary/link-like safety;
- removable-volume loss/reappearance;
- trustworthy provider-native identity behavior.

Android-specific fixtures are valid where implementation mechanics differ.

### 13.4 Foreground Execution Coverage

Tests must prove at minimum:

1. an admitted scan survives Activity backgrounding/detachment;
2. Activity recreation does not create a second Argus runtime;
3. cancellation from Flutter and native notification controls converges on the same authoritative job;
4. the foreground service stops after the final qualifying job;
5. process death/relaunch uses existing abandoned-work recovery and does not auto-resume.

### 13.5 Adaptive UI Coverage

Shared tests exercise Compact, Medium, Expanded, and Large widths independently of OS. Android adds platform-specific coverage for orientation, resizing, Back, system insets, and picker navigation.

### 13.6 Physical ARM64 Milestone

Phase 002 cannot be marked complete until the critical applicable path is verified on at least one physical ARM64 Android device or handheld.

The milestone covers:

- fresh install;
- mandatory All files access onboarding;
- notification grant and denial behavior;
- startup and appearance persistence;
- internal-storage browsing/root admission;
- removable storage where test hardware is available;
- Add & Scan;
- hierarchy inspection;
- Scan Again;
- multiple roots and Scan All;
- cancellation and retry;
- historical Jobs;
- background scan while another app is foregrounded and while the screen is off;
- Activity recreation;
- process termination and restart recovery;
- permission revocation and regrant;
- safe root removal.

Hardware-dependent removable-media cases are recorded as applicable evidence rather than making possession of one exact accessory a universal phase prerequisite.

## 14. Phase 002 Slice Structure

Phase 002 uses capability-vertical slices. Each slice ends with a coherent, demonstrable Android capability rather than deferring all integration to the end.

### SLICE-P02-001 — Android Platform Bootstrap and First-Run Readiness

- Android Flutter host and build integration.
- API 30 minimum.
- ARM64 production, emulator, and native-qualification builds.
- Android FRB/Rust/SQLite startup.
- Application-scoped cached Flutter engine and single Argus runtime.
- Mandatory All files access onboarding.
- Optional notification permission onboarding.
- Shared Compact `Sources / Jobs / Settings` bottom navigation.
- Existing startup/recovery, appearance settings, and persistence functioning on Android.
- No Android library-root management yet.

### SLICE-P02-002 — Android LocalFilesystem and Argus Folder Picker

- Mounted-volume discovery.
- Argus-owned Flutter folder-picker UI.
- Focused browse projections supplied from provider/native infrastructure.
- Internal/shared storage, Downloads, SD, and USB/OTG where accessible.
- Direct filesystem semantics under All files access.
- Existing `SourceProviderType::LocalFilesystem` preserved.
- Add/remove roots and duplicate/overlap outcomes.
- Durable root persistence and availability across restart.
- No scan execution yet.

### SLICE-P02-003 — Android Scan and Source Hierarchy

- Add & Scan.
- LibraryScan against Android LocalFilesystem.
- Incremental indexing and authoritative reconciliation.
- Source hierarchy inspection.
- Scan Again.
- Android-native identity/move behavior.
- Existing cancellation/retry/Jobs contracts exercised for single-root work.

### SLICE-P02-004 — Foreground Job Execution and Android Lifecycle

- Foreground-service execution host for qualifying user-started work.
- Activity detach/reattach without runtime teardown.
- Native notification projection and cancellation route.
- Background/screen-off continuity.
- OS interruption handling.
- Process death to existing abandoned/no-auto-resume recovery semantics.

### SLICE-P02-005 — Multi-Root and Applicable Feature Coverage

- Multiple Android roots.
- Scan All and partial eligibility/exclusions.
- Safe active-root removal behavior.
- Historical Jobs and existing retry/cancel behavior.
- Restart recovery.
- Permission revocation/regrant reconciliation.
- Storage-volume unavailable/remounted behavior.
- All currently applicable Phase 000/001 product capabilities demonstrably available on Android.

This slice does not require copying desktop-only interaction mechanics that are not meaningful on Android.

### SLICE-P02-006 — Adaptive Android UX and Platform Integration

- Phone/tablet/foldable/handheld validation.
- Portrait and landscape.
- Compact/Medium/Expanded/Large transitions.
- Android Back/predictive-Back behavior.
- Touch/accessibility/inset hardening.
- Folder-picker UX hardening.
- Lifecycle edge cases.
- Shared adaptive improvements remain shared rather than becoming Android forks.

### SLICE-P02-007 — Android CI, Distribution, and First-Class Platform Hardening

- ARM64 Android CI/native qualification through the real product stack.
- Residual non-ARM64 Android build targets, packaged libraries, emulator assumptions, harness branches, and CI jobs removed.
- Complete Android Phase 002 native milestone harness.
- Physical ARM64 verification record.
- Signed direct-distribution artifacts.
- Desktop regression gates retained.
- Documentation/spec/convention guards encode the first-class applicability model for future phases.
- Final Phase 002 verification record.

`SLICE-P02-007` is the final Phase 002 implementation slice.

## 15. Specification and Documentation Ownership

Phase 002 should extend existing authoritative subsystem specifications instead of creating Android copies of them.

### 15.1 New Cross-Cutting Specification

Create **SPEC-X-002 — Android Platform Runtime and Capability Contract** to own only Android-wide concerns:

- supported Android baseline and ABIs;
- mandatory All files access;
- optional notification permission;
- application-scoped runtime ownership;
- foreground-service execution lease;
- Android lifecycle/recovery rules;
- direct-distribution baseline;
- Android native verification;
- future phase platform-applicability rules.

### 15.2 Existing Specifications to Amend

Expected authoritative owners include:

- **SPEC-BE-004** — background operations and Android foreground execution integration.
- **SPEC-BE-008** — any bridge DTOs required by Android platform/storage browsing contracts.
- **SPEC-BE-011** — Android LocalFilesystem implementation semantics and capabilities.
- **SPEC-BE-013** — Android source management, availability, and scan behavior.
- **SPEC-FE-003** — focused APIs required for platform readiness/storage browsing where they belong in the client boundary.
- **SPEC-FE-004** — shared Compact bottom navigation and adaptive behavior.
- **SPEC-FE-005** — Android platform-readiness startup/recovery gate.
- **SPEC-FE-007** — Android touch/accessibility/platform layout baseline where applicable.
- **SPEC-FE-008** — Argus Android folder picker and root-management UX.
- **SPEC-FE-009** — foreground-job presentation and notification projection semantics.
- **SPEC-X-001** — matched Argus release/version compatibility language must no longer assume desktop-only distribution.

The architecture overview, phase index, testing conventions, implementation templates, and phase templates should be updated where necessary to make Android a normal supported platform and to encode the applicability model.

### 15.3 Phase Document

Create:

`docs/phases/phase-002-android-first-class-platform-support.md`

The phase document should reference the owning subsystem specifications rather than duplicating their detailed contracts.

## 16. Alternatives Considered and Rejected

### 16.1 SAF-First Storage

Rejected for the MVP local-filesystem path. Android SAF tree selection has root-selection constraints and would introduce a document-provider authorization/execution model that is unnecessary once All files access is mandatory. Arbitrary document-provider support can be designed later as a separate capability rather than being mislabeled as LocalFilesystem.

### 16.2 Android-Specific Persisted Source Type

Rejected. `AndroidDocumentTree` or similar would make local Android storage look like a separate product source family and would unnecessarily propagate provider-type branching through otherwise shared behavior.

### 16.3 Activity-Owned Runtime

Rejected. It would couple backend lifetime to Android UI lifecycle and break reliable background jobs and Activity recreation.

### 16.4 Native Service-Owned Rust Runtime

Rejected. Kotlin/JNI would become a parallel backend API surface and create competing runtime/database ownership.

### 16.5 Separate UI and Background Flutter Engines

Rejected because it would create competing Dart/FRB runtime ownership, duplicate event-subscription risk, and ambiguous shutdown semantics.

### 16.6 Foreground-Only Scanning

Rejected as insufficient for first-class Android support. Switching apps or turning the screen off should not implicitly abandon user-started scans.

### 16.7 WorkManager Auto-Resume

Rejected because significant abandoned work currently does not auto-resume and because it would establish an Android-specific scheduler alongside the existing background-operation authority.

### 16.8 Exact Desktop Feature Parity

Rejected. First-class platform support means platform-appropriate capability coverage and architectural inclusion, not forcing nonsensical desktop-only behavior onto Android.

## 17. Completion Criteria

Phase 002 is complete only when all of the following are true:

1. All seven Phase 002 slices are complete.
2. Android-applicable Phase 000 and Phase 001 product capabilities are implemented.
3. Android ARM64 native qualification is green through the real Flutter/FRB/Rust/SQLite stack.
4. Existing desktop regression gates remain green.
5. The physical ARM64 milestone is recorded.
6. Android direct-distribution artifacts are produced through the repository-owned release path.
7. Current architecture and specifications describe Android as a supported first-class platform.
8. Future phase/spec templates enforce explicit platform applicability rather than assuming desktop-only behavior or literal parity.
9. No known Android MVP blocker is hidden behind an undocumented exclusion.
10. Android 10 support, Google Play distribution, and non-local document providers remain clearly documented as post-MVP work, while non-ARM64 Android ABIs remain clearly documented and enforced as unsupported.
