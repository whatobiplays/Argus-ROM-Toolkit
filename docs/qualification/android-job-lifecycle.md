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

## 11. Inactive versioned product-observer successor

**Status:** Normative successor contract, inactive. It describes future evidence
collection only. It does not change host contract v5, capability v4, oracle v9,
SPEC-X-003 v1.0.0, assessment schema v1, the frozen AND-04/AND-05 operations,
or their deadlines and outcomes. It does not authorize implementation,
activation, device access, or qualification execution.

### 11.1 Process and evidence boundary

The observer may listen only inside an already-running qualification app
process while the owner-enabled Diagnostics setting is on. Diagnostics remains
off by default and persists across process death and relaunch. The observer
must not cold-start or keep the app alive, navigate or mutate app state, admit
or retry Jobs, acquire a foreground service, or expose a generic database or
filesystem interface. A second in-flight request receives `Busy`; requests
are not queued.

The host grant (`H`) and authenticated peer identity are separate checks. A
valid host grant does not prove that the connecting peer is the approved host,
and a permitted peer UID does not grant an operation. The existing grant must
bind the exact target and operation; if that binding cannot be established,
the request is `BLOCKED`. The contract adds no session token or trust root. The
exact forwarded peer UID and access behavior remain target-specific B1
evidence. An unauthorized peer receives no product facts.

The four request variants are the only product interface. The observer exposes
no generic FRB method, SQL surface, filesystem path, or shell command.

### 11.2 Closed wire contract

The proposed v1 transport uses a four-byte unsigned big-endian body length
followed by one strict UTF-8 JSON object. The length counts body bytes, must be
nonzero, and is checked against the reviewed frame cap before allocating the
body. A connection carries one request and, optionally, one matching
cancellation control frame, followed by one response.
It carries no second request, multiplexed stream, or page continuation. This
framing and connection lifetime are reviewed engineering choices, not prior
Q-decision approvals; their rationale and alternatives are recorded in
[REF-QUAL-004](adr-005-contract-reconciliation-proposal.md).

Rust-to-Flutter DTO contracts define conceptual value structures. Flutter Rust Bridge transports those values with its generated codec; that codec does not define JSON. The observer uses a separate JSON profile and leaves the existing DTOs unchanged. The profile maps nested DTO fields to the exact lower-camel-case names in [SPEC-BE-008 §68.2.1 and §68.6.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#6821-inactive-observer-json-mapping). Each enum or enum-like string uses the exact per-field JSON values listed there. Some DTO enums use PascalCase Rust variant spellings; existing string vocabularies such as error categories, refresh triggers, modes, and issue keys retain their explicitly mapped lower-case values. Implementations must not infer wire values from FRB, Rust enum defaults, or serde. Tagged unions use the explicit shapes below; neither FRB tuple positions nor serde defaults define this profile.

Every JSON object is closed. Duplicate keys, unknown fields, omitted required fields, `null` for a nonnullable field, invalid UTF-8, out-of-range integers, unknown enum values, or unsupported union tags are rejected. An `Option<T>` in a nested DTO is a required JSON member whose value is either `null` or a value of type `T`. Vectors are required JSON arrays, including when empty. The decoder does not insert defaults, coerce values, downgrade versions, or fall back to another variant. A wire-shape change requires a new protocol version.

Requests and responses use compact UTF-8 JSON without a byte-order mark. Emit object members in the order specified below and in the referenced DTO tables; parsers accept any member order while rejecting duplicate keys. A tagged union's `kind` member is first. Strings use JSON escaping for quotes, backslashes, and control characters; other Unicode scalar values are encoded directly as UTF-8. Integers use exact decimal JSON integer syntax, never floating point or exponent notation. The four-byte frame prefix counts UTF-8 body bytes and excludes the prefix.

| Type | Required fields and constraints |
| --- | --- |
| `ObserverRequestV1` | `protocol_id: "argus.product-observer"`; `protocol_version: 1`; host-issued `request_id`, `connection_id`, and `attempt_id`: exactly 32 lowercase hexadecimal characters, opaque and distinct. Each is unique within the authorized session; every reattempt receives a new, never-reused `attempt_id`. The `attempt_id` also serves as the nonempty observer reference. `remaining_budget_ms: uint32`, greater than zero and no greater than the host's remaining monotonic budget for the frozen operation; `operation: ObserverOperationV1`. |
| `ObserverOperationV1` | Closed tagged union: `Readiness {}`; `GetJob { job_run_id: JobRunId }`; `RetainedLibraryRefreshHistory {}`; or `AllActiveLibraryMembership { prior_game_ids: GameId[] }`. Identifier strings use the existing canonical validators in SPEC-BE-008 and SPEC-BE-015. The membership input contains unique IDs. Its maximum size is unresolved and governed by `ObserverResourceBudgetV1`. |
| `ObserverCancelV1` | `protocol_id: "argus.product-observer"`; `protocol_version: 1`; the matching `request_id`, `connection_id`, and `attempt_id` as exact 32-character lowercase hexadecimal strings; `control: "Cancel"`. Every identity must match the one active request on that connection. A mismatched or second control frame is `MalformedRequest`. |
| `ObserverResponseV1` | Exactly the success or failure member set defined below. It echoes the request's three IDs. Success includes both elapsed-time members; failure includes neither. |
| `CompleteSuccessV1` | `outcome` is `{"kind":"CompleteSuccess","result":...}`. `result` has exactly the operation-specific type below, without another wrapper or discriminator. A complete read may still contradict a pinned expectation and be classified `FAILED`. |
| `ReadinessResultV1` | Closed object with exactly `state: "Ready"`. A non-ready observer returns `NotReady` in the failure variant and no success facts. This response does not claim OS process, foreground, or task state. |
| `RetainedLibraryRefreshHistoryV1` | Closed object with `retentionScope: "AllRetainedLibraryRefreshRunsAtSnapshot"`, `snapshotStartedElapsedRealtimeMs: uint64`, `snapshotFinishedElapsedRealtimeMs: uint64`, `retainedJobCount: uint64`, and `jobs: JobDetailDto[]`. Each job is the full `GetJob` result with `operationDetail.kind == "LibraryRefresh"`; count equals array length and `job.jobRunId` values are unique. See [SPEC-BE-008 §68.6.5–68.6.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#6865-inactive-successor-complete-retained-history-read). |
| `ObserverMembershipResultV1` | Closed object with exactly `query`, `pageSize`, `pageCount`, `identityMembershipRevision`, `identityViewContractVersion`, `queryContractVersion`, `gameIds`, `memberIdentityBindings`, and `priorLookups`, in that order. `identityViewContractVersion` is exactly `2`; all other types, order constraints, and variants are in [SPEC-BE-015 §21.7](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#217-inactive-observer-owned-membership-and-identity-read). The operation requires `LibraryIdentityViewV2` and an opaque `lvt2` token; it cannot fall back to active `LibraryViewTokenV1`. |
| `ObserverMemberIdentityBindingV1` | Closed object with exactly `requestedGameId` and tagged `result`. The variants are `Found` (complete detail with `lifecycle: Active` and identity tuples), `FoundNonActive` (the same GameId with `lifecycle: InactiveOrphan`), `Redirected` (the canonical target), or `GameNotFound` (the typed missing-Game application error). A `Found` detail with `lifecycle: Redirected` is malformed. Exact payloads and C5 classifications are in SPEC-BE-015 §21.7. |
| `ObserverDirectGameLookupV1` | Closed object with `requestedGameId` and a tagged `result`: `Found` with full `GameDetailDto` whose lifecycle is not `Redirected`, `Redirected` with `canonicalGameId`, or `GameNotFound` with the existing typed `ApplicationErrorDto` whose code is exactly `ARGUS.V1.CONFIGURATION.GAME_NOT_FOUND`. A `Found` detail with `lifecycle: Redirected` is malformed. See the exact JSON mapping below and SPEC-BE-008 §68.2.1. |
| `FailureV1` | `{"kind":"Failure","code":ObserverFailureCodeV1,"stage":ObserverFailureStageV1}`. `ApplicationFailure` also requires `applicationError: ApplicationErrorDto`; all other codes forbid that member. Every failure forbids `result` and success timestamps and contains no partial facts, raw request, raw response, raw token, or cursor. |

`ObserverRequestV1` emits the top-level members in this order: `protocol_id`, `protocol_version`, `request_id`, `connection_id`, `attempt_id`, `remaining_budget_ms`, `operation`. `operation` is exactly one of these objects:

```json
{"kind":"Readiness"}
{"kind":"GetJob","job_run_id":"<JobRunId>"}
{"kind":"RetainedLibraryRefreshHistory"}
{"kind":"AllActiveLibraryMembership","prior_game_ids":["<GameId>"]}
```

`ObserverResponseV1` uses one of these exact top-level member sets, in emission order:

```json
{"protocol_id":"argus.product-observer","protocol_version":1,"request_id":"<id>","connection_id":"<id>","attempt_id":"<id>","outcome":{"kind":"CompleteSuccess","result":<result>},"observer_started_elapsed_realtime_ms":<uint64>,"observer_finished_elapsed_realtime_ms":<uint64>}
{"protocol_id":"argus.product-observer","protocol_version":1,"request_id":"<id>","connection_id":"<id>","attempt_id":"<id>","outcome":{"kind":"Failure","code":"<ObserverFailureCodeV1>","stage":"<ObserverFailureStageV1>"}}
{"protocol_id":"argus.product-observer","protocol_version":1,"request_id":"<id>","connection_id":"<id>","attempt_id":"<id>","outcome":{"kind":"Failure","code":"ApplicationFailure","stage":"Read","applicationError":<ApplicationErrorDto>}}
```

The first shape is the only success shape and has no additional top-level members. The second is the failure shape for every closed observer failure code except `ApplicationFailure`; it forbids `applicationError`. The third is the only typed application-failure shape. All failure shapes forbid both elapsed-time members and `result`. IDs, timestamps, and scalar bounds follow the rules above.

`ApplicationFailure` is available only to `GetJob`, `RetainedLibraryRefreshHistory`, and `AllActiveLibraryMembership` when a Rust application operation returns `ApplicationErrorDto`. `Readiness` is observer-local: it reports `NotReady` or another closed observer failure and never carries `applicationError`. The B1 Readiness profile therefore has no array-bearing failure shape.

For `AllActiveLibraryMembership`, match view errors by `ApplicationErrorDto.code` before applying the generic `ApplicationFailure` mapping. Map `ARGUS.V1.LIBRARY.STALE_VIEW` to `Failure` with `code: "StaleLibraryView"` and `stage: "Read"`; map `ARGUS.V1.LIBRARY.INVALID_VIEW_TOKEN` to `Failure` with `code: "InvalidLibraryViewToken"` and `stage: "Validate"`. These two observer failures omit `applicationError`. Every other typed application error uses `ApplicationFailure` at stage `Read` with its complete `ApplicationErrorDto`.

The success result is the direct JSON value for the requested operation: `Readiness` returns exactly `{"state":"Ready"}`; `GetJob` returns the complete existing `JobDetailDto`; `RetainedLibraryRefreshHistory` returns the exact retained-history object above with `jobs` as full `JobDetailDto` records; `AllActiveLibraryMembership` returns the exact membership object above. See SPEC-BE-008 §68.2.1 and §68.6.6 for nested Job and Game DTO fields, and SPEC-BE-015 §21.7 for membership and identity-binding fields.

The membership result's exact top-level field order and casing are:

```json
{"query":"AllActiveDisplayTitleAscendingV1","pageSize":<uint32>,"pageCount":<uint64>,"identityMembershipRevision":<positive int64>,"identityViewContractVersion":2,"queryContractVersion":<positive int64>,"gameIds":["<GameId>"],"memberIdentityBindings":[<ObserverMemberIdentityBindingV1>],"priorLookups":[<ObserverDirectGameLookupV1>]}
```

`identityMembershipRevision` is read from the same V2 view as every page and `GetGame` lookup. `queryContractVersion` is the positive signed 64-bit query version in that view. A missing, unknown, or unsupported identity view version, including an active V1 token, cannot produce `CompleteSuccess`; it returns a typed failure that the host classifies `BLOCKED`.

`ObserverDirectGameLookupV1.result` maps an existing `GetGameResultDto` result or its published missing-Game application error as follows:

```json
{"kind":"Found","game":<GameDetailDto>}
{"kind":"Redirected","canonicalGameId":"<GameId>"}
{"kind":"GameNotFound","applicationError":{"code":"ARGUS.V1.CONFIGURATION.GAME_NOT_FOUND","category":"configuration","severity":"Warning","recoverability":"UserAction","retryPolicy":"Never","messageKey":"errors.library.game_not_found","traceId":"<nonzero 128-bit TraceId as 32 lowercase hexadecimal characters>","safeContext":[]}}
```

`Found` and `Redirected` preserve the existing `GetGameResultDto` variants. For every direct lookup, `Found.game.gameId` must equal `requestedGameId`, and `Found.game.lifecycle` must not be `Redirected`; a detail with that lifecycle is malformed and must be rejected. `GameNotFound` is the observer wrapper for the existing `ApplicationErrorDto`; all eight fields have the exact names and values shown, including `safeContext: []`, matching the bridge's empty-context construction. `ApplicationErrorDto` always has exactly these eight required fields; all scalar values are strings, and `safeContext` is an array of closed `{field, value}` string records. Its general enum spellings, code-to-metadata pairing, TraceId format, and field-specific safe-context values are defined in [SPEC-BE-008 §68.2.1](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#6821-inactive-observer-json-mapping). Every other typed application error uses the top-level `ApplicationFailure` outcome.

The member-binding `FoundNonActive` form is exactly `{"kind":"FoundNonActive","gameId":"<same GameId>","lifecycle":"InactiveOrphan"}`. It is a complete contradictory observation for a listed GameId and is classified `FAILED`. A `Found` detail with `lifecycle: Redirected` is malformed and must be rejected as `BLOCKED`; `Redirected` or `GameNotFound` for a listed GameId is separate, complete contradictory evidence and is `FAILED`. Incomplete member details, missing bindings, duplicate or ambiguous identity attribution, stale/invalid V2 tokens, unsupported V2 views, transport uncertainty, and typed application errors other than the exact Game-not-found code are `BLOCKED`. A coherent complete identity grouping that differs from the independently pinned fixture manifest is `FAILED`.

Unsigned and signed 64-bit JSON integers are parsed as exact decimal integers,
never through floating-point conversion. Android elapsed-realtime timestamps
are monotonic within one device boot and the response interval encloses its
operation-specific snapshot interval. Device reboot invalidates comparisons
across that boundary; process loss invalidates the active observer attempt.

`ObserverFailureStageV1` is closed to `Accept`, `AuthenticatePeer`, `Parse`,
`Validate`, `Read`, `Assemble`, `Serialize`, `Cancel`, and `Transport`. The
host independently records its own monotonic start, deadline, and completion
times. It uses the host clock for frozen operation deadlines. Android and host
clock values are never compared or subtracted. The response identities bind
each Android interval to one observer attempt; a process loss prevents that
attempt from returning complete success.

For the B1 Readiness profile, the success `outcome` is exactly
`{"kind":"CompleteSuccess","result":{"state":"Ready"}}`. The two
elapsed-realtime members are top-level siblings after `outcome`, as specified
above; `result` is the `ReadinessResultV1` object itself.

The observer must detect the matching cancellation frame or connection EOF
while the read is active, without delaying the host deadline. A cancellation
frame is accepted only for the current request. If the observer cannot stop
work safely, the operation remains `BLOCKED`; it may not continue unbounded
queries after the host has abandoned the attempt.

### 11.3 Operation semantics

`GetJob` preserves the active per-run contract in
[SPEC-BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#686-typed-phase-003-jobs-detail).
The history operation is the separate, inactive
[`RetainedLibraryRefreshHistoryV1` successor](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#6865-inactive-successor-complete-retained-history-read).
It returns one coherent all-or-nothing snapshot of every retained
LibraryRefresh JobRun, active and terminal, with immutable requested scope,
admitted and excluded root outcomes, exact ScanRun ownership tuples, direct
Retry links, and an explicit retention boundary. It has no page, cursor,
newest-N limit, or inferred relationship. Missing historical proof,
contradictions, and resource exhaustion retain their distinct typed outcomes.

The membership operation follows
[SPEC-BE-015 §21.7](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#217-inactive-observer-owned-membership-and-identity-read).
It uses the fixed All-active query with no search or filters, title-ascending
order, and the specification's fixed page size. It must enumerate the
uninterrupted first-to-terminal chain under one token, generation, revision,
query fingerprint, and observation attempt; return unique GameIds; and perform
one same-token `GetGame` identity lookup for every returned GameId and each
required prior-ID lookup. Member lookups return only the identity projection
defined in SPEC-BE-015 §21.7, with no display title or artwork. Prior-ID
lookups preserve the full existing `GetGameResultDto` mapping. A redirect
target for a prior ID must occur in the completed membership set, and no
second hop is followed. Raw view tokens and cursors stay inside the app. Stale
views, missing pages, duplicate identities, incomplete direct lookups, or any
cross-attempt/revision stitching cannot produce success.

Neither operation returns partial success, cached facts, or data assembled
across attempts. Database snapshots are released before the socket response is
written. No snapshot or query may change retention, prune Jobs, or mutate the
Library.

### 11.4 Failure codes and classifications

Wire `ObserverFailureCodeV1` is closed to `Busy`, `Cancelled`, `TimedOut`,
`StaleLibraryView`, `InvalidLibraryViewToken`, `UnauthorizedPeer`,
`UnsupportedVersion`, `UnsupportedOperation`, `MalformedRequest`,
`IncompleteEvidence`, `IncompleteHistory`, `IncompleteMembership`,
`IntegrityConflict`, `ResourceLimitExceeded`, `NotReady`, `InternalError`,
and `ApplicationFailure`.
Host-only
`HostAttemptFailureCodeV1` adds `Disconnected` and `ProcessLost`; those values
are recorded in the sanitized host receipt and are never sent by an app that
has lost the connection or process.

An unsupported `protocol_id` or `protocol_version` maps to
`UnsupportedVersion`. A safely parsed unknown operation `kind` maps to
`UnsupportedOperation`. Duplicate,
missing, unknown, or malformed fields and mismatched cancellation identities
map to `MalformedRequest`. A frame that exceeds its reviewed byte cap maps to
`ResourceLimitExceeded` before the body is allocated.

| Failure or evidence | Classification and required handling |
| --- | --- |
| `Busy`, `Cancelled`, `TimedOut`, `StaleLibraryView`, `InvalidLibraryViewToken`, `IncompleteEvidence`, `IncompleteHistory`, `IncompleteMembership`, `ResourceLimitExceeded`, `NotReady`, `InternalError`, or `ApplicationFailure` | `BLOCKED`; publish no product success, preserve the sanitized attempt receipt, and mark dependent operations `NOT_RUN`. `ApplicationFailure` carries the exact typed `ApplicationErrorDto`. |
| `Disconnected` (host-only) | `BLOCKED` unless independent OS evidence establishes process loss for a separate assertion. A socket close by itself never proves process loss. |
| `ProcessLost` (host-only) | The host may use this code only when independent package-scoped OS evidence proves process loss. The unavailable product read remains `BLOCKED`; the applicable OS process-loss assertion is classified separately under its pinned criterion. |
| `UnauthorizedPeer`, `UnsupportedVersion`, `UnsupportedOperation`, or `MalformedRequest` | `BLOCKED`; return no product facts. If the message cannot be safely parsed or answered, close the connection and record the host-observed failure. |
| `IntegrityConflict` | The code alone is not a product verdict. Classify `FAILED` only when complete authoritative evidence for the affected assertion establishes a contradictory identity, scope, relation, or committed state; otherwise classify `BLOCKED`. Never relabel corruption as historical unavailability. |
| Complete, coherent evidence that proves a wrong pinned product result | `FAILED` for the affected product assertion. A response appearance or transport error alone is not proof of a product defect. |

Cancellation, timeout, disconnect, and process loss discard any incomplete
product result. The host sends the matching cancellation frame when the
connection remains usable, then enforces the host deadline and approved
cancellation-release bound. The observer releases query, snapshot, buffer,
and socket resources within that bound. Any response received after the host
deadline is discarded, even if it is complete. Every failed attempt retains
one bounded sanitized receipt with provenance as required by Q34. If safe
interruption or bounded release cannot be demonstrated, production use stays
blocked. There is no transparent retry, resume, replay, or automatic observer
recovery. A later request has a new `attempt_id` and requires its own operation
grant. Observer recovery never starts the app or creates a Job or Retry.

The failure receipt is stored through the existing private, append-only `H`
evidence path; it does not extend the shared assessment schema v1. Each
receipt contains:

| Field | Type or source |
| --- | --- |
| `protocol_id`, `protocol_version` | The fixed protocol ID and unsigned 32-bit protocol version used by the host request. |
| `request_id`, `connection_id`, `attempt_id` | Host-issued 32-character lowercase hexadecimal identities from the request. |
| `operation_kind`, `assertion_alias` | The closed operation tag and existing frozen operation/assertion alias; operation arguments are not copied into the failure receipt. |
| `failure_code`, `failure_stage` | `HostAttemptFailureCodeV1` and `ObserverFailureStageV1`. |
| `host_started`, `host_deadline`, `host_finished` | Existing `H` monotonic timing fields and units from host contract v5; no Android time is converted into this clock. |
| `request_body_bytes`, `response_body_bytes` | Unsigned 64-bit byte counts. The response count is zero when no response bytes arrive. |
| `target_ref`, `artifact_ref`, `authorization_ref`, `rules_ref` | Existing private `H` references to the exact target, artifact/signer, session authorization, and pinned plan/rules. |
| `sanitizer_version`, `evidence_ref` | Existing sanitizer version and append-only evidence reference. `attempt_id` is the observer reference used to correlate P facts with this attempt. |

The receipt excludes raw payloads, credentials, raw view tokens/cursors, ROM
names, private paths, serial numbers, screenshots, and unrelated OS state.
Receipt size and retention caps remain in the resource register. The host
reserves one receipt slot and its maximum bytes before dispatch. If it cannot
reserve that capacity, the observer request is not sent and the operation is
`BLOCKED`; the host never discards an earlier receipt to make room.

### 11.5 Observer resource register

`ObserverResourceBudgetV1` is the review register below, not a wire payload or
a caller-configurable set of limits. Each row records a measurement method, a
supported value or explicit unresolved status, and the fail-closed consequence.

No numeric production budget is inferred from the existing operation timeout
or token-only cap. Each limit must be measured on a representative maximum
workload, reviewed, and pinned before the production observer is implemented.
If a bound is absent, exceeded, or cannot be enforced, the affected operation
is `BLOCKED`; the observer does not truncate, page across attempts, or claim
completeness.

| Resource | Measurement and current value | Fail-closed consequence |
| --- | --- | --- |
| Concurrent observer requests | Fixed at one in-flight request per app process (Q23); second request returns `Busy`, with no queue. | `BLOCKED`; no product facts. |
| Request and response frame bytes; JSON depth and member count | Production caps and JSON depth/member caps are **UNRESOLVED**. B1 Readiness-only limits are schema-derived below; the reviewed B1 plan must pin them. | Reject before large allocation; `ResourceLimitExceeded` or sanitized `MalformedRequest`; no partial result. |
| B1 Readiness-only frame bytes | Derived by serializing compact JSON with 32-character IDs, `UINT32_MAX` for the request budget, `UINT64_MAX` for each response clock, and the longest closed failure code/stage. Request body: 274 bytes (278 including prefix). Largest failure response: 297 bytes. Complete Readiness response: 393 bytes (397 including prefix), which sets the response cap. Cancellation body: 227 bytes (231 including prefix). | Reject any larger frame before allocation. These caps apply only to the fixed Readiness profile and do not establish production history or membership limits. |
| B1 Readiness-only JSON structure | The success response has the shape `ObserverResponseV1 → outcome → result`, with timestamps as top-level siblings of `outcome`. Valid profile messages have maximum object nesting depth 3 (root object is depth 1), 8 members in any one object, 11 members across the response, and no arrays. These values are derived from the exact request, response, and cancellation schemas above. | Reject excess depth, members, or arrays as `MalformedRequest`; return no product facts. |
| Retained JobRuns, requested roots per run, ScanRuns, and direct Retry edges | Count from representative retained histories, including active and terminal attempts; all production caps are **UNRESOLVED**. | No newest-N truncation; reject the whole history as `ResourceLimitExceeded`. |
| Membership rows/pages, one same-view Game detail lookup per returned member, prior GameIds/lookups, and fixed page size | Measure the largest representative Library, identity projection fan-out, and maximum prior-ID set against the approved fixed query. Production caps are **UNRESOLVED**. | Reject the whole membership observation; no missing member binding, ID, or prior lookup may be reported as complete. |
| Database snapshot duration and total observer duration | Measure worst-case complete history/membership reads and compare with the host's existing monotonic operation deadline. The host deadline remains the current frozen operation deadline; production snapshot and internal duration caps are **UNRESOLVED**. | Cancel safely, release the snapshot, retain the failure receipt, return `TimedOut` or `ResourceLimitExceeded`; never extend the host deadline. |
| B1 Readiness-only deadline | Pin a separate host-monotonic deadline in the reviewed B1 session plan; its value is currently **UNRESOLVED**. It cannot extend or borrow a production operation deadline. | On expiry, record `TimedOut`, discard any response received later, and release the connection; no B1 success is recorded. |
| Peak working set and serialized response memory | Measure on representative maximum data with the production encoder and target runtime. Production caps are **UNRESOLVED**. | Stop before unsafe allocation or serialization; release resources and return no success. |
| Cancellation-to-resource-release time and failed-receipt bytes/retention | Measure cancellation under query and serialization load. Derive the maximum encoded receipt from the closed fields and existing H reference limits; set the per-session receipt count from the approved session plan. All three caps are **UNRESOLVED**. Reserve one receipt slot and its bytes before dispatch. | If receipt capacity is unavailable, do not dispatch. If safe interruption or bounded release cannot be demonstrated, keep the path `BLOCKED`. Never drop a failure receipt or continue unbounded work. |

The existing per-operation host timeouts remain authoritative and unchanged.
The Android elapsed-realtime interval may support measurement within one
attempt; the host monotonic clock alone enforces the host deadline. Readiness
probe limits do not authorize or imply production history or membership
budgets.

### 11.6 B1, B2, and physical qualification gates

B1 is a separately reviewed, non-production, `Readiness`-only probe. Its
fixed request cannot invoke GetJob, retained history, or membership. A B1
review package must pin the probe source and artifact hash, target and build,
framing/schema and calculated frame caps, peer-identity rule, session,
commands, effects, evidence, and cleanup. The owner separately authorizes any
device use. B1 tests target-specific transport, forwarded peer UID/access,
and permitted OS process/foreground/task evidence. It does not measure
production history or membership budgets and does not qualify G3, G4, or G5.

B2 may inspect the actual observer only after B1 passes and the exact artifact
has been independently reviewed. B2 requires separate owner authorization,
does not run G3/G4/G5, and does not by itself establish product acceptance.
The observer remains inactive until production resource bounds are supported,
the required feasibility evidence passes, and the owner separately approves
the versioned host, capability, and oracle pins. ADR-005 remains Draft until
B2 passes independent review and its other approved completion conditions are
met.

G3 admission/baseline, G4 AND-04, and G5 AND-05 remain distinct gates. G4
continues to require OS-backed same-task continuity only across its
background/return step. G5 continues to require independently verified
process loss and relaunch but does not require task identity across force-stop.
Equal PIDs across an unobserved gap never prove continuity. No product
observer result substitutes for O evidence, and no UI result substitutes for
P evidence.

### 11.7 Assertion-level G3/G4/G5 crosswalk

The following future evidence mapping applies only to the inactive successor.
It preserves every existing operation, order, deadline, criterion, and
classification. `P` includes both typed Job/history facts and the
RevisionFenced membership proof property; RevisionFenced is not a fifth
evidence class. `U` is visible UI evidence, `O` is independent OS evidence,
and `H` is host authorization and provenance. The per-operation rows and
non-collapsible acceptance notes below are copied from the supporting
crosswalk so the normative destination carries the complete assertion-level
mapping.

#### G4 — AND-04, 31 frozen operations

| Operation | Gate | Frozen operation / timeout | Prerequisites | Expected assertion | Exact source reference | Evidence / provenance | Operation-specific outcome and stop |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AND-04-01 | G3 prerequisite → G4 | `no_reset_baseline` (read_only); **30s** | G3: owner private no-reset fixture baseline, pinned qualifying artifact/signature, no pending cleanup | Exact qualification package/artifact/signer; fixture-only/no-reset Library, all retained refresh Jobs, no unresolved cleanup | [J:L133](android-job-lifecycle.md#L133), [J:L39–52](android-job-lifecycle.md#L39-L52), [J:L359–390](android-job-lifecycle.md#L359-L390), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | O installed package/base+split digest/signature; P complete retained refresh Jobs; P complete committed Library; H admission and owner manifest refs | PASSED: exact target/artifact and baseline established; BLOCKED: missing or partial OS/Jobs/Library/fixture proof; FAILED: valid wrong artifact/package or conclusively wrong baseline; do not dispatch Refresh. |
| AND-04-02 | G3 prerequisite → G4 | `navigate_library` (navigation); **10s** | AND-04-01 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L134](android-job-lifecycle.md#L134), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-03 | G3 prerequisite → G4 | `library_ready` (read_only); **20s** | AND-04-02 passed; exact plan operation grant | Successful observation of the established Library surface after the authorized navigation | [J:L135](android-job-lifecycle.md#L135), [J:L413–435](android-job-lifecycle.md#L413-L435), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | H (operation grant, exact target, monotonic start/end); U (selected Library route, surface capture/node ref and capture time; displayed membership count if present). UI readiness and any displayed membership count do not independently prove a complete GameId set, backend membership, or redirect continuity. | PASSED: established Library surface observed after the authorized navigation; FAILED: no FAILED outcome is emitted by this readiness step in the current executor; BLOCKED: Library-surface observation unavailable, malformed, or unestablished; dependents NOT_RUN. |
| AND-04-04 | G3 prerequisite → G4 | `navigate_jobs` (navigation); **10s** | AND-04-03 passed; exact plan operation grant | Jobs destination and selected state verified | [J:L136](android-job-lifecycle.md#L136), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-05 | G3 prerequisite → G4 | `jobs_preflight` (read_only); **20s** | AND-04-04 selected Jobs; admitted owner baseline includes all terminal-refresh refs | All retained refresh runs and required active history agree with admitted baseline; no unexplained duplicates | [J:L137](android-job-lifecycle.md#L137), [J:L371–390](android-job-lifecycle.md#L371-L390), [J:L507–508](android-job-lifecycle.md#L507-L508) | U Jobs rows/capture refs; P coherent bounded complete refresh history with observer ref; H admission baseline alias | PASSED: exact complete history matches admitted refs with no newly active parent; BLOCKED: incomplete/duplicate, extra/missing/ambiguous history or unexplained activity; AND-04-07 NOT_RUN. |
| AND-04-06 | G3 prerequisite → G4 | `navigate_library` (navigation); **10s** | AND-04-05 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L138](android-job-lifecycle.md#L138), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-07 | G4 | `start_library_refresh` (refresh); **30s** | G3 and AND-04-01..06 passed; exact approved single-refresh grant | Exactly one approved refresh admitted; parent JobRun identity bound to operation | [J:L139](android-job-lifecycle.md#L139), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L175–180](android-job-lifecycle.md#L175-L180), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H approved refresh intent, callback/dispatch receipt; P one admitted parent JobRunId + frozen roots; U arrival correlation | PASSED: one admitted original refresh bound; BLOCKED: uncertain admission or missing ID, no replay; FAILED: proven unauthorized/foreign run; later operations NOT_RUN. |
| AND-04-08 | G4 | `refresh_arrival` (read_only); **20s** | AND-04-07 passed; exact plan operation grant | Expected refresh detail arrives and identifies original parent JobRun | [J:L140](android-job-lifecycle.md#L140), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (typed JobRun/root/ScanRun refs, observer ref) | PASSED: exact typed/UI assertion proven; BLOCKED: missing or ambiguous identity/state/provenance; FAILED: valid contradictory identity or behavior under pinned oracle; dependents NOT_RUN. |
| AND-04-09 | G4 | `refresh_progress` (read_only); **30s** | AND-04-08 identifies source parent; first progress sample | Identified parent phase, status and progress are coherent; no child counter substituted | [J:L141](android-job-lifecycle.md#L141), [J:L359–369](android-job-lifecycle.md#L359-L369) | U parent refresh status/progress capture; P same parent coherent GetJob/ref; H monotonic sample1 | PASSED: first parent phase/status/progress valid; BLOCKED: missing status, child-only counter, ambiguity; FAILED: valid wrong parent; sample2 and downstream NOT_RUN. |
| AND-04-10 | G4 | `refresh_progress` (read_only); **30s** | AND-04-09 first typed parent-progress sample PASSED and retained; expected original parent JobRunId known; exact operation grant. | Apply `validate_active_progress_pair` to first and second committed progress samples: both individually valid, both bound to the *same expected parent* and unchanged phase; second `completed_units` **strictly greater** than first, not child-only progress. | [J:L142](android-job-lifecycle.md#L142), [J:L359–369](android-job-lifecycle.md#L359-L369), [Executor:L1227–1242](../../scripts/android_qualification/_job_lifecycle_executor.py#L1227-L1242), [Oracle:L119–149](../../scripts/android_qualification/_job_lifecycle_oracle.py#L119-L149) | H fixed operation 30s grant and ordered monotonic timestamps; U/P first and second `RefreshProgressFacts` (exact `parent_run_ref`, phase, `completed_units`, total, status key) with observer/capture IDs. | PASSED: exact parent/phase matched with strictly increased completed units; BLOCKED: flat progress, changed phase, first/second unbound or mismatched parent, incomplete/invalid sample; FAILED: decreased completed units or another proven progress contradiction; dependent operations NOT_RUN. |
| AND-04-11 | G4 | `navigate_jobs` (navigation); **10s** | AND-04-10 passed; exact plan operation grant | Jobs destination and selected state verified | [J:L143](android-job-lifecycle.md#L143), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-12 | G4 | `jobs_active` (read_only); **20s** | AND-04-11 passed; exact plan operation grant | Exact active parent is visible and no duplicated refresh is inferred | [J:L144](android-job-lifecycle.md#L144), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (typed JobRun/root/ScanRun refs, observer ref) | PASSED: exact parent/history set proven; BLOCKED: missing/partial/ambiguous history or identity; FAILED: conclusive wrong parent/state (where contract defines it); dependents NOT_RUN. |
| AND-04-13 | G4 | `open_refresh_detail` (navigation); **10s** | AND-04-12 passed; exact plan operation grant | Selected detail is bound to intended parent JobRun | [J:L145](android-job-lifecycle.md#L145), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-14 | G4 | `refresh_detail` (read_only); **20s** | AND-04-13 passed; exact plan operation grant | Parent status, progress and requested root coverage match the authoritative detail | [J:L146](android-job-lifecycle.md#L146), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (typed JobRun/root/ScanRun refs, observer ref) | PASSED: exact typed/UI assertion proven; BLOCKED: missing or ambiguous identity/state/provenance; FAILED: valid contradictory identity or behavior under pinned oracle; dependents NOT_RUN. |
| AND-04-15 | G4 | `parent_child_identity` (read_only); **15s** | Original valid parent JobRunId, frozen scope ref and captured requested/admitted/excluded roots known; exact read grant. | Separately prove (a) exact original owning parent identity and (b) *same captured frozen scope/root partition* plus one unique `(parent JobRunId, ScanRunId, LibraryRootId)` tuple for every admitted root; no label-based attribution. | [J:L147](android-job-lifecycle.md#L147), [J:L175–180](android-job-lifecycle.md#L175-L180), [J:L390–412](android-job-lifecycle.md#L390-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995), [Executor:L1311–1376](../../scripts/android_qualification/_job_lifecycle_executor.py#L1311-L1376), [Oracle:L152–212](../../scripts/android_qualification/_job_lifecycle_oracle.py#L152-L212) | P original expected parent and independently captured identity/partition vs fresh `JobIdentityObservation` root scope + all relation tuples; U linked parent-detail reference; H grant and observation time. | PASSED: valid original parent, same captured scope and complete unique tuples; BLOCKED: missing/stale/different captured root scope, ambiguous/missing/duplicate/mismatched root or ScanRun tuples; FAILED: a *different valid owning parent JobRunId*; background transition and dependents NOT_RUN. |
| AND-04-16 | G4 | `navigate_library` (navigation); **10s** | AND-04-15 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L148](android-job-lifecycle.md#L148), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-17 | G4 | `library_active` (read_only); **20s** | AND-04-16 passed; exact plan operation grant | Library interactive during refresh; complete membership asserted only by separate authorized view | [J:L149](android-job-lifecycle.md#L149), [J:L413–435](android-job-lifecycle.md#L413-L435), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (view/query/revision/page+direct lookup proof, private IDs) | PASSED: verified required UI/view and complete applicable memberships; BLOCKED: stale/missing page, ambiguous UI, unproven coverage; FAILED: definite wrong GameId/required direct continuity; dependents NOT_RUN. |
| AND-04-18 | G4 | `background_qualification_package` (launch); **10s** | AND-04-15 identity/coverage and AND-04-17 Library passed; authorize background effect | Background exactly the approved package/task | [J:L150](android-job-lifecycle.md#L150), [J:L165–168](android-job-lifecycle.md#L165-L168), [J:L483–487](android-job-lifecycle.md#L483-L487) | H one exact-package background grant/dispatch; O package/task and transition checkpoint | PASSED: approved package backgrounded without creating a new task; BLOCKED: uncertain effect or missing OS task/foreground proof; FAILED: observed wrong package/task; do not return/fresh-launch. |
| AND-04-19 | G4 | `process_foreground` (read_only); **15s** | AND-04-18 background action accepted; no product observer start | Exact package process and foreground state at checkpoint; do not infer continuity from PID reuse | [J:L151](android-job-lifecycle.md#L151), [J:L23–31](android-job-lifecycle.md#L23-L31), [J:L483–487](android-job-lifecycle.md#L483-L487) | O package-scoped process and foreground checkpoint/time; H admitted task ref | PASSED: process/foreground state consistent; BLOCKED: unavailable/malformed OS identity (PID alone not continuity); FAILED: valid contradictory package/process; next action NOT_RUN. |
| AND-04-20 | G4 | `return_existing_qualification_task` (launch); **30s** | AND-04-18/19 pass; original Android task reference retained | Return to the identical pre-background task (AND-04 only), not a newly launched task | [J:L152](android-job-lifecycle.md#L152), [J:L165–168](android-job-lifecycle.md#L165-L168), [J:L526](android-job-lifecycle.md#L526) | H return-existing-task grant/result; O identical OS task identity before/after; U foreground surface | PASSED: original task brought forward, not launched anew; BLOCKED: missing task/foreground proof; FAILED: verified fresh-task substitution or wrong task; downstream NOT_RUN. |
| AND-04-21 | G4 | `foreground_surface` (read_only); **15s** | AND-04-20 passed; exact plan operation grant | Expected foreground package and visible surface at checkpoint | [J:L153](android-job-lifecycle.md#L153) | H (grant, monotonic start/end, exact target); O (package-scoped OS read, observer/time ref); U (selected route, capture/node ref) | PASSED: exact typed/UI assertion proven; BLOCKED: missing or ambiguous identity/state/provenance; FAILED: valid contradictory identity or behavior under pinned oracle; dependents NOT_RUN. |
| AND-04-22 | G4 | `navigate_jobs` (navigation); **10s** | AND-04-21 passed; exact plan operation grant | Jobs destination and selected state verified | [J:L154](android-job-lifecycle.md#L154), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-23 | G4 | `jobs_returned` (read_only); **20s** | AND-04-22 passed; exact plan operation grant | Same original parent and consistent lifecycle after background/return | [J:L155](android-job-lifecycle.md#L155), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (typed JobRun/root/ScanRun refs, observer ref) | PASSED: exact parent/history set proven; BLOCKED: missing/partial/ambiguous history or identity; FAILED: conclusive wrong parent/state (where contract defines it); dependents NOT_RUN. |
| AND-04-24 | G4 | `open_refresh_detail` (navigation); **10s** | AND-04-23 passed; exact plan operation grant | Selected detail is bound to intended parent JobRun | [J:L156](android-job-lifecycle.md#L156), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-25 | G4 | `recovered_lifecycle` (read_only); **60s** | AND-04-24 opened original parent detail; exact parent observer/identity and permitted foreground proven | Two claims: observe the exact original parent terminal state within the fixed **60-second monotonic** operation window, and bind its lifecycle to coherent GetJob/UI proof. No deadline extension; active or unproven terminal at the deadline means BLOCKED, all AND-04-26..31 NOT_RUN. | [J:L157](android-job-lifecycle.md#L157), [J:L165–180](android-job-lifecycle.md#L165-L180), [J:L490](android-job-lifecycle.md#L490), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | P original GetJob parent lifecycle and nonempty observer ref; U matching detail/status capture; H fixed 60s deadline and monotonic start/end | PASSED: exact parent terminal within 60s with matched identities; BLOCKED: still active, absent terminal or unverified identity at deadline; FAILED: proven foreign parent/contradictory product state; downstream AND-04-26..31 NOT_RUN on stop. |
| AND-04-26 | G4 | `navigate_sources` (navigation); **10s** | AND-04-25 passed; exact plan operation grant | Sources destination selected | [J:L158](android-job-lifecycle.md#L158), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-27 | G4 | `open_scan_root` (navigation); **10s** | AND-04-26 passed; exact plan operation grant | Correct admitted LibraryRoot selected | [J:L159](android-job-lifecycle.md#L159), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-04-28 | G4 | `scan_root_state` (read_only); **20s** | AND-04-25 exact original parent terminal and AND-04-27 selected authorized root PASSED; expected original `(parent JobRunId, ScanRunId, LibraryRootId)` relation retained. | Two independent assertions: `validate_scan_root_relation` binds the exact original parent and selected root/ScanRun tuple; **historical last scan is identified and `last_scan_state` is a permitted terminal `ROOT_HISTORICAL_SCAN_STATES`**. An active root with otherwise correct ownership is insufficient. | [J:L160](android-job-lifecycle.md#L160), [J:L390–412](android-job-lifecycle.md#L390-L412), [J:L516–520](android-job-lifecycle.md#L516-L520), [Executor:L2310–2340](../../scripts/android_qualification/_job_lifecycle_executor.py#L2310-L2340), [Oracle:L389–429](../../scripts/android_qualification/_job_lifecycle_oracle.py#L389-L429) | U captured Sources root `HISTORICAL_LAST_SCAN`, identified last-scan terminal state, root ID and ScanRun ID; P verified expected original parent/root/ScanRun relation; H retained `_root_last_scan_state` and capture/observer ref for AND-04-30. | PASSED: exact owner tuple **and** identified historical terminal last scan; BLOCKED: active/nonhistorical root, missing or invalid terminal state, root/ScanRun tuple mismatch or unavailable evidence; FAILED: *different valid owning parent*; AND-04-29/30 and later dependents NOT_RUN. |
| AND-04-29 | G4 | `open_scan_job_detail` (navigation); **10s** | AND-04-28 root state/owner known; View Job target present exactly once | View Job leads to identified parent, not inferred ownership | [J:L161](android-job-lifecycle.md#L161), [J:L308–311](android-job-lifecycle.md#L308-L311), [J:L516](android-job-lifecycle.md#L516) | U View Job control with exact parent JobRunId in its own subtree; H navigation grant/result | PASSED: opens the owning parent detail; BLOCKED: missing/duplicate/ambiguous View Job; FAILED: verified wrong parent navigation; AND-04-30 NOT_RUN. |
| AND-04-30 | G4 | `scan_job_lifecycle` (read_only); **20s** | AND-04-28 identified historical terminal last scan and saved its exact terminal `last_scan_state`; AND-04-29 opened source-owning parent detail; expected original relation retained. | Independently compare selected ScanRun detail's original parent/ScanRun/root identity tuple, then require `scan_state` **equal to AND-04-28 captured historical terminal state** and a member of `ROOT_HISTORICAL_SCAN_STATES`. Identity attribution and terminal-state consistency are separate assertions. | [J:L162](android-job-lifecycle.md#L162), [J:L308–311](android-job-lifecycle.md#L308-L311), [J:L519–520](android-job-lifecycle.md#L519-L520), [Executor:L2342–2382](../../scripts/android_qualification/_job_lifecycle_executor.py#L2342-L2382), [Oracle:L545–588](../../scripts/android_qualification/_job_lifecycle_oracle.py#L545-L588) | P `ScanRunObservation` exact owner parent, ScanRun ID, root ID, `scan_state` and observer ref; U source root historical state/reference from AND-04-28; H stored `_root_last_scan_state` and operation/capture refs. | Evaluation order: (1) missing, malformed, or unestablished ScanRun detail or unavailable expected relation -> BLOCKED; (2) different valid owning parent -> FAILED; (3) ambiguous ScanRun/root tuple -> BLOCKED; (4) for an established exact tuple, any `scan_state` differing from AND-04-28's captured historical terminal state -> FAILED (`scan_run_state_mismatch`), including valid nonterminal `scanning` versus captured `complete`; (5) exact tuple with matching valid historical terminal state -> PASSED. AND-04-31 NOT_RUN after a non-PASSED result. |
| AND-04-31 | G4 | `restore_qualification_foreground` (launch); **20s** | AND-04-30 passed; exact plan operation grant | Restore approved foreground and task without fresh-task substitution | [J:L163](android-job-lifecycle.md#L163), [J:L453–487](android-job-lifecycle.md#L453-L487) | H (grant, monotonic start/end, exact target); O (package-scoped OS read, observer/time ref); U (selected route, capture/node ref) | PASSED: authorized effect and independently bound result; BLOCKED: uncertain effect/result or missing proof (no replay); FAILED: verified wrong package/run or unauthorized contradictory effect; dependents NOT_RUN. |

#### G5 — AND-05, 45 frozen operations

| Operation | Gate | Frozen operation / timeout | Prerequisites | Expected assertion | Exact source reference | Evidence / provenance | Operation-specific outcome and stop |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AND-05-01 | G3 prerequisite → G5 | `no_reset_baseline` (read_only); **30s** | G3: owner-approved no-reset target, fixture manifest, original roots, pending cleanup clear | Exact qualification package/artifact/signer; fixture-only/no-reset Library, all retained refresh Jobs, no unresolved cleanup | [J:L188](android-job-lifecycle.md#L188), [J:L39–52](android-job-lifecycle.md#L39-L52), [J:L359–390](android-job-lifecycle.md#L359-L390), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | O exact installed binary/signature; P complete retained refresh history; P complete committed Library; H signed session/fixture baseline refs | PASSED: exact fixed baseline; BLOCKED: incomplete/unverifiable identity, history or membership; FAILED: valid wrong artifact/product identity; no Refresh effect. |
| AND-05-02 | G3 prerequisite → G5 | `navigate_library` (navigation); **10s** | AND-05-01 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L189](android-job-lifecycle.md#L189), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-03 | G3 prerequisite → G5 | `library_ready` (read_only); **20s** | AND-05-02 passed; exact plan operation grant | Successful observation of the established Library surface after the authorized navigation | [J:L190](android-job-lifecycle.md#L190), [J:L413–435](android-job-lifecycle.md#L413-L435), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | H (operation grant, exact target, monotonic start/end); U (selected Library route, surface capture/node ref and capture time; displayed membership count if present). UI readiness and any displayed membership count do not independently prove a complete GameId set, backend membership, or redirect continuity. | PASSED: established Library surface observed after the authorized navigation; FAILED: no FAILED outcome is emitted by this readiness step in the current executor; BLOCKED: Library-surface observation unavailable, malformed, or unestablished; dependents NOT_RUN. |
| AND-05-04 | G3 prerequisite → G5 | `navigate_jobs` (navigation); **10s** | AND-05-03 passed; exact plan operation grant | Jobs destination and selected state verified | [J:L191](android-job-lifecycle.md#L191), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-05 | G3 prerequisite → G5 | `jobs_preflight` (read_only); **20s** | AND-05-04 Jobs selected and original baseline bound | All retained refresh runs and required active history agree with admitted baseline; no unexplained duplicates | [J:L192](android-job-lifecycle.md#L192), [J:L371–390](android-job-lifecycle.md#L371-L390), [J:L507–508](android-job-lifecycle.md#L507-L508) | U Jobs capture; P complete all-retained LibraryRefresh history observer ref; H admitted terminal-run list | PASSED: complete history/baseline match; BLOCKED: partial/missing/duplicate/newly active history; no Refresh intent; FAILED: proven wrong product identity; dependents NOT_RUN. |
| AND-05-06 | G3 prerequisite → G5 | `navigate_library` (navigation); **10s** | AND-05-05 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L193](android-job-lifecycle.md#L193), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-07 | G5 | `start_library_refresh` (refresh); **30s** | AND-05-06 passed; exact plan operation grant | Exactly one approved refresh admitted; parent JobRun identity bound to operation | [J:L194](android-job-lifecycle.md#L194), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); P (typed admitted run/ref) | PASSED: authorized effect and independently bound result; BLOCKED: uncertain effect/result or missing proof (no replay); FAILED: verified wrong package/run or unauthorized contradictory effect; dependents NOT_RUN. |
| AND-05-08 | G5 | `refresh_arrival` (read_only); **20s** | AND-05-07 passed; exact plan operation grant | Expected refresh detail arrives and identifies original parent JobRun | [J:L195](android-job-lifecycle.md#L195), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (typed JobRun/root/ScanRun refs, observer ref) | PASSED: exact typed/UI assertion proven; BLOCKED: missing or ambiguous identity/state/provenance; FAILED: valid contradictory identity or behavior under pinned oracle; dependents NOT_RUN. |
| AND-05-09 | G5 | `refresh_progress` (read_only); **30s** | AND-05-08 passed; exact plan operation grant | Identified parent phase, status and progress are coherent; no child counter substituted | [J:L196](android-job-lifecycle.md#L196), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (typed JobRun/root/ScanRun refs, observer ref) | PASSED: exact typed/UI assertion proven; BLOCKED: missing or ambiguous identity/state/provenance; FAILED: valid contradictory identity or behavior under pinned oracle; dependents NOT_RUN. |
| AND-05-10 | G5 | `refresh_progress` (read_only); **30s** | AND-05-09 first typed parent-progress sample PASSED and retained; expected original parent JobRunId known; exact operation grant. | Apply `validate_active_progress_pair` to first and second committed progress samples: both individually valid, both bound to the *same expected parent* and unchanged phase; second `completed_units` **strictly greater** than first, not child-only progress. | [J:L197](android-job-lifecycle.md#L197), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995), [Executor:L1227–1242](../../scripts/android_qualification/_job_lifecycle_executor.py#L1227-L1242), [Oracle:L119–149](../../scripts/android_qualification/_job_lifecycle_oracle.py#L119-L149) | H fixed operation 30s grant and ordered monotonic timestamps; U/P first and second `RefreshProgressFacts` (exact `parent_run_ref`, phase, `completed_units`, total, status key) with observer/capture IDs. | PASSED: exact parent/phase matched with strictly increased completed units; BLOCKED: flat progress, changed phase, first/second unbound or mismatched parent, incomplete/invalid sample; FAILED: decreased completed units or another proven progress contradiction; dependent operations NOT_RUN. |
| AND-05-11 | G5 | `navigate_library` (navigation); **10s** | AND-05-10 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L198](android-job-lifecycle.md#L198), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-12 | G5 | `library_preloss` (read_only); **20s** | AND-05-07..11 source refresh and visible Library established | Capture complete pre-loss committed GameId baseline/redirect facts under fixed All-active query | [J:L199](android-job-lifecycle.md#L199), [J:L415–435](android-job-lifecycle.md#L415-L435), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | P fixed All-active first-to-terminal same revision and direct GetGame records with page/lookup refs; U distinct visible Library capture | PASSED: complete unique pre-loss GameId baseline; BLOCKED: missing/stale pages, mixed revisions or incomplete direct lookups; FAILED: proven wrong membership vs pinned fixture expectation; stop before force-stop. |
| AND-05-13 | G5 | `navigate_sources` (navigation); **10s** | AND-05-12 passed; exact plan operation grant | Sources destination selected | [J:L200](android-job-lifecycle.md#L200), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-14 | G5 | `open_scan_root` (navigation); **10s** | AND-05-13 passed; exact plan operation grant | Correct admitted LibraryRoot selected | [J:L201](android-job-lifecycle.md#L201), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-15 | G5 | `scan_root_preloss` (read_only); **20s** | AND-05-14 opened an admitted source root before stop | Record identified root/ScanRun/parent tuple before stop | [J:L202](android-job-lifecycle.md#L202), [J:L235–245](android-job-lifecycle.md#L235-L245), [J:L390–412](android-job-lifecycle.md#L390-L412) | U exact root presentation/ref; P original source parent/ScanRun/root, active vs historical type | PASSED: pre-loss root tuple and presentation captured; BLOCKED: unidentified root/ScanRun or active+historical conflict; FAILED: different valid owner; AND-05-21 NOT_RUN. |
| AND-05-16 | G5 | `navigate_jobs` (navigation); **10s** | AND-05-15 passed; exact plan operation grant | Jobs destination and selected state verified | [J:L203](android-job-lifecycle.md#L203), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-17 | G5 | `open_refresh_detail` (navigation); **10s** | AND-05-16 passed; exact plan operation grant | Selected detail is bound to intended parent JobRun | [J:L204](android-job-lifecycle.md#L204), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-18 | G5 | `refresh_detail` (read_only); **20s** | AND-05-17 passed; exact plan operation grant | Parent status, progress and requested root coverage match the authoritative detail | [J:L205](android-job-lifecycle.md#L205), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref); P (typed JobRun/root/ScanRun refs, observer ref) | PASSED: exact typed/UI assertion proven; BLOCKED: missing or ambiguous identity/state/provenance; FAILED: valid contradictory identity or behavior under pinned oracle; dependents NOT_RUN. |
| AND-05-19 | G5 | `parent_child_identity` (read_only); **15s** | AND-05-18 original parent GetJob and all requested/admitted/excluded roots frozen | Exact parent JobRun, admitted roots, one ScanRun per root and exclusions/Retry identity checked | [J:L206](android-job-lifecycle.md#L206), [J:L175–180](android-job-lifecycle.md#L175-L180), [J:L493–496](android-job-lifecycle.md#L493-L496), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | P coherent original JobRun with all unique (parent,ScanRun,root) and typed exclusions; U linked detail nodes | PASSED: one ScanRun for each admitted source root and exact captured partition; BLOCKED: missing/duplicate/ambiguous relation; FAILED: valid different parent; force-stop NOT_RUN. |
| AND-05-20 | G5 | `pre_stop_guard` (read_only); **20s** | AND-05-12 committed Library baseline, 15 root presentation, 18 original parent detail and 19 complete source partition/ScanRun relations PASSED; exact original parent/root tuple captured; no force-stop intent yet. | Immediately before force-stop, require **the exact original parent `RecoveryState.ACTIVE`**, not terminal or any other state; verify pre-loss Sources root/ScanRun attribution to that parent and independent Android **`ProcessState.PRESENT` with foreground package `com.argusromtoolkit.argus.qualification`**. No process-loss experiment may start without all three proofs. | [J:L207](android-job-lifecycle.md#L207), [J:L235–245](android-job-lifecycle.md#L235-L245), [J:L333–340](android-job-lifecycle.md#L333-L340), [J:L491–496](android-job-lifecycle.md#L491-L496), [Executor:L1791–1857](../../scripts/android_qualification/_job_lifecycle_executor.py#L1791-L1857), [Oracle:L389–429](../../scripts/android_qualification/_job_lifecycle_oracle.py#L389-L429), [Executor:L500–544](../../scripts/android_qualification/_job_lifecycle_executor.py#L500-L544), [Oracle:L328–349](../../scripts/android_qualification/_job_lifecycle_oracle.py#L328-L349) | U pre-stop root presentation and fresh parent refresh detail with nonempty observer refs; P exact original parent, ACTIVE state, frozen root partition and ScanRun tuple; P pre-loss committed GameIds; **O independent process PRESENT, package and foreground identity with observer/timestamp**; H authorization and pre-stop guard receipt. | PASSED: same source/root tuple + original parent ACTIVE + independent OS PRESENT/foreground qualified; BLOCKED: terminal/non-ACTIVE/unknown state, root/ScanRun tuple mismatch, missing or unproven foreground, missing OS/P/U evidence; FAILED: different valid owning parent, or independently observed valid foreign package/contradictory process state; **AND-05-21 force-stop NOT_RUN and dependent Retry obligations NOT_RUN**. |
| AND-05-21 | G5 | `force_stop_qualification_package` (force_stop); **10s** | G5: AND-05-20 passed; one exact-package force-stop grant, still inside session deadline | Exactly scoped stop; subsequent independent OS observation must establish process loss | [J:L208](android-job-lifecycle.md#L208), [J:L473–487](android-job-lifecycle.md#L473-L487) | H force-stop intent/dispatch/time; O later independent process-loss evidence, not app success text | PASSED: authorized force-stop completed and OS absence subsequently provable; BLOCKED: uncertain effect/absence (no replay); FAILED: wrong package/process effect; relaunch NOT_RUN. |
| AND-05-22 | G5 | `process_foreground` (read_only); **15s** | AND-05-21 force-stop issued and no product observer query during process-loss checkpoint | Exact package process and foreground state at checkpoint; do not infer continuity from PID reuse | [J:L209](android-job-lifecycle.md#L209), [J:L23–31](android-job-lifecycle.md#L23-L31), [J:L481–487](android-job-lifecycle.md#L481-L487) | O package-scoped process absent and foreground state with observer/time ref; H original package and PID baseline | PASSED: independent process absence consistent with foreground state; BLOCKED: incomplete OS evidence/PID reuse ambiguity; FAILED: contradictory OS state or foreign package; launch NOT_RUN. |
| AND-05-23 | G5 | `launch_qualification_package` (launch); **30s** | AND-05-22 proved process loss and fresh package/foreground preflight passed; separate launch grant | Approved package relaunched after independently observed process loss; no same-task requirement | [J:L210](android-job-lifecycle.md#L210), [J:L481–487](android-job-lifecycle.md#L481-L487) | H exact-package single launch grant/dispatch; O relaunch process/foreground; U later UI surface | PASSED: authorized relaunch after verified loss; BLOCKED: incomplete preflight or uncertain launch (no replay); FAILED: wrong package; same-task across stop NOT required. |
| AND-05-24 | G5 | `foreground_surface` (read_only); **15s** | AND-05-23 passed; exact plan operation grant | Expected foreground package and visible surface at checkpoint | [J:L211](android-job-lifecycle.md#L211) | H (grant, monotonic start/end, exact target); O (package-scoped OS read, observer/time ref); U (selected route, capture/node ref) | PASSED: exact typed/UI assertion proven; BLOCKED: missing or ambiguous identity/state/provenance; FAILED: valid contradictory identity or behavior under pinned oracle; dependents NOT_RUN. |
| AND-05-25 | G5 | `navigate_sources` (navigation); **10s** | AND-05-24 passed; exact plan operation grant | Sources destination selected | [J:L212](android-job-lifecycle.md#L212), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-26 | G5 | `open_scan_root` (navigation); **10s** | AND-05-25 passed; exact plan operation grant | Correct admitted LibraryRoot selected | [J:L213](android-job-lifecycle.md#L213), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-27 | G5 | `scan_root_recovered` (read_only); **20s** | AND-05-15 source root captured before stop; AND-05-23..26 relaunch and correct root reached | Recovered root and exact original ScanRun attribution, with documented active/terminal transition | [J:L214](android-job-lifecycle.md#L214), [J:L239–247](android-job-lifecycle.md#L239-L247), [J:L461–464](android-job-lifecycle.md#L461-L464) | U root presentation/ScanRun/ref after relaunch; P exact original parent/ScanRun/LibraryRoot relation and prior tuple | PASSED: same source relation, historical terminal or valid active→historical transition; BLOCKED: active after recovery or missing IDs; FAILED: foreign valid parent; AND-05-35 NOT_RUN. |
| AND-05-28 | G5 | `navigate_library` (navigation); **10s** | AND-05-27 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L215](android-job-lifecycle.md#L215), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-29 | G5 | `library_recovered` (read_only); **30s** | AND-05-12 complete pre-loss baseline; AND-05-27 persistence passed; authorized post-relaunch All-active query | Every required prior committed GameId retained or direct-redirect proven against complete current view | [J:L216](android-job-lifecycle.md#L216), [J:L248–265](android-job-lifecycle.md#L248-L265), [J:L467–472](android-job-lifecycle.md#L467-L472), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | P complete current GameIds and exactly one token-bound direct GetGame for each required missing pre-loss ID, source-linked lookup/ref; U distinct visible Library | PASSED: all original IDs retained or canonical one-hop redirected into current set; FAILED: complete direct missing/no-redirect proof of loss; BLOCKED: stale/incomplete/ambiguous/foreign/multi-hop evidence; Retry NOT_RUN. |
| AND-05-30 | G5 | `navigate_jobs` (navigation); **10s** | AND-05-29 passed; exact plan operation grant | Jobs destination and selected state verified | [J:L217](android-job-lifecycle.md#L217), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-31 | G5 | `jobs_recovered` (read_only); **20s** | AND-05-29 complete Library persistence passed; Jobs destination selected | No unexpected duplicate or silently resumed JobRun; original parent preserved | [J:L218](android-job-lifecycle.md#L218), [J:L371–390](android-job-lifecycle.md#L371-L390), [J:L465–466](android-job-lifecycle.md#L465-L466) | U identified Jobs rows; P coherent all-retained refresh history original parent and no unexpected resumed/duplicated run; H admitted baseline | PASSED: original parent recovered without silent duplicate; BLOCKED: incomplete history or identities; FAILED: verified silent resume/wrong parent; Retry NOT_RUN. |
| AND-05-32 | G5 | `open_refresh_detail` (navigation); **10s** | AND-05-31 passed; exact plan operation grant | Selected detail is bound to intended parent JobRun | [J:L219](android-job-lifecycle.md#L219), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-33 | G5 | `recovered_lifecycle` (read_only); **60s** | AND-05-32 original refresh detail selected; AND-05-27/29/31 recovery proof passed | Expected lifecycle and parent/child relationships recovered without silent duplicate or resume | [J:L220](android-job-lifecycle.md#L220), [J:L474–480](android-job-lifecycle.md#L474-L480), [J:L333–340](android-job-lifecycle.md#L333-L340) | P exact original parent GetJob terminal state with source relations, nonempty observer ref; U matching detail status/ref | PASSED for recovery consistency: exact Failed/Cancelled/Abandoned with appropriate evidence; FAILED: active silent resume, unapproved Interrupted or cancellation without intent; BLOCKED: Completed/CompletedWithIssues as recovery proof or unavailable state; Retry NOT_RUN. |
| AND-05-34 | G5 | `retry_eligibility` (read_only); **20s** | AND-05-33 original terminal recovery established, AND-05-27 and 29 PASSED, owner-granted Retry not yet dispatched | Exact original JobRun eligible and all prerequisite assertions passed before effect | [J:L221](android-job-lifecycle.md#L221), [J:L333–340](android-job-lifecycle.md#L333-L340), [J:L498–501](android-job-lifecycle.md#L498-L501) | U exactly one Retry control in source detail; P same original parent state and eligibility, H grant/ref | PASSED: exactly one valid control/eligible terminal parent; BLOCKED: missing/malformed state, mismatched known state or control count; NOT_RUN: valid Retry unavailable; FAILED: valid wrong parent; no Retry intent. |
| AND-05-35 | G5 | `retry_library_refresh` (refresh); **60s** | AND-05-27 AND-05-29 AND-05-33 AND-05-34 PASSED; fresh source-bound read immediately before any Retry intent/dispatch; one authorized Retry grant | **Before dispatch:** fresh coherent source-bound relation lookup matches original parent JobRunId, captured requested/admitted/excluded partition, recovered terminal state and every unique original ScanRun/LibraryRoot relation; successor identity/link/scope/partition/exclusions are absent and successor ScanRun relations are **explicit empty tuple**, never unavailable (`None`). **Only then:** one Retry dispatch reuses original requested roots and rechecks eligibility; no second dispatch on uncertainty. | [J:L222](android-job-lifecycle.md#L222), [J:L267–291](android-job-lifecycle.md#L267-L291), [J:L473](android-job-lifecycle.md#L473), [J:L505–506](android-job-lifecycle.md#L505-L506), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995), [BE-013 Retry](../specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md#L790-L829) | P fresh GetJob source/observer ref, exact source partition and ScanRun set, explicit zero successor refs/scope and empty tuple; H grant, eligibility, intent/callback/ref/time; U source control state | PASSED: all absence and source binding preconditions proven, then one eligible dispatch; BLOCKED: missing/stale/contradictory fields, existing/unknown successor, `None` relations, uncertain effect; no Retry intent before proof and no replay. FAILED: proven wrong parent/unauthorized effect; dependent 36–45 NOT_RUN on stop. |
| AND-05-36 | G5 | `retry_outcome` (read_only); **30s** | AND-05-35 authorized exactly one Retry after fresh no-successor proof; original captured source scope, original source ScanRun IDs, and recovered terminal state retained. | A distinct successor JobRunId preserves the original requested roots, rechecks current eligibility, admits at least one root, gives every excluded root a typed BE-013 exclusion, and owns one unique ScanRun per admitted successor root. The original source partition and ScanRun set remain unchanged; source and successor ScanRun IDs must be **disjoint**. | [J:L223](android-job-lifecycle.md#L223), [J:L281–292](android-job-lifecycle.md#L281-L292), [J:L498–505](android-job-lifecycle.md#L498-L505), [BE-013 Retry](../specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md#L790-L829), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995), [Executor:L2060–2102](../../scripts/android_qualification/_job_lifecycle_executor.py#L2060-L2102), [Oracle:L777–905](../../scripts/android_qualification/_job_lifecycle_oracle.py#L777-L905), [Contract:L990–1015](../../scripts/android_qualification/_job_lifecycle_contract.py#L990-L1015) | P separate source/successor `JobIdentityObservation`, captured source root partition, successor current-admission partition, typed exclusions, parent-attributed relation tuples and ID-set intersection; U successor response identity; H one authorized Retry dispatch receipt and observer refs. | PASSED: distinct, complete source/successor partitions and disjoint ScanRun IDs; BLOCKED: missing/ambiguous root scope/exclusions/relations, or **overlapping source/successor ScanRun IDs despite otherwise correctly bound distinct parents** (`retry_complete` false, `validate_identity` blocks); FAILED: valid foreign source/parent, successor identity reusing source, or proven successor ScanRun foreign owner/excluded-root attribution explicitly rejected by `retry_outcome`; AND-05-37..45 NOT_RUN on stop. |
| AND-05-37 | G5 | `retry_relation` (read_only); **15s** | AND-05-36 accepted the exact distinct successor, source root partition, owned ScanRun set and typed exclusions | Independently confirm original parent/successor direct relation and complete source/successor scope, typed exclusions and ScanRun ownership. Source/successor ScanRun IDs remain disjoint; one unique successor ScanRun per admitted root; detailed parent/source IDs are exact and match separate JobIdentityObservation. Never infer any relation from row order, labels or timing. | [J:L224](android-job-lifecycle.md#L224), [J:L267–292](android-job-lifecycle.md#L267-L292), [J:L324–335](android-job-lifecycle.md#L324-L335), [J:L502–504](android-job-lifecycle.md#L502-L504), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995), [BE-013 Retry](../specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md#L790-L829) | P independent JobIdentityObservation (exact source/successor identities, scope, owned relations, nonempty observer ref) plus separate RefreshDetailObservation parent/source IDs and observer ref; H operation/ref | PASSED: independent complete source/successor relation; BLOCKED: missing/incomplete/mismatched JobIdentityObservation, malformed parent/source detail or unavailable evidence; FAILED: different valid parent/source or foreign ScanRun owner; no second Retry and AND-05-38..45 NOT_RUN on stop. |
| AND-05-38 | G5 | `navigate_library` (navigation); **10s** | AND-05-37 passed; exact plan operation grant | Required Library destination selected without unauthorized effects | [J:L225](android-job-lifecycle.md#L225), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-39 | G5 | `library_persisted` (read_only); **20s** | AND-05-29 complete recovery membership and AND-05-35..37 Retry relation PASSED; distinct post-Retry view | Recovered pre-Retry committed baseline not lost by Retry; same-token redirect proof where required | [J:L226](android-job-lifecycle.md#L226), [J:L294–298](android-job-lifecycle.md#L294-L298), [J:L521–525](android-job-lifecycle.md#L521-L525), [BE-015 §21.3–21.4](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#L764-L806) | P complete current GameIds and one direct same-view GetGame lookup per missing *recovered* ID, successor-bound source/lookup ref; U separate Library capture | PASSED: every op29 recovered ID still active or direct-canonical redirected; FAILED: complete no-redirect proof of newly lost ID; BLOCKED: incomplete/stale/foreign/multi-hop evidence; no further Retry. |
| AND-05-40 | G5 | `navigate_sources` (navigation); **10s** | AND-05-39 passed; exact plan operation grant | Sources destination selected | [J:L227](android-job-lifecycle.md#L227), [J:L54–69](android-job-lifecycle.md#L54-L69) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-41 | G5 | `open_scan_root` (navigation); **10s** | AND-05-40 passed; exact plan operation grant | Correct admitted LibraryRoot selected | [J:L228](android-job-lifecycle.md#L228), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-42 | G5 | `scan_root_state` (read_only); **20s** | AND-05-37 exact successor and AND-05-41 correct Sources root passed | Root/ScanRun/owner JobRun association and scan state match, not inferred from View Job label | [J:L229](android-job-lifecycle.md#L229), [J:L298–306](android-job-lifecycle.md#L298-L306), [J:L515–520](android-job-lifecycle.md#L515-L520) | U root active/historical presentation/ref; P unique successor ScanRunId/owning successor JobRunId/LibraryRootId | PASSED: exact authorized root and successor-owned ScanRun in valid active/historical form; BLOCKED: ambiguous/foreign root or presentation; FAILED: valid wrong owner; active does NOT establish terminal success. |
| AND-05-43 | G5 | `navigate_jobs` (navigation); **10s** | AND-05-42 passed; exact plan operation grant | Jobs destination and selected state verified | [J:L230](android-job-lifecycle.md#L230), [J:L54–69](android-job-lifecycle.md#L54-L69), [J:L359–412](android-job-lifecycle.md#L359-L412), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | H (grant, monotonic start/end, exact target); U (selected route, capture/node ref) | PASSED: identified destination/target reached; BLOCKED: unavailable hierarchy or uncertain dispatch; FAILED: conclusively wrong target; later dependent operations NOT_RUN. |
| AND-05-44 | G5 | `open_retry_successor_detail` (navigation); **10s** | AND-05-37 distinct exact successor known; AND-05-43 Jobs selected | Open specifically identified successor JobRun | [J:L231](android-job-lifecycle.md#L231), [J:L313–315](android-job-lifecycle.md#L313-L315) | U successor row/detail resource ref; H navigation grant and target successor identity; P original successor ID | PASSED: selected exact successor detail; BLOCKED: no verified successor ID or ambiguous route; FAILED: opened different valid JobRun; terminal check NOT_RUN. |
| AND-05-45 | G5 | `retry_successor_terminal` (read_only); **60s** | AND-05-37 exact successor/source binding PASSED, AND-05-44 successor detail selected; app expected foreground; fixed **60s monotonic** operation window | **Two separately recorded assertions:** (1) Exact Retry successor observed terminal within **60 seconds while the qualification package remained foreground**; (2) its **Retry-success** state meets pinned outcome rules. `Completed` passes success; `CompletedWithIssues` BLOCKED absent immutable owner criterion; `Failed`/`Cancelled`/`Abandoned` and **`Interrupted`** are terminal observations that FAIL Retry success. Active at deadline or missing/malformed successor ID/state BLOCKS terminal claim; different valid successor ID FAILS identity claim. No second Retry. | [J:L232](android-job-lifecycle.md#L232), [J:L313–335](android-job-lifecycle.md#L313-L335), [J:L477](android-job-lifecycle.md#L477), [J:L509–514](android-job-lifecycle.md#L509-L514), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995) | P coherent successor GetJob with exact typed terminal status + observer ref; U successor detail/status identity; O foreground package checkpoints/time; H monotonic 60s elapsed and pinned oracle refs; separate terminal and success assertion keys | Terminal PASSED only for exact terminal successor within 60s with OS foreground proof; otherwise BLOCKED (missing/active/foreground) or FAILED (wrong valid successor). Retry-success: PASSED only Completed; BLOCKED CompletedWithIssues unless owner-pinned criterion; FAILED Failed/Cancelled/Abandoned/**Interrupted**. No second Retry; owner recovery. |

#### Non-collapsible multi-assertion acceptance requirements

**Progress pair AND-04-10 / AND-05-10.** The executor calls `validate_active_progress_pair` on two committed parent-progress facts. The same expected parent and unchanged phase must have strictly increasing completed units; flat/change-of-phase/unbound parent is **BLOCKED**, a decrease is **FAILED**. The two single-sample progress assertions are not sufficient by themselves. Sources: [Executor:L1227–1242](../../scripts/android_qualification/_job_lifecycle_executor.py#L1227-L1242), [Oracle:L119–149](../../scripts/android_qualification/_job_lifecycle_oracle.py#L119-L149).

**AND-05-20 pre-stop guard.** Immediately before force-stop, the original parent's state must be exactly `ACTIVE`, its selected root/ScanRun attribution verified, and the **independent OS** observation must prove process `PRESENT` and the qualification package foreground. Terminal/non-active or unverified state is **BLOCKED**; valid foreign owning parent and valid contradictory OS package/process are separately **FAILED**. No force-stop and downstream Retry obligations remain **NOT_RUN**. Sources: [Executor:L1791–1857](../../scripts/android_qualification/_job_lifecycle_executor.py#L1791-L1857), [Oracle:L389–429](../../scripts/android_qualification/_job_lifecycle_oracle.py#L389-L429), [Oracle:L328–349](../../scripts/android_qualification/_job_lifecycle_oracle.py#L328-L349).

**AND-04-28 / AND-04-30 historical terminal state (distinct from AND-05-42).** AND-04-28 requires a *historical identified* Sources last scan whose state is one of `ROOT_HISTORICAL_SCAN_STATES`, **in addition to** exact parent/root/ScanRun attribution. AND-04-30 independently reads that ScanRun and matches its terminal state to the one captured at 28: missing/malformed/unestablished detail, unavailable expected relation, or ambiguous root/ScanRun identity is **BLOCKED**. A different valid owning parent is **FAILED**. Once the exact tuple is established, **any** `scan_state` different from AND-04-28's captured historical terminal state is **FAILED**, including a valid nonterminal `scanning` observation when op 28 captured `complete`; the oracle's expected-state mismatch check runs *before* its terminal-state membership check. A correct active root at AND-04-28 cannot pass, unlike **AND-05-42**, where an identified *active* successor ScanRun is allowed for **ownership only**, never terminal-success proof. Sources: [Executor:L2310–2340](../../scripts/android_qualification/_job_lifecycle_executor.py#L2310-L2340), [Executor:L2342–2382](../../scripts/android_qualification/_job_lifecycle_executor.py#L2342-L2382), [Oracle:L545–588](../../scripts/android_qualification/_job_lifecycle_oracle.py#L545-L588), [Oracle:L487–542](../../scripts/android_qualification/_job_lifecycle_oracle.py#L487-L542).

**AND-04-25 (§3, 60 s).** This is not merely a successful read of `GetJob`. The original parent must reach an observable terminal state within the **existing 60-second monotonic bound**; the identity/status evidence must be coherent with the matching UI. If still active when the deadline expires or the terminal result is unavailable, mark **BLOCKED**, leave **AND-04-26 through 31 NOT_RUN**, and do not extend the operation or session timeout. A conclusive different valid parent is **FAILED**. Sources: [J:L165–173](android-job-lifecycle.md#L165-L173), [J:L490](android-job-lifecycle.md#L490).

**AND-05-35 (pre-dispatch source-bound no-successor proof).** Before recording *Retry intent* or dispatching:
1. Require AND-05-27 (root recovery) and AND-05-29 (Library persistence) PASSED, plus recovered terminal source state and current Retry eligibility from AND-05-33/34; use one **fresh** coherent source-bound relation lookup.
2. Bind the exact original parent JobRunId, captured **requested/admitted/excluded** root sets, recovered terminal state, one unique source ScanRun per source-admitted root and all source `(parent JobRunId, ScanRunId, LibraryRootId)` tuples.
3. Prove there is **no** successor JobRunId, direct source/successor link, successor scope, successor requested/admitted/excluded partition, typed exclusion or successor ScanRun relation. The successor relation collection must be the **explicit empty tuple**; an unavailable `None` or omitted field is not empty evidence. Any successor metadata of uncertain identity blocks before intent/dispatch.
4. Only after those checks, perform the **one** owner-authorized Retry of the original requested root set with eligibility rechecked. A failed or uncertain effect must not be replayed. Any missing, stale, conflicting, nonempty, or unavailable precondition is **BLOCKED**, not absence; dependent work remains **NOT_RUN**. Sources: [J:L267–281](android-job-lifecycle.md#L267-L281), [J:L473](android-job-lifecycle.md#L473), [J:L505–506](android-job-lifecycle.md#L505-L506), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995), [BE-013 Retry](../specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md#L790-L829).

**AND-05-36 (successor outcome and scope).** The Retry successor is a *different* JobRunId from the original; it retains the **original requested root set** but may admit a different eligible subset. The current-eligibility recheck and changed admitted/excluded partition are recorded explicitly. There must be **at least one admitted root**, exactly **one successor-owned ScanRun for each admitted root**, and a typed **SPEC-BE-013** exclusion reason for **every excluded requested root**. The source's requested/admitted/excluded partition and exact source ScanRun set must still equal their **pre-interruption captured values**. Source and successor ScanRun IDs must be **disjoint**. Missing/ambiguous partition, exclusions or relations are **BLOCKED**. **Overlap of source/successor ScanRun IDs alone, when distinct parents and the otherwise valid partitions remain bound, is BLOCKED**: `retry_complete` becomes false and `validate_identity(retry=True)` does not accept it; do not reinterpret this as `FAILED`. A proven foreign source/parent or a successor ScanRun attributed to a foreign parent or an excluded root through the explicit `retry_outcome` contradiction check is **FAILED**. Sources: [J:L281–291](android-job-lifecycle.md#L281-L291), [BE-013 Retry](../specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md#L790-L829), [BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md#L2870-L2995).

**AND-05-37 (independent relationship proof).** An independently sourced `JobIdentityObservation` must verify the exact original-to-successor direct link, requested scope, both admitted/excluded partitions, typed exclusion reasons and complete source/successor ScanRun-to-root ownership; IDs remain disjoint and unambiguous. The separately captured `RefreshDetailObservation` must identify the expected successor parent and original source. Missing, incomplete or unbinding independent identity evidence is **BLOCKED**, as is malformed/missing detail identity; a **different valid** parent/source is **FAILED**. Neither list order, display labels nor timing supplies the link. No second Retry. Sources: [J:L267–292](android-job-lifecycle.md#L267-L292), [J:L324–335](android-job-lifecycle.md#L324-L335), [J:L502–504](android-job-lifecycle.md#L502-L504).

**AND-05-45 (two independent terminal/outcome claims, 60 s).** Record **both**:
1. Terminal observation: independently bound **exact successor** becomes terminal during the **fixed 60-second window**, with the **qualification package continuously foreground for the required observation**. Prove exact successor JobRunId, nonempty observer provenance, matching UI detail and OS foreground evidence. Missing/malformed ID, unavailable foreground evidence or `Active` at the deadline is **BLOCKED**; different *valid* successor identity is **FAILED**. A supported terminal state may satisfy this assertion even when Retry success fails.
2. Retry success: apply **pinned** outcome policy to the same exact successor, independent of terminal timing. `Completed` = **PASSED**. `CompletedWithIssues` = **BLOCKED** without immutable owner-approved acceptance. `Failed`, `Cancelled`, `Abandoned` and **`Interrupted`** = **FAILED** Retry-success assertion even when terminal observation passed. No automatic second Retry; owner recovery. In contrast, `Interrupted` on the *original post-stop parent* at AND-05-33 is a failed recovery-consistency case, not a successful Retry. Sources: [J:L313–331](android-job-lifecycle.md#L313-L331), [J:L474–480](android-job-lifecycle.md#L474-L480), [J:L509–514](android-job-lifecycle.md#L509-L514).
