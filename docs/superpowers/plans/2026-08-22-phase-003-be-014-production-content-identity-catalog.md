# Phase 003 BE-014 Production Content Identity Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a reviewable `SPEC-BE-014 — Production Content Identity Catalog` that converts BE-012's generic identity architecture into an exact Phase 003 production platform/content/representation catalog without implementing production parser code.

**Architecture:** Keep `SPEC-BE-012` authoritative for generic transformation, recognition, `ContentIdentity`, provenance, migration, and resource-safety semantics. Add BE-014 as the closed production catalog that names the supported `PlatformId`/`ContentType` rows, immutable identity-scheme semantics, accepted source representations, canonical logical representations, SHA-256 identity rules, qualification obligations, and explicit unsupported cases. Amend BE-012 and `ARCH-001` only where necessary to point to the catalog and remove deferrals that BE-014 resolves; Game grouping, providers, Library UX, and composed refresh remain owned by later Phase 003 contract plans.

**Tech Stack:** Markdown specifications, repository documentation conventions, authoritative public format specifications/reference implementations used only as cited research inputs; no production Rust/Flutter changes in this plan.

**Spec:** `docs/superpowers/specs/2026-08-22-phase-003-game-identification-and-enrichment-design.md`

## Global Constraints

- `SPEC-BE-012` remains authoritative for the generic transformation and identity architecture; BE-014 must specialize it, not fork or restate it inconsistently.
- Every Phase 003-advertised `(PlatformId, ContentType, representation)` must resolve to one exact supported catalog row or an explicit excluded/unsupported row; recognition-only capability does not count as supported.
- Argus owns canonical logical content identity. Each active production identity scheme ends in SHA-256 over the scheme-defined canonical logical representation.
- External CRC32, MD5, SHA-1, RetroAchievements, DAT, and provider hashes remain separate `HashRecord` contracts and must not become Argus `ContentIdentity` merely for interoperability convenience.
- Scheme semantics are immutable: semantic changes require a new `scheme_id`; implementation corrections that preserve intended semantics use `identity_revision`.
- Filenames, extensions, directory placement, and provider metadata may narrow transformation planning but never establish authoritative platform/content identity.
- Independently usable discs remain separate `GameContent` entities. M3U may provide relationship evidence but never creates one giant multi-disc `GameContent`.
- General ZIP/7z/RAR archives are single-game only in Phase 003. Multiple independently usable games inside one archive are rejected atomically for identification; Argus must not select the first entry or expand one archive into many games.
- Archive/container recursion, staging, expansion, parser work, and cancellation remain governed by the cumulative BE-012 `ParsingSession` resource model.
- Nintendo 3DS support is limited to content that can be authoritatively recognized and canonicalized without user-supplied decryption keys.
- Arcade/MAME/FBNeo semantics are excluded.
- Do not introduce provider matching, `Game` grouping, metadata, artwork, Library UI, RetroAchievements verification, or composed refresh semantics into BE-014.
- Do not leak Phase/Slice identifiers into runtime/public scheme names. Scheme IDs must describe immutable content semantics, not project scheduling.
- Do not choose concrete parser libraries in BE-014 unless the identity semantics genuinely depend on a public format contract that cannot be expressed independently of an implementation.
- External research is evidence, not authority inside runtime APIs. Cite primary format specifications or mature reference implementations where they materially justify canonicalization rules.
- If research cannot establish one trustworthy key-free canonical identity contract for an advertised row, do not guess. Record the evidence gap and surface that row as the only blocking design issue rather than weakening BE-012.
- This plan produces a **Draft** BE-014 for Daniel's review. Do not mark BE-014, PHASE-003, or any Phase 003 readiness checklist item Ready/complete without that explicit review.
- Do not stage, commit, push, restore, or discard unrelated owner worktree changes during execution.

---

## File Structure and Ownership Map

Expected documentation ownership after this plan:

- `docs/specifications/backend/spec-be-014-production-content-identity-catalog.md` — new normative production identity catalog; exact supported platform/content/representation rows, scheme semantics, qualification requirements, and exclusions.
- `docs/specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md` — generic identity architecture; receives only a narrow production-catalog linkage, Phase 003 activation note, and removal of deferrals now owned by BE-014.
- `docs/architecture/architecture-overview.md` — top-level architecture; receives a concise Phase 003 identity-catalog statement and the approved SHA-256-over-canonical-representation rule, without duplicating the entire matrix.
- `docs/specifications/backend/README.md` — adds BE-014 to the backend index with `Draft` status.
- `docs/phases/phase-003-game-identification-and-enrichment.md` — inspect for consistency only in this plan. Do not check off BE-014 readiness or change PHASE-003 status until Daniel reviews the resulting spec.
- `docs/superpowers/specs/2026-08-22-phase-003-game-identification-and-enrichment-design.md` — read-only design authority for this plan.

Do not modify BE-004/005/008/009/010/013, FE-003/004/008/009, or any Rust/Flutter source in this plan. Those changes belong to later focused contract/implementation plans.

---

### Task 1: Establish the BE-014 Contract Skeleton and Catalog Vocabulary

**Files:**
- Create: `docs/specifications/backend/spec-be-014-production-content-identity-catalog.md`
- Inspect: `docs/templates/subsystem-specification.md`
- Inspect: `docs/specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md`
- Inspect: `docs/superpowers/specs/2026-08-22-phase-003-game-identification-and-enrichment-design.md`
- Inspect: `docs/phases/phase-003-game-identification-and-enrichment.md`

**Interfaces:**
- Consumes: BE-012 generic `ContentIdentitySchemeDescriptor`, `RecognizedContent`, `ContentUnit`, `ParsingSession`, `ContentIdentity`, and identity-revision semantics.
- Produces: the exact vocabulary later catalog rows use: canonical platform IDs, content classes, source-representation names, scheme IDs, qualification state, and unsupported-row classification.

- [ ] **Step 1: Create BE-014 with governed metadata and Draft status.** Use this exact header shape:

```markdown
# Production Content Identity Catalog Specification

**Document ID:** SPEC-BE-014  
**Status:** Draft  
**Owner:** Daniel  
**Last Updated:** 2026-08-22  
**Depends On:** ARCH-001, ARCH-002, PHASE-003, SPEC-BE-011, SPEC-BE-012, SPEC-BE-013  
**Supersedes:** None  
**Superseded By:** None
```

- [ ] **Step 2: State BE-014's governing boundary.** The Purpose/Responsibilities sections must say, normatively, that BE-012 defines *how* transformations and identities work, while BE-014 defines *which* production content classes Argus supports and the immutable semantics of each current production identity scheme. Explicitly prohibit BE-014 from owning parser implementation classes, provider matching, Game grouping, metadata/artwork, or UI behavior.

- [ ] **Step 3: Define one closed catalog-row schema used consistently throughout the document.** Use a conceptual structure equivalent to:

```text
ProductionContentIdentityCatalogEntry
- platform_id
- content_type
- support_state
- accepted_source_representations[]
- canonical_representation
- identity_scheme_id
- identity_revision
- digest_algorithm = SHA-256
- required_dependencies[]
- normalization_rules
- equivalent_representation_rules
- rejection_rules
- qualification_requirements[]
```

`support_state` must be a closed specification concept with only:

```text
Supported
ExplicitlyExcluded
```

Do not add a product-visible "experimental" or "best effort" support tier. An advertised row is Supported only when its complete qualification contract exists.

- [ ] **Step 4: Define stable identifier rules.** BE-014 must establish that `PlatformId`, `ContentType`, accepted-representation identifiers, and `scheme_id` are application-owned stable identifiers. Scheme IDs must follow one descriptive versioned convention such as:

```text
argus.content.identity.<platform-or-family>.<content-class>.v1
```

The final strings written into the catalog must be explicit and unique. They must not contain `phase-003`, `p03`, slice IDs, parser-library names, provider names, or current filenames/extensions unless the representation itself is semantically part of the scheme.

- [ ] **Step 5: Define initial revision/digest rules.** Every new Phase 003 scheme starts with `identity_revision = 1` unless BE-014 documents an existing earlier production implementation that requires another value. Every current identity scheme uses SHA-256 over its canonical logical representation. Explain that SHA-256 uniformity does not imply uniform canonicalization.

- [ ] **Step 6: Add explicit support-advertising rules.** State all of the following:

```text
Recognized but no current identity scheme -> not advertised as supported.
Parser can open format but canonical identity is unresolved -> not advertised as supported.
Key-dependent/encrypted input without approved key-free canonicalization -> ExplicitlyExcluded.
Supported alternate packaging -> must converge when BE-014 claims logical equivalence.
Unsupported alternate packaging -> must fail as unsupported, never create packaging-sensitive canonical identity accidentally.
```

- [ ] **Step 7: Self-check the skeleton before filling rows.** Verify the document has no `TBD`, `TODO`, unresolved template prompts, speculative runtime APIs, or naming that leaks project scheduling into durable identifiers.

---

### Task 2: Define the Cartridge and Handheld Production Identity Matrix

**Files:**
- Modify: `docs/specifications/backend/spec-be-014-production-content-identity-catalog.md`
- Research/read as needed: authoritative public format specifications and mature emulator/reference implementation documentation for the listed platforms

**Interfaces:**
- Consumes: Task 1 catalog schema and BE-012 authoritative-recognition rules.
- Produces: complete current identity entries for the cartridge/handheld portion of the approved Phase 003 platform roster.

- [ ] **Step 1: Create the exact cartridge/handheld platform inventory.** The catalog must account for these approved product targets, using one canonical Argus `PlatformId` per logical platform and documenting aliases only as display/provider aliases:

```text
Nintendo: NES/Famicom, Famicom Disk System, SNES/Super Famicom,
Game Boy, Game Boy Color, Game Boy Advance, Nintendo 64,
Nintendo DS, Nintendo 3DS key-free subset

Sega: Master System, Game Gear, Genesis/Mega Drive, 32X
```

Famicom and NES share a platform identity only if the content-recognition/canonicalization semantics are genuinely the same; FDS must remain a distinct content class/platform identity when its disk semantics differ. Apply the same rule to regional marketing aliases such as Genesis/Mega Drive.

- [ ] **Step 2: For every platform, cite enough technical evidence to define authoritative recognition independently of filename extension.** For each row document the structural/header/magic/size/consistency evidence that a validating transformation must establish before producing `(PlatformId, ContentType)`. A file extension may appear only under `accepted_source_representations` or planning hints, never as authoritative recognition evidence.

- [ ] **Step 3: Define the canonical logical representation for every supported native form.** For each row answer all of these explicitly:

```text
What exact bytes/structured fields constitute canonical logical content?
Which packaging/header bytes are excluded, normalized, or retained?
Is byte order normalized before hashing?
Is interleaving/deinterleaving part of canonicalization?
Are padding/trailing bytes semantically retained or rejected?
What multi-entry dependencies, if any, participate?
What malformed/ambiguous states block identity?
```

Do not use a generic phrase such as "normalized ROM bytes" without specifying the normalization.

- [ ] **Step 4: Define equivalence and non-equivalence examples for every normalization rule.** Each row must include at least one normative example of two accepted source representations that *must* converge when alternate encodings exist, and at least one example that *must not* converge when semantic content differs. Examples use fabricated values/descriptions only; do not embed copyrighted ROM bytes.

- [ ] **Step 5: Resolve Nintendo 3DS explicitly.** Document exactly which key-free content form(s), if any, can satisfy authoritative recognition and canonical identity without user-supplied decryption material. Any encrypted/key-dependent forms outside that proof are `ExplicitlyExcluded`. If no trustworthy key-free supported row can be established from authoritative evidence, stop and surface 3DS as the single blocking design issue instead of inventing a scheme.

- [ ] **Step 6: Add qualification obligations per row.** Every Supported entry must require deterministic vectors for recognition, canonical identity stability, distinct-content separation, malformed/ambiguous failure, source mutation/re-identification, and alternate-representation convergence where applicable.

- [ ] **Step 7: Run a matrix completeness check.** Every cartridge/handheld target from Step 1 must be either represented by at least one Supported entry or explicitly excluded with a concrete reason consistent with the approved Phase 003 design. No target may disappear silently.

---

### Task 3: Define the Optical Disc, Multi-File, and Multi-Disc Identity Matrix

**Files:**
- Modify: `docs/specifications/backend/spec-be-014-production-content-identity-catalog.md`
- Research/read as needed: authoritative public disc/container format specifications and mature emulator/reference implementations

**Interfaces:**
- Consumes: Task 1 catalog schema, BE-012 `ContentUnit`/multi-entry boundary, and the approved rule that independently usable discs remain separate `GameContent`.
- Produces: complete logical-disc identity entries for Sega CD, Saturn, Dreamcast, PlayStation, PlayStation 2, PSP, GameCube, and Wii.

- [ ] **Step 1: Create the exact optical-disc platform inventory:**

```text
Sega CD / Mega-CD
Sega Saturn
Sega Dreamcast
Sony PlayStation
Sony PlayStation 2
Sony PSP
Nintendo GameCube
Nintendo Wii
```

- [ ] **Step 2: Define canonical logical disc semantics before alternate compression/container forms.** For each platform/content class, specify the ordered logical representation consumed by SHA-256 independently of CUE/BIN, ISO, CHD, RVZ, CSO, or WBFS packaging. The contract must explicitly define which tracks/sectors/filesystem bytes/metadata participate and in what order. If two physical formats cannot be proven losslessly equivalent under one canonical logical representation, do not promise convergence between them.

- [ ] **Step 3: Define descriptor/track dependency semantics.** For CUE/BIN or equivalent multi-file layouts, document:

```text
descriptor recognition and validation
referenced-track resolution
required vs optional files
logical track ordering
mode/sector interpretation
missing/conflicting dependency failure
exact ContentIdentityProvenance roles expected from BE-012
```

The descriptor filename or track filename cannot establish identity by itself.

- [ ] **Step 4: Define independently usable disc behavior.** One disc produces one `GameContent`. Multi-disc title/release grouping is explicitly outside BE-014. M3U may be cataloged as relationship/discovery evidence, but the playlist must not alter the canonical identity of the member discs or create a combined multi-disc identity scheme.

- [ ] **Step 5: Define native ISO applicability precisely.** Do not treat every `.iso` as interchangeable. State for each platform when an ISO-like representation is a complete supported logical disc representation, when raw/subchannel/multi-track information is required, and when an ISO input must be rejected as insufficient or unsupported.

- [ ] **Step 6: Add per-row deterministic qualification requirements.** Include track ordering, missing dependency, conflicting descriptor, truncated image, wrong-platform structurally valid image, source mutation, cancellation during canonicalization, and distinct-disc separation where applicable.

- [ ] **Step 7: Verify cross-platform ambiguity handling.** If the same physical representation can parse validly for more than one platform/content class, the catalog must require validated transformation evidence that disambiguates it or BE-012 `AmbiguousContentRecognition`; it must never authorize extension/folder/provider-based guessing.

---

### Task 4: Define Packaging, Compression, Archive, and Container Applicability

**Files:**
- Modify: `docs/specifications/backend/spec-be-014-production-content-identity-catalog.md`

**Interfaces:**
- Consumes: native/canonical content entries from Tasks 2–3 and BE-012 derived-container/resource-budget contracts.
- Produces: exact rules for ZIP, 7z, RAR, supported stream/tar-family forms, CHD, RVZ, CSO, WBFS, and M3U without allowing packaging to become canonical identity accidentally.

- [ ] **Step 1: Separate generic packaging from platform-specific alternate representations.** BE-014 must distinguish:

```text
Generic archive wrappers: ZIP, 7z, RAR, supported single-stream/tar-family forms
Platform-specific lossless/semantic representations: CHD, RVZ, CSO, WBFS
Relationship descriptors: M3U
```

Generic archive wrappers expose inner content to the applicable native identity scheme; archive bytes themselves are not `ContentIdentity` input.

- [ ] **Step 2: Specify the single-game archive contract exactly.** A Supported archive path may contain one independently usable game/content family plus files required by that family's multi-file representation. If enumeration reveals more than one independently usable game, identification for that archive is rejected atomically. No member `GameContent` is materialized from that archive in Phase 003.

- [ ] **Step 3: Specify nested-container applicability.** Nested containers are supported only for explicitly registered transformation paths, share one cumulative `ParsingSession` budget, and may not obtain fresh expansion/staging/nesting limits per level. Resource-limit exhaustion is a typed failure and never authorizes truncated recognition or derived absence.

- [ ] **Step 4: Define CHD applicability per supported optical platform.** For each platform that accepts CHD, document the exact requirement for decoding to the already-defined canonical logical disc representation and the conditions under which CUE/BIN/native disc and CHD must converge. Do not define a separate CHD-byte identity.

- [ ] **Step 5: Define RVZ applicability for GameCube/Wii, CSO for PSP, and WBFS for Wii.** Each rule must state whether the representation is lossless enough for the promised canonical identity, how logical bytes are obtained, and what metadata/holes/scrubbing behavior may or may not be normalized. If a representation can discard semantically relevant data such that convergence cannot be guaranteed, narrow or exclude that row rather than asserting equivalence.

- [ ] **Step 6: Define M3U as relationship evidence only.** It may help dependency discovery/grouping in later contracts but does not participate in member disc SHA-256 identity and does not create a `GameContent` by itself unless a future explicit content type supersedes this rule.

- [ ] **Step 7: Add adversarial qualification requirements.** Require deterministic synthetic tests for traversal-like entry names, extreme declared sizes, deep nesting, truncated archives/images, invalid member references, duplicate/cyclic descriptor references where applicable, multi-game archive rejection, and cancellation/resource exhaustion.

---

### Task 5: Reconcile BE-012 and ARCH-001 with the Production Catalog

**Files:**
- Modify: `docs/specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md`
- Modify: `docs/architecture/architecture-overview.md`
- Inspect: `docs/superpowers/specs/2026-08-22-phase-003-game-identification-and-enrichment-design.md`

**Interfaces:**
- Consumes: complete BE-014 Draft from Tasks 1–4.
- Produces: one non-duplicated authority chain: ARCH-001 -> BE-012 generic contract -> BE-014 production catalog.

- [ ] **Step 1: Amend BE-012 activation/scope text narrowly.** State that PHASE-003 activates concrete production transformation/identity schemes through BE-014 while BE-012 continues to own generic mechanics. Do not copy BE-014's full platform matrix into BE-012.

- [ ] **Step 2: Add a normative production-catalog linkage near BE-012 Identity Scheme Selection.** The text must establish:

```text
BE-012 defines zero-or-one current scheme selection semantics.
BE-014 is the authoritative production catalog of current supported mappings.
A row absent from / ExplicitlyExcluded by BE-014 is not a supported Phase 003 identity class.
```

- [ ] **Step 3: Resolve only BE-012 deferred decisions owned by BE-014.** In BE-012 Section 70, remove or rewrite the deferrals for `exact per-format transformation inventory` only to the extent BE-014 now owns that inventory. Leave concrete parser-library choice, numeric resource-budget defaults, `Game` grouping, metadata, RetroAchievements, watching, bridge DTOs, and other unrelated deferrals intact.

- [ ] **Step 4: Update BE-012 references.** Add PHASE-003 and BE-014 references where appropriate without changing BE-012's existing Ready status merely because a later phase activates more of it.

- [ ] **Step 5: Amend ARCH-001 content recognition/identity text concisely.** Add the approved rule that active production identity schemes use SHA-256 over scheme-defined canonical logical representations and that BE-014 is the concrete production catalog. Keep external hashes independent. Do not duplicate the full matrix or implementation detail.

- [ ] **Step 6: Check architecture direction.** Verify ARCH-001 does not depend on lower-level implementation details in prose beyond identifying BE-014 as the focused contract that realizes the architecture, and BE-014 references ARCH-001/BE-012 rather than redefining their general invariants.

---

### Task 6: Index, Cross-Document Consistency, and Review Handoff

**Files:**
- Modify: `docs/specifications/backend/README.md`
- Review: `docs/specifications/backend/spec-be-014-production-content-identity-catalog.md`
- Review: `docs/specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md`
- Review: `docs/architecture/architecture-overview.md`
- Review: `docs/phases/phase-003-game-identification-and-enrichment.md`
- Review: `docs/superpowers/specs/2026-08-22-phase-003-game-identification-and-enrichment-design.md`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: a coherent Draft BE-014 package ready for Daniel's explicit specification review; no production implementation authorization yet.

- [ ] **Step 1: Add BE-014 to the backend specification index.** Use exactly:

```markdown
| SPEC-BE-014 | [Production Content Identity Catalog](spec-be-014-production-content-identity-catalog.md) | Draft |
```

Do not change the status to Ready in this plan.

- [ ] **Step 2: Run a catalog completeness audit against the approved Phase 003 roster.** Confirm the document accounts explicitly for:

```text
Nintendo: NES/Famicom/FDS, SNES, GB, GBC, GBA, N64, DS, key-free 3DS, GameCube, Wii
Sega: Master System, Game Gear, Genesis/Mega Drive, Sega CD, 32X, Saturn, Dreamcast
Sony: PlayStation, PlayStation 2, PSP
Packaging/relationship forms: ZIP, 7z, RAR, supported stream/tar-family, CHD, RVZ, CSO, WBFS, native ISO/disc, CUE/BIN-equivalent, M3U
```

Every item must be mapped to Supported entries or an explicit evidence-backed exclusion. Arcade must remain excluded.

- [ ] **Step 3: Run an invariant audit.** Search BE-014/BE-012/ARCH-001 and verify no text implies any of the following:

```text
filename/extension establishes platform identity
provider ID establishes GameContent identity
archive bytes are canonical game identity
multi-game archive yields multiple GameContent in Phase 003
M3U creates a combined multi-disc GameContent
external CRC/MD5/SHA1/RA hash is the Argus canonical identity
identity scheme semantics can change without a new scheme_id
identity_revision changes intended semantics
unsupported encrypted 3DS input is guessed or silently accepted
```

- [ ] **Step 4: Run a placeholder/status audit.** Search the changed documents for `TBD`, `TODO`, unresolved bracketed template prompts, `Ready for Implementation` on BE-014, and accidental PHASE-003 readiness changes. BE-014 must remain Draft for owner review.

- [ ] **Step 5: Run repository validation.** Execute:

```bash
just check
```

Expected: PASS. If validation fails for an unrelated pre-existing reason, report the exact failing gate and do not edit unrelated code to make a documentation task pass.

- [ ] **Step 6: Review the final diff.** The only intended changed paths are:

```text
docs/specifications/backend/spec-be-014-production-content-identity-catalog.md
docs/specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md
docs/architecture/architecture-overview.md
docs/specifications/backend/README.md
```

If another file proves necessary to correct a direct contradiction introduced by these edits, stop and request a bounded scope amendment before editing it.

- [ ] **Step 7: Produce the implementation result/handoff without Git mutation.** Report:

```text
BE-014 status: Draft
Supported/excluded row count by platform
Any platform/representation blocked by insufficient canonicalization evidence
Exact changed paths
just check result
No production code changed
No stage/commit/push performed
```

Daniel reviews the written BE-014 after this plan. Only after explicit approval should a follow-up documentation change mark BE-014 `Ready for Implementation`, update its backend index status, and check the corresponding PHASE-003 readiness item.

---

## Self-Review Checklist for This Plan

Before execution, confirm:

1. **Spec coverage:** Tasks cover BE-014 vocabulary, the entire approved Nintendo/Sega/Sony roster, disc/multi-file semantics, approved packaging/container forms, SHA-256 identity, key-free 3DS limitation, single-game archive policy, qualification requirements, BE-012 linkage, ARCH-001 linkage, and Draft review handoff.
2. **Ownership:** No Task defines `Game`, provider resolution, metadata/artwork, Library UI, or refresh workflow behavior that belongs to BE-015/FE-010.
3. **No placeholders:** The executor has an exact catalog schema, exact target roster, exact invariants, exact intended files, and a precise rule for unresolved format evidence.
4. **Status discipline:** The plan does not claim BE-014 or PHASE-003 is Ready before Daniel reviews the exact concrete scheme semantics.
5. **Type/term consistency:** `ContentIdentityScheme`, `scheme_id`, `identity_revision`, `ContentIdentity`, `GameContent`, `ContentUnit`, `ParsingSession`, `RecognizedContent`, and `HashRecord` semantics remain consistent with BE-012 and the approved Phase 003 design.
