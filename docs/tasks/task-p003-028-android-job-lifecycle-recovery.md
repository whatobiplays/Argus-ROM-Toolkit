# Android Job Lifecycle and Recovery — Issue #28

**Document ID:** TASK-P003-028
**Status:** In Progress
**Owner:** Daniel
**Last Updated:** 2026-11-02
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

The original planning baseline was the primary checkout on `main` at
`39e03c74681635c1ab5be5060eed6fca1c928ca8`, after Issue #27 host-only PR #56.
That baseline is historical provenance; the PR #58 implementation was based
on it and was published at commit `c942c75ef9a1c85b4d5e1f2cf8bde5610f7339d7`.
The corrective work is scoped to the same linked feature branch and leaves the
primary checkout and its pre-existing untracked task document untouched.

**Planning-file transport (historical):** This task began as an untracked
primary-checkout document and was copied unchanged into the dedicated linked
worktree after the original plan was approved. The primary copy remains
unmodified. Its earlier instruction to transport the file applies to that
initial implementation and is complete.

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

### 3.1 Approved PR #58 corrective scope

The candidate-path list in the original prompt is historical. The owner-approved
corrective change is limited to these ten paths:

- `scripts/android_qualification/_job_lifecycle_contract.py`
- `scripts/android_qualification/_job_lifecycle_oracle.py`
- `scripts/android_qualification/_job_lifecycle_executor.py`
- `scripts/android_qualification/test_job_lifecycle.py`
- `scripts/android_qualification/physical/_job_lifecycle_ui.py`
- `scripts/android_qualification/physical/test_job_lifecycle_ui.py`
- `scripts/android_qualification/physical/ui.py`
- `docs/qualification/android-job-lifecycle.md`
- `docs/qualification/device-authorization.md`
- This task document, limited to metadata, §1.2, this scope clarification,
  the historical latency note in §4.3, and the Completion Result.

No other path is authorized. The change remains host-only and preserves the
legacy, Issue #26, and Issue #27 contracts and physical qualification gates.
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
- The approved host contract keeps the five-warmup, twenty-measurement,
  nearest-rank p95 method provisional. It does not run the 25 physical UI
  actions, approve a numerical ceiling, or create a device latency verdict.
- The host-only evaluator retains a P2: malformed negative latency samples can
  raise `ValueError`. Correct and requalify that evaluator before latency
  execution is enabled under a separately approved physical authorization.

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

### Candidate and provenance

PR #58 first published the host-only lifecycle implementation in commit
c942c75ef9a1c85b4d5e1f2cf8bde5610f7339d7. The earlier corrective commit is
500d1c954831ca6dfb1f5f1e6424136bec81fc64. Candidate preparation used
de01ee9e9c627fc7eb8aae386acb2fc5d02683b1, based on the fixed PR baseline
39e03c74681635c1ab5be5060eed6fca1c928ca8. The approved seven-file correction
was later published as d74ea138861163bbc2dcfe775fd545a60b2db2df, whose parent
is the candidate-preparation revision. The SHA-256 of that seven-file binary
diff is `ffd1630d1a4b52e30964683a8c7b77a14ed613a82e29cd81544f61ac4df32ae1`.

The prepublication checkpoint at de01ee9 had seven unstaged, index-clean
changes in inventory entries 2, 3, 5, 6, 7, 8, and 14. This is a historical
snapshot; those paths were subsequently published together in d74ea1. At the
last GitHub check recorded here, PR #58's head was d74ea1. The GitHub PR head
is authoritative for later revisions; this document does not predict a future
commit's own SHA. The primary checkout snapshot was main at the fixed baseline
with its pre-existing untracked task document. No device or ADB access or
Issue #28 state change occurred.

The full PR inventory is:

1. docs/qualification/README.md
2. docs/qualification/android-job-lifecycle.md
3. docs/qualification/device-authorization.md
4. docs/qualification/surface-classifications-v1.json
5. docs/tasks/task-p003-028-android-job-lifecycle-recovery.md
6. scripts/android_qualification/_job_lifecycle_contract.py
7. scripts/android_qualification/_job_lifecycle_executor.py
8. scripts/android_qualification/_job_lifecycle_oracle.py
9. scripts/android_qualification/admission.py
10. scripts/android_qualification/manifest.py
11. scripts/android_qualification/physical/_job_lifecycle_ui.py
12. scripts/android_qualification/physical/test_job_lifecycle_ui.py
13. scripts/android_qualification/physical/ui.py
14. scripts/android_qualification/test_job_lifecycle.py
15. scripts/android_qualification/test_repository_checks.py

The seven paths in the historical prepublication candidate were inventory
entries 2, 3, 5, 6, 7, 8, and 14.

### Version and behavior history

The lifecycle binding progressed from contract/capability/oracle v2/v2/v3, to
v3/v3/v4 in the earlier follow-up, and now to contract v4, capability v3, and
oracle v5. The earlier bindings remain historical; v4/v3/v5 are active. The
current correction requires exact lifecycle and process enum values, unique
parent-child references, rejects reuse of an admitted terminal JobRunId, and
treats Interrupted as terminal but ineligible for Retry. Initial child
attribution also must retain the scope captured at refresh arrival. Capability
v3 and its declaration digest are unchanged. Legacy, Issue #26, and Issue #27
contracts and pins remain unchanged.

AND-04 remains a 31-operation plan; AND-05 remains 45 operations. Operation
grants, ordering, timeout values, authorization, and session deadlines did not
change. AND-04 operation 25 uses its existing bounded terminal observation.
AND-05 operation 35 proves the fresh parent-bound Retry relation before intent
or dispatch; operation 42 stays bound to the exact successor; operation 45
remains the sole terminal-success decision. Operation 37 blocks when parent or
source identity is missing or malformed in Retry detail, and fails a
different valid detail relation. An incomplete or mismatched independent
`JobIdentityObservation` blocks because it cannot bind the exact successor to
the source and scope. Operation 45 blocks a missing successor identity and
fails a different valid successor ID. Parent-child attribution, the pre-stop
guard, and Retry eligibility require the exact parent identity; missing or
malformed IDs block, and a different valid ID fails before dependent effects.
Active Jobs parent IDs must be valid. Retry control count must be an integer
equal to one; Boolean and floating-point values do not qualify. A missing
or malformed recovered Jobs parent ID blocks, and a different valid parent ID
fails before Retry. A missing foreground identity blocks relaunch before
intent; a verified contradictory foreground state is Failed. No automatic
resume or second Retry is allowed.

Current derived pins are:

| Binding | SHA-256 |
| --- | --- |
| Capability v3 | ec1754f5fdaa8327b8725e2e30b11113938721c566941dcefb0974edab1008f2 |
| Oracle v5 | 22daf4e6f1de6a17f61523c9680e2491745ee0ece0074eb58966e602d9d99181 |
| AND-04 plan, test fixture | 20882c2555dc7050bde3f8f5495e026c2bddeb39ca0096ce5bbc2df096b767fe |
| AND-04 synthetic authorization | bd89bb67cac8ef8d61b0dfbfe1c1ca56d258417dad9096ed60365bf268cc6e40 |
| AND-05 plan, test fixture | f19fde67ecd9c82e9b492609138210ea04057550646f11a2ff6536357e927700 |
| AND-05 synthetic authorization | e0e7d1b256e6e19204ed6728a761d646896d0a522ff1e52e5d750de0c4624c83 |

Scenario plan and authorization digests are synthetic test fixtures, not owner
approvals. No physical authorization was created.

### Timing and verification

- AND-04: 575 seconds raw operation timeouts, plus a 31-second operation
  floor, 90-second evidence reserve, 45-second state-check reserve, and
  30-second restoration reserve. Required span: 771 seconds. Full
  issuance-time slack is 900 - 771 = 129 seconds. At latest permitted
  admission, 60 seconds after issuance, the margin is
  900 - 60 - 771 = 69 seconds.
- AND-05: 880 seconds raw operation timeouts, plus a 45-second operation
  floor, 120-second evidence reserve, 60-second state-check reserve, and
  30-second restoration reserve. Required span: 1,135 seconds. Full
  issuance-time slack is 1,280 - 1,135 = 145 seconds. At latest permitted
  admission, 60 seconds after issuance, the margin is
  1,280 - 60 - 1,135 = 85 seconds. Cleanup remains a separate 120-second
  window. Deadlines are not extended.

Pre-correction source validation snapshot:

- Focused lifecycle and parser tests: 270 passed. This includes missing and
  malformed identity cases at parent-child attribution, the pre-stop guard,
  active and recovered Jobs, Retry eligibility, and operation 37;
  Boolean/floating Retry counts; and terminal evidence returned after its
  deadline.
- just test-android-qualification: 1,091 passed, 2 skipped.
- just _format-check and just _architecture: passed.
- Qualification archive, naming, record, and base-to-worktree diff checks:
  passed after the Completion Result edit.
- git diff --check against the worktree and fixed baseline: passed.
- just check: NOT_RUN. The root filesystem had 16 GiB available. That did not
  provide a safe margin for the disk-intensive cross-platform builds. No
  caches or evidence were removed.

### Prior review and remaining gates snapshot

The GitHub review-thread snapshot recorded on 2026-11-01 showed 15 inline
threads: eight resolved by Cubic bot and seven unresolved. This is a historical
snapshot; the current thread count was not rechecked. No thread was answered or
resolved in this work.

The prior independent reports are traceable to two separate fresh-context
Codex session records. The Standards report is session
`01a19aed-e4ab-7002-ba3a-6a257a10bbd1`; it reviewed the supplied root
instructions, `docs/agents/domain.md`, `docs/adr/README.md`, ADR-001, and
ADR-002. The Specification report is session
`01a19aed-e50d-7a91-9e67-201e316d4ef2`; it reviewed this task, the AND-04 and
AND-05 manual qualification contract, the lifecycle and authorization
qualification documents, and
`docs/superpowers/specs/2026-08-30-phase-003-manual-qualification-closeout-design.md`.
The two review prompts fixed the candidate base at de01ee9, required review of
the seven modified paths, and prohibited access to the other review report.
That candidate diff was subsequently published as d74ea1; its seven-path
SHA-256 is recorded above. The session transcripts are durable local Codex
records, not files tracked by this repository.

Both independent reports returned PASS. Standards found no hard violation and
recorded repeated handler-specific validation as an optional Fowler
duplication observation. Specification found no implementation blocker; it
confirmed identity-classification precedence, operation-34 freshness and
Retry-count checks, operation-37's independent identity plus detail
provenance, and the unchanged operation-35 absent-successor proof. Its
physical G3/G4/G5 findings remain BLOCKED, not passed. These reports establish
the host-only review gate and do not establish owner or physical qualification.

The 2026-11-01 GitHub snapshot above is historical. A later read-only snapshot
on 2026-11-02 showed 19 inline threads, 11 resolved and 8 unresolved. No
review-thread replies or resolutions were made in this correction. The local
Cubic review had no GitHub remote context and left a nonblocking P2 about
centralizing repeated refresh-detail validation. The operation-25 late-return
regression and monotonic post-observation deadline check remain in place.

Three architectural follow-ups remain nonblocking: split the lifecycle
executor by scenario, split the combined lifecycle tests, and give lifecycle
admission a more focused seam. A dedicated Retry-relation type remains
unnecessary for the current contract. The negative-latency-sample P2 remains
open: malformed negative samples can raise ValueError in the host-only
evaluator. Latency execution stays disabled until a separately reviewed oracle
correction and requalification; its sample method and numerical ceilings remain
provisional pending owner approval.

Physical G3, G4, and G5 remain BLOCKED. Host evidence does not establish the
physical package and artifact, committed Library identities, Sources root and
job identities, refresh-child attribution, process continuity, cleanup, or
restoration facts. No owner qualification verdict was issued. Task status
remains In Progress.

### Refresh-detail provenance correction (2026-11-01)

Lifecycle detail handlers now require a nonempty observer reference before
accepting detail evidence. Valid foreign parent or source IDs retain their
`FAILED` classification. AND-05 operation 34 also requires the current detail
state to match the state established during recovery and exactly one Retry
control; missing or stale evidence blocks before operation 35 is authorized.
The AND-05 pre-stop guard applies the same provenance requirement before the
force-stop intent. Operation 37 still requires its independent identity
observation and provenance on the separate successor detail. Optional fields
that an operation does not use remain optional.

Prepublication validation for this correction recorded 279 focused lifecycle
and parser tests and 1,100 Android qualification tests passed, with two
skipped. Formatting, architecture, qualification archive, naming, record, and
baseline diff checks passed. That candidate had seven modified paths and the
15-path cumulative PR inventory. The correction did not change contract v4,
capability v3, oracle v5, authorization digests, or the 31/45 operation plans.
`just check` was NOT_RUN; 12 GiB was available and considered insufficient for
the disk-intensive cross-platform builds.

Refreshed independent Standards and Specification reviews both returned PASS
with no implementation blocker. Standards found no hard rule violation; it
retained repeated handler-specific provenance checks as an optional Fowler
duplication observation. Specification confirmed the pre-stop guard, recovery
and Retry detail checks, unchanged operation 35 proof, optional unrelated
fields, and the unchanged operation plans. Cubic's pre-stop P1 was corrected.
Its separate concern about missing parent identity in child attribution does
not award a pass: `validate_identity()` requires `parent_child_complete()`,
which requires a nonempty parent reference. The duplicated bounded-polling P2
remains a nonblocking follow-up.

During that earlier provenance-correction pass, there was no device or ADB
access, stage, commit, push, PR or Issue #28 state change, review-thread
action, or owner qualification verdict. The approved candidate was published
later as d74ea1. Physical G3/G4/G5 remain BLOCKED, and latency execution stays
disabled. Task status remains In Progress.

### Oracle-argument regression and Completion Result correction (2026-11-02)

The authorization-loader integration test still covers historical plan/oracle
bindings. A separate direct parser regression now exercises a valid operation
argument object for both AND-04 and AND-05, then changes only the oracle version
or only the oracle digest for each previously published oracle revision. The
current object is accepted; each obsolete field is rejected at
`_parse_job_lifecycle_operation_arguments()` with
`AuthorizationErrorCode.INVALID_VALUE`. The test does not load a plan or
authorization digest, so another validation boundary cannot satisfy its
failure assertions. The historical integration and plan-digest tests remain.

The Completion Result now labels the seven-path state at de01ee9 as a
prepublication snapshot, records the later d74ea1 publication, and gives the
review-session provenance and corrected deadline arithmetic above. This local
correction changes only `scripts/android_qualification/test_job_lifecycle.py`
and this task document. The cumulative PR inventory remains 15 paths. Contract
v4, capability v3, oracle v5, authorization digests, and the 31/45 operation
plans are unchanged. Latency execution remains disabled; G3/G4/G5 remain
BLOCKED.

Validation on this correction:

- Focused parser and authorization tests: 3 passed, including the new direct
  parser test, the historical oracle-binding test, and mismatched-plan-digest
  test.
- Focused lifecycle and physical parser tests: 280 passed.
- `just test-android-qualification`: 1,101 passed, 2 skipped.
- Formatting, architecture, qualification archive, naming, record, and
  base-to-worktree `git diff --check`: passed.
- `just check` was not rerun. No disk-intensive local build was started.

At the November 2, 2026 prepublication review checkpoint, this two-file
correction was unstaged and unpublished. No GitHub review-thread action, device
access, or owner qualification verdict occurred during preparation. Subsequent
publication status is authoritative in PR #58. TASK-P003-028 remains In Progress.
