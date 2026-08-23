# Library, Game Detail, and Enrichment UX Specification

**Document ID:** SPEC-FE-010  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-23  
**Depends On:** ARCH-001, ARCH-002, PHASE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-007, SPEC-BE-008, SPEC-BE-009, SPEC-BE-010, SPEC-BE-013, SPEC-BE-015, SPEC-FE-001, SPEC-FE-002, SPEC-FE-003, SPEC-FE-004, SPEC-FE-005, SPEC-FE-006, SPEC-FE-007, SPEC-FE-008, SPEC-FE-009, SPEC-X-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the Phase 003 Flutter experience for the logical game Library, product onboarding for metadata/artwork enrichment, adaptive Game detail, refresh actions, metadata-provider settings/readiness, and progressive presentation while backend work commits incrementally.

It activates the previously reserved Library and `/games/:gameId` routing surfaces while preserving Rust/application authority for identity, grouping, provider readiness, metadata/artwork resolution, jobs, persistence, and query semantics.

The governing UX rule is:

> A normal user chooses a library folder and browses games; scanning, identification, provider matching, metadata resolution, and artwork download remain automatic internal stages that become visible only when status or troubleshooting requires it.

## 2. Responsibilities

FE-010 owns:

- Library as the default ready-state product destination;
- Phase 003 product onboarding after platform/runtime readiness;
- guided/skippable provider configuration;
- initial Add Library Folder -> refresh UX;
- Library grid/list presentation;
- search, typed filters, sort, pagination, scopes, and view-mode interaction;
- progressive hydration presentation;
- unmatched/partial/unavailable states;
- adaptive `/games/:gameId` presentation;
- Refresh Library, Refresh Game, Force Refresh, and selected-game refresh interaction;
- Game detail sections for metadata, content/copies/discs, artwork, provenance/status, and history;
- provider/settings UI consuming safe readiness/configuration projections;
- desktop keyboard/focus/selection behavior;
- Android touch, Back/predictive Back, insets, and foreground-job projection integration;
- accessibility and test requirements.

## 3. Non-Responsibilities

FE-010 does not:

- parse files or containers;
- compute content identity/hashes;
- decide Game grouping;
- interpret provider confidence;
- resolve metadata/artwork fields;
- store/read provider secrets directly;
- implement filesystem traversal outside FE-008's picker boundary;
- own Job lifecycle;
- implement manual metadata editing;
- implement manual provider-candidate matching;
- implement manual artwork selection/locking;
- implement collections/favorites;
- implement RetroAchievements UI;
- implement cross-platform title grouping.

## 3.1 Platform Applicability

The semantic route graph, controllers, APIs, Library query model, Game detail state, refresh actions, and metadata-provider settings are shared Flutter behavior.

Presentation adapts by available width and input modality. Android-specific behavior is limited to established platform readiness, system insets, foreground-service projection, lifecycle reattachment, and Back/predictive Back integration.

No Android-only Library state machine or desktop-only Game authority is permitted.

## 4. Navigation Activation

Once Phase 003 onboarding/readiness is satisfied, the primary destination catalog is:

```text
Library
Sources
Jobs
Settings
```

Library is the default ready-state destination.

Canonical routes are:

```text
/onboarding/library
/library
/library/platforms/:platformId
/library/sources/:sourceId
/library/library-roots/:libraryRootId
/games/:gameId
```

`/library/collections/:collectionId` remains reserved and inactive.

The operational routes remain distinct:

```text
/sources
/sources/roots/:libraryRootId
/jobs
/jobs/:jobRunId
/settings
```

`/library/sources/:sourceId` is a logical Game browsing scope. It must never be conflated with operational `/sources` hierarchy management.

## 5. Adaptive Shell Placement

Use the established global width classes:

```text
Compact  <600
Medium   600-839
Expanded 840-1199
Large    >=1200
```

- Compact: bottom navigation with the four active primary destinations.
- Medium: icon navigation rail.
- Expanded/Large: labeled rail/sidebar according to FE-004 shell rules.

Changing width changes presentation only. URI, destination identity, branch history, selection, and durable query state remain semantically stable.

## 6. Product Onboarding

Phase 003 product onboarding is neither backend startup nor Android platform readiness. It renders at `/onboarding/library` outside the ready shell and is driven by query-authoritative `LibraryOnboardingState`, not a frontend-persisted completion flag.

Ordering is:

```text
platform readiness where applicable
        ↓
backend Ready + appearance authority
        ↓
Library onboarding if incomplete
        ↓
ready shell / preserved valid route intent
```

### 6.1 Steps and durable authority

The coordinator presents only steps reported incomplete by the backend/client projection:

1. current required privacy/data-sharing acceptance through `SettingsApi.acceptPrivacyTerms`;
2. preferred region/language confirmation through `LibraryApi.confirmLibraryMetadataPreferences`, initialized from OS locale only when no persisted preference exists;
3. metadata-provider explanation/readiness;
4. optional SteamGridDB API-key setup followed by `LibraryApi.recordLibraryProviderSetupOutcome(LibraryProviderSetupDecision.configured)`, or an explicit `Skipped` outcome;
5. Library folder selection if onboarding has never completed and no configured root exists;
6. completion/refresh admission: automatic after successful first-folder selection, or explicit `Finish & Refresh` when a root already existed.

Folder selection during fresh onboarding uses FE-008/`SourcesApi` root-only admission. After `Added` or `AlreadyConfigured`, the coordinator immediately calls `completeLibraryOnboardingAndRefresh`; selecting the first folder is the final user action and no second confirmation click is shown. `OverlapsExisting` remains folder-selection feedback and does not complete onboarding. Existing-root upgrades expose `Finish & Refresh`, which calls the same completion command. In every path onboarding commits before initial refresh admission.

Typed outcomes distinguish:

```text
completion + refresh admitted
completion + refresh not admitted
pre-completion validation/persistence failure
```

In the fresh no-root flow, a completion validation/persistence failure after root admission never rolls the root back. The coordinator re-queries onboarding state, renders the root-selection prerequisite as satisfied, and returns the user to the remaining incomplete step/error.

A post-completion refresh-admission failure keeps onboarding complete, enters the ready Library, reports the refresh failure, and offers an explicit retry. Transport ambiguity re-queries onboarding and Jobs state; it never blindly replays completion or refresh.

Later removal of every root does not reopen onboarding. A newer required privacy-terms version reopens only the consent gate.

Playmatch and GameTDB require no credential-entry step. Their current readiness can be shown without making onboarding depend on live provider availability.

### 6.2 Existing-user upgrade

A user upgrading from Phase 001/002 with existing roots is not asked to re-add them. The final onboarding action explicitly starts `Refresh Library`, making existing indexed content eligible for Phase 003 identification/enrichment without hidden migration work.

### 6.3 SteamGridDB setup

SteamGridDB setup is guided and recommended but skippable.

The credential field:

- is obscured;
- exists only in transient local input state until submit;
- submits through `MetadataProvidersApi`;
- is cleared from controller state after terminal submit;
- cannot read the stored secret back;
- later Settings UI offers Replace and Remove, not Reveal.

A securely stored credential may remain configured when live validation is temporarily unavailable; readiness then reports `Unavailable`, and the coordinator may record the durable `Configured` outcome. `Ready` is likewise configurable. `InvalidCredentials`, `MissingCredentials`, and `Misconfigured` cannot complete the configured path. Skipping is allowed only after no credential is configured: an invalid stored key must be removed successfully first, then the coordinator records `LibraryProviderSetupDecision.skipped`. This leaves other providers usable, and intentional `MissingCredentials` alone does not make every refresh a partial failure.

### 6.4 Consent decline

Required privacy acceptance follows the existing architecture contract. If declined, the frontend exits the gated product flow and does not attempt provider calls or invent a reduced-consent bypass.

## 7. Empty Library

When no configured library roots exist, `/library` shows one focused primary state:

```text
Your library is empty
Add a folder containing your games to get started.

[ Add Library Folder ]
```

The primary action invokes FE-008's platform-appropriate folder-selection/root-admission flow. On successful root creation, the frontend immediately requests the approved add-and-refresh workflow.

Operational `Add Without Refreshing` remains a secondary/advanced Sources action, not part of the normal empty-Library call to action.

If roots exist but no Games are currently active, the empty state distinguishes:

- refresh not yet run / content not identified;
- current refresh running;
- no supported game content found;
- all content temporarily unavailable.

Do not collapse these into the same misleading "empty" message.

## 8. Library Controller Boundary

`LibraryController` owns presentation coordination only.

It may hold:

```text
current scope
query text
LibraryFilter
sort
view mode
page/cursor state
selected GameIds
focused GameId
scroll restoration keys
request generation/token
synchronization uncertainty
```

It does not own:

- Game entities;
- identity/grouping state;
- provider confidence/readiness policy;
- metadata/artwork resolution;
- JobRun lifecycle.

After relevant events, runtime replacement, or sequence gaps, it re-queries focused authoritative APIs.

## 9. Library Query State and URL

Durable Library scope is route state. Temporary browse state uses query parameters according to FE-004.

Canonical concepts include:

```text
q=<search text>
view=grid|list
sort=<supported primary sort>
order=asc|desc
filter.<category>=<value(s)>
```

Exact encoding must be centralized and typed; widgets must not hand-build query strings.

Invalid/unknown query values are normalized to supported defaults without crashing or widening backend queries unexpectedly.

Changing temporary filters/sort/view mode does not create a new semantic primary destination.

## 10. Search, Filters, and Sort

All substantive query semantics are backend-owned through FE-003/BE-015 projections.

Search:

- is user initiated through the Library search field;
- may debounce keystroke requests;
- never filters an eagerly loaded full Library in Dart;
- preserves scope/filter/sort state.

Typed filter semantics are:

```text
values in same category -> OR
categories -> AND
```

Phase 003 filter categories may include only backend-supported facts such as platform, region, hydration state, availability/source scope, and other explicitly projected metadata. No filter is synthesized from provider-native fields in Flutter.

One user-selected primary sort is active; backend stable tie-breakers remain invisible implementation detail.

## 11. Grid and List Presentation

Both presentations consume the same `GameLibraryRow` query.

### 11.1 Grid

Game cards prioritize:

- selected cover or placeholder;
- display title;
- platform identity/icon/label;
- concise non-normal status when relevant.

Do not overload normal hydrated cards with provider/source/debug detail.

Cards and rows load selected artwork only through `ArtworkAssetsApi` using `ArtworkAssetId`. Widgets never receive object-store paths or provider URLs. Concurrent visible requests are deduplicated and cached within the bounded client/image cache; off-screen or whole-Library prefetch is prohibited.

### 11.2 List

- Compact/Medium: responsive rows with artwork thumbnail, title, platform, and relevant status.
- Expanded/Large: virtualized aligned/table-like rows where constraints permit.

### 11.3 Scroll restoration

Grid and list maintain independent scroll restoration keyed by durable Library scope plus normalized query state. Switching views does not destroy the other view's position.

## 12. Pagination and Loading

Library uses cursor pagination.

The frontend:

- requests bounded pages;
- appends/reconciles by `GameId`;
- never assumes cursors are offsets;
- discards stale responses from an earlier request generation;
- handles an item moving/disappearing because authoritative state changed;
- does not require total count for correctness.

First-page loading may show a skeleton/contained loading state. Loading later pages must not replace already rendered rows with a global spinner.

## 13. Progressive Hydration

A running refresh does not make an existing Library unusable.

As committed backend state changes:

```text
identified Game appears
    ↓
metadata may fill in
    ↓
artwork may appear
```

Presentation states derive from backend projections:

```text
Hydrated
PartiallyHydrated
Unmatched
Refreshing
```

Normal hydrated items need no persistent "Hydrated" badge. Non-normal states use concise text/icon semantics and must not rely on color alone.

Artwork appearance uses ordinary image transition behavior; it must not reorder the Library unless the active backend sort key actually changed.

## 14. Availability and Orphans

Temporary root/media unavailability is not deletion.

If all current copies of a visible Game are temporarily unavailable, the Game remains in normal Library with a clear unavailable/offline state and disabled actions that require local content.

When backend authority transitions a Game to `InactiveOrphan`, it no longer appears in the normal active Library query. Flutter does not locally hide/delete it based on filesystem assumptions.

When content returns and backend reactivates the Game, it reappears under the same surviving `GameId` unless authoritative grouping reconciliation changed it.

## 15. Selection

Selection remains separate from routed Game detail.

Desktop:

- click selects/opens according to established list/grid convention;
- Cmd/Ctrl-click toggles;
- Shift-click ranges over the loaded ordered query window;
- arrows move focus;
- Space toggles selection;
- Enter opens focused Game detail.

Touch:

- tap opens detail;
- long press enters selection mode;
- subsequent taps toggle.

Phase 003's meaningful bulk action is `Refresh Selected`, which requests one focused game-refresh admission over the selected bounded `GameId` set using normal `EligibleOnly` semantics. Force Refresh remains per-game only.

Selection is cleared/reconciled when selected Games leave the current authoritative result set unless the controller has enough identity to preserve a valid off-page selection safely. The frontend never converts row indexes into durable selection identity.

## 16. Refresh Library

The Library toolbar exposes one primary `Refresh Library` action when backend capability/readiness allows admission.

On accepted background admission:

- show transient accepted feedback;
- project activity through the shell active-job indicator;
- optionally show concise Library-local refresh status;
- provide navigation to authoritative Jobs detail;
- keep Library usable.

The frontend does not display acceptance as completion.

If admission fails synchronously, show the typed application error inline/toast according to FE-009 feedback rules; do not fabricate a JobRun.

There is no normal Library-wide Force Refresh action.

## 17. Add Library Folder from Library

`Add Library Folder` can also appear as a Library toolbar/action-menu command after initial setup.

The normal action is:

```text
pick folder
  ↓
validate/add root
  ↓
root success
  ↓
automatic refresh admission
```

If root creation succeeds but refresh admission fails, the UI reports the refresh failure while preserving/showing the newly configured root. It must not imply the folder was not added.

`AlreadyConfigured` and overlap outcomes admit no refresh through this composite action. After transport ambiguity, the controller replays only idempotent root admission and reconciles root/Jobs projections before presenting or issuing a separate Refresh Library action.

## 18. Game Detail Routing

`/games/:gameId` is canonical and width-independent.

- Compact: full-page routed detail.
- Medium: full-page detail by default.
- Expanded/Large: master-detail/inspector presentation where the Library layout supports it.

Changing width does not change GameId or create another semantic route.

If the requested Game ID is redirected by backend grouping, the client replaces/navigates to the canonical Game route without producing duplicate history loops.

If a Game genuinely no longer exists/is inaccessible under the query contract, show a typed not-found/unavailable state rather than stale cached detail.

An `InactiveOrphan` Game reached through history/support navigation is still a durable Game and renders read-only retained detail with its orphan status; it is not misrepresented as not found.

## 19. Game Detail Coordinator

Use a parent `GameDetailCoordinator` plus focused section controllers/APIs.

Phase 003 sections are:

```text
Overview
Metadata
Files & Copies
Artwork
Sources / Availability
Activity / History
Technical provenance (secondary/advanced)
```

An Achievements section is not activated until Phase 004.

Overview renders first. Heavy sections query lazily when opened where appropriate.

## 20. Game Detail Overview

Overview presents the current resolved Game projection:

- cover/hero artwork where available;
- display title;
- platform;
- preferred/current region/language where meaningful;
- description;
- release date;
- developer/publisher/genre when available;
- concise hydration/availability issue state.

Missing provider fields remain absent or use explicit generic placeholders only where layout needs one. Flutter never synthesizes fictional metadata.

## 21. Files, Variants, Discs, and Copies

Game detail exposes exact-content provenance without making normal browsing file-centric.

The section groups by `GameContent` and shows backend-projected facts such as:

- relationship/variant type;
- region/language/revision evidence where available;
- disc number/relationship where available;
- physical copy/source count;
- availability;
- source/root display context through safe presentation DTOs.

Raw opaque locators/URIs and provider-native identifiers are not displayed by default.

Duplicate physical copies appear as multiple sources beneath one exact content, not duplicate Games.

## 22. Metadata and Provenance Presentation

Metadata detail consumes `ResolvedMetadata` plus safe field provenance.

Normal view shows resolved values. A secondary provenance affordance may show which provider supplied a field and when it was last refreshed.

It must not expose raw response payloads, provider confidence internals as a cross-provider score, credentials, or secret-bearing URLs.

Phase 003 has no editable metadata fields and no provider candidate chooser.

## 23. Artwork Presentation

Artwork detail presents only backend-selected/resolved artwork by canonical type, with the ordered screenshot gallery where available.

Resolved assets are fetched through `ArtworkAssetsApi` as bounded immutable bytes. `asset_id = null` or an asset-not-found failure renders a placeholder and an explicit enrichment retry affordance; Flutter never falls back to a backend storage path.

The UI may show provider attribution/provenance where required/useful, but it does not fetch candidate lists independently or pick its own winning image.

Missing/failed artwork uses stable placeholders and concise retry/status affordances tied to Refresh Game.

Phase 003 has no manual artwork picker or artwork lock. Those remain later-MVP correction capabilities.

## 24. Refresh Game and Force Refresh

Game detail exposes:

```text
Refresh Game
Force Refresh
```

`Refresh Game` is the primary action and requests `EligibleOnly`.

`Force Refresh` is secondary/advanced, visually less prominent, and requires an explicit menu/action choice. It forces refreshable provider/enrichment work only as defined by BE-015.

If local content is temporarily unavailable, action availability follows backend-advertised capability rather than Flutter guessing which provider stages could theoretically run.

Accepted work navigates/links to Jobs as needed while detail remains usable.

## 25. Metadata-Provider Settings

Settings gains an enrichment/provider section that shows application-owned projections only:

```text
Playmatch      Enabled | readiness
GameTDB        Enabled | readiness
SteamGridDB    Enabled | credential configured | readiness
```

Users may:

- enable/disable each provider when backend policy exposes it;
- enter/replace/remove the SteamGridDB API key;
- see safe validation/readiness status;
- trigger explicit validation only through the owning API where supported.

There is no provider-priority/ranking UI.

Disabling a provider commits `MetadataProviderSettings` and may return a `library_resolution_refresh` handle. Retained provider records remain durable but are excluded from current metadata/artwork winners after local resolution; re-enable may reuse still-current records. The UI warns about enrichment/presentation changes without claiming canonical content, Game identity, memberships, or provider records will be deleted.

## 26. Region and Language Settings

Settings exposes ordered global preferred region and language values owned by `MetadataSettings`.

Changes persist immediately under FE-006/BE-005-style confirmed-mutation semantics:

- save on confirmed selection/reordering;
- revert to the last confirmed value only when settings persistence itself fails;
- when settings commit but local resolution admission fails, keep the committed control value and show a distinct "saved; Library update pending" error/retry state;
- follow the returned `library_resolution_refresh` handle through Jobs when admitted;
- re-query authoritative Library/detail state after relevant notifications or terminal observation.

Changing preferences does not initiate provider networking. `library_resolution_refresh` locally re-resolves current provider records and artwork references only. A newly selected reference without downloaded bytes remains a placeholder until a later explicit Refresh Library/Game downloads it.

## 27. Jobs Integration

FE-009 remains authoritative for background operation presentation.

Phase 003 adds user-meaningful labels/details for:

```text
library_refresh            -> Refresh Library
game_refresh               -> Refresh Game / Refresh Selected Games
library_resolution_refresh -> Apply Library Preferences
```

Job detail may show bounded phase/outcome summaries:

- roots scanned;
- content identified/issues;
- matches/unmatched;
- provider outcomes;
- metadata/artwork outcomes;
- resulting affected Games.

Do not render raw provider payloads, local opaque paths, or one error row per huge library item without paging/bounding.

## 28. Error Presentation

Use layered feedback:

- inline for local action/configuration errors;
- toast for accepted/rejected immediate actions where appropriate;
- Jobs detail for long-running/partial failures;
- Game-local status for persistent unmatched/incomplete state.

Examples:

- malformed multi-game archive: Library remains usable; job detail explains that the archive must be extracted/reorganized;
- SteamGridDB unavailable: existing metadata/artwork remains; job may CompleteWithIssues;
- unmatched game: card/detail remain visible with local fallback title;
- root unavailable: Game remains visible with unavailable state;
- invalid API key: inline Settings/onboarding error, never echo key.

## 29. Refresh Event Reconciliation

Game/Library events are notification-first.

Controllers re-query after:

- relevant Game/library/provider/settings events;
- runtime event sequence gaps;
- runtime replacement;
- return from background where state may have changed;
- accepted refresh terminal observation where local state may lag.

Dropped/coalesced events must not permanently strand a card in Refreshing or leave stale metadata/artwork visible as current after the authoritative query changed.

## 30. Android Lifecycle and Foreground Execution

Phase 002 remains authoritative.

A qualifying refresh may continue while the Activity detaches through the existing Android foreground-service host. Flutter:

- does not own or count native service leases independently;
- reconstructs presentation from authoritative Jobs/runtime state on reattachment;
- does not create a second Rust runtime;
- does not assume notification presence equals job state;
- handles notification denial while Jobs remains authoritative.

## 31. Back and Predictive Back

Use the existing Flutter navigator/pop pipeline.

Back ordering remains:

1. dismiss topmost transient surface;
2. leave selection mode/close local inspector if that is the meaningful topmost action;
3. pop Game detail or other routed navigation;
4. exit Activity only when route stack permits.

No Phase 003 global Back coordinator is added.

## 32. Insets and Responsive Composition

Use edge-to-edge/local inset rules from FE-007/Phase 002.

Do not globally wrap Library/Game detail in `SafeArea`. Components respond to their own constraints with `LayoutBuilder`-style local adaptation.

Wide Game detail inspector must remain usable when its nested width becomes Compact/Medium even inside a Large app window.

## 33. Accessibility

Accessibility is correctness.

Required:

- practical touch targets;
- semantic labels for cover placeholders, hydration/availability status, provider readiness, refresh actions, filters, selection state, and artwork gallery controls;
- logical keyboard traversal;
- visible focus;
- no color-only status;
- no hover-only action;
- 2x text scaling without clipping primary actions/status;
- screen-reader order matching visual/logical hierarchy;
- icon-only controls have names/tooltips where appropriate.

Game artwork itself should not produce redundant verbose semantics when adjacent title text already identifies the game; meaningful artwork-type/provenance controls remain labeled.

## 34. Performance

- Use lazy/virtualized grid/list rendering.
- Page from backend; never materialize the entire Library for filtering/sorting.
- Avoid one detail/provider query per card; Library rows contain the fields needed for cards/rows.
- Images load by `ArtworkAssetId` through the bounded artwork-assets client, deduplicate concurrent requests, and use bounded decode/cache behavior appropriate to displayed size without modifying stored originals.
- High-frequency job events are coalesced by existing architecture; Flutter avoids rebuilding the entire Library for one Game update.
- A Game row update reconciles by `GameId` or triggers a focused page/query refresh rather than resetting scroll indiscriminately.
- The UI must remain usable in the 10,000+ synthetic-Library qualification.

## 35. Controller State Ownership

Riverpod/controller state follows FE-002:

- backend entities remain queried/projection state;
- route scope lives in routing;
- filters/sort/view mode are typed query/presentation state;
- credential plaintext is transient ephemeral state only;
- dialog/menu/hover/focus state remains widget-local where possible;
- process-lifetime controllers may survive Activity recreation when the application composition survives;
- no durable persistence is introduced for transient selection, focus, open menus, or scroll positions beyond existing frontend restoration mechanisms.

## 36. Testing Requirements

### 36.1 Routing and shell

Tests assert:

- Library is default ready destination after onboarding;
- four active destinations preserve branch history;
- `/library` scopes parse/build correctly;
- `/games/:gameId` identity survives live width changes;
- redirected Game routes normalize without loops;
- Collections remains unavailable in production.

### 36.2 Exact adaptive boundaries

Exercise widths:

```text
599
600
839
840
1199
1200
```

plus live transitions across all classes. Route identity, selected/focused Game, query state, and usable primary actions remain correct.

### 36.3 Onboarding

Tests cover:

- fresh desktop no-root flow where confirming preferences and provider outcome uses authoritative commands, first-folder `Added`/`AlreadyConfigured` automatically completes onboarding, and initial refresh is admitted without a second click;
- Android readiness precedes product onboarding;
- existing-root upgrade skips folder re-add and uses explicit `Finish & Refresh` admission;
- locale defaults only when no persisted value exists;
- SteamGridDB `Ready`/`Unavailable` can record `Configured`, invalid/misconfigured configured states remain pending, credential removal is required before skip, and explicit no-credential skip records `Skipped`;
- credential plaintext cleared after submit;
- no secret appears in state serialization/log-safe error projections;
- completion persists before refresh admission and survives a later admission failure/restart;
- root removal, credential removal, or provider disablement after completion does not reopen onboarding;
- pre-completion configured credential removal makes that prerequisite incomplete again;
- transport ambiguity reconciles through onboarding/root/Jobs queries without duplicate dispatch;

### 36.4 Library

Widget/controller tests cover:

- no-root empty state;
- roots/no-games distinct states;
- first-page/later-page loading;
- grid/list switch with independent restoration;
- backend search/filter/sort requests;
- closed platform/region/hydration/availability filters and display-title/platform/release-date/updated-at sorts;
- backend facet requests whose own category is excluded from its count calculation;
- cursor/stale-request handling;
- progressive Game/metadata/artwork appearance;
- unmatched/partial/unavailable presentation;
- orphan removal only after authoritative query changes;
- duplicate source counts without duplicate cards;
- event loss/runtime replacement authoritative re-query.
- provider disablement triggers local resolution, excludes retained provider values from current winners without deleting records, and re-enable can reuse current retained records;

### 36.5 Selection/input

Tests cover desktop click/Cmd-Ctrl/Shift/arrow/Space/Enter and touch tap/long-press behavior, stable GameId selection, Refresh Selected admission, selection exit through Back, and focus restoration.

### 36.6 Game detail

Tests cover Compact/Medium/full detail and Expanded/Large inspector behavior, lazy sections, files/copies/discs, provider provenance, artwork gallery, Refresh Game, Force Refresh, unavailable content, redirected Game, and no Phase 004 Achievements/manual correction controls.

Coverage includes inactive-orphan historical detail plus artwork-byte success, missing-asset, cache/deduplication, and no-path/no-provider-URL leakage.

### 36.7 Accessibility

At 1x and 2x text scale, representative Library/onboarding/Game detail/provider settings/jobs flows must keep primary actions reachable. Semantics/focus tests cover meaningful status labels, filter controls, provider credential actions, artwork controls, selection, and refresh state.

### 36.8 Android integration

API 36 ARM64 integration coverage proves:

- Library default navigation;
- Add Library Folder -> refresh;
- refresh continues through Activity detach/reattach when foreground-hosted;
- Back/predictive Back order;
- notification cancellation path where applicable;
- permission/removable-volume state re-query;
- no duplicate runtime/provider/controller authority after recreation;
- secure credential-store failure never falls back to plaintext settings;
- artwork bytes remain loadable after Activity recreation without exposing app-private paths;
- `library_resolution_refresh` can remain foreground-hosted when it qualifies and reattaches through authoritative Jobs state.

## 37. Security and Privacy

- Never render/store/log credential plaintext outside transient entry controls.
- Never reveal stored SteamGridDB key; Replace/Remove only.
- Provider URLs/raw payloads do not become UI state unless explicitly sanitized by backend DTOs.
- Local opaque locators/Android URIs do not appear in Library state.
- Source display context comes only from safe backend projections.
- External network activity is attached to explicit user refresh/validation actions; simply viewing Library/Game detail does not initiate significant provider traffic.
- Artwork is retrieved by `ArtworkAssetId` through the bounded client API; app-private storage paths never enter Flutter state, and decoded bytes remain untrusted input under normal framework safety boundaries.

## 38. Out of Scope

- manual metadata editing;
- interactive match candidate selection;
- manual artwork selection/locking;
- manual Game merge/split;
- per-game locale overrides;
- provider priority editor;
- collections/favorites;
- command palette changes specific to Phase 003;
- RetroAchievements UI;
- automatic scheduled/background refresh.

Manual correction is later-MVP scope, not post-MVP.

## 39. Acceptance Criteria

SPEC-FE-010 is satisfied when:

1. Library is the default ready-state destination and primary navigation is Library/Sources/Jobs/Settings.
2. Product onboarding is separate from platform/backend readiness and supports required consent, locale preferences, provider setup, existing-root upgrades, and explicit initial refresh.
3. SteamGridDB setup is guided/skippable and never exposes stored credential plaintext.
4. Empty Library leads directly to Add Library Folder and normal add automatically requests refresh after root success.
5. Library uses backend-paged Game-level projections for grid/list/search/filter/sort/scopes.
6. Progressive refresh never replaces an already usable Library with a global blocking loading state.
7. Trustworthy unmatched Games remain visible with local fallback presentation.
8. Temporarily unavailable content remains distinguishable from authoritative orphan removal.
9. `/games/:gameId` uses one route identity across adaptive layouts and resolves backend Game redirects safely.
10. Game detail presents resolved metadata, variants/discs/copies, selected artwork, safe provenance/status, and history without recreating backend policy.
11. Refresh Library, Refresh Game, Force Refresh, and Refresh Selected reflect background admission truthfully through Jobs.
12. Normal Library-wide Force Refresh is absent.
13. Provider settings expose enablement/readiness and SteamGridDB credential replace/remove but no ranking UI.
14. Global region/language preferences persist through backend settings and affect presentation only.
15. Exact width boundaries, live resize, keyboard/touch, Back/predictive Back, semantics, focus, touch targets, and 2x text scaling are covered.
16. Android lifecycle/foreground execution reattaches to existing authoritative state without a second runtime.
17. Manual correction, Collections, and RetroAchievements UI remain absent from Phase 003.
18. The UI remains bounded and usable with a 10,000+ item Library.
19. Onboarding completion is backend-query-authoritative, survives refresh-admission failure, and does not reopen merely because all roots are later removed.
20. Metadata/provider setting changes preserve committed values independently from local resolution-job admission and never trigger provider networking implicitly.
21. Artwork rendering uses `ArtworkAssetId`/bounded bytes and never exposes object-store paths or provider URLs to feature code.

## 40. Prohibited Patterns

- Flutter-side platform/content identity or Game grouping;
- provider response parsing in feature widgets/controllers;
- storing credentials in Riverpod persistence/settings/DTOs;
- fetching provider data merely because a Game detail screen opened;
- local whole-Library filtering/sorting;
- route identity that changes with width;
- `/sources` reused as logical Library scope;
- hiding unavailable Games as though files were deleted;
- displaying provider confidence as one universal comparable score;
- frontend-selected metadata/artwork winners;
- manual candidate/editor controls in Phase 003;
- global SafeArea wrapping to patch Android insets;
- second Back coordinator;
- using notification state as job authority;
- presenting background admission as completion.

## 41. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-003 — Game Identification and Enrichment](../../phases/phase-003-game-identification-and-enrichment.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](../backend/spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](../backend/spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-009 — Application Service Contracts](../backend/spec-be-009-application-service-contracts.md)
- [SPEC-BE-010 — Provider Gateway Architecture](../backend/spec-be-010-provider-gateway-architecture.md)
- [SPEC-BE-013 — Library Source Management, Scan Operations, and Source Projections](../backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md)
- [SPEC-BE-015 — Game Library, Grouping, and Enrichment Contract](../backend/spec-be-015-game-library-grouping-and-enrichment-contract.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](spec-fe-004-routing-and-adaptive-application-shell.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-005 — Startup and Recovery UI](spec-fe-005-startup-and-recovery-ui.md)
- [SPEC-FE-006 — Appearance Settings and Theme Application](spec-fe-006-appearance-settings-and-theme-application.md)
- [SPEC-FE-007 — Design System Foundation and Accessibility Baseline](spec-fe-007-design-system-foundation-and-accessibility-baseline.md)
- [SPEC-FE-008 — Sources and Library Folder Management](spec-fe-008-sources-and-library-folder-management.md)
- [SPEC-FE-009 — Jobs and Background Operation Presentation](spec-fe-009-jobs-and-background-operation-presentation.md)
- [SPEC-X-002 — Android Platform Runtime and Capability Contract](../cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md)
