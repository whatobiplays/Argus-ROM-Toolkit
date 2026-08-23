# Transformation and Hash-Scheme Contract Specification

**Document ID:** SPEC-BE-012  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-23  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-003, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-006, SPEC-BE-007, SPEC-BE-009, SPEC-BE-011  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the canonical backend contract for typed content transformations, operation-scoped parsing, canonical content recognition, strong `ContentIdentity`, derived-container observations, source-version evidence for derived entries, demand-driven hash schemes, identity migration, and persistence of identity/hash provenance in Argus ROM Toolkit.

SPEC-BE-011 defines how Argus obtains trustworthy storage observations and stable source reads. This specification begins at that boundary. It defines how validated source data becomes typed logical content and how Argus persists only durable facts whose derivation and validity can be proven explicitly.

The governing rule is:

> Argus derives logical content through deterministic typed transformations over validated source data; establishes one current versioned canonical identity with explicit provenance; computes independently versioned hashes against explicit source or content subjects; and persists only durable facts whose validity can be proven without retaining parser execution state.

### 1.1 Activation scope

This is the generic forward MVP transformation/identity contract. Ready status by itself does not activate parsers, hashing, identity-maintenance jobs, schema, dependencies, fixtures, or placeholder modules. PHASE-003 activates concrete production recognition and identity-scheme coverage through SPEC-BE-014 while this specification remains authoritative for the generic mechanics those schemes must obey.

## 2. Scope

This specification covers:

- typed representation contracts
- transformation registration and runtime composition
- deterministic transformation planning
- transformation applicability
- `TransformationId` and implementation revisioning
- operation-scoped `ParsingSession`
- session-scoped `ParsedContent`
- sequential, seekable, and random-access input requirements
- transient disk-backed staging
- source-read validation integration
- application-owned transformation resource budgets
- transformation outcome and failure semantics
- authoritative platform/content recognition
- canonical content units spanning one or more source entries
- `ContentIdentityScheme`
- `ContentIdentity`
- `identity_revision`
- one-current-identity semantics
- identity convergence and `GameContent` materialization
- exact identity derivation provenance
- `NeedsReidentification`
- targeted eager identity migration
- source replacement and rebinding
- duplicate-identity conflict handling
- derived-container observation contracts
- `DerivedLocator`
- `DerivedEntryKey`
- `DerivedFingerprint`
- common `SourceVersionEvidence`
- derived-scope reconciliation authority
- source-scoped and content-scoped hash schemes
- `hash_scheme_id`
- `hashing_revision`
- `SourceHashRecord`
- `ContentHashRecord`
- demand-driven hash planning and reuse
- persistence and Unit of Work boundaries
- runtime, cancellation, retry, recovery, diagnostics, and event integration
- architecture, contract, migration, resource-safety, and integration testing

## 3. Non-Responsibilities

This specification does not define:

- source-provider discovery, root enumeration, or native source reconciliation beyond the contracts inherited from SPEC-BE-011
- metadata-provider matching, fallback, or refresh
- metadata resolution policy
- artwork object storage or download behavior
- RetroAchievements catalog import or verification policy
- automatic duplicate-`GameContent` merging
- final `GameContent` orphan-retention or deletion policy
- title/release-level grouping of independently usable multi-disc content
- persistent parsed-representation caches
- filesystem watching
- provider-specific remote staging optimizations
- user-configurable parser resource budgets
- parser-library implementation internals
- exact digest-library selection
- exact SQL migration text or index syntax
- bridge DTO shapes
- frontend presentation behavior

RetroAchievements-compatible hash algorithms may later be implemented as hash schemes under this specification, but RetroAchievements catalog, eligibility, verification, and result-lifecycle policy remain a separate subsystem.

## 4. Architectural Principles

1. Consumers request typed representations, identities, or hash schemes; they do not select parser chains.
2. Transformation planning is application-owned and deterministic.
3. Registration order never affects transformation behavior.
4. Transformation implementations do not own repositories, transactions, jobs, or application policy.
5. Applicability checks are bounded and side-effect free.
6. Only `NotApplicable` permits deterministic transformation fallback.
7. A recognized malformed or unsupported format is a real failure, not evidence that another parser should guess.
8. Parsed/intermediate representations are operation-scoped in MVP.
9. Whole-file memory buffering is never required merely to fake seekability or read atomicity.
10. Transformations declare byte-access requirements explicitly.
11. Transient staging is infrastructure-backed, operation-scoped, and not persistent source state.
12. Every transformation operation executes under an immutable application-owned resource budget.
13. Provider-native and transformation-derived version evidence remain distinct.
14. Neither provider fingerprints nor derived fingerprints are strong content identity.
15. Authoritative platform and content recognition comes from validated transformations, not filenames or directory placement.
16. `ContentIdentity` is Argus-owned canonical logical-content identity under an immutable semantic scheme.
17. One `GameContent` has at most one current `ContentIdentity`.
18. `GameContent` is created only after strong content identity is established.
19. Logical content identity may depend on multiple source entries.
20. Independently usable discs remain independently identified `GameContent` entities.
21. Identity provenance records the exact source basis that established the current identity.
22. `GameContentSource` remains an unversioned association and is not treated as current identity proof.
23. Identity repair is centralized in the dedicated re-identification workflow rather than hidden inside unrelated operations.
24. A source that changes to different content is rebound; an existing `GameContent` is never mutated into unrelated content.
25. Hash schemes explicitly declare whether they describe a source representation or canonical logical content.
26. Source and content hashes use separate persistence concepts.
27. Every durable derived fact owns its own versioning and validity contract.
28. Source I/O, transformation work, staging, canonicalization, and hashing occur outside database write transactions.
29. Durable facts publish events only after the owning Unit of Work commits.
30. Cancellation, retry, logging, diagnostics, and durable job lifecycle reuse SPEC-BE-003 and SPEC-BE-004.

## 5. Architectural Position

Conceptually:

```text
SourceEntry / source graph
        ↓
LibrarySourceAccess.open_stream()
        ↓
SourceRead
        ↓
ParsingSession
        ↓
application-owned transformation planner
        ↓
typed representations
        ├── derived scope observations -> indexer reconciliation
        ├── recognized canonical content -> ContentIdentity
        └── hash-scheme inputs -> hash result
        ↓
validated stable derivation result
        ↓
short application Unit of Work
        ↓
persistent identity / provenance / hash facts
        ↓ commit
post-commit events
```

The application layer owns planning and durable state transitions. Infrastructure supplies parser libraries, byte-stream adapters, temporary storage, and digest implementations. The runtime executes admitted work but does not choose parsers, identity schemes, hash schemes, or source semantics.

## 6. Layer Ownership

### 6.1 Domain

The domain owns stable logical concepts that do not depend on parser or storage implementation details, including:

- `GameContentId`
- `PlatformId`
- logical content type
- `ContentIdentity` value semantics
- source/content relationship semantics where domain-owned

The domain does not depend on parser libraries, provider locators, stream handles, SQLite, staging paths, or bridge DTOs.

### 6.2 Application

The application layer owns:

- transformation descriptors and registry contracts
- deterministic transformation planning
- recognition policy
- current identity-scheme selection
- hash-scheme selection
- `ParsingSession` lifecycle
- resource-budget policy
- content-identification orchestration
- `GameContent` convergence
- identity provenance
- `NeedsReidentification`
- identity migration
- identity-conflict handling
- derived-container handoff to indexing
- hash validity and persistence decisions
- Unit of Work lifecycle
- event publication after commit

### 6.3 Runtime

The runtime owns only execution mechanics inherited from SPEC-BE-004:

- admission
- execution context
- cancellation propagation
- background job state
- bounded retry policy when applicable
- interruption and recovery coordination

The runtime does not own transformation or identity semantics.

### 6.4 Infrastructure

Infrastructure owns replaceable mechanisms such as:

- parser-library adapters
- digest implementations
- source-stream adapters
- seekable/random-access adapters
- temporary-file creation and cleanup
- disk-backed staging
- platform filesystem primitives used for staging

Infrastructure returns application-owned results and errors at architectural boundaries.

### 6.5 Indexer

The indexer remains the sole owner of reconciling persistent `SourceEntry` graph state.

Transformation implementations may describe derived container entries but never create, update, delete, or reparent `SourceEntry` records directly.

## 7. Core Terminology

The following terms are normative:

| Term | Meaning |
|---|---|
| `RepresentationType` | Stable application-visible type identity for one transient parsed representation |
| `TransformationId` | Stable semantic identity of one typed transformation capability |
| `TransformationRevision` | Current trusted Argus implementation revision for that transformation |
| `ParsingSession` | Operation-scoped owner of transformation cache, staging, budget, and cancellation context |
| `ParsedContent` | Session-local typed representation cache |
| `ContentUnit` | One canonical logical-content unit that may require one or more source entries |
| `ContentIdentitySchemeId` | Immutable semantic identity of one canonical-content identity procedure |
| `IdentityRevision` | Current trusted Argus implementation revision of that identity procedure |
| `ContentIdentity` | Strong scheme-scoped identity for one canonical logical-content unit |
| `ContentIdentityProvenance` | Exact source/version basis that established the identity |
| `HashSchemeId` | Immutable semantic identity of one hashing procedure |
| `HashingRevision` | Current trusted Argus implementation revision of that hashing procedure |
| `DerivedLocator` | Transformation-owned opaque coordinate inside a derived container |
| `DerivedEntryKey` | Transformation-owned persistent equality key for one derived entry in its containing derived scope |
| `DerivedFingerprint` | Transformation-owned cheap version evidence for a derived `SourceEntry` |
| `SourceVersionEvidence` | Application abstraction over provider or derived version evidence |

## 8. Typed Representation Model

Transformations communicate through application-defined typed representations rather than parser-library objects.

Representative representation types include:

```text
SourceFile
SeekableBytes
ContainerContent
ArchiveEntries
DiscImage
ISO9660Filesystem
PlayStationDisc
PlayStation2Disc
GameCubeDisc
NESRom
SNESRom
ExecutableMetadata
PartitionTable
RecognizedContent
CanonicalContentUnit
```

This list is illustrative rather than exhaustive.

A representation contract defines what downstream consumers may rely on. Parser-library handles may be wrapped internally, but infrastructure-native types must not become cross-layer public contracts.

## 9. Transformation Registry

One runtime generation owns one immutable `TransformationRegistry`.

Registry membership is composed during runtime construction and remains fixed for that generation.

Conceptually:

```text
TransformationRegistry
- descriptors
- executors
```

Each registered transformation has a stable descriptor.

```text
TransformationDescriptor
- transformation_id
- input_types
- output_type
- applicability
- access_requirement
- estimated_cost
- priority
- implementation_revision
```

The exact Rust generic shape is an implementation decision, but these semantics are fixed.

### 9.1 `TransformationId`

`TransformationId` identifies the intended semantic typed conversion contract.

A semantic transformation change that intentionally changes the meaning of the produced representation requires a new transformation identity or a new representation contract, as appropriate.

### 9.2 `implementation_revision`

`implementation_revision` identifies which Argus implementation of the same intended transformation semantics is currently trusted.

A parser/canonicalizer defect fix or implementation change that can alter previously derived results while preserving intended semantics increments this revision.

Later cache/provenance rules may use the effective transformation revision to invalidate affected derived state.

## 10. Applicability Contract

Transformation applicability is a bounded application-facing predicate over already known facts.

It may use:

- known source structural kind
- bounded cheap metadata
- known platform/content hints
- already materialized typed representations in the current `ParsingSession`
- explicit operation policy

It must not perform:

- network calls
- repository mutation
- arbitrary database queries from inside a parser
- provider-specific metadata lookups
- hidden whole-file hashing
- unbounded source reads
- persistent state changes
- UI interaction

If determining applicability requires parsing or meaningful byte inspection, that work is represented as another transformation rather than hidden inside the applicability predicate.

Cheap hints may narrow candidates but do not become authoritative content recognition.

## 11. Deterministic Transformation Planner

Consumers request a target representation, not a parser or parser chain.

The application planner:

1. identifies transformations capable of eventually producing the requested representation;
2. removes candidates whose declared applicability is false;
3. prefers representations already materialized in the current `ParsingSession`;
4. minimizes declared execution cost;
5. applies explicit stable priority as a tie-breaker;
6. rejects indistinguishable ambiguous plans rather than using registration order.

`estimated_cost` is a bounded relative planning value. It does not represent measured milliseconds and is not a performance promise.

Planner behavior must be deterministic for the same registry, known inputs, session state, and request.

### 11.1 Invalid Graphs

A registry/planner configuration that cannot produce one deterministic plan when required returns `InvalidTransformationGraph`.

Examples include:

- indistinguishable competing plans after all declared tie-breakers
- invalid self-dependency
- unsatisfied required input contracts that the registry claims should be constructible
- contradictory registration metadata

An invalid graph is an Argus configuration/internal defect, not malformed user content.

### 11.2 Fallback Candidate Ordering

When multiple eligible plans remain because applicability cannot be proven cheaply, the planner computes their deterministic order before execution.

Execution-time `NotApplicable` may advance to the next preordered candidate.

The planner never turns execution into registration-order probe-until-success behavior.

## 12. `ParsingSession`

Each top-level parsing/identity/hash operation owns one operation-scoped `ParsingSession`.

Conceptually:

```text
ParsingSession
- operation_context
- ParsedContent
- TransformationBudget
- staging ownership
- cumulative resource accounting
- cancellation context
```

A session is never persisted and never reused across independent top-level execution attempts.

### 12.1 `ParsedContent`

`ParsedContent` caches typed representations produced during the session.

If identity computation and multiple requested hash schemes require the same representation, the representation is produced once and reused while the session remains alive.

For MVP:

- parsed representations are not persisted as cache state;
- parser-library handles do not escape the session;
- transient buffers and staged artifacts are disposed when the owning operation completes or are recovered as abandoned transient artifacts;
- only independently meaningful durable outputs survive.

## 13. Input Access Requirements

Every transformation that consumes byte-oriented input declares the minimum access semantics it requires:

```text
InputAccessRequirement
- Sequential
- Seekable
- RandomAccess
```

A transformation must not assume random access merely because one current provider happens to expose a local file handle.

The planner compares required semantics with the currently available input representation.

If the requirement is already satisfied, no staging occurs.

If not, the planner may insert an infrastructure-backed staging step.

## 14. Transient Disk-Backed Staging

Staging converts a stream-oriented source into a stable seekable/random-access transient representation when required.

Conceptually:

```text
SourceRead(stream only)
    ↓
StageToSeekableArtifact
    ↓
SeekableBytes
    ↓
transformation requiring seek/random access
```

Staging artifacts are:

- operation-scoped
- transient
- disk-backed by default for potentially large inputs
- owned by the `ParsingSession`
- subject to the transformation resource budget
- cleaned up at normal operation completion
- eligible for startup cleanup if abandoned by interruption/crash
- never represented as `SourceEntry`
- never persisted as provider/source configuration
- never treated as a reusable content cache in MVP

Argus must not buffer an entire large source in memory merely to fake seekability.

Small bounded parser-local buffers remain an implementation detail when they respect the active resource budget.

## 15. Source-Read Validation Integration

SPEC-BE-011 defines `Atomic` source reads and reads that `RequireValidation`.

BE-012 consumes that contract without weakening it.

### 15.1 Atomic Reads

An atomic read may be used to produce trusted immutable derived facts once the read completes successfully.

### 15.2 Reads Requiring Validation

A read requiring post-read validation follows this pattern:

```text
open SourceRead
    ↓
consume/stage bytes
    ↓
complete read
    ↓
ReadValidation
    ├── Consistent
    │       ↓
    │   derivation may become trusted
    ├── Changed
    │       ↓
    │   discard immutable derived result
    └── Indeterminate
            ↓
        result is not trusted as immutable
```

A staged copy becomes trusted immutable downstream input only after the source read that produced it is proven `Consistent`.

`Changed` and `Indeterminate` never authorize persistence of:

- `ContentIdentity`
- content/source hash records derived from that read
- authoritative derived-container absence
- other immutable facts that claim to describe one stable source version

## 16. Transformation Resource Budget

Every `ParsingSession` captures one immutable application-owned `TransformationBudget` when the operation begins.

Conceptually, budget dimensions may include:

```text
TransformationBudget
- max_staged_bytes
- max_expanded_bytes
- max_derived_entries
- max_nesting_depth
- max_single_representation_bytes
- max_parser_work
```

Exact dimensions and numeric defaults are implementation/runtime configuration, but every potentially unbounded parser/staging dimension must have a finite safety policy.

MVP budgets are Argus-owned runtime/build configuration rather than user-visible settings.

### 16.1 Shared Accounting

Where a limit represents operation-wide consumption, accounting is cumulative across the session.

A nested archive cannot obtain a fresh full expansion budget merely because it invokes another transformation.

### 16.2 Enforcement Ownership

The application defines the budget.

Individual transformations enforce format-specific consumption through the session because they understand the relevant work units and expansion behavior.

Staging infrastructure accounts for temporary storage consumption.

### 16.3 Limit Failure

Exceeding a limit returns `TransformationError::ResourceLimitExceeded`.

It must not:

- panic
- silently truncate
- return `NotApplicable`
- claim a complete derived scope
- authorize absence deletion

## 17. Transformation Outcome Contract

Transformation execution returns one of three semantic outcomes:

```text
TransformationResult<T>
- Produced(T)
- NotApplicable
- Failed(TransformationError)
```

`NotApplicable` is expected control flow, not a failure.

Representative failures include:

```text
TransformationError
- MalformedInput
- UnsupportedFeature
- ResourceLimitExceeded
- IoFailure
- InvalidDerivedStructure
- Cancelled
- InternalFailure
```

### 17.1 Fallback Rule

Only `NotApplicable` permits the deterministic planner to try the next preordered candidate.

Once a transformation has recognized its format strongly enough to claim ownership, later structural or semantic failure must be reported as `Failed(...)` rather than `NotApplicable`.

A corrupt recognized ZIP file, for example, must not silently fall through to an unrelated ROM parser.

### 17.2 Unsupported vs Malformed

`UnsupportedFeature` means the input is recognized and plausibly valid, but Argus does not implement a required feature.

`MalformedInput` means the recognized input violates the format contract.

These remain distinct for diagnostics and future capability work.

## 18. Authoritative Content Recognition

Platform and logical content type become authoritative only from validated transformation results.

Conceptually:

```text
SourceEntry / ContentInputSet
        ↓
validated transformation path
        ↓
RecognizedContent
- platform_id
- content_type
- canonical_representation
```

Filename extensions, directory names, source-provider metadata, and user organization may be planning hints but do not establish or override authoritative recognition.

### 18.1 Recognition Ambiguity

If incompatible transformations validly recognize the same input as different logical `(PlatformId, ContentType)` values, the operation returns `AmbiguousContentRecognition`.

Argus must not choose based on:

- filename
- folder placement
- registration order
- cheapest parser alone
- metadata title

Multiple equivalent paths that establish the same authoritative recognition are not inherently ambiguous; deterministic planning rules still apply.

## 19. Canonical Content Units

`ContentIdentity` identifies one canonical logical-content unit, not necessarily one source file.

A `ContentUnit` may depend on multiple source entries.

Examples:

```text
game.nes
    ↓
NESRom
    ↓
ContentUnit
```

```text
game.cue
track01.bin
track02.bin
    ↓
PlayStationDisc
    ↓
ContentUnit
```

The applicable transformation defines logical ordering and interpretation. Argus does not concatenate arbitrary files to manufacture identity.

### 19.1 Multi-Entry Input Resolution

A transformation that requires related source entries receives them through an application-owned source/dependency-resolution boundary.

It must not query repositories directly.

The application remains responsible for:

- resolving candidate `SourceEntry` dependencies from the persistent source graph
- opening source reads through the source-provider contract
- validation semantics
- cancellation
- provenance capture

Format-specific parsing may determine which logical dependencies are required, but persistence and source access remain outside the parser implementation.

### 19.2 Multi-Disc Boundary

Independently usable discs are independently identified `GameContent` entities.

A multi-disc release or title is grouped above `GameContent` in a later semantic/domain layer.

A playlist may participate in discovering or grouping those contents, but BE-012 does not create one giant content identity across independently usable discs.

## 20. Content Identity Scheme

A `ContentIdentityScheme` defines the complete Argus-owned canonical identity procedure for one supported class of logical content.

Conceptually:

```text
ContentIdentitySchemeDescriptor
- scheme_id
- supported_platforms
- supported_content_types
- required_representation
- estimated_cost
- identity_revision
```

The semantic scheme includes:

- applicable content class
- canonical representation contract
- canonicalization rules
- byte-selection rules
- ordering rules for multi-entry content
- digest/identity algorithm

The semantic identity of a scheme is immutable.

If the intended procedure changes, Argus defines a new `scheme_id`.

## 21. `identity_revision`

`identity_revision` identifies the currently trusted Argus implementation of one unchanged semantic identity scheme.

It increments when an implementation defect or dependency change may make previously computed identities untrustworthy while intended semantics remain unchanged.

Examples include:

- parser defect affecting canonical bytes
- incorrect track ordering
- byte-range implementation error
- canonicalizer defect
- relevant transformation correction

One effective `identity_revision` collapses relevant implementation dependencies for persistence validity.

Argus does not persist an arbitrary dependency-revision graph for each identity.

## 22. Identity Scheme Selection

Application policy maps authoritative `(PlatformId, ContentType)` recognition to zero or one active current identity scheme.

The invariant is:

> For every identifiable supported `(PlatformId, ContentType)`, Argus has zero or one active canonical `ContentIdentityScheme`, never multiple competing current schemes.

Zero means Argus can recognize the content but cannot currently establish strong logical identity for it.

Content without an applicable current identity scheme is not materialized as a new `GameContent` merely because recognition succeeded.

Selection is deterministic and independent of registration order.

### 22.1 Production catalog

SPEC-BE-014 is the authoritative Phase 003 production catalog for the current `(PlatformId, ContentType)` mappings, accepted source representations, canonical logical representations, `scheme_id` values, and current `identity_revision` values.

BE-012 continues to define the zero-or-one selection invariant and all generic transformation/identity mechanics. A content class absent from the Phase 003 catalog, or explicitly excluded by it, is not an advertised Phase 003 identity class even if a parser can recognize or inspect the representation.

## 23. `ContentIdentity`

Conceptually:

```text
ContentIdentity
- scheme_id
- identity_value
- identity_revision
```

`ContentIdentity` is:

- Argus-owned
- scheme-scoped
- canonical logical-content identity
- distinct from source location
- distinct from source object identity
- distinct from `SourceFingerprint`
- distinct from `DerivedFingerprint`
- distinct from consumer-facing hash records

Cross-scheme equality is never assumed.

Even when an identity is digest-backed, it remains semantically distinct from `HashRecord` because identity establishes Argus logical-content ownership while hashes satisfy explicitly requested hashing contracts.

Normative invariant:

> `ContentIdentity` identifies canonical logical content under an immutable Argus-owned identity scheme; source packaging, consumer-specific hashes, and storage location are separate concepts.

## 24. Current Identity Cardinality

Each `GameContent` has at most one current `ContentIdentity`.

A newly materialized `GameContent` must have one current identity.

An existing `GameContent` may temporarily have no current identity only while it is in an explicit identity-maintenance state such as:

```text
NeedsReidentification
IdentityConflict
```

Obsolete identities are removed from current identity and are not retained as valid aliases or general matching keys. Phase 003 may retain one bounded non-current identity-evidence record solely for exact orphan reconnection under Section 30.1; that evidence is excluded from ordinary current-identity queries, provider matching, grouping, hashing, and verification.

Conceptually, durable identification state distinguishes:

```text
ContentIdentificationState
- Identified
- NeedsReidentification
- IdentityConflict
```

`Identified` requires one current identity and one authoritative current provenance basis. The other states do not expose retained provenance hints as current proof.

## 25. Content Identification Workflow

A mere `ContentCandidate` does not create `GameContent`.

The normal identification flow is:

```text
SourceEntry / candidate source set
        ↓
validated SourceRead values
        ↓
ParsingSession
        ↓
transformation planning/execution
        ↓
authoritative RecognizedContent
        ↓
current ContentIdentityScheme
        ↓
canonical ContentUnit
        ↓
ContentIdentity + exact provenance basis
        ↓
short Unit of Work
        ↓
resolve/create GameContent
        ↓
attach source relationships
        ↓ commit
post-commit events
```

No source/provider I/O occurs inside the database write transaction.

### 25.1 Atomic Convergence

After identity is computed and validated, one short application Unit of Work:

1. looks up the current `(scheme_id, identity_value)`;
2. reuses the existing `GameContent` when one already owns that identity;
3. otherwise creates a new `GameContent`;
4. establishes or updates required `GameContentSource` relationships;
5. persists the current identity and provenance basis;
6. persists compatible derived records already computed for that resolved `GameContent` when appropriate;
7. commits;
8. publishes events after commit.

Persistence uniqueness is mandatory. Correctness must not depend solely on query-then-insert behavior.

Concurrent identification of the same identity converges to one canonical `GameContent`.

## 26. `GameContentSource` Boundary

`GameContentSource` is an unversioned semantic/source association.

Conceptually:

```text
GameContentSource
- game_content_id
- source_entry_id
- relationship
```

It means that the source entry has been associated with the logical content by prior application work.

It does **not** mean that the source entry is currently proven to contain the same bytes or logical content version.

Therefore:

- `GameContentSource` is not current identity proof;
- ordinary identity-dependent operations do not trust an alternative association without re-identification;
- version-bound proof lives only in `ContentIdentityProvenance`.

## 27. Content Identity Provenance

Every current `ContentIdentity` has one exact derivation basis recording the source entries and version evidence that established it.

Conceptually:

```text
ContentIdentityProvenance
- game_content_id
- source_entry_id
- role
- source_version_evidence
```

Representative roles include:

```text
Primary
Descriptor
RequiredData
Supporting
```

The role vocabulary may be implemented as a narrow application enum; it is not free-form persisted text.

### 27.1 Exact Basis

The basis contains only the source entries actually required to establish the identity in that successful derivation.

Argus does not persist every theoretically equivalent source set as simultaneous identity proof.

If another equivalent source later re-establishes the same identity, the successful re-identification workflow replaces the provenance basis.

### 27.2 Version Evidence

Each basis member captures the `SourceVersionEvidence` consumed by the successful derivation.

If current version evidence no longer matches, the basis is stale and the identity can no longer be treated as freshly proven from that basis.

### 27.3 Maintenance-State Retention

When a `GameContent` enters `NeedsReidentification` or `IdentityConflict`, the last provenance basis may be retained as a repair/input-selection hint.

While the content lacks a current identity, retained provenance is not authoritative proof and must not be represented as such externally.

This allows targeted maintenance to retry known source dependencies without retaining the obsolete identity value as valid history.

## 28. Source Content Replacement

A source that produces a different identity value under the same current identity scheme represents different logical content.

Argus does not mutate the old `GameContent` into the new content.

Instead:

```text
SourceEntry
    old association -> GameContent A / Identity A

source bytes change

SourceEntry
    new association -> existing/new GameContent B / Identity B
```

The stale source association to `GameContent A` is corrected according to application relationship policy.

`GameContent A` is never rewritten to mean Identity B. If the replaced source was part of A's only current provenance basis, A enters `NeedsReidentification` under the provenance rules; if no source relationships remain, it may also become orphaned. Final orphan lifecycle is outside this specification.

### 28.1 Identity-Scheme Migration Is Different

If the underlying logical content is unchanged but the active identity scheme or implementation revision changes, the `GameContentId` is preserved and its obsolete identity is replaced through the migration workflow.

Therefore:

```text
same semantic content + scheme/revision upgrade
    -> preserve GameContentId

different identity under same current scheme
    -> rebind source to different/new GameContent
```

## 29. Identity Migration

Identity scheme/revision migration is application-level maintenance because it requires source I/O and content processing.

It is not a SQLite schema migration.

### 29.1 Identity-maintenance admission and recovery

When application identity-maintenance policy detects that an existing identity's `scheme_id` or `identity_revision` is obsolete:

- the old identity becomes invalid immediately;
- the old identity value is removed from current matching semantics;
- the affected `GameContent` enters `NeedsReidentification`;
- the last provenance basis may remain only as a maintenance hint;
- targeted identity maintenance becomes eligible for normal background admission under SPEC-BE-004.

This contract does not define a user-visible priority tier. An interrupted maintenance run is terminal for its original `JobRun`. A later maintenance admission creates a new `JobRun` from current authoritative `NeedsReidentification` state; MVP does not automatically continue the old run or serialize transient parser sessions, staging handles, or in-memory execution state.

The library remains open, and each execution attempt obeys normal admission, checkpoint, cancellation, and restart-reconciliation rules.

### 29.2 Available During Migration

Unaffected operations remain usable, including:

- library browsing
- source configuration
- existing metadata
- independently valid artwork state
- independently valid content hash records
- other state whose own validity contract is unchanged

Identity-dependent work for affected content is blocked or degraded until re-identification succeeds.

### 29.3 Targeted Work

Migration does not imply a blind full re-index or full re-hash.

Rules:

- identity scheme/revision change -> re-identify affected content;
- transformation revision affecting derived structure -> reprocess affected derived scopes;
- source indexing contract/configuration change -> perform the indexing work required by that contract;
- hash scheme/revision change -> invalidate/recompute only that hash contract according to demand-driven rules.

### 29.4 Successful Replacement

Successful re-identification atomically establishes:

- the new current `ContentIdentity`;
- the new exact provenance basis;
- any relationship corrections required by that successful derivation;
- the identified state.

The obsolete identity is not retained as a valid alias.

## 30. Re-Identification Source Selection

Normal unrelated operations do not probe `GameContentSource` alternatives when the current identity basis is missing or stale.

If a missing/stale basis prevents identity-dependent work:

```text
GameContent
    ↓
NeedsReidentification
```

The dedicated maintenance workflow owns source recovery.

It may evaluate:

1. the last known provenance basis when still locatable;
2. associated `GameContentSource` candidates;
3. other explicitly allowed application-owned recovery candidates.

Every alternative source candidate must pass the normal validated identification pipeline before becoming trusted provenance.

An unversioned `GameContentSource` association alone is never sufficient proof.

Candidate ordering is deterministic and application-owned; repository enumeration order is never policy.

### 30.1 Phase 003 retained identity evidence for orphan reconnection

When authoritative source removal proves that a `GameContent` has no remaining current source association, the current identity and provenance cease being current. Phase 003 may retain a bounded record equivalent to:

```text
RetainedContentIdentityEvidence
- game_content_id
- scheme_id
- identity_value
- identity_revision
- retained_at
- reason = FinalSourceAbsent
```

This record is historical reconnection evidence only. It is not a current `ContentIdentity`, valid provenance, alias, provider/grouping input, hash subject proof, or verification authority.

A returning source must independently complete the ordinary current BE-012/BE-014 identification pipeline. After a current `(scheme_id, identity_value)` has been computed from validated source data, the short convergence Unit of Work may reconnect the source to an existing orphaned `GameContent` only when:

1. exactly one retained record matches the current scheme and identity value;
2. the retained `identity_revision` is still semantically comparable under the current scheme contract, or application policy has explicitly migrated the evidence without treating it as current proof;
3. no different current `GameContent` already owns the identity; and
4. the new exact current provenance basis is persisted in the same coherent mutation that reactivates the content.

Absent, obsolete, or multiple retained matches never authorize a guess. The workflow follows ordinary create/reuse/conflict rules. Filename, folder, provider metadata, old source association, and unavailable-media remount are not reconnection evidence.

## 31. Identity Conflict During Migration

If two existing `GameContent` records compute the same current identity during migration, Argus preserves the uniqueness invariant and does not automatically merge them.

Conceptually:

```text
GameContent A -> Identity X
GameContent B -> Identity X
```

Only one current owner may exist.

The unresolved entity enters an explicit identity-conflict state containing enough safe Argus-owned identifiers to support later reconciliation.

Automatic merging is outside BE-012 because a correct merge must reconcile broader content-owned state such as metadata, artwork, collections, verification results, source relationships, and future user overrides.

Operations requiring trustworthy unique current identity are blocked for the conflicting entity until reconciliation changes state.

## 32. Derived Containers

Transformations may interpret archive, disc, filesystem-image, or other virtual container content and return application-owned derived observations.

They do not mutate repositories.

Conceptually:

```text
SourceEntry
    ↓
validated read
    ↓
container transformation
    ↓
DerivedScopeResult
    ↓
indexer reconciliation
    ↓
persistent SourceEntry children
```

## 33. `DerivedEntryObservation`

Conceptually:

```text
DerivedEntryObservation
- derived_locator
- derived_entry_key
- display_name
- entry_kind
- cheap_metadata
- derived_fingerprint
```

It contains no parser-library object, provider-native locator, provider-native identity, or repository entity instance.

The indexer assigns/preserves `SourceEntryId` through reconciliation.

## 34. Derived Coordinates

### 34.1 `DerivedLocator`

`DerivedLocator` is the transformation-owned opaque coordinate required to reopen or address an entry within its containing derived scope.

Generic indexing/application code stores or passes it but does not parse its encoding.

### 34.2 `DerivedEntryKey`

`DerivedEntryKey` is the transformation-defined persistent equality key used to reconcile one derived child within its containing derived scope.

Its equality semantics are owned by the transformation contract.

It is not:

- global identity
- content identity
- a provider locator key
- a hash

## 35. `DerivedFingerprint`

Provider-native and transformation-derived entries use different cheap version-evidence types.

Conceptually:

```text
SourceVersionEvidence
- Provider(SourceFingerprint)
- Derived(DerivedFingerprint)
```

`DerivedFingerprint` is transformation-owned.

It deterministically reflects the inputs that can change the derived child's representation, including at minimum the relevant:

- parent `SourceVersionEvidence`;
- transformation semantic identity/revision;
- `DerivedEntryKey`;
- parser-observed metadata that the transformation defines as version-relevant.

Exact encoding remains transformation-owned.

Neither `SourceFingerprint` nor `DerivedFingerprint` proves byte identity.

Both exist to support cheap cache/provenance validity decisions.

## 36. Derived SourceEntry Persistence

Provider-native and transformation-derived entries remain nodes in one Argus `SourceEntry` graph while preserving distinct coordinate/evidence ownership.

A provider-native entry retains provider-owned concepts such as:

```text
relative_locator
locator_key
provider_native_identity
source_fingerprint
```

A derived entry instead requires transformation-owned concepts equivalent to:

```text
derived_locator
derived_entry_key
derived_fingerprint
derivation_transformation_id
derivation_revision
```

The exact table/column decomposition is an implementation decision, but persistence must not serialize a derived locator into provider fields and pretend provider semantics apply.

For application validity logic, either entry kind exposes one `SourceVersionEvidence` value.

## 37. Derived-Scope Outcome and Authority

A transformation that enumerates a derived scope returns an explicit terminal outcome:

```text
DerivedScopeOutcome
- Complete
- Partial
- Failed
- Cancelled
```

`Unavailable` remains a source/provider availability concept unless a specific derived transformation later defines a narrower equivalent.

Only:

```text
Complete + validated stable input
```

authorizes absence-based deletion for that exact derived scope.

`Partial`, `Failed`, `Cancelled`, `Changed`, and `Indeterminate` do not prove absence.

Positive derived observations may be reconciled according to SPEC-BE-011 only when doing so does not falsely claim immutable facts from an unvalidated read.

## 38. Nested Derived Containers

Nested containers compose as independently reconcilable scopes.

Example:

```text
provider-native archive.zip
    SourceFingerprint
        ↓
inner.iso
    DerivedFingerprint
        ↓
filesystem entry
    DerivedFingerprint
```

Each layer has:

- its own transformation identity/revision;
- its own derived key/locator semantics;
- its own exact-scope completion outcome;
- its own version evidence.

A parser for one container does not recursively become the owner of every downstream format.

## 39. Hash Scheme Model

A hash scheme defines the complete semantic procedure for one requested hash.

Conceptually:

```text
HashSchemeDescriptor
- hash_scheme_id
- subject_scope
- applicability
- required_representations
- estimated_cost
- hashing_revision
```

Representative semantic scheme definitions may include:

```text
MD5WholeFile
SHA1WholeFile
BLAKE3CanonicalContent
RetroAchievementsNESV1
RetroAchievementsPlayStationV1
```

The actual subject scope is defined by each scheme's semantics rather than its name.

## 40. Hash Subject Scope

Every scheme explicitly declares one subject scope:

```text
HashSubjectScope
- SourceEntry
- GameContent
```

### 40.1 Source Scope

A source-scoped hash describes one particular source representation.

Whole-file/raw-byte hashes normally belong here.

Equivalent logical content stored in different packaging may legitimately have different source-scoped hashes.

### 40.2 Content Scope

A content-scoped hash describes canonical logical content.

A scheme may be content-scoped only if equivalent source representations that resolve to the same `GameContent` are required by the scheme to produce the same hash value.

If packaging differences can legitimately alter the value, the scheme is not content-scoped.

Normative invariant:

> A hash scheme explicitly declares whether it describes a particular source representation or canonical logical content; source hashes belong to `SourceEntry`, while content hashes belong to `GameContent`.

## 41. `hash_scheme_id` and `hashing_revision`

These are separate dimensions.

### 41.1 `hash_scheme_id`

The scheme ID defines immutable semantic hashing behavior, including relevant:

- subject scope
- canonicalization/input representation
- byte-selection rules
- ordering rules
- digest algorithm
- external protocol version

A semantic procedure change requires a new scheme ID.

### 41.2 `hashing_revision`

The hashing revision identifies the current trusted Argus implementation of the unchanged semantic scheme.

A parser, canonicalizer, executor, or dependency defect fix that can make prior results untrustworthy while preserving intended scheme semantics increments the revision.

One effective revision collapses relevant dependency revisions for persisted hash validity.

## 42. `SourceHashRecord`

Conceptually:

```text
SourceHashRecord
- id
- source_entry_id
- hash_scheme_id
- hash_value
- hashing_revision
- source_version_evidence
- computed_at
```

A source hash is current only when:

```text
stored SourceVersionEvidence == current SourceVersionEvidence
AND
stored hashing_revision == current scheme revision
```

The stored evidence may be provider-native or derived.

No source hash treats its fingerprint/evidence as strong content identity.

## 43. `ContentHashRecord`

Conceptually:

```text
ContentHashRecord
- id
- game_content_id
- hash_scheme_id
- hash_value
- hashing_revision
- computed_at
```

A content hash belongs to the immutable logical content represented by `GameContent`.

It does not need a hard dependency on the specific `ContentIdentity` value that happened to exist when the hash was computed.

A content hash remains current when:

- its scheme ID remains the requested semantic scheme;
- its `hashing_revision` remains current;
- the `GameContent` still represents the same logical content;
- no change that affects the hash contract has caused its effective revision to advance.

## 44. Independent Derived-Fact Validity

Every durable derived fact owns its own validity contract.

Therefore:

```text
ContentIdentity scheme/revision change
    != automatic invalidation of every ContentHashRecord
```

If an identity migration changes only identity semantics or digest selection, an independently defined content hash may remain current.

If a canonical representation/parser change affects both identity and a content hash, the identity's `identity_revision` and the hash scheme's `hashing_revision` must each advance as required by their own contracts.

This avoids hidden coupling between version namespaces.

## 45. Demand-Driven Hash Planning

Hashing is not performed universally during indexing.

For a requested `(subject, scheme)` the application:

1. resolves the scheme descriptor;
2. validates subject scope and applicability;
3. checks for a current persisted record;
4. returns the current record without new source I/O when allowed;
5. otherwise builds the required representation plan;
6. executes the plan inside one `ParsingSession`;
7. validates the underlying source read(s);
8. persists the durable hash result in a short Unit of Work.

### 45.1 Source-Scoped Requests

A source-scoped request starts from the requested `SourceEntry` and current version evidence.

### 45.2 Content-Scoped Requests

A missing/stale content-scoped hash requires a usable current identity provenance basis so Argus knows which source set currently proves the `GameContent`.

If the item is `NeedsReidentification`, normal hash execution does not probe alternative `GameContentSource` associations.

Identity maintenance resolves that condition first.

### 45.3 Existing Content Hashes During Re-Identification

A still-current persisted content hash may be returned while the `GameContent` is undergoing an identity-scheme migration when the hash's own validity contract remains satisfied.

The hash does not become stale merely because the current identity value is temporarily absent.

## 46. Multi-Scheme Reuse

One `ParsingSession` may satisfy multiple identity/hash requests when they are part of one admitted application operation.

The session reuses:

- already parsed typed representations;
- validated staged input;
- bounded transient canonical buffers;
- digest/canonicalization work when an implementation can safely share it without changing scheme semantics.

Reuse is an optimization. It must not alter deterministic outputs or persistence validity.

## 47. Persistence Model

BE-012 requires durable concepts equivalent to:

```text
ContentIdentity
ContentIdentityProvenance
RetainedContentIdentityEvidence
SourceHashRecord
ContentHashRecord
ContentIdentificationState
```

The exact normalized schema is an implementation decision subject to SPEC-BE-002.

### 47.1 Identity Uniqueness

Persistence enforces current identity uniqueness on the semantic equivalent of:

```text
(scheme_id, identity_value)
```

Two `GameContent` records cannot simultaneously own the same current identity.

### 47.2 No Polymorphic Hash Owner

The following design is prohibited:

```text
HashRecord
- source_entry_id nullable
- game_content_id nullable
```

Source and content hashes use separate persistence concepts/tables so foreign-key ownership and validity rules remain explicit.

### 47.3 Stale Record Retention

MVP does not require general historical identity or hash revision retention.

Obsolete identity values are discarded from current identity state. The narrow Phase 003 `RetainedContentIdentityEvidence` record from Section 30.1 is the sole MVP exception: it is stored separately from current identity/provenance and is usable only after an independently computed current identity establishes an exact orphan-reconnection candidate.

Stale hash records may be replaced or deleted according to repository implementation, but they must never be returned as current.

## 48. Unit of Work Boundaries

All expensive source/content work completes before the write transaction that persists its durable facts.

These must remain outside database write transactions:

- opening source reads
- consuming source bytes
- staging
- source-read validation where provider access is required
- transformation planning
- parsing
- container traversal
- canonicalization
- digest computation
- identity computation
- network/provider work

Representative coherent write operations include:

- create/reuse one `GameContent` and establish identity/provenance/source associations;
- replace one current identity and provenance basis after re-identification;
- mark one or a bounded set of affected content records `NeedsReidentification`;
- persist one or a bounded set of hash results;
- reconcile one bounded derived scope through the indexer;
- record one identity-conflict state.

Transactions follow SPEC-BE-002.

## 49. Source Removal, Identity Provenance, and Orphan State

SPEC-BE-011 owns authoritative source-graph removal. Once BE-012 identity provenance exists, source-removal coordination must also preserve identity correctness.

If an authoritatively removed `SourceEntry` participates in a current identity provenance basis, the same coherent application mutation must ensure that:

- referencing identity-provenance rows no longer claim valid proof from the removed entry;
- the affected `GameContent` no longer exposes the old identity as current proof;
- if another current source association remains, the content enters `NeedsReidentification` unless replacement proof is established explicitly;
- if no current source association remains, current identity/provenance are cleared, optional Section 30.1 retained evidence is recorded, `ContentIdentificationState` becomes `NeedsReidentification`, and the separate SPEC-BE-015 `GameContentPresenceState` becomes `Orphaned`;
- `GameContent`, membership history, and independently valid enrichment are not deleted merely because provenance disappears.

Temporary source/root `Unavailable` state never executes this transition. The indexing reconciler does not compute or guess replacement identity; a later explicit identification workflow must establish new current proof before reconnection/reactivation.

## 50. Derived Reconciliation Transaction Boundary

Parser/transformation code returns `DerivedScopeResult` values outside persistence transactions.

The indexer applies the result through its own short coherent Unit of Work rules from SPEC-BE-011.

No parser receives a repository handle merely to persist children while parsing.

A complete derived result from an unvalidated mutable read does not authorize destructive reconciliation.

## 51. Cancellation

All potentially long-running BE-012 work cooperatively observes the operation cancellation context:

- source consumption
- staging
- transformation execution
- archive/disc traversal
- canonicalization
- hashing
- identity migration

Cancellation before durable commit produces the existing cancelled operation/job outcome from SPEC-BE-003/004.

A cancellation arriving after durable commit cannot convert committed success into failure or cancellation.

Incomplete transient staging artifacts are cleaned normally or recovered through startup transient-artifact cleanup.

## 52. Retry Semantics

BE-012 transformations do not implement unbounded private retry loops.

A terminal processing failure returns to application/runtime policy.

Rules:

- runtime-owned retries remain bounded under SPEC-BE-003/004;
- user-initiated retry is a new top-level operation;
- transient source I/O/change conditions may be retryable when their published error contract says so;
- malformed content is not automatically retried;
- unsupported content/features are not automatically retried;
- identity conflicts are not retried until reconciliation changes state;
- `NotApplicable` candidate fallback is transformation planning behavior, not an operation retry.

## 53. Background Identity Migration

Eager identity migration runs through the durable `JobRun` model from SPEC-BE-004.

Representative lifecycle remains:

```text
Queued
-> Preparing
-> Running
-> Completed / CompletedWithIssues / Failed / Cancelled / Interrupted / Abandoned
```

An interrupted historical `JobRun` remains terminal. Resume creates a new `JobRun` according to SPEC-BE-004.

Migration may persist durable checkpoints sufficient to resume bounded library progress, but it must not serialize:

- parser-library objects
- `ParsingSession`
- staged-file handles
- in-memory typed representations

Each resumed item is reprocessed from durable source/identity state.

## 54. Error Boundary

BE-012 uses precise internal processing errors but does not introduce a new top-level `ApplicationError` category.

Published failures map through SPEC-BE-003 categories such as:

```text
Operation
Filesystem
Configuration
Internal
```

and other existing categories where applicable.

Phase 003 internal processing outcomes map to the published SPEC-BE-003 catalog exactly as follows:

| BE-012 / catalog semantic | Published error code |
|---|---|
| `MalformedInput` or `InvalidDerivedStructure` | `ARGUS.V1.VALIDATION.CONTENT_MALFORMED` |
| `UnsupportedFeature` or no valid transformation path | `ARGUS.V1.VALIDATION.CONTENT_UNSUPPORTED_REPRESENTATION` |
| unsupported encrypted/key-dependent content | `ARGUS.V1.VALIDATION.CONTENT_ENCRYPTED_UNSUPPORTED` |
| unsupported multi-game generic container | `ARGUS.V1.VALIDATION.MULTI_GAME_CONTAINER_UNSUPPORTED` |
| missing required descriptor/content dependency | `ARGUS.V1.FILESYSTEM.CONTENT_DEPENDENCY_MISSING` |
| `AmbiguousContentRecognition` | `ARGUS.V1.VALIDATION.CONTENT_RECOGNITION_AMBIGUOUS` |
| `ResourceLimitExceeded` | `ARGUS.V1.OPERATION.TRANSFORMATION_RESOURCE_LIMIT_EXCEEDED` |
| `NeedsReidentification` prevents requested work | `ARGUS.V1.OPERATION.CONTENT_REIDENTIFICATION_REQUIRED` |
| current identity uniqueness/conflict | `ARGUS.V1.INTERNAL.CONTENT_IDENTITY_CONFLICT` |
| source changed during processing | `ARGUS.V1.OPERATION.SOURCE_CHANGED_DURING_PROCESSING` |
| source validation indeterminate | `ARGUS.V1.FILESYSTEM.SOURCE_VALIDATION_INDETERMINATE` |
| `InvalidTransformationGraph` | `ARGUS.V1.INTERNAL.INVALID_TRANSFORMATION_GRAPH` |
| `Cancelled` | `ARGUS.V1.OPERATION.CANCELLED` |
| unexpected `InternalFailure` | `ARGUS.V1.INTERNAL.UNEXPECTED` |

`IoFailure` maps through the narrower source/filesystem/persistence error already owned by the failing port when one exists; it must not be flattened into malformed or unsupported content. BE-012 creates no parallel public catalog.

An invalid transformation graph or impossible identity invariant is an Argus defect/configuration failure, not user-content corruption.

## 55. Diagnostics and Observability

All BE-012 operations inherit the top-level operation context and `TraceId` rules from SPEC-BE-003.

Useful bounded structured diagnostic fields include:

```text
transformation_id
identity_scheme_id
identity_revision
hash_scheme_id
hashing_revision
game_content_id
source_entry_id
representation_type
failure_reason
```

Diagnostics must not include:

- ROM bytes
- parser buffers
- raw credentials
- absolute source paths unless a separate sanitized diagnostic contract explicitly allows them
- opaque provider locator contents
- opaque derived locator contents
- arbitrary serialized parser input

Lower layers return errors rather than duplicating the one primary top-level error log.

## 56. Event Publication

BE-012 does not create a second event system.

Application events use SPEC-BE-006 and publish only after durable commit.

Events may notify consumers that identity, source association, migration state, derived structure, or hash availability changed, but the event is never the sole durable record of that state.

Event payloads use Argus-owned identifiers and safe bounded values rather than parser/provider-native objects.

Exact event names may be finalized with the first dependent application-service/bridge slice as long as the ownership and post-commit rules remain unchanged.

## 57. Concurrency

Concurrency must preserve deterministic identity/hash outcomes and database uniqueness.

Required rules:

1. Concurrent sessions do not share mutable `ParsedContent` or staging artifacts.
2. Runtime-global transformation registry membership is immutable per generation.
3. Concurrent identification of the same content converges through persistence uniqueness.
4. Query-before-insert alone is insufficient for identity uniqueness.
5. Concurrent hash computation may race, but persistence converges to one current result per subject/scheme/revision contract.
6. Identity migration cannot create two current owners of one identity.
7. Derived-scope reconciliation follows SPEC-BE-011 scan/scope ownership rules.
8. Cancellation of one session does not corrupt another session's staging or cache.

## 58. Architecture Tests

Architecture tests must verify:

- application/domain modules do not depend on parser-library concrete types;
- transformation implementations do not depend on repositories or Unit of Work implementations;
- infrastructure staging/digest/parser adapters implement application-owned ports;
- runtime scheduling code does not contain format-specific transformation selection policy;
- indexer remains the only component that persists derived `SourceEntry` graph mutations;
- source and content hash repositories are distinct;
- `GameContentSource` is not used as a substitute for version-bound identity provenance;
- provider-native and derived version-evidence types remain distinct;
- bridge/generated DTO modules do not become transformation contracts.

## 59. Planner Contract Tests

Tests must verify:

- identical registry/input/session state produces identical plans;
- registration order does not affect selection;
- already materialized representations are preferred where specified;
- lower declared execution cost wins;
- explicit priority resolves permitted ties;
- irreducible ambiguity returns `InvalidTransformationGraph`;
- applicability performs no persistence mutation or hidden unbounded work;
- `NotApplicable` alone advances to the next deterministic candidate;
- recognized malformed input does not fall through;
- recognized unsupported input does not fall through;
- missing representation paths return a stable unavailable/no-path result rather than panic.

## 60. ParsingSession and Staging Tests

Tests must verify:

- one session reuses typed representations across multiple consumers;
- representations do not leak across independent execution attempts;
- sequential transformations do not stage unnecessarily;
- seek/random-access transformations stage when required;
- large staging uses bounded disk-backed storage rather than mandatory whole-file memory buffering;
- atomic source reads can produce trusted staged input;
- reads requiring validation become trusted only after `Consistent`;
- `Changed` discards immutable derivation results;
- `Indeterminate` does not produce trusted immutable facts;
- cancellation terminates staging safely;
- abandoned transient artifacts are eligible for startup cleanup.

## 61. Resource-Safety Tests

Deterministic synthetic fixtures must exercise:

- maximum staging bytes
- maximum expanded bytes
- maximum derived-entry count
- maximum nesting depth
- maximum single-representation size
- bounded parser-work accounting where applicable
- cancellation during high-cost processing
- malformed nested structures
- pathological but valid container structures

Budget exhaustion must return `ResourceLimitExceeded` and must not:

- panic
- silently truncate
- claim `NotApplicable`
- authorize absence deletion

## 62. Recognition and Identity Tests

Tests must verify:

- filenames/extensions may narrow planning but cannot establish authoritative platform/content identity;
- validated transformation results establish `RecognizedContent`;
- conflicting authoritative recognition returns `AmbiguousContentRecognition`;
- each supported `(PlatformId, ContentType)` maps to zero or one current identity scheme;
- content with no current identity scheme is not materialized as new `GameContent`;
- semantic identity-scheme changes require a new scheme ID;
- implementation-affecting fixes may increment `identity_revision` without changing scheme semantics;
- cross-scheme identity equality is never assumed;
- multi-entry content produces one canonical `ContentUnit` where defined;
- independently usable discs remain separate `GameContent` entities.

## 63. Identity Convergence and Provenance Tests

Tests must verify:

- no `GameContent` is created from a mere `ContentCandidate`;
- identity is computed from validated input before the persistence transaction begins;
- concurrent identical identity creation converges to one `GameContent`;
- exact source entries, roles, and version evidence are persisted as the identity basis;
- `GameContentSource` alone is not accepted as current identity proof;
- a stale/missing provenance basis produces `NeedsReidentification`;
- retained stale provenance is treated only as a maintenance hint;
- a different identity under the same current scheme rebinds source provenance rather than mutating old logical content;
- scheme/revision migration preserves `GameContentId` for the same logical content;
- obsolete identity values cease current matching immediately;
- migration collision produces `IdentityConflict` rather than automatic merge;
- authoritative source removal invalidates affected identity provenance without deleting `GameContent` directly.
- final-source absence records retained identity evidence separately from current identity/provenance;
- retained evidence cannot satisfy current identity-dependent operations;
- an independently identified returning source reconnects only to one exact current-scheme retained match;
- absent, obsolete, multiple, or current-owner-conflicting matches follow normal create/reuse/conflict handling;

## 64. Derived-Container Tests

Tests must verify:

- parser output is application-owned `DerivedEntryObservation` data;
- provider locators/native identity do not appear in derived observations;
- `DerivedEntryKey` equality is deterministic for the same transformation semantics/input;
- `DerivedFingerprint` changes when its defined version-relevant inputs change;
- nested derived evidence chains correctly from parent evidence;
- provider and derived evidence remain distinguishable;
- parser code never directly persists `SourceEntry` rows;
- only `Complete` plus validated stable input grants absence authority;
- `Partial`, `Failed`, `Cancelled`, `Changed`, and `Indeterminate` do not grant absence authority;
- transformation revision changes target only affected derived scopes;
- resource exhaustion cannot produce authoritative truncated structure.

## 65. Hash Tests

Tests must verify:

- whole-file/raw representation schemes persist as `SourceHashRecord` when source-scoped;
- canonical logical schemes persist as `ContentHashRecord` when content-scoped;
- a content-scoped scheme produces the same value for equivalent supported source representations;
- a scheme that legitimately varies with packaging cannot be declared content-scoped;
- source hash validity depends on current `SourceVersionEvidence` and `hashing_revision`;
- content hash validity follows its own scheme/revision contract;
- identity scheme/revision migration does not automatically invalidate unrelated content hashes;
- relevant canonical-representation changes advance hash revision when required;
- demand-driven planning reuses valid persisted records;
- multiple requested hashes reuse compatible session representations;
- stale records are never returned as current;
- missing content hash computation requires usable identity provenance;
- identity-dependent hash computation does not secretly probe untrusted alternative `GameContentSource` rows.

## 66. Persistence and Transaction Tests

Tests must verify:

- source/provider I/O is outside database write transactions;
- parsing/staging/hashing/canonicalization are outside database write transactions;
- identity convergence commits atomically;
- identity replacement and provenance replacement commit atomically;
- conflict detection cannot leave two current owners of one identity;
- source and content hash foreign-key ownership is explicit;
- no nullable polymorphic hash owner is used;
- events publish only after durable commit;
- cancellation after commit cannot change committed success into cancelled/failed;
- repository constraints enforce invariants rather than relying on application prechecks alone.

## 67. Migration and Recovery Tests

Tests must verify:

- obsolete identity scheme detection marks only affected content;
- obsolete identity revision detection marks only affected content;
- the library remains open during identity maintenance;
- unrelated independently valid hashes remain available;
- re-identification runs through durable `JobRun` semantics;
- interrupted runs remain terminal and resume through a new `JobRun`;
- durable checkpoints do not serialize parser sessions or staging handles;
- successful re-identification establishes a new identity/provenance basis;
- normal unrelated operations do not perform hidden alternate-source identity repair;
- dedicated maintenance may validate associated sources before adopting a replacement basis.
- orphan reconnection independently recomputes current identity before consulting retained evidence;
- successful orphan reconnection atomically establishes current identity/provenance and reactivates the existing content;
- retained evidence never causes hidden startup, remount, or query-time identification work;

## 68. Acceptance Criteria

SPEC-BE-012 is satisfied when:

1. Parsing is implemented as typed transformations rather than consumer-selected parser chains.
2. One runtime generation owns one immutable transformation registry.
3. Every transformation has stable semantic identity and a current trusted implementation revision.
4. Applicability checks are bounded, side-effect free, and do not hide parsing/network/persistence work.
5. Transformation planning is deterministic and independent of registration order.
6. Existing session representations are reused before redundant work is scheduled.
7. Irreducible plan ambiguity is reported as an invalid graph rather than resolved implicitly.
8. Only `NotApplicable` permits deterministic fallback to another candidate.
9. Recognized malformed/unsupported content never silently falls through to another parser.
10. Every operation owns an isolated `ParsingSession` and `ParsedContent` cache.
11. Parsed representations and parser handles are not persisted as MVP cache state.
12. Transformations declare sequential/seekable/random-access requirements explicitly.
13. Missing seek/random-access capability may be satisfied by operation-scoped disk-backed staging.
14. Whole-file RAM buffering is not required merely to fake seekability or atomicity.
15. Staged data becomes trusted immutable input only under the source-read validation rules from SPEC-BE-011.
16. `Changed` and `Indeterminate` reads cannot produce trusted immutable persisted facts.
17. One immutable application-owned resource budget governs each parsing session.
18. Resource accounting is cumulative where operation-wide limits apply.
19. Resource-limit exhaustion fails safely and never claims authoritative truncated results.
20. Authoritative platform/content recognition comes from validated transformations rather than filenames or source organization.
21. Conflicting authoritative recognition is explicit and never guessed.
22. One supported `(PlatformId, ContentType)` maps to at most one current identity scheme.
23. `ContentIdentity` is a versioned Argus-owned canonical logical-content identity distinct from hashes and source fingerprints.
24. `scheme_id` versions identity semantics while `identity_revision` versions the trusted implementation.
25. Every new `GameContent` is materialized only after strong current identity is established.
26. Each `GameContent` has at most one current identity.
27. A content unit may depend on multiple source entries.
28. Independently usable discs remain separate `GameContent` entities.
29. Every current identity records one exact source/version provenance basis.
30. `GameContentSource` remains unversioned and is never treated as current identity proof.
31. Source changes affecting the identity basis transition affected content to re-identification rather than preserving uncertain identity.
32. A changed source producing a different identity under the same current scheme is rebound to different/new logical content.
33. Existing `GameContent` is never mutated into unrelated logical content.
34. Obsolete identity schemes/revisions invalidate current identity immediately and trigger targeted eager maintenance.
35. Identity migration is application-level maintenance rather than SQLite schema migration.
36. The library remains usable during identity maintenance except for operations requiring missing trustworthy identity.
37. Identity migration does not imply unrelated re-indexing or hash recomputation.
38. Normal operations do not probe alternative `GameContentSource` associations to repair identity implicitly.
39. Dedicated re-identification may validate associated sources and replace the provenance basis.
40. Identity collisions preserve uniqueness and enter explicit conflict state rather than auto-merging `GameContent`.
41. Derived containers are enumerated by transformations and reconciled only by indexing.
42. `DerivedLocator`, `DerivedEntryKey`, and `DerivedFingerprint` remain transformation-owned concepts.
43. Provider-native and derived version evidence remain distinct through a common `SourceVersionEvidence` abstraction.
44. Neither source nor derived fingerprints are strong content identity.
45. Nested derived scopes carry deterministic chained version evidence.
46. Only `Complete` derived scope results over validated stable input authorize absence deletion.
47. Hash schemes explicitly declare `SourceEntry` or `GameContent` subject scope.
48. Source and content hashes use separate persistence concepts.
49. `hash_scheme_id` versions hash semantics while `hashing_revision` versions the trusted implementation.
50. Source hashes are current only when source version evidence and hashing revision are current.
51. Content hashes follow their own independent scheme/revision validity contract.
52. Identity migration does not automatically invalidate unrelated content hashes.
53. Hashing is demand-driven rather than universal during indexing.
54. Valid persisted hashes are reused without unnecessary source work.
55. Session-local representations may be reused across identity/hash consumers in one operation.
56. All expensive source/transformation/hash work occurs outside database write transactions.
57. Identity convergence and identity/provenance replacement use short atomic Units of Work.
58. Current identity uniqueness is enforced by persistence constraints.
59. Source removal invalidates affected identity provenance without directly deleting `GameContent`.
60. Cancellation, retry, logging, diagnostics, and durable migration jobs reuse SPEC-BE-003/004 semantics.
61. BE-012 introduces capability-specific error codes through the existing `ApplicationError` contract rather than a new top-level error family.
62. Events publish only after durable commits.
63. Architecture, planner, staging, resource-safety, recognition, identity, derived-container, hash, transaction, migration, and recovery tests enforce the defined boundaries.
64. Phase 003 retained identity evidence is non-current, separately persisted, and usable only after independent exact re-identification of returning orphaned content; orphan-reconnection tests enforce the no-guessing boundary.

## 69. Prohibited Patterns

The following patterns are prohibited unless a later specification explicitly supersedes them:

- consumers selecting named parser chains;
- planner behavior depending on transformation registration order;
- applicability checks performing hidden unbounded parsing or network work;
- treating arbitrary parser failure as permission to try unrelated formats;
- returning `NotApplicable` after a format has been authoritatively recognized and then found malformed;
- persisting parser-library objects or `ParsingSession` state;
- mandatory whole-file memory buffering to fake seekability;
- unbounded archive expansion, nesting, entry count, staging, or parser work;
- treating temporary staging files as `SourceEntry` nodes or durable source cache;
- persisting identity/hash facts from changed or indeterminate mutable reads;
- authoritative platform/content recognition from filename or folder placement alone;
- multiple competing current identity schemes for one recognized content class;
- creating `GameContent` from a mere `ContentCandidate` without strong identity;
- treating `SourceFingerprint` or `DerivedFingerprint` as `ContentIdentity`;
- retaining obsolete identities as valid aliases during migration;
- using `GameContentSource` as version-bound identity proof;
- hidden alternative-source probing by unrelated hash/metadata/verification operations;
- mutating an existing `GameContent` into different logical content after source replacement;
- automatic duplicate-`GameContent` merge inside identity migration;
- parser implementations writing repositories directly;
- representing derived coordinates as provider locators;
- representing derived fingerprints as provider `SourceFingerprint` values;
- granting derived absence authority after partial/failed/cancelled/unvalidated parsing;
- declaring a packaging-sensitive hash as content-scoped;
- nullable polymorphic hash ownership;
- implicitly invalidating every content hash merely because identity versioning changed;
- source/provider I/O inside database write transactions;
- private unbounded transformation retry loops;
- logging ROM bytes, parser buffers, or opaque locator contents.

## 70. Deferred Decisions

The following remain intentionally deferred:

- concrete parser-library choices
- concrete parser/decompressor implementation choices for the production transformation inventory defined by SPEC-BE-014
- exact numeric resource-budget defaults
- persistent transformation-result caching beyond MVP
- persistent staging reuse
- automatic reconciliation/merge of pre-existing duplicate `GameContent` records beyond the exact current-identity/orphan-reconnection rules defined here
- concrete persistence implementation of the SPEC-BE-015-owned Game/orphan lifecycle
- concrete implementation of the SPEC-BE-015-owned title/release/multi-disc grouping model
- concrete implementation of the SPEC-BE-015-owned metadata matching/resolution policies
- RetroAchievements verification policy
- filesystem watching
- remote source-provider staging optimization
- user-facing resource-limit configuration
- exact bridge DTOs/events for transformation status

These decisions must preserve the invariants in this specification.

## 71. Final Invariant

> Transformations produce typed, validated facts; application policy decides how those facts establish logical identity and hashes; indexing alone persists derived source structure; and durable state survives only when its provenance and independent validity contract are explicit.

## 72. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [PHASE-003 — Game Identification and Enrichment](../../phases/phase-003-game-identification-and-enrichment.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-006 — Minimal Domain Event Bus](spec-be-006-minimal-domain-event-bus.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-009 — Application Service Contracts](spec-be-009-application-service-contracts.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-BE-014 — Production Content Identity Catalog](spec-be-014-production-content-identity-catalog.md)
- [SPEC-BE-015 — Game Library, Grouping, and Enrichment Contract](spec-be-015-game-library-grouping-and-enrichment-contract.md)
- [Backend Specifications Index](README.md)
