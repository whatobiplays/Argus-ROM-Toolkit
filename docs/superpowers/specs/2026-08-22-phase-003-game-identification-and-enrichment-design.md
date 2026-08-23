# Phase 003 Game Identification and Enrichment Design

**Status:** Approved design pending written-spec review  
**Owner:** Daniel  
**Date:** 2026-08-22  
**Scope:** MVP outcome 2 — identify local games, resolve metadata, and manage artwork across desktop and Android

## 1. Purpose

Phase 003 turns the authoritative local source graph delivered by Phase 001 and the first-class Android platform support delivered by Phase 002 into a trustworthy, hydrated, user-facing game Library.

The phase delivers the second MVP outcome from `ARCH-001`:

1. index local ROM libraries;
2. **identify games, resolve metadata, and manage artwork;**
3. verify local content against RetroAchievements hashes.

RetroAchievements verification remains a separate Phase 004 outcome.

The normal user experience minimizes manual work. Once a user chooses a library folder, Argus should scan changed sources, identify new or changed content, group exact content into durable logical games, obtain all eligible metadata and artwork, and progressively present the results in Library without requiring the user to understand internal processing stages.

## 2. Architectural Shape

The authoritative flow is:

```text
Configured Library Roots
        ↓
Source Scan
        ↓
Recognized Content
        ↓
Canonical GameContent Identity
        ↓
Argus-owned Game Grouping
        ↓
Provider Matching
        ↓
Provider Metadata + Artwork References
        ↓
Deterministic Resolution
        ↓
Downloaded Selected Artwork
        ↓
Library / Game Detail
```

The major authority boundaries are:

- `SourceEntry` remains physical/source indexing truth.
- `GameContent` remains exact canonical logical content.
- `Game` becomes the durable platform-specific user-facing grouping entity above one or more `GameContent` records.
- Provider identities remain mappings/provenance and never become Argus identity.
- Metadata and artwork remain replaceable, provenance-bearing enrichment.
- `Refresh Library` composes independent authoritative capabilities into one incremental user operation without collapsing their internal responsibilities.
- `Refresh Game` provides focused enrichment without rescanning unrelated roots.
- Significant provider network traffic remains user-initiated.
- Desktop and Android share the same Rust/domain authorities and adapt only platform-specific presentation/hosting concerns.

## 3. Scope

### 3.1 In scope

Phase 003 includes:

- concrete production canonical content identity schemes for the advertised platform/content matrix;
- parsing, transformation, multi-file, archive, and compressed-representation handling required by that matrix;
- durable `GameContent` identification and provenance;
- durable Argus-owned `Game` and `GameMembership` grouping;
- orphan/reappearance semantics;
- production Library read projections;
- Playmatch, GameTDB, and SteamGridDB production providers;
- automatic provider matching;
- provider-native metadata persistence and deterministic resolved metadata;
- artwork discovery, resolution, selected downloads, and immutable object storage;
- automatic region/language preferences initialized from OS locale;
- provider onboarding and readiness presentation;
- `Refresh Library`, `Refresh Game`, and focused Force Refresh;
- Library as the default product destination;
- adaptive Library browsing and game detail;
- deterministic platform-neutral verification plus desktop and Android native qualification.

### 3.2 Explicit exclusions

Phase 003 does not add:

- RetroAchievements verification;
- arcade/MAME/FBNeo set semantics;
- collections or smart collections;
- cross-platform game grouping;
- manual metadata editing;
- manual artwork candidate selection or locks;
- Argus-hosted cloud/provider proxy infrastructure;
- IGDB or ScreenScraper production integration;
- silent automatic restart/resume of abandoned significant work;
- encrypted/key-dependent platform support that cannot be authoritatively identified without user-supplied decryption material.

Manual metadata/artwork correction remains part of the MVP roadmap, but it is intentionally deferred to a later MVP phase rather than classified as post-MVP.

## 4. Canonical Content Identity

### 4.1 Existing BE-012 boundary

`SPEC-BE-012` remains authoritative for transformation and identity architecture:

- authoritative `(PlatformId, ContentType)` comes from validated transformations;
- filenames, extensions, folders, and provider metadata are planning hints only;
- every supported content class maps to zero or one current identity scheme;
- `GameContent` is created only after strong current identity is established;
- independently usable discs remain separate `GameContent` entities;
- identity semantics and implementation revisions remain separately versioned.

Phase 003 activates concrete production identity schemes rather than weakening those rules.

### 4.2 Production support rule

A platform/content form is not considered supported merely because Argus can recognize or parse it.

Every advertised `(PlatformId, ContentType)` must have:

- a stable `scheme_id`;
- canonical representation and canonicalization rules;
- byte-selection and ordering rules where applicable;
- SHA-256 as the final Argus digest over that canonical logical representation;
- a current `identity_revision`;
- deterministic qualification fixtures/test vectors;
- malformed/ambiguous-input behavior;
- multi-file/container rules where applicable;
- bounded resource and cancellation semantics where parsing is nontrivial.

Recognition-only capability does not satisfy Phase 003 support criteria.

### 4.3 Identity digest strategy

Argus owns logical identity. A canonical content identity is conceptually:

```text
ContentIdentity
- scheme_id
- sha256_identity_value
- identity_revision
```

The semantic meaning is defined by the scheme. SHA-256 is intentionally uniform; platform-specific complexity belongs in canonicalization.

External CRC32, MD5, SHA-1, RetroAchievements hashes, DAT hashes, and provider-specific hashes remain separate `HashRecord` values. They may be computed on demand and evolve independently from Argus identity.

### 4.4 Equivalent representations

Equivalent lossless representations converge only when the applicable identity scheme explicitly defines them as the same logical content. For example:

```text
PS1 CUE/BIN ─┐
             ├→ canonical PlayStation disc representation → SHA-256
PS1 CHD ─────┘
```

The compressed/container bytes do not become canonical identity merely because they are the physical source representation.

## 5. Logical Game Domain

### 5.1 `Game`

`Game` becomes the durable, Argus-owned Library identity already anticipated by existing `GameId`, `/games/:gameId`, and `GamesApi` contracts.

A `Game`:

- belongs to exactly one `PlatformId`;
- contains one or more `GameContent` records;
- owns the stable user-facing Library identity;
- does not use a provider record ID as identity;
- survives provider outages, rematches, metadata replacement, and artwork replacement.

Cross-platform ports/remakes remain separate `Game` entities. A later higher-level title/franchise relationship may relate them without weakening this identity boundary.

### 5.2 `GameMembership`

Membership is explicit durable state rather than an implicit provider-ID join.

Conceptually:

```text
GameMembership
- game_id
- game_content_id
- relationship
- grouping_basis
- grouping_revision
```

Representative closed relationships may include:

```text
PrimaryContent
RegionalVariant
RevisionVariant
Disc
EquivalentRepresentation
```

The exact vocabulary belongs to the owning backend specification.

### 5.3 Conservative grouping

Argus may group content when trustworthy evidence establishes equivalent releases of the same platform game, including:

- regional/language variants;
- ordinary revisions;
- alternate verified dumps;
- equivalent lossless packaging;
- independently usable discs belonging to the same multi-disc release;
- explicit playlist/descriptor relationships where valid;
- compatible trusted external mappings.

Filename or normalized-title similarity alone never establishes membership.

Materially distinct products remain separate, including different games in a paired release, demos, substantial remakes, and ROM hacks/homebrew with distinct identity.

If evidence is insufficient, Argus keeps separate `Game` records rather than risking a false merge.

### 5.4 Duplicate copies

Multiple physical copies or equivalent source representations may converge on one `GameContent` through multiple `GameContentSource` associations. Normal Library browsing displays one logical game rather than duplicate rows. Source provenance remains available in game detail and operational surfaces.

### 5.5 Orphan lifecycle

When the final authoritatively absent source association disappears:

- `GameContent` remains durable;
- its `Game` relationship remains durable;
- identity, provider mappings, metadata, and artwork remain preserved;
- the content stops contributing to the normal active Library while no active content remains.

Temporary source unavailability or disconnected removable media does not orphan content.

If the same canonical content later reappears, Argus reconnects the existing entity and reuses enrichment that remains valid.

Phase 003 adds no automatic orphan garbage collection.

## 6. Advertised Platform and Format Matrix

### 6.1 Platforms

Phase 003 advertises the following platform families, subject to exact `(PlatformId, ContentType)` qualification:

**Nintendo**

- NES / Famicom / Famicom Disk System
- SNES / Super Famicom
- Game Boy
- Game Boy Color
- Game Boy Advance
- Nintendo 64
- Nintendo DS
- Nintendo 3DS only where authoritative key-free identification is possible
- GameCube
- Wii

**Sega**

- Master System
- Game Gear
- Genesis / Mega Drive
- Sega CD / Mega-CD
- 32X
- Saturn
- Dreamcast

**Sony**

- PlayStation
- PlayStation 2
- PSP

Arcade remains outside Phase 003.

### 6.2 Content and packaging forms

The exact support catalog is `(PlatformId, ContentType, representation)` specific. Phase 003 is intended to cover, where applicable:

- native cartridge/file images;
- native ISO/disc images;
- CUE/BIN and equivalent descriptor/track layouts;
- CHD;
- RVZ;
- CSO;
- WBFS;
- ZIP;
- 7z;
- RAR;
- useful single-stream/tar-family containers;
- M3U for explicit multi-disc relationship evidence.

No combination is advertised until the production identity catalog defines and qualifies it.

### 6.3 Single-game archive policy

General archives such as ZIP/7z/RAR are supported only when their independently usable contents represent one game/content family under the applicable transformation rules.

A multi-game archive such as:

```text
collection.zip
├── Mario.nes
├── Zelda.nes
└── Metroid.nes
```

is rejected atomically for identification. Argus does not materialize the first entry or expand the archive into multiple independent games. The enclosing refresh may continue and complete with issues; the user must extract or reorganize the archive.

### 6.4 Nested containers and hostile input

Nested containers are permitted only when a registered transformation path explicitly supports them. Nested work shares one cumulative parsing-session budget; recursion cannot reset limits.

Budgets cover at least nesting depth, expanded bytes, entry count, parser work, staging/storage use, memory, and cancellable processing boundaries.

Resource exhaustion fails safely and never persists truncated recognition as authoritative truth.

### 6.5 Multi-file and multi-disc content

A valid multi-file representation may produce one `GameContent` when the identity scheme defines one logical content unit.

Independently usable discs remain separate exact contents and may be grouped beneath one `Game` when explicit trustworthy relationship evidence supports it. M3U can supply relationship evidence; it never becomes one giant multi-disc `GameContent`.

## 7. Provider and Enrichment Architecture

### 7.1 Production provider set

Phase 003 activates:

| Provider | Setup | Role |
| --- | --- | --- |
| Playmatch | none | content/game matching and supported enrichment mappings |
| GameTDB | none | applicable-platform metadata/artwork |
| SteamGridDB | user API key | artwork enrichment |

IGDB and ScreenScraper are deferred because safe production use would require application-owned secret handling or hosted infrastructure outside the current local-first architecture.

### 7.2 Matching remains exact-content based

Matching begins from `GameContent` because exact content owns canonical identity, hashes, region evidence, and provenance.

```text
GameContent
    ↓
Match Metadata
    ↓
ExternalIdentityMapping[]
```

An external mapping records provider identity, the matching `GameContent`, evidence, provider-local confidence where applicable, release/region information, and revision/provenance.

Provider scores are provider-local evidence and are not treated as a universal cross-provider confidence scale.

Low-confidence/conflicting candidate sets remain unresolved. Phase 003 contains no interactive candidate picker.

### 7.3 Provider matching never establishes canonical identity

The dependency direction is always:

```text
Argus canonical identity
        ↓
provider matching
```

Never the reverse.

### 7.4 Game-level enrichment resolution

Provider evidence is gathered from compatible mappings on member `GameContent`, then resolved into one user-facing `Game` projection.

Provider-native records are retained rather than destructively flattened.

For each field, resolution may consider:

1. compatibility with content actually owned by the user;
2. preferred region;
3. preferred language;
4. field/capability-specific provider priority;
5. completeness/provider-native quality evidence;
6. freshness;
7. deterministic tie-breaking.

Different fields may resolve from different providers. Every resolved value retains provenance.

Users can enable/disable providers and configure required credentials, but Phase 003 exposes no provider-ranking UI.

### 7.5 Region and language policy

Preferred region/language are durable global preferences initialized from OS locale.

They affect presentation only. Strong evidence from owned content outranks an unrelated locale default. When several equivalent regional variants are owned, preference ordering determines the normal display projection. Fallback to another suitable locale is automatic.

### 7.6 Provider readiness

The established readiness vocabulary remains:

```text
Ready
Disabled
MissingCredentials
InvalidCredentials
Misconfigured
Unavailable
```

Only `Ready` is eligible for provider execution.

### 7.7 Best-effort enrichment

Each provider runs independently. Successful results persist even when another provider fails. The resolver computes the best available projection from current valid data. The enclosing refresh may finish `CompletedWithIssues` while leaving the game usable.

A later eligible refresh fills missing/stale data without discarding current successful results or repeating unnecessary work.

### 7.8 Unmatched games

A trustworthy Argus content identity is sufficient for Library membership. Provider success is not.

An unmatched game remains visible with bounded local fallback presentation such as normalized source-derived display text, known platform, generic/no artwork, and an explicit unmatched/incomplete hydration state. Source-derived text is presentation-only and never becomes canonical identity or grouping evidence.

## 8. Artwork

### 8.1 Pipeline

The existing separation remains:

```text
ArtworkDiscoveryProvider
    ↓
ArtworkReference
    ↓
ArtworkResolver + ArtworkResolutionPolicy
    ↓
ResolvedArtwork
    ↓
ArtworkDownloader + ArtworkDownloadPolicy
    ↓
ArtworkAsset
```

### 8.2 Game-level presentation ownership

The existing reserved future model that places `ResolvedArtwork` directly on `GameContent` must evolve when Phase 003 activates `Game`:

```text
ResolvedArtwork
- game_id
- artwork_type
- reference_id
- asset_id nullable
- ordering where applicable
- resolution_reason
- resolved_at
```

Provider/content provenance remains traceable below the selected reference. This prevents independent discs or equivalent regional content from owning competing Library covers.

### 8.3 Canonical taxonomy

The MVP artwork taxonomy remains:

```text
CoverFront
CoverBack
CoverSpine
Screenshot
TitleScreen
Logo
Icon
Background
Banner
Manual
```

All types resolve to one selected asset except `Screenshot`, which may retain an ordered, diverse set.

### 8.4 Download and storage

Phase 003 downloads only resolver-selected artwork.

Downloaded assets:

- preserve original provider bytes;
- are immutable;
- are content-addressed using the existing artwork asset contract;
- live in the app-private artwork object store;
- are not resized, recompressed, or converted in Phase 003.

Multiple references/games may reuse one immutable byte-identical asset.

## 9. Refresh Library and Refresh Game

### 9.1 Composed user operation

`Refresh Library` is one durable user-visible `JobRun` that composes independent capabilities:

```text
scan eligible roots
      ↓
identify new/changed content
      ↓
reconcile Game membership
      ↓
match eligible content
      ↓
refresh eligible provider metadata
      ↓
resolve Game metadata
      ↓
discover/resolve/download artwork
```

Subsystems retain their own plans, persistence, safe checkpoints, cancellation semantics, and completion policy. The runtime does not gain a generic opaque-node scheduler.

### 9.2 Incremental pipelining

There is no whole-Library stage barrier. Once upstream state commits authoritatively, eligible downstream work may begin.

```text
scan commit
   ↓
identify
   ↓
group
   ↓
hydrate
```

Games can therefore appear and hydrate progressively while other roots are still scanning.

Downstream work consumes only committed authoritative state. Events remain notification/invalidation signals; authoritative queries repair uncertainty.

### 9.3 Default eligibility

Normal `Refresh Library` uses `EligibleOnly` semantics. It processes new, changed, stale, incomplete, revision-affected, or otherwise eligible work and reuses current valid state.

A second refresh with no relevant changes should perform negligible substantive work.

### 9.4 `Refresh Game`

`Refresh Game(GameId)` is a focused top-level operation that does not rescan unrelated roots. It validates identity/provenance as required, then refreshes eligible matching, metadata, artwork, and resolution for that game.

A secondary Force Refresh is available for one game. Force applies to refreshable provider/enrichment work; it never bypasses canonical identity requirements or fabricates source truth.

There is no normal Library-wide Force Refresh action.

### 9.5 Add Library Folder

The normal product flow becomes:

```text
Add Library Folder
        ↓
persist validated root
        ↓
admit Refresh Library for affected scope
        ↓
scan → identify → hydrate
```

`Add Without Refreshing` remains available as an advanced/secondary Sources operation.

### 9.6 Concurrency and resource authority

Pipelining is bounded. Subsystems own the relevant source-read, parser, archive, hash, provider, and download limits. `BackgroundOperationManager` remains authoritative for top-level resource-class admission and lifecycle. Provider request/rate-limit policy remains inside provider sessions.

### 9.7 Partial failures

Scoped content/provider/artwork failures do not abort unrelated work when the job can safely continue. A refresh with meaningful success plus unsatisfied requested scope finishes `CompletedWithIssues` with bounded detail retained in Jobs.

Global execution-safety failures remain governed by existing runtime policy.

### 9.8 Cancellation

Cancellation is cooperative and top-level:

- no new downstream work is admitted after accepted cancellation;
- in-flight work reaches owning safe checkpoints;
- coherent committed results remain valid;
- successful provider/artwork work is not rolled back merely because later work was cancelled;
- no half-persisted identity, grouping, metadata, or artwork-selection state is allowed.

### 9.9 Restart and process loss

Phase 003 preserves the MVP rule that significant work is never silently resumed.

Startup reconciliation preserves committed terminal work and reconciles stale active work to the applicable recovery state without performing scans, provider calls, parsing, or downloads. The user explicitly retries or starts a new refresh.

Retry creates a new `JobRunId`, reconstructs original bounded intent, re-evaluates current eligibility, and reuses still-current completed work.

### 9.10 Android execution

A qualifying user-admitted refresh may use the established Android foreground-service execution host. The service is not scheduler/job authority and never creates a second Rust runtime or database authority.

## 10. Persistence and Projections

### 10.1 Durable normalized state

Phase 003 extends the existing SQLite model with normalized authoritative state such as:

```text
Game
GameMembership
GameContent
ContentIdentity
ContentIdentityProvenance
GameContentSource
ExternalIdentityMapping
ProviderMetadata
ResolvedMetadata
ArtworkReference
ResolvedArtwork
ArtworkAsset
JobRun
operation-specific durable refresh/identification state
```

The dependency direction remains source truth → content identity → Game membership → provider evidence → resolved presentation.

Resolved state is derived and must never become the source of canonical identity.

### 10.2 Resolved metadata

`ProviderMetadata` remains provider-native, application-owned persisted evidence. `ResolvedMetadata` is a durable derived projection used for fast stable presentation and retains field-level provenance plus resolver/policy revision information.

This separation must allow a later MVP manual-correction layer to sit above automatic resolution without changing provider-native records or `GameContent` identity.

### 10.3 Library read projection

Normal browsing uses a dedicated Game-level projection conceptually similar to:

```text
GameLibraryRow
- game_id
- display_title
- platform_id
- preferred_region
- selected_cover_asset_id nullable
- hydration_state
- content_count
- source_count
- availability_state
- updated_at
```

Core fields required for correct Library rendering update transactionally with authoritative mutations. Expensive secondary indexes may rebuild asynchronously if stale derived indexing never corrupts authoritative game state.

### 10.4 Incremental projection maintenance

A mutation affecting one game updates only the required game-level projections. Phase 003 must not rebuild the full Library for one metadata or artwork change.

### 10.5 Query semantics

Library/search uses:

- cursor pagination;
- stable backend tie-breakers ending in a unique identity;
- typed `LibraryFilter` semantics;
- one primary user-selected sort;
- backend-owned search/filter/sort behavior.

Flutter never loads the entire Library to implement those semantics locally.

### 10.6 Migration behavior

Phase 003 migrations preserve valid Phase 000–002 databases and never perform hidden user-work during schema migration.

Migrations must not infer `GameContent` or `Game` identity from historical filenames/folders or silently parse/hash the user's library. Existing indexed sources become eligible for identification only through an explicit user-initiated refresh.

### 10.7 Revision-driven maintenance

Derived work uses explicit revision/freshness semantics such as:

```text
identity_revision
grouping_revision
provider/matching revision
metadata resolution revision
artwork resolution revision
```

Revision changes make only affected work eligible and do not authorize blanket destructive resets.

## 11. Library and Onboarding UX

### 11.1 Default destination

Once startup/readiness/onboarding are satisfied, `/library` becomes the normal product destination.

Primary navigation becomes:

```text
Library
Sources
Jobs
Settings
```

`Sources` remains the operational root/filesystem/index surface. Collections remain inactive.

### 11.2 Product onboarding

Platform readiness remains separate from product onboarding.

Phase 003 product onboarding includes:

1. existing required privacy/data-sharing acceptance;
2. preferred region/language confirmation prefilled from OS locale;
3. provider explanation/readiness;
4. Playmatch and GameTDB shown as zero-setup ready providers when service readiness permits;
5. optional SteamGridDB API-key entry and validation;
6. first Library-folder selection;
7. automatic admission of the initial refresh.

SteamGridDB setup is guided/recommended but skippable. Provider readiness/outage never prevents the backend runtime from reaching `Ready`.

### 11.3 Empty Library

With no configured roots, Library presents a focused empty state with `Add Library Folder` as the primary action. Successful root admission automatically starts the appropriate refresh.

### 11.4 Browsing

Phase 003 activates the existing Library contract:

- grid/list;
- search;
- temporary typed filters;
- stable sorting;
- cursor pagination;
- platform scope;
- source scope;
- library-root scope;
- adaptive multi-selection;
- independent grid/list scroll restoration.

Canonical routes include:

```text
/library
/library/platforms/:platformId
/library/sources/:sourceId
/library/library-roots/:libraryRootId
/games/:gameId
```

### 11.5 Progressive presentation

Running refreshes do not replace an already usable Library with a global loading screen. Existing games stay interactive while newly identified games and enrichment appear as committed state becomes available.

User-visible hydration states may include hydrated, partially hydrated, unmatched, and refreshing projections derived from authoritative backend state.

Temporary source unavailability remains distinguishable from authoritative orphaning.

### 11.6 Game detail

`/games/:gameId` uses the established adaptive route identity:

- Compact: full routed detail;
- Medium: full detail by default;
- Expanded/Large: inspector/master-detail presentation.

Phase 003 detail includes overview, metadata, files/content variants, artwork, useful provider/provenance information, and appropriate operation/history state. RetroAchievements detail remains inactive until Phase 004.

`Refresh Game` and secondary Force Refresh actions are available from game detail.

### 11.7 Minimal-intervention principle

Normal use should approximate:

```text
choose folder once
        ↓
browse games
```

Scanning, canonicalization, provider matching, metadata refresh, and artwork discovery remain observable for troubleshooting but are not normal user workflow concepts.

### 11.8 Manual correction roadmap

Phase 003 deliberately does not activate per-game metadata editing, candidate matching, manual artwork selection, or artwork locks. Those correction surfaces remain scheduled for a later MVP phase. Existing documentation that currently describes them as post-MVP must be corrected as part of Phase 003 contract work.

## 12. Security and Privacy

### 12.1 External-data minimization

Provider requests include only the minimum information required for the requested capability, such as provider platform mappings, required hashes, normalized matching hints, region/language hints, or known external IDs.

Argus does not transmit local filesystem paths, root locators, Android storage URIs, unrelated Library contents, diagnostics, or user settings merely to enrich a game.

Versioned privacy consent must disclose transmission of file-derived identifiers to enabled external providers.

### 12.2 Credentials

SteamGridDB's user-supplied API key is handled only through the credential service.

Secrets never enter ordinary settings, SQLite settings records, logs, traces, diagnostics, events, job history, provider configuration DTOs, or normal UI read models. UI may persist/present only non-secret readiness/configured-state facts.

### 12.3 No embedded application secrets

Phase 003 contains no production IGDB or ScreenScraper application secret and no hidden Argus proxy. A secret is not protected merely because it is compiled, obfuscated, stored in assets/resources, or split across binaries.

### 12.4 Untrusted provider and artwork input

Provider responses and remote artwork are untrusted input. Adapters/downloaders validate and bound response size, schema/types, identifiers, URLs, redirects according to networking policy, image metadata, image size, and storage use.

Remote filenames/URLs never determine local object-store paths. Artwork identity is computed from actual downloaded bytes.

### 12.5 Archive safety

Container handling preserves BE-012's hostile-input posture: no traversal extraction, no extraction beside user files, cumulative expansion/nesting limits, bounded staging, cancellation, and no authoritative persistence of truncated results.

### 12.6 No autonomous networking

Provider work occurs only as a consequence of an explicit user operation such as initial folder refresh, `Refresh Library`, `Refresh Game`, or focused Force Refresh. Startup, migration, process recovery, merely opening Library, and timers do not initiate significant provider work.

## 13. Verification and Qualification

### 13.1 Canonical deterministic gate

`just check` remains the required deterministic platform-neutral gate. It requires no network, real credentials, copyrighted ROM data, or machine-local state.

Phase 003 adds deterministic coverage for:

- domain/persistence behavior;
- parser/transformation and identity vectors;
- grouping/orphan/reappearance;
- provider adapters with synthetic/captured-safe fixtures;
- metadata/artwork resolvers;
- composed refresh with deterministic fake providers;
- bridge/API behavior;
- Flutter controllers/widgets/routes;
- generated-source and architecture checks.

### 13.2 Identity qualification matrix

Every advertised matrix row proves, as applicable:

- valid recognition;
- deterministic canonicalization;
- stable scheme-scoped SHA-256 identity;
- equivalent-representation convergence where promised;
- distinct-content separation;
- malformed/ambiguous failure;
- changed-source reidentification;
- multi-file dependency/ordering;
- container budgets;
- cancellation;
- multi-game-archive rejection.

Committed parser fixtures are fabricated/minimal or otherwise safely redistributable.

### 13.3 Adversarial parsing

Targeted property/fuzz-style tests cover malformed headers, extreme declared sizes, invalid references, traversal-like archive names, duplicate/cyclic dependencies, excessive nesting, truncation, and inconsistent disc layouts where applicable.

### 13.4 Domain/persistence scenarios

Tests prove duplicate-source convergence, concurrent identity convergence, conservative grouping, orphan semantics, reappearance, resolver independence from canonical identity, incremental projection maintenance, and safe migration from supported pre-Phase-003 databases.

### 13.5 Provider verification

Playmatch, GameTDB, and SteamGridDB each receive offline adapter contract tests for readiness, platform mapping, request construction, parsing, error/rate-limit translation, revision/provenance, redaction, and artwork normalization where applicable.

Live-provider qualification is separate from `just check` and explicitly reports current service/environment failures rather than hiding them as deterministic code failures.

### 13.6 Composed workflow scenarios

Deterministic integration coverage includes clean first refresh, no-op eligible refresh, one changed game, duplicate copies, unmatched games, partial provider failure, invalid SteamGridDB credentials, provider recovery between attempts, malformed archive, rejected multi-game archive, cancellation through major stages, process-loss reconciliation plus explicit retry, per-game refresh, and Force Refresh.

### 13.7 Flutter verification

Frontend tests cover Library default routing, empty Library onboarding, Add Library Folder composition, grid/list/search/filter/sort/pagination, progressive hydration, unmatched/partial states, adaptive game detail, Jobs navigation, provider settings/onboarding, accessibility/focus/keyboard/touch/text-scale behavior, and Android Back/predictive Back at established size boundaries.

### 13.8 Native qualification

A desktop native milestone exercises the real filesystem/provider boundary, parser/container I/O, canonical identity, duplicate convergence, SQLite persistence, artwork object storage, restart restoration, cancellation, eligible no-op refresh, and source mutation using safe deterministic fixture data.

The established API 36 ARM64 Android milestone is extended to cover Library default navigation, folder-to-refresh flow, Android-accessible parsing/identity, app-private metadata/artwork persistence, Activity detach/reattach, foreground execution, cancellation, process loss/no silent resume, removable-volume loss/remount, credential readiness, adaptive Library/detail behavior, and single-runtime invariants.

### 13.9 Scale qualification

A reproducible synthetic Library with at least 10,000 identified contents is used to detect accidental whole-Library Flutter loading, N+1 planning/query behavior, whole-projection rebuilds for one-game changes, unbounded progress events, parser staging growth, and artwork-concurrency mistakes.

This is an architecture/regression qualification rather than a fixed wall-clock SLA.

## 14. Required Specification and Architecture Work

Before the first dependent implementation slice, Phase 003 requires:

### 14.1 New specifications

- `SPEC-BE-014 — Production Content Identity Catalog`
- `SPEC-BE-015 — Game Library, Grouping, and Enrichment Contract`
- `SPEC-FE-010 — Library, Game Detail, and Enrichment UX`

### 14.2 Existing-spec amendments

Targeted amendments are required where existing documents already own the boundary:

- BE-004 — composed refresh lifecycle/resource/cancellation behavior;
- BE-005 — metadata/artwork/locale settings and credential-presence state;
- BE-008 — Phase 003 bridge DTOs/events/projections;
- BE-009 — focused Library/Game/enrichment services;
- BE-010 — concrete provider activation/readiness and outdated provider-roadmap statements;
- BE-012 — production catalog linkage/Phase 003 identity maintenance semantics;
- BE-013 — scan-commit interaction with composed Library refresh;
- FE-003 — Library/Game/provider focused APIs;
- FE-004 — Library routes/branch/default destination;
- FE-008 — add-and-refresh normal folder UX;
- FE-009 — new background-operation presentation.

### 14.3 Architecture corrections

`docs/architecture/architecture-overview.md` must be updated where approved Phase 003 decisions supersede reserved/deferred wording, including:

- durable `Game` above `GameContent`;
- Game-level resolved metadata/artwork presentation;
- production provider roster;
- current provider-authentication rationale;
- single-game archive policy;
- Library as product home;
- manual correction as later-MVP rather than post-MVP;
- RetroAchievements remaining the subsequent separate outcome.

### 14.4 Readiness gate

Implementation does not begin until:

```text
BE-014  Ready for Implementation
BE-015  Ready for Implementation
FE-010  Ready for Implementation
required existing-spec amendments reviewed
cross-document consistency pass clean
PHASE-003 marked Ready for Implementation
```

## 15. Ordered Implementation Slices

Specification/architecture work is a readiness prerequisite, not an implementation slice.

### P03-001 — Canonical Content and Logical Library Foundation

Establish Phase 003 migrations/repositories, `Game`, `GameMembership`, identity provenance/orphan semantics, an initial qualified simple content tranche, duplicate convergence, fallback unmatched-game presentation, `GameLibraryRow`, and focused backend/bridge APIs sufficient to query a real logical Library. No live provider dependency is required.

### P03-002 — Metadata Providers and Automatic Hydration

Activate Playmatch, GameTDB, SteamGridDB credential-service/readiness, external identity mappings, provider metadata, deterministic resolution, artwork discovery/resolution/download, immutable object storage, and best-effort partial-provider semantics for the P03-001 content tranche.

### P03-003 — Library Experience and Composed Refresh

Activate Library as default destination, onboarding, provider setup, empty Library, Add Library Folder → Refresh Library, incremental scan/identify/group/hydrate composition, progressive UI updates, `Refresh Library`, `Refresh Game`, Force Refresh, Jobs integration, cancellation/retry/recovery, and Android foreground hosting for qualifying work.

### P03-004 — Cartridge and Handheld Platform Coverage

Extend the complete vertical path across the cartridge/handheld-oriented platform matrix, including NES/Famicom/FDS, SNES, GB/GBC/GBA, N64, DS, key-free 3DS content, Master System, Game Gear, Genesis/Mega Drive, and 32X. No platform/form is advertised until the complete identity/enrichment/Library qualification row passes.

### P03-005 — Disc, Multi-File, and Multi-Disc Coverage

Establish canonical logical disc semantics for Sega CD, Saturn, Dreamcast, PlayStation, PlayStation 2, PSP, GameCube, and Wii, including descriptor/track resolution, CUE/BIN-style layouts, native ISO forms, deterministic ordering, independently identified discs, M3U relationship evidence, multi-disc Game grouping, and missing/inconsistent dependency failures.

### P03-006 — Containers and Compressed Representations

Add ZIP, 7z, RAR, applicable single-stream/tar-family containers, CHD, RVZ, CSO, and WBFS on top of already-qualified logical identities. Prove equivalent-representation convergence, single-game archive enforcement, atomic multi-game rejection, nested-container policy, cumulative resource accounting, hostile-input safety, staging limits, and cancellation.

### P03-007 — Library Browsing and Game Detail Completeness

Complete grid/list/search/filter/sort/cursor pagination, platform/source/root scopes, adaptive selection and game detail, content variants/discs/copies, source availability, unmatched/partial hydration presentation, provenance, artwork gallery/detail, orphan/reappearance behavior, and large-Library incremental projections. Collections and manual correction remain deferred.

### P03-008 — Cross-Platform Integration and Lifecycle Hardening

Exercise all Phase 003 capabilities as first-class desktop and Android behavior, including filesystem/object storage, Android storage permission interactions, removable media, credential storage, Activity detach/reattach, foreground execution, process loss, explicit retry/no silent resume, predictive Back, live size transitions, accessibility/touch/keyboard behavior, and single-runtime invariants.

### P03-009 — Full Matrix Qualification and Phase Hardening

Complete every advertised identity row, equivalent-representation qualification, offline provider contracts, live-provider qualification, desktop native milestone, API 36 ARM64 milestone, 10,000+ item synthetic Library qualification, migration coverage, security/redaction checks, generated-source verification, documentation consistency, and full `just check`. No new feature scope belongs in this final hardening slice.

## 16. Design Invariants

Phase 003 is correct only if all of these remain true:

1. Filesystem/source observations never become canonical game identity by filename convention alone.
2. Every advertised content form has a concrete current identity scheme and qualification evidence.
3. Argus owns canonical logical content identity; provider hashes/IDs remain external evidence.
4. `GameContent` represents exact content; `Game` represents one platform-specific user-facing game.
5. Provider availability cannot destroy or redefine canonical Library identity.
6. Ambiguous grouping stays separate rather than risking a false merge.
7. Duplicate physical copies do not produce duplicate normal Library entries.
8. Temporarily unavailable roots do not authorize orphaning.
9. Unmatched but identified content remains visible in Library.
10. Normal enrichment is automatic after identification and best-effort across eligible providers.
11. Users do not need provider-order, candidate-selection, metadata-edit, or artwork-lock controls in Phase 003.
12. Manual metadata/artwork correction remains later-MVP scope.
13. `Refresh Library` is explicit, eligibility-driven, incremental, bounded, cancellable, and non-auto-resumable.
14. Provider/network work is never triggered autonomously by startup, migration, or recovery.
15. Resolved metadata/artwork are derived presentation state, not canonical identity authority.
16. Library queries remain paged/backend-owned; Flutter never needs the whole Library for correctness.
17. Desktop and Android share one semantic backend architecture.
18. Arcade, RetroAchievements verification, collections, cross-platform grouping, and hosted cloud infrastructure remain outside Phase 003.

## 17. Acceptance Summary

The design is ready for written-spec review when it is internally consistent with the approved decisions above. After written-spec approval, implementation planning begins with the contract package, not production code.
