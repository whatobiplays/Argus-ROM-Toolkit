# Android job lifecycle recovery qualification boundary

This document describes the private host-only Issue #28 plan for AND-04 and
AND-05. Host tests validate the closed operation plans, admission bindings,
recovery classifications, evidence behavior, and fail-closed observations.
They do not run Android, observe a physical job, or issue an owner verdict.

## 1. Execution boundary

Issue #28 adds a third private authorization profile, `JOB_LIFECYCLE`, with a
dedicated loader that accepts only the exact AND-04 and AND-05 operation
schemas. The legacy and Library-interaction profiles keep their existing
parsers, operation limits, executors, and pins. No public command or live
transport is added.

The lifecycle executor is a separate private class. It reuses the shared
owner-approval validation, session claim, EvidenceStore writer, UTC deadline
checks, monotonic call budget, and fail-closed session shell. It does not
inherit the Issue #26 scan/fixture executor or the Issue #27 Library executor.
The shared dispatch function admits the lifecycle executor only by exact type;
subclasses and unrelated executors are rejected.

Admission requires a no-reset session for
`com.argusromtoolkit.argus.qualification`, the pinned APK and certificate
digests, the expected source revision and version code, the exact plan digest,
an owner approval valid for the execution window, an independently observed
baseline, and no pending cleanup or restoration obligation. The session
capability is one-use and the owner approval remains bound to the canonical
authorization digest.

Lifecycle admission passes a bounded timeout to the baseline observer and
checks monotonic elapsed time before accepting the returned baseline. An
observation returned at or after its timeout is blocked. This post-call check
rejects an overdue return; it cannot interrupt an observer that never returns,
so a hard interruption guarantee requires a cooperative or separately
controlled physical observer.

## 2. Authorization flow

The owner provisions an authorization document and an owner-private approval
sidecar. The lifecycle loader computes the canonical authorization digest from
the supplied document. `OwnerApproval.authorization_sha256` must equal that
digest; this shared invariant is unchanged. Separately, the lifecycle loader
computes the plan digest from the scenario, artifact identity, rules digest,
and every operation identifier, category, phase, timeout, and argument. The
independently computed plan digest must equal `authorization.plan_sha256`, and
the admitted session binding must pin the same value.

Each operation grant is bound to the exact operation identifier, scenario,
package, category, phase, timeout, and arguments in the approved plan. The
executor rejects a reordered, missing, extra, or invented operation before it
claims the capability. A refused or uncertain effect stops the session; no
operation is replayed under the same grant.

The authorization document uses UTC timestamps for issuance, approval validity,
the session deadline, and the cleanup deadline. Elapsed time, operation
timeouts, and latency measurements use monotonic clocks. The existing typed
evidence schema is unchanged. A blocked or undecided obligation is recorded as
`BLOCKED`; a dependent operation that was not run is recorded as `NOT_RUN`.
There is no persisted `NOT_APPLICABLE` outcome and no new event variant.

The lifecycle contract and capability versions are 3. The oracle version is
4. The AND-05 capability declaration names the fresh Retry-relation
precondition. Previous v2 contract, v2 capability, and v3 oracle bindings are
rejected for both scenarios. Legacy, Issue #26, and Issue #27 pins are
unaffected.

## 3. AND-04 operation table

AND-04 has 31 operations. Its raw timeout sum is 575 seconds.

| # | Category | Operation | Timeout (s) |
|---:|---|---|---:|
| 1 | read_only | `no_reset_baseline` | 30 |
| 2 | navigation | `navigate_library` | 10 |
| 3 | read_only | `library_ready` | 20 |
| 4 | navigation | `navigate_jobs` | 10 |
| 5 | read_only | `jobs_preflight` | 20 |
| 6 | navigation | `navigate_library` | 10 |
| 7 | refresh | `start_library_refresh` | 30 |
| 8 | read_only | `refresh_arrival` | 20 |
| 9 | read_only | `refresh_progress` | 30 |
| 10 | read_only | `refresh_progress` | 30 |
| 11 | navigation | `navigate_jobs` | 10 |
| 12 | read_only | `jobs_active` | 20 |
| 13 | navigation | `open_refresh_detail` | 10 |
| 14 | read_only | `refresh_detail` | 20 |
| 15 | read_only | `parent_child_identity` | 15 |
| 16 | navigation | `navigate_library` | 10 |
| 17 | read_only | `library_active` | 20 |
| 18 | launch | `background_qualification_package` | 10 |
| 19 | read_only | `process_foreground` | 15 |
| 20 | launch | `return_existing_qualification_task` | 30 |
| 21 | read_only | `foreground_surface` | 15 |
| 22 | navigation | `navigate_jobs` | 10 |
| 23 | read_only | `jobs_returned` | 20 |
| 24 | navigation | `open_refresh_detail` | 10 |
| 25 | read_only | `recovered_lifecycle` | 60 |
| 26 | navigation | `navigate_sources` | 10 |
| 27 | navigation | `open_scan_root` | 10 |
| 28 | read_only | `scan_root_state` | 20 |
| 29 | navigation | `open_scan_job_detail` | 10 |
| 30 | read_only | `scan_job_lifecycle` | 20 |
| 31 | launch | `restore_qualification_foreground` | 20 |

Operation 20 returns the existing qualification task to the foreground. It
requires the exact package and the original task-continuity reference; it does
not perform a fresh launch. A missing task reference or an unproven foreground
return blocks the session.

## 4. AND-05 operation table

AND-05 has 45 operations. Its raw timeout sum is 880 seconds.

| # | Category | Operation | Timeout (s) |
|---:|---|---|---:|
| 1 | read_only | `no_reset_baseline` | 30 |
| 2 | navigation | `navigate_library` | 10 |
| 3 | read_only | `library_ready` | 20 |
| 4 | navigation | `navigate_jobs` | 10 |
| 5 | read_only | `jobs_preflight` | 20 |
| 6 | navigation | `navigate_library` | 10 |
| 7 | refresh | `start_library_refresh` | 30 |
| 8 | read_only | `refresh_arrival` | 20 |
| 9 | read_only | `refresh_progress` | 30 |
| 10 | read_only | `refresh_progress` | 30 |
| 11 | navigation | `navigate_library` | 10 |
| 12 | read_only | `library_preloss` | 20 |
| 13 | navigation | `navigate_sources` | 10 |
| 14 | navigation | `open_scan_root` | 10 |
| 15 | read_only | `scan_root_preloss` | 20 |
| 16 | navigation | `navigate_jobs` | 10 |
| 17 | navigation | `open_refresh_detail` | 10 |
| 18 | read_only | `refresh_detail` | 20 |
| 19 | read_only | `parent_child_identity` | 15 |
| 20 | read_only | `pre_stop_guard` | 20 |
| 21 | force_stop | `force_stop_qualification_package` | 10 |
| 22 | read_only | `process_foreground` | 15 |
| 23 | launch | `launch_qualification_package` | 30 |
| 24 | read_only | `foreground_surface` | 15 |
| 25 | navigation | `navigate_sources` | 10 |
| 26 | navigation | `open_scan_root` | 10 |
| 27 | read_only | `scan_root_recovered` | 20 |
| 28 | navigation | `navigate_library` | 10 |
| 29 | read_only | `library_recovered` | 30 |
| 30 | navigation | `navigate_jobs` | 10 |
| 31 | read_only | `jobs_recovered` | 20 |
| 32 | navigation | `open_refresh_detail` | 10 |
| 33 | read_only | `recovered_lifecycle` | 60 |
| 34 | read_only | `retry_eligibility` | 20 |
| 35 | refresh | `retry_library_refresh` | 60 |
| 36 | read_only | `retry_outcome` | 30 |
| 37 | read_only | `retry_relation` | 15 |
| 38 | navigation | `navigate_library` | 10 |
| 39 | read_only | `library_persisted` | 20 |
| 40 | navigation | `navigate_sources` | 10 |
| 41 | navigation | `open_scan_root` | 10 |
| 42 | read_only | `scan_root_state` | 20 |
| 43 | navigation | `navigate_jobs` | 10 |
| 44 | navigation | `open_retry_successor_detail` | 10 |
| 45 | read_only | `retry_successor_terminal` | 60 |

Operations 13 through 15 capture the pre-loss Sources root presentation.
The root observation must identify the authorized root and exactly one
`View Job` run. Its presentation is either an active scan with no historical
last-scan state, or a historical last scan with one terminal scan state. A
missing presentation, an unidentified root, or a missing run identity blocks
the session before the controlled stop. This observation does not establish
that the root's `View Job` run is a child of the tested Library Refresh.

Operations 25 through 29 run after relaunch and before Retry. Operation 27
compares the recovered root with the pre-loss root. The root identity and the
`View Job` run identity must match. A historical presentation must keep the
same last-scan state. An active presentation that becomes historical is
accepted only when the run identity is unchanged. A root that remains active,
reactivates, changes identity, or loses its presentation records `BLOCKED`.

Operation 29 compares the exact recovered Library membership identities with
the identities captured at operation 12. Counts, row order, titles, and
screenshots do not substitute for identities. Every captured identity must
remain committed; a missing identity records `FAILED`, while unavailable or
incomplete identity evidence records `BLOCKED`. Newly committed assets may
appear. Operation 35 does not dispatch Retry unless both operation 27 and
operation 29 passed. A blocked or failed persistence check therefore prevents
Retry from recreating a lost asset before the persistence assertion runs.

Operations 35 through 37 separate three claims. Operation 35 dispatches the
single authorized Retry only after the pre-Retry persistence gate passes and a
fresh relation lookup independently establishes that the verified source has
no Retry successor. The lookup must bind the exact parent JobRunId, frozen
scope, recovered terminal state, and complete previously verified child set;
the child identities must be unique and unchanged. The observation must state
that the current source relation lookup completed, bind that query to the same
parent, and establish that both successor identity and successor scope are
absent. A missing successor identifier alone is not proof of absence, and
contradictory or stale relation fields block before effect intent or dispatch.
This pre-Retry query fact is separate from the existing post-Retry
`source_run_ref` relationship semantics. Operation 36 observes the retry
outcome and requires one exact successor run
identity. Operation 37 checks that the successor's source, frozen scope,
successor identity, and successor scope match the observed refresh. Neither
operation infers identity from row order, labels, or timing.

Operation 39 re-observes the Library after Retry and compares it with the
identities recovered at operation 29, not with the original pre-loss snapshot.
The post-Retry integrity check therefore remains separate from the
process-recovery persistence check. An identity that disappears after Retry
records `FAILED`; incomplete identity evidence records `BLOCKED`. Operation 42
re-observes the Sources root after Retry. It accepts an identified active or
historical presentation only when the root matches the authorized root and
the single `View Job` reference equals the verified Retry successor run. The
active form must carry no historical last-scan state; the historical form must
carry one terminal last-scan state. An accepted active presentation proves
current successor ownership of the root, not terminal completion of the
successor. Operation 42 never awards refresh-child attribution, and operation
45 remains the only terminal-success decision for the successor.

Operations 43 through 45 verify the retry successor without another effect.
Operation 43 navigates to Jobs. Operation 44 opens the successor detail only
when the observer supplied one exact successor identity. Operation 45 records
two separate claims: the successor reached a terminal state within the fixed
60-second window while the qualification package remained in the foreground,
and the retry outcome satisfies the pinned acceptance contract. `Completed`
satisfies Retry success. `CompletedWithIssues` remains `BLOCKED` unless an
immutable owner-approved criterion admits it. `Failed`, `Cancelled`, and
`Abandoned` record a `FAILED` Retry-success assertion even though the terminal
observation itself succeeded. An absent identity, a different identity, or a
successor that remains active at the deadline records `BLOCKED` and leaves
recovery with the owner. The executor does not dispatch a second retry.

## 5. Session and reserve accounting

Both scenarios keep a positive margin at the latest permitted admission. The
operation floor reserves one second for each operation; the evidence, state
check, and restoration reserves cover persistence, final state verification,
and foreground task restoration.

| Scenario | Raw timeouts | Operation floor | Evidence | State check | Restoration | Required span | Session | Margin at latest admission |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| AND-04 | 575 s | 31 s | 90 s | 45 s | 30 s | 771 s | 900 s | 69 s |
| AND-05 | 880 s | 45 s | 120 s | 60 s | 30 s | 1135 s | 1280 s | 85 s |

The cleanup window is a separate 120-second closure window after the session
deadline. A new session may start no later than 60 seconds after issuance.
Admission rejects an authorization whose session deadline or cleanup deadline
does not match the pinned span. Deadlines are never extended during execution.

## 6. Observation and identity limits

The refresh detail surface provides `RefreshProgressFacts`: phase, completed
units, total units, status key, and issue count when present. These are parent
refresh facts. LibraryScan child counters and generic "entries observed" text
do not establish committed refresh progress. Missing progress, a missing
status key, or conflicting progress records `BLOCKED` and stops dependent
operations. An issue count by itself also remains `BLOCKED`; it cannot
authorize a dependent effect.

The Jobs surface exposes refresh row and lifecycle status but not a durable
JobRunId. A row status is reported only when one accessibility node binds
exactly one `Library Refresh` title with exactly one lifecycle status, so a
neighbouring job status cannot be attributed to the refresh row. When the
capture cannot establish that binding, the row status and active-row count
are withheld and dependent operations record `BLOCKED`. The private executor
accepts a parent run identity only from an authorized independent observer. A
row position, matching label, or detail page title cannot supply identity. Jobs preflight compares complete observed
terminal-refresh history against the admitted
`JobLifecycleBaselineObservation.terminal_refresh_run_refs` and visible row
count. Extra, missing, substituted, duplicated, or paginated history blocks
before a Refresh effect. A refresh that became active after admission also
blocks.

The Sources root detail exposes the root identity and at most one `View Job`
run. A root observation must carry an explicit `ScanRootPresentation`.
`ACTIVE_SCAN` means the root shows an active scan and no historical last-scan
state. `HISTORICAL_LAST_SCAN` means the root shows one terminal last-scan
state. `UNIDENTIFIED`, a missing run identity, contradictory root identity, or
conflicting labels records `BLOCKED`. Operation 15 accepts an identified
active or historical pre-loss presentation. Operation 27 accepts a recovered
historical presentation with the same root and run identity, or an
active-to-historical transition with the same run identity. A root that
remains active, reactivates, changes identity, or loses its presentation
blocks before Retry. After Retry, operation 42 requires the same authorized
root and exactly one `View Job` reference equal to the verified successor run.
Either an identified active presentation with no historical last-scan state or
an identified historical presentation with one terminal last-scan state
passes. A foreign root, a stale last scan from the original refresh or another
job, a missing or duplicate `View Job` control, and contradictory state record
`BLOCKED`. The observed `view_job_run_ref` is a JobRunId, never a ScanRunId.
The active form records current successor ownership of the root; it does not
record terminal completion.

The root's `View Job` run is not a child of the tested LibraryRefresh until
the independent identity observer proves that run appears in the refresh's
child references. Operation 27 records that attribution as a separate
assertion: a matching run can pass root persistence while the child
attribution remains `BLOCKED`. Neither the Sources route nor a scan-detail
navigation awards parent-child identity by itself.

The Library surface exposes a membership count and fixed controls, but counts,
row order, titles, screenshots, and private database reads cannot substitute
for identity evidence. The pre-loss snapshot binds
`LibrarySurfaceObservation.membership_ids`; after relaunch every captured
identity must remain committed. Newly committed assets may appear, but a
missing captured identity is `FAILED`, and incomplete identity evidence is
`BLOCKED`. The post-Retry integrity check compares the Library with the
identities recovered before Retry, so a successful Retry cannot repair or hide
a process-recovery loss. The sanitized observation digest binds the sorted
membership identities, so different committed sets cannot share a digest. Raw
identifiers stay owner-private and outside shared evidence.

The executor records persistence intent and result as separate append-only
assertions. The recovery checks use the
`:root-preloss`, `:root-recovery-persistence`, `:refresh-child-attribution`,
`:process-recovery-persistence`, `:post-retry-integrity`, and
`:root-post-retry-active-scan` keys. The last key is appended only when an
accepted active presentation proves current successor ownership; a historical
pass records `:root-post-retry-integrity` alone. These assertions reuse the
existing typed evidence schema. No new event variant or persisted
`NOT_APPLICABLE` outcome is introduced.

Owner attestation can describe expected baseline values, but it does not
replace independent device observations. A missing observation remains
`BLOCKED`.

## 7. Recovery and failure matrix

| Observation or condition | Outcome | Dependent action |
|---|---|---|
| Parent refresh identity missing or ambiguous | `BLOCKED` | Dependent observations `NOT_RUN` |
| Parent and child identity not independently linked | `BLOCKED` | Child attribution and later claims `NOT_RUN` |
| Pre-loss Sources root presentation unidentified, run identity missing, or root identity contradictory | `BLOCKED` | No controlled stop; dependent operations `NOT_RUN` |
| Recovered Sources root remains active, changes run identity, or changes root identity | `BLOCKED` | No Retry; owner recovery |
| Recovered Sources root persistence passes but the `View Job` run is absent from the refresh child references | `BLOCKED` for child attribution | Root persistence may pass; no refresh-child claim |
| Committed Library asset identity missing after relaunch | `FAILED` | No Retry; owner recovery |
| Recovered Library identity evidence unavailable or incomplete | `BLOCKED` | No Retry; owner recovery |
| Pre-Retry root or Library persistence unverified | `BLOCKED` | Retry not dispatched |
| Fresh Retry-relation lookup is unavailable, incomplete, stale, contradictory, or does not prove absence of both successor identity and scope | `BLOCKED` | No Retry intent or dispatch; owner recovery |
| Refresh reaches a terminal state before the controlled stop | `BLOCKED` for process loss | Retry obligations `NOT_RUN`; completed state is not proof of interruption |
| `Completed` or `CompletedWithIssues` after the stop | `BLOCKED` as recovery proof | Retry remains undecided |
| `Interrupted` after a non-resumable refresh stop | `FAILED` | No retry or relaunch |
| `Active` after relaunch | `FAILED` as silent resumption | No retry |
| `Cancelled` without durable cancellation intent | `FAILED` | No retry |
| `Failed`, `Cancelled`, or `Abandoned` after observed process loss | Recovery consistency supported | Retry may proceed only through the approved eligibility check |
| Force-stop proof missing | `BLOCKED` | No relaunch, retry, cleanup, or product mutation |
| Force-stop, retry, background, relaunch, return, or restoration result uncertain | `BLOCKED` | Stop immediately; owner recovery required; never repeat the effect |
| Evidence append fails | `BLOCKED` | Preserve evidence; owner recovery required; no cleanup or product mutation |
| Retry is not advertised for the durable state | `NOT_RUN` | No retry dispatched |
| Retry successor identity or scope differs from the observed source | `BLOCKED` | No second retry; owner recovery |
| Retry was dispatched without eligibility | `FAILED` | No second retry |
| Source run already has a retry successor | `BLOCKED` | No second retry |
| Jobs preflight history differs from the admitted baseline | `BLOCKED` | No Refresh effect; owner recovery |
| Jobs preflight shows a newly active refresh | `BLOCKED` | No Refresh effect; admission prerequisite changed |
| Successor remains active at the 60-second bound | `BLOCKED` | Owner recovery; no second retry |
| Successor terminal but qualification foreground unproven | `BLOCKED` | Owner recovery |
| Successor terminal with `CompletedWithIssues` and no pinned criterion | `BLOCKED` for Retry success | Terminal observation may pass; owner recovery; no second retry |
| Successor terminal with `Failed`, `Cancelled`, or `Abandoned` | `FAILED` for Retry success | Terminal observation may pass; no second retry |
| Successor identity wrong or ambiguous | `BLOCKED` | No row-order or timing inference |
| Post-Retry root is a different Sources root than the authorized root | `BLOCKED` | No terminal-success claim; owner recovery |
| Post-Retry `View Job` reference is not the verified Retry successor | `BLOCKED` | No refresh-child or terminal attribution; owner recovery |
| Post-Retry root shows a stale historical last scan from the previous refresh or another job | `BLOCKED` | No terminal-success claim; owner recovery |
| Post-Retry `View Job` control is missing, duplicated, or its run identity is absent | `BLOCKED` | No terminal-success claim; owner recovery |
| Post-Retry root shows both active and historical state, or neither identified presentation | `BLOCKED` | No terminal-success claim; owner recovery |
| Scan detail names a different run than the root `View Job` control | `FAILED` | Sources route never awards refresh-child attribution |
| Post-Retry Library asset identity missing | `FAILED` | No second Retry; owner recovery |
| Post-Retry Library identity evidence missing or incomplete | `BLOCKED` | No second Retry; no count, order, title, or database substitution |
| Foreground return or task continuity fails in AND-04 | `FAILED` for recovery consistency | No fresh-launch substitution |

`BLOCKED` means the available evidence cannot decide the assertion. `FAILED`
means an observed product outcome contradicts the pinned contract. A blocked
process-loss scenario is not a product failure by itself, and a supported
recovery state does not prove that the controlled interruption occurred.

## 8. Latency contract

The host-only slice ships the typed latency measurement contract with
execution disabled. The contract requires five warmup cycles, twenty measured
cycles, and the nearest-rank 95th percentile in integer milliseconds. Each cycle names an
action, records whether its return completed, carries an evidence reference,
and uses a monotonic elapsed duration. Evaluation also requires confirmed
active-work overlap and an owner-pinned rule containing the workload and
environment references, rule digest, per-cycle timeout, 95th-percentile ceiling, and
action identifiers.

An absent rule, unapproved ceiling, missing active overlap, incomplete cycle
count, incomplete return, or missing evidence records `BLOCKED`. Host
fake-clock tests do not create a physical latency verdict. Executing the 25
cycles requires separately approved physical authorization and per-cycle
bounds.

## 9. Physical qualification blockers

Physical admission remains blocked until permitted independent surfaces can
verify the exact package and artifact, no-reset Library and job baseline,
parent and child run identities, retry source and successor identity, process
presence and task continuity, committed Library state, scan-root and scan-job
relationships, and pending cleanup and restoration facts.

The pinned refresh detail does not expose a JobRunId. The Sources root-detail
route does not link its `View Job` control to the tested refresh child. The
current accessibility parser also raises an ambiguous-surface block when an
active Sources root shows `Scanning in progress` next to `View Job`, so it
cannot identify an active scan presentation. It reports a last-scan label, but
that label alone does not establish whether the root is showing an active scan
or a historical last scan, and it does not establish the run identity.
Physical operations 15, 27, and 42 therefore remain `BLOCKED` until separate
G5 transport work supplies an authorized independent observer for the explicit
presentation and exact run identity. Operation 42 additionally requires that
observer to bind the single `View Job` reference to the verified Retry
successor.

The accessibility parser exposes a Library membership count but not the exact
committed asset identities required by operations 12 and 29. A count or row
title cannot substitute for those identities. Physical Library recovery and
post-Retry integrity therefore remain `BLOCKED` until an authorized observer
can supply identity-bound membership evidence. The qualification UI also does
not independently prove foreground process loss or task continuity. These
gaps keep AND-04 and AND-05 physical qualification `BLOCKED` even when host
tests pass.

The Jobs accessibility parser binds a row status to the tested refresh row
only inside one merged accessibility node. The pinned production surface has
not yet demonstrated that binding, so physical Jobs state remains `BLOCKED`
until one capture shows the title and exactly one lifecycle status occurrence
in the same node and an authorized independent observer confirms the row
identity. Jobs classification also requires one selected Jobs destination and
a separate Jobs page title. A populated page may contain one or both standalone
`Active` and `Recent` section markers. It must have a separate row node
containing exactly one `Library Refresh` or `Library Scan` title and exactly
one lifecycle status occurrence. Missing, duplicate, or conflicting row
statuses block classification. An empty page requires one `No jobs yet` marker and no
lifecycle row. The raw `Active` or `Recent` label alone is insufficient.
Flutter defines selected navigation state, but Android accessibility has not
been physically verified to expose it. Missing or ambiguous selected-state or
page structure remains `BLOCKED`.

G3, G4, and G5 remain separate owner-authorized physical gates. No host test,
CI run, or synthetic observation may claim Android physical qualification or
an owner verdict.

## 10. Changed-path inventory

The host-only implementation changes only these paths:

| Path | Change | Reason |
|---|---|---|
| `scripts/android_qualification/manifest.py` | Modified | Narrow `JOB_LIFECYCLE` profile and private loader; approved task-scope exception |
| `scripts/android_qualification/admission.py` | Modified | Exact-type lifecycle admission, one-use capability, and private binding |
| `scripts/android_qualification/_job_lifecycle_contract.py` | Added | Closed operation plans, plan digest, and typed observations |
| `scripts/android_qualification/_job_lifecycle_oracle.py` | Added | Recovery, progress, retry, process, and latency classification |
| `scripts/android_qualification/_job_lifecycle_executor.py` | Added | Standalone lifecycle executor and evidence integration |
| `scripts/android_qualification/physical/_job_lifecycle_ui.py` | Added | Bounded accessibility parser for the five lifecycle surfaces |
| `scripts/android_qualification/physical/ui.py` | Modified | Shared bounded UI parser and action primitives used by lifecycle surfaces |
| `scripts/android_qualification/test_job_lifecycle.py` | Added | Contract, manifest, admission, oracle, and executor tests |
| `scripts/android_qualification/physical/test_job_lifecycle_ui.py` | Added | Surface parser tests |
| `docs/qualification/android-job-lifecycle.md` | Added | This qualification boundary |
| `docs/qualification/README.md` | Modified | Link to the Issue #28 boundary |
| `docs/qualification/device-authorization.md` | Modified | Narrow lifecycle authorization note; approved task-scope exception |
| `docs/qualification/surface-classifications-v1.json` | Modified | Register six active Issue #28 surfaces; totals become 134 and 86 active |
| `scripts/android_qualification/test_repository_checks.py` | Modified | Keep the pinned current-inventory assertion aligned with the approved registry rows |
| `docs/tasks/task-p003-028-android-job-lifecycle-recovery.md` | Added | Owner task copy and final Completion Result |

No Flutter, Rust, Android native, product runtime, database schema, generated
code, public CLI, or retired archive path is changed.
