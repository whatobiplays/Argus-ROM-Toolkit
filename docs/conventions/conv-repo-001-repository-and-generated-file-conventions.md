# Repository and Generated-File Conventions

**Document ID:** CONV-REPO-001  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-09  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, SPEC-BE-001, SPEC-BE-008  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This convention defines the repeatable repository, toolchain, automation, generated-file, and repository-hygiene rules for Argus ROM Toolkit.

Its purpose is to make a clean checkout self-describing and reproducible for Daniel, Codex, CI, and future contributors without turning repository automation into a second build system.

This convention owns repository-wide engineering rules. Rust code style, Flutter/Dart code style, test strategy, and documentation/Codex-result rules belong to their dedicated conventions.

## 2. Core Invariant

> **A clean Argus checkout is self-describing and reproducible: committed files define the required project state, generated source can be recreated deterministically, machine-local state is disposable, and canonical workflows execute through a small, explicit `just` interface over pinned toolchains.**

## 3. Canonical Repository Shape

The repository uses the following top-level responsibilities:

```text
/
├── .github/
│   └── workflows/
├── docs/
├── flutter/
│   ├── .fvmrc
│   ├── pubspec.yaml
│   └── pubspec.lock
├── rust/
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── crates/
├── scripts/
├── justfile
├── rust-toolchain.toml
├── .gitattributes
├── .gitignore
└── README.md
```

Rules:

1. `rust/` is the Rust workspace root defined by SPEC-BE-001.
2. `flutter/` is the Flutter application root.
3. `docs/` follows ARCH-002 and is the durable engineering source of truth.
4. `.github/` owns GitHub-hosted CI and workflow configuration.
5. `scripts/` contains repository automation that is too substantial to remain directly in the `justfile`.
6. The repository root remains shallow and composition-oriented.
7. Feature-specific source belongs under `rust/` or `flutter/`, not in parallel top-level feature trees.
8. A new top-level directory requires a concrete repository responsibility.
9. Empty speculative directory trees are prohibited.
10. Symlink-dependent repository behavior is avoided when a normal file or directory structure can express the same requirement, because canonical workflows must remain predictable on Windows as well as Unix-like systems.

## 4. Required Developer Tooling

Canonical development assumes these globally available prerequisites:

```text
Git
just
rustup
FVM
Bash
platform-native build prerequisites
```

These are developer-machine prerequisites rather than dependencies that Argus installs globally.

On Windows, **Git Bash is the documented canonical Bash environment for Argus repository automation**. WSL or another Bash environment may be used personally when compatible, but repository instructions and CI assumptions must not require WSL.

Platform-native prerequisites such as compilers, SDKs, signing tools, or desktop build support are documented by the applicable implementation/release instructions. Repository automation may validate them but does not silently install or reconfigure them.

## 5. Toolchain Pinning

Project toolchain versions are explicit repository state.

### 5.1 Rust

The Rust toolchain is pinned through the committed root `rust-toolchain.toml` file.

Canonical Rust commands run under that project toolchain. A developer's unrelated global default Rust toolchain must not change Argus build or verification semantics.

The Rust workspace commits one lockfile:

```text
rust/Cargo.lock
```

### 5.2 Flutter and Dart

The Flutter SDK is pinned through committed FVM project configuration under the Flutter application root.

Dart is not independently pinned from Flutter for the application toolchain; the Dart SDK distributed with the selected Flutter SDK is authoritative for Flutter application work.

The Flutter application commits its application dependency lockfile:

```text
flutter/pubspec.lock
```

### 5.3 Upgrade Rule

Changing a pinned toolchain version is an intentional repository change.

A toolchain upgrade must regenerate and verify any committed source whose output can depend on that toolchain or associated generators. Incidental local upgrades must not alter canonical repository behavior.

Exact tool versions are selected and updated by the applicable implementation slice or explicit maintenance change; this convention fixes the pinning mechanism and reproducibility requirement.

## 6. Canonical Repository Command Interface

`just` is a required developer tool and the canonical root-level orchestration interface.

Cargo, Flutter, Dart, `flutter_rust_bridge`, Git, and other native tools remain the underlying build and development tools. `just` composes them; it does not replace their build systems or dependency graphs.

The initial canonical recipe vocabulary is:

```text
just bootstrap
just generate
just check-generated
just format
just lint
just test
just check
```

Additional recipes may be introduced when they represent a stable repository-level workflow. Do not add aliases merely to hide every native command.

### 6.1 `just bootstrap`

Prepares a checkout using already-installed developer prerequisites.

It may:

- install the pinned Rust project toolchain through `rustup`;
- install the pinned Flutter SDK through FVM;
- resolve or fetch project dependencies;
- prepare project-local generation prerequisites;
- validate required platform build prerequisites;
- report actionable failures when required tooling is missing.

It must not:

- install `just`, `rustup`, FVM, Git, an IDE, Xcode, Visual Studio, Android Studio, or similar global tooling;
- invoke Homebrew, `apt`, `dnf`, `pacman`, `winget`, Chocolatey, or another system package manager;
- invoke `sudo` or equivalent privilege escalation;
- modify shell profiles;
- silently alter unrelated developer-machine configuration.

Bootstrap must be safe to repeat without damaging valid local project state.

### 6.2 `just generate`

Regenerates every committed generated-source family using repository-pinned toolchains and committed generator configuration.

One canonical generation command prevents individual contributors, CI jobs, or Codex tasks from inventing different generator sequences.

### 6.3 `just check-generated`

Runs the canonical generation process and verifies that generation leaves no unexpected repository difference.

The check must detect both:

- changed tracked generated files; and
- unexpected untracked generated source that should be committed.

A stale generated-source check fails rather than silently repairing the repository and continuing.

In a local checkout, generated differences may remain visible after the failed check so the developer can inspect them. CI may discard its ephemeral workspace after reporting failure.

### 6.4 `just format`

Applies the canonical formatters to authored source and other formatter-owned repository files.

Generated files are changed only through their generator unless the generator's documented workflow itself includes formatting.

### 6.5 `just lint`

Runs the repository's static-analysis and lint checks, including ShellCheck for repository Bash scripts and language-specific checks established by the Rust and Flutter/Dart conventions.

### 6.6 `just test`

Runs the canonical platform-neutral test set defined by CONV-TEST-001 and the applicable implementation slice.

Platform-specific suites may have additional explicit recipes or CI jobs when they cannot reasonably run everywhere.

### 6.7 `just check`

`just check` is the canonical local quality gate and the CI-equivalent entry point for platform-neutral verification.

It composes the applicable checks for:

- formatting;
- lint/static analysis;
- Rust tests;
- Flutter tests;
- architecture/dependency-boundary verification;
- generated-source freshness;
- other repository-wide correctness checks explicitly adopted later.

A documented native command may still be run directly for focused development or debugging. Direct native commands do not become a competing canonical root workflow.

## 7. Bash Automation

Bash is the canonical scripting environment for repository automation that exceeds simple `just` orchestration.

### 7.1 Script Boundary

Short command composition belongs in `justfile`.

Substantial branching, loops, filesystem manipulation, repeated error handling, or multi-step orchestration belongs in focused scripts under:

```text
scripts/*.sh
```

The `justfile` must not become a collection of large embedded shell programs.

### 7.2 Script Requirements

Repository Bash scripts must:

- use Bash explicitly rather than relying on an unspecified `/bin/sh` implementation;
- use strict failure behavior, normally at least `set -euo pipefail`, unless a narrower behavior is deliberately required and clear from the script;
- quote variables and paths safely;
- fail with actionable messages when a prerequisite is unavailable;
- clean up temporary files/directories they create when practical;
- avoid embedding developer-machine absolute paths;
- remain compatible with the documented canonical Bash environment on every supported development platform where that script is required;
- pass ShellCheck under the repository's configured policy.

OS-specific scripts are allowed only when the underlying operation is genuinely OS-specific.

### 7.3 Prohibited Script Behavior

Repository scripts must not:

- use `sudo` or equivalent privilege escalation;
- silently install global tools or packages;
- modify shell startup files;
- overwrite user configuration outside project-owned paths;
- assume WSL on Windows;
- depend on undocumented interactive prompts for canonical CI/build/test workflows.

## 8. Generated-Source Policy

Argus commits deterministic generated source when that source participates in the repository's source/build contract.

Examples include, when adopted by the relevant specification or implementation:

- `flutter_rust_bridge` generated Rust/Dart bindings;
- Riverpod generated provider source;
- Freezed generated model source;
- JSON serialization generated source;
- other deterministic code-generation output explicitly required by the source/build contract.

This policy does not make build products or caches source artifacts.

## 9. Generated-Source Placement

Generated output follows the generator's native layout unless an explicit boundary is supported and materially improves ownership clarity.

Examples:

- Dart `part` output such as `.g.dart` or `.freezed.dart` stays adjacent to its authored source when required by the Dart generator model.
- A large generated bridge surface may live under an explicit generated boundary such as a bridge-owned `generated/` area when supported by `flutter_rust_bridge` configuration.

A single artificial repository-wide `generated/` directory is not required and must not be imposed when it fights a generator's normal layout.

Generated files should carry generator-provided `generated` or `do not edit` markers when supported. `.gitattributes` may mark generated paths/files for review tooling where useful.

## 10. Generated-Source Ownership

Generated files are read-only by convention.

A generated-file change must originate from one or more of:

1. authored source;
2. generator configuration;
3. a dependency or toolchain version change;
4. the generator implementation/version itself.

Manual edits to generated source are prohibited, including "temporary" corrections intended to be cleaned up later.

If generated output is wrong, fix its authored input, configuration, generator version, or owning contract and regenerate it.

## 11. Generated-Source Determinism

Committed generation must be reproducible from committed inputs and pinned toolchains.

Generated source must not embed avoidable machine-specific or run-specific data such as:

- absolute developer paths;
- usernames;
- nondeterministic timestamps;
- transient build directories;
- random ordering where semantic ordering is available;
- platform-specific path separators in a platform-neutral output format.

When a required third-party generator emits unavoidable nondeterministic content, the issue must be corrected, normalized through an explicitly owned deterministic generation step, or isolated by a documented exception. CI must not simply ignore arbitrary generated diffs.

## 12. Tracked and Ignored Repository State

### 12.1 Commit

Commit repository state needed to reproduce or review the project, including:

- authored source;
- governed documentation;
- project configuration;
- CI configuration;
- `justfile` and owned repository scripts;
- pinned toolchain configuration;
- application/workspace dependency lockfiles;
- required deterministic generated source;
- test fixtures that are intentionally part of the repository and comply with data/privacy rules.

### 12.2 Ignore

Do not commit disposable machine-local or build state, including:

- Rust `target/` output;
- Flutter/Dart build output;
- `.dart_tool/`;
- FVM-downloaded SDK/cache content rather than its project configuration;
- IDE caches and ordinary user-specific IDE state;
- local application databases;
- exported diagnostic bundles;
- temporary files and staging directories;
- local logs not intentionally maintained as test fixtures;
- OS metadata files;
- local secret/environment files;
- packaged binaries/installers unless a future release process explicitly defines an artifact repository policy.

Dependency vendoring is not part of the default Argus repository model. A later offline/release requirement may introduce vendoring only with an explicit ownership and update policy.

## 13. Git Attributes and Line Endings

Committed text uses LF line endings.

`.gitattributes` must establish line-ending behavior strongly enough that canonical scripts and generated-file freshness checks are not affected by a contributor's host operating system.

Bash scripts must retain executable mode in Git where they are intended to be executed directly.

Generated files or paths may be marked as generated for repository/review tooling when that improves diff presentation without hiding substantive source changes.

Do not use Git attributes to suppress correctness-relevant diffs.

## 14. Environment and Local Configuration

Canonical Phase 000 build, test, generation, and theme workflow requires no secret environment variables.

When later features need local environment configuration:

- local secret/config files remain ignored;
- a sanitized `.env.example` or equivalent may be committed when it materially improves setup;
- example files contain names, structure, and safe placeholder syntax only;
- committed examples must not contain real or realistic production credentials;
- canonical build/test correctness must not depend on undocumented local variables.

Patterns such as `.env`, `*.local.*`, or tool-specific equivalents should be ignored when adopted, except for an intentionally committed sanitized example/configuration file.

## 15. Clean-Checkout Reproducibility

A fresh checkout containing only committed repository files must be sufficient to establish a correct development state after the documented prerequisites are installed.

The canonical setup/verification sequence is:

```text
just bootstrap
just check
```

No undocumented generated file, developer-specific cache, IDE state, absolute local path, or machine-local configuration may be required for correctness.

Codex tasks and CI must be designed around this same clean-checkout assumption.

## 16. CI Policy

Argus uses tiered cross-platform CI rather than multiplying every platform-neutral check across every desktop target.

### 16.1 Canonical Quality Gate

One primary CI job runs the complete platform-neutral repository gate through:

```text
just check
```

The CI configuration may select the most appropriate primary runner platform without changing this convention, provided the platform-neutral checks remain representative and native-platform coverage below is preserved.

### 16.2 Targeted Native-Platform Validation

Targeted native-platform jobs must cover Windows and macOS behavior where platform differences materially matter. If either platform is already the primary quality-gate runner, its native checks may run in that primary job rather than a duplicate job.

Native coverage includes as applicable:

- clean bootstrap assumptions;
- Rust/Flutter native compilation;
- bridge generation/build integration;
- platform-native application build/startup smoke behavior;
- other explicitly platform-specific requirements.

Linux-specific native validation may likewise be added when Argus supports a Linux desktop target requiring behavior beyond the primary quality-gate runner.

Platform-neutral suites should not be duplicated across every OS without a demonstrated reason.

### 16.3 Failure Behavior

CI must fail when canonical verification changes tracked repository state or discovers generated source that should have been committed.

CI must not auto-format, regenerate, commit, or otherwise silently repair stale repository state and report success.

## 17. Repository Growth Rules

Repository structure grows in response to real responsibilities, not anticipated ones.

Rules:

1. Do not create empty feature directories merely to mirror a future architecture diagram.
2. Do not create a new top-level directory when an existing owned area is appropriate.
3. Do not add a second root task runner such as Make alongside `just` for the same canonical workflows.
4. Do not introduce Python, Node scripts, `xtask`, PowerShell, or another general automation layer merely to wrap existing Bash/`just` workflows.
5. A new automation technology is justified only when a concrete requirement makes the current approach materially unsuitable; the owning convention/specification must then be updated.
6. Do not introduce vendored dependency trees, generated artifact archives, or binary blobs without an explicit lifecycle and ownership policy.

## 18. Prohibited Patterns

The following patterns are prohibited:

- manually editing generated source;
- committing generated source that cannot be reproduced from committed inputs without a documented exception;
- committing stale generated output;
- committing build output or caches to make a checkout appear complete;
- using system package managers from canonical repository automation;
- invoking `sudo` or equivalent privilege escalation from repository automation;
- silently modifying shell profiles or global developer configuration;
- committing developer-machine absolute paths;
- relying on unpinned Rust or Flutter SDK versions in canonical workflows;
- requiring WSL for Windows repository automation;
- hiding substantial application or build logic inside `justfile` recipes;
- introducing Make or another competing root command interface for canonical workflows;
- requiring undocumented environment variables for normal build/test/generation behavior;
- committing secrets, credentials, private keys, personal access tokens, or secret-bearing local configuration;
- committing local application databases or user diagnostic exports;
- creating speculative empty directory structures;
- using manual generated-file edits as a substitute for fixing generator inputs or contracts.

## 19. Examples

### 19.1 Compliant: Root Orchestration

```text
just check
  -> Rust formatter/lints/tests
  -> Flutter formatter/analyzer/tests
  -> architecture checks
  -> just check-generated
```

The native tools continue to own compilation, dependency resolution, incremental builds, and their language-specific behavior.

### 19.2 Non-Compliant: Competing Build System

```text
Makefile
  -> duplicates Cargo dependency logic
  -> separately duplicates Flutter build logic
  -> becomes a second canonical interface next to just
```

This is prohibited unless the repository convention is deliberately revised for a concrete future requirement.

### 19.3 Compliant: Generator-Native Placement

```text
flutter/lib/src/features/settings/
├── appearance_settings.dart
├── appearance_settings.freezed.dart
└── appearance_settings.g.dart
```

The generated Dart `part` files remain next to their authored source because that is the generator's natural contract.

### 19.4 Compliant: Isolated Large Generated Surface

```text
flutter/lib/src/bridge/
├── generated/
└── argus_client_adapter.dart
```

The exact FRB-generated paths are selected by the bridge implementation/configuration, but generated transport types remain isolated from feature/controller/widget code as required by SPEC-BE-008.

### 19.5 Non-Compliant: Manual Generated Fix

```text
edit appearance_settings.freezed.dart by hand
commit the edit
```

The authored model or generator configuration must be corrected and `just generate` rerun instead.

### 19.6 Compliant: Bounded Bootstrap

```text
just bootstrap
  -> rustup installs repository-pinned Rust toolchain
  -> FVM installs repository-pinned Flutter SDK
  -> project dependencies are fetched
  -> native prerequisites are validated
```

### 19.7 Non-Compliant: Machine Management

```text
just bootstrap
  -> sudo apt install ...
  -> brew install ...
  -> edits ~/.bashrc
```

Argus repository automation does not own the developer's machine.

## 20. Enforcement

The convention is enforced through the strongest practical mechanism for each rule.

### 20.1 Git Configuration

`.gitignore` excludes known disposable and local-only state.

`.gitattributes` normalizes line endings and may identify generated output for review tooling.

### 20.2 Toolchain Files

`rust-toolchain.toml`, FVM project configuration, and committed lockfiles establish reproducible tool/dependency selection.

### 20.3 Repository Commands

`just check` is the canonical local/CI quality gate.

`just check-generated` verifies committed generated source freshness.

### 20.4 Static Analysis

ShellCheck validates repository Bash scripts. Language-specific linting and formatting are defined by their dedicated conventions.

### 20.5 CI

CI runs the canonical quality gate and targeted native-platform validation.

A CI verification job fails rather than silently modifying repository state into compliance.

### 20.6 Review

Review covers rules that cannot be reasonably enforced mechanically, including:

- whether a new top-level directory has a real responsibility;
- whether a new script belongs in `justfile` or `scripts/`;
- whether generated output is correctly owned;
- whether an exception is durable enough to require a convention/specification update.

## 21. Exceptions

This is a solo project; exceptions use the lightest durable mechanism that preserves clarity.

1. A temporary exception must be documented in the applicable specification, implementation slice, task, or repository change rationale.
2. A durable exception that changes repository structure, canonical tooling, generated-file ownership, or reproducibility rules requires updating this convention or the higher-level owning specification.
3. An ADR is not required for every repository exception. Use an ADR only when the rationale is architecturally durable and would otherwise be difficult to recover from the governing documents.
4. A generated-file exception must identify:
   - the owning generator or producer;
   - why normal deterministic regeneration cannot apply;
   - the canonical regeneration/update process;
   - how freshness/correctness is verified.
5. Security rules prohibiting committed secrets and privilege-escalating repository automation are not bypassed by ordinary convention exceptions.

## 22. Acceptance Criteria

CONV-REPO-001 is satisfied by an implementation slice when all applicable conditions are true:

1. The root repository layout follows the responsibilities defined here.
2. Rust and Flutter application roots are `rust/` and `flutter/`.
3. `just` is the documented canonical root command interface.
4. `rust-toolchain.toml` pins the project Rust toolchain.
5. FVM configuration pins the project Flutter SDK.
6. Rust and Flutter application lockfiles are committed.
7. `just bootstrap` obeys the bounded-bootstrap policy.
8. `just generate` regenerates all committed generated-source families in scope.
9. `just check-generated` detects stale tracked and unexpected untracked generated source.
10. Generated source is committed only when it participates in the source/build contract.
11. Generated files are not manually edited.
12. Generator-native placement is preserved unless an explicit supported generated boundary is preferable.
13. Generated source is deterministic from committed inputs and pinned toolchains, or an explicit exception exists.
14. Build products, caches, local databases, diagnostics, secrets, and machine-local state are ignored.
15. Text line endings are normalized to LF.
16. Repository Bash scripts are ShellCheck-clean under the configured policy.
17. Git Bash is sufficient for canonical Windows repository scripting workflows.
18. `just check` is the canonical platform-neutral quality gate.
19. CI runs the canonical gate and targeted native-platform validation.
20. CI fails on stale generated or formatter-owned committed source rather than silently repairing it.
21. No second root task runner competes with `just` for canonical workflows.
22. A clean checkout can be prepared and verified through the documented `just bootstrap` and `just check` flow after global prerequisites are installed.

## 23. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../phases/phase-000-foundation.md)
- [SPEC-BE-001 — Rust Workspace and Module Boundaries](../specifications/backend/spec-be-001-rust-workspace-and-module-boundaries.md)
- [SPEC-BE-008 — Rust-to-Flutter Bridge DTO Contract](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [Convention Template](../templates/convention.md)
