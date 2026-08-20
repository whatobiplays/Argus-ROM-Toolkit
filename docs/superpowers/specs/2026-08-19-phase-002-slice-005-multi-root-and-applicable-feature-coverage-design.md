# Phase 002 Slice 005 — Multi-Root and Applicable Feature Coverage Design

**Date:** 2026-08-19  
**Status:** Approved design  
**Phase:** 002  
**Slice:** SLICE-P02-005  
**Scope:** Activate the existing Phase 000/001 product capabilities that are applicable to Android, preserving shared authority and adding only required Android platform adaptations.

## 1. Summary

SLICE-P02-005 completes functional Android coverage of the currently applicable Phase 000 and Phase 001 product capabilities. It activates multiple roots, Scan All, safe active-root removal, historical Jobs/retry/cancel, restart recovery, permission revocation/regrant, removable-volume loss/remount, and Android-adapted startup diagnostic export.

The implementation is capability activation over existing Phase 001 contracts. Shared Sources, Jobs, runtime, persistence, and reconciliation behavior remain authoritative. Android-specific code supplies platform facts and publication mechanics only. Shared code changes are permitted only when tests prove a real cross-platform defect or missing abstraction; unrelated refactoring is out of scope.

## 2. Binding Decisions

1. Startup diagnostic export is in scope for P02-005, as assigned by PHASE-002 and SPEC-X-002.
2. Phase 001 semantics are reused first. Shared behavior changes require concrete failing tests that demonstrate a real gap.
3. Android diagnostic export uses the Android system share sheet. Backend-owned sanitized archive generation remains authoritative; Android publishes the completed artifact through scoped `content://` access.
4. Loss of All files access terminates affected active work using truthful existing failure semantics, preserves durable state, blocks new storage-dependent admission, prohibits destructive absence reconciliation, and requires explicit retry after regrant.
5. Removable SD/USB loss follows the same isolation principle: only affected work terminates; unrelated roots/jobs continue; durable root/index/history state is preserved; trustworthy remount restores the existing root identity; no auto-resume occurs.
6. Android activates the full existing safe active-root cancel-and-remove workflow. User files are never mutated.
7. Scan All mirrors Phase 001 eligibility/exclusion semantics. Unavailable roots are explicit exclusions rather than whole-operation failures or silent skips.
8. Multiple-root presentation remains the shared Sources model. P02-005 unlocks capabilities rather than introducing an Android-specific management screen.
9. The overall architecture is capability activation over existing shared contracts, not an Android orchestration layer or a promotion of Android-only mechanics into generic business concepts.

## 3. Architecture and Capability Boundaries

### 3.1 Shared authority

Shared Sources and Jobs behavior remains authoritative:

- multiple configured roots use the existing `LibraryRoot` model;
- Scan All uses the existing shared admission and exclusion behavior;
- per-root retry, cancel, and history use the existing Jobs model;
- active-root removal uses the existing cancel-and-remove semantics;
- Flutter reconciles from focused queries and events rather than maintaining Android-owned truth.

No Android-specific scheduler, source model, job lifecycle, or database authority is introduced.

### 3.2 Android platform boundaries

Android-specific mechanics remain at platform/native boundaries:

- All-files-access observation and regrant handling remain platform-readiness concerns under the existing platform composition boundary;
- mounted-volume discovery and remount facts remain Android/native infrastructure concerns;
- diagnostic publishing is an Android adapter from a completed backend-owned sanitized ZIP to scoped `content://` access and the system share sheet.

These mechanics do not become new generic source types or application business concepts.

### 3.3 Capability activation

P02-005 enables Android capabilities deliberately withheld by earlier slices:

- Scan All;
- active-root cancel-and-remove;
- full applicable historical Jobs, retry, and cancel behavior;
- multiple-root workflows through the existing shared Sources presentation.

P02-006 adaptive UX, predictive Back, form-factor polish, and picker hardening remain deferred unless a correctness defect blocks P02-005.

### 3.4 Environmental loss invariant

Permission loss and removable-volume loss are environmental availability changes, not user cancellation and not proof of file deletion.

Therefore:

- only affected active work terminates;
- existing truthful typed failure semantics are used;
- roots, indexed entries, settings, and Jobs history remain durable;
- destructive absence reconciliation is prohibited while access is unavailable;
- regrant/remount triggers authoritative availability refresh;
- significant work is never automatically resumed.

The core invariant is: **loss of access can reduce availability, but it never manufactures evidence that user files were deleted.**

### 3.5 Shared-code change rule

Shared Phase 001 code is changed only when an Android test demonstrates an incorrect cross-platform assumption or a missing abstraction required for the governed behavior. Any such change must preserve desktop semantics and gain regression coverage. Broad cleanup or opportunistic refactoring is not part of this slice.

## 4. Scan All

Android activates the existing Scan All workflow without introducing platform-specific scheduling semantics.

1. Direct user admission enters the shared Scan All command path.
2. Authoritative root state determines eligible roots and explicit exclusions.
3. Each eligible root receives independent child scan admission through existing application/runtime contracts.
4. Unavailable removable roots or otherwise ineligible roots are reported as exclusions and do not fail the entire Scan All request.
5. Independently executing roots remain isolated from one another.
6. Aggregate state and results are derived from authoritative child/job state rather than Android-owned bookkeeping.
7. P02-004 foreground-execution guarantees continue to apply when multiple qualifying jobs are active.

Unavailable roots must not be silently skipped.

## 5. All Files Access Revocation and Regrant

Android platform authorization state remains observed from Android rather than trusted from persisted state.

### 5.1 Revocation

When All files access is lost:

- new storage-dependent admissions are blocked;
- affected active scans terminate through existing truthful failure semantics rather than fabricated user cancellation;
- configured roots, indexed entries, settings, and Jobs history remain intact;
- destructive absence reconciliation is prohibited because loss of authorization is not evidence of filesystem absence;
- non-storage product state remains available according to existing readiness rules.

### 5.2 Regrant

When authorization returns:

1. mounted-volume facts are refreshed first;
2. configured roots are re-resolved against current authoritative platform/provider state;
3. roots whose trustworthy identity remains valid return to available state;
4. no scan is automatically restarted or resumed;
5. the user explicitly invokes retry, Scan Again, or Scan All as appropriate.

## 6. Removable-Volume Loss and Remount

A disappeared SD card or USB/OTG volume affects only roots that depend on that volume.

On loss:

- affected roots become unavailable;
- active scans against those roots terminate using existing truthful failure semantics;
- destructive absence finalization is prohibited;
- unrelated roots and jobs continue normally;
- root configuration, indexed state, and history remain durable.

On remount:

- provider/native infrastructure refreshes mounted-volume facts;
- trustworthy stable volume identity plus root-relative identity is used to re-resolve configured roots;
- the same trustworthy volume/root restores the existing `LibraryRootId` rather than creating a duplicate configured root;
- no significant work auto-resumes.

A waiting/suspended scan model is explicitly not introduced.

## 7. Safe Active-Root Removal

Android exposes the full existing Phase 001 cancel-and-remove workflow.

For a root with active work:

1. removal requests cancellation through the authoritative Jobs path;
2. the workflow waits for the required terminal/settled state defined by existing shared contracts;
3. only then is Argus configuration/index state removed;
4. user files are never deleted, renamed, moved, or modified.

Transport ambiguity is reconciled through authoritative queries rather than assuming success or failure. Immediate removal followed by eventual job failure is not an acceptable implementation.

## 8. Historical Jobs, Retry, Cancel, and Restart Recovery

Android exposes the existing applicable Jobs behavior rather than adding Android-specific lifecycle semantics.

- Historical Jobs remain query-authoritative.
- Retry creates fresh execution identity according to existing Phase 001 contracts.
- Cancel uses the same authoritative cancellation path used by existing Flutter Jobs controls and P02-004 notification actions.
- Restart recovery uses existing abandoned/no-auto-resume semantics.
- Permission or volume loss does not create a new persisted job lifecycle state.
- P02-004 foreground-service state remains a projection/execution lease, never job authority.

## 9. Android Startup Diagnostic Export

Diagnostic archive assembly remains backend-owned and sanitized according to SPEC-BE-003. Android adapts only the destination/publication interaction.

### 9.1 Flow

1. The user explicitly requests startup diagnostic export.
2. The existing backend diagnostic export path creates the versioned sanitized ZIP in bounded app-private temporary/export storage appropriate to the Android publishing adapter.
3. Android exposes only the completed artifact through scoped `content://` access.
4. Android launches the system share sheet for user-directed publication.
5. Temporary export artifacts are lifecycle-managed and bounded.

### 9.2 Security and ownership

- Flutter does not receive or construct raw app-private filesystem paths.
- Raw app-private paths, mount coordinates, and authorization implementation details do not enter safe context, logs, application errors, or diagnostic manifests.
- Diagnostic redaction and contributor policies remain unchanged and backend-owned.
- The share adapter never weakens sanitization or publishes a partially assembled/failed archive as a successful export.
- Scoped URI access is granted only as required for the selected Android share operation.

This export mechanism does not introduce SAF/content-provider library-source semantics. `Open data directory` remains excluded on Android.

## 10. Presentation

P02-005 preserves the existing shared Sources and Jobs presentation architecture.

- Multiple roots use the existing root list and hierarchy model.
- Scan All becomes available through the shared capability/presentation gates.
- Active-root removal becomes available through the shared safe-removal workflow.
- Existing per-root actions, hierarchy inspection, and Jobs integration remain shared.
- Android-specific multi-root screens are not introduced.

Any UI adjustment required solely for adaptive form-factor quality belongs to P02-006 unless it is necessary for correctness or to expose an otherwise inaccessible P02-005 capability.

## 11. Failure Handling

Failure handling must preserve semantic truth and root isolation.

- Permission loss is an environmental/platform-readiness failure, not cancellation intent.
- Removable-volume loss is source unavailability, not evidence that indexed files were deleted.
- One unavailable root does not invalidate unrelated roots.
- Scan All partial eligibility remains explicit.
- Transport ambiguity is reconciled from authoritative queries.
- Restart recovery does not auto-resume significant work.
- Diagnostic publishing failures do not corrupt or weaken the backend diagnostic artifact contract.

No P02-005 behavior may introduce a second state authority to simplify presentation.

## 12. Verification Strategy

### 12.1 Shared verification

`just check` remains deterministic and platform-neutral. Shared/unit coverage must prove that Android activation does not alter existing desktop semantics for:

- Scan All admission and exclusions;
- cancel-and-remove;
- Jobs history/retry/cancel;
- restart recovery;
- root availability and reconciliation;
- diagnostic archive sanitization.

Desktop tests must not acquire Android SDK/NDK dependencies.

### 12.2 Android-native verification

Repository-owned Android-native coverage must exercise the real product path where applicable:

`Flutter -> focused client -> FRB -> Rust -> SQLite -> Android LocalFilesystem`

The P02-005 milestone must prove:

1. multiple configured Android roots;
2. Scan All with mixed eligible and unavailable roots and explicit exclusions;
3. independent child/root execution behavior;
4. historical Jobs, retry, and cancellation;
5. safe active-root cancel-and-remove;
6. All-files-access revocation during active work, preservation of durable state, blocked new admission, regrant refresh, and explicit retry behavior;
7. removable-volume disappearance during active work, isolation from unrelated roots, preservation of indexed state, and trustworthy remount restoration to the existing root identity;
8. restart recovery with no automatic resumption;
9. Android startup diagnostic bundle creation and share-sheet publication through scoped `content://` access;
10. no raw app-private path or authorization detail leaks into Flutter-facing state, safe context, logs, errors, or diagnostic manifests;
11. P02-004 foreground execution remains correct with multiple qualifying jobs.

These cases should use controlled focused fixtures rather than one oversized end-to-end scenario when separation improves runtime and failure diagnosis.

## 13. Scope

### 13.1 In scope

- Multiple Android roots using existing `LocalFilesystem` contracts.
- Scan All and Phase 001 eligibility/exclusion semantics.
- Safe active-root cancel-and-remove.
- Historical Jobs and existing retry/cancel behavior.
- Restart recovery with no auto-resume.
- All-files-access revocation/regrant reconciliation.
- Removable-volume unavailability/remount reconciliation.
- Android startup diagnostic export through the system share sheet.
- Demonstrable availability of all other currently Android-applicable Phase 000/001 capabilities.

### 13.2 Explicitly out of scope

- P02-006 adaptive UX hardening, predictive Back, broader picker hardening, and form-factor-specific polish.
- P02-007 CI/distribution/signing and physical ARM64 completion evidence.
- Android 10 / API 29.
- Google Play policy or submission work.
- 32-bit Android ABIs.
- SAF/content-provider library sources.
- WorkManager or automatic significant-work resumption.
- New resumable scan semantics.
- Android-specific multi-root or Jobs business models.
- Broad Sources redesign.
- Unrelated Phase 001 refactoring.

## 14. Completion Contract

P02-005 is complete only when Android demonstrably exposes the entire currently applicable Phase 000/001 capability set assigned to this slice. Isolated unit tests are insufficient if an Android capability gate remains disabled or the real native product path cannot perform the workflow.

Representative native qualification must cover the combined capability surface, using separate focused scenarios where appropriate:

`multiple roots -> Scan All with mixed eligibility -> Jobs/history -> retry/cancel -> active-root removal -> permission loss/regrant -> removable-volume loss/remount -> restart recovery -> diagnostic export`

After P02-005:

- Android has functional coverage of all applicable Phase 000/001 product capabilities;
- P02-006 remains responsible for adaptive Android UX and platform-integration hardening;
- P02-007 remains responsible for CI, distribution, physical ARM64 evidence, and final Phase 002 first-class-platform qualification.

## 15. Rejected Alternatives

### 15.1 Broader shared refactoring

Rejected because P02-005 is Android capability activation, not a Phase 001 redesign. Shared changes require evidence of a real defect or missing abstraction.

### 15.2 Android-specific orchestration layer

Rejected because it would duplicate application reconciliation/state logic and risk becoming a second application authority.

### 15.3 Android-specific multi-root screen

Rejected because the existing shared Sources model already represents the product capability. Adaptive presentation hardening belongs to P02-006.

### 15.4 Require every root to be available for Scan All

Rejected because it diverges from Phase 001 partial eligibility and makes removable storage unnecessarily disruptive.

### 15.5 Silent Scan All exclusions

Rejected because unavailable roots are meaningful user-visible execution facts.

### 15.6 Keep scans alive waiting for permission or removable media

Rejected because it introduces suspended/resumable semantics that the current operation model does not support.

### 15.7 Treat environmental loss as user cancellation

Rejected because it records semantically false intent and obscures the actual failure condition.

### 15.8 `ACTION_CREATE_DOCUMENT` diagnostic export

Rejected for P02-005 in favor of the system share sheet. Share-sheet publication is the narrower Android-native adaptation and does not require a new save-destination workflow.

### 15.9 Support both diagnostic publication mechanisms

Rejected as unnecessary product and test surface for the Phase 002 requirement.

## 16. References

- `docs/phases/phase-002-android-first-class-platform-support.md`
- `docs/superpowers/specs/2026-08-15-phase-002-android-first-class-platform-support-design.md`
- `docs/specifications/cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md`
- `docs/specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md`
- `docs/specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md`
- Existing Phase 001 Sources, Jobs, LocalFilesystem, reconciliation, and restart-recovery specifications remain authoritative for shared semantics.
