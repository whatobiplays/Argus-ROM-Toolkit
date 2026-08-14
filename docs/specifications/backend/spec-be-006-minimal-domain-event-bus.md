# Minimal Domain Event Bus Specification

**Document ID:** SPEC-BE-006  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-14  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative application event model and minimal in-process domain event bus for Argus ROM Toolkit.

The event bus exists to notify interested application components that committed facts occurred. It is intentionally not a second command pipeline, workflow engine, scheduler, durable message broker, or source of authoritative state. Meaningful downstream work continues to enter through the application runtime defined by SPEC-BE-004.

Phase 000 requires only enough event infrastructure to publish `AppearanceSettingsChanged` after a successful settings commit and route that notification toward the Rust-to-Flutter bridge without coupling the settings handler directly to bridge infrastructure.

## 2. Scope

This specification covers:

- application-event ownership and taxonomy
- immutable event semantics
- operation-scoped pending event collection
- runtime-coordinated post-commit publication
- minimal in-process `EventBus` responsibilities
- concrete event-type subscriptions
- subscriber registration and ownership
- subscriber execution boundaries
- `OperationStarter` as the only downstream application-execution path
- per-operation event ordering
- subscriber failure isolation
- best-effort transient delivery
- observability requirements
- bridge publication integration
- Phase 000 `AppearanceSettingsChanged` routing
- architecture and test requirements

## 3. Non-Responsibilities

This specification does not define:

- durable event storage
- event replay
- an outbox or inbox pattern
- cross-process messaging
- distributed messaging
- message brokers
- event sourcing
- command dispatch through events
- workflow orchestration
- saga/process-manager semantics
- automatic subscriber retry
- dead-letter queues
- user-visible notification history
- bridge DTO serialization details
- Flutter event coordination
- bridge event sequence generation, coalescing, or overflow mechanics already owned by SPEC-BE-004
- the complete future event catalog
- operation-specific business logic triggered by future events

Those concerns require later specifications if demonstrated product needs emerge.

## 4. Architectural Principles

1. Application events announce committed facts; they do not carry authoritative application state by default.
2. Queries remain the authoritative mechanism for reading current application state.
3. Commands and background operations remain the authoritative mechanisms for producing side effects.
4. The event bus transports notifications but does not execute hidden application workflows.
5. Every application event is owned by exactly one bounded context.
6. Application events are strongly typed and immutable.
7. Handlers record pending events but never publish them directly.
8. Pending events are scoped to one top-level operation.
9. `ApplicationRuntime` coordinates publication only after successful durable commit.
10. Persistence and Unit of Work abstractions do not own event publication.
11. Subscribers register for concrete event types rather than strings or wildcard categories.
12. Event consumers are notification adapters, not unrestricted execution contexts.
13. Meaningful downstream work initiated by an event must start a new runtime operation.
14. New downstream operations receive a new `TraceId` and normal runtime admission.
15. Event ordering is guaranteed only within one originating operation.
16. Subscriber failures are isolated and cannot invalidate an already committed operation.
17. Delivery is in-process, transient, bounded where buffering exists, and best effort.
18. Event loss must never compromise authoritative correctness.
19. The event bus owns routing mechanics, never domain semantics.
20. Technology-specific messaging or async-runtime details do not leak into application contracts.

## 5. Terminology

### 5.1 Application Event

An immutable, strongly typed notification that a meaningful application or domain fact has occurred.

Example:

```text
SettingsEvent
└── AppearanceSettingsChanged
```

Future bounded contexts may define their own events, such as library, provider, metadata, verification, or runtime-state events.

### 5.2 Pending Event

An application event recorded during an operation before the runtime has established that the related authoritative mutation committed successfully.

Pending events are not externally visible.

### 5.3 Published Event

A pending event that the runtime has released to the event bus after the operation reached its required post-commit publication boundary.

### 5.4 Event Consumer

A component registered to receive one concrete application event type.

Consumers observe notifications. They do not gain implicit permission to read or mutate authoritative state outside the runtime operation model.

### 5.5 Event Bus

The in-process routing component that maps a published concrete event type to its registered consumers and isolates delivery failures.

The bus does not interpret domain meaning.

## 6. Application Event Taxonomy

Application events are domain-owned rather than maintained as one semantically flat global catalog.

Conceptually:

```text
ApplicationEvent
├── SettingsEvent
│   └── AppearanceSettingsChanged
├── LibraryEvent
├── MetadataProviderEvent
├── MetadataEvent
├── VerificationEvent
└── RuntimeEvent
```

The exact Rust representation may use enums, traits, concrete types, generated routing metadata, or another strongly typed mechanism. The conceptual ownership rules are normative even if no literal root `ApplicationEvent` enum exists.

Every event belongs to exactly one bounded context.

The owning bounded context defines:

- event name
- semantic meaning
- event payload, if any
- versioning expectations
- conditions under which the event is recorded

The event bus defines none of those semantics.

## 7. Event Naming

Application event type names describe facts that already occurred.

Preferred examples:

```text
AppearanceSettingsChanged
LibraryRootsChanged
LibraryRootChanged
SourceEntriesChanged
JobStateChanged
MetadataProviderHealthChanged
MetadataAssignmentChanged
```

Avoid imperative names such as:

```text
UpdateAppearanceSettings
RefreshLibrary
FetchMetadata
```

Imperative behavior belongs to commands or background operations, not events.

Published event type names become stable application contracts once consumed outside their defining bounded context.

## 8. Event Immutability

Every application event is immutable after construction.

Required flow:

```text
handler
    ↓
construct immutable event
    ↓
EventCollector
    ↓
ApplicationRuntime
    ↓
EventBus
    ↓
subscribers
```

Rules:

1. Events are fully constructed before being recorded.
2. `EventCollector` stores immutable events.
3. Runtime publication does not mutate event semantics.
4. Event routing does not mutate event semantics.
5. Subscribers cannot modify a shared event instance.
6. Bridge adapters may map the event into a bridge DTO but cannot redefine its meaning.
7. Observability metadata added outside the event payload does not mutate the application event itself.

The concrete Rust implementation may use owned values, immutable references, shared immutable ownership, or another memory-safe representation.

## 9. Events Are Notifications, Not Authoritative State

Application events announce that authoritative state changed or that another committed fact occurred.

Consumers that require current state re-query it through a focused query contract.

For Phase 000:

```text
AppearanceSettingsChanged
    ↓
consumer knows appearance settings changed
    ↓
GetAppearanceSettingsQuery
    ↓
authoritative AppearanceSettings
```

`AppearanceSettingsChanged` therefore carries no authoritative `AppearanceSettings` payload, as defined by SPEC-BE-005.

Future events may carry bounded immutable context when required for their semantics, but payload convenience must not turn transient events into the only copy of authoritative application state.

## 10. Operation-Scoped Event Collection

Every top-level operation that can produce application events owns one operation-scoped pending event collector.

Conceptually:

```text
OperationContext
├── TraceId
├── Cancellation
├── progress facilities where applicable
├── observability facilities
└── EventCollector
```

The exact field ownership may use a narrower capability passed to handlers rather than exposing the complete runtime context. The semantic requirement is that pending-event lifetime is exactly one operation lifetime.

Required properties:

- one collector per operation
- no collector reuse across operations
- deterministic recording order
- no direct publication API on domain handlers
- discard on failed or rolled-back mutation
- drain only under runtime control

## 11. `EventCollector` Contract

Conceptually:

```text
EventCollector
├── record(event)
├── is_empty()
└── take_all()
```

Exact Rust signatures are deferred to implementation planning.

Required semantics:

1. `record` appends one immutable event in deterministic order.
2. Recording does not deliver the event.
3. Recording does not perform I/O.
4. Recording does not acquire persistence transactions.
5. `take_all` preserves recording order.
6. The collector is empty after a successful drain.
7. A collector associated with a failed operation is discarded rather than published.
8. Event collection must not require the aggregate itself to own an event queue.

## 12. Handler Responsibilities

Application handlers own the decision that a meaningful event occurred.

A handler may:

- validate business intent
- mutate authoritative state through the allowed Unit of Work or operation mechanism
- construct an event describing the resulting fact
- record the event in the operation-scoped collector

A handler must not:

- invoke `EventBus.publish` directly
- publish before commit
- invoke bridge stream infrastructure directly
- depend on subscriber implementations
- assume any particular subscriber exists
- synchronously invoke another bounded context merely because an event was recorded

For `UpdateAppearanceSettingsCommand`, SPEC-BE-005 remains authoritative over the semantic condition: `AppearanceSettingsChanged` is recorded only when the persisted aggregate semantically changes.

## 13. Persistence Boundary

The Unit of Work owns transaction consistency, not event publication.

Prohibited coupling:

```text
UnitOfWork.commit()
    ↓
EventBus.publish(...)
```

as an implicit persistence responsibility.

Required ownership is:

```text
handler records event
    ↓
Unit of Work commits
    ↓
runtime observes successful commit outcome
    ↓
runtime releases pending events
    ↓
EventBus routes events
```

Persistence adapters must not depend on the application event bus.

This preserves the technology-neutral repository and Unit of Work contracts from SPEC-BE-002.

## 14. Runtime-Coordinated Publication

`ApplicationRuntime` owns the publication boundary because it owns the top-level operation lifecycle.

For an immediate command with one transactional mutation:

```text
runtime admission
    ↓
create OperationContext + EventCollector
    ↓
invoke handler
    ↓
handler records pending events
    ↓
Unit of Work commit succeeds
    ↓
runtime receives successful committed outcome
    ↓
drain EventCollector
    ↓
publish events in recorded order
    ↓
complete originating operation
```

If validation, persistence, cancellation, or another pre-commit failure prevents commit, the runtime discards all pending events for that mutation.

Event publication is post-commit. Therefore publication failure cannot roll back the committed state and cannot convert committed success into application failure.

## 15. Multiple Commit Boundaries

Long-running background operations may contain multiple bounded durable checkpoints under SPEC-BE-004.

A later operation-specific specification may define event publication at each successfully committed checkpoint where that is semantically correct.

The invariant remains:

> An application event describing authoritative persisted state is never published before the durable state it describes exists.

SPEC-BE-006 does not require Phase 000 to implement persisted background jobs or multi-checkpoint event publication.

## 16. Event Bus Responsibilities

The minimal `EventBus` owns:

- concrete event-type routing
- subscriber registration metadata
- deterministic subscriber enumeration according to implementation registration order or another documented stable implementation policy
- failure isolation between subscribers
- delivery observability
- bounded handoff where buffering exists

The event bus does not own:

- business rules
- persistence
- Unit of Work
- runtime admission
- commands
- queries
- background scheduling
- subscriber retry
- durable event storage
- bridge sequence numbering
- Flutter state
- domain-specific recovery

## 17. Publication Handoff Model

The Phase 000 event bus uses a lightweight synchronous publication handoff with isolated consumers.

Conceptually:

```text
runtime publishes committed event
    ↓
EventBus routes by concrete type
    ↓
subscriber A accepts notification
subscriber B accepts notification
subscriber C accepts notification
```

The publication handoff may enqueue into a bounded subscriber-owned or bridge-owned buffer when required, but the event bus must not become a general asynchronous application scheduler.

Subscriber acceptance must remain lightweight. Substantial downstream application work is prohibited inline and must start a new runtime operation.

No event publication path may wait indefinitely on Flutter, provider I/O, filesystem I/O, database work, or another unbounded consumer action.

## 18. Type-Based Subscriptions

Subscriptions are defined by concrete event type.

Conceptually:

```text
subscribe<AppearanceSettingsChanged>(consumer)
```

rather than:

```text
subscribe("settings.*", consumer)
subscribe(SettingsEvent, consumer)
subscribeAll(consumer)
```

Phase 000 prohibits wildcard and category subscriptions.

Benefits are normative goals:

- explicit dependencies
- compile-time discoverability
- no stringly typed routing
- bounded consumer awareness
- simpler architecture testing

The exact Rust generic or trait syntax is an implementation detail.

## 19. Subscriber Registration

Subscriber registration occurs at application/runtime composition time.

Rules:

1. Registration is explicit.
2. Event-producing handlers do not register subscribers.
3. Domain aggregates do not know subscribers.
4. Subscriber registration is complete before normal runtime readiness for subscribers required by that runtime generation.
5. Runtime replacement constructs a fresh event bus/subscriber graph for the new runtime instance.
6. Feature-level code must not mutate global subscription topology as a side effect of ordinary command execution.

Dynamic plugin-driven subscriptions are out of scope.

## 20. Subscriber Dependency Boundary

Application event consumers are notification adapters, not execution contexts.

Event consumers must not receive direct dependencies on:

- transaction-bound repositories
- Unit of Work
- Unit of Work factories
- persistence adapters
- provider gateways for business actions
- filesystem gateways for business actions
- bridge-independent domain mutation services that bypass runtime admission

Consumers may receive narrowly scoped facilities such as:

- the concrete event type they consume
- observability capability
- cancellation/status needed for bounded notification handling
- `OperationStarter` when they are authorized to initiate downstream application work
- a bridge notification sink when their sole responsibility is transport toward the bridge

Architecture boundaries should make hidden side effects difficult or impossible to implement accidentally.

## 21. `OperationStarter`

`OperationStarter` is the application/runtime port through which an event consumer requests meaningful downstream work.

Conceptually it can provide typed capabilities equivalent to:

```text
start_query(...)
start_command(...)
start_background_operation(...)
```

The exact API may be split into narrower typed ports if that produces better compile-time boundaries.

Required semantics:

1. Starting downstream work re-enters centralized runtime admission.
2. The new work receives a new top-level `OperationContext`.
3. The new work receives a new `TraceId`.
4. The new work follows its normal Query, Immediate Command, or Background Operation classification.
5. Cancellation, error mapping, logging, and runtime lifecycle rules are identical to work initiated through any other application entry point.
6. The event consumer cannot reuse the originating operation's Unit of Work.
7. The event consumer cannot extend the originating transaction.

### 21.1 Publication-stack and resource-release boundary

`OperationStarter` performs only a bounded request/admission handoff while an event is being published. An event consumer must not synchronously execute or await completion of the downstream handler on the originating publication stack.

Before downstream business execution begins, the originating Unit of Work, event collector, operation locks, and other operation-scoped resources must be released. The new operation receives independent admission, context, cancellation, and trace identity and cannot re-enter the originating operation.

This boundary prevents event delivery from turning post-commit publication into hidden recursive command execution or a lock/resource deadlock.

## 22. Causality and Trace Identity

Event-triggered work is causally related to the event but is not the same top-level operation.

Example:

```text
UpdateAppearanceSettingsCommand
trace_id = A
    ↓ commit
AppearanceSettingsChanged
    ↓ consumer requests refresh work
GetAppearanceSettingsQuery
trace_id = B
```

`trace_id = B` is mandatory for the new top-level operation.

If later observability needs explicit causal linkage, safe provenance metadata may reference the origin operation according to SPEC-BE-003 conventions. Such metadata must not cause trace reuse across independent top-level operations.

## 23. What May Execute Inline

An event consumer may execute only lightweight notification work inline with publication handoff.

Permitted examples:

- route the event to a bounded bridge notification sink
- emit structured observability about delivery
- update ephemeral subscriber-local bookkeeping
- request a new operation through `OperationStarter` as a bounded handoff without awaiting downstream handler completion on the publication stack
- perform bounded mapping from an application event to a transport notification

Prohibited inline work includes:

- authoritative persistence reads or writes
- opening a Unit of Work
- provider network calls
- filesystem scans or writes
- long-running CPU work
- waiting for user input
- hidden retries of application actions
- executing another command handler directly

A practical classification rule is:

> If the downstream action deserves its own admission decision, trace, cancellation behavior, error outcome, or meaningful execution duration, it is a new runtime operation.

## 24. Event Ordering

The event system guarantees per-operation ordering only.

If one operation records:

```text
E1
E2
E3
```

then publication and routing preserve:

```text
E1 -> E2 -> E3
```

for that originating operation.

No total ordering is guaranteed across independent concurrent operations.

Consumers must not infer causal relationships from the relative delivery ordering of events produced by different operations.

If strict causal ordering between multiple facts is required, the operation-specific design must establish an explicit dependency or shared consistency boundary rather than relying on global event-bus ordering.

## 25. Subscriber Ordering

SPEC-BE-006 does not define semantic dependencies between subscribers to the same event.

A subscriber must not require another subscriber to have already processed the event.

If consumer B requires output from consumer A, that relationship is a workflow dependency and must be modeled explicitly through runtime operations or another later orchestration abstraction.

Implementation may use deterministic registration order for repeatable tests, but subscriber order is not an application contract.

## 26. Subscriber Failure Isolation

Each subscriber is isolated from all other subscribers for delivery outcome.

Required behavior:

```text
publish event
    ├── subscriber A succeeds
    ├── subscriber B fails -> observe failure
    └── subscriber C still receives event
```

Rules:

1. One subscriber failure never aborts delivery to remaining subscribers.
2. A subscriber failure never rolls back committed authoritative state.
3. A subscriber failure never changes the originating command from committed success to failure.
4. Subscriber failures are observable through SPEC-BE-003 logging and diagnostic rules.
5. The bus does not automatically retry a failed subscriber during Phase 000.
6. Consumers should be designed to tolerate duplicate delivery even though intentional redelivery is not a Phase 000 feature.

## 27. Best-Effort Delivery

Application-event delivery is best effort.

This implies that any of the following may result in a committed fact without successful notification to every consumer:

- process termination after commit
- runtime shutdown
- subscriber failure
- bounded buffer overflow downstream
- bridge disconnect
- runtime replacement

This is acceptable because authoritative state remains queryable.

No correctness invariant may depend on successful transient event delivery.

## 28. No Durable Event Log During Phase 000

Phase 000 does not persist application events as a durable stream.

Therefore the following are explicitly unsupported:

- replay after application restart
- delivery acknowledgement persistence
- exactly-once delivery
- at-least-once delivery guarantees
- durable subscriber offsets
- event history queries

If a future feature requires those semantics, it must introduce a separate durable messaging specification rather than silently changing the meaning of this minimal bus.

## 29. Idempotent Consumer Design

Although intentional redelivery is not required, consumers should be safe when receiving the same notification more than once.

For notification-first events this usually means:

- re-query authoritative state
- avoid append-only side effects based solely on event receipt
- avoid incrementing counters that assume exactly-once delivery unless those counters are ephemeral diagnostics

Idempotent consumer design preserves future flexibility without requiring durable delivery infrastructure today.

## 30. Bridge Integration Boundary

The application event bus and the bridge event stream are separate layers.

Conceptually:

```text
ApplicationRuntime
    ↓ committed application event
EventBus
    ↓ concrete subscriber
BridgeEventPublisher
    ↓
runtime/bridge event stream envelope
    ↓
Flutter event coordinator
```

SPEC-BE-006 owns the `EventBus -> BridgeEventPublisher` application notification relationship.

SPEC-BE-004 owns bridge-stream runtime mechanics including:

- `RuntimeInstanceId`
- per-runtime sequence numbers
- sequence-gap detection contract
- bounded bridge queue
- coalescing
- overflow behavior
- runtime replacement behavior

SPEC-BE-008 will own exact Rust-to-Flutter DTO mapping.

The internal application event itself does not need to carry bridge sequence information.

## 31. Phase 000 `AppearanceSettingsChanged` Flow

The required Phase 000 path is:

```text
UpdateAppearanceSettingsCommand
    ↓
semantic settings change
    ↓
EventCollector.record(AppearanceSettingsChanged)
    ↓
Unit of Work commit
    ↓
ApplicationRuntime drains committed events
    ↓
EventBus.publish(AppearanceSettingsChanged)
    ↓
BridgeEventPublisher receives notification
    ↓
bridge stream envelope assigned by runtime/bridge layer
    ↓
Flutter event coordinator
    ↓
GetAppearanceSettings
    ↓
apply authoritative theme
```

No settings handler directly references Flutter, bridge bindings, bridge DTOs, or the bridge publisher.

## 32. No-Op and Rollback Semantics

SPEC-BE-005 defines semantic no-op behavior for settings.

Required event behavior:

- semantic no-op update -> no `AppearanceSettingsChanged`
- validation failure -> no event
- persistence failure -> no event
- rollback -> no event
- cancellation before commit -> no event
- successful semantic commit -> one `AppearanceSettingsChanged`

The event bus does not deduplicate semantic events on behalf of the publisher. Correct event creation is the responsibility of the owning bounded context/handler.

## 33. Runtime Shutdown

When the runtime enters `ShuttingDown`:

- no new normal application operations are admitted under SPEC-BE-004
- already committed events may be handed to currently active subscribers while the runtime remains able to do so safely
- event delivery does not extend shutdown indefinitely
- subscriber notification work obeys the runtime's bounded shutdown lifecycle
- event loss during shutdown remains acceptable because authoritative state is durable

The bus does not own a separate independent shutdown lifecycle outside its `ApplicationRuntime` generation.

## 34. Runtime Replacement

Each `ApplicationRuntime` generation owns a fresh event-bus/subscriber composition.

A bus from a `StartupFailed` or `Stopped` runtime is never reused by a new runtime generation.

Subscriber handles tied to an old runtime generation must not remain capable of routing into the replacement runtime through stale references.

Bridge reconnection and authoritative refresh after runtime replacement remain governed by SPEC-BE-004.

## 35. Observability

SPEC-BE-003 applies to event publication and subscriber delivery.

Stable diagnostic event names should include:

```text
event.publish.completed
event.publish.partial_failure
event.subscriber.failed
event.subscriber.completed
```

Exact logging volume may be tuned to avoid excessive normal-path noise.

Required observability fields where applicable include:

- originating `trace_id` for the publication handoff
- event type
- bounded subscriber identity/name
- delivery outcome
- duration for unexpectedly slow subscribers
- safe error code/context for subscriber failure

Do not log arbitrary event payload serialization.

Event-triggered downstream operations receive new `trace_id` values under SPEC-BE-004.

## 36. Error Handling

Subscriber failures occur after the authoritative operation has committed and therefore do not propagate as failures of that committed operation.

The bus isolates each subscriber failure and records diagnostics.

An event consumer that starts a new operation through `OperationStarter` receives the normal result/error behavior of that new operation. Its failure is not retroactively attached to the event publisher's committed result.

The event bus does not introduce a broad published user-facing error code solely for ordinary subscriber failure during Phase 000. If a required infrastructure subscriber becomes unavailable in a way that changes runtime health, the owning runtime/bridge specification maps that condition through the appropriate existing error/health contracts.

## 37. Health Reporting

The minimal event bus itself should normally be either available as part of a valid runtime composition or prevent readiness if a required Phase 000 subscriber graph cannot be constructed.

A transient failure of one event consumer after readiness is observable but does not automatically make all runtime health `Unavailable`.

Provider-style health states are not assigned to every subscriber.

If a critical bridge notification sink becomes persistently unavailable, bridge/runtime health policy is owned by SPEC-BE-004 and SPEC-BE-008 rather than by generic event semantics.

## 38. Security and Privacy

Application events must follow SPEC-BE-003 redaction and safe-context requirements.

Events must never contain:

- credentials
- tokens
- passwords
- authorization headers
- raw secrets
- arbitrary ROM content
- unsanitized filesystem paths unless a later event contract explicitly demonstrates necessity and defines redaction

Event payloads should prefer Argus-owned identities once they exist.

The event bus must not automatically serialize event payloads into logs or diagnostics.

## 39. Technology-Neutral Contracts

Application event contracts must not expose concrete messaging, channel, async-runtime, serialization, or bridge implementation types.

Avoid public application concepts such as:

```text
TokioBroadcastEvent
MpscEventSender
StreamControllerEvent
FlutterRustBridgeEvent
SerdeJsonEvent
```

Preferred concepts remain:

```text
ApplicationEvent
EventCollector
EventBus
EventConsumer
OperationStarter
```

Concrete queues, channels, smart pointers, and async primitives are implementation details.

## 40. Crate Ownership

Ownership follows SPEC-BE-001.

### `argus-domain`

May own pure domain event types only when the event is genuinely a domain concept and does not introduce application/runtime dependencies.

Phase 000 does not require a generic domain-event base type in `argus-domain`.

### `argus-application`

Owns:

- application event definitions associated with application use cases when appropriate
- `AppearanceSettingsChanged`
- event-consumer application ports
- `OperationStarter` application/runtime-facing port where boundary placement fits the workspace direction
- typed subscriber interfaces or routing abstractions that contain no infrastructure technology

### `argus-runtime`

Owns:

- operation-scoped event collector lifecycle
- post-commit publication coordination
- event-bus runtime composition/lifecycle
- concrete event routing orchestration when it does not belong to infrastructure
- runtime-safe handoff to registered consumers

### `argus-infrastructure`

May own technology-specific bounded queue/channel adapters if implementation requires them. It does not own application event semantics.

### `argus-bridge`

Owns the application-event subscriber that maps supported application notifications into the bridge event stream contract.

It does not become the application event bus.

## 41. Dependency Rules

Required dependency direction:

```text
domain/application event definitions
        ↑
application handlers
        ↑
runtime event collection and routing
        ↑
infrastructure/bridge adapters
```

Forbidden dependencies include:

- domain -> runtime event bus
- domain -> bridge publisher
- application handler -> bridge subscriber
- persistence -> event bus publication
- event consumer -> infrastructure repository implementation
- event consumer -> Unit of Work implementation
- event consumer -> direct command handler invocation

Architecture tests should enforce these boundaries where practical.

## 42. Testing Requirements

### 42.1 Event type tests

Test:

- events are immutable application values
- `AppearanceSettingsChanged` has no authoritative settings payload
- event names/types are stable and strongly typed

### 42.2 EventCollector tests

Test:

- recording one event
- recording multiple events preserves order
- `take_all` preserves order
- drained collector becomes empty
- collectors are operation-scoped
- collector disposal after failure publishes nothing

### 42.3 Post-commit publication tests

Test:

- successful commit publishes recorded events
- validation failure publishes none
- rollback publishes none
- persistence failure publishes none
- pre-commit cancellation publishes none
- event publication failure after commit does not change committed operation success

### 42.4 Type-routing tests

Test:

- concrete subscriber receives matching event
- subscriber does not receive unrelated event types
- multiple subscribers for one type each receive the event
- no string route is required
- wildcard subscription is unavailable through the Phase 000 public contract

### 42.5 Ordering tests

Test:

- events from one operation retain recording order
- the bus does not promise total ordering between independent operations
- subscribers do not rely on another subscriber's processing order

### 42.6 Failure-isolation tests

Test:

- first subscriber succeeds, second fails, third still executes
- failure is observable
- originating committed command remains successful
- no automatic retry occurs

### 42.7 Consumer-boundary tests

Architecture tests or compile-time dependency tests must verify event consumers cannot directly depend on:

- transaction-bound repositories
- Unit of Work
- provider adapters/gateways for authoritative work
- filesystem adapters/gateways for authoritative work

Test that downstream meaningful work uses `OperationStarter` and receives a new `TraceId`.

### 42.8 Bridge subscriber tests

Test:

- `AppearanceSettingsChanged` reaches the bridge publisher subscriber
- bridge publisher performs bounded notification mapping only
- settings handler has no bridge dependency
- bridge publication loss does not affect settings persistence correctness

### 42.9 Shutdown/runtime replacement tests

Test:

- event bus belongs to one runtime generation
- stopped bus/subscriber graph is not reused
- shutdown does not wait indefinitely for consumer delivery
- replacement runtime constructs fresh subscriptions

### 42.10 Privacy tests

Test:

- event infrastructure does not generically dump payloads to logs
- known secret-like values are excluded from event diagnostic paths
- bridge mapping does not add internal persistence data

## 43. Phase 000 Minimum Implementation

Phase 000 implements only the minimum event infrastructure required for the theme workflow:

- immutable `AppearanceSettingsChanged`
- operation-scoped `EventCollector`
- runtime post-commit event drain/publication
- in-process `EventBus`
- explicit concrete-type registration
- isolated subscriber delivery
- one bridge-facing subscriber for supported Phase 000 application events
- lightweight publication handoff
- observability sufficient to diagnose subscriber failure
- architecture boundaries preventing event consumers from becoming hidden execution contexts

Phase 000 does not implement:

- durable event records
- replay
- retry
- dead-letter queues
- persisted subscriber state
- cross-process messaging
- a generic event workflow system
- dynamic plugin subscriptions

## 44. Acceptance Criteria

SPEC-BE-006 is satisfied when:

1. Every application event belongs to exactly one bounded context.
2. Application events are strongly typed.
3. Application events are immutable after construction.
4. `AppearanceSettingsChanged` remains notification-only and carries no authoritative settings aggregate.
5. Every event-producing operation uses an operation-scoped pending `EventCollector`.
6. Handlers record events but cannot publish them directly.
7. Aggregates do not own generic application-event queues.
8. Unit of Work does not publish application events.
9. `ApplicationRuntime` coordinates publication after successful commit.
10. Failed or rolled-back mutations publish no application events.
11. Event publication failure after commit cannot roll back authoritative state.
12. Event routing uses concrete event types rather than strings.
13. Wildcard/category subscriptions are absent from the Phase 000 contract.
14. Subscribers are explicitly registered during runtime composition.
15. Subscriber dependencies do not provide direct authoritative persistence, provider, filesystem, or Unit of Work capabilities.
16. Meaningful downstream work starts through `OperationStarter` or a narrower equivalent runtime port.
17. Event-triggered downstream work receives a new `OperationContext` and new `TraceId`.
18. The originating Unit of Work is never reused by an event consumer.
19. Per-operation event recording/publication order is preserved.
20. No global event order is promised across independent operations.
21. Subscriber order is not an application dependency contract.
22. One subscriber failure does not prevent remaining subscribers from receiving an event.
23. Subscriber failure does not change committed operation success.
24. Automatic subscriber retry is absent during Phase 000.
25. Delivery is transient and best effort.
26. No correctness requirement depends on event delivery.
27. The application event bus is distinct from the bridge stream envelope.
28. SPEC-BE-004 remains authoritative for runtime event sequence/backpressure mechanics.
29. Runtime replacement constructs a fresh bus/subscriber graph.
30. Event contracts leak no messaging or async-runtime implementation technology.
31. Phase 000 theme reconciliation works through `AppearanceSettingsChanged` followed by authoritative settings re-query.
32. Architecture, ordering, failure, post-commit, bridge, and privacy tests cover the required behavior.

## 45. Prohibited Patterns

- handlers calling `EventBus.publish` directly
- events published before commit
- Unit of Work publishing events
- persistence adapters depending on event delivery
- aggregates carrying generic mutable pending-event collections
- mutable application events
- stringly typed event routing
- wildcard subscribers during Phase 000
- one global subscriber receiving all events by default
- event consumers opening Units of Work directly
- event consumers directly invoking command handlers
- event consumers performing provider or filesystem business work inline
- reusing the originating `TraceId` for event-triggered top-level work
- treating events as the sole authoritative state transport
- subscriber failures rolling back committed operations
- automatic subscriber retry without an explicit later specification
- durable replay semantics hidden inside the minimal event bus
- global total event ordering
- subscriber-order business dependencies
- unbounded publication blocking
- direct settings-handler dependency on bridge infrastructure
- technology-specific queue/channel types in application contracts

## 46. Out of Scope

This specification does not finalize:

- exact Rust trait signatures
- exact enum-versus-trait event representation
- exact queue/channel implementation
- exact subscriber storage data structure
- exact subscriber registration syntax
- bridge DTO fields
- Flutter stream/controller implementation
- durable event identifiers
- distributed trace-link representation between causally related operations
- replay
- durable outbox/inbox
- workflow engines
- event sourcing
- remote subscribers
- plugin-defined event topology

## 47. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-005 — Settings Service and Appearance Settings](spec-be-005-settings-service-and-appearance-settings.md)
- [Backend Specifications Index](README.md)
