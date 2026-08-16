# Phase 001 Local Sources and Indexing — Completion Verification

**Document ID:** IMPL-P01-007-VERIFICATION
**Owner:** Daniel
**Last Updated:** 2026-08-15
**Status:** Active verification record for SLICE-P01-007
**Depends On:** PHASE-001, SPEC-BE-011, SPEC-BE-013, SPEC-FE-008, SPEC-FE-009, CONV-TEST-001
**Supersedes:** None
**Superseded By:** None

## Purpose

This document records the reproducible verification procedure for the final
Phase 001 implementation slice (Slice 007). It distinguishes automated gates
that are portable from those that are platform-native, maps automated evidence
to the Phase 001 exit criteria, and requires every evidence slot to be filled
only after the corresponding check has actually been executed. Manual checks
that have not been executed remain `NOT RUN`.

## Automated Completion Gates

Run these commands from the repository root in the order shown. The native
gates are intentionally outside the platform-neutral gate.

| Command | Portable | What it proves |
| --- | --- | --- |
| `just generate` | Yes | Regenerates all canonical FRB/Riverpod/Freezed output through the repository's generation commands. |
| `just check-generated` | Yes | Registered generated files are current and reproducible, no unexpected generated output exists, and no machine-local absolute path appears in generated FRB output. |
| `just check` | Yes | The platform-neutral quality gate passes: formatting, lint/static analysis (including ShellCheck), Rust dependency architecture checks, and the full deterministic offline Rust/Flutter test suite. It has no dependency on native desktop/E2E gates. |
| `just test-local-filesystem-native` | Yes (runs real native filesystem semantics on the host OS) | The complete `argus-infrastructure` package test suite with locked/all-feature inputs, including the real LocalFilesystem provider evidence in `tests/sources.rs`, `tests/jobs.rs`, `tests/scan_reconciliation.rs`, and the new `tests/local_filesystem_contract.rs` cross-platform contract tests. |
| `just test-phase-000-native` | No (macOS) | The Phase 000 native milestone passes: locked bridge rebuild, native bridge smoke, native startup-failure/recovery/diagnostics smoke, and the real two-process restart-restoration proof. |
| `just test-phase-001-native` | No (macOS) | The Phase 001 native milestone passes: the canonical Sources/Jobs composition proof and the real two-process restart-recovery proof against test-owned state. |

`just check` does not include `just test-phase-000-native` or
`just test-phase-001-native`. Windows/Linux provider evidence comes from the
dedicated CI jobs that execute `just test-local-filesystem-native` on
`windows-latest` and `ubuntu-24.04`; macOS CI executes both native milestones.

## Evidence Mapping to Phase 001 Exit Criteria

| Exit-criterion family | Evidence |
| --- | --- |
| Generated output (26) | `just generate` + `just check-generated` pass; no generated output outside the registered set; no machine-local path leakage. |
| Architecture (27) | `flutter/test/architecture/architecture_boundaries_test.dart` mechanically rejects Flutter filesystem authority, provider-native contract leakage, feature-owned native event streams, event-payload state authority, duplicate Sources/Jobs authority, and Phase 002+ concepts. |
| LocalFilesystem behavior on Windows/Linux/macOS (22, 24) | `just test-local-filesystem-native` (complete `argus-infrastructure` suite) on the platform-neutral gate and dedicated Windows/Linux CI jobs; contract tests cover root validation/relationships, resolve/enumeration, link-like boundaries, missing/inaccessible roots, error mapping, cancellation before and during enumeration, and native identity (Unix stable, non-Unix `None`). |
| Add & Scan (2, 4, 5) | macOS milestone: Add & Scan through the real flow with an injected picker selection; durable job admission and terminal state; root preserved. |
| Hierarchy (7, 12) | macOS milestone: the real Sources hierarchy browser renders representative committed entries (one directory, one file) after Add & Scan; authoritative `SourcesApi` reads carry the exact identity/kind/reconciliation assertions. Exhaustive hierarchy behavior remains owned by the lower-level hierarchy controller/persistence tests. |
| Scan Again and reconciliation (8) | macOS milestone: added entry appears, removed entry disappears only after authoritative completed reconciliation. |
| Move reconciliation (9) | macOS milestone: moved entry preserves its `SourceEntryId` through provider-native Unix move evidence. |
| Scan All (6) | macOS milestone: one durable job with two independent per-root outcomes; each root's hierarchy matches only its own fixture. |
| Cancellation (16) | macOS milestone: cooperative cancellation reaches durable `Cancelled`; committed positive observations remain; no absence authority. |
| Restart recovery / no auto-resume (18) | macOS milestone restart proof: the harness makes the configured library root path unavailable before the verify launch; verify still reaches `Ready` and asserts the exact Slice 006 `Abandoned` recovery, cleared active ownership, surviving committed observations (read from the test-owned SQLite data), unchanged persisted root availability, no new admission, and no automatic resume. Because the root path is absent, reaching `Ready` and reconciling proves startup recovery performs no provider resolution/enumeration. The lower-level Slice 006 Rust recovery tests (`argus-runtime`/`argus-infrastructure`) remain the complementary deterministic evidence for the persistence-only reconciler. |
| Safe root removal (19, 20) | macOS milestone: removed root leaves active Sources state; test-owned files unchanged; terminal job/scan history remains intelligible. |
| Phase 000 preservation (25) | `just test-phase-000-native` remains an explicit native regression gate in CI and locally. |
| Platform-neutral gate (29) | `just check` passes without any native-gate dependency. |
| No Phase 002+ capability (30) | Architecture guard rejects game-content parsing, hashing, metadata/artwork, RetroAchievements, filesystem watching, additional providers, and related families in production sources. |
| Truthful evidence (31) | This record and the bound `RESULT.json` report only executed evidence; manual slots below remain `NOT RUN`. |

## Implementation Notes

- The macOS milestone drives workflow actions through the same application
  controllers and focused client APIs the UI controls invoke. Pointer-level
  taps are used for navigation, the add-folder flow dialogs, and the
  job-detail view button; bottom-row controls are controller-driven because
  macOS native hit-testing of those controls is not reliable in the test
  harness. All waits synchronize on authoritative backend state.
- Hierarchy presentation is exercised directly: after Add & Scan, the native
  test waits for the real hierarchy browser to display one committed directory
  and one committed file; all exact semantics remain authoritative-API
  assertions. This supplements, and does not duplicate, the lower-level
  hierarchy controller tests.
- Restart provider-I/O evidence: after the seed process terminates, the
  harness moves the configured library root aside so the verify process
  launches against an absent root path. Verify reaches `Ready` and reconciles
  the stale job to `Abandoned`, which proves startup recovery does not resolve
  or enumerate the provider. Committed observations are asserted from the
  persisted SQLite state, never by touching the filesystem. The harness
  cleanup protocol removes both the original and moved fixture paths.
- The milestone exposed and Slice 007 fixed one genuine expanded-layout
  defect: the Sources root sidebar's animated width transition laid out
  expanded `ListTile`s at too-narrow widths. The animation was removed and a
  focused widget regression added in `sources_feature_test.dart`.
- The restart seed writes a test-owned sentinel only after durable Running;
  the harness treats a missing sentinel as an accidental seed failure and the
  presence of the sentinel as the expected intentional interruption.

## Manual Milestone Evidence Slots

The following Phase 001 requirements are not yet automated by this slice.
Each slot must be recorded as exactly one of `PASS`, `FAIL`, `NOT RUN`, or
`BLOCKED` when the check is executed. An unexecuted check is `NOT RUN`; it
must never be pre-marked as passing.

| Evidence slot | What to execute | Status |
| --- | --- | --- |
| Keyboard walkthrough | Keyboard-only traversal of startup, shell, Sources, Add Library Folder, hierarchy browsing, Scan Again, Scan All, Jobs detail, cancellation, and removal surfaces. | NOT RUN |
| Screen-reader smoke | Screen-reader smoke test of the canonical Phase 001 surfaces. | NOT RUN |
| Reviewed visual evidence | Selective visual review of Sources/Jobs surfaces at compact, medium, expanded, and large widths. | NOT RUN |
| Large text/display scaling | 200% text-scaling and display-scaling checks on the essential Phase 001 surfaces. | NOT RUN |
| Exploratory filesystem verification | Manual exploration of real filesystem behavior beyond the automated provider tests. | NOT RUN |

## Phase Boundary

Slice 007 is the seventh and final implementation slice of Phase 001. Passing
Slice 007 transitions Phase 001 to a separate closeout review against all 31
phase exit criteria. A closeout review that finds only deferred manual
evidence does not justify an invented Slice 008; a new implementation slice
would require a demonstrated implementation defect or an approved contract
change.
