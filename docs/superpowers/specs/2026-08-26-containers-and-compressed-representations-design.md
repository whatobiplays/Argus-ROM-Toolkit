# Containers and Compressed Representations Design

## Status

Approved in design review on 2026-08-26.

## Purpose

Extend Argus's existing source-recognition, canonical identity, grouping, and refresh pipeline to supported archive/stream wrappers and compressed optical-disc representations without creating packaging-sensitive identities or a parallel container subsystem.

This design activates the BE-012 derived-container model and the BE-014 alternate-representation rules on top of the cartridge and native/raw optical identities already qualified.

## Scope

The MVP representation set for this work is:

- ZIP
- 7z
- tar
- gzip
- bzip2
- xz
- CHD
- RVZ
- CSO
- WBFS

RAR is intentionally deferred until post-MVP because currently available pure-Rust decoder coverage is not sufficient to support the advertised semantics confidently. Password-protected/encrypted archives, split or multi-volume archives, and generic multi-game archive expansion are also outside this work.

## Architectural approach

Use the existing BE-012 transformation graph as the center of the implementation.

```text
SourceEntry
   ↓ validated read
ParsingSession + shared TransformationBudget
   ↓
registered transformation
   ├─ archive enumeration → DerivedScopeResult → persistent derived SourceEntries
   └─ media decoding → canonical representation → existing identity pipeline
```

Each supported format receives a narrow infrastructure adapter. Decoder libraries perform decoding only. Argus owns transformation registration, resource charging, derived coordinates and fingerprints, dependency admission, archive eligibility, canonical identity, reconciliation authority, cancellation, and error mapping.

CHD, RVZ, CSO, and WBFS reconstruct or expose the representation required by the already-qualified optical canonicalization contracts. They do not create new identity schemes.

The implementation is pure-Rust-first. Mature safe Rust dependencies may be used when they satisfy the exact required semantics. If a dependency is insufficient for a BE-014-advertised representation, Argus supplies the missing safe-Rust adapter/decoder behavior rather than weakening the advertised matrix. No C/C++ FFI or external decoder executables are introduced.

## Archive traversal and derived source truth

ZIP, 7z, tar, gzip, bzip2, and xz produce derived source scopes. Safely enumerated members become persistent derived `SourceEntry` children through BE-012/BE-011 reconciliation.

A derived observation carries transformation-owned evidence equivalent to:

```text
DerivedEntryObservation
- derived_locator
- derived_entry_key
- display_name
- entry_kind
- cheap_metadata
- derived_fingerprint
```

Derived entries never masquerade as provider-native paths, locators, native identities, or fingerprints.

### Scope authority

A derived scope may authorize absence-based deletion only when:

1. the parent read was validated as stable;
2. enumeration completed with `DerivedScopeOutcome::Complete`;
3. the entire transformation chain stayed within its cumulative resource budget;
4. cancellation was not accepted; and
5. the current transformation identity/revision still matches the persisted derivation contract.

`Partial`, `Failed`, `Cancelled`, source mutation, malformed structure, budget exhaustion, or indeterminate processing never authorize absence.

### Single-game eligibility

Archive source truth and logical-library materialization are separate concerns.

- One recognizable game/content family plus unrelated sidecars is accepted.
- A multi-file content unit such as CUE/BIN counts as one content family when its required dependencies validate.
- Multiple discs are allowed only when explicit validated relationship evidence such as M3U ties them to one release; each disc remains its own `GameContent`.
- Multiple independently usable games cause atomic `MULTI_GAME_CONTAINER_UNSUPPORTED` rejection for identification from that archive. No member `GameContent` is materialized from it.
- All safely enumerated members may still remain truthful persistent derived `SourceEntry` nodes even when logical materialization is rejected.
- Non-game sidecars such as README/NFO/images/checksums do not count as independent games and never enter `ContentIdentity` unless a registered downstream representation explicitly requires them.
- Nested supported containers must be traversed sufficiently to determine eligibility and share the same cumulative parsing budget.

Encrypted/password-protected archives are rejected with the existing encrypted-content error. Split/multi-volume archives and RAR are unsupported representations in MVP.

## ParsingSession, staging, and budgets

All transformations in one operation run inside a single BE-012 `ParsingSession` owning cancellation, staging, and cumulative accounting.

Initial fixed Argus safety ceilings are:

- maximum single representation: 16 GiB
- maximum cumulative expanded bytes: 32 GiB
- maximum cumulative staged bytes: 16 GiB
- maximum derived entries: 65,536
- maximum nesting depth: 4
- maximum parser work: finite implementation-defined ceiling sized to the advertised optical matrix

These are internal runtime policy, not user settings. Desktop and Android use the same semantic ceilings. Tests inject much smaller budgets to exercise boundaries without huge fixtures.

Every nested transformation charges the same session. No nested archive or compressed media representation receives a fresh expansion, staging, entry-count, depth, or parser-work allowance.

Large temporary data is staged in app-private, operation-scoped, disk-backed storage when stable seekable/random access is required. Staging is never a `SourceEntry`, never a reusable content cache, and must be removable during startup cleanup if an operation is abandoned. Large staging also requires sufficient available app-private free space; insufficient space maps to `TRANSFORMATION_RESOURCE_LIMIT_EXCEEDED` rather than partial success.

Cancellation is observed during source consumption, enumeration, decompression, staging, alternate-disc decoding, canonicalization, and hashing. Source mutation during processing invalidates trusted output and follows the existing source-changed/retry path; it cannot establish identity or derived absence.

## Alternate optical representations

### CHD

CHD is media-semantic, not a generic identity container:

- `chd-cd` reproduces the canonical CD session/track envelope for Sega CD, Saturn, PlayStation, and PlayStation 2 CD content.
- `chd-gd` reproduces Dreamcast GD session/density/track semantics.
- `chd-dvd` reproduces the exact PlayStation 2 DVD 2048-byte logical-sector stream.
- `chd-umd` reproduces the exact PSP UMD 2048-byte logical-sector stream.

Applicability comes from validated media metadata, never filename or folder placement. CHD compression and hunk layout are transport details only.

### RVZ

RVZ is limited to GameCube and Wii. A representation advertised as complete must reconstruct every canonical byte required by the owning raw logical-disc contract. Missing or unreconstructable bytes cause rejection; Argus does not infer or zero-fill bytes to force convergence.

### CSO

CSO is PSP-only and must reconstruct the exact canonical UMD 2048-byte logical-sector stream. Invalid/truncated indexes, unsupported semantics, or incomplete output fail before identity persistence.

### WBFS

WBFS is Wii-only and participates through the existing sparse logical-disc contract. The validated allocation map determines the exact preserved extents that enter the sparse identity envelope.

Argus must not hash WBFS container metadata as game payload, infer absent sectors from filesystem structure, decrypt missing content, zero-fill absent extents, or claim that a scrubbed WBFS converges with a complete raw/RVZ image. WBFS representations converge only when the same sparse extents and exact bytes are proven.

## Persistence and migration

P03-006 is the first implementation that makes BE-012 derived `SourceEntry` semantics durable.

The durable source model gains an explicit provider-native versus derived coordinate/evidence distinction.

Provider-native entries retain concepts equivalent to:

```text
relative_locator
locator_key
provider_native_identity
source_fingerprint
```

Derived entries instead use concepts equivalent to:

```text
derived_locator
derived_entry_key
derived_fingerprint
derivation_transformation_id
derivation_revision
```

The two coordinate families are mutually exclusive. Existing provider-native `SourceEntryId` values, hierarchy, fingerprints, and logical associations must survive migration unchanged. No migration may fabricate provider locators for derived entries or require a destructive library rebuild.

Derived reconciliation occurs within its exact containing scope using the transformation-owned key and revision, conceptually:

```text
(parent_source_entry_id,
 transformation_id,
 transformation_revision,
 derived_entry_key)
```

A changed transformation revision invalidates the old interpretation rather than asserting cross-revision equality. `DerivedFingerprint` is cheap version evidence, not strong content identity.

`GameContentSource`, identity provenance, source-removal handling, hierarchy reads, and orphan/re-identification transitions continue to reference ordinary `SourceEntryId`, regardless of whether an entry is provider-native or derived.

## Error model

Decoder-library errors never cross the infrastructure boundary. Relevant failures map to existing Argus semantics:

- malformed container/representation → `CONTENT_MALFORMED`
- encrypted/password-dependent input → `CONTENT_ENCRYPTED_UNSUPPORTED`
- RAR, multipart archives, or unsupported transform variants → `CONTENT_UNSUPPORTED_REPRESENTATION`
- multiple independently usable games → `MULTI_GAME_CONTAINER_UNSUPPORTED`
- missing required companion member → `CONTENT_DEPENDENCY_MISSING`
- cumulative resource/staging exhaustion → `TRANSFORMATION_RESOURCE_LIMIT_EXCEEDED`
- cancellation → existing cancelled operation/job outcome
- source mutation → existing source-changed-during-processing retry/reconciliation path

No failure may be converted into truncated success, a weakened identity, or false absence authority.

## Qualification

Use synthetic, non-copyrighted fixtures only.

Required deterministic coverage includes:

- each supported generic wrapper with supported cartridge content;
- CUE/BIN and other supported multi-file optical units inside archives;
- M3U-related multi-disc releases inside archives;
- nested supported wrappers through the permitted depth;
- accepted non-game sidecars;
- atomic multi-game rejection;
- encrypted input rejection;
- RAR and multipart rejection;
- traversal-like names, malformed headers/indexes, extreme declarations, entry-count limits, expansion bombs, staging limits, cancellation, and source mutation;
- stable derived `SourceEntryId` reconciliation across unchanged refreshes;
- authoritative removal only after complete stable re-enumeration;
- no absence authority after failed/cancelled/changed processing;
- coherent provenance/orphan/re-identification behavior when outer or derived sources disappear or reappear;
- no changes to existing native cartridge or optical identity values/revisions.

Alternate-media convergence must prove:

```text
native CD/GD/DVD/UMD == equivalent CHD
PSP ISO              == equivalent CSO
GameCube raw         == complete equivalent RVZ
Wii raw              == complete equivalent RVZ
WBFS A               == WBFS B only when sparse extents + bytes match
scrubbed WBFS        != falsely equivalent complete raw/RVZ
```

## Explicit exclusions

This work does not add:

- RAR support;
- password/key acquisition or encrypted-content workflows;
- split/multi-volume archive support;
- generic multi-game archive expansion;
- container/compression-specific identity schemes;
- user-configurable transformation budgets;
- new Library browsing/detail UX;
- physical-device qualification.

Cross-platform lifecycle and physical-device qualification remain later hardening work. The implementation must nevertheless remain portable and buildable for the existing desktop and Android targets.
