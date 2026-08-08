# SQLite, Migrations, Repositories, and Unit of Work Specification

**Document ID:** SPEC-BE-002
**Status:** Ready for Implementation
**Owner:** Daniel
**Last Updated:** 2026-08-08
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-001
**Supersedes:** None
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative persistence architecture for Argus ROM Toolkit, including SQLite access, connection ownership, database execution, migration integrity, Unit of Work semantics, repositories, query interfaces, error translation, SQL organization, testing, and performance guardrails.

The design prioritizes correctness, explicit transaction ownership, long-term maintainability, cross-platform reproducibility, and a clean migration path from the MVP's single-connection architecture to a post-MVP read pool.

## 2. Scope

This specification covers:

- SQLite library and build configuration
- database executor ownership and threading
- connection initialization and PRAGMAs
- Unit of Work lifecycle and transaction semantics
- CQRS-lite read/write persistence interfaces
- repository borrowing and lifetime conventions
- SQL-first hybrid migrations
- migration history and checksum validation
- persistence error boundaries
- SQLite infrastructure layout
- SQL ownership and organization
- persistence testing conventions
- performance and indexing guidelines
- post-MVP read-pool evolution

## 3. Architectural Principles

1. SQLite is an infrastructure detail and does not leak into domain or application contracts.
2. All database access executes away from Flutter's UI-sensitive thread.
3. The MVP uses one dedicated database thread and one long-lived writable connection.
4. One Unit of Work owns exactly one top-level SQLite transaction.
5. Transaction ownership is explicit; ambient transactions are prohibited.
6. Write repositories are transaction-bound.
7. UI and reporting reads use focused query interfaces and immutable projections.
8. Reads required to decide a mutation occur inside the Unit of Work.
9. Domain objects returned from persistence are owned values.
10. Repository adapters are ephemeral views over the current transaction.
11. Released migrations are immutable and checksum-validated.
12. Observable side effects occur only after successful commit.
13. Persistence interfaces express application intent, not SQL mechanics.
14. Performance optimizations must preserve the application-facing contracts.

## 4. SQLite Library

Argus uses `rusqlite` with bundled SQLite.

Requirements:

- Enable the `bundled` feature so supported platforms use a consistent SQLite implementation.
- Do not depend on the operating system's installed SQLite version.
- Keep `rusqlite` confined to `argus-infrastructure`.
- Do not expose `rusqlite::Connection`, `Transaction`, `Row`, `Error`, or statement types outside infrastructure.
- Select additional `rusqlite` features only when a documented implementation requirement exists.

SQLx, Diesel, SeaORM, and mixed persistence stacks are out of scope.

## 5. Database Executor

### 5.1 MVP model

The MVP uses:

```text
Application calls
      ↓
Database executor queue
      ↓
Dedicated database thread
      ↓
One long-lived rusqlite::Connection
      ↓
SQLite database
```

The executor owns:

- the database thread
- connection creation
- connection initialization
- migration execution during startup
- serialized database work
- shutdown and connection closure
- panic/error containment appropriate to the runtime design
- queue-level diagnostics

### 5.2 Executor rules

- The connection is created and used only on the database thread.
- Application and bridge code never access the connection directly.
- Database operations are submitted as bounded work items.
- The public application-facing operation may be async even though `rusqlite` work is synchronous.
- Blocking SQLite work must never execute on Flutter's platform/UI thread.
- The executor must reject new work after shutdown begins.
- Shutdown must drain or reject queued work according to the runtime shutdown specification.
- Migrations complete before the executor reports readiness for normal work.
- Long-running queries must be measurable and diagnosable.

### 5.3 Post-MVP evolution

A read pool may be added after profiling demonstrates a real bottleneck.

The future model is:

```text
Commands and transactional reads
      ↓
Single writer executor and connection

Independent projections
      ↓
Read executor / small read-only pool
```

Invariants retained post-MVP:

- exactly one writer
- Unit of Work always uses the writer
- repository contracts do not change
- query contracts do not change
- application code does not know about connection pools
- WAL remains the concurrency foundation
- read-pool introduction is infrastructure-only

## 6. Connection Configuration

Every writable connection is initialized with:

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
PRAGMA temp_store = MEMORY;
```

### 6.1 Required behavior

- `foreign_keys` must be verified as enabled.
- `journal_mode` must be verified as `wal`.
- `busy_timeout` is 5000 milliseconds.
- Connection initialization failure is a structured startup failure.
- The application must not silently continue with different durability or integrity settings.
- PRAGMA application belongs to infrastructure startup, not repositories.

### 6.2 Durability rationale

`WAL` plus `synchronous = NORMAL` is the required MVP balance:

- preserves practical database integrity
- supports future concurrent readers
- reduces write latency relative to `FULL`
- is appropriate because most indexed and metadata-derived data is reconstructible
- still transactionally protects user-authored settings and application state

Changing the durability policy requires an update to this specification or an ADR.

## 7. Unit of Work

### 7.1 Ownership

Unit of Work contracts live in `argus-application`.

The concrete SQLite implementation lives in `argus-infrastructure`.

Runtime constructs and supplies the Unit of Work factory.

### 7.2 Lifecycle

One focused mutating application operation handler owns one Unit of Work:

```text
begin
  ↓
perform transactional reads
  ↓
perform writes
  ↓
record pending events in the operation-scoped EventCollector
  ↓
commit explicitly
  ↓
return committed operation outcome
  ↓
ApplicationRuntime releases recorded events
```

The operation-scoped `EventCollector` and post-commit publication lifecycle are defined by SPEC-BE-006. The Unit of Work does not own or contain the event collector.

### 7.3 Invariants

- One Unit of Work owns exactly one top-level transaction.
- Nested Unit of Work creation is prohibited.
- Nested top-level transactions are prohibited.
- Savepoints are not implemented in Phase 000.
- Commit is explicit.
- Commit consumes or permanently finalizes the Unit of Work.
- Dropping an uncommitted Unit of Work rolls back.
- Repositories cannot commit or roll back.
- A Unit of Work cannot be reused after commit or rollback.
- Transaction-scoped values cannot escape the Unit of Work.
- All mutation-decision reads occur inside the same transaction as the write.

### 7.4 Rollback behavior

Any of the following before commit results in rollback:

- validation failure
- repository failure
- early return
- `?` propagation
- cancellation before the commit boundary
- dropped Unit of Work
- panic where unwinding reaches the transaction owner and the process survives

Rollback failure must be logged with technical detail and surfaced as a stable persistence failure where possible.

### 7.5 Savepoints

Savepoints are deferred.

A future savepoint API must be explicit and narrowly scoped. Releasing a savepoint must never be described as durable commit because the outer transaction remains authoritative.

## 8. Side Effects and Events

Domain/application events are recorded in the operation-scoped `EventCollector`, not inside the Unit of Work. The Unit of Work owns transaction consistency only and does not publish events.

Required ordering:

```text
application handler records pending event
      ↓
database mutation
      ↓
transaction commit
      ↓
runtime observes committed operation outcome
      ↓
ApplicationRuntime releases EventCollector contents
      ↓
runtime event publication
      ↓
bridge/UI observation
```

No observable side effect may occur before successful commit.

Observable side effects include:

- event publication
- bridge broadcasts
- scheduler enqueueing
- notifications
- dependent filesystem mutation
- analytics or telemetry
- future server or websocket events

If commit fails, the runtime discards the operation-scoped pending events according to SPEC-BE-006.

## 9. CQRS-Lite Persistence Interfaces

Argus separates transactional write persistence from independent read projections.

This is CQRS-lite only. It does not introduce:

- event sourcing
- separate read databases
- eventual consistency
- distributed command buses
- mandatory message brokers
- separate deployment units

### 9.1 Write repositories

Write repository contracts:

- live in `argus-application`
- are owned by the relevant feature
- are available only through a Unit of Work
- return owned domain entities or aggregates
- may read state required to make a mutation decision
- persist Argus-owned state
- remain persistence-agnostic

Examples:

```text
AppearanceSettingsRepository
LibrarySourceRepository
LibraryRootRepository
SourceEntryRepository
GameContentRepository
MetadataRepository
ArtworkRepository
```

Typical methods express aggregate intent:

```rust
pub trait AppearanceSettingsRepository {
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError>;

    fn save(
        &mut self,
        settings: &AppearanceSettings,
    ) -> Result<(), PersistenceError>;
}
```

### 9.2 Query interfaces

Query contracts:

- live in `argus-application`
- do not require a Unit of Work
- return immutable snapshots and projections
- support UI/reporting reads
- may use joins, aggregation, filtering, sorting, and pagination
- express application intent rather than arbitrary SQL execution
- use the same database executor during MVP

Examples:

```text
AppearanceSettingsQueries
LibraryQueries
GameDetailQueries
DiagnosticsQueries
```

Query result examples:

```text
AppearanceSettingsSnapshot
GameSummary
GameDetail
PlatformCount
LibraryFilterOptions
ScanHistorySummary
```

### 9.3 Read routing rule

Reads required to decide a mutation use the transaction-bound repository.

Independent UI, diagnostics, reporting, and browsing reads use query interfaces.

A command handler must not read mutation-decision state through an independent query interface and then write through a later transaction.

### 9.4 No generic repository abstraction

Do not introduce:

```text
Repository<T>
CrudRepository<T>
BaseRepository
GenericQueryRepository
```

Aggregate and projection contracts must express specific application semantics.

## 10. Repository Borrowing and Lifetimes

### 10.1 Owned return values

Persistence returns owned domain and projection values.

Do not return references tied to:

- the SQLite connection
- a transaction
- a row
- a statement
- a repository wrapper
- the Unit of Work

Preferred:

```rust
let settings: AppearanceSettings = uow.settings().get()?;
```

Not permitted:

```rust
let settings: &AppearanceSettings = uow.settings().get()?;
```

### 10.2 Ephemeral repository accessors

The Unit of Work exposes lightweight repository accessors:

```rust
let mut settings = uow.settings().get()?;
settings.set_theme(theme)?;
uow.settings().save(&settings)?;
```

The accessor returns a temporary repository view borrowing the active transaction for the shortest practical scope.

Repository wrappers:

- contain no independent transaction state
- are not cached
- are not stored in application structs
- do not outlive the immediate operation
- do not escape closures or handlers
- are cheap typed views over the current transaction

### 10.3 Prohibited repository lifetime patterns

Do not:

```rust
struct Handler {
    repository: SqliteAppearanceSettingsRepository<'static>,
}
```

Do not cache a repository obtained from a Unit of Work.

Do not design APIs requiring several simultaneous mutable repository borrows from one Unit of Work.

Application handlers should sequence repository operations so each mutable borrow ends before the next begins.

### 10.4 Implementation flexibility

The concrete Rust shape may use:

- temporary wrapper values
- short reborrows
- internal helper functions
- transaction-scoped repository constructors

The public application contract must preserve the call-site model and owned-value invariant.

## 11. Migration System

Argus uses SQL-first hybrid migrations.

### 11.1 SQL migrations

Embedded ordered SQL files are the default.

Naming:

```text
0001_initial.sql
0002_add_library_sources.sql
0003_add_source_entry_indexes.sql
```

Use SQL for:

- tables
- columns
- indexes
- constraints
- triggers
- ordinary backfills
- SQLite table-rebuild migrations
- deterministic schema transformations

### 11.2 Rust-assisted migrations

Rust-assisted migrations are allowed only when SQL cannot express the transformation safely or maintainably.

Examples:

- parsing a legacy serialized format
- complex application-independent derivation
- filesystem-assisted migration
- cryptographic transformation
- validation requiring procedural logic

Rust-assisted migrations must:

- be self-contained
- avoid current repositories
- avoid current application services
- avoid current domain behavior that may evolve
- use stable migration-local data structures
- have dedicated tests
- document why SQL was insufficient

### 11.3 Migration immutability

After release, a migration is immutable.

Never:

- edit an applied migration
- reorder released migrations
- reuse a version
- silently replace a migration
- bypass checksum validation

Corrections are new migrations.

### 11.4 Migration transaction

By default, all pending migrations run in one startup-owned transaction:

```text
open database
      ↓
create/validate migration history
      ↓
validate embedded history
      ↓
BEGIN IMMEDIATE
      ↓
apply all pending migrations
      ↓
insert history rows
      ↓
validate resulting schema
      ↓
COMMIT
```

A non-transactional migration is exceptional and requires an ADR.

### 11.5 Startup exclusivity

- No normal database work runs during migration.
- The migration runner owns startup database access.
- Runtime readiness is not reported until migrations succeed.
- Migration failure produces a structured startup failure.
- The last fully committed schema remains authoritative after transactional failure.

## 12. Migration History and Integrity

The dedicated history table is authoritative.

`PRAGMA user_version` is not used.

Required schema:

```sql
CREATE TABLE schema_migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    checksum TEXT NOT NULL,
    applied_at TEXT NOT NULL,
    app_version TEXT NOT NULL
);
```

### 12.1 Column semantics

- `version`: monotonically increasing migration number
- `name`: stable human-readable migration name
- `kind`: `sql` or `rust`
- `checksum`: deterministic checksum of the released migration definition
- `applied_at`: UTC timestamp
- `app_version`: Argus version that applied the migration

### 12.2 Validation

Startup must detect:

- modified historical migration
- missing embedded historical migration
- duplicate version
- invalid ordering
- unknown applied migration
- kind mismatch
- checksum mismatch
- invalid migration table contents

These are integrity and diagnostics requirements, not compliance auditing.

### 12.3 Checksum policy

- Use one documented checksum algorithm.
- Normalize only what the algorithm explicitly defines.
- Do not silently normalize migration contents in ways that hide edits.
- SQL and Rust-assisted migrations use the same checksum field and validation process.

## 13. Persistence Error Boundaries

Error ownership follows SPEC-BE-001.

### 13.1 Infrastructure

Infrastructure owns technical errors such as:

- connection open failure
- PRAGMA failure
- SQLite error code
- migration execution failure
- checksum mismatch detail
- statement preparation failure
- row mapping failure
- executor queue failure
- executor shutdown
- rollback failure

Technical errors retain enough context for logs and diagnostics.

### 13.2 Application

Application sees stable persistence categories, such as:

```text
Unavailable
ConstraintViolation
NotFound
Conflict
CorruptOrIncompatible
MigrationRequired
MigrationFailed
Cancelled
Internal
```

The exact cross-application error catalog is finalized by SPEC-BE-003.

### 13.3 Boundary rules

- `rusqlite::Error` never leaves infrastructure.
- SQL strings are not exposed to Flutter.
- database paths are redacted where appropriate
- secrets and user-sensitive values are not included in bridge errors
- low-level error chains may be logged but are mapped to stable application categories
- constraint failures should map predictably where application semantics are known

## 14. Infrastructure Organization

Recommended structure:

```text
argus-infrastructure/src/
└── sqlite/
    ├── mod.rs
    ├── connection.rs
    ├── executor.rs
    ├── errors.rs
    ├── unit_of_work.rs
    ├── migrations/
    │   ├── mod.rs
    │   ├── runner.rs
    │   ├── history.rs
    │   ├── checksum.rs
    │   └── sql/
    ├── repositories/
    ├── queries/
    ├── mapping/
    └── test_support/
```

Rules:

- Do not create empty directories for future features.
- Repository implementations are grouped by owning feature.
- Query implementations are grouped by projection/use case.
- Shared row mapping remains narrow and typed.
- Migration-local code remains under migrations.
- Test support is not exposed in production APIs.

## 15. SQL Organization

### 15.1 Ownership

SQL lives beside the repository, query, or migration that owns it.

Do not create one global query file.

### 15.2 Small SQL

Short stable statements may be constants in focused implementation modules.

### 15.3 Large SQL

Large or complex statements should use dedicated `.sql` files near their owning implementation.

Examples:

```text
queries/library/list_games.sql
queries/game_detail/load_game_detail.sql
repositories/source_entries/upsert_source_entry.sql
```

### 15.4 SQL contract rules

- Select explicit columns; avoid `SELECT *`.
- Define stable ordering for paginated queries.
- Use bound parameters.
- Do not construct SQL by concatenating user-controlled values.
- Dynamic sorting/filtering must use allow-listed fragments or typed query builders.
- Keep persistence SQL out of domain and application crates.
- Index requirements must be delivered through migrations.
- Schema-qualified assumptions must be documented when non-obvious.

## 16. Query and Pagination Semantics

Every paginated query interface documents:

- ordering
- tie-breaker ordering
- page/cursor semantics
- filter behavior
- empty result behavior
- snapshot/staleness expectations
- maximum requested page size where applicable

Offset pagination may be used for bounded/simple views. Cursor/keyset pagination should be preferred for large, frequently changing library result sets when implemented.

Pagination strategy is chosen per query contract, not through a universal generic repository.

## 17. Testing Strategy

### 17.1 Domain and application unit tests

Use fakes or in-memory test doubles for repository, query, Unit of Work, and executor-facing contracts.

These tests do not require SQLite.

Test:

- command orchestration
- commit behavior
- event publication ordering
- rollback on failure
- query handler mapping
- application error mapping

### 17.2 Infrastructure integration tests

Use temporary on-disk SQLite databases by default.

Reasons:

- WAL behavior matches production
- file locking is exercised
- connection initialization is exercised
- journal files are exercised
- lifecycle and cleanup behavior are realistic

In-memory SQLite may be used only for narrow tests where file/WAL semantics are irrelevant.

### 17.3 Repository tests

Each repository implementation tests:

- insert/save
- load
- update
- delete where supported
- missing values
- constraints
- transaction rollback
- mapping failures where constructible
- owned return-value behavior
- no partial persistence

### 17.4 Query tests

Each query implementation tests:

- projection correctness
- filtering
- sorting
- deterministic ordering
- pagination boundaries
- empty results
- representative joins and aggregation
- no N+1 behavior where measurable

### 17.5 Migration tests

Migration tests must:

- create every supported historical schema state
- run all later migrations
- verify migration history rows
- verify checksums
- verify representative preserved data
- verify constraints and indexes
- verify rollback on migration failure
- reject modified historical migrations
- reject unknown or invalid migration history
- verify fresh-database creation

Historical schema fixtures must remain immutable after release.

### 17.6 Executor tests

Test:

- serialized execution
- connection/thread affinity
- startup readiness
- migration-before-work ordering
- queue rejection during shutdown
- error propagation
- work after shutdown
- panic containment according to runtime policy

## 18. Performance Guidelines

The following are guardrails, not permission for speculative optimization:

- prepare and reuse statements where beneficial
- batch writes inside one Unit of Work
- avoid one transaction per row for bulk operations
- avoid N+1 query patterns
- retrieve only required projection columns
- keep transaction duration bounded
- do not perform network or slow filesystem work while a database transaction is open
- add indexes through migrations based on query requirements
- inspect query plans for complex or high-volume queries
- benchmark before introducing caches
- measure database queue wait time and execution time separately
- chunk large indexing operations where atomicity permits
- preserve UI responsiveness regardless of background database work

## 19. Concurrency and Cancellation

### 19.1 MVP serialization

All MVP database work is serialized through one executor.

Serialization is an intentional correctness model, not an invitation to perform unbounded work in one task.

### 19.2 Cancellation

- Work cancelled before execution should be removable or skipped where supported.
- Once a transaction begins, cancellation must produce a deterministic rollback before the operation is reported cancelled.
- Commit is a critical boundary and must not be reported as cancelled after SQLite has durably committed.
- The caller must receive either committed success or failure/cancellation with rollback; ambiguous outcomes are prohibited where technically avoidable.

### 19.3 External work

Do not hold a transaction open while:

- performing HTTP requests
- scanning large filesystem trees
- hashing ROM content
- waiting for user input
- downloading artwork
- invoking external tools

External work is completed before the transactional persistence phase or coordinated through explicit staged workflows.

## 20. Security and Privacy

- Use bound parameters for all values.
- Do not log secret values or credentials.
- Avoid logging full user filesystem paths unless diagnostics policy explicitly allows it.
- Database files use platform-appropriate application data directories.
- Database file permissions should use the safest practical platform defaults.
- SQLCipher or other database encryption is not required for MVP.
- Future encryption must not alter application persistence contracts.
- Corrupt or incompatible databases must fail safely rather than be silently recreated.
- Destructive recovery requires explicit user intent and a later recovery specification.

## 21. Backup and Recovery Boundaries

Phase 000 does not require automatic backup or restore.

The design must not prevent later support for:

- SQLite online backup
- pre-migration backup for high-risk upgrades
- diagnostic database copy with redaction policy
- integrity checks
- repair/export workflows

Argus must not silently delete or replace a database after migration, integrity, or open failure.

## 22. Naming Conventions

Write contracts:

```text
<Aggregate>Repository
```

Read contracts:

```text
<Feature>Queries
<Projection>Queries
```

Concrete implementations:

```text
Sqlite<Aggregate>Repository
Sqlite<Feature>Queries
SqliteUnitOfWork
SqliteUnitOfWorkFactory
SqliteDatabaseExecutor
```

Avoid:

```text
Manager
Helper
Util
Store
RepositoryImpl
DatabaseService
GenericRepository
```

unless a later specification gives the term a precise bounded responsibility.

## 23. Documentation Requirements

Every write repository contract documents:

- owning aggregate
- transaction requirement
- mutation-decision read behavior
- not-found semantics
- concurrency/version assumptions
- event implications

Every query contract documents:

- projection ownership
- ordering
- pagination
- filtering
- snapshot/staleness semantics
- expected result size
- cancellation behavior where relevant

Every migration documents:

- purpose
- data preservation behavior
- risk
- transactional behavior
- validation performed
- reason for Rust assistance when applicable

## 24. Prohibited Patterns

- SQLite types outside infrastructure
- database access from Flutter
- database access from domain
- direct connection use from application handlers
- ambient or task-local transactions
- nested top-level Unit of Work creation
- repository-owned commits
- repository caching
- references escaping SQLite rows or transactions
- generic CRUD repositories
- arbitrary SQL execution exposed through application ports
- event publication before commit
- HTTP/filesystem waits inside transactions
- editing released migrations
- `PRAGMA user_version` as schema authority
- silent database recreation after failure
- production reliance on in-memory SQLite tests alone
- introducing a read pool before profiling justifies it

## 25. Phase 000 Minimum Implementation

Phase 000 implements only the persistence needed for the appearance theme workflow:

- bundled `rusqlite`
- one database executor thread
- one long-lived connection
- required PRAGMAs
- initial migration and migration history
- appearance settings write repository
- appearance settings query interface
- SQLite Unit of Work
- explicit commit and rollback behavior
- committed settings event handoff
- temporary-file integration tests
- migration integrity tests
- startup migration failure reporting

No library, indexing, metadata, artwork, or RetroAchievements schema is included.

## 26. Acceptance Criteria

SPEC-BE-002 is satisfied when:

1. `rusqlite` uses bundled SQLite.
2. SQLite is confined to `argus-infrastructure`.
3. One dedicated database thread owns one long-lived connection.
4. Normal work is accepted only after migrations complete.
5. Required PRAGMAs are applied and verified.
6. One Unit of Work owns one top-level transaction.
7. Nested Unit of Work creation is prohibited.
8. Uncommitted Unit of Work drop rolls back.
9. Repositories cannot commit or roll back.
10. Events are published only after successful commit.
11. Write repositories and query interfaces are separate.
12. Mutation-decision reads occur inside the Unit of Work.
13. Query interfaces return immutable projections.
14. Repository methods return owned values.
15. Repository accessors are ephemeral and uncached.
16. SQL-first hybrid migrations are implemented.
17. Released migration checksums are validated.
18. `schema_migrations` is authoritative.
19. `PRAGMA user_version` is unused.
20. SQLite errors are translated before leaving infrastructure.
21. Integration tests use temporary on-disk databases by default.
22. Migration tests cover every supported historical schema.
23. Database queue and execution failures propagate deterministically.
24. No external I/O occurs while a transaction is held.
25. Post-MVP read-pool introduction requires no application contract changes.

## 27. Out of Scope

This specification does not finalize:

- the full cross-application error catalog
- logging and diagnostic redaction details
- exact async channel/runtime implementation
- detailed runtime shutdown policy
- backup and recovery UX
- SQLCipher
- read-pool implementation
- cloud synchronization
- schema for phases after Phase 000
- scheduler persistence
- library indexing batching strategy

These belong to later backend specifications, implementation slices, or ADRs.

## 28. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [Backend Specifications Index](README.md)
