# Test Pyramid, Fixtures, and Verification Commands

**Document ID:** CONV-TEST-001  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-09  
**Depends On:** ARCH-001, PHASE-000, SPEC-BE-002, SPEC-BE-003, SPEC-BE-004, SPEC-BE-008, SPEC-BE-010, SPEC-BE-011, SPEC-BE-012, CONV-REPO-001, CONV-RUST-001, CONV-FLUTTER-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This convention defines the repository-wide test pyramid, fixture taxonomy, deterministic-test rules, verification command semantics, CI evidence expectations, regression policy, and minimum evidence required for Argus implementation work.

It coordinates the test-writing rules already owned by language- and subsystem-specific specifications without duplicating those specifications.

This convention exists so that a claim such as "the slice is tested" has a stable repository meaning: the relevant behavioral and architectural contracts were verified at the lowest reliable boundary, the canonical deterministic gate passed, and any required native or milestone evidence was also produced.

This convention does not redefine:

- Rust test-writing style owned by CONV-RUST-001;
- Flutter/Dart test-writing style owned by CONV-FLUTTER-001;
- repository task-runner and CI topology owned by CONV-REPO-001;
- persistence semantics and migration behavior owned by SPEC-BE-002;
- application error semantics owned by SPEC-BE-003;
- runtime/cancellation semantics owned by SPEC-BE-004;
- bridge DTO semantics owned by SPEC-BE-008;
- provider contract semantics owned by SPEC-BE-010;
- source-provider/indexing semantics owned by SPEC-BE-011;
- transformation/hash semantics owned by SPEC-BE-012;
- exact feature-specific test scenarios defined by their owning specifications or phases.

More specific specifications may require stronger evidence than this convention. They must not weaken the deterministic, isolation, privacy, or architectural-boundary requirements defined here.

## 2. Governing Invariant

> **Argus test evidence must correspond directly to the behavior and architectural contract being claimed, with the lowest deterministic test boundary preferred and broader tests reserved for risks that genuinely cross boundaries.**

The default repository test suite must be deterministic, offline, isolated from developer-machine state, and practical to run routinely.

## 3. Testing Principles

Argus follows these repository-wide principles:

1. Prefer the lowest test boundary that can prove the contract faithfully.
2. Use real owned infrastructure when its semantics are the subject of the test; do not mock away SQLite, filesystem, serialization, or bridge behavior when those are what must be verified.
3. Substitute external systems and unrelated layers through existing architecture seams.
4. Keep ordinary required tests deterministic and offline.
5. Treat reusable contract suites as first-class protection for interchangeable implementations.
6. Treat architecture enforcement as test evidence where compiler/static checks cannot enforce a rule directly.
7. Add regression coverage for defects at the lowest boundary that reproduces them.
8. Do not use test count or raw coverage percentage as a substitute for required behavioral scenarios.
9. A flaky required test is a defect, not a successful test after retries.
10. Test data committed to the repository must be safe to publish.
11. Broader tests are valuable only when they prove behavior that narrower tests cannot.
12. Performance, fuzz, stress, live-service, and manual verification remain distinct from ordinary correctness tests unless deliberately promoted into the canonical gate.

## 4. Test Pyramid

Argus uses a balanced deterministic test pyramid.

Conceptually:

```text
many
│
├── unit / value / pure-model / state-machine tests
├── reusable contract tests
├── component tests with controlled infrastructure
├── integration tests
├── bridge / UI integration tests
└── end-to-end / native / live-service tests
│
few
```

The pyramid expresses expected quantity and scope, not rigid framework categories.

A test is classified by the boundary it exercises and the risks it proves rather than only by whether a framework calls it a "unit" or "integration" test.

## 5. Unit Tests

Unit tests verify one small owned behavior with minimal dependencies.

Representative targets include:

- domain value objects and policies;
- validation and normalization;
- planners and deterministic graph construction;
- scheduler/state-machine transitions;
- pure mappers;
- frontend identifiers/read-model mapping;
- Riverpod controller transitions using focused API fakes;
- parser subcomponents where no real container/filesystem behavior is needed.

Unit tests should dominate the suite because they are fast, precise, and diagnostic.

A unit test must not be forced when the behavior inherently depends on an owned infrastructure contract. For example, repository transaction semantics are better proven using real SQLite than by mocking SQL calls.

## 6. Contract Tests

A contract test is a reusable suite that verifies every implementation of an Argus-owned capability against the same invariants.

Contract tests are required where interchangeable implementations exist or are expected, including as applicable:

- repositories;
- provider gateways/adapters;
- source-provider adapters;
- transformation planners/executors;
- bridge serialization/compatibility boundaries;
- other stable ports with multiple implementations.

A contract suite should verify externally observable Argus semantics rather than implementation-specific call sequences.

When a defect reveals a missing invariant that applies to every implementation, the regression belongs in the shared contract suite where practical.

## 7. Component Tests

Component tests exercise one substantial subsystem with its owned infrastructure while substituting unrelated external dependencies.

Examples:

- repository + real isolated SQLite;
- migration runner + historical database fixture;
- provider adapter + controlled fake transport;
- transformation planner + synthetic filesystem/container fixtures;
- bridge mapper + canonical DTO fixture;
- Flutter controller + focused API fake.

Component tests are preferred over full end-to-end tests when they can prove the same contract more deterministically and with clearer failure localization.

## 8. Integration Tests

Integration tests verify behavior spanning two or more real Argus components where the interaction itself is important.

Representative examples include:

- runtime + persistence lifecycle;
- Unit of Work commit/rollback + event publication;
- startup coordination + migration/open failures;
- bridge DTO generation/mapping + Dart contract consumption;
- event sequence/gap recovery across bridge/client boundaries;
- routing + controller restoration where both layers materially participate.

Integration tests remain isolated and deterministic unless explicitly categorized as native, live-service, or end-to-end tests.

## 9. End-to-End Tests

End-to-end tests verify a complete user-visible or operational workflow across major boundaries.

They are intentionally fewer than lower-level tests.

Examples include the architecture-level scenarios defined by ARCH-001 and phase documents, such as:

- startup through ready UI;
- settings persistence across application restart;
- scan/index/update workflows;
- dropped-event recovery;
- cancellation of a long-running operation;
- diagnostic export through the user-facing workflow.

An end-to-end test must not be added merely because a lower-level regression exists. Add it only when the defect or acceptance requirement genuinely crosses boundaries that narrower tests cannot prove.

## 10. Live-Service Tests

Tests that call an actual external provider are a separate category.

They must:

- be clearly labeled/separated from deterministic tests;
- be opt-in when credentials or public network access are required;
- use provider-approved behavior and reasonable request volume;
- never require committed credentials;
- never become the only evidence for provider adapter correctness;
- avoid destructive account behavior;
- sanitize any retained failure artifacts.

Ordinary provider correctness is proven with controlled transport/SDK fakes or safe recorded fixtures.

A live external service is never required for `just test` or the platform-neutral `just check` gate.

## 11. Native-Platform Tests

Native-platform tests verify behavior that materially differs across supported operating systems or native build environments.

CONV-REPO-001 owns the tiered CI topology. This convention defines the evidence expected from targeted native jobs.

Native checks include as applicable:

- Rust/Flutter native compilation;
- `flutter_rust_bridge` generation/build integration;
- native application startup smoke behavior;
- platform filesystem/path semantics;
- credential-store/platform-service integration when introduced;
- installer/package behavior when the release process reaches that scope;
- other requirements explicitly identified as OS-specific.

Platform-neutral suites should not be duplicated across every supported OS without a demonstrated reason.

## 12. Canonical Verification Commands

CONV-REPO-001 defines the canonical root command surface:

```text
just bootstrap
just generate
just check-generated
just format
just lint
just test
just check
```

This convention defines the test meaning of those commands.

### 12.1 `just test`

`just test` runs the complete deterministic, platform-neutral, offline automated test set required by the current repository state and completed implementation slices.

It must include, as applicable:

- Rust unit/component/integration tests that are platform-neutral;
- repository/migration contract tests;
- bridge contract tests that can run without native UI automation;
- Flutter/Dart unit, provider/controller, and widget tests that are platform-neutral;
- reusable provider/source-provider/transformation contract suites;
- architecture tests that are implemented as test suites rather than lint/static checks.

`just test` must not require:

- provider credentials;
- public internet access;
- developer-specific directories;
- an existing user database;
- ROM/BIOS collections;
- manually prepared local state;
- interactive input.

### 12.2 `just check`

`just check` remains the canonical local/CI platform-neutral quality gate and composes the applicable checks for:

```text
formatting
+ lint/static analysis
+ generated-source freshness
+ architecture/dependency verification
+ just test
+ other explicitly adopted repository checks
```

Passing `just test` alone does not imply formatting, lints, generated source, or non-test architecture checks are clean.

### 12.3 Focused Native Commands

Direct `cargo test`, `flutter test`, specific test filters, or subsystem recipes remain valid during development and debugging.

A focused command proves only the scope it executed. It does not replace the canonical completion gate unless the implementation task explicitly requires only that narrower evidence.

### 12.4 Additional Stable Recipes

Additional root recipes may be introduced when a test category becomes a stable workflow, for example conceptually:

```text
just test-native
just test-e2e
just test-live-provider <provider>
```

Exact names are implementation decisions and must follow CONV-REPO-001 rather than being mandated prematurely here.

A new recipe must represent a durable category, not an alias for every individual test command.

## 13. Determinism

Required tests must be repeatable for the same repository/toolchain state.

Ordinary tests must not depend unnecessarily on:

- wall-clock timing;
- test execution order;
- public network availability;
- global random state;
- existing developer files;
- developer usernames/home directories;
- real provider accounts;
- mutable process-global state;
- arbitrary sleep delays;
- previous test output;
- locally installed applications beyond documented project prerequisites.

Use owned seams such as:

```text
clock
ID generator
random source
provider transport
filesystem root
temporary database
runtime admission/control
focused Flutter API
```

when exact environmental values affect the behavior under test.

## 14. Time, Randomness, and Identity

Tests involving time use a controlled clock or a runtime-supported controllable-time mechanism where the tested layer offers that seam.

Tests involving generated identifiers use a deterministic ID source when exact identity matters to the assertion.

Property/fuzz tests may use randomness intentionally. Reproducibility requirements then change:

- a failing seed/input must be reported or persisted sufficiently to reproduce the failure;
- a minimized regression case should be added when appropriate;
- random test order must not hide state leakage.

Do not add injectable clocks/ID sources to production APIs solely for tests when an existing architectural seam already provides the needed control.

## 15. Async and Concurrency Tests

Async/concurrent tests synchronize on meaningful events/state rather than guessed elapsed time.

Prefer:

```text
start operation
wait for explicit barrier/state/event
release controlled dependency
await terminal state
assert result
```

over:

```text
start operation
sleep 500 ms
assert that it probably completed
```

Tests for stale completion, cancellation, ordering, or concurrency must deliberately control competing operations so the condition is deterministic.

A timing-sensitive race reproduced only by repeatedly running a flaky test is not sufficient regression protection.

## 16. Test Isolation and Parallelism

Tests own their mutable state.

They must support parallel execution unless the behavior genuinely requires process-global serialization.

Rules:

1. Use unique temporary directories/databases/resources per test or per explicitly isolated fixture scope.
2. Do not share mutable test databases merely to reduce setup time.
3. Do not rely on test execution order.
4. Global locks/serial-suite flags are not the default solution for poor isolation.
5. A test that requires an exclusive global/native resource documents that requirement and minimizes its exclusive scope.
6. Cleanup should not destroy another test's resources.
7. Failure cleanup must be safe to repeat and must not target developer-owned paths.

## 17. Fixture Taxonomy

Argus distinguishes three fixture categories.

### 17.1 Synthetic Fixtures

Synthetic fixtures are the default.

They are created specifically for a test and contain the minimum data needed to demonstrate the contract.

Examples include:

- fabricated domain values;
- synthetic ROM-like byte streams;
- generated archive/container layouts;
- fake provider payloads;
- small controller/read-model datasets.

### 17.2 Canonical Repository Fixtures

Canonical repository fixtures are committed because they preserve durable compatibility/regression evidence.

Examples include:

- historical SQLite schema databases;
- sanitized provider responses;
- bridge contract/snapshot fixtures;
- parser/container regression samples;
- carefully reviewed golden images.

A canonical fixture requires a clear owner and contract. It must not become an unexplained data dump.

### 17.3 Runtime-Generated Fixtures

Runtime-generated fixtures are temporary resources created during a test run, including:

- SQLite databases;
- directories/files;
- archives;
- generated configuration;
- fake transport state;
- temporary diagnostics.

They are disposable and must not be required from a previous run.

## 18. Fixture Ownership and Placement

Fixtures live with the subsystem that owns their semantics or in a clearly named shared test-support area with a specific owner.

Prefer owned categories such as:

```text
persistence migration fixtures
provider contract fixtures
bridge contract fixtures
transformation/parser fixtures
Flutter golden assets
```

over an unrestricted global directory such as:

```text
test/fixtures/everything/
```

A fixture is promoted to shared use only when multiple tests genuinely share the same durable contract.

Fixture filenames and adjacent documentation should make scenario/purpose discoverable without reverse-engineering opaque binary content.

## 19. Historical Migration Fixtures

Historical schema fixtures are durable compatibility evidence.

Once a schema version has been released and retained as a supported migration source, its fixture is immutable.

Conceptually:

```text
schema-v1.sqlite
schema-v2.sqlite
schema-v3.sqlite
```

Migration tests open these historical databases using the current application migration path and verify forward migration and resulting invariants.

Do not regenerate an old historical fixture with current schema-creation logic. Doing so would erase evidence that current migration code can read the historical format.

If a historical fixture is proven invalid, correcting/replacing it requires explicit documented rationale and review as a compatibility change.

## 20. Database Test Rules

Repository, migration, Unit of Work, transaction, and persistence behavior should normally use real SQLite rather than mocking SQL calls.

Use:

- isolated in-memory SQLite when disk semantics are irrelevant;
- per-test temporary database files when reopen, locking, journaling, filesystem, migration-file, or durable-write behavior matters.

Persistence tests verify Argus-level behavior, including as applicable:

- schema invariants;
- migration compatibility;
- commit/rollback;
- foreign-key behavior;
- repository contracts;
- Unit of Work ownership;
- projection consistency;
- reopen behavior;
- failure recovery.

Tests must not operate on a developer's normal Argus application database.

## 21. Filesystem and Container Fixtures

Filesystem tests use test-owned temporary roots.

When relevant to an owning specification, fixtures should cover edge conditions such as:

- nested paths;
- Unicode names;
- invalid/unavailable paths;
- case-related collisions where platform semantics matter;
- symlink/link rules;
- partial inputs;
- archives/containers;
- path traversal attempts;
- resource-limit boundaries.

Do not create unnecessarily huge repository fixtures to test size limits. Prefer synthetic bounded inputs, sparse/generated data, or configurable limits where the production design permits faithful deterministic testing.

## 22. Provider Fixtures

Ordinary provider adapter tests use a controlled fake transport/SDK boundary or sanitized recorded provider responses.

A committed recorded response must:

1. contain no credentials, tokens, cookies, auth headers, or private account data;
2. avoid personally identifying information unless fabricated;
3. preserve enough native structure to test translation honestly;
4. identify provider/scenario ownership;
5. remove irrelevant volatile fields only when doing so does not change tested semantics;
6. be deliberately reviewed when updated after provider API changes.

Tests must not silently refresh committed provider fixtures from the live service as part of the canonical gate.

## 23. Bridge Contract Fixtures

Rust and Dart bridge compatibility is a durable contract and may use snapshot/fixture tests where they provide strong change detection.

Contract evidence should detect incompatible changes such as:

- field removal;
- field type changes;
- enum/union incompatibility;
- identifier representation changes;
- changed error semantics;
- changed event metadata semantics;
- accidental infrastructure/internal type leakage.

A changed snapshot/fixture is not correct merely because a generator or update command produced it. Contract changes require semantic review against SPEC-BE-008 and the applicable compatibility specification.

Snapshot testing remains targeted rather than a blanket style for all serialization.

## 24. Flutter Golden Fixtures

Golden tests are selective visual-regression tools.

Use them where visual stability has high value, such as:

- stable design-system primitives;
- major adaptive application-shell states;
- specifically regression-prone visual components.

Do not golden-test every widget.

Semantic widget tests remain primary for interaction, state, accessibility, focus, and routing behavior.

Golden updates require visual review. CI must not blindly auto-accept a changed baseline.

## 25. Test Data Privacy, Security, and Licensing

Committed test data must be safe to publish with the source repository.

Do not commit:

- user ROMs or BIOS files;
- credentials, API keys, tokens, cookies, or auth headers;
- private diagnostic bundles;
- user application databases;
- provider account exports;
- save data/private personal content;
- personally identifying local paths/usernames;
- copyrighted assets without explicit redistribution rights.

Synthetic ROM-like/parser fixtures contain only fabricated/minimum bytes necessary for the tested contract.

CI failure artifacts must follow the same privacy rules.

## 26. Test Doubles

Use existing architectural seams rather than creating test-only architecture.

General preference:

```text
real pure implementation
    ↓
small fake/stub at an Argus-owned seam
    ↓
in-memory implementation where reusable behavior warrants it
    ↓
mocking framework only when interaction assertions/boilerplate justify it
```

Do not:

- design production traits/APIs solely for a mocking framework;
- mock the infrastructure semantics that are themselves under test;
- expose private implementation details solely to assert them;
- substitute broad application layers when a narrower focused API seam exists.

Language-specific double conventions remain in CONV-RUST-001 and CONV-FLUTTER-001.

## 27. Architecture Enforcement

Architectural rules use the strongest practical enforcement mechanism.

Preference order:

```text
compile-time/module/package boundary
    ↓
static analysis/lint
    ↓
architecture test
    ↓
review-only rule
```

Examples of mechanically enforced concerns include as applicable:

- Rust crate dependency direction;
- infrastructure/runtime technology types not leaking into application/domain contracts;
- bridge/generated FRB types not entering Flutter feature code;
- feature-private `src/` imports;
- provider/source-provider implementation dependency direction;
- transaction/repository ownership boundaries that can be expressed structurally.

Do not build brittle source-text scanning tests when the compiler/module/package system can enforce the same invariant more reliably.

Architecture tests belong in `just check` whether implemented as tests, lints, or another deterministic repository check.

## 28. Regression Policy

A defect fix normally includes a regression test at the lowest boundary that reproduces the actual defect and protects the intended contract.

Representative mapping:

| Defect | Preferred regression boundary |
|---|---|
| domain invariant | unit test |
| SQLite transaction/repository behavior | repository/UoW integration test |
| migration compatibility | historical migration fixture test |
| provider normalization/error translation | provider adapter/contract test |
| bridge mapping/compatibility | bridge contract test |
| Riverpod async/state race | controller/provider test |
| responsive interaction | widget test |
| routing/restoration | routing/widget integration test |
| native startup/filesystem behavior | applicable native test |
| cross-stack workflow | integration/E2E only when narrower layers cannot prove it |

Do not automatically add an end-to-end regression when the defect is completely and faithfully captured at a lower deterministic boundary.

If a defect reveals a missing contract invariant shared by multiple implementations, update the reusable contract suite.

## 29. Specification-Driven Acceptance

Explicit test scenarios and acceptance criteria in specifications/phases are implementation obligations.

A completed implementation slice must:

1. identify the specification/convention criteria affected by the slice;
2. map mechanically testable requirements to tests/static/architecture checks;
3. execute the relevant focused and canonical verification;
4. record legitimately manual evidence separately;
5. avoid claiming coverage merely because an adjacent test happened to pass.

"Unit tests added" is not a substitute for satisfying the named scenarios in an owning specification.

Tests prove behavior; test count is not a success metric.

## 30. Minimum Evidence by Change Type

Unless an owning specification requires stronger evidence, use this baseline:

| Change type | Minimum expected evidence |
|---|---|
| Pure Rust/Dart logic | focused unit tests + applicable canonical gate |
| Persistence/repository | focused repository/component tests + canonical gate |
| Migration | historical/current migration fixtures + reopen/schema assertions + canonical gate |
| Provider adapter | adapter unit/component tests + reusable provider contract suite |
| Source provider | adapter tests + reusable source-provider contract suite |
| Transformation/hash behavior | planner/path/resource tests required by owning spec |
| Bridge contract | Rust mapping tests + Dart/fixture/compatibility tests as applicable |
| Flutter controller | provider/controller state tests |
| Widget behavior | widget interaction/semantics test |
| Architecture boundary | compile/static/architecture test |
| Platform-specific behavior | applicable native-platform CI/test |
| Cross-stack workflow | integration/E2E when lower layers cannot prove it |
| Bug fix | regression at the lowest faithful reproducing boundary |

A focused test plus `just check` is generally expected before a normal implementation slice is considered complete when the repository can execute that gate.

## 31. Flaky Tests

Required tests have no accepted flaky status.

Blind automatic retry must not convert an unreliable test into a successful gate.

When a required test is flaky:

1. investigate state leakage, synchronization, environment coupling, or a real product race;
2. make the relevant seam deterministic;
3. fix the test or production defect;
4. preserve a reliable regression.

Temporary quarantine is allowed only when keeping the test active blocks unrelated work and all of the following are true:

- the defect is explicitly tracked;
- the quarantine is narrowly scoped;
- the test remains visible/discoverable;
- affected behavior is not reported as verified;
- removal/repair is treated as technical debt.

Quarantine is not a permanent test category.

## 32. Manual Verification

Manual verification is reserved for criteria that cannot yet be automated economically or reliably.

Examples may include:

- deliberate visual review of a changed golden baseline;
- installer/native packaging behavior;
- early-phase diagnostic bundle inspection;
- a canonical demonstration walkthrough.

Manual evidence records at least:

- scenario checked;
- expected result;
- environment/platform when relevant;
- actual outcome.

A bare statement such as "tested manually" is insufficient evidence.

Recurring manual checks should be automated when the value and stability justify it.

## 33. CI Evidence and Failure Artifacts

Required CI jobs must identify the failing verification category clearly enough to support diagnosis.

Where useful, CI may retain non-sensitive artifacts such as:

- structured test reports;
- sanitized logs;
- screenshots or golden diffs;
- generated-source diffs;
- small synthetic failure fixtures.

CI must not retain or upload secrets, real ROM/BIOS content, private user data, or unsanitized diagnostic bundles.

A CI artifact is diagnostic evidence, not authoritative application state.

## 34. Coverage Metrics

Argus does not require a repository-wide line/branch coverage percentage gate by default.

Coverage tools may be used diagnostically to identify suspiciously untested areas, but acceptance is driven by:

- specification-required scenarios;
- contract suites;
- regression tests;
- architecture verification;
- explicit risk review.

A numeric threshold may be adopted later only if project experience demonstrates that it improves behavior rather than incentivizing low-value assertions.

Do not add trivial tests solely to increase a percentage.

## 35. Property, Fuzz, Stress, Soak, and Performance Tests

Specialized test categories are adopted for demonstrated risk.

Appropriate areas include:

- parsers and untrusted archive/container inputs;
- normalization/identity invariants;
- transformation/hash correctness;
- resource limits;
- runtime scheduling/cancellation;
- large-library indexing/query behavior;
- pagination stability.

These tests are separate from the ordinary deterministic gate unless a bounded form is fast/reliable enough to promote deliberately.

Rules:

- fuzz/property failures must be reproducible from retained input/seed information;
- stress/soak tests do not replace deterministic state-machine tests;
- benchmarks do not replace correctness tests;
- performance gates require a stable environment/tolerance strategy before becoming required CI.

## 36. End-to-End and Milestone Gates

A phase/release may require end-to-end or demonstration evidence beyond `just check`.

For example, PHASE-000 requires its canonical demonstration and startup/recovery/settings workflows as part of phase completion.

Rules:

1. Milestone-critical scenarios must pass before the milestone is claimed complete.
2. The complete E2E suite does not automatically run on every edit if it is materially slower or environment-dependent.
3. A fast, deterministic, high-value E2E scenario may later be promoted into normal CI.
4. Manual milestone evidence remains explicit until automated.
5. E2E failures should be reduced to lower-level regression tests when the root defect can subsequently be captured more precisely there.

## 37. Failure Diagnostics

A test failure should communicate the contract that failed.

Prefer assertions against:

- typed values;
- structured errors;
- state-machine states;
- canonical serialized/fixture values where serialization itself is the contract;
- meaningful user-visible widget semantics.

Avoid assertions that fail only with opaque implementation-specific text when structured semantics are available.

Test names and failure output should allow a developer or Codex session to identify the scenario without reading the entire implementation first.

## 38. Source Control Rules for Tests and Fixtures

Tests and fixtures follow CONV-REPO-001.

Commit:

- authored test source;
- canonical deterministic fixtures;
- historical schema fixtures;
- reviewed golden baselines;
- other deterministic test assets that form part of the repository contract.

Do not commit:

- temporary test databases;
- local failure dumps;
- runtime-generated test directories;
- credentials;
- arbitrary live-service captures;
- developer-specific snapshots;
- test result caches/build products.

Generated test source, if introduced by an approved tool, follows the same generated-source drift policy as other repository generation.

## 39. Prohibited Patterns

The following are prohibited unless an owning specification explicitly requires and justifies an exception:

- public-network/provider credentials required by `just test` or platform-neutral `just check`;
- ordinary correctness tests depending on developer ROM/BIOS collections;
- tests mutating the normal user/developer Argus database or data directory;
- arbitrary sleeps used as synchronization where an explicit state/event seam is available;
- test-order dependencies;
- mutable shared fixtures used merely for speed;
- blind retries used to hide required-test flakiness;
- regenerating historical migration fixtures with current schema logic;
- auto-accepting changed bridge/golden snapshots without review;
- real user/provider secrets or personal data in committed fixtures;
- mocking SQLite when real SQLite semantics are the contract under test;
- mocking generated FRB calls directly in ordinary feature tests when a focused frontend API seam exists;
- end-to-end tests added reflexively for behavior completely proven at a lower boundary;
- architecture rules enforced only by documentation when compile/static/test enforcement is practical;
- global coverage percentage used as the sole definition of adequate testing;
- production architecture distorted solely for test/mocking convenience;
- permanent quarantined/flaky test categories;
- manual verification described without a concrete scenario/outcome;
- benchmarks treated as correctness evidence.

## 40. Examples

### 40.1 Compliant: Repository behavior

```text
create unique temporary SQLite database
run real repository/UoW operation
commit or inject failure
reload using real repository
assert typed persisted state
```

The test proves persistence semantics without involving the Flutter UI or an external provider.

### 40.2 Non-Compliant: Mocked transaction behavior

```text
mock execute("COMMIT") -> success
assert repository called COMMIT once
```

This does not prove SQLite transaction or rollback behavior.

### 40.3 Compliant: Provider adapter

```text
provider adapter
    ↓
controlled fake transport returns native payload
    ↓
adapter normalizes result
    ↓
shared provider contract assertions
```

### 40.4 Non-Compliant: Ordinary live-provider dependency

```text
test requires personal API token
calls public provider
fails when network/provider is unavailable
```

### 40.5 Compliant: Async race regression

```text
start request A
start newer request B
complete B
complete A
assert A cannot overwrite B
```

### 40.6 Non-Compliant: Timing-based race hope

```text
start A and B
sleep 750 ms
assert current state
```

### 40.7 Compliant: Migration compatibility

```text
copy immutable schema-v2 fixture to temp location
open with current migration runner
migrate
assert current schema + retained values
```

### 40.8 Non-Compliant: Historical fixture regeneration

```text
create "v2" fixture using current schema builder
run current migrator
claim v2 compatibility
```

### 40.9 Compliant: Flutter feature test

```text
widget/controller
    ↓
focused API fake
    ↓
explicit state completion
    ↓
assert user-visible/state semantics
```

No real Rust backend is required for ordinary feature behavior.

## 41. Enforcement

This convention is enforced through the strongest practical mechanism for each rule.

### 41.1 Root Commands

`just test` and `just check` provide the canonical deterministic verification surfaces according to CONV-REPO-001 and this convention.

### 41.2 Language Test Runners

Rust and Flutter/Dart native test runners execute the language-specific suites defined by CONV-RUST-001 and CONV-FLUTTER-001.

### 41.3 Contract Suites

Reusable contract-test harnesses enforce common invariants across interchangeable repository/provider/source-provider/transformation implementations.

### 41.4 Architecture Verification

Compile-time/module checks, static analysis, lints, or architecture tests enforce dependency and technology-isolation rules where practical.

### 41.5 CI

The primary CI job runs `just check`. Targeted native jobs add OS-specific evidence according to CONV-REPO-001.

Live-service, E2E, stress, fuzz, or milestone jobs are separate unless explicitly promoted into the standard gate.

### 41.6 Review

Review covers requirements that are difficult to automate, including:

- whether the chosen test boundary is unnecessarily broad;
- whether a fixture is safe and legitimately canonical;
- whether a snapshot/golden update is semantically intentional;
- whether manual verification is still justified;
- whether a quarantine remains necessary;
- whether a new dependency/test framework is justified;
- whether coverage is proving requirements rather than implementation details.

## 42. Exceptions

Exceptions use the lightest durable mechanism that preserves verification integrity.

1. A test may require serialization/exclusive execution only when a real process-global/native resource requires it; the reason is documented and scope minimized.
2. A temporary flaky-test quarantine follows Section 31 and does not count as verified coverage.
3. A live/provider/native/milestone test may require environment-specific prerequisites when it is explicitly outside `just test`/platform-neutral `just check`.
4. A historical fixture correction requires explicit compatibility rationale and review.
5. A manual criterion may remain manual when automation cost/reliability is currently disproportionate; evidence remains explicit.
6. A durable exception that changes the meaning of `just test`, deterministic offline gating, fixture privacy, or completion evidence requires updating this convention and any affected higher-level documentation.

## 43. Acceptance Criteria

CONV-TEST-001 is satisfied by the repository and an applicable implementation slice when:

1. `just test` has one documented meaning: the complete deterministic platform-neutral offline automated test set applicable to implemented slices.
2. `just check` includes the canonical test set plus formatting, lint/static analysis, generated-source freshness, architecture verification, and other adopted repository checks.
3. Ordinary required tests require no public network, provider credentials, developer application data, or ROM/BIOS collections.
4. Test layers use the lowest faithful boundary and broad E2E tests are not used reflexively.
5. Unit tests cover focused pure/state-machine behavior where appropriate.
6. Reusable contract suites cover interchangeable implementations where the owning specification requires them.
7. Persistence/transaction/migration behavior uses real isolated SQLite where SQLite semantics matter.
8. Historical supported-schema fixtures are immutable compatibility evidence unless explicitly corrected with rationale.
9. Tests own mutable databases/filesystems/resources and do not rely on execution order.
10. Required async/concurrency tests synchronize on meaningful state/events rather than arbitrary sleeps.
11. Tests support parallel execution except for explicitly justified process-global/native resources.
12. Synthetic fixtures are preferred unless a durable canonical fixture has a real compatibility/regression purpose.
13. Canonical fixtures have clear ownership and discoverable scenario intent.
14. Provider recorded fixtures are sanitized and ordinary provider tests do not require live services.
15. Bridge snapshots/fixtures are reviewed as semantic contracts rather than auto-accepted output.
16. Golden tests remain selective and changed baselines receive visual review.
17. Committed fixtures contain no secrets, private user data, unlicensed ROM/BIOS/artwork content, or personally identifying machine state.
18. Test doubles use existing architectural seams and do not distort production architecture.
19. Architecture rules use compile/static/lint enforcement where possible and architecture tests where needed.
20. Bug fixes normally add a regression at the lowest faithful reproducing boundary.
21. Specification-required scenarios are mapped to explicit automated or manual evidence.
22. Required flaky tests are fixed; blind retries do not define pass status.
23. Any temporary quarantine is visible, tracked, narrowly scoped, and not counted as verified behavior.
24. Manual verification identifies scenario, expectation, environment when relevant, and actual outcome.
25. CI failure artifacts comply with repository privacy/security rules.
26. No global numeric coverage threshold is required unless separately adopted from demonstrated project value.
27. Fuzz/property/stress/performance tests are reproducible and remain distinct from ordinary correctness evidence unless deliberately promoted.
28. Milestone-critical E2E/demonstration scenarios pass before the applicable milestone is claimed complete.
29. Applicable native-platform requirements receive targeted native CI/test evidence.
30. A completed implementation slice has behavior-specific tests/checks, canonical verification, and any additional native/milestone evidence required by its owning specification.

## 44. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../architecture/architecture-overview.md)
- [PHASE-000 — Foundation](../phases/phase-000-foundation.md)
- [SPEC-BE-002 — SQLite, Migrations, Repositories, and Unit of Work](../specifications/backend/spec-be-002-sqlite-migrations-repositories-and-unit-of-work.md)
- [SPEC-BE-003 — Application Errors, Logging, Diagnostics, and Observability](../specifications/backend/spec-be-003-application-errors-logging-and-diagnostics.md)
- [SPEC-BE-004 — Application Runtime, Command Pipeline, and Background Operations](../specifications/backend/spec-be-004-application-runtime-command-pipeline-and-background-operations.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-010 — Provider Gateway Architecture](../specifications/backend/spec-be-010-provider-gateway-architecture.md)
- [SPEC-BE-011 — Source Provider and Indexing Contract](../specifications/backend/spec-be-011-source-provider-and-indexing-contract.md)
- [SPEC-BE-012 — Transformation and Hash-Scheme Contract](../specifications/backend/spec-be-012-transformation-and-hash-scheme-contract.md)
- [SPEC-FE-007 — Design-System Foundation and Accessibility Baseline](../specifications/frontend/spec-fe-007-design-system-foundation-and-accessibility-baseline.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-RUST-001 — Rust Coding and Test Conventions](conv-rust-001-rust-coding-and-test-conventions.md)
- [CONV-FLUTTER-001 — Flutter/Dart Coding and Test Conventions](conv-flutter-001-flutter-dart-coding-and-test-conventions.md)
- [Convention Template](../templates/convention.md)
