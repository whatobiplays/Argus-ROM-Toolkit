# Game Identification and Enrichment

**Document ID:** PHASE-003  
**Status:** Draft  
**Owner:** Daniel  
**Last Updated:** 2026-08-22  
**Depends On:** PHASE-001, PHASE-002, ARCH-001, SPEC-BE-010, SPEC-BE-012, SPEC-BE-013  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

Phase 003 delivers the second MVP product outcome: transform the authoritative local source graph into a trustworthy, hydrated logical game Library.

It activates canonical game-content identification, durable platform-specific game grouping, production metadata/artwork providers, automatic enrichment, Library browsing, and the composed `Refresh Library` / `Refresh Game` workflows across desktop and Android.

## 2. User-Visible Outcome

When Phase 003 is complete, a user can select a library folder once and allow Argus to:

1. scan changed local sources;
2. identify supported ROM/game content with a trustworthy Argus-owned canonical identity;
3. group equivalent exact contents into one logical platform-specific game;
4. automatically source and resolve metadata and artwork from enabled usable providers;
5. progressively present games in a real Library while refresh work continues;
6. browse, search, filter, sort, inspect, and refresh individual games;
7. keep unmatched but identified games visible instead of losing content that external databases do not know about.

Library becomes the default normal product destination. Sources remains the operational storage/indexing surface; Jobs remains the authoritative background-operation history/control surface.

## 3. Dependencies

Phase 003 depends on:

- `ARCH-001` for canonical MVP architecture, provider, artwork, job, query/projection, privacy, and Flutter boundaries;
- PHASE-001 for configured roots, authoritative source indexing, `SourceEntry`, scan/job semantics, and safe absence/reconciliation;
- PHASE-002 for first-class Android runtime, storage readiness, foreground execution hosting, adaptive UX, ARM64 packaging/CI, and lifecycle invariants;
- `SPEC-BE-010` provider gateway architecture;
- `SPEC-BE-012` transformation and hash-scheme architecture;
- `SPEC-BE-013` source management/scan contracts;
- existing runtime, persistence, bridge, frontend-state, routing, design-system, Sources, and Jobs contracts.

Before implementation begins, Phase 003 additionally requires the focused specifications and amendments in Section 7 to reach their required readiness state.

## 4. In Scope

### 4.1 Canonical identification

- Concrete production `ContentIdentityScheme` catalog for every advertised supported `(PlatformId, ContentType)`.
- SHA-256 over each scheme-defined canonical logical representation.
- Stable scheme IDs and identity revisions.
- Exact identity provenance and reidentification semantics.
- Multi-file content where required by platform formats.
- Duplicate physical/source representation convergence.

### 4.2 Logical Library domain

- Durable `Game` above `GameContent`.
- Explicit `GameMembership` and conservative evidence-based grouping.
- One `Game` per platform-specific logical game.
- Regional/revision/equivalent representation/multi-disc grouping where trustworthy evidence supports it.
- Orphan retention, temporary-unavailability protection, and reappearance/reconnection.
- Game-level read projections for Library browsing.

### 4.3 Platform/content coverage

Advertised platforms are:

**Nintendo:** NES/Famicom/FDS, SNES/Super Famicom, GB, GBC, GBA, N64, DS, key-free identifiable 3DS content, GameCube, Wii.

**Sega:** Master System, Game Gear, Genesis/Mega Drive, Sega CD/Mega-CD, 32X, Saturn, Dreamcast.

**Sony:** PlayStation, PlayStation 2, PSP.

The exact production matrix is `(PlatformId, ContentType, representation)` specific and must be qualified before a row is advertised.

Applicable representations include native cartridge/file images, ISO/disc images, CUE/BIN and equivalent multi-file layouts, CHD, RVZ, CSO, WBFS, ZIP, 7z, RAR, useful single-stream/tar-family containers, and M3U relationship evidence.

General archives are single-game only. Multi-game archives are rejected atomically for identification rather than expanded into multiple independent games.

### 4.4 Metadata and artwork providers

Production providers are:

- Playmatch — zero-setup matching/enrichment support;
- GameTDB — zero-setup applicable metadata/artwork;
- SteamGridDB — user-supplied API key for artwork enrichment.

Provider-native evidence is persisted separately from deterministic resolved metadata/artwork. Provider availability or mapping changes never redefine Argus canonical content identity.

### 4.5 Automatic enrichment

After successful identification, the normal composed workflow automatically performs all eligible downstream work:

```text
identify
  ↓
Game grouping
  ↓
provider matching
  ↓
metadata refresh/resolution
  ↓
artwork discovery/resolution/download
```

Provider failures are best-effort and isolated. Successful provider results remain durable; later eligible refreshes fill gaps.

### 4.6 Region and language

Global preferred region/language settings initialize from OS locale. They influence presentation only. Strong evidence from owned content outranks an unrelated locale default. Fallback is automatic.

### 4.7 Refresh workflows

- `Refresh Library` is the normal Library-wide user action and uses `EligibleOnly` behavior.
- Work is incrementally pipelined after authoritative upstream commits.
- `Refresh Game` performs focused eligible enrichment without rescanning unrelated roots.
- Game detail exposes a secondary focused Force Refresh for provider/enrichment work.
- No normal Library-wide Force Refresh is exposed.
- Add Library Folder automatically admits the appropriate full refresh after root persistence.

### 4.8 Library UX

- Library becomes the default ready-state destination.
- Primary navigation: Library, Sources, Jobs, Settings.
- Empty Library primary action: Add Library Folder.
- Grid/list, search, typed filters, stable sorting, cursor pagination, platform/source/root scopes, adaptive selection, and adaptive game detail.
- Progressive hydration keeps existing usable content interactive.
- Unmatched identified games remain visible with bounded local fallback presentation.
- Provider setup is part of guided onboarding; SteamGridDB setup is recommended but skippable.

### 4.9 Artwork

- Existing canonical artwork taxonomy remains active.
- Resolved artwork becomes Game-level presentation state with traceable provider/content provenance.
- Only resolver-selected artwork is downloaded.
- Original provider bytes are preserved in immutable content-addressed app-private storage.
- No resize/recompress/convert pipeline is added in Phase 003.

## 5. Platform Applicability

### 5.1 Shared across desktop and Android

The following are shared Rust/application capabilities:

- parsing/transformation and canonical identity;
- Game grouping;
- metadata/artwork provider gateways;
- provider readiness and credential abstraction;
- metadata/artwork resolution;
- persistence/projections;
- Refresh Library / Refresh Game semantics;
- cancellation/retry/recovery;
- search/filter/sort/pagination semantics.

### 5.2 Platform-adapted

- folder selection and filesystem/root access;
- credential-store implementation;
- application shell/navigation presentation;
- game/library layout at Compact/Medium/Expanded/Large widths;
- Android foreground execution projection;
- Android removable-media/readiness behavior;
- desktop keyboard/focus behaviors and Android touch/Back/predictive-Back behaviors.

### 5.3 Platform-specific

Android continues to require Phase 002 All-files-access readiness and may host qualifying user-admitted refreshes through the established foreground service. This hosting never becomes a second job/runtime/database authority.

### 5.4 Excluded

No Phase 003 capability is intentionally desktop-only if it is semantically applicable on Android. Platform exclusions must be explicit and justified by the relevant focused specification.

## 6. Out of Scope

Phase 003 explicitly excludes:

- RetroAchievements verification (Phase 004);
- arcade/MAME/FBNeo set semantics;
- collections and smart collections;
- manual metadata field editing;
- interactive provider-candidate matching;
- manual artwork candidate selection/locks;
- cross-platform Game grouping;
- IGDB production integration;
- ScreenScraper production integration;
- Argus-hosted provider/cloud proxy infrastructure;
- automatic background refresh timers;
- silent restart/resume of abandoned significant work;
- multi-game archive expansion;
- user-supplied decryption-key workflows for otherwise unsupported encrypted content.

Manual metadata/artwork correction is deferred to a later **MVP** phase, not post-MVP.

## 7. Required Subsystem Specifications

### 7.1 New focused specifications

The following must be written, reviewed, and reach **Ready for Implementation** before the first dependent implementation slice begins:

- `SPEC-BE-014 — Production Content Identity Catalog`
- `SPEC-BE-015 — Game Library, Grouping, and Enrichment Contract`
- `SPEC-FE-010 — Library, Game Detail, and Enrichment UX`

### 7.2 Required amendments

Targeted amendments are required to the existing owning contracts where Phase 003 activates reserved behavior:

- SPEC-BE-004 — composed refresh lifecycle/resource/cancellation semantics;
- SPEC-BE-005 — metadata/artwork/locale settings and credential-presence state;
- SPEC-BE-008 — Phase 003 DTO/event/query boundaries;
- SPEC-BE-009 — focused Library/Game/enrichment application services;
- SPEC-BE-010 — production provider activation/readiness and corrected provider-roadmap statements;
- SPEC-BE-012 — production identity-catalog linkage and Phase 003 maintenance semantics;
- SPEC-BE-013 — scan-commit interaction with composed Library refresh;
- SPEC-FE-003 — Library/Game/provider focused APIs;
- SPEC-FE-004 — Library branch/routes/default destination activation;
- SPEC-FE-008 — normal Add Library Folder → Refresh Library behavior;
- SPEC-FE-009 — presentation of Phase 003 durable operations.

The architecture overview must also be reconciled with the approved Phase 003 Game layer, provider roster, Game-level resolved artwork/metadata, single-game archive policy, Library-default navigation, and later-MVP manual-correction roadmap.

## 8. Ordered Implementation Slices

1. **P03-001 — Canonical Content and Logical Library Foundation**: establish Phase 003 persistence/domain foundations, `Game`/`GameMembership`, initial qualified simple content identity, duplicate/orphan semantics, fallback unmatched presentation, read projections, and focused Library APIs without live provider dependency.
2. **P03-002 — Metadata Providers and Automatic Hydration**: activate Playmatch, GameTDB, SteamGridDB credential/readiness, mappings, provider metadata, deterministic resolution, artwork discovery/resolution/download, immutable storage, and best-effort provider behavior.
3. **P03-003 — Library Experience and Composed Refresh**: activate Library as product home, onboarding, Add Library Folder → Refresh Library, incremental scan/identify/group/hydrate composition, Refresh Game/Force Refresh, Jobs integration, cancellation/retry/recovery, and Android foreground hosting for qualifying work.
4. **P03-004 — Cartridge and Handheld Platform Coverage**: qualify the complete cartridge/handheld-oriented Nintendo/Sega matrix through recognition, identity, grouping, provider mapping, enrichment, and Library presentation.
5. **P03-005 — Disc, Multi-File, and Multi-Disc Coverage**: establish canonical logical disc semantics and qualify Sega CD/Saturn/Dreamcast, PS1/PS2/PSP, GameCube/Wii, descriptor/track inputs, native ISO, independently identified discs, M3U evidence, and multi-disc grouping.
6. **P03-006 — Containers and Compressed Representations**: add ZIP/7z/RAR/supported stream containers and CHD/RVZ/CSO/WBFS, equivalent-representation convergence, single-game archive enforcement, multi-game rejection, nested resource limits, hostile-input safety, staging, and cancellation.
7. **P03-007 — Library Browsing and Game Detail Completeness**: complete grid/list/search/filter/sort/pagination/scopes, adaptive selection/detail, variants/discs/copies, availability, hydration/provenance/artwork detail, orphan/reappearance, and large-Library incremental projections.
8. **P03-008 — Cross-Platform Integration and Lifecycle Hardening**: harden the full capability set across desktop and Android storage, credentials, removable media, lifecycle/foreground execution, process loss, Back/predictive Back, adaptive behavior, accessibility, and single-runtime guarantees.
9. **P03-009 — Full Matrix Qualification and Phase Hardening**: complete all advertised identity rows, provider qualification, desktop/API36 ARM64 native milestones, 10,000+ synthetic Library qualification, migrations, security/redaction, generated-source verification, documentation consistency, and full `just check`; no new feature scope.

The contract/specification package in Section 7 is a readiness prerequisite, not an implementation slice.

## 9. Failure, Cancellation, and Recovery Expectations

- Provider/content failures are isolated as narrowly as correctness permits.
- Meaningful success plus incomplete requested scope uses `CompletedWithIssues`.
- One malformed/unsupported game or provider outage does not abort unrelated eligible work.
- Multi-game archives are rejected atomically for identification and never partially materialized.
- Downstream pipelined work consumes only committed authoritative upstream state.
- Accepted cancellation stops new downstream admissions and lets in-flight operations reach owning safe checkpoints.
- Already-committed coherent identity/metadata/artwork state is preserved through later cancellation.
- Half-persisted identity/grouping/resolution state is prohibited.
- Startup reconciliation performs no provider/network/parser/scan work.
- Significant work is never silently auto-resumed after process loss.
- Retry creates a new `JobRunId`, reconstructs bounded intent, re-evaluates current eligibility, and reuses valid committed work.
- Temporarily unavailable roots/removable media never gain false absence/orphan authority.

## 10. Security and Privacy Impact

Phase 003 introduces external provider sharing and remote artwork downloads.

Required rules:

1. External requests send only capability-required data; local paths, root locators, Android storage URIs, unrelated Library data, settings, and diagnostics are not transmitted.
2. Versioned privacy consent discloses transmission of file-derived identifiers to enabled providers.
3. SteamGridDB credentials are handled only through the credential service and never stored in normal settings, logs, events, diagnostics, job records, or bridge/read DTOs.
4. No application-owned IGDB/ScreenScraper secret is embedded/obfuscated in clients.
5. Provider responses and remote artwork are untrusted and strictly validated/bounded.
6. Artwork object-store paths are derived from application-owned content identity, never remote filenames/URLs.
7. Archive/container parsing enforces cumulative resource limits, safe path handling, bounded staging, and cancellation.
8. Provider work occurs only from explicit user operations; startup/migration/recovery/opening Library do not trigger autonomous significant networking.
9. Existing Phase 001/002 source-boundary, redaction, Android readiness, and app-private-storage rules remain in force.

## 11. Test Strategy

### 11.1 Deterministic gate

`just check` remains deterministic/platform-neutral and requires no network, real provider credentials, copyrighted ROM data, or developer-machine state.

It covers domain/persistence behavior, transformation/identity vectors, grouping/orphan behavior, synthetic provider adapters, metadata/artwork resolution, composed refresh with fakes, bridge/client/controller/widget behavior, generated source, and architecture checks.

### 11.2 Identity matrix

Every advertised `(PlatformId, ContentType, representation)` row has deterministic positive/negative qualification, including canonical identity, convergence where promised, distinct-content separation, malformed/ambiguous inputs, source mutation, dependency ordering, container limits, cancellation, and multi-game archive rejection where applicable.

### 11.3 Provider qualification

Playmatch, GameTDB, and SteamGridDB have deterministic offline adapter-contract tests. Separate live-provider qualification verifies current production compatibility without weakening `just check`.

### 11.4 End-to-end deterministic scenarios

Required scenarios include clean first refresh, no-op eligible refresh, one changed game, duplicates, unmatched content, partial provider failure, invalid SteamGridDB credentials, provider recovery, malformed/single-game archive behavior, multi-game rejection, cancellation through major stages, process-loss reconciliation plus explicit retry, Refresh Game, and Force Refresh.

### 11.5 Native/platform qualification

- Desktop native milestone proves real source/provider filesystem boundaries, parser/container I/O, persistence, artwork object storage, restart/cancel/no-op/mutation behavior using safe deterministic data.
- API 36 ARM64 Android milestone extends Phase 002 evidence with Library default navigation, folder-to-refresh, Android-accessible parsing/identity, app-private artwork/metadata, Activity lifecycle, foreground execution, cancellation, process loss/no silent resume, removable media, credentials, adaptive detail, and single-runtime behavior.

### 11.6 Scale

A reproducible synthetic Library with at least 10,000 identified contents verifies bounded/paged/incremental architecture and catches whole-Library Flutter loading, N+1 planning/query behavior, full projection rebuilds for one-game mutations, unbounded progress event volume, parser staging growth, and artwork concurrency errors.

## 12. Exit Criteria

Phase 003 is complete when all of the following are true:

1. The production content identity catalog defines and qualifies every advertised supported matrix row.
2. Every new `GameContent` is backed by strong current Argus-owned canonical identity and provenance.
3. Equivalent physical copies/representations converge where the applicable scheme promises convergence.
4. `Game` is the durable platform-specific Library identity above exact `GameContent`.
5. Conservative grouping correctly handles regional/revision/equivalent/multi-disc relationships and does not guess ambiguous merges.
6. Temporary root/media unavailability does not orphan games; authoritative final absence does, while preserving durable identity/enrichment for reconnection.
7. Playmatch, GameTDB, and SteamGridDB production adapters satisfy deterministic contracts and current live-provider qualification.
8. SteamGridDB credentials are stored and used only through the credential service with required redaction guarantees.
9. Provider matches never establish canonical content identity.
10. Metadata resolution is deterministic, provenance-preserving, region/language aware, and can combine fields from multiple providers.
11. Artwork discovery/resolution/download uses the canonical taxonomy, Game-level resolved presentation, resolver-selected downloads, and immutable content-addressed original bytes.
12. Unmatched but identified games appear in Library with bounded fallback presentation.
13. Library is the default ready-state destination and supports the approved grid/list/search/filter/sort/pagination/scoping contract.
14. Add Library Folder automatically starts the composed refresh after successful root admission.
15. `Refresh Library` is eligibility-driven, incremental/pipelined, bounded, cancellable, durable, and best-effort across scoped failures.
16. `Refresh Game` and focused Force Refresh work without rescanning unrelated roots.
17. Repeating an unchanged `EligibleOnly` refresh performs negligible substantive work.
18. Cancellation/restart/retry preserve committed results and never silently auto-resume significant work.
19. Android foreground hosting projects the existing Rust-owned job lifecycle and never creates a second runtime/scheduler/database authority.
20. General archives containing multiple independent games are rejected atomically for identification.
21. Archive/container parsing satisfies resource, traversal, staging, cancellation, and hostile-input requirements.
22. Phase 000–002 databases migrate without hidden identification/network/filesystem work or fabricated Game identities.
23. Game-level Library projections update incrementally and normal Flutter browsing remains paged/backend-owned.
24. Manual metadata/artwork correction remains explicitly later-MVP rather than accidentally post-MVP or implemented in Phase 003.
25. RetroAchievements, arcade, collections, cross-platform grouping, IGDB, ScreenScraper, and cloud-proxy scope remain absent.
26. `just check` passes.
27. The full identity qualification matrix passes.
28. Desktop native qualification passes.
29. API 36 ARM64 native qualification passes.
30. Current production-provider qualification passes.
31. The 10,000+ synthetic Library qualification passes.
32. Generated source is current/reproducible and architecture/redaction/privacy checks pass.
33. Required result artifacts report executed and deferred evidence truthfully.

## 13. Readiness Checklist

- [x] User-visible outcome is defined
- [x] Dependencies are available or sequenced
- [x] Scope and exclusions are explicit
- [x] Platform applicability is explicit for each substantive capability
- [x] Required public interfaces are identified at the phase/design level
- [x] Persistence impact is identified
- [x] Failure and cancellation behavior are identified
- [x] Security and privacy impact is identified
- [x] Test requirements are specified
- [x] Implementation slices are ordered
- [x] Exit criteria are measurable
- [x] No blocking phase-level product decisions remain
- [x] Daniel has accepted the capability and scope
- [ ] SPEC-BE-014 is written, reviewed, and Ready for Implementation
- [ ] SPEC-BE-015 is written, reviewed, and Ready for Implementation
- [ ] SPEC-FE-010 is written, reviewed, and Ready for Implementation
- [ ] Required existing specification amendments are written/reviewed
- [ ] Architecture-overview corrections are written/reviewed
- [ ] Cross-document consistency review is clean

**Readiness rule:** PHASE-003 remains **Draft** until the focused contract package and required amendments are complete and consistent. Implementation readiness is a deliberate documentation-state change and is not inferred from this phase design alone.

## 14. References

- `docs/superpowers/specs/2026-08-22-phase-003-game-identification-and-enrichment-design.md`
- `docs/architecture/architecture-overview.md`
- `docs/product-contract.json`
- `docs/phases/phase-001-local-sources-and-indexing.md`
- `docs/phases/phase-002-android-first-class-platform-support.md`
- `docs/specifications/backend/spec-be-010-provider-gateway-architecture.md`
- `docs/specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md`
- `docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md`
