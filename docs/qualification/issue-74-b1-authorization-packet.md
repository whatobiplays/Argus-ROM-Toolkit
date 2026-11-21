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

The selected target is KONKR Pocket Advance; its exact build fingerprint is
still unverified. The serial stays private. Identity success establishes no
artifact, OS-parser, transport or B1 qualification. This attempt has no device
mutation or cleanup action.

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

## 4. Exploratory OS observations

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

## 5. Outcome and retention

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
