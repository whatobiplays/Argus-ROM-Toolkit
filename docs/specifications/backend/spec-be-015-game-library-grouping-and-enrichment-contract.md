# Game Library, Grouping, and Enrichment Contract Specification

**Document ID:** SPEC-BE-015  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-09-03  
**Depends On:** ARCH-001, ARCH-002, PHASE-003, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-006, SPEC-BE-007, SPEC-BE-009, SPEC-BE-010, SPEC-BE-012, SPEC-BE-013, SPEC-BE-014, SPEC-X-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the backend contract that turns trustworthy exact `GameContent` identities into a durable platform-specific logical game Library and automatically enriches those games with provider metadata and artwork.

It owns the Phase 003 `Game`/`GameMembership` domain, conservative grouping/re-grouping, orphan visibility, production provider activation, external identity mappings, metadata/artwork refresh and deterministic resolution, Library projections, and the composed `Refresh Library` / `Refresh Game` workflows.

The governing rule is:

> Exact local content identity remains independent from external services; Argus groups exact content into a durable platform-specific `Game`, treats provider results as replaceable evidence, resolves the best available presentation deterministically, and composes explicit user-initiated refresh work without creating a second scheduler or provider-owned source of truth.

## 2. Responsibilities

SPEC-BE-015 owns:

- durable `GameId`, `Game`, and `GameMembership` semantics;
- one-current-Game membership for each active `GameContent`;
- conservative grouping and regrouping policy;
- stable Game-ID behavior across merges and splits;
- orphaned content/game activity semantics;
- provider activation for Playmatch, GameTDB, and SteamGridDB;
- provider enablement/readiness as consumed by enrichment;
- `ExternalIdentityMapping` semantics;
- matching thresholds and unresolved behavior;
- provider metadata persistence/freshness;
- deterministic Game-level metadata resolution;
- region/language presentation preference semantics;
- artwork references, resolution, selected downloads, and Game-level ownership;
- `GameLibraryRow` and related query-projection semantics;
- `Refresh Library` and `Refresh Game` eligibility/composition;
- partial-success, cancellation, retry, and recovery behavior;
- Game/enrichment events and diagnostics boundaries.

## 3. Non-Responsibilities

This specification does not define:

- source indexing or root authority;
- per-format parsing/canonical identity semantics owned by BE-012/BE-014;
- concrete HTTP client or credential-store implementation;
- Flutter navigation/widget behavior owned by FE-010;
- manual metadata editing or manual artwork selection/locking;
- collections/favorites/playlists;
- cross-platform title/franchise grouping;
- RetroAchievements verification;
- autonomous periodic refresh;
- an application-wide generic workflow scheduler.

## 3.1 Platform Applicability

The domain, provider, resolver, persistence, query, and refresh semantics are shared across desktop and Android.

Platform-adapted concerns are limited to credential-store implementation, source-provider access, Android foreground execution hosting, and frontend presentation. They do not alter `Game`, grouping, provider, or resolution authority.

## 4. Architectural Position

Phase 003 composes:

```text
SourceEntry
   ↓
BE-012/BE-014 identification
   ↓
GameContent
   ↓
ensure provisional Game membership
   ↓
provider matching / local relationship evidence
   ↓
Game grouping reconciliation
   ↓
provider metadata + artwork discovery
   ↓
deterministic Game-level resolution
   ↓
GameLibraryRow / Game detail
```

The provisional Game step guarantees trustworthy identified content can exist in Library even when every external provider is unavailable. Provider matching can later contribute grouping evidence, but provider identity never becomes `GameId` or `GameContent` identity.

## 5. `Game`

Conceptually:

```text
Game
- id: GameId
- platform_id: PlatformId
- created_at
- updated_at
- grouping_revision
- lifecycle_state
```

`GameId` is an opaque Argus-owned durable identity.

`Game` invariants:

1. exactly one `PlatformId`;
2. zero or more historical memberships, at least one current membership while active;
3. provider IDs are never the Game primary key or durable identity;
4. provider outages/rematches do not replace the Game;
5. metadata/artwork replacement does not replace the Game;
6. one Game may contain regional, language, normal revision, equivalent representation, or multi-disc `GameContent` where evidence permits;
7. cross-platform content cannot share one Game.

### 5.1 Lifecycle state

```text
GameLifecycleState
- Active
- InactiveOrphan
- Redirected
```

`Active` means at least one current member content has not been authoritatively orphaned. A temporarily unavailable root/removable volume may make that content unavailable for immediate reads while the Game remains Active in the logical Library.

`InactiveOrphan` means every current member content has authoritative final-source absence, but durable identity/grouping/enrichment is retained.

`Redirected` is a retained route/history identity that was absorbed during deterministic grouping merge and points to one surviving `GameId`.

A redirected Game does not appear as a normal Library row.

## 6. `GameMembership`

Conceptually:

```text
GameMembership
- game_id
- game_content_id
- relationship
- grouping_basis
- grouping_revision
- created_at
- updated_at
```

Current relationship values are closed:

```text
PrimaryContent
RegionalVariant
LanguageVariant
RevisionVariant
Disc
EquivalentReleaseRepresentation
```

Each `GameContent` has exactly one current `GameMembership`. Historical audit representation may be retained separately, but no content simultaneously appears in two current Games.

### 6.1 Primary member

Each non-empty current Game has exactly one `PrimaryContent` membership. It is an internal deterministic anchor, not a user assertion that the underlying file is a preferred region/revision.

When no stronger preference exists, the anchor is selected by stable membership creation order and then `GameContentId` tie-break.

## 7. Grouping Evidence

Grouping is conservative. Accepted evidence includes:

- exact same `GameContent` identity, which is already collapsed before Game grouping;
- an explicit validated multi-disc/playlist relationship from local content structure, including M3U evidence defined by SPEC-BE-014;
- compatible trusted provider mappings that identify members as releases/variants/discs of the same platform game;
- platform-native product/release identifiers extracted by validated transformations when the owning format specification establishes their semantics;
- a combination of region/revision/language evidence plus a trusted common external game/release-family mapping.

The following are not sufficient by themselves:

- filename similarity;
- normalized display-title similarity;
- common parent folder;
- matching artwork;
- same provider search result title without an accepted mapping;
- user locale;
- source root.

Ambiguity means separate Games.

### 7.1 Materially distinct products

The following remain separate unless a future explicit contract supersedes this rule:

- Pokémon Red versus Pokémon Blue or equivalent paired distinct products;
- game versus demo/trial;
- original versus substantial remake;
- base game versus materially distinct expansion/edition;
- commercial original versus ROM hack/homebrew with its own identity;
- different platforms.

## 8. Provisional Membership and Reconciliation

When new trustworthy `GameContent` has no current membership, Argus creates a new provisional single-content `Game` immediately. This requires no provider access.

A later `GameGroupingService` reconciliation may merge or split memberships when new trustworthy evidence appears or old evidence becomes invalid.

Conceptually:

```text
reconcile_game_memberships(game_content_ids, evidence_snapshot, grouping_revision)
    -> GameGroupingResult
```

The reconciliation service receives application-owned evidence; it does not call providers or repositories from domain policy.

### 8.1 Merge stability

When two or more existing Games become one equivalence class:

1. choose the surviving `GameId` by earliest `created_at`, then stable `GameId` ordering;
2. capture each absorbed Game's pre-merge `PrimaryContent` as its immutable `continuity_anchor_game_content_id`;
3. atomically move current memberships to the survivor;
4. recompute exactly one `PrimaryContent` anchor for the survivor;
5. mark absorbed Games `Redirected` to the survivor while retaining their continuity anchors;
6. flatten any pre-existing redirect chain to the current survivor without changing the historical redirect's own continuity anchor;
7. preserve history/job references to old Game IDs;
8. re-resolve metadata/artwork for the survivor after commit.

Redirect persistence enforces one canonical target, no self-target, and no cycle. Routing/query APIs follow the bounded flattened redirect and return the current canonical Game ID.

### 8.2 Split stability

When one Game must split into multiple evidence classes:

1. retain the original `GameId` for the class containing the existing deterministic primary anchor;
2. create new Game IDs for other classes;
3. move memberships atomically;
4. for every historical redirected Game whose `continuity_anchor_game_content_id` belongs to the split membership set, retarget that redirect to the resulting Game containing its anchor;
5. independently re-resolve each resulting Game;
6. do not infer manual user intent because Phase 003 has no manual grouping overrides.

Membership movement and redirect retargeting commit atomically, so an old route never resolves to the wrong post-split variant merely because its prior survivor retained the original `GameId`. A missing or contradictory continuity anchor is an invariant violation, not permission to guess from title/provider data.

### 8.3 `grouping_revision`

Grouping policy is application-owned and versioned.

A policy correction that may change memberships increments `grouping_revision` and makes affected Games eligible for targeted grouping maintenance. It does not trigger source re-indexing or canonical content re-identification unless those independent facts are stale.

## 9. Duplicate, Presence, and Orphan Semantics

Multiple physical copies converge to one `GameContent` through BE-012 `GameContentSource` associations. They therefore contribute one membership and one normal Library item.

Content presence is an application-owned lifecycle fact independent from BE-012 identification state:

```text
GameContentPresenceState
- Active
- Orphaned
```

`Active` means at least one current source association exists, even when every associated root is temporarily unavailable. `Orphaned` means authoritative source reconciliation removed the final current source association. Temporary `Unavailable` roots/removable media never prove absence and never transition content to `Orphaned`.

On final-source absence, the coherent BE-011/BE-012 handoff:

- removes current source associations and invalid provenance;
- clears current identity proof;
- may retain the narrow non-current exact identity evidence permitted by BE-012 solely for later reconnection;
- sets content presence to `Orphaned` without deleting `GameContent`, membership, or enrichment.

When every current member of a Game is orphaned:

- Game becomes `InactiveOrphan`;
- it disappears from the normal active Library query but remains queryable through explicit historical/detail support paths;
- `Game`, memberships, retained identity evidence, provider mappings, metadata, resolved metadata, artwork references, and assets remain durable;
- no automatic expiration or garbage collection runs in Phase 003.

A returning source follows the normal current BE-012/BE-014 identification pipeline first. If its independently computed current identity has exactly one permitted retained match, the same short Unit of Work establishes new current identity/provenance, reconnects the source to the existing `GameContent`, clears `Orphaned`, and reactivates the existing Game when applicable. Missing, obsolete, ambiguous, or conflicting retained evidence follows ordinary create/reuse/conflict behavior rather than filename/provider/title guessing. Reused enrichment remains subject to normal freshness and revision eligibility.

## 10. Production Provider Set

Stable provider IDs activated by Phase 003 are:

```text
playmatch
gametdb
steamgriddb
```

Their roles are capability-based, not concrete adapter-type checks.

### 10.1 Playmatch

Zero user setup. Primary Phase 003 role: exact-content-to-external-game matching and supported metadata/mapping enrichment exposed by its adapter capabilities.

### 10.2 GameTDB

Zero user setup. Role: applicable-platform metadata and artwork discovery plus any exact external-ID/platform lookup capabilities supported by the adapter contract.

### 10.3 SteamGridDB

Requires one user-supplied API key through the credential service. Role: artwork discovery/enrichment and any provider-local game lookup required to obtain artwork candidates.

### 10.4 Deferred providers

IGDB and ScreenScraper are not production Phase 003 providers. Argus does not embed application Client Secrets/developer credentials and does not introduce an Argus cloud broker in this phase.

Hasheous is not part of the Phase 003 production provider roster. Its absence is a product selection decision, not a credential-model assumption.

## 11. Provider Readiness and Sessions

BE-010 readiness remains authoritative:

```text
Ready
Disabled
MissingCredentials
InvalidCredentials
Misconfigured
Unavailable
```

Only an enabled capability whose current readiness is `Ready` enters executable provider scope.

Planning and completion rules are:

- `Disabled` is an intentional configuration exclusion, not a refresh issue;
- `MissingCredentials` is an exclusion when the credentialed provider step was intentionally skipped or the provider remains enabled-but-unconfigured; it does not make every refresh `CompletedWithIssues`;
- `InvalidCredentials` and `Misconfigured` are actionable typed issues when the enabled capability would otherwise be eligible;
- `Unavailable` is a scoped transient issue when an enabled otherwise-eligible capability cannot execute;
- one provider/capability state never blocks canonical identification, provisional Game creation, an independent provider, or browsing committed data.

One job-scoped provider session owns transient authenticated clients, credentials, bounded retry/rate-limit state, and request cache. No secret becomes metadata-provider settings, job detail, metadata provenance, event payload, or bridge DTO.

## 12. Matching and `ExternalIdentityMapping`

Matching starts from exact `GameContent` evidence.

Conceptually:

```text
ExternalIdentityMapping
- id
- game_content_id
- provider_id
- external_game_id
- external_release_id nullable
- provider_platform_id
- provider_confidence nullable
- match_basis
- provider_revision
- matched_at
- last_validated_at
- state
```

`state` is:

```text
Current
Stale
RejectedByPolicy
```

Provider confidence is provider-local. Scores from different providers are never arithmetically compared as though they share one confidence scale.

### 12.1 Compile-time automatic-acceptance policy

Phase 003 automatic acceptance is evidence-class based, not a tunable generic confidence threshold.

A mapping may become `Current` only under one of these provider-specific rules:

- **Playmatch:** the response explicitly binds the submitted exact strong content hash/identifier and validated platform to one external game or release identity. Search/title/fuzzy candidates are never auto-accepted.
- **GameTDB:** a validated provider-platform mapping plus an exact platform-native product, disc, serial, or release identifier identifies one record, or a previously current exact external mapping is being refreshed. Title search alone is never auto-accepted.
- **SteamGridDB:** it is not Phase 003 canonical-content, Game-grouping, or automatic external-identity authority. Artwork lookup may use a provider game ID obtained through a deterministic accepted mapping/adapter path, but a SteamGridDB title/fuzzy candidate cannot merge Games or create a current content mapping.

Provider-local numeric confidence may be retained as provenance and used to reject results according to provider semantics, but numeric confidence alone can never establish `Current`. Region/language evidence may reject an otherwise exact candidate; it cannot promote a non-exact candidate.

Multiple exact candidates, contradictory current mappings, or any fuzzy-only result remain unmatched. Phase 003 has no interactive candidate chooser, so conservative non-acceptance is mandatory.

### 12.2 Mapping freshness

A mapping becomes stale when its owning provider/match policy revision changes or required local evidence is no longer current. Stale mappings remain inspectable as historical evidence but do not participate as current grouping/resolution authority.

## 13. Provider Metadata

Provider-native accepted records are retained independently so automatic resolution can be recomputed without immediately re-fetching.

Conceptually:

```text
ProviderMetadata
- id
- provider_id
- external_game_id
- provider_record_revision
- region nullable
- language nullable
- fetched_at
- expires_at nullable
- normalized_fields
- provenance
```

The exact storage decomposition may be provider-specific, but the application must retain the accepted provider-native values required to re-run deterministic resolution. A transient raw HTTP response is not required as durable authority.

MVP normalized metadata fields include, where supplied:

```text
title
alternate_titles[]
description
release_date nullable
developers[]
publishers[]
genres[]
region nullable
languages[]
```

Providers may omit unsupported fields. Absence is not replaced with fabricated values.

## 14. `ResolvedMetadata`

`ResolvedMetadata` is durable derived Game-level presentation state.

Conceptually:

```text
ResolvedMetadata
- game_id
- display_title
- sort_title
- description nullable
- release_date nullable
- developers[]
- publishers[]
- genres[]
- presentation_region nullable
- presentation_languages[]
- field_provenance[]
- resolution_revision
- resolved_at
```

Each resolved field records its contributing provider record or local fallback basis. Different fields may come from different providers.

Resolved metadata never establishes canonical identity or membership by itself.

### 14.1 Deterministic field selection

For a candidate field, the resolver evaluates in this order:

1. compatibility with actual current member content;
2. region fit;
3. language fit;
4. field-specific provider preference;
5. provider-native completeness/quality facts explicitly understood by the adapter;
6. freshness;
7. stable provider ID + provider record ID tie-break.

Phase 003 default metadata provider preference is:

```text
GameTDB
Playmatch
other future enabled providers only after a later contract revision
```

A provider that does not expose the field simply contributes no candidate.

Only currently enabled providers contribute candidates to current resolved metadata/artwork. Disabling a provider retains its accepted mappings, provider-native records, references, and provenance but excludes its records from winner selection on the ensuing local `library_resolution_refresh`. Re-enabling may reuse still-current retained records without network access. If no enabled candidate remains, the resolver uses the defined local fallback or leaves the field/artwork absent. Provider enablement alone does not rewrite canonical content identity or automatically undo an already established Game membership/redirect; grouping evidence changes only through its independently versioned reconciliation policy.

### 14.2 Local fallback

If no accepted provider metadata supplies a title, Argus may derive a sanitized normalized display-title hint from current local source naming strictly for presentation.

The fallback:

- does not enter `GameContent` identity;
- does not become grouping evidence;
- retains a `LocalFallback` provenance marker;
- is replaced automatically when better current provider metadata becomes available.

## 15. Region and Language Preferences

Global `MetadataSettings` own ordered preferred regions and languages.

Initial values are derived once from OS locale during Phase 003 onboarding/default creation. Subsequent OS locale changes do not silently overwrite user settings.

Resolution rules:

1. actual owned-content region/language compatibility outranks an unrelated preference;
2. among compatible candidates, ordered user preferences win;
3. fallback to another compatible locale is automatic;
4. locale affects presentation only, not canonical identity or Game membership;
5. changing preferences increments/effectively changes resolution eligibility but does not trigger provider network access by itself.

The UI may show current values and allow global changes. Per-game locale overrides are not Phase 003 scope.

## 16. Artwork References

The canonical taxonomy remains:

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

Conceptually:

```text
ArtworkReference
- id
- provider_id
- provider_asset_id
- external_game_id
- canonical_type
- native_type
- source_location: CredentialFreeUrl(url) | ProviderAssetLocator(opaque)
- thumbnail_location nullable: CredentialFreeUrl(url) | ProviderAssetLocator(opaque)
- width nullable
- height nullable
- format nullable
- region nullable
- language nullable
- variant_tags[]
- discovered_at
- provider_revision
```

Artwork locations are provider data, not local storage paths. `CredentialFreeUrl` may contain only a stable credential-free URL. `ProviderAssetLocator` is opaque outside the owning adapter/session.

When a provider requires a signed, token-bearing, expiring, or credential-derived URL, the authenticated provider session resolves the opaque locator to the transport URL transiently at download time. Credentials and signed URLs never become durable artwork provenance, Jobs detail, diagnostics, events, or bridge data.

## 17. Artwork Resolution

`ResolvedArtwork` is Game-level presentation state:

```text
ResolvedArtwork
- game_id
- artwork_type
- reference_id
- asset_id nullable
- ordering nullable
- resolution_reason
- resolution_revision
- resolved_at
```

One asset resolves for every type except `Screenshot`, which resolves to an ordered bounded gallery.

### 17.1 Deterministic policy

Artwork candidate scoring considers:

1. compatibility with current Game/provider mappings;
2. region/language fit;
3. canonical artwork type;
4. field/type-specific provider preference;
5. image dimensions/aspect suitability;
6. provider-native official/preferred variant facts;
7. duplicate suppression;
8. stable provider/reference tie-break.

Default provider preference is capability-specific:

```text
CoverFront/CoverBack/CoverSpine/Manual/Screenshot/TitleScreen:
    GameTDB -> SteamGridDB -> Playmatch when capability exists

Logo/Icon/Background/Banner:
    SteamGridDB -> GameTDB -> Playmatch when capability exists
```

A provider lacking a type contributes no candidate. This ordering is application policy and has no Phase 003 user-configurable ranking UI.

Screenshot selection may combine providers to favor a bounded diverse gallery rather than taking every candidate from one source.

## 18. Artwork Download and Storage

Only currently resolver-selected references are automatically downloaded.

`ArtworkAsset` follows ARCH-001:

```text
ArtworkAsset
- asset_id: BLAKE3(actual downloaded bytes)
- width
- height
- format
- mime_type
- size_bytes
- storage_path
- created_at
```

Rules:

- preserve original provider bytes;
- immutable content-addressed object storage;
- no resize/recompress/convert in Phase 003;
- validate supported image structure rather than trusting extension/MIME header alone;
- enforce download size/time/storage limits;
- remote filename/URL never determines local path;
- one byte-identical asset may be referenced by multiple games/types/providers.

Orphaning a Game does not automatically delete referenced assets in Phase 003.

## 19. Metadata and Artwork Refresh Policy

BE-010 invocation modes remain:

```text
EligibleOnly
Force
MissingOnly
```

Normal Library/Game refresh uses `EligibleOnly`.

Eligibility is provider/game/capability specific and includes:

- missing current mapping/metadata/artwork;
- stale-after policy reached;
- provider revision changed;
- match/resolver/artwork policy revision changed;
- provider newly enabled/configured;
- locale preference change requiring re-resolution;
- current membership changed;
- selected artwork reference has no valid local asset.

Provider fetch policy remains separate from resolution policy. A pure resolution revision or locale change can re-resolve current records without network access when no provider data is stale.

On provider failure, current stale data is preserved when the provider's compile-time refresh policy says `preserve_stale_on_failure`.

## 20. Library Query Projection

Normal Library browsing uses a Game-level read projection.

Conceptually:

```text
GameLibraryRow
- game_id
- display_title
- platform_id
- presentation_region nullable
- selected_cover_asset_id nullable
- hydration_state
- content_count
- source_count
- availability_state
- updated_at
```

`hydration_state` is a derived closed projection with this precedence:

```text
Refreshing
Unmatched
Hydrated
PartiallyHydrated
```

Derivation rules:

1. `Refreshing` — at least one nonterminal admitted `library_refresh`, `game_refresh`, or `library_resolution_refresh` currently targets the Game.
2. `Unmatched` — no active member has a current accepted external mapping and at least one current-revision matching attempt reached a terminal no-accepted-match result. A disabled/skipped provider alone does not establish `Unmatched`.
3. `Hydrated` — the Game has current accepted mapping evidence where matching is applicable, resolved metadata is current, every resolver-selected artwork reference is current, and every selected reference required for normal presentation has a valid local asset.
4. `PartiallyHydrated` — every other non-refreshing state, including no match-capable provider successfully evaluated yet, stale/missing metadata, unresolved selected artwork, or selected artwork whose `asset_id` is null.

It is not independent mutable domain state. The row projection recomputes only for affected Games when the underlying facts change.

`availability_state` is derived exactly as:

```text
Available            # every current source association is on a currently available root
PartiallyUnavailable # at least one current association is available and at least one is unavailable
Unavailable          # current source associations exist, but none is currently available
InactiveOrphan       # no current source association remains after authoritative final absence
```

Normal active Library queries exclude `InactiveOrphan`; explicit historical/detail queries may request it. Core row fields update transactionally with owning authoritative mutations. Expensive search/facet indexes may rebuild asynchronously but essential Library correctness never depends on transient events.

## 21. Library Query Semantics

Backend queries own grid/list page data, search, filtering, facets, sorting, cursor pagination, scope, and active/historical inclusion.

Phase 003 exposes this closed filter vocabulary:

```text
platform_ids: set<PlatformId>
regions: set<RegionCode>
hydration_states: set<HydrationState>
availability_states: set<AvailabilityState>
```

Multiple values within one category combine with OR; categories combine with AND. Empty sets impose no constraint. Generic nested Boolean expressions and provider-native field filters remain deferred.

Phase 003 exposes one primary sort:

```text
DisplayTitle
Platform
ReleaseDate
UpdatedAt
```

with explicit ascending/descending direction. The backend appends deterministic semantic tie-breakers ending in `GameId`. Null release dates sort last in either direction; changing direction reverses non-null values, not null placement. Cursor tokens bind to the normalized scope/search/filter/sort query and are invalid for another query shape.

Text search is backend-owned and runs over the current application-owned searchable projection, including resolved display/alternate titles and the active local fallback title where present. Provider-native raw payload fields are not searched directly. Search normalization/versioning is application-owned and must remain deterministic for one runtime/database revision.

`GetLibraryFacetsQuery` is active in Phase 003 and returns bounded buckets for platform, region, hydration state, and availability state. Each category's counts apply the current scope, search text, and every active filter except that same category. Pagination and selected sort do not affect facet counts. Bucket ordering is deterministic by the category's stable application-owned value order, with `PlatformId`/`RegionCode` as final tie-breakers where needed.

Normal queries exclude `Redirected` and `InactiveOrphan` Games. Explicit historical/detail/support queries may include `InactiveOrphan`; redirects resolve through the typed redirect result and never appear as duplicate rows.

Flutter must not load the entire Library to implement search, filters, facets, or sorting locally.

## 22. Refresh Operations

Stable operation types are:

```text
library_refresh
game_refresh
library_resolution_refresh
```

They are logical operation identifiers under BE-004, not implementation class names.

### 22.0 Library refresh trigger

Every admitted `library_refresh` persists one closed immutable trigger:

```text
LibraryRefreshTrigger
- Manual
- AddedRoot(library_root_id)
- InitialOnboarding
```

`Manual` represents the normal explicit Library action. `AddedRoot` is used by the post-onboarding Add Library Folder composite and gives the named root complete initial-scan scope while other roots contribute ordinary eligible work. `InitialOnboarding` is admitted only after onboarding completion commits. Trigger identity is durable Job detail used for truthful recovery and transport-ambiguity reconciliation; it does not change `JobRunId` or create a second workflow authority.

### 22.1 `Refresh Library`

`Refresh Library` is one user-visible top-level durable `JobRun` that composes existing focused capabilities:

```text
scan eligible configured roots
        ↓
identify new/changed/stale content
        ↓
ensure/reconcile Game membership
        ↓
match eligible content
        ↓
reconcile grouping with new mapping evidence
        ↓
refresh eligible metadata
        ↓
resolve Game metadata
        ↓
discover/resolve/download eligible artwork
        ↓
update Library projections
```

The operation does not introduce a generic workflow-node scheduler. Each subsystem owns its plan/checkpoints/executor semantics.

### 22.2 Scan composition

A composed Library refresh reuses BE-013 scan planning/execution semantics inside the already-admitted `library_refresh` operation rather than calling a public `start_library_scan` command that would create a second top-level JobRun.

The same `ScanRun`/root target/absence-authority invariants apply. Standalone Source `Scan` remains available and continues to use `library_scan` as its own top-level operation.

### 22.3 Incremental pipelining

There is no global barrier requiring every root scan to finish before downstream work begins.

After a source observation/scan checkpoint commits, affected content may proceed to identification and enrichment while other roots continue scanning.

Rules:

- only committed upstream facts feed downstream work;
- one game's/provider's failure cannot stall unrelated games;
- bounded central/provider-specific admission limits apply;
- event delivery is notification-only; authoritative queries repair gaps.

### 22.4 Default eligibility

Normal `Refresh Library` is `EligibleOnly`.

It skips current work and selects only new/changed/stale/incomplete/revision/configuration-affected scope. An unchanged second refresh should perform negligible substantive work.

There is no normal Library-wide Force Refresh action.

### 22.5 `library_resolution_refresh`

A user-confirmed `MetadataSettings` or `MetadataProviderSettings` mutation may admit one local-only `library_resolution_refresh` after the settings aggregate commits.

Its immutable intent records the committed settings revision(s) and resolution-policy revision required to determine affected Games. The operation:

- re-evaluates current accepted mappings and persisted provider records;
- re-resolves metadata fields and artwork references for affected Games;
- updates only affected Library/detail projections incrementally;
- performs no source scan, source read, parsing, hashing, metadata-provider request, artwork discovery request, or artwork download;
- leaves a newly selected `ResolvedArtwork.asset_id` null when the selected reference has no valid downloaded asset;
- has no public Force mode and is not admitted merely by opening Library or Game detail.

Settings-commit success and resolution-job admission are separate durable boundaries. Admission failure does not roll back the confirmed setting; affected projections are marked resolution-stale until explicit retry. The operation is non-auto-resumable, retry creates a new `JobRunId` from current committed settings, and Android may foreground-host qualifying work through the existing execution lease.

## 23. `Refresh Game`

The focused `game_refresh` operation accepts a bounded non-empty target set:

```text
RefreshGames(game_ids: NonEmptyBoundedSet<GameId>, mode)
```

`mode` is:

```text
EligibleOnly
Force
```

Normal Game detail uses a one-element target set. Library multi-selection may submit a bounded set using `EligibleOnly`. `Force` is permitted only for a one-Game target set and is not exposed as a bulk or Library-wide action.

The operation does not scan unrelated roots. It validates current member/provenance readiness as needed, performs eligible matching/grouping maintenance for targeted Games' contents, refreshes provider metadata/artwork, and re-resolves the affected current Game(s).

`Force` bypasses provider freshness eligibility for refreshable provider/enrichment work only. It does not bypass source validation, canonical identity, provider readiness, resource limits, or privacy consent.

If grouping reconciliation redirects/splits an originally requested Game during execution, the result records the resulting canonical affected Game IDs.

## 24. Add Library Folder Composition

Normal post-onboarding Add Library Folder uses the exact composite results defined by SPEC-BE-009:

```text
AddedAndRefreshAdmitted
AddedButRefreshNotAdmitted
AlreadyConfigured
OverlapsExisting
```

A newly added root commits first. The admitted `library_refresh` persists intent `AddedRoot(root_id)`: that root receives a complete initial scan, while other configured roots contribute only ordinary eligible work. Duplicate/overlap results create neither a new root nor a refresh job.

Root creation remains successful if later refresh admission fails. The typed child issue is reported separately and the root is not rolled back. After transport ambiguity, callers replay only the idempotent root-admission step and reconcile root/Jobs projections; blindly replaying the composite operation is prohibited.

During incomplete first-run onboarding, folder selection intentionally uses root-only admission. After `Added` or `AlreadyConfigured`, `CompleteLibraryOnboardingAndRefresh` immediately commits onboarding and admits the one initial refresh without another user action; existing-root upgrades invoke that same command through explicit `Finish & Refresh`. This sequencing prevents duplicate refresh jobs.

An advanced `Add Without Refreshing` path may persist a root without admitting refresh.

## 25. Admission and Concurrency

`BackgroundOperationManager` remains authoritative for top-level admission/resource classes/job lifecycle.

Required conflict policy:

- overlapping source mutation/scan ownership uses BE-013 root admission rules;
- one `library_refresh` cannot obtain contradictory active scan ownership for the same root;
- standalone Source Scan and Refresh Library coordinate through one shared root-operation admission boundary;
- provider request concurrency/rate limits remain provider-session policy;
- canonicalization/parsing uses BE-012 budgets;
- artwork downloads use bounded application/provider limits.
- runtime/kernel lifecycle synchronization must not be retained across long-running `library_refresh`, `game_refresh`, or `library_resolution_refresh` execution;
- while refresh execution is active or deliberately blocked at an owning provider/enrichment checkpoint, unrelated Library/Sources/Jobs/onboarding reads and job cancellation/control remain available subject only to their normal persistence/resource boundaries.

No feature maintains a second job-state machine.

Foreground responsiveness is a correctness requirement, not a best-effort performance target. The refresh handlers may own cloneable execution capabilities derived during admission, but they must not retain the runtime/kernel lifecycle handle as the mechanism for executing ordinary scan/identity/grouping/provider/resolution/artwork work. Provider latency or content volume must therefore not serialize all foreground runtime access behind the refresh lifetime.

## 26. Progress and Job Detail

Refresh operations report structured facts, not fabricated percentages.

Representative phase-local progress:

```text
phase
roots_total / roots_terminal
source_entries_changed
contents_identified
contents_issues
matches_attempted / matches_current / matches_unresolved
metadata_provider_pairs_terminal
artwork_references_resolved
artwork_assets_downloaded
issues_count
```

`library_resolution_refresh` reports only local resolution/projection facts:

```text
games_planned / games_terminal
metadata_games_resolved
artwork_selections_resolved
projections_updated
missing_selected_assets
issues_count
```

A resolver-selected reference with no local asset increments `missing_selected_assets`, leaves `asset_id` null, makes the Game eligible for a later explicit enrichment refresh, and normally produces `PartiallyHydrated`; it is not by itself a failure of the local-only resolution job because downloading is outside that admitted scope.

A percentage is shown only when BE-004's completed/total requirements are truthfully available for the current phase/scope.

Detailed provider/content issues are bounded and paged/queryable when volume requires it.

## 27. Completion Policy

A refresh is `Completed` when all admitted scope reaches safe terminal completion and no requested eligible scope remains unsatisfied by an issue.

It is `CompletedWithIssues` when meaningful work completed but one or more scoped items safely failed/remained unsatisfied, including examples such as:

- unmatched content;
- provider unavailable/failure;
- artwork download failure;
- malformed/unsupported archive/content;
- key-dependent excluded representation.

An unmatched provider result does not invalidate canonical Game existence.

`Disabled` and intentionally skipped/unconfigured `MissingCredentials` capabilities are exclusions and do not independently produce `CompletedWithIssues`. `InvalidCredentials`, `Misconfigured`, or `Unavailable` may produce a scoped issue only when the enabled capability was otherwise eligible for the admitted operation.

Global persistence/runtime failures that prevent safe continuation may fail the Job according to BE-004.

## 28. Cancellation

Cancellation is cooperative through BE-004.

After accepted cancellation:

- no new downstream work is admitted;
- active source/parsing/provider/download operations stop at owning safe checkpoints;
- already committed source/identity/Game/provider/metadata/artwork results remain valid;
- no half-written membership or resolved projection can commit;
- a provider response received after cancellation may commit only if the owning atomic operation reached its accepted commit point before cancellation became effective under BE-004 semantics.

Cancellation never rolls back independent successful provider results merely to make the job look atomic.

## 29. Retry and Recovery

Significant work is never silently auto-resumed.

Startup recovery:

- reconciles stale active refresh JobRuns under BE-004/BE-007;
- performs no scans, parsing, provider calls, grouping work, or downloads;
- preserves committed terminal child/domain state;
- marks stale execution `Abandoned`/other applicable recovery terminal state unless accepted cancellation semantics require `Cancelled`.

Retry creates a new JobRun and reconstructs the original bounded intent. Current eligibility is re-evaluated, so valid completed work is reused and missing/stale work is selected.

## 30. Persistence

SPEC-BE-002 owns schema mechanics. Phase 003 requires normalized persistence equivalent to:

```text
game
game_membership
game_redirect + continuity_anchor_game_content_id
game_grouping_basis/explainable grouping evidence
game_content_presence
retained content identity evidence as owned by BE-012
external_identity_mapping
provider_metadata
resolved_metadata + field provenance
artwork_reference
resolved_artwork
artwork_asset metadata
library read projection/indexes
refresh admission/detail state, including AddedRoot/onboarding/settings-revision intent
```

Secrets are not stored in these tables.

Current-membership uniqueness and Game redirect integrity are database-enforced where practical, not application-precheck-only conventions.

Migrations do not parse/hash/source-scan/provider-refresh the user's library. Pre-Phase-003 indexed sources become eligible only through an explicit user refresh.

## 31. Events

Publish post-commit notification facts through the existing event system, including representative events:

```text
GameChanged(game_id)
GameRedirected(old_game_id, canonical_game_id)
GameMembershipChanged(game_id)
GameMetadataChanged(game_id)
GameArtworkChanged(game_id)
LibraryProjectionChanged(scope_hint)
```

Events are invalidation hints, not authoritative DTO snapshots. Flutter re-queries the smallest relevant authoritative API. Event failure/gaps never roll back committed state.

## 32. Diagnostics and Observability

Safe diagnostics may include:

```text
GameId
GameContentId
ProviderId
JobRunId
scheme_id
identity/grouping/provider/resolution revisions
bounded readiness/error codes
counts and durations
```

They must not include:

- provider credentials;
- raw ROM/disc bytes;
- full provider HTTP payloads;
- authorization headers;
- unnecessary local paths/root locators;
- credential-bearing URLs.

## 33. Security and Privacy

### 33.1 External-data minimization

Provider calls send only the minimum capability-required data such as provider platform mapping, provider-required hashes/identifiers, accepted normalized matching hints, region/language hints, or known external IDs.

Local paths, root locators, Android URIs, unrelated Library contents, diagnostics, and unrelated settings are not transmitted.

### 33.2 Consent

External provider work requires the existing current versioned privacy acceptance. Declining the required product privacy terms retains the existing product behavior defined by architecture; provider work never bypasses the consent boundary.

### 33.3 Credentials

SteamGridDB's API key is stored and retrieved only by the credential service. `MetadataProviderSettings` persist enablement only; configured/readiness facts are query projections and never secret settings data.

Production must not fall back to ordinary SQLite, settings records, shared preferences, plain files, Dart persistence, or other plaintext application storage when the secure credential service is unavailable. The command returns `ARGUS.V1.CONFIGURATION.CREDENTIAL_STORE_UNAVAILABLE`, SteamGridDB remains non-Ready, and existing stored-secret state is not guessed or overwritten.

No application-owned IGDB/ScreenScraper secret is embedded, obfuscated, or proxied.

### 33.4 Untrusted remote input

Provider responses and artwork are untrusted. Adapters validate bounded schemas/identifiers/URLs/strings. Artwork downloader validates actual content, size, format, redirect/network policy, and storage bounds before creating an `ArtworkAsset`.

## 34. Performance Requirements

- Library queries are cursor-paged and backend-filtered/sorted.
- Provider planning avoids N+1 readiness/session construction.
- One job-scoped provider session is reused per provider.
- Resolution recomputes only affected Games.
- One metadata/artwork mutation must not rebuild the full Library projection.
- Provider concurrency and artwork downloads are bounded.
- Pipelined refresh may start downstream work as committed eligible inputs become available without retaining the entire Library in memory.
- Phase qualification includes at least 10,000 identified synthetic contents.

## 35. Testing Requirements

### 35.1 Game/grouping

Tests must prove:

- new identified content obtains a provisional Game without provider access;
- one GameContent has one current membership;
- duplicate physical sources do not duplicate membership;
- cross-platform grouping is rejected;
- filenames/titles/folders alone cannot merge;
- trusted region/revision/disc/provider evidence can merge where policy permits;
- materially distinct products remain separate;
- ambiguity remains separate;
- deterministic merge survivor and redirects;
- immutable redirect continuity anchors, flattened acyclic redirect chains, and post-split retargeting to the class containing each historical anchor;
- deterministic split anchor behavior;
- grouping revision targets affected Games;
- authoritative orphaning versus temporary unavailability;
- final-source absence clears current proof while retaining only bounded non-current evidence;
- returning content independently re-identifies before exact retained-evidence reconnection;
- absent, obsolete, ambiguous, or current-owner-conflicting retained evidence never guesses a reconnection;
- successful content reappearance reactivates the existing durable Game/enrichment atomically.

### 35.2 Matching/providers

Offline deterministic adapter tests for Playmatch, GameTDB, and SteamGridDB must cover readiness, platform mapping, request formation, parsing, malformed/unknown response data, bounded retry/rate-limit translation, provider revision, provenance, and redaction.

Matching tests prove the exact automatic-acceptance policy: Playmatch exact-hash binding, GameTDB exact platform-native/existing mapping, SteamGridDB non-authority for content/grouping, provider-local confidence as rejection/provenance only, and no title/fuzzy automatic acceptance or cross-provider score comparison.

### 35.3 Metadata resolution

Tests cover field-level provider composition, region/language compatibility, deterministic provider/tie ordering, stale preservation, local fallback title, locale/provider-setting changes admitting local-only `library_resolution_refresh`, committed-setting versus resolution-admission failure, no network/download work during local resolution, provider disablement excluding retained records from current winners without deletion, and re-enable reuse of still-current records.

### 35.4 Artwork

Tests cover taxonomy mapping, provider/type preferences, region/language fit, resolution/aspect criteria, duplicate suppression, screenshot diversity, selected-only downloads, actual-byte BLAKE3 asset identity, invalid image rejection, immutable reuse, orphan retention, credential-free persisted URLs/opaque locators, transient signed-URL resolution, and `asset_id = null` when local-only re-resolution selects an undownloaded reference.

### 35.5 Refresh composition

Tests cover:

- first Refresh Library;
- no-op second EligibleOnly refresh;
- changed single content;
- scan-to-identify-to-hydrate pipelining;
- partial provider failure;
- unmatched content;
- provider configuration change;
- malformed/multi-game archive issue isolation;
- cancellation during scan/identify/match/metadata/artwork;
- process loss and explicit retry;
- Refresh Game EligibleOnly;
- Refresh Game Force;
- grouping redirect/split during targeted refresh;
- standalone Scan/Refresh root admission conflicts;
- root added successfully but refresh admission failure preserved separately;
- duplicate/overlap Add Folder outcomes admit no refresh;
- add-folder transport ambiguity replays only idempotent root admission and reconciles Jobs;
- onboarding completion commits before initial refresh admission and survives child admission failure;
- metadata/provider settings commit independently from `library_resolution_refresh` admission;
- `library_resolution_refresh` success, partial failure, cancellation, process loss, and explicit retry with no source/provider/download I/O;
- Disabled and intentionally skipped MissingCredentials capabilities are exclusions, while InvalidCredentials/Misconfigured/Unavailable are scoped issues only when otherwise eligible;

### 35.6 Persistence/query

Tests cover historical Phase 000-002 migration fixtures through an explicitly configured custom/full registry, production forward migration from supported schema-8+ state, safe rejection of validated production schema 1–7 history, current-membership and acyclic redirect/continuity-anchor constraints, retained identity-evidence separation, concurrent grouping/mapping updates, query-bound cursor stability, closed filter/sort semantics, own-category-excluded facet counts, exact hydration/availability precedence, active/orphan/redirect query behavior, incremental projection maintenance, and event-loss authoritative re-query.

## 36. Out of Scope

- manual metadata field editor;
- interactive match candidate picker;
- manual artwork picker/locks;
- manual Game merge/split;
- per-game locale override;
- provider ranking UI;
- collections/favorites;
- cross-platform title/franchise entity;
- provider health dashboard/circuit-breaker history;
- autonomous scheduled refresh;
- RetroAchievements verification.

Manual correction remains later-MVP scope.

## 37. Acceptance Criteria

SPEC-BE-015 is satisfied when:

1. `Game` is durable Argus-owned platform-specific identity above exact `GameContent`.
2. New identified content remains Library-eligible without any provider success.
3. Grouping is conservative, explainable, and filename-independent.
4. Every GameContent has one current membership.
5. Automatic merge/split behavior preserves deterministic Game-ID continuity/redirects.
6. Duplicate physical copies collapse through one GameContent/Game membership.
7. authoritative absence produces retained inactive-orphan semantics while temporary unavailability does not.
8. Playmatch, GameTDB, and SteamGridDB are the Phase 003 production provider set.
9. SteamGridDB credentials never enter ordinary settings/domain/DTO/log state.
10. Provider confidence remains provider-local and unresolved ambiguity stays unmatched.
11. Provider-native accepted metadata remains independently refreshable from ResolvedMetadata.
12. Game-level metadata resolution is deterministic, field-provenance preserving, and locale aware.
13. Global locale preferences do not alter identity/grouping.
14. Resolved artwork is Game-level, selected-only downloads preserve immutable original bytes, and BLAKE3 identifies actual assets.
15. Provider failures preserve independent successes and allow `CompletedWithIssues`.
16. `Refresh Library` is one top-level durable user operation composed from focused subsystem capabilities without a universal scheduler.
17. Refresh work pipelines incrementally only from committed upstream facts.
18. normal refresh uses EligibleOnly and unchanged state performs negligible substantive work.
19. Refresh Game is targeted and Force affects provider/enrichment freshness only.
20. cancellation preserves coherent committed successes and stops new downstream admission.
21. recovery never silently resumes significant work; retry creates a new JobRun.
22. Library projections are Game-level, incremental, cursor-paged, and backend queried.
23. external provider work is explicit/user-initiated and privacy/credential boundaries remain intact.
24. desktop and Android share the same semantic domain/provider/resolution contracts.
25. Redirect continuity anchors preserve historical Game-route meaning across later automatic splits without redirect loops or title-based guessing.
26. Final-source absence clears current proof but retains bounded non-current evidence; returning content reconnects only after independent exact current identification.
27. Automatic provider matching accepts only the provider-specific exact evidence classes defined here, and SteamGridDB never becomes content/grouping authority.
28. Library hydration, availability, filter, sort, facet, and cursor semantics are closed, deterministic, and backend-owned.
29. `library_resolution_refresh` preserves committed settings independently from admission, remains local-only, and never performs provider or artwork-download I/O.
30. Add-folder and onboarding composites preserve committed parent state, expose typed child-admission failures, and prohibit blind replay after transport ambiguity.
31. Persisted artwork references contain no credential-bearing URL, and app-private artwork is addressed by `ArtworkAssetId` rather than a leaked storage path.
32. Disabled and intentionally unconfigured metadata-provider capabilities are exclusions rather than automatic partial-failure causes.
33. `library_refresh`, `game_refresh`, and `library_resolution_refresh` execute without retaining the runtime/kernel lifecycle mutex across long-running business work, and foreground focused reads/job control remain available while those operations are active.
34. Deterministic concurrency coverage proves foreground query/control responsiveness while refresh execution is intentionally blocked at a test-owned provider/enrichment seam, then proves normal terminalization after release.

## 38. Prohibited Patterns

- provider ID as `GameId` or `GameContent` identity;
- provider title/fuzzy search or numeric confidence alone creating a current mapping;
- SteamGridDB lookup becoming content identity or Game-grouping authority;
- filename/title/folder-only grouping;
- one Game spanning multiple PlatformIds;
- automatic ambiguous merge;
- redirect creation without a durable continuity anchor or redirect retargeting by display/provider data;
- deleting orphan identity/enrichment on last-source absence;
- treating retained orphan identity evidence as current identity/provenance or consulting it before independent re-identification;
- treating unavailable media as authoritative absence;
- one universal provider confidence scale;
- flattening provider records irreversibly into one metadata row;
- one winning provider for every metadata field regardless of capability/locale;
- downloading every discovered artwork candidate;
- storing remote filename/URL as object-store path;
- persisting signed, token-bearing, or credential-derived artwork URLs;
- exposing provider credentials through normal settings or bridge reads;
- Flutter-side Library search/filter/sort over an eagerly loaded full library;
- `Refresh Library` calling public scan admission to create an unrelated second top-level job;
- `library_resolution_refresh` performing source, metadata-provider, artwork-discovery, or artwork-download I/O;
- blindly replaying add-folder/onboarding/settings composite commands after transport ambiguity;
- using the runtime/kernel lifecycle mutex as the business-execution lock for Phase 003 refresh stages;
- automatic refresh on startup/timer/process recovery;
- silently resuming abandoned work;
- manual correction or collections leaking into Phase 003.

## 39. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-003 — Game Identification and Enrichment](../../phases/phase-003-game-identification-and-enrichment.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-009 — Application Service Contracts](spec-be-009-application-service-contracts.md)
- [SPEC-BE-010 — Provider Gateway Architecture](spec-be-010-provider-gateway-architecture.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-BE-012 — Transformation and Hash-Scheme Contract](spec-be-012-transformation-and-hash-scheme-contract.md)
- [SPEC-BE-013 — Library Source Management, Scan Operations, and Source Projections](spec-be-013-library-source-management-scan-operations-and-source-projections.md)
- [SPEC-BE-014 — Production Content Identity Catalog](spec-be-014-production-content-identity-catalog.md)
- [SPEC-X-002 — Android Platform Runtime and Capability Contract](../cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md)
