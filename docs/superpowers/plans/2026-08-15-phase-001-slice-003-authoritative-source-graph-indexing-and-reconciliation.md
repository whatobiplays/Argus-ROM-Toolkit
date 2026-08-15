# Phase 001 Slice 003 — Authoritative Source Graph Indexing and Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make repeat local-library scans authoritatively maintain the persistent `SourceEntry` graph: update current observations, preserve identity only with unambiguous provider-native continuity, and remove prior entries only from exact scopes that completed with valid destructive authority.

**Architecture:** Keep Slice 002's Rust/SQLite authority, runtime-owned background manager, LocalFilesystem provider boundary, and incremental positive-observation checkpoints. Extend the application indexer with a two-phase reconciliation model: discovery first records positive observations and which exact scopes completed authoritatively; destructive reconciliation is deferred until discovery has seen all available observations, then completed scopes are finalized with fresh configuration-authority checks. This avoids traversal-order-dependent move deletion while preserving partial-scan authority for individually completed scopes. No durable staging/tombstone subsystem is introduced.

**Tech Stack:** Rust workspace, rusqlite/SQLite migrations and repositories, existing `ApplicationRuntime`/`BackgroundOperationManager`, LocalFilesystem provider, existing bridge/client contracts only where current root/job projections must reflect corrected backend truth, `just` validation.

## Global Constraints

- Slice 003 only: implement authoritative source-graph reconciliation for repeat scans; do not activate hierarchy UI/API, Add & Scan, Scan Again UI, Retry, Scan All, cancel-and-remove orchestration, or restart recovery.
- Preserve the Slice 002 runtime/background-operation architecture; no second runtime, database, event stream, worker authority, or provider traversal path.
- Positive observations remain incrementally durable and survive later `Partial`, `Failed`, `Cancelled`, or `Abandoned` termination.
- Absence authority exists only for an exact scope whose enumeration outcome is `Complete`, whose current root/source/policy authority still matches the frozen scan plan, and whose coherent finalization transaction commits successfully.
- Use **deferred exact-scope finalization**: discovery records completed scopes first; move reconciliation and absence deletion happen only after discovery has seen all available observations, so traversal order cannot erase a move candidate before its new observation is known.
- A partially successful overall scan may still finalize exact scopes that individually completed authoritatively. Incomplete scopes never infer absence.
- Phase 001 move preservation uses only unambiguous stable provider-native identity. `ContentIdentity` is inactive; filename/path/timestamp/size/fingerprint heuristics must never preserve `SourceEntryId`.
- Provider-native identity is not globally or per-root unique by schema contract. A native-identity lookup may return zero, one, or multiple candidates; only exactly one eligible match preserves identity. Ambiguity falls back to creation plus later authoritative removal.
- Do not add a unique constraint on provider-native identity. Add only lookup indexes required for bounded reconciliation.
- Provider I/O remains outside write transactions. Destructive finalization transactions operate only on already-established provider facts plus bounded persistence reads.
- Before each destructive finalization, recheck current source/root configuration and discovery-policy authority. Incompatible authority suppresses deletion and forces the scan to `Partial` rather than falsely `Complete`.
- Cancellation never grants absence authority. If cancellation arrives while a coherent finalization transaction is committing, that transaction completes atomically; no additional destructive finalization begins after cancellation is observed.
- Root-level successful access contributes `Available` evidence. Root-level unavailability remains distinct from nested scope failures; cancellation alone never changes availability.
- LocalFilesystem link-like entries are retained as `LinkLike` and never traversed. Boundary validation must not canonicalize/follow a link target in a way that turns an in-root link to an outside target into a failed scope merely because the target is outside the root.
- Events remain post-commit invalidation/progress hints. No Flutter or event-payload state authority is introduced.
- No new dependency unless the approved existing toolchain cannot express a required governed contract.
- Tests use only test-owned temporary trees and application data. Never touch a developer ROM library or user data.
- Do not stage, commit, push, or rewrite Git history during delegated implementation unless separately authorized by Daniel.

---

### Task 1: Reconciliation repository contracts and source-entry state model

**Files:**
- Modify: `rust/crates/argus-application/src/jobs.rs`
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Modify: `rust/crates/argus-application/src/sources/library.rs`
- Test: `rust/crates/argus-application/tests/jobs.rs`
- Test: `rust/crates/argus-application/tests/slice_002_contract.rs`
- Create or extend: focused Slice 003 application tests under `rust/crates/argus-application/tests/`

**Interfaces:**
- Consumes: `SourceEntryId`, `ScanRunId`, `LibraryRootId`, `NewSourceEntry`, opaque `SourceLocatorKey`, optional provider-native identity, frozen `LibraryScanExecutionPlan` revisions.
- Produces: repository/query operations sufficient to load exact-scope prior children, find native-identity candidates within one root, update an existing entry at a new locator/parent while preserving `SourceEntryId`, delete one authoritative subtree, and re-read current root configuration authority before destructive finalization.

- [ ] Add failing application tests that define the reconciliation port behavior: exact locator observations keep identity, one unambiguous native-identity match can move/reparent an existing entry, multiple native-identity matches are ambiguous, exact-scope prior children can be enumerated without loading the whole tree, and subtree deletion is explicit rather than accidental whole-root replacement.
- [ ] Verify the focused tests fail against the Slice 002 repository contract.
- [ ] Extend `SourceEntryRepository`/related application contracts with the smallest typed operations required by those tests. Keep provider locators opaque; generic application code may compare provider-produced keys/identity tokens but must not parse filesystem strings.
- [ ] Add an authority-check seam that lets finalization compare the frozen scan plan's source/root/policy revisions to current authoritative configuration immediately before destructive mutation. Reuse current configuration projections where possible instead of inventing duplicate state.
- [ ] Run the focused application tests and existing Slice 002 contract tests; they must pass without broadening public bridge/frontend APIs.

### Task 2: Additive SQLite reconciliation support

**Files:**
- Create: `rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0004_source_reconciliation.sql`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/migrations/mod.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`
- Modify if needed: `rust/crates/argus-infrastructure/src/sqlite/sources.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/unit_of_work.rs`
- Test: `rust/crates/argus-infrastructure/tests/jobs.rs`
- Test: `rust/crates/argus-infrastructure/tests/sources.rs`
- Test: `rust/crates/argus-infrastructure/tests/sqlite_kernel.rs`

**Interfaces:**
- Consumes: Task 1 repository operations and existing `source_entry` rows from migration 0003.
- Produces: bounded indexed lookups for `(library_root_id, parent_source_entry_id)`, `(library_root_id, provider_native_identity)` when identity is non-null, current locator-key lookup, identity-preserving move/update, and recursive/coherent subtree removal.

- [ ] Write failing persistence tests for Phase 001 upgrade from migration 0003 to the new schema support, including existing rows surviving unchanged.
- [ ] Add a **non-unique** partial/indexed native-identity lookup suitable for one-root candidate matching; do not assert uniqueness because hard links or provider ambiguity can legitimately produce duplicate tokens.
- [ ] Implement repository reads that return all candidate rows needed to decide whether native continuity is zero/unique/ambiguous, with stable bounded ordering.
- [ ] Implement identity-preserving row relocation/update by `SourceEntryId`, including parent, locator key, relative locator, display facts, kind/classification, fingerprint/native identity, `last_observed_scan_id`, and `updated_at`.
- [ ] Implement coherent subtree deletion for one already-authorized absent entry. Descendants must be removed with the parent; no user filesystem mutation occurs.
- [ ] Verify migration, repository recreation, constraints, and all existing Slice 002 job/root history tests pass.

### Task 3: Rework LibraryScan discovery into deferred exact-scope finalization

**Files:**
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Test: create or extend focused indexer tests under `rust/crates/argus-application/tests/`
- Test: `rust/crates/argus-runtime/tests/sources.rs`

**Interfaces:**
- Consumes: Task 1/2 repository capabilities, `EnumerationOutcome`, `SourceObservation`, frozen plan revisions, cancellation callback, progress reporter, post-commit event sink.
- Produces: discovery-time positive reconciliation plus an in-memory bounded worklist of exact scopes that actually completed and may later be finalized.

- [ ] Add failing tests proving completed-scope absence deletion is deferred until discovery has seen all observations; a move from an earlier-traversed scope to a later-traversed scope must not be deleted before native-identity matching can preserve it.
- [ ] Add failing tests proving an overall `Partial` scan can still finalize an unrelated exact scope that completed, while the failed/incomplete scope and its descendants retain prior state.
- [ ] Replace the Slice 002 locator-key-only `upsert` decision with application-owned positive reconciliation: exact locator match updates in place; otherwise, exactly one eligible native-identity candidate within the root preserves the old `SourceEntryId`; zero or multiple candidates create a new entry.
- [ ] Record completed exact scopes only when enumeration returns `Complete`. `Partial`, `Failed`, `Unavailable`, and `Cancelled` scopes are never added to the destructive-finalization worklist.
- [ ] Preserve the existing incremental checkpoint model and post-commit `SourceEntriesChanged` notifications. Do not accumulate the entire source graph in memory; retain only bounded per-observation/checkpoint facts plus the completed-scope descriptors required for finalization.
- [ ] After traversal has consumed all reachable observations, iterate the completed-scope worklist and finalize each scope only after cancellation and authority checks. Each finalization identifies prior direct children not observed by this scan, excludes entries already preserved/moved by current positive evidence, and removes unmatched absent subtrees in a coherent transaction.
- [ ] If current plan authority is incompatible before a scope finalizes, skip destructive mutation for that scope and ensure the root scan terminal result is `Partial`.
- [ ] If cancellation is observed before starting a finalization, stop starting new destructive work and finish `Cancelled`. Never roll back already committed positive observations or a finalization transaction already in progress.
- [ ] Run focused application/runtime tests; verify complete rescans delete only authorized absences and incomplete/cancelled scans never do.

### Task 4: Prove conservative move semantics and fixed policy behavior

**Files:**
- Modify: `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs`
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Test: add/extend LocalFilesystem integration tests under `rust/crates/argus-infrastructure/tests/`
- Test: add/extend indexer tests under `rust/crates/argus-application/tests/`

**Interfaces:**
- Consumes: provider-native identity emitted by LocalFilesystem where the current implementation can cleanly guarantee it; `ObservedEntryKind`; fixed Phase 001 classification table.
- Produces: trustworthy move evidence only, correct link-like retention/no-follow behavior, and deterministic Phase 001 kind/classification mapping during rescans.

- [ ] Add a temporary-tree test for a rename/move on a platform where stable native identity is available; the second scan must preserve `SourceEntryId` while updating parent/location.
- [ ] Add an ambiguity test using duplicate provider-native identity candidates through a fake/application-level provider seam; verify identity is **not** guessed and the result becomes creation plus authoritative removal when scope completion permits it.
- [ ] Add negative tests proving filename, display path, size, modified time, and fingerprint alone never preserve identity.
- [ ] Add LocalFilesystem tests proving symlink/link-like entries are observed as `LinkLike`, retained, never traversed, and do not fail the containing scope solely because their target resolves outside the root.
- [ ] Correct the current namespace/boundary check so it validates traversal targets without following link-like observations. Continue rejecting actual traversal requests that escape the resolved-root namespace.
- [ ] Verify hidden/system ordinary entries continue to follow structural mapping with no new include/exclude behavior and no archive/content semantic refinement.

### Task 5: Root availability, terminal aggregation, events, and restart-safe persisted graph

**Files:**
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Modify as needed: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`
- Modify as needed: `rust/crates/argus-runtime/src/runtime.rs`
- Test: `rust/crates/argus-runtime/tests/sources.rs`
- Test: `rust/crates/argus-infrastructure/tests/jobs.rs`

**Interfaces:**
- Consumes: completed/partial/failed/cancelled reconciliation outcomes and current root projections.
- Produces: correct `LibraryRoot.availability`, last-scan summary, `ScanRun` terminal status, generic `JobRun` terminal status, and post-commit invalidations after reconciliation mutations.

- [ ] Add failing tests that successful root resolution/enumeration updates availability evidence to `Available`, while nested failure leaves root availability independent and cancellation alone does not mark it unavailable.
- [ ] Verify `Complete` requires all required scopes authoritative and all destructive finalization still authorized; incompatible authority becomes `Partial` even if discovery itself enumerated successfully.
- [ ] Verify `Partial` retains useful committed work; `Failed` remains reserved for no meaningful indexing result; root-level unavailable still maps `ScanRun=Failed` plus root last-scan/availability `Unavailable`.
- [ ] Ensure every identity-preserving move and authoritative subtree deletion emits `SourceEntriesChanged` only after commit. Root summary/availability changes emit `LibraryRootChanged` only after commit. Do not introduce a competing scan-completed lifecycle event.
- [ ] Recreate the SQLite/runtime query layer after a successful rescan and verify the reconciled graph plus terminal root/job history remain durable. Do not implement stale-active startup recovery here.

### Task 6: Slice 003 verification and scope hardening

**Files:**
- Modify only if required: architecture/contract tests already inside authorized implementation-test paths.
- Update: `docs/superpowers/plans/2026-08-15-phase-001-slice-003-authoritative-source-graph-indexing-and-reconciliation.md` only if implementation uncovers a factual plan correction that remains within governed scope.

**Interfaces:**
- Consumes: completed Tasks 1–5.
- Produces: evidence that Slice 003 satisfies PHASE-001/SPEC-BE-011/SPEC-BE-013 without leaking Slice 004+ behavior.

- [ ] Run focused Rust tests for application reconciliation, SQLite migration/repositories, LocalFilesystem provider behavior, and runtime LibraryScan execution.
- [ ] Run `just generate` only if generated-contract inputs changed, then `just check-generated`; there must be no hand-edited generated output.
- [ ] Run the repository's canonical `just check` gate and `git diff --check` equivalent through the approved repository validation workflow.
- [ ] Confirm no new Flutter hierarchy route/controller/widget, source-entry child-page bridge API, Add & Scan, Scan Again UI, Retry, Scan All, cancel-and-remove workflow, or restart recovery was implemented.
- [ ] Confirm no unique provider-native-identity constraint or content/path/filename heuristic was introduced.
- [ ] Write the bound Delegation v3 `RESULT.json` truthfully with all TAC evidence, changed paths, tests, and any blocker/scope-extension request. Do not claim deferred manual verification passed.

## Self-Review

- Spec coverage: covers SPEC-BE-011 incremental reconciliation, `last_observed_scan_id`, conservative move tiers, exact-scope finalization, stale-plan suppression, availability mapping, transaction boundaries, link/no-follow semantics, cancellation, and event-after-commit behavior needed by SLICE-P01-003.
- Scope boundary: hierarchy presentation remains Slice 004; full interaction/retry remains Slice 005; Scan All/removal orchestration/restart recovery remain Slice 006.
- Type consistency: the plan extends existing `SourceEntryRepository`, `LibraryScanExecutionPlan`, `LibraryRootQueries`, `ScanRunRepository`, and `LibraryScanOperationHandler` rather than introducing a parallel indexing subsystem.
- No placeholders remain. Implementation details deliberately left flexible are internal mechanics that do not change the approved authority model.
