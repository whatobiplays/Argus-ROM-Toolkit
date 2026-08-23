# Android First-Class Platform Support

**Document ID:** PHASE-002  
**Status:** Complete  
**Owner:** Daniel  
**Last Updated:** 2026-08-22  
**Depends On:** ARCH-001, ARCH-002, PHASE-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

Phase 002 adds Android as a first-class Argus product platform without creating a second mobile architecture. Android must use the existing Flutter presentation layer, focused client APIs, Flutter Rust Bridge, Rust application/runtime, SQLite persistence, source-provider contracts, job model, and event-driven reconciliation model.

First-class does not mean literal desktop feature or interaction parity. Every capability is classified as **Shared**, **Platform-adapted**, **Platform-specific**, or **Excluded**. Phase completion requires every Android-applicable capability to be implemented and verified; it does not require forcing desktop-only behavior onto Android or Android-only platform behavior onto desktop.

## 2. User-Visible Outcome

When Phase 002 is complete, a user can install Argus directly on a supported Android 11+ ARM64 device, complete required storage onboarding, configure locally mounted game-library roots, scan and rescan them, inspect indexed source hierarchy, manage multiple roots and Scan All, review and control Jobs, leave the Activity while qualifying long-running work continues through Android foreground execution within platform execution limits, restart after process loss without silent auto-resume, and use the same width-driven adaptive product across phones, tablets, foldables, split-screen windows, and gaming handhelds.

## 3. Dependencies

- `ARCH-001` and `ARCH-002` remain authoritative.
- `PHASE-001` supplies the implemented local-source, scan, hierarchy, Jobs, removal, and restart-recovery contracts that Android adapts.
- Existing backend/frontend/cross-cutting specifications remain authoritative and are amended for Android rather than duplicated into mobile-only copies.

## 4. In Scope

- Android 11 / API 30 minimum.
- ARM64 (`arm64-v8a`) Android support for production, emulator, CI, and native qualification.
- Direct-distribution-first Android release path with a signed installable APK by phase completion.
- Mandatory Android All files access (`MANAGE_EXTERNAL_STORAGE`) as a platform readiness prerequisite.
- Optional notification permission onboarding on API 33+.
- One application-scoped cached Flutter engine, one normal Dart isolate, one Argus runtime, and one SQLite authority per process.
- Android `LocalFilesystem` using actual locally mounted storage under the existing provider family.
- Argus-owned Android filesystem browser rather than SAF tree selection for Phase 002.
- Internal/shared storage, Downloads, removable SD, and USB/OTG where Android exposes usable local filesystem access.
- Android `dataSync` foreground-service execution host for qualifying user-started long-running local-file work, started from direct user admission while the app is eligible to create the service.
- Shared width-driven Compact/Medium/Expanded/Large adaptive presentation with no orientation lock.
- ARM64-only emulator/native verification and a physical ARM64 phase milestone.
- Explicit platform applicability classification for future phases.

## 5. Platform Applicability

Phase 002 establishes the following required vocabulary:

- **Shared:** same product capability is meaningful on desktop and Android and should normally share domain/application contracts.
- **Platform-adapted:** same user outcome, but platform mechanics or UX differ.
- **Platform-specific:** meaningful only on one platform family; no artificial counterpart is required elsewhere.
- **Excluded:** deliberately unsupported on a platform; the owning spec records the rationale.

Implementation slices may sequence platforms differently. A phase cannot be marked complete while an Android-applicable capability remains deferred without an explicit owning-spec exclusion.

For the inherited Phase 000 capability set, appearance settings are **Shared**, startup diagnostic export is **Platform-adapted** and owned by `SLICE-P02-005`, and `Open data directory` is **Excluded** on Android because app-private storage is not a user file-management surface.

## 6. Out of Scope

- Android 10 / API 29 support; add post-MVP with an intentionally designed compatibility path.
- Non-ARM64 Android ABIs, including `x86_64` and 32-bit ABIs.
- Google Play submission, Play policy approval, or Play-specific product compromises.
- SAF/content-provider execution as the Phase 002 local-filesystem engine.
- Cloud-backed or virtual `DocumentsProvider` sources.
- A separate Android backend, database authority, business-logic layer, or scheduler.
- Automatic resumption of significant abandoned work after process death or OS interruption.
- Literal pixel/interaction parity with desktop when the desktop interaction is not meaningful on Android.

## 7. Required Subsystem Specifications

Phase 002 is governed by the following Ready specifications, as amended for Android:

- `SPEC-X-002` — Android platform runtime, readiness, applicability, distribution, and verification.
- `SPEC-X-001` — matched Argus product/version compatibility across desktop and Android artifacts.
- `SPEC-BE-003` — bounded Android diagnostics/observability classification.
- `SPEC-BE-004` — background-operation authority and Android foreground execution host semantics.
- `SPEC-BE-005` — shared appearance-settings persistence and Android lifecycle invariants.
- `SPEC-BE-007` — platform readiness outside backend startup coordination.
- `SPEC-BE-008` — bridge initialization and Android-facing DTO boundaries.
- `SPEC-BE-011` — Android `LocalFilesystem`, mounted-root identity, traversal, and availability.
- `SPEC-BE-013` — Android source-management, scan, removable-media, and reconciliation behavior.
- `SPEC-FE-001` — Flutter `app/platform` composition boundary.
- `SPEC-FE-003` — focused APIs/projections used by Android-applicable workflows.
- `SPEC-FE-004` — shared adaptive shell and Compact direct navigation.
- `SPEC-FE-005` — Android readiness gate and platform-applicable startup recovery presentation.
- `SPEC-FE-006` — shared appearance authority and Android Activity-lifecycle behavior.
- `SPEC-FE-007` — touch/accessibility/inset/adaptive design baseline.
- `SPEC-FE-008` — Android folder browsing and root-management UX.
- `SPEC-FE-009` — Android foreground-job notification projection and Jobs authority.

## 8. Ordered Implementation Slices

1. **SLICE-P02-001 — Android Platform Bootstrap and First-Run Readiness**: native Android host/build integration, API 30 baseline, ARM64 bridge packaging, one application-scoped runtime, mandatory All files access onboarding, optional notification onboarding, shared Compact direct navigation, and existing startup/settings persistence on Android; no Android root management yet.
2. **SLICE-P02-002 — Android LocalFilesystem and Argus Folder Picker**: mounted-volume discovery, Argus-owned filesystem browser, Android `LocalFilesystem` root admission, duplicate/overlap behavior, root persistence, and availability; no scan execution yet.
3. **SLICE-P02-003 — Android Scan and Source Hierarchy**: Add & Scan, `LibraryScan`, authoritative reconciliation, hierarchy inspection, Scan Again, identity/move behavior, and existing single-root Jobs controls.
4. **SLICE-P02-004 — Foreground Job Execution and Android Lifecycle**: `dataSync` foreground-service execution host, direct-user-admission start boundary, Activity detach/reattach, notification projection/cancel route, bounded partial wake-lock use when active work requires screen-off CPU continuity, Android 15+ timeout handling, OS interruption handling, and process-death recovery with no auto-resume.
5. **SLICE-P02-005 — Multi-Root and Applicable Feature Coverage**: multiple roots, Scan All, safe active-root removal, history/retry/cancel, restart recovery, permission regrant, removable-volume unavailability/remount, Android-adapted startup diagnostic export, and all currently Android-applicable Phase 000/001 capabilities.
6. **SLICE-P02-006 — Adaptive Android UX and Platform Integration**: phone/tablet/foldable/handheld hardening, portrait/landscape, live size-class transitions, Back/predictive Back, touch/accessibility/system-inset behavior, picker hardening, and lifecycle edge cases.
7. **SLICE-P02-007 — Android CI, Distribution, and First-Class Platform Hardening**: ARM64 Android CI/native qualification through the real stack, removal of residual non-ARM64 build targets, packaged libraries, emulator assumptions, harness branches, and CI jobs, physical ARM64 evidence, signed direct-distribution artifact, desktop regression preservation, future-phase applicability guards, and final Phase 002 verification record.

`SLICE-P02-007` is the final Phase 002 implementation slice.

## 9. Failure, Cancellation, and Recovery Expectations

- Denied/revoked All files access is a platform readiness failure, not root corruption or a new Rust startup phase.
- Existing configured roots, indexed entries, settings, and Jobs history remain durable while platform authorization is missing.
- Missing removable media makes affected roots unavailable and does not authorize destructive absence reconciliation.
- Current non-resumable `LibraryScan` execution lost unexpectedly recovers as `Abandoned` unless already-accepted cancellation intent maps it to `Cancelled`.
- Android foreground execution must not create a second backend or scheduler.
- Foreground-service admission, timeout, wake-lock, or notification state never becomes a second job lifecycle authority. A live timeout callback ends work through ordinary typed `Partial`/`Failed` semantics; only stale nonterminal work discovered after process loss becomes recovery-only `Abandoned` unless durable cancellation intent requires `Cancelled`.
- Notification denial does not block foreground execution; it removes notification-drawer projection/actions while the Jobs UI remains authoritative.
- Significant work is not silently auto-resumed during MVP.
- Removing a configured root never deletes or mutates user files.

## 10. Security and Privacy Impact

- All files access is explicitly requested and explained because local-library management is core product functionality for the direct-distribution MVP.
- Platform authorization state is observed from Android and is never trusted from a persisted boolean.
- App-private database/log paths remain implementation details and are not exposed as an Android file-management surface.
- Provider-owned root locators and removable-volume identity remain opaque outside the provider boundary.
- Secrets and private paths remain governed by `SPEC-BE-003` and existing redaction policy.
- Signing credentials remain external to the repository.

## 11. Test Strategy

- `just check` remains the deterministic platform-neutral gate.
- Shared domain/application/bridge/controller behavior continues to run there.
- Android-native verification is repository-owned but separate from `just check`.
- ARM64 Android native qualification exercises the real Flutter -> focused client -> FRB -> Rust -> SQLite -> Android `LocalFilesystem` path where the active slice reaches that capability.
- Native lifecycle tests cover Activity recreation, permission loss/regrant, foreground execution, process death, and restart recovery as those slices activate them.
- Foreground-execution tests cover `dataSync` declaration/admission, Android 15+ timeout callbacks and exhausted-budget start rejection, bounded wake-lock acquisition/release, notification denial, and service teardown after the final qualifying job.
- Shared UI tests cover Compact, Medium, Expanded, and Large widths independent of OS.
- Phase completion requires a recorded critical-path run on at least one physical ARM64 Android device or handheld.

## 12. Exit Criteria

Phase 002 is complete only when:

1. all seven slices are complete;
2. all Android-applicable Phase 000/001 capabilities are implemented or explicitly excluded with rationale in their owning spec;
3. the ARM64 Android native gate is green through the real product stack;
4. existing desktop regression gates remain green;
5. the physical ARM64 milestone is recorded;
6. a signed installable Android APK is produced through the repository-owned release path with external signing credentials;
7. architecture/specifications/templates describe Android as a first-class platform and enforce the applicability model for future phases;
8. no known Android MVP blocker is hidden behind an undocumented exclusion; and
9. Android 10, Google Play, and non-local document providers remain explicitly deferred, while non-ARM64 Android ABIs remain explicitly unsupported rather than partially implemented by accident.

## 13. Readiness Checklist

- [x] User-visible outcome is defined
- [x] Dependencies are available or sequenced
- [x] Scope and exclusions are explicit
- [x] Platform applicability is explicit for each substantive capability
- [x] Required public interfaces are identified
- [x] Persistence impact is identified
- [x] Failure and cancellation behavior are identified
- [x] Security and privacy impact is identified
- [x] Test requirements are specified
- [x] Implementation slices are ordered
- [x] Exit criteria are measurable
- [x] No blocking design questions remain
- [x] Daniel has accepted the capability and scope

## 14. References

- [ARCH-001 — Architecture Overview](../architecture/architecture-overview.md)
- [ARCH-002 — Documentation Architecture](../architecture/documentation-architecture.md)
- [PHASE-001 — Local Sources and Indexing](phase-001-local-sources-and-indexing.md)
- [SPEC-X-002 — Android Platform Runtime and Capability Contract](../specifications/cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md)
- [Approved Phase 002 design](../superpowers/specs/2026-08-15-phase-002-android-first-class-platform-support-design.md)
