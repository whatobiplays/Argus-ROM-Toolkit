# ADR-005: Proposed qualification-contract reconciliation and physical-gate crosswalk

**Status:** Draft proposal / NON-NORMATIVE. Not an active oracle or session authorization.
**Owner:** Daniel
**Source:** [ADR-005](../adr/adr-005-physical-product-observation-boundary.md), [Q1–Q37 rationale](../adr/adr-005-design-decision-log.md), Issue #68
**Source operation tables:** [Android job lifecycle](android-job-lifecycle.md), AND-04 = 31 operations, AND-05 = 45 operations
**Preparation date:** 2026-11-14

## 1. Change-control boundary

The owner accepted the architectural design choices Q1–Q36 and closed the design tree at Q37. This document identifies the required *future amendments* to active qualification/specification contracts; it is not itself permission to change those contracts, run the observer, operate a device, or declare physical acceptance. **Keep qualification contract v5, capability v4, oracle v9, frozen AND-04 31/AND-05 45 operation orders and deadlines, and existing artifact pins unchanged** until separately reviewed. Do not reinterpret an old assertion to accept a new source without explicit versioned authorization. Incompatible historical records retain their original pins.

The Stage A/B NO-GO evidence remains historically correct for the then-permitted mechanisms. Q8's proposed socket is unimplemented and requires target-specific feasibility. The new G3/G4/G5 definitions are owner-approved design labels, not evidence of passed gates.

## 2. Required spec/contract reconciliation before production implementation

| Target | Proposed amendment; must be reviewed/versioned separately | Invariant |
| --- | --- | --- |
| `SPEC-BE-008 §68.6` | Define a coherent, bounded *all retained LibraryRefresh* history read, covering active and terminal JobRuns and direct Retry source/successor links; explicitly state retention boundary and atomicity/error behavior | No all-job global history, pruning, silent truncation, or inferred ScanRun ownership |
| `SPEC-BE-015 §21` | Permit a distinct observer-owned ordinary read-only RevisionFenced first-to-terminal enumeration for the approved All-active fixed query and same-view direct GetGame lookups | Observer result is NOT the Flutter UI controller's query; original membership/redirect coherence and no cross-revision stitching remain unchanged |
| `docs/qualification/android-job-lifecycle.md` and host typed evidence contract | Admit separately named authenticated product-backend observations for committed membership, Job identity and refresh history; require distinct OS and UI evidence; define fail-closed outcomes, provenance, G3/G4/G5 crosswalk | Frozen AND-04/05 operations and original outcome rules remain operative until formally repinned |
| `docs/qualification/android-library-interactions.md` and C5 adapter/oracle | Separate committed-membership proof (typed backend) from rendering/interaction proof (accessibility). Retain C5's original one-capture rule for claims that explicitly require one UI hierarchy | No multi-capture stitching, no reinterpretation of a backend query as UI capture; missing UI semantics BLOCKED |
| Observer wire contract / Android host integration | Specify versioned closed read-only operations: runtime readiness; GetJob; bounded complete refresh history; complete revision-fenced Library membership + required directs. Include Busy, stale, incomplete, timeout, cancellation, identity, session and size errors | No generic FRB bridge, SQL, filesystem, app mutation, process keepalive, or observer-generated launch |
| `ADR-001` exact-distributable smoke / relevant qualification plan | Add separately authorized checks that advanced diagnostics default OFF and socket cannot be reached while OFF | Smoke remains data-preserving and distinct from qualification-variant lifecycle work; no ordinary-app full AND-04/05 |
| Physical evidence/latency criteria | Add private typed-identity receipts and sanitized shared assertions, OS checkpoints, matchable diagnostics-enabled latency calibration | No raw XML, private ROM paths, serials, raw tokens/cursors, unspecified p95 thresholds, or invented PAC/TAC names |

The protocol's numeric limits, storage bounds, exact wire framing, OS command allowlist and actual peer UID are **engineering investigations**, not owner-approved values. Measure/prove these before proposing final contract fields. Library mutation races and process loss invalidate an observation (Q15, Q34); no silent restart. Complete Jobs history uses one bounded coherent read (Q6/Q16), not offset paging.

## 3. Gate definitions and evidence classes

| Proposed gate | Scope | Essential evidence |
| --- | --- | --- |
| **G3 — admission and baseline** | Before AND-04/AND-05 effectful operations | Exact target and qualification signed APK/base/splits/signer, OS readiness, authorized installed fixture-only/no-reset state, all retained refresh history, committed Library baseline, diagnostics enabled during preparation, observer readiness and pending-cleanup safety |
| **G4 — AND-04** | Original 31-operation background/return sequence | Active refresh and typed parent/child progress, complete state, background OS checkpoint, same *existing* Android task upon return, expected foreground/UI, truthful restoration and evidence |
| **G5 — AND-05** | Original 45-operation process-loss/Retry sequence | Pre-stop complete state, authorized force-stop and independent process-loss OS evidence, authorized relaunch (no same-task requirement across force-stop), durable committed membership/redirects, correct root attribution, no silent resume, at most one eligible explicit Retry, successor terminalization and cleanup |

Evidence classes: `P` = authoritative product backend read (not independent backend correctness oracle); `U` = ordinary visible Flutter/accessibility state; `O` = independent Android OS package/process/foreground/task data; `H` = admitted host action and private owner/session/fixture authority. Claims must name their actual source, not label a combined adapter as a second backend. The source fields in the crosswalk below describe a **proposed proof obligation** to be translated into versioned PAC/TAC criteria; they are not newly active acceptance oracles.

### G4 — AND-04 operation-level proposed crosswalk

| Op | Gate | Frozen operation (category) | Candidate evidence source | Proposed observable assertion (subject to exact contract review) |
| --- | --- | --- | --- | --- |
| AND-04-01 | G3 prerequisite → G4 | `no_reset_baseline` (read_only) | OS + product + private fixture authority | Exact qualification package/artifact/signer; fixture-only/no-reset Library, all retained refresh Jobs, no unresolved cleanup |
| AND-04-02 | G3 prerequisite → G4 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-04-03 | G3 prerequisite → G4 | `library_ready` (read_only) | UI + product | Expected Library state reachable; independent membership claim requires complete read-only backend proof |
| AND-04-04 | G3 prerequisite → G4 | `navigate_jobs` (navigation) | UI + host action receipt | Jobs destination and selected state verified |
| AND-04-05 | G3 prerequisite → G4 | `jobs_preflight` (read_only) | UI + bounded Jobs history | All retained refresh runs and required active history agree with admitted baseline; no unexplained duplicates |
| AND-04-06 | G3 prerequisite → G4 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-04-07 | G4 | `start_library_refresh` (refresh) | Authorized host effect + product | Exactly one approved refresh admitted; parent JobRun identity bound to operation |
| AND-04-08 | G4 | `refresh_arrival` (read_only) | UI + product Job detail | Expected refresh detail arrives and identifies original parent JobRun |
| AND-04-09 | G4 | `refresh_progress` (read_only) | UI + product Job detail | Identified parent phase, status and progress are coherent; no child counter substituted |
| AND-04-10 | G4 | `refresh_progress` (read_only) | UI + product Job detail | Identified parent phase, status and progress are coherent; no child counter substituted |
| AND-04-11 | G4 | `navigate_jobs` (navigation) | UI + host action receipt | Jobs destination and selected state verified |
| AND-04-12 | G4 | `jobs_active` (read_only) | UI + product Jobs read | Exact active parent is visible and no duplicated refresh is inferred |
| AND-04-13 | G4 | `open_refresh_detail` (navigation) | UI + host action receipt | Selected detail is bound to intended parent JobRun |
| AND-04-14 | G4 | `refresh_detail` (read_only) | UI + coherent GetJob | Parent status, progress and requested root coverage match the authoritative detail |
| AND-04-15 | G4 | `parent_child_identity` (read_only) | Coherent GetJob + UI | Exact parent JobRun, admitted roots, one ScanRun per root and exclusions/Retry identity checked |
| AND-04-16 | G4 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-04-17 | G4 | `library_active` (read_only) | UI + revision-fenced Library read | Library interactive during refresh; complete membership asserted only by separate authorized view |
| AND-04-18 | G4 | `background_qualification_package` (launch) | Authorized host lifecycle effect | Background exactly the approved package/task |
| AND-04-19 | G4 | `process_foreground` (read_only) | Android OS checkpoint | Exact package process and foreground state at checkpoint; do not infer continuity from PID reuse |
| AND-04-20 | G4 | `return_existing_qualification_task` (launch) | Authorized host return + OS task | Return to the identical pre-background task (AND-04 only), not a newly launched task |
| AND-04-21 | G4 | `foreground_surface` (read_only) | Android OS + UI | Expected foreground package and visible surface at checkpoint |
| AND-04-22 | G4 | `navigate_jobs` (navigation) | UI + host action receipt | Jobs destination and selected state verified |
| AND-04-23 | G4 | `jobs_returned` (read_only) | UI + product Jobs read | Same original parent and consistent lifecycle after background/return |
| AND-04-24 | G4 | `open_refresh_detail` (navigation) | UI + host action receipt | Selected detail is bound to intended parent JobRun |
| AND-04-25 | G4 | `recovered_lifecycle` (read_only) | UI + coherent GetJob | Expected lifecycle and parent/child relationships recovered without silent duplicate or resume |
| AND-04-26 | G4 | `navigate_sources` (navigation) | UI + host action receipt | Sources destination selected |
| AND-04-27 | G4 | `open_scan_root` (navigation) | UI + host action receipt | Correct admitted LibraryRoot selected |
| AND-04-28 | G4 | `scan_root_state` (read_only) | UI + coherent GetJob | Root/ScanRun/owner JobRun association and scan state match, not inferred from View Job label |
| AND-04-29 | G4 | `open_scan_job_detail` (navigation) | UI + host action receipt | View Job leads to identified parent, not inferred ownership |
| AND-04-30 | G4 | `scan_job_lifecycle` (read_only) | UI + coherent GetJob | Exact ScanRun/parent ownership and lifecycle consistent |
| AND-04-31 | G4 | `restore_qualification_foreground` (launch) | Authorized host task action + OS/UI | Restore approved foreground and task without fresh-task substitution |

### G5 — AND-05 operation-level proposed crosswalk

| Op | Gate | Frozen operation (category) | Candidate evidence source | Proposed observable assertion (subject to exact contract review) |
| --- | --- | --- | --- | --- |
| AND-05-01 | G3 prerequisite → G5 | `no_reset_baseline` (read_only) | OS + product + private fixture authority | Exact qualification package/artifact/signer; fixture-only/no-reset Library, all retained refresh Jobs, no unresolved cleanup |
| AND-05-02 | G3 prerequisite → G5 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-05-03 | G3 prerequisite → G5 | `library_ready` (read_only) | UI + product | Expected Library state reachable; independent membership claim requires complete read-only backend proof |
| AND-05-04 | G3 prerequisite → G5 | `navigate_jobs` (navigation) | UI + host action receipt | Jobs destination and selected state verified |
| AND-05-05 | G3 prerequisite → G5 | `jobs_preflight` (read_only) | UI + bounded Jobs history | All retained refresh runs and required active history agree with admitted baseline; no unexplained duplicates |
| AND-05-06 | G3 prerequisite → G5 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-05-07 | G5 | `start_library_refresh` (refresh) | Authorized host effect + product | Exactly one approved refresh admitted; parent JobRun identity bound to operation |
| AND-05-08 | G5 | `refresh_arrival` (read_only) | UI + product Job detail | Expected refresh detail arrives and identifies original parent JobRun |
| AND-05-09 | G5 | `refresh_progress` (read_only) | UI + product Job detail | Identified parent phase, status and progress are coherent; no child counter substituted |
| AND-05-10 | G5 | `refresh_progress` (read_only) | UI + product Job detail | Identified parent phase, status and progress are coherent; no child counter substituted |
| AND-05-11 | G5 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-05-12 | G5 | `library_preloss` (read_only) | UI + revision-fenced Library read | Capture complete pre-loss committed GameId baseline/redirect facts under fixed All-active query |
| AND-05-13 | G5 | `navigate_sources` (navigation) | UI + host action receipt | Sources destination selected |
| AND-05-14 | G5 | `open_scan_root` (navigation) | UI + host action receipt | Correct admitted LibraryRoot selected |
| AND-05-15 | G5 | `scan_root_preloss` (read_only) | UI + coherent GetJob | Record identified root/ScanRun/parent tuple before stop |
| AND-05-16 | G5 | `navigate_jobs` (navigation) | UI + host action receipt | Jobs destination and selected state verified |
| AND-05-17 | G5 | `open_refresh_detail` (navigation) | UI + host action receipt | Selected detail is bound to intended parent JobRun |
| AND-05-18 | G5 | `refresh_detail` (read_only) | UI + coherent GetJob | Parent status, progress and requested root coverage match the authoritative detail |
| AND-05-19 | G5 | `parent_child_identity` (read_only) | Coherent GetJob + UI | Exact parent JobRun, admitted roots, one ScanRun per root and exclusions/Retry identity checked |
| AND-05-20 | G5 | `pre_stop_guard` (read_only) | UI + product + OS | All required pre-loss identity, history, membership, and authorized scope prerequisites satisfied |
| AND-05-21 | G5 | `force_stop_qualification_package` (force_stop) | Authorized host force-stop + OS | Exactly scoped stop; subsequent independent OS observation must establish process loss |
| AND-05-22 | G5 | `process_foreground` (read_only) | Android OS checkpoint | Exact package process and foreground state at checkpoint; do not infer continuity from PID reuse |
| AND-05-23 | G5 | `launch_qualification_package` (launch) | Authorized host launch + OS | Approved package relaunched after independently observed process loss; no same-task requirement |
| AND-05-24 | G5 | `foreground_surface` (read_only) | Android OS + UI | Expected foreground package and visible surface at checkpoint |
| AND-05-25 | G5 | `navigate_sources` (navigation) | UI + host action receipt | Sources destination selected |
| AND-05-26 | G5 | `open_scan_root` (navigation) | UI + host action receipt | Correct admitted LibraryRoot selected |
| AND-05-27 | G5 | `scan_root_recovered` (read_only) | UI + coherent GetJob | Recovered root and exact original ScanRun attribution, with documented active/terminal transition |
| AND-05-28 | G5 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-05-29 | G5 | `library_recovered` (read_only) | UI + revision-fenced Library read | Every required prior committed GameId retained or direct-redirect proven against complete current view |
| AND-05-30 | G5 | `navigate_jobs` (navigation) | UI + host action receipt | Jobs destination and selected state verified |
| AND-05-31 | G5 | `jobs_recovered` (read_only) | UI + complete retained refresh history | No unexpected duplicate or silently resumed JobRun; original parent preserved |
| AND-05-32 | G5 | `open_refresh_detail` (navigation) | UI + host action receipt | Selected detail is bound to intended parent JobRun |
| AND-05-33 | G5 | `recovered_lifecycle` (read_only) | UI + coherent GetJob | Expected lifecycle and parent/child relationships recovered without silent duplicate or resume |
| AND-05-34 | G5 | `retry_eligibility` (read_only) | UI + coherent GetJob + completed guards | Exact original JobRun eligible and all prerequisite assertions passed before effect |
| AND-05-35 | G5 | `retry_library_refresh` (refresh) | Authorized one-time host effect + product | At most one explicit Retry with separately identified successor; no replay on uncertainty |
| AND-05-36 | G5 | `retry_outcome` (read_only) | UI + coherent GetJob | Successor outcome and progress/status come from its own detail |
| AND-05-37 | G5 | `retry_relation` (read_only) | Coherent source/successor GetJob | Direct source-to-successor relationship and distinct JobRun identities checked |
| AND-05-38 | G5 | `navigate_library` (navigation) | UI + host action receipt | Required Library destination selected without unauthorized effects |
| AND-05-39 | G5 | `library_persisted` (read_only) | UI + revision-fenced Library read | Recovered pre-Retry committed baseline not lost by Retry; same-token redirect proof where required |
| AND-05-40 | G5 | `navigate_sources` (navigation) | UI + host action receipt | Sources destination selected |
| AND-05-41 | G5 | `open_scan_root` (navigation) | UI + host action receipt | Correct admitted LibraryRoot selected |
| AND-05-42 | G5 | `scan_root_state` (read_only) | UI + coherent GetJob | Root/ScanRun/owner JobRun association and scan state match, not inferred from View Job label |
| AND-05-43 | G5 | `navigate_jobs` (navigation) | UI + host action receipt | Jobs destination and selected state verified |
| AND-05-44 | G5 | `open_retry_successor_detail` (navigation) | UI + host action receipt | Open specifically identified successor JobRun |
| AND-05-45 | G5 | `retry_successor_terminal` (read_only) | UI + coherent successor GetJob | Successor reaches required terminal state with consistent related roots |

### Existing PAC/TAC nomenclature

Issue #28 and the reviewed qualification source do not supply canonical PAC/TAC identifiers for every AND-04/05 assertion. **Do not invent them.** Independent review must associate each row above with real owner-approved acceptance criteria and gate records, preserving criterion identity and provenance. Operation rows alone do not pass a PAC/TAC.

## 4. Result classification and blocked dependent effects

| Proven event | Qualification classification |
| --- | --- |
| Complete product/OS/UI evidence meets the specified assertion and pinned expectation | `PASSED` |
| Coherent evidence conclusively demonstrates wrong artifact, identity, root ownership, missing committed GameId without required direct redirect, or another wrong product result | `FAILED` |
| Socket Busy, bad/inapplicable peer UID, timeouts, ambiguous process/task, stale view, changed Library revision, insufficient UI semantics, incomplete history, missing target proof or oversized output | `BLOCKED` |
| Any operation not executed because a prerequisite was blocked/failed | `NOT_RUN` |

A failed observer attempt must be recorded with bounded sanitized provenance, not hidden by transparent retries. No observed same PID after an unobserved gap proves continuous process life (Q20). For AND-04, task continuity requires OS-backed same-task identity at background/return (Q26); for AND-05, the force-stop boundary intentionally breaks that requirement (Q30). No product read proves OS foreground/task/process state. Host approval does not replace independent installed binary/signer identity.

## 5. Runtime and privacy invariants

1. Trust owner-controlled ADB host with existing owner/session admission; require target-qualified peer UID, allowlisted read operations and bounded outputs, but no new PKI. Unverified UID/forwarding access => NO-GO for that mechanism, not authority to downgrade.
2. Ship identical observer implementation in qualification and distributable Release; diagnostics default OFF via Advanced setting, persist enablement across process death, and verify OFF during authorized cleanup. Listener exists only in a live application process and must not cold-start or keep it alive.
3. Serialized observer operations; concurrent attempt => typed Busy, no partial facts. Observer can issue separate read-only backend enumeration while app is already running but cannot create Flutter controller, navigate, mutate, launch or run during a controlled process-loss checkpoint.
4. Library proof executes internally from first page to terminal and required direct same-token GetGame lookups; never export raw token/cursor values. One changed revision, duplicate, missing page, process restart, or unprovable redirect invalidates the whole attempt. A new attempt is distinct and cannot repair the original.
5. Jobs history covers all retained LibraryRefresh, including active/terminal, preexisting and Retry relations, within a single bounded consistent transaction/read. Exceeding the measured resource ceiling is BLOCKED; no new deletion or retention policy.
6. Exact typed identities may cross the local owner-private channel; shared evidence contains only aliases/digests and source/provenance, not ROM paths, raw XML, device identifiers, or credentials. Broad OS diagnostics can only be transient inputs for package-scoped sanitized facts and require separately approved command scope.
7. Cleanup failure is recorded and remediated only under separate owner authority; do not reset app state to reestablish the diagnostics default. Match diagnostics state/workload for latency calibration and candidate qualification, without changing measured thresholds without approval.

## 6. Verification prerequisites and implementation order

1. **Documentation review:** Independent Standards and Spec review of ADR-005 + decision log + proposed crosswalk; reconcile exact parent/root/Retry evidence and original C5 oracles without inventing criteria.
2. **Versioned contract review:** Propose and independently review revisions to the cited backend, UI/C5 and host evidence contracts, typed protocol and OS allowlist. Repin all affected artifacts/rules deliberately, retaining historical evidence.
3. **Physical feasibility (separate owner authorization):** Verify target-specific ADB forwarding/socket accessibility, peer UID, diagnostics OFF/default and ON readiness, no cold start or lifecycle effects, permitted OS sources for package/signer/process/foreground/same-task, and privacy-limited filtering. Record NO-GO for unsupported mechanisms. Do not run here.
4. **ADR Complete eligibility (Q36):** Only after independently reviewed architectural/contract reconciliation and essential target physical feasibility, with owner approval. This is separate from AND-04/AND-05 execution, G3/G4/G5 passing, owner verdicts and latency qualification.
5. **Implementation/qualification:** New isolated reviewed tasks/PRs and separately pinned owner-authorized sessions; #28/#57/#68 remain open until their distinct acceptance obligations are met.

No device actions, production code edits, oracle activation, protocol/contract version bump, or approval of a final physical architecture occur through publication of this proposal.
