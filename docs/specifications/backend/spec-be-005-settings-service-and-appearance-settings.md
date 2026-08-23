# Settings Service and Appearance Settings Specification

**Document ID:** SPEC-BE-005  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-23  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, PHASE-002, PHASE-003, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-X-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This specification defines the authoritative backend contract for typed application settings domains and the Phase 000 `AppearanceSettings` capability.

It establishes the first concrete query and immediate-command workflow built on the persistence, error, observability, and runtime foundations defined by SPEC-BE-002 through SPEC-BE-004. The design intentionally avoids a generic key/value settings system. Each settings domain is independently typed, validated, persisted, queried, updated, migrated, and recovered.

Phase 000 implements only appearance theme mode, but the architectural conventions in this specification are normative for future settings domains unless a later specification explicitly revises them.

## 2. Scope

This specification covers:

- typed settings-domain ownership
- `AppearanceSettings` and `ThemeMode`
- singleton settings aggregate semantics
- persistence-only settings metadata
- materialized default records
- `AppearanceSettingsRepository`
- `AppearanceSettingsQueries`
- thin `AppearanceSettingsService` over the focused handlers
- `GetAppearanceSettingsQuery`
- `UpdateAppearanceSettingsCommand`
- validation and Unit of Work behavior
- last-successful-commit concurrency semantics
- `AppearanceSettingsChanged`
- startup integrity validation
- explicit targeted settings reset
- error mapping and recovery semantics
- observability and diagnostic requirements
- Phase 000 testing and acceptance criteria

## 3. Non-Responsibilities

This specification does not define:

- Flutter widgets or controller state
- bridge DTO serialization layout
- Riverpod or Freezed models
- the generic event bus implementation
- runtime lifecycle mechanics already owned by SPEC-BE-004
- SQLite connection or transaction implementation already owned by SPEC-BE-002
- restart-required settings behavior
- settings import/export
- cloud synchronization
- multi-user or multi-client concurrency
- credential storage
- provider-specific configuration domains
- a generic settings registry
- a generic key/value settings API

Those concerns belong to later frontend, bridge, event, credential, provider, or application specifications.

## 4. Architectural Principles

1. Settings are modeled as strongly typed domain-specific aggregates.
2. Argus does not expose or depend on a generic application-level key/value settings model.
3. Each settings domain owns its schema, defaults, validation, repository contract, queries, commands, migrations, and recovery behavior.
4. UI composition does not imply backend aggregate composition.
5. Singleton settings aggregates do not expose artificial application identities.
6. Persistence metadata remains behind the repository/query boundary.
7. Required singleton settings records are materialized during database initialization or migration.
8. Missing or invalid required settings records are integrity failures, not normal defaulting paths.
9. Queries provide authoritative settings state.
10. Commands express update intent and do not return authoritative read state.
11. Events announce committed change and do not transport the authoritative aggregate.
12. Settings updates are atomic and publish events only after commit.
13. Phase 000 uses last-successful-commit semantics rather than optimistic concurrency.
14. Invalid persisted settings prevent the runtime from reaching `Ready`.
15. Targeted settings reset is explicit user recovery and never automatic repair.
16. Application contracts model settings intent and domain state, not storage technology or persistence mechanics.

## 5. Settings Domain Ownership

Settings domains are independent aggregates.

Conceptual future domains include:

```text
AppearanceSettings
LibrarySettings
ProcessingSettings
MetadataSettings
ArtworkSettings
DiagnosticsSettings
```

Each domain may evolve independently and may have different defaults, validation, migrations, restart behavior, and recovery requirements.

Argus must not introduce one global aggregate such as:

```text
Settings
├── Appearance
├── Library
├── Metadata
├── Artwork
└── Diagnostics
```

unless a future architecture revision demonstrates a real cross-domain consistency requirement.

The application layer may compose several settings queries for a unified Settings UI without combining their persistence or aggregate ownership.

## 6. No Generic Key/Value Settings Model

The following application-level model is prohibited:

```text
Setting
- key
- value
- value_type
```

Likewise, application contracts such as these are prohibited:

```text
get_setting("appearance.theme_mode")
set_setting("appearance.theme_mode", "dark")
```

Reasons:

- string keys weaken compile-time guarantees
- values require runtime parsing
- migration semantics become implicit
- ownership becomes unclear
- validation is fragmented
- typo-prone identifiers become accidental APIs
- database constraints become less expressive

Infrastructure may use implementation-local representations where useful, but application and domain contracts remain typed.

## 7. `AppearanceSettings` Domain Model

The complete application-level aggregate is:

```text
AppearanceSettings
- theme_mode
```

No application-visible identifier exists.

No persistence metadata exists on the domain model.

Conceptually:

```rust
pub struct AppearanceSettings {
    pub theme_mode: ThemeMode,
}
```

Exact Rust syntax, derives, and module layout are implementation decisions governed by SPEC-BE-001 and coding conventions.

`AppearanceSettings` is immutable from the perspective of consumers. Updates construct or submit a complete desired value rather than mutating shared state in place.

## 8. `ThemeMode`

Allowed values are exactly:

```text
System
Light
Dark
```

Semantics:

- **System:** Follow the host platform's active light/dark appearance behavior as interpreted by Flutter.
- **Light:** Request the application's light theme.
- **Dark:** Request the application's dark theme.

Rust owns validation of the stable setting value.

No additional values, aliases, integer meanings, or free-form strings are accepted by application logic.

Bridge serialization may use a stable bridge representation defined by SPEC-BE-008, but bridge representation does not redefine domain semantics.

## 9. Persistence Metadata Boundary

The persistence representation may contain metadata required for schema evolution and diagnostics, such as:

```text
internal singleton key
aggregate schema revision
updated timestamp
migration metadata
```

These are not fields on `AppearanceSettings`.

Rules:

1. Persistence metadata never crosses the repository or query boundary as part of the domain model.
2. Flutter does not supply persistence metadata when updating settings.
3. Application handlers do not branch on SQLite row identifiers or persistence schema revisions.
4. Repository mapping is responsible for translating persisted representation into the current valid domain model.
5. Persistence evolution must not force application contract changes when domain semantics are unchanged.

## 10. Singleton Aggregate Semantics

There is exactly one `AppearanceSettings` aggregate per Argus application database.

The application does not model an `AppearanceSettingsId`.

Write repository contracts therefore use singleton-oriented operations such as:

```text
get()
save(settings)
```

The independent query interface exposes its own focused `get()` operation.

The application does not use an identity-oriented singleton lookup such as:

```text
get(AppearanceSettingsId)
```

Persistence may use a stable internal singleton key or equivalent constraint. That key is an infrastructure detail and must not become an application or bridge identifier.

The identity-first observability rule from SPEC-BE-003 does not require inventing an identifier for a singleton configuration aggregate that has no domain identity.

## 11. Materialized Defaults

The canonical Phase 000 default is:

```text
AppearanceSettings
- theme_mode: System
```

Defaults are materialized into persistence during database initialization or migration.

After successful database initialization, the following invariant holds:

> The required `AppearanceSettings` singleton record exists and maps to a valid current-domain aggregate.

Consequences:

- `get()` does not synthesize defaults.
- `get()` does not use missing-row-as-default semantics.
- application code does not distinguish between "default" and "missing."
- first launch has explicit authoritative persisted settings before runtime readiness.
- missing required settings after initialization is an integrity failure.

## 12. Persistence Schema Requirements

The exact SQL belongs to the implementation plan, but the persistence schema must guarantee:

- at most one authoritative appearance-settings row
- a required persisted theme value
- deterministic mapping to `ThemeMode`
- enough persistence-local metadata to support future migration when necessary
- no generic key/value schema requirement

The initial migration must both create the storage required for `AppearanceSettings` and materialize the canonical `System` default for a fresh database.

Future changes to appearance settings use released immutable migrations under SPEC-BE-002. A migration may transform persistence representation without changing the application contract when semantics remain equivalent.

## 13. Repository Contract

The write repository is owned by the appearance-settings feature and participates in the Unit of Work defined by SPEC-BE-002.

Conceptually:

```rust
pub trait AppearanceSettingsRepository {
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError>;

    fn save(
        &mut self,
        settings: &AppearanceSettings,
    ) -> Result<(), PersistenceError>;
}
```

`save` is the persistence operation underlying the application-level aggregate update. Exact naming may follow project coding conventions, but the semantics are fixed.

Rules:

1. The repository is transaction-bound.
2. The repository never creates or commits its own transaction.
3. `get()` returns an owned aggregate.
4. Missing required persistence is an error.
5. Invalid persisted values are errors.
6. Repository mapping never silently substitutes defaults for invalid persisted data.
7. Repository APIs expose no SQLite types, row IDs, schema revisions, or SQL details.

## 14. Query Interface Contract

Independent authoritative reads use a focused query interface as required by SPEC-BE-002.

Conceptually:

```text
AppearanceSettingsQueries
└── get() -> AppearanceSettings
```

The query interface:

- does not require a Unit of Work
- uses the persistence executor owned by infrastructure
- returns an immutable owned `AppearanceSettings`
- reports missing or invalid required persistence as an error
- does not create or repair settings

Although the result is the same domain shape used by the command, the read path remains distinct from the transaction-bound repository path.

## 15. `GetAppearanceSettingsQuery`

The application query contract is:

```text
GetAppearanceSettingsQuery
        ↓
AppearanceSettings
```

The query has no parameters.

Requirements:

1. It is statically classified as a Query under SPEC-BE-004.
2. It enters through centralized runtime admission.
3. It receives the standard `OperationContext` and `TraceId`.
4. It performs no authoritative side effects.
5. It returns the complete authoritative persisted aggregate.
6. It never returns a partial settings shape.
7. It never creates, repairs, or materializes defaults.
8. It does not create a Unit of Work for mutation.
9. Persistence and application failures map through SPEC-BE-003.

## 16. `UpdateAppearanceSettingsCommand`

The application command contract is conceptually:

```text
UpdateAppearanceSettingsCommand
└── settings: AppearanceSettings
```

The command represents intent; the aggregate represents desired domain state.

The command returns only terminal success or `ApplicationError`. It does not echo the updated aggregate.

Required flow:

```text
runtime admission
    ↓
UpdateAppearanceSettingsCommand
    ↓
begin Unit of Work
    ↓
load current AppearanceSettings through transaction-bound repository
    ↓
validate requested complete aggregate
    ↓
persist replacement aggregate
    ↓
collect AppearanceSettingsChanged
    ↓
commit
    ↓
publish committed event
    ↓
return success
```

Loading the current aggregate inside the Unit of Work establishes the mutation-decision read boundary and allows future validation to compare current and requested state without changing the contract.

## 17. Aggregate Replacement Semantics

`AppearanceSettings` is the unit of consistency.

The command submits the complete desired aggregate rather than a field-level persistence mutation.

Rules:

1. Validation applies to the complete requested aggregate.
2. Persistence occurs atomically.
3. Partial settings updates are not exposed at the application-command boundary.
4. Field-specific bridge/UI interactions map into a complete `AppearanceSettings` command input before reaching the application handler.
5. Persistence replacement mechanics remain private to infrastructure.

Future fields may be added to `AppearanceSettings` through the normal contract-versioning process. This does not justify introducing `SetThemeMode`, `SetLanguage`, or other field-per-command APIs during Phase 000.

## 18. Validation

Rust is authoritative for settings validation.

For Phase 000, valid `AppearanceSettings` requires exactly one valid `ThemeMode` value.

Validation occurs before persistence mutation is committed.

Invalid command input maps to the stable validation contract from SPEC-BE-003, including `ARGUS.V1.VALIDATION.INVALID_ARGUMENT` where applicable.

Bridge or Flutter validation may improve user experience but is not authoritative and does not replace backend validation.

Persisted values are validated during mapping/startup integrity checks even if the database schema normally constrains them. Persistence must be treated as potentially invalid after corruption, incompatible external modification, or implementation defects.

## 19. No Optimistic Concurrency During MVP

`AppearanceSettings` exposes no application-level version, revision, ETag, or expected-version field.

Concurrent updates use last-successful-commit semantics.

Requirements:

- each update is independently atomic
- database serialization follows SPEC-BE-002
- no stale-write conflict error is introduced solely for Phase 000 settings
- no version field is added to the domain or bridge contract

If Argus later supports multiple independent clients, synchronization, or another demonstrated concurrency requirement, optimistic concurrency may be added through a later specification without replacing the typed aggregate model.

## 20. `AppearanceSettingsChanged` Event

The committed notification contract is:

```text
AppearanceSettingsChanged
```

The event carries no authoritative `AppearanceSettings` payload.

Its meaning is exactly:

> The authoritative appearance settings aggregate committed a change and consumers should re-query when they require current state.

Requirements:

1. The event is collected during the command but published only after successful commit.
2. The event is never published on validation failure, persistence failure, rollback, or pre-commit cancellation.
3. The event does not transport the aggregate.
4. Flutter responds by issuing `GetAppearanceSettingsQuery` through its focused API when reconciliation is needed.
5. Event loss is safe because authoritative state remains persisted and queryable.
6. SPEC-BE-004 runtime sequence-gap and runtime-replacement behavior applies.
7. Event publication failure after commit does not change the committed command outcome.

## 21. No-Op Updates

A command whose requested `AppearanceSettings` is semantically identical to the current aggregate does not create a domain change.

Required behavior:

- validation still applies
- the handler may complete successfully without issuing a persistence update
- `AppearanceSettingsChanged` is not published when authoritative state did not change
- observability may record a successful no-op outcome at an appropriate diagnostic level

This prevents redundant event traffic and keeps the event's name semantically truthful.

## 22. Startup Integrity Validation

Appearance settings are mandatory startup state for Phase 000 because the ready Flutter shell requires authoritative theme mode before presentation.

Before the runtime reaches `Ready`, startup must verify that:

- migrations completed successfully
- the required appearance-settings record exists
- the persisted representation maps to the current domain model
- `theme_mode` is valid

A missing or invalid required aggregate prevents readiness.

The runtime enters `StartupFailed` according to SPEC-BE-004 rather than exposing a partially ready shell or silently creating a replacement value.

## 23. Persisted Settings Integrity Error

SPEC-BE-005 extends the published Phase 000 error catalog with:

```text
ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID
```

Default contract:

| Field | Value |
|---|---|
| Category | Configuration |
| Severity | Error |
| Recoverability | UserAction |
| Retry Policy | UserInitiated |
| Message Key | `errors.configuration.persisted_settings_invalid` |

Allowed safe context is limited to stable non-secret fields such as:

```text
settings_domain = appearance
reason = missing | invalid_value | mapping_failed
```

Raw persisted values, SQL, database paths, or arbitrary error text are prohibited from `SafeContext`.

Broader database corruption, migration failure, incompatible schema, or database-open failure must continue to use the applicable persistence/runtime error contracts and must not be disguised as an appearance-settings error.

## 24. Targeted Recovery Contract

When startup proves that failure is isolated to `AppearanceSettings`, the recovery layer may expose an explicit action:

```text
Reset Appearance Settings
```

This action is not automatic repair.

Required recovery flow:

```text
StartupFailed runtime
    ↓
user explicitly chooses Reset Appearance Settings
    ↓
recovery operation opens a bounded Unit of Work
    ↓
replace only AppearanceSettings with canonical defaults
    ↓
commit
    ↓
retire failed runtime
    ↓
construct new ApplicationRuntime
    ↓
normal startup validation
```

Rules:

1. The reset is available only when the failure is provably isolated to the appearance-settings aggregate.
2. Reset writes exactly the canonical current default: `ThemeMode::System`.
3. The reset must not delete or recreate the application database.
4. The reset must not modify unrelated settings or domain data.
5. The reset is atomic.
6. The failed `ApplicationRuntime` is never reused after recovery.
7. A new startup attempt receives a new runtime instance and `TraceId`.
8. If targeted reset itself fails, the original database remains preserved and the failure is surfaced through the applicable `ApplicationError`.

## 25. Failures Not Eligible for Targeted Reset

`Reset Appearance Settings` must not be presented as recovery for:

- migration failure
- migration checksum mismatch
- incompatible database schema
- SQLite structural corruption
- database open failure
- broad foreign-key/integrity failures
- permission failures unrelated to the appearance row
- failures whose scope cannot be proven to be limited to `AppearanceSettings`

Those conditions use the broader startup and persistence recovery contracts.

Targeted settings recovery must never mask an unknown persistence problem.

## 26. Runtime Integration

`GetAppearanceSettingsQuery` and `UpdateAppearanceSettingsCommand` use SPEC-BE-004 without special runtime machinery.

`GetAppearanceSettingsQuery`:

- execution class: Query
- authoritative side effects: none
- background job: none

`UpdateAppearanceSettingsCommand`:

- execution class: Immediate Command
- authoritative side effect: persisted settings update
- Unit of Work: one bounded transaction
- background job: none
- shutdown behavior: finish if already executing unless runtime cancellation occurs safely before commit

No settings-specific runtime queue, scheduler, executor, or background manager is introduced.

## 27. Cancellation Semantics

Query cancellation follows SPEC-BE-004 query behavior.

Update cancellation follows immediate-command semantics:

- before Unit of Work execution: command may be cancelled without mutation
- while the transaction is active and before commit: cancellation rolls back
- after durable commit: the command remains successful even if cancellation arrives afterward

`AppearanceSettingsChanged` is published only for committed semantic changes.

## 28. Observability

SPEC-BE-003 applies without settings-specific parallel logging infrastructure.

Stable event names should include:

```text
settings.appearance.read.completed
settings.appearance.update.completed
settings.appearance.update.noop
settings.appearance.integrity.failed
settings.appearance.reset.completed
```

Rules:

- every top-level settings operation has one `trace_id`
- settings failures follow the single-primary-error-log rule
- do not log arbitrary serialized settings objects
- `theme_mode` may be logged as a stable enum when diagnostically useful because it is non-secret
- persistence-local singleton IDs or raw database values are not observability identities
- operation and persistence duration measurements follow SPEC-BE-003

## 29. Diagnostic Bundle Behavior

Appearance settings are configuration data, so diagnostic inclusion is allowlist-based.

Phase 000 diagnostic summaries may include:

```text
appearance.theme_mode = system | light | dark
appearance.integrity = valid | invalid
```

They must not dump database rows or generic settings serialization.

When startup fails because persisted settings are invalid, diagnostics may report:

- settings domain: `appearance`
- sanitized failure reason
- relevant published error code
- startup `trace_id`

The invalid raw persisted value is excluded by default.

## 30. Security and Privacy

Appearance settings contain no credentials or user content in Phase 000.

Nevertheless, the settings architecture must preserve the broader rule that future sensitive configuration does not automatically become normal settings data.

Credentials, tokens, passwords, and authorization material belong to credential-specific infrastructure and must not be introduced into typed settings aggregates merely for convenience.

Generic serialization of all settings domains into logs, events, errors, or diagnostic bundles is prohibited.

## 31. Crate Ownership

Ownership follows SPEC-BE-001.

### `argus-domain`

Owns the domain concepts:

```text
AppearanceSettings
ThemeMode
```

The domain model contains no SQLite, bridge, runtime, logging, schema-version, or timestamp dependencies.

### `argus-application`

Owns:

```text
AppearanceSettingsRepository
AppearanceSettingsQueries
AppearanceSettingsService (thin application service over focused handlers)
GetAppearanceSettingsQuery / handler
UpdateAppearanceSettingsCommand / handler
AppearanceSettingsChanged
settings-specific application error mapping
```

Exact file/module organization follows implementation needs; empty speculative settings frameworks are prohibited.

### `argus-infrastructure`

Owns:

- SQLite persistence representation
- singleton key/constraint implementation
- row mapping
- repository adapter
- query adapter
- migration/default materialization
- persistence-local metadata

### `argus-runtime`

Owns only normal operation admission, execution context, event publication, startup orchestration, and runtime replacement responsibilities defined by SPEC-BE-004.

### `argus-bridge`

Maps the dedicated application contracts to bridge DTOs defined later by SPEC-BE-008. It does not own settings validation or persistence behavior.

## 32. Future Settings Domains

Future settings domains should follow this pattern by default:

```text
TypedDomainSettings
TypedDomainSettingsRepository
TypedDomainSettingsQueries
GetTypedDomainSettingsQuery
UpdateTypedDomainSettingsCommand
TypedDomainSettingsChanged
```

This is a convention, not a requirement to create a generic base class, generic repository, settings registry, or shared persistence blob.

A future domain may legitimately differ when its semantics require:

- multiple instances
- restart-required active/persisted values
- credential references
- more complex recovery
- separate commands because distinct consistency boundaries exist

Such differences must be justified by that domain's specification rather than forced into Phase 000 abstractions.

## 33. Testing Requirements

### 33.1 Domain tests

Test:

- `System`, `Light`, and `Dark` are the complete valid theme set
- invalid representations cannot construct a valid domain value through application mapping
- `AppearanceSettings` equality reflects domain state only

### 33.2 Repository integration tests

Using temporary on-disk SQLite databases as required by SPEC-BE-002, test:

- fresh migration materializes exactly one `AppearanceSettings` row
- default maps to `ThemeMode::System`
- load returns an owned aggregate
- save persists each valid theme mode
- rollback preserves the prior value
- missing required row produces an error
- invalid persisted value produces an error where it can be injected safely
- internal persistence metadata does not appear in the domain result

### 33.3 Query tests

Test:

- `GetAppearanceSettingsQuery` has no parameters
- returns the complete persisted aggregate
- produces no Unit of Work mutation
- does not synthesize defaults
- maps persistence failure through `ApplicationError`

### 33.4 Command tests

Test:

- complete aggregate validation
- Unit of Work ownership
- current aggregate read occurs inside the transaction
- successful change commits
- failed persistence rolls back
- pre-commit cancellation rolls back
- late cancellation does not overwrite committed success
- command returns no aggregate result
- identical requested state succeeds as a no-op
- no-op update publishes no change event

### 33.5 Event tests

Test:

- `AppearanceSettingsChanged` is collected only for semantic change
- publication occurs only after commit
- rollback publishes nothing
- event payload contains no authoritative aggregate
- event loss does not affect later query correctness
- sequence-gap recovery re-queries authoritative state through the normal runtime/event contracts

### 33.6 Startup integrity tests

Test:

- valid materialized default permits startup
- valid persisted Light and Dark values permit startup
- missing row prevents `Ready`
- invalid persisted value prevents `Ready`
- isolated settings failure maps to `ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID`
- broad database failures do not map to the targeted settings error

### 33.7 Targeted recovery tests

Test:

- recovery is offered only for proven isolated appearance-settings failure
- reset requires explicit invocation
- reset modifies only appearance settings
- reset writes `System`
- reset is atomic
- failed reset preserves unrelated data
- successful reset retires the failed runtime and uses a new runtime instance for retry
- broad corruption never triggers targeted reset

### 33.8 Architecture tests

Verify:

- no generic application `Setting` or key/value repository is introduced
- no `AppearanceSettingsId` leaks into domain/application/bridge contracts
- persistence metadata does not appear on `AppearanceSettings`
- SQLite types remain infrastructure-only
- Flutter/bridge concerns do not enter domain or repository contracts

## 34. Phase 000 Minimum Implementation

Phase 000 implements:

- `AppearanceSettings`
- `ThemeMode::{System, Light, Dark}`
- materialized `System` default
- typed SQLite persistence for the singleton aggregate
- transaction-bound appearance settings repository
- independent appearance settings query interface
- `GetAppearanceSettingsQuery`
- `UpdateAppearanceSettingsCommand`
- post-commit `AppearanceSettingsChanged`
- no-op update semantics
- startup settings integrity validation
- `ARGUS.V1.CONFIGURATION.PERSISTED_SETTINGS_INVALID`
- explicit targeted appearance-settings reset
- settings observability and diagnostic allowlisting
- tests required by this specification

Phase 000 does not implement additional settings domains, restart-required settings, generic settings infrastructure, credentials, import/export, synchronization, or optimistic concurrency.

## 35. Acceptance Criteria

SPEC-BE-005 is satisfied when:

1. Settings domains are strongly typed and independently owned.
2. No generic application-level key/value settings model exists.
3. `AppearanceSettings` contains only `theme_mode` at the application/domain boundary.
4. `ThemeMode` contains exactly System, Light, and Dark.
5. Persistence metadata is hidden behind persistence contracts.
6. No application-visible `AppearanceSettingsId` exists.
7. A fresh database materializes the canonical `System` default before runtime readiness.
8. Missing required appearance settings are treated as integrity failure rather than defaulted silently.
9. The write repository is transaction-bound.
10. The independent query interface is read-only and does not create defaults.
11. `GetAppearanceSettingsQuery` has no parameters and returns the complete authoritative aggregate.
12. `UpdateAppearanceSettingsCommand` carries the complete desired aggregate.
13. The update command returns success or `ApplicationError`, not the updated aggregate.
14. Update validation is Rust-owned.
15. Updates execute in one Unit of Work.
16. Mutation-decision reads occur inside the Unit of Work.
17. Semantic no-op updates do not publish change events.
18. Phase 000 uses last-successful-commit semantics without optimistic concurrency metadata.
19. `AppearanceSettingsChanged` carries no authoritative aggregate payload.
20. `AppearanceSettingsChanged` is published only after successful commit.
21. Event loss cannot make persisted settings incorrect.
22. Invalid required persisted settings prevent runtime `Ready`.
23. Isolated persisted settings failure maps to the stable configuration error contract.
24. Targeted reset is explicit user action and resets only `AppearanceSettings`.
25. Targeted reset is unavailable for broader or unknown persistence failures.
26. Successful targeted recovery starts with a new `ApplicationRuntime` instance.
27. Diagnostic output is allowlisted rather than generic settings serialization.
28. No settings contract leaks SQLite, bridge, Flutter, or other implementation technology.
29. Repository, query, command, event, startup integrity, and recovery tests pass.

## 36. Prohibited Patterns

- generic key/value settings APIs
- one global settings aggregate containing unrelated domains
- application-visible singleton persistence IDs
- persistence schema revisions on domain settings values
- backend timestamps required by Flutter settings models solely because persistence stores them
- missing-row-as-default behavior after successful initialization
- create-on-first-read settings behavior
- silent repair of invalid persisted settings
- automatic settings reset
- full database deletion as appearance-settings recovery
- field-per-command APIs without a demonstrated consistency requirement
- optimistic concurrency machinery during Phase 000
- event payloads used as the authoritative settings state
- event publication before commit
- generic serialization of all settings into diagnostics
- credentials stored in ordinary settings records

## 37. Out of Scope

This specification does not finalize:

- exact SQL table/column names
- exact Rust file names
- bridge DTO representation
- Flutter-facing settings models
- settings UI behavior
- restart-required settings state
- additional settings domains beyond the domains activated by later amendments
- credential-store implementation and secret persistence
- settings backup/export/import
- multi-client concurrency
- cloud synchronization
- policy for deleting obsolete settings columns beyond normal migrations

## 38. Phase 002 Android Appearance-Authority Amendment

Android platform readiness and lifecycle do not create a second settings domain or change `AppearanceSettings` semantics.

1. The same persisted `AppearanceSettings` singleton and `ThemeMode::{System, Light, Dark}` authority is shared across desktop and Android.
2. Activity detach/recreation, temporary backgrounding, foreground-service attachment, notification authorization changes, and All files access revocation/regrant do not mutate, reset, duplicate, or re-scope appearance settings.
3. Android permission/onboarding/readiness facts are platform-host state and must not be added to `AppearanceSettings` merely because they affect whether normal application startup may proceed.
4. A platform-readiness overlay may delay backend startup or normal-shell admission, but once the existing runtime/settings authority is usable it remains the sole appearance authority; the overlay does not own a fallback persisted theme.
5. Android tests must prove appearance persistence and first-shell restoration use the same backend settings contract rather than an Android-only store or controller.

## 38.1 Phase 003 Settings and Product-Onboarding Activation

PHASE-003 activates independently typed configuration records rather than extending `AppearanceSettings` or introducing a generic key/value store:

```text
MetadataSettings
- preferred_regions: ordered RegionCode values
- preferred_languages: ordered BCP-47 language tags

MetadataProviderSettings
- enabled_provider_ids: set<ProviderId>

PrivacyConsentRecord
- accepted_terms_version
- accepted_at

LibraryProviderSetupOutcome
- Pending
- Configured
- Skipped

LibraryOnboardingProgress
- metadata_preferences_confirmed
- provider_setup_outcome: LibraryProviderSetupOutcome
- completed_at nullable
```

These records have independent repositories, commands, integrity validation, and transaction boundaries. A unified Settings/onboarding UI does not make them one aggregate.

### 38.1.1 Defaults and onboarding authority

Fresh MetadataSettings defaults derive preferred region/language once from the host OS locale when no persisted values exist. Later OS-locale changes do not overwrite confirmed user preferences. The initial enabled metadata-provider set is `playmatch`, `gametdb`, and `steamgriddb`; SteamGridDB may therefore be enabled while capability readiness is `MissingCredentials` after the optional credential step is skipped.

A query-authoritative `LibraryOnboardingState` is derived from the current required privacy-terms version, `PrivacyConsentRecord`, `MetadataSettings`, `LibraryOnboardingProgress`, and whether at least one root exists when onboarding has never completed. The frontend does not own a second persisted completion boolean.

Rules:

1. onboarding can complete only after current privacy terms are accepted, metadata preferences are confirmed, the provider-setup step is completed or explicitly skipped, and at least one root exists;
2. onboarding completion commits before any initial refresh admission;
3. refresh-admission failure after completion does not roll onboarding back or reopen it on restart;
4. later removal of every root does not reopen onboarding; Library shows its normal no-root empty state;
5. a newer required privacy-terms version makes only the consent step incomplete until accepted;
6. declining required privacy terms follows ARCH-001 and does not create a reduced-consent product mode.

### 38.1.2 Onboarding commands and initial refresh

Onboarding steps mutate durable authority through focused commands rather than frontend-only flags:

```text
ConfirmLibraryMetadataPreferencesCommand(metadata_settings)
    -> LibraryOnboardingState

RecordLibraryProviderSetupOutcomeCommand(Configured | Skipped)
    -> LibraryOnboardingState
```

`ConfirmLibraryMetadataPreferencesCommand` validates the typed `MetadataSettings` aggregate and atomically commits it together with `metadata_preferences_confirmed = true`. It performs no provider request, artwork download, source work, or `library_resolution_refresh` admission while onboarding is incomplete.

`RecordLibraryProviderSetupOutcomeCommand` persists an explicit outcome rather than a generic completed Boolean. `Configured` is accepted only when SteamGridDB credential presence is authoritatively true and current readiness is `Ready` or transiently `Unavailable`; `MissingCredentials`, `InvalidCredentials`, and `Misconfigured` cannot be recorded as configured. `Skipped` is accepted only when no SteamGridDB credential is configured. A user skipping after an invalid credential attempt must first remove that credential successfully, preventing a durable `Skipped` outcome from coexisting with actionable `InvalidCredentials`. Skipping remains an explicit user choice and does not prevent later credential setup.

Before onboarding completes, a `Configured` outcome whose credential is subsequently removed no longer satisfies the completion prerequisite. After `completed_at` commits, later credential removal, provider disablement, locale changes, or root removal do not reopen product onboarding; those are normal Settings/Library states.

For a fresh no-root flow, successful root admission (`Added` or the idempotent `AlreadyConfigured` result) is immediately followed by `CompleteLibraryOnboardingAndRefreshCommand`; there is no second required confirmation click after folder selection. An existing-root upgrade has no folder-selection event, so it retains an explicit `Finish & Refresh` action. In both cases onboarding completion commits before refresh admission and remains complete if the child admission fails.

### 38.1.3 Settings changes and local re-resolution

`UpdateMetadataSettings` and `UpdateMetadataProviderSettings` persist the confirmed aggregate first. When the change affects current resolved metadata/artwork selection, the application then requests the local-only `library_resolution_refresh` operation defined by SPEC-BE-004/SPEC-BE-015.

The result distinguishes:

```text
CommittedNoResolutionWork(settings)
CommittedAndResolutionAdmitted(settings, operation_handle)
CommittedButResolutionNotAdmitted(settings, application_error)
```

A failure before settings commit reverts the UI to its last confirmed value. A later resolution-admission failure does not roll back the committed setting; current projections remain queryable but are marked resolution-stale until an explicit retry succeeds. The local resolution operation performs no source scan, provider request, or artwork download. If newly selected artwork lacks a local asset, `asset_id` remains null until a later explicit enrichment refresh downloads it.

### 38.1.4 Credential boundary

Metadata-provider enablement and locale preferences persist through ordinary typed repositories/commands. Credential configured/readiness facts are query projections from the credential/provider boundary, not secret settings data.

SteamGridDB key bytes are never persisted in `MetadataProviderSettings`, `MetadataSettings`, SQLite settings serialization, logs, diagnostics, events, Jobs records, or normal read DTOs. Credential creation/replacement/removal uses the credential-specific service defined by SPEC-BE-010/SPEC-BE-015. A secure-store failure cannot fall back to ordinary settings or plaintext application storage.

### 38.1.5 Phase 003 tests

Tests must prove:

- OS locale initializes missing metadata preferences once and never silently overwrites confirmed values;
- preference confirmation atomically commits settings and onboarding progress;
- provider setup permits only the closed `Configured`/`Skipped` command outcomes, derives `Pending` from authoritative state, and requires credential removal before skipping a configured invalid key;
- `Configured` requires secure credential presence plus `Ready` or transient `Unavailable` readiness;
- current required privacy terms, root presence, and all durable steps gate completion;
- first-folder completion is automatic after root success, existing-root completion is explicit, and child refresh failure never rolls completion back;
- credential/root/provider/locale changes after completion do not reopen onboarding, while a new required privacy version gates consent only;
- each settings-update result preserves committed settings independently from local-resolution admission;
- secure-store failure never writes secret material to ordinary settings or diagnostics.

Phase 003 does not activate an `ArtworkSettings` aggregate merely to expose compile-time resolver policy. A later user-configurable artwork policy may activate that domain when real durable user settings exist.

## 39. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../../phases/phase-000-foundation.md)
- [PHASE-002 — Android First-Class Platform Support](../../phases/phase-002-android-first-class-platform-support.md)
- [PHASE-003 — Game Identification and Enrichment](../../phases/phase-003-game-identification-and-enrichment.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-010 — Provider Gateway Architecture](spec-be-010-provider-gateway-architecture.md)
- [SPEC-BE-015 — Game Library, Grouping, and Enrichment Contract](spec-be-015-game-library-grouping-and-enrichment-contract.md)
- [SPEC-X-002 — Android Platform Runtime and Capability Contract](../cross-cutting/spec-x-002-android-platform-runtime-and-capability-contract.md)
- [Backend Specifications Index](README.md)
