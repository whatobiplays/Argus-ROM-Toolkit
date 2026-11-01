# Android Job Lifecycle and Recovery — Issue #28

**Document ID:** TASK-P003-028  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-10-30  
**Depends On:** Phase 003; Issue #28 (blocked by closed #26); ARCH-003; SPEC-X-003; SPEC-BE-004; SPEC-BE-013; SPEC-BE-015; SPEC-FE-009; REF-QUAL-001; CONV-DOC-001; CONV-TEST-001; ADR-001; ADR-002; ADR-004; Issue #26's first Add & Scan host contract; Issue #27's independent Library host contract  
**Supersedes:** None  
**Superseded By:** None

## 1. Objective and authority

Implement the next bounded **host-only, fail-closed** qualification slice for GitHub Issue #28: truthful Android active Library refresh/Jobs observation, background/foreground transitions, deliberate product process loss, durable-state recovery, separately authorized explicit retry, and a measurable foreground-responsiveness evidence contract.

This document is the Codex implementation prompt and execution boundary. **Start in Plan mode. Inspect the repository and return an implementation plan for owner review before editing source, tests, or governed docs.** Approval of this task prompt is not authorization for immediate code implementation, device access, issue closure, Git staging, commit, push, or PR publication.

The executable scope is the intersection of the active Phase 003 qualification work, Issue #28, ARCH-003, SPEC-X-003, the listed BE/FE contracts, and the narrow paths below. Any discrepancy must be surfaced in the plan, not resolved by silently expanding scope.

### 1.1 Platform applicability and native evidence

- **Android:** Host-simulated qualification plan, independent typed observations, fake-device regression tests, and append-only safety/evidence checks are in scope. **Physical Android execution is NOT RUN/BLOCKED until separately authorized.** Real timing measurements and scenario PASS require a pinned real Qualification Release, approved fixture/workload, actual product-visible evidence, and independent owner verdict.
- **macOS:** Existing historical owner qualification is reference context only. Do not modify, rerun, or reclassify its results.
- **Ordinary Android product:** Protected. Do not install, launch, reset, stop, navigate, or otherwise operate com.argusromtoolkit.argus. A future physical scenario must target only com.argusromtoolkit.argus.qualification.
- **Cross-platform Rust/Flutter:** Inspect as the behavioral authority. This slice does not change product code or introduce test-only product APIs; report observability gaps as blockers or separate proposed production corrections.

### 1.2 Current baseline and non-negotiable distinctions

The observed primary checkout was clean on main at 39e03c74681635c1ab5be5060eed6fca1c928ca8 (merged Issue #27 host-only PR #56). Revalidate both local and remote baseline before planning; do not assume that SHA remains current.

**Planning-file transport:** This newly authored task is currently an untracked document in the primary checkout and is not present in a new linked worktree created from Git HEAD. Codex must read this file from the primary checkout as a read-only planning input. After plan approval, copy its exact contents into the isolated implementation worktree if the implementation is to commit this task/Completion Result. Do not edit, stage, or delete the primary copy as an implicit worktree setup step.

- Issue #26 closed its host-only first Add & Scan implementation; it did not prove a physical scan.
- Issue #27 closed as host-only with physical Library acceptance transferred to #57. **Issue #28 has not received a corresponding scope-transfer/closure decision. Keep its physical acceptance obligations intact.**
- The public qualification CLI and public physical runner still fail closed; current private scenario runners have fake transports, not an approved live ADB/device adapter.
- The existing historical AND-04/AND-05 surface probes do not prove job identity, persistence, active work, or retry. Their observation of a returned page is not sufficient evidence.
- The current Jobs page uses a durable JobRunId internally, but the first Add & Scan UI observation path does not expose that run identifier. A visual label, navigation time, or inferred route is not a durable identity oracle.
- The primary background operation for this slice is **LibraryRefresh**, including its composed child scan/identify/enrich work where applicable. Do not mistake an individual LibraryScan child for the whole refresh. Inspect the actual pinned Release semantics rather than assuming a UI label identifies the exact run.
- On startup following forced process loss, non-resumable active LibraryRefresh/LibraryScan work reconciles according to the durable recovery policy: normally Abandoned, or Cancelled when accepted durable cancellation intent requires it. Do not require Interrupted for a non-resumable refresh, fabricate Completed/Failed, or claim automatic resume. Retry is a new JobRunId, not a transition that reopens the old run.
- Distinguish a **planned, explicitly authorized product force-stop** within a qualification scenario from interruption of the host qualification executor. If the qualification session itself becomes terminal/uncertain, it must not continue or reissue effects; require a new session authorization as governed.

## 2. Inspect first

1. AGENTS.md, CONTEXT.md, docs/agents/domain.md, relevant ADRs and docs/agents/issue-tracker.md.
2. docs/architecture/qualification-architecture.md; docs/specifications/cross-cutting/spec-x-003-qualification-contract.md.
3. docs/specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md; docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md; docs/specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md.
4. docs/specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md; docs/implementation/phase-003-manual-qualification.md, specifically AND-04 and AND-05 and MAC-05/MAC-06 as historical precedents, not substitute evidence.
5. docs/qualification/README.md, android-first-add-scan.md, android-library-interactions.md, device-authorization.md, evidence-records.md, surface-classifications-v1.json.
6. scripts/android_qualification/admission.py; evidence.py; _evidence_storage.py; _library_interaction_contract.py; _library_interaction_executor.py; _library_interaction_oracle.py; physical/_library_interaction_ui.py; physical/ui.py; physical/runner.py and focused fake tests. The older ordinary-package physical probes are **not** an authorized transport.
7. flutter/lib/features/jobs/application/job_detail_controller.dart; flutter/lib/features/jobs/presentation/job_detail_page.dart; flutter/lib/features/jobs/presentation/jobs_page.dart; flutter/lib/features/library/presentation/library_page.dart.
8. rust/crates/argus-application/src/jobs.rs; rust/crates/argus-runtime/src/runtime.rs; rust/crates/argus-runtime/tests/slice_006_restart_recovery.rs; other focused job/refresh tests.
9. docs/conventions/conv-doc-001-documentation-and-codex-result-conventions.md; docs/conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md; justfile.

Perform a **redundancy check**: identify what existing tests already establish about runtime/job semantics versus what an independent product-visible Android qualification still cannot observe. Do not duplicate backend Rust unit/integration coverage or revive retired public commands. Check .out-of-scope entries if present; report any conflicting prior rejection.

## 3. Authorized implementation scope (after plan approval)

### 3.1 Candidate allowed paths — narrow to actual need in the plan

- New, narrowly named private host-only contract/oracle/executor/UI-observation modules under scripts/android_qualification/ (for example _job_lifecycle_contract.py, _job_lifecycle_oracle.py, _job_lifecycle_executor.py, physical/_job_lifecycle_ui.py).
- Focused associated Python tests under scripts/android_qualification/ and scripts/android_qualification/physical/, including tests for guarded admission/evidence integration.
- scripts/android_qualification/admission.py **only** for an explicit closed-plan private binding with one-use authorization and no new public execution route; obtain separate review if change to common parser/admission behavior would impact #26/#27.
- docs/qualification/android-job-lifecycle.md (new), docs/qualification/README.md, and docs/qualification/surface-classifications-v1.json only as needed to document/register new active qualification surfaces.
- This task file, solely for final Completion Result after implementation and verification.

Any other production or shared file is outside this task until independently justified and approved. In particular, changes to acceptance-rule or evidence schema are **not** assumed necessary; prefer the existing typed evidence facade and immutable storage contract.

### 3.2 Forbidden paths and effects

- No Flutter, Rust, Android native, product runtime, bridge, database schema, or generated-code edits under this host-only task.
- No modifications to retired archives, historical test reports, prior owner verdicts, Issue #26/#27 oracles, existing 19-operation/42-operation pins, or their compatibility rules.
- No public CLI or runner live execution, production ADB/device transport, generic shell/path executor, guessed-coordinate tap, arbitrary accessibility XML dump, broad force-stop, permission change, fixture transfer, install/uninstall/reset, or access to real owner ROMs, device, credentials, private serials, or ordinary application state.
- No new test-only product endpoint, private product database interrogation, hidden debug state, or reliance on synthetic UI output to certify a physical scenario.
- No automatic Git staging, commit, push, PR creation, issue transition/closure, or release approval.

## 4. Required plan and contracts

### 4.1 Scenario and operation boundaries

Define two authoritative public scenario identities, **AND-04** (job lifecycle/foreground responsiveness) and **AND-05** (planned process loss, persistence, explicit retry), with versioned private operation plans, independent expectations, exact ordering/deadlines and typed operation slots. Internal assertion aliases may describe separate steps, but must not manufacture a new public scenario ID.

The host contract must distinguish **read-only observations** (authoritative job/detail state, lifecycle/phase/progress, Library state, foreground/return, persisted facts, visible retry outcome) from **effects** (initiate/refresh, Home/background, foreground return, planned qualification-app force-stop/relaunch, explicitly authorized product Retry). Each effect is bound to a one-use approval, exact target, exact qualified application/artifact, allowed type/parameters and deadline. No broad command execution.

Separate the planned process-loss scenario from host executor loss. An expected product process stop may be a preauthorized scenario action. If host evidence append, target identity, actual effect, or executor progress becomes uncertain, no blind replay and no continuation after session terminalization.

### 4.2 Objective observation and independent oracle

Require the following independent, source-grounded facts, all available through approved normal UI/product-facing observations in a future physical run:

1. A single durable **parent LibraryRefresh JobRunId** and frozen requested scope, with child/phase progress bound to that identity; absence or ambiguous identity is BLOCKED, never inferred from position/time/title.
2. At least one confirmed active interval with actual committed progress facts, without invented percentage or a mere spinner as proof. Observe Jobs, Library, and app navigation/state queryability while work remains active.
3. Background and foreground transitions preserve coherent authoritative state; never infer the number of jobs from one screen or treat native notification content as the authoritative Jobs store.
4. For AND-05, establish pre-loss committed Library state, deliberate loss while a known refresh is active, recovery after relaunch, and no silent resumption/duplicate attempt. Distinguish Abandoned/Cancelled according to the actual prior durable cancellation intent.
5. Explicitly authorized Retry is available only if the source run is terminal and the backend advertises current eligibility. An admitted retry must have a distinct JobRunId, a provable relationship to the old attempt and equivalent bounded original intent. AlreadyRetried must not dispatch another retry. Failed/nonadmitted/transport-ambiguous retry is reconciled read-only before any further effect.
6. Committed Library data and scan-root state survive process loss without unsupported assumptions or destructive repair. Do not use a private SQLite query as the black-box oracle.
7. End with objectively observed terminal state, fail-fast categorical assertions and appropriately verified cleanup/restoration. Uncertain active work, resource ownership, or evidence append withholds unsafe cleanup and emits a structured owner-recovery obligation.

A conclusive wrong product result is FAILED; missing/ambiguous UI identity, unprovable complete state, unavailable genuine fixture/workload oracle, or missing owner performance rule is BLOCKED; later dependent steps are NOT_RUN. Fake-session success may prove the harness' *safety tests* PASS but must never turn AND-04/AND-05 into physical PASS.

### 4.3 Latency evidence and calibration boundary

Model a **Qualification Latency Criterion** separate from action/scenario/session timeouts. Define a typed repeatable capture contract for independently timed, precisely named foreground actions during an active refresh (e.g. route switching, Jobs/Library query response and an available job control when safe), each bound to a pinned workload/environment and artifact.

- Use a monotonic clock for duration measurement and integer milliseconds for the existing evidence Measurement unit. Do not use wall-clock deltas as responsiveness measurements.
- Require repeated representative baseline samples and a separately **owner-approved immutable ceiling/rule digest** before any pass/fail judgment. No invented numerical threshold, percentile, fallback, or inferred device timing.
- Classify absent/unapproved threshold or unverified active-work overlap as BLOCKED; provide the sanitized measurement contract and precise missing inputs for later owner calibration.
- Do not confuse operation timeout, absence of failure, or a fake-clock test with measured real-device latency.
- Before implementation, Codex should propose the sample/aggregation method and identify which foreground observations are actually measurable through the pinned product UI; owner approval of numerical criteria remains a separate gate.

### 4.4 Admission, evidence and interruption

Reuse the private session authorization and EvidenceStore APIs wherever possible. Freeze exact APK/package/signature/version/source, manifest/fixture/plan/rule digests, deadline and allowed operations before a mutation. Persist intent before each effect, one result afterward, and stable categorical observations tied to exact scenario and rule identity.

Use existing assertion, lifecycle, interruption/terminal and measurement record types; immutable evidence is append-only, hash-verified, owner-private and sanitized. Preserve prior observations when a scenario or host session is interrupted. Do not write raw job identifiers, UI text, fixture data, paths, device serials, private ROM hashes, screenshots or credentials into shared records; use opaque aliases with owner-private mapping if needed.

The execution code cannot issue owner verdicts. A sanitized review packet is for owner assessment and never an automatic approval. If append, cleanup, identity, approval, permission-restoration status, or product state is uncertain, fail closed and report follow-up rather than discarding evidence.

## 5. Required deterministic tests

Use injected fakes only; test that importing modules, running the public entrypoints, or exercising the host suite cannot execute ADB. Include negative/adversarial cases:

1. Plan/oracle revision mismatch, extra/missing/reordered operations, invented action, expired approval/deadline, wrong package/signature/APK/source pin, malformed observation, ambiguous target/foreground.
2. Missing/duplicated/contradictory JobRunId or parent-child attribution; active-vs-terminal contradictions; stale snapshots; progress that does not establish an active interval.
3. Correct background/return state; false duplicate/auto-resume claims; invalid recovery state; accepted-cancellation distinction; no fabricated Interrupted for non-resumable refresh.
4. Explicit retry from eligible terminal run yields exactly one new identity and links history; AlreadyRetried is idempotent; no retry for clean Completed, nonterminal source, missing original target, or uncertain transport result; no blind retry after lost acknowledgement.
5. Deliberate app process loss vs host qualification executor interruption, evidence append-before-effect failure, uncertain post-effect result, durable interruption recovery, identity substitution, and cleanup ownership failure.
6. Correct verdict isolation, private-value rejection, fixed alias/schema compatibility and no leakage through reports or exception strings.
7. Fake monotonic latency samples in valid units and pinned workload context, zero unsupported source-derived thresholds, explicit BLOCKED without approved calibration, and refusal to turn fake timing into physical PASS.
8. Regression preservation of #26 first Add & Scan and #27 Library paths and exact pins/behavior.

## 6. Verification gates

Codex must identify the exact applicable focused Python commands in its plan, then run them after approval. Required gates unless unavailable with an explicit BLOCKED/NOT_RUN reason:

1. Focused new contract, observer, executor and admission tests.
2. just test-android-qualification
3. just check-qualification-archive
4. just check-qualification-naming
5. just check
6. git diff --check
7. Independent two-axis Standards/Spec review and evidence of no ordinary-app/device access.

Report individual results honestly. Host CI, a fake transport, and a successful static review **never** constitute physical Android qualification or owner PASS.

## 7. Codex workflow and output contract

**First response: Plan only.** Work from a dedicated linked worktree created from verified current main. Do not modify the primary checkout or its existing untracked/ignored content. Do not make source changes before explicit approval of the plan. The plan must give:

1. Current branch/HEAD/provenance, worktree path, cleanliness, and exact changed-path proposal.
2. Confirmed existing production Jobs/refresh semantics and which observations can/cannot be grounded through user-visible accessibility surfaces.
3. A concise typed interface/data model, closed operation sequence, oracle shape/version, deadline/evidence/fail-fast and cleanup design, with explicit reason for each new module.
4. Dependency map including relevant tests; any conflict with #26/#27, #35 or #57; redundancy/previous-rejection findings.
5. Failure-mode matrix including absent identity, force-stop uncertainty, retry uncertainty, and unavailable latency calibration.
6. Verification/test matrix and expected physical blockers.
7. Explicit owner decisions needed **only** if the approved host-only boundary cannot be maintained. Do not expand scope on assumptions.

After the owner approves the plan, implement only those paths and contracts, run the required gates, obtain independent Standards/Spec review, and report exact results. Append a concise Completion Result to this task as permitted by CONV-DOC-001 (without raw Codex transcript or sensitive evidence). Do not claim Issue #28 accepted or completed until its full physical obligations are handled or the owner expressly approves a scope split that preserves them in a separate issue.

## 8. Git boundary

Suggested future implementation commit subject: Add host-only Android job lifecycle qualification contract

No stage, commit, push, PR publication or issue edits are authorized by this task. An approved implementation plan does not imply any Git write or live-device session authority. Future physical qualification requires a separate exact session authorization and owner verdict, preserving all failed/blocked historical attempts.

## Completion Result

The approved Issue #28 host-only slice, the AND-05 45-operation amendment, the
successor-identity-bound operation-42 correction, and the lifecycle admission
timeout guard were implemented in the linked worktree at
`/Users/daniel/.codex/worktrees/issue-28-job-lifecycle-recovery/Argus-ROM-Toolkit`
on branch `codex/issue-28-job-lifecycle-recovery`, based on
`39e03c74681635c1ab5be5060eed6fca1c928ca8`. No Android device, ADB, staging,
commit, push, pull request, Issue #28 transition, or owner qualification verdict
was used. The primary checkout remains unchanged except for its pre-existing
untracked task document.

Changed paths (14):

- Modified: `docs/qualification/README.md`,
  `docs/qualification/device-authorization.md`,
  `docs/qualification/surface-classifications-v1.json`,
  `scripts/android_qualification/admission.py`,
  `scripts/android_qualification/manifest.py`,
  `scripts/android_qualification/test_repository_checks.py`.
- Added: `docs/qualification/android-job-lifecycle.md`,
  `scripts/android_qualification/_job_lifecycle_contract.py`,
  `scripts/android_qualification/_job_lifecycle_oracle.py`,
  `scripts/android_qualification/_job_lifecycle_executor.py`,
  `scripts/android_qualification/physical/_job_lifecycle_ui.py`,
  `scripts/android_qualification/physical/test_job_lifecycle_ui.py`,
  `scripts/android_qualification/test_job_lifecycle.py`, and this task
  document.
- The task document received only this refreshed Completion Result; its plan
  sections were not edited.

The narrow `manifest.py` and `device-authorization.md` exceptions use the
private `JOB_LIFECYCLE` authorization profile. `test_repository_checks.py`
keeps the pinned surface inventory aligned with the approved six rows (134
total, 86 active). Legacy, Issue #26, and Issue #27 parser, admission, executor,
and pin behavior remain unchanged.

The lifecycle contract and capability versions remain 2. The oracle version is
3, and its derived digest is shared by both scenarios. Version 2 lifecycle
authorization pins are therefore invalid for AND-04 as well as AND-05. Both
scenario documents bind the v3 shared digest; the authorization SHA and the
independently computed plan SHA remain separate bindings.

The parser occurrence check and the added stale-revision coverage required no
contract, capability, or oracle version change.

Lifecycle admission now measures monotonic elapsed time around the baseline
observer and returns `OBSERVATION_UNAVAILABLE` when the observation reaches
its approved timeout, before baseline validation or capability claim. The
guard rejects an overdue return; it cannot interrupt an observer that never
returns.

The operation-42 correction accepts only the exact authorized root with one
`View Job` reference equal to the verified Retry successor. It accepts either
an identified active presentation with no historical last-scan state or an
identified historical presentation with one terminal last-scan state. Active
acceptance records current successor ownership, not terminal completion. The
executor sets `_root_last_scan_ref` only for a historical pass, appends
`:root-post-retry-active-scan` only for an active pass, never awards
refresh-child attribution, and never dispatches a second Retry. Operation 45
remains the only terminal-success decision. The physical parser still raises
an ambiguous-surface block for `Scanning in progress` with `View Job`, so
physical operations 15, 27, and 42 remain blocked pending G5 transport work.

The 45-operation layout and timing are unchanged:

- AND-04: 31 operations, 575 seconds raw timeouts, 31-second operation floor,
  90-second evidence reserve, 45-second state-check reserve, 30-second
  restoration reserve, 771-second required span, 900-second session, and
  69-second margin at latest admission.
- AND-05: 45 operations, 880 seconds raw timeouts, 45-second operation floor,
  120-second evidence reserve, 60-second state-check reserve, 30-second
  restoration reserve, 1,135-second required span, 1,280-second session, and
  85-second margin at latest admission.
- Cleanup remains a separate 120-second closure window. No deadline is
  extended during execution.

Verified on the final candidate:

- Focused lifecycle and parser tests: 205 passed.
- `just test-android-qualification`: 1,026 passed, 2 skipped.
- `just check`: passed, including formatting, lint, architecture, the
  1,026-test Android qualification suite, the 40-test cleanup suite, Rust
  tests, Flutter tests (633 passed), macOS FRB export checks, and macOS Rust
  build checks.
- `just check-qualification-archive`, `just check-qualification-naming`, and
  `bash scripts/check_qualification_record.sh`: passed.
- `git diff --check`: clean across code and documentation. The task document
  keeps the repository's Markdown hard-break trailing spaces, which
  `git diff --check` reports only while that file is staged as new.

Cubic review triage:

- Fixed the final P2 parser finding: the Jobs row parser now counts lifecycle
  status occurrences instead of distinct values. A merged node containing two
  identical `Running` labels withholds `lifecycle_status` and
  `active_refresh_row_count`; a regression covers the downstream observation.
- Extended the stale oracle-revision test to AND-04 and AND-05. Both scenarios
  accept v3 authorization and reject v2 authorization arguments and digests.
- Fixed a P1 where operation 19 accepted an unidentified foreground package as
  a successful background transition. It now records `BLOCKED`, with a
  regression test.
- Fixed a P2 where `LibrarySurfaceObservation.digest()` omitted
  `membership_ids`. The digest now binds the sorted identities, with a
  regression test.
- Fixed a P2 where the recovered Sources root accepted an `ACTIVE_SCAN`
  presentation carrying a terminal last-scan state. The check now requires an
  identified historical presentation, with a contradiction regression test.
- Fixed a P1 where a successor detail with no state was reported as still
  active at the deadline. Unavailable terminal evidence now records
  `successor_terminal_unavailable`, with a regression test.
- Retained one P1 from an earlier Cubic run: the scan-detail handler records
  refresh-child attribution as `BLOCKED` but continues to foreground
  restoration. The scan-detail result proves only scan identity, no parent-child
  claim is awarded, and the approved host-only workflow treats restoration as
  safe. Physical qualification remains `BLOCKED`.
- Fixed the final P1: lifecycle admission now measures monotonic elapsed time
  around the baseline observer and rejects a return at or beyond its timeout
  with `OBSERVATION_UNAVAILABLE`. The check runs before baseline validation or
  capability claim. Controlled-clock tests cover within-time, late, exact
  boundary, raising and unavailable observers, non-consumption, and both
  scenario admissions. The guard cannot interrupt a permanently
  non-cooperative synchronous observer.
- Retained one final Cubic P2 outside this correction's authorized paths:
  `evaluate_latency` in `_job_lifecycle_oracle.py` passes an unvalidated
  `LatencyCycle.elapsed_milliseconds` into `nearest_rank_percentile_95`, so a
  negative sample raises `ValueError` instead of returning a typed
  `BLOCKED`/`FAILED` result. Reproduced with controlled inputs against the
  current tree. Latency execution stays disabled host-only, and this
  correction may change only the admission flow, its tests, and
  documentation, so the oracle guard is deferred as a scoped follow-up.
- Retained three architecture findings: the 2,064-line lifecycle executor
  combines both scenario workflows; the 4,287-line lifecycle test module
  combines contract, admission, oracle, and executor tests; and lifecycle
  admission adds a focused branch to the shared admission module. Splitting
  the executor or moving admission would change the approved architecture and
  path inventory; splitting the test module is follow-up cleanup. One
  residual correctness finding remains, recorded above as an out-of-scope
  latency-oracle follow-up.
- Two earlier boundary findings were evaluated and left unchanged: the
  host-only workflow records `scenario-outcome` as `BLOCKED` by design, and
  an empty Library cannot satisfy the required committed-asset persistence
  workload.
- An independent two-axis Standards/Spec review is `UNVERIFIED`: no
  independent reviewer was available under the instruction to implement
  without subagents. Cubic is not represented as independent review.

Physical admission remains `BLOCKED`. Host evidence cannot independently prove
the exact no-reset package, artifact, signer, Library asset identities, Sources
root presentation and run identity, refresh-child attribution, row-scoped Jobs
status, parent and child run identities, retry source and successor identity,
process presence, task continuity, or cleanup and restoration facts. The
latency execution path remains disabled pending separate owner-approved
physical authorization with a pinned workload, environment, per-cycle bounds,
sample count, and numerical ceilings. G3, G4, and G5 remain deferred,
separately authorized physical qualification gates.
