# Source Provider and Indexing Contract Specification

**Document ID:** SPEC-BE-011  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-15  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-001, PHASE-002, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-006, SPEC-BE-007, SPEC-BE-009, SPEC-BE-010, SPEC-X-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the canonical backend contract for source/storage providers, library-root discovery, source-entry indexing, reconciliation, scan authority, move detection, classification boundaries, and source-read consistency in Argus ROM Toolkit.

The source-provider layer answers how Argus accesses storage. The indexing layer answers what Argus has authoritatively observed within configured library roots. These concerns are deliberately separated: providers report storage facts, while application-owned indexing logic decides how those facts alter the persistent Argus source graph.

The governing rule is:

> A source provider reports trustworthy storage facts; indexing converts those facts into a persistent Argus source graph, recording presence immediately but accepting absence only when it has explicit authority to do so.

### 1.1 Activation scope

This was a forward MVP contract during Phase 000. PHASE-001 now activates only the local-filesystem provider, configured local roots, source-graph indexing, and LibraryScan subset explicitly bounded by the active phase and slices. Ready status alone still does not activate additional providers, watching, content processing, or placeholder modules beyond that scope.

## 2. Scope

This specification covers:

- source-provider identity and registration
- `SourceProviderType`
- `LibrarySource` provider configuration
- provider configuration versioning and instance revisioning
- `SourceProviderRegistry`
- `SourceProviderFactory`
- operation-scoped `LibrarySourceAccess`
- opaque root and relative locators
- provider-defined locator equality
- `SourceLocatorKey`
- root resolution and `ResolvedRoot`
- provider-verifiable root overlap checks
- source capabilities
- provider-native identity
- source fingerprints
- `SourceObservation`
- provider-neutral `DiscoveryPath`
- structural observation kinds
- persisted `SourceEntryKind`
- discovery policy
- classification boundaries
- scan planning
- one-active-scan-per-root ownership
- `ScanRun` lifecycle and `JobRun` relationship
- streamed enumeration and exact-scope authority
- incremental reconciliation
- `last_observed_scan_id`
- move detection
- policy pruning
- authoritative source removal
- root availability semantics
- source access errors
- cancellation and abandoned-scan recovery
- source-read consistency
- MVP local-filesystem adapter semantics
- repository and Unit of Work interaction
- event and diagnostics boundaries
- architecture, contract, reconciliation, and integration testing

## 3. Non-Responsibilities

This specification does not define:

- metadata-provider gateways, which are defined by SPEC-BE-010
- metadata matching, provider fallback, or metadata refresh
- artwork storage or download behavior
- RetroAchievements catalog or verification behavior
- transformation planning, derived-entry contracts, hash-scheme contracts, canonical `ContentIdentity`, and content-derived platform recognition, which are defined by SPEC-BE-012
- concrete parser-library implementation internals
- automatic reconciliation/merge of pre-existing duplicate `GameContent` records
- final `GameContent` orphan-retention or deletion policy
- eager hashing during discovery
- filesystem watching
- concurrent source discovery
- link traversal
- cloud or SMB provider implementations
- provider credential-store implementation
- bridge DTO shapes for library browsing
- exact SQL migration text or index syntax
- UI configuration workflows

Later transformation, hashing, game-content-resolution, and frontend specifications may build on this contract but must not weaken its source-authority rules.

## 4. Explicit Provider-Family Boundary

Source/storage providers and metadata/external-service providers are separate architectural families.

Source providers expose storage primitives such as root resolution, enumeration, stat, and byte access. Metadata providers expose information-service capabilities such as matching, refresh, and artwork discovery.

They differ in identity, lifecycle, configuration, retry, health, selection, and orchestration semantics. No generic provider abstraction may combine them merely because both use the word "provider".

Normative rule:

> `SPEC-BE-011` applies only to source/storage access and indexing. `MetadataProviderRegistry`, `ProviderSession`, and metadata capability interfaces from SPEC-BE-010 are not reused for source providers.

## 5. Architectural Principles

1. Providers report storage mechanics and facts; indexing owns traversal and interpretation.
2. Application code never depends on provider-native filesystem, SDK, path, stream, or error types.
3. Source-provider implementations are infrastructure adapters.
4. Persisted source configuration is authoritative application state.
5. Provider handles and resolved roots are transient runtime objects.
6. Generic application code never parses opaque provider locators.
7. Location equality is provider-defined rather than inferred from serialized path text.
8. Provider-native identity, current location, source fingerprint, and Argus entity identity are distinct concepts.
9. Positive observations may be persisted incrementally.
10. Absence is accepted only from an independently authoritative completed scope or a current deterministic policy exclusion.
11. Incomplete, failed, cancelled, abandoned, or unavailable scopes never imply absence.
12. Reconciliation correctness does not depend on observation order.
13. Move detection is conservative and never guesses from filename, timestamp, or size alone.
14. Discovery policy controls graph inclusion/traversal; classification controls semantic meaning.
15. Classification does not establish logical game identity.
16. Source removal owns source provenance removal, not `GameContent` lifecycle.
17. Provider I/O is never held open inside a database write transaction merely for indexing convenience.
18. One root has at most one active authoritative scan owner.
19. One `ScanRun` uses one immutable effective scan plan.
20. Immutable derived facts may only be committed from a source read proven to represent one stable source version.
21. MVP source traversal is single-threaded, but contracts remain valid if observation production becomes concurrent later.
22. Link-like storage objects are never traversed in MVP.

## 6. Architectural Position

Conceptually:

```text
Application scan command
        ↓
Scan planner / admission
        ↓
SourceProviderRegistry
        ↓
SourceProviderFactory
        ↓
LibrarySourceAccess
        ↓
ResolvedRoot
        ↓
streamed SourceObservation values
        ↓
Discovery policy
        ↓
Incremental reconciler
        ↓
Classifier
        ↓
short Unit of Work mutations
        ↓
authoritative scope finalization
```

The application layer owns scan planning, traversal, policy, reconciliation, classification, status derivation, and persistence orchestration.

The infrastructure layer owns concrete source adapters and native storage interaction.

The runtime owns background-operation execution and cancellation according to SPEC-BE-004.

The persistence layer remains accessed through application-owned repository and Unit of Work contracts according to SPEC-BE-002.

The bridge never accesses source providers directly.

## 7. Layer Ownership

### 7.1 Domain Layer

The domain owns stable business identities and source-graph concepts where they are intrinsic to the model, including typed identities such as:

- `LibrarySourceId`
- `LibraryRootId`
- `SourceEntryId`
- `GameContentId`

The domain must not depend on filesystem APIs, SQLite, provider SDKs, runtime handles, or bridge DTOs.

### 7.2 Application Layer

The application layer owns:

- source-provider port contracts
- `SourceProviderType`
- source capabilities
- normalized observations
- source access error vocabulary
- scan planning
- scan admission and exclusive root ownership
- discovery policy evaluation
- traversal decisions
- reconciliation
- classification coordination
- root availability interpretation
- `ScanRun` lifecycle semantics
- Unit of Work orchestration
- event publication after commit

### 7.3 Infrastructure Layer

Infrastructure owns:

- local-filesystem adapter implementation
- future SMB/cloud/removable-storage adapters
- native path handling
- native metadata/stat calls
- native identity extraction
- native file opening
- provider-specific configuration decoding
- provider-specific locator serialization and comparison
- provider-specific fingerprint construction
- native error translation

### 7.4 Runtime Layer

Runtime owns:

- the lifetime of one runtime generation
- operation admission and execution
- `JobRun` lifecycle
- cancellation context
- runtime-scoped source-provider registry composition

Runtime does not perform reconciliation or decide source semantics.

### 7.5 Bridge Layer

The bridge may expose application services and immutable library projections defined by bridge-specific specifications.

It must not expose:

- `LibrarySourceAccess`
- `ResolvedRoot`
- `SourceRead`
- provider-native handles
- native filesystem paths as generic internal contracts
- `SourceAccessError` directly as a Flutter contract

## 8. Source Identity Model

### 8.1 `SourceProviderType`

`SourceProviderType` identifies a stable implementation family, for example:

```text
local_filesystem
```

Future examples may include SMB or cloud-backed types.

`SourceProviderType` answers:

> How does Argus access this configured source?

It is not the identity of a user-configured source instance.

### 8.2 `LibrarySourceId`

`LibrarySourceId` identifies one persisted configured source instance.

Multiple `LibrarySource` records may share the same `SourceProviderType`.

Display names, paths, hostnames, API endpoints, mount names, and provider configuration values must not substitute for `LibrarySourceId`.

### 8.3 `LibraryRootId`

`LibraryRootId` identifies one configured scan boundary within one `LibrarySource`.

Different roots remain distinct reconciliation namespaces even if physical storage aliases or future cross-source configurations happen to point to the same bytes.

### 8.4 `SourceEntryId`

`SourceEntryId` identifies one Argus source-graph entity.

It may survive a provider-confirmed move when continuity is established according to this specification.

It is not a path, locator, fingerprint, native file ID, or content identity.

## 9. `LibrarySource` Configuration

Conceptually:

```text
LibrarySource
- id
- source_type
- display_name
- provider_config
- config_revision
- created_at
- updated_at
```

`source_type` stores the stable serialized form of `SourceProviderType`.

`config_revision` is a monotonically changing revision of this configured `LibrarySource` instance. Any change that may alter source-access semantics must advance it.

### 9.1 Versioned Provider Configuration

`provider_config` is a provider-owned structured configuration document contained within a stable Argus envelope.

Conceptually:

```text
ProviderConfigEnvelope
- schema_version
- config
```

`schema_version` describes the provider configuration document format. It is distinct from `LibrarySource.config_revision`.

The difference is normative:

```text
schema_version
    = which configuration format is this?

config_revision
    = which revision of this configured source instance is this?
```

Provider factories own decoding, validation, and provider-config schema migration.

A factory may produce an in-memory migrated/normalized configuration value, but it does not write repositories itself. Any durable configuration rewrite is owned by an application configuration workflow through the normal Unit of Work boundary.

Generic application and repository code must not interpret provider-specific configuration fields.

### 9.2 Secrets

Raw credentials, passwords, access tokens, private keys, or API keys must not be stored directly inside `provider_config`.

Provider configuration may hold an opaque credential reference when a future provider requires one.

Credential storage itself is outside this specification.

### 9.3 Local-Filesystem Configuration

The MVP `LocalFilesystem` provider may legitimately use an empty source-level configuration document.

User-selected scan paths belong to `LibraryRoot.root_locator`, not an invented provider configuration field.

### 9.4 Durable Platform Authorization

Some platforms require durable platform-specific authorization before a configured source can be accessed. For example, a sandboxed macOS application may persist a security-scoped bookmark so a user-selected folder remains accessible after restart.

Persisted source/root configuration may therefore include provider-owned opaque authorization material in addition to the logical path/location. The exact storage location is provider-owned configuration, not a domain-model field.

Rules:

1. The domain/application model never depends on platform-specific bookmark or authorization types; opaque authorization material is decoded only by the owning provider factory/adapter.
2. Generic application and repository code must not interpret persisted authorization material.
3. Reopening a configured local source after restart must restore or reacquire platform authorization before traversal begins. A persisted path string alone is not sufficient durable authorization on platforms that require more.
4. Stale, missing, or revoked authorization produces a typed `SourceAccessError`; it must not silently delete or rewrite the configured source/root, and it does not by itself prove the storage disappeared.
5. Non-sandboxed platforms/providers remain free to use simpler or empty authorization representations.

## 10. `LibraryRoot` Configuration

Conceptually:

```text
LibraryRoot
- id
- library_source_id
- root_locator
- display_name
- availability_status
- last_scan_status
- last_scan_started_at
- last_scan_completed_at
- discovery_policy
- config_revision
- created_at
- updated_at
```

`config_revision` is the revision of the root configuration relevant to scan authority. Changes to root locator, discovery policy, enablement, or other authority-affecting root configuration advance it.

Availability states remain:

```text
Available
Unavailable
Unknown
```

Root last-scan states remain:

```text
NeverScanned
Complete
Partial
Unavailable
Cancelled
Failed
Abandoned
```

## 11. Provider Registry and Binding

One runtime generation owns one runtime-composed `SourceProviderRegistry`.

Conceptually:

```text
SourceProviderRegistry
    -> SourceProviderFactory
    -> LibrarySourceAccess
```

Registry membership is fixed for one runtime generation.

The registry maps a `SourceProviderType` to the matching provider factory. It is not a generic service locator and does not contain scan policy.

### 11.1 `SourceProviderFactory`

A provider factory owns:

- provider-type identity
- provider configuration decoding
- provider configuration validation
- configuration-schema compatibility
- creation/binding of `LibrarySourceAccess`

The factory may reject configuration before any source access is created.

### 11.2 `LibrarySourceAccess`

`LibrarySourceAccess` is bound to exactly one `LibrarySourceId` and one top-level operation or `JobRun` execution attempt.

It may be reused by multiple `LibraryRoot` scans belonging to that source within the same owning operation when orchestration chooses to do so.

It may hold transient state such as:

- native connection/session handles
- future network connection state
- resolved credentials
- provider-local caches
- capability negotiation state

It is never persisted and never reused across runtime generations or unrelated execution attempts.

The name deliberately differs from metadata `ProviderSession` because source-provider lifecycle semantics are separate from SPEC-BE-010.

Normative invariant:

> The registry binds a configured source; `LibrarySourceAccess` performs storage operations for one execution attempt.

## 12. Source Access Contract

The cohesive application-owned source port conceptually supports:

```text
LibrarySourceAccess
- capabilities()
- compare_root_locators(...)
- resolve_root(...)
- enumerate_children(...)
- stat_entry(...)
- open_stream(...)
- native_identity(...)
```

Exact Rust method signatures are implementation-plan decisions, but the semantic boundary is fixed.

The contract exposes storage mechanics only.

It must not:

- recurse automatically
- own scan scheduling
- evaluate discovery policy
- classify entries
- reconcile entries
- perform move detection
- create `GameContent`
- compute semantic hashes as part of normal discovery
- write repositories
- own a Unit of Work
- publish application events

## 13. Source Capabilities

Providers expose typed capabilities sufficient for generic application logic to adapt without provider-specific branching.

Representative capabilities include:

```text
stable_native_identity
hierarchical_enumeration
seekable_streams
random_access
modification_timestamps
atomic_reads
case_sensitive_paths
supports_partial_enumeration
supports_change_notifications
supports_symlinks
```

Capabilities are promises, not guesses.

A provider type may have broad potential capabilities while a resolved root exposes narrower effective guarantees. Application behavior must use the effective guarantees applicable to the current bound source/root.

`supports_change_notifications` is capability vocabulary only. Filesystem watching remains post-MVP.

`supports_symlinks` does not imply link traversal is enabled. Link traversal is disabled for MVP regardless.

## 14. Locator Model

### 14.1 `RootLocator`

`LibraryRoot.root_locator` is an opaque provider-owned configured coordinate within a `LibrarySource`.

Generic application code must not:

- split it on separators
- infer drive letters
- resolve `.` or `..`
- normalize case
- assume URI semantics
- assume filesystem semantics

The provider may serialize it as text or another persistence-safe form, but the application treats it as opaque.

### 14.2 `RelativeSourceLocator`

A `RelativeSourceLocator` identifies a source entry relative to one resolved root namespace.

It is also opaque to generic application code.

A persisted relative locator must remain sufficiently stable that the provider can attempt to reopen the same current location after restart when that location still exists.

### 14.3 `SourceLocatorKey`

`SourceLocatorKey` is a separate provider-generated canonical equality key for the current location represented by a `RelativeSourceLocator`.

Conceptually:

```text
RelativeSourceLocator
    = where/how the provider reopens the entry

SourceLocatorKey
    = provider-defined equality for that current location
```

The provider must generate the key deterministically across restarts while the location semantics remain unchanged.

Generic application and persistence code may compare the key for equality but must not parse or construct it.

The source graph requires uniqueness within one root namespace:

```text
UNIQUE(library_root_id, locator_key)
```

The exact SQL representation is defined during schema implementation, but the uniqueness invariant is normative.

If two distinct observations within one root produce the same locator key, the provider response is invalid. Argus must not choose one by observation order.

### 14.4 Locator Key Is Not Identity

A locator key answers whether two observations represent the same current provider location.

It is not:

- `SourceEntryId`
- `ProviderNativeIdentity`
- `SourceFingerprint`
- `ContentIdentity`

A move may change `relative_locator` and `locator_key` while preserving `ProviderNativeIdentity` and `SourceEntryId`.

## 15. Root Relationship and Overlap

Within one `LibrarySource`, the provider owns locator relationship semantics.

Conceptually:

```text
RootRelationship
- Same
- Ancestor
- Descendant
- Disjoint
- Unknown
```

Configuration validation rules:

- `Same` -> reject
- `Ancestor` -> reject
- `Descendant` -> reject
- `Disjoint` -> allow
- `Unknown` -> allow conservatively

Generic application code must never infer overlap by comparing opaque locator strings.

`Unknown` means the provider cannot prove the relationship. It does not mean overlap is known.

Across different `LibrarySourceId` values, Argus does not attempt physical overlap detection. Later content identity may converge logical content while retaining distinct source provenance.

If a root edit would create provider-verifiable overlap, the configuration mutation must be rejected before it can become authoritative. SPEC-BE-011 does not automatically merge source graphs or migrate `SourceEntry` trees between roots.

## 16. Root Resolution

At scan start:

```text
ScanPlan.root_locator
        ↓
LibrarySourceAccess.resolve_root(...)
        ↓
ResolvedRoot
```

`ResolvedRoot` is a transient provider-owned handle/state object bound to the current `LibrarySourceAccess` and operation.

It is never persisted and never reused across runtime generations.

### 16.1 Successful Resolution Guarantees

Successful root resolution establishes that:

1. the configured locator is valid for the provider;
2. the target can currently be addressed;
3. the target represents an enumerable root scope;
4. relative locators beneath it belong to that root namespace;
5. provider operations can enforce the root boundary;
6. effective capabilities for the root are known sufficiently for the scan.

For the MVP local-filesystem provider, a configured root must resolve to a directory-like enumerable object.

A normal file cannot be configured as a library root.

### 16.2 No Silent Canonicalization

Resolution must not silently rewrite the persisted `LibraryRoot.root_locator` merely because the provider or operating system exposes another canonical spelling.

Provider-native normalization may occur internally for access and comparison.

Changing the configured locator is a configuration-management action, not a scan side effect.

A configured root that is renamed externally is treated as unavailable at its configured locator. Provider-native identity does not automatically cause the configured root boundary itself to follow a move.

### 16.3 Link-Like Roots

For MVP, the resolved root itself must not be a link-like object such as a symlink, alias, junction, or equivalent provider redirect.

This prevents root resolution from becoming implicit link traversal.

## 17. Source Observations

Provider enumeration emits normalized Argus-owned facts.

Conceptually:

```text
SourceObservation
- relative_locator
- locator_key
- discovery_path
- observed_kind
- display_name
- provider_native_identity?
- source_fingerprint
- metadata
```

Observations contain no `SourceEntryId`; the reconciler assigns or preserves Argus identity.

Native OS or SDK types must not escape infrastructure.

### 17.1 Observation Metadata

Observation metadata is bounded to cheap provider facts useful to indexing, for example:

```text
size?
modified_at?
created_at?
hidden?
read_only?
```

Presence of individual facts is capability-aware.

`enumerate_children()` should return enough cheap facts to avoid a mandatory `stat_entry()` call for every child.

`stat_entry()` exists for targeted refresh/revalidation, opening known locators, or providers whose enumeration cannot supply sufficient metadata.

## 18. Structural Kind and Persisted Entry Kind

Provider-observed storage shape and Argus-derived source interpretation are separate concepts.

### 18.1 `ObservedEntryKind`

Providers report only structural shape:

```text
ObservedEntryKind
- Directory
- File
- LinkLike
- Other
```

Providers do not report semantic format concepts such as archive, playlist, or disc image.

### 18.2 `SourceEntryKind`

Argus owns the richer persisted interpretation:

```text
SourceEntryKind
- Directory
- File
- LinkLike
- Archive
- ArchiveEntry
- DiscImage
- Playlist
- VirtualContainer
- Unknown
```

The set may be extended by later specifications without changing the provider boundary.

A retained provider file may initially persist as `File` and later be refined to `Archive`, `Playlist`, or another application-owned kind without changing `SourceEntryId`.

### 18.3 Kind Is Not Classification

Kind answers what type of source object Argus understands the node to be.

Classification answers what role the node plays in library processing.

Examples:

```text
SourceEntryKind::Archive + Classification::Container
SourceEntryKind::Playlist + Classification::ContentCandidate
SourceEntryKind::File + Classification::SupportingEntry
SourceEntryKind::LinkLike + Classification::Ignored
```

## 19. Provider-Native Identity

`ProviderNativeIdentity` represents continuity of the same underlying storage object when the provider can guarantee that concept.

Rules:

1. It is opaque and provider-defined.
2. It is scoped to one `LibrarySource`.
3. It may remain stable across rename/move only when the provider guarantees that behavior.
4. It is optional.
5. It is never parsed by application logic.
6. It is not `SourceEntryId`.
7. It is the strongest source-level move signal when available.

If stable native identity cannot be guaranteed, the provider must not synthesize it from path, filename, size, or timestamp.

## 20. Source Fingerprints

`SourceFingerprint` is cheap evidence relevant to whether cached or derived assumptions may still be reusable.

It is not global identity and is not a content hash.

A fingerprint may incorporate provider-appropriate cheap facts such as:

- structural kind
- size
- modification metadata
- provider revision/generation token
- other cheap native revision facts

The fingerprint representation must be self-describing enough to support revisioned semantics, conceptually including a scheme/revision plus opaque provider data.

Equal fingerprints mean only that the provider's defined cheap change evidence is unchanged under the current fingerprint scheme.

Fingerprint changes invalidate affected derived assumptions according to later feature specifications.

Routine indexing must not read entire file contents solely to construct `SourceFingerprint`.

## 21. Discovery Path

`DiscoveryPath` is the explicit provider-neutral path projection used by application discovery policy.

Conceptually:

```text
DiscoveryPath
- segments: [DiscoverySegment]
```

It is distinct from `RelativeSourceLocator`.

The provider constructs it from native namespace structure and guarantees:

- it is root-relative;
- one segment represents one logical child name;
- native separator rules have already been resolved;
- traversal escapes such as parent-directory semantics cannot escape the root;
- the provider's declared comparison semantics apply to equivalent names.

Application code may inspect and pattern-match `DiscoveryPath` but never parses the opaque locator to reproduce it.

### 21.1 Pattern Syntax

Discovery include/exclude rules use one Argus-owned portable syntax.

`/` in the policy language is a logical segment separator, not an operating-system path separator.

Provider-specific options remain separate typed provider configuration/policy options and must not be hidden inside glob syntax.

### 21.2 Case Semantics

Pattern evaluation follows the effective provider/root path-comparison semantics, represented through capability data such as `case_sensitive_paths`.

The application must not infer case behavior from operating-system name or locator text.

Maximum-depth evaluation uses `DiscoveryPath` segment depth rather than parsing provider locators.

## 22. Discovery Policy

Discovery policy controls whether an observed storage node enters the managed source graph and whether traversal continues through it.

Conceptually the policy produces two independent decisions:

```text
DiscoveryDecision
- retain_entry
- traverse_children
```

Representative cases:

```text
structurally excluded file
    retain = false
    traverse = false

structurally excluded directory
    retain = false
    traverse = false

accepted directory
    retain = true
    traverse = true

link-like entry in MVP
    retain = policy-dependent
    traverse = false
```

Discovery policy may include:

- include patterns
- exclude patterns
- hidden/system behavior
- archive traversal policy
- maximum depth
- link traversal disabled for MVP
- provider-specific options

Policy evaluation is deterministic for a frozen scan plan.

### 22.1 Phase 001 fixed discovery policy

PHASE-001 activates one non-configurable policy:

| Provider observation | Retain | Traverse |
|---|---:|---:|
| Directory | Yes | Yes |
| File | Yes | No |
| Link-like | Yes | No |
| Other/unsupported structural object | Yes | No |

The active policy has no filename-, extension-, include-pattern-, exclude-pattern-, hidden-, or system-attribute exclusion rule. Ordinary provider-visible hidden/system directories and files therefore remain in the managed graph under the same structural rules.

Link-like objects are retained as evidence but never traversed. Phase 001 has no user-configurable semantic maximum depth. Implementations still enforce bounded safety/resource limits; exhausting such a limit makes the affected scope incomplete and therefore yields `Partial` or `Failed` according to committed useful work. It never authorizes absence or a falsely truncated `Complete` result.

The full effective policy and policy revision are frozen into the scan plan.

## 23. Classification

Classification is application-owned and occurs after a retained observation has been reconciled into the source graph.

Classification values remain:

```text
Container
ContentCandidate
SupportingEntry
Ignored
Unknown
```

The classifier may use:

- Argus-owned cheap observation facts
- persisted source kind
- ancestor/sibling structural context when required
- frozen classification policy revision

The classifier must not:

- perform network access
- call metadata providers
- compute expensive hashes
- arbitrarily open source content as part of routine discovery
- implement provider-specific storage policy
- mutate persistence directly

Unknown is preferred over unsupported guessing.

A later deterministic reclassification may change classification without changing source identity.

Structural exclusion and semantic `Ignored` remain different:

```text
structural exclusion
    -> outside managed SourceEntry graph

Classification::Ignored
    -> retained SourceEntry intentionally treated as non-content
```

### 23.1 Phase 001 fixed classification

PHASE-001 maps retained observations deterministically:

| Persisted source kind | Classification |
|---|---|
| `Directory` | `Container` |
| `File` | `Unknown` |
| `LinkLike` | `Ignored` |
| `Unknown` | `Ignored` |

Archive-like, disc-image-like, playlist-like, and similarly named files remain ordinary `File` entries classified `Unknown`. Phase 001 does not infer `ContentCandidate`, archive, playlist, disc-image, or logical game meaning from a filename or extension.

## 24. Traversal Ownership

The indexer owns traversal.

A source provider enumerates one native storage scope at a time. It does not recursively scan a tree on behalf of the application.

For native directories:

```text
indexer schedules scope
    ↓
provider enumerates direct children
    ↓
indexer decides which child scopes to schedule
```

### 24.1 Derived Containers

Archives and other derived/virtual containers are not source providers.

The source provider supplies the underlying bytes through the source-read contract. A parser/transformation component interprets the container. The indexer decides whether the container should be traversed and reconciles derived child entries according to the same exact-scope authority principles.

The component that enumerates a scope is the component that can report whether that exact scope completed authoritatively:

- source provider for native storage scopes
- archive/parser component for archive scopes
- transformation owner for other virtual scopes

Detailed derived-entry observation shapes, transformation version evidence, and parsing rules are defined by SPEC-BE-012 — Transformation and Hash-Scheme Contract.

### 24.2 Link-Like Entries

Link-like objects may be observed and optionally retained according to discovery policy, but the indexer never schedules them for traversal in MVP.

The provider must also use no-follow semantics sufficient to identify link-like children instead of transparently treating them as traversable target directories.

## 25. Enumeration Outcome and Authority

Enumeration is streamed and ends with an explicit terminal outcome for the exact enumerated scope.

Conceptually:

```text
EnumerationOutcome
- Complete
- Partial
- Unavailable
- Failed
- Cancelled
```

### 25.1 Presence

Each valid observation is positive evidence of presence and may be reconciled/persisted before the scope completes.

This remains true if the containing scan later becomes `Partial`, `Failed`, `Cancelled`, or `Abandoned`.

### 25.2 Absence

Only `Complete` establishes authority to infer absence for unobserved entries in that exact enumeration scope.

No other outcome authorizes absence-based deletion.

### 25.3 Exact-Scope Semantics

Authority does not automatically propagate to descendants.

A parent directory may enumerate completely even when a child directory later fails to enumerate.

Example:

```text
Root enumeration -> Complete
A observed
A enumeration -> Failed
```

The scan may authoritatively reason about which direct children exist under Root. It may not infer absence among the unobserved descendants of A.

### 25.4 Provider Omissions

A provider must not return `Complete` when it knowingly omitted children required by the requested enumeration semantics.

If a provider cannot support partial enumeration semantics and encounters an interruption that makes the result incomplete, it must report `Failed`, `Unavailable`, or `Cancelled` as appropriate rather than falsely returning `Complete`.

### 25.5 Pagination

Provider pagination boundaries are infrastructure details.

Completion of an internal provider page does not create application-level authority for that portion of the namespace. The application observes one logical streamed scope and one terminal `EnumerationOutcome`.

## 26. Enumeration Ordering

Provider enumeration order is unspecified.

Equivalent complete child sets may arrive in different orders across scans.

Reconciliation, classification, move detection, and authoritative final state must not depend on:

- alphabetical ordering
- native directory iteration order
- provider pagination order
- creation order
- observation arrival order

The first ambiguous candidate must never win merely because it arrived first.

Presentation ordering is a query/projection concern and must use explicit sort semantics.

## 27. Scan Plan

Every `ScanRun` executes from one immutable effective `ScanPlan` captured at admission.

Conceptually:

```text
ScanPlan
- scan_run_id
- library_root_id
- library_source_id
- root_locator
- discovery_policy
- classification_policy_revision
- source_provider_type
- source_config_revision
- root_config_revision
```

The plan is an execution value and does not require a dedicated persistence table for MVP.

The scan uses the captured source/root configuration throughout its execution. It must not repeatedly reread mutable configuration and silently change behavior halfway through the run.

### 27.1 Configuration Changes During a Scan

Configuration edits apply to future scans.

A root removal/disable action may request cancellation of an active scan, but it does not cause the active scan to switch plans.

Before destructive authoritative finalization, indexing must verify that the relevant current source/root revisions remain compatible with the plan.

If incompatible configuration has superseded the plan:

- already committed positive observations remain valid;
- absence deletion is suppressed;
- the run becomes `Partial` rather than pretending full authority.

A full serialized copy of every configuration field need not be persisted with `ScanRun`; bounded provenance/revision information is sufficient unless later audit requirements demand more.

## 28. Per-Root Exclusive Scan Ownership

At most one active `ScanRun` may own one `LibraryRoot` at a time.

A duplicate scan request for an already-owned root does not create a competing `ScanRun`.

Conceptually it returns an application outcome such as:

```text
AlreadyScanning
- library_root_id
- active_scan_run_id
```

The ownership rule is application-level indexing policy, not a filesystem lock.

Ownership begins before the scan enters active discovery and remains held through authoritative finalization and terminal status persistence.

It is not released between scope transactions.

A multi-root job may continue processing other roots even if one requested root is already scanning. MVP does not hide a retry queue behind this condition.

After a process crash, runtime-local ownership disappears. Before the replacement runtime becomes `Ready`, startup recovery under SPEC-BE-004 and the scan-specific policy in Section 46 reconciles stale `Running` scans: a stale `Running` scan whose owning job has accepted durable cancellation intent becomes `Cancelled`; any other stale `Running` scan becomes recovery-only `Abandoned`. After that reconciliation, a fresh scan may be admitted with new `JobRun` and `ScanRun` identities.

No distributed lease is required for MVP.

## 29. `ScanRun` and `JobRun`

`JobRun` and `ScanRun` are separate durable concepts.

- `JobRun` describes one generic background execution attempt according to SPEC-BE-004.
- `ScanRun` describes what happened while scanning one `LibraryRoot`.

Conceptually:

```text
ScanRun
- id
- job_run_id
- library_root_id
- status
- started_at
- completed_at
- failure_reason
```

`Running` is the only active `ScanRun` status. Terminal statuses are `Complete`, `Partial`, `Failed`, `Cancelled`, and recovery-only `Abandoned`. `Unavailable` is a root last-scan summary derived from a failed root-level access attempt; it is not a separate terminal `ScanRun` status.

One `JobRun` may own multiple `ScanRun` records.

Job status and individual root-scan status are not required to be one-to-one.

A retry creates a new `JobRun` and new `ScanRun` records. Historical runs are not reopened.

On startup, a stale `ScanRun` still marked `Running` becomes `Cancelled` when durable cancellation intent had already been accepted for its owning `JobRun`; otherwise it becomes recovery-only `Abandoned`. Already-terminal `ScanRun` records remain unchanged and drive aggregate job recovery rather than being overwritten.

`LibraryRoot.last_scan_*` fields are summaries of recent root state, not replacements for durable `ScanRun` history.

## 30. Scan Execution Flow

Admission and execution are separate boundaries:

```text
admission (LibraryService / focused workflow handler)
    validate request and active ownership
    ↓
freeze effective ScanPlan / configuration revision
    ↓
create JobRun + child ScanRun(Running) + acquire root ownership
    ↓
hand off to BackgroundOperationManager
    ↓
execution (LibraryScanOperationHandler)
    ↓
bind LibrarySourceAccess
    ↓
resolve root
    ↓
single-threaded traversal scheduler
    ↓
stream SourceObservation values
    ↓
discovery policy
    ↓
incremental reconciliation + classification
    ↓
exact-scope finalization as scopes complete
    ↓
derive root/scan terminal status
    ↓
commit terminal records
    ↓
publish post-commit events
    ↓
release root ownership
```

Concurrency may be added later, but no downstream contract may assume one permanent producer or meaningful arrival ordering.

## 31. Incremental Reconciliation

Presence reconciliation occurs incrementally as observations arrive.

For each retained valid observation, indexing may perform a short Unit of Work that:

- finds the current entry by root and locator key;
- attempts native-identity continuity where appropriate;
- creates a new `SourceEntry` when required;
- updates current locator/fingerprint/cheap facts;
- reparents a provider-confirmed move;
- sets `last_observed_scan_id` to the current run;
- persists current source kind/classification when determined;
- updates known source provenance relationships when independently justified.

Provider I/O must complete before opening the write transaction for that mutation.

Batching several observations is an implementation optimization only when it preserves the same authority and crash-safety semantics.

## 32. `last_observed_scan_id`

`SourceEntry.last_observed_scan_id` means exactly:

> The most recent `ScanRun` that positively observed and reconciled this `SourceEntry`.

It is positive-presence evidence only.

Argus must not clear all observation markers at scan start.

Entries observed during a run retain that evidence even if the scan later becomes incomplete, cancelled, failed, or abandoned.

A stale marker alone never authorizes deletion.

For a completed exact parent scope, the finalizer may identify prior direct children not marked with the current `ScanRunId` as absence candidates. It must then complete move matching and authority checks before deletion.

## 33. Move Detection

Move detection is conservative and tiered.

### 33.1 Tier 1: Provider-Native Identity

When stable provider-native identity is supported and an observation unambiguously matches an existing entry in the relevant source namespace, indexing may preserve the existing `SourceEntryId` while changing parent/locator information.

### 33.2 Tier 2: Strong Content Identity

When no reliable native identity exists, `ContentIdentity` may support move reconciliation only when one absent prior entry and one new entry form a unique one-to-one match in the relevant completed reconciliation scope.

This tier is available only when strong content identity already exists from later content-processing work. Indexing does not eagerly compute it merely to improve move detection.

PHASE-001 has no authoritative `ContentIdentity`, so this tier is inactive for the entire phase. During Phase 001 only an unambiguous stable provider-native identity may preserve `SourceEntryId`; every other apparent move becomes removal plus creation after the relevant completed scope establishes absence authority.

### 33.3 Tier 3: Removal Plus Creation

If continuity cannot be established unambiguously, the result is removal plus creation.

### 33.4 Prohibited Move Heuristics

MVP must not preserve source identity based only on:

- similar filename
- similar path
- timestamp
- size
- extension
- observation order

Ambiguous matches remain ambiguous.

## 34. Scope Finalization

Only a `Complete` exact scope may perform absence-based finalization.

Conceptually:

1. identify prior direct children not observed by the current scan;
2. perform any remaining conservative move reconciliation that requires the completed child set;
3. recheck current source/root configuration authority;
4. remove unmatched authoritatively absent entries;
5. commit the coherent mutation;
6. treat that exact scope as authoritatively finalized.

If the scope outcome is `Partial`, `Failed`, `Unavailable`, or `Cancelled`, no absence-based finalization occurs for that scope.

An overall `ScanRun` may be `Partial` while individual completed scopes still performed valid authoritative finalization.

## 35. Discovery-Policy Pruning

A current frozen discovery policy may deliberately exclude storage from the managed Argus source graph.

That authority is distinct from provider absence.

If a previously indexed subtree becomes deterministically excluded by the current compatible policy revision, a successful scan may remove that subtree from the managed graph even though the provider did not enumerate inside it.

Such removal means:

> This subtree is intentionally outside the configured Argus discovery scope.

It does not mean the underlying storage disappeared.

Policy pruning is permitted only when:

- the exclusion rule deterministically covers the affected subtree;
- the scan reached enough structure to identify the excluded boundary;
- the current configuration revision still authorizes the policy;
- a provider failure is not being misrepresented as policy exclusion.

A deliberately excluded scope does not make the scan `Partial`.

## 36. Source Removal and `GameContentSource`

Authoritative removal of a `SourceEntry` subtree is one coherent source-graph mutation.

The same Unit of Work removes:

- the affected `SourceEntry` subtree;
- `GameContentSource` relationships referencing those entries.

When SPEC-BE-012 identity provenance exists, the owning application coordinator also invalidates/removes provenance references to the removed entries and transitions any affected currently identified `GameContent` to the BE-012 re-identification state unless an explicit identification workflow has already established replacement proof.

No provider I/O occurs inside that write transaction.

The indexing reconciler does not compute replacement content identity or directly delete `GameContent` merely because source provenance disappears.

It also does not directly delete content-owned:

- hashes
- metadata
- artwork
- external identities
- RetroAchievements verification state

Later game-content lifecycle work owns final orphan cleanup and automatic reconciliation/merge of pre-existing duplicate `GameContent` records. SPEC-BE-012 owns strong identity convergence for newly identified content but deliberately does not auto-merge pre-existing duplicates.

Database foreign keys may support referential integrity, but semantic correctness must not depend on accidental cascade behavior alone.

## 37. Classification and `GameContent` Boundary

`Classification::ContentCandidate` does not automatically create `GameContent`.

Indexing may preserve or update an existing `GameContentSource` relationship when it has authoritative existing evidence for that relationship.

Otherwise a content candidate remains an unmaterialized candidate until later content-identification work establishes the strong logical identity required to create or link `GameContent`.

A move that preserves `SourceEntryId` naturally preserves its source relationship unless independent evidence shows the content changed.

A content-affecting fingerprint change marks downstream identity/hash assumptions stale according to SPEC-BE-012; indexing must not invent a new logical game identity from the fingerprint alone.

Normative invariant:

> Classification establishes candidacy; strong content identity establishes logical `GameContent` identity.

## 38. Source Access Errors

Application-owned source operations use a stable `SourceAccessError` vocabulary.

Representative variants:

```text
SourceUnavailable
EntryNotFound
PermissionDenied
AuthorizationUnavailable
InvalidLocator
InvalidConfiguration
UnsupportedOperation
IoFailure
InvalidResponse
Cancelled
```

Concrete adapters translate native filesystem/SDK errors before those errors cross the infrastructure boundary.

`SourceAccessError` explains why an operation failed. It is separate from `EnumerationOutcome`, which expresses whether a scope is authoritative.

`AuthorizationUnavailable` covers stale, missing, or revoked platform authorization for a configured source (for example an expired macOS security-scoped bookmark). It must never cause the configured source/root to be deleted or rewritten, and it does not by itself prove that the underlying storage physically disappeared.

MVP source access has no generic automatic retry layer. A local filesystem failure is returned to the owning indexing workflow rather than silently retried as policy. Retry behavior for future remote/network source providers requires an explicit later contract; it must not be inferred from metadata-provider retry rules in SPEC-BE-010.

A provider error must not directly mutate persisted root availability.

## 39. Availability Semantics

`LibraryRoot.availability_status` is application-owned current evidence about root reachability.

Representative interpretation:

- successful root resolution/enumeration -> evidence for `Available`;
- root-level missing or unreachable source -> evidence for `Unavailable`;
- no sufficiently recent evidence -> `Unknown`;
- nested entry disappearance -> does not make the root unavailable;
- nested permission denial -> does not make the root unavailable;
- archive parse failure -> does not make the root unavailable;
- cancellation -> does not make the root unavailable.

A permission failure at the configured root is a scan failure, but it must not automatically be treated as proof that the root physically disappeared.

A stale/revoked platform authorization prevents traversal and may contribute application-owned evidence of `Unavailable` or `Unknown`, but it never deletes the configured source/root and never grants absence authority.

Availability policy may evolve later, but providers themselves do not write these states.

## 40. `ScanRun` Terminal Status

`ScanRun.status` describes the semantic result of scanning one root.

### 40.1 `Complete`

`Complete` requires:

- successful root resolution;
- every scope required by the frozen scan plan to have completed authoritatively;
- policy-pruned scopes to have been intentionally excluded rather than failed;
- all required destructive finalization to have remained authorized by current configuration.

### 40.2 `Partial`

`Partial` means useful indexing progress was committed, but full authority for the required discovery scope was not established.

Examples include:

- one nested required scope failed after other work succeeded;
- a scope produced valid observations before terminal failure;
- configuration changed incompatibly before destructive finalization.

### 40.3 `Failed`

`Failed` means the scan did not produce a meaningful indexing result for the root.

Examples include:

- root resolution failed before useful discovery;
- root enumeration failed before any useful observation was committed;
- invalid source/root configuration prevented execution.

### 40.4 `Cancelled`

If cancellation determines termination before a durable terminal result was committed, the `ScanRun` becomes `Cancelled` regardless of previously committed positive observations.

Cancellation is not converted to `Partial` merely because some work was committed.

### 40.5 `Abandoned`

`Abandoned` is recovery-only. Normal scan execution does not explicitly choose it.

Startup converts a stale `Running` scan to `Abandoned` only when durable cancellation intent had not been accepted for the owning job; a stale `Running` scan with accepted durable cancellation intent becomes `Cancelled` instead. Both mappings follow SPEC-BE-004 restart reconciliation and this scan-specific policy.

## 41. Root Last-Scan Status Mapping

Normal mapping is:

```text
ScanRun Complete   -> LibraryRoot Complete
ScanRun Partial    -> LibraryRoot Partial
ScanRun Cancelled  -> LibraryRoot Cancelled
ScanRun Failed     -> LibraryRoot Failed
ScanRun Abandoned  -> LibraryRoot Abandoned
```

A root-level source-unavailability failure is represented specially:

```text
ScanRun.status = Failed
LibraryRoot.last_scan_status = Unavailable
LibraryRoot.availability_status = Unavailable
```

A nested unavailable scope under an otherwise reachable root produces a `Partial` scan and does not make the root itself unavailable.

`ScanRun.failure_reason` stores only a bounded terminal summary. Detailed provider/scope failures belong in diagnostics according to SPEC-BE-003.

`Cancelled` and `Abandoned` root last-scan summaries describe execution history; they do not by themselves change root availability.

## 42. Transaction and Unit of Work Strategy

Indexing uses short coherent Unit of Work mutations.

A complete scan is never one long SQLite transaction.

Representative coherent mutations include:

- create/update one reconciled entry;
- reparent a confirmed move;
- update one known `GameContentSource` relationship;
- remove one authoritatively absent subtree and its provenance edges;
- finalize a bounded completed scope;
- update `ScanRun`/`LibraryRoot` terminal summary state.

Application handlers/coordinators own Unit of Work lifecycle according to SPEC-BE-002.

Repositories never start or commit transactions themselves.

### 42.1 No Provider I/O Inside Write Transactions

Provider enumeration, stat, root resolution, and source reads occur outside database write transactions.

Before destructive finalization begins a write transaction, indexing must already have established:

- exact-scope completion;
- move-reconciliation evidence;
- current configuration authority;
- the set of entries affected by the coherent mutation.

Bounded database reads required to form the mutation may occur according to repository/UoW design, but arbitrary storage I/O must not be held across the transaction.

## 43. Source Read Consistency

A source may change while Argus reads it. The source port therefore exposes explicit consistency semantics rather than pretending every stream is a stable snapshot.

Conceptually:

```text
SourceRead
- byte_stream
- consistency_mode
- provider-owned validation state
```

Consistency modes:

```text
Atomic
RequiresValidation
```

For a non-atomic read, completion validation returns:

```text
Consistent
Changed
Indeterminate
```

The provider owns the mechanism used to establish this result.

A pre/post `SourceFingerprint` comparison may be one provider technique but is not itself the universal architectural guarantee.

### 43.1 Derived-Data Rule

Anything that claims to describe immutable content may only be committed when the consumed read is either:

- `Atomic`; or
- `RequiresValidation` followed by `Consistent`.

This includes future:

- `ContentIdentity`
- hash records
- authoritative derived container structure

If validation returns `Changed`, the derived result is discarded.

If it returns `Indeterminate`, the caller must not persist the result as trusted immutable data. The owning application workflow decides failure/retry behavior.

### 43.2 Read Lifetime

`SourceRead` is transient, belongs to its `LibrarySourceAccess`, and never survives runtime-generation replacement.

It is never persisted or bridged to Flutter.

A provider must not silently reopen a changed source and concatenate bytes from different versions into one supposedly coherent read.

## 44. MVP Local-Filesystem Provider

MVP implements one provider type:

```text
SourceProviderType::LocalFilesystem
```

Windows, macOS, and Linux do not become separate persisted provider types.

### 44.1 Root-Specific Semantics

The adapter may expose effective guarantees based on the resolved root/filesystem rather than broad operating-system stereotypes.

It must not blindly assume:

```text
Windows = always case-insensitive
macOS = always case-insensitive
Linux = always case-sensitive
```

If a guarantee cannot be established reliably, the adapter must not claim it. For path comparison in particular, the resolved root must expose explicit effective semantics sufficient for `DiscoveryPath` matching rather than encoding uncertainty as a false case-sensitivity claim.

### 44.2 Native Identity

The adapter should expose stable native identity when the underlying filesystem/platform can provide a sufficiently stable provider-scoped token.

The internal representation may incorporate volume/filesystem namespace information when required to avoid collisions.

If continuity cannot be guaranteed, `stable_native_identity = false` and observations omit native identity.

Paths, filenames, size, and timestamps must not be fabricated into a fake native identity.

### 44.3 No-Follow Enumeration

The adapter must inspect entries with semantics sufficient to identify link-like objects without following them for traversal decisions.

Link-like entries may be returned as `ObservedEntryKind::LinkLike`, but the indexer never schedules them in MVP.

### 44.4 Enumeration Races

External filesystem mutation during a scan is normal.

For example:

```text
enumerate -> entry exists
stat/open -> entry no longer exists
```

The targeted operation returns an appropriate error such as `EntryNotFound`. That event does not automatically make the root unavailable.

The adapter does not attempt to freeze or globally lock the filesystem tree.

### 44.5 Fingerprints

Local filesystem fingerprints use only reliable cheap filesystem facts available for the resolved root/platform.

Routine fingerprint construction must not read whole file contents.

### 44.6 Root Boundary Enforcement

Opening/statting an entry is performed through the provider using the resolved root and opaque relative locator.

Generic application-side native path concatenation is prohibited.

The adapter must enforce that requested source access cannot escape the resolved root namespace.

### 44.7 Platform Authorization

On platforms that require durable platform authorization (for example a sandboxed macOS application), the provider restores or reacquires that authorization before resolving/enumerating a configured root after restart.

Rules:

1. Authorization material is provider-owned and opaque; it never crosses application, bridge, event, or diagnostics contracts.
2. The provider must not treat the persisted logical path/location alone as durable authorization on platforms that require more.
3. If authorization cannot be restored or has been revoked, the provider returns a typed source-access failure (Section 38). The configured source/root remains persisted and may be revalidated; it is never silently deleted or rewritten by a failed authorization attempt.

## 45. Cancellation

Cancellation propagates from the owning runtime operation through scan traversal and source access.

Providers must stop initiating new work promptly when cancellation is observed and translate cancellation to `SourceAccessError::Cancelled` where an in-flight source operation terminates for that reason.

An interrupted enumeration reports `EnumerationOutcome::Cancelled` rather than `Complete`.

Already committed positive observations remain valid.

Cancellation never creates absence authority and never changes root availability merely because the user stopped the operation.

Cancellation is job-scoped: it targets the owning background execution, not an individual root inside a multi-root `JobRun`. A root whose child `ScanRun` already reached `Complete` before cancellation keeps that durable outcome; still-active child runs terminate as `Cancelled`, and the owning job is `Cancelled` when cancellation determines termination.

A cancellation request arriving while a coherent mutation or scope finalization is already committing does not interrupt that in-flight transaction. The mutation commits atomically, the finalized scope retains its `Complete` outcome, and cancellation is observed at the next safe checkpoint.

## 46. Crash and Recovery Semantics

Indexing uses in-place committed presence rather than a scan-wide transaction, so a process may terminate after some observations have been committed.

Before the replacement runtime becomes `Ready`, bounded persistence-only reconciliation applies these rules:

- already-terminal `ScanRun` records remain unchanged;
- a stale `Running` `ScanRun` becomes `Cancelled` when durable cancellation intent had already been accepted for its owning `JobRun`;
- otherwise a stale `Running` `ScanRun` becomes recovery-only `Abandoned`;
- the owning root's last-scan summary is updated to the recovered child outcome;
- `Cancelled` and `Abandoned` do not change root availability merely because execution stopped;
- committed positive observations remain valid;
- no incomplete scope gains absence authority retroactively;
- stale runtime-local root ownership disappears;
- recovery performs no provider I/O, enumeration, retry admission, automatic resume, or new scan work;
- a fresh user-initiated scan uses a new `JobRunId` and `ScanRunId`.

Already-terminal child truth is not overwritten merely because parent job aggregation was interrupted. Parent-job aggregation and readiness failure behavior are governed by SPEC-BE-007 and SPEC-BE-013.

No rollback of the entire cancelled or abandoned scan is attempted.

## 47. Events

Indexing follows SPEC-BE-006 event durability rules.

Persistence commits before event publication.

Representative indexing-owned events include:

```text
SourceEntriesChanged
LibraryRootChanged
```

Generic `JobStateChanged` and `JobProgress` notifications remain owned by the background-operation/runtime contract. Indexing does not introduce a competing `LibraryScanCompleted` lifecycle event.

Events describe committed application state changes; they are not the durable scan history.

Consumers must not rely on one event per individual source observation or assume event order mirrors provider enumeration order.

Event coalescing is permitted where it preserves meaningful committed-state notification semantics.

`GamesRemoved` must not be emitted merely because indexing removed a source path unless the later game-content lifecycle policy actually removed the logical game.

## 48. Diagnostics and Observability

Indexing and source-provider diagnostics follow SPEC-BE-003.

Diagnostics should include stable context where available, such as:

- `TraceId`
- `JobRunId`
- `ScanRunId`
- `LibrarySourceId`
- `LibraryRootId`
- `SourceProviderType`
- `SourceEntryId` when known
- bounded safe locator/display context when policy permits

Provider-native errors are translated before crossing infrastructure.

Logs and diagnostics must not expose raw secrets or secret-bearing provider configuration.

`ScanRun.failure_reason` is not a replacement for detailed diagnostic records.

## 49. Repository Contracts

Exact repository method names are implementation details, but application persistence contracts must support the semantics required here.

At minimum, indexing needs bounded operations equivalent to:

- load `LibrarySource` and `LibraryRoot` configuration/revisions;
- create and update `ScanRun`;
- query active scan ownership/state as required by the application admission mechanism;
- find a source entry by `(LibraryRootId, SourceLocatorKey)`;
- find candidate entries by provider-native identity within the correct source/root scope;
- list prior direct children for exact-scope finalization;
- create/update/reparent `SourceEntry`;
- update `last_observed_scan_id`;
- read/update source relationships;
- remove an authoritative subtree and its source relationships atomically;
- update root availability and last-scan summaries.

Repositories remain technology-neutral application ports. SQLite-specific queries and row mappings remain infrastructure details.

## 50. Dependency Rules

The following rules are normative:

1. Application source contracts must not depend on native filesystem/path types.
2. Application source contracts must not depend on metadata-provider contracts from SPEC-BE-010.
3. Concrete source adapters may depend inward on stable Argus source-port contracts.
4. Source adapters must not call repositories or Unit of Work implementations.
5. Source adapters must not publish application events.
6. Source adapters must not classify or create `GameContent`.
7. Reconciliation must not import concrete local-filesystem adapter types.
8. Discovery policy must not parse provider locators.
9. Bridge/generated DTO modules must not be source-provider contracts.
10. Runtime operation machinery must not own source reconciliation policy.
11. Parser/transformation implementations must not masquerade as source providers merely because they enumerate derived children.
12. Persisted provider configuration must not embed infrastructure-native SDK objects.

## 51. Architecture Tests

Architecture checks should enforce, where practical:

- source-provider application contracts contain no native filesystem/SDK types;
- application indexing modules do not import concrete source adapters;
- source adapters do not import repositories, Unit of Work implementations, or bridge DTOs;
- metadata-provider and source-provider registries remain separate families;
- no generic provider abstraction combines SPEC-BE-010 and SPEC-BE-011 contracts;
- generic indexing code does not parse `RootLocator` or `RelativeSourceLocator` text;
- source adapters cannot publish application events directly;
- parser/archive components do not register as source providers.

Compile-time crate/module boundaries are preferred to convention-only tests.

## 52. Source Provider Contract Tests

Every source-provider adapter must support reusable contract tests covering applicable capabilities.

Required scenarios include:

1. provider type identity is stable;
2. valid provider configuration binds successfully;
3. invalid configuration translates to `InvalidConfiguration`;
4. root resolution returns a root-bound transient handle;
5. relative access cannot escape the resolved root;
6. root relationship comparison returns only valid `RootRelationship` values;
7. locator keys are deterministic for unchanged locations;
8. distinct simultaneously valid locations do not collide on locator key;
9. native identity is omitted when continuity cannot be guaranteed;
10. enumeration returns normalized observations with no native types;
11. observation ordering is not promised;
12. `Complete` is never returned after known required omissions;
13. cancellation cannot return `Complete` for an interrupted scope;
14. link-like entries are identifiable without traversal in MVP;
15. native errors translate to `SourceAccessError`;
16. source-read consistency follows advertised `atomic_reads` behavior.

## 53. Reconciliation Tests

Reconciliation tests must verify:

- equivalent observation permutations produce equivalent final state;
- new observations create entries;
- unchanged observations preserve identity;
- fingerprint changes update current source facts without inventing logical content identity;
- native-identity moves preserve `SourceEntryId` when unambiguous;
- ambiguous move candidates remain unmatched;
- no filename-only move preservation occurs;
- an incomplete scope never deletes unobserved prior children;
- a completed exact scope may delete unmatched unobserved direct children;
- nested failure preserves descendants under the failed nested scope;
- completed sibling scopes may still finalize during an overall partial scan;
- policy pruning removes deterministically excluded managed state without claiming storage absence;
- stale scan plans cannot perform destructive finalization;
- authoritative subtree removal also removes referencing `GameContentSource` edges atomically;
- source removal alone does not delete `GameContent`.

## 54. Scan Lifecycle Tests

Required scan tests include:

- one active scan owner per `LibraryRoot`;
- duplicate same-root admission returns the existing active scan identity rather than racing;
- different roots may proceed independently;
- one `JobRun` may own multiple `ScanRun` records;
- retry creates new run identities;
- startup preserves already-terminal child scans;
- startup converts a stale `Running` scan with accepted durable cancellation intent to `Cancelled`;
- startup converts any other stale `Running` scan to `Abandoned`;
- recovery updates root last-scan summaries without changing availability for `Cancelled` or `Abandoned`;
- recovery performs no provider I/O, new admission, retry, or resume;
- committed positive observations from a cancelled or abandoned scan remain valid;
- cancellation produces `Cancelled` when it determines termination;
- cancellation is job-scoped and never rewrites an already-terminal child `ScanRun`;
- cancellation arriving during a coherent commit/finalization checkpoint completes the in-flight mutation before the next safe checkpoint;
- a root completing before another root is cancelled keeps its `Complete` child outcome while the job terminates `Cancelled`;
- partial useful work produces `Partial` rather than `Failed`;
- root-level unavailability maps `ScanRun` to `Failed` and root last-scan status to `Unavailable`;
- nested unavailability produces `Partial` without marking the root unavailable;
- incompatible configuration revision changes suppress destructive finalization.

## 55. Discovery and Classification Tests

Tests must verify:

- discovery patterns operate on `DiscoveryPath`, not serialized locators;
- provider-declared case semantics affect pattern matching correctly;
- maximum depth is based on logical path segments;
- structural exclusion prevents entry persistence/traversal as configured;
- semantic `Ignored` remains a retained graph node;
- link-like nodes are never traversed in MVP;
- provider `ObservedEntryKind` does not report archive/playlist/disc semantics;
- application-owned `SourceEntryKind` may be refined without changing `SourceEntryId`;
- classification does not trigger network metadata calls or eager hashing;
- `ContentCandidate` does not automatically create `GameContent`;
- the Phase 001 observation-to-kind/classification mapping is exact;
- hidden/system ordinary entries remain retained under the same structural rules;
- Phase 001 resource-limit exhaustion produces an incomplete scope rather than a truncated `Complete` result;
- Phase 001 never invokes the inactive strong-content-identity move tier.

## 56. Source Read Tests

Tests must verify:

- atomic reads may produce trusted derived data directly;
- non-atomic reads require completion validation;
- `Changed` causes derived output to be discarded;
- `Indeterminate` cannot be committed as trusted immutable data;
- a provider does not silently stitch together bytes from multiple source versions;
- cancellation of a read is preserved as cancellation;
- source-read handles do not outlive their source access/runtime generation.

## 57. MVP Local-Filesystem Integration Tests

Deterministic temporary-filesystem integration tests should cover, where platform support permits:

- root resolution;
- directory enumeration;
- file observation metadata;
- locator-key stability;
- no root escape;
- file removal between enumerate and stat/open;
- file modification between observations;
- rename/move behavior with and without stable native identity;
- link-like entry observation without traversal;
- case-comparison behavior according to the effective filesystem semantics;
- cancellation during enumeration;
- source-read validation behavior;
- platform authorization restore/reacquire and stale/revoked failure behavior where the platform requires it (for example sandboxed macOS).

Tests must not require a user's actual ROM library.

Platform-specific tests may be conditional where native filesystem features differ, but the shared provider-contract suite remains mandatory.

## 58. Acceptance Criteria

SPEC-BE-011 is satisfied when:

1. Source/storage providers are architecturally separate from metadata/external-service providers.
2. `SourceProviderType` identifies provider family while `LibrarySourceId` identifies one configured source instance.
3. `LibrarySource` persists a versioned provider configuration document plus a separate monotonic instance `config_revision`.
4. Raw secrets are absent from provider configuration documents.
5. One runtime generation owns a `SourceProviderRegistry` of provider factories.
6. `LibrarySourceAccess` is bound to one configured source and one execution attempt and is never persisted.
7. Source access exposes storage primitives only and owns no reconciliation, classification, persistence, or event behavior.
8. Provider capabilities are typed and may narrow for a resolved root.
9. `RootLocator` and `RelativeSourceLocator` remain opaque to generic application code.
10. `SourceLocatorKey` provides provider-defined persistent location equality and is unique within one root.
11. Provider-native identity, locator identity, source fingerprint, and `SourceEntryId` remain distinct.
12. Provider-verifiable overlapping roots within one `LibrarySource` are rejected; unknown relationships are conservatively allowed.
13. Cross-source physical overlap detection is not attempted.
14. `resolve_root()` produces a transient `ResolvedRoot` and does not silently rewrite persisted configuration.
15. MVP root resolution rejects link-like configured roots.
16. `SourceObservation` contains normalized Argus-owned facts and no native provider objects.
17. `DiscoveryPath` is distinct from the opaque locator and is the only path projection used by generic discovery matching.
18. Providers report structural `ObservedEntryKind`; Argus owns richer persisted `SourceEntryKind`.
19. `ProviderNativeIdentity` is optional and never fabricated from weak heuristics.
20. `SourceFingerprint` is cheap change evidence and never substitutes for `ContentIdentity`.
21. Discovery policy controls retention/traversal while classification controls semantic role.
22. Link-like entries are never traversed in MVP.
23. Providers enumerate one native scope at a time; indexing owns recursion/traversal.
24. Derived containers are enumerated by transformation/parser components, not registered as source providers.
25. Enumeration ends with an explicit exact-scope outcome.
26. Only exact-scope `Complete` authorizes absence-based deletion.
27. Positive observations may commit before scope completion and remain valid after incomplete scan termination.
28. Reconciliation is independent of observation arrival order.
29. One immutable `ScanPlan` governs one `ScanRun`.
30. Stale/incompatible plans may preserve committed presence but cannot perform destructive authoritative finalization.
31. At most one active `ScanRun` owns one `LibraryRoot`.
32. `ScanRun` remains distinct from, and references, its `JobRun`.
33. `last_observed_scan_id` records positive presence only and is never a root-wide deletion marker by itself.
34. Move detection prefers stable native identity, then unique strong content identity when already available, otherwise removal plus creation.
35. Filename/timestamp/size-only move heuristics are prohibited.
36. Current deterministic discovery-policy exclusion may prune previously indexed state without claiming physical storage absence.
37. Authoritative source removal atomically removes source entries and referencing `GameContentSource` edges; when SPEC-BE-012 identity provenance exists, the same coherent application mutation invalidates affected identity proof without deleting `GameContent` directly.
38. Indexing does not directly determine `GameContent` orphan lifecycle.
39. `ContentCandidate` does not automatically create `GameContent`.
40. Source adapters translate native failures into stable `SourceAccessError` values.
41. Root availability is application-owned interpretation, not provider-owned persisted state.
42. `Running` is the sole active `ScanRun` status; `Complete`, `Partial`, `Failed`, `Cancelled`, and recovery-only `Abandoned` follow the semantic terminal rules defined here, while root last-scan summaries also represent `NeverScanned` and root-level `Unavailable`.
43. Root-level unavailability remains distinct from nested scope failure.
44. A scan uses short coherent Unit of Work mutations and never one scan-wide transaction.
45. Provider/source I/O is not held across indexing database write transactions.
46. `SourceRead` explicitly establishes atomicity or requires post-read consistency validation.
47. Trusted immutable derived data is never committed from a changed or indeterminate mutable read.
48. MVP uses one `LocalFilesystem` provider type across supported desktop platforms and Android; platform-specific mounted-storage mechanics remain provider-owned rather than becoming new product-level provider types.
49. Local-filesystem capabilities are conservative and based on effective resolved-root semantics rather than OS-name assumptions.
50. Local filesystem links/junctions/aliases are not followed for traversal.
51. Cancellation preserves already committed positive observations and never grants absence authority.
52. Startup recovery preserves committed presence, keeps already-terminal child truth, maps accepted cancellation to `Cancelled` and unexpected loss to `Abandoned`, clears stale ownership, and performs no provider I/O or automatic work.
53. Source/indexing events publish only after durable commits.
54. Architecture, provider-contract, reconciliation, scan-lifecycle, discovery/classification, read-consistency, and filesystem integration tests enforce the defined boundaries.
55. Cancellation is job-scoped, preserves already-terminal child outcomes, and treats an in-flight coherent commit as completing before the next safe checkpoint.
56. Platform-durable authorization is provider-owned opaque configuration; stale/revoked authorization yields a typed source-access failure without deleting or rewriting the configured source/root.

## 59. Prohibited Patterns

The following patterns are prohibited unless a later specification explicitly supersedes them:

- one generic provider abstraction combining source and metadata providers;
- concrete filesystem/path types in application-facing source contracts;
- parsing provider locators in generic indexing code;
- generic path concatenation to access source entries;
- using serialized locator text directly as cross-platform equality semantics;
- treating `SourceLocatorKey` as object or content identity;
- treating `SourceFingerprint` as a content hash;
- fabricating provider-native identity from filename, path, size, or timestamp;
- provider-owned recursion or reconciliation;
- source adapters creating `GameContent`;
- source adapters owning repositories or Unit of Work;
- source adapters publishing application events;
- providers reporting archives/playlists/disc images as native storage kinds;
- treating policy exclusion as provider-reported physical absence;
- deleting unobserved entries from a non-complete exact scope;
- root-wide mark-and-sweep based solely on `last_observed_scan_id`;
- first-observation-wins reconciliation;
- filename similarity move detection;
- eager content hashing as part of routine source discovery;
- one database transaction around an entire scan;
- filesystem/provider I/O held across arbitrary write transactions;
- automatic `GameContent` deletion when its final source path disappears;
- following symlinks, aliases, junctions, or equivalent link-like objects in MVP;
- silently rewriting a configured root locator during root resolution;
- silently changing scan policy/configuration mid-run;
- allowing concurrent active authoritative scans of the same `LibraryRoot`;
- silently reopening a changed source and treating the resulting composite bytes as one stable read;
- committing immutable derived facts from an unverified mutable read.

## 60. Deferred Decisions

This specification intentionally defers:

- exact Rust trait signatures and async-stream library choices;
- exact SQLite column encodings for opaque locator/fingerprint/native-identity values;
- exact provider-config JSON library and serialization implementation;
- credential-store technology;
- SMB/NAS provider implementation;
- removable-storage-specific provider behavior beyond the generic contract;
- cloud source providers;
- filesystem watching/change notifications;
- concurrent source discovery;
- distributed scan leases;
- link traversal;
- any future automatic source retry framework beyond MVP;
- provider-specific network retry policy for future remote source providers;
- automatic reconciliation/merge of pre-existing duplicate `GameContent` records;
- final orphan `GameContent` lifecycle;
- post-Phase-001 provider-generic source configuration, editing, rename, credential, and advanced root-policy workflows beyond the fixed local-folder UI owned by SPEC-FE-008;
- long-term scan-history retention policy;
- durable per-observation scan history;
- exact event coalescing thresholds;
- source-provider plugin loading.

## 61. Phase 002 Android `LocalFilesystem` Amendment

Android Phase 002 uses the existing `SourceProviderType::LocalFilesystem`. It does not introduce a persisted `AndroidDocumentTree` or other Android-only product source family.

### 61.1 Supported storage meaning

Android `LocalFilesystem` means actual locally mounted filesystem storage accessible under the mandatory platform authorization, including primary shared storage, ordinary accessible subdirectories such as Downloads, removable SD storage, and USB/OTG storage where Android exposes usable local filesystem semantics.

Cloud-backed/virtual `DocumentsProvider` trees and protected application-private areas that cannot satisfy the provider contract are unsupported for this capability. SAF/content-provider execution is a separate future capability, not a fallback engine inside this provider.

### 61.2 Root identity and removable volumes

A transient mount path alone is not sufficient durable identity for removable storage. Provider-owned persisted material must retain enough stable volume identity plus root-relative location information to re-identify the same configured root after a trustworthy remount.

The domain/application layers continue to treat `RootLocator` and all platform identity/authorization material as opaque. The same trustworthy root returning after temporary absence preserves its existing `LibraryRootId`.

### 61.3 Authorization and availability

Mandatory Android All files access is a process/platform readiness prerequisite, not per-root SAF authorization. Losing that platform authorization or unmounting a volume never proves indexed entries were deleted and must not authorize destructive reconciliation.

Unavailable media produces typed root/provider unavailability. Regrant/remount causes authoritative availability re-evaluation. Other roots remain usable when their own evidence is valid.

### 61.4 Folder browsing boundary

Provider/native infrastructure owns mounted-volume discovery facts, canonical root validation, bounded enumeration, relationships, stat/open, identity, and boundary safety. Flutter may consume a focused typed browse projection but never becomes traversal authority or constructs canonical provider locators from UI strings.

Android link-like entries remain governed by the existing no-traversal MVP rule.

## 62. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [PHASE-001 — Local Sources and Indexing](../../phases/phase-001-local-sources-and-indexing.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-006 — Minimal Domain Event Bus](spec-be-006-minimal-domain-event-bus.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-009 — Application Service Contracts](spec-be-009-application-service-contracts.md)
- [SPEC-BE-010 — Provider Gateway Architecture](spec-be-010-provider-gateway-architecture.md)
- [SPEC-BE-012 — Transformation and Hash-Scheme Contract](spec-be-012-transformation-and-hash-scheme-contract.md)
- [Backend Specifications Index](README.md)
