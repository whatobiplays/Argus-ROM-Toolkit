# Issue #74 B1 authorization packet proposal

**Status: unpopulated proposal. This file is not an authorization. Physical B1 remains NOT_RUN.**

Prepare a separate copy for each preliminary target-observation attempt or physical B1 attempt. Keep serials, owner identity, signatures and permitted identifying evidence in owner-private storage. Raw diagnostic output and stderr must never be retained, including privately. Complete every required field and obtain independent pre-device review before the owner authorizes any operation. This template grants no device access or command authority.

## 1. Candidate source and artifact

1. Host adapter repository and exact source commit: `OWNER ENTRY REQUIRED`
2. Adapter source tree state and digest: `OWNER ENTRY REQUIRED`
3. B1 procedure path, revision and digest: `OWNER ENTRY REQUIRED`
4. APK source checkout commit: `OWNER ENTRY REQUIRED`
5. Embedded `probeSourceCommit`: `OWNER ENTRY REQUIRED`
6. APK SHA-256 and signer certificate SHA-256: `OWNER ENTRY REQUIRED`
7. Build workflow, run identifier and provenance record: `OWNER ENTRY REQUIRED`

The APK source checkout commit must identify the exact source used to build the APK and match its embedded `probeSourceCommit`. Record the adapter, procedure and APK source revisions separately. Do not copy the planning baseline into an artifact built from a later checkout.

For an identity-only preliminary attempt, complete items 1–3 for the exact adapter and procedure. Mark items 4–7 not applicable because the attempt builds, signs and uses no APK.

## 2. Target identity

1. Private target serial or owner-controlled alias: `OWNER ENTRY REQUIRED`
2. Android build fingerprint, API level, ABI and OEM identity: `OWNER ENTRY REQUIRED` for physical B1. For an identity-only preliminary attempt, record the fingerprint as `UNOBSERVED OUTPUT AT AUTHORIZATION`; no expected value is supplied. Mark API level, ABI and OEM identity out of scope because the approved commands do not read them.
3. Method and evidence reference used to confirm the target: `OWNER ENTRY REQUIRED`. For a preliminary attempt, reference its approved command procedure and record the observed fingerprint later in a separate private outcome record.

Store the serial and any identifying evidence privately. Shared records should use an opaque reference.

## 3. Command and effect allowlist

Copy each approved command and effect into the final procedure. Mark each row approved or excluded; an unmarked row grants no authority.

| Candidate operation | Owner decision and exact bound values |
|---|---|
| `adb -s <serial> get-state` | `OWNER ENTRY REQUIRED` |
| `adb -s <serial> shell getprop ro.build.fingerprint` | `OWNER ENTRY REQUIRED` |
| `adb -s <serial> forward --list` | `OWNER ENTRY REQUIRED` |
| `adb -s <serial> forward --no-rebind tcp:<port> localabstract:<name>` | `OWNER ENTRY REQUIRED` |
| `adb -s <serial> forward --remove tcp:<port>` | `OWNER ENTRY REQUIRED` |
| Loopback connection and exact Readiness request sequence | `OWNER ENTRY REQUIRED` |
| Build-specific OS command and reviewed Q7 parser profile, if required | `OWNER ENTRY REQUIRED` |

The command forms above describe the host adapter boundary; listing them does not approve execution. The final packet must name every permitted command, argument, effect, expected observation and restoration step. The adapter exposes no generic shell, automatic retry, alternate target, dynamic port or package-management command. Any additional operation requires separate owner approval and independent review.

For an identity-only preliminary attempt, approve only these two rows and exclude every other command or effect with a reason. Permit at most one invocation of each command. Run the fingerprint command only if `get-state` returns exactly `device`; otherwise mark it `NOT_RUN`. Both commands share one five-second host-monotonic deadline. Do not enumerate devices, retry, use a fallback, or add another shell operation.

## 4. Session and UID controls

1. Owner-approved start and expiry: `OWNER ENTRY REQUIRED`
2. Session maximum: 600 seconds
3. Maximum phase and Readiness request: five seconds each
4. Discovery admission window: five seconds
5. Socket release allowance: one second
6. Separate forward-cleanup reserve: 60 seconds after session expiry; it grants cleanup only
7. Exact discovery attempt, endpoint and connection-count evidence: `OWNER ENTRY REQUIRED`
8. Independently observed peer UID and owner confirmation record: `OWNER ENTRY REQUIRED`

Specify the host and Android clocks separately. Do not derive one clock from the other. No deadline may extend session, connection, observation or UID-approval authority. Automatic retry is prohibited.

For an identity-only preliminary attempt, item 1 must still state the approved execution window. Mark items 2–8 not applicable because the attempt creates no qualification session, phase, discovery connection, Readiness request, forward or UID observation.

## 5. OS evidence and Q7 profile

1. Exact target build and evidence source: `OWNER ENTRY REQUIRED`
2. Reviewed parser profile name, revision and digest: `OWNER ENTRY REQUIRED`
3. Exact command, output bounds, timeout and completion marker: `OWNER ENTRY REQUIRED`
4. Sanitized evidence reference and acquisition intervals: `OWNER ENTRY REQUIRED`

If Q7 evidence is needed, bind its parser to the exact Android/OEM build and review the complete output contract before use. A `dumpsys` command is not authorized by this template.

For an identity-only preliminary attempt, mark items 1–4 not applicable because it collects no OS diagnostics or Q7 evidence. Record the observed target/build identity under section 2 in the separate private outcome record.

## 6. Evidence handling

1. Owner-private evidence location: `OWNER ENTRY REQUIRED`
2. Retention end date and deletion owner: `OWNER ENTRY REQUIRED`
3. Publication destination and approved sanitized fields: `OWNER ENTRY REQUIRED`
4. Evidence integrity references: `OWNER ENTRY REQUIRED`

Do not publish serials, build fingerprints, raw command output, stderr, screenshots, unrelated application names or local paths.

For an identity-only preliminary attempt, bind the private outcome record to the approved packet digest and the reviewed adapter-source and procedure digests. Record the attempt's host-monotonic start and finish readings, command counts, final classification, and whether the conditional fingerprint command was not run. Keep the target serial and any observed fingerprint in that private record. Retain its digest as the evidence integrity reference; do not retain or hash raw command output or stderr. Shared records may contain only an opaque target reference and sanitized status.

## 7. Restoration plan

1. Package, task and process state to record before the attempt: `OWNER ENTRY REQUIRED`
2. Forward tuple and proof of absence before creation: `OWNER ENTRY REQUIRED`
3. Exact package, task and forward restoration actions: `OWNER ENTRY REQUIRED`
4. Readback required to confirm each restoration: `OWNER ENTRY REQUIRED`
5. Recovery owner and escalation route for unresolved obligations: `OWNER ENTRY REQUIRED`

Record each restoration obligation before mutation. Never adopt a pre-existing forward. An uncertain create, ownership check or removal leaves the attempt blocked until separately authorized recovery proves the exact state.

For an identity-only preliminary attempt, mark package, task and process baselines as not observed and out of scope. Mark restoration as not applicable because both approved commands are read-only and this attempt makes no device-state change. Do not authorize cleanup as part of this attempt.

## 8. Independent review and owner authorization

1. Independent pre-device reviewer and review date: `OWNER ENTRY REQUIRED`
2. Reviewed packet digest and applicable source, adapter, procedure and (for physical B1) APK identities: `OWNER ENTRY REQUIRED`
3. Review findings and disposition: `OWNER ENTRY REQUIRED`
4. Owner identity and explicit approved operations: `OWNER ENTRY REQUIRED`
5. Authorization time window and approval reference: `OWNER ENTRY REQUIRED`

Proceed only after every required field is complete. Mark inapplicable items as not used and record the reason. The reviewer must approve the exact packet digest, and the owner must authorize each listed operation. Any changed source, target, command or procedure requires a new review and approval. For physical B1, a changed APK or signer also requires new review and approval. Until then, B1 stays NOT_RUN and Issue #74 stays open.

For an identity-only preliminary attempt, mark the APK identity in item 2 not applicable because no APK is used. Complete the packet digest and applicable source/adapter/procedure identity review before owner approval.

## 9. Attempt scope and preliminary observation admission

1. Attempt kind: `OWNER ENTRY REQUIRED`. Use the packet label `PRELIMINARY_IDENTITY_ONLY` only for this attempt record; do not add it as a runtime or persisted protocol value.
2. Exact purpose and facts: identify the owner-selected target and read its build fingerprint; maximum command count is two, with the second command conditional on the first.
3. Private target reference and serial: `OWNER ENTRY REQUIRED`. The build fingerprint is an unobserved command output at authorization time, not an approved input value.
4. Adapter source commit and state digest: `OWNER ENTRY REQUIRED`. Procedure revision and digest: `OWNER ENTRY REQUIRED`.
5. Exact command vectors, start/expiry, one shared five-second host-monotonic deadline and no-retry rule: `OWNER ENTRY REQUIRED`.
6. Evidence storage, retained private fields, publication restrictions, retention end date and deletion owner: `OWNER ENTRY REQUIRED`.
7. Baseline declaration: read-only observation with no device mutation; restoration is not applicable for this attempt, with this reason recorded.
8. Mark the following fields not applicable, each with the reason that this attempt does not read or change application state: APK and signer; Android user, package, component, task and process state; UID; forwarding and Readiness; OS diagnostics and Q7 profile.
9. Independent review of the completed packet digest, reviewer and date: `OWNER ENTRY REQUIRED`.
10. Explicit owner approval of this exact attempt, target and two-command conditional allowlist, including the approved execution window: `OWNER ENTRY REQUIRED`.

A preliminary observation authorizes only its enumerated scope. It grants no physical B1 authority or implicit install, launch, forwarding, UID discovery/enrollment, reset or cleanup permission. Mark unused B1 fields and command rows explicitly excluded with reasons. If an observation needs setup or restoration effects, name and approve each effect before execution. Historical Issue #28 target authorization does not authorize either attempt kind.

For Q7 evidence collection, review a safe filter and reliable completion contract before collection. Preserve the runbook's exact Q7 command restriction, 1 MiB total and 16 KiB line limits, three-second device timeout and five-second host deadline. These Q7 controls do not apply to an identity-only preliminary attempt, which is limited to the two commands in sections 3 and 9 and collects no diagnostics. For either attempt, do not retain raw command output or stderr, use fallback commands, retry automatically, or publish partial facts. Missing, inconsistent, ambiguous, truncated, stale or unsupported evidence blocks the applicable observation.

The existing parser cannot establish the complete physical OS fact set. Its fixtures are not target evidence. Target selection, a completed preliminary packet or a successful preliminary observation does not qualify that parser or satisfy B1. Any later parser/acquisition implementation requires a separately approved concrete plan. Physical B1 additionally requires the exact reviewed probe artifact and signer, complete B1 packet, independent review and explicit owner authorization.
