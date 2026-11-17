# Issue #74 B1 authorization packet proposal

**Status: unpopulated proposal. This file is not an authorization. Physical B1 remains NOT_RUN.**

Prepare one copy for each proposed B1 attempt. Keep serials, owner identity, signatures and raw evidence in owner-private storage. Complete every required field and obtain independent pre-device review before the owner authorizes any operation. This template grants no device access or command authority.

## 1. Candidate source and artifact

1. Host adapter repository and exact source commit: `OWNER ENTRY REQUIRED`
2. Adapter source tree state and digest: `OWNER ENTRY REQUIRED`
3. B1 procedure path, revision and digest: `OWNER ENTRY REQUIRED`
4. APK source checkout commit: `OWNER ENTRY REQUIRED`
5. Embedded `probeSourceCommit`: `OWNER ENTRY REQUIRED`
6. APK SHA-256 and signer certificate SHA-256: `OWNER ENTRY REQUIRED`
7. Build workflow, run identifier and provenance record: `OWNER ENTRY REQUIRED`

The APK source checkout commit must identify the exact source used to build the APK and match its embedded `probeSourceCommit`. Record the adapter, procedure and APK source revisions separately. Do not copy the planning baseline into an artifact built from a later checkout.

## 2. Target identity

1. Private target serial or owner-controlled alias: `OWNER ENTRY REQUIRED`
2. Android build fingerprint, API level, ABI and OEM identity: `OWNER ENTRY REQUIRED`
3. Method and evidence reference used to confirm the target: `OWNER ENTRY REQUIRED`

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

## 5. OS evidence and Q7 profile

1. Exact target build and evidence source: `OWNER ENTRY REQUIRED`
2. Reviewed parser profile name, revision and digest: `OWNER ENTRY REQUIRED`
3. Exact command, output bounds, timeout and completion marker: `OWNER ENTRY REQUIRED`
4. Sanitized evidence reference and acquisition intervals: `OWNER ENTRY REQUIRED`

If Q7 evidence is needed, bind its parser to the exact Android/OEM build and review the complete output contract before use. A `dumpsys` command is not authorized by this template.

## 6. Evidence handling

1. Owner-private evidence location: `OWNER ENTRY REQUIRED`
2. Retention end date and deletion owner: `OWNER ENTRY REQUIRED`
3. Publication destination and approved sanitized fields: `OWNER ENTRY REQUIRED`
4. Evidence integrity references: `OWNER ENTRY REQUIRED`

Do not publish serials, build fingerprints, raw command output, stderr, screenshots, unrelated application names or local paths.

## 7. Restoration plan

1. Package, task and process state to record before the attempt: `OWNER ENTRY REQUIRED`
2. Forward tuple and proof of absence before creation: `OWNER ENTRY REQUIRED`
3. Exact package, task and forward restoration actions: `OWNER ENTRY REQUIRED`
4. Readback required to confirm each restoration: `OWNER ENTRY REQUIRED`
5. Recovery owner and escalation route for unresolved obligations: `OWNER ENTRY REQUIRED`

Record each restoration obligation before mutation. Never adopt a pre-existing forward. An uncertain create, ownership check or removal leaves the attempt blocked until separately authorized recovery proves the exact state.

## 8. Independent review and owner authorization

1. Independent pre-device reviewer and review date: `OWNER ENTRY REQUIRED`
2. Reviewed packet digest and source, adapter, procedure and APK identities: `OWNER ENTRY REQUIRED`
3. Review findings and disposition: `OWNER ENTRY REQUIRED`
4. Owner identity and explicit approved operations: `OWNER ENTRY REQUIRED`
5. Authorization time window and approval reference: `OWNER ENTRY REQUIRED`

Proceed only after every required field is complete. Mark inapplicable items as not used and record the reason. The reviewer must approve the exact packet digest, and the owner must authorize each listed operation. Any changed source, APK, signer, target, command or procedure requires a new review and approval. Until then, B1 stays NOT_RUN and Issue #74 stays open.
