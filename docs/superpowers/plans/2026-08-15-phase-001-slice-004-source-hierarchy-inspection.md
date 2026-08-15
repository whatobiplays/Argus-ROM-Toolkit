# Phase 001 Slice 004 — Sources Hierarchy Inspection Implementation Plan (Revised)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose the Slice 003 authoritative `SourceEntry` graph through safe bounded row/detail queries and opaque cursor-paged children, carry them through runtime/FRB/pure-Dart `SourcesApi`, deliver exact source-entry invalidations to Dart, and add a query-authoritative `SourceHierarchyController(rootId)` with responsive drill-down/tree root-detail browsing.

**Architecture:** Rust/SQLite remains source-graph authority. Application reads sit behind a new read-only `SourceEntryQueries` port, separate from the transaction-scoped reconciliation repository. SQLite implements deterministic keyset paging behind an additive index. The bridge validates external input at its boundary and exposes focused DTOs; Flutter consumes typed models only through `SourcesApi`, and one `SourceHierarchyController(rootId)` owns bounded per-parent page caches plus transient expansion/selection/drill-down state. Events remain invalidation hints that drive authoritative re-query; runtime replacement reconciliation is owned by the hierarchy controller through the existing `sourcesRuntimeContextProvider` seam.

**Tech Stack:** Rust (argus-application, argus-infrastructure, argus-runtime, argus-bridge), SQLite/rusqlite, flutter_rust_bridge 2.12 codegen, Dart/Riverpod 3 + Freezed, `just check`.

## 1. Global Constraints

1. SLICE-P01-004 only: no Slice 005+ scan workflow, no new hierarchy route, no durable hierarchy preference, no provider/reconciliation/identity changes, no governed doc edits.
2. Rust/SQLite remains authority; Flutter holds only bounded confirmed-page and transient interaction state; events never mutate the graph.
3. **Safe projection vocabulary:** row/detail projections expose only id, parent id, display name, display location, kind, classification. `last_observed_scan_id` is provenance/identity and is never relabeled as user-facing status, never carried into projections, DTOs, Dart models, or UI. No status vocabulary is invented. The BE-008 reserved status fields remain on the bridge DTOs as `Option` values mapped to `None` (intentionally absent until authoritative status facts exist); they are never populated from provenance.
4. **Cursor trust boundary:** Flutter treats the cursor as an opaque string. The bridge/application boundary parses and validates an externally supplied cursor into a validated application-owned `SourceEntryCursor`; malformed external cursor text maps to `ValidationInvalidArgument`, never `PersistenceError::Internal`. `SourceEntryQueries` receives only the validated cursor value; persistence reads its structured keys and never reinterprets an untrusted string. Persistence corruption remains a persistence failure. Cursor encoding is implementation-private and is not a public plan-level invariant.
5. Page size backend-bounded (1–200, default 100); order `created_at ASC, source_entry_id ASC` (Unix **seconds** in `source_entry.created_at`, per `migrations::timestamp()`), backend-owned, with the unique-id tie breaker.
6. Per-parent scope owns independent load/page/refresh/error state; refresh preserves confirmed content, restarts at page one, and replaces the cursor chain only on success.
7. **No partial-page absence authority:** absence from currently loaded pages never proves deletion. Transient identities are pruned only when authoritative evidence (focused `getSourceEntry` not-found, or a provably complete parent scope — no such completeness marker exists in Slice 004) proves removal. Stable identities survive refresh/move even when their new location is not loaded; Flutter never fabricates parentage/ancestry.
8. Fixed Phase 001 semantics: only `Directory`/`Container` traversable; `File`/`Unknown`, `LinkLike`/`Ignored`, `Unknown`/`Ignored` visible non-traversable evidence. No filename/extension/hidden/system inference.
9. Compact and Medium use drill-down; Expanded/Large use an incremental tree; one shared controller/state model; selection is never route state.
10. TDD throughout. Do **not** stage, commit, push, or rewrite Git history (delegation contract overrides the usual per-task commit step).

---

### Task 1: Rust application hierarchy query boundary

**Files:**
- Create: `rust/crates/argus-application/src/sources/hierarchy.rs`
- Modify: `rust/crates/argus-application/src/sources/mod.rs`
- Modify: `rust/crates/argus-application/src/sources/library.rs` (`LibraryService` gains a queries capability)
- Modify: `rust/crates/argus-application/src/errors.rs` (new error code)
- Modify: `rust/crates/argus-application/tests/contracts.rs` (catalog snapshot)
- Modify: `rust/crates/argus-application/tests/sources.rs` (all 8 `LibraryService::new` call sites gain the new queries argument; add a shared `FakeSourceEntryQueries` helper in `tests/common/mod.rs`)
- Create: `rust/crates/argus-application/tests/slice_004_hierarchy.rs`

**Interfaces:**
- Consumes: `SourceEntryId`, `LibraryRootId`, `SourceEntryKind`, `SourceEntryClassification` (already exported by `argus-application`), `OperationContext`, `PersistenceError`, `ApplicationError`.
- Produces (exact, used by Tasks 2–4):

```rust
/// Safe row projection. Contains NO provenance, persistence, or provider facts.
pub struct SourceEntryProjection {
    source_entry_id: SourceEntryId,
    parent_source_entry_id: Option<SourceEntryId>,
    display_name: String,
    display_location: String,
    kind: SourceEntryKind,
    classification: SourceEntryClassification,
}

/// Safe detail projection. Structurally identical safe facts for now; kept as
/// a distinct type to preserve the BE-008 row/detail split. No status field:
/// current authoritative data has no user-meaningful status fact, so the
/// reserved DTO status fields map to `None` at the bridge (Task 4).
pub struct SourceEntryDetailProjection {
    source_entry_id: SourceEntryId,
    parent_source_entry_id: Option<SourceEntryId>,
    display_name: String,
    display_location: String,
    kind: SourceEntryKind,
    classification: SourceEntryClassification,
}

/// Validated, application-owned cursor. Parsing of untrusted external text
/// happens ONLY here (via TryFrom<&str>) or at the bridge boundary.
/// Encoding is implementation-private; the plan does not fix its text form.
pub struct SourceEntryCursor {
    created_at_seconds: i64,      // source_entry.created_at (Unix seconds)
    source_entry_id: SourceEntryId,
}
impl SourceEntryCursor {
    /// Backend-owned constructor for persistence-generated paging keys.
    /// The structured cursor remains application-owned backend state; its
    /// textual encoding stays opaque/implementation-private to Flutter and
    /// ordinary callers. Dart never sees parsing or key semantics.
    pub fn from_paging_keys(created_at_seconds: i64, source_entry_id: SourceEntryId) -> Self;
    pub fn created_at_seconds(&self) -> i64;
    pub fn source_entry_id(&self) -> SourceEntryId;
}
impl TryFrom<&str> for SourceEntryCursor { /* versioned parse; Err -> SourceEntryCursorError */ }
impl fmt::Display for SourceEntryCursor { /* private wire encoding */ }

pub struct SourceEntryChildrenPage {
    items: Vec<SourceEntryProjection>,
    next_cursor: Option<SourceEntryCursor>,
}

pub struct ListSourceEntryChildrenQuery {
    library_root_id: LibraryRootId,
    parent_source_entry_id: Option<SourceEntryId>,
    cursor: Option<SourceEntryCursor>, // always validated before construction
    page_size: u32,                    // clamped 1..=200, default 100
}

pub struct GetSourceEntryQuery { source_entry_id: SourceEntryId }

pub trait SourceEntryQueries {
    fn list_children(
        &self,
        context: &OperationContext,
        query: &ListSourceEntryChildrenQuery,
    ) -> Result<SourceEntryChildrenPage, PersistenceError>;
    fn get(
        &self,
        context: &OperationContext,
        source_entry_id: SourceEntryId,
    ) -> Result<Option<SourceEntryDetailProjection>, PersistenceError>;
}
impl<Q> SourceEntryQueries for &Q where Q: SourceEntryQueries { /* delegate */ }
```

1. `ListSourceEntryChildrenQuery::new(root_id, parent, cursor, page_size)` clamps with `page_size.clamp(1, 200)`; exposes `DEFAULT_PAGE_SIZE = 100`, `MAX_PAGE_SIZE = 200`. Callers that hold raw strings must convert via `SourceEntryCursor::try_from` first; the query type cannot be constructed with an unvalidated string.
2. `ListSourceEntryChildrenHandler<Q>` and `GetSourceEntryHandler<Q>` wrap the trait; missing detail maps to a new `ConfigurationSourceEntryNotFound` error code (`ARGUS.V1.CONFIGURATION.SOURCE_ENTRY_NOT_FOUND`, policy `Configuration/Error/UserAction/Never`, message key `errors.configuration.source_entry_not_found`), appended to `phase_001_all` (22 → 23) with the `contracts.rs` snapshot updated.
3. `LibraryService<Q, S, U, P>` gains `source_entry_queries: S` and methods `list_source_entry_children(...)` / `get_source_entry(...)`; `new(queries, source_entry_queries, unit_of_work, provider)`. Update **all** 11 construction sites: `argus-runtime/src/lib.rs` (2), `argus-runtime/src/startup.rs` (1), `argus-application/tests/sources.rs` (8, using `FakeSourceEntryQueries::default()`).

**Steps (TDD):**
- [ ] Step 1: In `slice_004_hierarchy.rs`, write tests: cursor round trip via `TryFrom<&str>`/`Display`; malformed cursor strings fail with `SourceEntryCursorError` (and, at bridge level in Task 4, `ValidationInvalidArgument`); page-size clamp at 0→1 and 999→200; `GetSourceEntryHandler` maps `None` to `ConfigurationSourceEntryNotFound`; `ListSourceEntryChildrenHandler` delegates and maps persistence errors. Add a compile-time assertion that `SourceEntryProjection`/`SourceEntryDetailProjection` have no provenance/status fields (field-level assertions on construction/accessors). Update `contracts.rs` snapshot for the new catalog entry.
- [ ] Step 2: Run `bash scripts/run_rust.sh cargo test --manifest-path rust/Cargo.toml -p argus-application --all-features --locked` — expect compile/test failure (missing module/types).
- [ ] Step 3: Implement `hierarchy.rs`, extend `sources/mod.rs` re-exports, extend `LibraryService`, add the error-code entry, update `contracts.rs`, and update the 8 application-test construction sites with `FakeSourceEntryQueries`.
- [ ] Step 4: Re-run the application tests — all pass.

---

### Task 2: SQLite keyset paging adapter and additive index

**Files:**
- Create: `rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0005_source_hierarchy.sql`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/migrations/mod.rs` (register version 5)
- Create: `rust/crates/argus-infrastructure/src/sqlite/source_entries.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/mod.rs` (re-export `SqliteSourceEntryQueries`)
- Create: `rust/crates/argus-infrastructure/tests/source_hierarchy.rs`

**Interfaces:**
- Consumes: `SourceEntryQueries` trait and types from Task 1, `SqliteDatabaseExecutor`, `map_executor_error`.
- Produces:

```rust
#[derive(Clone)]
pub struct SqliteSourceEntryQueries { executor: SqliteDatabaseExecutor }
impl SqliteSourceEntryQueries { pub const fn new(executor: SqliteDatabaseExecutor) -> Self; }
impl SourceEntryQueries for SqliteSourceEntryQueries { /* list_children + get */ }
```

Migration SQL (exact):

```sql
-- Slice 004: bounded keyset paging for hierarchy inspection.
CREATE INDEX idx_source_entry_root_parent_created_id
    ON source_entry(library_root_id, parent_source_entry_id, created_at, source_entry_id);
```

`list_children` SQL (exact; `created_at` is selected only as the internal cursor key and is never projected out):

```sql
SELECT source_entry_id, parent_source_entry_id, display_name, display_location,
       kind, classification, created_at
FROM source_entry
WHERE library_root_id = ?1 AND parent_source_entry_id IS ?2
  AND (?3 IS NULL OR (created_at, source_entry_id) > (?3, ?4))
ORDER BY created_at ASC, source_entry_id ASC
LIMIT ?5
```

1. The `?3/?4` pair comes **only** from `cursor.created_at_seconds()` / `cursor.source_entry_id()` getters on the already-validated `SourceEntryCursor`; this adapter never receives or parses an external string. Malformed user cursor text cannot reach this layer.
2. Query `page_size + 1`; if more rows arrive than `page_size`, build `SourceEntryCursor::from_paging_keys(created_at, source_entry_id)` for the last returned row and set `next_cursor`; otherwise `None`.
3. `get` SQL: `SELECT source_entry_id, parent_source_entry_id, display_name, display_location, kind, classification FROM source_entry WHERE source_entry_id = ?1`; missing → `None`.
4. Mapping: parse `kind`/`classification` via existing `as_str()` round-trip; an unknown stored value or unparseable stored id is `PersistenceError::CorruptOrIncompatible` (persistence corruption), which is distinct from user-supplied malformed cursor text.
5. The public hierarchy query remains fully separate from Slice 003's transaction-scoped `SourceEntryRepository::list_children` (offset-based reconciliation support); `SqliteSourceEntryQueries` is a read adapter over `SqliteDatabaseExecutor`, not a transaction-scoped repository.

**Steps (TDD):**
- [ ] Step 1: Write `tests/source_hierarchy.rs` with a real SQLite fixture (mirror `tests/reconciliation.rs`): insert root A and root B entries directly; verify root-scope page 1 + continuation with deterministic `created_at, id` order; verify a parent scope pages independently; verify cursor continuation has no gaps/duplicates; verify `get` returns the safe detail and `None` for a missing id; verify the returned projections expose no `last_observed_scan_id`/locator/fingerprint fields (compile-time + value assertions); verify the migration applies fresh and upgrades a version-4 database (reuse existing migration-test helpers); verify `idx_source_entry_root_parent_created_id` exists.
- [ ] Step 2: Run infrastructure tests — fail (no module).
- [ ] Step 3: Implement migration registration + `source_entries.rs` + mod re-export.
- [ ] Step 4: Run infrastructure tests — pass.

---

### Task 3: Runtime host methods and service construction updates

**Files:**
- Modify: `rust/crates/argus-runtime/src/lib.rs` (imports, `KernelBootstrap` field type, `from_parts` signature, fixture constructor, two service construction sites, two new methods)
- Modify: `rust/crates/argus-runtime/src/startup.rs` (service construction)
- Modify: `rust/crates/argus-runtime/tests/source_reconciliation.rs` or new `tests/source_hierarchy.rs` (runtime-level coverage)

**Interfaces:**
- Consumes: Task 1 types, `SqliteSourceEntryQueries` from Task 2.
- Produces:

```rust
impl KernelBootstrap {
    pub fn list_source_entry_children_with_context(
        &self,
        query: &ListSourceEntryChildrenQuery,
        context: &OperationContext,
    ) -> Result<SourceEntryChildrenPage, ApplicationError>;

    pub fn get_source_entry_with_context(
        &self,
        source_entry_id: SourceEntryId,
        context: &OperationContext,
    ) -> Result<SourceEntryDetailProjection, ApplicationError>;
}
```

Update every `LibraryService::new(queries, unit_of_work, provider)` call to `LibraryService::new(queries, SqliteSourceEntryQueries::new(executor.clone()), unit_of_work, provider)` (3 production sites; the 8 application-test sites are handled in Task 1).

**Steps (TDD):**
- [ ] Step 1: Add a runtime test: boot a kernel with a scanned fixture, call `list_source_entry_children_with_context` for root scope, assert page-1 items and safe fields; call `get_source_entry_with_context` for a known id.
- [ ] Step 2: Run `cargo test -p argus-runtime` — fails to compile.
- [ ] Step 3: Implement the methods and constructor updates.
- [ ] Step 4: Run `cargo test -p argus-runtime` — pass.

---

### Task 4: Bridge DTOs, FRB functions, cursor validation boundary

**Files:**
- Modify: `rust/crates/argus-bridge/src/lib.rs`
- Create: `rust/crates/argus-bridge/tests/slice_004_hierarchy.rs`

**Interfaces:**
- Consumes: Task 1/3 application and runtime APIs.
- Produces (FRB-visible DTOs and functions):

```rust
pub enum SourceEntryKindDto { Directory, File, LinkLike, Unknown }
pub enum SourceEntryClassificationDto { Container, ContentCandidate, SupportingEntry, Ignored, Unknown }

pub struct SourceEntryDto {
    pub source_entry_id: String,
    pub parent_source_entry_id: Option<String>,
    pub display_name: String,
    pub display_location: String,
    pub kind: SourceEntryKindDto,
    pub classification: SourceEntryClassificationDto,
    /// Reserved BE-008 status field. Always None in Slice 004: no authoritative
    /// user-meaningful status fact exists yet. Never populated from provenance.
    pub bounded_status_summary: Option<String>,
}

pub struct SourceEntryDetailDto {
    pub source_entry_id: String,
    pub parent_source_entry_id: Option<String>,
    pub display_name: String,
    pub display_location: String,
    pub kind: SourceEntryKindDto,
    pub classification: SourceEntryClassificationDto,
    /// Reserved BE-008 status field. Always None in Slice 004.
    pub bounded_status_summary: Option<String>,
    /// Reserved BE-008 detail status field. Always None in Slice 004.
    pub bounded_observation_status_detail: Option<String>,
}

pub struct SourceEntryChildrenPageDto {
    pub items: Vec<SourceEntryDto>,
    pub next_cursor: Option<String>, // opaque wire token; Dart never parses it
}

pub struct ListSourceEntryChildrenRequestDto {
    pub library_root_id: String,
    pub parent_source_entry_id: Option<String>,
    pub cursor: Option<String>, // untrusted external text, validated here
    pub page_size: u32,
}

#[allow(clippy::result_large_err)]
pub fn list_source_entry_children(
    request: ListSourceEntryChildrenRequestDto,
) -> Result<SourceEntryChildrenPageDto, ApplicationErrorDto>;

#[allow(clippy::result_large_err)]
pub fn get_source_entry(source_entry_id: String)
    -> Result<SourceEntryDetailDto, ApplicationErrorDto>;
```

1. Add `pub fn parse_source_entry_id(value: &str, trace_id: TraceId) -> Result<SourceEntryId, ApplicationErrorDto>` mirroring `parse_library_root_id`.
2. `list_source_entry_children` is the **only** place an external cursor string is parsed: `request.cursor.as_deref().map(SourceEntryCursor::try_from).transpose().map_err(validation_error)?`; a malformed cursor yields `ARGUS.V1.VALIDATION.INVALID_ARGUMENT`. The parsed `Option<SourceEntryCursor>` is passed into `ListSourceEntryChildrenQuery::new`.
3. Private mappers `source_entry_projection_dto`, `source_entry_detail_projection_dto`, `source_entry_kind_dto`, `source_entry_classification_dto`, `source_entry_children_page_dto`; status fields map to `None`; `next_cursor` maps via `Display` (implementation-private encoding; no plan-level textual invariant).
4. The DTOs structurally cannot carry locators, fingerprints, native identity, `last_observed_scan_id`, or any persistence field.

**Steps (TDD):**
- [ ] Step 1: Write `tests/slice_004_hierarchy.rs` against a real kernel: list root children page; request the next page with the returned opaque cursor; assert deterministic order and `next_cursor` only when a further page exists; `get_source_entry` returns safe detail; malformed root/parent ids and malformed cursor text return `ARGUS.V1.VALIDATION.INVALID_ARGUMENT`; `bounded_status_summary`/`bounded_observation_status_detail` are `None`; assert no field name or value resembling `last_observed_scan_id`, locator, fingerprint, or native identity appears in any returned DTO (structural + value assertions).
- [ ] Step 2: Run `cargo test -p argus-bridge` — fails (functions missing).
- [ ] Step 3: Implement DTOs, mappers, parse helpers, cursor boundary validation, and functions.
- [ ] Step 4: Run bridge tests — pass.

---

### Task 5: Pure-Dart client models, gateway, and API

**Files:**
- Modify: `flutter/lib/core/client/src/models.dart` (+ generated `models.freezed.dart`)
- Modify: `flutter/lib/core/client/src/ports.dart`
- Modify: `flutter/lib/core/client/src/argus_client.dart`
- Modify: `flutter/lib/core/bridge/src/frb_argus_client_gateway.dart`
- Modify: `flutter/test/core/client/sources_gateway_stub.dart`
- Modify: `flutter/test/features/sources/sources_test_fakes.dart`
- Create: `flutter/test/core/client/source_entries_client_test.dart`
- Modify: `flutter/test/core/bridge/frb_mapper_test.dart`

**Interfaces:**
- Consumes: generated DTO types (only inside `frb_argus_client_gateway.dart`).
- Produces (exact Dart surface):

```dart
final class SourceEntryId {
  const SourceEntryId(this.value);
  static SourceEntryId? tryParse(String value);
  bool get isValid; // same 32-hex nonzero rule as LibraryRootId
}

enum SourceEntryKind { directory, file, linkLike, unknown } // fromWire
enum SourceEntryClassification {
  container, contentCandidate, supportingEntry, ignored, unknown,
} // fromWire

@freezed
sealed class SourceEntry with _$SourceEntry {
  const factory SourceEntry({
    required SourceEntryId sourceEntryId,
    SourceEntryId? parentSourceEntryId,
    required String displayName,
    required String displayLocation,
    required SourceEntryKind kind,
    required SourceEntryClassification classification,
  }) = _SourceEntry;
}

@freezed
sealed class SourceEntryDetail with _$SourceEntryDetail {
  const factory SourceEntryDetail({
    required SourceEntryId sourceEntryId,
    SourceEntryId? parentSourceEntryId,
    required String displayName,
    required String displayLocation,
    required SourceEntryKind kind,
    required SourceEntryClassification classification,
  }) = _SourceEntryDetail;
}

final class SourceEntryChildrenPage {
  const SourceEntryChildrenPage({required this.items, this.nextCursor});
  final List<SourceEntry> items;
  final String? nextCursor; // opaque; never parsed or synthesized by Flutter
}

// ports.dart:
abstract interface class SourcesGateway {
  Future<SourceEntryChildrenPage> listSourceEntryChildren({
    required LibraryRootId libraryRootId,
    SourceEntryId? parentSourceEntryId,
    String? cursor,
    required int pageSize,
  });
  Future<SourceEntryDetail> getSourceEntry(SourceEntryId sourceEntryId);
}
abstract interface class SourcesApi { /* same two methods */ }
```

1. Dart models deliberately contain **no status/provenance fields**; the bridge's reserved status DTO fields are not surfaced into feature models in Slice 004 (additive later per SPEC-X-001).
2. Change `SourceEntriesChangeScope` from an enum to a Freezed sealed class:

```dart
@freezed
sealed class SourceEntriesChangeScope with _$SourceEntriesChangeScope {
  const factory SourceEntriesChangeScope.rootChildren() =
      SourceEntriesChangeScopeRootChildren;
  const factory SourceEntriesChangeScope.entryChildren({
    required SourceEntryId parentSourceEntryId,
  }) = SourceEntriesChangeScopeEntryChildren;
  const factory SourceEntriesChangeScope.entireRootHierarchy() =
      SourceEntriesChangeScopeEntireRootHierarchy;
}
```

3. Gateway additions: `sourceEntryIdFromDto`, `sourceEntryFromDto`, `sourceEntryDetailFromDto`, `sourceEntryChildrenPageFromDto`, `sourceEntryKindFromDto`, `sourceEntryClassificationFromDto`; implement the two gateway methods via `_call`, passing `cursor` through as an opaque `String?`; update `sourceEntriesChangeScopeFromDto` to preserve `SourceEntriesChangeScopeDto_EntryChildren(field0)` as `parentSourceEntryId`. `_SourcesApi` in `argus_client.dart` delegates through `_request` wrappers.

**Steps (TDD):**
- [ ] Step 1: Extend `sources_gateway_stub.dart` and `sources_test_fakes.dart` with the new methods (stub throws `TransportFailure`; fake serves configurable `children`/`details` maps and call counters). Write `source_entries_client_test.dart`: delegation of both methods; cursor is passed through byte-for-byte as an opaque string (fake records the exact value; client must not transform it); application failure vs transport failure translation; `SourceEntryId` validation rejects malformed ids; `fromWire` contract for kind/classification. Extend `frb_mapper_test.dart`: `SourceEntriesChangeScopeDto_EntryChildren` maps with parent id; unknown wire kind/classification throws contract-mismatch; `SourceEntryChildrenPageDto` mapping preserves `nextCursor` as an opaque string; mapper output contains no `lastObservedScanId`/provenance fields.
- [ ] Step 2: Run `cd flutter && fvm flutter test test/core/client/source_entries_client_test.dart test/core/bridge/frb_mapper_test.dart` — fails (missing surface).
- [ ] Step 3: Implement models, ports, client, gateway; run `just generate` to regenerate Freezed/FRB outputs.
- [ ] Step 4: Re-run the focused tests plus existing `sources_client_test.dart` — pass.

---

### Task 6: Sources reconciliation demand and event coordinator (existing seam)

**Files:**
- Modify: `flutter/lib/features/sources/application/sources_state.dart` (+ generated)
- Modify: `flutter/lib/features/sources/sources.dart` (export new variant/types)
- Modify: `flutter/lib/features/sources/application/root_list_controller.dart`
- Modify: `flutter/lib/features/sources/application/root_detail_controller.dart`
- Modify: `flutter/lib/app/bootstrap/sources_event_coordinator.dart`
- Modify: `flutter/test/app/bootstrap/sources_event_coordinator_test.dart`

**Existing seam (verified):** `sourcesRuntimeContextProvider` is overridden in `app_bootstrap.dart` from `readyRuntimeInstanceIdProvider`, and `sourcesReconciliationDemandProvider` carries the coordinator's demand stream. The coordinator is the only Sources consumer of `EventsApi` envelopes/continuity. This task extends that seam; it creates no second event connection and no new global coordinator.

```dart
const factory SourcesReconciliationDemand.sourceChanged({
  required LibraryRootId libraryRootId,
  required SourceEntriesChangeScope scope,
}) = SourcesReconciliationDemandSourceChanged;
```

Coordinator behavior (exact):
1. `RuntimeEventPayloadSourceEntriesChanged(libraryRootId:, scope:)` → add root to `_recentSourceRootIds` and emit `sourceChanged(libraryRootId, scope)` for all three scope variants (including `entryChildren(parentSourceEntryId)`).
2. Non-contiguous sequence, stream `onError`, or `onDone` → emit existing `rootsChanged` AND, for every root in `_recentSourceRootIds` (backend-bounded), emit `sourceChanged(rootId, entireRootHierarchy)`. Never replay event payloads.
3. On runtime generation change, the coordinator resets sequence state and `_recentSourceRootIds`. This is **hygiene only**: hierarchy refresh after runtime replacement is NOT owned by or dependent on these tracked roots (see Task 7). No loaded hierarchy may depend on `_recentSourceRootIds` to learn about replacement.
4. Root-list/root-detail demand switches add `case SourcesReconciliationDemandSourceChanged(): break;` — only the hierarchy controller consumes source scopes.
5. Provenance note: Slice 003's scan currently publishes only `EntireRootHierarchy`; the coordinator still routes all three scopes per contract so future exact-scope events work unchanged. Tests use synthetic events for all three.

**Steps (TDD):**
- [ ] Step 1: Extend coordinator tests: exact `entryChildren` scope preserves parent id; `rootChildren`/`entireRootHierarchy` map exactly; gap after a source event emits both `rootsChanged` and entire-root source demand for the affected root; stream error/done same; a source event for root B does not invalidate root A; runtime generation change resets tracked roots and sequence (assert subsequent first event is treated as a fresh domain, and that no demand is emitted merely from the reset itself).
- [ ] Step 2: Run coordinator test — fails.
- [ ] Step 3: Implement state variant, exports, coordinator, and the two controller switch updates.
- [ ] Step 4: Re-run coordinator + sources feature tests — pass.

---

### Task 7: SourceHierarchyController (bounded validation + runtime-replacement owner)

**Files:**
- Create: `flutter/lib/features/sources/application/source_hierarchy_state.dart` (+ generated)
- Create: `flutter/lib/features/sources/application/source_hierarchy_controller.dart` (+ generated)
- Create: `flutter/lib/features/sources/application/source_entry_detail_controller.dart` (+ generated)
- Modify: `flutter/lib/features/sources/sources.dart` (exports)
- Create: `flutter/test/features/sources/source_hierarchy_controller_test.dart`

**Interfaces:**

```dart
@freezed
sealed class ParentScopeState with _$ParentScopeState {
  const factory ParentScopeState({
    required List<SourceEntry> children,
    String? nextCursor,
    required bool hasLoaded,
    required bool loadingFirstPage,
    required bool loadingMore,
    required bool refreshing,
    ClientFailure? failure,
  }) = _ParentScopeState;
}

@freezed
sealed class SourceHierarchyState with _$SourceHierarchyState {
  const factory SourceHierarchyState({
    required LibraryRootId rootId,
    required Map<String, ParentScopeState> scopesByParent, // '' = root scope
    required Set<String> expandedEntryIds,
    SourceEntryId? selectedEntryId,
    required List<SourceEntryId> compactDrillDownPath,
    required bool reconciling,
  }) = _SourceHierarchyState;
}

@Riverpod(keepAlive: true)
class SourceHierarchyController extends _$SourceHierarchyController {
  AsyncValue<SourceHierarchyState> build(LibraryRootId rootId);
  Future<void> refresh(rootId);                       // reconcile all loaded scopes
  Future<void> expand(rootId, entryId);               // page-1 load when missing
  Future<void> collapse(rootId, entryId);             // keep cached children
  Future<void> loadMore(rootId, String parentKey);    // append via stored cursor
  Future<void> retry(rootId, String parentKey);       // re-issue failed op
  Future<void> select(rootId, entryId);
  Future<void> openContainer(rootId, entryId);        // compact drill-down advance
  Future<void> goBack(rootId);                        // compact pop
}

@Riverpod(keepAlive: true)
Future<SourceEntryDetail> sourceEntryDetail(Ref ref, SourceEntryId sourceEntryId);
```

**Paging and invalidation (unchanged from approved direction):**
1. Initial load loads only root scope (`''`); expand loads only that parent's page 1; siblings never block each other.
2. `loadMore` appends in backend order; failure preserves children and sets scoped `failure`; `retry` re-requests the stored `nextCursor` (or page 1 after a first-page failure).
3. Invalidation: `rootChildren` → refresh `''` from page one; `entryChildren(parentId)` → refresh that scope only if loaded; `entireRootHierarchy` → refresh every loaded scope. Confirmed content stays visible while pending; children + cursor chain replace only after success.
4. Stale protection: every async read captures `(generation, requestToken)` and publishes only when current; runtime context change increments `_generation`.

**Interaction-state reconciliation (revised — no partial-page absence authority):**
1. Loaded page snapshots are bounded caches, not complete graph authority. Absence from any loaded page is never treated as deletion.
2. After each authoritative scope refresh, the controller computes `transientIds = {selectedEntryId} ∪ expandedEntryIds ∪ compactDrillDownPath` and `absentFromLoadedScopes` (ids not present in any loaded scope's children).
3. Validation uses only focused `getSourceEntry` (one bounded query per transient identity, not per loaded row — no N+1 refresh pattern), in a bounded batch per reconciliation: priority `selectedEntryId` → current Compact path node → remaining path (nearest-first) → expanded ids (insertion order), capped at `maxTransientValidationsPerReconcile = 8`. Identities beyond the cap remain preserved and are queued for the next reconciliation pass; they are never pruned speculatively.
4. **Bounded continuation:** the 8-identity bound is per batch, not a permanent cap. If more than 8 transient identities need validation, process at most 8, then — if the current runtime/root/generation is still valid — schedule another bounded batch (microtask/next-pass) until the queue drains; a later backend event is not required to continue an already-started reconciliation. Generation/root replacement or controller disposal cancels/supersedes remaining old-generation work.
5. `getSourceEntry` found → preserve the identity and its transient role even when its new hierarchy location is not loaded; never fabricate parentage/ancestry.
6. `getSourceEntry` not-found (authoritative removal) → clear selection; remove the id from `expandedEntryIds`; for Compact path, drop the node and any descendants then retreat to the nearest path ancestor that is present in a loaded scope or proven valid by a focused read, else to root scope (`''`).
7. Any non-not-found application/transport failure during validation preserves the transient identity and is never interpreted as deletion. Unresolved identities are retained (not failed-fast retried in a tight loop) and may be resolved by a later authoritative reconciliation or explicit user retry.
8. A parent scope in Slice 004 has no authoritative completeness marker, so absence from a fully-paged scope also never proves deletion; if such a marker is added by a later slice, this rule can narrow.

**Runtime replacement (single canonical path):**
1. The controller watches the existing `sourcesRuntimeContextProvider` (same seam as `SourcesRootDetailController`). On `RuntimeInstanceId` change it: preserves last-confirmed state, increments `_generation`, and schedules an authoritative broad refresh (page-one restart) of **every** currently loaded scope. Old-generation in-flight results cannot publish.
2. This is the canonical hierarchy replacement path; it does not depend on coordinator `_recentSourceRootIds` or on any event arriving. The coordinator's later scoped/entire-root demands are supplementary and coalesce into the controller's pending broad refresh (if a broad refresh is already pending for the root, subsequent scoped demands fold into it and trigger no duplicate requests).
3. No second native event connection, no new global coordinator, no duplicate racing mechanisms.

**Steps (TDD):**
- [ ] Step 1: Write controller tests against the extended `FakeSourcesApi`: root first page; nested/independent branch loads; per-parent paging preserving order; scoped next-page failure preserves children and `retry` succeeds; exact invalidation scopes; broadening; stable-ID preservation; stale async rejection; dispose safety. Then the revised reconciliation tests:
  - Regression: selected/expanded/path entry exists but moved beyond the refreshed first page (page 1 no longer contains it; `getSourceEntry` returns found) → identity preserved, no pruning, no fabricated parentage.
  - `getSourceEntry` not-found → selection cleared, expansion removed, Compact retreats to nearest proven-valid ancestor or root.
  - Validation batch cap: > 8 absent transient ids → only the prioritized subset is queried per pass, remaining ids stay preserved, later passes validate the queue.
  - Validation continuation: > 8 transient identities are eventually processed in multiple bounded batches without one unbounded burst (fake API records per-call batch sizes; each batch ≤ 8 and the queue fully drains without any additional backend event).
  - A non-not-found validation failure (e.g., `TransportFailure`) preserves the transient identity and does not retry in a tight loop.
  - Generation replacement prevents queued old-generation validation batches from publishing (start a validation pass, replace runtime generation, complete the stale responses, assert no state mutation).
  - Runtime replacement with **no events at all**: context change alone triggers broad refresh of all loaded scopes and rejects an old-generation in-flight completion.
  - Runtime replacement followed by a scoped demand while the broad refresh is pending → coalesces (no duplicate request for the same scope).
- [ ] Step 2: Run — fails (missing controller).
- [ ] Step 3: Implement state, controller, detail provider, exports.
- [ ] Step 4: Run controller tests plus the full existing sources feature suite — pass.

---

### Task 8: Hierarchy presentation, inspector, accessibility, responsive behavior

**Files:**
- Create: `flutter/lib/features/sources/presentation/source_hierarchy_browser.dart`
- Create: `flutter/lib/features/sources/presentation/hierarchy_drill_down_view.dart`
- Create: `flutter/lib/features/sources/presentation/hierarchy_tree_view.dart`
- Create: `flutter/lib/features/sources/presentation/source_entry_inspector.dart`
- Modify: `flutter/lib/features/sources/presentation/sources_messages.dart` (copy strings)
- Modify: `flutter/lib/features/sources/presentation/root_detail_page.dart` (embed browser)
- Modify: `flutter/lib/features/sources/sources.dart` (presentation exports)
- Create: `flutter/test/features/sources/source_hierarchy_presentation_test.dart`
- Modify: `flutter/test/features/sources/sources_feature_test.dart` (root-detail layout expectations)

**Interfaces:**

```dart
class SourceHierarchyBrowser extends ConsumerWidget {
  const SourceHierarchyBrowser({required this.rootId, super.key});
  final LibraryRootId rootId;
}
```

Behavior (exact):
1. Uses `WindowSizeClass` from `core/responsive`: Compact/Medium → `HierarchyDrillDownView` (list of current container's children, explicit Back button + breadcrumb of `compactDrillDownPath`, Load More row, scoped retry row); Expanded/Large → `HierarchyTreeView` (indented rows, expand/collapse chevrons, Load More per expanded parent, scoped retry).
2. Row presentation: safe facts only — display name plus kind/classification label. **No status line, no scan/provenance facts** (Slice 004 has no authoritative user-meaningful status fact). Inspector shows only display name, display location, kind, and classification. Never raw locators/identities/fingerprints.
3. Traversability exactly: `kind == directory && classification == container` traversable; `file/unknown`, `link_like/ignored`, `unknown/ignored` non-traversable.
4. Selection: tapping a row calls `select`; tapping a traversable row in drill-down calls `openContainer`; tree row activation (Enter/Space) selects; Right expands/enters, Left collapses/parent, Up/Down move visible focus, all via per-row `FocusNode.onKeyEvent`; Load More/retry are standard focusable controls (never hover-only).
5. Inspector: watches `sourceEntryDetail(rootId, selectedEntryId)`; Compact → modal bottom sheet with dismissal restoring focus to the originating row when it still exists; Medium → in-page region when local width ≥ 600, otherwise Compact behavior; Expanded/Large → persistent side panel. `GetSourceEntry` not-found clears selection through the Task 7 contract.
6. Async loads/refresh never steal focus; `Semantics(expanded: ...)`, selected state perceivable without color, live regions for loading.
7. `root_detail_page.dart`: header block (name/location/status chip/View Job/remove/scan actions, preserving existing widget keys) followed by `Expanded(child: SourceHierarchyBrowser(rootId: rootId))`.

**Steps (TDD):**
- [ ] Step 1: Write presentation tests (pump with `FakeSourcesApi`, fixed `tester.view.physicalSize`, `textScaleFactorTestValue`): Compact drill-down Back/breadcrumb; Expanded tree expand/collapse; Medium adaptation; inspector open/dismiss/focus restore; Load More keyboard-reachable; Up/Down/Right/Left/Enter/Space tree navigation; semantics flags; no focus theft during event-driven refresh; exact traversal mapping (archive-like file not decorated); no provenance/status text rendered; 1.0x and 2.0x text scale at Compact and Large without critical clipping; 600/840/1200 width boundaries.
- [ ] Step 2: Run — fails (widgets missing).
- [ ] Step 3: Implement the four widgets, messages, root-detail integration, exports.
- [ ] Step 4: Run presentation tests + existing sources feature/widget tests — pass.

---

### Task 9: Generation, registration, full verification, RESULT.json

**Files:**
- Modify: `justfile` (`registered_generated_files` additions for every new `.freezed.dart`/`.g.dart` produced by Tasks 5–8)
- Create: `.chatgpt/codex-runs/2026-08-15T060107Z-phase-001-slice-004-sources-hierarchy-inspection/RESULT.json`

**Steps:**
- [ ] Step 1: Run `just generate`; confirm all new generated files exist and are registered in `justfile`; no generated file contains a machine-local absolute path.
- [ ] Step 2: Run `just check` from a clean tree (check-generated, format, lint, architecture, full tests). Fix only slice-caused drift; never weaken a gate.
- [ ] Step 3: Confirm `git status` shows only authorized paths, uncommitted.
- [ ] Step 4: Write `RESULT.json` (schema_version 3; every TAC exactly once with `passed` and concrete evidence; or `blocked`/`unverified` only if truthfully blocked; no unknown fields).
- [ ] Step 5: Final chat response: plain-language completion, what improved, whether the user must act, remaining limitations.

## 2. Self-Review (post-revision)

1. **Binding spec coverage:** TAC-1/2/3 → Tasks 1–5 with the safe projection vocabulary (status reserved and `None`; no provenance relabeling); TAC-4/5 → Tasks 5–6 (exact scopes incl. parent id; gap/uncertainty broadening; runtime replacement canonical path in Task 7); TAC-6–11 → Task 7 (bounded paging, no partial-page absence authority, focused `getSourceEntry` validation with a bounded batch, runtime-replacement refresh, stale rejection, identity preservation, Compact retreat only on proof); TAC-12/13 → Task 8; TAC-14/15/16 → Tasks 7–8 test lists; TAC-17 → Task 9; TAC-18 → exclusions enforced.
2. **Type/signature consistency:** `SourceEntryCursor` (validated, structured) ↔ opaque `String?` on the Dart wire; `Option<&SourceEntryCursor>` in `SourceEntryQueries`; `TryFrom<&str>` only at the bridge; `SourceEntryProjection`/`SourceEntryDetailProjection` carry only the six safe fields; DTO reserved status fields `Option<String>` mapped `None`; Dart models omit status fields; `parent_source_entry_id` ↔ `SourceEntryId?`; `SourceEntriesChangeScopeDto_EntryChildren(field0)` ↔ `SourceEntriesChangeScope.entryChildren(parentSourceEntryId)`. All 11 `LibraryService::new` sites are listed with their fix.
3. **No partial-page absence authority:** Task 7 rules and the move-beyond-page-one regression test make this explicit; no task prunes from loaded-page absence.
4. **One runtime-replacement path:** Task 7 owns replacement refresh via `sourcesRuntimeContextProvider`; Task 6's coordinator reset is hygiene only; demands coalesce into the pending broad refresh; no second connection/coordinator.
5. **Safe projection vocabulary:** no provenance or invented status anywhere in Rust projections, DTO values, Dart models, or UI; bridge fields stay `None` and are documented as reserved.
6. **Cursor trust boundary:** bridge parses/validates; persistence consumes structured keys; malformed external text → `ValidationInvalidArgument`; persistence corruption remains `CorruptOrIncompatible`; encoding is implementation-private.
7. **Provenance re-check:** `source_entry.created_at` is Unix seconds (`migrations::timestamp()`), so the cursor key is `created_at_seconds`; `SourceEntryKind`/`SourceEntryClassification` variants match current application types; Slice 003 currently emits `EntireRootHierarchy` only, while the coordinator routes all three scopes; the runtime-context seam is `sourcesRuntimeContextProvider` wired in `app_bootstrap.dart`.

## 3. Execution Handoff

Plan complete. Execution options once the plan is approved:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task with two-stage review between tasks.
2. **Inline Execution** — execute tasks in this session with checkpoints.
