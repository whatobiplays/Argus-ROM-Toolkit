# Application Errors, Logging, Diagnostics, and Observability Specification

**Document ID:** SPEC-BE-003  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-11  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-001, SPEC-BE-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative backend contracts for application errors, structured logging, execution trace events, trace identity, metrics, subsystem health, diagnostic bundles, redaction, and observability behavior in Argus ROM Toolkit.

The design provides stable machine-readable failures to Flutter while preserving technical detail inside the backend, gives every top-level operation one consistent `trace_id`, and ensures diagnostics remain useful without exposing secrets or user data. It refines ARCH-001's operation-linking requirement by standardizing on OpenTelemetry terminology where practical.

## 2. Scope

This specification covers:

- layer-specific internal error ownership
- the stable `ApplicationError` envelope
- versioned published error codes
- error category, severity, recoverability, and retry semantics
- error translation at architectural boundaries
- top-level operation identity and `TraceId` propagation
- identity-first observability
- structured `LogEvent` contracts
- separate execution-oriented `TraceEvent` contracts
- metric and performance instrumentation requirements
- startup and shutdown logging
- subsystem and provider health reporting
- user-initiated diagnostic ZIP bundles
- redaction and path-sanitization policy
- crate ownership and testing requirements

## 3. Non-Responsibilities

This specification does not define:

- Flutter-facing error DTO layout or recovery-action presentation
- runtime command dispatch, executor topology, or background-job scheduling
- exact retry delays, jitter, retry budgets, or circuit-breaker algorithms
- a distributed tracing backend
- OpenTelemetry span creation during Phase 000 or MVP
- remote telemetry upload
- analytics collection
- a durable general-purpose event log
- provider-specific error catalogs beyond shared contract rules
- final log-retention durations or rotation sizes

Those concerns belong to later bridge, runtime, provider, deployment, or implementation specifications.

## 4. Architectural Principles

1. Each architectural layer owns errors expressed in its own vocabulary.
2. Internal errors never cross an architectural boundary directly.
3. `ApplicationError` is the only stable cross-application failure envelope.
4. Published error codes are immutable, versioned API contracts.
5. Error category, application severity, recoverability, and retry policy are independent dimensions.
6. User-facing localization is selected through `MessageKey`; backend technical messages are not UI contracts.
7. Safe context is allowlisted by error code and contains only bounded, non-secret values.
8. Every top-level operation receives exactly one non-zero `TraceId`.
9. All logs, trace events, metric observations, health checks, and returned `ApplicationError` values for an operation inherit that operation's `trace_id`.
10. Once an Argus-owned entity identifier exists, it is the canonical observability identifier for that entity.
11. `LogEvent` and `TraceEvent` are different contracts with different purposes.
12. A single failure produces exactly one primary `Error` log.
13. Propagation between layers does not duplicate error logs.
14. Diagnostic export is user initiated, sanitized by construction, and independently versioned.
15. Secrets and user data are excluded by default rather than removed after collection.
16. Performance instrumentation must not introduce unbounded metric cardinality.
17. Observability must remain useful when no external collector is configured.

## 5. Error Ownership by Layer

### 5.1 Domain errors

`argus-domain` owns errors produced by domain rules and value objects, such as:

- invalid value construction
- violated aggregate invariants
- unsupported domain transitions
- domain policy rejection

Domain errors contain domain meaning only. They do not contain SQL errors, filesystem paths, HTTP status bodies, logging dependencies, `ApplicationError`, or bridge DTOs.

### 5.2 Application errors and port errors

`argus-application` owns:

- `ApplicationError`
- `ErrorCode`
- error categories and policy enums
- application-facing port errors
- use-case-specific validation and operation errors
- mapping contracts from domain and port errors into `ApplicationError`

Port errors use the vocabulary of the capability exposed by the port. Representative types include:

```text
PersistenceError
SourceAccessError
FilesystemError
ProviderError
ConfigurationError
RuntimeError
OperationError
```

`SourceAccessError` is the stable port-error family for configured library-source access. `FilesystemError` remains appropriate for non-library filesystem capabilities such as application-data or diagnostic-artifact I/O. Metadata/external-service provider failures use `ProviderError`; source/storage provider failures do not.

Port errors are stable enough for application orchestration but are not published directly to Flutter.

### 5.3 Infrastructure errors

`argus-infrastructure` owns technical adapter errors, including:

- `rusqlite` failures and SQLite result codes
- migration checksum details
- operating-system I/O failures
- archive and filesystem adapter failures
- HTTP client and provider protocol failures
- credential-store adapter failures
- log-sink and archive-writer failures

Infrastructure may retain a technical source chain for diagnostics. Before an error leaves infrastructure, it is translated to the applicable application port error. Infrastructure types and third-party error types never escape through application ports.

### 5.4 Runtime errors

`argus-runtime` owns composition and lifecycle failures, including:

- startup phase failure
- shutdown coordination failure
- executor admission or drain failure
- panic containment outcomes
- operation-context creation failure
- top-level application-error mapping for runtime-owned operations

Runtime is normally the boundary that records the primary failure log and returns the final `ApplicationError` to the bridge.

### 5.5 Bridge errors

`argus-bridge` maps `ApplicationError` into dedicated bridge DTOs. It must not:

- inspect infrastructure errors
- construct published error semantics independently
- include raw Rust error strings or source chains
- reinterpret retry or recovery policy
- expose stack traces by default

## 6. Boundary Translation Rules

Errors are translated exactly once at each boundary:

```text
technical adapter error
    -> application port error
    -> use-case/runtime error
    -> ApplicationError
    -> bridge error DTO
```

Required rules:

1. A lower layer returns an error; it does not log the same failure at `Error` merely because the error is being propagated.
2. Translation preserves the original technical error as an internal source where safe and useful.
3. Translation adds only context owned by the translating layer.
4. Unknown third-party errors map to a stable internal or capability-specific fallback code.
5. No mapping may expose SQL text, absolute user paths, credentials, authorization material, provider response bodies, ROM content, or arbitrary serialized input.
6. The top-level operation boundary creates the published `ApplicationError`, records the one primary error log, and returns the envelope.
7. Cleanup failures that occur while handling a primary failure are separate secondary failures. They may produce their own error log marked `failure_role=secondary`, but they must not duplicate the primary failure.

## 7. Stable `ApplicationError` Contract

The conceptual application contract is:

```rust
pub struct ApplicationError {
    pub code: ErrorCode,
    pub category: ErrorCategory,
    pub severity: ApplicationSeverity,
    pub recoverability: Recoverability,
    pub retry_policy: RetryPolicy,
    pub message_key: MessageKey,
    pub trace_id: TraceId,
    pub safe_context: SafeContext,
}
```

Exact Rust module paths and serialization derives are implementation decisions, but field semantics are fixed by this specification.

### 7.1 `ErrorCode`

A stable, machine-readable, versioned identifier. Clients branch on this field when code-specific behavior is required.

### 7.2 `ErrorCategory`

A broad stable classification used for filtering, fallback presentation, and diagnostics. It is not a substitute for `ErrorCode`.

### 7.3 `ApplicationSeverity`

The application impact of the failure. It is independent from log level and recoverability.

### 7.4 `Recoverability`

The kind of recovery required to make progress. It does not imply whether retry is automatic.

### 7.5 `RetryPolicy`

The stable retry strategy exposed by the application contract. Exact timing and budgets remain runtime policy.

### 7.6 `MessageKey`

A stable localization key, such as:

```text
errors.persistence.database_locked
errors.configuration.invalid
errors.internal.unexpected
```

The backend does not use localized text as a contract. Message-template parameters must come only from `SafeContext` keys explicitly allowed for that message.

### 7.7 `TraceId`

The identifier of the top-level operation that produced the error. It is always present and non-zero.

### 7.8 `SafeContext`

A bounded immutable map of allowlisted diagnostic and presentation-safe values. It is not a general JSON payload.

Allowed value classes are:

- booleans
- bounded integers
- bounded decimal values
- stable enum strings
- bounded non-sensitive strings
- Argus-owned typed identifiers serialized through their canonical representation
- sanitized technical identifiers explicitly permitted by the error-code definition

Collections, nested arbitrary objects, raw exception strings, raw paths, provider payloads, and unbounded text are prohibited.

## 8. Published Error-Code Contract

### 8.1 Format

Published codes use:

```text
ARGUS.V<major>.<CATEGORY>.<NAME>
```

Examples:

```text
ARGUS.V1.VALIDATION.INVALID_ARGUMENT
ARGUS.V1.PERSISTENCE.DATABASE_LOCKED
ARGUS.V1.RUNTIME.STARTUP_FAILED
ARGUS.V1.INTERNAL.UNEXPECTED
```

Rules:

- `ARGUS` and `V<major>` are fixed namespace and contract-major components.
- `<CATEGORY>` matches one declared error category.
- `<NAME>` is uppercase snake case and describes stable semantics rather than implementation technology.
- Codes are unique across the application.
- A published code is never reused for different semantics.
- A spelling or semantic correction that could affect clients requires a new code.
- Breaking catalog restructuring requires a new contract major.
- Removal of a code requires a deprecation period and a documented replacement where applicable.

### 8.2 Catalog entry

Every published code has one authoritative catalog entry defining:

- category
- default severity
- recoverability
- retry policy
- message key
- allowed safe-context keys and value types
- whether the code is valid during startup
- whether the code may cross the bridge
- replacement code when deprecated

The catalog is code-reviewed and covered by a deterministic snapshot or equivalent contract test. Error policy must not be reconstructed independently in multiple layers.

### 8.3 Phase 000 minimum catalog

Phase 000 must publish at least the following contracts:

| Error Code | Category | Severity | Recoverability | Retry Policy | Message Key |
|---|---|---|---|---|---|
| `ARGUS.V1.VALIDATION.INVALID_ARGUMENT` | Validation | Warning | UserAction | Never | `errors.validation.invalid_argument` |
| `ARGUS.V1.CONFIGURATION.INVALID` | Configuration | Error | UserAction | Never | `errors.configuration.invalid` |
| `ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID` | Configuration | Error | UserAction | UserInitiated | `errors.configuration.persisted_settings_invalid` |
| `ARGUS.V1.PERSISTENCE.DATABASE_OPEN_FAILED` | Persistence | Error | Retry | Backoff | `errors.persistence.database_open_failed` |
| `ARGUS.V1.PERSISTENCE.DATABASE_LOCKED` | Persistence | Warning | Retry | Backoff | `errors.persistence.database_locked` |
| `ARGUS.V1.PERSISTENCE.MIGRATION_FAILED` | Persistence | Error | ManualIntervention | UserInitiated | `errors.persistence.migration_failed` |
| `ARGUS.V1.PERSISTENCE.INCOMPATIBLE_SCHEMA` | Persistence | Error | ManualIntervention | Never | `errors.persistence.incompatible_schema` |
| `ARGUS.V1.FILESYSTEM.PERMISSION_DENIED` | Filesystem | Error | UserAction | UserInitiated | `errors.filesystem.permission_denied` |
| `ARGUS.V1.RUNTIME.BRIDGE_INITIALIZATION_FAILED` | Runtime | Error | RestartRequired | UserInitiated | `errors.runtime.bridge_initialization_failed` |
| `ARGUS.V1.RUNTIME.CORE_SERVICE_INITIALIZATION_FAILED` | Runtime | Error | RestartRequired | UserInitiated | `errors.runtime.core_service_initialization_failed` |
| `ARGUS.V1.RUNTIME.NOT_READY` | Runtime | Warning | Retry | UserInitiated | `errors.runtime.not_ready` |
| `ARGUS.V1.RUNTIME.STARTUP_FAILED` | Runtime | Error | RestartRequired | UserInitiated | `errors.runtime.startup_failed` |
| `ARGUS.V1.RUNTIME.SHUTTING_DOWN` | Runtime | Warning | RestartRequired | UserInitiated | `errors.runtime.shutting_down` |
| `ARGUS.V1.RUNTIME.STOPPED` | Runtime | Warning | RestartRequired | UserInitiated | `errors.runtime.stopped` |
| `ARGUS.V1.RUNTIME.STALE_INSTANCE` | Runtime | Warning | UserAction | Never | `errors.runtime.stale_instance` |
| `ARGUS.V1.OPERATION.CANCELLED` | Operation | Info | None | Never | `errors.operation.cancelled` |
| `ARGUS.V1.INTERNAL.UNEXPECTED` | Internal | Error | ManualIntervention | Never | `errors.internal.unexpected` |
| `ARGUS.V1.INTERNAL.INVARIANT_VIOLATION` | Internal | Fatal | RestartRequired | Never | `errors.internal.invariant_violation` |

Runtime admission uses the lifecycle-specific codes above rather than a generic internal fallback. `NOT_READY` applies while a constructed runtime has not reached readiness, `STARTUP_FAILED` applies when normal work targets a failed generation, `SHUTTING_DOWN` and `STOPPED` preserve terminal lifecycle meaning, and pre-admission cancellation uses `ARGUS.V1.OPERATION.CANCELLED`.

`ARGUS.V1.RUNTIME.STALE_INSTANCE` is returned when a generation-bound request references a retired or non-current `RuntimeInstanceId`. The caller re-queries authoritative runtime state and does not replay the stale action automatically.

`ARGUS.V1.RUNTIME.BRIDGE_INITIALIZATION_FAILED` is valid only when the call reached a reportable backend host and backend-side bridge adapter/composition failed. Failure to load the native library, generated bindings, marshalling contract, or transport before `ApplicationError` delivery is possible belongs to the frontend `TransportFailure` boundary and is not mapped into this catalog.

### 8.4 Later-MVP background-admission extension

This catalog entry is reserved by the Ready runtime contract but is not Phase 000 implementation scope:

| Error Code | Category | Severity | Recoverability | Retry Policy | Message Key |
|---|---|---|---|---|---|
| `ARGUS.V1.OPERATION.CAPACITY_UNAVAILABLE` | Operation | Warning | Retry | UserInitiated | `errors.operation.capacity_unavailable` |

Later specifications add codes through the same catalog rules rather than creating parallel error enums.

## 9. Error Categories

The only top-level categories are:

```text
Validation
Persistence
Filesystem
Provider
Runtime
Configuration
Operation
Internal
```

Semantics:

- **Validation:** Input or requested state is invalid before the operation can proceed.
- **Persistence:** Database availability, transaction, query, migration, or persisted-integrity failure.
- **Filesystem:** Local or provider-backed filesystem access failure not better represented as a provider protocol failure.
- **Provider:** External provider readiness, transport, protocol, authentication, throttling, or remote-service failure.
- **Runtime:** Application lifecycle, executor, dispatch, composition, bridge initialization, or runtime coordination failure.
- **Configuration:** Invalid, missing, unsupported, or incompatible application configuration.
- **Operation:** Cancellation, conflict, unsupported operation state, or failure intrinsic to application workflow orchestration.
- **Internal:** Unexpected defects, impossible states, invariant violations, or failures with no safe narrower classification.

Categories are stable and serialized using lower snake case at external boundaries unless the bridge specification explicitly requires another representation.

## 10. Application Severity

Severity values are:

```text
Info
Warning
Error
Fatal
```

Definitions:

- **Info:** An expected non-success outcome that does not indicate application degradation, such as acknowledged cancellation.
- **Warning:** The requested operation did not complete or completed with a recoverable limitation, while the application remains usable.
- **Error:** A significant operation or subsystem failed, but the process can still report and coordinate recovery safely.
- **Fatal:** Continued operation is unsafe or impossible for the affected process/runtime instance.

Severity is not a logging level. An `ApplicationError` with severity `Warning` may still produce the one primary `Error` log when an operation fails. Conversely, an informational cancellation may be logged at `Info`.

Severity is also independent from recoverability. A fatal failure may be restartable, and a non-fatal error may require manual intervention.

## 11. Recoverability

Recoverability values are:

```text
None
Retry
UserAction
RestartRequired
ManualIntervention
```

Definitions:

- **None:** No recovery action is needed or applicable for the completed outcome.
- **Retry:** Repeating the operation may succeed without changing user configuration or application state.
- **UserAction:** The user must change input, permissions, configuration, availability, or another actionable condition.
- **RestartRequired:** A new runtime instance is required before the operation can succeed safely.
- **ManualIntervention:** Recovery requires support, repair, upgrade, data restoration, or another deliberate technical intervention.

Recovery actions presented by Flutter are defined by the bridge and frontend specifications. They must be derived from the published contract rather than inferred from raw messages.

## 12. Retry Policy

Retry policy values are:

```text
Never
Immediate
Backoff
UserInitiated
```

Definitions:

- **Never:** The runtime must not automatically repeat the failed operation.
- **Immediate:** The runtime may repeat the operation without delay according to a bounded runtime policy.
- **Backoff:** The runtime may repeat the operation using bounded delay, jitter, and attempt limits.
- **UserInitiated:** The operation is retried only after an explicit user action.

Rules:

1. Retry loops are always bounded.
2. Published `ApplicationError.RetryPolicy` governs repetition of the failed application operation; it does not govern transparent retries internal to one provider interaction.
3. For runtime-owned application-operation retries, timing, jitter, maximum attempts, and capability-specific budgets are runtime policy and may evolve without changing the application contract.
4. Provider-internal same-provider transport retries are a separate provider-infrastructure policy defined by SPEC-BE-004 and SPEC-BE-010 and are exhausted before a terminal `ProviderError` reaches application workflow logic.
5. Automatic application-operation retries remain part of the same top-level operation and retain the same `trace_id`.
6. A user-initiated retry is a new top-level operation and receives a new `trace_id`.
7. A durable commit must never be reported as cancelled or failed because cancellation arrived after the commit boundary.
8. Provider-owned request retries and runtime-owned application-operation retries must not nest into unbounded multiplicative retry behavior.

## 13. Trace Identity and Operation Context

### 13.1 `TraceId`

Argus uses OpenTelemetry-compatible trace identifiers:

- 128 bits
- non-zero
- serialized as 32 lowercase hexadecimal characters
- generated by the backend at the start of each top-level operation

The field name is always `trace_id`. The field name `correlation_id` is prohibited in new backend contracts, logs, metrics, diagnostic schemas, and bridge mappings.

### 13.2 Top-level operations

Top-level operations include:

- application startup
- application shutdown
- each bridge command or query
- diagnostic export
- explicit health collection
- each independently executed background operation or persisted job run

An accepted command and its later independently executed job are separate top-level operations. They are linked through Argus-owned identifiers such as `CommandId` and `JobRunId`, not by reusing one trace indefinitely.

### 13.3 Operation context

The conceptual context is:

```rust
pub struct OperationContext {
    pub trace_id: TraceId,
    pub subsystem: SubsystemName,
    pub operation: OperationName,
}
```

Rules:

- Runtime creates the context.
- Child work inherits the same `TraceId` while it remains part of the same top-level operation.
- Async queues, executor submissions, database work items, provider calls, and filesystem work explicitly carry or reconstruct the operation context from a typed envelope.
- Task-local logging context may be used as an implementation aid, but correctness must not depend solely on ambient task-local state.
- A missing context at an internal boundary is an observability defect and must be testable.
- `TraceId` is observability identity, not a domain entity ID or database primary key.

### 13.4 No spans during Phase 000 or MVP

Argus does not create OpenTelemetry spans during Phase 000 or MVP unless a concrete need is approved through an update to this specification.

Execution visibility is provided by `TraceEvent`, structured logs, and duration metrics. This keeps the contract simple while preserving a future migration path to spans.

## 14. Identity-First Observability Invariant

Once an Argus-owned identifier exists, it becomes the canonical identifier for that entity in:

- logs
- trace events
- metric exemplars or structured metric context
- diagnostics
- health reporting

Examples include:

```text
LibrarySourceId
LibraryRootId
SourceEntryId
GameContentId
JobRunId
ScanRunId
ProviderId
CommandId
```

Required rules:

1. Prefer Argus entity IDs over filenames, ROM names, filesystem paths, hashes, provider-native IDs, and display text.
2. External identifiers are permitted only before Argus identity assignment or when explicitly required to diagnose an integration.
3. When an external identifier is recorded, its field name must identify its namespace and its inclusion must be allowlisted.
4. Provider-native IDs never replace `ProviderId` or Argus entity IDs after mapping exists.
5. A content hash is not used as an entity identifier in observability when `GameContentId` or `HashRecordId` exists.
6. Metrics must not place unbounded entity IDs in ordinary aggregation labels. When supported, the `trace_id` and relevant Argus IDs may be attached as exemplars or structured observation context.
7. Diagnostic summaries may include Argus IDs without including the associated user-facing names or paths.

This invariant is mandatory for every later backend specification.

## 15. Structured Logging Contract

### 15.1 Required fields

Every `LogEvent` contains:

```text
timestamp
level
trace_id
subsystem
operation
event_name
fields
application_error optional
```

Field semantics:

- `timestamp`: UTC timestamp generated at emission time.
- `level`: traditional logging level.
- `trace_id`: current operation trace identifier.
- `subsystem`: stable low-cardinality subsystem name.
- `operation`: stable low-cardinality operation name.
- `event_name`: stable dot-separated event name.
- `fields`: bounded structured fields that pass redaction policy.
- `application_error`: the published envelope when the event records a mapped application failure.

### 15.2 Logging levels

Logging levels are:

```text
Trace
Debug
Info
Warn
Error
```

They describe diagnostic importance and sink filtering. They do not replace `ApplicationSeverity`.

### 15.3 Event names

Event names use lowercase dot-separated identifiers:

```text
runtime.started
database.migration.completed
scan.started
provider.request.completed
```

Rules:

- Event names describe facts, not prose.
- Names remain stable after release.
- Dynamic values never appear inside the event name.
- Dynamic values belong in structured fields.
- Renaming a widely consumed event requires a compatibility plan.

### 15.4 Field conventions

- Field names use lower snake case.
- Durations in logs use `*_duration_ms` or `duration_ms`.
- Counts use explicit nouns such as `migration_count` or `outstanding_operation_count`.
- Outcomes use stable enums such as `success`, `failed`, `cancelled`, or `rejected`.
- Argus IDs use their canonical field names, such as `job_run_id` or `game_content_id`.
- Free-form message text is optional and must not carry the only copy of machine-relevant information.

## 16. Error Logging and Propagation

### 16.1 One primary error log

A single failed top-level operation produces exactly one primary `Error` log.

The primary log is emitted by the boundary that owns the operation outcome, normally runtime or the top-level application handler. It includes:

- `trace_id`
- stable event name
- operation and subsystem
- final `ApplicationError`
- safe Argus identifiers
- sanitized internal error classification
- bounded source-chain detail where policy permits
- `failure_role=primary`

### 16.2 Lower-layer behavior

Lower layers:

- return errors upward
- may emit `Trace` or `Debug` events for attempted work
- may emit `Warn` for a recovered condition that is not the final operation failure
- do not emit duplicate `Error` logs for normal propagation

### 16.3 Retry behavior

Failed retry attempts may be logged at `Warn` with attempt metadata. The final exhausted failure produces the one primary `Error` log. Successful retries produce completion diagnostics without an error log for the final operation outcome.

### 16.4 Panics and invariant violations

A contained panic or invariant violation is mapped to an internal error when the process remains able to report safely. The primary log may include a sanitized backtrace in local diagnostic storage when enabled, but backtraces are excluded from user-facing errors and diagnostic bundles by default.

## 17. Trace Events

`TraceEvent` represents execution. `LogEvent` represents human diagnostics. They are separate types and may use separate sinks.

The conceptual trace event is:

```text
TraceEvent
- timestamp
- trace_id
- subsystem
- operation
- event_name
- phase
- fields
- duration_ms optional
- error_code optional
```

Allowed execution phases are:

```text
Started
Progress
Completed
Failed
Cancelled
```

Rules:

- `Started` is emitted after a top-level operation is admitted.
- `Completed`, `Failed`, or `Cancelled` is emitted exactly once for an admitted top-level operation.
- `Progress` is bounded and operation-specific; it is not a substitute for persisted job progress.
- `Failed` references the stable error code when mapping has occurred.
- Trace events do not contain raw error strings, secrets, user paths, or ROM content.
- Trace events are not durable application state.
- Future spans may be derived from these concepts, but no span hierarchy is required during MVP.

## 18. Metrics and Performance Instrumentation

Argus records at least:

- operation duration
- queue wait duration
- persistence duration
- provider duration
- filesystem duration

Recommended instrument names are:

```text
argus.operation.duration
argus.operation.queue_wait
argus.persistence.duration
argus.provider.duration
argus.filesystem.duration
```

Requirements:

1. Metric durations use seconds as the instrument unit.
2. Logs and trace events may expose the same observations in milliseconds for readability.
3. Low-cardinality dimensions may include subsystem, operation, outcome, provider type, and operation class.
4. User paths, ROM names, hashes, raw provider IDs, error messages, and arbitrary entity IDs are prohibited as ordinary metric labels.
5. `trace_id` and Argus IDs may be attached as exemplars or structured observation context when supported.
6. Queue wait and execution duration are measured separately.
7. Persistence timing excludes queue wait when both are recorded.
8. Provider timing distinguishes provider-managed transport retry delay from request execution when practical; application-operation retry delay is measured separately when applicable.
9. Instrumentation failure must not fail the business operation.
10. Metric sinks are optional; local structured observations remain available through logs or trace events.

## 19. Startup Logging

Startup is one top-level operation with one `trace_id`.

Startup logging must always include:

- application version
- backend version
- platform
- CPU architecture
- migration summary

When metadata-provider infrastructure is part of the current runtime generation, startup logging also includes enabled provider identities/configuration state and emits `runtime.startup.providers_configured`.

Required stable core events include:

```text
runtime.startup.started
runtime.startup.environment
database.migration.completed
runtime.started
```

Rules:

- Provider configuration, when present, is represented by provider type and `ProviderId` when available, never credentials.
- Migration summary includes applied count, current schema version, and outcome, not SQL contents.
- Database paths are sanitized.
- A startup failure emits one terminal `TraceEvent` and one primary error log.
- Runtime readiness is logged only after all mandatory startup work succeeds.

## 20. Shutdown Logging

Shutdown is one top-level operation with one `trace_id`.

Required stable events include:

```text
runtime.shutdown.requested
runtime.shutdown.outstanding_operations
runtime.executor.drained
database.closed
runtime.shutdown.completed
```

Required fields include applicable operation counts, drain outcome, and bounded duration data.

Rules:

- Shutdown must not claim completion before executors are drained or explicitly abandoned according to runtime policy and the database is closed or a closure failure is recorded.
- Rejected new work after shutdown begins is logged at `Debug` or `Warn` according to caller visibility, not as repeated primary errors.
- A shutdown failure follows the single-primary-error rule.

## 21. Health Reporting

### 21.1 Covered subsystems

Health reporting covers:

```text
Runtime
Persistence
Filesystem
Providers
```

Runtime, persistence, and filesystem use:

```text
Healthy
Degraded
Unavailable
```

Provider health uses:

```text
Healthy
Degraded
Unavailable
Disabled
```

These values define the operational-health vocabulary for providers when provider health is implemented. Per ARCH-001, provider health, circuit breaking, and cross-`JobRun`-attempt health indicators are post-MVP concerns and are not Phase 000 implementation requirements. Capability-specific `ProviderReadiness` is defined separately by SPEC-BE-010 and must not be collapsed into this health type.

### 21.2 Provider-state semantics

- **Healthy:** Required configured capabilities are currently usable.
- **Degraded:** The provider remains partially usable, but one or more capabilities are impaired or recent failures exceed the healthy threshold.
- **Unavailable:** Required provider capabilities are not currently usable.
- **Disabled:** The provider is intentionally disabled by configuration. Disabled is not an error.

### 21.3 Health snapshot

A health snapshot contains:

```text
subsystem
state
observed_at
trace_id
summary_key
safe_context
```

Provider snapshots also include `provider_id` once assigned.

Rules:

- Health is a current operational summary, not a replacement for errors or logs.
- Health checks use a top-level operation context when explicitly requested.
- Periodic checks must not emit repeated error logs for an unchanged condition.
- State transitions may emit stable `Info` or `Warn` events.
- Health output uses Argus IDs and sanitized context.
- Provider health aggregation must preserve individual provider states.
- Exact provider-health thresholds and polling cadence remain deferred provider-operational-health policy.

## 22. Diagnostic Bundles

### 22.1 Creation

Diagnostic bundles are:

- initiated by an explicit user action
- ZIP archives
- written to a user-selected location
- independently versioned from the application and database schema
- assembled through bounded diagnostic contributors
- sanitized before archive entry creation

Automatic background upload is prohibited.

### 22.2 Bundle format

The minimum version-1 layout is:

```text
manifest.json
logs/argus.ndjson
runtime.json
persistence.json
health.json
configuration.json
```

The manifest contains at least:

```text
bundle_schema_version
created_at
application_version
backend_version
platform
architecture
trace_id
included_artifacts
omitted_artifacts
contributor_failures
```

### 22.3 Required contents

Bundles include:

- bounded recent structured logs
- runtime and platform information
- persistence information
- health snapshots
- sanitized configuration summary

Persistence information may include:

- SQLite version
- schema version
- migration-history summary
- configured PRAGMA outcomes
- database-open and integrity-check status where available
- sanitized database-location classification

It does not include the database file or table contents by default.

Configuration summary includes only explicit allowlisted values such as enabled feature flags, provider enabled/disabled state, and non-sensitive runtime modes. It does not serialize arbitrary settings records.

### 22.4 Contributor behavior

A diagnostic contributor has one stable identifier and returns one or more already-sanitized artifacts.

Contributor failures are recorded in the manifest. A non-critical contributor failure may produce a partial bundle. Archive creation, manifest generation, or redaction-policy failure causes the export operation to fail rather than emit an unsanitized bundle.

### 22.5 Versioning

- `bundle_schema_version` is an integer major version.
- Additive compatible fields may be introduced within the same major.
- Removing or changing field semantics requires a new major.
- Consumers must ignore unknown additive fields.
- Artifact filenames and JSON field semantics are contract-tested.

## 23. Redaction and Privacy Policy

### 23.1 Never record

The following must never appear in logs, trace events, metrics, health output, application errors, or diagnostic bundles:

- credentials
- access tokens
- refresh tokens
- passwords
- secrets
- authorization headers
- session cookies
- credential-store payloads
- private keys
- provider request signatures

Known secret-bearing fields are rejected by key and by value-pattern tests where practical.

### 23.2 Filesystem paths

Filesystem paths are sanitized before recording.

Required behavior:

1. Prefer `LibraryRootId`, `SourceEntryId`, or another Argus ID instead of a path.
2. Argus-controlled locations may be represented by logical tokens such as `$ARGUS_DATA`, `$ARGUS_CACHE`, or `$TEMP`.
3. User-selected roots are represented by `LibraryRootId` and a path class, not by the absolute path.
4. Relative ROM filenames and directory names are omitted by default.
5. When path shape is technically necessary, record bounded metadata such as path class, depth, extension, or platform error code without recording user-identifying segments.
6. Raw paths may be enabled only in a deliberately separate developer-only diagnostic mode that is excluded from normal bundles and public builds unless later approved.

### 23.3 ROM and content data

ROM bytes, archive contents, parsed content, filenames, display names, and provider-returned content are excluded from logs and bundles by default.

Content hashes are omitted when an Argus-owned identifier exists. Before identity assignment, a hash may be recorded only when explicitly required for a diagnostic contract and then must use a documented representation and allowlist.

### 23.4 Error sources

Third-party error messages and source chains are treated as untrusted data. They may be stored only after sanitization and bounded truncation. They never cross the bridge by default.

### 23.5 Safe-by-construction rule

Collection APIs must request typed safe fields rather than accepting arbitrary serializable objects. Redaction after unrestricted collection is insufficient.

## 24. Concurrency, Cancellation, and Retry Observability

1. Every queued work item carries its operation context.
2. Queue wait starts at accepted enqueue and ends when execution begins or the work is rejected/cancelled.
3. Cancellation requested before execution produces a cancelled terminal trace event without running the operation.
4. Cancellation during a transaction follows SPEC-BE-002 rollback rules.
5. Cancellation after durable commit does not change the committed success outcome.
6. Automatic retry attempts retain the same `trace_id` and include bounded attempt metadata.
7. User-initiated retry creates a new operation and `trace_id` while retaining Argus entity IDs that link it to the same subject.
8. Concurrent child work uses the parent operation's `trace_id` unless it is promoted to an independently managed top-level job or operation.
9. Instrumentation must be thread-safe and must not reorder authoritative state transitions.
10. Logging or metric backpressure must not block the UI-sensitive bridge path indefinitely; sink overflow policy must be bounded and diagnosable.

## 25. Persistence and Retention

- `ApplicationError` is not automatically persisted as a business record.
- Durable job, scan, or diagnostic records may store the stable error code and sanitized context when their owning specification requires it.
- Local structured logs may use bounded rotation under runtime configuration.
- Exact retention duration and size limits are runtime/deployment policy.
- Health snapshots are ephemeral unless a later diagnostics specification explicitly persists summaries.
- Trace events are transient during MVP.
- Diagnostic bundles exist only at the user-selected export destination.
- No raw database copy, ROM data, artwork cache, credentials, or provider cache is included by default.

## 26. Crate Ownership and Suggested Organization

Ownership follows SPEC-BE-001.

### 26.1 `argus-domain`

Owns domain-specific error types and typed entity IDs. It has no logging, tracing, diagnostic archive, or application-error dependency.

### 26.2 `argus-application`

Owns:

```text
ApplicationError
ErrorCode and catalog contract
ErrorCategory
ApplicationSeverity
Recoverability
RetryPolicy
MessageKey
SafeContext
TraceId
OperationContext-facing port requirements
LogEvent and TraceEvent contracts
health models
DiagnosticContributor ports
```

### 26.3 `argus-infrastructure`

Owns:

- structured log sinks and local file rotation
- metric sink adapters
- SQLite, filesystem, provider, and archive technical errors
- path sanitization implementations
- diagnostic ZIP writing
- concrete diagnostic contributors
- platform/runtime information collection

### 26.4 `argus-runtime`

Owns:

- `TraceId` generation
- top-level operation context creation
- context propagation through executors
- error mapping at runtime boundaries
- primary error logging
- startup and shutdown event emission
- health aggregation
- diagnostic export orchestration
- observability configuration and sink lifecycle

### 26.5 `argus-bridge`

Owns only mapping from stable application contracts to dedicated bridge DTOs.

Concrete folders are created only when implementation requires them. Empty speculative modules are prohibited.

## 27. Testing Requirements

### 27.1 Error contract tests

Test:

- every error code is unique
- every code matches the required format
- every code has one complete catalog entry
- catalog snapshot changes are explicit
- category, severity, recoverability, retry policy, and message key are stable
- deprecated codes identify replacements where applicable
- unknown technical errors map to a stable fallback
- no infrastructure or third-party error type crosses the application boundary

### 27.2 Mapping tests

Test representative translation chains for:

- domain validation
- SQLite open, locked, migration, constraint, and integrity failures
- filesystem permission and not-found failures
- provider transport, authentication, throttling, and protocol failures
- runtime startup and executor failures
- cancellation
- unexpected internal errors

### 27.3 Trace propagation tests

Test:

- one non-zero `trace_id` per top-level operation
- child work inherits the same `trace_id`
- queued database, provider, and filesystem work retains context
- automatic retries retain the trace
- user retries receive a new trace
- returned `ApplicationError` uses the operation trace
- no emitted log, trace event, or metric observation lacks required operation context

### 27.4 Logging tests

Test:

- required fields are present
- event names are stable and valid
- one failed operation produces exactly one primary error log
- propagation does not duplicate error logs
- retry attempts use `Warn` and final exhaustion uses one primary `Error`
- application severity does not overwrite logging level semantics
- startup and shutdown events occur in valid order

### 27.5 Redaction tests

Use table-driven and property-based tests where practical to verify exclusion of:

- credentials and token-shaped values
- authorization headers
- passwords and secret keys
- absolute user paths
- ROM filenames and content
- raw provider response bodies
- SQL text and database contents
- unbounded third-party error strings

Tests must inspect both individual events and completed diagnostic ZIP entries.

### 27.6 Diagnostic bundle tests

Test:

- valid ZIP creation
- manifest schema and version
- required artifact presence
- bounded log inclusion
- partial bundle behavior for non-critical contributor failure
- hard failure on manifest, archive, or sanitization failure
- no database file inclusion
- no arbitrary settings serialization
- reproducible artifact naming and JSON compatibility

### 27.7 Health tests

Test:

- runtime, persistence, and filesystem state mapping
- unchanged unhealthy state does not produce repeated primary errors
- transition events use the operation trace and safe context

When provider operational health is implemented, also test:

- provider state mapping uses Healthy, Degraded, Unavailable, and Disabled
- `Disabled` is valid only for providers
- provider aggregation preserves individual states
- provider health remains distinct from capability-specific `ProviderReadiness`

### 27.8 Performance instrumentation tests

Test:

- queue wait and execution duration are separate
- persistence, provider, and filesystem durations are recorded
- metric labels remain low cardinality
- instrumentation failure does not fail the operation
- exemplars or structured context use Argus IDs when available

## 28. Phase 000 Minimum Implementation

Phase 000 implements only the observability required for startup and appearance settings:

- the stable `ApplicationError` envelope
- the Phase 000 minimum error catalog
- non-zero OpenTelemetry-compatible `TraceId` generation
- one trace per startup, shutdown, bridge operation, and diagnostic export
- structured local logging
- separate `TraceEvent` values without spans
- primary-error deduplication
- startup and shutdown event conventions
- persistence and operation duration observations
- runtime, persistence, and filesystem health snapshots sufficient for recovery diagnostics
- user-initiated version-1 diagnostic ZIP bundles
- allowlist-based configuration summaries
- path sanitization and secret exclusion tests
- identity-first observability for Phase 000 Argus entities

Remote collectors, spans, persisted trace history, provider operational-health implementation (including thresholds, polling, history, circuit breaking, and cross-`JobRun`-attempt state), and production retention tuning remain deferred.

## 29. Acceptance Criteria

SPEC-BE-003 is satisfied when:

1. Every layer has an internal error type appropriate to its vocabulary.
2. Internal and third-party errors do not cross architectural boundaries directly.
3. `ApplicationError` contains all required stable fields.
4. Published codes follow the versioned `ARGUS.V<major>.<CATEGORY>.<NAME>` contract.
5. The Phase 000 minimum error catalog is implemented and contract-tested.
6. Category, severity, recoverability, and retry policy remain independent.
7. Retry timing remains runtime policy.
8. Every top-level operation receives one non-zero 128-bit `trace_id`.
9. All child observability signals inherit the operation trace.
10. New backend contracts do not use the prohibited alternate trace field name.
11. Phase 000 and MVP create no spans unless this specification is revised.
12. `LogEvent` and `TraceEvent` are separate types.
13. Every log contains all required structured fields.
14. Event names are stable and dot-separated.
15. One failure produces exactly one primary error log.
16. Error propagation does not produce duplicate error logs.
17. Startup logs include application/backend version, platform, architecture, and migration summary; enabled providers are included only when provider infrastructure exists in the active runtime generation.
18. Shutdown logs include request, outstanding operations, executor drain, database close, and completion.
19. Operation, queue, persistence, provider, and filesystem durations are measurable.
20. Metrics avoid unbounded label cardinality.
21. Runtime, persistence, and filesystem health are reportable; provider health follows this contract when its post-MVP implementation is introduced.
22. When provider operational health is implemented, it uses Healthy, Degraded, Unavailable, and Disabled and remains distinct from `ProviderReadiness`.
23. Diagnostic export is user initiated and produces a versioned ZIP bundle.
24. Bundles contain logs, runtime, persistence, health, and sanitized configuration information.
25. Bundles exclude secrets and user data by default.
26. Credentials, tokens, passwords, secrets, and authorization headers never enter observability output.
27. Filesystem paths are sanitized.
28. ROM content and names are excluded unless a later explicit diagnostic contract requires otherwise.
29. Argus-owned IDs are canonical after identity assignment.
30. Redaction, mapping, trace propagation, error deduplication, bundle, health, and instrumentation tests pass.

## 30. Out of Scope

This specification does not implement or finalize:

- OpenTelemetry spans
- distributed tracing export
- remote log or metric upload
- analytics
- crash-reporting vendors
- production retention and rotation values
- complete provider-specific error catalogs
- circuit-breaker policy
- background-job state machines
- command scheduling and executor ownership
- Flutter error presentation
- bridge DTO schemas
- persisted diagnostic history
- automatic support-bundle upload
- raw database export

## 31. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-010 — Provider Gateway Architecture](spec-be-010-provider-gateway-architecture.md)
- [Backend Specifications Index](README.md)
