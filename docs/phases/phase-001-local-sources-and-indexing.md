# Phase 001 — Local Sources and Indexing

**Document ID:** PHASE-001  
**Status:** In Progress  
**Owner:** Daniel  
**Last Updated:** 2026-08-15  
**Depends On:** ARCH-001, ARCH-002, PHASE-000  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

Phase 001 establishes the first ROM-management capability on top of the Phase 000 application foundation: authoritative discovery and persistence of what exists inside user-selected local library folders.

The phase activates the local-filesystem source and indexing contracts, durable background jobs, Sources presentation, Jobs presentation, and the bridge/application contracts required to coordinate them. Its product outcome is deliberately narrower than a game library. Phase 001 proves that Argus can safely configure storage boundaries, scan them in the background, persist and reconcile a hierarchical source graph, expose that graph for inspection, and recover correctly across cancellation, failure, and process restart.

The governing product boundary is:

> **Phase 001 answers “what source objects exist in the library folders the user explicitly selected?” It does not yet answer “what games are these?”**

### 1.1 Active implementation authority

Phase 001 implementation began after the focused public contracts identified in Section 6 were completed and this document moved to **Ready for Implementation**. All seven implementation slices and the required automated/native gates are now complete. The phase remains **In Progress** until the explicitly deferred manual evidence recorded in `IMPL-P01-007-VERIFICATION` is executed or reclassified through an explicit phase-closeout decision.

Section 6 lists governing prerequisites and same-phase refining contracts. Those same-phase subsystem specifications intentionally do not appear in this phase's authoritative `Depends On` metadata because they refine this phase rather than precede it.

While this document was in Draft, it served as sequencing and product-scope authority only, not authorization to implement unresolved bridge, application-service, Sources, or Jobs contracts.

Executable scope for an agent remains the intersection of:

1. this phase;
2. the active ordered slice or approved slice plan;
3. the explicit bounded task; and
4. the governing architecture, specifications, and conventions.

Ready later-MVP specifications continue to constrain compatibility without authorizing speculative game-content, parsing, hashing, metadata, artwork, verification, provider, route, schema, DTO, fixture, dependency, or UI work outside the active slice.

## 2. User-Visible Outcome

At the end of Phase 001, a user can:

1. Launch Argus on Windows, macOS, or Linux after Phase 000 startup completes.
2. Navigate to a genuine **Sources** destination.
3. Choose **Add Library Folder** and select a local directory through the native platform folder-selection flow.
4. Confirm an explicit **Add & Scan** action.
5. Have Argus persist the selected folder as a library root under its internally managed local-filesystem source model.
6. Continue using already available application UI while the scan runs as a durable background `LibraryScan` job.
7. See scan activity on the affected library folder, through the application-shell active-job indicator, and in a genuine **Jobs** destination.
8. Open a job and inspect its current or terminal status, affected root or roots, structured progress facts, timestamps, and bounded failure information.
9. Cancel an active library scan and have cancellation reach a safe durable terminal boundary without invalidating already committed positive observations.
10. Retry or rescan explicitly; every retry creates new immutable execution identities rather than reopening a historical run.
11. Browse an incrementally loaded hierarchical view of source entries Argus has authoritatively indexed for a configured root.
12. Inspect user-meaningful source facts such as display name, relative location, source-entry kind, classification, and relevant observation/scan status without exposing raw persistence or provider internals.
13. Add multiple local library folders.
14. Scan one configured folder independently.
15. Use **Scan All** to create one durable `LibraryScan` job coordinating separate per-root scan runs.
16. Inspect mixed per-root outcomes when a multi-root scan is only partially successful.
17. Remove a configured library folder after explicit confirmation, deleting only Argus-managed configuration/current index state and never deleting, renaming, or modifying files in the selected folder.
18. Close and relaunch Argus while preserving configured roots, committed indexed source state, terminal job history, and correct recovery of stale active scan execution.
19. Explicitly start a new scan after restart when prior work was abandoned; Argus does not automatically resume significant user work.

### 2.1 User-facing terminology

Phase 001 presentation uses product concepts such as:

- Library Folder
- Sources
- Scan
- Scan All
- Jobs

Normal setup and operational UI must not require the user to understand implementation concepts such as:

- `LibrarySource`
- provider instance
- reconciliation scope
- provider-native identity
- locator key
- source fingerprint
- Unit of Work
- runtime generation

Those concepts remain architectural/application concerns unless a later diagnostic surface explicitly requires a sanitized representation.

## 3. Canonical Demonstration Scenario

Phase 001 is demonstrated by the following sequence:

1. Start Argus against a valid Phase 000 application database with no configured library roots.
2. Navigate to Sources and confirm the empty state explains that no library folders are configured.
3. Choose **Add Library Folder** and select a test-owned local directory containing nested directories and files.
4. Confirm **Add & Scan**.
5. Argus persists the root configuration before scan admission; the root remains configured even if later scan admission fails.
6. The `LibraryScan` background job is admitted and appears in Sources, the shell active-job indicator, and Jobs.
7. The application remains usable while the scan runs.
8. Rust resolves and enumerates the selected root through the local-filesystem source-provider adapter and persists positive source observations incrementally through bounded transactions.
9. The Sources hierarchy begins showing committed indexed entries without requiring the full scan to complete first.
10. The scan reaches `Complete`; the root summary and Jobs detail reflect the durable result.
11. Modify the test-owned filesystem by adding one entry, removing another entry, and renaming/moving an entry where the platform/provider can establish trustworthy native continuity.
12. Run **Scan Again**.
13. Argus adds the new entry, removes the authoritatively absent entry only after exact-scope completion, and preserves the moved entry identity only when the source-provider evidence satisfies the governing move contract.
14. Configure a second library folder.
15. Run **Scan All** and observe one job with independent per-root scan outcomes.
16. Start another scan and cancel it.
17. Already committed positive observations remain valid; cancellation grants no absence authority.
18. Start a scan, terminate/restart the application before completion, and relaunch against the same test-owned application data.
19. Startup recovery marks stale scan execution as terminal recovery history according to the focused contract; no scan resumes automatically.
20. The user can inspect prior job history and explicitly start a fresh scan.
21. Remove one configured library folder after confirmation.
22. Argus removes current application-owned root/index state without modifying the underlying filesystem and preserves intelligible terminal job history.
23. No logical game records, metadata, artwork, hashing, or other later-phase capability is required for the demonstration.

This scenario should be automated wherever deterministic and practical. The primary full native milestone may remain macOS-based, with targeted Windows/Linux native filesystem coverage for platform-specific behavior.

## 4. In Scope

### 4.1 Local Library Folder Configuration

Phase 001 implements the local-filesystem source family only.

The user-facing workflow is folder-first:

- the user selects one or more local folders;
- Argus owns any required local-filesystem `LibrarySource` composition internally;
- each selected scan boundary is persisted as a `LibraryRoot`;
- normal UI manages library folders/roots rather than provider-instance plumbing.

Required capabilities include:

- list configured library folders;
- add a library folder;
- reject invalid or provider-provably overlapping root configurations according to SPEC-BE-011;
- persist root configuration independently of scan admission;
- remove a configured library folder safely;
- preserve root configuration across application restart.

Phase 001 does not require arbitrary editing of provider configuration, root locators, or discovery policy after creation. A later focused specification may add edit workflows when there is concrete user value.

### 4.2 Fixed Discovery and Classification Policy

Phase 001 uses one centrally owned, deterministic MVP discovery and classification policy. It answers what provider-visible source objects exist without guessing game/content meaning or silently filtering ordinary storage objects by name.

The fixed policy is:

| Provider observation | Retain | Traverse | Phase 001 persisted kind | Phase 001 classification |
|---|---:|---:|---|---|
| Directory | Yes | Yes | `Directory` | `Container` |
| File | Yes | No | `File` | `Unknown` |
| Link-like | Yes | No | `LinkLike` | `Ignored` |
| Other/unsupported structural object | Yes | No | `Unknown` | `Ignored` |

Additional invariants:

- no filename, extension, include-pattern, exclude-pattern, hidden, or system-attribute rule removes an otherwise provider-visible ordinary entry from the managed graph;
- hidden/system directories and files follow the same structural mapping above;
- symlinks, aliases, junctions, and equivalent link-like objects are retained as non-traversable evidence and are never followed;
- no user-facing include/exclude editor, hidden/system preference, or maximum-depth setting exists;
- no semantic maximum depth is treated as a successful policy exclusion;
- bounded safety/resource limits remain mandatory, but exhausting one makes the affected scope incomplete and produces `Partial` or `Failed` according to committed useful work; it never grants absence authority or silently truncates a `Complete` scan;
- the complete effective policy and policy revision are frozen into each scan plan;
- archive/container expansion is not performed in this phase.

Potential archives, disc images, playlists, and other meaningful files are retained as ordinary provider-observed `File` entries classified `Unknown`. Phase 001 does not refine them into archive, playlist, disc-image, content-candidate, or other transformation-owned semantic kinds. Later transformation work may refine application-owned kind/classification without changing stable `SourceEntryId` when its contract permits.

### 4.3 Durable Background Job Activation

Phase 001 activates the later-MVP background-operation portions of SPEC-BE-004 only as required by real `LibraryScan` work.

Required capabilities include:

- persisted `JobRun` execution identity and lifecycle;
- persisted per-root `ScanRun` identity and lifecycle;
- `BackgroundOperationManager` admission for library scans;
- structured progress facts;
- cooperative persisted cancellation intent;
- bounded resource admission required by the local scan operation;
- terminal job history;
- explicit retry/new-run behavior;
- startup reconciliation of stale active execution;
- one application-level event stream plus authoritative pull-based state queries.

Phase 001 must not create speculative background-operation types merely to exercise generic infrastructure. `LibraryScan` is the only product job type required by this phase.

### 4.4 Single-Root Scan

A configured root exposes an explicit Scan/Scan Again action.

At most one active `ScanRun` may own one root at a time. Duplicate same-root requests must not create competing scan ownership.

A successful single-root scan:

- resolves the current root;
- freezes the configuration/revision inputs required for authority;
- enumerates retained source observations;
- persists positive observations incrementally;
- performs safe reconciliation/finalization only where authority is established;
- records durable scan and job state;
- publishes notification events only after authoritative commits.

### 4.5 Add & Scan Coordination

The primary first-run action is **Add & Scan**.

This is a coordinated UX over two distinct durable boundaries:

```text
persist LibraryRoot
    ↓
root creation commits
    ↓
admit LibraryScan job
```

If root creation succeeds and scan admission subsequently fails, the root remains configured with a truthful never-scanned/current status and the user can explicitly invoke Scan later.

The UI must not compensate by silently deleting a successfully persisted root merely to make the combined interaction appear atomic.

### 4.6 Multi-Root Scan All

Sources exposes **Scan All** when appropriate.

One Scan All request creates one durable `LibraryScan` `JobRun` that may own multiple root-specific `ScanRun` records.

Required semantics include:

- each root preserves independent scan outcome semantics;
- mixed outcomes remain inspectable;
- a root already owned by another active scan is not raced by a second scan run;
- other eligible roots may continue when safe;
- cancellation applies to the owning background execution while preserving committed positive observations;
- retry creates new job and scan-run identities.

The focused Phase 001 application/Jobs specifications own the exact aggregate job-status and already-scanning presentation contract.

### 4.7 Authoritative Source Graph

Every retained discovered object becomes application-owned source-graph state according to SPEC-BE-011.

Phase 001 activates persistence and reconciliation sufficient for:

- `LibrarySource` configuration required by the local provider;
- `LibraryRoot`;
- `SourceEntry` hierarchy;
- `JobRun`;
- `ScanRun`;
- application/read projections required by Sources and Jobs.

Source observations are positive evidence and may be committed before a scan completes.

Absence authority is strictly bounded:

- only a successfully completed exact required scope may infer absence for unobserved prior entries in that scope;
- failed, partial, cancelled, unavailable, or abandoned work never implies absence;
- stale/incompatible configuration revision prevents destructive finalization;
- current deterministic policy exclusion may prune managed state only under the authority rules of SPEC-BE-011.

### 4.8 Conservative Move Preservation

Phase 001 preserves `SourceEntryId` across a move only when the provider/indexing contracts establish trustworthy continuity.

Phase 001 has no authoritative `ContentIdentity`, so SPEC-BE-011's strong-content-identity move tier is inactive. Only unambiguous stable provider-native identity may preserve `SourceEntryId`; every other apparent move is removal plus creation once the relevant completed scope has absence authority.

It must not preserve identity based only on:

- filename similarity;
- relative-path similarity;
- timestamp;
- size.

Ambiguous continuity becomes removal plus creation when the completed authoritative scope permits the removal.

### 4.9 Sources Destination

Phase 001 activates a genuine Sources destination rather than temporarily using the game-oriented Library destination.

Sources owns user-facing storage/indexing concerns including:

- library-folder list and empty state;
- Add Library Folder / Add & Scan;
- per-root status;
- Scan / Scan Again;
- Scan All initiation;
- safe root removal;
- root-detail navigation;
- hierarchical indexed-source inspection;
- source-specific local progress and failure presentation.

The game-oriented Library destination remains unavailable until a later active phase creates authoritative logical game content.

### 4.10 Hierarchical Source Inspector

Root detail exposes an operational hierarchy inspector for the current authoritative source graph.

The inspector must:

- load children incrementally rather than materializing an arbitrarily large source graph in Flutter;
- preserve stable hierarchy identity across ordinary refreshes;
- expose only user-useful source facts by default;
- remain usable while background scanning mutates committed source state;
- reconcile from authoritative focused queries after relevant notifications or event uncertainty.

Normal presentation may include:

- display name;
- relative location;
- directory/file/link-like/application-owned kind as appropriate;
- classification;
- last-observed or scan-related state when it is meaningful to the user.

Normal presentation must not expose raw provider-native identity, source fingerprints, internal locator keys, database metadata, or other persistence/infrastructure fields merely because they exist.

Source-entry search, arbitrary filtering, and developer-style raw source browsing are deferred.

### 4.11 Jobs Destination

Phase 001 activates a genuine Jobs destination and the application-shell active-job indicator.

The Jobs feature owns reusable background-operation presentation including:

- active/recent job list;
- job detail;
- structured progress presentation;
- cancellation;
- terminal states;
- retry/resume affordance rules according to operation capability;
- failure presentation;
- event-driven authoritative reconciliation.

Phase 001 supplies only the real `LibraryScan` job type. Jobs must not fabricate UI or contracts for metadata, artwork, verification, import, or other future operations.

### 4.12 Flutter Focused APIs and Bridge

Phase 001 activates the reserved focused client areas required by real product behavior:

- Sources-focused API surface;
- Jobs-focused API surface;
- minimal background-operation handle identity;
- source/root projections;
- source-entry child-page projections;
- job/scan projections;
- structured progress projections;
- typed events required for responsive reconciliation.

The bridge remains notification-first and query-authoritative:

```text
backend authoritative commit
    ↓
typed runtime event
    ↓
Flutter reconciliation demand
    ↓
focused authoritative query
    ↓
confirmed Riverpod state
```

Event payloads do not become a second state store.

### 4.13 Cross-Platform Desktop Support

Phase 001 product behavior is supported on:

- Windows;
- macOS;
- Linux.

The persisted provider type remains one `LocalFilesystem` family across desktop platforms. Platform-specific implementation differences remain behind infrastructure/platform boundaries.

Correctness must be based on effective resolved-root/provider guarantees rather than broad OS stereotypes about case sensitivity, identity, link behavior, or filesystem semantics.

Platforms that require durable filesystem authorization (for example a sandboxed macOS application) keep that authorization provider-owned and opaque: persisted configuration may carry provider-owned opaque authorization material in addition to the logical path/location, reopening a configured root restores or reacquires authorization before traversal, and a stale/revoked authorization is a typed source-access failure rather than a reason to delete the configured root.

The primary complete native E2E milestone may remain macOS-based. Windows and Linux require targeted native filesystem/provider coverage sufficient to prove their implementation is exercised rather than dead compile-only code.

## 5. Out of Scope

Phase 001 explicitly excludes:

- logical `GameContent` creation or game identity;
- the production game-oriented Library destination;
- game-detail presentation;
- parsing or typed intermediate representations;
- archive/container expansion;
- disc-image parsing;
- playlist interpretation;
- demand-driven or eager hashing;
- content identity schemes introduced by SPEC-BE-012;
- metadata matching or refresh;
- metadata-provider sessions/readiness implementation;
- artwork discovery, selection, download, or storage;
- RetroAchievements catalog/verification behavior;
- filesystem watching or automatic change notifications;
- automatic/periodic rescanning;
- automatic startup resume of significant scan work;
- concurrent discovery within one root;
- symlink/alias/junction/link traversal;
- cloud, SMB, NAS, removable-media-specific, or other additional source-provider families;
- source-provider credential storage;
- provider health/circuit breakers;
- discovery-policy editor;
- include/exclude glob UI;
- user-configurable maximum depth;
- source-entry search/filtering;
- raw source/persistence debug explorer;
- arbitrary provider/source-instance configuration UI;
- game collections;
- command palette;
- post-MVP notification inbox;
- unrelated Phase 002+ scaffolding, DTOs, routes, migrations, fixtures, dependencies, or generated bindings.

## 6. Required Subsystem Specifications

Phase 001 depends on the following existing contracts:

| ID | Specification | Phase 001 role |
|---|---|---|
| ARCH-001 | Argus ROM Toolkit Architecture | MVP scope, source/indexing model, jobs, Flutter ownership, scalability, security |
| ARCH-002 | Documentation Architecture | authority hierarchy, phase/slice rules, readiness requirements |
| PHASE-000 | Foundation | runtime, persistence, bridge, Flutter shell, startup/recovery, settings, events |
| SPEC-BE-002 | SQLite, Migrations, Repositories, and Unit of Work | Phase 000-to-Phase 001 migrations, repositories, transactional checkpoints, historical/current-state separation |
| SPEC-BE-003 | Application Errors, Logging, Diagnostics, and Observability | stable failures, trace correlation, sanitization, diagnostics boundaries |
| SPEC-BE-004 | Application Runtime, Command Pipeline, and Background Operations | durable jobs, cancellation, progress, restart reconciliation |
| SPEC-BE-006 | Minimal Domain Event Bus | post-commit application event semantics |
| SPEC-BE-007 | Startup Coordination and Recovery Contract | Phase 001 service composition and bounded stale-execution reconciliation before readiness |
| SPEC-BE-008 | Rust-to-Flutter Bridge DTO Contract | bridge identity/result/event rules and long-running operation foundation |
| SPEC-BE-009 | Application Service Contracts | use-case, transaction, repository, gateway, and event-recording ownership |
| SPEC-BE-011 | Source Provider and Indexing Contract | local source provider, roots, observations, source graph, reconciliation, scan semantics |
| SPEC-FE-001 | Flutter Project Structure and Feature Boundaries | Sources/Jobs ownership boundaries |
| SPEC-FE-002 | Riverpod, Freezed, and Controller State Conventions | generated state/controller rules |
| SPEC-FE-003 | ArgusClient and Focused Domain APIs | focused Sources/Jobs client boundaries |
| SPEC-FE-004 | Routing and Adaptive Application Shell | Sources/Jobs route and destination integration |
| SPEC-FE-005 | Startup and Recovery UI | preservation of Phase 000 startup/recovery authority |
| SPEC-FE-006 | Appearance Settings and Theme Application | preservation of root-theme authority |
| SPEC-FE-007 | Design-System Foundation and Accessibility Baseline | responsive/accessibility presentation baseline |
| SPEC-X-001 | Versioning and Compatibility Contract | additive bridge evolution, migration compatibility, and durable contract semantics |

### 6.1 Focused contracts required before Ready

The following focused contracts were completed before this phase moved from Draft to **Ready for Implementation**:

1. **SPEC-BE-013 — Library Source Management, Scan Operations, and Source Projections**  
   Defines the exact Phase 001 application use cases, read projections, folder-first local-source workflow, single/multi-root scan commands, root removal coordination, source-child queries, and scan-history contracts.

2. **SPEC-FE-008 — Sources and Library Folder Management**  
   Defines Sources routes/presentation, folder selection, Add & Scan, root listing/detail, scanning controls, hierarchy inspection, removal, responsive behavior, and feature-owned reconciliation.

3. **SPEC-FE-009 — Jobs and Background Operation Presentation**  
   Defines Jobs routes/presentation, active/recent jobs, detail, structured progress, cancellation, retry/resume affordances, shell indicator, and authoritative reconciliation.

4. **Focused Phase 001 amendments to SPEC-BE-008**  
   Concretizes only the Phase 001 bridge DTO/API/event surface required for Sources, Jobs, scan operation handles, source/root projections, and background-job queries.

These focused contracts must refine the approved phase decisions rather than reopen or silently broaden the product scope in this document.

## 7. Ordered Implementation Slices

Phase 001 uses seven vertical slices. Infrastructure may be introduced only when required by the observable outcome of the active slice.

Before any Phase 001 slice relies on the foundation, the repository must satisfy the applicable automated Phase 000 implementation and verification gates. The explicitly deferred Phase 000 manual evidence remains `NOT RUN`, must never be reported as passed, and does not block Phase 001 unless executing it later exposes a foundation defect. A Phase 001 slice may extend the implemented foundation; it must not silently compensate for an incomplete or defective Phase 000 contract by creating a parallel runtime, persistence, bridge, event, startup, routing, or theme path.

### SLICE-P01-001 — Sources Navigation and Library Folder Configuration

**Outcome:** The shipped application exposes a genuine Sources destination where a user can select, validate, persist, list, and safely remove local library folders using the folder-first product model, while preserving Phase 000 startup/theme behavior and without implementing scan execution yet.

This slice establishes only the source/root configuration contracts required by real UI. It does not add speculative source providers, policy editing, or source-entry graphs.

### SLICE-P01-002 — Durable Library Scan Job Foundation

**Outcome:** A never-scanned configured root can start one real single-root `LibraryScan` background execution with persisted job/scan identity, durable lifecycle/progress evidence, cancellation plumbing, a genuine Jobs destination, shell active-job indication, and incremental persistence of retained positive source observations under the fixed Phase 001 policy.

The scan must exercise the real local-filesystem operation boundary and durable runtime lifecycle. It may report `Complete` only when the first scan fully enumerated and persisted the initially empty managed graph. This slice does not activate repeat-scan absence deletion, prior-entry reconciliation, or move preservation; those authority-sensitive behaviors begin in Slice 003.

### SLICE-P01-003 — Authoritative Source Graph Indexing and Reconciliation

**Outcome:** Real library scans build and maintain the persistent hierarchical `SourceEntry` graph with positive-observation commits, exact-scope absence authority, conservative move preservation, partial/failure semantics, fixed discovery policy, and safe reconciliation across rescans.

This slice proves backend/indexing correctness before source-tree presentation becomes a user navigation contract.

### SLICE-P01-004 — Sources Hierarchy Inspection

**Outcome:** Root detail exposes an incrementally loaded, responsive, accessible operational hierarchy of the authoritative source graph with user-meaningful entry facts and event-triggered authoritative refresh.

The inspector remains source-oriented and does not masquerade as the future logical game Library.

### SLICE-P01-005 — Complete Scan Interaction Workflow

**Outcome:** The normal Sources/Jobs workflow supports Add & Scan, Scan Again, trustworthy structured progress presentation, cancellation, retry/new-run semantics, detailed job state, and robust event-gap/runtime-replacement reconciliation without duplicate frontend authority.

### SLICE-P01-006 — Multi-Root Scan All, Removal, and Restart Recovery

**Outcome:** Multiple configured roots can participate in one Scan All job with independent per-root outcomes; root removal coordinates safely with active ownership; terminal history remains intelligible after removal; and stale active scans reconcile correctly after application restart without automatic resume.

### SLICE-P01-007 — Cross-Platform and Phase Hardening

**Outcome:** The complete Phase 001 canonical scenario passes the platform-neutral quality gate plus dedicated native filesystem/E2E verification, Windows/macOS/Linux local-provider behavior is exercised appropriately, generated output is current, architecture boundaries are enforced, diagnostics remain sanitized, and no Phase 002+ capability has leaked into the repository.

## 8. Failure, Cancellation, and Recovery Expectations

### 8.1 Add & Scan failure boundaries

Root persistence and scan admission are separate durable operations.

If root persistence fails, no configured root exists and no scan is admitted.

If root persistence succeeds but scan admission fails, the root remains configured and truthfully reports that it has not completed a scan. The UI exposes a retryable Scan action where appropriate.

### 8.2 Positive evidence and absence authority

A scan may commit valid positive observations incrementally.

Already committed positive observations remain valid even when the overall scan later becomes:

- Partial;
- Failed;
- Cancelled;
- Abandoned.

Those incomplete outcomes never grant absence authority for unobserved entries.

Only completed exact-scope authority or deterministic current policy exclusion may justify removal according to SPEC-BE-011.

### 8.3 Per-root terminal outcomes

Root scan outcomes retain the governing semantics:

- `Complete` — full required discovery authority was established.
- `Partial` — useful work committed, but full required authority was not established.
- `Failed` — no meaningful indexing result was established for the root.
- `Cancelled` — user cancellation determined the terminal outcome.
- `Abandoned` — recovery-only terminal status after unexpected execution loss.

Root-level source unavailability remains distinct from a nested inaccessible/missing scope.

### 8.4 Cancellation

Cancellation is cooperative, durable, and job-scoped.

Required invariants:

- cancellation targets the owning `LibraryScan` background execution (the logical scan operation/job), never an individual root inside a multi-root Scan All job; Phase 001 provides no root-scoped cancellation;
- cancellation intent is persisted through the job/runtime contract and remains distinguishable from unexpected process loss;
- providers/indexing stop initiating new work promptly at safe checkpoints;
- a cancellation request arriving while a coherent mutation or scope finalization is already committing does not interrupt that in-flight transaction; the mutation commits atomically and cancellation is observed at the next safe checkpoint;
- a root whose child `ScanRun` already reached `Complete` before cancellation keeps that durable outcome; other still-active roots terminate as `Cancelled`, and the owning job is `Cancelled` when cancellation determines termination;
- committed positive observations remain valid, including partial discoveries from interrupted roots;
- cancellation grants no absence authority;
- terminal historical runs are immutable;
- a retry creates new execution identities;
- after restart, accepted durable cancellation intent maps stale active child scans to `Cancelled`, while unexpected loss maps them to recovery-only `Abandoned` (see Section 8.7).

### 8.5 Folder removal while scanning

Removing a root with active scan ownership is coordinated rather than raced.

Conceptually:

```text
confirm removal
    ↓
request/observe cancellation as required
    ↓
reconcile ambiguous transport outcomes through authoritative reads
    ↓
observe terminal/no-active ownership
    ↓
remove root + current Argus-managed source graph
```

Destructive current-state removal must not proceed merely because Flutter lost contact with a cancellation request.

`CancelJob` is job-scoped. When the root belongs to a multi-root Scan All execution, approving **Cancel Scan & Remove** cancels the entire owning job and may stop work for other roots. The confirmation and typed active-owner detail must disclose that impact; Phase 001 does not pretend to provide root-scoped cancellation inside a multi-root job.

### 8.6 Multi-root failure isolation

A Scan All job may have mixed root outcomes.

Failure, unavailability, existing ownership, or cancellation affecting one root must not be silently reinterpreted as success for that root. Other roots may continue when permitted by the focused orchestration contract.

A root that completes while another root is still enumerating keeps its durable `Complete` child outcome; aggregate job status is derived from all child outcomes and never rewrites an already-terminal child.

### 8.7 Restart recovery

Before the replacement runtime becomes `Ready`, startup performs bounded mandatory persistence reconciliation for stale Phase 001 execution. It performs no provider I/O, enumeration, retry admission, automatic resume, or new significant user work.

For each stale `LibraryScan` job:

1. already-terminal child `ScanRun`s remain unchanged;
2. a child still marked `Running` becomes `Cancelled` when durable cancellation intent had been accepted for the owning job, otherwise it becomes recovery-only `Abandoned`;
3. if every child was already terminal because the process died after child finalization but before generic job aggregation, the `JobRun` terminal state is derived from those durable child outcomes and admission exclusions rather than defaulted to `Abandoned`;
4. otherwise any recovery-cancelled child makes the owning job `Cancelled`, and any recovery-abandoned child makes it `Abandoned`;
5. root last-scan summaries are updated from the recovered child terminal result, while `Cancelled` and `Abandoned` do not change root availability;
6. stale root ownership is cleared, committed positive observations remain valid, and no incomplete scope gains absence authority.

Failure of this mandatory reconciliation prevents readiness. The user explicitly starts Scan Again, Scan All, or Retry afterward, creating new execution identities.

### 8.8 Event uncertainty

Sources and Jobs never depend on lossless event delivery for correctness.

Event gaps, runtime replacement, reconnect uncertainty, or coalescing trigger focused authoritative refresh rather than reconstruction from event payloads.

### 8.9 Diagnostics

Provider/native failures are translated before they cross infrastructure boundaries.

User-facing failures use stable application/feature semantics. Detailed diagnostics remain bounded and sanitized according to SPEC-BE-003.

## 9. Security and Privacy Impact

Phase 001 introduces read access to user-selected filesystem trees and therefore carries a higher filesystem/privacy impact than Phase 000.

Required security/privacy rules are:

1. Filesystem access begins only from explicit user-selected/configured roots.
2. Provider/root resolution must enforce the configured root boundary.
3. Link-like redirects are not followed for traversal in MVP.
4. Provider-provable overlapping roots are rejected according to SPEC-BE-011 rather than creating ambiguous authority.
5. Library scanning is read-only with respect to user ROM/library content.
6. Removing a root never deletes, renames, rewrites, or otherwise modifies underlying user files.
7. Source/provider input is untrusted and must not escape infrastructure as native objects or unsanitized native errors.
8. Absolute user paths, raw native errors, provider-native identities, source fingerprints, ROM names/content, and arbitrary serialized provider input do not enter normal logs, trace events, application errors, or diagnostic bundles unless an explicit governed sanitization contract permits a bounded representation.
9. UI may display the user-selected folder and relative locations required to operate Sources. Permission to present those values locally does not authorize unsanitized diagnostics or telemetry.
10. Phase 001 does not persist ROM bytes merely because content was indexed.
11. No credentials, tokens, API keys, or new credential-storage mechanism are introduced.
12. No remote provider/network activity is introduced by scanning local folders.
13. Temporary test/E2E directories must be test-owned and must never point at the developer's real ROM library or normal Argus application-data directory.
14. On platforms that require durable access authorization (for example a sandboxed macOS application), provider-owned opaque authorization material is persisted with the configured source only inside the provider boundary; the domain/application model never depends on platform-specific bookmark or authorization types.
15. Reopening a configured local source after restart restores or reacquires platform authorization before traversal; stale, missing, or revoked authorization produces a typed source-access failure and never silently deletes the configured source/root.
16. Non-sandboxed platforms/providers remain free to use simpler authorization representations.

## 10. Test Strategy

### 10.1 Domain and application tests

Required coverage includes:

- source/root/job/scan identifier invariants;
- root configuration validation;
- provider-provable overlap rejection;
- add/list/remove workflows;
- scan admission;
- duplicate same-root ownership;
- single-root job lifecycle;
- multi-root job semantics;
- cancellation;
- retry/new-run identity;
- removal coordination;
- application-event recording/publish boundaries.

### 10.2 Reconciliation tests

Required coverage includes:

- new observations create entries;
- unchanged observations preserve identity;
- trustworthy provider-native moves preserve identity;
- ambiguous/weak move evidence does not preserve identity;
- completed exact scopes may remove authoritatively absent entries;
- incomplete scopes never delete based on absence;
- nested failure preserves descendants under the failed scope;
- cancellation never grants absence authority;
- stale/incompatible scan-plan authority suppresses destructive finalization;
- policy pruning follows the governing distinction between exclusion and physical absence;
- root-level unavailability remains distinct from nested failure;
- the fixed Phase 001 observation-to-kind/classification table is applied exactly;
- hidden/system ordinary entries are retained rather than silently filtered;
- bounded resource-limit exhaustion yields an incomplete scope and never a falsely complete truncation;
- Phase 001 move preservation never uses the inactive `ContentIdentity` tier.

### 10.3 Persistence and migration tests

Phase 001 migrations/repositories must cover the persisted records actually activated by the phase, including:

- local source configuration as required;
- library roots;
- source entries;
- job runs;
- scan runs;
- required constraints/indexes;
- current read projections;
- startup/repository recreation persistence;
- root removal and historical-reference behavior defined by the focused application contract.

Migration tests must preserve the Phase 000 database upgrade path rather than assuming only fresh databases.

### 10.4 Local-filesystem provider integration tests

Use real temporary test-owned directory trees to exercise:

- nested directories/files;
- root resolution;
- source observation normalization;
- add/remove/rescan behavior;
- missing/unavailable roots where deterministic;
- nested access failures where deterministic;
- link-like entries without traversal;
- rename/move identity where the effective provider/filesystem guarantee supports it;
- platform-specific locator, case, and identity semantics where they materially differ.
- platform authorization restore/reacquire and stale/revoked failure behavior where the platform requires it (for example sandboxed macOS).

Tests must not encode broad OS stereotypes as provider guarantees.

### 10.5 Runtime and background-operation tests

Required coverage includes:

- persisted admission;
- lifecycle transitions;
- structured progress facts;
- queued/preparing/running cancellation boundaries as applicable;
- shutdown/process-interruption safety;
- startup reconciliation;
- no automatic resume;
- stale child recovery distinguishes durable cancellation intent (`Cancelled`) from unexpected loss (`Abandoned`);
- already-terminal child runs drive aggregate job recovery instead of being overwritten;
- recovery performs no provider I/O, new admission, retry, or resume;
- cancellation arriving during a coherent commit/finalization checkpoint completes the in-flight mutation before the next safe checkpoint;
- a root that completes before another root is cancelled keeps its `Complete` child outcome while the job terminates `Cancelled`;
- one active owner per root;
- multi-root failure isolation;
- event sequencing/uncertainty behavior.

### 10.6 Bridge and Dart client contract tests

Required coverage includes:

- focused Sources/Jobs APIs;
- Phase 001 DTO mapping;
- minimal operation-handle identity;
- source/root projection mapping;
- source-child page mapping;
- job/scan/progress mapping;
- typed event mapping;
- runtime sequence/replacement semantics;
- transport failure versus application failure;
- authoritative pull after ambiguous notification state.

### 10.7 Flutter controller and widget tests

Required coverage includes:

- Sources empty state;
- configured-root list/detail;
- native-picker seam behavior through deterministic fakes;
- Add & Scan success and split-boundary failure;
- Scan/Scan Again;
- Scan All mixed outcomes;
- incremental hierarchy loading;
- live committed hierarchy refresh during scanning;
- Jobs active/recent/detail state;
- structured progress presentation;
- cancellation;
- retry/new-run behavior;
- root removal with/without active scan ownership;
- event-gap/runtime-replacement reconciliation;
- active-job shell indicator;
- keyboard/focus/semantics behavior;
- representative Compact/Medium/Expanded/Large layouts;
- representative 1.0x and 2.0x text-scale behavior;
- Light/Dark/System theme compatibility through the existing Phase 000 theme owner.

### 10.8 Scalability-oriented tests

Normal verification must not require an enormous real filesystem fixture.

Scalability is protected through:

- incremental child queries;
- bounded page/query contracts;
- no requirement to materialize the entire source graph in Flutter;
- bounded event payloads;
- deterministic synthetic/load-focused tests where useful;
- database indexes/query-plan checks where the focused persistence contract requires them.

The architecture must remain viable for libraries containing hundreds of thousands of source entries without making everyday CI depend on a correspondingly large physical fixture.

### 10.9 Native milestone

A dedicated macOS native milestone should exercise the real Rust/FRB/SQLite stack against test-owned application data and a test-owned library tree.

The canonical proof should include, where practical and deterministic:

- add a temporary library folder;
- persist and scan it through real UI/client/backend layers;
- observe durable job state;
- inspect indexed hierarchy;
- mutate the test tree and rescan;
- verify authoritative add/remove/move reconciliation;
- exercise cancellation;
- exercise restart recovery/abandonment;
- verify no production/user filesystem state is used.

The native milestone remains separate from the deterministic platform-neutral `just check` gate when platform/process requirements make that separation necessary.

### 10.10 Windows and Linux native coverage

Windows and Linux CI must exercise the native local-filesystem provider and relevant platform glue sufficiently to prove real behavior rather than only compile compatibility.

Full duplication of the macOS E2E suite on every OS is not required unless a focused platform-risk analysis demonstrates that it is necessary.

### 10.11 Manual verification

Manual keyboard, screen-reader, visual, and exploratory filesystem checks remain documented evidence slots but may be intentionally reported as **NOT RUN/deferred** during the current implementation cadence.

Automated gates and result artifacts must never mark unexecuted manual verification as passing.

The completed implementation and automated/native evidence do not justify an invented Slice 008. The remaining work is phase-closeout evidence only unless a manual check exposes an implementation defect or an approved contract change creates new scope.

## 11. Exit Criteria

Phase 001 is complete when all of the following are true:

1. The approved Sources and Jobs workflow operates end-to-end through the real application architecture.
2. Users can add multiple local library folders with explicit folder selection and the folder-first product model.
3. Configured roots persist across application restart.
4. Add & Scan preserves the root when root creation succeeds but scan admission fails.
5. Single-root Scan/Scan Again produces durable job and scan-run history.
6. Scan All produces one durable job with independent per-root outcomes.
7. Successful scans build the authoritative hierarchical source graph.
8. Rescans correctly add and update observed entries.
9. Trustworthy move evidence preserves `SourceEntryId` only when permitted by the source contract.
10. Completed exact-scope authority may remove authoritatively absent entries.
11. Partial, failed, cancelled, unavailable, or abandoned work never gains invalid absence authority.
12. Users can browse the indexed hierarchy incrementally without loading the entire graph into Flutter.
13. Sources exposes only user-meaningful operational source facts by default.
14. Jobs remains usable independently of Sources widget/controller lifetime.
15. The shell exposes truthful active-job status without becoming job-state authority.
16. Cancellation reaches a safe durable terminal boundary and preserves committed positive observations.
17. Retry/rescan creates new immutable execution identities.
18. Startup reconciles stale active scan execution before readiness, distinguishes accepted cancellation from unexpected abandonment, derives aggregate state from already-terminal children where applicable, and performs no automatic resume.
19. Removing a root safely coordinates with active ownership, discloses that cancelling a multi-root owner cancels the whole job, and never modifies user filesystem content.
20. Terminal historical job/scan records remain intelligible after current root removal according to the focused application contract.
21. Event gaps/runtime replacement cannot make Sources or Jobs state incorrect; authoritative queries recover state.
22. Local-filesystem behavior satisfies the Phase 001 contract on Windows, macOS, and Linux.
23. The macOS native milestone passes against test-owned data.
24. Targeted Windows/Linux native filesystem coverage passes.
25. Phase 000 startup, recovery, diagnostics, event lifecycle, routing, settings, and appearance behavior remain intact.
26. Generated FRB/Riverpod/Freezed output is current and reproducible.
27. Architecture checks prevent Flutter filesystem traversal, provider-native leakage, duplicate job authority, feature-owned native event streams, and event-payload state authority.
28. Diagnostics remain sanitized under SPEC-BE-003.
29. `just check` remains deterministic/platform-neutral; required platform/native milestones use dedicated gates rather than weakening the canonical check.
30. No game-content, parsing, hashing, metadata, artwork, RetroAchievements, watching, extra provider, or other deferred capability has leaked into implementation.
31. Required result evidence reports automated and manual checks truthfully, including deferred manual verification.

## 12. Readiness Checklist

- [x] User-visible outcome is defined
- [x] Phase dependency on PHASE-000 is identified
- [x] Scope and exclusions are explicit
- [x] Required Phase 001 public interfaces are fully specified in focused subsystem contracts
- [x] Persistence impact is identified at the phase level
- [x] Failure and cancellation behavior are identified at the phase level
- [x] Security and privacy impact is identified
- [x] Test requirements are specified
- [x] Implementation slices are ordered
- [x] Exit criteria are measurable
- [x] No blocking phase-level product decisions remain
- [x] Daniel has accepted the capability and scope
- [x] SPEC-BE-013 is written, reviewed, and Ready for Implementation
- [x] SPEC-FE-008 is written, reviewed, and Ready for Implementation
- [x] SPEC-FE-009 is written, reviewed, and Ready for Implementation
- [x] SPEC-BE-008 Phase 001 bridge amendments are written, reviewed, and internally consistent
- [x] Cross-document consistency review confirms no unresolved Phase 001 public-contract ambiguity

**Readiness rule:** this document moves to **Ready for Implementation** only when every focused-contract/readiness item above is resolved. Moving the phase to Ready is a deliberate documentation-state change and must not be inferred merely because implementation could begin mechanically.

**Current completion state:** Slices P01-001 through P01-007 and their required automated/native gates are complete. The phase remains **In Progress** because the manual milestone evidence slots in `docs/implementation/phase-001-local-sources-and-indexing-verification.md` are still `NOT RUN`; those slots are not implementation-slice backlog.

## 13. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../architecture/architecture-overview.md)
- [ARCH-002 — Documentation Architecture](../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](phase-000-foundation.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](../specifications/backend/spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-006 — Minimal Domain Event Bus](../specifications/backend/spec-be-006-minimal-domain-event-bus.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](../specifications/backend/spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-009 — Application Service Contracts](../specifications/backend/spec-be-009-application-service-contracts.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](../specifications/backend/spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-BE-013 — Library Source Management, Scan Operations, and Source Projections](../specifications/backend/spec-be-013-library-source-management-scan-operations-and-source-projections.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](../specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](../specifications/frontend/spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](../specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](../specifications/frontend/spec-fe-004-routing-and-adaptive-application-shell.md)
- [SPEC-FE-005 — Startup and Recovery UI](../specifications/frontend/spec-fe-005-startup-and-recovery-ui.md)
- [SPEC-FE-006 — Appearance Settings and Theme Application](../specifications/frontend/spec-fe-006-appearance-settings-and-theme-application.md)
- [SPEC-FE-007 — Design-System Foundation and Accessibility Baseline](../specifications/frontend/spec-fe-007-design-system-foundation-and-accessibility-baseline.md)
- [SPEC-FE-008 — Sources and Library Folder Management](../specifications/frontend/spec-fe-008-sources-and-library-folder-management.md)
- [SPEC-FE-009 — Jobs and Background Operation Presentation](../specifications/frontend/spec-fe-009-jobs-and-background-operation-presentation.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../specifications/cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
