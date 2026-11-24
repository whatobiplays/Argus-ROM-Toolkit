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
| 0. Baseline | Rebind the exact target/build and current user. Verify all-user probe absence, complete Package Manager history with no conflicting live or finalized session, no open current install or forward obligation, and absence of the exact planned forward. Record the prior selected-device forward and Package Manager baselines for restoration. Keep unresolved legacy records separate from this attempt. |
| 1. Passive launch | Journal one new attempt and install the pinned APK through the existing session-backed adapter. Verify package, user, version, UID and installed digest. Launch the reviewed launcher once and have the owner enter the control screen. Capture **C1** before arming discovery. The owner sees the control screen in its inactive state. |
| 2. Transport and Readiness | Persist the forward obligation and use `ForwardSession.create()` for one exact no-rebind forward and readback. The owner arms deny-only discovery after verifying the three setup fields. In coordination with that tap, record the host monotonic arm time and call `ForwardSession.arm()` with the discovery attempt ID. Use the same name with the `localabstract:` prefix on the host. Open one deny-only connection through `open_discovery_transport()` before either five-second admission window closes. Send zero application bytes. Require a bounded read to confirm EOF with zero response bytes, then record completed release. Correlate the entire device discovery window with exactly one host attempt, matching session, endpoint and attempt IDs, counts and intervals on their respective clocks. Require the owner to confirm the correlation and separately approve, enter and activate the exact observed UID. Call `enforce()` with that confirmation and open one distinct Readiness connection through `open_readiness_transport()`. Send one fixed ObserverV1 **Readiness** request through `AttemptRunner`, reserve the existing failure-receipt slot and require one validated `{"state":"Ready"}` result and timely release. Use the attended `run_readiness_exchange()` caller for this phase. It removes the exact owned forward and verifies absence before returning. Capture **C2** after that readback and before navigation. The owner records the enforcing control screen and whether any navigation or display change occurred. |
| 3. Background and return | Have the owner press Home once without killing the process. Capture **C3** while the Home screen remains visible. Then have the owner return to the same task through Recents once, without invoking the launcher. Capture **C4** before another action. Expect the original task to return without another arm action or an unplanned navigation. Record the exact visible screen and label. The control screen can retain its previous status text after pause. Treat this as a UI observation only. The reviewed on-pause shutdown behavior establishes what the source does. A physical claim about listener shutdown or absence of rearming would also need an independent, qualified endpoint observation. No additional socket connection or Readiness request belongs to this transition. |
| 4. Restore | Have the owner press Stop session if the control screen is available. Verify every opened socket released and the exact owned forward remains absent. The exchange uses `ForwardSession.cleanup()` for removal and first readback, including on handled failures. An unfinished or uncertain obligation stays open. Perform the adapter's journal-backed version-scoped uninstall only for the verified installed attempt. Read back all-user package absence, absence of the probe process, no remaining owned forward, and complete Package Manager history with no outstanding live session and the prior history preserved. Close only verified obligations. Record any unresolved obligation and keep its journal. |

On the [owner-approved assisted target](https://github.com/whatobiplays/Argus-ROM-Toolkit/pull/91#issuecomment-7133964799), the owner selects each empty identifier field and confirms focus. The host rechecks the target, build, bound user, and original foreground probe activity and display before and after entering one expected session value. Keep the device untouched during entry. The owner checks the inserted value before moving to the next field. The three setup fields are filled before the arm cue. Fill the two confirmation fields only after the owner compares the actual one-peer Android observation with the host attempt and records its UID and elapsed times. The owner checks the correlation box, taps Confirm, then separately enters and approves the observed UID on Android. The host records each dialog outcome and completion time. Operator dialogs use the remaining session budget before the restoration cutoff. The five-second arm and Readiness gates run outside the operator prompts.

For **C1–C4**, record host monotonic action, acquisition start/finish and completion times, with the owner’s visible screen observation tied to the same checkpoint. Keep the device stable between the checkpoint's component observations. Independently collect the fixed build-bound Activity Manager observation and the package-scoped process observation once per checkpoint. At C3, require the retained probe activity and task, the probe's negative resumed and top-resumed results, a same-display Home root linked to the global top-resumed activity, and the owner's direct observation of Home. Record changes in display or mode if the OS evidence establishes them. End the attempt on an incomplete checkpoint or an unplanned transition. The reviewed bounds in [runbook sections 3–4](android-readiness-probe.md#3-resource-and-wire-boundaries) and section 3 above apply throughout. The cleanup reserve is only for forward cleanup.

| Assertion | Comparison and source |
|---|---|
| Ownership and task identity | The qualified Activity Manager history row binds the exact control component and Android user to its leaf and root task. Compare the activity token, leaf task number and instance token, root, and bound user across C1–C4. The Home and Recents observations bound the interval that requires same-task evidence. A matching task number alone supplies no continuity evidence. |
| Resumed and top-resumed | Check state and the per-root resumed reference separately from the global top-resumed reference. Expect both at C1, C2 and C4, and neither for the selected activity at C3. A qualified different value is an observed change. An unbound reference, rejected observation or missing checkpoint is incomplete evidence. |
| Display and windowing | The fixed Activity Manager reader binds the probe activity and leaf task to the root and logical display and reports the task's windowing mode. Corroborate the expected foreground surface directly with the owner. ADR-005 Q7/Q11 and ObserverV1 §11.6 require task/display/mode and foreground evidence. The procedure makes no window-token assertion. WindowManager is available for bounded exploratory follow-up if the activity association is ambiguous. |
| Process identity and lifecycle | Use `read_readiness_process()` to record the exact main-process PID privately with installed UID validation and the checkpoint timeline. Android PID is the sole process identity under ADR-005 Q20. A changed PID or a verified absence is an observed change. Equal PIDs at separate checkpoints leave uninterrupted lifetime unproven. If a required assertion depends on unproven continuity, mark it BLOCKED. Verify process absence after uninstall as a separate restoration fact. |
| Independent evidence | Keep **P** for the validated protocol result, **U** for direct owner UI observations, **O** for independently acquired OS facts and **H** for host provenance, timing, authorization, commands and restoration. Each must support its own assertions. Persist only approved private facts and bounded receipts. |

For C3, Android 12 can omit the scoped resumed row when the root has no resumed activity. The fixed reader accepts that omission only in a complete acquisition with a bound paused or stopped target, no conflicting scoped result, and a global top-resumed reference matching the same-display Home root's unique scoped reference and its user-bound activity history row. The owner independently confirms the displayed Home surface. Qualify this shape on the selected build before formal use. [Android 12 Task](https://github.com/aosp-mirror/platform_frameworks_base/blob/android12-release/services/core/java/com/android/server/wm/Task.java#L7300) · [Android 12 ActivityTaskSupervisor](https://github.com/aosp-mirror/platform_frameworks_base/blob/android12-release/services/core/java/com/android/server/wm/ActivityTaskSupervisor.java#L1973)

Review the attended live caller and its durable forward obligation and failure cleanup before execution. A host interruption with an unresolved obligation blocks subsequent admission. The public live-execution guard stays in effect.

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
