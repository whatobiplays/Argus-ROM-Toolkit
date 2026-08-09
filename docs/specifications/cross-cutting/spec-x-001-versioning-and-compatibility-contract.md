# Versioning and Compatibility Contract

**Document ID:** SPEC-X-001  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-09  
**Depends On:** ARCH-001, ARCH-002, PHASE-000  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative cross-cutting versioning and compatibility contract for Argus ROM Toolkit.

It establishes how Argus distinguishes product release identity from compatibility-domain versions, how supported persisted state moves forward, how incompatible state fails safely, how the Rust-to-Flutter bridge is versioned inside a matched desktop distribution, and how compatibility claims are verified.

The specification coordinates versioning requirements already established by persistence, diagnostics, startup, bridge, provider, testing, and repository conventions without replacing their subsystem-specific semantics.

The central rule is:

> **Argus has one product release version, while every durable compatibility surface owns the smallest independent version identifier needed to interpret that surface safely. Version numbers from unrelated domains are never treated as interchangeable.**

## 2. Responsibilities

This specification owns repository-wide rules for:

- Argus product release version semantics;
- build identity versus release identity;
- compatibility-domain separation;
- database support-window semantics;
- forward migration and downgrade behavior;
- minimum supported database schema policy;
- bridge compatibility-major semantics;
- matched Flutter/Rust distribution expectations;
- compatibility classification of durable contract changes;
- immutable published semantics;
- provider/configuration schema compatibility principles;
- compatibility observability and diagnostics;
- release compatibility review requirements;
- compatibility test requirements.

It defines the cross-cutting interpretation of those concerns. Subsystem specifications remain authoritative for the detailed schema, migration, DTO, error, provider, or diagnostic behavior they own.

## 3. Non-Responsibilities

This specification does not define:

- the exact future release automation or distribution service;
- a remote network API or remote-client version-negotiation protocol;
- independently deployed frontend/backend support;
- plugin compatibility or extension API policy;
- package-manager update channels;
- installer rollback mechanics;
- a general-purpose schema registry;
- migration SQL or migration implementation details;
- complete provider-specific configuration schemas;
- exact generated `flutter_rust_bridge` syntax;
- source-control branching or release-branch strategy;
- a promise to support every historical persistent format forever.

Those concerns belong to subsystem, release, packaging, or future compatibility specifications when needed.

## 4. Governing Principles

Argus follows these compatibility principles:

1. One product release has one authoritative Argus version.
2. Flutter and Rust are components of one desktop release, not independently versioned products.
3. Build identity is diagnostic provenance, not a compatibility protocol.
4. Database schema state is determined from migration history, never inferred from application SemVer.
5. Bridge compatibility state is independent from application SemVer.
6. Durable schemas receive independent version identifiers only when compatibility interpretation requires them.
7. Published semantic meaning is never silently reinterpreted.
8. Supported historical persisted state moves forward through explicit migration.
9. Routine in-place database downgrade is not supported.
10. Software that cannot fully understand newer persistent state refuses to write it.
11. Unsupported or corrupt compatibility state fails safely and non-destructively.
12. Compatibility support is explicit rather than inferred from elapsed release count.
13. Breaking changes require an explicit versioned transition or compatibility decision.
14. Compatibility claims require fixture/test evidence appropriate to the contract.
15. Compatibility complexity is introduced only for deployment models Argus actually supports.

## 5. Version Domains

Argus deliberately separates product identity from compatibility-domain identity.

Conceptually:

```text
Argus application release      0.4.0
build commit                   d74e164...
latest database migration      17
minimum supported schema       1
bridge contract major          1
error-code contract major      1
diagnostic bundle schema       1
```

The values may change independently.

No requirement exists for these numbers to match or advance together.

## 6. Product Release Version

Argus has one canonical application release version using:

```text
MAJOR.MINOR.PATCH
```

Examples:

```text
0.1.0
0.4.0
1.0.0
1.3.2
```

This value identifies the released Argus desktop product.

The authoritative release version must feed all product surfaces that require a product version, including as applicable:

- Flutter application metadata;
- Rust application/build metadata;
- diagnostics;
- packaging metadata;
- release artifacts;
- user-visible About/version information.

The repository must not require maintainers to edit unrelated independent product-version values manually and hope they remain synchronized.

The exact repository file or generation mechanism that owns the canonical value is an implementation decision. It must be deterministic, reviewable, and mechanically checked for drift.

## 7. Flutter and Rust Release Identity

Flutter and Rust ship as one Argus desktop product.

Conceptually:

```text
Argus 0.4.0
├── Flutter frontend: product release 0.4.0
└── Rust backend:     product release 0.4.0
```

A diagnostic field such as `backend_version` may identify a Rust component build where useful, but that field must not imply that arbitrary frontend and backend releases are independently supported or negotiable.

Argus does not define a support matrix such as:

```text
Flutter 1.3.x supports Rust 1.1.x through 1.8.x
```

for the desktop architecture.

## 8. Semantic Versioning Policy

Argus product releases use conventional SemVer meanings:

- **PATCH**: compatible bug fixes, maintenance, and corrections;
- **MINOR**: compatible feature additions or meaningful product capability changes;
- **MAJOR**: intentionally incompatible product-level changes.

Before `1.0.0`, Argus may evolve public product compatibility more rapidly in accordance with normal pre-1.0 SemVer expectations.

Pre-1.0 status does not authorize careless treatment of durable user state. Database migration safety, declared schema compatibility floors, published error codes, diagnostic schemas, and other explicitly versioned durable contracts still follow their owning compatibility rules.

## 9. Product Version Does Not Determine Domain Compatibility

Application SemVer does not mechanically determine database, bridge, diagnostic, error, or provider-schema compatibility.

For example:

```text
Argus 0.5.0 -> 0.6.0
latest migration 12 -> 15
bridge contract remains 1
```

is valid.

Likewise:

```text
Argus 1.4.0 -> 2.0.0
minimum supported database schema advances
bridge contract 1 -> 2
```

may be valid when those changes are explicitly designed and tested.

The following inference is prohibited:

```text
if application_version >= 0.5.0
    assume database schema >= 23
```

Database state must be read from database migration state. Bridge state must be identified by the bridge contract. Other formats use their own contract identities.

## 10. Compatibility-Domain Change Versus Product-Version Change

A compatibility-domain version change does not automatically dictate an Argus product-version bump.

For example, a bridge-major transition can remain an internal coordinated change because Flutter and Rust are distributed together.

Conversely, dropping support for a meaningful range of persisted user state may be a product-level breaking change even if the bridge contract does not change.

Release planning must consider user-visible and externally supported compatibility impact rather than applying a simplistic mapping from one domain version to product SemVer.

## 11. Build Identity

Build identity is separate from product release identity.

A build may expose diagnostic provenance such as:

- Git commit SHA;
- CI/build identifier;
- release channel;
- debug/release profile where useful;
- platform and architecture.

Example:

```text
application_version = 0.4.0
build_commit        = d74e164889bf8952...
```

Build identity answers:

> Which exact build produced or is running this software?

It does not answer:

> Which persisted or transport schema versions are compatible?

Compatibility logic must not branch on Git SHA or opaque build identifiers unless a future explicitly versioned recovery tool requires exact-build provenance.

## 12. Database Schema Versioning

Database compatibility is governed by the migration system in SPEC-BE-002.

The authoritative database schema state is the validated `schema_migrations` history.

Migration numbers are monotonically increasing and independently meaningful from the application release version.

Example:

```text
Argus application version  0.4.0
latest database migration  17
```

There is no requirement for a second manually synchronized database-version integer.

`PRAGMA user_version` remains non-authoritative according to SPEC-BE-002.

## 13. Migration Immutability

Released migrations are immutable compatibility evidence.

After release, Argus must not:

- edit an applied migration;
- reorder released migrations;
- reuse a released migration version;
- silently replace migration contents;
- bypass checksum validation;
- regenerate historical state so it resembles current schema creation.

Corrections are new forward migrations.

Historical fixture behavior follows SPEC-BE-002 and CONV-TEST-001.

## 14. Database Compatibility Floor

Argus uses an **explicit compatibility floor** rather than a release-count window.

Conceptually:

```text
minimum_supported_schema = N
```

The current application supports every released historical schema state that:

1. is at or above the declared minimum supported schema;
2. has valid recognized migration history;
3. can be migrated through the current released migration chain.

There is no rule such as:

```text
support only the previous 5 releases
```

because users of a desktop application may skip arbitrary numbers of application releases.

Compatibility depends on persisted schema state, not elapsed release count.

## 15. Initial Compatibility Floor

During the initial Phase 000 implementation, the minimum supported schema is the first released Argus schema once that schema is actually released.

Before any public/released historical database exists, the repository may treat the initial schema as the sole supported state without fabricating fake legacy versions.

When the first released historical fixture exists, it becomes durable compatibility evidence under CONV-TEST-001.

## 16. Raising the Compatibility Floor

Raising the minimum supported schema is exceptional.

Ordinary feature and patch releases should preserve the existing floor unless maintaining the old state has become disproportionate or technically unsafe.

Raising the floor requires:

- an explicit compatibility decision in the relevant specification/release work;
- identification of the old and new floors;
- release documentation describing the unsupported historical range when user-relevant;
- deterministic handling for databases below the new floor;
- a safe recovery or staged-upgrade path where practical;
- updated historical-fixture expectations;
- tests proving rejection below the floor and successful migration at the floor;
- no silent database recreation.

A product major release is the natural time for a compatibility-floor break when one is justified, but incrementing the product major does not by itself authorize destructive behavior.

## 17. Forward Database Upgrade

Argus persistence compatibility is forward-migration oriented.

For a recognized supported older schema:

```text
recognized supported historical schema
        ↓
validate migration history/checksums
        ↓
apply all pending forward migrations
        ↓
current schema
        ↓
Ready
```

For an already-current schema:

```text
current schema
    ↓
validate
    ↓
Ready
```

A user may skip multiple Argus releases as long as the database schema remains inside the current supported compatibility range and the complete migration chain is present.

## 18. Database Downgrade

Routine in-place database downgrade is not supported.

Argus does not maintain reverse migrations as a normal product capability.

If an older Argus binary encounters migration history or schema state newer than it understands, it must not attempt to downgrade that database in place.

It must not:

- delete unknown columns/tables;
- lower migration-history versions;
- run reverse SQL opportunistically;
- ignore unknown applied migrations;
- infer that a newer schema is probably compatible;
- recreate the database silently;
- write through a partially understood schema.

Downgrade is a recovery problem, not a reverse-migration feature.

## 19. Newer or Unknown Database State

When current software encounters database state it cannot safely interpret, the classification is conceptually:

```text
recognized and migratable
→ migrate

recognized and current
→ open

recognized but below compatibility floor
→ reject safely

newer/unknown migration history
→ reject safely

modified/corrupt/inconsistent history
→ reject safely
```

Detailed persistence errors remain owned by SPEC-BE-002 and SPEC-BE-003.

Startup projection uses the existing startup classifications from SPEC-BE-007, including `IncompatibleSchema` where applicable.

## 20. Non-Destructive Compatibility Failure

Compatibility failure is non-destructive by default.

When Argus cannot safely interpret a persistent format, it refuses to mutate the format rather than attempting speculative repair through data loss.

This principle applies to SQLite and to future durable formats such as:

- persisted provider configuration;
- import/export packages;
- durable cache/index formats when they contain authoritative or expensive state;
- user-visible exported data formats;
- other persistent cross-release contracts.

A subsystem may define an explicitly disposable cache format that can be rebuilt safely. Such a format must be documented as disposable and must not be confused with authoritative user state.

## 21. Backup and Recovery

A pre-migration backup may reduce upgrade risk but does not replace compatibility correctness.

A backup does not replace:

- migration tests;
- checksum validation;
- supported-schema fixtures;
- transactional migration behavior;
- compatibility-floor checks;
- failure classification.

Restoring a compatible backup may be part of a future downgrade/recovery workflow. That does not make the already-migrated newer database compatible with an older application.

## 22. Bridge Contract Version

The Rust-to-Flutter bridge has an independent compatibility-major identifier.

Phase 000 begins conceptually with:

```text
BRIDGE_CONTRACT_MAJOR = 1
```

The bridge uses an integer major rather than another product-style `MAJOR.MINOR.PATCH` version because its purpose is to distinguish incompatible semantic contract generations within a matched application distribution.

Compatible additive evolution does not require an independently meaningful bridge minor or patch number.

## 23. Bridge Semantically Append-Only Evolution

SPEC-BE-008 remains authoritative for bridge DTO semantics.

Within one bridge contract major:

- existing published field meanings remain immutable;
- units remain immutable;
- identity semantics remain immutable;
- nullability semantics remain immutable;
- lifecycle interpretation remains immutable;
- additive fields are preferred when compatible;
- additive DTOs or operations are preferred when new concepts are required.

If semantics must change incompatibly, use one of:

- a new field;
- a new DTO;
- a new operation;
- a new bridge contract major.

Existing identifiers must not be reused with incompatible meaning.

## 24. Closed Bridge Variants

Generated closed/sealed enum or event hierarchies may require a coordinated generated-client update when a new semantic variant is introduced.

Such a tooling limitation does not justify reinterpreting an existing variant.

Because Flutter and Rust are built and shipped together, a coordinated source update is the expected mechanism.

If a new variant is structurally breaking to the generated contract, the bridge-major policy applies according to the actual compatibility impact.

## 25. Matched Flutter/Rust Distribution

The supported desktop deployment model is:

```text
Flutter from Argus build X
        ↕
Rust from Argus build X
```

Argus does not support arbitrary combinations such as:

```text
Flutter from Argus 1.3.0
        ↕
Rust from Argus 1.7.0
```

as an independent deployment model.

Therefore the bridge contract version exists to identify and verify the semantic boundary, not to create a multi-version network-style protocol.

## 26. No Bridge Runtime Negotiation

Phase 000 does not implement bridge-version negotiation such as:

```text
frontend supports bridge majors 1..3
backend supports bridge majors 2..4
negotiate bridge major 3
```

There is no fallback bridge implementation chosen at runtime.

A matched Argus build expects one bridge contract major.

If later architecture introduces independently deployed clients, plugins, remote processes, or a public network API, those deployment models require a new compatibility specification or explicit revision of this one.

## 27. Bridge Compatibility Enforcement

Bridge compatibility uses the strongest practical enforcement available.

Preferred order:

```text
generated/compile-time consistency
        ↓
contract fixture/static verification
        ↓
runtime bridge-major assertion where useful
        ↓
startup failure on mismatch
```

Where both runtime sides expose the bridge major, they must agree before the application becomes Ready.

A mismatch is treated as a packaging/build/integration defect, not as a request to negotiate another bridge implementation.

Failure maps through the existing bridge/startup error contracts in SPEC-BE-003, SPEC-BE-007, and SPEC-BE-008.

## 28. Bridge Major Transition

A breaking bridge transition is coordinated in one repository change/release line.

Conceptually:

```text
bridge major 1
    ↓
breaking semantic contract change
    ↓
bridge major 2
```

The corresponding Flutter and Rust changes land together.

The desktop application is not required to retain active implementations such as:

```text
BridgeV1
BridgeV2
BridgeV3
```

merely because historical releases existed.

The bridge major exists to:

- identify the contract generation;
- detect incompatible drift;
- make compatibility fixtures meaningful;
- communicate deliberate breaking transitions;
- support diagnostics.

It is not a commitment to runtime multi-version serving.

## 29. Other Independently Versioned Schemas

Other durable formats retain their own version domains when their owning specifications require them.

Existing examples include:

- published application error-code contract major from SPEC-BE-003;
- diagnostic bundle schema major from SPEC-BE-003;
- database migration history from SPEC-BE-002;
- bridge contract major from this specification and SPEC-BE-008.

Future examples may include:

- provider configuration schema;
- export/import package schema;
- plugin manifest schema if plugins are introduced;
- user-facing portable configuration formats.

Do not invent version numbers for ephemeral internal Rust/Dart structs merely because they are serialized temporarily inside one process.

## 30. Error-Code Compatibility

SPEC-BE-003 owns the published `ARGUS.V<major>.<CATEGORY>.<NAME>` error-code contract.

This specification establishes the cross-cutting rule that published error-code meaning is immutable within its compatibility major.

Do not:

- reuse an existing error code for a different condition;
- change its semantic category while retaining the same published identity;
- use application SemVer as a substitute for the error-code major.

A materially incompatible published error vocabulary requires the versioned transition defined by its owning error specification.

## 31. Diagnostic Bundle Compatibility

SPEC-BE-003 owns diagnostic bundle schema semantics.

`bundle_schema_version` remains independently versioned from:

- Argus application SemVer;
- database migration state;
- bridge contract major;
- error-code contract major.

Additive compatible diagnostic fields may remain within the same diagnostic major. Removing fields or changing their semantic meaning requires the transition defined by the diagnostic bundle contract.

## 32. Provider Configuration Compatibility

Persisted provider/source-provider configuration must carry enough schema identity to be interpreted safely once incompatible representations exist.

The exact representation is owned by the applicable provider specification.

Cross-cutting rules:

1. Do not infer provider configuration shape solely from Argus application SemVer.
2. Additive compatible configuration changes need not create unnecessary major versions.
3. Incompatible configuration changes require explicit migration, a new schema generation, or deterministic rejection.
4. Configuration migration must preserve provider identity and user intent where possible.
5. Unknown/newer required configuration semantics must not be silently ignored when doing so would change provider behavior.
6. Provider-specific compatibility logic remains inside the provider/configuration boundary rather than leaking into general application code.

SPEC-BE-011 remains authoritative for source-provider configuration validation and compatibility ownership.

## 33. Compatibility Classification

Changes to durable contracts are classified as one of:

```text
additive compatible
semantic compatible
migration-required compatible
breaking
```

### 33.1 Additive compatible

Adds data or capability without changing existing published meaning and while existing supported consumers can safely tolerate the addition.

Examples:

- an optional diagnostic field;
- an additive bridge field that generated consumers safely tolerate;
- a new independent operation that does not reinterpret old behavior.

### 33.2 Semantic compatible

Changes implementation while preserving the externally promised semantics of the compatibility domain.

Examples:

- internal serialization refactoring that produces the same durable representation;
- performance improvements with identical persistence/contract behavior;
- internal mapper replacement preserving the same DTO contract.

### 33.3 Migration-required compatible

Changes durable representation but provides a supported deterministic forward transition.

Examples:

- adding a required SQLite column through a released migration;
- changing a persisted provider configuration through an explicit configuration migration.

### 33.4 Breaking

Requires an existing supported consumer or persisted state to change in a way not covered by the existing compatibility contract.

Examples:

- changing bridge `progress` units from `0..100` to `0.0..1.0`;
- reusing an error code for a different semantic condition;
- removing database schemas below a newly raised compatibility floor;
- removing/renaming a required durable field without a supported migration;
- changing stable identifier interpretation.

Private implementation changes with no durable contract effect are not compatibility changes.

## 34. Published Semantic Immutability

Once a durable contract is published, its existing semantic meaning must not change silently.

This applies to:

- bridge DTO fields;
- published error codes;
- diagnostic schema fields;
- migration history;
- persisted provider configuration;
- stable identifiers;
- durable enum values;
- import/export fields;
- future public plugin/network contracts.

When meaning must change, prefer an explicit new identity:

```text
new field
new variant
new operation
new schema version
new contract major
new forward migration
```

rather than reinterpretation.

## 35. Compatibility and Stable Identifiers

A stable identifier remains opaque unless its owning contract explicitly defines structure.

Compatibility-sensitive identifiers must not silently switch meaning across releases.

Examples include:

- domain IDs exposed through bridge DTOs;
- provider-type identities;
- error-code identities;
- schema/migration identifiers;
- event/operation identities when published durably.

Database-local row IDs, memory addresses, and transient implementation handles are not compatibility contracts unless explicitly elevated by another specification.

## 36. Unknown Additive Data

Consumers of explicitly extensible durable schemas should tolerate unknown additive fields where their owning representation and tooling permit safe tolerance.

Unknown additive data must not be tolerated blindly when:

- the field changes required semantics;
- the representation is closed/sealed and cannot safely decode it;
- ignoring it would change security/privacy behavior;
- ignoring it would lose authoritative user intent;
- the format explicitly requires exact schema matching.

The owning specification decides whether a format is open/additive or exact/closed.

## 37. Compatibility Failure Classification

Compatibility failures must be diagnosable without creating one giant generic error.

At minimum, subsystem contracts should preserve enough distinction between conditions such as:

- below supported compatibility floor;
- newer/unknown schema;
- corrupt/inconsistent migration history;
- checksum mismatch;
- bridge contract mismatch;
- unsupported configuration schema;
- invalid configuration contents;
- migration execution failure.

The exact error taxonomy remains owned by SPEC-BE-003 and subsystem error contracts.

## 38. Startup Behavior

Compatibility checks required for runtime correctness occur before readiness.

Relevant startup ordering remains owned by SPEC-BE-007.

Examples:

- database compatibility is verified in `PersistenceInitialization` before normal database work;
- required bridge compatibility is verified before the bridge/application runtime reports Ready;
- mandatory persisted configuration compatibility is verified before the dependent service becomes ready.

Argus must not enter Ready state and only later discover that mandatory authoritative state is incompatible.

## 39. Recovery Behavior

Recovery actions must reflect what Argus can do safely.

A compatibility failure may offer actions such as:

- retry after a transient environmental condition is corrected;
- export diagnostics;
- choose/restore an appropriate backup through a future explicit workflow;
- install an intermediate/newer supported Argus version when required;
- reset only an explicitly disposable cache/configuration when the owning contract permits it.

Recovery must not imply that authoritative user data can be safely deleted merely because the current build cannot read it.

## 40. Security and Privacy

Compatibility metadata must not create a privacy leak.

Version information may be included in diagnostics when useful, but compatibility reporting must follow SPEC-BE-003 sanitization requirements.

Do not include:

- provider credentials;
- private account payloads;
- ROM/BIOS content;
- arbitrary user paths;
- raw user database contents;

merely to prove a version mismatch.

Compatibility failures should report bounded identifiers and version/schema state sufficient for diagnosis.

## 41. Compatibility Observability

Where applicable, diagnostics should expose bounded compatibility state such as:

```text
application_version
build identity
bridge_contract_major
current database migration/schema state
minimum supported database schema
diagnostic bundle schema
relevant provider/config schema versions
```

Only values that help diagnose compatibility belong in these outputs.

Subsystems should avoid duplicating the same version under multiple ambiguous field names.

## 42. Application and Backend Version Diagnostics

If diagnostics expose both `application_version` and `backend_version`, their semantics must be documented.

For the matched desktop distribution:

- `application_version` identifies the Argus product release;
- `backend_version` may identify Rust component/build provenance;
- neither field establishes independent frontend/backend compatibility support.

A backend build provenance field should normally match the same product release source lineage as the frontend package.

## 43. Release Compatibility Review

A release that changes a durable compatibility surface must answer:

1. Which compatibility domain changed?
2. Is the change additive compatible, semantic compatible, migration-required compatible, or breaking?
3. Does the domain version need to advance?
4. Which historical states remain supported?
5. What happens when unsupported state is encountered?
6. Which fixtures/tests prove the compatibility claim?
7. Is user-facing release documentation required?
8. Does the product SemVer impact differ from the domain-version impact?

This is a repository review requirement, not a committee process.

## 44. Breaking Compatibility Review

A breaking compatibility change requires explicit treatment in the owning design/specification.

The review must identify:

- the old supported contract/state;
- the new contract/state;
- why additive/migratable evolution is insufficient;
- version/domain changes required;
- migration/recovery behavior;
- user-data risk;
- rollback/downgrade implications;
- test fixtures to preserve;
- documentation/release-note impact.

Breaking changes must not be smuggled through under an unrelated refactor or dependency update.

## 45. Product Major Releases

A product-major release is an appropriate boundary for user-visible breaking compatibility when one is justified.

It is not an automatic permission to:

- delete unsupported databases;
- discard unknown provider configuration;
- ignore incompatible exported data;
- remove recovery paths without review.

Domain compatibility remains explicit even when the product major changes.

## 46. Pre-1.0 Releases

Before Argus 1.0, product/API stability may evolve more quickly.

Nevertheless, the following remain deliberate contracts once released:

- released database migrations;
- supported historical schema fixtures;
- published error-code identities;
- diagnostic bundle schema generations;
- released bridge contract semantics inside a distribution;
- other explicitly documented durable formats.

Pre-1.0 releases may make more frequent breaking decisions, but those decisions remain explicit and tested.

## 47. Exact-Version Versus Compatible-Version Requirements

Some relationships require exact build consistency; others require compatible schema interpretation.

Examples:

| Relationship | Requirement |
|---|---|
| Flutter generated bridge code ↔ Rust bridge code in one build | Matched generated/build contract |
| Current app ↔ supported historical SQLite schema | Forward-compatible via migration |
| Current app ↔ newer unknown SQLite schema | Reject safely |
| Diagnostic consumer ↔ additive fields in same diagnostic major | Compatible when owning schema allows |
| Current provider adapter ↔ older supported config schema | Explicit compatibility/migration |
| Product version ↔ database migration number | No direct equality/inference |

The repository must not collapse these distinct relationships into one generic version comparison.

## 48. No General Runtime Version Negotiator

Phase 000 must not introduce a generic compatibility negotiation service.

There is no requirement for a central runtime component that negotiates every schema/version domain.

Each owning boundary validates the version state it understands:

- migration runner validates database history;
- bridge composition validates bridge contract;
- diagnostic tooling writes/reads its schema;
- provider configuration boundary validates provider config schema.

Cross-cutting policy is shared; validation remains close to the owning data contract.

## 49. Version Constants and Ownership

Compatibility constants should live with the contract they identify.

Examples conceptually:

```text
application release version      -> repository/build version authority
bridge contract major            -> bridge-owned contract module
minimum supported DB schema      -> persistence/migration compatibility boundary
diagnostic schema major          -> diagnostics bundle module
provider config schema           -> provider/configuration owner
```

Do not create one global `versions.rs` or Dart equivalent merely to collect unrelated constants unless future usage demonstrates a genuine shared ownership need.

## 50. Serialization of Version Values

Version values must use representations appropriate to their domain.

Recommended forms:

- application release: SemVer-compatible string;
- migration identifier/schema floor: integer migration number or explicitly defined schema identifier;
- compatibility major: non-negative integer;
- build commit: bounded opaque string/hash;
- provider schema: provider-owned integer/string as documented.

Consumers must parse these according to the owning schema rather than assuming every version is SemVer.

## 51. Database Compatibility Tests

Database compatibility tests must cover at least:

- fresh database to current schema;
- every supported historical schema fixture to current schema;
- schema exactly at the compatibility floor to current schema;
- recognized schema below the compatibility floor -> safe rejection;
- newer/unknown migration history -> safe rejection;
- modified released migration/checksum -> safe rejection;
- invalid migration history -> safe rejection;
- failure during migration -> previous committed state remains authoritative;
- reopen after successful migration;
- representative data preservation across supported migrations.

Historical schema fixtures follow CONV-TEST-001 and remain immutable after release unless explicitly corrected with compatibility rationale.

## 52. Bridge Compatibility Tests

Bridge compatibility tests must cover at least:

- Rust and Dart/generated consumers agree on the bridge contract major;
- generated contract drift is detected;
- field removal is detected;
- field renaming is detected;
- incompatible field type/representation changes are detected;
- enum/event representation changes are detected;
- semantic unit changes are structurally detected where practical;
- error projection drift is detected;
- mismatched bridge major prevents readiness where runtime assertion exists;
- no runtime negotiation/fallback path is introduced accidentally.

SPEC-BE-008 remains authoritative for the detailed bridge contract test catalog.

## 53. Product Version Consistency Tests

Repository/build verification must ensure:

- one canonical Argus release version feeds all required release surfaces;
- Flutter and Rust product metadata cannot silently disagree;
- generated/build metadata can be reproduced from the canonical source;
- diagnostics report the intended application version;
- build identity is distinguishable from release identity;
- compatibility decisions do not derive database/bridge state from application SemVer.

The exact check is implemented through repository tooling owned by CONV-REPO-001.

## 54. Durable Schema Contract Tests

Every independently versioned durable schema must have tests appropriate to its risk.

Examples:

- diagnostic bundle fixture/manifest tests;
- error-code catalog contract tests;
- provider configuration migration/validation fixtures;
- import/export schema fixtures when introduced;
- bridge contract snapshots/fixtures;
- historical database fixtures.

CONV-TEST-001 owns fixture and deterministic-test conventions.

## 55. Compatibility Regression Policy

A compatibility defect receives a regression at the lowest faithful boundary.

Examples:

| Defect | Preferred regression |
|---|---|
| old DB no longer migrates | historical migration fixture test |
| new app writes DB old build partially corrupts | newer-schema rejection test |
| bridge field silently changes units | bridge contract/semantic fixture test |
| diagnostic field reused with new meaning | diagnostic schema contract test |
| provider config misread after schema change | provider config migration/validation test |

Broader E2E coverage is added only when a narrower test cannot prove the cross-boundary failure.

## 56. Compatibility Fixtures

Compatibility fixtures are durable evidence rather than convenience data.

They must follow CONV-TEST-001 rules for:

- ownership;
- provenance;
- sanitization;
- immutability where historical;
- explicit semantic review when updated;
- reproducibility.

A fixture must not be regenerated blindly merely to make a changed implementation pass.

## 57. Generated Bridge Source

Generated bridge source follows CONV-REPO-001.

When the bridge contract changes:

- regenerate through the canonical repository command;
- review generated drift semantically;
- commit generated source when required by repository policy;
- verify freshness;
- ensure the generated Dart/Rust sides correspond to the same bridge contract source.

Generated-source freshness is necessary but not sufficient evidence of semantic compatibility.

## 58. Documentation Requirements

Compatibility changes must update the owning durable documentation in the same reviewed change when documented truth changes.

Examples:

- bridge major change -> SPEC-X-001/SPEC-BE-008 as applicable;
- compatibility-floor change -> SPEC-X-001 and persistence/release documentation;
- diagnostic schema major change -> SPEC-BE-003;
- provider configuration compatibility change -> owning provider/source-provider specification;
- product release compatibility promise -> release documentation.

CONV-DOC-001 governs documentation synchronization and Codex result reporting.

## 59. Failure Diagnostics

Compatibility failures should include bounded machine-readable context sufficient to diagnose the state.

Examples include:

- observed migration version/history classification;
- minimum supported migration/schema floor;
- expected bridge major;
- observed bridge major;
- configuration schema identity;
- published application error code;
- application/build version provenance.

Diagnostics must not dump raw migration SQL, provider secrets, user databases, or arbitrary private configuration.

## 60. Performance Requirements

Compatibility validation occurs at bounded lifecycle points and should not add material steady-state overhead.

Examples:

- database compatibility validation during persistence startup;
- bridge contract validation during bridge/runtime composition;
- provider configuration validation when loading/binding provider configuration;
- diagnostic schema version assignment during export.

Do not add per-call bridge version negotiation or repeated database-version polling to ordinary application operations.

## 61. Concurrency and Cancellation

Compatibility checks occur before dependent mutable work begins where possible.

Database compatibility/migration follows SPEC-BE-002 transaction/startup ownership and cancellation rules.

Bridge compatibility validation occurs before readiness and does not require long-running background negotiation.

Configuration migrations must not race with normal consumers of the configuration they are migrating.

No compatibility mechanism may bypass owning transaction or runtime lifecycle guarantees.

## 62. Out of Scope

This specification intentionally does not define:

- automatic application updates;
- release signing;
- installer package version syntax;
- app-store version codes;
- remote-client protocol negotiation;
- plugin ABI/API compatibility;
- long-term network API stability;
- cross-major downgrade automation;
- reverse database migrations;
- support lifetime measured in years/releases;
- a compatibility matrix for independently deployed Flutter/Rust versions;
- a universal schema-conversion framework.

These may be specified later when the architecture actually requires them.

## 63. Prohibited Patterns

The following patterns are prohibited unless a future approved specification explicitly changes the contract:

- inferring database schema from application SemVer;
- inferring provider configuration schema from application SemVer alone;
- treating build SHA as a compatibility version;
- maintaining independently editable Flutter/Rust product versions that can silently drift;
- modifying or reusing released migration versions;
- silently recreating an incompatible authoritative database;
- reverse-migrating databases as an implicit downgrade mechanism;
- allowing older software to write a newer schema it does not fully understand;
- runtime negotiation across multiple bridge implementations in Phase 000;
- reusing published fields/error codes/enum variants with incompatible meaning;
- auto-accepting changed compatibility fixtures without semantic review;
- raising the database compatibility floor without explicit design/recovery/test updates;
- treating a product-major release as blanket permission for destructive compatibility breaks;
- assigning versions to ephemeral internal structs without a compatibility consumer;
- centralizing unrelated version constants into a global catch-all without ownership need.

## 64. Phase 000 Minimum Contract

Phase 000 must establish at least:

- one canonical Argus application release version source;
- matched Flutter/Rust release metadata derived from that product identity;
- build provenance sufficient for diagnostics;
- migration-history-based database schema identification;
- an explicit initial minimum supported database schema policy;
- forward-only migration semantics;
- safe rejection of newer/unknown/incompatible schema history;
- bridge contract major `1` or equivalent first-major representation;
- no bridge runtime negotiation;
- bridge-major/generated-contract consistency checks;
- compatibility diagnostics sufficient to distinguish application/build/schema/bridge identities;
- deterministic tests for the Phase 000 compatibility cases.

No remote-client or plugin compatibility system is required.

## 65. Acceptance Criteria

SPEC-X-001 is satisfied by the applicable Phase 000 implementation when:

1. Argus has one canonical `MAJOR.MINOR.PATCH` product release version.
2. Flutter and Rust release metadata derive from the same product release identity.
3. Build identity is separate from product compatibility identity.
4. Database schema state is determined from validated migration history rather than product SemVer.
5. Migration numbers remain independent from the product version.
6. Released migrations are immutable and checksum-validated according to SPEC-BE-002.
7. The database compatibility window is represented by an explicit minimum supported schema rather than a last-N-releases rule.
8. Every released schema at or above the compatibility floor is supported through the current migration chain unless an explicit later compatibility decision changes the floor.
9. Raising the compatibility floor requires explicit design, recovery, documentation, fixture, and test updates.
10. Supported historical databases migrate forward deterministically to current schema.
11. Routine in-place database downgrade/reverse migration is not implemented.
12. Newer/unknown database state is rejected without mutation.
13. Below-floor database state is rejected without silent recreation.
14. Corrupt, modified, or inconsistent migration history is rejected according to persistence error contracts.
15. Compatibility failure is non-destructive by default.
16. The bridge has an independently identified compatibility major.
17. Phase 000 uses bridge contract major `1` or the equivalent initial major representation.
18. Bridge field semantics remain immutable within a supported contract major.
19. Incompatible bridge semantics use a new field/DTO/operation or new bridge major rather than reinterpretation.
20. Flutter and Rust are treated as one matched desktop distribution.
21. No arbitrary independently deployed Flutter/Rust compatibility matrix is promised.
22. No runtime bridge-version negotiation/fallback implementation exists in Phase 000.
23. Bridge-major mismatch prevents readiness where runtime assertion is used.
24. Product SemVer does not act as a proxy for bridge, database, diagnostic, error, or provider schema versions.
25. Published error-code compatibility remains independently versioned according to SPEC-BE-003.
26. Diagnostic bundle compatibility remains independently versioned according to SPEC-BE-003.
27. Provider configuration compatibility is validated by the provider/configuration owner rather than inferred from product SemVer.
28. Durable compatibility changes are classified as additive compatible, semantic compatible, migration-required compatible, or breaking.
29. Published durable semantic meaning is not silently reinterpreted.
30. Unsupported compatibility state fails with bounded diagnosable context and without leaking secrets/private user data.
31. Compatibility checks required for mandatory state complete before application readiness.
32. Database tests cover fresh, every supported historical, floor, below-floor, newer/unknown, checksum mismatch, invalid history, migration failure, reopen, and representative data-preservation cases.
33. Bridge tests detect major mismatch and incompatible generated/DTO/error/event contract drift.
34. Repository verification detects drift between the canonical Argus product version and required Flutter/Rust release metadata.
35. Other independently versioned durable schemas use contract fixtures/tests appropriate to their owning specification.
36. Compatibility fixture changes receive semantic review and are not blindly regenerated.
37. Compatibility diagnostics distinguish product release identity, build provenance, and relevant schema/contract versions where applicable.
38. No compatibility mechanism adds per-operation version negotiation or other unjustified steady-state overhead.
39. Release changes to durable compatibility surfaces answer the compatibility review questions in this specification.
40. Documentation changes accompany material compatibility-contract changes according to CONV-DOC-001.

## 66. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](../backend/spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-007 — Startup Coordination and Recovery Contract](../backend/spec-be-007-startup-coordination-and-recovery-contract.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](../backend/spec-be-011-source-provider-and-indexing-contract.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [CONV-DOC-001 — Documentation and Codex Result Conventions](../../conventions/conv-doc-001-documentation-and-codex-result-conventions.md)
- [Cross-Cutting Specifications Index](README.md)
- [Subsystem Specification Template](../../templates/subsystem-specification.md)
