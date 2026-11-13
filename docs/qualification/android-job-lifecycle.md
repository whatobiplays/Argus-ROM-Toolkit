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

Lifecycle observations accept only exact `RecoveryState` enum values when a
state is present. Jobs preflight and identity observations may omit their
optional state; an operation that requires a state blocks when it is missing
or malformed. Valid terminal states remain recognized by the observation
contracts, with each operation enforcing its own state requirement. Process
observations use the shared oracle: unavailable evidence, a malformed process
state, or a missing observer identity is `BLOCKED`. With a valid observer
identity, a foreign package or a contradictory typed process state is
`FAILED`. An unsuccessful pre-effect check stops before intent and dispatch.
An uncertain result after an effect requires owner recovery and never triggers
an automatic replay.
An intent append does not prove transport dispatch: if the call budget expires
before the transport callback is entered, navigation is recorded as blocked
and not dispatched. An unverified result after callback entry remains
uncertain and requires owner recovery.

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

The active lifecycle contract is version 5, the capability is version 4, and
the oracle is version 9. Capability v4 binds one admitted LibraryRefresh
JobRun to per-root ScanRuns. Each relation uses the tuple `(parent JobRunId,
ScanRunId, LibraryRootId)`. Source and Retry-successor ScanRun ID sets must be
disjoint. The capability digest remains
`919d3bcf6e692a2936c53af929334326b54df60cd3c7089e0a5083fb7c691644`.

Oracle v9 preserves the independent lookup checks at operations 36 and 37 and
adds the same source-reference requirements to operation 35's pre-Retry
lookup. Before comparing the lookup source to the admitted parent JobRunId,
the oracle requires an exact string of 1–256 characters with nonblank content
after stripping. Equality-impersonating objects and string subclasses block.
JobIdentity and GameId continuity observer references retain their existing
exact-string, length, and nonblank requirements. The supplied references are
preserved in evidence. The canonical oracle digest is
`ffada5ef446923dfba24aaf8dd3b2dc7cb483e749aa5480cd23431ef5bf4be4f`.

`ScanRunRelation` host code now requires named arguments for the parent,
ScanRun, and root fields. This prevents positional identity swaps without
changing the serialized tuple, plan, evidence shape, or contract v5.

The AND-04 and AND-05 plan digests below come from synthetic host-test
authorization fixtures. They verify canonical plan computation; they are not
owner-approved authorization digests and cannot admit physical execution.

| Scenario | Oracle v9 synthetic test-fixture plan digest |
|---|---|
| AND-04 | `437698c1128d0bd1096c6a6d87a7776ee048b83a35043723eb5b047b34fb7c81` |
| AND-05 | `cd2a90e18a32856a2c097de5a937816030194a2645cf54187c9e71fc6faa1a04` |

Published v8 records remain historical; oracle v9 rejects their authorization
pins. The v8 oracle digest is
`c15ee6d1d46043739d539367f16dd550e0c5b2e53708b5b30083551a42fe9e38`, with
synthetic AND-04 and AND-05 plan digests
`5be168cf38cfd13288cdbd9536247f1d9d630245c4ab2ed38aa49b0229c04c41` and
`dddbaa166f5d5b06f109445b199692b7f22fa95ed98ed63871683b9e291263d6`.
Published v7 records remain historical and are rejected by v9: oracle digest
`3f035f161cbb5d1cb3edd88b29069a12c2bc8dd2fc72c5783f39279c9243698a`, with
synthetic AND-04 and AND-05 plan digests
`71c13ba6d003787d212be1d7283969b42735bb5a192cd7c133028d306d974e13` and
`d2898f073a89730619bdad4bc028ec935cbf0322c76fdcd7e9b7ae7e58896ad4`.

The AND-05 capability declares a fresh Retry-relation precondition and binds
the successor observation to the captured source root partition and ScanRun
set. Owner authorizations must bind the exact contract, capability, oracle,
artifact, rules, and frozen operations. Earlier v5/v4/v7, v4/v3/v6, v4/v3/v5,
v3/v3/v4, and v2/v2/v3 bindings are rejected for both scenarios. Legacy, Issue
#26, and Issue #27 pins are unaffected.

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

Operation 25 uses its existing 60-second monotonic timeout to observe the exact
parent until a terminal state is available. An active state at the deadline or
missing terminal evidence blocks the session and leaves later operations
`NOT_RUN`; this does not extend the operation or session deadline.

In both scenarios, the independent identity observer must repeat the frozen
requested, admitted, and excluded root scope captured with the parent refresh.
It binds each admitted root to exactly one ScanRun using the parent JobRunId,
ScanRunId, and LibraryRootId. A missing, duplicated, or contradictory relation
blocks before the background transition in AND-04 or process stop in AND-05.
The model contains no separate LibraryScan child JobRunId.

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

Operations 13 through 15 capture the pre-loss Sources root presentation. The
observation keeps the root's `View Job` JobRunId separate from its ScanRunId.
The presentation must identify the authorized root and one active scan with
no historical last-scan state, or one historical last scan with a terminal
state. Missing or ambiguous presentation or identity blocks before the
controlled stop. `View Job` navigation alone does not establish the root's
ScanRun ownership.

Operations 25 through 29 run after relaunch and before Retry. Operation 27
checks the recovered root's `(parent JobRunId, ScanRunId, LibraryRootId)`
against the independently captured source relation, then compares it with the
pre-loss tuple. A historical presentation must keep the same terminal state.
An active presentation that becomes historical is accepted only for the same
ScanRun. A root that remains active or has missing or ambiguous root or
ScanRun evidence records `BLOCKED`. A different valid owning parent is a
contradiction and records `FAILED`. `View Job` remains parent JobRun navigation;
it is not compared with the ScanRunId.

Operation 29 compares the exact recovered Library membership identities with
the identities captured at operation 12. Counts, row order, titles, and
screenshots do not substitute for identities. Each captured GameId must remain
present or have a complete, unique, refresh-bound direct redirect to a GameId
in the complete current Library set. The redirect source must be in
`queried_game_ids`; the oracle does not follow a second redirect. Missing query
coverage, an intermediate target, a target outside current membership, or
incomplete, ambiguous, cyclic, or foreign-run continuity evidence records
`BLOCKED`. A complete lookup with no redirect proves loss only for an ID in
that query. Newly committed assets may appear, but they do not conceal an
unresolved loss. Operation 35 does not
dispatch Retry unless both operation 27 and operation 29 passed. A blocked or
failed persistence check therefore prevents Retry from recreating a lost asset
before the persistence assertion runs.

Operations 35 through 37 separate three claims. Operation 35 dispatches the
single authorized Retry only after the pre-Retry persistence gate passes and a
fresh relation lookup proves that the source parent has no Retry successor.
The lookup binds the exact parent JobRunId, the captured requested/admitted/
excluded root sets, recovered terminal state, and complete source ScanRun
relation set. Each source-admitted root has exactly one unique ScanRun. The
lookup must establish an empty Retry relation: no successor JobRunId,
source/successor link, successor scope, requested/admitted/excluded partition,
typed exclusion, or successor ScanRun relation may already be present. Any
successor metadata without a verified successor JobRunId blocks before Retry
intent or dispatch. The lookup must report the successor ScanRun relation
collection as an explicit empty tuple; missing (`None`) relation evidence does
not prove absence and blocks before Retry intent or dispatch.

Retry reuses the original requested root set and rechecks current eligibility.
The successor may admit a different subset and must provide one typed
SPEC-BE-013 exclusion reason for every excluded requested root. At least one
root must be admitted; each admitted root must have exactly one ScanRun owned
by the distinct successor JobRunId. Successor ScanRun IDs must be disjoint
from the source set. Operation 36 also requires the source partition and
ScanRun set to match the values captured before process interruption. Missing
or ambiguous successor scope or exclusion evidence
is `BLOCKED`; a proven foreign identity or a ScanRun assigned to an excluded
root is `FAILED`. Operation 36 captures the successor partition and relations;
operation 37 independently confirms the source and successor relations. Neither
operation infers identity from row order, labels, or timing.

Operation 39 re-observes the Library after Retry and compares it with the
identities recovered at operation 29, not with the original pre-loss snapshot.
The post-Retry integrity check therefore remains separate from the
process-recovery persistence. An identity that disappears after Retry records
`FAILED`; incomplete identity evidence records `BLOCKED`. Operation 42
re-observes the Sources root after Retry. It requires the authorized root, the
exact successor ScanRunId, and an owning parent JobRunId that matches the
independently verified Retry successor. It does not use `View Job` navigation
to establish this relation. The active form has no historical last-scan state;
the historical form has one terminal state. An active observation proves
current successor ownership of the root, not terminal completion. Operation 42
does not award terminal success. Operation 45 remains the only
terminal-success decision for the successor.

AND-04 operations 29 and 30 retain their frozen identifiers and grants.
Operation 29 follows `View Job` to the owning LibraryRefresh detail. Operation
30 reads the selected root's ScanRun from that parent detail. The parent
JobRunId and ScanRunId are checked as separate identities.

Operations 43 through 45 verify the retry successor without another effect.
Operation 43 navigates to Jobs. Operation 44 opens the successor detail only
when the observer supplied one exact successor identity. Operation 45 records
two separate claims: the successor reached a terminal state within the fixed
60-second window while the qualification package remained in the foreground,
and the retry outcome satisfies the pinned acceptance contract. `Completed`
satisfies Retry success. `CompletedWithIssues` remains `BLOCKED` unless an
immutable owner-approved criterion admits it. `Failed`, `Cancelled`, and
`Abandoned` record a `FAILED` Retry-success assertion even though the terminal
observation itself succeeded. An unavailable identity or a successor that
remains active at the deadline records `BLOCKED` and leaves recovery with the
owner. At operation 37, an unavailable, incomplete, or mismatched independent
`JobIdentityObservation` is `BLOCKED` because it does not bind the exact
successor to the expected source and scope. The separate
`RefreshDetailObservation` is `BLOCKED` when its parent or source ID is
missing or malformed, and `FAILED` when a different valid ID proves a
contradictory Retry relation. At operation 45, a missing or malformed
successor ID remains `BLOCKED`, while a different valid successor ID is
`FAILED`. The executor does not dispatch a second Retry.

Every accepted refresh detail also requires a nonempty observer reference.
Missing observer provenance blocks the detail assertion or Retry control.
A valid foreign parent or source remains `FAILED` even when its observer
reference is missing. The AND-05 pre-stop detail must pass this check before
the force-stop intent is recorded. Operation 34 also requires a readable
lifecycle state that matches the state established during recovery and exactly
one Retry control. Fields that the current operation does not use may remain
unavailable.

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

The Flutter Jobs surface emits a `job-run:<JobRunId>` semantics resource on
each row, but Android accessibility has not been verified to preserve it. The
host parser reports a row operation or status only when that validated
resource and its hierarchy bind the labels to the row; a neighbouring label
cannot supply identity. When the capture cannot establish that binding, the
row status and active-row count are withheld and dependent operations record
`BLOCKED`. The private executor accepts a parent run identity only from an
authorized independent observer. A row position, matching label, or detail
page title cannot supply identity. Jobs preflight compares complete observed
terminal-refresh history against the admitted
`JobLifecycleBaselineObservation.terminal_refresh_run_refs` and visible row
count. Extra, missing, substituted, duplicated, or paginated history blocks
before a Refresh effect. A refresh that became active after admission also
blocks.

The Sources root detail exposes its LibraryRootId and at most one `View Job`
JobRunId. It does not expose ScanRun ownership by itself. A root observation
must carry an explicit `ScanRootPresentation`. `ACTIVE_SCAN` means the root
shows an active scan with no historical last-scan state. `HISTORICAL_LAST_SCAN`
means it shows one terminal last-scan state. `UNIDENTIFIED`, missing or
ambiguous ScanRun identity, an unidentified root, or conflicting labels
records `BLOCKED`.

Operation 15 captures the identified pre-loss presentation. Operation 19
independently binds the parent JobRunId and frozen root scope to one ScanRun
per admitted root. Operation 20 checks that the pre-loss Sources tuple matches
that relation before force-stop. Operation 27 checks the recovered tuple
against the source relation and pre-loss tuple. An active-to-historical
transition passes only for the same ScanRun with a terminal state. A root that
remains active or has missing or ambiguous root or ScanRun evidence blocks
Retry. A different valid owning parent is a contradiction and records
`FAILED`.

After Retry, operation 42 requires the same authorized root and exact
ScanRunId whose owning parent JobRunId is the verified Retry successor. It
does not use `view_job_run_ref` to prove ScanRun ownership. That field is a
JobRunId used for navigation, never a ScanRunId. An identified active
presentation has no historical last-scan state; a historical presentation has
one terminal last-scan state. A foreign root or ambiguous ScanRun identity is
`BLOCKED`. An active presentation proves current successor ownership of the
root, not terminal completion.

The root route does not prove that its ScanRun belongs to the tested
LibraryRefresh. The independent identity observer must establish the exact
`(parent JobRunId, ScanRunId, LibraryRootId)` relation. Operation 27 records
root persistence and ScanRun attribution as separate assertions, but neither
the Sources route nor `View Job` navigation alone proves that relation.

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

For one Library hierarchy capture, the host parser keeps a sanitized preorder
ordinal for each page marker and row. The adapter requires every row on page N
to precede page N+1's boundary. The first row remains nested under its page
marker, and later rows remain siblings. An empty terminal page, including a
terminal continuation page, is valid; a boundary that interrupts the prior
page or any row after an empty terminal boundary blocks membership. This
checks the supplied host capture only. Android accessibility may omit offscreen
rows or page markers, so it does not establish that the full chain is
physically available.

The executor records persistence intent and result as separate append-only
assertions. The recovery checks use the
`:root-preloss`, `:root-recovery-persistence`, `:refresh-scanrun-attribution`,
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
| Required lifecycle state is missing or not an exact `RecoveryState` value | `BLOCKED` | Dependent actions `NOT_RUN` |
| Parent JobRun and per-root ScanRun relations are missing, duplicated, or ambiguous | `BLOCKED` | ScanRun attribution and dependent claims `NOT_RUN` |
| New parent JobRunId is present in the admitted terminal-refresh history | `BLOCKED` | No dependent background transition, force-stop, or Retry; owner recovery |
| Pre-loss Sources root presentation unidentified, run identity missing, or root identity contradictory | `BLOCKED` | No controlled stop; dependent operations `NOT_RUN` |
| Recovered Sources root remains active or its root or ScanRun identity is missing or ambiguous | `BLOCKED` | No Retry; owner recovery |
| Recovered root names a different valid parent JobRunId | `FAILED` | No Retry; owner recovery |
| `View Job` JobRunId is available without an independently verified ScanRun relation | `BLOCKED` | No ScanRun-attribution claim |
| Recovered Jobs observation lacks a valid parent JobRunId | `BLOCKED` | No Retry intent or dispatch; owner recovery |
| Recovered Jobs observation names a different valid parent JobRunId | `FAILED` | No Retry; owner recovery |
| Missing pre-loss GameId has a complete refresh-bound continuity lookup with no redirect | `FAILED` | No Retry; owner recovery |
| Missing pre-loss GameId has a complete, unique, refresh-bound direct redirect to a current GameId | `PASSED` for identity persistence | Retry eligibility remains separately gated |
| Missing pre-loss GameId depends on an unqueried or multi-hop redirect, or its target is absent from current membership | `BLOCKED` | No Retry; owner recovery |
| Missing pre-loss GameId has unavailable, incomplete, ambiguous, cyclic, or foreign-run continuity evidence | `BLOCKED` | No Retry; owner recovery |
| Recovered Library identity evidence unavailable or incomplete | `BLOCKED` | No Retry; owner recovery |
| Pre-Retry root or Library persistence unverified | `BLOCKED` | Retry not dispatched |
| Fresh Retry-relation lookup is unavailable, incomplete, stale, contradictory, or does not prove absence of both successor identity and scope | `BLOCKED` | No Retry intent or dispatch; owner recovery |
| Refresh reaches a terminal state before the controlled stop | `BLOCKED` for process loss | Retry obligations `NOT_RUN`; completed state is not proof of interruption |
| `Completed` or `CompletedWithIssues` after the stop | `BLOCKED` as recovery proof | Retry remains undecided |
| `Interrupted` after a non-resumable refresh stop | `FAILED` | No retry or relaunch |
| Exact Retry successor is `Interrupted` | Terminal observation `PASSED`; Retry-success assertion `FAILED` | No second Retry; owner recovery |
| `Active` after relaunch | `FAILED` as silent resumption | No retry |
| `Cancelled` without durable cancellation intent | `FAILED` | No retry |
| `Failed`, `Cancelled`, or `Abandoned` after observed process loss | Recovery consistency supported | Retry may proceed only through the approved eligibility check |
| Force-stop proof missing | `BLOCKED` | No relaunch, retry, cleanup, or product mutation |
| Fresh relaunch preflight lacks a valid foreground-package identity | `BLOCKED` | No launch intent or dispatch; owner recovery |
| Force-stop, retry, background, relaunch, return, or restoration result uncertain | `BLOCKED` | Stop immediately; owner recovery required; never repeat the effect |
| Process observer evidence unavailable, malformed, or missing its observer identity | `BLOCKED` | No dependent effect; owner recovery |
| Process observer reports a foreign package or contradictory typed process state | `FAILED` | Stop before any subsequent effect; owner recovery |
| Required foreground-package or task-continuity identity is unavailable | `BLOCKED` | No foreground claim or relaunch; owner recovery |
| Process is reported absent while the qualification package is still identified in the foreground | `FAILED` | No relaunch or Retry |
| Active Jobs row lacks a valid parent JobRunId | `BLOCKED` | No lifecycle claim or background effect; owner recovery |
| Active Jobs row names a different valid parent JobRunId | `FAILED` | No background effect; owner recovery |
| AND-04 parent remains active or terminal evidence is unavailable at operation 25's 60-second bound | `BLOCKED` | No later operation or terminal-state claim; owner recovery |
| Pre-stop detail lacks a valid parent JobRunId | `BLOCKED` | No force-stop intent or dispatch; owner recovery |
| Pre-stop detail names a different valid parent JobRunId | `FAILED` | No force-stop intent or dispatch; owner recovery |
| Parent-to-ScanRun attribution lacks a valid parent JobRunId or exact root partition | `BLOCKED` | No ScanRun-attribution claim or dependent effect; owner recovery |
| ScanRun relation names a different valid parent JobRunId | `FAILED` | No dependent effect; owner recovery |
| Initial root scope differs from the scope captured for the parent refresh | `BLOCKED` | No background transition, process stop, or Retry; owner recovery |
| An admitted root has a missing, duplicated, or contradictory ScanRun relation | `BLOCKED` | No ScanRun-attribution claim; owner recovery |
| Evidence append fails | `BLOCKED` | Preserve evidence; owner recovery required; no cleanup or product mutation |
| Retry is not advertised for the durable state | `NOT_RUN` | No retry dispatched |
| Retry-eligibility detail lacks a valid parent JobRunId | `BLOCKED` | No Retry intent or dispatch; owner recovery |
| Retry-eligibility detail names a different valid parent JobRunId | `FAILED` | No Retry intent or dispatch; owner recovery |
| Retry eligibility has a malformed control count, including a Boolean or floating-point value | `BLOCKED` | No Retry intent or dispatch; owner recovery |
| Operation 37 `JobIdentityObservation` is unavailable, incomplete, or mismatched and cannot bind the exact successor to the exact source and scope | `BLOCKED` | No relation claim or terminal-success claim; owner recovery |
| Operation 37 Retry detail lacks a valid parent or source identity | `BLOCKED` | No Retry relation claim or terminal-success claim; owner recovery |
| Operation 37 Retry detail names a different valid parent or source than the requested successor relation | `FAILED` | No second Retry; owner recovery |
| Retry was dispatched without eligibility | `FAILED` | No second retry |
| Source run already has a retry successor | `BLOCKED` | No second retry |
| Jobs preflight history differs from the admitted baseline | `BLOCKED` | No Refresh effect; owner recovery |
| Jobs preflight shows a newly active refresh | `BLOCKED` | No Refresh effect; admission prerequisite changed |
| Successor remains active at the 60-second bound | `BLOCKED` | Owner recovery; no second retry |
| Successor terminal but qualification foreground unproven | `BLOCKED` | Owner recovery |
| Successor terminal with `CompletedWithIssues` and no pinned criterion | `BLOCKED` for Retry success | Terminal observation may pass; owner recovery; no second retry |
| Successor terminal with `Failed`, `Cancelled`, or `Abandoned` | `FAILED` for Retry success | Terminal observation may pass; no second retry |
| Terminal detail has no valid JobRunId or its lifecycle state is unavailable | `BLOCKED` | No terminal-state or successful Retry claim; owner recovery |
| Terminal detail identifies a different valid JobRunId than the exact Retry successor | `FAILED` | No successful Retry claim; owner recovery |
| Post-Retry root is a different Sources root than the authorized root | `BLOCKED` | No terminal-success claim; owner recovery |
| Before AND-04 operations 29–30, `View Job` is missing, duplicated, or does not identify the observed parent JobRunId | `BLOCKED` | Do not navigate to detail or claim ScanRun attribution |
| Post-Retry root names a different valid parent JobRunId than the Retry successor | `FAILED` | No terminal-success claim; owner recovery |
| Post-Retry root shows both active and historical state, or neither identified presentation | `BLOCKED` | No terminal-success claim; owner recovery |
| ScanRun detail names a different valid owning parent JobRunId | `FAILED` | No source or successor relation claim |
| ScanRun detail has a missing or mismatched ScanRunId or LibraryRootId | `BLOCKED` | No source or successor relation claim |
| Missing recovered GameId has a complete successor-bound continuity lookup with no redirect | `FAILED` | No second Retry; owner recovery |
| Missing recovered GameId has a complete, unique, successor-bound direct redirect to a current GameId | `PASSED` for identity persistence | Retry-success assertion remains separate |
| Missing recovered GameId depends on an unqueried or multi-hop redirect, or its target is absent from current membership | `BLOCKED` | No successful integrity claim; owner recovery |
| Missing recovered GameId has unavailable, incomplete, ambiguous, cyclic, or foreign-run continuity evidence | `BLOCKED` | No second Retry; owner recovery |
| Post-Retry Library identity evidence is missing or incomplete | `BLOCKED` | No second Retry; no count, order, title, or database substitution |
| Foreground return or task continuity fails in AND-04 | `FAILED` for recovery consistency | No fresh-launch substitution |

`BLOCKED` means the available evidence cannot decide the assertion. `FAILED`
means an observed product outcome contradicts the pinned contract. A blocked
process-loss scenario is not a product failure by itself, and a supported
recovery state does not prove that the controlled interruption occurred.

## 8. Latency contract

The host-only slice ships the typed latency measurement contract with
execution disabled. Five warmups, twenty measured cycles, and nearest-rank
p95 remain provisional. Timeout, ceiling, cycle counts, and elapsed samples
must be built-in integers. Timeout must be positive; ceiling and elapsed
values must be nonnegative; cycle counts stay at five and twenty. Active
overlap, warmup, and return fields must be built-in Booleans. The evaluator
also requires valid action IDs, unique cycle evidence references, and a
well-typed owner rule with workload, environment, and rule digest. Action IDs
are exact strings of at most 64 characters matching
`[a-z][a-z0-9_-]{0,63}`. Workload, environment, and cycle evidence references
are exact strings of at most 256 characters and must remain nonblank after
stripping whitespace. The owner-rule digest is exactly 64 lowercase
hexadecimal characters.

The evaluator rejects duplicate evidence-reference values, action IDs outside
the owner-pinned set, and missing or excessive total or per-action cycle
counts. It cannot establish that different evidence references represent
different executions, so it cannot detect semantic replay that uses a new
reference.
Malformed or unavailable criteria or evidence return `BLOCKED` without raising
a Python exception. This includes a nonpositive per-cycle timeout or a
negative p95 ceiling. A well-formed measured timeout or p95 ceiling violation
remains `FAILED`.

Baseline calibration and candidate acceptance are separate decisions.
Representative baseline measurements may be collected and reported before an
acceptance ceiling is chosen, but they do not produce a pass/fail result. A
candidate verdict requires an immutable owner-approved workload, environment,
action set, numerical ceiling, and rule digest. Each warmup and measured
navigation effect requires its own bounded grant and evidence reference. Each
required return or reset transition also requires its own bounded grant and
evidence reference. A single one-use navigation grant cannot cover 25 hidden
UI effects or their returns. The frozen 31- and 45-operation plans do not
contain these per-cycle grants; latency therefore needs a separate physical
authorization plan with its own deadline and reserves. The provisional method
does not approve numerical criteria, and host fake-clock tests do not create a
physical latency verdict.

## 9. Physical qualification blockers

Physical admission remains blocked until permitted independent surfaces can
verify the exact package and artifact, no-reset Library and job baseline,
parent JobRunId, per-root ScanRunId and LibraryRootId relations, retry source
and successor identity, process presence and task continuity, committed
Library state, and pending cleanup and restoration facts.

Flutter now emits a `job-run:<JobRunId>` semantics resource on each Jobs row and on the Library Refresh detail. The refresh detail nests each `scan-run:<ScanRunId>` under its parent JobRun and each `library-root:<LibraryRootId>` under that ScanRun. Sources root detail nests the root, owning JobRun, and ScanRun identities around its scan-state node. The host parser maps these resource IDs and checks the resulting relations against an independent `JobIdentityObservation`. The `View Job` control alone does not prove root ownership. Physical operations 15, 19, 20, 27, 29, 30, 37, and 42 remain `BLOCKED` until Android exposes those semantics in an authorized capture and an independent observer confirms the parent, frozen root scope, and per-root relation. Operation 42 must bind the root ScanRun and owning parent to the verified Retry successor. A last-scan label by itself does not establish a ScanRunId.

Flutter Library page markers and row markers carry the observation, baseline profile, page ordinal, expected row count, and exact GameId. In C4, the page-boundary `Semantics` node wraps only the first row of each nonempty page; later rows are siblings. The host adapter accepts membership only when one hierarchy capture contains a unique, contiguous marker for every page, binds each nonempty page's first row to its marker, and contains the remaining rows in traversal order with matching observation, page, one-based row, and GameId identities. Row counts and GameIds must match exactly, and the chain must have one terminal page. A terminal page may be empty, including the first page; every nonterminal page must contain at least one row.

The Library uses lazy grid and list builders, so Android accessibility may omit offscreen rows or boundary nodes. A terminal marker and the currently visible subset cannot establish complete membership. The adapter rejects page facts from separate parser captures even when their `obs-N`, task, or observer references match. Its in-memory capture reference identifies a parser call; it is not an Android process-incarnation signal. No C5 device-capture implementation or OS process observer is added. The Android projection and physical Library recovery remain `BLOCKED` until an authorized observation path supplies a complete chain. Synthetic parser tests do not establish that the chain is physically obtainable. The qualification UI also does not independently prove foreground process loss or task continuity.

The Jobs parser binds operation and lifecycle labels to a validated `job-run` row subtree or to one merged row node. The adapter rejects duplicate JobRun IDs before projecting row counts or history references. It returns `BLOCKED` when a Jobs observation reports cancellation intent because the existing Jobs type cannot carry that fact. Refresh detail status is accepted only when one status belongs to the identified parent JobRun subtree; nested JobRun and ScanRun subtrees cannot supply it. The screen-level status must match that parent row, and missing, duplicate, child-only, or conflicting evidence remains `BLOCKED`. The typed Jobs observation keeps visible row identities but marks history incomplete; it cannot claim that offscreen or unprojected rows are absent. Physical Jobs state therefore remains `BLOCKED` until Android projection and complete history evidence are verified. Jobs classification still requires a selected Jobs destination, a separate page title, and coherent section markers. Each observed row must contain exactly one `Library Refresh` or `Library Scan` title and one lifecycle status. Missing, duplicate, or conflicting statuses block classification. An empty page requires one `No jobs yet` marker and no lifecycle row. Flutter defines selected navigation state, but Android accessibility has not been verified to expose it. Missing or ambiguous selected state or page structure remains `BLOCKED`.

### Observer design for a later physical authorization

Use two independent observation sources because the UI and Android OS prove
different facts. The owner-attested baseline supplies expected values; it does
not replace either observation.

**A. Normal production accessibility semantics.** The host parser reads ordinary Library, Jobs, refresh-detail, Sources-root, and scan-detail hierarchies through `scripts/android_qualification/physical/_job_lifecycle_ui.py`. Flutter source now provides JobRunId, ScanRunId, LibraryRootId, page, and GameId semantics for the relevant rows. The parser accepts only validated `resource-id` values and their hierarchy relationships.

A complete Library hierarchy maps to `LibrarySurfaceObservation.membership_ids` only when one capture contains every baseline page marker. The first row of each nonempty page must be beneath its boundary; later rows are siblings checked by their own observation, page, one-based row, GameId, and traversal order. Exact row counts, unique GameIds, and one terminal page are required. A terminal page may be empty; every nonterminal page must contain at least one row. The parser's capture reference distinguishes parser calls; it does not identify an Android process. The adapter rejects multi-capture composition, including pages whose C4 `obs-N` values match after a process restart. Lazy builders may hide offscreen rows or boundaries, so an incomplete snapshot remains `BLOCKED`.

A Jobs row maps its `job-run` identity, operation, and lifecycle state from the row's semantic subtree. `JobsSurfaceObservation.history_complete` remains false because visible rows do not prove complete history. A refresh-detail JobRunId comes from its `job-run` resource. Each Retry source or successor comes only from a `job-run` resource node that itself carries the corresponding `Retried from` or `Retried as` label; labels on wrappers, nested content, or nearby nodes do not supply an identity.

A refresh detail maps nested `scan-run` and `library-root` resource IDs to `ScanRunRelation(scan_run_ref, parent_run_ref, root_ref)`. The parser cross-checks those relations against an independently supplied `JobIdentityObservation`; it never creates that independent observation. Root-coverage markers count only within the identified refresh JobRun subtree; a marker elsewhere in the hierarchy cannot establish complete scope. A Sources root maps its root, ScanRun, and owning JobRun to separate fields in `ScanRootObservation`. The View Job target comes from a validated `job-run:` resource node whose local hierarchy subtree contains the control. A nearby label alone cannot establish that target, which must match the independently verified parent JobRun. Missing or mismatched target identity, missing root scope, unavailable historical coverage, or mismatched root outcomes remain `BLOCKED`.

This module parses supplied XML and adapts parsed facts to the existing lifecycle types. It does not capture a device hierarchy or implement a physical transport. Android accessibility projection remains unverified, and synthetic parser tests do not establish physical qualification. Missing or ambiguous facts remain `BLOCKED`; a different valid identity or proven committed-state loss uses the existing operation-specific `FAILED` classification. Any production accessibility change requires its own product review, artifact pin, and requalification. The product touchpoints to review are `flutter/lib/features/jobs/presentation/jobs_page.dart`, `flutter/lib/features/jobs/presentation/job_detail_page.dart`, `flutter/lib/features/library/presentation/library_page.dart`, `flutter/lib/features/sources/presentation/sources_page.dart`, and `flutter/lib/features/sources/presentation/root_detail_page.dart`. Private database reads and qualification-only endpoints remain excluded.

**B. Fixed, read-only OS observer.** A future adapter, proposed at
`scripts/android_qualification/physical/_job_lifecycle_os_observer.py`, would
accept the privately bound exact target and expected package and return typed,
sanitized package-artifact, signer, process, foreground, and task-continuity
facts with observer provenance. It may query only allowlisted package-scoped
OS surfaces, such as package metadata and the exact package's process
presence. Read-only discovery established a package-scoped process-presence
query, but no permitted target-specific task-continuity query. The platform
version and identifying device attributes are omitted from shared
qualification documentation; any future physical evidence must keep them in
owner-private records. This shared plan retains only the sanitized capability
result.
Global stack or activity dumps would expose unrelated application state and
are excluded. The observer must not enumerate other applications, retain broad
`ps` or ActivityManager dumps, capture screenshots, or read app-private
storage. A missing package, signer, process, or permitted task observation is
`BLOCKED`; a valid observation of a different artifact, signer, package, or
required process state is `FAILED`. OS facts cannot establish app-owned
JobRunIds, per-root ScanRun relations, frozen scope, committed Library
membership, or Sources attribution. If Android cannot return a required
foreground or task fact without exposing unrelated app state, that assertion
stays `BLOCKED`.

The existing host boundary is the bounded `JobLifecycleTransport` observation
API. The admission result uses `JobLifecycleBaselineObservation`; process and
foreground results use `ProcessAndForegroundObservation`. The host binds each
observation to the immutable target, package, artifact, and authorization and
stores only the permitted sanitized receipt. Android PackageManager and the
OS process service are the independent evidence sources for those OS facts;
the app's own success text cannot establish them.

For artifact identity, the future observer must read only the APK paths
returned for the exact approved package, calculate the base APK SHA-256 on the
host without retaining APK bytes, and compare it with the owner-pinned digest.
Any installed splits must also be covered by the approved artifact pin; an
unrepresented split set is `BLOCKED`. The observer must independently verify
the expected signer; version labels and package metadata alone are
insufficient.

The recommended future design combines A for product-owned identities and
committed state with B for independently observed artifact and OS state. The
current target discovery did not find the qualification package installed and
did not establish a permitted target-only foreground or task query. No
physical observer or transport was implemented in this host-only change.

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
