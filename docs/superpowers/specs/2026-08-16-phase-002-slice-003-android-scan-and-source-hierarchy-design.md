# Phase 002 Slice 003 — Android Scan and Source Hierarchy Design

## Status

Approved slice design for `SLICE-P02-003`.

This document refines the already-approved Phase 002 Android first-class platform design for the specific Slice 003 boundary. It does not replace the phase plan or backend/frontend specifications.

## Binding references

- `docs/phases/phase-002-android-first-class-platform-support.md`
- `docs/superpowers/specs/2026-08-15-phase-002-android-first-class-platform-support-design.md`
- `docs/specifications/backend/spec-be-011-source-provider-and-indexing-contract.md`
- `docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md`
- `docs/specifications/frontend/spec-fe-008-sources-and-library-folder-management.md`
- `docs/specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md`
- Phase 001 scan/reconciliation/hierarchy/interaction contracts and their completed implementation
- Phase 002 Slice 002 Android LocalFilesystem and Argus folder-picker implementation

## Goal

Activate the existing Phase 001 single-root scan, reconciliation, hierarchy, and Jobs workflows on Android using the Slice 002 Android LocalFilesystem provider and Argus folder picker.

Slice 003 is an activation/integration slice, not a new scan architecture. Android must execute the same authoritative `LibraryScan` model as desktop wherever the capability is applicable.

## Chosen approach

Reuse the Phase 001 scan stack unchanged in authority and semantics.

Android `LocalFilesystem` resolves its persisted volume-relative root locator through the current mounted-volume registry, then the existing `LibraryScan` pipeline owns traversal, reconciliation, hierarchy state, JobRun/ScanRun state, progress, cancellation, retry, and events.

Do not introduce an Android-specific scan coordinator, scheduler, persistence model, or hierarchy authority.

## Slice boundary

### Activated in P02-003

- Add & Scan from the Android Argus folder picker.
- Scan for an eligible never-scanned root.
- Scan Again for an eligible previously scanned root.
- Existing single-root `LibraryScan` execution.
- Existing authoritative source reconciliation and hierarchy inspection.
- Existing single-root Jobs progress, cancellation, retry, history, and navigation where backend-authorized.
- Android-native source-entry move behavior only through the existing trustworthy provider-native identity rules.

### Explicitly deferred

- Scan All and Android multi-root scan orchestration remain P02-005.
- Safe active-root cancel-and-remove coordination remains P02-005.
- Full restart-recovery/permission-regrant/removable-media coverage across all applicable capabilities remains P02-005.
- Foreground service hosting, screen-off/background continuation, Activity detach/reattach hardening, native notification controls, OS interruption handling, and process-death execution continuity remain P02-004.
- Adaptive Android UX hardening remains P02-006.

The current P02-002 `scanExecution` presentation gate must therefore be refined so Android can enable single-root scan controls while keeping Scan All hidden.

## Architecture

1. Android keeps using the P02-002 mounted-volume synchronization path before provider-dependent operations.
2. Add & Scan, Scan, and Scan Again call the existing Phase 001 application/runtime APIs. No Android-specific scan API is added.
3. `LocalFilesystem::open_access()` resolves the persisted Android root locator against the current mounted-volume registry and supplies the existing `LibrarySourceAccess` implementation to `LibraryScan`.
4. Existing reconciliation remains authoritative: incremental positive observations, exact-scope absence finalization, conservative move preservation, hierarchy projections, and event-after-commit behavior.
5. Existing Jobs remains authoritative for progress, cancellation, retry, and history.
6. Flutter presentation capability must distinguish single-root scan execution from Scan All exposure. Android enables the former and disables the latter; desktop behavior remains unchanged.
7. No Android-specific scheduler, second runtime, second database authority, foreground service, WorkManager task, wake lock, auto-resume mechanism, or duplicate hierarchy state is introduced.

## User-visible behavior

### Add Library Folder

Android continues to use the Argus-owned folder browser from P02-002.

The confirmation flow exposes:

- **Add & Scan** as the primary scan-enabled action.
- **Add Without Scanning** as the non-scanning alternative.

Add & Scan preserves the existing committed-root-then-child-admission contract: root creation commits first, then child scan admission is attempted. Scan-admission failure never rolls back or deletes the newly configured root.

### Root detail

- Eligible never-scanned root: show **Scan**.
- Eligible previously scanned root: show **Scan Again**.
- Active scan: show the existing active-scan summary and **View Job** behavior.
- Unavailable Android root: do not admit a new scan until current availability is restored.

### Source hierarchy

The existing hierarchy UI becomes usable for Android roots. It reads the same authoritative indexed source-entry graph used on desktop and introduces no Android-only hierarchy cache or state model.

### Jobs

Existing single-root Jobs behavior is enabled unchanged on Android:

- active and recent history;
- structured progress;
- cancellation when backend-authorized;
- retry for eligible terminal attempts;
- navigation between Sources and Jobs.

Jobs remains query-authoritative. Android native state must not become a second source of job truth.

### Scan All

Scan All remains hidden on Android throughout P02-003, even though the shared Phase 001 backend already supports it. P02-005 owns Android Scan All activation and multi-root coverage.

## Data flow and reconciliation authority

1. Before Add & Scan, Scan, or Scan Again, Android refreshes the mounted-volume snapshot through the existing P02-002 gateway/platform path.
2. If the refresh cannot establish trustworthy current mount facts, scan admission must not proceed against stale mount data.
3. Scan admission creates the existing immutable `LibraryScanExecutionPlan` and uses existing JobRun/ScanRun identities.
4. `LocalFilesystemSourceAccess` resolves the configured Android locator through the current mounted-volume registry.
5. Filesystem/provider I/O remains outside SQLite write transactions.
6. Positive observations commit incrementally at coherent checkpoints.
7. A fully completed exact scope may perform authoritative absence reconciliation.
8. Partial, failed, cancelled, unavailable, abandoned, or otherwise incomplete scopes never infer absence from unseen entries.
9. Positive observations committed before an interrupted or failed terminal outcome remain valid.

## Android native identity and move preservation

The current LocalFilesystem implementation emits Unix native identity from filesystem device/inode metadata on Unix platforms, including Android.

P02-003 does not create a second Android identity mechanism. Instead it verifies and, if necessary, appropriately namespaces or narrows the existing provider-native identity behavior.

The binding rules are:

1. Preserve an existing `SourceEntryId` across a move only when exactly one trustworthy provider-native identity match exists in the relevant source/root scope.
2. Never synthesize native identity from path, filename, size, timestamp, or other heuristics.
3. If the underlying Android filesystem cannot provide sufficiently stable continuity, omit or narrow native identity rather than claim a guarantee the provider cannot support.
4. If required to prevent cross-volume collisions, provider-native identity may be namespaced with stable provider-volume identity without changing the application-level reconciliation model.
5. When trustworthy identity is unavailable or ambiguous, an apparent move becomes removal plus creation only after an authoritative completed scope establishes absence.

## Failure and removable-media behavior

- Global All files access loss preserves configured roots, indexed entries, Jobs/ScanRun history, and settings. New Android storage scans are not admitted while platform readiness is unmet.
- Permission loss is not root deletion and is never fresh absence evidence.
- If configured removable media disappears during a scan, the affected scope terminates through existing typed failure/unavailable/interruption semantics and receives no destructive absence-finalization authority.
- Already committed positive observations remain valid.
- A trustworthy remount of the same provider-native volume/root restores availability under the existing `LibraryRootId`; it does not silently create a replacement root.
- Root removal remains Argus configuration/index removal only and never mutates user files.

## Persistence and schema

P02-003 should reuse the existing Phase 001 persistence model and P02-002 stable root locator model. No database migration or parallel Android scan schema is expected.

If implementation proves that a schema migration is genuinely required, Codex must stop and surface a bounded scope-extension request rather than adding the migration silently.

## Testing strategy

### Existing gates

Retain all existing repository validation and milestone gates, including generation/check-generated, format/check, Phase 000/001 native coverage, and P02-001/P02-002 Android coverage.

### Provider-level Android coverage

Tests must prove:

- stable Android root locators resolve through the mounted-volume registry;
- enumeration remains bounded/no-follow and cannot escape the configured root;
- removable-volume loss maps to unavailable evidence without absence authority;
- Android native identity behavior is verified against actual platform behavior and is omitted/narrowed where continuity cannot be trusted.

### Application/reconciliation coverage

Tests must prove:

- initial single-root scan indexes nested files/directories;
- completed Scan Again can authoritatively add, update, and remove entries;
- partial, failed, cancelled, and unavailable scans preserve unseen previously indexed entries;
- one unique trustworthy native-identity match preserves `SourceEntryId` across a move;
- ambiguous or unsupported identity results in removal plus creation;
- Add & Scan retains committed-root-then-child-admission semantics.

### Flutter coverage

Tests must prove:

- Android exposes Add & Scan, Scan, Scan Again, hierarchy, and applicable single-root Jobs controls;
- Scan All remains absent on Android;
- desktop presentation remains unchanged;
- event gaps and runtime replacement continue to reconcile through authoritative queries.

## Required Android native milestone

Run on the configured ARM64 API 36 emulator and exercise the real stack:

`Flutter -> ArgusClient -> FRB -> Rust -> SQLite -> Android LocalFilesystem`

The milestone must:

1. select an Android folder through the Argus browser;
2. perform Add & Scan;
3. wait for terminal completion;
4. inspect the indexed hierarchy;
5. mutate the filesystem fixture;
6. run Scan Again;
7. verify authoritative hierarchy reconciliation;
8. exercise applicable single-root Jobs cancellation/retry behavior using deterministic synchronization rather than timing-dependent sleeps;
9. verify Scan All is not exposed;
10. verify the APK packages the supported ARM64 ABI.

## What P02-003 does not prove

P02-003 intentionally does not claim:

- background or screen-off scan continuation;
- Activity destruction/reattachment execution continuity;
- process-death execution continuity;
- Android foreground-service notification/control behavior.

Those are P02-004 acceptance concerns.

## Success criteria

P02-003 is complete when an Android user can select one local mounted folder with the Argus browser, Add & Scan it through the real shared stack, inspect the authoritative indexed hierarchy, Scan Again after filesystem changes, and use the applicable existing single-root Jobs controls, while desktop behavior remains unchanged and Android Scan All/background execution remain explicitly deferred to their owning slices.
