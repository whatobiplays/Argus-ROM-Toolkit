# First Android Add & Scan qualification boundary

This document describes the host-testable plan for one fresh Android
Qualification Release Add & Scan session. Host simulation checks the operation
bindings and failure behavior. It does not connect to Android, qualify genuine
game identity, or produce an owner verdict.

## Operating boundary

The public qualification CLI and the public physical runner remain fail-closed.
The private `_AddScanOperationExecutor` accepts only an injected typed
transport and is exercised with fake transports. No production transport
constructor or live command is provided. A successful fake workflow therefore
returns `BLOCKED`; physical qualification is a separate owner-authorized gate.

The target package is always
`com.argusromtoolkit.argus.qualification`. Every target check uses the exact
owner-approved target reference. The host artifact must match the approved APK
digest, package, version, certificate, source revision, and clean source state.
After install or before reset, the injected observer must report the exact
qualification package, version, signer, and installed artifact digest. A
package-name match or signer match alone does not establish the APK identity.
The ordinary `com.argusromtoolkit.argus` package is never an execution target.

## One closed operation plan

The first-session plan has nineteen operations in a fixed order:

1. Install the pinned APK only when the qualification package is absent, or
   clear data only when the exact compatible qualification APK is already
   installed and the owner explicitly authorized reset.
2. Stage the manifest-bound fixture set into the symbolic
   `qualification_fixture_root` destination and require a receipt bound to the
   authorization session, fixture manifest, file count, byte count, and
   content digest.
3. Launch the qualification package and use the normal onboarding controls.
4. Open the exact approved fixture directory, select the exact `Add & Scan`
   control on its confirmation screen, and verify scan admission from the root
   detail. Creating a root or viewing a populated Library is not evidence of
   scan admission.
5. Independently record the scan-admission observation, parent job status,
   child scan terminal outcome, and each expected fixture-specific Library
   result.
6. Remove only the session-owned fixture set after its ownership is verified
   and, if Add & Scan was attempted, after terminal job and scan states are
   observed.

The UI parser uses the qualification package explicitly and rejects foreign or
ambiguous surfaces. It accepts only allowlisted labels and emits opaque
fixture-result indexes. The expected title and platform values are compared in
memory; raw accessibility text is not written to evidence.

The job observation remains bound to the one Add & Scan session through a
closed route chain: the root detail confirms scan admission and exposes one
unique `View Job` control; the executor selects that control once; and the
resulting page must expose one `Library Scan` heading and one parent status plus
one child status in each captured snapshot. The production page does not render
run identifiers, so this plan does not infer them from elapsed time or hidden
application state. A missing or duplicate route control, foreign screen,
missing status, or contradictory parent/child pair blocks the observation.

Only the production job-detail label `Loading job details` is treated as
transient loading. A loaded active parent state (`Queued`, `Preparing`, or
`Running`) must appear with the child `Scanning` state. Each poll takes one
accessibility capture and derives both statuses from that same snapshot. Polls
wait at most 250 milliseconds and are bounded by the operation, session, and
owner-approval deadlines; the executor checks the deadline before every wait
and capture. Explicit product failure, unknown or ambiguous surfaces, and
conflicting parent/child states stop immediately. Once a terminal pair is
observed, the separate terminal-outcome evidence operation consumes that exact
pair without another capture. Elapsed time, a disappearing page, or a later
unrelated frame cannot stand in for terminal evidence. An interrupted poll is
classified as interrupted and does not authorize cleanup while scan state is
unresolved.

## Installation and reset decisions

Admission distinguishes three states. An absent package permits only the
explicit pinned-artifact install operation. A compatible installation must
match the exact package, version, signer, and APK digest, and it permits only
the separately authorized qualification-package data reset in this fresh
session. An incompatible, unknown, ambiguous, or wrong-signer installation
blocks before mutation. The plan never uninstalls an application or silently
replaces an installation. No-reset qualification is outside this slice.

Before claiming the one-use session or observing the target, admission sums the
timeouts for every non-cleanup operation and the separately authorized cleanup
operation. Their combined budget must fit within the owner approval window, the
session deadline, and the cleanup deadline; cleanup must also fit the explicit
cleanup reserve. If any bound is too short, admission blocks without claiming
the session or contacting the admission observer. Runtime checks continue to
enforce the live owner approval window during cleanup. The cleanup deadline is
an additional upper bound; it does not extend approval authority after
`valid_until`.

## Failure, interruption, and recovery

Before each product mutation, the execution writer durably appends an intent
assertion. The transport is called once, then the observed result is appended.
If intent persistence fails, that mutation does not start. If a mutation result
is uncertain, the executor appends a blocked result and a structured owner-
recovery request, then never retries the mutation. This applies to install or
reset transport errors, post-mutation package identity mismatches, launch and
navigation errors, and a staging receipt that does not match the approved
session, fixture manifest, count, and content digest. If the result cannot be
durably appended, the executor stops before the next mutation and retains the
recovery request in its returned blocker. Transport error details are not
copied into the evidence record.

No later workflow operation runs after a failure. The only allowed follow-up is
the exact cleanup operation when a valid receipt proves session ownership and
the scan is known to be terminal or was confirmed not admitted. An uncertain or
mismatched staging receipt proves no cleanup ownership, so cleanup is withheld.
An explicit failed product assertion finalizes evidence with outcome `FAILED`;
interruption uses `INTERRUPTED`, and unresolved prerequisites or mutation
outcomes use `BLOCKED`. The overall host execution status remains `BLOCKED` in
all cases.

An uncertain Add & Scan tap is not repeated. The executor may continue with
read-only observations to establish whether the scan was admitted and reached
terminal state. It does not remove fixture inputs while the scan may still be
active. If terminal state or fixture ownership cannot be established, cleanup
is withheld and a structured owner-recovery request is required. If an earlier
step fails before scan admission, only the separately authorized cleanup may
follow, and only after the exact staged-set receipt proves session ownership.
Cleanup is attempted at most once, only for the exact staged session set, and is considered
complete only when its receipt matches the approved session and manifest and
reports zero remaining files. A failed cleanup or evidence append remains
visible as a blocker.

The executor checks the approved target and expected foreground package before
each planned operation. Each transport call is checked against the one-use
session binding and the operation's cumulative deadline. The owner-approval
window and session deadline are rechecked throughout. It also refuses to
begin while an Issue #23 permission-restoration obligation is pending. The
existing permission executor and its exact snapshot restoration flow are
unchanged; the Add & Scan plan does not grant or change permissions.

The transport receives only the closed `qualification_ui_capture` slot for UI
captures. A future separately authorized transport must map that slot to the
session-specific file
`/data/local/tmp/argus-qualification-ui-<session-id>.xml`, read it in memory,
and remove that exact temporary file. The location is outside
`qualification_fixture_root`; captures, logs, and working files must never
enter the approved fixture inventory. The current implementation supplies no
device transport, so host tests verify the typed slot and do not claim that a
physical transport has met this contract.

## Identity and acceptance limits

The Issue #24 fixture manifest, transferred bytes, structural validation, and
`pinned_unverified` identity evidence do not establish genuine game identity.
Synthetic fixtures and synthetic Library labels are host tests only. A future
eligible physical result requires independently owner-validated identity
expectations and actual observations for all four Add & Scan evidence gates:
scan admission, parent job status, terminal scan outcome, and fixture-specific
Library results. The automation appends execution evidence only. It never
creates an owner verdict or declares Android qualification or release
readiness. Missing owner validation and separate physical authorization remain
blockers, not scope-extension requests for a capability already represented by
this closed plan. A scope-extension request is emitted only for an actual
out-of-plan recovery capability, such as resolving an uncertain device-side
mutation. A successful host simulation therefore has no scope extension, but
still returns `BLOCKED` and cannot satisfy physical qualification.

The selected design reuses the production Flutter workflow without changing
Flutter or Rust. A separate qualification-only product API was rejected because
it would no longer demonstrate the normal user flow. Reusing the legacy
physical runner was rejected because it targets the ordinary package and
contains broader uninstall, clear, and fixture operations. A generic shell or
path executor was rejected because it cannot bind every effect to the single
approved session. An unconditional reinstall or data reset was rejected
because either could replace or erase state without an exact owner-authorized
decision.
