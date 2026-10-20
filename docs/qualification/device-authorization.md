# Owner-authorized device admission

This guide describes the private authorization contract and the current limits
of Android qualification admission. It does not add a public live-execution
command or a live device transport. The public `--dry-run` and `--preflight`
commands remain host-only, and an unflagged live request remains blocked with
`LIVE_ADMISSION_NOT_IMPLEMENTED`.

## Current evidence boundary

The qualification package provides an injected interface for read-only fresh
admission and a typed permission-operation boundary. Tests use synthetic
observations and in-memory transports. A test that returns `ADMITTED` proves
only that the supplied synthetic values satisfy the admission checks; it is
not evidence about an Android device.

No-reset admission returns `BLOCKED` because the repository has no independent
observer for comparing the Library fixture membership, relevant job states,
and pending cleanup with the owner-approved baseline. The authorization may
carry that baseline, but it is not compared with fabricated observations or
read from application storage. Fresh admission reports an absent qualification
installation separately from a present but incompatible installation. Both
conditions block this slice because installation and reset operations are not
enabled.

Host APK inspection supplies the exact APK digest, package and version facts,
declared permissions, signature-inspector results, and the source revision
value found in the embedded build record. The embedded revision value is a
claim carried by the APK; this interface does not independently prove source
provenance. Host inspection does not prove which binary is installed on a
device, the installed signer, foreground identity, device identity, or
no-reset contents.

## Private authorization and approval

The owner provisions two separate JSON files for each session:

1. The authorization document identifies the owner, target, qualification
   application, artifact, plan, fixture-manifest digest, state mode, typed
   operations, remediation, reserves, and deadlines.
2. The owner-private approval sidecar binds the exact canonical authorization
   digest and owner identity to a validity window.

The authorization uses schema version `1` and has these fields:

| Field | Contents |
|---|---|
| `authorization_id`, `owner_identity` | Session identifier and owner identity string |
| `issued_at_utc`, `session_deadline_utc`, `cleanup_deadline_utc` | UTC issuance, qualification, and separate cleanup limits |
| `target` | Private serial, alias, opaque reference, minimum Android API, ABI, and required capabilities |
| `application` | The isolated package `com.argusromtoolkit.argus.qualification` |
| `artifact` | APK SHA-256, certificate SHA-256, embedded source revision, version code, and declared permissions |
| `plan` | Plan and rules digests plus scenario identifiers |
| `fixture_manifest_sha256` | Digest of the separately maintained private fixture manifest |
| `state` | `fresh` or `no-reset`, inherited session identifier, and optional no-reset baseline |
| `operations` | Exact typed operation records and the nested permission restoration authorization |
| `approved_remediation` | Empty without the permission operation; otherwise exactly `restore_permission_snapshot` |
| `reserves` | Minimum free storage and cleanup-time reserve |

The approval sidecar has exactly `schema_version`, `authorization_sha256`,
`owner_identity`, `valid_from_utc`, and `valid_until_utc`. The digest is
SHA-256 of the authorization JSON encoded as UTF-8 with sorted keys, compact
separators, and non-ASCII characters preserved. The parser rejects duplicate
keys, unknown fields, floating-point numbers, non-finite values, malformed
types, and unsupported schema versions. Approval starts at `valid_from_utc`
and expires at `valid_until_utc`; its window must fit within the authorized
session.

The implementation reads both files and never creates an authorization or
approval. The digest binds the supplied documents together. It does not
authenticate the owner or verify a digital signature. Keep both files and all
device, owner, and fixture identifiers in owner-private storage. Inputs must
be regular, non-symlink files no larger than 64 KiB. On POSIX they must belong
to the current user and have no group or other permissions. Errors omit paths
and input values. Do not copy private identifiers into shared logs or results.

## Operation authorization

The typed operation vocabulary can represent read-only work, permission
app-ops, reset, reinstall, launch, force-stop, navigation, refresh, fixture
staging, shell, and path mutation. Only the reversible
`MANAGE_EXTERNAL_STORAGE` permission/app-op transition is enabled. It must
name the qualification package, the exact target, the expected prior state,
and the desired `allowed` or `denied` state. The permission must appear in the
pinned artifact's declared permission list. Unknown categories are rejected;
known unsupported categories are denied before a transport mutation call.

Before changing the permission, the injected transport rechecks the target,
foreground package, and installed qualification package identity. It captures
a typed snapshot with two independent parts: effective access and the stored
app-op mode with whether a package override is present. An unset `default`
mode and an explicit `allow` override can both produce effective access, but
they are different stored configurations and must be restored differently.
Missing, unsupported, or ambiguous fields block execution before the setter.

The setter accepts only an explicit `allow` or `deny` configuration for
`MANAGE_EXTERNAL_STORAGE`. Before calling it, the executor durably records the
exact original snapshot and restoration obligation in owner-private state. It
then performs at most one approved mutation and reads the typed state back.
The session enters a trusted qualification phase explicitly before this
mutation can run; the plan's phase string alone is insufficient. A no-op
request completes without a setter call. After a mutation starts, the session
allows restoration only.

The nested restoration record names a distinct operation identifier, the same
target, qualification package, and permission, plus a separate deadline and
timeout. Its deadline must be after the qualification deadline and no later
than the authorized cleanup deadline. The timeout must fit both the cleanup
reserve and time remaining. After interruption or qualification expiry, the
executor permits only this restoration of the captured snapshot. A setter
failure, interruption, or uncertain result triggers one automatic attempt
within the approved cleanup window. The executor rechecks target and installed
package identity, reads the current state, writes the original stored
configuration at most once when needed, and independently verifies the exact
effective and stored state. `PERMISSION_RESTORED` is returned only after that
verification succeeds. A successful mutation keeps its approved interval
available for the qualification step before explicit restoration. The
executor does not retry the product mutation, extend a deadline, or resume a
terminal session.

The pending obligation is stored atomically in
`~/.argus-rom-toolkit/device-restoration.json`, in an owner-only directory and
file protected by a separate owner-only lock. It includes the private target
serial and remains private; diagnostics and shared results do not include
device identity. Missing, corrupt, unsafe, or unwritable safety state blocks
admission or mutation. An unresolved record blocks every new admission for
that target, including a session with a new approval. Failed or unverifiable
cleanup leaves the record in place across process restarts. Clearing it
requires an explicit recovery call using the original loaded authorization
and owner approval, followed by an independent exact-state readback. Recovery
cannot run a product operation or resume the prior session. The local record
does not authenticate its owner or provide a cryptographic tamper-proof
guarantee.

Reset or clear-data, reinstall, launch, force-stop, navigation or refresh,
fixture staging, arbitrary shell or path changes, ordinary-app operations,
and scenario behavior are not enabled by this slice. The broader typed
authorization vocabulary does not grant those actions.

## Safe validation

Run `just test-android-qualification` for the simulated qualification tests.
They use synthetic owner inputs and fake transports only. The test recipe also
uses a poisoned command shim to detect accidental device-command invocation.
There is no device adapter that independently observes the stored app-op
configuration, so these guarantees are tested only with host-side fakes and do
not establish physical restoration. The public `--dry-run` and `--preflight`
commands remain host-only and unflagged live requests remain
`LIVE_ADMISSION_NOT_IMPLEMENTED`. Their result meanings are documented in
[Android qualification operations](README.md).

## One-use session state

Admission atomically records both the authorization's opaque session
identifier (`authorization_id`) and canonical digest (`authorization_sha256`)
before it requests device observations. Each registry session entry stores
both fields; the registry does not persist owner names, device identifiers,
or credential data. The default
registry is `~/.argus-rom-toolkit/session-registry.json`, protected by an
owner-only directory and file, with a separate owner-only lock file. Updates
use an exclusive lock and an atomic file replacement so concurrent processes
cannot admit the same authorization.

Admission fails closed before transport access if the directory or files are
unsafe, linked, malformed, or unavailable. The digest remains consumed across
process restarts and terminal outcomes. Do not remove or replace the registry
to resume a session; any recovery requires owner intervention. This local
state prevents accidental reuse but does not authenticate an owner or provide
a cryptographic tamper-proof guarantee.

## Restoration approval after process restart

The normal approval loader rejects an expired approval. A separate
restoration-only loader can reopen the original owner-private sidecar while
the pending record's restoration deadline and the authorization's independent
cleanup deadline still leave enough time for the complete restoration call.
It checks the original owner identity and canonical authorization digest, the
sidecar's private-file protections, exact path and file identities, and the
sidecar's original byte digest. The pending record must also match the same
authorization, target, permission operation, restoration operation, and hash
of the exact typed permission snapshot.

This approval is accepted only by pending-restoration recovery. It cannot
admit a session, resume a terminal session, or authorize a product mutation.
A new qualification approval does not prove recovery authority. Recovery
rechecks target and installed-package identity, then reads the effective
access and stored app-op configuration. It emits `PERMISSION_RESTORED` and
clears the pending record only after both values exactly match the snapshot.

The executor makes one automatic restoration attempt after an uncertain
product mutation and does not retry it automatically. A manual recovery call
is separate and explicit. Before its restoration setter, the owner-private
record atomically marks that setter as consumed. Later calls using that
obligation may verify and clear an already-restored snapshot, but cannot call
the setter again. If verification still fails, the durable blocker remains;
this schema does not provision a replacement recovery authorization. No
deadline is extended and no product mutation is repeated. These guarantees
are exercised with synthetic transports only; the repository has no device
interface that proves exact physical stored-state restoration.
