# Rust Coding and Test Conventions

**Document ID:** CONV-RUST-001  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-09  
**Depends On:** ARCH-001, PHASE-000, SPEC-BE-001, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, CONV-REPO-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This convention defines repeatable coding, API-design, error-handling, async/concurrency, dependency, and Rust-test-writing rules for handwritten Argus Rust code.

It exists to keep implementation quality predictable across human and Codex-authored changes while preserving the architectural boundaries defined by the backend specifications.

This convention does not redefine:

- crate and feature ownership from SPEC-BE-001;
- persistence and transaction semantics from SPEC-BE-002;
- published error semantics from SPEC-BE-003;
- runtime scheduling and operation semantics from SPEC-BE-004;
- repository-wide task orchestration from CONV-REPO-001;
- the repository-wide test pyramid, fixture taxonomy, and verification matrix that belong to CONV-TEST-001.

## 2. Governing Invariant

> **Argus Rust code should make valid behavior easy to express, invalid behavior difficult to represent, architectural boundaries visible in the type system, and failures straightforward to diagnose and test.**

## 3. Formatting and Compiler Baseline

`rustfmt` owns formatting for handwritten Rust source.

Canonical verification includes the equivalent of:

```text
cargo fmt --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
```

These commands are executed through the canonical `just` workflows defined by CONV-REPO-001.

Rules:

1. Compiler warnings fail canonical verification.
2. Enabled Clippy warnings fail canonical verification.
3. The project may enable a curated set of additional high-value lints.
4. `clippy::pedantic`, `clippy::nursery`, and the complete `clippy::restriction` group are not enabled wholesale.
5. Lint configuration is centralized at the workspace level when Cargo/Rust tooling supports doing so cleanly.
6. A lint suppression is scoped as narrowly as practical.
7. A non-obvious suppression includes a reason explaining why the code intentionally violates the lint.
8. Lint allowances must not be used to conceal an architecture violation, unhandled failure path, or speculative dead code.
9. Generated code may receive generator-specific lint treatment according to CONV-REPO-001.

## 4. Module and File Organization

SPEC-BE-001 remains authoritative for crate boundaries, dependency direction, feature-first organization, and `common/` admission.

Within those boundaries:

1. A module has one identifiable responsibility.
2. Source is organized by feature/domain responsibility rather than generic technical buckets when the owning specification defines a feature boundary.
3. `lib.rs` and `mod.rs` files are primarily declaration, composition, documentation, and intentional re-export surfaces.
4. Substantial business or infrastructure implementation should not accumulate in façade/root module files.
5. Split a module when it combines unrelated responsibilities or makes its contract difficult to understand; no arbitrary line-count limit is imposed.
6. Internal module structure is not automatically part of the crate's public API.
7. Broad wildcard re-export trees are avoided unless they provide a deliberate stable façade.

Generic dumping-ground modules or types are prohibited unless their responsibility genuinely matches the name and the owning architecture permits them. Examples to avoid include:

```text
utils
helpers
misc
manager
service_impl
common
```

`common` is additionally governed by the admission policy in SPEC-BE-001.

## 5. Naming

Names describe domain meaning, capability, or implementation responsibility.

Rules:

- types and traits use nouns or capability-oriented names;
- functions use verbs or verb phrases that describe the action performed;
- Boolean predicates use names that read naturally as conditions;
- concrete infrastructure adapters may identify their implementation technology where doing so improves clarity;
- application/domain contracts do not include infrastructure technology names merely because the current implementation uses that technology;
- abbreviations follow conventional Rust/ecosystem spelling when established and otherwise favor readability.

Avoid vague names whose meaning can only be discovered by reading the implementation.

## 6. Visibility and Public API Discipline

Use the narrowest visibility that satisfies the actual consumer.

Preferred progression:

```rust
fn internal() {}
pub(super) fn parent_only() {}
pub(crate) fn crate_internal() {}
pub fn intentional_public_contract() {}
```

Rules:

1. `pub` means the item is an intentional crate-facing contract.
2. Public visibility must not be used merely to make testing or wiring convenient when a narrower design is available.
3. Re-export only concepts consumers should intentionally depend on.
4. Do not expose internal module layout through unnecessary re-exports.
5. Public contracts must not leak third-party, SQLite, Tokio, `flutter_rust_bridge`, HTTP-client, archive-library, or other infrastructure types when the owning architecture requires technology-neutral vocabulary.
6. A public API should remain understandable without reading private implementation details.

## 7. Type Design

Use Rust's type system to represent Argus semantics directly where doing so improves correctness and clarity.

Prefer:

- dedicated identifier/newtype types instead of interchangeable primitive IDs;
- enums instead of magic strings or magic integers;
- validated constructors for values with real invariants;
- exhaustive matching when all states matter;
- `Option<T>` for genuine absence;
- `Result<T, E>` for fallible operations;
- structured option/configuration types when multiple Boolean arguments would make call sites ambiguous.

Avoid code such as:

```rust
load_game(game_id, false, true)
```

when the flags encode domain or operational choices that deserve names.

Do not introduce elaborate type-level machinery for trivial implementation details. Type strength must serve readability, correctness, or boundary enforcement rather than complexity for its own sake.

## 8. Ownership, Borrowing, and Cloning

Follow normal Rust ownership semantics and choose APIs around logical ownership rather than around minimizing every allocation.

Rules:

1. Borrow when the caller retains ownership and the callee only needs temporary access.
2. Take ownership when the callee logically consumes, stores, or transfers the value.
3. Return owned values when doing so materially simplifies an API and the cost is appropriate.
4. `clone()` is acceptable when a second owned value is semantically required.
5. Do not use habitual cloning merely to silence borrow-checker design issues.
6. Do not contort clear code to eliminate insignificant clones without measurement.
7. For large or performance-sensitive values, investigate clone frequency when profiling or benchmarks show it matters.

## 9. `unsafe` Rust

Handwritten Argus Rust denies `unsafe` by default.

The workspace should enforce this through a deny-level `unsafe_code` lint for handwritten crates where practical.

A handwritten exception is allowed only when a concrete infrastructure, bridge, FFI, OS-integration, or similarly low-level requirement cannot reasonably be implemented safely.

Every exception must:

1. be isolated to the smallest practical module or item;
2. explicitly opt out of the default `unsafe_code` denial only at that narrow boundary;
3. include a `SAFETY:` comment for each unsafe operation/block stating the invariant that makes the operation sound;
4. expose a safe wrapper to ordinary callers wherever possible;
5. keep unsafe invariants out of domain/application contracts;
6. include focused tests for the safe boundary and important invalid inputs;
7. document durable architectural rationale in the owning specification/convention or ADR when the exception becomes a long-lived design choice.

Generated source is governed by CONV-REPO-001. If an approved generator emits `unsafe`, generated files are not manually modified merely to satisfy the handwritten-source policy.

`forbid(unsafe_code)` is not required because the convention intentionally preserves the ability to grant a narrowly scoped audited exception.

## 10. Recoverable Errors and Panics

SPEC-BE-003 owns Argus error semantics and translation boundaries.

Rust code follows these rules:

1. Recoverable runtime conditions return typed `Result` values.
2. Use `?`, explicit `match`, or another clear typed propagation mechanism for ordinary failure flow.
3. Domain errors use domain vocabulary.
4. Application/port errors use capability/application vocabulary.
5. Infrastructure and third-party errors remain internal to their owning implementation layer.
6. Architectural boundaries translate errors explicitly according to SPEC-BE-003.
7. Third-party error types do not become stable Argus public contracts.
8. Errors are not reduced to arbitrary strings when callers require structured semantics.
9. Internal source chains may be retained for diagnostics when doing so does not expose restricted information through application/bridge contracts.

Panics are reserved for programmer errors, violated internal invariants, or states where continuing would mean the implementation's assumptions are already invalid.

Do not use `panic!` as ordinary validation, provider failure, filesystem failure, persistence failure, cancellation, user-error, or retry control flow.

## 11. `unwrap` and `expect`

Use standard Rust practice rather than a blanket restriction-lint policy.

### 11.1 Production code

- Avoid `unwrap()` in ordinary production paths.
- Prefer typed error propagation for recoverable conditions.
- `expect()` is acceptable when an invariant has already been established and the message states that invariant clearly.
- An invariant-dependent `expect()` should be close enough to the validation/construction that its correctness remains apparent.
- Do not use `unwrap()` or `expect()` as a substitute for handling input, storage, provider, runtime, or configuration failures.

Example:

```rust
let first = values
    .first()
    .expect("validated non-empty value collection");
```

is acceptable only when the non-empty invariant is established by construction or immediately preceding validated logic.

### 11.2 Tests

Tests may use `unwrap()` and `expect()` when success is the precondition under test and the panic output is sufficiently diagnostic.

Error-path tests should assert the actual typed error or observable failure semantics rather than merely expecting a panic or checking that a call returned `Err`.

The project does not globally enable `clippy::unwrap_used` or `clippy::expect_used` solely for strictness. Those restriction lints may be enabled locally for a module with a demonstrated need.

## 12. Error Helper Crates

Focused ecosystem crates may reduce boilerplate without changing architecture.

`thiserror` is the preferred convenience crate for handwritten typed error enums when it materially improves clarity.

Opaque error aggregators such as `anyhow` are not permitted in domain or application contracts because callers there require structured failure semantics.

An opaque process/tooling error type may be used in narrowly scoped developer tooling, migration utilities, binaries, or composition glue where:

- no architectural caller needs to branch on structured error semantics;
- the opaque error never crosses into published application/bridge contracts;
- use does not bypass SPEC-BE-003 mapping rules.

No error helper crate is mandatory where standard Rust types are clearer.

## 13. Async Design

Async is introduced because an operation is genuinely asynchronous, not as a default coding style.

Rules:

1. Domain logic should remain synchronous unless asynchronous behavior is inherent in its contract.
2. Tokio-specific types stay within runtime/infrastructure implementation boundaries established by SPEC-BE-004.
3. Public application/domain contracts use technology-neutral operational vocabulary.
4. Blocking filesystem, database, CPU-intensive, archive/transformation, or similar work does not execute arbitrarily on async runtime worker threads.
5. Blocking work follows the execution/scheduling contract owned by SPEC-BE-004 and the applicable subsystem specification.
6. Futures should not retain large values, lock guards, database transactions, or other scarce resources across `.await` without a clear requirement.
7. Cancellation semantics are defined by the owning operation contract; dropping a future is not automatically assumed to be a correct semantic cancellation boundary.
8. Do not introduce an async-trait helper library globally by convention. Trait shape and helper use follow concrete object-safety and compatibility needs.

## 14. Concurrency and Shared State

Prefer ownership and message/operation boundaries that reduce shared mutable state.

Rules:

- keep lock critical sections small;
- do not hold synchronous lock guards across `.await`;
- avoid `Arc<Mutex<T>>` as a reflexive solution to ownership design problems;
- use asynchronous locks only where asynchronous waiting for shared state is genuinely required;
- prefer immutable shared state when practical;
- prefer ownership transfer or dedicated coordination components over global mutable state;
- use atomics only when the required ordering semantics are understood and documented by the code structure or comments where non-obvious;
- concurrency-sensitive invariants receive focused tests;
- domain/application code should not inherit runtime synchronization types merely because infrastructure is concurrent.

## 15. `Send`, `Sync`, and Lifetime Bounds

Do not add `Send`, `Sync`, or `'static` bounds reflexively.

They are introduced where actual runtime ownership requires them.

Rules:

1. Runtime/background task boundaries may require `Send + 'static` according to SPEC-BE-004.
2. Shared runtime abstractions may require `Sync` where concurrent access is real.
3. Domain contracts do not inherit those bounds merely to make one infrastructure implementation convenient.
4. If a bound exists only because a current executor/library requires it, keep that requirement at the narrowest boundary that owns the executor/library.

## 16. Transactions and Await Boundaries

SPEC-BE-002 owns transaction semantics.

Rust implementation follows this operational shape:

```text
external/network/long-running work
    ↓
application coordination
    ↓
short persistence transaction
    ↓
commit
```

Rules:

- do not hold SQLite transactions across provider/network calls;
- do not hold a Unit of Work open across unrelated long-running computation;
- avoid awaiting unrelated work while transaction-owned resources remain live;
- make transaction ownership and commit/rollback boundaries apparent in application handler structure;
- repository methods do not independently start, commit, or roll back transactions when SPEC-BE-002 assigns that responsibility to the Unit of Work.

## 17. Third-Party Dependencies

New Rust dependencies require a concrete maintenance or correctness benefit.

Guidelines:

1. Prefer the standard library when it provides a clear, maintainable solution.
2. Prefer mature focused crates over bespoke infrastructure for well-solved problems when adoption reduces risk or maintenance cost.
3. Declare shared dependency versions/features consistently at the workspace level when appropriate.
4. Enable only required crate features when practical.
5. Avoid broad convenience/meta crates to obtain one trivial helper.
6. Avoid introducing competing libraries for the same repository-wide concern without a demonstrated reason.
7. Consider maintenance activity, ecosystem adoption, security history, license compatibility, transitive dependency impact, and API stability when a dependency is material.
8. A dependency is not rejected merely because equivalent code could be written manually.
9. Generated-code dependencies required by approved tooling are evaluated as part of that tooling choice rather than as incidental convenience dependencies.

Dependency changes remain subject to repository lockfile and reproducibility rules from CONV-REPO-001.

## 18. Rustdoc and Comments

Documentation explains contracts, invariants, rationale, and non-obvious behavior rather than restating syntax.

Rustdoc is required where callers need information not obvious from the signature/type alone, including:

- intentional public contracts with meaningful semantics;
- invariants enforced by constructors or types;
- meaningful error conditions;
- caller-visible panic behavior when a public function can intentionally panic;
- safety requirements;
- lifecycle, cancellation, ownership, ordering, or threading requirements callers must honor;
- behavior that would otherwise require reading implementation details.

Use conventional sections such as `# Errors`, `# Panics`, and `# Safety` when they improve caller understanding.

Comments should explain why code is structured a certain way when the reason is non-obvious. Avoid comments that merely translate the next line into English.

## 19. Conditional Compilation and Cargo Features

Conditional compilation expresses real platform, feature, test, or build boundaries.

Rules:

1. Keep platform-specific implementation behind infrastructure/runtime abstractions where possible.
2. Avoid scattering `#[cfg(target_os = ...)]` branches through domain/application logic.
3. Cargo features represent coherent optional capabilities or integration surfaces, not arbitrary implementation switches.
4. Feature combinations used by canonical verification must compile and test consistently.
5. Test-only compilation helpers remain test-only and do not leak into public production contracts.
6. Platform-specific modules should expose the same stable capability contract when the architecture requires interchangeable adapters.

## 20. Production Source Hygiene

Committed production Rust must not contain accidental development artifacts.

Prohibited in completed implementation slices:

- `dbg!`;
- unresolved `todo!`;
- unresolved `unimplemented!`;
- unexplained temporary `panic!`;
- commented-out obsolete implementations;
- broad `allow(dead_code)` used to preserve speculative future code;
- temporary debug logging that bypasses the observability conventions;
- placeholder implementations that silently return fabricated success/default values.

`todo!` or `unimplemented!` may exist only in deliberately incomplete scaffolding when the owning implementation task explicitly permits it. Such scaffolding cannot satisfy the acceptance criteria of a completed slice.

## 21. Rust Test Placement

CONV-TEST-001 owns the repository-wide test pyramid. Within Rust, tests live at the narrowest boundary that can verify the behavior without coupling to unnecessary internals.

Use:

- colocated `#[cfg(test)]` unit tests for private implementation behavior and focused logic;
- crate `tests/` integration tests for public crate-facing behavior where external-consumer perspective matters;
- higher-level integration/system tests only when behavior genuinely spans multiple crates/subsystems, as defined by CONV-TEST-001.

A bug fix should normally include a regression test at the lowest boundary that reproduces the defect and protects the intended contract.

Do not move tests outward merely to avoid exposing test seams; improve the internal design instead when a focused deterministic seam is warranted.

## 22. Test Naming and Structure

Test names state behavior, condition, or expected outcome.

Good examples:

```rust
#[test]
fn rejects_duplicate_library_root() {}

#[test]
fn rollback_preserves_existing_settings_on_write_failure() {}
```

Avoid names such as:

```text
test1
works
basic_test
test_handler
```

Tests generally follow a clear setup → action → assertion structure, but formal `Arrange/Act/Assert` comments are not required when the structure is already obvious.

A test should fail for one understandable behavioral reason. Avoid giant scenario tests that assert many unrelated contracts when focused tests would be clearer.

## 23. Test Determinism

Tests must be repeatable and independent of incidental developer-machine state.

Avoid unnecessary dependence on:

- wall-clock timing;
- execution order;
- public network availability;
- developer filesystem layout;
- global random state;
- shared mutable process state;
- arbitrary `sleep()` delays;
- external provider accounts or credentials.

Use Argus abstractions such as clocks, ID generators, gateways, repositories, provider interfaces, runtime admission seams, and temporary project-owned storage to make tests deterministic.

Async/concurrency tests wait for meaningful synchronization/state transitions rather than sleeping for a guessed duration.

Tests involving time use an owned/fake clock or runtime-supported controllable time where the tested layer provides such a seam.

## 24. Test Doubles

Prefer the simplest test double that communicates the scenario clearly.

Order of preference is generally:

1. real pure/domain value or implementation where deterministic and cheap;
2. small handwritten fake/stub implementing an existing Argus trait;
3. purpose-built in-memory implementation when repeated behavior warrants it;
4. a mocking framework only when repeated interaction assertions or test-double boilerplate create a demonstrated maintenance problem.

Do not design production traits solely to satisfy a mocking framework.

Shared test support must have a clear owner and must not become another unrestricted `common`, `helpers`, or `utils` area.

## 25. Assertions and Error Tests

Assertions should make failures diagnostically useful.

Rules:

- compare complete structured values when that best expresses the expected contract;
- assert only meaningful fields when incidental fields are intentionally variable;
- error tests assert typed variants/codes/semantics rather than arbitrary formatted strings;
- use string equality/matching when text itself is the contract;
- include explanatory assertion messages only when the expression does not already make the expectation clear;
- do not assert private implementation call order unless ordering is itself part of the observable contract.

Example intent:

```rust
assert_eq!(error, ExpectedError::DuplicateLibraryRoot { /* ... */ });
```

is preferable to testing whether `format!("{error}")` happens to contain an implementation-specific phrase.

## 26. Property, Snapshot, and Specialized Testing

Specialized test techniques are introduced for a demonstrated problem rather than by default.

- property-based testing is appropriate for transformation, parser, normalization, identity, or invariant-heavy behavior when generated cases materially improve coverage;
- snapshot testing is appropriate only when the serialized/textual structure is intentionally reviewable and stable enough that snapshots do not become approval noise;
- fuzzing is appropriate for parsers, untrusted binary/container inputs, or other robustness-sensitive boundaries when the owning implementation phase adopts it;
- benchmark crates/harnesses are introduced when repeatable performance comparisons are required.

No specialized test framework is mandated globally by this convention.

## 27. Performance and Optimization

Do not complicate ordinary Rust code for speculative performance gains.

When optimization is required:

1. identify the performance requirement or symptom;
2. measure current behavior;
3. isolate the demonstrated bottleneck;
4. optimize the bottleneck rather than surrounding code indiscriminately;
5. preserve/add correctness tests;
6. add a repeatable benchmark when future regression comparison is valuable.

Readable ownership, explicit boundaries, and correctness take precedence over unmeasured micro-optimization.

## 28. Prohibited Patterns

The following are prohibited unless an owning specification explicitly requires and justifies an exception:

- handwritten `unsafe` without a narrowly scoped audited exception;
- ordinary recoverable failures implemented with panic control flow;
- infrastructure/third-party error types leaking into stable application/domain contracts;
- technology-specific runtime/database/provider types leaking across architecture boundaries;
- habitual `unwrap()` in production paths;
- `expect()` messages that provide no invariant context;
- lock guards held across `.await` without a demonstrated and safe requirement;
- broad shared mutable state introduced merely to satisfy ownership constraints;
- reflexive `Arc<Mutex<_>>` wrapping;
- reflexive `Send + Sync + 'static` bounds at layers that do not require them;
- SQLite transactions held open across provider/network operations;
- broad lint disabling;
- blanket `clippy::pedantic`, `clippy::nursery`, or `clippy::restriction` enablement without revising this convention;
- speculative public APIs or modules added for hypothetical future use;
- production `dbg!`, unresolved `todo!`, or unresolved `unimplemented!` in a completed slice;
- tests that depend on arbitrary sleeps when a deterministic synchronization seam exists;
- assertions against formatted error text when typed semantics are available;
- mocking-framework-driven production architecture;
- performance complexity without evidence.

## 29. Examples

### 29.1 Compliant: Narrow error translation

```rust
let record = repository
    .load(id)
    .map_err(SettingsPortError::from)?;
```

The concrete repository error stays below the application-facing port boundary.

### 29.2 Non-Compliant: Infrastructure error leakage

```rust
pub fn load_settings(...) -> Result<AppearanceSettings, rusqlite::Error> {
    // ...
}
```

This couples an application contract to the persistence implementation.

### 29.3 Compliant: Explicit invariant

```rust
let primary = candidates
    .first()
    .expect("validated candidate set is non-empty");
```

This is acceptable when the non-empty state is established by construction/validation and violation indicates a programmer invariant failure.

### 29.4 Non-Compliant: User-data panic

```rust
let root = configured_root.unwrap();
```

If absence can result from user configuration or runtime state, it must be represented and handled explicitly.

### 29.5 Compliant: Platform isolation

```text
application capability trait
        ↓
infrastructure adapter
        ├── windows implementation
        └── macOS implementation
```

Platform checks remain behind the capability boundary.

### 29.6 Non-Compliant: Platform spread

```text
domain module -> #[cfg(target_os = "windows")]
application handler -> #[cfg(target_os = "macos")]
feature policy -> target-specific branches
```

Platform implementation detail has leaked upward.

### 29.7 Compliant: Deterministic async test

```text
start operation
signal fake dependency completion
await terminal state
assert typed result
```

### 29.8 Non-Compliant: Timing guess

```text
start operation
sleep(500 ms)
assert that it probably finished
```

## 30. Enforcement

The convention is enforced through the strongest practical mechanism for each rule.

### 30.1 Formatting

`cargo fmt --check` verifies `rustfmt` ownership.

### 30.2 Compiler and Clippy

Canonical Clippy verification runs across the workspace, all targets, and all features with warnings denied.

Workspace lint configuration captures stable lint policy where practical.

### 30.3 Architecture Tests

Architecture/boundary tests defined by the owning specifications and CONV-TEST-001 verify crate dependency direction and other mechanically testable boundaries.

### 30.4 Unit and Integration Tests

`cargo test --workspace --all-features` is part of canonical Rust verification unless CONV-TEST-001 later defines a more precise equivalent command matrix while preserving coverage.

### 30.5 Review

Review covers requirements that are not reliably machine-enforceable, including:

- whether a public API is unnecessarily broad;
- whether a clone hides an ownership design problem;
- whether an `expect()` represents a real invariant;
- whether a dependency is justified;
- whether concurrency/shared state is unnecessarily broad;
- whether an unsafe exception is adequately isolated and justified;
- whether tests are placed at the narrowest useful boundary.

## 31. Exceptions

Exceptions use the lightest durable mechanism that preserves architectural clarity.

1. A local lint exception is allowed when the code is clearer/correct and the suppression is narrowly scoped.
2. Non-obvious lint suppressions include a reason.
3. A handwritten `unsafe` exception follows Section 9 and is never granted merely to improve convenience or performance without evidence.
4. A durable exception that changes public API philosophy, error-boundary rules, async/runtime leakage, or dependency policy requires updating this convention or the owning higher-level specification.
5. A local implementation exception may be documented in the implementation slice/task when it does not alter a durable repository rule.
6. Generated source exceptions follow CONV-REPO-001.

## 32. Acceptance Criteria

CONV-RUST-001 is satisfied by an applicable implementation slice when:

1. Rust source is `rustfmt` compliant.
2. Compiler and enabled Clippy warnings are clean under canonical verification.
3. Lint suppressions are narrowly scoped and justified where non-obvious.
4. Crate/module ownership follows SPEC-BE-001.
5. Public visibility is intentional and no broader than required.
6. Public application/domain contracts remain free of prohibited infrastructure technology types.
7. Domain/application failures use typed errors and respect SPEC-BE-003 translation boundaries.
8. Recoverable runtime conditions do not rely on panic control flow.
9. Ordinary production paths avoid `unwrap()` and use `expect()` only for clear invariants.
10. Handwritten `unsafe` is absent or satisfies the audited exception policy.
11. Blocking work and async execution respect SPEC-BE-004.
12. Locks/shared state are scoped narrowly and synchronous guards are not held across `.await` without an explicit safe requirement.
13. `Send`, `Sync`, and `'static` bounds exist only where actual ownership/runtime needs justify them.
14. Persistence transactions are not held across unrelated provider/network/long-running work.
15. New dependencies have a concrete purpose and do not duplicate an existing repository-wide concern without reason.
16. Public/non-obvious contracts contain sufficient Rustdoc for correct use.
17. Completed production source contains no accidental `dbg!`, unresolved `todo!`, or unresolved `unimplemented!` artifacts.
18. Rust tests live at the narrowest useful boundary.
19. Tests are deterministic and do not rely on public network access, developer filesystem layout, or arbitrary sleeps where controlled seams are available.
20. Error tests assert typed/contract semantics rather than incidental formatting when structured semantics exist.
21. Optimization work is evidence-driven rather than speculative.
22. Canonical Rust format, lint, and test verification passes for the slice's supported configuration.

## 33. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../architecture/architecture-overview.md)
- [PHASE-000 — Foundation](../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](../specifications/backend/spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](../specifications/backend/spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](conv-repo-001-repository-and-generated-file-conventions.md)
- [Convention Template](../templates/convention.md)
