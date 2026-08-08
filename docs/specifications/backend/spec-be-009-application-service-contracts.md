# Application Service Contracts Specification

**Document ID:** SPEC-BE-009  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-08  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-006, SPEC-BE-007, SPEC-BE-008  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative contract for the Argus application service layer.

Application services sit between transport adapters such as the Rust-to-Flutter bridge and the lower-level runtime, domain, persistence, and gateway abstractions. They own named application capabilities, use-case orchestration, transaction boundaries for authoritative mutations, typed application request contracts, application result contracts, and event-recording semantics.

The service layer is intentionally behavioral rather than stateful. It coordinates application work but does not become a cache, persistence layer, runtime scheduler, transport layer, or service-locator graph.

## 2. Scope

This specification covers:

- application service ownership and purpose
- capability-oriented service APIs
- service lifetime and runtime-generation ownership
- stateless service behavior
- immutable constructor-injected dependencies
- prohibition on direct service-to-service dependencies
- explicit cross-domain workflow coordinators
- repository dependency rules
- gateway dependency rules
- runtime-port dependency rules
- approved infrastructure ports
- application-owned command/query request contracts
- `Result<T, ApplicationError>` result contract
- transaction boundary ownership
- read-operation behavior
- background-operation checkpoint behavior
- event semantic ownership and `EventCollector` recording
- runtime-owned post-commit event publication
- bridge/application mapping boundaries
- architecture and test requirements

## 3. Non-Responsibilities

This specification does not define:

- Rust-to-Flutter DTOs or bridge serialization
- Flutter API/client architecture
- domain entity internals
- repository implementations
- SQL or migration details
- provider gateway implementation details
- runtime scheduler/executor implementation
- event-bus transport mechanics
- startup/recovery sequencing
- feature-specific application services beyond the minimum examples required by Phase 000
- authentication/authorization
- distributed transactions
- remote service orchestration

Those concerns remain owned by their respective specifications.

## 4. Architectural Principles

1. Application services expose named application capabilities.
2. Service APIs are use-case-oriented, not CRUD-oriented.
3. Every application operation belongs to exactly one application service or one explicit workflow coordinator.
4. Application services do not depend directly on other application services.
5. Cross-domain workflows are owned by explicit orchestration components.
6. Application service instances belong to one `ApplicationRuntime` generation.
7. Services are long-lived for that runtime generation but stateless with respect to authoritative application state.
8. Service dependencies are immutable after construction.
9. Application services depend only on stable application-facing ports.
10. Repositories own persistence access for bounded persistence concerns.
11. Application services own business consistency across repositories.
12. Gateways own access to external systems.
13. Runtime owns execution; application services request runtime capabilities.
14. Authoritative mutating service operations own explicit Unit of Work boundaries.
15. Read-only operations do not create a Unit of Work unless a later specification explicitly requires a transactional read boundary.
16. Application services own event semantics and event recording.
17. `ApplicationRuntime` owns post-commit event publication.
18. Application services return `Result<T, ApplicationError>`.
19. Application services own application request contracts and never consume bridge DTOs.
20. Application services expose no implementation technology in public contracts.

## 5. Layer Position

Conceptually:

```text
Flutter / CLI / future adapters
            ↓
Transport adapters
            ↓
Application Services
            ↓
Runtime ports / Repositories / Gateways
            ↓
Domain and Infrastructure implementations
```

Application services are the authoritative application-use-case boundary.

A caller invokes an application capability. The service coordinates the dependencies required to satisfy that capability while preserving runtime, persistence, event, and error contracts.

## 6. Application Service Responsibilities

An application service may own:

- named application operations
- request validation at the application boundary
- authorization/admission checks delegated through approved ports where applicable
- delegation to focused application operation handlers
- repository/query coordination through the operation handler
- gateway coordination
- runtime capability requests
- domain-rule invocation
- event construction and operation-scoped event recording
- mapping internal errors to stable `ApplicationError`
- application-level result assembly

An application service does not own:

- transport DTO mapping
- persistence implementation
- database connection pools/executors
- runtime lifecycle state machines
- event-bus routing
- provider implementation routing internals
- mutable authoritative state caches
- frontend presentation state

## 7. Capability-Oriented Interfaces

Every public service method represents one explicit application capability.

Preferred examples:

```text
SettingsService
├── GetAppearanceSettings
└── UpdateAppearanceSettings
```

Future examples:

```text
LibraryService
├── GetLibrary
├── ListLibraries
├── AddLibrarySource
└── RemoveLibrarySource
```

Public service APIs must not degrade into generic CRUD or generic dispatch contracts.

Prohibited examples include:

```text
Get()
Set()
Delete()
Execute(operation)
Invoke(name, payload)
```

unless a future specification defines one of those words as a real application capability rather than generic plumbing.

## 8. Operation Ownership

Each application operation has exactly one authoritative owner.

For example:

```text
UpdateAppearanceSettingsCommand
    → SettingsService
```

The same operation must not be independently implemented by multiple services.

Operation ownership determines:

- transaction policy
- repository dependencies
- gateway dependencies
- runtime dependencies
- error mapping
- event semantics
- success result semantics

Shared lower-level capabilities may be reused, but application operation ownership remains singular.

## 9. No Direct Service-to-Service Dependencies

Application services must not depend directly on other application services.

Prohibited:

```text
LibraryService
    ↓
MetadataService
    ↓
ProviderService
```

This rule exists to prevent:

- hidden orchestration chains
- cyclic service graphs
- transaction ownership ambiguity
- event ownership ambiguity
- accidental runtime re-entry
- broad coupling between bounded contexts

## 10. Cross-Domain Workflow Coordinators

A workflow that genuinely spans multiple application capabilities is owned by an explicit coordinator/orchestrator.

Conceptually:

```text
ImportCoordinator
├── Library capability/ports
├── Metadata capability/ports
└── Provider capability/ports
```

A coordinator:

- owns one explicit cross-domain workflow
- depends on the minimum capabilities required for that workflow
- does not become a generic service locator
- owns the workflow's operation boundary
- follows the same error, runtime, transaction, and event rules as application services

A coordinator is introduced only when a real workflow crosses capability boundaries. Shared behavior alone does not justify creating a coordinator.

## 11. Service Lifetime

Application services are runtime-scoped and long-lived.

Conceptually:

```text
Runtime A
├── SettingsService A
├── DiagnosticsService A
└── ...

Runtime B
├── SettingsService B
├── DiagnosticsService B
└── ...
```

Rules:

1. Each service instance belongs to exactly one runtime generation.
2. Services are constructed as part of runtime composition.
3. Services are retired with their runtime generation.
4. Services are never reused after runtime replacement.
5. Global process-singleton application services are prohibited.
6. Per-call service construction is not the default architecture.

## 12. Stateless Service Model

Application services are behavioral and do not own authoritative mutable application state.

Services must not retain:

- cached aggregates as authoritative state
- repository-backed collections
- mutable settings snapshots
- operation history
- runtime lifecycle state
- provider health state
- bridge/client state

If mutable long-lived state is required, it belongs in an explicitly owned component such as:

- a repository/persistence concern
- runtime component
- gateway/infrastructure component
- dedicated stateful subsystem specified independently

Transient local variables and operation-scoped state are permitted.

## 13. Immutable Dependencies

All service dependencies are supplied during construction and remain immutable for the life of the service instance.

Dependencies must not be replaced dynamically after runtime readiness.

This enables:

- predictable service composition
- straightforward unit testing
- deterministic architecture boundaries
- safe runtime replacement

The exact Rust ownership mechanism (`Arc`, references, owned trait objects, generics, etc.) is an implementation detail.

## 14. Approved Dependency Categories

An application service may depend on stable application-facing ports from these categories:

- independent read/query interfaces
- gateway interfaces
- runtime interfaces
- Unit of Work factory/transaction boundary abstractions where defined by SPEC-BE-002
- approved infrastructure ports such as `Clock`, `IdGenerator`, randomness, or typed configuration interfaces
- operation-scoped context/capabilities supplied by the runtime

Transaction-bound write repositories are not long-lived service dependencies. They are acquired ephemerally from the operation's `UnitOfWork` by the focused mutating operation handler and must not be cached or stored on the service.

Every dependency must be explicit and required by one or more owned capabilities.

## 15. Prohibited Dependency Categories

Application services must not depend directly on:

- other application services
- unrelated bounded-context domain services used as hidden application orchestration
- SQLite APIs
- database driver types
- HTTP clients
- provider SDKs
- filesystem APIs
- logging framework implementations
- async executor/worker-pool implementations
- generated bridge bindings
- bridge DTOs
- Flutter concepts
- service locators
- generic repository/gateway registries used for dynamic resolution

Concrete implementations remain behind stable ports.

## 16. Repository and Query Dependencies

Application services may constructor-inject independent read/query interfaces required by their owned capabilities. Transaction-bound write repositories are acquired only from the active `UnitOfWork` by the focused mutating operation handler.

Example service composition:

```text
LibraryService
├── LibraryQueries
├── MetadataQueries
├── UnitOfWorkFactory
└── other stable ports
```

Example mutation execution:

```text
AddLibrarySource handler
    ↓
UnitOfWorkFactory.begin()
    ↓
UnitOfWork
├── ephemeral LibraryRepository
└── ephemeral SourceRepository
```

Rules:

1. Independent query-interface dependencies are explicit constructor dependencies.
2. Transaction-bound write repositories are ephemeral views over one active Unit of Work.
3. Write repositories are never cached or stored on runtime-scoped services or coordinators.
4. Repositories do not depend on one another for application orchestration.
5. Repositories do not commit transactions independently of the owning Unit of Work.
6. A repository owns persistence behavior for one aggregate or persistence concern.
7. The focused operation handler owns business consistency across repositories within its operation boundary.

## 17. No Repository Locator

The following pattern is prohibited:

```text
RepositoryProvider.get("library")
RepositoryRegistry.resolve(...)
```

when used to hide application-service dependencies.

A Unit of Work exposes transaction-bound repositories according to SPEC-BE-002. The operation's required repository capabilities must remain statically discoverable from its focused handler/service design, but the repository instances themselves are acquired only for the active transaction and never retained by the runtime-scoped service.

## 18. Gateway Dependencies

Application services depend only on gateway abstractions.

Preferred for a workflow that selects among metadata providers:

```text
MetadataWorkflowCoordinator
├── ProviderSelectionPolicy
└── MetadataProviderRegistry
```

The registry is the bounded metadata-provider catalog defined by SPEC-BE-010, not a generic gateway locator.

Avoid application-service dependencies on concrete providers such as:

```text
IGDBClient
ScreenScraperClient
SteamGridDbClient
```

Provider gateway architecture owns:

- provider catalog/discovery
- provider session construction and lifecycle
- provider-specific request/response translation
- provider-specific readiness evaluation
- transparent same-provider transport retry and rate-limit coordination

Application-level provider policy/workflows own:

- deterministic provider selection according to explicit policy
- semantic retry decisions
- cross-provider fallback/failover
- reconciliation of provider results

Application services and workflow coordinators invoke stable provider capabilities, not concrete provider implementations. SPEC-BE-010 is authoritative for this ownership split.

## 19. No Gateway Locator

Dynamic service-layer gateway resolution is prohibited.

Application services must not use:

```text
GatewayRegistry.resolve(providerName)
ServiceLocator.get<Gateway>()
```

as a way to hide their dependencies.

Provider discovery and session access required by a feature belong behind the bounded metadata-provider gateway architecture defined by SPEC-BE-010. Provider selection and cross-provider fallback remain explicit application policy/workflow responsibilities; a generic service-layer locator remains prohibited.

## 20. Runtime Port

Application services interact with runtime functionality only through explicit stable runtime ports.

A runtime port may expose narrowly scoped capabilities such as:

- background operation admission
- cancellation requests
- runtime operation context access
- readiness/admission capabilities where required internally
- operation-scoped event collector access

It must not expose:

- concrete schedulers
- thread pools
- raw executor handles
- runtime lifecycle internals
- mutable global runtime state

## 21. Runtime Ownership Rule

The ownership split is:

> The runtime owns execution; application services own application intent and orchestration.

Application services decide:

- what application operation is being performed
- what business steps are required
- what repositories/gateways are needed
- what authoritative mutation should occur

Runtime decides:

- admission
- operation context
- cancellation plumbing
- execution resources
- background scheduling
- post-commit event publication

## 22. Application Request Contracts

Application service methods accept application-owned immutable request contracts.

Examples:

```text
GetAppearanceSettingsQuery
UpdateAppearanceSettingsCommand
ExportDiagnosticsCommand
```

Rules:

1. Request contracts are defined in the application layer.
2. Request contracts are immutable values.
3. Request contracts describe application intent.
4. Request contracts contain no bridge/transport metadata unless that metadata is itself an application concept.
5. Request contracts contain no database or provider implementation objects.

## 23. Bridge Mapping Boundary

Bridge request DTOs are mapped explicitly into application request contracts.

Required direction:

```text
UpdateAppearanceSettingsRequestDto
    ↓ bridge mapping
UpdateAppearanceSettingsCommand
    ↓
SettingsService
```

Application services never accept bridge DTOs directly.

Application service outputs are mapped by the bridge into canonical DTOs defined by SPEC-BE-008.

This preserves independent transport and application contract evolution.

## 24. Application Result Contract

Every application service operation returns conceptually:

```text
Result<T, ApplicationError>
```

where `T` is the operation-specific application success type.

Rules:

1. `ApplicationError` is the sole stable application failure envelope.
2. Services do not return `BridgeResult<T>`.
3. Services do not return transport-specific error types.
4. Internal/domain/infrastructure failures are translated before crossing the service boundary.
5. Success types are domain/application concepts, never bridge DTOs.

Operation-specific result values are allowed when an operation genuinely has structured success semantics.

## 25. Query Operations

Read-only application operations:

- are idempotent with respect to authoritative application state
- do not create authoritative side effects
- do not publish application events
- do not create a Unit of Work by default
- may use read-only repository/query ports
- return immutable application values or collections

Observability side effects such as logs/metrics do not violate query semantics.

## 26. Authoritative Mutation Operations

An authoritative mutating application capability owns its transaction boundary, and its focused command/use-case handler executes that boundary beneath the application service façade.

Conceptually:

```text
Application Service Façade
    ↓
Focused Command / Use-Case Handler
    ↓
Create UnitOfWork
    ↓
Validate / load / execute domain logic
    ↓
Acquire ephemeral transaction-bound repositories
    ↓
Persist authoritative mutation
    ↓
Record pending events
    ↓
Commit UnitOfWork
    ↓
Return committed outcome to runtime/service façade
```

Rules:

1. The focused mutating operation handler owns Unit of Work lifetime for the capability.
2. The service façade exposes the capability but does not create a competing transaction/orchestration layer around the handler.
3. The Unit of Work is not reused across unrelated operations.
4. The operation returns success only after commit succeeds.
5. Repository implementations never commit independently.
6. Failure before commit results in rollback according to SPEC-BE-002.

## 27. One Commit Boundary by Default

An authoritative mutation uses exactly one Unit of Work/commit boundary by default.

This keeps operations atomic and easy to reason about.

A later operation-specific specification may define multiple durable checkpoints for long-running background work.

Such an exception must explicitly define:

- checkpoint boundaries
- rollback scope
- event association
- cancellation behavior
- crash recovery expectations

Implicit multi-commit behavior inside a normal application service method is prohibited.

## 28. Background Operation Checkpoints

Long-running operations admitted through SPEC-BE-004 follow the same mutation rules at each durable checkpoint.

Conceptually:

```text
Background workflow
    ↓
Checkpoint A
    ├── UnitOfWork
    ├── commit
    └── associated events become publishable
    ↓
Checkpoint B
    ├── UnitOfWork
    ├── commit
    └── associated events become publishable
```

A background coordinator must not hold one database transaction open across arbitrary long-running provider/filesystem/CPU work unless explicitly justified by a later specification.

## 29. Event Semantic Ownership

Application services own the semantic decision that an application event occurred.

A service operation may:

- construct an immutable event
- record it into the operation-scoped `EventCollector`

A service operation must not:

- call `EventBus.publish` directly
- publish before commit
- publish from repository code
- treat publication as part of persistence implementation

## 30. Runtime-Owned Event Publication

SPEC-BE-006 remains authoritative for publication.

Required flow:

```text
Application Service
    ↓ records pending event
UnitOfWork commits
    ↓
ApplicationRuntime observes committed outcome
    ↓
ApplicationRuntime releases pending events
    ↓
EventBus routes events
```

The ownership invariant is:

> Application services own event semantics and recording; `ApplicationRuntime` owns post-commit publication.

## 31. Event Failure Semantics

If an application mutation fails or rolls back:

- pending events from that mutation are not published
- service returns an `ApplicationError`

If event delivery fails after commit:

- authoritative state remains committed
- the service operation's committed success is not reversed
- runtime/event infrastructure observes delivery failure according to SPEC-BE-006

## 32. Application Error Translation

A service boundary may expose only `ApplicationError` failures.

Internal errors from:

- repositories
- gateways
- domain logic
- runtime ports
- approved infrastructure ports

must be translated into the stable error catalog before they escape the application service operation.

A service must not leak implementation-specific error strings or concrete error types to transport callers.

## 33. Cancellation

Cancellation behavior follows SPEC-BE-004.

Application services must:

- honor operation cancellation at safe boundaries
- avoid beginning new authoritative work after cancellation has become terminal for the operation
- preserve transaction atomicity
- never convert committed authoritative success into cancellation after the commit boundary

Operation-specific specifications define finer cancellation semantics where needed.

## 34. Concurrency

Application services must be safe under the concurrency policy owned by SPEC-BE-004.

Services do not implement private thread pools or schedulers.

Shared mutable service state should not be introduced to serialize operations. Logical resource classes, runtime admission, persistence serialization, and gateway policy own concurrency control.

## 35. Observability

Application service operations participate in SPEC-BE-003 operation observability.

Services may emit structured diagnostic events through approved observability abstractions supplied by the operation/runtime environment.

They must not depend directly on concrete logging frameworks as public service dependencies.

Application operation names should be stable and suitable for structured logging/trace event fields.

## 36. Phase 000 Service Catalog

Phase 000 requires application capabilities sufficient for the currently specified backend foundation.

Conceptually:

```text
SettingsService
DiagnosticsService
```

Runtime/startup/recovery capabilities may be exposed through runtime/application host ports rather than forcing all lifecycle operations into ordinary application services, consistent with SPEC-BE-004 and SPEC-BE-007.

Future feature services may include:

```text
LibraryService
ProviderService
MetadataService
```

Their exact catalogs are owned by later feature specifications.

## 37. Phase 000 `SettingsService`

`SettingsService` exposes:

```text
GetAppearanceSettingsQuery
UpdateAppearanceSettingsCommand
```

The focused query/command handlers remain the operation executors beneath the thin service façade, consistent with SPEC-BE-005.

### Get

- read-only
- no Unit of Work by default
- no application events
- returns authoritative `AppearanceSettings`

### Update

- focused command handler owns one Unit of Work
- service façade delegates the capability without creating a second transaction boundary
- validates the complete desired aggregate
- loads current state as required
- persists only a semantic change
- records `AppearanceSettingsChanged` only for a committed semantic change
- returns `Result<(), ApplicationError>`

SPEC-BE-005 remains authoritative for appearance-settings semantics.

## 38. Phase 000 Diagnostics Capability

Diagnostics application capabilities expose sanitized diagnostic actions without leaking filesystem/archive implementation details.

Examples may include:

```text
ExportDiagnosticsCommand
GetTechnicalDetailsQuery
OpenDataDirectoryCommand
```

Depending on platform/application architecture, `OpenDataDirectory` may be represented through a platform gateway rather than direct filesystem APIs.

All outputs remain constrained by SPEC-BE-003 privacy/redaction rules.

## 39. Application Service vs Bridge Service

Bridge services and application services are conceptually aligned but not identical types.

Example:

```text
SettingsBridge
    ↓ maps DTOs
SettingsService
```

The bridge owns:

- request/response DTO mapping
- `BridgeResult<T>` projection
- generated binding integration

The application service/application operation layer owns:

- application request contract
- capability façade
- focused use-case handler orchestration
- operation transaction semantics
- application error result
- event semantics

For mutating capabilities, the focused handler executes the Unit of Work boundary; the service façade does not duplicate that responsibility.

Neither layer absorbs the other's responsibilities.

## 40. Technology-Neutral Contracts

Application service public contracts must not expose concrete technologies.

Prohibited concepts include:

```text
SqliteSettingsService
TokioLibraryService
FlutterSettingsCommand
ReqwestMetadataService
FrbApplicationService
```

Preferred concepts include:

```text
SettingsService
UpdateAppearanceSettingsCommand
MetadataProviderRegistry
ProviderSelectionPolicy
RuntimePort
```

Implementation technology remains behind ports.

## 41. Crate Ownership

Ownership follows SPEC-BE-001.

### `argus-domain`

Owns pure domain concepts and rules.

It does not depend on application services.

### `argus-application`

Owns:

- application service traits/types where public abstraction is required
- concrete application service orchestration where appropriate
- application command/query request types
- application result types
- application-facing repository/gateway/runtime ports when ownership belongs at this layer
- cross-domain workflow coordinators

### `argus-runtime`

Owns:

- operation admission/execution
- runtime ports/implementations
- operation context
- cancellation plumbing
- post-commit event publication

It does not own feature business semantics.

### `argus-infrastructure`

Owns concrete repository/gateway/platform implementations.

It does not own application service operation semantics.

### `argus-bridge`

Owns transport mapping and invokes application service/runtime capabilities.

It does not implement application use cases.

## 42. Dependency Direction

Required conceptual direction:

```text
bridge/adapters
    ↓
application services/coordinators
    ↓
application-facing ports + domain
    ↑
infrastructure implementations
```

Runtime integration remains explicit and follows SPEC-BE-001 dependency direction rather than allowing arbitrary cyclic crate dependencies.

## 43. Architecture Tests

Architecture checks should enforce where practical:

- application service modules do not import bridge DTO/generated modules
- application services do not import concrete infrastructure packages
- application services do not import other application service implementations
- domain does not depend on application services
- repositories do not depend on application services
- gateway implementations do not call application services directly

Compile-time crate boundaries are preferred over convention-only enforcement.

## 44. Unit Testing Requirements

Each application service operation must be testable without:

- Flutter
- generated bridge bindings
- a running production runtime
- real provider network access
- concrete filesystem APIs

Tests use fakes/mocks/test implementations of explicit ports.

Required cases include:

- successful operation
- application validation failure
- repository/gateway failure mapping
- transaction commit failure
- rollback behavior
- cancellation at applicable boundaries
- event recording semantics

## 45. Transaction Tests

Mutating service tests must verify:

- exactly one Unit of Work by default
- commit only after successful business/persistence steps
- no success before commit
- rollback/no commit on failure
- multiple repository mutations share the same Unit of Work when atomicity requires it
- repositories do not commit themselves

## 46. Event Tests

Mutating service tests must verify:

- semantic event created only when appropriate
- event recorded before runtime publication
- semantic no-op records no event where specified
- rollback leaves no publishable event
- service never calls event bus publication directly
- runtime post-commit integration publishes recorded events according to SPEC-BE-006

## 47. Dependency Tests

Tests or architecture lints must verify:

- explicit independent query-interface and Unit of Work factory dependencies
- ephemeral write-repository acquisition only through the active Unit of Work
- explicit gateway dependencies
- no repository/gateway service locator
- no direct application service dependency
- immutable service composition after startup
- stale service instances are not reused across runtime generations

## 48. Bridge Boundary Tests

Verify:

- bridge request DTO maps into an application command/query
- application service receives no DTO type
- service returns application model/error
- bridge maps the result to canonical DTO / `BridgeResult<T>`
- generated bridge changes do not alter service signatures

## 49. Phase 000 Minimum Implementation

Phase 000 implements only the application service infrastructure required for its existing capabilities:

- runtime-scoped service composition
- explicit application request types
- `Result<T, ApplicationError>` service result convention
- `SettingsService` read/update capabilities
- required diagnostics application capabilities
- explicit query/runtime/platform and Unit of Work factory dependencies
- focused handler Unit of Work ownership for settings mutation
- operation-scoped event recording
- architecture tests preventing bridge/infrastructure leakage

Phase 000 does not need empty placeholder services for future library/provider/metadata domains.

## 50. Acceptance Criteria

SPEC-BE-009 is satisfied when:

1. Application services expose explicitly named application capabilities.
2. Every operation has exactly one owning service/coordinator.
3. Application services do not depend directly on other application services.
4. Genuine cross-domain workflows use explicit coordinators.
5. Services are runtime-scoped and never reused across runtime generations.
6. Service dependencies are immutable after construction.
7. Services retain no authoritative mutable application state.
8. Service dependencies are restricted to approved stable ports.
9. Independent query-interface and Unit of Work factory dependencies are explicit.
10. Transaction-bound write repositories are acquired ephemerally from the active Unit of Work and are never stored on services.
11. Focused operation handlers may use multiple transaction-bound repositories when required by one owned capability.
12. Repositories do not coordinate each other or commit independently.
13. Gateway dependencies are explicit abstractions rather than concrete provider implementations.
14. Service locators, repository registries, and gateway registries are not used to hide dependencies.
15. Runtime interaction occurs only through stable runtime ports/capabilities.
16. Runtime owns execution; services own application intent/orchestration.
17. Application request contracts are immutable and application-owned.
18. Bridge DTOs never appear in application service signatures.
19. Every service operation returns `Result<T, ApplicationError>` conceptually.
20. Queries do not perform authoritative mutations or publish events.
21. Authoritative mutating capabilities use one Unit of Work by default, executed by the focused operation handler beneath the service façade.
22. Multiple durable checkpoints require explicit operation-specific specification.
23. Application services/handlers own event semantics and event recording.
24. Application services/handlers never publish directly to `EventBus`.
25. `ApplicationRuntime` owns post-commit publication.
26. Failed/rolled-back mutations leave no publishable events.
27. Application services expose no concrete persistence, network, async-runtime, filesystem, logging, bridge, or provider implementation types.
28. Phase 000 settings and diagnostics capabilities conform to this contract.
29. Unit, architecture, transaction, event, dependency, and bridge-boundary tests cover the required behavior.

## 51. Prohibited Patterns

- application service-to-service dependency graphs
- service locator usage
- generic `Execute`/`Invoke` service APIs
- CRUD-only naming where domain/application intent exists
- process-global application service singletons
- service instances reused after runtime replacement
- mutable authoritative caches inside application services
- hidden query/gateway resolution or long-lived storage of transaction-bound repositories
- concrete SQLite/HTTP/filesystem/provider SDK dependencies in service code
- bridge DTOs in application service signatures
- `BridgeResult<T>` returned by application services
- repositories committing transactions
- Unit of Work automatically publishing events
- application services directly publishing events
- runtime implementing feature business semantics
- long-lived transactions across arbitrary background external work without explicit specification
- application-layer logging-framework implementation dependencies

## 52. Out of Scope

This specification does not finalize:

- exact Rust trait vs struct representation for every service
- exact module/file layout
- dependency-injection framework choice
- provider gateway architecture details
- library/metadata/import service catalogs
- authentication/authorization services
- distributed transactions
- remote RPC/service deployment
- frontend-focused API wrapper design

## 53. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](spec-be-005-settings-service-and-appearance-settings.md)
- [SPEC-BE-006 — Minimal Domain Event Bus](spec-be-006-minimal-domain-event-bus.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-010 — Provider Gateway Architecture](spec-be-010-provider-gateway-architecture.md)
- [Backend Specifications Index](README.md)
