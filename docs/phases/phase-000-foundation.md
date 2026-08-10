# Phase 000 — Foundation

**Document ID:** PHASE-000  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-09  
**Depends On:** ARCH-001, ARCH-002  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

Phase 000 establishes the smallest complete Argus application foundation that proves the approved Rust-to-Flutter architecture through a real persisted workflow.

The phase does not attempt to implement the complete settings system, source providers, library indexing, jobs, metadata, artwork, or RetroAchievements. It creates only the cross-cutting infrastructure required by later phases and validates it with one user-visible capability: selecting an application theme, applying it immediately, and restoring it after restart.

This is a product milestone rather than a collection of disconnected infrastructure tasks. At completion, Argus is a launchable cross-platform application with a functioning Rust backend, SQLite persistence, native bridge, adaptive Flutter shell, settings screen, event propagation, startup recovery, and diagnostic foundation.

## 2. User-Visible Outcome

At the end of Phase 000, a user can:

1. Launch Argus on a supported development platform.
2. See a blocking startup screen while required backend initialization completes.
3. Enter the application shell after the database opens and migrations succeed.
4. Navigate to Settings.
5. Choose one of these theme modes:
   - System
   - Light
   - Dark
6. See the new theme apply immediately without restarting Argus.
7. Close and relaunch Argus.
8. See the previously selected theme restored before the main shell is presented.
9. Receive a targeted recovery screen if backend startup, database opening, migration, or required appearance-settings integrity validation fails.
10. Copy startup error details or export a sanitized diagnostic bundle from the recovery screen.

No library source or ROM-management workflow is available in this phase.

## 3. Canonical Demonstration Scenario

Phase 000 is demonstrated by the following sequence:

1. Start Argus with a new or valid application database.
2. The startup screen appears.
3. Rust initializes successfully, opens SQLite, runs migrations, loads appearance settings, and reports readiness.
4. The Flutter application shell appears using the current system theme because `themeMode` defaults to `system`.
5. Open Settings.
6. Change Theme Mode from System to Dark.
7. The control enters a local pending state while the update is submitted.
8. Rust validates and persists the new value in a Unit of Work.
9. The transaction commits.
10. Rust publishes `AppearanceSettingsChanged` after the commit.
11. Flutter receives the event, refreshes authoritative appearance settings, and applies Dark theme.
12. Close Argus normally.
13. Relaunch Argus.
14. Startup loads the persisted Dark setting before constructing the ready application shell.
15. The shell appears in Dark theme.
16. No restart-required indicator is shown.
17. No unexpected warnings or errors appear in diagnostics.

This scenario must be supported by automated tests wherever practical and remain available as a manual release-verification flow.

## 4. Architecture Validated by This Phase

Phase 000 must exercise and validate the following approved boundaries:

```text
Flutter settings control
    ↓
Riverpod controller
    ↓
Focused SettingsApi
    ↓
ArgusClient
    ↓
flutter_rust_bridge generated bindings
    ↓
Rust AppearanceSettingsService façade
    ↓
Use-case handler
    ↓
Unit of Work
    ↓
SQLite
    ↓ commit
AppearanceSettingsChanged application event
    ↓
Flutter event coordinator
    ↓
Riverpod authoritative refresh
    ↓
MaterialApp theme update
```

It also validates:

- Rust as the authoritative owner of application settings.
- Flutter as the owner of rendering and interaction only.
- Dedicated bridge DTOs rather than exposed Rust domain types.
- String IDs or bridge-compatible primitives at the bridge boundary and typed Dart models inside Flutter.
- Two-stage mapping from bridge DTOs to frontend read models to UI-facing models where presentation adaptation is required.
- Riverpod code generation for all providers.
- Freezed for immutable Dart models.
- `go_router` for routed shell navigation.
- Feature-first Flutter organization with explicit internal layers and purpose-specific public APIs.
- Operation-level transactions owned by a Unit of Work.
- Event publication only after persistence commits.
- Structured error translation rather than raw Rust errors in the UI.
- Immediate settings persistence with rollback to the last confirmed value on failure.
- A blocking startup screen for mandatory initialization only.

## 5. Dependencies

### 5.1 Required Completed Documents

- **ARCH-001 — Argus ROM Toolkit Architecture**
- **ARCH-002 — Argus Documentation Architecture**

### 5.2 Required External Toolchain

Exact version pins belong in the repository/workspace specification and implementation slices, but the phase assumes:

- Rust toolchain
- Flutter SDK and Dart SDK
- SQLite
- `flutter_rust_bridge`
- Riverpod and Riverpod generator
- Freezed
- JSON serialization support where bridge DTOs require it
- `build_runner`
- `go_router`

### 5.3 Phase Dependencies

None. This is the first implementation phase.

## 6. In Scope

### 6.1 Repository and Workspace Foundation

- Repository layout for Rust backend, Flutter application, generated bridge output, tests, scripts, and documentation.
- Formatting, linting, static analysis, and baseline CI.
- Reproducible code-generation commands.
- Local development instructions sufficient for a fresh Codex or human session.

### 6.2 Rust Application Foundation

- Core crate/module boundaries required for Phase 000.
- Shared typed identifiers and stable application error model.
- Structured logging and `trace_id` propagation sufficient for startup and settings operations.
- Configuration and application data-directory resolution.
- SQLite connection management.
- Migration framework and initial schema.
- Unit of Work abstraction with transaction-bound repositories.
- Appearance settings repository.
- `AppearanceSettingsService` façade and focused query/command handlers.
- Minimal in-process domain event bus.
- Startup coordinator and readiness result.
- Startup failure classification.
- Sanitized diagnostic-contributor foundation.

### 6.3 Appearance Settings Domain

The application-level settings domain is:

```text
AppearanceSettings
- theme_mode
```

Persistence-local metadata such as schema revision, timestamps, and the internal singleton key does not cross the repository boundary.

Allowed theme modes:

```text
System
Light
Dark
```

Requirements:

- A fresh or migrated database materializes the canonical `System` default before runtime readiness.
- The required singleton record must exist and be valid after successful initialization; missing or invalid persistence is a startup integrity failure.
- Rust validates all incoming values.
- Settings are read through a focused query.
- Updates persist immediately.
- The update operation is transactional.
- `AppearanceSettingsChanged` is published only after a semantic change commits successfully and carries no authoritative aggregate payload.
- A failed update leaves persisted state unchanged.
- A failed Flutter submission restores the last confirmed UI value and presents an inline error.
- Theme changes do not require application restart.

### 6.4 Bridge Foundation

- `flutter_rust_bridge` project integration.
- Generated bindings treated as internal infrastructure.
- Dedicated startup, appearance-settings, event, command-result, and UI-error DTOs.
- One root backend initialization call.
- Focused settings read/update calls.
- One application-level event stream.
- Stable structured error translation.
- Bridge smoke tests.

### 6.5 Flutter Application Foundation

- Flutter project and supported development targets.
- `ProviderScope` composition root.
- Riverpod-generated application and feature providers.
- Freezed immutable models.
- Root `ArgusClient` with focused `settings` and `events` APIs.
- App-level event coordinator.
- `go_router` route configuration.
- Adaptive application shell skeleton.
- Compact bottom navigation, medium navigation rail, and expanded/large sidebar structure sufficient for available Phase 000 destinations.
- Settings destination.
- Placeholder destinations may be used only when clearly labeled unavailable and required to validate shell routing; unnecessary future-feature stubs are excluded.
- Theme application through `MaterialApp.themeMode` or the equivalent root theme mechanism.
- Initial loading, loaded, error, and recovery states.
- Immediate settings persistence behavior.
- Transient non-blocking feedback where appropriate.

### 6.6 Startup and Recovery

Mandatory startup work may block on:

- native bridge initialization
- database path resolution
- database opening
- migrations
- core service construction
- appearance-settings loading
- event-stream initialization required for a safe ready state

Startup must not wait for future library, provider, indexing, metadata, artwork, or verification work.

Startup failures must be classified at least into:

```text
BridgeInitialization
DatabaseOpen
DatabaseLocked
MigrationFailed
IncompatibleSchema
ConfigurationInvalid
AppearanceSettingsInvalid
Permissions
CoreServiceInitialization
Unknown
```

The recovery screen exposes only applicable actions, which may include:

- Retry
- Copy technical details
- Export diagnostics
- Reset Appearance Settings when the startup failure is proven to be isolated to the appearance-settings aggregate
- Open data directory where supported
- Exit

Destructive database-reset or restore workflows are not required in Phase 000 unless necessary to test the recovery architecture; they remain deferred.

### 6.7 Diagnostics Foundation

- Copyable plain-text startup error report.
- Exportable ZIP diagnostic bundle.
- Contributor-based diagnostic assembly so later subsystems can add sanitized content.
- Application version, backend version, OS/runtime details, migration state, sanitized configuration, and startup logs.
- Argus-owned identifiers as the canonical observability identity once assigned.
- No credentials, secrets, ROM paths beyond sanitized/necessary metadata, user content, or unrelated personal data.

## 7. Out of Scope

Phase 000 explicitly excludes:

- `LibrarySource`, `LibraryRoot`, and `SourceEntry` functionality.
- Filesystem provider implementation beyond any minimal path utility needed for the application data directory.
- Library scanning or filesystem watching.
- Persisted user-visible jobs or the full generic execution-graph scheduler.
- Indexing, reconciliation, move detection, or source classification. Their architecture is defined for later phases by [SPEC-BE-011 — Source Provider and Indexing Contract](../specifications/backend/spec-be-011-source-provider-and-indexing-contract.md); SPEC-BE-011 does not add source/indexing work to Phase 000.
- `GameContent`.
- Parsing and transformation graphs, canonical content identity, identity migration, hash schemes, or hash persistence. Their architecture is defined for later phases by [SPEC-BE-012 — Transformation and Hash-Scheme Contract](../specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md); SPEC-BE-012 does not add transformation/identity/hash work to Phase 000.
- Metadata matching, Playmatch, provider sessions, or metadata refresh. Their architecture is defined for later phases by [SPEC-BE-010 — Provider Gateway Architecture](../specifications/backend/spec-be-010-provider-gateway-architecture.md); SPEC-BE-010 does not add provider work to Phase 000.
- Artwork discovery, resolution, download, or storage.
- RetroAchievements integration.
- Search, library grid/list, filters, pagination, selection, or inspector UI.
- Full design-system implementation beyond minimum reusable foundations needed by startup, shell, recovery, and settings.
- Complete settings domains beyond appearance theme mode.
- Restart-required settings workflow, except interfaces may avoid blocking its later addition.
- Persistent notification inbox.
- Command palette.
- Custom keyboard shortcuts.
- Global undo history or command-level undo implementation.
- Plugin system.
- Production packaging, signing, installers, and release distribution.
- Final privacy/terms copy.

## 8. Required Subsystem Specifications

The following specifications must be written and reach **Ready for Implementation** before their first dependent slice begins. They do not all need to exist before Phase 000 planning starts.

### Backend

| Planned ID | Specification | Required before |
|---|---|---|
| [SPEC-BE-001](../specifications/backend/spec-be-001-rust-workspace-and-module-boundaries.md) | Rust Workspace and Module Boundaries | First workspace slice |
| [SPEC-BE-002](../specifications/backend/spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md) | SQLite, Migrations, Repositories, and Unit of Work | Persistence slice |
| [SPEC-BE-003](../specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md) | Application Errors, Logging, Diagnostics, and Observability | Startup/backend slice |
| [SPEC-BE-004](../specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md) | Application Runtime, Command Pipeline, and Background Operations | Runtime/startup slice |
| [SPEC-BE-005](../specifications/backend/spec-be-005-settings-service-and-appearance-settings.md) | Settings Service and Appearance Settings | Settings backend slice |
| [SPEC-BE-006](../specifications/backend/spec-be-006-minimal-domain-event-bus.md) | Minimal Domain Event Bus | Event propagation slice |
| [SPEC-BE-007](../specifications/backend/spec-be-007-startup-coordination-and-recovery-contract.md) | Startup Coordination and Recovery Contract | Startup integration slice |
| [SPEC-BE-008](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md) | Rust-to-Flutter Bridge DTO Contract | Bridge slice |
| [SPEC-BE-009](../specifications/backend/spec-be-009-application-service-contracts.md) | Application Service Contracts | First application-service slice |
| [SPEC-BE-010](../specifications/backend/spec-be-010-provider-gateway-architecture.md) | Provider Gateway Architecture | First metadata-provider-dependent slice |
| [SPEC-BE-011](../specifications/backend/spec-be-011-source-provider-and-indexing-contract.md) | Source Provider and Indexing Contract | First source-provider/indexing-dependent slice |
| [SPEC-BE-012](../specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md) | Transformation and Hash-Scheme Contract | First transformation/identity/hash-dependent slice |

### Frontend

| Planned ID | Specification | Required before |
|---|---|---|
| [SPEC-FE-001](../specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md) | Flutter Project Structure and Feature Boundaries | Flutter workspace slice |
| [SPEC-FE-002](../specifications/frontend/spec-fe-002-riverpod-freezed-and-controller-state-conventions.md) | Riverpod, Freezed, and Controller State Conventions | First provider/controller slice |
| [SPEC-FE-003](../specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md) | ArgusClient and Focused Domain APIs | Bridge integration slice |
| [SPEC-FE-004](../specifications/frontend/spec-fe-004-routing-and-adaptive-application-shell.md) | Routing and Adaptive Application Shell | Shell slice |
| SPEC-FE-005 | Startup and Recovery UI | Startup integration slice |
| SPEC-FE-006 | Appearance Settings and Theme Application | Theme workflow slice |
| SPEC-FE-007 | Design-System Foundation and Accessibility Baseline | First user-facing Flutter slice |

### Cross-Cutting and Conventions

| Planned ID | Document | Required before |
|---|---|---|
| [SPEC-X-001](../specifications/cross-cutting/spec-x-001-versioning-and-compatibility-contract.md) | Versioning and Compatibility Contract | Bridge and migration slices |
| [CONV-REPO-001](../conventions/conv-repo-001-repository-and-generated-file-conventions.md) | Repository and Generated-File Conventions | Workspace slice |
| [CONV-RUST-001](../conventions/conv-rust-001-rust-coding-and-test-conventions.md) | Rust Coding and Test Conventions | First Rust implementation slice |
| [CONV-FLUTTER-001](../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md) | Flutter/Dart Coding and Test Conventions | First Flutter implementation slice |
| [CONV-TEST-001](../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md) | Test Pyramid, Fixtures, and Verification Commands | First test-bearing slice |
| [CONV-DOC-001](../conventions/conv-doc-001-documentation-and-codex-result-conventions.md) | Documentation and Codex Result Conventions | First Codex task |

IDs are reserved by this phase. A specification may be split only if the split preserves these responsibilities and updates this phase before dependent implementation begins.

## 9. Ordered Implementation Slices

The following are phase-level slices, not Codex tasks. Exact child task counts are defined later.

### SLICE-P00-001 — Repository and Toolchain Bootstrap

**Outcome:** A reproducible Rust/Flutter workspace exists with formatting, linting, baseline CI, documentation links, and code-generation commands.

Validates repository layout and development workflow only. It does not introduce application behavior.

### SLICE-P00-002 — Rust Startup and Persistence Kernel

**Outcome:** Rust can resolve its data directory, open SQLite, run the initial migration, construct a Unit of Work, and return a structured startup result in backend tests.

Includes the minimum error, logging, and diagnostic foundations required for startup.

### SLICE-P00-003 — Appearance Settings Backend

**Outcome:** Backend tests can read the materialized default appearance setting, update theme mode transactionally, reject invalid input, persist across process/repository recreation, and publish `AppearanceSettingsChanged` only after a semantic change commits.

### SLICE-P00-004 — Flutter Bootstrap and Static Shell

**Outcome:** Flutter launches into a generated-provider composition root, runs code generation successfully, routes between the shell and Settings, and adapts navigation presentation across defined size classes using static/fake data.

### SLICE-P00-005 — Native Bridge and ArgusClient Integration

**Outcome:** Flutter initializes Rust through `flutter_rust_bridge`, receives structured readiness and appearance-settings DTOs, and accesses them through a root `ArgusClient` with focused settings and event APIs.

### SLICE-P00-006 — Startup and Recovery Experience

**Outcome:** The blocking startup screen transitions to the ready shell on success and to a targeted recovery screen on injected startup failures. Copy-details and sanitized diagnostic export work end to end.

### SLICE-P00-007 — Immediate Theme Persistence Workflow

**Outcome:** The real Settings screen reads authoritative theme mode, submits immediate updates, shows pending/error behavior, applies confirmed theme changes, and reverts to the last confirmed value on failure.

### SLICE-P00-008 — Event-Driven Theme Reconciliation

**Outcome:** A committed backend `AppearanceSettingsChanged` event reaches Flutter through the application event stream, triggers the smallest appropriate authoritative refresh, and updates the root theme without duplicate state ownership.

### SLICE-P00-009 — Restart Restoration and Phase Hardening

**Outcome:** The canonical demonstration scenario passes, generated output is current, architecture boundaries are tested, diagnostics remain sanitized, and the selected theme survives a real application restart.

## 10. Failure, Cancellation, and Recovery Expectations

### 10.1 Startup

- Startup has explicit phases and cannot remain indefinitely in an unexplained loading state.
- Startup failure produces one structured `StartupFailureDto`.
- Retry occurs on the same recovery screen without stacking dialogs.
- Failed startup does not expose a partially functional shell.
- Existing databases are never silently deleted or reset.

### 10.2 Settings Read

- A missing or invalid required appearance-settings record prevents runtime readiness and produces a structured persisted-settings integrity error.
- If the failure is provably isolated to `AppearanceSettings`, the recovery flow may offer an explicit **Reset Appearance Settings** action that atomically restores the canonical `System` default without modifying unrelated data.
- No missing or corrupt settings value is silently interpreted differently by Flutter.

### 10.3 Settings Update

- Flutter remains interactive while persistence runs.
- The changed control shows pending state without blocking unrelated controls.
- Rust validates before commit.
- Persistence failure leaves authoritative storage unchanged.
- Flutter reverts to the last confirmed value after failure.
- The originating control shows an inline error.
- No `AppearanceSettingsChanged` event is published on rollback or semantic no-op.

### 10.4 Event Delivery

- Event sequence gaps or stream reconnection cause Flutter to re-query authoritative appearance settings.
- Events are notifications, not the durable settings record.
- Duplicate or coalesced settings events must not produce incorrect theme state.

### 10.5 Cancellation

Phase 000 does not introduce long-running cancellable jobs. Startup retry and settings submission may use request cancellation or disposal defensively, but no persisted cancellation workflow is required.

## 11. Security and Privacy Impact

### 11.1 Data Stored

Phase 000 stores only application infrastructure data and appearance settings required by this phase.

It does not store ROM metadata, source paths, provider credentials, or user account data.

### 11.2 Secrets

No secrets are required for the theme workflow.

The architecture must nevertheless ensure future secrets cannot enter:

- normal settings serialization
- logs
- events
- bridge DTOs
- diagnostic bundles

### 11.3 Diagnostics

Diagnostic export must be sanitized by construction. Tests must verify exclusion of known secret-like fields and arbitrary settings values not explicitly allowlisted.

### 11.4 Filesystem

Application data-directory resolution must prevent path traversal and must surface permission failures through structured startup recovery.

## 12. Test Strategy

### 12.1 Rust Unit Tests

Required coverage includes:

- theme-mode parsing and validation
- default appearance settings
- settings update behavior
- Unit of Work commit and rollback
- repository behavior against isolated test databases
- migration application and idempotent reopen
- event publication after commit only
- startup-failure classification
- diagnostic redaction and allowlisting

### 12.2 Rust Integration Tests

Required scenarios include:

- initialize a new database
- reopen an existing database
- persist and reload Dark theme
- inject a migration failure
- inject a database lock/open failure where supported
- verify failed settings updates do not change the stored value

### 12.3 Bridge Contract Tests

Required coverage includes:

- startup success DTO
- each supported startup-failure category
- appearance settings DTO mapping
- theme update result mapping
- UI error mapping
- event mapping and sequence information
- no raw internal error or domain object leakage

### 12.4 Flutter Controller Tests

Using focused API fakes:

- initial settings load
- immediate successful persistence
- pending state
- rollback after failure
- event-driven authoritative refresh
- stream-gap/reconnect refresh
- no full-screen loading after the settings screen has usable data

### 12.5 Flutter Widget Tests

Required coverage includes:

- startup loading screen
- ready shell
- recovery screen actions
- responsive navigation modes
- theme selector states
- inline update error
- Light, Dark, and System theme application
- accessibility labels and keyboard focus for Phase 000 controls

### 12.6 End-to-End and Manual Verification

- Canonical demonstration scenario.
- Startup failure to recovery flow using an injected failure mode.
- Isolated invalid appearance-settings recovery through explicit Reset Appearance Settings.
- Diagnostic bundle inspection for sanitization.
- Generated-file freshness check.
- Clean checkout build and test instructions.

## 13. Exit Criteria

Phase 000 is Complete only when all of the following are true:

### Repository and Tooling

- Rust and Flutter projects build from documented commands on the primary development platform.
- Formatting, linting, static analysis, and Phase 000 tests pass.
- Required generated files are reproducible and current.
- CI executes the agreed baseline checks.

### Backend

- SQLite initializes and migrations run on a new database.
- Existing Phase 000 databases reopen without data loss.
- Unit of Work owns settings transactions.
- A fresh database materializes `AppearanceSettings.themeMode = System` before runtime readiness.
- System, Light, and Dark values persist and reload correctly.
- Invalid values are rejected by Rust.
- Failed writes roll back.
- `AppearanceSettingsChanged` is emitted only after a semantic change commits and contains no authoritative aggregate payload.

### Bridge

- Flutter initializes Rust through generated `flutter_rust_bridge` bindings.
- Dedicated DTOs cover startup, settings, events, and errors.
- Generated bridge types do not leak into feature controllers or widgets.
- The application event stream connects and can recover authoritative state after an injected gap or reconnect.

### Flutter

- The blocking startup screen appears before backend readiness.
- Successful startup enters the routed adaptive application shell.
- Injected startup failure enters the targeted recovery screen.
- The Settings destination reads authoritative appearance settings.
- Theme selection persists immediately.
- A successful update applies the confirmed theme without restart.
- A failed update reverts to the last confirmed value and shows an inline error.
- The selected theme survives a real application restart.
- Compact, medium, expanded, and large shell presentations pass responsive tests.

### Diagnostics and Safety

- Copy Details produces a human-readable startup report.
- Export Diagnostics produces a valid sanitized archive.
- Tests confirm diagnostic output excludes secrets and unrelated user content.
- No destructive recovery action silently deletes an existing database.

### Documentation

- All specifications and conventions required by completed slices are at least Ready for Implementation and reflect the implementation.
- Every completed slice has measurable evidence.
- Architecture tests or lints enforce the initial dependency boundaries where practical.
- The canonical demonstration scenario is documented and passes.

## 14. Readiness Checklist

- [x] User-visible outcome is defined.
- [x] Dependencies are available or explicitly sequenced.
- [x] Scope and exclusions are explicit.
- [x] Required public interfaces are identified at the phase level.
- [x] Persistence impact is identified.
- [x] Failure and cancellation behavior are identified.
- [x] Security and privacy impact is identified.
- [x] Test requirements are specified.
- [x] Implementation slices are ordered.
- [x] Exit criteria are measurable.
- [x] No blocking phase-level design questions remain.
- [x] Daniel has accepted the capability and scope.

Detailed interface, schema, package-version, and file-layout decisions intentionally remain in the required subsystem specifications and slice plans. Their absence does not block phase readiness because each is explicitly sequenced before dependent implementation.

## 15. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../architecture/documentation-architecture.md)
- [SPEC-BE-010 — Provider Gateway Architecture](../specifications/backend/spec-be-010-provider-gateway-architecture.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](../specifications/backend/spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-BE-012 — Transformation and Hash-Scheme Contract](../specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md)
- [SPEC-FE-001 — Flutter Project Structure and Feature Boundaries](../specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md)
- [SPEC-FE-002 — Riverpod, Freezed, and Controller State Conventions](../specifications/frontend/spec-fe-002-riverpod-freezed-and-controller-state-conventions.md)
- [SPEC-FE-003 — ArgusClient and Focused Domain APIs](../specifications/frontend/spec-fe-003-argusclient-and-focused-domain-apis.md)
- [SPEC-FE-004 — Routing and Adaptive Application Shell](../specifications/frontend/spec-fe-004-routing-and-adaptive-application-shell.md)
- [SPEC-X-001 — Versioning and Compatibility Contract](../specifications/cross-cutting/spec-x-001-versioning-and-compatibility-contract.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](../conventions/conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-RUST-001 — Rust Coding and Test Conventions](../conventions/conv-rust-001-rust-coding-and-test-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](../conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](../conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [CONV-DOC-001 — Documentation and Codex Result Conventions](../conventions/conv-doc-001-documentation-and-codex-result-conventions.md)
- [Phase Documentation Rules](README.md)
- [Phase Template](../templates/phase.md)
