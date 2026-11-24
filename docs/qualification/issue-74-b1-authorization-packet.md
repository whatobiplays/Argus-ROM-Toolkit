# Issue #74 B1 session record

**Template only. Physical B1 remains NOT_RUN.**

Use the [proportionate session workflow](device-authorization.md#proportionate-session-workflow).
The owner approved removal of the former packet-review and external-custody
requirements on 2026-11-20. The existing filename is retained for links and
task history. This record collects the facts needed to authorize and review a
bounded B1 session; it is not itself execution authority.

## 1. Identity preflight

An identity-only attempt does not need a B1 packet. An ordinary owner
instruction authorizing the selected target and the following procedure is
sufficient. Reuse that instruction rather than asking for duplicate approval.
Target selection or approval of this process change alone does not run it.

1. Use the selected private serial with the reviewed host adapter. Record the
   owner instruction and source/procedure reference.
2. Run one `get-state`, followed by one `getprop ro.build.fingerprint` only if
   the validated state is exactly `device`. Both share one five-second
   host-monotonic deadline. No enumeration, retry, fallback or other operation
   is included. The current attended session can be the execution window.
3. Save a small private outcome: target serial, observed fingerprint if
   available, acquisition time, monotonic start/finish, command counts and
   classification. Record an unrun conditional command as `NOT_RUN`.
   Missing, malformed, late or inconsistent identity is `BLOCKED`.
4. Share only an opaque target reference and sanitized status. Retain no raw
   output or stderr. No packet digest, independent identity reviewer, separate
   receipt, custodian, fixed retention period or unrelated B1 fields are needed.

The selected target is KONKR Pocket Advance. Its identity preflight established
the exact build fingerprint, which remains in the private outcome record. Keep
the serial private. Identity success establishes no artifact, OS-parser,
transport or B1 qualification. The identity attempt had no device mutation or
cleanup action.

## 2. Before the B1 session

The executor fills known values from source, artifacts and existing records.
The owner decides the intended effects and approves the complete bounded
session. Use references to existing reviewed information instead of copying
it into multiple forms. The following facts must be concrete before execution:

| Fact | Record or reference |
|---|---|
| Session | Opaque session identifier, purpose, owner approval reference and agreed start/expiry. |
| Source and procedure | Reviewed host-adapter revision and source state, procedure revision, APK source revision and embedded `probeSourceCommit`. Record those identities separately. |
| Artifact | Exact final signed APK SHA-256, signer certificate SHA-256, package/version/variant and build/provenance reference. The embedded source commit must match the source used to build the APK. |
| Target | Opaque shared reference; private serial, exact observed build fingerprint and relevant API/ABI/OEM facts with their evidence references. The two-command identity preflight does not establish API or ABI. |
| Operations and bounds | Exact command vectors/effects, permitted counts/order, fixed requests, private owner controls, socket endpoint and forward tuple, OS observations and cleanup. Use the fixed limits below. Unlisted effects are excluded. |
| Baseline and restoration | Observations allowed before mutation; expected package/task/process state; absent-before-creation forward check; exact restoration actions and confirming readbacks. Acquire device baselines after session approval and before mutation. |
| OS evidence | Required facts/checkpoints, exact commands, reviewed build-specific parser/profile, completeness/error rules and independent acquisition times. Exploratory notes do not fill this field as qualified evidence. |
| Evidence | Existing owner-private location, sanitized shared report destination and relevant evidence/digest references. No serial, fingerprint, private path, raw dump, stderr, screenshot or unrelated app state in shared evidence. |
| Review | Independent code/procedure review reference and findings disposition. Review the source, artifact provenance, access rules, observations and cleanup; a separate approval of this record's digest is unnecessary. |

An unsigned or CI-signed test artifact is not automatically approved for
physical use. Keep the host, procedure and APK source identities distinct.
A changed target/build, artifact/signer, operation or material procedure
requires reassessment and approval of the affected scope, not repetition of
unaffected checks.

## 3. Session controls

1. Keep the 600-second session maximum, five-second phase/Readiness maximum,
   five-second discovery admission, one-second socket release and separate
   60-second forward-cleanup reserve. Specify host and Android clock readings
   in their own domains. No timeout extends operation authority.
2. Permit only the approved probe install/start, one exact session-owned
   forward, deny-only discovery, fixed Readiness requests, specified OS
   observations and exact cleanup/restoration. Listing a candidate operation
   here does not authorize it. Data reset is not implicit cleanup.
3. Retain direct owner controls and observation/confirmation of the exact peer
   UID before enforcement. Never trust the first UID automatically, adopt a
   pre-existing forward or substitute a target. No automatic retry or fallback.
4. Record restoration obligations before mutation. Verify the exact owned
   tuple before removal and the required state after cleanup. Exit code zero
   alone is insufficient. Uncertain creation, ownership or restoration remains
   blocked; additional recovery effects need owner authority.

One approval covers the listed session operations. It does not authorize B2,
production activation, pin changes, later qualification or destructive
effects outside that scope.

## 4. Formal B1 procedure

Use the standing [Issue #74 owner authorization](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/74#issuecomment-7063468806) for this controlled-device scope. The owner operates the probe controls and Android navigation and confirms the actual forwarded peer UID during the session. Record those actions against the session identifier. Admission also requires independent review of the exact procedure and adapter, required CI, verified artifact and baseline, and usable sources for every required OS assertion below.

Record a fresh session ID, discovery attempt ID, nonzero host loopback port and matching abstract socket name before beginning. Bind the host session start and absolute expiry before mutation. Stop collecting checkpoints and begin restoration at least 60 seconds before that expiry, or earlier on failure. This leaves the last minute of the ordinary session for the owned uninstall and restoration reads. The separate post-expiry reserve remains forward-only. Use the approved signed APK in the [artifact record](../tasks/task-issue-74-readiness-probe.md#checkpoint-h--signed-readiness-apk-digest-correction-2026-11-22). Recompute its digest and verify signer, manifest, package/version and embedded source revision. Keep the target serial, build, user, endpoint, peer UID and observation identifiers private.

| Step | Action and evidence |
|---|---|
| 0. Baseline | Rebind the exact target/build and current user. Verify all-user probe absence, complete Package Manager history with no conflicting live or finalized session, no open current journal, and absence of the exact planned forward. Record the prior selected-device forward and Package Manager baselines for restoration. Keep unresolved legacy records separate from this attempt. |
| 1. Passive launch | Journal one new attempt and install the pinned APK through the existing session-backed adapter. Verify package, user, version, UID and installed digest. Launch the reviewed launcher once and have the owner enter the control screen. Capture **C1** before arming discovery. The owner sees the control screen in its inactive state. |
| 2. Transport and Readiness | Persist the forward obligation and use `ForwardSession.create()` for one exact no-rebind forward and readback. The owner enters the raw socket name on Android and arms deny-only discovery. In coordination with that tap, record the host monotonic arm time and call `ForwardSession.arm()` with the discovery attempt ID. Use the same name with the `localabstract:` prefix on the host. Open one deny-only connection through `open_discovery_transport()` before either five-second admission window closes. Send zero application bytes. Require a bounded read to confirm EOF with zero response bytes, then record completed release. Correlate the entire device discovery window with exactly one host attempt, matching session, endpoint and attempt IDs, counts and intervals on their respective clocks. Require the owner to confirm the correlation and separately approve, enter and activate the exact observed UID. Call `enforce()` with that confirmation and open one distinct Readiness connection through `open_readiness_transport()`. Send one fixed ObserverV1 **Readiness** request through `AttemptRunner`, reserve the existing failure-receipt slot and require one validated `{"state":"Ready"}` result and timely release. Capture **C2** after release, before navigation. The owner records the enforcing control screen and whether any navigation or display change occurred. |
| 3. Background and return | Have the owner press Home once without killing the process. Capture **C3** while the Home screen remains visible. Then have the owner return to the same task through Recents once, without invoking the launcher. Capture **C4** before another action. Expect the original task to return without another arm action or an unplanned navigation. Record the exact visible screen and label. The control screen can retain its previous status text after pause. Treat this as a UI observation only. The reviewed on-pause shutdown behavior establishes what the source does. A physical claim about listener shutdown or absence of rearming would also need an independent, qualified endpoint observation. No additional socket connection or Readiness request belongs to this transition. |
| 4. Restore | Have the owner press Stop session if the control screen is available. Verify every opened socket released and remove only the exact owned forward through `ForwardSession.cleanup()`. Perform the adapter's journal-backed version-scoped uninstall only for the verified installed attempt. Read back all-user package absence, absence of the probe process, no remaining owned forward, and complete Package Manager history with no outstanding live session and the prior history preserved. Close only verified obligations. Record any unresolved obligation and keep its journal. |

For **C1–C4**, record host monotonic action, acquisition start/finish and completion times, with the owner’s visible screen observation tied to the same checkpoint. Keep the device stable between the checkpoint's component observations. Independently collect the fixed build-bound Activity Manager observation and the package-scoped process observation once per checkpoint. Collect bounded WindowManager evidence at C1, C2 and C4 to corroborate the selected window's display and foreground position. At C3, the required facts are the retained activity/task, loss of resumed and top-resumed state, and independent observation of Home. Record changes in display or mode if the OS evidence establishes them. End the attempt on an incomplete checkpoint or an unplanned transition. The reviewed bounds in [runbook sections 3–4](android-readiness-probe.md#3-resource-and-wire-boundaries) and section 3 above apply throughout. The cleanup reserve is only for forward cleanup.

| Assertion | Comparison and source |
|---|---|
| Ownership and task identity | The qualified Activity Manager history row binds the exact control component and Android user to its leaf and root task. Compare the activity token, leaf task number and instance token, root, and bound user across C1–C4. The Home and Recents observations bound the interval that requires same-task evidence. A matching task number alone supplies no continuity evidence. |
| Resumed and top-resumed | Check state and the per-root resumed reference separately from the global top-resumed reference. Expect both at C1, C2 and C4, and neither for the selected activity at C3. A qualified different value is an observed change. An unbound reference, rejected observation or missing checkpoint is incomplete evidence. |
| Display and windowing | Use Activity Manager for the logical display and task mode at each checkpoint. At foreground checkpoints, corroborate the exact probe window and its display and foreground state with the qualified WindowManager result and the owner's direct screen observation. |
| Process identity and lifecycle | Use the package-scoped query for main-process presence and the installed UID. To compare process instances where continuity is required, bind the target process to an independently observed incarnation identifier captured at the same checkpoint. PID, package and UID alone cannot rule out reuse. A verified changed incarnation across Checkpoints C1–C4 fails the expected same-instance assertion. A lost probe session on backgrounding is expected even if the process remains. Verified process absence after uninstall is a separate restoration fact. |
| Independent evidence | Keep **P** for the validated protocol result, **U** for direct owner UI observations, **O** for independently acquired OS facts and **H** for host provenance, timing, authorization, commands and restoration. Each must support its own assertions. Persist only approved private facts and bounded receipts. |

**Admission gaps.** The current process query projects role, count and UID consistency without an incarnation identifier. The existing WindowManager path supplies exploratory aliases and cannot establish complete, exact window/display evidence. The first missing process fact is a stable birth marker bound to the UID and PID of the exact main process. The first missing WindowManager facts are a uniquely attributable probe window, its display and foreground state, and an exact-build completion indicator. The fixed Activity Manager reader requires an explicit per-root resumed row. Android 12 can omit the row when the root has no resumed activity. The current reader rejects that shape even with a complete frame, a stopped target and a different top-resumed activity. Confirm C3 on the selected build and review how a complete negative result differs from missing evidence. [Android 12 ActivityTaskSupervisor](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android12-release/services/core/java/com/android/server/wm/ActivityTaskSupervisor.java#1973) Investigate these specific gaps with reviewed bounded local acquisition.

The adapter and wire classes supply the session primitives. Before execution, review the concrete caller, including its durable forward-obligation callback and failure cleanup. Preserve the public live-execution guard. Formal B1 remains blocked until the required sources and caller are admitted.

Record a complete observed violation as `NO-GO`, missing or incomplete evidence as `BLOCKED`, and unattempted assertions as `NOT_RUN`. A `PASS` requires all listed evidence, verified restoration and independent review of the physical outcome. The procedure supplies no B2 result.

## 5. Exploratory OS observations

Use [runbook section 9](android-readiness-probe.md#9-os-evidence-readiness-and-observation-prerequisites)
for a separately scoped exploratory observation when the build's grammar or
observable facts are unknown. A fully qualified semantic parser is not an
entry requirement for exploration. The acquisition/privacy path still needs
review and the owner must authorize the exact bounded observation scope.

Preserve the Q7 command restriction, 1 MiB total and 16 KiB line caps,
three-second device timeout and five-second host deadline. Keep raw output
only in local bounded memory; exclude it from logs, terminal transcripts,
tool responses and chat, and immediately discard unrelated records. Retain
only sanitized exploratory target notes. No raw dumps, stderr or raw-dump
hashes, automatic retries or partial facts presented as complete evidence.
If privacy or acquisition bounds cannot be enforced, stop.

Exploration grants no install, launch, forwarding, UID enrollment or B1/B2
authority. Before formal assertions use the result, independently review the
exact-build semantics, completeness/error handling and acquisition/parser
implementation, then collect fresh complete observations under the approved
qualification procedure. Synthetic fixtures and exploratory notes cannot
establish a physical PASS.

## 6. Outcome and retention

Record what actually ran, relevant timings and command counts, exact
artifact/target/session identities, sanitized observations, evidence digests,
stop events and verified cleanup or outstanding obligations. Keep P/U/O/H
evidence independent. Verified incorrect behavior is `FAILED/NO-GO`; missing
or uncertain evidence is `BLOCKED`; dependent unattempted checks are `NOT_RUN`.
Independently review the B1 report before treating it as B1 PASS. B2 requires
a separate approved session and independently reviewed report.

Keep evidence needed to support a result while that result is relied upon.
Daniel controls retention and deletion; a 180-day period or calendar deletion
date is optional, not an admission prerequisite. Reuse the approved private
storage arrangement unless its access or backup/sync exposure changes. Do not
delete or rewrite earlier private records as part of adopting this template.

Digests identify exact retained bytes and permit later comparison. Preserve
the existing runtime failure receipts, evidence capacity and integrity checks.
External custody, email delivery and a separate tamper-evident receipt are not
required; do not claim local hashes prove authenticity against a malicious
storage owner. Corrections to completed qualification evidence remain new,
linked records rather than silent rewrites.
