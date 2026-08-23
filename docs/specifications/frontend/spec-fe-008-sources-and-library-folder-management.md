# Sources and Library Folder Management Specification

**Document ID:** SPEC-FE-008  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-23  
**Depends On:** ARCH-001, ARCH-002, PHASE-001, PHASE-002, PHASE-003, SPEC-BE-004, SPEC-BE-008, SPEC-BE-013, SPEC-BE-015, SPEC-FE-001, SPEC-FE-002, SPEC-FE-003, SPEC-FE-004, SPEC-FE-005, SPEC-FE-006, SPEC-FE-007, SPEC-X-001, SPEC-X-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative Flutter product contract for Phase 001 Sources and local library-folder management.

It turns the backend source/root/scan contracts from SPEC-BE-013 into one coherent user-facing capability for:

- navigating to a genuine Sources destination;
- adding local library folders through the platform-appropriate folder-selection flow;
- explicitly choosing Add & Scan or Add Without Scanning;
- listing and inspecting configured roots;
- starting Scan, Scan Again, and Scan All;
- seeing concise root-local scan state while full background-operation detail remains owned by Jobs;
- browsing the authoritative indexed source hierarchy incrementally;
- inspecting safe source-entry details;
- removing roots without touching user files;
- coordinating root removal with active scan cancellation;
- reconciling authoritative state after backend events, sequence uncertainty, transport ambiguity, or runtime replacement;
- adapting the same route identities and feature state across Compact, Medium, Expanded, and Large layouts.

The central invariant is:

> **Sources is a folder-first, query-authoritative operational view over configured storage and the indexed source graph. Durable location stops at the selected root; source-entry browsing is transient feature state; background execution detail remains owned by Jobs.**

## 2. Responsibilities

SPEC-FE-008 owns:

- the Sources semantic application destination;
- Sources route declarations and route-to-feature behavior;
- placement of Sources in the adaptive application shell;
- the Sources empty state;
- local folder picker integration through a focused presentation/platform seam;
- the post-picker confirmation flow;
- Add & Scan and Add Without Scanning presentation;
- configured-root list and root-detail presentation;
- adaptive root-list/sidebar behavior;
- the session-only root-sidebar collapse override;
- Scan, Scan Again, and Scan All interaction presentation;
- concise root-local scan summaries and View Job navigation;
- root-removal confirmation and active-scan cancel-and-remove coordination;
- feature-owned Riverpod/controller state for roots and source hierarchy;
- incremental source-entry child loading and per-parent pagination state;
- source-entry expansion, drill-down, selection, and inspector presentation;
- live source-graph reconciliation while scans commit new state;
- error, stale-state, synchronization-uncertainty, and transport-ambiguity presentation for Sources;
- accessibility, keyboard, focus, responsive, text-scale, security, privacy, and performance rules for Sources;
- deterministic controller/widget test expectations.

## 3. Non-Responsibilities

SPEC-FE-008 does not own:

- backend source-provider semantics;
- source reconciliation/absence authority;
- provider-native filesystem APIs;
- `RootLocator`, `RelativeSourceLocator`, provider-native identity, source fingerprints, or locator keys;
- generic `JobRun` lifecycle authority;
- full Jobs destination/detail presentation;
- shell-wide active-job indicator behavior beyond navigation into Jobs;
- bridge DTO serialization layout;
- generated FRB source;
- logical game Library presentation;
- game resolution, parsing, hashing, metadata, artwork, or RetroAchievements presentation;
- source-entry search/filtering;
- filesystem watching or automatic periodic scanning;
- include/exclude policy editing;
- hidden/system-file preferences;
- archive/disc-image/playlist semantic expansion;
- durable persistence of transient source browsing state;
- durable persistence of the Sources root-sidebar collapse preference during MVP.

Those responsibilities remain with SPEC-BE-004, SPEC-BE-008, SPEC-BE-013, SPEC-FE-009, later frontend contracts, or post-MVP work.

## 4. Architectural Principles

1. Sources is a real semantic destination, not a Settings subsection.
2. Routes represent durable application location and scope; Riverpod/controller state owns transient source browsing interaction.
3. The configured `LibraryRoot` is the deepest durable Sources route identity in Phase 001.
4. Source-entry selection, expansion, pagination, drill-down, scroll, and focus are not route-authoritative.
5. Flutter consumes safe frontend models from focused APIs and never parses provider-owned locators.
6. Backend reads remain authoritative; events cause reconciliation and never become a second source graph in Flutter.
7. Usable confirmed content remains visible during ordinary mutations and refreshes.
8. Sources presents concise local scan context while Jobs owns complete durable operation detail.
9. Root removal never implies filesystem deletion.
10. Active-scan removal is an explicit composed UI workflow over separate CancelJob and RemoveLibraryRoot backend capabilities.
11. Adaptive layout changes presentation only; route identity and feature ownership do not change with width.
12. Source hierarchy browsing remains bounded and incremental for libraries containing hundreds of thousands of entries.
13. Accessibility and keyboard behavior are feature requirements, not optional polish.
14. Session-only presentation preferences do not silently become new durable Settings contracts.

## 5. Feature and Client Boundaries

The Sources feature follows SPEC-FE-001 feature-first ownership and depends on narrow frontend/client contracts rather than the `ArgusClient` facade.

Conceptually:

```text
Sources controllers
    ↓
SourcesApi
    ↓
bridge/client mapper
    ↓
SPEC-BE-013 application capabilities
```

Where Sources must cancel an active scan as part of the explicit removal workflow, it consumes the narrow generic Jobs control capability approved for Phase 001 rather than reaching through a root client facade.

Conceptually:

```text
Cancel-and-remove coordinator
    ├── SourcesApi
    └── JobsApi.cancelJob(...)
```

The feature must not import generated bridge source or bridge DTO types.

## 6. Required Focused API Semantics

The exact Dart interface syntax is owned by the focused client/bridge specifications, but FE-008 requires a Sources-focused capability surface equivalent to:

```text
listLibraryRoots(...)
getLibraryRoot(rootId)
addLocalLibraryRoot(selection)
addLocalLibraryRootAndScan(selection)
removeLibraryRoot(rootId)
startLibraryScan(rootId)
startLibraryScanAll()
listSourceEntryChildren(rootId, parentEntryId?, cursor?, pageSize)
getSourceEntry(sourceEntryId)
```

The feature also requires generic Jobs navigation/control capabilities sufficient to:

```text
cancelJob(jobRunId)
open/view job by JobRunId through typed application routing
```

Focused client calls follow SPEC-FE-003:

- queries return immutable snapshots;
- background admission returns an operation handle/admission result rather than awaiting completion;
- successful mutations do not cause Flutter to fabricate authoritative read state;
- application failures remain distinct from transport failures;
- ambiguous mutation transport outcomes are not blindly replayed;
- compatible additive DTO/model evolution follows SPEC-X-001; unknown additive fields are tolerated rather than rejected.

## 7. Sources Destination Placement

Sources is a lower-frequency semantic destination in the application-shell catalog.

Presentation by application size class is:

| Size class | Sources navigation placement |
|---|---|
| Compact | `More` |
| Medium | navigation rail |
| Expanded | labeled sidebar |
| Large | labeled sidebar |

`More` remains a presentation affordance rather than a route, consistent with SPEC-FE-004.

The destination identity is `Sources` regardless of size class.

The future game-oriented Library destination remains unavailable until a later phase creates authoritative logical game content.

Sources participates in the ready-shell branch/history model from SPEC-FE-004. Switching away from an inactive Sources branch and later returning may restore that branch's prior durable route such as `/sources/roots/:rootId`; reselecting the already active Sources destination follows the shell's canonical reselect behavior and returns that branch to `/sources`. This branch history does not persist source-entry selection, expansion, or other transient inspector state into route identity.

## 8. Canonical Sources Routes

Phase 001 defines these canonical durable Sources locations:

```text
/sources
/sources/roots/:rootId
```

`/sources` owns:

- empty state;
- configured-root landing/list;
- Add Library Folder;
- Scan All when meaningful.

`/sources/roots/:rootId` owns durable selection of one configured root.

No alternate wide-layout root-selection URI exists.

Do not represent the same root as:

```text
/sources/roots/:rootId
```

on Compact and:

```text
/sources?selectedRoot=:rootId
```

on wide layouts.

One route identity drives every adaptive presentation.

## 9. Invalid or Removed Root Routes

A routed `rootId` is an identity, not proof that the current root still exists.

When `/sources/roots/:rootId` resolves to a root that no longer exists:

1. Sources reconciles through the authoritative root query/list state;
2. stale root-specific transient state is discarded;
3. routing canonicalizes to `/sources`;
4. no stale cached root detail remains presented as current authority.

A root removed successfully from the current Sources model therefore cannot remain a valid current Sources detail route even though historical Jobs/ScanRuns may still reference its former identity.

## 10. Source Entries Are Not Routes

Phase 001 does not assign a durable route to each `SourceEntry`.

The following are intentionally not part of the route graph:

```text
/sources/roots/:rootId/entries/:entryId
/sources/roots/:rootId?selectedEntry=:entryId
```

Source-entry selection is operational browsing state over a mutable source graph.

Feature-owned transient state includes:

- expanded entry IDs;
- selected entry ID;
- Compact drill-down path;
- loaded children and paging cursors;
- local scroll position;
- local focus position;
- inspector open/closed state as required by presentation.

## 11. Sources Feature State Decomposition

Sources does not use one monolithic controller for unrelated responsibilities.

The feature must preserve clear state ownership equivalent to:

```text
SourcesRootListController
SourcesRootDetailController(rootId)
SourceHierarchyController(rootId)
SourcesMutationCoordinator
SourcesSessionPresentationState
```

Exact class names may differ, but responsibilities remain separated.

### 11.1 Root-list state

Owns:

- configured root page/list;
- empty state;
- list loading/refresh state;
- Scan All availability/pending initiation state;
- root-list reconciliation.

### 11.2 Root-detail state

Keyed by routed `LibraryRootId` and owns:

- current authoritative root projection;
- root-detail initial loading;
- focused root refresh/reconciliation;
- local scan summary projection;
- invalid/deleted-root detection.

### 11.3 Hierarchy state

Keyed by routed `LibraryRootId` and owns:

- loaded child pages by parent scope;
- per-parent cursors;
- expanded IDs;
- selected ID;
- Compact drill-down path;
- scoped loading/failure state;
- hierarchy reconciliation.

### 11.4 Mutation/workflow state

Owns pending user-initiated workflows such as:

- add confirmation;
- Add & Scan;
- Add Without Scanning;
- Scan;
- Scan Again;
- Scan All admission;
- remove confirmation;
- cancel-and-remove sequencing.

It does not replace root/read controllers as authoritative state stores.

### 11.5 Session presentation state

Owns the explicit root-sidebar collapse override and other strictly presentation-local session state approved by this specification.

Because the approved sidebar override intentionally survives route/widget observation gaps, this narrow presentation provider may be explicitly long-lived/`keepAlive` for the current Flutter application/provider-scope session under SPEC-FE-002. That lifetime is justified by the user-facing session contract, not by caching backend data.

## 12. Root Sidebar Collapse State

On Expanded/Large layouts the configured-root list may appear as a collapsible Sources-local sidebar beside root detail.

The collapse policy uses a nullable session override:

```text
sidebarOverride = null
    -> use adaptive default

sidebarOverride = collapsed
    -> collapsed for the remainder of the current Flutter application/provider-scope session

sidebarOverride = expanded
    -> expanded for the remainder of the current Flutter application/provider-scope session
```

Adaptive default while the override is `null`:

```text
0 roots  -> no root sidebar
1 root   -> collapsed
2+ roots -> expanded
```

Once the user explicitly toggles the sidebar, that explicit choice wins even if root count later changes during the same Flutter application session.

Leaving and returning to Sources during the same Flutter application/provider-scope session preserves the explicit override. A backend `RuntimeInstanceId` replacement or event-stream generation change does not by itself reset this purely presentational choice.

Relaunching Argus/recreating the root application provider scope resets the override to `null` and reapplies the adaptive default.

### 12.1 Post-MVP durable preference

Persisting the user's Sources sidebar-collapse preference across application restarts is an explicit post-MVP enhancement.

If introduced later, that preference must use the governed Settings/preferences architecture and migration rules. It must not be implemented through ad hoc local files, arbitrary shared preferences, or widget-owned storage merely because the MVP value is currently session-only.

## 13. Adaptive Root Layout

### 13.1 Compact

Compact uses a routed page flow:

```text
/sources
    ↓ select root
/sources/roots/:rootId
```

Root detail occupies the primary content region.

### 13.2 Medium

Medium also uses a full routed root-detail presentation by default.

Local subregions inside root detail may adapt to available width, but Medium does not require a persistent root-list/detail split.

### 13.3 Expanded/Large

Expanded/Large may render `/sources/roots/:rootId` as a stable list/detail layout:

```text
┌─────────────────┬──────────────────────────────┐
│ Library folders │ Selected root                │
│                 │ hierarchy / inspector        │
└─────────────────┴──────────────────────────────┘
```

Collapsing the root-list sidebar returns horizontal space to root content without changing the selected root or URI.

## 14. Sources Empty State

When no roots are configured, `/sources` presents a purpose-specific empty state.

It must:

- explain that Library Folders are folders Argus indexes as configured sources;
- state that indexing does not modify the user's files;
- expose **Add Library Folder** as the primary action;
- avoid showing disabled Scan All merely to reserve layout space;
- avoid presenting fake game-library content;
- avoid developer/provider terminology that is not useful to the user.

Once at least one root exists, normal root-management presentation replaces the onboarding empty state.

The configured-root list remains a bounded administrative projection. If pagination is required by the focused API, Sources follows the backend's bounded root-list paging contract rather than requesting or assuming an unbounded complete dataset.

## 15. Add Library Folder Entry Point

The user starts folder configuration through **Add Library Folder**.

Folder selection is accessed through a focused presentation/platform seam that can be deterministically substituted in tests.

On desktop, the seam may use the supported native folder-selection mechanism. On Android Phase 002, the seam is implemented by the Argus-owned local filesystem browser backed by provider/native browse projections; it does not use SAF tree selection as the product root-selection path.

The selection flow supplies a typed local-filesystem selection suitable for the Sources focused API contract.

Flutter must not construct a backend-authoritative `RootLocator` or infer provider overlap semantics.

Selecting a folder does not itself mutate Argus state.

## 16. Folder Selection Confirmation

After successful native folder selection, Sources presents an explicit confirmation step.

The primary action is:

```text
Add & Scan
```

The secondary action is:

```text
Add Without Scanning
```

Cancelling this confirmation performs no mutation.

The confirmation surface displays only safe provider/user-facing folder information needed to confirm the selection.

It must not display:

- provider-native identity;
- locator keys;
- source fingerprints;
- backend database metadata.

## 17. Add & Scan Workflow

Sources invokes the composite backend/application use case defined by SPEC-BE-013 rather than reproducing the two durable boundaries in Flutter.

Conceptually:

```text
user confirms Add & Scan
    ↓
SourcesApi.addLocalLibraryRootAndScan(selection)
    ↓
typed committed outcome
    ↓
authoritative Sources reconciliation
```

Flutter does not implement:

```text
add root
if success:
    separately call scan
```

as the canonical Add & Scan product workflow.

### 17.1 `AddedAndScanAdmitted`

Sources:

1. reconciles authoritative root state;
2. navigates to `/sources/roots/:rootId`;
3. shows the root-local active-scan summary;
4. exposes **View Job** for complete execution detail.

The returned operation handle identifies admission, not completion.

### 17.2 `AddedButScanNotAdmitted`

Sources:

1. preserves the committed root;
2. navigates to `/sources/roots/:rootId`;
3. reconciles the authoritative root and Jobs projections;
4. for `AlreadyScanning`, presents the existing active-scan summary and **View Job** without offering a duplicate scan;
5. for `AdmissionFailure`, presents the bounded `ApplicationError` in product language and exposes explicit **Scan** only after authoritative state confirms no active owner and current eligibility.

The UI must never compensate by deleting the committed root merely to make Add & Scan appear atomic.

### 17.3 `AlreadyConfigured`

Sources creates nothing new.

It navigates to the existing configured root and may show a bounded informational notice that the selected folder is already configured.

### 17.4 `OverlapsExisting`

Sources creates nothing new.

The add flow explains that the selected folder overlaps an existing configured Library Folder and, where useful, offers a direct action to open the existing root.

The frontend does not derive the overlap relationship itself.

## 18. Add Without Scanning

The secondary confirmation action invokes the root-add capability without admitting a scan.

On successful `Added`:

- authoritative root state is reconciled;
- Sources navigates to `/sources/roots/:rootId`;
- the root truthfully presents as never scanned/currently unindexed according to its projection;
- **Scan** is available when backend/current-state semantics permit it.

`AlreadyConfigured` and `OverlapsExisting` behave consistently with the Add & Scan workflow and do not silently initiate a scan.

## 19. Mutation Transport Ambiguity

A transport failure after issuing a mutation does not prove whether the backend committed the requested change.

For Add, Add & Scan, scan admission, cancellation, or removal when transport outcome is ambiguous:

1. Sources does not blindly replay the mutation;
2. the feature requests the smallest authoritative reconciliation capable of establishing current state;
3. last confirmed usable content remains visible when safe;
4. the UI exposes synchronization uncertainty when the committed outcome cannot yet be proven;
5. a conflicting/destructive follow-up mutation remains unavailable until the relevant uncertainty is resolved.

Capability-specific replay rules refine the general prohibition:

- the exact same `AddLocalLibraryRoot` selection may be replayed because backend creation is explicitly idempotent and returns `AlreadyConfigured`;
- `AddLocalLibraryRootAndScan` is never replayed as a composite after an ambiguous response;
- for ambiguous Add & Scan, replay only the idempotent add step to establish the authoritative root identity, then query the root and Jobs state;
- issue an explicit `startLibraryScan` only after those authoritative reads establish that no child scan admission exists;
- ambiguous scan, cancellation, or removal still reconciles through the relevant root/job queries before any conflicting repeat.

This follows SPEC-FE-002 and SPEC-FE-003 mutation/reconciliation conventions.

## 20. Root Detail State Dimensions

Root detail stores and renders independent authoritative dimensions supplied by the Sources read projection.

Conceptually:

```text
root identity/configuration
availability
lastScan?
activeScan?
```

The frontend must not flatten these into a single state machine that loses backend distinctions.

A root may simultaneously have facts such as:

```text
availability = Available
lastScan = Partial
activeScan = Running
```

Presentation may summarize those facts for readability, but the controller retains the independent authoritative dimensions.

When present, `lastScan.status` is one of `Complete`, `Partial`, `Unavailable`, `Cancelled`, `Failed`, or `Abandoned`; a missing summary means `NeverScanned`. `Cancelled` and `Abandoned` describe historical execution termination and do not by themselves change root availability.

## 21. Root Availability Presentation

A root that becomes unavailable does not cause Sources to erase the last confirmed indexed hierarchy merely because current filesystem access failed.

Sources:

- presents current root availability distinctly;
- retains last confirmed indexed graph data that remains authoritative;
- avoids implying that unavailable means empty/deleted;
- disables obviously invalid current-access actions where the projection/capability contract supports that conclusion;
- still treats backend admission as authoritative for races and changed state.

Nested source-access failures must not be presented as whole-root unavailability unless the authoritative root projection says so.

## 22. Scan and Scan Again

Root detail exposes operation initiation according to current root state.

Representative presentation is:

```text
never scanned, eligible       -> Scan
terminal scan history, eligible -> Scan Again
active scan                   -> View Job / active summary
```

The exact label is presentation-owned, but the backend remains authoritative for admission.

While an initiation request is unresolved, the conflicting initiation control for that root is disabled to avoid duplicate user submission.

Unrelated roots and already loaded hierarchy state remain usable.

### 22.1 Already scanning race

If backend admission reports that the root is already owned by an active scan:

- Sources does not show a generic unexpected failure;
- it reconciles the root projection;
- it presents the existing active scan;
- it offers **View Job** using the returned/current `JobRunId` where available.

Backend same-root ownership remains the race authority even when Flutter pre-disables obvious duplicate controls.

## 23. Scan All

`/sources` exposes **Scan All** when the authoritative root-list projection reports `totalCount > 0` and the normal read/admission guard permits interaction. Flutter does not infer target eligibility from the currently loaded root page; backend admission remains authoritative and may return partial exclusions or `NothingEligible`.

The control belongs to the Sources landing/global Sources action region rather than being duplicated on every root.

After admission, Sources presents concise operation-local feedback:

- the scan job was admitted;
- how many roots were admitted when that fact is part of the typed response;
- that some requested roots were excluded when applicable;
- **View Job** for exact exclusions, per-root progress, and durable execution detail.

Sources does not duplicate the full multi-root job-detail UI.

If no target is eligible and the backend creates no job, Sources shows the stable typed reason rather than fabricating an empty job card.

## 24. Sources Versus Jobs Presentation Boundary

Sources owns root-local operational context.

It may present:

- availability;
- last scan summary;
- active scan phase/state;
- bounded trustworthy progress facts;
- cancellation-in-progress state when part of cancel-and-remove;
- View Job navigation.

Jobs owns full background-operation detail, including:

- durable job timeline;
- complete requested/admitted/excluded target detail;
- full per-root ScanRun outcome list;
- complete structured progress detail;
- generic cancellation/retry/resume presentation;
- terminal failure detail;
- historical retry/new-run relationships.

Sources must not grow a parallel full Jobs detail screen.

## 25. Root Removal Without Active Scan

Removing a configured root is a destructive Argus-state operation but never a filesystem deletion operation.

When no active scan is known, Sources presents an explicit confirmation equivalent to:

```text
Remove Library Folder?

Removes this folder and its indexed data from Argus.
Files on disk are not changed.

Cancel | Remove
```

The exact wording may be localized/refined, but both consequences must remain clear:

1. Argus configuration/index state is removed;
2. underlying user files are untouched.

On successful removal:

- the current root disappears from Sources authoritative state;
- root-specific hierarchy/transient state is discarded;
- `/sources/roots/:removedId` canonicalizes to `/sources`;
- historical Jobs/ScanRuns remain accessible through Jobs.

## 26. Root Removal With Active Scan

If current state or a removal attempt establishes active scan ownership, Sources uses one explicit guided cancel-and-remove flow.

The user is asked to approve **Cancel Scan & Remove**.

Because cancellation is job-scoped, the confirmation consumes `owningJobRootCount`. When that count is greater than one, it must explicitly state that cancelling the scan also stops work for the other roots in the same Scan All job. The UI must not imply that only the selected root's child work can be cancelled.

Conceptually:

```text
user confirms Cancel Scan & Remove
    ↓
JobsApi.cancelJob(jobRunId)
    ↓
authoritatively reconcile job/root
    ↓
prove active ownership ended
    ↓
SourcesApi.removeLibraryRoot(rootId)
```

The frontend must not behave as though `RemoveLibraryRoot` implicitly cancels the job.

### 26.1 Cancellation failure/uncertainty

If cancellation fails definitely or its transport outcome is ambiguous:

- destructive removal stops;
- the root remains visible;
- authoritative job/root reconciliation is attempted;
- removal is not retried until active ownership is proven to have ended.

### 26.2 Removal race

If `RemoveLibraryRoot` itself returns the typed active-scan outcome because state changed after the UI initially inspected the root, Sources transitions into the same guided active-scan removal flow.

It does not show an opaque generic error.

## 27. Confirmed State During Mutations

Sources preserves usable confirmed state while ordinary mutations execute.

Examples:

- scanning one root does not blank or disable unrelated root rows;
- Scan All initiation does not replace the configured-root list with a full-page spinner;
- removing one root does not hide other configured roots;
- refreshing a root does not erase previously confirmed hierarchy while the refresh is pending;
- browsing loaded source entries remains possible while a background scan commits additional source state.

Only controls whose action conflicts with the pending operation are disabled.

A full loading replacement is reserved for true initial-load states where no usable confirmed content exists.

## 28. Error and Uncertainty Presentation

Sources distinguishes failure classes rather than reducing them to one error screen.

### 28.1 Initial-load failure

When no confirmed content exists, present a scoped failure surface with a deliberate retry action.

### 28.2 Refresh/reconciliation failure

When confirmed content exists:

- retain it;
- show bounded stale/synchronization indication;
- allow retry/reconciliation without discarding the current useful view.

### 28.3 Expected typed outcomes

Expected outcomes such as:

- already configured;
- overlaps existing;
- already scanning;
- root has active scan;
- nothing eligible to scan;

are rendered as feature-specific product states/messages rather than generic infrastructure errors.

### 28.4 Definite mutation failure

Preserve last confirmed state and offer deliberate retry where the operation semantics allow it.

### 28.5 Ambiguous mutation outcome

Reconcile authoritatively before another conflicting mutation is allowed.

Raw provider/native errors, opaque locators, fingerprints, database details, and stack/source-chain details never appear in normal Sources presentation.

## 29. Source Hierarchy Controller Model

The hierarchy controller is keyed by the current routed `LibraryRootId`.

Conceptual state includes:

```text
rootId
childrenByParent
pageStateByParent
expandedEntryIds
selectedEntryId?
compactDrillDownPath
reconciliationState
```

`childrenByParent` is a bounded frontend cache of authoritative child-page snapshots, not a complete source-graph authority.

Each parent scope owns its own pagination/loading/error state.

## 30. Incremental Child Loading

All hierarchy presentations use the focused child-page query from SPEC-BE-013.

Rules:

1. Entering/expanding a container loads only its direct children when not already sufficiently loaded.
2. Additional pages append within that parent scope only.
3. Loading one branch does not block already loaded sibling branches.
4. A child-page failure preserves previously loaded children for that parent.
5. A failed next-page request exposes a scoped retry rather than failing the entire root detail.
6. Flutter does not infer that an incomplete page is the complete child set.
7. Flutter does not globally resort partial pages as though it owned the complete backend ordering.
8. Collapsed branches may retain loaded child pages for the current feature/controller lifetime as a performance cache.

## 31. Adaptive Source Hierarchy Presentation

The same hierarchy state and IDs back different local presentations.

### 31.1 Compact

Compact uses a drill-down browser:

```text
current container
    ↓ select directory
child container view
```

Back/breadcrumb interaction returns toward the root.

### 31.2 Medium

Medium may use drill-down or shallow expandable hierarchy according to local available width.

This is a local layout choice, not a different route/state model.

### 31.3 Expanded/Large

Expanded/Large uses an expandable tree-style hierarchy with incremental child loading.

Expansion never implies eager recursive materialization.

## 32. Compact Drill-Down Path

Compact hierarchy navigation keeps a transient path of source-entry identities from the root scope to the current container.

This path is:

- feature state, not route state;
- validated during authoritative reconciliation;
- shortened to the nearest still-valid ancestor if a current node disappears;
- discarded when navigating to a different root or after root removal.

It is not serialized across application restart.

## 33. Source Entry Selection

Selecting a source entry updates transient `selectedEntryId` state.

Selection does not modify the URI.

When authoritative reconciliation completes:

- if selected identity still exists, selection is preserved;
- if the identity moved and continuity was preserved by the backend, selection remains associated with that same identity;
- if the identity is authoritatively removed, selection is cleared;
- if its new hierarchy location is not currently loaded, Flutter does not invent parentage merely to preserve visual placement.

A focused `getSourceEntry` read may maintain inspector detail for an existing selected identity independently of whether every ancestor branch is currently loaded.

## 34. Adaptive Selected-Entry Inspector

Selected-entry detail adapts to local available width.

### 34.1 Compact

Selection opens a transient focused detail surface such as an architecture-approved modal/bottom-sheet equivalent.

Dismissal returns focus to the selected hierarchy row when that row still exists.

### 34.2 Medium

Entry detail may appear in a secondary in-page region when local width permits. At narrower local constraints it may use the Compact-style transient surface.

### 34.3 Expanded/Large

A persistent entry inspector may appear beside the hierarchy.

A wide root detail may therefore render:

```text
roots | hierarchy | selected-entry inspector
```

The root sidebar and entry inspector remain independently presentational. Collapsing the root sidebar must not clear selected entry state.

## 35. Source Entry Projection Presentation

Normal hierarchy rows may display only user-useful safe facts such as:

- display name;
- directory/file/link-like/application-owned kind;
- classification where meaningful;
- bounded observation/scan state where meaningful.

The selected-entry inspector may additionally show the backend/client's safe relative display location and other bounded presentation facts approved by SPEC-BE-013/BE-008.

Normal Sources UI must not expose:

- `RootLocator`;
- `RelativeSourceLocator`;
- locator keys;
- provider-native identities;
- source fingerprints;
- raw persistence metadata;
- native error payloads.

## 36. Phase 001 File Semantics

Sources presents the fixed Phase 001 source-indexing policy exactly:

| Authoritative kind | Classification | Traversal presentation |
|---|---|---|
| `Directory` | `Container` | expandable/drill-down capable |
| `File` | `Unknown` | non-container entry |
| `LinkLike` | `Ignored` | retained evidence, never traversable |
| `Unknown` | `Ignored` | retained unsupported structural entry, never traversable |

Archive-like, disc-image-like, playlist-like, and similarly named files remain ordinary `File`/`Unknown` entries unless a later active phase supplies authoritative transformed semantics. FE-008 never guesses or decorates future kinds from filename or extension.

Hidden/system ordinary entries follow the same authoritative mapping and are not silently hidden by a frontend preference or name rule. If bounded backend resource limits make a scope incomplete, Sources presents the resulting `Partial`/`Failed` truth rather than implying a successfully truncated complete hierarchy.

## 37. Live Source-Graph Reconciliation

A scan may commit positive source observations while the user is browsing Sources.

Runtime/application events are invalidation hints, not source-entry mutations.

Canonical flow:

```text
backend commit
    ↓
typed event/invalidation
    ↓
Sources reconciliation demand
    ↓
focused authoritative query
    ↓
merge confirmed frontend projection
```

Flutter must not directly create, remove, or reparent source entries from event payloads as durable authority.

## 38. Reconciliation Scope

Sources refreshes the smallest reliable authoritative scope.

`SourceEntriesChanged` scope is explicit:

- `rootChildren` refreshes the configured root's direct-child page;
- `entryChildren(parentSourceEntryId)` refreshes that entry's direct-child page;
- `entireRootHierarchy` invalidates/reconciles all loaded hierarchy scopes for the identified root while preserving usable confirmed content during refresh.

Coalescing may broaden several narrow demands to `entireRootHierarchy`; it must never narrow them or interpret a missing/nullable parent as ambiguous scope.

Examples:

- root projection change -> refresh affected root;
- known loaded hierarchy parent/scope invalidation -> refresh that child scope;
- selected-entry invalidation -> refresh selected entry when appropriate;
- root-list configuration change -> refresh root list;
- event sequence gap, uncertain scope, or runtime replacement -> refresh the smallest broader Sources state that restores confidence.

High-frequency compatible demands may be coalesced, but coalescing must not suppress eventual authoritative refresh.

## 39. Browsing-State Preservation During Reconciliation

Authoritative reconciliation attempts to preserve interaction state by stable identity.

Rules:

- existing expanded entry -> remains expanded;
- existing selected entry -> remains selected;
- stable-ID move -> identity remains selected/expanded where the new graph location is known;
- removed selected entry -> clear selection;
- removed expanded entry -> remove stale expansion state;
- disappeared Compact current node -> retreat to nearest valid ancestor/root;
- stale loaded child cache may be replaced by the authoritative refreshed child page.

Flutter must not keep a stale hierarchy fact solely to avoid visible movement.

## 40. Runtime Replacement and Event Uncertainty

Sources participates in the application-level event uncertainty/reconciliation architecture established in Phase 000.

A runtime-instance replacement or detected sequence discontinuity invalidates assumptions that incremental notifications are complete.

Sources therefore:

1. does not replay event history to reconstruct state;
2. invalidates affected confirmedness as narrowly as safe;
3. performs authoritative focused reads;
4. preserves usable last-confirmed content while reconciliation is pending when safe;
5. prevents destructive/conflicting actions that depend on unresolved uncertain ownership.

## 41. Navigation to Jobs

Sources may navigate to a job from:

- an active root scan summary;
- Scan All admission feedback;
- already-scanning outcomes;
- other root-local scan context where a `JobRunId` is available.

Navigation uses typed routing/destination contracts owned by the application shell/Jobs feature.

Sources must not construct raw Jobs URIs through string concatenation.

The detailed Jobs route shape is owned by SPEC-FE-009.

## 42. Folder Selection Boundary

Folder selection is a presentation/platform side effect and must be isolated behind a narrow Flutter-side seam. The concrete interaction is platform-adapted: supported desktop platforms may use their native picker, while Android Phase 002 uses the Argus-owned mounted-filesystem browser.

The seam must support deterministic fakes for tests covering:

- user cancellation;
- one selected folder;
- picker/platform failure;
- controlled folder display information.

Production code may use the approved cross-platform native picker implementation, but feature controllers must not depend directly on plugin-specific result objects.

## 43. Security and Privacy

Sources introduces direct local presentation of user-selected filesystem context and must obey the Phase 001 privacy boundary.

Required rules:

1. Flutter never fabricates or parses backend/provider locators.
2. User-selected folder presentation is used only where needed to identify configured roots.
3. Safe relative entry locations may be displayed when supplied by the focused client model.
4. UI-visible path strings do not become implicit authorization to log or telemetry-record them.
5. Source/provider identifiers not intended for users remain outside presentation.
6. No ROM bytes/content are persisted or exposed merely because the source entry is browsed.
7. Root removal copy explicitly states that user files are not changed.
8. Link-like entries are not presented as traversable when traversal is disallowed.
9. Raw platform/native picker errors are mapped/sanitized before normal user presentation.
10. Tests use test-owned fake or temporary folder contexts and never point at a developer's actual ROM library.
11. On platforms that require durable platform authorization (for example a sandboxed macOS application), a persisted path string is not durable authorization; authorization is provider-owned and opaque, is restored/reacquired before traversal after restart, and a stale/revoked authorization surfaces as a typed source-access failure without Sources deleting the configured root.

## 44. Root Action Hierarchy

Root actions remain intentionally compact and state-appropriate.

Representative primary action mapping:

```text
Never scanned      -> Scan
Terminal scan      -> Scan Again
Active scan        -> View Job
```

Secondary actions include removal and contextual inspection.

Scan All is a Sources-level action rather than a duplicated per-root command.

Scanning is not styled as destructive.

Removing a root receives consequence-appropriate destructive emphasis consistent with SPEC-FE-007.

## 45. Keyboard Interaction

Desktop hierarchy interaction is keyboard-complete.

For expandable hierarchy presentation:

- Up/Down move among visible entries;
- Right expands a collapsed expandable entry or moves into its first visible child according to the chosen component semantics;
- Left collapses an expanded entry or returns focus toward its parent;
- Enter/Space invokes the primary inspect/open action appropriate to the focused row;
- Load More/retry controls are keyboard reachable;
- row actions are not hover-only.

Compact drill-down uses ordinary navigable list semantics with explicit Back/breadcrumb controls.

Exact shortcuts may follow Material/platform conventions, but equivalent keyboard capability is required.

## 46. Accessibility Semantics

Sources follows SPEC-FE-007.

Required semantics include:

- root rows expose accessible names and meaningful availability/scan state;
- expandable hierarchy entries expose expandable/collapsed state;
- selected state is perceivable without color alone;
- asynchronous child loading is announced without unexpected focus theft;
- scan state/progress uses semantic text/facts rather than animation-only communication;
- Add confirmation identifies the selected folder sufficiently for the user to verify intent;
- removal confirmation identifies the configured folder and consequence;
- **Cancel Scan & Remove** is distinguishable from ordinary cancellation;
- removal explicitly communicates that filesystem content remains untouched.

## 47. Focus Management

Focus behavior must remain predictable across transient and adaptive surfaces.

Examples:

- closing the Add confirmation returns focus to Add Library Folder when practical;
- dismissing a Compact selected-entry inspector returns focus to the originating hierarchy item if it still exists;
- successful root removal moves focus to an appropriate remaining root or the Sources landing action;
- pagination refresh does not reset hierarchy focus to the beginning without cause;
- an event-driven refresh does not steal focus merely because list contents changed;
- collapsing/expanding the root sidebar moves focus only when the focused control itself requires it.

## 48. Responsive Behavior

Sources supports the application-wide Compact, Medium, Expanded, and Large classifications while allowing child regions to react to local constraints.

Global size class chooses shell/root structural presentation.

Local constraints choose details such as:

- whether Medium shows an in-page inspector or transient inspector;
- how much root metadata remains visible;
- whether hierarchy row secondary text wraps, truncates, or moves to detail;
- tree indentation affordances.

The feature must not propagate hardware-category booleans such as `isDesktop` as layout authority.

## 49. Text Scaling

Representative 1.0x and 2.0x text-scale behavior is required.

At constrained width/text scale:

- primary folder/entry names remain readable;
- primary actions remain reachable;
- secondary metadata yields/collapses before essential controls;
- destructive-confirmation meaning remains visible;
- navigation does not rely on fixed-height text assumptions.

## 50. Theming

Sources consumes the application Material 3 Light/Dark/System theme ownership established by SPEC-FE-006 and SPEC-FE-007.

The feature does not maintain a parallel theme mode or hard-coded appearance authority.

Hierarchy selection, scan state, errors, destructive actions, and availability states must remain legible under both light and dark themes and cannot rely on color alone.

## 51. Performance and Scalability

Sources must remain viable for source graphs containing hundreds of thousands of entries.

Required constraints:

- no eager whole-tree load;
- bounded child pages;
- independent per-parent paging state;
- no client-wide global sort/filter of all entries;
- no assumption that Flutter owns the full sibling set while paged;
- no N-level eager recursion merely because a tree widget is expanded at an ancestor;
- bounded event/reconciliation work;
- coalescing of compatible high-frequency invalidation demands where useful;
- preservation of loaded useful state during background scan activity;
- root list/detail reads remain bounded;
- disposal of root-specific hierarchy caches when their owning feature/controller lifetime ends.

## 52. No Full-Tree Frontend Authority

The hierarchy controller is an incremental view cache only.

It must not become a client-side mirror database responsible for:

- proving absence;
- move reconciliation;
- deduplicating native identity;
- classifying files;
- resolving path overlap;
- rebuilding the backend graph from events.

Those remain backend responsibilities.

## 53. Persistence and Restoration

Phase 001 does not persist Sources feature interaction state separately from the governed router/settings architecture.

After application restart:

- `/sources` can restore normally;
- `/sources/roots/:rootId` re-enters authoritative root loading;
- deleted/stale root IDs canonicalize to `/sources`;
- selected source entry is reset;
- expanded entries are reset;
- Compact drill-down path is reset;
- loaded child-page caches are reset;
- scroll/focus state is reset;
- root-sidebar session override resets to adaptive default when the Flutter application/provider scope is recreated.

This is deliberate MVP behavior.

## 54. Concurrency and Stale Result Protection

Sources controllers obey SPEC-FE-002 stale-result and disposal rules.

Required behavior includes:

- results for a previously routed root cannot overwrite state for a newly routed root;
- a stale child-page completion cannot append to a parent state that has been invalidated/replaced without identity/version checks;
- disposed controllers do not publish later async completions;
- overlapping refreshes apply only when still relevant to the current controller generation;
- a pending add/scan/remove request does not mutate confirmed read models locally as a shortcut.

## 55. Testing Strategy

Normal frontend tests use focused API/provider/platform fakes and do not require the real Rust backend.

Native/backend integration coverage belongs to the Phase 001 integration/E2E strategy and SPEC-BE-008 bridge amendment.

## 56. Root-List Controller Tests

Required coverage includes:

- empty initial load;
- configured root load;
- initial-load failure and retry;
- refresh failure preserving confirmed roots;
- event-driven root-list reconciliation;
- stale async completion protection;
- Scan All hidden when root-list `totalCount == 0` and available when `totalCount > 0` without inferring per-root eligibility from the loaded page;
- Scan All admission/exclusion feedback remains backend-authoritative;
- zero-eligible Scan All behavior;
- mixed admitted/excluded concise feedback without duplicating Jobs detail.

## 57. Root-Detail Controller Tests

Required coverage includes:

- valid root load;
- stale/deleted routed root canonicalization demand;
- independent availability/lastScan/activeScan preservation;
- `Complete`, `Partial`, `Unavailable`, `Cancelled`, `Failed`, `Abandoned`, and nullable `NeverScanned` presentation without deriving availability;
- Scan admission;
- Scan Again admission;
- AlreadyScanning reconciliation;
- root unavailable presentation state;
- event-driven focused refresh;
- refresh failure preserving confirmed root detail;
- stale result protection when routed root changes.

## 58. Add Workflow Tests

Required coverage includes:

- picker cancellation -> no mutation;
- picker success -> confirmation only;
- confirmation cancellation -> no mutation;
- Add & Scan success;
- AddedButScanNotAdmitted retains root and offers Scan;
- AlreadyConfigured navigates to existing root;
- OverlapsExisting is non-mutating and explains conflict;
- Add Without Scanning success;
- ambiguous Add is safely replayable through exact idempotent root creation;
- ambiguous Add & Scan never replays the composite, establishes root identity through idempotent Add, queries root/Jobs authority, and starts an explicit scan only when no child admission exists;
- provider-native/locator details are absent from normal UI.

## 59. Removal Workflow Tests

Required coverage includes:

- remove with no active scan;
- removal confirmation states user files are untouched;
- cancellation of confirmation;
- active scan -> explicit Cancel Scan & Remove flow;
- multi-root owner -> confirmation discloses that job-scoped cancellation stops other roots in the same Scan All job;
- cancellation success -> authoritative no-owner reconciliation -> removal;
- cancellation definite failure -> no removal;
- cancellation transport ambiguity -> no removal until reconciled;
- removal race returning active ownership -> guided cancel-and-remove flow;
- successful removal canonicalizes route to `/sources`;
- removed root hierarchy/transient state is discarded;
- Jobs history is not presented as deleted by the Sources UI.

## 60. Hierarchy Controller Tests

Required coverage includes:

- root-level first page;
- nested direct-child loading;
- independent branch loading;
- per-parent next-page loading;
- scoped pagination failure and retry;
- loaded children preserved during failed next-page request;
- authoritative refresh of one loaded scope;
- `rootChildren`, `entryChildren`, and `entireRootHierarchy` invalidations refresh exactly the required loaded scopes;
- coalescing broadens but never narrows source invalidation scope;
- selection preservation by stable identity;
- expansion preservation by stable identity;
- selected-entry removal clears selection;
- expanded-entry removal clears stale expansion state;
- stable-ID move preservation;
- Compact drill-down retreat when current node disappears;
- event sequence uncertainty broadens authoritative refresh appropriately;
- runtime replacement does not reconstruct graph from event history;
- stale async child results cannot corrupt current state.

## 61. Adaptive Layout Widget Tests

Required coverage includes:

- Compact Sources via More;
- Medium Sources via rail;
- Expanded/Large Sources via sidebar destination;
- `/sources` and `/sources/roots/:rootId` route identity unchanged across resize;
- Compact/Medium full root detail;
- Expanded/Large root-list/detail split;
- zero-root no-sidebar behavior;
- one-root default collapsed sidebar;
- two-plus-root default expanded sidebar;
- explicit sidebar toggle overrides adaptive root-count changes for the current session;
- sidebar override resets only on a fresh Flutter application/provider-scope fixture;
- backend runtime/event-generation replacement alone does not reset the current Flutter-session sidebar override;
- collapsed sidebar does not clear root or source-entry selection;
- no alternate selected-root query URI.

## 62. Hierarchy/Inspector Widget Tests

Required coverage includes:

- Compact drill-down with Back/breadcrumb interaction;
- Medium local adaptation;
- Expanded/Large expandable tree;
- incremental loading affordance;
- selected-entry transient inspector on Compact;
- selected-entry secondary/persistent inspector on wider layouts;
- deselection/inspector dismissal behavior;
- loaded pages not mistaken for complete hierarchy;
- safe source facts only;
- archive/disc-image/playlist-like files not given speculative semantic UI.
- exact Directory/Container, File/Unknown, LinkLike/Ignored, and Unknown/Ignored presentation mapping;
- hidden/system ordinary entries are not silently filtered;
- incomplete resource-limited scopes never appear as successfully complete hierarchies.

## 63. Accessibility and Keyboard Tests

Required coverage includes:

- root semantics include name plus meaningful state;
- hierarchy expansion semantics;
- selection semantics independent of color;
- keyboard tree navigation;
- keyboard reachability of Load More/retry/actions;
- focus restoration after dialogs/inspectors;
- no focus theft during event-driven refresh;
- removal consequence and file-preservation semantics;
- representative 1.0x and 2.0x text scale;
- Light/Dark/System theme compatibility.

## 64. Integration and Native Verification Expectations

Phase 001 integration/E2E verification exercises FE-008 through the real architecture for the canonical user scenario, including:

- native folder selection seam on supported desktop platforms;
- configured root persistence across restart;
- Add & Scan split durable boundary behavior;
- live hierarchy changes during real scanning;
- Scan/Scan Again;
- Scan All;
- active-scan removal coordination;
- event-gap/runtime-replacement authoritative reconciliation where testable;
- cross-platform Windows/macOS/Linux local-folder behavior;
- macOS primary full native milestone proof.

Manual verification may remain deferred according to the current Phase 001 execution plan. Result artifacts must distinguish `PASS`, `FAIL`, and `NOT RUN`.

## 65. Prohibited Patterns

FE-008 implementations must not:

- place Sources under Settings instead of the semantic destination catalog;
- make Sources a Compact primary bottom-navigation item during Phase 001;
- create a separate wide-layout selected-root URI;
- encode source-entry selection into route/query state;
- construct/parse backend provider locators in Flutter;
- mutate source graph state directly from event payloads;
- model the entire source graph as one frontend snapshot;
- globally sort/filter partial paged hierarchy as though complete;
- duplicate full Jobs detail inside Sources;
- silently cancel jobs inside a remove call;
- proceed with destructive root removal while scan cancellation/ownership is uncertain;
- imply that root removal deletes user filesystem content;
- persist the MVP sidebar override through ad hoc storage;
- add source-entry search/filtering in Phase 001;
- infer future archive/game semantics from filename extensions;
- block the entire Sources destination during one root mutation;
- expose raw provider/native errors or internal persistence identifiers.

## 66. Out of Scope

The following are outside Phase 001 FE-008:

- logical game Library screens;
- game/content search;
- source-entry search/filtering;
- root rename UI;
- provider configuration editing;
- include/exclude glob editing;
- hidden/system-file preferences;
- user-configurable maximum scan depth;
- archive/container expansion UI;
- disc-image/playlist semantic inspection;
- drag-and-drop root creation;
- filesystem watch controls;
- scheduled/automatic rescans;
- persistent source hierarchy expansion/selection;
- durable root-sidebar collapse preference;
- full Jobs detail/history UI;
- metadata/artwork/RetroAchievements actions.

## 67. Post-MVP Follow-Up

The following is explicitly recorded for post-MVP product work:

> Persist the user's Sources root-sidebar collapsed/expanded preference across application restarts.

That follow-up should preserve the current adaptive default as the no-preference baseline and introduce durability only through the governed Settings/preferences architecture.

This note does not authorize MVP persistence implementation.

## 68. Acceptance Criteria

SPEC-FE-008 is satisfied when:

1. Sources is a genuine semantic destination presented through More on Compact, rail on Medium, and sidebar on Expanded/Large.
2. Canonical routes are `/sources` and `/sources/roots/:rootId` across all layouts.
3. Source-entry selection/expansion/drill-down remains transient feature state rather than route state.
4. Expanded/Large root detail supports a collapsible root-list sidebar.
5. With no explicit session override, one root defaults collapsed and two or more roots default expanded.
6. A user's explicit sidebar toggle overrides later root-count changes for the remainder of the current Flutter application/provider-scope session and is unaffected by backend runtime replacement alone.
7. Sidebar preference is not durable in MVP, and post-MVP persistence is documented as governed Settings work.
8. Add Library Folder invokes a native picker without mutating Argus merely from selection.
9. Folder selection is followed by explicit Add & Scan primary and Add Without Scanning secondary actions.
10. Add & Scan uses the backend composite workflow, presents typed child-admission outcomes, and preserves a committed root when scan admission fails.
11. AlreadyConfigured and OverlapsExisting are typed, non-mutating product outcomes.
12. Ambiguous Add may use exact idempotent replay, ambiguous Add & Scan never replays the composite, and all other ambiguous mutations reconcile authoritative state before conflicting repeat.
13. Root detail exposes independent availability, active-scan, and complete last-scan truth including `Abandoned`, without inventing a duplicate authority enum or deriving availability from historical execution status.
14. Scan/Scan Again remain usable without blocking unrelated Sources state.
15. Scan All is exposed from authoritative root-list `totalCount > 0`, never infers per-root eligibility from the loaded page, presents concise typed admitted/excluded feedback, and delegates full execution detail to Jobs.
16. Sources exposes View Job rather than duplicating the complete Jobs UI.
17. Root removal explicitly states that user files are untouched.
18. Active-scan removal discloses whole-job impact for multi-root owners, performs explicit CancelJob, authoritatively proves no remaining ownership, then calls RemoveLibraryRoot.
19. Removal stops while cancellation/ownership remains uncertain.
20. Successful removal canonicalizes stale root detail to `/sources` and discards root-specific transient hierarchy state.
21. Source hierarchy loads direct children incrementally with independent per-parent pagination.
22. Compact uses drill-down hierarchy, Expanded/Large uses expandable tree, and Medium adapts locally while using the same state model.
23. Selected-entry inspector is transient/adaptive and never changes route identity.
24. Live scan updates use explicit root-children/entry-children/entire-root invalidation scope to drive focused authoritative reconciliation rather than direct event-driven source-graph mutation.
25. Stable source identity preserves selection/expansion where authoritative entities still exist; removed entities clear stale transient references.
26. Root unavailability does not erase valid last-confirmed indexed hierarchy.
27. Sources never exposes provider-native locators, identities, fingerprints, or database metadata in normal UI.
28. Keyboard, focus, accessibility, text-scale, and Light/Dark/System behavior meet FE-007 requirements.
29. The feature remains bounded for very large source graphs and never requires full-tree materialization in Flutter.
30. Deterministic controller/widget tests cover all approved workflows, uncertainty behavior, adaptive layouts, hierarchy paging/reconciliation, and accessibility interactions.
31. Phase 001 native/integration verification exercises the real Sources workflow without treating deferred manual checks as passed.
32. Sources presents the exact Phase 001 kind/classification/traversal mapping, retains hidden/system ordinary entries, and never presents an incomplete resource-limited scope as a complete hierarchy.

## 69. Phase 002 Android Folder-Browser and Root-Availability Amendment

Android root selection is platform-adapted rather than a literal copy of the desktop picker.

The Android flow:

1. presents provider/native-discovered locally mounted storage volumes;
2. browses bounded accessible child directories through focused typed projections;
3. provides breadcrumbs/up navigation and an explicit `Select this folder` action;
4. uses Android Back to move up hierarchy before dismissing when appropriate;
5. never asks Flutter to canonicalize filesystem paths, infer overlap, or interpret Android volume/authorization identity; and
6. does not use SAF/cloud/virtual document providers as a hidden fallback for Phase 002 local roots.

Final selection enters the existing root-admission API and preserves Added / AlreadyConfigured / OverlapsExisting semantics plus committed-root-then-child-scan admission for Add & Scan.

If All files access is revoked, the Sources feature is covered by platform readiness rather than deleting configuration. If removable media is absent, affected roots render typed unavailable state while other roots remain usable. A trustworthy remount restores the same configured root identity. Removing a root remains configuration/index removal only and never deletes user files.

## 70. Phase 003 Library Add-Folder Integration

PHASE-003 activates a logical game Library, but Sources remains the operational root/filesystem/index surface defined by this specification.

The normal Add Library Folder action launched from Library uses the same platform picker, root validation, duplicate/overlap policy, and root-persistence authority as Sources. After root persistence succeeds it requests the composed `AddLocalLibraryRootAndRefresh` / `library_refresh` workflow defined by SPEC-BE-015 and FE-010.

During incomplete first-run Library onboarding, folder selection uses the existing root-only `AddLocalLibraryRoot` capability. After `Added` or the idempotent `AlreadyConfigured` outcome, the onboarding coordinator automatically commits completion and requests the initial `library_refresh`; selecting the first folder is therefore the final user action and no second confirmation click is required. An `OverlapsExisting` outcome remains unresolved folder-selection feedback and admits no refresh. Existing-root upgrades, which have no folder-selection event, retain the explicit `Finish & Refresh` action.

This sequence prevents duplicate refresh jobs while preserving the committed-root-first boundary. Transport ambiguity is reconciled through idempotent root admission plus authoritative onboarding/root/Jobs queries rather than replaying either composite operation blindly.

Truthfulness rule:

```text
root creation succeeds + refresh admission fails
    -> root remains configured
    -> UI reports refresh failure separately
```

The Library flow must not roll back a successfully committed root or mislabel the add operation as wholly failed.

Sources retains explicit operational actions for users who need lower-level control, including existing scan/rescan controls and an advanced `Add Without Refreshing` path where the active product surface exposes it. A Sources-originated standalone scan still creates the `library_scan` operation defined by SPEC-BE-013; it does not masquerade as full metadata/artwork hydration.

Archive/disc/playlist semantic expansion introduced by Phase 003 remains backend transformation/Game authority. FE-008 continues to render the source graph it is given and does not infer game/media identity from filenames or extensions.

## 71. References

- `docs/architecture/architecture-overview.md` — ARCH-001
- `docs/architecture/documentation-architecture.md` — ARCH-002
- `docs/phases/phase-001-local-sources-and-indexing.md` — PHASE-001
- `docs/phases/phase-003-game-identification-and-enrichment.md` — PHASE-003
- `docs/specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md` — SPEC-BE-004
- `docs/specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md` — SPEC-BE-008
- `docs/specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md` — SPEC-BE-013
- `docs/specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md` — SPEC-BE-015
- `docs/specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md` — SPEC-FE-001
- `docs/specifications/frontend/spec-fe-002-riverpod-freezed-and-controller-state-conventions.md` — SPEC-FE-002
- `docs/specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md` — SPEC-FE-003
- `docs/specifications/frontend/spec-fe-004-routing-and-adaptive-application-shell.md` — SPEC-FE-004
- `docs/specifications/frontend/spec-fe-005-startup-and-recovery-ui.md` — SPEC-FE-005
- `docs/specifications/frontend/spec-fe-006-appearance-settings-and-theme-application.md` — SPEC-FE-006
- `docs/specifications/frontend/spec-fe-007-design-system-foundation-and-accessibility-baseline.md` — SPEC-FE-007
- `docs/specifications/frontend/spec-fe-010-library-game-detail-and-enrichment-ux.md` — SPEC-FE-010
- `docs/specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md` — SPEC-FE-009
- `docs/specifications/cross-cutting/spec-x-001-versioning-and-compatibility-contract.md` — SPEC-X-001
