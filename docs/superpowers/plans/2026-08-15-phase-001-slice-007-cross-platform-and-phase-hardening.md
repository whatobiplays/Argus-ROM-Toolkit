# Phase 001 Slice 007 — Cross-Platform and Phase Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Phase 001 by proving the shipped Local Sources and Indexing capability across the real macOS composition and real Windows/Linux LocalFilesystem behavior, while hardening architecture/generated-output gates and preserving Phase 000.

**Architecture:** Extend the repository-owned verification architecture rather than replacing it. `just check` remains the deterministic platform-neutral authority; focused Rust provider tests exercise native filesystem semantics on every CI OS; a separate macOS Phase 001 native harness proves the canonical Flutter/FRB/Rust/SQLite workflow against test-owned state; GitHub Actions only orchestrates repository-owned targets.

**Tech Stack:** Rust, Cargo, LocalFilesystem provider, SQLite, Flutter/Dart, Riverpod, `integration_test`, flutter_rust_bridge, Bash, `just`, GitHub Actions.

## Global Constraints

- Implement only `SLICE-P01-007 — Cross-Platform and Phase Hardening` from `docs/superpowers/specs/2026-08-15-phase-001-slice-007-cross-platform-and-phase-hardening-design.md` and the governing Phase 001/specification contracts.
- This is the seventh and final implementation slice of Phase 001. Do not invent Slice 008 work or add Phase 002+ product capability.
- `just check` retains its current deterministic, platform-neutral meaning and must not depend on native desktop/E2E gates.
- The macOS Phase 001 native milestone is a required normal push/pull-request CI gate, not an on-demand or local-only check.
- Windows and Linux must execute real LocalFilesystem/provider behavior; compile-only evidence is insufficient.
- Do not duplicate the complete macOS Flutter E2E suite on Windows/Linux unless a concrete platform defect proves lower-layer coverage insufficient.
- Preserve the existing Phase 000 native milestone and all Phase 000 startup, recovery, diagnostics, event lifecycle, routing, settings, appearance, and restart-restoration contracts.
- Rust/SQLite remain authoritative for durable source, scan, job, and recovery state. Flutter remains a consumer of focused typed APIs and authoritative re-reads.
- Native event payloads remain invalidation hints, never application-state authority. Feature code must not own native event subscriptions.
- Flutter must not traverse or interpret the native filesystem. Provider-native path/identity semantics remain inside the LocalFilesystem provider boundary.
- Timing-sensitive native tests synchronize on durable state, explicit lifecycle signals, or observable UI/controller predicates. Arbitrary sleeps may be used only as bounded failure protection, never as the success condition.
- All test application data, databases, and library trees must be test-owned and isolated. No test may use the developer's normal Argus data or ambient library folders.
- Diagnostics and retained failure evidence must satisfy SPEC-BE-003 sanitization; do not print or persist sensitive raw user filesystem paths merely to improve test diagnostics.
- Generated FRB/Riverpod/Freezed output changes only through canonical generation. No machine-local path leakage is permitted.
- Do not weaken or delete existing Slice 001–006 tests to make hardening pass. If hardening exposes a genuine existing-contract defect, fix the owning layer and add a focused regression.
- Manual keyboard, screen-reader, visual, scaling, and exploratory filesystem verification remains `NOT RUN/deferred` unless actually executed.
- No Git index, commit/history, branch, push, restore, or other Git-state mutations. Normal implementation edits to worktree files are required and remain uncommitted.

---

### Task 1: Add explicit cross-platform LocalFilesystem contract coverage

**Files:**
- Modify only if a proven defect requires it: `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs`
- Create or modify focused `argus-infrastructure` LocalFilesystem tests using the crate's existing test layout.
- Modify `argus-application` test support only if required by a real provider/application contract defect.

**Interfaces:**
- Consumes: `LocalFilesystemProvider`, `LocalFilesystemSourceAccess`, `LocalFilesystemProviderPort`, `LibrarySourceAccess`, provider-owned locators/identity facts, and existing provider/source-access error vocabulary.
- Produces: real native-filesystem tests running on Windows, Linux, and macOS.

- [ ] **Step 1: Inventory existing provider coverage**

Locate current tests for:
- root validation and root relationships;
- root/access resolution;
- direct enumeration;
- files/directories/link-like entries;
- missing/inaccessible roots;
- cancellation;
- native identity;
- error mapping.

Add only missing Phase 001 coverage. Existing `rust/crates/argus-infrastructure/tests/sources.rs` and `tests/jobs.rs` coverage (root validation/relationships, link-like root rejection, nested enumeration, link retention, namespace-escape rejection, root-resolution behavior, and pre-enumeration cancellation) is retained as owned provider evidence; the new focused file must not duplicate those assertions merely to look self-contained.

- [ ] **Step 2: Write failing root-validation and relationship tests**

Where genuinely missing (existing covered cases remain owned evidence), using test-owned temporary directories, prove:

```text
absolute directory selection validates
missing selection maps to the documented provider error
file selection is rejected as not-a-directory
same/ancestor/descendant/disjoint relationships follow canonical filesystem semantics
unresolvable relationships return Unknown rather than guessing
link-like/reparse-point roots are rejected where supported
```

Do not add blanket Windows case-folding rules.

- [ ] **Step 3: Run focused tests RED**

Run the smallest relevant `cargo test` invocation and confirm failures represent missing coverage or a genuine contract defect.

- [ ] **Step 4: Write failing enumeration/access tests**

Prove:

```text
resolve_root rejects unavailable, non-directory, and link-like roots correctly
direct enumeration retains files/directories with correct observed kinds
link-like children are retained but never traversed
nested traversal cannot escape the configured root
missing/inaccessible scopes map to documented SourceAccessError values
cancellation is honored before and during enumeration
Unix native identity supports trustworthy move evidence
non-Unix platforms do not fabricate unsupported native identity
```

Permission-denied tests must only assert denial when the runner can genuinely create an inaccessible fixture.

- [ ] **Step 5: Implement only proven provider corrections**

Keep canonicalization, traversal, identity interpretation, path handling, and native error mapping inside the LocalFilesystem provider.

- [ ] **Step 6: Run focused provider tests GREEN**

Run the focused suite and relevant `argus-infrastructure` crate tests.

---

### Task 2: Harden Phase 001 architecture and generated-output boundaries

**Files:**
- Modify: `flutter/test/architecture/architecture_boundaries_test.dart`
- Modify if appropriate: `scripts/check_rust_dependencies.sh`
- Modify `justfile` only if legitimate new generated output requires registration.
- Modify production code only if a new guard exposes a real existing-contract violation.

- [ ] **Step 1: Add filesystem-authority architecture guards**

Mechanically prevent Flutter Sources/Jobs production code from taking native filesystem authority.

Guard against direct:
- `dart:io`
- `File`
- `Directory`
- native directory enumeration
- canonicalization
- provider locator interpretation

Preserve the approved picker seam: the picker may return an untrusted selected folder value but does not become filesystem authority.

- [ ] **Step 2: Guard provider-native contract leakage**

Public Flutter-facing focused APIs/models must not expose:
- native inode/file-ID semantics;
- reparse-point implementation vocabulary;
- provider path parsing APIs;
- infrastructure types;
- FRB DTOs.

Opaque values may remain opaque where already required by contract.

- [ ] **Step 3: Guard event/authority ownership**

Prove mechanically that:

```text
only app-level event coordinators consume runtime event continuity
Sources and Jobs feature code owns no native event subscription
event payloads are never authoritative source/job state
Sources/Jobs authority flows through focused APIs/controllers
no duplicate mutable source/job repository or cache authority appears
```

- [ ] **Step 4: Extend Phase 002+ leakage guard**

Reject implementation concepts for:
- game-content parsing;
- hashing;
- metadata/artwork enrichment;
- RetroAchievements;
- filesystem watching;
- additional source providers;
- other later-phase product families.

Avoid false positives from docs/comments/generated output.

- [ ] **Step 5: Run architecture tests RED and fix only real violations**

```bash
cd flutter && fvm flutter test test/architecture/architecture_boundaries_test.dart --no-pub
bash scripts/check_rust_dependencies.sh
```

- [ ] **Step 6: Run architecture and generated-output gates GREEN**

```bash
just generate
just check-generated
```

---

### Task 3: Add the macOS Phase 001 canonical native integration proof

**Files:**
- Create: `flutter/integration_test/phase_001_local_sources_milestone_test.dart`
- Modify: `flutter/lib/app/bootstrap/app_bootstrap.dart` to add one narrow optional test seam for the existing `LibraryFolderPicker` contract, analogous to `clientGatewayFactory`; `bootstrapArgus()` keeps using `const ArgusBootstrap()` with no override.
- Modify other existing app/Sources/Jobs/client/bridge code only if a proven contract/testability defect requires it.
- Do not add a generic provider-override bag or general production environment-variable mechanism.

**Interfaces:**
- Consumes: real `ArgusBootstrap` (with the narrow optional picker seam), existing client-gateway test seam, `FrbArgusClientGateway(dataDirectoryOverride: ...)`, Sources UI, Jobs UI, FRB, Rust runtime/application, SQLite, LocalFilesystem.
- Produces: real macOS composition proof against test-owned state.

- [ ] **Step 1: Define strict test-owned inputs**

The integration target may read explicit test-only environment inputs for:
- isolated application-data directory;
- first temporary library root;
- second temporary library root.

Fail immediately if any required input is missing or invalid. Never fall back to normal Argus or user-library locations.

Folder selection is injected through the approved narrow seam: `ArgusBootstrap` gains one optional `LibraryFolderPicker? libraryFolderPicker` constructor parameter applied via `libraryFolderPickerProvider.overrideWithValue(...)` inside its existing owned `ProviderScope`. Production `bootstrapArgus()` passes no override. Do not construct a second `ProviderScope` around `ArgusBootstrap`, and do not add a generic provider-override list or environment-driven production DI mechanism.

- [ ] **Step 2: Prove Add & Scan**

From fresh state:

1. open Sources;
2. add root one;
3. execute **Add & Scan**;
4. observe durable job admission/execution;
5. inspect committed hierarchy;
6. verify Jobs detail/progress is meaningful.

Wait on explicit authoritative predicates, not fixed sleeps.

- [ ] **Step 3: Prove Scan Again reconciliation**

Mutate root one:
- add an entry;
- remove an entry;
- perform a move where native identity permits trustworthy move evidence.

Invoke **Scan Again** through the real workflow.

Assert:
- added entry appears;
- removed entry disappears only after authoritative completed reconciliation;
- moved identity is preserved only when provider-native evidence proves it.

- [ ] **Step 4: Prove Scan All**

Add root two with distinct contents.

Invoke **Scan All**.

Verify:
- each eligible root receives independent admission/outcome;
- Jobs represents each result correctly;
- one root's result is never inferred from another.

- [ ] **Step 5: Prove cooperative cancellation**

Start sufficiently controllable scan work, wait until the durable job exposes `canCancel`, cancel through the real control, then wait for the authoritative terminal state.

If the fixture completes too quickly, use a narrow test seam at an already-approved boundary rather than production sleeps or artificial product delay.

- [ ] **Step 6: Prove root-removal safety and historical Jobs intelligibility**

Remove a configured root through the real workflow.

Assert:
- the root is removed from active Sources state;
- test-owned files remain unchanged on disk;
- historical terminal job/scan detail remains intelligible afterward.

- [ ] **Step 7: Run focused macOS native proof**

Rebuild the locked bridge and run the integration target against isolated test state. Include focused bootstrap/architecture regression coverage for the new narrow picker seam (for example: `bootstrapArgus()` remains override-free and the seam is applied only through the optional constructor parameter).

---

### Task 4: Add real restart-recovery proof

**Files:**
- Modify the Phase 001 integration target or create a narrowly separate restart target.
- Create: `scripts/run_phase_001_native_tests.sh`
- Modify: `justfile`

**Interfaces:**
- Consumes: Slice 006 restart-recovery semantics and Phase 000's proven two-process harness pattern.
- Produces: `just test-phase-001-native`.

- [ ] **Step 1: Add restart seed/verify phases**

**Seed process**
- start real scan work;
- wait until authoritative durable state proves it is active/running;
- then intentionally terminate the native process without `generalShutdown`, `CancelJob`, normal scan completion, or any other terminalization.

The native harness must have an explicit protocol that distinguishes this expected intentional interruption from an accidental seed-test failure. A test-owned readiness/sentinel mechanism is acceptable if needed; it must not become production behavior or leak sensitive path data into diagnostics.

**Verify process**
- launch a distinct native Flutter process against the same test-owned application directory;
- prove the exact Slice 006 recovery contract: a stale `Running` child with no accepted durable cancellation intent becomes `Abandoned` (assert `Abandoned` explicitly);
- prove active ownership was cleared;
- prove committed positive observations survive;
- prove incomplete work gained no destructive absence authority;
- prove no provider enumeration or new admission occurred during startup recovery;
- prove no scan automatically resumes.

Do not simulate restart by recreating providers/runtime objects inside one Dart process.

- [ ] **Step 2: Keep normal canonical workflow separate**

Run the normal Phase 001 workflow proof independently before the deliberate interruption chain so failures remain attributable.

- [ ] **Step 3: Implement `scripts/run_phase_001_native_tests.sh`**

Follow Phase 000 harness conventions:

```text
set -euo pipefail
require Darwin
resolve repo root independently of caller cwd
create isolated app-data + library-root fixtures
trap cleanup of only owned paths
build argus-bridge with locked inputs
run normal Phase 001 native milestone
run restart seed in one Flutter invocation
run restart verify in a second Flutter invocation against the same app-data directory
```

Respect macOS sandboxing through explicit documented test seams.

- [ ] **Step 4: Add `just test-phase-001-native`**

Keep it outside `just test` and `just check`.

- [ ] **Step 5: Run Phase 001 native milestone GREEN**

```bash
just test-phase-001-native
```

---

### Task 5: Add repository-owned Windows/Linux provider verification

**Files:**
- Modify: `justfile`
- Modify: `.github/workflows/ci.yml`
- Create a wrapper script only if necessary for portable invocation.

- [ ] **Step 1: Add `test-local-filesystem-native`**

Create a stable repository-owned recipe that runs the combined real LocalFilesystem/provider evidence: the complete `argus-infrastructure` package test suite with locked/all-feature inputs (preferred), which executes the existing `sources.rs`/`jobs.rs` provider contract evidence plus the new `local_filesystem_contract.rs` missing-coverage tests.

It must execute actual filesystem tests, not only `cargo check`.

- [ ] **Step 2: Run it locally**

```bash
just test-local-filesystem-native
```

- [ ] **Step 3: Run real provider tests on Windows and Linux CI**

Keep Ubuntu `quality` as the canonical `just check` gate.

Add CI evidence:

```text
Windows -> actual LocalFilesystem provider tests
Linux   -> actual LocalFilesystem provider tests
macOS   -> Phase 001 native milestone, plus provider tests where useful
```

Do not duplicate the full macOS Flutter E2E suite on Windows/Linux.

- [ ] **Step 4: Preserve native desktop build checks if still useful**

Existing Windows/macOS compile checks can remain, but they do not satisfy the real-provider requirement.

---

### Task 6: Make the macOS Phase 001 milestone a required CI gate

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add a dedicated macOS Phase 001 job**

Use the existing pinned Flutter/Rust/FVM/just conventions and execute:

```bash
just test-phase-001-native
```

The workflow must run on normal `push` and `pull_request`.

GitHub Actions is orchestration only; do not replicate the milestone implementation in YAML.

- [ ] **Step 2: Preserve explicit Phase 000 native regression evidence**

Keep `just test-phase-000-native` as an explicit native regression gate/step. Do not silently assume the Phase 001 milestone subsumes all Phase 000 invariants.

- [ ] **Step 3: Make CI failure domains obvious**

Use names that distinguish:
- platform-neutral quality;
- Windows provider;
- Linux provider;
- Phase 000 native regression;
- Phase 001 native milestone.

Do not dump sensitive raw fixture paths into CI diagnostics.

---

### Task 7: Record Phase 001 completion verification

**Files:**
- Create: `docs/implementation/phase-001-local-sources-and-indexing-verification.md`

- [ ] **Step 1: Document automated gates**

At minimum:

```bash
just generate
just check-generated
just check
just test-local-filesystem-native
just test-phase-000-native
just test-phase-001-native
```

Document which are portable versus platform-native.

- [ ] **Step 2: Map automated evidence to Phase 001 exit criteria**

Include:
- generated output;
- architecture;
- LocalFilesystem behavior;
- add/scan;
- hierarchy;
- Scan Again;
- move reconciliation;
- Scan All;
- cancellation;
- restart recovery;
- no auto-resume;
- safe root removal;
- historical Jobs detail;
- Phase 000 preservation.

- [ ] **Step 3: Keep manual evidence truthful**

Record remaining keyboard, screen-reader, visual, scaling, and exploratory checks as one of:

```text
PASS
FAIL
NOT RUN
BLOCKED
```

Unexecuted checks remain `NOT RUN`.

- [ ] **Step 4: Record phase boundary**

State that Slice 007 is the final implementation slice and that the next step is a separate Phase 001 closeout against all 31 exit criteria, not an invented Slice 008.

---

### Task 8: Final verification and scope audit

- [ ] **Step 1: Canonical generation**

```bash
just generate
just check-generated
```

- [ ] **Step 2: Platform-neutral gate**

```bash
just check
```

Confirm `just check` still has no dependency on Phase 000/001 native gates.

- [ ] **Step 3: Run locally available native gates**

On macOS:

```bash
just test-local-filesystem-native
just test-phase-000-native
just test-phase-001-native
```

Do not fabricate Windows/Linux PASS locally; their CI runners provide that evidence.

- [ ] **Step 4: Validate scripts and CI**

Ensure ShellCheck/syntax validation passes through existing gates and review `.github/workflows/ci.yml` for all required jobs.

- [ ] **Step 5: Audit scope and diff**

Run:

```bash
git diff --check
```

Inspect changed paths.

Reject:
- build outputs;
- temporary DBs;
- diagnostics archives;
- caches;
- generated files not produced canonically;
- Phase 002+ functionality.

Every production change must trace to a demonstrated Phase 001 contract defect.

- [ ] **Step 6: Write truthful `RESULT.json`**

Report all evidence as `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED`.

Windows/Linux claims require actual runner evidence.
Manual accessibility/visual/exploratory evidence remains deferred unless executed.

## Plan Self-Review

1. `just check` remains platform-neutral.
2. Windows/Linux execute real filesystem-provider behavior.
3. macOS proves the real Flutter → focused client → FRB → Rust → SQLite/LocalFilesystem composition.
4. The milestone covers Add & Scan, hierarchy, Scan Again, reconciliation, Scan All, cancellation, removal safety, historical Jobs, and restart recovery/no auto-resume.
5. Native filesystem semantics remain provider-owned.
6. Sources/Jobs durable state remains authoritative; events remain invalidation hints.
7. Phase 000 native proof remains explicit regression evidence.
8. Generated output remains canonical/reproducible.
9. Production changes are only allowed to correct existing Phase 001 contract defects.
10. Manual evidence cannot be fabricated.
11. No Phase 002+ capability is introduced.
12. Passing Slice 007 transitions Phase 001 to closeout rather than Slice 008.

Implement **SLICE-P01-007 — Cross-Platform and Phase Hardening**, the seventh and final implementation slice of Phase 001.

The binding design is:

`docs/superpowers/specs/2026-08-15-phase-001-slice-007-cross-platform-and-phase-hardening-design.md`

Before implementation, save the supplied implementation plan exactly to:

`docs/superpowers/plans/2026-08-15-phase-001-slice-007-cross-platform-and-phase-hardening.md`

Then execute it task-by-task using **TDD** and the repository’s existing Superpowers workflow. Prefer `superpowers:subagent-driven-development`; `superpowers:executing-plans` is also acceptable.

## Required outcomes

Finish Phase 001 by proving and hardening the already-implemented Local Sources and Indexing capability. Do **not** add new product capability.

You must deliver:

1. Real LocalFilesystem/provider contract tests that execute on Windows, Linux, and macOS and cover the platform-sensitive Phase 001 semantics:
   - root validation and relationships;
   - enumeration and retained entry classification;
   - link-like/reparse-point boundary handling;
   - missing/inaccessible roots/scopes and error mapping;
   - cancellation;
   - trustworthy native identity/move evidence where supported.

2. Stronger architecture guards proving:
   - Flutter does not become filesystem authority;
   - provider-native filesystem concepts do not leak through public Flutter-facing contracts;
   - Sources/Jobs features do not own native event streams;
   - event payloads are not authoritative application state;
   - Sources/Jobs/background-operation authority is not duplicated;
   - Phase 002+ capability has not leaked into production.

3. A real macOS Phase 001 native milestone using the actual Flutter → focused client → FRB → Rust → SQLite/LocalFilesystem composition against test-owned state. It must prove the canonical Phase 001 workflows, including where deterministic and practical:
   - Add & Scan;
   - durable Jobs state/progress/detail;
   - hierarchy inspection;
   - Scan Again;
   - authoritative add/remove reconciliation;
   - trustworthy move preservation;
   - multiple roots and Scan All;
   - cooperative cancellation;
   - root-removal safety without deleting user files;
   - historical Jobs/scan detail remaining intelligible after root removal.

4. A real two-process restart-recovery proof:
   - process one has authoritative active scan work;
   - the process is interrupted without normally completing that work;
   - process two launches against the same isolated persisted state;
   - startup recovery produces the documented durable terminal result;
   - no scan automatically resumes.

5. Repository-owned commands:
   - a focused real provider target such as `just test-local-filesystem-native`;
   - `just test-phase-001-native`;
   - preserve `just test-phase-000-native`;
   - **do not** add native gates to `just check`.

6. CI hardening:
   - `just check` remains the platform-neutral Ubuntu quality gate;
   - Windows runs actual LocalFilesystem/provider tests;
   - Linux runs actual LocalFilesystem/provider tests;
   - macOS runs the full required Phase 001 native milestone on normal push/pull-request CI;
   - Phase 000 native regression evidence remains explicit;
   - existing desktop compile checks may remain but are not a substitute for real provider/native tests.

7. A Phase 001 verification record at:

`docs/implementation/phase-001-local-sources-and-indexing-verification.md`

It must distinguish actual automated evidence from manual evidence. Manual keyboard, screen-reader, visual, scaling, and exploratory filesystem checks remain `NOT RUN/deferred` unless genuinely executed.

## Non-negotiable invariants

- This is the final Phase 001 implementation slice. Do not invent Slice 008 capability.
- Do not implement game parsing, hashing, metadata/artwork, RetroAchievements, watching, additional providers, or other Phase 002+ functionality.
- Rust/SQLite remain authoritative for durable source, scan, job, and recovery state.
- Native events remain invalidation hints only.
- Flutter must not interpret or traverse native filesystem structure.
- LocalFilesystem retains ownership of native path parsing, canonicalization, root relationships, link-like semantics, native identity, and filesystem error mapping.
- `just check` stays deterministic and platform-neutral.
- Tests must use isolated, test-owned application/database/library state and must never touch ambient Argus or user library data.
- Timing-sensitive tests must synchronize on explicit durable/UI/lifecycle predicates, not arbitrary sleeps.
- Preserve Phase 000 behavior and its native milestone.
- Generated output must come only from canonical generation and must remain reproducible without machine-local path leakage.
- Do not weaken existing tests to make the slice pass.
- If hardening exposes a genuine defect from Slices 001–006, fix the smallest owning layer and add a focused regression. Do not redefine the approved contract.
- Diagnostics/failure output must remain bounded and sanitized.
- Do not stage, commit, push, or rewrite Git history.

## Validation

At minimum, finish by genuinely running all locally applicable gates:

```bash
just generate
just check-generated
just check
just test-local-filesystem-native
just test-phase-000-native
just test-phase-001-native
git diff --check
```

Windows/Linux provider PASS claims must come from actual CI runner evidence, not inference from macOS.

Update the bound `RESULT.json` truthfully. Use `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED`; do not claim unexecuted manual or unavailable-platform evidence.

When implementation is complete, stop. Do not commit or push.
