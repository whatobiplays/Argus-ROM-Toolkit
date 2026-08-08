# Provider Gateway Architecture Specification

**Document ID:** SPEC-BE-010  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-08  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-005, SPEC-BE-006, SPEC-BE-007, SPEC-BE-008, SPEC-BE-009  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the canonical backend architecture for Argus metadata and external-service provider gateways.

The gateway layer isolates application workflows from provider-specific APIs, authentication schemes, HTTP clients, SDKs, payloads, rate limits, retry conventions, error vocabularies, and branding. Application code consumes stable capability-oriented contracts owned by Argus; provider implementations translate those contracts into provider-specific interactions.

This specification formalizes the provider architecture established by ARCH-001 and makes its lifecycle, capability, readiness, selection, error, retry, and dependency rules normative for later metadata, artwork, and related feature specifications.

## 2. Scope

This specification covers:

- metadata/external-service provider identity
- `ProviderId`
- `ProviderDescriptor`
- static provider capabilities
- dynamic `ProviderReadiness`
- readiness refresh semantics
- runtime-composed `MetadataProviderRegistry`
- provider selection policy boundaries
- `ProviderSessionFactory`
- `JobRun`-attempt-scoped `ProviderSession`
- capability-oriented provider contracts
- metadata matching capability
- metadata refresh capability
- artwork discovery capability
- provider request/response ownership
- canonical `ProviderError`
- provider error translation
- transport retry ownership
- application-owned provider fallback
- rate-limit coordination
- request deduplication and `JobRun`-attempt-scoped request caching
- observability and health integration
- cancellation
- provider configuration boundaries
- provider implementation dependency rules
- architecture tests and acceptance criteria

## 3. Non-Responsibilities

This specification does not define:

- source/storage provider architecture, which is defined separately by SPEC-BE-011
- `LibrarySource`, `LibraryRoot`, or `SourceEntry`
- ROM scanning, hashing, or classification
- canonical metadata domain entities
- metadata reconciliation or merge policy
- provider-specific field mapping details
- persistence schemas for resolved metadata
- artwork file storage or download implementation
- frontend provider settings UI
- bridge DTOs
- provider credential storage implementation
- plugin discovery or third-party provider loading
- exact HTTP library selection
- exact retry timing constants
- final provider preference UX

Those concerns remain owned by later feature specifications or existing architectural contracts.

## 4. Explicit Scope Boundary: Metadata Providers Only

`SPEC-BE-010` applies only to external providers used to retrieve, match, refresh, or discover metadata-like information.

Examples include providers conceptually similar to:

- game metadata databases
- artwork catalogs
- other enrichment services only when they explicitly implement one of the metadata capability contracts defined here

RetroAchievements catalog retrieval and hash verification remain the separate subsystem defined by ARCH-001 and are not automatically members of `MetadataProviderRegistry`. A later RetroAchievements specification may reuse compatible cross-cutting gateway patterns without collapsing its verification semantics into the metadata-provider family.

This specification intentionally does not unify those providers with source/storage providers.

Source providers expose storage access and enumeration primitives; indexing owns discovery traversal and reconciliation semantics as defined by SPEC-BE-011. Metadata providers expose external information capabilities. They have different lifecycle, failure, health, authentication, retry, and orchestration semantics and therefore must not be forced behind one generic provider abstraction.

Normative rule:

> Metadata/external-service providers and source/storage providers are separate architectural families. Shared naming does not imply shared gateway contracts.

## 5. Architectural Principles

1. Application workflows depend on Argus-owned capability contracts, never provider-specific APIs.
2. Provider implementations are infrastructure adapters.
3. A provider is identified independently from its implementation, branding, URL, or SDK.
4. Static capability declaration is separate from dynamic readiness.
5. Provider discovery is separate from provider selection.
6. Provider selection is separate from provider execution.
7. Provider execution occurs through sessions scoped to one `JobRun` execution attempt.
8. Provider sessions own provider-specific transient execution state only.
9. Capability interfaces are small, behavior-oriented, and independently extensible.
10. Unsupported capabilities are represented by absence wherever practical.
11. Native provider errors are translated into one provider-agnostic `ProviderError` vocabulary.
12. Provider sessions own transport-level retries.
13. Application workflows own semantic retries and provider fallback.
14. Provider sessions never silently switch to another provider.
15. Provider readiness is a current snapshot, not a guarantee of future request success.
16. Provider registry membership is immutable for one runtime generation.
17. Provider IDs are stable, strongly typed, and owned by Argus.
18. Provider-specific secrets and credentials never cross application-facing gateway contracts.
19. Significant provider activity remains subject to application/runtime admission and user-intent policy from higher-level specifications.
20. Provider APIs expose no transport implementation technology.

## 6. Architectural Position

Conceptually:

```text
Application Workflow / Coordinator
            ↓
ProviderSelectionPolicy
            ↓
MetadataProviderRegistry
            ↓
ProviderSessionFactory
            ↓
ProviderSession
            ↓
Capability Interface
            ↓
Concrete Provider Adapter
            ↓
External Service / SDK / HTTP
```

Application workflows own business intent.

The provider layer owns interaction with external metadata services.

The runtime owns execution and cancellation semantics according to SPEC-BE-004.

The bridge and frontend never communicate with concrete provider implementations directly.

## 7. Provider Identity

Every metadata provider has exactly one stable Argus-owned identity represented by the strongly typed value object:

```text
ProviderId
```

`ProviderId` must not be represented as an unvalidated raw string inside application/provider contracts.

A provider ID is serialized as a stable string only at boundaries that require serialization or persistence.

Illustrative IDs may include:

```text
playmatch
igdb
screenscraper
steamgriddb
```

These examples describe identity shape only and do not mandate provider implementation scope for Phase 000.

### 7.1 Identity Invariants

1. `ProviderId` is immutable.
2. `ProviderId` is globally unique within the metadata-provider family.
3. Provider IDs are assigned and controlled by Argus.
4. Provider IDs are stable across application versions.
5. Provider branding changes do not change `ProviderId`.
6. Provider API URL changes do not change `ProviderId`.
7. Replacing an implementation does not change `ProviderId` when the logical provider identity remains the same.
8. External provider IDs are never used as Argus provider identities.
9. Provider identity is suitable for persistence, diagnostics, provenance, configuration references, and policy references.

## 8. Provider Descriptor

Every registered provider exposes an immutable `ProviderDescriptor`.

Conceptually:

```text
ProviderDescriptor
├── provider_id: ProviderId
├── display_name
├── implementation_version
├── capabilities
└── configuration_requirements
```

The exact Rust representation is an implementation detail.

### 8.1 Descriptor Responsibilities

`ProviderDescriptor` answers static questions such as:

- What provider is this?
- What should it be called in diagnostics or presentation metadata?
- Which capabilities can this implementation support?
- Does it require credentials or other configuration?
- Which implementation/version is currently registered?

It does not answer:

- Is the provider usable right now?
- Are credentials valid right now?
- Is the service currently reachable?
- Should this provider participate in a particular workflow?

Those belong to readiness and selection policy.

### 8.2 Static Capability Declaration

Capabilities are declared statically in the provider descriptor.

The initial capability family includes:

```text
MetadataMatching
MetadataRefresh
ArtworkDiscovery
```

Later specifications may add capabilities without changing the meaning of existing capabilities.

Capability identifiers are Argus-owned application concepts. They must not be named after provider-specific endpoints or transport operations.

## 9. Provider Readiness

`ProviderReadiness` represents the runtime's current view of whether a provider can reasonably satisfy one or more declared capabilities.

The initial readiness states are:

```text
Ready
Disabled
MissingCredentials
InvalidCredentials
Misconfigured
Unavailable
```

### 9.1 Readiness Is Dynamic

Unlike `ProviderDescriptor`, readiness may change during one runtime generation.

Examples:

- a user enables or disables a provider
- credentials become available
- credentials expire
- provider configuration becomes invalid
- an external service becomes temporarily unavailable
- a lightweight readiness validation succeeds after a prior failure

Readiness change does not require runtime replacement.

### 9.2 Configuration-Derived vs Availability-Derived States

The following states primarily describe local configuration or credential conditions:

```text
Disabled
MissingCredentials
InvalidCredentials
Misconfigured
```

`Unavailable` primarily describes transient external availability.

`Ready` means that current known configuration and availability are sufficient to attempt the requested capability. It does not guarantee request success.

### 9.3 Readiness Snapshot Contract

Readiness must be inexpensive to query.

The registry exposes the current readiness snapshot without requiring a network request on every read.

A provider may perform an on-demand lightweight readiness refresh when required before session creation or execution.

Normative rule:

> `ProviderReadiness` is authoritative only for the moment it is observed. Request success must never be inferred solely from a prior readiness snapshot.

### 9.4 Capability-Specific Readiness

Where a provider can be ready for one capability and unavailable for another, readiness should be representable per capability rather than collapsing the provider into one global boolean.

For example:

```text
ProviderReadiness
├── MetadataMatching: Ready
├── MetadataRefresh: Ready
└── ArtworkDiscovery: MissingCredentials
```

A provider implementation must not report a capability as `Ready` if its prerequisites are known to be unsatisfied.

## 10. Metadata Provider Contract Family

Every metadata provider participates in one canonical contract family:

```text
MetadataProvider
├── descriptor()
├── readiness()
└── session_factory()
```

The concrete Rust trait decomposition may differ, but the responsibilities must remain separate.

### 10.1 Provider Object Responsibilities

A runtime-registered provider object owns:

- stable provider identity
- immutable descriptor
- readiness state access
- creation of `JobRun`-attempt-scoped sessions
- provider-specific adapter dependencies required to create sessions

It does not own:

- application workflow state
- authoritative metadata state
- application transaction state
- cross-provider selection policy
- long-lived job results

## 11. MetadataProviderRegistry

`MetadataProviderRegistry` is the immutable runtime-composed catalog of metadata providers available to one `ApplicationRuntime` generation.

Conceptually:

```text
ApplicationRuntime
        ↓
MetadataProviderRegistry
        ├── Provider A
        ├── Provider B
        └── Provider C
```

### 11.1 Registry Responsibilities

The registry may provide:

- enumeration of registered provider IDs
- lookup by `ProviderId`
- descriptor enumeration
- readiness enumeration
- capability-aware provider discovery
- access to the provider's `ProviderSessionFactory`

### 11.2 Registry Non-Responsibilities

The registry must not:

- choose the preferred provider for a workflow
- implement fallback order
- execute provider capabilities
- retry requests
- aggregate provider results
- merge metadata
- resolve conflicts
- map provider results into persisted domain state

Normative rule:

> The registry answers "what providers exist". It does not answer "which provider should be used".

### 11.3 Runtime Generation Ownership

1. Registry membership is fixed during runtime composition.
2. The registry is immutable after the runtime reaches `Ready`.
3. A replacement runtime generation receives a newly composed registry.
4. Provider objects are not reused across runtime generations unless a lower-level immutable dependency is explicitly safe to share and does not violate runtime ownership.

This registry is not a generic service locator. It represents one specific application concept: the set of available metadata providers.

## 12. Provider Session Factory

Each registered provider exposes a `ProviderSessionFactory` responsible for constructing a provider session for one `JobRun` execution attempt.

Conceptually:

```text
ProviderSessionFactory
    ↓
create(job_run_context, session_requirements)
    ↓
ProviderSession
```

`session_requirements` identifies the capability or capabilities known to be required when the session is acquired. It is not a separate capability-specific session identity.

The factory may bind:

- validated provider configuration
- credential access
- provider-specific HTTP/client infrastructure
- retry policy
- rate-limit coordination
- provider-specific adapters

The factory must not start unrelated provider work during construction.

Session creation must verify that every capability declared in the initial session requirements is statically supported and currently `Ready`, performing any permitted lightweight readiness refresh first. If those requirements are not satisfied, session creation returns a canonical `ProviderError` rather than leaking native failures.

If the same `JobRun` execution attempt later needs another capability from that provider, it reuses the existing provider session and performs the applicable support/readiness check before exposing that capability. A second provider session must not be created merely because the capability set expanded.


## 13. Provider Session

`ProviderSession` is the ephemeral execution context for one provider within one `JobRun` execution attempt.

Conceptually:

```text
JobRun Execution Attempt
├── Provider A Session
├── Provider B Session
└── Provider C Session
```

A `JobRun` attempt may use zero, one, or many providers. For any given provider, that execution attempt creates at most one session and reuses it for all interactions with that provider during the attempt.

### 13.1 Session Lifetime

A `ProviderSession`:

1. is created for exactly one `JobRun` execution attempt,
2. belongs to exactly one `ProviderId`,
3. is not reused by unrelated execution attempts,
4. is disposed when the owning `JobRun` completes, fails, or is cancelled,
5. must not outlive the runtime generation that created it.

`JobRunId` is the canonical execution-attempt identity from SPEC-BE-004. Retry or resume creates a new `JobRunId` and therefore new provider sessions; sessions are never carried across execution attempts. This specification introduces no second durable logical-job identity.

The owning application workflow decides the provider-session use within that execution attempt. The provider layer must not extend session lifetime for speculative caching or connection reuse beyond the `JobRun` boundary.

### 13.2 Session-Owned Transient State

A session may own or coordinate transient provider-specific state such as:

- an authenticated provider client,
- access tokens or ephemeral authentication material obtained from approved credential infrastructure,
- one `JobRun`-attempt-scoped request cache,
- request deduplication state,
- provider-specific retry coordination,
- provider-specific rate-limit coordination,
- pagination cursors used during the execution attempt,
- provider-specific transport state,
- transient protocol/session state required by an SDK,
- diagnostic counters or timing data scoped to the execution attempt.

The session is the preferred owner for state that is meaningful only while one `JobRun` execution attempt is interacting with one provider.

### 13.3 State a Session Must Not Own

A session must not own or become the authoritative source for:

- provider configuration,
- persisted credentials,
- provider enablement policy,
- provider preference ordering,
- provider health history,
- application runtime state,
- canonical metadata entities,
- resolved metadata,
- library entities,
- persisted artwork records,
- application transactions,
- cross-provider workflow state.

Long-lived authoritative state belongs to the layers already assigned by ARCH-001 and SPEC-BE-002 through SPEC-BE-009.

### 13.4 Session Capability Exposure

A session exposes only the capability interfaces supported by its provider implementation and permitted by current readiness.

Conceptually:

```text
ProviderSession
├── metadata_matching() -> optional MetadataMatchingCapability
├── metadata_refresh() -> optional MetadataRefreshCapability
└── artwork_discovery() -> optional ArtworkDiscoveryCapability
```

The exact language representation may use typed accessors, capability objects, trait implementations, or another compile-time-safe form.

The architectural requirement is that unsupported capabilities are represented by absence wherever practical, rather than by broad interfaces containing methods that merely return `UnsupportedCapability` at runtime.

`UnsupportedCapability` remains part of the canonical error vocabulary for defensive boundary handling, version skew, or provider-specific cases where capability availability changes after session creation. It is not the preferred normal discovery mechanism.

## 14. Capability Interface Architecture

Provider capability interfaces are Argus-owned gateway contracts representing externally supplied behavior.

Capability interfaces must be:

- provider-independent,
- transport-independent,
- narrowly cohesive,
- immutable in semantic meaning once published,
- additive where practical,
- explicit about request and result types,
- explicit about cancellation support,
- free of bridge DTOs,
- free of persistence models,
- free of provider-native payloads.

Application handlers and coordinators depend on these contracts rather than concrete provider adapters.

### 14.1 Prohibited Generic Dispatch

The following style is prohibited:

```text
provider.execute(capability_name, arbitrary_payload)
```

Likewise prohibited are gateway contracts based on untyped maps, JSON blobs, endpoint names, provider-specific operation strings, or generic request envelopes whose meaning is interpreted dynamically by each adapter.

New provider behaviors must be introduced as explicit capabilities or explicit operations on an existing cohesive capability.

## 15. MetadataMatchingCapability

`MetadataMatchingCapability` finds provider-owned candidate records that may correspond to an Argus game or unresolved library item.

Conceptually:

```text
MetadataMatchingCapability
    ↓
match(request, cancellation)
    ↓
MatchResult
```

### 15.1 Match Request

The request contains application-owned matching evidence, not provider-specific query parameters.

Depending on later metadata specifications, evidence may include:

- normalized title,
- alternate titles,
- platform identity or platform hint,
- region hint,
- release year hint,
- known external identifiers when legitimately available,
- other explicitly standardized matching evidence.

The request must not contain:

- raw HTTP query strings,
- provider endpoint paths,
- provider-native field names,
- provider SDK request objects,
- frontend DTOs,
- database rows.

### 15.2 Match Result

A match result returns zero or more immutable provider candidates.

Each candidate must preserve sufficient provider provenance to allow later application logic to understand where the candidate came from without exposing native provider payloads.

Conceptually:

```text
ProviderMatchCandidate
├── provider_id: ProviderId
├── provider_record_id
├── normalized_identity_fields
├── match_evidence
└── provider_confidence? / provider_score?
```

Any provider score is provider-originated evidence only. It must not be treated as a universal cross-provider confidence scale unless a later application specification explicitly defines normalization semantics.

Selection among candidates, cross-provider ranking, conflict resolution, and persistence are application responsibilities.

### 15.3 Provider Record Identity

A provider's own record identifier must be preserved as a provider-scoped external identifier.

It must never become an Argus entity identity.

The pair:

```text
(ProviderId, provider_record_id)
```

may be used as external provenance or lookup identity where later specifications permit it.

## 16. MetadataRefreshCapability

`MetadataRefreshCapability` retrieves current provider metadata for a known provider record or other provider-independent refresh reference supported by the application contract.

Conceptually:

```text
MetadataRefreshCapability
    ↓
refresh(request, cancellation)
    ↓
ProviderMetadataSnapshot
```

The capability returns provider-sourced information. It does not mutate Argus persistence.

### 16.1 Refresh Request

The request identifies what provider-owned record should be refreshed and may contain application-owned hints needed to disambiguate the request.

A refresh request must not embed persistence commands or instructions for how the returned data should be reconciled with existing Argus metadata.

### 16.2 Refresh Result

The result is an immutable provider metadata snapshot normalized into Argus gateway-level concepts.

It may contain fields such as:

- provider record identity,
- title data,
- release information,
- descriptions,
- genres or categories,
- developer/publisher information,
- platform references,
- external links,
- artwork references,
- provider-specific provenance metadata that has an explicit stable representation.

The precise canonical metadata model is owned by later metadata specifications. SPEC-BE-010 defines only the gateway boundary: native provider payloads must be translated before leaving the adapter.

## 17. ArtworkDiscoveryCapability

`ArtworkDiscoveryCapability` discovers provider-owned artwork candidates associated with a known game candidate or provider record.

Conceptually:

```text
ArtworkDiscoveryCapability
    ↓
discover(request, cancellation)
    ↓
ArtworkDiscoveryResult
```

The capability discovers remote artwork references and metadata. It does not decide which artwork Argus should select, persist, download, crop, transform, or display.

### 17.1 Artwork Candidate

A normalized artwork candidate may include:

- provider identity,
- provider artwork identity when available,
- artwork kind,
- remote resource reference,
- width and height when known,
- language or region when known,
- provider-originated tags,
- provider-originated quality/rating evidence when available,
- provenance required for later refreshes or diagnostics.

Provider-native artwork categories must be translated into Argus-owned gateway concepts where a canonical concept exists. Provider-specific attributes that do not have stable Argus meaning must not silently leak through generic metadata maps.

### 17.2 Remote Resource Safety

A remote artwork reference is external data, not an instruction to fetch arbitrary resources without policy enforcement.

Later download/storage logic must enforce its own network, file, content, and destination rules. Discovery alone does not authorize a download.

## 18. Gateway Request and Result Contracts

Capability requests and results belong to the provider gateway/application boundary.

They are not:

- bridge DTOs,
- domain entities,
- persistence records,
- provider SDK models,
- raw transport payloads.

Contracts should use immutable value objects and stable Argus-owned concepts.

### 18.1 Normalization Boundary

Concrete provider adapters perform translation in both directions:

```text
Argus Gateway Request
        ↓
Provider-native request
        ↓
External service
        ↓
Provider-native response
        ↓
Argus Gateway Result
```

No provider-native response object may escape this boundary.

### 18.2 Lossless-enough, Not Raw

Normalization does not require preserving every field returned by a provider.

It requires preserving the information Argus has deliberately modeled for the capability while maintaining necessary provenance.

ARCH-001's requirement to retain provider-native metadata means retaining provider-sourced semantic records and provenance that Argus deliberately models; it does not require persisting raw HTTP bodies, SDK objects, or unrestricted provider payload blobs. Provider-specific source facts may be retained through typed provider metadata contracts where their semantics are intentionally modeled.

If Argus later needs additional provider data, the gateway contract must be extended deliberately. A catch-all raw payload field must not be used as a substitute for architectural modeling.

## 19. Provider Selection Policy

`ProviderSelectionPolicy` is the dedicated application policy responsible for deciding which registered providers may participate in a workflow requiring one or more capabilities.

Normative rule:

> The registry says what exists. The selection policy says which providers participate.

### 19.1 Inputs

Selection may consider:

- required capability,
- configured provider enablement,
- current readiness snapshot,
- operation mode,
- user/provider preferences when later defined,
- provider-specific refresh policy,
- workflow-specific eligibility constraints explicitly supplied by the application.

Selection must not depend on concrete adapter types.

### 19.2 Output

The policy returns an ordered or otherwise explicitly structured set of eligible `ProviderId` values according to the workflow contract.

The policy does not execute provider requests.

The policy does not merge provider results.

### 19.3 Determinism

For a given:

- runtime provider registry,
- provider configuration state,
- readiness snapshot,
- policy configuration,
- operation input,

the selection result must be deterministic.

Handlers must not implement hidden provider order by relying on hash-map iteration, registration accident, filesystem order, or concrete dependency order.

### 19.4 No Hardcoded Provider Identity in Workflows

Application workflows should express required behavior, for example:

```text
requires MetadataMatching
```

rather than:

```text
call IGDB, then ScreenScraper
```

A workflow may refer to a specific provider only when provider identity is itself part of explicit user intent or the defined business operation, such as a user-requested provider-specific refresh.

### 19.5 Selection Is Not Fallback

Initial selection and runtime fallback are related but distinct.

Selection determines the providers eligible to participate before execution.

Fallback determines what an application workflow should do after an attempted provider interaction produces a terminal outcome.

The provider gateway must not conflate the two.


## 20. Canonical Provider Error Model

Every concrete provider adapter translates provider-native failures into the canonical application-facing provider port error type:

```text
ProviderError
```

`ProviderError` is owned by `argus-application` under the port-error rules of SPEC-BE-003; concrete infrastructure adapters construct and return it after translating native failures. Infrastructure must not define a competing public provider-error vocabulary.

Native SDK exceptions, HTTP library errors, serialization errors, transport errors, and provider-specific error payloads must not escape the provider adapter.

The initial error categories are:

```text
AuthenticationFailed
AuthorizationFailed
RateLimited
Timeout
Unavailable
InvalidRequest
InvalidResponse
ProtocolViolation
UnsupportedCapability
ConfigurationError
Cancelled
```

### 20.1 Error Responsibilities

`ProviderError` describes a failed provider interaction in provider-independent terms.

It may carry structured diagnostic context such as:

- `provider_id`,
- capability,
- provider operation,
- safe external status/code,
- retry-related provider hints,
- safe protocol metadata,
- trace information inherited from the operation context.

It must not expose:

- credentials,
- access tokens,
- authorization headers,
- secret query parameters,
- unsafe full URLs,
- raw provider response bodies by default,
- arbitrary provider SDK exception objects.

### 20.2 Provider Identity Is Context, Not Type

Provider identity must not be encoded by creating provider-specific error variants such as:

```text
IgdbRateLimited
ScreenScraperTimeout
```

Instead:

```text
ProviderError::RateLimited
provider_id = ProviderId(...)
```

This keeps application workflows independent from provider implementations while preserving diagnostic identity.

### 20.3 Error Translation Boundary

Error translation occurs in two stages:

```text
Provider-native failure
        ↓ concrete adapter
ProviderError
        ↓ application handler/coordinator
ApplicationError
```

The application layer translates `ProviderError` into `ApplicationError` according to workflow semantics defined by SPEC-BE-003 and the relevant feature specification.

The bridge and Flutter must never receive `ProviderError` directly.

### 20.4 InvalidRequest

`InvalidRequest` means the provider adapter cannot validly execute an Argus gateway request against the provider under the current request semantics.

It is not a substitute for ordinary application validation. Application-owned input validation should occur before provider execution whenever the application can determine invalidity independently of a provider.

### 20.5 InvalidResponse and ProtocolViolation

`InvalidResponse` describes provider output that cannot be translated into the expected gateway result because required information is malformed, missing, or semantically unusable.

`ProtocolViolation` describes a stronger violation of the provider contract or protocol assumptions, such as an impossible response shape, inconsistent pagination contract, or unsupported protocol state.

These errors should remain distinct because they have different diagnostic and provider-health implications.

### 20.6 Cancelled

`Cancelled` represents cooperative cancellation of provider work and must not be reclassified as `Timeout`, `Unavailable`, or `Internal` merely because the underlying transport library reports cancellation through a generic transport error.

## 21. Retry Ownership

Retry behavior is split explicitly between provider sessions and application workflows.

### 21.1 Transport Retry

`ProviderSession` owns transparent transport-level retries for one logical provider interaction.

A transport retry means:

```text
same provider
+ same logical request
+ same capability interaction
+ no changed application semantics
```

Examples may include retrying after:

- transient connection reset,
- retryable transport timeout,
- provider-declared temporary throttle where the session policy permits waiting,
- retryable 5xx-style service failure,
- equivalent SDK transient conditions.

The exact retry count, delay, backoff, jitter, and provider-specific classification are provider-infrastructure policy details unless promoted by a later specification. They remain subordinate to the owning runtime operation deadline and cancellation signal.

### 21.2 Terminal ProviderError

The application sees a `ProviderError` only after any permitted provider-managed transparent retries for that interaction have completed or when the error is not transparently retryable.

A terminal `ProviderError` must not imply that the application should automatically retry the operation.

### 21.3 Application Semantic Retry

The application owns retry decisions that can affect workflow meaning, timing, provider choice, provenance, or user intent.

Examples include:

- retry later as a new operation,
- retry after user changes credentials,
- defer the job,
- continue with partial results,
- ask another eligible provider,
- fail the overall operation.

These decisions belong to the relevant application handler/coordinator and must use the stable error semantics from SPEC-BE-003.

### 21.4 Runtime Does Not Auto-Retry Providers

The runtime executes admitted operations but does not automatically retry provider interactions or failed application operations merely because they involved a provider.

Automatic runtime-level retry would obscure application semantics and conflict with the ownership rules above.

## 22. Provider Fallback

Provider fallback is an application workflow decision.

Fallback means attempting a different provider after another provider has produced an outcome that the workflow determines permits continuation.

Conceptually:

```text
Provider A attempt
    ↓ terminal outcome
Application fallback policy
    ↓
Provider B attempt
```

### 22.1 Why Fallback Is Not Transport Retry

Switching providers can change:

- data provenance,
- available fields,
- confidence characteristics,
- artwork inventory,
- matching semantics,
- rate-limit consumption,
- credentials used,
- user expectations.

Therefore fallback is never a transparent transport concern.

### 22.2 No Silent Provider Switching

A concrete provider adapter, `ProviderSession`, or registry must never silently call a different provider.

If a workflow uses multiple providers, that fact must be visible at the application orchestration level.

### 22.3 Fallback Eligibility

Later feature specifications may define which terminal outcomes permit fallback.

SPEC-BE-010 does not mandate that every failure should fall back. For example, cancellation must normally stop the workflow rather than trigger another provider.

## 23. Cancellation

Provider gateway operations participate in the cancellation model owned by SPEC-BE-004.

### 23.1 Cancellation Propagation

The owning `OperationContext` cancellation signal must be propagated through:

```text
Application operation
    ↓
Provider interaction
    ↓
ProviderSession
    ↓
Capability implementation
    ↓
Transport / SDK where supported
```

Provider adapters should stop outstanding work promptly when cancellation is observed.

### 23.2 No New Work After Cancellation

Once cancellation has been observed for the owning operation, a session must not begin new provider requests for that operation except minimal cleanup required for resource safety.

Transparent retries must also cease.

### 23.3 Cancellation and Partial Results

Whether already-produced partial results may be retained is an application workflow decision. The provider layer must not persist partial results or publish application events on its own.

## 24. Rate-Limit Coordination

Rate-limit behavior is provider-specific execution infrastructure and is coordinated by the provider session or a provider-owned lower-level component explicitly used by sessions.

### 24.1 Session Responsibility

A session may:

- serialize requests when required,
- honor provider-declared retry-after information,
- apply provider-specific request pacing,
- track remaining request budget when exposed,
- avoid redundant calls using its `JobRun`-attempt-scoped cache,
- translate exhausted limits to `ProviderError::RateLimited`.

### 24.2 Cross-`JobRun`-Attempt Coordination

Some providers enforce limits across all concurrent `JobRun` execution attempts or across an account rather than per session.

A provider implementation may therefore depend on a runtime-scoped rate-limit coordinator shared by that provider's sessions.

Such a coordinator:

- remains provider-infrastructure state,
- must not become application business state,
- must not own provider selection,
- belongs to one runtime generation and is retired with that generation,
- must remain opaque behind provider gateway construction.

Lower-level immutable transport infrastructure may be shared more broadly only when independently safe, but mutable provider rate-limit state is runtime-generation scoped.

### 24.3 Rate Limits Are Not Readiness by Default

Temporary throttling during execution normally produces `RateLimited`, not an immediate permanent readiness transition.

A provider may update its readiness snapshot to `Unavailable` when repeated or provider-declared conditions indicate that attempting new work is currently unreasonable. That transition is provider policy and must remain observable.

## 25. Request Deduplication

A provider session should avoid issuing multiple equivalent provider requests within one job when the provider interaction is safe to reuse.

Deduplication may cover concurrent identical requests as well as already-completed requests cached for the job.

### 25.1 Deduplication Key

A deduplication key must be derived from stable provider-interaction semantics, not from unsafe raw object addresses or incidental serialization order.

The key may include:

- provider identity,
- capability,
- normalized request identity,
- provider-relevant request options.

### 25.2 Safety

Only interactions that are semantically safe to reuse may be deduplicated.

A capability operation with externally visible mutation, one-time tokens, cursor advancement, or other non-idempotent provider behavior must not be deduplicated merely because request bytes are equal.

## 26. `JobRun`-Attempt-Scoped Request Cache

Each `ProviderSession` may maintain a request/result cache for its owning `JobRun` execution attempt.

The primary purpose is to:

- reduce duplicate provider calls,
- reduce rate-limit consumption,
- share repeated lookup results across steps of one workflow,
- make multi-step provider interactions consistent within one execution attempt.

### 26.1 Cache Lifetime

The default provider request cache lifetime is exactly the provider session lifetime.

The cache is discarded when the owning `JobRun` execution attempt terminates.

### 26.2 No Authoritative Application Cache

A provider request cache is not an authoritative application cache.

It must not replace:

- persisted metadata,
- application query models,
- repository reads,
- provider readiness state,
- provenance records.

Longer-lived provider caching requires a separate explicit architecture decision because freshness, invalidation, privacy, and persistence semantics differ from `JobRun`-attempt-scoped reuse.

### 26.3 Cache Failure Semantics

Cache implementation failures must not silently alter provider result semantics. If a cache is purely an optimization, the implementation should prefer safe cache bypass where possible rather than failing valid provider work solely because the optimization failed.

## 27. Observability

Provider interactions follow SPEC-BE-003 observability rules.

### 27.1 Trace Identity

Provider interactions inherit the `TraceId` of the top-level application operation executing them.

A provider session does not create a new top-level trace merely because an external request occurs.

### 27.2 Structured Context

Provider-related log, metric, and trace fields should use stable structured identifiers such as:

```text
provider_id
provider_capability
provider_operation
provider_readiness
provider_error_category
provider_attempt
transport_retry_count
```

Provider display names and URLs must not substitute for `provider_id` as the canonical identity field.

### 27.3 Identity-First Observability

Where the provider interaction is associated with an existing Argus-owned entity identity, that identity should also be included according to SPEC-BE-003's identity-first observability rules.

External provider record IDs may be included as safe structured provenance when useful, but never as a replacement for Argus identity once an Argus identity exists.

### 27.4 Secret Safety

Provider observability must never record credentials, tokens, secrets, authorization headers, or provider URLs containing secret query values.

Provider response bodies must not be logged by default.

If narrowly scoped diagnostic capture is introduced later, it must follow the explicit diagnostic and sanitization rules in SPEC-BE-003.

## 28. Provider Readiness and Provider Health

SPEC-BE-003 reserves coarse provider health states for operational observability when post-MVP provider health is implemented:

```text
Healthy
Degraded
Unavailable
Disabled
```

SPEC-BE-010 defines capability-aware `ProviderReadiness` for application selection and session admission:

```text
Ready
Disabled
MissingCredentials
InvalidCredentials
Misconfigured
Unavailable
```

These concepts are related but are not the same type and must not be collapsed.

### 28.1 Readiness Purpose

Readiness answers:

> Can this provider reasonably attempt this capability now?

It is consumed by registry/selection/session-admission logic.

### 28.2 Health Purpose

Health answers:

> What is the operational condition of this provider for diagnostics and observability?

It is intended for diagnostics, health summaries, and operational visibility.

### 28.3 Mapping

A provider implementation may derive health from readiness plus recent execution signals.

Illustrative mappings include:

```text
Ready                         -> Healthy or Degraded
Disabled                      -> Disabled
MissingCredentials            -> Degraded or Unavailable
InvalidCredentials            -> Degraded or Unavailable
Misconfigured                 -> Degraded or Unavailable
Unavailable                   -> Unavailable
```

The configuration-derived states map to `Degraded` only when some configured capabilities remain usable; they map to `Unavailable` when required configured capabilities are unusable. This mapping is intentionally not one-to-one. A provider can also be `Ready` while operationally `Degraded`, for example when recent requests are succeeding only after retries.

Health must not be used as a substitute for capability-specific readiness in provider selection. Provider health implementation itself remains post-MVP as required by ARCH-001.

## 29. Readiness Refresh

Readiness is maintained as a snapshot with provider-owned refresh behavior.

### 29.1 Lightweight Refresh

Before creating a session for a selected capability, the provider may perform a lightweight readiness refresh when:

- the snapshot is stale according to provider policy,
- credentials changed,
- configuration changed,
- a recent execution outcome invalidated the prior snapshot,
- the provider requires a cheap token/configuration validation.

A readiness refresh must not perform substantial metadata work merely to answer readiness.

### 29.2 Refresh Ownership

The provider implementation owns how provider-specific signals are translated into `ProviderReadiness`.

The application owns when readiness is required for workflow selection/admission.

The registry exposes the snapshot but does not invent provider-specific readiness logic.

### 29.3 Readiness Changes During a Job

Readiness may change after a session is created.

The session remains responsible for translating actual execution failures into `ProviderError`. Application workflows must handle those terminal outcomes rather than assuming session creation guaranteed continued readiness.


## 30. Provider Configuration and Credentials

Provider configuration is long-lived application/configuration state and is not owned by `ProviderSession`.

### 30.1 Configuration Boundary

Concrete provider adapters may consume an Argus-owned typed configuration view supplied during runtime composition or session creation.

Application-facing provider contracts must not expose raw configuration files, environment-variable names, secret-store APIs, or provider SDK configuration objects.

### 30.2 Credentials

Credential storage and secret retrieval are separate infrastructure responsibilities.

A provider implementation may receive a credential access abstraction capable of obtaining only the credentials required by that provider.

Rules:

1. Credentials are never stored in `ProviderDescriptor`.
2. Credentials are never returned by readiness APIs.
3. Credentials are never embedded in `ProviderError`.
4. Credentials are never exposed in gateway result contracts.
5. Credentials are never persisted in provider request caches unless an explicitly approved secure credential subsystem requires it.
6. Credential changes may invalidate readiness and existing sessions as defined by provider policy.

### 30.3 Enablement

Provider enablement is configuration/policy state, not registry membership.

A disabled provider may remain registered in `MetadataProviderRegistry` with readiness `Disabled`.

This distinction allows stable discovery, settings, diagnostics, and identity without reconstructing the runtime every time a provider is enabled or disabled.

## 31. Provider Construction and Runtime Composition

Metadata provider implementations are composed as part of one runtime generation.

Conceptually:

```text
ApplicationHost
    ↓ constructs
ApplicationRuntime
    ↓ composes
MetadataProviderRegistry
    ├── provider adapters
    ├── provider factories
    └── provider-specific infrastructure
```

### 31.1 Composition Rules

1. Concrete providers are created in the composition root/infrastructure layer.
2. Provider implementations are registered by stable `ProviderId`.
3. Duplicate provider IDs are a composition error.
4. Descriptor capability declarations must agree with the capabilities a session can expose.
5. Runtime readiness must not require contacting every optional metadata provider unless a later phase explicitly promotes a provider to mandatory startup infrastructure.
6. Provider-specific construction failures should normally yield provider readiness/diagnostic state rather than making the entire application runtime unusable when that provider is optional.

### 31.2 Phase 000 Boundary

PHASE-000 explicitly excludes metadata matching, provider sessions, metadata refresh, and artwork discovery.

Therefore SPEC-BE-010 is a forward architecture contract. Its existence does not add provider initialization to the Phase 000 startup critical path or Phase 000 implementation slices.

## 32. Application Service and Coordinator Integration

SPEC-BE-009 remains authoritative for application-service dependency rules.

Application services and workflow coordinators may depend on explicit provider-facing application abstractions required by their owned capabilities.

They must not depend on:

- concrete provider adapters,
- provider SDKs,
- HTTP clients,
- provider-native models,
- provider-specific retry components.

### 32.1 Registry Visibility

`MetadataProviderRegistry` is a first-class provider catalog, not a generic service locator.

Application code may consume it only through explicitly declared provider workflow dependencies where provider discovery is genuinely part of that workflow.

The registry must not be exposed as a mechanism for resolving arbitrary application services, repositories, or infrastructure dependencies.

### 32.2 Selection Policy Ownership

`ProviderSelectionPolicy` is an application-level policy that consumes provider catalog/readiness information but remains independent of concrete provider adapters.

A workflow coordinator may use the policy to obtain eligible provider identities and then obtain the corresponding provider session factory through the provider-facing gateway boundary.

This explicit usage does not violate SPEC-BE-009's prohibition on a generic gateway locator because:

- the registry contains only metadata providers,
- provider identity is a first-class application concept,
- capability discovery is part of the provider architecture,
- resolution is bounded to one explicit provider family,
- arbitrary infrastructure resolution is impossible.

## 33. Transaction Boundaries and Provider I/O

Provider network calls must not be hidden inside repository implementations or database transaction machinery.

### 33.1 Avoid Long-Lived Transactions Across Provider Calls

Application workflows should not hold a database write transaction open across arbitrary provider network activity.

Preferred flow for long or uncertain provider work:

```text
Read required authoritative state
    ↓
Perform provider interactions outside write transaction
    ↓
Validate/reconcile results in application layer
    ↓
Open UnitOfWork
    ↓
Persist one authoritative checkpoint
    ↓
Commit
```

A later feature specification may define a different transactional arrangement only with explicit justification and failure semantics.

### 33.2 Provider Layer Does Not Commit

Provider sessions and capabilities:

- do not create Unit of Work instances,
- do not invoke repositories,
- do not commit application transactions,
- do not publish application events.

They return provider interaction results to the application workflow that owns authoritative state changes.

## 34. Event Semantics

Provider adapters do not publish application/domain events directly.

If a provider interaction causes an application-significant fact after reconciliation or persistence, the owning application handler/coordinator decides whether an event should be recorded in the operation `EventCollector` according to SPEC-BE-006 and SPEC-BE-009.

Transport retries, rate-limit waits, readiness refreshes, and request-cache hits are observability facts, not application events by default.

## 35. Provenance

Provider-sourced data must preserve provider provenance wherever the data can later influence authoritative metadata, user-visible values, refresh decisions, or diagnostics.

At minimum, provenance must be able to identify:

- `ProviderId`,
- provider-scoped source record identity where available,
- the provider capability/interaction that produced the data when relevant.

Later metadata specifications own persisted provenance structure and field-level provenance rules.

Provider branding or display name is not provenance identity.

## 36. Provider-Specific Refresh Policy

ARCH-001 defines provider-specific metadata refresh policy, including concepts such as:

```text
stale_after
refresh_on_provider_revision_change
preserve_stale_on_failure
```

These policies are provider/application policy inputs. They are not decisions made autonomously by `ProviderSession`.

The application refresh workflow evaluates eligibility and constructs an immutable refresh plan. A selected provider session executes the requested fetches.

Normative rule:

> Providers execute requested refresh interactions; application workflow policy decides whether a provider/game pair should be refreshed.

Supported invocation modes and final metadata-refresh semantics remain owned by the metadata feature specification and ARCH-001.

## 37. Provider Concurrency

Provider concurrency is constrained by both runtime operation policy and provider-specific execution policy.

A provider implementation may limit concurrent requests for reasons such as:

- documented provider quotas,
- account-level rate limits,
- connection limits,
- SDK safety,
- provider fairness.

The provider layer must not create an independent general-purpose scheduler competing with `ApplicationRuntime`.

Provider-specific concurrency controls are subordinate execution controls inside admitted runtime work.

## 38. Timeouts

Provider interactions must have bounded timeout behavior appropriate to the provider and operation.

Timeout policy may distinguish:

- connection timeout,
- individual request timeout,
- provider interaction deadline,
- application operation deadline supplied by runtime/workflow context.

A provider-specific timeout must not exceed a stricter owning operation deadline.

Timeout exhaustion is translated to `ProviderError::Timeout` unless the owning cancellation signal caused termination, in which case it is `Cancelled`.

## 39. Pagination and Streaming

Provider capabilities may internally use pagination or streaming APIs.

Those transport mechanisms must remain hidden unless pagination/streaming is itself part of the stable Argus capability semantics.

A capability may return an application-appropriate collection, iterator/stream abstraction, or paged gateway result only when the contract explicitly defines lifecycle, cancellation, error, and ownership semantics.

Raw provider page tokens and SDK streams must not leak into application code by default.

## 40. Provider Protocol Evolution

Provider APIs and SDKs can change independently of Argus.

Concrete provider adapters absorb compatible provider protocol changes without changing application-facing capability semantics.

If a provider change alters the meaning of an Argus capability rather than merely its implementation, the capability contract must be evolved deliberately rather than silently reinterpreted.

Stable Argus semantics take precedence over mirroring provider-native models.

## 41. Crate and Layer Ownership

Exact crate names and dependency direction follow SPEC-BE-001. Conceptually:

### Domain Layer

Owns `ProviderId` as the stable pure Argus-owned provider identity, consistent with SPEC-BE-001's typed-identifier ownership. It may own additional pure provider-related value concepts only when they are genuinely domain concepts.

It does not own HTTP clients, provider adapters, SDK types, readiness probes, provider sessions, or provider execution policy.

### Application Layer

Owns or defines stable application-facing provider capability contracts and policies where required, including:

- `ProviderDescriptor` and `ProviderReadiness` contracts,
- provider session and session-factory contracts,
- capability request/result concepts,
- canonical `ProviderError`,
- provider selection policy semantics,
- workflow orchestration that uses provider capabilities,
- translation from terminal provider outcomes into application semantics.

### Runtime Layer

Owns operation execution, cancellation context, admission, and runtime-generation lifecycle.

It does not choose providers as business policy and does not retry provider failures automatically.

### Infrastructure Layer

Owns concrete provider adapters and provider-specific machinery, including:

- HTTP/SDK integration,
- authentication implementation,
- native payload translation,
- transport retry classification,
- rate-limit coordination,
- provider request caching,
- readiness probing/refresh implementation.

### Bridge Layer

May expose provider-related application capabilities and canonical DTOs defined by SPEC-BE-008/later bridge feature specs.

It does not invoke concrete provider adapters directly and never exposes `ProviderError` or provider-native types.

## 42. Dependency Rules

The following dependency rules are normative:

1. Provider adapters may depend inward on stable Argus gateway contracts.
2. Stable gateway contracts must not depend outward on provider SDKs or HTTP libraries.
3. Application handlers/coordinators must not import concrete provider adapters.
4. Provider adapters must not import bridge/generated DTO modules.
5. Provider adapters must not call repositories or Unit of Work implementations.
6. Provider sessions must not depend on application services.
7. Provider registry must not become a general dependency resolver.
8. Provider selection policy must not inspect concrete adapter types.
9. Capability contracts must not expose provider-native payload types.
10. Provider error contracts must not expose native error types.

## 43. Architecture Tests

Architecture checks should enforce, where practical:

- application/provider-contract modules do not import concrete provider SDKs,
- concrete provider adapters do not leak into application service signatures,
- bridge modules do not directly instantiate provider adapters,
- provider session modules do not import repositories or Unit of Work implementations,
- capability contracts contain no raw transport payload types,
- `ProviderId` is used instead of arbitrary provider-name strings in stable internal contracts,
- no generic capability dispatch API exists,
- no provider adapter calls another provider as fallback,
- registry APIs remain provider-family-specific.

Compile-time module/crate boundaries are preferred to convention-only tests.

## 44. Unit Testing Requirements

Every concrete provider adapter must be testable without calling the live external service for ordinary unit/contract tests.

Tests should use controlled transport/SDK fakes at the adapter's infrastructure boundary.

Required coverage includes, as applicable:

- descriptor identity and capability declarations,
- readiness derivation,
- readiness refresh behavior,
- session creation prerequisites,
- capability absence for unsupported capabilities,
- request translation,
- response normalization,
- provider record provenance,
- native error to `ProviderError` translation,
- secret-safe error context,
- transparent retry classification,
- retry exhaustion,
- cancellation propagation,
- rate-limit handling,
- request deduplication,
- `JobRun`-attempt-scoped cache reuse,
- cache isolation across execution attempts.

## 45. Provider Contract Tests

Reusable provider contract tests should validate all adapters against common invariants.

Examples:

1. descriptor `provider_id` equals registry identity,
2. descriptor capabilities match session capability exposure,
3. disabled/not-ready capabilities cannot create usable sessions incorrectly,
4. native payload types do not appear in normalized results,
5. all terminal native failures translate to `ProviderError`,
6. cancellation is preserved as cancellation,
7. provider identity is present in diagnostic error context,
8. sessions do not outlive their job contract,
9. unsupported capabilities are discoverable as absent rather than failing late where practical.

## 46. Selection Policy Tests

`ProviderSelectionPolicy` tests must verify:

- disabled providers are excluded,
- providers lacking the required capability are excluded,
- providers whose capability readiness is not `Ready` are excluded unless an explicit workflow rule allows a pre-selection refresh,
- ordering/preferences are deterministic,
- registration iteration order cannot change the result,
- explicit provider user intent is honored where supported,
- concrete provider implementation types do not affect selection.

## 47. Retry and Fallback Tests

Tests must distinguish transport retry from application fallback.

Required scenarios include:

- retryable same-provider transport failure succeeds on a later transparent attempt,
- retry budget exhaustion returns one terminal `ProviderError`,
- non-retryable provider failure is returned immediately,
- cancellation stops transparent retries,
- a provider session never invokes another provider,
- application fallback, when a feature defines it, occurs only after the workflow receives the terminal outcome,
- provenance reflects the provider that actually produced each result.

## 48. Observability and Security Tests

Tests must verify:

- stable `provider_id` is emitted in provider observability context,
- credentials/tokens/auth headers are absent from logs and errors,
- raw provider response bodies are not logged by default,
- retry attempts remain correlated to the owning operation `TraceId`,
- provider-native error text is sanitized before inclusion in safe context,
- diagnostic representation does not expose secret-bearing URLs.

## 49. Integration Testing

Live provider integration tests, when added, must be clearly separated from deterministic unit/contract tests.

They should:

- be opt-in where credentials/network are required,
- avoid becoming required for ordinary offline development unless a provider's public test endpoint makes that reliable,
- use provider-approved test behavior,
- avoid destructive or excessive API consumption,
- never commit credentials to the repository.

A live service must not be required to prove basic gateway architecture correctness.

## 50. Acceptance Criteria

SPEC-BE-010 is satisfied when:

1. Metadata/external-service providers are architecturally separate from source/storage providers.
2. Every metadata provider has one stable strongly typed Argus-owned `ProviderId`.
3. Every provider exposes an immutable static `ProviderDescriptor`.
4. Static capability declaration is separate from dynamic capability-aware `ProviderReadiness`.
5. Readiness uses the states `Ready`, `Disabled`, `MissingCredentials`, `InvalidCredentials`, `Misconfigured`, and `Unavailable`.
6. Readiness is an inexpensive snapshot and may be refreshed on demand according to provider policy.
7. One runtime generation owns one immutable-membership `MetadataProviderRegistry`.
8. The registry catalogs providers but does not select, route workflow semantics, retry, merge, or fall back.
9. `ProviderSelectionPolicy` owns deterministic eligibility/ordering decisions without depending on concrete adapters.
10. Each provider exposes a `ProviderSessionFactory`.
11. Each `JobRun` execution attempt creates at most one session per provider.
12. Sessions are never reused across unrelated execution attempts.
13. Sessions own only provider-specific transient execution state.
14. Sessions expose only supported/ready capability interfaces wherever practical.
15. Capability interfaces are small, typed, provider-independent, and behavior-oriented.
16. Generic capability dispatch and arbitrary payload APIs are prohibited.
17. `MetadataMatchingCapability`, `MetadataRefreshCapability`, and `ArtworkDiscoveryCapability` follow the boundaries defined here.
18. Provider-native requests/responses are translated entirely inside concrete adapters.
19. Provider-native errors are translated to canonical `ProviderError` before leaving the adapter.
20. `ProviderError` uses provider identity as structured context rather than provider-specific error types.
21. Provider sessions own transparent same-provider transport retries.
22. Application workflows own semantic retry, continuation, deferral, and provider fallback decisions.
23. Neither runtime nor provider adapters silently switch providers.
24. Cancellation propagates from the owning runtime operation through provider work and stops new requests/retries.
25. Provider-specific rate limiting remains inside provider infrastructure and may coordinate across sessions when necessary.
26. Request deduplication and request caching are `JobRun`-attempt-scoped by default.
27. Provider request caches never become authoritative application state.
28. Provider observability follows SPEC-BE-003, including `TraceId`, stable provider identity, and secret sanitization.
29. Readiness and operational provider health remain distinct concepts.
30. Credentials and provider configuration do not leak through gateway contracts.
31. Provider network activity is not hidden inside repositories or application database transaction machinery.
32. Provider sessions never own Unit of Work, repositories, persistence commits, or application event publication.
33. Provider provenance is preserved in normalized results where required.
34. Provider-specific refresh policy is evaluated by application workflow policy; providers execute requested fetches.
35. Concrete provider implementations remain infrastructure adapters behind stable Argus-owned contracts.
36. Architecture, contract, selection, retry/fallback, observability, and security tests enforce the defined boundaries.

## 51. Prohibited Patterns

The following patterns are prohibited unless a future specification explicitly supersedes this rule:

- one generic abstraction combining metadata providers and source/storage providers,
- raw provider-name strings in place of `ProviderId` in stable internal contracts,
- provider IDs derived from display names or API URLs,
- provider SDK/HTTP types in application-facing capability signatures,
- provider-native response payloads escaping adapters,
- bridge DTOs used as provider gateway contracts,
- generic `execute(capability, payload)` provider interfaces,
- capability interfaces containing unrelated provider operations,
- unsupported capability methods implemented only as routine runtime failures when absence can represent support statically,
- application handlers hardcoding provider order as concrete provider names,
- registry iteration order determining workflow behavior,
- registry-owned business selection policy,
- provider-owned cross-provider fallback,
- runtime-owned automatic provider retry,
- long-lived provider sessions reused by unrelated `JobRun` execution attempts,
- provider sessions owning authoritative application state,
- provider sessions owning repositories or Unit of Work,
- provider adapters publishing application events,
- request caches used as durable metadata stores,
- credentials in descriptors, errors, logs, diagnostics, or gateway results,
- full provider response-body logging by default,
- database write transactions held across arbitrary external provider calls without explicit feature specification,
- provider health used as a substitute for capability readiness,
- generic service locator behavior hidden behind `MetadataProviderRegistry`.

## 52. Deferred Decisions

Source/storage provider architecture is defined by SPEC-BE-011 and is outside this specification rather than an unresolved decision here.

This specification intentionally defers:

- exact metadata canonical entities and reconciliation rules,
- exact provider preference UI and persistence schema,
- exact credential-store technology,
- exact HTTP client/SDK choices,
- exact transport retry timing constants,
- exact cross-`JobRun`-attempt circuit-breaker implementation,
- cross-`JobRun`-attempt durable provider response caching,
- provider plugin/discovery system,
- third-party provider loading,
- final persisted provider health history,
- final provider-specific capability catalogs beyond the initial capability family,
- exact artwork download/storage pipeline,
- exact live integration-test credentials/environment conventions.

Provider health, circuit breaking, and cross-`JobRun`-attempt runtime health indicators remain post-MVP implementation concerns as stated by ARCH-001. The readiness contract in this specification is required independently of those deferred operational features.

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
- [SPEC-BE-009 — Application Service Contracts](spec-be-009-application-service-contracts.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](spec-be-011-source-provider-and-indexing-contract.md)
- [Backend Specifications Index](README.md)
