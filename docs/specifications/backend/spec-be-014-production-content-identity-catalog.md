# Production Content Identity Catalog Specification

**Document ID:** SPEC-BE-014  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-23  
**Depends On:** ARCH-001, ARCH-002, PHASE-003, SPEC-BE-003, SPEC-BE-011, SPEC-BE-012, SPEC-BE-013  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the production content-identity catalog activated by Phase 003.

`SPEC-BE-012` remains authoritative for how Argus performs typed transformations, validates source reads, establishes authoritative `(PlatformId, ContentType)` recognition, builds canonical `ContentUnit` values, computes `ContentIdentity`, persists provenance, handles identity revisioning, and enforces parsing-session resource safety.

This specification defines which Phase 003 content classes are actually supported and the immutable semantics of each current production `ContentIdentityScheme`.

The governing rule is:

> Argus advertises a platform/content representation as supported only when a validated transformation can produce an authoritative content class and a current catalog entry can deterministically reduce that logical content to a scheme-defined canonical representation whose SHA-256 digest is the Argus `ContentIdentity` value.

## 2. Responsibilities

SPEC-BE-014 owns:

- stable production `PlatformId` values for Phase 003 game content;
- production `ContentType` values used by this catalog;
- stable accepted-source-representation identifiers;
- the closed Phase 003 support matrix;
- immutable production identity `scheme_id` values;
- each scheme's canonical logical representation;
- normalization, ordering, dependency, equivalence, and rejection rules;
- current `identity_revision` values;
- the mandatory SHA-256 identity digest rule;
- single-game generic archive applicability;
- key-free Nintendo 3DS applicability;
- optical-disc, multi-file, and alternate-container applicability;
- deterministic qualification obligations for each supported catalog row.

## 3. Non-Responsibilities

This specification does not own:

- parser-library or decompressor implementation choices;
- transformation planner mechanics or `ParsingSession` ownership;
- source-provider/root semantics;
- SQL schema details;
- `Game` or `GameMembership` grouping;
- provider matching or provider-native identity;
- metadata or artwork resolution;
- Library queries or Flutter presentation;
- `Refresh Library` orchestration;
- RetroAchievements verification or hash semantics;
- arcade/MAME/FBNeo set semantics;
- user-supplied decryption-key workflows.

Those boundaries remain with their owning architecture/specifications.

## 3.1 Platform Applicability

The catalog is shared backend policy on desktop and Android. Platform-specific filesystem access, Android storage readiness, staging location, and lifecycle hosting do not change identity semantics.

A byte-equivalent or logically equivalent content unit must receive the same current `(scheme_id, identity_value)` on every supported host platform.

## 4. Catalog Model

Conceptually:

```text
ProductionContentIdentityCatalogEntry
- platform_id
- content_type
- support_state
- accepted_source_representations[]
- canonical_representation
- identity_scheme_id
- identity_revision
- digest_algorithm
- required_dependencies[]
- normalization_rules
- equivalent_representation_rules
- rejection_rules
- qualification_requirements[]
```

`support_state` is closed:

```text
Supported
ExplicitlyExcluded
```

There is no production `Experimental`, `BestEffort`, or partially supported state. A representation may be useful as a planning hint without being advertised as supported.

## 5. Stable Identifiers

### 5.1 Platform identifiers

Phase 003 uses these stable application-owned identifiers:

```text
nintendo.nes
nintendo.fds
nintendo.snes
nintendo.gb
nintendo.gbc
nintendo.gba
nintendo.n64
nintendo.nds
nintendo.3ds
nintendo.gamecube
nintendo.wii
sega.sms
sega.gamegear
sega.genesis
sega.32x
sega.sega-cd
sega.saturn
sega.dreamcast
sony.playstation
sony.playstation2
sony.psp
```

Regional marketing names such as Famicom/NES, Super Famicom/SNES, Genesis/Mega Drive, and Mega-CD/Sega CD are aliases for presentation/provider mapping where the underlying platform semantics are the same. Famicom Disk System remains distinct because its media/content semantics differ from NES/Famicom cartridges.

### 5.2 Content types

This catalog uses:

```text
CartridgeImage
MagneticDiskImage
OpticalDiscCd
OpticalDiscGd
OpticalDiscDvd
OpticalDiscGameCube
OpticalDiscWii
OpticalDiscUmd
```

A platform may support more than one content type only when the media semantics genuinely differ. For example, PlayStation 2 may use `OpticalDiscCd` or `OpticalDiscDvd`.

### 5.3 Source-representation identifiers

Accepted representation identifiers are application-owned descriptors such as:

```text
nes-ines
nes-2
fds-fw
fds-headerless
snes-linear
snes-copier-headered
n64-native
n64-byteswapped16
n64-byteswapped32
ncsd-nocrypto
genesis-linear-be
genesis-smd
raw-cartridge-image
cue-bin
chd-cd
chd-gd
chd-dvd
chd-umd
iso-2048-cd
iso-2048
raw-disc-image
rvz
gdi
cso
wbfs
zip
sevenzip
rar
tar
gzip
bzip2
xz
m3u
```

Filename extensions are planning hints only. The parser must validate the structure named by the representation identifier.

### 5.4 Identity scheme identifiers

Current production identity schemes use:

```text
argus.content.identity.<platform>.<content-class>.v1
```

All schemes introduced by this specification begin at:

```text
identity_revision = 1
digest_algorithm = SHA-256
```

Scheme IDs describe immutable content semantics. They must not contain phase/slice identifiers, parser-library names, provider names, or transient implementation details.

## 6. Support Advertising Rules

A row is `Supported` only when all of the following are true:

1. A bounded validating transformation can establish authoritative platform/content recognition without relying on filename/folder/provider metadata.
2. One current scheme exists for that `(PlatformId, ContentType)`.
3. The scheme defines exact canonicalization, byte/field selection, ordering, and dependency behavior.
4. Malformed and ambiguous inputs fail without guesswork.
5. Deterministic positive and negative qualification vectors are defined.
6. Any claimed equivalent representations deterministically converge.

Therefore:

```text
Recognized + no current identity scheme -> not advertised as supported.
Parser can open format + unresolved canonical identity -> not advertised as supported.
Key-dependent encrypted input without approved key-free canonicalization -> ExplicitlyExcluded.
Unsupported packaging -> unsupported; never packaging-sensitive identity by accident.
```

## 7. Canonical Digest Envelope

Every scheme computes:

```text
identity_value = SHA256(canonical_representation_bytes)
```

The canonical representation is scheme-specific and may itself be a structured deterministic byte stream. When structure must be encoded, the scheme defines field order and integer encoding; implementation-specific serialization formats are prohibited.

Unless a row explicitly says otherwise, structured canonical envelopes use:

```text
ASCII tag bytes exactly as shown
unsigned integers as fixed-width big-endian
length-prefixed byte strings as u64 length + bytes
arrays as u32 count + ordered elements
```

This encoding rule prevents JSON/CBOR/library-version differences from changing identity.

External CRC32, MD5, SHA-1, DAT, provider, or RetroAchievements hashes remain independent `HashRecord` values even if their input bytes overlap an identity representation.

## 8. Nintendo Cartridge and Disk Catalog

### 8.1 NES / Famicom cartridge

```text
platform_id: nintendo.nes
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-nes.cartridge.v1
identity_revision: 1
accepted_source_representations: nes-2, nes-ines
```

Authoritative recognition requires a valid iNES/NES 2.0 magic, internally consistent declared PRG/CHR/trainer/miscellaneous lengths, and a supported console/mapper interpretation. Invalid/truncated declarations fail as malformed. Filename extension is not evidence.

Canonical representation:

```text
"ARGUS-NES-CART-V1"
normalized console/timing class
mapper
submapper-or-explicit-unknown
mirroring/four-screen semantics
battery/nonvolatile semantics
trainer_present
trainer bytes when present
PRG-ROM length + PRG-ROM bytes
CHR-ROM length + CHR-ROM bytes
ordered miscellaneous-ROM regions described by the validated header
```

The 16-byte transport header is not hashed verbatim. Its semantic fields are normalized into the envelope so equivalent valid headers with irrelevant padding do not fork identity. iNES fields that cannot be mapped unambiguously to the required semantic descriptor use explicit `unknown` values; Argus never invents a NES 2.0 submapper. Two images converge only when the normalized descriptor and all logical ROM/trainer bytes agree.

Malformed/ambiguous mapper metadata that could cause two distinct cartridge hardware interpretations must fail rather than collapsing to one identity.

Technical basis: NESdev iNES/NES 2.0 specifications.

### 8.2 Famicom Disk System

```text
platform_id: nintendo.fds
content_type: MagneticDiskImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-fds.disk.v1
identity_revision: 1
accepted_source_representations: fds-fw, fds-headerless
```

Recognition validates FDS side structure, block ordering, the `*NINTENDO-HVC*` disk verification marker, side count, and block lengths.

Canonical representation is:

```text
"ARGUS-FDS-DISK-V1"
side_count:u32
for each side in physical logical order:
    side_length:u64
    65,500-byte normalized fwNES side payload
```

The optional 16-byte fwNES container header is excluded. Headered and headerless dumps with identical ordered 65,500-byte side payloads converge. Gap timing and physical CRC material absent from the fwNES logical format are not synthesized into identity. QD/raw magnetic captures that cannot be losslessly reduced to this exact logical side representation are not supported by this v1 scheme.

Technical basis: NESdev FDS file-format/disk-format specifications.

### 8.3 SNES / Super Famicom

```text
platform_id: nintendo.snes
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-snes.cartridge.v1
identity_revision: 1
accepted_source_representations: snes-linear, snes-copier-headered
```

Recognition requires a validated LoROM/HiROM/ExHiROM internal-header candidate using header location, map mode, reset-vector plausibility, ROM-size consistency, and checksum/complement evidence where available. Heuristics may reject uncertain content but may not silently choose between incompatible valid mappings.

Canonical representation is the complete linear cartridge ROM byte stream in CPU-ROM storage order after removing a validated 512-byte external copier header and rejecting unexplained bytes outside the validated cartridge ROM extent.

The internal SNES header remains part of the ROM bytes and is therefore identity-bearing. A validated 512-byte copier-headered dump converges with its equivalent linear headerless dump. Legacy interleaved copier layouts are explicitly excluded from this v1 row until a later catalog revision names an exact reversible representation/algorithm; implementation heuristics must not guess a deinterleave transform. Different revisions, ROM-hacks, or changed internal registration/checksum bytes do not converge merely because titles match.

Technical basis: SNESdev ROM header and ROM file-format references.

### 8.4 Game Boy

```text
platform_id: nintendo.gb
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-gb.cartridge.v1
identity_revision: 1
accepted_source_representations: raw-cartridge-image
```

Recognition validates the cartridge header, Nintendo-logo region, ROM-size code, cartridge type, and header checksum, and requires no CGB capability flag. Content that validly declares CGB capability belongs to the Game Boy Color row instead of being duplicated across both platforms.

Canonical representation is the raw cartridge ROM byte stream from offset zero through the exact header-declared ROM size, and `raw-cartridge-image` is valid only when the source byte length exactly equals that declared extent. Extra leading or trailing bytes are unsupported under this representation rather than silently trimmed. Any future padded-dump support requires a separately named representation/transformation with its own proof and normalization contract. No header field is rewritten.

### 8.5 Game Boy Color

```text
platform_id: nintendo.gbc
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-gbc.cartridge.v1
identity_revision: 1
accepted_source_representations: raw-cartridge-image
```

Recognition uses the same validated cartridge-header contract and additionally requires a valid CGB capability flag. Both CGB-only and dual-mode CGB-capable cartridges are canonically `nintendo.gbc`; the same binary is never duplicated as a Game Boy `GameContent`.

Canonical representation is the raw cartridge ROM byte stream from offset zero through the exact header-declared ROM size, and `raw-cartridge-image` is valid only when the source byte length exactly equals that declared extent. Extra leading or trailing bytes are unsupported under this representation rather than silently trimmed. Any future padded-dump support requires a separately named representation/transformation with its own proof and normalization contract. Header/title/checksum/revision changes remain identity-bearing.

Technical basis for both rows: GBDev Pan Docs cartridge-header specification.

### 8.6 Game Boy Advance

```text
platform_id: nintendo.gba
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-gba.cartridge.v1
identity_revision: 1
accepted_source_representations: raw-cartridge-image
```

Recognition validates the GBA cartridge entry/header region, Nintendo-logo data, fixed fields, and complement/checksum semantics defined by the cartridge header contract.

Canonical representation is the complete validated cartridge-ROM byte stream. This v1 scheme does not strip arbitrary external copier prefixes or normalize arbitrary trailing bytes because the native cartridge header does not provide a universally safe semantic rule for doing so. Such representations must first be transformed by a separately validated representation transformation or are unsupported.

Technical basis: GBATEK GBA cartridge-header specification.

### 8.7 Nintendo 64

```text
platform_id: nintendo.n64
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-n64.cartridge.v1
identity_revision: 1
accepted_source_representations: n64-native, n64-byteswapped16, n64-byteswapped32
```

Recognition validates one of the known N64 ROM byte-order signatures and a structurally plausible cartridge header.

Canonical representation is the complete cartridge ROM normalized to native big-endian `.z64` byte order:

```text
native:          ABCD -> ABCD
16-bit swapped:  BADC -> ABCD
32-bit reversed: DCBA -> ABCD
```

The extension does not determine conversion. The first bytes/header signature do. All byte-order representations of the same ROM converge; different ROM bytes do not.

Technical basis: N64 development ROM-format references and established emulator tooling.

### 8.8 Nintendo DS

```text
platform_id: nintendo.nds
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-nds.cartridge.v1
identity_revision: 1
accepted_source_representations: raw-cartridge-image
```

Recognition validates the NDS cartridge header, Nintendo-logo area, header CRCs, ARM9/ARM7 region declarations, filesystem tables, and declared/used ROM bounds before authoritative recognition.

Canonical representation is the byte stream from offset zero through the validated logical/used ROM extent declared by the cartridge structure. Alignment/padding bytes beyond that extent are excluded only after proving they are outside every declared executable/filesystem/overlay region. If the transformation cannot prove the safe logical extent, it hashes the complete validated image rather than trimming speculatively.

A trimmed and padded dump converges only when both parse to the same proven logical used extent and all canonical bytes match.

Technical basis: GBATEK Nintendo DS cartridge-header/filesystem specification.

### 8.9 Nintendo 3DS key-free subset

```text
platform_id: nintendo.3ds
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-3ds.nocrypto-ncsd.v1
identity_revision: 1
accepted_source_representations: ncsd-nocrypto
```

Recognition requires a structurally valid NCSD game-card container and valid contained NCCH partitions. Every identity-bearing NCCH partition must explicitly indicate the key-free `NoCrypto` state and all declared partition ranges must be readable and internally consistent. A merely externally decrypted payload whose headers still require cryptographic interpretation does not satisfy this v1 row.

Canonical representation is the complete declared NCSD logical media extent with non-media transport padding beyond the declared extent excluded. Bytes inside that declared extent, including NCSD/NCCH headers and key-free payload bytes, remain identity-bearing; Argus does not normalize signatures, executable builds, or content revisions into equivalence.

Explicitly excluded in Phase 003:

- NCSD/NCCH whose identity-bearing partitions do not prove `NoCrypto` key-free semantics;
- encrypted NCSD/NCCH requiring external keys;
- CIA packages requiring title-key/ticket decryption or installation semantics;
- partially decrypted images whose complete identity-bearing content cannot be validated from the persisted representation alone.

No key material is requested, persisted, embedded, or inferred by this scheme.

Technical basis: 3dbrew NCSD/NCCH container and crypto-state documentation.

## 9. Sega Cartridge Catalog

### 9.1 Master System

```text
platform_id: sega.sms
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.sega-sms.cartridge.v1
identity_revision: 1
accepted_source_representations: raw-cartridge-image
```

Recognition validates the Sega cartridge header, including the `TMR SEGA` marker at the size-appropriate header location, declared ROM-size information, and internally consistent checksum/header fields where applicable.

Canonical representation is the complete validated cartridge ROM logical extent. The Sega header remains identity-bearing. External copier prefixes are not stripped unless a separate transformation proves their exact non-cartridge extent.

Technical basis: Sega Master System software/reference manual cartridge-header contract.

### 9.2 Game Gear

```text
platform_id: sega.gamegear
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.sega-gamegear.cartridge.v1
identity_revision: 1
accepted_source_representations: raw-cartridge-image
```

Recognition uses the validated Sega `TMR SEGA` header plus product/region/media fields that distinguish Game Gear from Master System where the formats overlap. If the same bytes admit incompatible valid SMS and Game Gear recognition, BE-012 `AmbiguousContentRecognition` applies.

Canonical representation is the complete validated cartridge ROM logical extent with the header retained.

### 9.3 Genesis / Mega Drive

```text
platform_id: sega.genesis
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.sega-genesis.cartridge.v1
identity_revision: 1
accepted_source_representations: genesis-linear-be, genesis-smd
```

Recognition validates the cartridge vector/header region, Sega system marker in the header, declared ROM address range, and header consistency. `genesis-smd` is accepted only for a validated standalone/terminal Super Magic Drive image: the 512-byte copier header is excluded, the remaining length is a whole number of 16 KiB blocks, and every block is reversibly deinterleaved from its two 8 KiB even/odd-byte halves into linear cartridge order. Split-series SMD members are not independently supported.

Canonical representation is the complete cartridge image in normal 68000 big-endian linear ROM order. The 512-byte SMD copier header and reversible 16 KiB interleaving are transport details and do not enter identity. A valid SMD image and its byte-identical linear reconstruction must converge.

### 9.4 Sega 32X

```text
platform_id: sega.32x
content_type: CartridgeImage
support_state: Supported
identity_scheme_id: argus.content.identity.sega-32x.cartridge.v1
identity_revision: 1
accepted_source_representations: genesis-linear-be
```

Recognition requires the shared Mega Drive cartridge structure plus validated 32X-specific startup/vector/header evidence. A generic Genesis image is not promoted to 32X based on filename or directory placement.

Canonical representation is the complete normal big-endian cartridge byte stream. The 32X identity scheme is distinct from Genesis even if a malformed pair of inputs happened to share payload bytes because the authoritative platform/content class differs.

## 10. Canonical Optical-Disc Envelopes

Optical media requires explicit structure. Argus never hashes a CUE text file, CHD container, GDI descriptor, or filename sequence as the logical disc identity.

### 10.1 Canonical CD logical-track envelope

`OpticalDiscCd` schemes use a semantic track/sector envelope rather than hashing transport-specific 2352-byte framing. All numeric fields use the Section 7 fixed-width big-endian rule. Closed one-byte values are:

```text
track_mode / pregap_mode:
  0x00 = None                  # pregap_mode only
  0x01 = Audio
  0x02 = Mode1
  0x03 = Mode2

pregap_kind:
  0x00 = None
  0x01 = Stored
  0x02 = Synthesized

sector_kind:
  0x01 = Audio2352
  0x02 = Mode1User2048
  0x03 = Mode2Formless2336
  0x04 = Mode2XaForm1
  0x05 = Mode2XaForm2
```

The canonical stream is:

```text
"ARGUS-CD-LOGICAL-V1"
session_count:u32
for each session in physical order:
    first_track:u32
    last_track:u32
for each track in physical order:
    track_number:u32
    track_mode:u8
    index01_start_lba:i64 encoded as signed two's-complement u64
    pregap_kind:u8
    pregap_mode:u8
    pregap_sector_count:u64
    when pregap_kind = Stored:
        canonical_sector_record for each stored pregap sector in order
    main_sector_count:u64
    canonical_sector_record for each main sector in order
    postgap_sector_count:u64
```

Each `canonical_sector_record` begins with exactly one `sector_kind:u8`, followed immediately by its canonical bytes:

- `Audio2352`: exact 2352 PCM bytes;
- `Mode1User2048`: exact 2048 user-data bytes;
- `Mode2Formless2336`: exact 2336 bytes following the standard 16-byte sync/header area;
- `Mode2XaForm1`: one validated 4-byte XA subheader tuple (`file`, `channel`, `submode`, `coding_info`) followed by the exact 2048 user-data bytes;
- `Mode2XaForm2`: the same validated 4-byte XA subheader tuple followed by the exact 2324 user-data bytes.

For XA sectors the two on-disc copies of the 4-byte subheader must agree before canonicalization; conflicting copies are malformed rather than normalized. Standard raw sync/header/EDC/ECC framing and the duplicate XA subheader copy are excluded only after validation because they are redundant/derivable from track position, sector kind, canonical subheader, and payload. Mixed Mode-2 Form-1/Form-2 sectors therefore remain distinguishable through their per-sector tags and XA subheaders.

Stored/index-00 pregap data is identity-bearing and is distinguished from a synthesized pregap that exists only as track geometry. Synthesized pregaps contribute `pregap_kind`, `pregap_mode`, and count but no invented sector records. A track with no pregap uses `pregap_kind = None`, `pregap_mode = None`, and count zero. Postgap count is likewise geometry, not synthesized payload.

Subchannel data and secondary index markers beyond the v1 track/pregap geometry are not canonicalized. Inputs whose correct behavior or identity depends on nonstandard raw framing, protection-bearing main-channel anomalies, subchannel content, or additional index semantics that cannot survive the supported representation round-trip are `ExplicitlyExcluded` rather than silently flattened.

### 10.2 Descriptor dependencies

For CUE/BIN-equivalent layouts, the descriptor transformation must validate:

- descriptor grammar and track modes;
- every referenced source entry;
- ordered file/track/index relationships;
- stored versus synthesized pregap semantics, index-00/index-01 relationship, and postgap geometry;
- rejection of additional index semantics that the v1 canonical envelope cannot preserve;
- sector-size/mode/form compatibility;
- absence of contradictory overlapping track extents.

All source entries consumed by the disc become exact BE-012 identity-provenance roles. Missing, conflicting, cyclic, or out-of-bounds dependencies fail before identity is persisted.

### 10.3 CHD CD representation

`chd-cd` is Supported only when decoding plus CHD track metadata yields the complete canonical CD logical-track envelope required by the platform's scheme, including whether pregap bytes are physically stored versus synthesized. CHD track metadata distinguishes stored pregap data from generated pregap geometry; Argus preserves that distinction. A CHD that cannot reproduce required track geometry or semantic sector payloads is unsupported. CHD container bytes and compression choices never enter identity.

### 10.4 Native ISO applicability

`.iso` is not a universal semantic format.

A 2048-byte-sector ISO source is accepted for a CD platform only when the validating transformation proves that the platform/content class is fully represented by one **Mode 1** data track and does not require omitted audio, XA subheader, raw-sector, subchannel, or index information. It maps to `iso-2048-cd`; each sector becomes `Mode1User2048` and therefore converges with an equivalent validated raw Mode-1 source. A 2048-byte image that could represent stripped Mode-2/XA content is not promoted to `iso-2048-cd` without independent structural proof of Mode-1 semantics. Mixed-mode, Mode-2/XA, protection-sensitive, or otherwise raw/index-dependent discs require a representation containing the required information.

## 11. Sega Optical Catalog

### 11.1 Sega CD / Mega-CD

```text
platform_id: sega.sega-cd
content_type: OpticalDiscCd
support_state: Supported
identity_scheme_id: argus.content.identity.sega-cd.disc.v1
identity_revision: 1
accepted_source_representations: cue-bin, chd-cd, iso-2048-cd
```

Recognition requires validated Sega CD system-disc identification (`SEGADISCSYSTEM` for bootable system discs) in the proper disc data plus a structurally valid CD track layout. Data-only `SEGADATADISC` media is not advertised as a game unless later product policy explicitly activates it.

Canonical representation is the canonical CD logical-track envelope in Section 10.

Technical basis: Sega Mega-CD Disc Format Specifications.

### 11.2 Sega Saturn

```text
platform_id: sega.saturn
content_type: OpticalDiscCd
support_state: Supported
identity_scheme_id: argus.content.identity.sega-saturn.disc.v1
identity_revision: 1
accepted_source_representations: cue-bin, chd-cd, iso-2048-cd
```

Recognition requires a valid Saturn boot/header area beginning with the `SEGA SEGASATURN ` hardware identifier plus structurally valid CD geometry. Canonical representation is the Section 10 CD logical-track envelope.

### 11.3 Dreamcast

```text
platform_id: sega.dreamcast
content_type: OpticalDiscGd
support_state: Supported
identity_scheme_id: argus.content.identity.sega-dreamcast.gdrom.v1
identity_revision: 1
accepted_source_representations: gdi, cue-bin, chd-gd
```

Recognition validates the Dreamcast bootstrap/header identity (`SEGA SEGAKATANA `), session/track geometry, and the high-density data region for GD-ROM content. Self-boot MIL-CD/CD-R layouts are accepted only when the transformation can establish the same Dreamcast content class without guessing.

Canonical representation uses a Dreamcast-specific logical track envelope:

```text
"ARGUS-GD-LOGICAL-V1"
session_count:u32
for each session in physical order:
    density:u8             # 0x01 = low density, 0x02 = high density
    first_track:u32
    last_track:u32
for each track in physical order:
    track_number:u32
    density:u8
    track_mode:u8          # same Audio/Mode1/Mode2 values as Section 10.1
    index01_start_lba:i64 encoded as signed two's-complement u64
    sector_count:u64
    canonical_sector_record for each sector in order
```

`canonical_sector_record` is exactly the Section 10.1 record format, including Mode-2/XA subheader semantics. Session and density boundaries are identity-bearing. GDI/CUE/CHD descriptor/container text, filenames, byte offsets, and compression layout are transport details after they have been validated to reconstruct this envelope. A representation that cannot preserve required session/density/sector semantics is unsupported rather than flattened.

Technical basis: Dreamcast IP.BIN/IP0000.BIN documentation and established GDI tooling.

## 12. Sony Optical Catalog

### 12.1 PlayStation

```text
platform_id: sony.playstation
content_type: OpticalDiscCd
support_state: Supported
identity_scheme_id: argus.content.identity.sony-playstation.disc.v1
identity_revision: 1
accepted_source_representations: cue-bin, chd-cd, iso-2048-cd
```

Recognition requires a structurally valid PlayStation CD layout plus bootable PlayStation evidence such as valid `SYSTEM.CNF`/`PS-X EXE` boot structure or an equivalent validated platform marker. ISO9660 presence alone is insufficient because it is cross-platform.

Canonical representation is the Section 10 CD logical-track envelope. Mixed-mode/audio tracks are retained and ordered. Data-only ISO is accepted only when it fully determines the canonical track representation.

### 12.2 PlayStation 2 CD

```text
platform_id: sony.playstation2
content_type: OpticalDiscCd
support_state: Supported
identity_scheme_id: argus.content.identity.sony-playstation2.cd.v1
identity_revision: 1
accepted_source_representations: cue-bin, chd-cd, iso-2048-cd
```

Recognition requires valid PlayStation 2 boot evidence, including a valid `SYSTEM.CNF` `BOOT2` contract, plus CD geometry. Canonical representation is the Section 10 CD logical-track envelope.

### 12.3 PlayStation 2 DVD

```text
platform_id: sony.playstation2
content_type: OpticalDiscDvd
support_state: Supported
identity_scheme_id: argus.content.identity.sony-playstation2.dvd.v1
identity_revision: 1
accepted_source_representations: iso-2048, chd-dvd
```

Recognition requires a valid 2048-byte logical-sector DVD image, valid filesystem/volume structures, and PlayStation 2 `SYSTEM.CNF` `BOOT2` evidence.

Canonical representation is:

```text
"ARGUS-PS2-DVD-V1"
logical_sector_count:u64
for each logical sector: exact 2048 bytes
```

No filesystem-file reserialization is performed; ordering and otherwise-unused image bytes within the validated logical extent remain identity-bearing.

### 12.4 PSP UMD

```text
platform_id: sony.psp
content_type: OpticalDiscUmd
support_state: Supported
identity_scheme_id: argus.content.identity.sony-psp.umd.v1
identity_revision: 1
accepted_source_representations: iso-2048, cso, chd-umd
```

Recognition validates UMD/ISO9660 structures and PSP game metadata/boot structures rather than relying on `.iso`/`.cso` naming.

Canonical representation is:

```text
"ARGUS-PSP-UMD-V1"
logical_sector_count:u64
for each logical sector: exact 2048 bytes
```

CSO is a storage representation only: decompression must reproduce the exact ISO logical-sector stream. Compression level/index layout does not enter identity.

## 13. Nintendo Optical Catalog

### 13.1 GameCube

```text
platform_id: nintendo.gamecube
content_type: OpticalDiscGameCube
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-gamecube.disc.v1
identity_revision: 1
accepted_source_representations: raw-disc-image, rvz
```

Recognition validates GameCube disc magic/header, filesystem/boot structures, and logical image geometry.

Canonical representation is:

```text
"ARGUS-GAMECUBE-DISC-V1"
logical_disc_size:u64
complete reconstructed raw logical disc bytes
```

RVZ is accepted only when the decoder reconstructs the complete logical disc byte stream required above. RVZ compression/chunking and reversible pseudorandom-data reconstruction are transport details. Any representation that cannot reproduce every canonical byte is unsupported by this GameCube v1 row; Argus does not infer or zero missing bytes to force convergence.

### 13.2 Wii

```text
platform_id: nintendo.wii
content_type: OpticalDiscWii
support_state: Supported
identity_scheme_id: argus.content.identity.nintendo-wii.disc.v1
identity_revision: 1
accepted_source_representations: raw-disc-image, rvz, wbfs
```

Recognition validates Wii disc magic/header, partition tables, partition extents, and source-representation geometry.

Wii v1 uses an explicit sparse logical-disc envelope so Argus never needs to decrypt partitions, infer scrubbed filesystem usage, or synthesize bytes that the source representation discarded:

```text
"ARGUS-WII-DISC-V1"
logical_disc_size:u64
present_extent_count:u32
for each present extent in raw logical-disc address order:
    start_offset:u64
    length:u64
    exact reconstructed bytes
```

A complete raw image contributes one complete logical extent. An RVZ source contributes the same complete extent only when its decoder reconstructs the full logical disc bytes; transport compression and reversible pseudorandom-data reconstruction do not enter identity. A WBFS source contributes only the raw logical extents actually preserved by its allocation map after structural validation.

Argus does not use Wii title/common keys to derive a scrub map, does not decrypt partitions to decide which omitted sectors were semantically unused, and does not replace absent WBFS data with guessed zeroes. Therefore ordinary scrubbed WBFS is a Supported Wii representation with a strong sparse-content identity, but it is not promised to converge with a complete raw/RVZ image of the same release. Such representations may still group under one `Game` later through trustworthy release/provider evidence. Two WBFS sources converge only when their canonical sparse extent map and all preserved bytes match.

Technical basis: Dolphin WIA/RVZ format documentation and Wii-disc image handling semantics.

## 14. Generic Archive and Stream Wrappers

### 14.1 Supported wrappers

Phase 003 supports these generic wrappers as derived-container transformations, not identity schemes:

```text
zip
sevenzip
rar
tar
gzip
bzip2
xz
```

Single-stream compressors expose one decompressed child. Tar-family archives expose validated member entries. ZIP/7z/RAR expose bounded member scopes.

Archive container bytes, timestamps, compression levels, filenames, comments, directory-entry order, and compressor implementation do not enter the inner game's `ContentIdentity` except when a downstream native format itself defines some derived byte as content.

### 14.2 Single-game rule

A generic archive is eligible for Phase 003 identification only when bounded enumeration establishes exactly one independently usable game/content family, including any required companion files of one multi-file content unit.
That one game family may contain multiple independently usable discs only when explicit validated relationship evidence such as M3U ties those discs to one release; each disc still becomes its own `GameContent` under the owning optical scheme.


Allowed:

```text
game.zip -> game.gba
ps1-game.7z -> game.cue + track01.bin + track02.bin
multi-disc-game.7z -> game.m3u + disc1.cue/bin + disc2.cue/bin
```

Rejected atomically:

```text
collection.zip -> mario.nes + zelda.nes
```

When multiple independently usable games exist:

- no member `GameContent` is materialized from that archive;
- no "first entry" rule exists;
- the archive receives a typed unsupported-multi-game-container result;
- unrelated refresh work may continue.

### 14.3 Nested wrappers

Nested wrapper paths are Supported only when each edge is an explicitly registered transformation and the entire chain runs inside one cumulative BE-012 `ParsingSession` resource budget.

Every level shares expansion, staging, entry-count, nesting-depth, representation-size, parser-work, and cancellation accounting. A nested level never receives a fresh budget.

## 15. Alternate Disc Representations

### 15.1 CHD

CHD is a Supported source representation only where its decoded media plus metadata can reproduce the owning platform scheme's canonical disc envelope exactly. Representation identifiers remain media-semantic rather than generic container labels:

- `chd-cd` reproduces the canonical CD session/track envelope, including stored-versus-synthesized pregap semantics and canonical sector payloads;
- `chd-gd` reproduces the Dreamcast GD session, density, track, and canonical sector envelope;
- `chd-dvd` reproduces the exact PlayStation 2 DVD 2048-byte logical-sector stream;
- `chd-umd` reproduces the exact PSP UMD 2048-byte logical-sector stream.

A CHD whose media metadata cannot establish the required owning representation is unsupported rather than interpreted from extension or folder placement. CHD compression/hunk layout is never identity-bearing.

### 15.2 RVZ

RVZ is limited to GameCube/Wii applicability. Its compression, chunk size, packing, and metadata layout are transport details. For GameCube and complete Wii representations, identity is computed after reconstruction of the full owning logical-disc byte stream. A representation that cannot reconstruct required canonical bytes is not silently treated as equivalent.

### 15.3 CSO

CSO is PSP-only in Phase 003 and must decompress to the exact canonical UMD 2048-byte logical-sector stream.

### 15.4 WBFS

WBFS is Wii-only in Phase 003. It participates through the Wii sparse logical-disc contract: the validated allocation map determines which raw logical extents are present, and only those exact preserved bytes enter the sparse identity envelope. WBFS container/header/allocation-table bytes are not hashed as game payload, and missing extents are not reconstructed through decryption, filesystem-use inference, or zero filling.

### 15.5 M3U

M3U is relationship/discovery evidence only:

```text
support_state: ExplicitlyExcluded
```

A validated M3U may supply Phase 003 Game-grouping evidence for ordered member discs. It never alters the `ContentIdentity` of those discs and never creates one combined multi-disc `GameContent`.

## 16. Explicit Exclusions

The following are outside the current catalog:

- arcade/MAME/FBNeo ROM-set semantics;
- Switch, Wii U, PS3, PS4, PS5, Vita, current Xbox families;
- encrypted/key-dependent Nintendo 3DS content requiring external/user key material;
- CIA installation packages requiring title-key/install semantics;
- multi-game generic archives;
- disc images whose required subchannel/protection information is not represented by the v1 canonical disc contract;
- GameCube alternate representations that cannot reconstruct every required canonical byte;
- NKit or other transforms whose original/canonical required bytes cannot be deterministically reconstructed under an owning scheme;
- arbitrary executable/folder dumps that are not a supported console media representation.

## 17. Provenance Requirements

Every identity computation records exact BE-012 `ContentIdentityProvenance` for all source entries and transformations that established the canonical content unit.

Examples:

```text
single cartridge:
  source ROM -> validated cartridge transform -> canonical content

CUE/BIN:
  CUE descriptor + every consumed track file -> canonical disc

archive:
  outer archive source -> derived child evidence -> native cartridge/disc dependencies

RVZ/CSO/WBFS/CHD:
  container source -> decoder transform -> canonical owning disc representation
```

A later source association is not current proof merely because it looks equivalent; it must independently establish a valid current identity/provenance basis.

## 18. Failure Semantics

Catalog-specific failures map through BE-012 to the exact SPEC-BE-003 Phase 003 codes:

```text
ARGUS.V1.VALIDATION.CONTENT_UNSUPPORTED_REPRESENTATION
ARGUS.V1.VALIDATION.CONTENT_ENCRYPTED_UNSUPPORTED
ARGUS.V1.VALIDATION.MULTI_GAME_CONTAINER_UNSUPPORTED
ARGUS.V1.VALIDATION.CONTENT_MALFORMED
ARGUS.V1.FILESYSTEM.CONTENT_DEPENDENCY_MISSING
ARGUS.V1.VALIDATION.CONTENT_RECOGNITION_AMBIGUOUS
ARGUS.V1.OPERATION.TRANSFORMATION_RESOURCE_LIMIT_EXCEEDED
ARGUS.V1.OPERATION.CONTENT_REIDENTIFICATION_REQUIRED
```

A recognized malformed/unsupported representation does not fall through to an unrelated parser. Filename/provider hints never rescue failed authoritative recognition.

## 19. Concurrency and Cancellation

BE-012 remains authoritative.

All canonicalization work occurs outside long database write transactions. Cancellation is checked at bounded parser/decompression/staging/hash checkpoints. No cancelled, changed, indeterminate, resource-exhausted, or partially decoded input may persist a new current identity.

Concurrent computations of the same canonical `(scheme_id, identity_value)` converge through the BE-012 persistence uniqueness contract.

## 20. Security and Privacy

- No supported scheme requires network access.
- No supported scheme sends content bytes or identifiers externally.
- No supported scheme requires user-supplied decryption keys.
- Container entry paths are untrusted and cannot escape staging/source boundaries.
- Decompression and virtual-disc decoding are bounded by the BE-012 session budget.
- ROM/disc bytes and opaque source locators must not be logged.
- Parser/reference-tool output is untrusted until converted into application-owned validated facts.

## 21. Performance Requirements

Identity is correctness-first but must remain streamable/bounded:

- SHA-256 is computed incrementally; canonical images need not be buffered wholly in RAM.
- Byte-order transforms, archive decompression, and disc reconstruction stream where their format permits.
- Seek/random-access requirements use BE-012 disk-backed staging instead of mandatory whole-image RAM buffering.
- One parsing session reuses compatible decoded/canonical representations across identity and other requested hash work.
- Generic archives and nested containers enforce cumulative finite limits.

## 22. Qualification Contract

Every Supported catalog entry requires deterministic, redistributable fixtures covering:

1. positive authoritative recognition;
2. canonical identity stability;
3. distinct-content separation;
4. malformed/truncated rejection;
5. ambiguous-platform failure where applicable;
6. source mutation -> stale/re-identification behavior;
7. cancellation at a meaningful processing checkpoint;
8. representation convergence where this specification promises it;
9. representation non-convergence where semantic bytes differ;
10. exact provenance roles for multi-entry content.

Additional required coverage:

- NES: NES 2.0/iNES semantic-header normalization and ambiguous mapper cases;
- FDS: headered/headerless convergence and ordered side changes;
- SNES: copier-header stripping, explicit interleaved-layout rejection, and LoROM/HiROM/ExHiROM ambiguity;
- GB/GBC: CGB classification and declared ROM extent;
- GBA: malformed logo/header/complement checks;
- N64: all accepted byte orders converge;
- NDS: used-ROM extent/padding behavior and malformed region declarations;
- 3DS: NCSD with all identity-bearing NCCH partitions explicitly `NoCrypto` as positive vectors, plus encrypted, contradictory-flag, and merely partially decrypted negative vectors;
- CD platforms: track ordering, modes, pregaps, audio/data distinction, missing/conflicting descriptor dependencies;
- Dreamcast: GDI/CUE/CHD-GD convergence when each representation reconstructs the complete session/density/track envelope, plus rejection of missing high-density or contradictory session geometry;
- PS2: CD vs DVD content-type separation, and ISO-2048/CHD-DVD convergence for a fabricated DVD logical-sector stream with rejection of a CHD whose media profile cannot reproduce that stream;
- PSP: ISO-2048/CSO/CHD-UMD convergence for the same fabricated UMD logical-sector stream, plus rejection of wrong-media CHD metadata and truncated CSO indexes;
- GameCube: raw/RVZ convergence when RVZ reconstructs every canonical byte, plus rejection of representations that cannot reconstruct the complete logical disc;
- Wii: raw/RVZ convergence when RVZ reconstructs the complete synthetic disc, deterministic WBFS sparse-extent identity, matching-WBFS convergence, and proof that scrubbed WBFS is not falsely equated with a complete raw/RVZ image;
- generic archives: traversal-like paths, extreme declarations, nesting, multi-game rejection, cancellation, and budget exhaustion.

No test fixture may require copyrighted commercial ROM/disc content. Synthetic media must contain only the minimum fabricated structures/bytes required to exercise the contract.

## 23. Architecture Tests

Architecture/static checks must prevent:

- provider/native metadata from becoming identity authority;
- runtime code selecting format-specific schemes outside the immutable catalog;
- parser libraries leaking types into domain/application public contracts;
- multiple current identity schemes for one cataloged `(PlatformId, ContentType)`;
- archive/container bytes being hashed directly as canonical game identity;
- M3U becoming a standalone `GameContent` identity;
- encrypted 3DS content silently invoking key acquisition;
- platform-specific Flutter/native code defining identity policy.

## 24. Acceptance Criteria

SPEC-BE-014 is satisfied when:

1. Every Phase 003 Nintendo/Sega/Sony product target is represented by a Supported catalog entry or explicit exclusion consistent with PHASE-003.
2. Every Supported `(PlatformId, ContentType)` has exactly one current `scheme_id`.
3. Every current scheme uses SHA-256 over an exact immutable canonical logical representation.
4. Every scheme has `identity_revision = 1` at initial activation.
5. Authoritative recognition is independent of filename/folder/provider metadata.
6. NES/FDS/SNES/N64 normalization rules distinguish transport representation from semantic content.
7. Key-free 3DS support is restricted to structurally valid NCSD content whose identity-bearing NCCH partitions explicitly prove `NoCrypto`; encrypted/CIA inputs remain excluded.
8. CD/GD/DVD/UMD canonical envelopes define deterministic track/sector ordering and dependency handling.
9. Independently usable discs remain separate `GameContent` entities.
10. Generic archives are single-game only and reject multi-game contents atomically.
11. CHD/RVZ/CSO/WBFS participate only through owning platform canonical representations.
12. M3U is relationship evidence only.
13. Nested transformations remain cumulatively bounded and cancellable under BE-012.
14. Every claimed representation equivalence has deterministic convergence tests.
15. Unsupported/lossy/ambiguous representations fail rather than weaken canonical identity.
16. Desktop and Android share identical identity semantics.
17. BE-012 remains the generic transformation/identity authority and this catalog contains no Game/provider/UI ownership.

## 25. Prohibited Patterns

- deriving platform from extension/folder name;
- hashing the ZIP/7z/RAR/CHD/RVZ/CSO/WBFS container bytes as logical game identity;
- using provider/RetroAchievements IDs as `ContentIdentity`;
- treating iNES/NES 2.0 transport headers as opaque identity bytes without semantic normalization;
- choosing N64 byte order from filename extension;
- silently trimming unknown cartridge bytes;
- choosing the first file from a multi-game archive;
- concatenating arbitrary companion files;
- making a playlist one multi-disc identity;
- decrypting/inferencing Wii partition usage or zero-filling absent WBFS extents merely to force WBFS/raw convergence;
- treating lossy/scrubbed representations as equivalent without proof;
- asking for or embedding 3DS keys;
- changing scheme semantics while retaining the same `scheme_id`;
- changing intended semantics through `identity_revision`.

## 26. Out of Scope

- concrete parser/decompression libraries;
- numeric `TransformationBudget` defaults;
- persistent parsed-representation caches;
- Game/title grouping semantics above exact content;
- provider matching/metadata/artwork;
- user manual correction;
- RetroAchievements hashing/verification;
- arcade set management;
- automatic filesystem watching.

## 27. Technical References

These references inform format semantics; Argus runtime contracts remain application-owned:

- NESdev NES 2.0: https://www.nesdev.org/wiki/NES_2.0
- NESdev FDS file format: https://www.nesdev.org/wiki/FDS_file_format
- NESdev FDS disk format: https://www.nesdev.org/wiki/FDS_disk_format
- SNESdev ROM header: https://snes.nesdev.org/wiki/ROM_header
- SNESdev ROM file formats: https://snes.nesdev.org/wiki/ROM_file_formats
- GBDev Pan Docs cartridge header: https://gbdev.io/pandocs/The_Cartridge_Header.html
- GBATEK GBA/NDS technical reference: https://problemkaputt.de/gbatek.htm
- N64 ROM formats: https://n64dev.org/romformats.html
- Genesis/Mega Drive SMD interleave reference: https://github.com/franckverrot/EmulationResources/blob/master/consoles/megadrive/genesis_rom.txt
- Sega Mega-CD Disc Format Specifications: https://segaretro.org/images/archive/a/a5/20190509114738%21Mega-CD_Disc_Format_Specifications.pdf
- Dreamcast IP0000/IP.BIN reference: https://mc.pp.se/dc/ip0000.bin.html
- PlayStation specifications/CD formats: https://psx-spx.consoledev.net/cdromfileformats/
- MAME CHD/CD metadata implementation: https://github.com/mamedev/mame/blob/master/src/lib/util/chd.cpp and https://github.com/mamedev/mame/blob/master/src/lib/util/cdrom.cpp
- PS2 SYSTEM.CNF: https://www.psdevwiki.com/ps2/System.cnf
- Dolphin WIA/RVZ format: https://github.com/dolphin-emu/dolphin/blob/master/docs/WiaAndRvz.md
- WBFS allocation/used-block reference implementation: https://github.com/wiidev/usbloadergx/blob/enhanced/source/libs/libwbfs/libwbfs.c and https://github.com/wiidev/usbloadergx/blob/enhanced/source/libs/libwbfs/wiidisc.c
- 3dbrew NCSD/NCCH documentation: https://www.3dbrew.org/wiki/NCSD and https://www.3dbrew.org/wiki/NCCH

## 28. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-003 — Game Identification and Enrichment](../../phases/phase-003-game-identification-and-enrichment.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-BE-012 — Transformation and Hash-Scheme Contract](spec-be-012-transformation-and-hash-scheme-contract.md)
- [SPEC-BE-013 — Library Source Management, Scan Operations, and Source Projections](spec-be-013-library-source-management-scan-operations-and-source-projections.md)
