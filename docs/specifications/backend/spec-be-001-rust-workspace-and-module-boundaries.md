# Rust Workspace and Module Boundaries Specification

**Document ID:** SPEC-BE-001
**Status:** Ready for Implementation
**Owner:** Daniel
**Last Updated:** 2026-08-08
**Depends On:** ARCH-001, ARCH-002, PHASE-000
**Supersedes:** None
**Superseded By:** None

## 1. Purpose

This specification defines the Rust workspace structure, crate responsibilities, dependency direction, internal module organization, visibility rules, adapter boundaries, and future extraction criteria for Argus ROM Toolkit.

The workspace must optimize for long-term maintainability, compiler-enforced architectural boundaries, focused testing, and safe delegation to Codex. It must remain restrained enough that Phase 000 does not become a crate-management exercise.

## 2. Architectural Principles

1. Domain rules are independent of persistence, Flutter, operating-system APIs, network clients, and generated bridge code.
2. Application use cases define the ports they require.
3. Infrastructure implements repositories and external-system gateways.
4. Runtime owns composition and lifecycle.
5. Bridge code translates between Flutter-facing DTOs and the runtime/application boundary.
6. Dependencies point inward toward stable policy.
7. Crates are introduced for meaningful architectural boundaries, not for every feature or directory.
8. Feature-first organization is preferred within crates.
9. Public APIs are intentionally small; implementation details remain private.
10. Circular crate dependencies are prohibited.

## 3. Workspace Layout

The initial Rust workspace contains five crates:

```text
rust/
├── Cargo.toml
├── Cargo.lock
└── crates/
    ├── argus-domain/
    ├── argus-application/
    ├── argus-infrastructure/
    ├── argus-runtime/
    └── argus-bridge/
```

The root `Cargo.toml` owns workspace members, resolver version, workspace package metadata, shared dependency versions where appropriate, workspace lints, and common profile defaults when justified.

The workspace uses one committed lockfile at `rust/Cargo.lock`.

## 4. Crate Dependency Graph

Allowed dependency direction:

```text
argus-domain
    ↑
argus-application
    ↑
argus-infrastructure
    ↑
argus-runtime
    ↑
argus-bridge
```

Exact rules:

- `argus-domain` has no Argus crate dependencies.
- `argus-application` depends only on `argus-domain` among Argus crates.
- `argus-infrastructure` depends on `argus-domain` and `argus-application`.
- `argus-runtime` depends on domain, application, and infrastructure.
- `argus-bridge` depends on runtime plus only the narrow domain/application types needed for mapping.
- No lower-level crate imports bridge DTOs.
- No crate depends on generated Dart code.
- Circular dependencies are prohibited.

CI must enforce dependency direction where practical.

## 5. Crate Responsibilities

### 5.1 `argus-domain`

Owns stable business vocabulary and rules:

- entities and aggregates
- value objects
- strongly typed identifiers
- domain events
- policies and invariants
- domain-specific validation
- domain-owned service traits only when intrinsic to the domain

It must not contain SQL, repository implementations, Unit of Work abstractions, HTTP/filesystem access, platform APIs, Flutter/FRB types, startup composition, or presentation DTOs.

### 5.2 `argus-application`

Owns use cases and required ports:

- application façades
- commands and queries
- use-case handlers
- repository port traits
- gateway port traits
- Unit of Work contracts
- planners and orchestration
- command results
- application errors
- event publication contracts

It contains no concrete adapters.

### 5.3 `argus-infrastructure`

Owns concrete technical adapters:

- SQLite connections, migrations, repositories, and Unit of Work
- source-provider adapters and filesystem/archive technical adapters
- HTTP/provider adapters
- credential-store adapters
- diagnostic bundle writers
- clock and ID implementations
- operating-system integration
- logging sinks

Infrastructure implements ports but does not decide application workflows.

### 5.4 `argus-runtime`

Owns composition and lifecycle:

- configuration loading
- application data-directory resolution
- database lifecycle and migration orchestration
- adapter and service construction
- event-bus wiring
- startup and shutdown coordination
- concrete façade container exposed to the bridge

It does not expose infrastructure implementations directly to Flutter.

### 5.5 `argus-bridge`

The only Flutter-facing Rust crate. It owns:

- dedicated bridge DTOs
- DTO mapping
- exported FRB functions
- event-stream adaptation
- stable bridge error DTOs

It must not contain business rules, SQL, repository implementations, provider behavior, or scheduler logic. Bridge DTOs do not leak inward.

## 6. Feature-First Internal Organization

Domain and application crates are organized primarily by bounded context:

```text
argus-domain/src/
├── lib.rs
├── common/
├── settings/
├── library/
├── content/
├── metadata/
├── artwork/
├── retroachievements/
├── jobs/
└── diagnostics/
```

```text
argus-application/src/
├── lib.rs
├── common/
├── settings/
├── library/
├── content/
├── metadata/
├── artwork/
├── retroachievements/
├── jobs/
└── diagnostics/
```

Feature folders may contain commands, queries, handlers, repositories, gateways, events, and service entry points as needed. Empty structural folders are prohibited.

Infrastructure may organize first by technology, then feature:

```text
argus-infrastructure/src/
├── sqlite/
├── filesystem/
├── http/
├── credentials/
├── diagnostics/
├── time/
└── identifiers/
```

Runtime and bridge remain shallow and composition-focused.

## 7. Common Module Admission Policy

A type may enter `common/` only when:

1. It is independent of every bounded context in that crate.
2. At least three distinct feature areas require it.
3. No feature remains its natural owner.
4. Sharing removes real coupling rather than anticipated duplication.
5. Its semantics are stable.

Feature-owned concepts remain with their feature even when referenced elsewhere. Examples include `GameContentId`, `LibraryRootId`, `ArtworkReference`, and `RetroAchievementsGameId`.

Exceptions require an ADR or an explicit update to this specification.

## 8. Repositories and Gateways

### 8.1 Repositories

Repositories persist and query Argus-owned state. Contracts live in `argus-application`; implementations live in `argus-infrastructure`.

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

Transaction-bound repositories are obtained through a Unit of Work. Repositories never start, commit, or roll back transactions independently.

### 8.2 Gateways

Gateways communicate with external systems or operating-system capabilities. Contracts live in `argus-application`; implementations live in `argus-infrastructure`.

Examples:

```text
LibrarySourceAccess
MetadataMatchingCapability
MetadataRefreshCapability
ArtworkDiscoveryCapability
CredentialStoreGateway
ClockGateway
IdGeneratorGateway
```

Metadata-provider contracts use the provider-independent capability/session architecture defined by SPEC-BE-010. Concrete provider names such as Playmatch belong to infrastructure adapter implementations, not application gateway port names. Source/storage access uses the separate registry/factory/access provider family defined by SPEC-BE-011; source providers are not metadata-provider sessions, and archive/container parsing remains transformation infrastructure rather than a source-provider gateway. RetroAchievements remains a separately specified external-service subsystem unless a later specification explicitly adopts shared provider capability contracts.

Gateways generally do not participate in the SQLite transaction. Application handlers coordinate external calls and persistence explicitly.

### 8.3 Naming

Contracts use capability-oriented names. Concrete adapters identify implementation technology when useful. Generic names such as `Manager`, `Helper`, `Util`, and `ServiceImpl` are prohibited unless they accurately describe a narrow responsibility.

## 9. Unit of Work Ownership

Unit of Work contracts live in `argus-application`. SQLite implementations live in `argus-infrastructure`. Application handlers own the lifecycle; runtime constructs the factory.

Conceptually:

```rust
pub trait UnitOfWork {
    type Error;

    fn appearance_settings(
        &mut self,
    ) -> &mut dyn AppearanceSettingsRepository<Error = Self::Error>;

    fn commit(self) -> Result<(), Self::Error>;
    fn rollback(self) -> Result<(), Self::Error>;
}
```

Exact signatures, async behavior, and object-safety details are defined by SPEC-BE-002. Ownership and dependency direction are fixed by this specification.
