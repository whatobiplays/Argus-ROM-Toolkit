# Reported Issue Audit and Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the reported defects against the current Argus ROM Toolkit implementation, fix every confirmed defect with regression coverage, and document any report that is not applicable.

**Architecture:** Keep the existing application/infrastructure/runtime boundaries. Make safety fixes at the layer that owns the invalid state: parsers enforce bounded work and format invariants, infrastructure preserves I/O and staging semantics, application preserves identity and admission evidence, and runtime carries already-resolved relationships. Use focused helpers only where the existing implementation duplicates the same admission logic.

**Tech Stack:** Rust 1.97.1, Cargo workspace, SQLite persistence, CHD/CSO/RVZ/WBFS/archive adapters, repository contract tests, Markdown specifications.

## Global Constraints

- Preserve the existing public behavior and error vocabulary unless a reported defect requires a more accurate existing error classification.
- Every production behavior change must have a regression test that fails against the pre-fix implementation before the fix is applied.
- Keep filesystem and parser work bounded by the existing parser-work, expansion, cancellation, and staging budgets.
- Do not expose raw source locators or weaken source stability checks while repairing identity or dependency handling.
- Keep changes minimally scoped; do not redesign the persistence or runtime architecture.
- Run Cargo commands with the repository-pinned Rust 1.97.1 compiler.

---

### Task 1: Mechanical test, documentation, and dependency corrections

**Files:**
- Modify: `rust/crates/argus-application/tests/content_contract.rs`
- Modify: `rust/crates/argus-infrastructure/tests/content_session.rs`
- Modify: `rust/crates/argus-infrastructure/tests/archive_content.rs`
- Modify: `rust/crates/argus-infrastructure/tests/chd_content.rs`
- Modify: `docs/architecture/architecture-overview.md`
- Modify: `docs/superpowers/plans/2026-08-26-containers-and-compressed-representations.md`
- Modify: `rust/Cargo.toml` and `rust/Cargo.lock` only if the dependency audit confirms a compatible maintained lock crate can replace `fs2`

**Interfaces:** No new runtime interfaces. The test and documentation changes must reflect current production contracts, including exclusion of RAR from Phase 003 and explicit enter/leave container depth accounting.

- [x] **Step 1: Confirm each mechanical report against the current lines and dependency graph.**
- [x] **Step 2: Remove only duplicate assertions, dead test state, and unused reader state; correct the low-space fixture so it reaches the available-space branch.**
- [x] **Step 3: Update the architecture and plan documents to agree with the implemented RAR deferral, container state-machine API, and decoder feature pins.**
- [x] **Step 4: Resolve the `fs2` report by either adopting the smallest compatible maintained lock dependency or recording a justified pin if replacement would change the supported behavior.**
- [x] **Step 5: Run the affected contract tests and documentation consistency checks.**

### Task 2: Application identity, dependency admission, and runtime accounting

**Files:**
- Modify: `rust/crates/argus-application/src/sources/derived.rs`
- Modify: `rust/crates/argus-application/src/optical.rs`
- Modify: `rust/crates/argus-application/src/logical.rs`
- Modify: `rust/crates/argus-application/src/phase_003.rs`
- Modify: `rust/crates/argus-runtime/src/lib.rs`
- Modify or create focused tests under `rust/crates/argus-application/tests/` and `rust/crates/argus-runtime/tests/`

**Interfaces:** Preserve the existing `SourceVersionEvidence`, `ProcessedContentCandidate`, optical dependency resolver, and `SourceTreeResult` contracts unless a field is proven dead. Derived timestamps must come from the existing runtime/application clock convention or a narrowly introduced timestamp parameter, and resolved optical dependency IDs must travel with the processed candidate to grouping.

- [x] **Step 1: Add failing tests for subquadratic archive-family admission, nonzero derived timestamps/update timestamps, drive-qualified optical references, derived fingerprint round-tripping, dependency-aware grouping, and single-count transformation failures.**
- [x] **Step 2: Add one shared optical admission loop parameterized by the candidate match predicate and reject drive-qualified references before relative normalization.**
- [x] **Step 3: Replace linear uniqueness scans with a hash-based admission set while preserving first-seen ordering and equality semantics.**
- [x] **Step 4: Preserve derived evidence through convergence, propagate real timestamps, carry resolved dependency IDs, remove or populate dead playlist plumbing, and map/read-count transformation failures using the existing error catalog.**
- [x] **Step 5: Run the focused application/runtime tests and then the affected integration tests.**

### Task 3: Source stability, startup cleanup, staging, and container dispatch safety

**Files:**
- Modify: `rust/crates/argus-runtime/src/startup.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_session.rs`
- Modify: `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_stream.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_source.rs`
- Modify or create focused tests under `rust/crates/argus-runtime/tests/` and `rust/crates/argus-infrastructure/tests/`

**Interfaces:** Preserve the current operation-marker and cleanup APIs where possible. Startup cleanup must not remove live work owned by another runtime, incomplete markers must be recoverable, provider handles without a current fingerprint must not reuse persisted evidence, and all `SourceReadHandle` counts must be bounded by the destination slice.

- [x] **Step 1: Add failing tests for concurrent startup cleanup, crash-window marker cleanup, same-length rapid rewrites, missing current fingerprints, invalid source-read counts, preserved read failures, and container-source dispatch exclusion.**
- [x] **Step 2: Implement ownership/liveness protection and recoverable marker handling with the smallest existing lock or marker protocol extension.**
- [x] **Step 3: Use a non-truncated native change marker or byte validation for local file stability, preserve I/O errors as `ReadFailure`, reject invalid adapter counts, and restore the complete container guard.**
- [x] **Step 4: Run the focused source/session/runtime tests and inspect cross-process cleanup behavior.**

### Task 4: Recursive derived-subtree cleanup

**Files:**
- Modify: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`
- Modify or extend: `rust/crates/argus-infrastructure/tests/reconciliation.rs` and related source-tree tests

**Interfaces:** `finalize_sources` must remove stale derived roots and all authoritative descendants in one transaction without crossing library-root boundaries.

- [x] **Step 1: Add a failing nested-container disappearance test that leaves a grandchild when only the direct stale row is deleted.**
- [x] **Step 2: Collect stale roots and pass their full authoritative subtree to the existing transactional deletion path.**
- [x] **Step 3: Run reconciliation and hierarchy tests.**

### Task 5: Archive member persistence and TAR field validation

**Files:**
- Modify: `rust/crates/argus-infrastructure/src/content_archive.rs`
- Modify or extend: `rust/crates/argus-infrastructure/tests/archive_content.rs`

**Interfaces:** Empty non-directory 7z entries must reopen through operation staging, and TAR octal fields must reject any non-NUL/non-space trailing byte after the digit sequence.

- [x] **Step 1: Add failing tests for reopening an empty 7z file member and rejecting octal fields with trailing non-whitespace bytes.**
- [x] **Step 2: Stage zero-byte members and tighten numeric-field validation without changing accepted valid archives.**
- [x] **Step 3: Run archive tests and the archive-library convergence tests.**

### Task 6: Format parser bounds, metadata, and canonical reconstruction

**Files:**
- Modify: `rust/crates/argus-infrastructure/src/content_chd.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_cso.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_rvz.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_wbfs.rs`
- Modify or extend: `rust/crates/argus-infrastructure/tests/chd_content.rs`, `cso_content.rs`, `rvz_content.rs`, and `wbfs_content.rs`

**Interfaces:** Keep canonical identities stable for valid inputs while rejecting malformed metadata and bounding all decompression/table work before excessive allocation or hashing.

- [x] **Step 1: Add failing format-specific tests for CHD work accounting and pregap mode/boundaries, aligned CSO spans, bounded RVZ LZMA2 output and generated-word reconstruction, and large-valid/zero-WLBA/work-budget WBFS layouts.**
- [x] **Step 2: Implement the smallest parser-local fixes that enforce these invariants before committing identity evidence.**
- [x] **Step 3: Run all format-specific tests plus the shared content-recognition suite.**
