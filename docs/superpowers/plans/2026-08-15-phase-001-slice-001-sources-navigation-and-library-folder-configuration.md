# Phase 001 Slice 001 — Sources Navigation and Library Folder Configuration Implementation Plan

> **For agentic workers:** Implement this plan with TDD. Steps use checkbox
> (`- [ ]`) syntax. The approved plan and delegation PROMPT at
> `.chatgpt/codex-runs/2026-08-15T000014Z-phase-001-slice-001-sources-navigation-and-library-folder-configuration/PROMPT.md`
> are binding; this document records the concrete execution shape and the
> availability rationale required by the review.

**Goal:** Ship a genuine adaptive Sources destination where a user selects a
local folder through the native picker seam, confirms a root-only add, receives
typed duplicate/overlap outcomes, sees durable configured roots after restart,
and removes a root with explicit assurance that files on disk are untouched.
No scans, Jobs, source entries, or Add & Scan.

**Architecture:** Rust/SQLite remains the only durable authority. The
LocalFilesystem provider (argus-infrastructure) owns all filesystem parsing,
normalization, validation, locator construction, and overlap semantics.
argus-application owns the provider-facing normalized contracts and the
LibraryService. argus-domain owns only the stable identities
(`LibrarySourceId`, `LibraryRootId`). The bridge, ArgusClient, app composition,
routing/shell, and the Sources feature follow the existing Phase 000 patterns.

## Global Constraints

- Slice 001 only: no scan execution, JobRun/ScanRun persistence, Jobs UI,
  source-entry graphs, Add & Scan, Scan/Scan Again/Scan All, or cancel-and-remove.
- One lazily created internal LocalFilesystem `LibrarySource`; all roots reuse
  it; removing the final root preserves it.
- `GetLibraryRoot` is non-null end-to-end; a valid-but-missing root maps to
  `ConfigurationLibraryRootNotFound` (`ARGUS.V1.CONFIGURATION.LIBRARY_ROOT_NOT_FOUND`).
- Malformed `/sources/roots/:rootId` renders the distinguishable
  `invalidRouteData` surface (never a silent redirect); valid-but-missing roots
  canonicalize to `/sources` through authoritative feature state.
- No blanket platform case-folding: overlap returns `Unknown` unless the
  relationship is proven under actual filesystem semantics; persisted locators
  are never rewritten.
- Initial availability is `Available` only because add-time validation proves
  current reachability/enumerability (metadata plus opening the directory as an
  enumerable root). `lastScan = null` independently represents `NeverScanned`.
- Confirmation copy is root-only ("Add Library Folder") with scanning presented
  as unavailable; no inactive scan actions.
- Session-only sidebar override on Expanded/Large; no durable persistence.
- One root ProviderScope, one ArgusClient, one native event connection.
- Generated output only via `just generate`; all new generated files registered
  in the justfile.
- Tests use test-owned temporary directories; no developer library paths.
- Do not stage, commit, push, or rewrite Git history.

## Task 1: Rust domain identities

- [ ] TDD: `LibrarySourceId`/`LibraryRootId` (32-hex, non-zero, case-insensitive
  parse, canonical lowercase display) with domain tests.

## Task 2: Rust application contracts

- [ ] TDD: provider boundary (`SourceProviderType`, opaque `RootLocator`,
  `LocalFilesystemRootSelection`, `RootRelationship`, `ValidatedLocalRoot`,
  `ProviderError`, `LocalFilesystemProvider` port), projections
  (`LibraryRootProjection` with independent availability/lastScan/activeScan),
  queries/repositories, `LibraryService` (list/get/add/remove with typed
  `Added | AlreadyConfigured | OverlapsExisting` and slice `Removed`), events
  (`LibraryRootsChanged`, `LibraryRootChanged`), and the two additive error
  codes (`ConfigurationLibraryRootNotFound`,
  `FilesystemInvalidRootSelection`) plus `phase_001_all()`.

## Task 3: Rust infrastructure

- [ ] TDD: migration `0002_sources.sql` (library_source + library_root with a
  partial unique local-filesystem source index), LocalFilesystem provider
  (directory acceptance with enumerability proof, file/link-like rejection,
  relationship comparison via canonicalization with `Unknown` fallback, no
  persisted-locator rewrite), SQLite queries/repositories/UoW accessors, and
  restart survival tests using temporary directories.

## Task 4: Rust runtime and bridge

- [ ] TDD: `KernelBootstrap`/`ApplicationHost` library operations, extended
  `EventBus` with sources subscribers, `RuntimeEventPayload` sources variants,
  startup composition, bridge DTOs (`LibraryRootDto`, page, selection, typed
  results, event payloads), mapping, and FRB regeneration.

## Task 5: Flutter client and app composition

- [ ] TDD: client models (`LibraryRootId`, roots, page, selection, typed add
  result, remove result, event payloads), `SourcesGateway`/`SourcesApi`,
  ArgusClient.sources, FRB gateway mapping, `SourcesEventCoordinator`, and the
  `ArgusBootstrap` overrides (api, runtime context, reconciliation demand).

## Task 6: Routing, shell, and Sources feature

- [ ] TDD: `/sources` and `/sources/roots/:rootId` routes, `AppDestination.sources`,
  shell placement (Compact More, Medium rail, Expanded/Large sidebar), the
  distinguishable invalid-location surface, root list/detail controllers,
  root-only add workflow with picker seam, safe removal confirmation, and the
  session-only collapsible sidebar (0 roots none, 1 collapsed, 2+ expanded).

## Task 7: Architecture, generation, and completion gates

- [ ] Architecture-boundary tests updated (Sources activated; future
  `SourcesRoute`/`SourcesApi` prohibitions removed; feature guard added).
- [ ] `just generate` then `just check-generated` pass with zero drift.
- [ ] `just check` passes (format, lint/analyze, shellcheck, Rust dependency
  architecture, Rust and Flutter suites).
- [ ] `git diff --check` clean; no change outside the authorization boundary.
- [ ] Write `RESULT.json` per the completion contract with truthful evidence;
  if the MCP validator remains blocked by missing HOME/FVM, report it truthfully.

## Availability Rationale

SPEC-BE-011 §39 treats successful root resolution/enumeration as evidence for
`Available`. Slice 001 validation resolves the selected root as a real
directory-like enumerable object and opens the directory handle, which
establishes current reachability/enumerability without scanning contents.
Therefore a successfully configured root persists `availability_status =
available`; `last_scan` remains null and is the sole representation of
`NeverScanned`. If that evidence cannot be established, the add fails with the
sanitized provider/application failure and no root is persisted. Later slices
refresh availability from scan/read evidence.

## Plan Self-Review

1. Layer ownership matches SPEC-BE-011: identities in domain, provider-facing
   contracts in application, concrete adapter in infrastructure.
2. GetLibraryRoot stays non-null; missing roots are typed configuration errors.
3. Malformed route data and missing roots stay distinguishable.
4. Overlap semantics never use blanket OS case rules and default to Unknown.
5. Root-only confirmation copy exposes no inactive scan capability.
6. Availability and scan history remain independent authoritative dimensions.
7. Events are notification-only; all confirmed state comes from focused reads.
8. No scan/job/source-entry capability is scaffolded.
