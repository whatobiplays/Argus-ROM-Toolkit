# Best-Effort Owner Fixture Staging

**Document ID:** ADR-004
**Status:** Complete
**Owner:** Daniel
**Last Updated:** 2026-10-28
**Depends On:** ARCH-003, SPEC-X-003, Issue #24
**Supersedes:** The unmerged privileged staging proposal in PR #52
**Superseded By:** None

## Decision lifecycle and approval

The owner approved this additive replacement on 2026-10-28. `Complete` is the
repository lifecycle status for an implemented and recorded decision. This
decision changes Issue #24's host-side fixture preparation approach; it does
not change the device authorization, data-protection, or physical-device rules
in Issues #23 and #26.

## Context

Issue #24 needs a host workflow that copies explicitly selected owner fixtures
for qualification, checks complete bytes and file relationships, and can
inspect or clean up an interrupted run. The earlier proposal depended on a
privileged service, a separate UID, signed IPC, protected ownership journals,
and OS-enforced namespace isolation. That design was not installed or
qualified, and same-UID staging cannot provide its hostile-process guarantees.

The replacement must preserve originals, make the owner selection explicit,
fail safely when inputs are incomplete, and distinguish byte integrity from
independently established game identity. Synthetic test evidence cannot satisfy
Issue #24's independent fixture acceptance requirement.

## Options Considered

### Option 1: Install a privileged isolated staging service

Continue with the proposed service identity, authenticated broker, protected
state, and owner key enrollment. This could provide stronger isolation after
production signing, installation, and adversarial qualification, but those
owner-controlled prerequisites are unavailable and the architecture is not
presently installable as a normal host workflow.

### Option 2: Use an unprivileged best-effort filesystem workflow

Keep selection, copying, verification, run inspection, and cleanup in a small
host module. Use private owner-controlled directories, bounded streaming,
readback hashes, an exact manifest membership check, and atomic publication.
Document that concurrent same-user modification is outside its guarantee.

### Option 3: Do not provide host staging

Leave Issue #24 without a staging workflow until a separately authorized
production isolation system is available. This avoids implying security
properties but also leaves the requested host-side fixture preparation
unimplemented.

## Decision

Implement Option 2. The workflow requires an explicit manifest, a caller's
selected source root for each selected fixture, and affirmative owner approval.
It streams files in bounded chunks, checks free-space reserve during transfer,
verifies the staged bytes and declared playlist/CUE relationships, then
publishes the complete set with a same-filesystem rename. It records a small
run marker for inspection and best-effort cleanup. Cleanup is explicit and
follows the location-sensitive rules in the clarification below.

Interrupted mutations are never resumed automatically.

## Cleanup policy clarification (2026-10-28)

The corrective implementation distinguishes the two fixed content trees under
the validated run directory. Explicit cleanup may remove any manifest-listed
ordinary file under `incomplete/` without requiring its final size or digest,
so interrupted transfers can reclaim partial bytes. Under `published/`, a file
is removable only when its size and SHA-256 match the run record. This published
rule also applies if the final record update was interrupted after the atomic
publication rename.

Symlinks, unexpected filesystem objects, unlisted files, and unexpected
directories are retained. Cleanup does not recursively delete arbitrary
directories. When the marker remains writable, unknown content or filesystem
errors leave it in `cleanup_pending`, with the corresponding error recorded
for a later explicit retry. If updating the marker also fails, cleanup returns
`failed` rather than claiming success. This correction assumes cooperative
access to the owner-controlled staging directory and does not add same-user
adversarial race protection.

## Rationale

The unprivileged workflow directly implements the current host-side acceptance
criteria with ordinary filesystem APIs and testable recovery outcomes. It does
not claim that mode bits, hashes, or atomic rename prevent an interfering
process with the same user identity from replacing files or changing the
destination. A valid manifest digest establishes input consistency, not owner
identity or game authenticity. Independent identity evidence remains
unverified until reviewed against real, independently sourced fixture data.

## Consequences

### Positive

- Fixture selection and owner approval are visible in the API call.
- Source files remain read-only; staged content is read back and verified.
- Large files use bounded copy buffers rather than whole-file memory reads.
- Incomplete output is not published as a verified fixture set.
- Recognized run content can be inspected and safely cleaned without deleting
  unlisted files or following symlinks.
- The implementation has no privileged service, XPC/Mach IPC, Secure Enclave
  key, broker, VM, or native AQStore dependency.

### Negative

- A concurrent process running as the same user can modify the run marker or
  published files. This is a best-effort local workflow, not a security
  boundary or production isolation proof.
- A successful synthetic run proves only the tested host behavior. It does not
  qualify real ROMs, production signing, owner consent, a VM, or a device.
- Unrecognized cleanup content is retained for owner inspection and can leave
  disk usage behind.

### Follow-Up

- Preserve Issue #24's independent fixture-corpus acceptance criteria and keep
  the issue open until genuine evidence is independently reviewed.
- Keep Issue #23 authorization and Issue #26 physical Android qualification
  contracts unchanged.
- Retain the old isolation feasibility document as historical design evidence;
  it is not current operating guidance.
- Do not merge or close Issue #24 based on synthetic tests or this ADR.

## References

- [Issue #24 fixture staging requirements](../qualification/fixture-staging.md)
- [Historical staging isolation feasibility proposal](../qualification/staging-isolation-feasibility.md)
- [Issue #24](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/24)
