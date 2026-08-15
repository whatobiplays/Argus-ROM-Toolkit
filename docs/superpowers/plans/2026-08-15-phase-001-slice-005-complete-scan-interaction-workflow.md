# SLICE-P01-005 — Complete Scan Interaction Workflow

Run: `2026-08-15T133133Z-phase-001-slice-005-complete-scan-interaction-workflow`

## 1. Outcome

Users can Add & Scan or Add Without Scanning, Scan / Scan Again an eligible
root, observe trustworthy structured scan detail/progress, cancel through
backend-authoritative controls, retry eligible historical attempts into a new
durable execution, and reconcile every outcome through authoritative queries
without duplicate frontend authority or duplicate mutations after ambiguous
transport. Sources stays concise/root-local; Jobs owns full execution history
and controls.

## 2. Binding contracts

- SPEC-BE-013 (Add & Scan, retry, detail projections, progress, retry links)
- SPEC-BE-004 / SPEC-BE-009 (background operation and application service
  ownership, coherent admission durability)
- SPEC-BE-008 (bridge DTO/API rules) and SPEC-X-001 (additive compatibility)
- SPEC-FE-008 (Sources: confirmation, Add & Scan, ambiguity reconciliation,
  Scan/Scan Again, View Job)
- SPEC-FE-009 (Jobs: detail, progress, controls, retry, ambiguity, lifetime)
- Slice 002-004 implemented behavior must remain green; the user-owned
  `.serena/project.yml` worktree modification is preserved exactly.

## 3. Corrections applied to the plan

1. **Application-owned Add & Scan.** `AddLocalLibraryRootAndScan` is a
   `LibraryService` application workflow. A new application handler commits the
   root through the existing `AddLocalLibraryRootHandler`, then requests child
   admission through a narrow runtime-supplied `LibraryScanChildAdmission`
   capability (durable admission + manager registration), then assembles the
   typed committed result. `ArgusRuntime`/`BackgroundOperationManager` keeps
   runtime registration/scheduling ownership; the runtime does not manually
   sequence an independent Add followed by StartLibraryScan.
2. **Ambiguous Add & Scan reconciliation.** Never infer admission from
   `lastScan`. Replay only the exact idempotent `AddLocalLibraryRoot` to
   establish root identity, then reconcile root authority
   (`getLibraryRoot`) and Jobs authority (new focused
   `getRootScanAdmission(rootId)` query returning any active/terminal
   scan-run admission for that root). Explicit `startLibraryScan` is issued
   only when both reads prove no child admission exists; otherwise the flow
   stays synchronization-uncertain with conflicting mutation disabled. The
   `addedWithHistoricalScan` state is removed.
3. **Shared retry eligibility.** One application seam
   (`evaluate_retry_eligibility`) computes `canRetry` and Retry admission
   exclusions from the same per-target facts: configured, current
   configuration valid, no active owner. The Jobs projection and the Retry
   admission handler both consume it, so semantics cannot drift.
4. **Generic `JobRun` stays generic.** No `invocation_kind` /
   `retry_source_job_run_id` on `NewJobRun`. Immutable LibraryScan admission
   context is persisted in a new `library_scan_admission_context` table
   (`job_run_id`, `invocation_kind`, `retry_source_job_run_id`). The
   invocation vocabulary is operation-specific and distinguishes
   `initial_single_root` / `retry_single_root` (Slice 006 extends it for Scan
   All). The source run's direct successor is stored separately in
   `job_retry_link` with foreign keys on both source and successor
   `job_run_id`s plus source-PK / successor-UNIQUE one-successor and
   one-predecessor integrity.
5. **Jobs provider lifetime.** `JobDetailController(jobRunId)` is
   auto-disposed/recreatable (drop `keepAlive`). `JobsListController` also
   drops `keepAlive`: no FE-009-approved consumer outside the Jobs branch
   depends on it, and route identity owns branch restoration. The shell
   consumes only `ActiveJobSummaryController`, which remains keepAlive.
6. **Retry registration failure.** If application Retry admission durably
   created the new JobRun/ScanRun and manager registration subsequently fails,
   the new execution identity is preserved and terminalized coherently
   (existing `fail_unregistered_scan` path), and the operation returns a
   definite application error — never `NotAdmitted`, which would falsely imply
   no new execution. Focused runtime/client tests cover this boundary.
7. **Migration verification.** In addition to fresh/full-chain coverage, an
   upgrade test applies the new migration to a representative Slice 004
   (0005-schema) database containing existing JobRun/ScanRun/target rows and
   proves defaults, nullability, retry metadata integrity, FK enforcement, and
   preservation of existing history.

## 4. Implementation changes

### 4.1 argus-application

- `sources/library.rs`: `AddLocalLibraryRootAndScanCommand`,
  `AddLocalLibraryRootAndScanResult`, `LibraryScanChildAdmissionIssue`,
  `LibraryScanChildAdmission` trait, `AddLocalLibraryRootAndScanHandler`, and
  `LibraryService::add_local_library_root_and_scan` (root commit via the
  existing add handler, then child admission through the supplied capability,
  then typed result assembly; duplicate/overlap remain non-mutating).
- `jobs.rs`:
  - `JobControlAvailability::new(can_cancel, can_retry)`.
  - `ScanProgressFacts`: `entries_committed` becomes `Option<u64>`, add
    `entries_observed: Option<u64>` and `issue_count: Option<u64>`.
  - `LibraryScanInvocationKind` (`InitialSingleRoot`, `RetrySingleRoot`) and
    `LibraryScanAdmissionContext` (job, invocation kind, optional retry
    source) with a transaction-scoped repository port
    (`insert`, `get_by_job`).
  - `RetryJobResult` (`Admitted`, `AlreadyRetried`, `NotAdmitted`),
    `RetryNotAdmittedReason` (`SourceRunNotTerminal`, `OperationNotRetryable`,
    `NoEligibleTargets(exclusions)`), `RetryJobAdmissionResult` carrying the
    `AdmittedScan` payload for runtime registration.
  - Shared `LibraryScanTargetEligibility` (configured, configuration_valid,
    active_owner) and `evaluate_retry_eligibility` returning
    `can_retry` plus typed exclusions; used by both projection and admission.
  - `RetryJobHandler` check order: job exists -> successor exists
    (`AlreadyRetried`) -> operation is `library_scan` -> source state
    (`SourceRunNotTerminal` / `OperationNotRetryable` / eligible) ->
    revalidate requested targets inside one UoW -> `NoEligibleTargets` with no
    job, or admit new JobRun + admission context (RetrySingleRoot,
    retry_source) + ScanRun + requested/admitted/excluded targets +
    `insert_retry_link(source, new)`; events for new job, source job, and each
    admitted root.
  - `JobsService::retry_job` and `JobsService::get_root_scan_admission`.
  - Port additions: `JobRunRepository::insert_retry_link`,
    `ScanRunRepository::set_progress_facts`, `JobsQueries::find_retry_successor`,
    `JobsQueries::list_requested_library_scan_targets`,
    `JobsQueries::find_scan_admission_for_root`.
- `sources/scan.rs`: track observed/committed/issue counters and persist them
  through `set_progress_facts` at checkpoints and terminalization.

### 4.2 argus-infrastructure

- Migration `0006_retry_and_progress.sql` (registered in `migrations/mod.rs`):
  - `library_scan_admission_context(job_run_id PK -> job_run,
    invocation_kind CHECK('initial_single_root','retry_single_root'),
    retry_source_job_run_id -> job_run)`, backfilled for existing
    `library_scan` jobs as `initial_single_root`.
  - `job_retry_link(source_job_run_id PK -> job_run,
    successor_job_run_id NOT NULL UNIQUE -> job_run)`.
  - Nullable `scan_run.entries_observed / entries_committed / issue_count`.
  - Supporting partial index on admission-context retry source.
- Repositories: SQLite implementations for the new ports; `read_job_detail`
  loads admission context + successor + per-target eligibility and computes
  controls through the shared application eligibility seam; scan-run progress
  counters aggregate into `ScanProgressFacts` (null when any contributing
  scan run is unknown); `find_scan_admission_for_root` returns the newest
  scan-run admission (active or terminal) for a root.
- Unit-of-work scope exposes the admission-context repository.

### 4.3 argus-runtime

- Extract the admission+registration block from `start_library_scan_with_context`
  into a shared registration helper (provider access, handler construction,
  `manager.register`, `fail_unregistered_scan` on failure).
- Kernel implements `LibraryScanChildAdmission` (durable admission +
  registration) so the application composite can consume it without the
  runtime sequencing add-then-scan.
- `ArgusRuntime::add_local_library_root_and_scan(selection)` acquires the
  operation ticket, invokes the application composite with the kernel
  capability, and publishes collected events.
- `ArgusRuntime::retry_job(job_run_id)` invokes `JobsService::retry_job` and
  registers the admitted payload; registration failure preserves the new
  identity, terminalizes coherently, and returns an application error.

### 4.4 Bridge/FRB and Dart client

- FRB functions `add_local_library_root_and_scan`, `retry_job`,
  `get_root_scan_admission`.
- DTOs: `AddLocalLibraryRootAndScanResultDto` (4 variants),
  `LibraryScanChildAdmissionIssueDto`,
  `LibraryRootScanAdmissionReferenceDto`,
  `RetryJobResultDto`, `RetryNotAdmittedReasonDto`; `ScanProgressFactsDto`
  gains nullable `entries_observed`, `entries_committed`, `issue_count`.
- Pure-Dart `models.dart`/`ports.dart`/`argus_client.dart`/gateway: matching
  models and methods; invalid required identities remain
  `contractMismatch` failures.

### 4.5 Flutter Sources

- Confirmation dialog: primary **Add & Scan**, secondary **Add Without
  Scanning**; controller gains `addAndScan` with states for admitted, split
  outcomes, and sync-uncertain ambiguity; ambiguity path replays idempotent
  Add, queries root + `getRootScanAdmission`, and issues explicit scan only
  when no admission is proven.
- Root detail: Scan (never scanned) / Scan Again (terminal history), no
  lastScan-based blocking; AlreadyScanning remains an expected race; View Job
  from active scan and from lastScan.

### 4.6 Flutter Jobs

- `JobDetailController`: `retrying`/`retryAmbiguous` state and `retry`
  mutation (one unresolved control per job); Admitted/AlreadyRetried
  navigate; NotAdmitted refreshes and presents typed reasons; transport
  ambiguity keeps confirmed detail, marks sync-uncertain, refreshes, and
  navigates only when `retrySuccessorJobRunId` is established.
- Detail page: Retry only when `canRetry` with confirmation; Cancel only when
  `canCancel`; CancellationRequested stays pending; no Resume; factual
  nullable progress without percentages; CompletedWithIssues distinct;
  per-root outcomes from durable snapshots; Retried from/Retried as links.
- Lifetime: `JobDetailController` and `JobsListController` auto-dispose;
  `ActiveJobSummaryController` remains keepAlive.

## 5. Test plan (TDD)

- Application: Add & Scan all outcomes incl. admission failure preserving the
  committed root and no orphan state; retry success / AlreadyRetried /
  SourceRunNotTerminal / OperationNotRetryable / NoEligibleTargets /
  linear-chain continuation / no broadening; shared eligibility parity
  between projection and admission; nullable progress facts.
- Infrastructure: fresh and 0005->0006 upgrade migrations with representative
  data; retry-link FK + one-successor/one-predecessor integrity; admission
  context defaults; scan-run counters; detail assembly (retry fields,
  canRetry, nullable progress); root scan-admission lookup.
- Runtime: Add & Scan registration failure -> AddedButScanNotAdmitted with
  terminalized scan; retry registration failure -> preserved identity,
  terminalized coherently, application error (never NotAdmitted).
- Bridge/client: DTO mapping, null counters preserved, contract mismatch on
  invalid required representation.
- Flutter controller/widget: Add & Scan split/ambiguity; Scan Again +
  AlreadyScanning; progress nullability + CompletedWithIssues; cancel races;
  retry all outcomes + ambiguity; event-gap/runtime replacement; stale-async
  rejection; provider disposal; responsive/keyboard/focus/accessibility.
- Verification: `just generate`, `just check-generated`, fresh `just check`.

## 6. Guardrails

- No Slice 006 (Scan All, cancel-and-remove, restart recovery), no Resume, no
  discovery/reconciliation/policy changes, no governed-doc edits, no
  `argus-domain` changes, no `.serena/**` changes, no staging/commit/push.
- `RESULT.json` (schema_version 3) is the only `.chatgpt/**` write and reports
  every TAC-1..18 exactly once with concrete evidence.
