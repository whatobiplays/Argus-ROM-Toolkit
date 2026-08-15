# Phase 001 Slice 002 — Durable Library Scan Job Foundation Implementation Plan

> **For agentic workers:** Implement with TDD. The delegation PROMPT at
> `.chatgpt/codex-runs/2026-08-15T021327Z-phase-001-slice-002-durable-library-scan-job-foundation/PROMPT.md`,
> SPEC-BE-004/008/011/013, SPEC-FE-003/004/008/009, and SPEC-X-001 are binding.
> Steps use checkbox (`- [ ]`) syntax. Run the repository's safe validation
> workflow (`just generate`, `just check-generated`, `just check`) and finish
> by writing `RESULT.json` per the Completion Contract plus a user-facing
> completion response. Do not stage, commit, push, or rewrite Git history.

**Goal:** One real single-root `LibraryScan` background operation on an
eligible never-scanned root, with durable JobRun/ScanRun identity and
lifecycle, structured progress, cooperative cancellation, incremental
positive-observation persistence, authoritative root scan summaries, a
genuine Jobs destination, and a shell active-work indicator — without Scan
Again, Scan All, retry, resume, absence deletion, or restart recovery.

**Architecture:** Rust/SQLite stays the sole durable authority via the
existing one-worker executor; `ApplicationRuntime` owns exactly one
`BackgroundOperationManager` per generation; background execution runs on
manager-owned worker threads using a cloned executor handle and the shared
event bus, never holding the kernel mutex. The LocalFilesystem provider
(infrastructure) owns resolution, locator keys, direct-child enumeration,
native identity, and error translation; the application indexer owns
traversal and reconciliation; Flutter consumes only pure-Dart focused models
via the single ArgusClient/event path. No new dependencies.

## Global Constraints

- Slice 002 only: no Add & Scan, Scan Again, Scan All, Retry, Resume, absence
  deletion, move reconciliation, hierarchy UI, cancel-and-remove
  orchestration, or stale-active restart recovery.
- One `BackgroundOperationManager` per runtime generation; generic and
  runtime-owned; no process-global/static manager or second runtime/database.
- `LibraryScan` resource intent is exactly `FilesystemRead` +
  `PersistenceWrite`; no CpuIntensive/network resources.
- `ScanRun` is durably `Running` from successful application admission until
  terminalization, even while its `JobRun` is Queued/Preparing.
- Provider I/O happens outside write transactions; positive observations are
  incremental and retained after partial/failure/cancellation.
- Events are invalidation/progress hints; authoritative queries remain the
  source of truth. No parallel runtime, database, or native event connection.
- Generated output only via `just generate`; all new generated files
  registered in the justfile.
- Tests use test-owned temporary directories; no developer library paths.
- Do not stage, commit, push, or rewrite Git history.

## Corrected Decisions (approved by Daniel)

1. **Routing/shell:** Slice 002 migrates the ready shell/routing composition
   to the stateful branch model required by SPEC-FE-004. Sources, Jobs, and
   Settings have independent branch history: switching to an inactive
   destination restores that branch's prior location; reselecting the active
   destination returns that branch to its canonical root. Placement: Compact
   = Jobs direct + More (Sources/Settings); Medium = Jobs rail, Sources
   rail/secondary, Settings secondary; Expanded/Large = governed sidebar
   groupings. Routing tests cover independent branch history, destination
   switching, active-destination reselection, and route-to-destination
   mapping.
2. **SourceEntriesChanged:** the backend emits it after committed
   source-entry checkpoints (event contract), but Slice 002 has no Flutter
   hierarchy consumer. It is NOT mapped to root-list/root-detail
   reconciliation; root projection changes reconcile from
   `LibraryRootChanged`/`LibraryRootsChanged`. No high-frequency root reads
   are introduced because source-entry checkpoints changed.
3. **Provider root enumeration:** the application-owned `LibrarySourceAccess`
   contract exposes `resolve_root()` producing a transient opaque
   `ResolvedRoot` (root namespace), then direct-child enumeration within that
   resolved namespace. No synthetic root-sentinel `RelativeSourceLocator` is
   exposed; `RelativeSourceLocator` remains an opaque locator for entries
   beneath the root. Infrastructure may use private representations.
4. **Non-governed mechanics are internal policy, not contracts:**
   `ProviderNativeIdentity` is implemented only where the existing toolchain
   provides clean continuity guarantees (Unix dev+inode via std metadata;
   omitted elsewhere). Manager internals (pending bound, resource
   capacities, checkpoint size, drain deadline, worker strategy) are
   internal runtime policy behind a testable config seam, not public
   application/domain/bridge contracts.

## Task 1: Rust domain identities

**Files:**
- Create: `rust/crates/argus-domain/src/jobs.rs`
- Modify: `rust/crates/argus-domain/src/lib.rs`, `rust/crates/argus-domain/src/sources.rs`
- Test: `rust/crates/argus-domain/tests/jobs.rs`, `rust/crates/argus-domain/tests/sources.rs`

**Interfaces:**
- Consumes: existing `LibraryRootId` pattern (16-byte hex, non-zero).
- Produces: `JobRunId`, `ScanRunId`, `SourceEntryId` with `from_bytes`,
  `as_bytes`, `TryFrom<&str>`, `Display`, `Error` types; re-exported from
  `argus-domain::lib` and later `argus-application`.

- [ ] TDD: write identity tests (valid/invalid length, non-zero, hex case,
      round-trip), run to verify failure, implement `jobs.rs` +
      `SourceEntryId`, run to verify pass.

## Task 2: Rust application contracts

**Files:**
- Create: `rust/crates/argus-application/src/jobs.rs`,
  `rust/crates/argus-application/src/sources/scan.rs`
- Modify: `rust/crates/argus-application/src/lib.rs`, `errors.rs`,
  `events.rs`, `sources/mod.rs`, `sources/library.rs`, `sources/provider.rs`,
  `unit_of_work.rs`
- Test: `rust/crates/argus-application/tests/jobs.rs`,
  `rust/crates/argus-application/tests/slice_002_contract.rs`

**Interfaces:**
- Produces: `JobRunState`, `JobProgress`, `JobRunProjection`, `JobSummary`,
  `JobDetail`, `OperationDetail`, `LibraryScanJobDetail`, `OperationHandle`,
  `JobControlAvailability`, `JobsService` (`get_job`, `list_jobs`,
  `cancel_job`), `CancelJobResult`, `StartLibraryScanResult`,
  `RemoveLibraryRootResult::RootHasActiveScan`, `SourceEntriesChangeScope`,
  `SourceEntriesChanged`, `JobStateChanged`, `JobProgressChanged`,
  `JobsSubscriber`, `SourceEntriesSubscriber`, `LibrarySourceAccess`
  (`resolve_root` -> `ResolvedRoot`; `enumerate_root_direct_children`;
  `enumerate_direct_children(&ResolvedRoot, &RelativeSourceLocator)`),
  `SourceObservation`, `ObservedEntryKind`, `EnumerationOutcome`,
  `SourceAccessError`, `LibraryScanOperationHandler`, repositories/queries
  ports (`JobRunRepository`, `ScanRunRepository`, `SourceEntryRepository`,
  `LibraryScanTargetRepository`, `JobsQueries`), UnitOfWork accessors
  (`job_runs()`, `scan_runs()`, `source_entries()`,
  `library_scan_targets()`).

- [ ] TDD: generic job/scan models, progress invariants, typed admission and
      removal outcomes, error codes `ARGUS.V1.JOBS.JOB_RUN_NOT_FOUND` and
      `ARGUS.V1.OPERATION.CAPACITY_UNAVAILABLE` in `phase_001_all()`
      (keeping `all()` at 9), event variants/subscribers, provider port
      shape, handler behavior with fakes (traversal, checkpoints,
      terminalization mapping, cancellation), and slice-002 catalog tests.

## Task 3: Rust infrastructure

**Files:**
- Create: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`,
  `rust/crates/argus-infrastructure/src/sqlite/sources_scan.rs`,
  `rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0003_jobs_scans.sql`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/mod.rs`,
  `unit_of_work.rs`, `sources.rs`, `migrations/mod.rs`,
  `local_filesystem/mod.rs`
- Test: `rust/crates/argus-infrastructure/tests/jobs.rs`,
  `rust/crates/argus-infrastructure/tests/local_filesystem_scan.rs`

**Interfaces:**
- Produces: migration `0003_jobs_scans.sql` (job_run, scan_run,
  library_scan_target, source_entry + indexes + partial unique active-root
  index), `SqliteJobsQueries`, `SqliteJobRunRepository`,
  `SqliteScanRunRepository`, `SqliteSourceEntryRepository`,
  `SqliteLibraryScanTargetRepository`, root query joins for
  active/last scan, root-removal cascade of current source entries only,
  `LocalFilesystemSourceAccess` implementing the application port.

- [ ] TDD: migration upgrade path (Phase 000 -> Phase 001) and restart
      survival; repository CRUD/query behavior; temporary-tree provider tests
      (direct-child enumeration, nested traversal ownership, link-like
      no-follow, namespace escape rejection, locator-key stability, error
      translation, user-file immutability).

## Task 4: Rust runtime and bridge

**Files:**
- Create: `rust/crates/argus-runtime/src/background.rs`
- Modify: `rust/crates/argus-runtime/src/operations.rs`, `runtime.rs`,
  `startup.rs`, `events.rs`, `lib.rs`; `rust/crates/argus-bridge/src/lib.rs`
- Test: `rust/crates/argus-runtime/tests/background_operations.rs`,
  `rust/crates/argus-runtime/tests/sources.rs`, `rust/crates/argus-bridge/tests/jobs.rs`

**Interfaces:**
- Produces: `OperationClass::BackgroundOperation`, `ResourceClass`,
  `OperationPolicy`, `BackgroundManagerConfig` (internal policy seam),
  `BackgroundOperationManager` (register/admit, resource acquisition/release,
  lifecycle transitions, cancellation, shutdown, registration-failure
  terminalization, post-commit events), `ApplicationRuntime`-owned manager,
  runtime event payloads `JobStateChanged`/`JobProgress`/
  `SourceEntriesChanged`, `ApplicationHost::start_library_scan/list_jobs/
  get_job/cancel_job`, bridge DTOs (`OperationHandleDto`, `JobRunDto`,
  `JobSummaryDto`, `JobDetailDto`, `OperationDetailDto`,
  `LibraryScanJobDetailDto`, `ScanRunDto`, `ListJobsRequestDto`,
  `JobSummaryPageDto`, `StartLibraryScanResultDto`, `CancelJobResultDto`,
  `RemoveLibraryRootResultDto::RootHasActiveScan`, event payload variants),
  and FRB regeneration.

- [ ] TDD: manager tests (durable handoff, one-active-scan-per-root,
      resource wait/release, legal/illegal transitions, progress validation,
      cancellation queued/running, shutdown coordination, event-after-commit,
      no second database authority); runtime host tests; bridge mapping
      tests; run `just generate` + `just check-generated` with zero drift.

## Task 5: Flutter client and Jobs feature

**Files:**
- Create: `flutter/lib/features/jobs/**` (composition, state, controllers,
  event coordinator, presentation), jobs route/shell updates
- Modify: `flutter/lib/core/client/src/models.dart`, `ports.dart`,
  `argus_client.dart`; `flutter/lib/core/bridge/src/frb_argus_client_gateway.dart`;
  `flutter/lib/app/routing/app_routes.dart`, `app_destination.dart`;
  `flutter/lib/app/shell/application_shell.dart`;
  `flutter/lib/app/bootstrap/app_bootstrap.dart`;
  `flutter/lib/features/sources/**`; justfile generated-file registration
- Test: `flutter/test/core/client/jobs_client_test.dart`,
  `flutter/test/features/jobs/**`, `flutter/test/app/routing/app_router_test.dart`,
  `flutter/test/app/shell/application_shell_test.dart`,
  `flutter/test/features/sources/**`

**Interfaces:**
- Produces: client models (`JobRunId`, `ScanRunId`, `OperationHandle`,
  `JobLifecycleState`, `JobListItem`, `JobDetail`, `OperationDetail`,
  `LibraryScanJobDetail`, `ScanRunSummary`, `JobControlAvailability`,
  `ActiveJobSummary`, `StartLibraryScanResult`, `CancelJobResult`,
  `RemoveLibraryRootResult.rootHasActiveScan`, event payload variants),
  `JobsGateway`/`JobsApi`, `SourcesApi.startLibraryScan`,
  `JobsEventCoordinator`, `JobsListController`, `JobDetailController`,
  `ActiveJobSummaryController`, `/jobs` + `/jobs/:jobRunId` routes, stateful
  branch shell (independent Sources/Jobs/Settings branch history), shell
  active-job indicator, root detail scan/last-scan/active-scan presentation,
  RootHasActiveScan removal handling.

- [ ] TDD: mapper/client tests; Jobs controller/widget tests (active/recent,
      empty, pagination, detail, cancellation/reconciliation, zero/one/
      multiple indicator, adaptive layouts, accessibility); routing tests
      (branch history, switching, reselection, route-to-destination);
      Sources scan/status tests; `SourceEntriesChanged` mapped but NOT
      wired to any reconciliation demand.

## Task 6: Architecture, generation, and completion gates

**Files:**
- Modify: `flutter/test/architecture/architecture_boundaries_test.dart`,
  docs per AGENTS.md

- [ ] Architecture-boundary tests updated (Jobs activated; future prohibitions
      removed; feature guards added).
- [ ] `just generate` then `just check-generated` pass with zero drift.
- [ ] `just check` passes (format, lint/analyze, shellcheck, Rust dependency
      architecture, Rust and Flutter suites).
- [ ] `git diff --check` clean; no change outside the authorization boundary.
- [ ] Write `RESULT.json` per the completion contract with truthful evidence;
      then provide the user-facing completion response.

## Test Plan (maps to TACs)

- Backend (TAC-22): durable admission handoff and orphan-prevention,
  one-active-scan-per-root, resource wait/release, legal/illegal lifecycle
  transitions, progress <= committed work, cancellation while queued/running,
  shutdown drain, event-after-commit ordering, no second database authority.
- Provider/indexing (TAC-23): temporary trees for direct-child enumeration,
  nested traversal ownership, link-like no-follow, namespace escape
  rejection, positive checkpoint persistence, cancellation retaining
  committed observations, partial/unavailable/failure mapping, user-file
  immutability, locator-key stability, native-identity rules.
- Bridge/client/controllers/widgets (TAC-24): typed admission +
  `AlreadyScanning`, Jobs active/recent/detail mapping, shell indicator
  zero/one/multiple, Scan/View-Job root states, cancellation + authoritative
  reconciliation, event-gap refresh, routes/adaptive layouts,
  accessibility/focus, Light/Dark/System.
- Gates (TAC-25): `just generate`/`check-generated` zero drift, `just check`
  all green, prior Phase 000/Slice 001 suites remain green; report any
  environment blocker truthfully.
- Scope (TAC-26): no files outside the authorization boundary; no Slice 003+
  behavior beyond additive schema/contracts required for forward
  compatibility.

## Assumptions and Defaults

- Manager policy defaults are internal runtime policy behind
  `BackgroundManagerConfig`: pending bound 16, FilesystemRead=1,
  PersistenceWrite=1, worker strategy = one spawned thread per admitted run,
  shutdown drain <=5s, checkpoint every 100 observations or per completed
  scope; tests use small bounded values through the config seam.
- No `RetryJob`/`ResumeJob` anywhere in this slice; `canRetry` is always
  false.
- Terminal-first-scan root detail shows the last-scan summary and no scan
  control.
- `GetActiveJobSummary` reuses `ListJobs(Active)`; no new backend shell
  authority.
- One migration (`0003_jobs_scans.sql`) covers all new tables; existing
  `all()` error-catalog shape stays stable; new codes go through
  `phase_001_all()`.
- Startup reconciliation of stale active jobs stays deferred (Slice 006);
  terminal history naturally survives restart (TAC-13).
- Serena MCP tools are not exposed in this session; `.serena/project.yml`
  (read-write, project Argus-ROM-Toolkit) was used as activation context and
  no Serena Instructions Manual file exists in the repo.
