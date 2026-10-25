# Owner fixture preparation

This guide describes the private fixture contract used to prepare owner
supplied ROM copies for future isolated Android qualification. Preparation is
host only. It does not connect to Android, add a public command, populate the
product Library, run a product scan, or produce a qualification verdict.

The public host-only API is `scripts/android_qualification/fixture_staging.py`.
It is a small facade over private modules with separate responsibilities:
`_fixture_staging_model.py` defines shared values and results;
`_fixture_staging_manifest.py` validates pinned plans, manifests, and authority;
`_fixture_staging_content.py` validates source membership, content expectations,
and companion relationships; `_fixture_staging_transfer.py` streams and verifies
bytes under capacity and deadline checks; `_fixture_staging_destination.py`
manages destination paths, file writes, readback, and atomic publication;
`_fixture_staging_ownership.py` persists ownership records, proves tree identity,
and handles cleanup and recovery; and
`_fixture_staging_orchestration.py` coordinates host-only preparation and
explicitly authorized cleanup. Import the public API from the facade; these
private modules implement it.

The existing `--dry-run` and `--preflight` commands retain their host
validation meanings, and requests without either flag remain
`LIVE_ADMISSION_NOT_IMPLEMENTED`.

## Private inputs and authority

Keep the plan, fixture manifest, authorization, approval sidecar, and original
ROM files outside the repository. The authorization and approval sidecar must
be owner private and loaded through `manifest.load_authorization` and
`manifest.load_owner_approval`. Do not generate an approval from the fixture
manifest or from Argus observations.

The authorization pins canonical SHA-256 digests for the plan, its rules, and
the fixture manifest. The loaded approval is bound to the exact canonical
authorization digest and owner identity; the grant also retains the approval
sidecar's exact byte digest and rejects a changed sidecar. Plan and fixture
files are rechecked against their original bytes and file identities before
publication.

The grant is available only for the exact authorized operation whose category
is `fixture_staging`, phase is `admission`, target is the authorization's
target, and package is `com.argusromtoolkit.argus.qualification`. Authorization
and approval deadlines are checked. The grant is an in memory host-preparation
capability; it does not admit a device, consume the session's later single-use
admission authority, or enable any other typed operation.

## Plan and coverage

The version 1 plan is strict JSON. Duplicate keys, floating-point values,
unknown fields, duplicate identifiers, and unsupported versions are rejected.
Its required fields are `schema_version`, `rules`, `scenario_ids`,
`fixture_coverage`, and `host_reserve_bytes`. `destination_reserve_bytes` and
`cleanup_authorized` are optional. The latter defaults to `false`.

`fixture_coverage` contains `mode`, `required_fixture_ids`,
`selected_fixture_ids`, and `mandatory_fixture_ids`:

| Mode | Required selection |
|---|---|
| `mandatory_full_plan` | Selected IDs must equal the complete ordered required list. |
| `authorized_partial_plan` | Selected IDs must be a proper subset of the ordered required list; every mandatory ID must remain selected. |

The mode and selection are in the authorization-pinned plan. The fixture
manifest must repeat that mode and ordered selection exactly, and include one
expectation for every selected ID in the same order. A partial selection is
therefore explicit and digest bound; it cannot be inferred from a sample or
from whichever source files happen to be present.

## Fixture manifest

The version 1 fixture manifest is strict JSON with `schema_version`,
`plan_sha256`, `rules_sha256`, `coverage_mode`, `selected_fixture_ids`, and
`fixtures`. Each fixture has:

- `fixture_id`, `platform`, `representation`, `identity`, `group_id`, and
  nonnegative `order` values, reviewed and approved by the owner;
- a relative `entrypoint` and ordered `files` list. Each file pins its relative
  `path`, `role`, byte `size`, and lowercase SHA-256 digest;
- `companions`, an ordered list of `{ "source": "...", "target": "..." }`
  edges for descriptor-to-member references; and
- `identity_evidence`, which must be
  `owner_approved_expectation_match` for a staging grant.

Paths use relative POSIX syntax. Absolute paths, drive prefixes, backslashes,
empty or dot components, traversal, non-normalized Unicode, duplicate paths,
and case-fold collisions are rejected. The fixture's complete file list,
digests, sizes, roles, logical expectations, and companion graph are pinned by
the owner's approval of the exact manifest digest. For CUE and M3U/M3U8
descriptors, the host validator reads references and requires them to match
the complete declared graph. Cycles and unreachable declared members are
rejected while parsing the manifest, before a staging grant can be issued.
Dangling tracks and changed source descriptors block preparation. Files are
copied with their exact relative names and layout; descriptors are not
rewritten and archives are not extracted.

`owner_approved_expectation_match` means only that copied bytes match the
owner-approved manifest expectations. It is not an independently verified
game identity or an external oracle result. A separate pinned and verified
oracle record is not part of this contract. Header, filename, and structural
recognition are never treated as game identity. An expectation marked
`structural_only` remains distinguishable and is blocked from staging.

## Source and destination safety

Original files are opened read only through no-follow directory handles. The
host snapshots source file identity and metadata, then streams every byte with
a bounded buffer while computing SHA-256. It rejects changed files, symlinks,
hard links, unsafe directory components, unlisted files or directories, and
source/destination overlap. Each selected fixture source directory must match
the manifest's complete member list. The source modification timestamp and
relative layout are retained. Staged files are owner private (`0600`) and
directories are owner private (`0700`), even when original permissions are
broader.

The production interface has no caller-selectable destination. A
caller-supplied root exists only in the private synthetic mechanics used by
host tests. A future production backend must resolve a fixed protected
installation-owned anchor or identifier; no grant, plan, caller parameter, or
configuration flag may replace it. Production remains blocked until the
operating-system isolation backend exists and admits that namespace.

Capacity observation is also private to the synthetic transfer path. It
requires the exact owner-bound capability and a live grant before the host
filesystem is inspected. Public capacity observation always raises
`BLOCKED_UNSUPPORTED_EXCLUSIVITY`. The plan supplies the host reserve; the
destination reserve is the greater of the plan reserve and the existing
authorization's storage reserve. Missing or insufficient capacity blocks
before risking exhaustion.

There is no fixed per-ROM or aggregate fixture byte ceiling.

### Production namespace admission

Successful production staging requires kernel-enforced isolation between the
destination namespace and every writable source namespace. The supported host
does not currently install that boundary, so production admission always
raises `BLOCKED_UNSUPPORTED_EXCLUSIVITY`. The public `stage_fixtures` and
`cleanup_fixture_staging` entry points check that boundary before validating
the grant, converting or inspecting caller paths, reading destination or
ancestor state, invoking callbacks, observing capacity, reserving a session,
creating a lock or ownership state, creating a quarantine, or writing or
deleting bytes. A staging result from this boundary reports zero inspected
counts and an empty coverage mode because none of those caller-owned values
has been read. No production capability is issued, and no backend, configuration
flag, or caller parameter can enable production staging. Private synthetic
mechanics use a separate capability object retained by the synthetic adapter.
That capability is immutable and non-subclassable. Its owner object, timing
source, and exact `threading.Thread` object remain in a closure-held registry
keyed by the exact capability object, and the capability has no writable data
slots. The registry strongly retains the issuing thread object while the
capability exists, so a new thread that receives a recycled numeric thread
identifier is still rejected. Rewriting slots with `object.__setattr__`,
copying or reconstructing the object, use by a different owner, and use from
another live or replacement thread therefore fail before a lock, state write,
callback, or filesystem operation. These guarantees defend against normal
capability-object misuse within the trusted Python process. Arbitrary code
already able to rewrite the process's closure internals or monkeypatch its
authorization functions is outside that boundary. Production owners have no
capability issuer.

Directory device and inode checks detect replacement of paths that were already
inspected. They do not prove that a writable same-user process cannot move a
destination directory into a source tree. Private directories with mode
`0700`, advisory locks, pathname rechecks, and caller declarations are not
accepted as evidence of namespace isolation.

The regression suite exercises transfer, publication, ownership, cleanup, and
recovery mechanics through a private synthetic adapter. Results produced by
that adapter prove implementation mechanics only. They do not establish
production admissibility, game identity, or physical qualification.

### Timing evidence

The first staging attempt captures one immutable timing record. It contains
the operating system boot identity, the monotonic-clock value at the original
start, the trusted UTC start value used to translate authorization deadlines,
the fixture operation deadline, the staging authorization deadline, the
cleanup authorization deadline, and the start of the cleanup reserve interval.
Staging uses the earlier of the session deadline and approval validity for its
authorization deadline. Cleanup uses the authorization's cleanup deadline.

The original operation deadline is the sole end boundary for staging, cleanup,
and recovery. The cleanup reserve is an interval inside that same timeline,
ending at the operation deadline and starting no earlier than the operation
start. A reserve at least as long as the operation timeout therefore spans the
whole operation; it does not prevent staging. A shorter reserve identifies only
the final part of the original timeline. Cleanup and recovery remain available
through the original operation deadline, and the reserve does not create an
earlier cutoff or renew authority when either action starts or restarts.

Subsequent checks compare the current operating system boot identity and
monotonic clock with that persisted record. A process restart during the same
boot therefore continues the original timeline. Public staging and cleanup
derive current UTC time from the trusted authority clock and current
monotonic time from the operating system. The legacy `now` arguments remain
accepted for call compatibility, but caller timestamps cannot extend or
replace either clock. Public staging does not accept a monotonic-clock
override. Deterministic mechanics tests use private adapters and clocks;
those adapters do not change production authority. Host wall-clock changes do
not move the monotonic deadlines. Missing or malformed timing evidence, a
different boot identity, a monotonic clock that moved backward, an unavailable
clock, or an unreadable record blocks the operation. Expiry leaves any owned
data in place for explicit owner review; it does not convert a partial result
into an eligible fixture.

Clock acquisition and private synthetic clocks use integer nanoseconds through
`time.monotonic_ns()` and the internal timing interface. Persisted schema 1
already stores integer nanoseconds: previously written starts and deadlines
remain unchanged, including any rounding introduced by older float-based
writers. No existing record is regenerated or migrated.

On macOS, Python's monotonic clock uses `mach_absolute_time()` and excludes
system sleep. Linux `CLOCK_MONOTONIC` also excludes suspend. This differs from
Darwin's sleep-inclusive `CLOCK_MONOTONIC` and `mach_continuous_time()`. The
precision correction does not change those clock domains. UTC grant checks
remain independently required; a paused uptime budget alone does not prove
that elapsed real time remains authorized. A sleep-inclusive timing contract
requires separate approval and a new clock discriminator/version, without
reinterpreting retained records. The proposed boundary and that separate
decision are described in [Staging isolation feasibility](staging-isolation-feasibility.md).

### Ownership generations and publication

Each run reserves a unique 32-character session identifier and writes state
under the private `.fixture-staging-state` directory. The initial record is
`.fixture-staging-state/<session>.00000000.json`. State changes create the next
eight-digit immutable generation, bind it to the previous generation's exact
byte digest, and add a self-digest covering every record field. The ownership
token remains part of the immutable record. The complete contiguous generation
chain is verified before use. Generation
files, the quarantine owner marker, and the final fixture root are published
with exclusive no-replace operations after their temporary contents have been
written and synchronized. A state generation therefore either appears complete
at its authoritative pathname or does not appear there at all; an interrupt can
leave a private temporary sidecar but cannot create a partial authoritative
record. The `recovery_state_path(session_id)` owner reader returns the highest
recorded generation pathname, or generation zero when no record exists. Loading
that record still performs full chain and timing verification.

Versioned records are the current contract. A lone legacy
`<session>.json` record is still recognized by owner inspection and recovery
reporting, but it has no versioned continuity proof or trusted original timing.
It is not silently upgraded or treated as sufficient authority for destructive
cleanup. A session containing both a legacy record and versioned generations is
ambiguous and fails closed.

Every staged file is independently read back in full and checked against the
pinned size and digest; preserved timestamps and companion relationships are
checked before the temporary root is renamed. Publication requires the exact
expected file set to be recorded as verified and the quarantine tree to match
its ownership ledger. The verified quarantine directory is held open and its
device/inode identity is pinned in state.

Before the rename, the record durably changes to `publication_pending` and
stores a bounded publication intent containing the exact temporary name, final
name, device, and inode. The state generation is complete before the no-replace
rename begins. A crash after this write but before the rename therefore leaves
the durable intent plus only the temporary entry. A crash after the atomic
rename but before confirmation leaves the same intent plus only the final entry.
Neither state is eligible. Recovery reports the pending publication as blocked
and retains a positive ownership result when the pinned intent and tree agree.
An intent with both entry names present, neither entry present, or a mismatched
identity remains ownership-unproven and is not eligible.

The final rename uses directory descriptors and does not replace an existing
entry. Immediately afterward the authoritative final entry must resolve to the
same open directory object; the owner marker, exact tree membership, every
published byte, and every preserved timestamp are checked again. Only a later
confirmation step, with the temporary entry absent and authorization still
valid, changes the durable state to `published`.

If a same-user process replaces the quarantine entry after verification, the
replacement may be the object moved to the final-looking pathname. The
post-rename identity check detects that mismatch, leaves the replacement and
the original verified directory untouched, and records a durable blocked
recovery obligation when state persistence remains available. The staged
result is blocked, `eligible_root` refuses the pathname, and cleanup refuses it
because ownership of the final entry is unproven. The final rename is also
exclusive: a final pathname that exists before the operation, or appears
between verification and rename, is never replaced. Its foreign bytes remain
intact.

State generations and the quarantine owner marker use the same sidecar
binding. The complete sidecar is written through a held descriptor, checked
against the temporary entry, renamed without replacement, and checked again
against the authoritative entry. A swapped sidecar remains in place, is not
accepted as valid state, and makes the generation chain or recovery inspection
blocked and unproven. The host cannot exclude a same-user writer between the
last successful check and a later mutation, so these checks establish
post-publication detection and fail-closed eligibility rather than perpetual
object exclusivity. The public production `eligible_root(session_id,
grant=...)` method currently returns `None` because admission is unavailable.
The private synthetic eligibility helper rejects a final-looking directory
while durable publication state is pending, interrupted, blocked, expired, or
bound to the wrong grant. It rehashes published members on every private
eligibility check.

State generation temporary sidecars are retained after every publication
attempt. A same-user process can recreate the visible temporary pathname after
a successful rename or a failed publication, so unlinking that pathname cannot
prove ownership of the current entry. Retained temporary sidecars are ignored
by authoritative generation and recovery scans; only complete generation files
participate in the durable state chain. Recovery review owns any later decision
about the retained entry.

### Interrupt and cleanup boundary

Interrupted or failed copies remain quarantined and produce a durable recovery
obligation. An interrupt before the final rename leaves the quarantine and its
owner marker for inspection. An interrupt after the rename but before the
durable eligibility transition leaves a final-looking tree that is not
eligible and is not automatically deleted. The implementation does not retry a
failed mutation or delete a partial automatically.

Cleanup requires `cleanup_authorized: true` in the pinned plan and a still-valid
grant. The current host cannot prove exclusive destructive authority over a
pathname against another process running as the same user. Public cleanup
therefore returns `BLOCKED_UNSUPPORTED_EXCLUSIVITY` before validating the grant,
reading the destination, converting paths, invoking callbacks, acquiring the
coordination lock, loading or replacing ownership state, creating a quarantine,
or attempting deletion. It creates no new durable blocker record or recovery
obligation. Existing ownership, recovery, quarantine, and fixture state remains
unchanged for owner follow-up, including when an interrupted cleanup is
recovering previously persisted state. A private advisory lock serializes
cooperating staging, state-transition, and cleanup calls. It does not prevent a
same-user process
from replacing a pathname and is not evidence that deletion is safe. Ownership
checks reject symlinks, hard links, special files, unrecorded entries, changed
ownership, and uncertain state. The ownership record is safety state, not
Issue #25's execution evidence ledger.

## Result meaning and validation

Fixture transfer mechanics are exercised through the private synthetic adapter
and report `VERIFIED_FIXTURE` together with
`HOST_PREPARATION_ONLY` and `SYNTHETIC_SIMULATION`. The simulation label
describes the injected local destination boundary; it does not mean that a
device or product Library accepted the fixture, and it does not establish that
the production namespace-isolation gate was satisfied. Public production
staging remains blocked until a kernel-enforced boundary is integrated. The
private synthetic adapter receives and retains an object-bound test capability
tied to the adapter owner and exact issuing `threading.Thread` object. The
capability is not a production configuration option, is not propagated through
context variables, has no adapter reset path, and is unusable from another live
thread or a later thread object that reuses the same numeric identifier.
Authority is read from private closure-held object identity, so copied objects,
forged instances, subclasses, owner changes, and attempts to rewrite normalized
attributes fail closed before destination mutation. The registry strongly holds
the issuing thread object while the capability exists. These checks assume a
trusted Python process; arbitrary code that can rewrite closure internals or
authorization functions is outside this boundary.
Failures report `BLOCKED` with a sanitized blocker code. Results include the
sanitized coverage mode and the
required and selected fixture counts for both mandatory full-plan and
explicitly authorized partial-plan coverage. Missing or unsupported
expectations are unverified, and structural-only evidence has its own blocked
classification. No status is a product scan pass, device admission, physical
qualification, or owner verdict.

The deterministic tests generate synthetic bytes and use temporary host
directories only. Run `just test-android-qualification` for the host suite.
The suite is ADB free; full-format and physical-device verification remain
unperformed and belong to later qualification work.
