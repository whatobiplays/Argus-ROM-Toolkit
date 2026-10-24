# Durable qualification evidence and owner verdicts

This document defines the host-only storage contract for qualification
execution records and explicit owner verdicts. It describes a library boundary;
it does not start a qualification run, contact Android or a device, launch ADB,
or decide release readiness.

The implementation is split across three modules:

- scripts/android_qualification/evidence.py contains the public facade,
  dataclasses, enums, and stable error codes.
- scripts/android_qualification/_evidence_storage.py owns execution records,
  chain verification, publication, manifests, and recovery.
- scripts/android_qualification/_evidence_review.py owns owner verdicts and
  deterministic review-packet projection.

## Store and capabilities

Create a store with an optional private root:

    from pathlib import Path

    from scripts.android_qualification.evidence import EvidenceStore

    store = EvidenceStore(Path("/an/owner/private/evidence-root"))
    writer = store.execution_writer()
    reviewer = store.owner_reviewer("owner-0123456789abcdef0123456789abcdef")

The default root is
~/.argus-rom-toolkit/qualification-evidence. The root and every created
directory must be owned by the effective user and have mode 0700. Regular files
must be owned by the effective user, have mode 0600, and have one hard link.
Symbolic links, changed directory/file identities, and unexpected entries fail
closed.

The returned capabilities enforce workflow separation:

- ExecutionWriter has no verdict method. It can open a session, append an
  assertion, lifecycle event, or terminal event, inspect a verified snapshot,
  verify a finalized execution, and recover it.
- OwnerReviewer has no execution-event method. It can append an explicit
  verdict, return the latest verdict for a scenario, and generate a review
  packet from finalized evidence.

This separation prevents routine execution code from calling a verdict as part
of a normal append path. It is an API and control-flow boundary. It is not
human authentication and cannot protect against arbitrary code running as the
same operating-system user.

## Pinned session provenance

ExecutionWriter.open_session(spec, WriteRequest(...)) requires a SessionSpec
containing:

- A 32-character lowercase hexadecimal session_id.
- A stable opaque scenario_id.
- An ArtifactPin: opaque artifact reference, 64-character lowercase SHA-256,
  and artifact class (qualification_variant or distributable_release).
- An AuthorizationPin: authorization-manifest version and SHA-256.
- A FixturePin: fixture-manifest version, SHA-256, and opaque corpus reference.
- A PlanPin: qualification-plan reference, version, and SHA-256.
- An AcceptanceRulesPin: rule reference, exact semantic version string (for
  example, `1.0.0`), and SHA-256. The acceptance-rule version remains a string
  in records, assertions, verdicts, and manifests so its original spelling is
  preserved. It is independent of the integer evidence schema version.
- An EnvironmentPin: Android or macOS, opaque platform-version token,
  environment reference, and opaque target reference.
- ReviewRequirements: required evidence-reference aliases and booleans for
  objective review, direct owner observation, and retrospective review.

References use field-specific typed opaque aliases. Every suffix is exactly 32
lowercase hexadecimal characters:

- `scenario-<32 hex>`
- `artifact-<32 hex>`
- `corpus-<32 hex>`
- `plan-<32 hex>`
- `rules-<32 hex>`
- `environment-<32 hex>`
- `platform-version-<32 hex>`
- `target-<32 hex>`
- `evidence-<32 hex>`
- `assertion-<32 hex>`
- `measurement-<32 hex>`
- `owner-<32 hex>`

The evidence-store API enforces these formats when accepting a write and again
when loading hash-verified bytes. Enforcement belongs to the store, so callers
cannot bypass it by constructing dataclasses directly. The API rejects path
separators, URLs, whitespace, control characters, credential-like tokens,
device-serial markers, generic slugs, and raw hashes. Private ROM identities or
hashes, screenshots, logs, paths, credentials, and other arbitrary payloads
therefore cannot be written to an execution or verdict record. A review packet
verifies its complete record chain before projection, so the same checks
prevent such values from being emitted in packet bytes.

The session-opened record is sequence 1 and contains the complete pin. Later
assertions must match the pinned rule reference, version, and digest. Loading
an execution chain repeats this cross-record rule check, so a hash-valid but
inconsistent assertion is rejected as corrupt. Owner verdicts must match the
pinned artifact and rule identities from the verified execution manifest.

## Canonical records

Every persisted document is compact UTF-8 JSON with sorted keys, no
insignificant whitespace, no floating-point numbers, and no non-finite
constants. Decoding rejects duplicate keys, unknown fields, missing fields,
invalid types, values outside bounds, unsupported schema versions,
noncanonical byte encodings, and oversized documents.

Each execution record has this envelope:

    {
      "schema_version": 1,
      "session_id": "32 lowercase hex characters",
      "sequence": 1,
      "previous_record_sha256": null,
      "event": {},
      "event_sha256": "64 lowercase hex characters",
      "record_sha256": "64 lowercase hex characters"
    }

event_sha256 is the SHA-256 of the canonical event bytes. record_sha256 is the
SHA-256 of the canonical envelope with the record_sha256 field omitted. The
first record has no previous digest; each later record binds the preceding
record digest.

The supported event variants are deliberately narrow:

- session_opened contains the scenario and complete provenance pin.
- assertion contains an assertion reference, pinned rule identity, expected
  and actual outcomes, observed time, bounded evidence references, and zero to
  32 integer measurements. Each measurement has a typed opaque name, one declared
  unit from count, bytes, milliseconds, seconds, or
  device_independent_pixels, and an integer value. Floating-point measurements
  are rejected.
- lifecycle contains one of preparation_started, preparation_completed,
  execution_started, cleanup_started, or cleanup_completed, plus bounded
  evidence references.
- terminal contains completed, failed, blocked, or interrupted, a bounded
  reason code, end time, and bounded evidence references. It must be the last
  execution record.

Timestamps are UTC YYYY-MM-DDTHH:MM:SSZ. Observed and end times identify the
observation boundary; the append time identifies when the record was written.

Assertion outcomes are passed, failed, blocked, or not_run. These are
machine-observation values. They never create an owner verdict.

## Publication and idempotency

Every execution event is written with this sequence:

1. Open the evidence root without following its final component, then traverse
   every root, `executions`, session, owner-verdict, and record-directory
   component relative to its already verified parent. Each step uses
   `O_DIRECTORY | O_NOFOLLOW` and verifies that the opened device and inode
   match the named directory. Every directory created or used below the root
   must be owned by the effective user and have exact mode 0700. The store
   creates missing components one at a time and synchronizes each new parent
   entry before descending. A platform may canonicalize symbolic links in
   components above the evidence root to accommodate paths such as a
   temporary-directory alias. The evidence root itself and every component
   below it are opened without following symbolic links.
2. Create a uniquely named same-directory temporary file with mode 0600.
3. Write and flush the canonical bytes, then synchronize the file.
4. Verify the open and named file identities.
5. Publish the record with an atomic no-replace primitive.
6. Synchronize the parent directory.
7. Return an acknowledgement receipt.

Non-contention lock, temporary-file open/write/sync, post-publication stat,
and other filesystem failures return bounded stable evidence errors. Raw
operating-system messages and absolute paths are not exposed. Lock contention
continues to return `EVIDENCE_STREAM_BUSY`.

The final no-replace operation is the conflict authority. A preliminary
path-existence check is not authority. macOS uses
renameatx_np(RENAME_EXCL) and Linux uses renameat2(RENAME_NOREPLACE).
Unsupported platforms fail closed.

Writers use a per-session cooperating-writer file lock. Separate sessions do
not share a global lock. A lock conflict returns the stable
EVIDENCE_STREAM_BUSY error for an append. Recovery returns a BUSY
RecoveryResult and makes no change while another cooperating writer holds the
session lock.

Callers provide an `operation-<32 hex>` ID on every write. A retry compares the
canonical event content, ignoring only append-time occurrence, with the
published event carrying that operation ID. An exact retry first completes the
required directory synchronization, then returns the original receipt and
digest with idempotent=True. Reusing an operation ID with changed content
returns EVIDENCE_OPERATION_CONFLICT. A caller-provided expected head must equal
the current chain head before a new append; otherwise the store returns
EVIDENCE_EXPECTED_HEAD_CONFLICT. IDs beginning with `internal-` are reserved
for store-generated recovery events and are rejected from public requests.
Read validation also accepts an internal operation ID only on the exact
recovery interruption event; hash-recomputed ordinary events cannot enter that
namespace.

Temporary sidecars are never promoted merely because a final pathname is
missing. An unproven sidecar is retained. A temporary file's absence is not
evidence that a session is idle or abandoned.

An idempotent replay reconstructs its receipt from the record carrying the
requested operation ID. The replay head is that record's own digest, even when
later operations have advanced the current chain head.

## Finalized manifests

append_terminal(...) first publishes the terminal record and then publishes
manifest.json with the same no-replace and parent-sync rules. The manifest
contains:

    {
      "schema_version": 1,
      "session_id": "32 lowercase hex characters",
      "scenario_id": "opaque scenario alias",
      "provenance": {},
      "record_count": 3,
      "head_sha256": "terminal record digest",
      "terminal_sequence": 3,
      "terminal_record_sha256": "terminal record digest",
      "manifest_sha256": "self digest excluding this field"
    }

The manifest is immutable. verify_execution(session_id) verifies the contiguous
sequence, every self and previous digest, the exact final terminal event, the
manifest self digest, and every manifest field against the chain. A finalized
execution rejects further execution events with EVIDENCE_ALREADY_FINALIZED.

If a process loses an acknowledgement after record or session publication,
retrying the same operation synchronizes the containing directory before
returning the published receipt without adding a duplicate. If the terminal
record is durable and the manifest is missing or interrupted, recovery verifies
the terminal event and finalizes the manifest. A retry that finds an already
published manifest verifies its exact binding and synchronizes the session
directory before acknowledging it. The durable terminal event takes precedence
over manifest absence.

## Recovery

recover(session_id, abandoned_before=timestamp) verifies the chain before
making a decision:

- A finalized chain returns FINALIZED; a missing manifest is recreated only
  after verification.
- An active cooperating writer returns BUSY with no change.
- With no abandonment cutoff, an unterminated session returns INCOMPLETE and is
  not changed.
- With a cutoff earlier than the last record time, recovery returns INCOMPLETE.
- With an explicit cutoff at or after the last record time, recovery appends
  one terminal interrupted / recovery_abandoned event and finalizes the
  manifest.

Before appending an interruption, recovery checks for an existing manifest.
Only ENOENT means that no manifest entry exists. A permission denial or other
I/O failure, including a failure while reading or restating the opened file, is
uncertain, not absence. It maps to EVIDENCE_UNAVAILABLE and fails closed before
the chain is changed. A readable manifest that conflicts with an open record
chain raises EVIDENCE_MANIFEST_MISMATCH. Both failures leave the record count
and record bytes unchanged.

A caller sets abandoned_before only after establishing that execution is
genuinely abandoned. The lock being free is not proof. Recovery never resumes a
session, rewrites a record, promotes a sidecar, or turns an automated result
into an owner PASS. A recovered session remains permanently terminated.

## Owner verdicts

The owner-review stream is separate from execution records and is also
append-only. OwnerReviewer.record_verdict(...) requires:

- Exact manifest SHA-256, selected record sequence/digest pairs, artifact
  reference/digest, rule reference/version/digest, verdict, basis, sufficiency,
  retrospective flag, direct-observation declaration, review time, and an
  operation ID.
- One verdict from PASS, FAIL, BLOCKED, or NOT_RUN.
- Basis objective_review or direct_owner_observation.
- Sufficiency sufficient or insufficient.

The manifest must verify and remain finalized. Selected records must exist at
their exact sequence and digest. Artifact and rule fields must equal the pinned
provenance. Objective review must be allowed by the session. Direct owner
observation must also be allowed and requires an explicit
direct_observation_declared=True; the record states that identity is
self_asserted and attendance authentication is not_provided. Retrospective
review is accepted only when the pinned review requirements allow it.

`direct_observation_declared` must be an exact boolean before any basis or
truthiness check. Objective review requires `False`; direct owner observation
requires `True`. Other false-valued or truth-valued objects fail with
`EVIDENCE_INVALID_INPUT` before publication.

An objective review requires sufficient sufficiency. It must select records
whose evidence references contain every pinned required evidence reference.
PASS also requires sufficient sufficiency. No code path converts terminal
completed or an automated passed assertion into an owner PASS.

An absent verdict is represented by no record. It is distinct from an explicit
NOT_RUN. BLOCKED records a pinned prerequisite or evidence obstruction; NOT_RUN
records that the owner did not run the observation. Neither value is inferred.

A correction supplies the current logical verdict digest in
supersedes_verdict_sha256 and appends a new record. Earlier verdict files stay
in place. Retrying an operation with identical canonical content returns its
original receipt after the owner-verdict directory is synchronized; changed
content under the same operation ID conflicts.

Every new verdict must have an `occurred_at` no earlier than the `occurred_at`
of the last persisted verdict; equal timestamps are permitted. This requirement
applies equally to caller-supplied times and writer-generated wall-clock times.
An idempotent retry is recognized first and returns its original receipt without
appending another verdict.

Reading the verdict chain repeats the binding checks used during publication.
It verifies the exact execution manifest and chain, artifact and rule identity,
selected record digests, required evidence references, sufficiency rules,
supersession relationships, enum types, and reference allow-list/privacy rules.
A hash-valid persisted record that fails one of these checks raises the stable
EVIDENCE_CORRUPT error.

The owner alias must use `owner-<32 hex>` and is a self-asserted review
attribute. A matching alias does not authenticate the human owner, prove
attendance, or establish cryptographic authorship. The capability split is a
workflow guard, not a security boundary between processes running as the same
operating-system user.

## Deterministic review packet

OwnerReviewer.review_packet(manifest_sha256) verifies a finalized execution,
revalidates every field-specific alias, and returns canonical bytes containing
the manifest and every verified record. The bytes contain:

- The packet schema version.
- The exact execution-manifest digest and manifest document.
- Each record's sequence, prior digest, self digest, and strictly allow-listed
  event.

There is no packet-generation timestamp. The same manifest and verified record
bytes therefore produce byte-identical packet bytes. The packet is not written
to the evidence root and is not a second authority. It contains only the
already-sanitized execution data.

## Integrity limits

Canonical SHA-256 chains detect accidental or detectable inconsistent records.
They do not establish cryptographic authorship, human identity, durable tamper
resistance against arbitrary same-user processes, or protection from an
attacker able to rewrite the complete local history. Detecting such rewrite
would require an external trust anchor outside this contract.

This storage layer does not perform device admission, execute product
scenarios, assess release readiness, or modify historical qualification
evidence.
