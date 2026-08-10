# Argus ROM Toolkit Architecture

**Document ID:** ARCH-001  
**Status:** Complete  
**Owner:** Daniel  
**Last Updated:** 2026-08-10  
**Depends On:** None  
**Supersedes:** None  
**Superseded By:** None  
**Audience:** Engineers, Codex implementation agents, reviewers, and future maintainers

## 1. Purpose

Argus ROM Toolkit is a cross-platform ROM library management application focused on three primary MVP outcomes:

1. Index local ROM libraries accurately and incrementally.
2. Identify games, resolve metadata, and manage artwork.
3. Verify local game content against RetroAchievements-recognized hashes.

Argus is not an emulator frontend, save manager, synchronization platform, or achievement-progress client in the MVP. Its primary responsibility is to maintain a trustworthy, inspectable model of a user's ROM library and the derived information associated with that content.

This document is the canonical architecture overview for the MVP. It captures the agreed backend and frontend boundaries, domain models, processing pipelines, execution model, persistence strategy, Flutter architecture, UI requirements, deferred scope, and implementation sequencing.

## 2. Architectural goals

The architecture must provide the following properties:

- **Correctness before throughput.** Indexing, reconciliation, hashing, and provider results must be deterministic and explainable.
- **One authoritative backend.** Rust owns domain rules, persistence, validation, planning, scheduling, and derived state.
- **Presentation-only Flutter layer.** Flutter owns rendering, interaction, navigation, and transient presentation state.
- **Immediate UI responsiveness.** Once startup completes, background work must never block unrelated interaction or replace already usable content with a global loading state.
- **Explicit asynchronous work.** Long-running user operations become persisted jobs and report progress through the event channel.
- **Composable subsystems.** Indexing, parsing, hashing, metadata, artwork, and RetroAchievements remain independently testable and reusable.
- **Provider independence.** Shared orchestration must not contain provider-specific or tool-specific logic.
- **Stable public contracts.** Flutter talks to purpose-built Rust application façades through dedicated bridge DTOs.
- **Scalability.** The design must remain viable for libraries containing hundreds of thousands of source entries.
- **MVP restraint.** Deferred capabilities must not be partially implemented in ways that complicate the MVP.

## 3. Technology direction

The intended stack is:

- **Backend:** Rust
- **Frontend:** Flutter and Dart
- **Native bridge:** `flutter_rust_bridge`
- **Flutter state management:** Riverpod with code generation for all providers
- **Flutter immutable models:** Freezed for all immutable model types
- **Flutter routing:** `go_router`
- **Persistence:** SQLite behind Rust repositories and a Unit of Work abstraction
- **Code generation:** `build_runner`, Riverpod generator, Freezed, JSON serialization where required, and `flutter_rust_bridge` generation

Exact package versions are implementation-plan decisions and must be pinned when foundational project setup is implemented.

## 4. System overview

```text
Flutter UI
    |
    v
Riverpod controllers and feature presentation models
    |
    v
ArgusClient and focused domain APIs
    |
    v
Generated flutter_rust_bridge bindings
    |
    v
Rust application façades
    |
    +--> Query handlers --> read repositories / projections
    |
    +--> Use-case handlers --> planners --> execution graphs --> scheduler
                                    |                         |
                                    v                         v
                              repositories               executors
                                    |                         |
                                    +-----------+-------------+
                                                v
                                      Unit of Work / SQLite
                                                |
                                                v
                                      transient domain events
                                                |
                                                v
                                      Flutter event coordinator
```

## 5. MVP scope

### 5.1 Included

The MVP includes:

- Library sources and library roots
- Local filesystem source provider
- Explicit library scans
- Hierarchical source-entry discovery
- Archive/container-aware source graphs
- Source classification
- Stable source-entry identity and conservative move detection
- Game-content resolution
- Session-scoped parsing and typed intermediate representations
- Demand-driven hashing
- Metadata matching
- Metadata provider sessions and provider readiness
- Metadata refresh and resolved metadata
- Artwork discovery, resolution, download, and content-addressed storage
- RetroAchievements catalog caching and local hash verification
- Persisted user-visible jobs
- Generic execution-graph scheduler
- Application façades, commands, queries, read projections, and events
- Responsive Flutter UI for desktop, tablet, and phone
- Diagnostics export and startup recovery

### 5.2 Explicitly deferred

The following are post-MVP unless separately approved:

- Save files, save states, memory cards, or emulator configuration management
- Filesystem watching
- Concurrent source discovery
- Background autonomous metadata refresh
- Background autonomous artwork refresh
- Provider health and circuit-breaker UI
- Hasheous integration
- User-selectable artwork candidate browsing
- Derived artwork variants and thumbnail generation
- Achievement details, badges, account progress, or synchronization
- Persistent notification inbox
- Command palette
- Custom keyboard shortcuts
- General plugin system
- Full application undo/redo history
- Persistent parsed-content cache
- Cloud library providers
- Symlink, alias, junction, or link traversal

## 6. Core domain model

### 6.1 LibrarySource

A `LibrarySource` represents the access mechanism through which Argus reaches storage.

Examples:

- Local filesystem
- SMB or NAS provider in a future release
- Removable storage
- Future cloud provider

Conceptual fields:

```text
LibrarySource
- id
- source_type
- display_name
- provider_config
- config_revision
- created_at
- updated_at
```

A source may own one or more `LibraryRoot` records.

### 6.2 LibraryRoot

A `LibraryRoot` is a user-configured scanning boundary within a source.

```text
LibraryRoot
- id
- library_source_id
- root_locator
- display_name
- availability_status
- last_scan_status
- last_scan_started_at
- last_scan_completed_at
- discovery_policy
- config_revision
- created_at
- updated_at
```

Availability states:

```text
Available
Unavailable
Unknown
```

Scan outcome states:

```text
NeverScanned
Complete
Partial
Unavailable
Cancelled
Failed
```

Root availability and scan completeness govern whether absence is authoritative.

### 6.3 SourceEntry

Every discovered object retained by discovery policy becomes a `SourceEntry` node in a hierarchical graph.

```text
SourceEntry
- id
- library_root_id
- parent_source_entry_id
- entry_kind
- relative_locator                # provider-native entries only
- locator_key                     # provider-native entries only
- derived_locator                 # transformation-derived entries only
- derived_entry_key               # transformation-derived entries only
- display_name
- provider_native_identity        # provider-native entries only
- source_fingerprint              # provider-native entries only
- derived_fingerprint             # transformation-derived entries only
- derivation_transformation_id    # transformation-derived entries only
- derivation_revision             # transformation-derived entries only
- classification
- last_observed_scan_id
- created_at
- updated_at
```

Provider-native and transformation-derived coordinates/evidence remain distinct. Application validity logic may view either through `SourceVersionEvidence = Provider(SourceFingerprint) | Derived(DerivedFingerprint)`, but persistence must not pretend derived entries have provider locator or fingerprint semantics.

Representative entry kinds:

```text
Directory
File
LinkLike
Archive
ArchiveEntry
DiscImage
Playlist
VirtualContainer
Unknown
```

Source providers report structural observation kinds such as directory, file, link-like, or other. Richer persisted kinds such as archive, playlist, or disc image are Argus-owned interpretations and may be refined without changing `SourceEntryId`.

Classification values:

```text
Container
ContentCandidate
SupportingEntry
Ignored
Unknown
```

A content-bearing node is not required to be a leaf. A playlist or CUE sheet may be a content candidate while owning supporting child entries.

### 6.4 GameContent

`GameContent` represents one canonical logical-content unit managed by Argus, independent of where it was discovered.

```text
GameContent
- id
- platform_id
- content_type
- content_identity       # current only while identified
- identity_state
- created_at
- updated_at
```

Each `GameContent` has at most one current `ContentIdentity`. A newly created `GameContent` is created only after strong identity is established. Existing content may temporarily have no current identity while in `NeedsReidentification` or `IdentityConflict` during targeted identity maintenance.

Source relationships are represented separately:

```text
GameContentSource
- game_content_id
- source_entry_id
- relationship
```

Representative relationship values include:

```text
Primary
Descriptor
Supporting
AlternativeSource
```

`GameContentSource` is an unversioned association, not current identity proof. The exact source/version basis that established the current identity is stored separately:

```text
ContentIdentityProvenance
- game_content_id
- source_entry_id
- role
- source_version_evidence
```

A canonical content unit may depend on several source entries, such as CUE/BIN. Independently usable discs remain separate `GameContent` entities; release/title-level multi-disc grouping belongs above this layer.

### 6.5 Identity distinctions

The following concepts must not be conflated:

| Type | Meaning |
|---|---|
| `LibrarySourceId` | Configured source-instance identity |
| `LibraryRootId` | Configured scan-boundary identity |
| `SourceEntryId` | Stable Argus discovered-object identity |
| `SourceLocatorKey` | Provider-defined equality for one provider-native entry's current location within a root |
| `ProviderNativeIdentity` | Optional provider-scoped continuity of the same underlying storage object |
| `SourceFingerprint` | Cheap provider-defined change evidence for provider-native entries, not content identity |
| `DerivedFingerprint` | Cheap transformation-defined change evidence for derived entries, not content identity |
| `SourceVersionEvidence` | Application abstraction over provider or derived cheap version evidence |
| `GameContentId` | Logical managed-content identity |
| `ContentIdentity` | Strong versioned canonical identity of one logical content unit |
| `SourceHashRecordId` | One source-scoped hash result |
| `ContentHashRecordId` | One content-scoped hash result |

## 7. Source providers

### 7.1 Provider contract

Source providers expose storage primitives only. They do not reconcile, classify, create games, or schedule work.

Provider family and configured source-instance identity are separate. A runtime-composed `SourceProviderRegistry` resolves a `SourceProviderFactory`, which binds one operation-scoped `LibrarySourceAccess` for a configured `LibrarySource`.

Conceptual interface:

```text
LibrarySourceAccess
- capabilities()
- compare_root_locators()
- resolve_root()
- enumerate_children()
- stat_entry()
- open_stream()
- native_identity()
```

`RootLocator` and `RelativeSourceLocator` are opaque provider-owned coordinates. `SourceLocatorKey` is the separate provider-defined persistence key used for location equality. Successful root resolution returns a transient `ResolvedRoot`; it does not silently rewrite persisted root configuration.

### 7.2 Provider capabilities

Providers declare capabilities such as:

```text
stable_native_identity
hierarchical_enumeration
seekable_streams
random_access
modification_timestamps
atomic_reads
case_sensitive_paths
supports_partial_enumeration
supports_change_notifications
supports_symlinks
```

The shared indexing layer adapts behavior based on capabilities. It must not contain local-filesystem-specific assumptions. Effective guarantees may narrow for a particular resolved root; capabilities are promises, not guesses.

### 7.3 MVP provider implementation

The MVP initially implements a local filesystem provider. Link-like entries are not followed:

- symbolic links
- aliases
- junctions
- filesystem links or link-like provider objects

They may be observed or ignored according to discovery policy, but must not be traversed.

### 7.4 Source-read consistency

Opening source content returns a transient provider-owned read with explicit consistency semantics. Providers that cannot guarantee an atomic stable-version read must support completion validation. Trusted immutable derived facts such as content identities, hashes, or authoritative derived-container structure may be committed only after the read is known to represent one stable source version.

## 8. Indexing architecture

### 8.1 Responsibilities

Indexing answers:

> What content exists in the configured library roots?

It does not resolve metadata, download artwork, verify RetroAchievements, or eagerly compute every possible hash.

### 8.2 Discovery and filtering

Filtering is split into two stages.

**Discovery policy** determines whether Argus retains and/or traverses a node:

- include patterns
- exclude patterns
- hidden/system behavior
- archive traversal policy
- maximum depth
- link traversal disabled for MVP
- provider-specific options

Generic policy matching operates on a provider-neutral root-relative `DiscoveryPath`, not by parsing opaque provider locators.

**Classification policy** determines the meaning of an observed node:

- content candidate
- supporting entry
- container
- ignored
- unknown

Structural exclusions prevent irrelevant nodes from entering the graph. Semantic classification preserves useful supporting records without treating them as games.

### 8.3 Streaming execution

Discovery is single-threaded for MVP and emits observations incrementally. Provider enumeration order is not semantically significant.

```text
Scan planner
    -> single-threaded discovery executor
    -> streamed SourceObservation values
    -> discovery policy
    -> incremental reconciler
    -> classifier
    -> known GameContentSource relationship updates when independently justified
    -> authoritative scope finalization
```

Concurrency may be added post-MVP, but downstream contracts must not assume observations always have a single producer or rely on observation arrival order.

### 8.4 Reconciliation outcomes

Reconciliation produces transient outcomes:

```text
New
Unchanged
Moved
Modified
Removed
```

These are not persistent source-entry states.

### 8.5 Scan authority and deletion

Absence-based deletion is permitted only when a scope was fully and successfully enumerated.

Rules:

1. If a `LibraryRoot` is unavailable, preserve all known entries beneath it.
2. If a root or nested scope completes authoritatively, attempt move reconciliation and remove unmatched prior entries not observed in that exact scope.
3. If a specific scope does not complete authoritatively because it is partial, failed, cancelled, unavailable, or its owning scan is abandoned, preserve unobserved entries within that scope. An overall `ScanRun` may still be `Partial` while other exact scopes finalize authoritatively.
4. Current deterministic discovery-policy exclusions may prune previously indexed state because that state is intentionally outside the managed graph; this is distinct from provider-reported absence.
5. The same exact-scope rules apply recursively to archives and other containers.
6. Observed additions and modifications may be committed during an incomplete scan when individually valid.

### 8.6 Scan records

Persist user-relevant scan lifecycle:

```text
ScanRun
- id
- job_run_id
- library_root_id
- status
- started_at
- completed_at
- failure_reason
```

Statuses:

```text
Running
Complete
Partial
Failed
Cancelled
Abandoned
```

On startup, any scan still marked `Running` becomes `Abandoned`.

`ScanRun` is distinct from the generic `JobRun`: one job execution attempt may own multiple root scan records, and each retry creates new run identities. Only one active `ScanRun` may own a given `LibraryRoot` at a time.

### 8.7 Transaction strategy

Indexing uses in-place streaming updates with operation-level transactions.

Each coherent graph mutation is atomic, for example:

- create an entry
- update an entry
- reparent a moved entry
- replace a completely enumerated container child set
- update `GameContentSource` relationships
- remove an authoritatively absent subtree

A complete scan is not one long database transaction.

### 8.8 Move detection

Move detection is conservative and tiered:

1. Match by provider-native stable identity.
2. Otherwise match by `ContentIdentity` only when one absent prior entry and one new entry form a unique one-to-one match in the relevant reconciliation scope.
3. Otherwise treat the result as removal plus creation.

Filename similarity, timestamp-only, and size-only heuristics are excluded from the MVP.

`last_observed_scan_id` is positive-presence evidence only; it never authorizes root-wide deletion by itself. Location equality uses the provider-defined `SourceLocatorKey`, while provider-native identity remains the stronger continuity signal for moves.

## 9. Parsing and transformation engine

### 9.1 General model

Parsing is implemented as a graph of typed transformations rather than one parser per complete format stack.

```text
SourceFile
    -> ContainerContent
    -> ArchiveEntries or DiscImage
    -> FilesystemContent
    -> PlatformContent
    -> ExecutableMetadata or other requested representation
```

Each transformation declares typed inputs/outputs, bounded applicability, byte-access requirements, relative cost, stable priority, and implementation revision. Consumers request a representation; they never request a named parser chain.

An application-owned deterministic planner prefers already materialized representations, minimizes declared cost, uses explicit priority for permitted ties, and reports an invalid transformation graph when ambiguity remains. Registration order is never policy.

### 9.2 Typed representations

Examples include:

```text
SourceFile
SeekableBytes
ArchiveEntries
DiscImage
ISO9660Filesystem
PlayStationDisc
PlayStation2Disc
GameCubeDisc
NESRom
SNESRom
ExecutableMetadata
PartitionTable
RecognizedContent
CanonicalContentUnit
```

### 9.3 ParsingSession and ParsedContent

Each operation owns one session-scoped `ParsingSession` containing `ParsedContent`, immutable transformation resource budget, transient staging ownership, cumulative resource accounting, and cancellation context.

`ParsedContent` stores typed representations already produced during that session so identity/hash consumers can reuse them.

For MVP:

- parsed content is not persisted;
- intermediate representations are disposed when the operation completes;
- parser-library handles do not cross the session boundary;
- only independently meaningful persistent outputs survive.

### 9.4 Access requirements and staging

Transformations declare `Sequential`, `Seekable`, or `RandomAccess` requirements. When input cannot satisfy the required semantics directly, the planner may insert operation-scoped disk-backed staging.

For mutable reads requiring validation, a staged copy becomes trusted immutable downstream input only after the source read validates as `Consistent`. `Changed` or `Indeterminate` input cannot produce trusted immutable identity/hash facts or authoritative derived absence.

Every session runs under finite Argus-owned resource limits for staging, expansion, nesting, derived-entry count, representation size, and other potentially unbounded parser work. Resource-limit exhaustion fails safely and cannot authorize truncated derived structure.

### 9.5 Transformation outcomes

Transformation execution distinguishes:

```text
Produced<T>
NotApplicable
Failed(TransformationError)
```

Only `NotApplicable` permits deterministic fallback to another preordered candidate. Once a format is recognized, malformed, unsupported, I/O, resource, cancellation, or internal failure does not silently fall through to an unrelated parser.

### 9.6 Derived containers

Transformations describe archive/disc/virtual-container contents through application-owned `DerivedEntryObservation` values. The indexer alone reconciles those observations into persistent `SourceEntry` children.

Derived entries use transformation-owned `DerivedLocator`, `DerivedEntryKey`, and `DerivedFingerprint`. Only a `Complete` derived scope over validated stable input authorizes absence-based deletion in that exact scope.

### 9.7 Content recognition and identity

Authoritative `(PlatformId, ContentType)` recognition comes from validated transformations. Filename, extension, directory placement, and provider metadata are planning hints only.

Application policy maps each recognized content class to zero or one current canonical identity scheme. A `ContentIdentity` contains semantic `scheme_id`, strong `identity_value`, and trusted `identity_revision`.

A canonical content unit may span multiple source entries. Identity is established first from validated source data; only then does a short Unit of Work create/reuse `GameContent` and persist its exact version-bound `ContentIdentityProvenance` basis.

Each `GameContent` has at most one current identity. Scheme/revision upgrades invalidate old identity immediately and trigger targeted eager re-identification while keeping the rest of the library open. A source that produces a different identity under the same current scheme is rebound to different/new logical content rather than mutating the old `GameContent`.

## 10. Hashing subsystem

### 10.1 Explicit hash subjects

A hash scheme declares whether it describes one source representation or canonical logical content:

```text
HashSubjectScope
- SourceEntry
- GameContent
```

Source-scoped and content-scoped hashes use separate persistence concepts rather than nullable polymorphic ownership.

```text
SourceHashRecord
- id
- source_entry_id
- hash_scheme_id
- hash_value
- hashing_revision
- source_version_evidence
- computed_at
```

```text
ContentHashRecord
- id
- game_content_id
- hash_scheme_id
- hash_value
- hashing_revision
- computed_at
```

Whole-file/raw hashes normally belong to `SourceEntry`. Canonical logical hashes may belong to `GameContent` only when all equivalent supported source representations are required to produce the same value.

### 10.2 Scheme semantics and revisioning

`hash_scheme_id` identifies the complete immutable hashing procedure, including subject scope, canonicalization/input representation, byte-selection rules, digest algorithm, and any external protocol version.

`hashing_revision` identifies the current trusted Argus implementation of that unchanged semantic contract. Semantic changes require a new scheme ID; implementation corrections that invalidate prior results bump the revision.

Representative schemes may include:

```text
MD5WholeFile
SHA1WholeFile
BLAKE3CanonicalContent
RetroAchievementsNESV1
RetroAchievementsPlayStationV1
```

### 10.3 Validity

A source hash is current only when its stored `SourceVersionEvidence` and `hashing_revision` remain current.

A content hash follows its own scheme/revision validity contract. Content-identity migration does not automatically invalidate unrelated content hashes. If a canonical representation change affects both identity and a hash, each contract advances its own effective revision.

### 10.4 Demand-driven hashing

Hashing is never performed universally during indexing.

For each requested subject/scheme, the hash planner:

1. checks scope and applicability;
2. reuses a current persisted record when available;
3. builds only missing/stale representation work;
4. executes inside one `ParsingSession`;
5. reuses compatible typed representations across requested schemes;
6. validates consumed source data;
7. persists the result in a short Unit of Work.

Computing a missing/stale content-scoped hash requires usable current identity provenance. Normal hash execution does not probe untrusted alternative `GameContentSource` associations to repair identity implicitly; the dedicated re-identification workflow owns that repair.

## 11. Metadata subsystem

### 11.1 Separation of stages

Metadata processing is divided into independent stages:

```text
GameContent
    -> Match Metadata
    -> ExternalIdentityMapping
    -> Refresh Metadata
    -> ProviderMetadata
    -> MetadataResolver
    -> ResolvedMetadata
```

Tools must not implicitly invoke one another. A future composed workflow may chain them, but each tool retains one responsibility.

### 11.2 Matching

Matching produces provider identities and confidence information. It does not download full metadata or artwork.

Future interactive matching may present ranked candidates, but the MVP uses compile-time policy thresholds.

Playmatch is included as an MVP matching provider using the public server at `https://playmatch.retrorealm.dev`.

Hasheous is deferred because it requires an API key.

### 11.3 Provider capability model

Providers expose narrow capabilities through one job-scoped provider session.

```text
ProviderDescriptor
    -> static supported capabilities
ProviderReadiness
    -> current per-capability usability
ProviderSessionFactory
    -> one session per job
ProviderSession
    -> shared authenticated client, transient credential access/state, retry state, rate limiting, request cache
```

Readiness states include:

```text
Ready
Disabled
MissingCredentials
InvalidCredentials
Misconfigured
Unavailable
```

Only `Ready` satisfies prerequisites.

Provider health, circuit breaking, and cross-job runtime health indicators are explicitly post-MVP roadmap items.

### 11.4 Refresh policy

Each provider defines a compile-time `MetadataRefreshPolicy` including:

```text
stale_after
refresh_on_provider_revision_change
preserve_stale_on_failure
```

`RefreshMetadataService` evaluates eligibility and builds an immutable refresh plan. Providers execute requested fetches but do not decide workflow eligibility.

Supported invocation modes include:

```text
EligibleOnly
Force
MissingOnly
```

Refresh is manual in the MVP. Significant provider network activity must be user-initiated.

### 11.5 Refresh granularity

A metadata refresh evaluates all configured providers for each selected game. Provider policy determines which provider/game pairs are eligible.

Resolved metadata is recomputed once per game after all provider refresh attempts for that game complete.

### 11.6 Resolved values

Provider-native metadata is retained. The database also persists the resolved display projection consumed by the UI.

Resolution must retain provenance so a value can be traced to its provider and source record.

## 12. Artwork subsystem

### 12.1 Pipeline

Artwork uses separate discovery, resolution, download, and storage stages.

```text
ArtworkDiscoveryProvider
    -> ArtworkReference
    -> ArtworkResolver + ArtworkResolutionPolicy
    -> ResolvedArtwork
    -> ArtworkDownloader + ArtworkDownloadPolicy
    -> ArtworkAsset
```

### 12.2 ArtworkReference

Represents provider knowledge that an image exists remotely.

```text
ArtworkReference
- id
- provider_id
- provider_asset_id
- external_game_id
- canonical_type
- native_type
- source_url
- thumbnail_url
- width
- height
- format
- region
- language
- variant_tags
- discovered_at
```

### 12.3 Canonical artwork taxonomy

Argus uses a fixed canonical taxonomy grounded in established ecosystems such as RomM and SteamGridDB while preserving provider-native types and tags.

MVP types:

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

Cardinality:

- Single resolved asset for all types except `Screenshot`.
- Ordered multiple assets for `Screenshot`.

### 12.4 Resolution policy

`ArtworkResolutionPolicy` controls candidate scoring, including:

- provider priority
- region and language fit
- image resolution
- aspect-ratio suitability
- official or preferred variants
- screenshot limit
- duplicate suppression
- gallery diversity

Screenshot selection scores candidates across providers, removes duplicates, and favors a diverse gallery rather than taking every image from the highest-priority provider.

### 12.5 ResolvedArtwork

Resolved artwork points first to a reference and optionally to a downloaded asset:

```text
ResolvedArtwork
- game_content_id
- artwork_type
- reference_id
- asset_id nullable
- ordering where applicable
- resolution_reason
- resolved_at
```

Resolution is independent of download state.

### 12.6 Download policy and storage

For MVP:

- Download only resolver-selected artwork.
- Preserve original provider bytes.
- Store immutable content-addressed assets.
- Do not resize, recompress, or convert images.

```text
ArtworkAsset
- asset_id (BLAKE3 of bytes)
- width
- height
- format
- mime_type
- size_bytes
- storage_path
- created_at
```

Filesystem storage is a pure object store. Game, provider, and type relationships remain in the database.

Post-MVP roadmap:

- User-selected artwork candidates, especially SteamGridDB variants
- User-locked artwork overrides
- Original-plus-derived thumbnail and optimized cache variants

## 13. RetroAchievements subsystem

### 13.1 Purpose

RetroAchievements verification answers:

> Does RetroAchievements recognize this exact local content hash?

It is independent from metadata identity resolution.

### 13.2 Unit of verification

Verification is performed once per `GameContent`, not once per source path or metadata identity.

```text
GameContent
    + HashRecords
    -> RetroAchievementsVerificationService
    -> AchievementVerification
```

### 13.3 Rich verification states

Persist detailed outcomes:

```text
Recognized
NotRecognized
UnsupportedPlatform
NoEligibleHash
ProviderUnavailable
VerificationFailed
```

The Flutter UI may collapse these into simpler presentation categories while preserving the backend result.

Recognition and achievement availability are separate facts. A recognized game may currently have zero achievements.

### 13.4 Catalog caching

Argus internally retrieves the complete game and hash list per supported RetroAchievements platform using the `Get Game List` endpoint with hashes enabled and without filtering out games lacking achievements.

Catalog refresh is internal to the user-facing `Verify RetroAchievements` operation and is not exposed as a standalone tool.

Normal verification is a local indexed lookup against the active cached catalog.

### 13.5 Catalog persistence

Use normalized relational records:

```text
RAPlatformCatalog
- id
- ra_console_id
- generation
- refreshed_at
- provider_revision
- status

RAGameRecord
- catalog_id
- ra_game_id
- title
- achievement_count
- date_modified

RASupportedHash
- catalog_id
- ra_game_id
- normalized_hash
```

Required uniqueness/indexing includes:

```text
UNIQUE (catalog_id, ra_game_id)
UNIQUE (catalog_id, normalized_hash)
INDEX (normalized_hash)
```

### 13.6 Catalog generations

Catalog refresh uses immutable generations:

1. Create an importing generation.
2. Fetch and normalize the complete platform catalog.
3. Validate completeness and constraints.
4. Atomically activate the new generation.
5. Retire and immediately delete the previous generation.
6. Delete failed or abandoned importing generations.

Verification records retain the generation identifier as historical evidence but do not foreign-key to deleted generations.

### 13.7 Verification freshness

`RetroAchievementsVerificationPolicy` defines status-specific freshness:

- recognized results are long-lived and become eligible after catalog or hashing revision changes
- unrecognized results have a shorter stale interval
- unsupported-platform results depend on platform-support revision
- no-eligible-hash results depend on parser or hash-scheme revision
- provider and processing failures are immediately retryable

A catalog-generation mismatch makes prior results eligible, but only the current explicit user operation determines actual verification scope.

### 13.8 Platform mapping

Argus `PlatformId` to RetroAchievements console ID mapping is compile-time provider configuration. There is no runtime string matching or persisted mapping table.

## 14. Job and execution architecture

### 14.1 Persisted jobs

Only user-visible operations are persisted as jobs. Internal work items remain ephemeral.

```text
JobRun
- id
- job_type
- status
- progress
- created_at
- started_at
- completed_at
- result
- error
- cancellation_requested
```

Representative jobs:

- Scan Library
- Match Metadata
- Refresh Metadata
- Refresh Artwork
- Verify RetroAchievements

### 14.2 Job states

The job lifecycle keeps preparation separate from execution. The agreed conceptual states are:

```text
Queued
Preparing
Running
Completed
Failed
Cancelled
```

The tool requests transitions; the scheduler has final authority over valid state transitions.

### 14.3 Progress reporting

All tool output, including progress, flows through the event channel.

The progress API supports:

- status text during `Preparing`, such as “Finding eligible games”
- tool-controlled transition request to `Running`
- numeric progress after work scope is known
- item definition controlled by the tool
- bounded advancement that can never exceed total

The scheduler validates progress invariants and is authoritative over persisted job state.

### 14.4 Execution graphs

All planners produce immutable directed acyclic execution graphs.

```text
Planner
    -> ExecutionGraph
    -> Scheduler
    -> Executor registry
    -> Executors
```

The graph defines what should happen. Runtime execution state is maintained separately.

The scheduler understands only:

- dependencies
- readiness
- cancellation
- completion
- retry/failure policy

It does not interpret domain payloads.

### 14.5 Graph composition

Planners remain domain-specific and compose work by submitting additional graphs rather than building one giant cross-domain graph.

For example, a composed user workflow may run:

```text
Index graph
    -> Hash graph
    -> Metadata graph
    -> Artwork graph
    -> RetroAchievements graph
```

The scheduler remains unaware of application workflow meaning.

### 14.6 Scheduler generality

The scheduler must contain no tool-specific or provider-specific logic.

Execution-node payloads are opaque to the scheduler and dispatched by executor type.

### 14.7 Cancellation and retries

Detailed retry budgets and cancellation checkpoints are implementation-plan items, but the architecture requires:

- cooperative cancellation
- persisted cancellation request on `JobRun`
- executors checking cancellation at safe boundaries
- provider-owned request retries and rate limiting
- scheduler-owned node and graph state transitions
- no retry loop capable of advancing progress beyond total

## 15. Application layer

### 15.1 Domain façades and use-case handlers

Flutter interacts with a compact set of domain-oriented application façades.

Conceptual examples:

```text
LibraryService
GameService
ArtworkService
JobService
SettingsService
DiagnosticService
```

Each façade method delegates to a focused use-case handler.

```text
LibraryService.scan(root_id)
    -> ScanLibraryHandler
    -> IndexPlanner
    -> Scheduler.submit(graph)
```

Façades do not expose repositories, planners, graphs, or executors.

### 15.2 CommandResult

Accepted asynchronous commands return one standard envelope:

```text
CommandResult
- command_id
- job_run_id nullable
- accepted_at
- warnings
- affected_scope
- undo_token nullable
```

Synchronous validation errors return application errors and do not create jobs.

`Accepted` must never be presented as `Completed` when a background job exists.

### 15.3 Command-level undo

Undo is a command capability, not a global history stack.

Undoable commands may return an `undo_token`. Flutter invokes a backend undo command with that token.

Undo is generally appropriate for user edits such as:

- metadata overrides
- artwork selection
- favorite/hidden state
- tags
- selected settings changes

It is not appropriate for scans, hashing, provider refreshes, verification, migrations, or startup.

For MVP, undo tokens may expire and do not survive application restart.

### 15.4 Unit of Work

Use-case handlers own the `UnitOfWork` lifecycle.

The Unit of Work:

- owns the database transaction
- exposes transaction-bound repositories
- commits authoritative state and core projections atomically
- rolls back on failure

Repositories never start or commit transactions themselves.

Long-running jobs use one Unit of Work per coherent execution node or mutation, not one transaction for the entire job.

## 16. Query and projection architecture

### 16.1 Hybrid reads

Use normalized repositories for:

- entity details
- editing
- workflow validation
- low-volume administrative queries

Use dedicated read projections for:

- library grid/list
- search
- filters and facets
- dashboards
- jobs and diagnostics history

### 16.2 Projection consistency

Core UI projections update transactionally with authoritative writes.

Examples:

```text
GameLibraryRow
- game_id
- display_title
- platform_id
- region
- selected_artwork_id
- verification_state
- source_count
- updated_at
```

Expensive derived projections may update asynchronously or rebuild on demand:

- full-text search indexes
- aggregate counts
- dashboard summaries
- duplicate summaries
- storage statistics

Essential library views must not depend on lossy transient events for correctness.

### 16.3 Pagination

Use cursor pagination for large mutable datasets, including library browsing and search.

Use offset pagination for bounded administrative datasets, such as providers, roots, short job histories, settings, and diagnostics.

Sorting exposes one user-selected primary field and direction. The backend appends stable tie-breakers ending in a unique identifier.

## 17. Domain events

### 17.1 Purpose

The backend publishes immutable facts after authoritative state commits.

Examples:

```text
JobStarted
JobProgressChanged
JobCompleted
JobFailed
LibraryScanCompleted
SourceEntriesChanged
GamesAdded
GamesRemoved
MetadataUpdated
ArtworkUpdated
VerificationUpdated
SettingsChanged
DiagnosticRaised
```

Events never represent commands.

### 17.2 Durability

Events are transient and in-memory for live coordination.

Durable state lives in purpose-built records such as:

- `JobRun`
- `ScanRun`
- diagnostics
- current domain and projection tables

There is no general append-only event log in the MVP.

### 17.3 Delivery

Delivery is asynchronous and best effort:

- publishers do not wait for subscribers
- each subscriber has a bounded queue
- compatible events, especially progress and entity-update events, are coalesced
- non-coalescible overflow drops the oldest queued event
- process-local sequence numbers allow subscribers to detect gaps
- gap detection triggers re-query of authoritative state

Persistence must commit before publication.

## 18. Privacy and provider data sharing

Argus submits file-derived identifiers, including hashes, to external services such as RetroAchievements and Playmatch where required by enabled workflows.

Use of Argus is conditional on accepting development privacy terms that disclose this behavior. If the user declines, Argus exits and cannot be used.

Final legal and privacy copy will be supplied before public release. The implementation must keep the acceptance mechanism and versioned consent record separate from final wording.

Credentials are managed and retrieved by the credential service. They must not be embedded in settings records, logs, diagnostic bundles, events, or bridge DTOs.

## 19. Flutter architecture

### 19.1 Responsibilities

Flutter owns:

- rendering
- interaction
- navigation
- responsive layout
- local and screen presentation state
- selection, filtering, and sorting state
- error and progress presentation

Rust owns:

- domain validation
- business workflows
- persistence
- planning and scheduling
- indexing and processing
- authoritative job state
- provider behavior

Flutter widgets never call generated bridge bindings directly.

### 19.2 State management

Use Riverpod for dependency injection and state exposure.

All providers use Riverpod code generation for consistency.

Provider hierarchy:

```text
App composition providers
    -> ArgusClient, event coordinator, startup, restart state
Feature-local providers
    -> focused API adapter, controllers, selection, inspector, drafts
Widgets
    -> watch feature-local providers only
```

Controllers expose `AsyncValue<State>` for initial readiness. After initial success, explicit operational state represents refresh, pagination, commands, and local errors while preserving usable data.

A loaded screen must not return to global loading because of a background operation.

### 19.3 Immutable models

All immutable Dart models use Freezed, including:

- shared domain primitives
- read models
- UI models
- controller states
- drafts
- validation results
- route state
- operational-state unions
- settings models
- event models

Mutable collections must not leak through model APIs.

### 19.4 Bridge

Use `flutter_rust_bridge`.

Only dedicated bridge DTOs cross the native boundary. Rust repositories, entities, domain aggregates, planners, graph nodes, and provider-native models remain private.

Long-running commands return quickly with a bridge `OperationHandleDto` representing admitted operation identity and are tracked through jobs and events. Backend application-layer command-result semantics remain internal to Rust.

Rust domain events are exposed as one application-level Dart stream.

### 19.5 ArgusClient

Flutter has one root backend gateway with focused application APIs:

```text
ArgusClient
- runtime
- library
- games
- jobs
- settings
- sources
- diagnostics
- events
```

The root owns:

- generated bindings
- lifecycle and readiness
- common error translation
- event connection
- tracing
- cancellation/timeout policy
- shared mapping infrastructure

Features depend on narrow API interfaces rather than the concrete root client.

The startup feature is not given the full root client. Root composition exposes the initialization contract through a narrow lifecycle seam, while runtime/recovery and ordinary feature work use the applicable focused APIs.

### 19.6 Model mapping

Use two-stage mapping:

```text
Bridge DTO
    -> focused client API mapper
    -> frontend read model
    -> feature presentation mapper
    -> UI model
```

Bridge DTOs never enter feature code. Client APIs do not return widget-specific models.

Read models are owned by the focused API that produces them by default and deliberately promoted to shared read-model modules only when no single API remains their natural owner.

### 19.7 Typed identifiers

Bridge DTOs use serialization-friendly strings for IDs.

`ArgusClient` converts them into typed Dart IDs such as:

```text
GameId
JobRunId
LibraryRootId
SourceEntryId
PlatformId
```

Flutter application and feature code must use typed IDs.

### 19.8 Project organization

Use feature-first organization with explicit internal layers.

```text
lib/
- app/
  - bootstrap/
  - routing/
  - shell/
  - actions/
- core/
  - bridge/
  - client/
  - domain/
  - events/
  - errors/
  - responsive/
  - design_system/
  - utilities/
- features/
  - library/
  - game_detail/
  - jobs/
  - settings/
  - startup/
  - diagnostics/
  - sources/
```

Substantial features may contain:

```text
application/
models/
presentation/
routing/
src/
```

Small features must not create empty layers merely to follow a template.

### 19.9 Feature boundaries

Features have directed dependencies and expose small purpose-specific public APIs.

Examples:

```text
library_routes.dart
library_models.dart
library_actions.dart
library_destination.dart
```

Consumers may not import another feature's `src/` implementation files.

Circular feature dependencies are prohibited. Shared concepts belong in `core`, or composition belongs in `app`.

### 19.10 Shared domain primitives

Stable cross-feature primitives live in `core/domain` behind purpose-specific entry points:

```text
domain_ids.dart
domain_commands.dart
domain_pagination.dart
domain_time.dart
```

`core/domain` must avoid Flutter, Riverpod, features, and bridge-generated dependencies so it can be extracted into a separate package later.

### 19.11 Routing

Use `go_router`.

Routes represent durable location and scope. Riverpod owns transient interaction state.

Library scope uses hierarchical routes:

```text
/library
/library/collections/:collectionId
/library/platforms/:platformId
/library/sources/:sourceId
/library/library-roots/:libraryRootId
```

Temporary filters, sorting, and view mode use query parameters.

Game selection is route-addressable and presents differently by available width without changing the route identity.

### 19.12 Application shell

A persistent application shell owns:

- adaptive primary navigation
- global toolbar/chrome
- active-job indicator
- transient toasts
- backend/startup status
- restart-required banner
- routed content

Navigation modes:

- **Compact:** bottom navigation with `Library`, `Collections`, `Jobs`, and `More`
- **Medium:** icon navigation rail
- **Expanded/Large:** full sidebar with icons and labels

`More` contains lower-frequency destinations on compact layouts, such as diagnostics and settings.

### 19.13 Responsive layout

Argus supports desktop, tablet, and phone based on available width, not hardware category.

Define global window size classes, conceptually:

```text
Compact
Medium
Expanded
Large
```

Exact logical-pixel thresholds are a design-system decision and must be centralized.

Use:

- window size classification for application structure
- `LayoutBuilder`-style local constraints for component adaptation

A wide window can contain a narrow nested pane; components must respond to their own constraints.

### 19.14 Library browsing

The library supports both grid and list presentation with shared query, filter, sorting, pagination, and selection state.

List presentation is adaptive:

- compact/medium: responsive rows
- expanded/large: virtualized table-like aligned rows

Grid and list maintain independent scroll restoration.

The library uses:

- navigation sidebar/scope selector
- search
- temporary filter chips
- single primary sort with stable backend tie-breakers
- cursor pagination

Library scope and temporary filters are distinct models.

### 19.15 Filtering

Use a typed `LibraryFilter` model.

Semantics:

- multiple values within one category combine with `OR`
- different categories combine with `AND`

A generic nested Boolean expression language is deferred.

### 19.16 Selection

Use adaptive multi-selection.

Desktop:

- click selects one
- Cmd/Ctrl-click toggles
- Shift-click/range selection
- arrow-key focus
- Space toggles
- Enter opens detail

Phone/tablet:

- tap opens detail
- long press enters selection mode
- additional taps toggle
- contextual action bar presents bulk actions

Track focused item, selected items, range anchor, and open detail route separately.

### 19.17 Game detail

Use adaptive master-detail presentation:

- compact: full routed detail page
- medium: full detail by default
- expanded/large: collapsible, resizable inspector pane

The same route and controller state drive all layouts.

Compact detail uses a scrolling page with collapsible sections. Wide inspector presentation uses tabs for major categories.

Detail data loads incrementally. Overview renders first; expensive sections load when opened.

Use a parent `GameDetailCoordinator` plus independent section controllers for metadata, files, artwork, achievements, diagnostics, and history.

### 19.18 Editing

Use section-scoped drafts with explicit Save and Cancel for game/detail edits.

Settings are the exception and persist immediately.

Game-edit conflict policy is last-write-wins. Background updates must never overwrite an active local draft before the user saves or cancels.

### 19.19 Feedback and notifications

Use layered feedback:

- immediate actions: inline feedback
- accepted background commands: transient toast plus persistent shell job indicator
- long-running operations: jobs UI and local progress where relevant
- failures: inline when possible, otherwise toast plus job details

MVP uses transient notifications only. A lightweight actionable inbox is post-MVP.

### 19.20 Startup and recovery

MVP uses a blocking startup screen while Rust bridge initialization, database opening, migrations, and core-service startup complete.

Do not wait for library queries, scans, metadata, or secondary data.

Client/bootstrap failure before Flutter can obtain a trustworthy runtime contract presents a bootstrap failure surface with only client-available actions. A successfully reported backend `StartupFailed` runtime presents the targeted recovery screen with only the recovery capabilities advertised for that failed runtime generation.

Provide both:

- copyable technical details
- exportable diagnostic ZIP bundle

Diagnostic bundles must exclude ROMs, BIOS files, credentials, tokens, artwork cache, save data, and unnecessary personal information.

### 19.21 Settings

Settings are grouped into strongly typed domains coordinated by `SettingsService`, for example:

```text
AppearanceSettings
LibrarySettings
ProcessingSettings
MetadataSettings
ArtworkSettings
DiagnosticsSettings
AdvancedSettings
```

Flutter uses one controller per settings domain.

Settings persist immediately:

- toggles/selectors save on change
- text values save on submit or focus loss
- paths save after picker confirmation
- credentials save after credential-dialog confirmation

Failed persistence reverts the control to the last confirmed value and shows an inline error.

Restart-required settings persist immediately but expose both active and persisted values. The shell shows one global restart-required state and offers restart now or later.

### 19.22 Application actions and shortcuts

Define a central semantic `ApplicationAction` registry containing:

```text
id
title
description
category
icon
default_shortcut
availability
```

Menus, toolbar controls, context menus, and keyboard shortcuts invoke the same actions.

Controllers implement feature behavior; the registry does not contain business logic.

The command palette and user-customizable shortcuts are post-MVP.

## 20. Error model and diagnostics

Errors crossing into Flutter must be structured and stable.

Conceptual UI-facing model:

```text
UiError
- code
- title
- message
- recovery_actions
- diagnostic_id
- field_errors where applicable
```

Raw Rust errors and stack traces are not default user-facing copy.

Diagnostics requirements:

- structured Rust logging
- trace IDs (`trace_id`) for commands, jobs, scans, and provider requests
- sanitized diagnostic export contributors
- job and scan failure details
- startup-specific log capture
- no secrets in logs or bundles

## 21. Persistence requirements

The concrete schema will be specified in implementation plans, but persistence must support:

- versioned migrations
- foreign-key enforcement
- WAL or another appropriate SQLite concurrency mode
- repository isolation
- Unit of Work transaction ownership
- transactional core read projections
- indexed cursor-pagination sort keys
- normalized provider and RetroAchievements catalogs
- content-addressed artwork metadata
- cleanup of abandoned catalog/import generations
- explicit schema tests and migration tests

Database location and backup/recovery policy must be designed before the first public release. Save-management storage is not part of the MVP.

## 22. Security requirements

- Credentials are stored through a credential service appropriate to each target platform.
- Secrets never enter normal settings serialization.
- Secrets are never included in events, logs, diagnostics, bridge DTOs, or UI read models.
- External provider URLs and responses are treated as untrusted input.
- Archive and container parsing must enforce resource limits and avoid unsafe path traversal.
- Source-provider locators must be normalized and validated.
- Link traversal is disabled in MVP.
- Destructive startup recovery actions require explicit confirmation and preserve the old database where practical.

## 23. Testing strategy

### 23.1 Rust backend

Required test layers:

- unit tests for domain policies and value objects
- planner tests producing deterministic execution graphs
- scheduler state-machine tests
- repository contract tests
- migration tests from every supported schema version
- provider adapter tests with recorded or fake responses
- reconciliation tests for complete, partial, failed, cancelled, and unavailable scopes
- move-detection ambiguity tests
- parser transformation-path tests
- hash revision and invalidation tests
- metadata and artwork resolution tests
- RetroAchievements catalog generation and verification tests
- Unit of Work rollback and projection consistency tests

### 23.2 Bridge

- DTO mapping tests in Rust
- generated binding smoke tests
- Dart fixture/contract tests
- error translation tests
- event-stream sequence and gap tests
- cancellation propagation tests

### 23.3 Flutter

- controller tests with focused API fakes
- provider override tests
- widget tests for initial, loaded, empty, refreshing, partial failure, and retry states
- responsive layout tests for all size classes
- keyboard and focus tests on desktop
- selection behavior tests for desktop and touch interactions
- route parsing and restoration tests
- startup/recovery flow tests
- settings immediate-persistence and rollback tests
- golden tests for stable design-system components and major responsive layouts where useful

### 23.4 End-to-end scenarios

At minimum:

1. Add a local root and scan it.
2. Rescan after adding, moving, modifying, and deleting content.
3. Disconnect and reconnect a root without losing indexed data.
4. Match metadata through Playmatch.
5. Refresh provider metadata and resolve display values.
6. Discover, resolve, and download artwork.
7. Refresh RetroAchievements catalogs and verify recognized, unrecognized, and zero-achievement games.
8. Cancel a long-running job.
9. Recover UI state after a dropped event sequence.
10. Restart after a restart-required setting change.
11. Export a sanitized startup diagnostic bundle.

## 24. Implementation strategy

Implementation must be sliced into independently testable increments. No Codex task should be “implement Argus.”

Recommended dependency order:

### Slice 1: Repository and workspace foundation

- Rust and Flutter workspace layout
- formatting, linting, and CI
- core typed IDs and shared errors
- SQLite access and migration framework
- Unit of Work skeleton
- Flutter application bootstrap
- code-generation workflow

### Slice 2: Job and event infrastructure

- `JobRun`
- scheduler state machine
- immutable execution graph contracts
- executor registry
- cancellation
- transient event bus
- Flutter event stream and coordinator

### Slice 3: Source provider foundation

- source/provider traits
- provider capability model
- local filesystem provider
- `LibrarySource` and `LibraryRoot`
- availability checks
- discovery policy

### Slice 4: Indexing and reconciliation

- `SourceEntry` graph
- `ScanRun`
- streaming discovery
- operation-level transactions
- classification
- authoritative deletion
- conservative move detection
- initial library projection

### Slice 5: Game-content resolution

- content-candidate selection
- `GameContent`
- source relationships
- content fingerprints and identity
- duplicate-source handling

### Slice 6: Transformation and hashing

- typed representation registry
- transformation planner and session
- initial format parsers
- hash-scheme descriptors and executors
- demand-driven hash planning
- hash persistence and revision invalidation

### Slice 7: Metadata matching and providers

- provider descriptors, readiness, and job-scoped sessions
- credential abstraction
- Playmatch integration
- external identity mappings
- matching policy and reports

### Slice 8: Metadata refresh and resolution

- provider metadata tables
- refresh policy and plan
- resolved metadata projection
- failure preservation and provenance

### Slice 9: Artwork

- canonical taxonomy
- artwork references
- resolution policy
- screenshot scoring and deduplication
- resolved artwork projection
- content-addressed download storage

### Slice 10: RetroAchievements

- compile-time platform mapping
- catalog download and normalization
- immutable catalog generations
- local hash lookup
- verification policy and persistence
- verification report

### Slice 11: Application façades and read APIs

- command/result DTOs
- domain façades and use-case handlers
- cursor and offset query contracts
- focused read projections
- bridge DTOs and `flutter_rust_bridge` surface

### Slice 12: Flutter application shell

- Riverpod composition root
- `ArgusClient` focused APIs
- `go_router`
- adaptive navigation
- startup and recovery UI
- job indicator and layered feedback
- design-system foundations

### Slice 13: Library UI

- grid and adaptive list/table
- typed filters and scopes
- cursor pagination
- selection and keyboard behavior
- route synchronization
- inspector shell

### Slice 14: Game detail and settings

- parent detail coordinator
- section controllers
- adaptive detail presentation
- section drafts
- immediate-persistence settings
- restart-required state

### Slice 15: Diagnostics and hardening

- diagnostic contributors
- support bundle export
- security review
- performance profiling
- large-library testing
- packaging and release readiness

## 25. Codex implementation rules

Every implementation plan and Codex task must include:

- exact files to inspect
- exact files permitted to change
- explicit interfaces consumed and produced
- one independently testable deliverable
- tests written before or alongside implementation
- exact verification commands
- explicit exclusions
- a local commit boundary

Additional rules:

- Do not invent new architectural patterns without updating this document or an approved subordinate design spec.
- Keep each task small enough for a fresh reviewer to approve or reject independently.
- Prefer vertical slices that leave the repository compiling and tests passing.
- Do not combine unrelated refactoring with feature work.
- Generated files are committed when required by the chosen Flutter generation workflow and verified in CI.
- Architectural dependency rules must be enforced with lints or architecture tests rather than documentation alone.

## 26. Post-MVP roadmap commitments

The following items have been explicitly identified for future consideration:

- Provider health, health UI, circuit breakers, and cross-job health state
- Concurrent discovery
- Filesystem watching
- Persistent actionable notification inbox
- Command palette and shortcut customization
- User-selected and user-locked artwork candidates
- Derived artwork variants and thumbnail cache
- Hasheous provider
- Achievement details and user progress
- Save-data management
- Parsed-content persistence for proven bottlenecks
- General plugin/extension system
- Additional source providers
- Full or richer undo history if justified

These roadmap items must build on the existing contracts rather than being partially embedded in MVP implementations.

## 27. Architectural invariants

The following invariants are non-negotiable unless this architecture is formally revised:

1. Rust is the authoritative owner of business rules and persistence.
2. Flutter never accesses repositories, SQLite, planners, the scheduler, or provider implementations directly.
3. Widgets never call generated bridge bindings directly.
4. Significant background work is user-initiated in the MVP.
5. The scheduler contains no tool-specific or provider-specific logic.
6. Progress cannot advance beyond its declared total.
7. An incomplete or unavailable scan cannot delete unobserved source entries.
8. Provider-native data and resolved projections remain separate.
9. RetroAchievements verification is content/hash-centric, not metadata-title-centric.
10. Existing usable UI content remains interactive during background operations.
11. Bridge DTOs do not leak into feature code.
12. Feature internals are not imported across feature boundaries.
13. Core read projections update transactionally with authoritative writes.
14. Events notify; they are not the sole durable record of state.
15. Save management remains outside MVP scope.

## 28. Follow-up design documents

This overview is intentionally broad. Before implementation of each major slice, create a subordinate design or implementation plan containing concrete schemas, Rust traits, Dart interfaces, filenames, test cases, and migration details.

Priority follow-up documents:

1. Repository/workspace and module layout
2. SQLite schema and migration strategy
3. Execution graph and scheduler contract
4. Source-provider and indexing contract
5. Transformation and hash-scheme contract
6. Metadata provider and resolution contract
7. Artwork object-store contract
8. RetroAchievements catalog and verification contract
9. Rust-to-Flutter bridge DTO contract
10. Flutter design system and responsive breakpoint specification

This document remains the high-level source of truth that subordinate specifications must satisfy.
