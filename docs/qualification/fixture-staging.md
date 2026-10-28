# Owner Fixture Staging

This guide describes the host-only workflow for copying owner-selected ROM
fixtures into a private staging directory for qualification. It applies the
unprivileged best-effort design recorded in [ADR-004](../adr/adr-004-best-effort-fixture-staging.md).
It does not authorize device access or establish production isolation.

## Guarantees and limits

The workflow validates a versioned manifest, the owner's explicit fixture
selection, and the exact source tree for every selected fixture. It copies in
bounded chunks, checks the configured free-space reserve during transfer,
reads back each staged file to verify its declared size and SHA-256 digest,
checks playlist and CUE relationships, then renames the completed set from
`incomplete` to `published` on the same filesystem. A failed or interrupted
copy is never reported as a verified publication.

The source files are opened read-only. A hash confirms that bytes match the
manifest; it does not prove who supplied the manifest or whether a game
identity is authentic. Same-user concurrent modification is outside the
workflow's threat model. The run marker and local directory permissions are
not a security boundary against another process with the same account.

The module does not install or invoke a privileged service, use XPC/Mach IPC,
enroll a Secure Enclave key, authenticate an application signature, or run a
qualification VM. It does not access an Android device, use ADB, or change
device data. Issue #23 authorization and Issue #26 physical-device rules remain
separate and unchanged.

## Public API

The implementation is `scripts/android_qualification/fixture_staging.py`.
Callers provide a manifest, a mapping from selected fixture IDs to source
directories, the ordered fixture selection, and explicit owner approval:

```python
result = stage_fixtures(
    manifest,
    sources={"fixture-id": "/path/to/selected/source"},
    selected_fixture_ids=("fixture-id",),
    owner_approved=True,
)
```

The manifest can be a mapping, UTF-8 JSON bytes, or a regular file path. JSON
objects reject duplicate keys, floating-point values, constants such as NaN,
unknown fields, unsupported schema versions, and inputs larger than 32 MiB.
The source mapping must contain exactly the selected fixture IDs. Approval
must be the boolean value `true`; no environment variable or test-only flag
can silently approve a run.

The default staging root is:

- macOS: `~/Library/Application Support/ArgusROMToolkit/FixtureStaging`
- Other systems: `$XDG_STATE_HOME/argus-rom-toolkit/fixture-staging`, or
  `~/.local/state/argus-rom-toolkit/fixture-staging` when unset

`ARGUS_FIXTURE_STAGING_ROOT` can select another owner-controlled directory.
The selected root must be owned by the current user and have no group or other
permissions. User-controlled symlink ancestors and non-sticky directories
writable by group/other users are rejected. Root-owned system path aliases are
resolved; sticky writable directories are accepted only when owned by root or
the current user. Source and destination trees may not overlap.

## Manifest schema version 2

The top-level object contains exactly `schema_version`, `coverage`, and
`fixtures`. Version 2 defines these fields:

| Field | Meaning |
|---|---|
| `coverage.mode` | `mandatory_full_plan` requires every listed fixture; `authorized_partial_plan` permits an explicitly selected subset. |
| `coverage.required_fixture_ids` | Ordered fixture IDs represented by this manifest. |
| `coverage.mandatory_fixture_ids` | IDs that must be included even in a partial run. |
| `fixture_id`, `group_id`, `order` | Stable fixture identity and its position in an ordered group. Group orders start at zero and contain no gaps. |
| `platform`, `representation` | Human-readable platform and source format. |
| `entrypoint` | A relative path to the file used to launch or interpret the fixture. |
| `expected_identity` | Expected game identity facts. These remain owner-reviewed expectations. |
| `structural_expectations` | Supported structure claims: `entrypoint_kind` is `raw-file`, `cue`, or `m3u`; an M3U entrypoint also requires a positive integer `disc_count`. |
| `files` | Exact relative path, role, byte size, and lowercase SHA-256 for every regular source file. |
| `companions` | Ordered `source` to `target` relationships. Every file must be reachable from the entrypoint. |
| `identity_evidence` | `null`, synthetic provenance, or a pinned independent reference. A pinned reference is still unverified and does not qualify the fixture. |

Paths must be relative POSIX paths. Absolute paths, traversal, backslashes,
duplicate paths, case-fold collisions, and file/directory name conflicts are
rejected. Each selected source directory must contain exactly the manifest's
files. Symlinks, non-regular files, unlisted files, and missing files block
staging.

Manifest file paths, entrypoints, and companion `source` and `target` paths are
relative to the fixture root. Paths inside M3U and CUE descriptors are relative
to the directory containing that descriptor. The validator resolves each
descriptor reference to a fixture-root-relative path once, then compares it
with the manifest's ordered companion targets. For example, `disc1.cue` in
`games/playlist.m3u` resolves to `games/disc1.cue`; a root-level playlist entry
of `games/disc1.cue` resolves to that same path.

`structural_expectations` has a closed schema. `raw-file` requires a non-M3U,
non-CUE entrypoint and permits no other expectation field. `cue` requires a
`.cue` entrypoint and permits no other expectation field. `m3u` requires a
`.m3u` entrypoint and a positive integer `disc_count`; Boolean values are not
integers for this contract. Unknown keys, unsupported kinds, invalid types,
and expectations that do not apply to the entrypoint are rejected as an
invalid manifest before a staging run is created. Persisted run records are
checked against the same contract before inspection or cleanup.

Coverage is explicit. A full plan cannot omit a listed fixture. A partial plan
must name a strict subset and include every mandatory fixture. The selection
must preserve the order in `required_fixture_ids`; the result reports exactly
which fixtures were selected.

## Byte and relationship verification

The copy buffer is limited to 1 MiB. The module checks free space for the
complete selected set plus the configured reserve before creating a run, and
rechecks the reserve while copying and before publication. There is no
artificial per-fixture byte limit. If a source changes during a read, has an
unexpected size, or produces a different SHA-256, publication fails.

The copied files are flushed to disk and read back in bounded chunks. The
staged tree must contain exactly the manifest files and expected directories;
extra files, directories, links, or content mismatches prevent publication.
`entrypoint_kind: "raw-file"` is a single-file representation and cannot
declare companion edges because no on-disk descriptor can verify those
relationships. For `entrypoint_kind: "m3u"`, UTF-8 playlist entries must match
the manifest's ordered playlist companion edges, and `disc_count` must equal
the number of entries. For each CUE file, its `FILE` references must match that
CUE's ordered companion edges. Descriptor input is bounded to 8 MiB. Unsafe,
missing, unlisted, or reordered references fail with `STRUCTURE_MISMATCH`.

After bytes and relationships verify, the complete run directory contains a
`published` tree. The move from `incomplete` to `published` is atomic within
that run directory. The result status `verified` means byte and declared
structure checks passed; it does not mean game identity or qualification
passed.

## Identity evidence and qualification

Each result keeps four concepts separate: byte integrity, structural checks,
identity support, and qualification status. `fixture_oracle.py` accepts these
identity evidence tiers:

- Missing evidence is `not_independently_verified`.
- Generated evidence is `synthetic_only`.
- A reference with source, revision, method, provenance, conflicts, and a hash
  bound to `expected_identity` is `pinned_unverified`.

All tiers report `qualification_status: "not_qualified"`. A hash, a test
fixture, or a source citation alone is not independent game verification.
Issue #24 remains open until genuine owner-provided corpus evidence is
independently reviewed and accepted. No private ROM evidence is included in
the repository or this result.

## Run inspection and cleanup

Each run has a random 32-character lowercase hexadecimal ID and a small
`run.json` marker containing the canonical manifest digest, selected fixture
IDs, file metadata, status, byte counts, expected identity, and identity
evidence. Inspection recomputes the recorded evidence tier from those fields
and rejects an inconsistent tier. The marker is written atomically. It is for
best-effort recovery; it is not signed or protected from same-user replacement.

Use `inspect_staging(run_id, staging_root=...)` to re-read the marker and
rehash a published set. An interrupted `staging` marker is reported as
incomplete, even if a complete tree was renamed immediately before the
interruption. Inspection never resumes a copy or promotes an interrupted run.

Use `cleanup_staging(run_id, staging_root=...)` to explicitly remove a run's
content. Cleanup validates the run ID and run marker before examining either
tree. Under `incomplete/`, it may remove manifest-listed ordinary files without
requiring their final size or SHA-256; this reclaims partial transfers and
files completed before an interruption. It never follows or removes a symlink,
or removes an unlisted file or unexpected directory.

Under `published/`, cleanup removes a file only when its size and SHA-256 still
match the validated run record. A modified, replaced, foreign, or otherwise
ambiguous published file is retained. This rule also applies when publication
completed but the final run-record update was interrupted. Empty recognized
directories are removed without recursive deletion. Unknown content leaves the
run in `cleanup_pending` with `UNRECOGNIZED_CONTENT`; a filesystem error leaves
it `cleanup_pending` with `CLEANUP_FAILED`. Retries are explicit. Successful
cleanup retains the small `run.json` tombstone. If the marker cannot be updated
after a cleanup failure, the API returns `failed` and does not claim cleanup
succeeded.

The workflow assumes cooperative, owner-controlled access to the staging
directory. Another same-user process can change the marker or entries between
checks; cleanup does not claim adversarial race protection. Do not use this
workflow on paths shared with other programs or on irreplaceable source
material without an independent backup.

## Qualification boundary

Synthetic tests qualify only the host module's stated best-effort behavior.
They cannot establish production code signing, owner consent, Secure Enclave
enrollment, kernel-enforced isolation, VM isolation, physical-device behavior,
or genuine-corpus correctness. Production or device operations remain blocked
until their separate authorization and evidence requirements are met.
