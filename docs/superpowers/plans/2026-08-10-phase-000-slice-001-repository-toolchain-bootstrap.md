# Phase 000 Slice 001 — Repository and Toolchain Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible Rust/Flutter repository skeleton with pinned project toolchains, canonical `just` workflows, baseline cross-platform CI, and no application behavior.

**Architecture:** This slice creates the repository and build-system boundaries defined by CONV-REPO-001, SPEC-BE-001, and SPEC-FE-001 without implementing startup, persistence, routing, state management, or bridge behavior. Rust is a five-crate workspace whose active dependency edges are declared in Cargo manifests and checked by the canonical repository gate; Flutter is one desktop application package with only a toolchain smoke surface. Root automation composes native tools rather than replacing them.

**Tech Stack:** Rust 1.97.1, Cargo resolver 3 / Rust 2024 edition, Flutter 3.44.7 with Dart 3.12.x through FVM, Flutter Material dependencies only, `flutter_lints` 6.x baseline, Bash, ShellCheck, `just`, GitHub Actions.

**Re-evaluation baseline:** Revalidated on 2026-08-11 against the committed governed-document set at HEAD `80e38d73f59daf0a75a1286658572085342d7cb1`. This plan is subordinate to PHASE-000 and the governing architecture/specifications/conventions; later Ready contracts constrain compatibility but do not expand Slice 001 scope.

## Global Constraints

- This plan implements only `SLICE-P00-001 — Repository and Toolchain Bootstrap`; it introduces no Argus application behavior.
- Executable scope is the intersection of `PHASE-000`, `SLICE-P00-001`, the current Codex task contract below, and governing documents. A broader Ready specification never authorizes work outside that intersection.
- Do not introduce deferred Phase 000 or later-MVP scaffolding: no persisted jobs, `BackgroundOperationManager`, operation-handle DTOs/events, resource scheduling, provider/source/indexing/transformation modules, future-feature routes, bridge DTOs/bindings, or placeholder feature trees.
- Preserve unrelated dirty/untracked work. Each Codex task may inspect and edit only the paths its task contract authorizes; this plan file is reference-only during implementation unless Daniel separately authorizes changing it.
- Pin Rust through root `rust-toolchain.toml`; selected pin: `1.97.1`.
- Pin Flutter through `flutter/.fvmrc`; selected pin: `3.44.7`. Dart is the SDK shipped with that Flutter release.
- FVM is a global developer prerequisite; CI activates FVM `4.1.2` explicitly for reproducibility.
- `just` is the sole canonical root task interface. Required recipes: `bootstrap`, `generate`, `check-generated`, `format`, `lint`, `test`, `check`.
- `just check` must be non-mutating. `just format` is the only canonical formatting recipe that intentionally rewrites authored source.
- Rust canonical verification is `cargo fmt --check`, `cargo clippy --workspace --all-targets --all-features -- -D warnings`, and `cargo test --workspace --all-features` through root recipes.
- Flutter canonical verification is `dart format --output=none --set-exit-if-changed`, `flutter analyze`, and `flutter test` through FVM/root recipes.
- Bash scripts use `set -euo pipefail` and must be ShellCheck-clean.
- Windows repository automation must work in Git Bash and must not require WSL.
- Bootstrap may install project-pinned Rust/Flutter SDKs through already-installed `rustup`/FVM, but must not install global tools, invoke a system package manager, use privilege escalation, or modify shell profiles.
- Generated-source recipes are intentionally no-op in this slice because no generated-source family exists yet; the recipes must already exist so later slices have one canonical registration point.
- Commit Rust `Cargo.lock`, Flutter `pubspec.lock`, `.fvmrc`, native Flutter runner source, and deterministic project configuration. Ignore SDK caches/build output, including `flutter/.fvm/`.
- The Flutter package targets desktop runners only in this slice: Windows, macOS, and Linux.
- Flutter scaffolding uses `dev.argusromtoolkit` only as the repository-local organization value required to generate deterministic native runner identifiers. It is not an approved production/release bundle identity; packaging, signing, installers, and release distribution remain outside Phase 000.
- Do not create empty speculative feature/module directory trees. Create only files required for the workspace/toolchain contract.
- Do not introduce Riverpod, Freezed, `go_router`, `flutter_rust_bridge`, SQLite, tracing, or any other application dependency in this slice.
- Git commits remain user-controlled. Every task below has a commit checkpoint, but the implementing agent must not stage or commit unless Daniel explicitly authorizes that Git write.

## Version Selection Basis

The implementation plan fixes versions rather than leaving moving-channel inputs:

- Rust `1.97.1` is the selected Slice 001 project pin.
- Flutter `3.44.7` is the selected Slice 001 project pin; Dart is the SDK bundled with that Flutter release.
- FVM `4.1.2` is used only as the CI-installed version manager; the project Flutter version remains owned by `.fvmrc`.
- `just` `1.58.0` is pinned in CI setup for deterministic hosted-runner behavior; developer `just` remains a global prerequisite per CONV-REPO-001.
- These are intentional repository-plan selections. Changing them during execution is a dependency/toolchain upgrade and is outside a task unless Daniel explicitly revises the plan or task authority.

## Global Codex Execution and Result Contract

Every task below is a bounded Codex task under `PHASE-000` / `SLICE-P00-001` even though this plan groups them in one file.

For every task:

1. Read the task's `Inspect first` paths before editing.
2. Edit only its `Allowed paths`; `Forbidden paths` remain out of scope even when an adjacent cleanup looks useful.
3. Implement only the stated `Deliverable` and `Include` items. `Exclude` items are explicit non-goals.
4. If a committed governing document contains an unambiguous defect that blocks the task, correct it only when that document is explicitly allowed by the task. Otherwise report the conflict instead of widening scope.
5. Preserve unrelated dirty/untracked work and do not restore/reset/stash another actor's changes.
6. Report every required verification command as `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED` with its exact executed scope.
7. Result reporting must include: material changed paths, acceptance-criterion status/evidence, verification command statuses, non-trivial deviations, documentation impact, current Git state, and any remaining blocker/follow-up relevant to the task.
8. A suggested commit checkpoint is a review boundary only. Do not stage, commit, amend, restore, reset, or push unless Daniel's current instruction explicitly authorizes that Git mutation.

---

## File Structure Produced by This Slice

```text
/
├── .github/
│   └── workflows/
│       └── ci.yml
├── docs/
│   └── ... existing governed documentation
├── flutter/
│   ├── .fvmrc
│   ├── .metadata
│   ├── analysis_options.yaml
│   ├── lib/
│   │   └── main.dart
│   ├── test/
│   │   └── workspace_smoke_test.dart
│   ├── linux/                 # generated by Flutter
│   ├── macos/                 # generated by Flutter
│   ├── windows/               # generated by Flutter
│   ├── pubspec.yaml
│   └── pubspec.lock
├── rust/
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── crates/
│       ├── argus-domain/
│       │   ├── Cargo.toml
│       │   └── src/lib.rs
│       ├── argus-application/
│       │   ├── Cargo.toml
│       │   └── src/lib.rs
│       ├── argus-infrastructure/
│       │   ├── Cargo.toml
│       │   └── src/lib.rs
│       ├── argus-runtime/
│       │   ├── Cargo.toml
│       │   └── src/lib.rs
│       └── argus-bridge/
│           ├── Cargo.toml
│           └── src/lib.rs
├── scripts/
│   ├── bootstrap.sh
│   └── check_rust_dependencies.sh
├── .gitattributes
├── .gitignore                 # existing file; add FVM cache rule only
├── justfile
├── README.md
└── rust-toolchain.toml
```

No feature directories under `flutter/lib/app`, `flutter/lib/core`, or `flutter/lib/features` are created until their implementation slices begin.

---

### Task 1: Pin Project Toolchains and Repository Text/Ignore Policy

**Files:**
- Create: `rust-toolchain.toml`
- Create: `.gitattributes`
- Modify: `.gitignore`
- Modify: `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`

**Interfaces:**
- Consumes: existing repository/Git conventions.
- Produces: exact Rust pin `1.97.1`, committed LF policy, ignored FVM SDK/cache state, and an explicit ShellCheck developer prerequisite used by Task 4.

**Codex task contract:**
- Parent: `PHASE-000` / `SLICE-P00-001`.
- Inspect first: `.gitignore`, `docs/phases/phase-000-foundation.md`, `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`, `docs/conventions/conv-rust-001-rust-coding-and-test-conventions.md`, `docs/conventions/conv-doc-001-documentation-and-codex-result-conventions.md`.
- Allowed paths: `rust-toolchain.toml`, `.gitattributes`, `.gitignore`, `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`.
- Forbidden paths: all other repository paths, including this plan file.
- Deliverable: reproducible project toolchain/text-policy prerequisites for later Slice 001 tasks plus the narrow ShellCheck prerequisite documentation correction.
- Include: Rust pin, LF policy, FVM cache ignore, ShellCheck prerequisite list correction.
- Exclude: workspace/crate creation, Flutter scaffold creation, CI, application dependencies, application behavior, and unrelated documentation cleanup.
- Acceptance criteria: the exact pin is parseable, LF policy is effective, `.fvm/` is ignored without ignoring `.fvmrc`, and the canonical developer-prerequisite list names ShellCheck because `just lint` requires it.
- Verification/result reporting: run Step 6 and report it under the Global Codex Execution and Result Contract.

- [ ] **Step 1: Verify the repository currently lacks committed toolchain/text-policy files**

Run:

```bash
test ! -e rust-toolchain.toml
test ! -e .gitattributes
```

Expected: both commands exit `0` before implementation. If either file already exists when execution begins, inspect it and reconcile this task rather than overwriting blindly.

- [ ] **Step 2: Create the pinned Rust toolchain file**

Create `rust-toolchain.toml`:

```toml
[toolchain]
channel = "1.97.1"
profile = "minimal"
components = ["clippy", "rustfmt"]
```

- [ ] **Step 3: Create repository text normalization policy**

Create `.gitattributes`:

```gitattributes
* text=auto eol=lf

*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.ico binary
*.icns binary
*.zip binary
```

- [ ] **Step 4: Ignore FVM-downloaded SDK/cache state without ignoring `.fvmrc`**

Add under the Flutter/Dart section of `.gitignore`:

```gitignore
# FVM project cache/SDK state. The root Flutter pin lives in flutter/.fvmrc.
.fvm/
**/.fvm/
```

Do not ignore `.fvmrc` or `pubspec.lock`.

- [ ] **Step 5: Align the documented developer prerequisites with canonical lint behavior**

In `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`, change the required tooling list from:

```text
Git
just
rustup
FVM
Bash
platform-native build prerequisites
```

to:

```text
Git
just
rustup
FVM
Bash
ShellCheck
platform-native build prerequisites
```

This is a consistency correction: `just lint` is already required to run ShellCheck, so a clean developer environment must list it as a prerequisite.

Because this materially corrects a governed convention, also change that document's `Last Updated` value to `2026-08-11` in the same edit, as required by CONV-DOC-001.

- [ ] **Step 6: Verify the pin and ignore rules**

Run:

```bash
grep -F 'channel = "1.97.1"' rust-toolchain.toml
grep -F '.fvm/' .gitignore
grep -F 'ShellCheck' docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md
git check-attr eol -- docs/phases/phase-000-foundation.md
```

Expected:

```text
channel = "1.97.1"
.fvm/
ShellCheck
...: eol: lf
```

- [ ] **Step 7: Commit checkpoint — only after explicit Daniel authorization**

Suggested commit message:

```text
build: pin project toolchains and repository text policy
```

Do not stage or commit without explicit authorization.

---

### Task 2: Create the Five-Crate Rust Workspace Skeleton

**Files:**
- Create: `rust/Cargo.toml`
- Create: `rust/Cargo.lock`
- Create: `rust/crates/argus-domain/Cargo.toml`
- Create: `rust/crates/argus-domain/src/lib.rs`
- Create: `rust/crates/argus-application/Cargo.toml`
- Create: `rust/crates/argus-application/src/lib.rs`
- Create: `rust/crates/argus-infrastructure/Cargo.toml`
- Create: `rust/crates/argus-infrastructure/src/lib.rs`
- Create: `rust/crates/argus-runtime/Cargo.toml`
- Create: `rust/crates/argus-runtime/src/lib.rs`
- Create: `rust/crates/argus-bridge/Cargo.toml`
- Create: `rust/crates/argus-bridge/src/lib.rs`

**Interfaces:**
- Consumes: Rust `1.97.1` from Task 1 and SPEC-BE-001 dependency direction.
- Produces: compilable crates named `argus-domain`, `argus-application`, `argus-infrastructure`, `argus-runtime`, and `argus-bridge` with only the allowed Argus crate dependency edges.

**Codex task contract:**
- Parent: `PHASE-000` / `SLICE-P00-001`.
- Inspect first: `rust-toolchain.toml`, `docs/phases/phase-000-foundation.md`, `docs/specifications/backend/spec-be-001-rust-workspace-and-module-boundaries.md`, `docs/conventions/conv-rust-001-rust-coding-and-test-conventions.md`.
- Allowed paths: `rust/Cargo.toml`, `rust/Cargo.lock`, and the five crate manifests/`src/lib.rs` files listed under this task's Files section.
- Forbidden paths: all Flutter, CI, scripts, governed docs, feature/module trees, and this plan file.
- Deliverable: the five-crate compile-only Rust workspace boundary with centralized handwritten-Rust lint policy.
- Include: exact five members, allowed Argus dependency direction, one workspace lockfile, `unsafe_code = "deny"` inherited by all five handwritten crates.
- Exclude: application/domain feature modules, SQLite, runtime behavior, startup, events, bridge DTOs/FRB, background-operation infrastructure, provider/indexing/transformation code, and third-party Rust dependencies.
- Acceptance criteria: Cargo metadata contains exactly five workspace packages, all five inherit workspace lints, all allowed edges point inward, canonical Rust format/clippy/tests pass, and no crate-local lockfile exists.
- Verification/result reporting: run Step 9 and report it under the Global Codex Execution and Result Contract.

- [ ] **Step 1: Write the workspace manifest before creating member manifests**

Create `rust/Cargo.toml`:

```toml
[workspace]
members = [
    "crates/argus-domain",
    "crates/argus-application",
    "crates/argus-infrastructure",
    "crates/argus-runtime",
    "crates/argus-bridge",
]
resolver = "3"

[workspace.package]
version = "0.1.0"
edition = "2024"
rust-version = "1.97.1"
license = "GPL-3.0-only"
publish = false

[workspace.lints.rust]
unsafe_code = "deny"
```

- [ ] **Step 2: Run Cargo metadata and verify the intended failure**

Run:

```bash
cargo metadata --manifest-path rust/Cargo.toml --no-deps
```

Expected: FAIL because the listed member manifests do not exist yet. This proves the next step is establishing the workspace members rather than testing an unrelated global Cargo workspace.

- [ ] **Step 3: Create `argus-domain`**

Create `rust/crates/argus-domain/Cargo.toml`:

```toml
[package]
name = "argus-domain"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
```

Create `rust/crates/argus-domain/src/lib.rs`:

```rust
//! Stable Argus domain vocabulary and business rules.
```

- [ ] **Step 4: Create `argus-application`**

Create `rust/crates/argus-application/Cargo.toml`:

```toml
[package]
name = "argus-application"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
argus-domain = { path = "../argus-domain" }
```

Create `rust/crates/argus-application/src/lib.rs`:

```rust
//! Argus application use cases and required ports.
```

- [ ] **Step 5: Create `argus-infrastructure`**

Create `rust/crates/argus-infrastructure/Cargo.toml`:

```toml
[package]
name = "argus-infrastructure"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
argus-application = { path = "../argus-application" }
argus-domain = { path = "../argus-domain" }
```

Create `rust/crates/argus-infrastructure/src/lib.rs`:

```rust
//! Concrete Argus technical adapters.
```

- [ ] **Step 6: Create `argus-runtime`**

Create `rust/crates/argus-runtime/Cargo.toml`:

```toml
[package]
name = "argus-runtime"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
argus-application = { path = "../argus-application" }
argus-domain = { path = "../argus-domain" }
argus-infrastructure = { path = "../argus-infrastructure" }
```

Create `rust/crates/argus-runtime/src/lib.rs`:

```rust
//! Argus runtime composition and lifecycle boundary.
```

- [ ] **Step 7: Create `argus-bridge`**

Create `rust/crates/argus-bridge/Cargo.toml`:

```toml
[package]
name = "argus-bridge"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
argus-runtime = { path = "../argus-runtime" }
```

Create `rust/crates/argus-bridge/src/lib.rs`:

```rust
//! Flutter-facing Argus bridge boundary.
```

Do not add FRB yet; this crate is only the architectural boundary in Slice 001.

- [ ] **Step 8: Generate the single committed workspace lockfile**

Run:

```bash
cargo generate-lockfile --manifest-path rust/Cargo.toml
```

Expected: `rust/Cargo.lock` is created; no crate-local `Cargo.lock` files appear.

- [ ] **Step 9: Verify all five crates compile and the manifests express only allowed edges**

Run:

```bash
cargo metadata --manifest-path rust/Cargo.toml --no-deps --locked
cargo test --manifest-path rust/Cargo.toml --workspace --all-features --locked
cargo clippy --manifest-path rust/Cargo.toml --workspace --all-targets --all-features --locked -- -D warnings
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
grep -F '[workspace.lints.rust]' rust/Cargo.toml
grep -F 'unsafe_code = "deny"' rust/Cargo.toml
for manifest in rust/crates/*/Cargo.toml; do
  grep -F '[lints]' "$manifest"
  grep -F 'workspace = true' "$manifest"
done
find rust/crates -name Cargo.lock -print
```

Expected:

- metadata lists exactly the five `argus-*` packages above;
- tests/clippy/format exit `0`;
- the workspace denies handwritten unsafe Rust and every crate inherits that lint policy;
- the final `find` command prints nothing.

- [ ] **Step 10: Commit checkpoint — only after explicit Daniel authorization**

Suggested commit message:

```text
build: add Rust workspace skeleton
```

Do not stage or commit without explicit authorization.

---

### Task 3: Create the Minimal Flutter Desktop Workspace

**Files:**
- Create: `flutter/.fvmrc`
- Create/generated: `flutter/.metadata`
- Create: `flutter/pubspec.yaml`
- Create: `flutter/pubspec.lock`
- Create: `flutter/analysis_options.yaml`
- Create: `flutter/lib/main.dart`
- Create: `flutter/test/workspace_smoke_test.dart`
- Create/generated: `flutter/windows/**`
- Create/generated: `flutter/macos/**`
- Create/generated: `flutter/linux/**`
- Transient scaffold output to delete if emitted: `flutter/.gitignore`, `flutter/README.md`, `flutter/test/widget_test.dart`

**Interfaces:**
- Consumes: Flutter `3.44.7` pin and FVM prerequisite.
- Produces: one analyzable/testable desktop Flutter package named `argus`, with no Riverpod/router/bridge/application behavior.

**Codex task contract:**
- Parent: `PHASE-000` / `SLICE-P00-001`.
- Inspect first: `docs/phases/phase-000-foundation.md`, `docs/specifications/frontend/spec-fe-001-flutter-project-structure-and-feature-boundaries.md`, `docs/conventions/conv-flutter-001-flutter-dart-coding-and-test-conventions.md`, `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`.
- Allowed paths: `flutter/.fvmrc`, `flutter/.metadata`, `flutter/pubspec.yaml`, `flutter/pubspec.lock`, `flutter/analysis_options.yaml`, `flutter/lib/main.dart`, `flutter/test/workspace_smoke_test.dart`, generated `flutter/windows/**`, `flutter/macos/**`, `flutter/linux/**` runner files, and transient scaffold output `flutter/.gitignore`, `flutter/README.md`, `flutter/test/widget_test.dart` only for deletion if emitted.
- Forbidden paths: `flutter/lib/app/**`, `flutter/lib/core/**`, `flutter/lib/features/**`, `flutter/android/**`, `flutter/ios/**`, `flutter/web/**`, all Rust/CI/docs/scripts paths, and this plan file.
- Deliverable: one desktop-only Flutter package that proves the pinned SDK, analyzer, test harness, and native runner scaffolds without implementing Argus application structure yet.
- Include: exact Flutter pin, strict analyzer modes, behavior-free `main.dart`, one workspace smoke test, Windows/macOS/Linux runners.
- Exclude: Riverpod, Freezed, `go_router`, `build_runner`, FRB, JSON codegen, app/core/features ownership trees, routes, shell, settings, startup, diagnostics UI, future destinations, and production packaging identity decisions.
- Acceptance criteria: pub resolution/analyze/test/full-package format checks pass, only desktop runner directories exist, authored Dart source is exactly the two files named above, and FVM cache state remains ignored.
- Verification/result reporting: run Steps 8-9 and report them under the Global Codex Execution and Result Contract.

- [ ] **Step 1: Create the FVM pin**

Create `flutter/.fvmrc`:

```json
{
  "flutter": "3.44.7"
}
```

- [ ] **Step 2: Install the pinned SDK and generate only desktop platform runners**

Run:

```bash
cd flutter
fvm install
fvm flutter create \
  --empty \
  --platforms=windows,macos,linux \
  --project-name=argus \
  --org=dev.argusromtoolkit \
  .
rm -f .gitignore README.md test/widget_test.dart
```

Expected: Flutter generates the package plus Windows/macOS/Linux runners, then scaffold-local boilerplate not owned by the final Slice 001 repository contract is removed. No Android, iOS, web runner, nested Flutter README, nested Flutter `.gitignore`, or generated sample widget-test file remains.

`dev.argusromtoolkit` is a scaffold-only organization value for deterministic generated runner identifiers. Do not describe or treat it as an approved public release/bundle identity.

- [ ] **Step 3: Replace the generated pubspec with the minimal governed dependency surface**

Set `flutter/pubspec.yaml` to:

```yaml
name: argus
description: Argus ROM Toolkit Flutter application.
publish_to: none
version: 0.1.0+1

environment:
  sdk: ^3.12.0
  flutter: 3.44.7

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

Do not add state-management, routing, code-generation, serialization, or bridge packages yet.

- [ ] **Step 4: Set the analyzer baseline**

Set `flutter/analysis_options.yaml` to:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

- [ ] **Step 5: Replace generated sample application code with a behavior-free compile entry point**

Set `flutter/lib/main.dart` to:

```dart
import 'package:flutter/widgets.dart';

void main() => runApp(const SizedBox.shrink());
```

This deliberately proves the Flutter engine/application package compiles without introducing shell, routing, settings, startup, or design-system behavior before their slices.

- [ ] **Step 6: Replace any generated sample widget test with a workspace smoke test**

Set `flutter/test/workspace_smoke_test.dart` to:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter test harness is operational', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    expect(find.byType(SizedBox), findsOneWidget);
  });
}
```

Delete the generated counter/sample test if Flutter created one.

- [ ] **Step 7: Resolve and commit the Flutter lockfile**

Run:

```bash
cd flutter
fvm flutter pub get
```

Expected: `flutter/pubspec.lock` exists and is based on the pinned Flutter/Dart toolchain.

- [ ] **Step 8: Verify the minimal Flutter package**

Run:

```bash
cd flutter
fvm flutter pub get --enforce-lockfile
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze
fvm flutter test
```

Expected: all commands exit `0`.

- [ ] **Step 9: Verify the generated platform scope and ignored FVM cache**

Run from repository root:

```bash
test -d flutter/windows
test -d flutter/macos
test -d flutter/linux
test ! -d flutter/android
test ! -d flutter/ios
test ! -d flutter/web
test ! -e flutter/README.md
test ! -e flutter/.gitignore
test ! -e flutter/test/widget_test.dart
git check-ignore flutter/.fvm || true
git check-ignore flutter/.fvm/flutter_sdk || true
```

Expected: Windows/macOS/Linux checks succeed; mobile/web directories are absent; FVM-local cache paths are ignored when present.

- [ ] **Step 10: Commit checkpoint — only after explicit Daniel authorization**

Suggested commit message:

```text
build: add Flutter desktop workspace skeleton
```

Do not stage or commit without explicit authorization.

---

### Task 4: Add Canonical Bootstrap and Root `just` Workflows

**Files:**
- Create: `scripts/bootstrap.sh`
- Create: `scripts/check_rust_dependencies.sh`
- Create: `justfile`

**Interfaces:**
- Consumes: `rust-toolchain.toml`, `flutter/.fvmrc`, the Rust/Flutter workspaces from Tasks 2–3, and globally installed Git/just/rustup/FVM/Bash/ShellCheck.
- Produces: canonical repository commands required by CONV-REPO-001.

**Codex task contract:**
- Parent: `PHASE-000` / `SLICE-P00-001`.
- Inspect first: `rust-toolchain.toml`, `flutter/.fvmrc`, `rust/Cargo.toml`, `flutter/pubspec.yaml`, `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`, `docs/conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md`.
- Allowed paths: `scripts/bootstrap.sh`, `scripts/check_rust_dependencies.sh`, `justfile`.
- Forbidden paths: application source/manifests, CI, governed docs, generated-source trees, and this plan file.
- Deliverable: the canonical root command vocabulary and bounded bootstrap over the already-created Rust/Flutter workspace.
- Include: prerequisite validation, project SDK/dependency bootstrap, format/lint/test/check orchestration, Cargo-based enforcement of the active five-crate dependency graph, and an explicitly empty generated-source registration for Slice 001.
- Exclude: global tool installation, package-manager use, privilege escalation, generator dependencies/configuration, FRB/Riverpod/Freezed generation, architecture for future capabilities, and application behavior.
- Acceptance criteria: all seven public recipes exist, bootstrap is repeatable, `just check` is non-mutating, format is the explicit mutating formatter path, ShellCheck is included, the current Rust dependency direction is mechanically checked, and the empty generation registry performs no speculative generation.
- Verification/result reporting: run Steps 5-8 and report them under the Global Codex Execution and Result Contract.

- [ ] **Step 1: Verify the canonical command interface does not yet exist**

Run:

```bash
just --list
```

Expected: FAIL because no root `justfile` exists yet.

- [ ] **Step 2: Create bounded bootstrap automation**

Create `scripts/bootstrap.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required developer tool is missing: %s\n' "$command_name" >&2
    return 1
  fi
}

for command_name in git just rustup fvm bash shellcheck; do
  require_command "$command_name"
done

rust_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' "$ROOT_DIR/rust-toolchain.toml")"
if [[ -z "$rust_channel" ]]; then
  printf 'Could not read Rust channel from rust-toolchain.toml\n' >&2
  exit 1
fi

rustup toolchain install "$rust_channel" \
  --profile minimal \
  --component clippy \
  --component rustfmt

cargo fetch --manifest-path "$ROOT_DIR/rust/Cargo.toml" --locked

(
  cd "$ROOT_DIR/flutter"
  fvm install
  fvm flutter pub get --enforce-lockfile
)

printf 'Argus bootstrap complete.\n'
```

Make it executable:

```bash
chmod +x scripts/bootstrap.sh
```

- [ ] **Step 3: Create the active Rust dependency-boundary check**

Create `scripts/check_rust_dependencies.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/rust/Cargo.toml"

check_argus_dependencies() {
  local package_name="$1"
  shift

  local actual
  local expected

  actual="$(
    cargo tree \
      --manifest-path "$MANIFEST" \
      --package "$package_name" \
      --depth 1 \
      --edges normal \
      --prefix none \
      --locked \
      | tail -n +2 \
      | sed -n 's/^\(argus-[^ ]*\) .*/\1/p' \
      | LC_ALL=C sort
  )"

  expected="$(printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort)"

  if [[ "$actual" != "$expected" ]]; then
    printf 'Unexpected Argus crate dependencies for %s.\n' "$package_name" >&2
    printf 'Expected:\n%s\n' "$expected" >&2
    printf 'Actual:\n%s\n' "$actual" >&2
    return 1
  fi
}

check_argus_dependencies argus-domain
check_argus_dependencies argus-application argus-domain
check_argus_dependencies argus-infrastructure argus-application argus-domain
check_argus_dependencies argus-runtime argus-application argus-domain argus-infrastructure
check_argus_dependencies argus-bridge argus-runtime
```

Make it executable:

```bash
chmod +x scripts/check_rust_dependencies.sh
```

This check enforces the exact Argus dependency edges active in Slice 001. A later task may revise the bridge expectation only when an active bridge mapping actually requires one of the additional narrow dependencies permitted by SPEC-BE-001.

- [ ] **Step 4: Create the canonical root recipes**

Create `justfile`:

```just
set shell := ["bash", "-uc"]

bootstrap:
    bash scripts/bootstrap.sh

generate:
    @echo "No committed generated-source families are registered in SLICE-P00-001."

check-generated: generate
    @echo "Generated-source freshness check: no registered generated families."

format:
    cargo fmt --manifest-path rust/Cargo.toml --all
    cd flutter && fvm dart format .

_format-check:
    cargo fmt --manifest-path rust/Cargo.toml --all -- --check
    cd flutter && fvm dart format --output=none --set-exit-if-changed .

lint:
    cargo clippy --manifest-path rust/Cargo.toml --workspace --all-targets --all-features --locked -- -D warnings
    cd flutter && fvm flutter analyze
    shellcheck scripts/*.sh

_architecture:
    bash scripts/check_rust_dependencies.sh

test:
    cargo test --manifest-path rust/Cargo.toml --workspace --all-features --locked
    cd flutter && fvm flutter test

check: check-generated _format-check lint _architecture test
```

Keep recipe paths repository-relative. `just` runs recipes from the directory containing the root `justfile`, so this avoids host-form absolute-path conversion at the Git Bash boundary while still allowing `just` to be invoked from a repository subdirectory.

- [ ] **Step 5: Verify the command vocabulary exactly**

Run:

```bash
bash scripts/check_rust_dependencies.sh
just --list
```

Expected: the dependency-boundary check exits `0` before the recipe list is inspected.

Expected public recipes include:

```text
bootstrap
check
check-generated
format
generate
lint
test
```

The private `_format-check` and `_architecture` helpers may also be listed depending on the pinned `just` display behavior; they are not competing public workflows.

- [ ] **Step 6: Run bootstrap twice to prove idempotence**

Run:

```bash
just bootstrap
just bootstrap
```

Expected: both invocations exit `0`; the second run does not damage or reset valid project state.

- [ ] **Step 7: Prove `just check` is non-mutating**

Run:

```bash
before="$(git status --porcelain --untracked-files=all)"
just check
after="$(git status --porcelain --untracked-files=all)"
test "$before" = "$after"
```

Expected: `just check` exits `0` and the before/after status strings are identical.

- [ ] **Step 8: Prove `just format` is the mutating formatting entry point**

Temporarily introduce a harmless formatting-only change in `flutter/test/workspace_smoke_test.dart`, then run:

```bash
just format
just check
```

Expected: `just format` restores canonical formatting and `just check` exits `0`. Revert no semantic source because the formatter itself should leave the file in its intended final form.

- [ ] **Step 9: Commit checkpoint — only after explicit Daniel authorization**

Suggested commit message:

```text
build: add canonical repository workflows
```

Do not stage or commit without explicit authorization.

---

### Task 5: Add Baseline Tiered GitHub Actions CI

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: root `just check`, Rust/Flutter pins, desktop runner source.
- Produces: one Ubuntu platform-neutral quality gate plus targeted Windows/macOS native compilation, without duplicating the entire test suite on every OS.

**Codex task contract:**
- Parent: `PHASE-000` / `SLICE-P00-001`.
- Inspect first: `justfile`, `scripts/bootstrap.sh`, `scripts/check_rust_dependencies.sh`, `rust-toolchain.toml`, `flutter/.fvmrc`, `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`, `docs/conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md`.
- Allowed paths: `.github/workflows/ci.yml`.
- Forbidden paths: all source/manifests/docs/scripts outside that workflow and this plan file.
- Deliverable: tiered baseline CI that executes the canonical platform-neutral gate once and adds only required Windows/macOS native compile evidence.
- Include: read-only checkout permission, explicit prerequisite setup, Ubuntu `just bootstrap` + `just check`, targeted Windows/macOS Rust/Flutter native compilation.
- Exclude: future bridge/codegen jobs, persisted-job tests, future feature routes/tests, release packaging/signing, auto-format/regenerate/commit repair behavior, and duplicated full test suites on every OS.
- Acceptance criteria: YAML is valid/reviewable, exactly one job invokes `just check`, both native OS runners are present, jobs do not mutate source as repair, and hosted CI evidence is recorded before Slice 001 completion.
- Verification/result reporting: run Steps 2-4 and report local/hosted evidence under the Global Codex Execution and Result Contract.

- [ ] **Step 1: Create the CI workflow with read-only repository permissions**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
  pull_request:

permissions:
  contents: read

jobs:
  quality:
    name: Platform-neutral quality gate
    runs-on: ubuntu-24.04
    steps:
      - name: Check out repository
        uses: actions/checkout@v6

      - name: Set up just
        uses: extractions/setup-just@v4
        with:
          just-version: 1.58.0

      - name: Set up pinned Flutter
        uses: subosito/flutter-action@v2.23.0
        with:
          channel: stable
          flutter-version-file: flutter/.fvmrc
          cache: true
          pub-cache: true

      - name: Install CI FVM prerequisite
        run: |
          dart pub global activate fvm 4.1.2
          echo "$HOME/.pub-cache/bin" >> "$GITHUB_PATH"

      - name: Verify ShellCheck prerequisite
        run: shellcheck --version

      - name: Bootstrap repository
        run: just bootstrap

      - name: Run canonical quality gate
        run: just check

  native-desktop:
    name: Native desktop compile (${{ matrix.os }})
    strategy:
      fail-fast: false
      matrix:
        os:
          - windows-latest
          - macos-latest
    runs-on: ${{ matrix.os }}
    steps:
      - name: Check out repository
        uses: actions/checkout@v6

      - name: Set up pinned Flutter
        uses: subosito/flutter-action@v2.23.0
        with:
          channel: stable
          flutter-version-file: flutter/.fvmrc
          cache: true
          pub-cache: true

      - name: Install pinned Rust toolchain
        shell: bash
        run: |
          rust_channel="$(sed -n 's/^channel = "\([^"]*\)"/\1/p' rust-toolchain.toml)"
          rustup toolchain install "$rust_channel" --profile minimal

      - name: Check Rust workspace
        shell: bash
        run: cargo check --manifest-path rust/Cargo.toml --workspace --all-targets --locked

      - name: Resolve Flutter dependencies
        shell: bash
        run: cd flutter && flutter pub get --enforce-lockfile

      - name: Build native Flutter desktop shell
        shell: bash
        run: |
          if [[ "${{ runner.os }}" == "Windows" ]]; then
            cd flutter
            flutter build windows --debug
          else
            cd flutter
            flutter build macos --debug
          fi
```

The native jobs intentionally use the same exact `.fvmrc` pin through `flutter-action` but do not run the full platform-neutral suite again.

- [ ] **Step 2: Validate YAML syntax locally without adding a new project scripting language**

Use an existing editor/YAML validator if available, then inspect the workflow with:

```bash
git diff --check -- .github/workflows/ci.yml
```

Expected: exit `0`.

Do not introduce Python/Node solely to validate this one YAML file.

- [ ] **Step 3: Verify the CI workflow calls the canonical root gate exactly once**

Run:

```bash
grep -n 'run: just check' .github/workflows/ci.yml
grep -n 'windows-latest\|macos-latest' .github/workflows/ci.yml
```

Expected: one `just check` invocation in the `quality` job and both targeted native runner values in the matrix.

- [ ] **Step 4: Verify hosted CI behavior once a review branch is available with explicit Git authorization**

Do not push merely to satisfy this step unless Daniel has explicitly authorized the push. If no authorized remote branch/hosted run is available yet, report this evidence as `BLOCKED` or `NOT RUN`; do not report Slice 001 complete until the required hosted evidence exists.

Expected GitHub Actions results:

- `Platform-neutral quality gate` passes `just bootstrap` then `just check`;
- Windows native job passes Rust `cargo check` and `flutter build windows --debug`;
- macOS native job passes Rust `cargo check` and `flutter build macos --debug`;
- no job auto-formats, regenerates, commits, or repairs source.

If a hosted-runner prerequisite is missing, fix the explicit CI setup step; do not weaken `just check` or make bootstrap install global developer tools.

- [ ] **Step 5: Commit checkpoint — only after explicit Daniel authorization**

Suggested commit message:

```text
ci: add Phase 000 baseline quality gates
```

Do not stage or commit without explicit authorization.

---

### Task 6: Add Root Contributor/Bootstrap Documentation

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the actual commands implemented in Tasks 1–5.
- Produces: one discoverable repository entry point for Daniel, Codex, CI, and future contributors.

**Codex task contract:**
- Parent: `PHASE-000` / `SLICE-P00-001`.
- Inspect first: `justfile`, `scripts/bootstrap.sh`, `docs/README.md`, `docs/phases/phase-000-foundation.md`, `docs/conventions/conv-doc-001-documentation-and-codex-result-conventions.md`.
- Allowed paths: root `README.md` only.
- Forbidden paths: all source, configuration, CI, governed documentation, and this plan file.
- Deliverable: a concise root entry point that documents only workflows and scope rules actually established by Slice 001.
- Include: repository layout, prerequisites, bootstrap/check commands, focused root recipes, documentation entry points, active-scope warning.
- Exclude: future feature usage, startup/settings instructions not yet implemented, packaging/release claims, and duplicated subsystem contracts.
- Acceptance criteria: every documented recipe exists, no unresolved documentation placeholders remain, and the README states that Ready specs do not independently authorize implementation outside the active phase/slice/task.
- Verification/result reporting: run Steps 3-4 and report them under the Global Codex Execution and Result Contract.

- [ ] **Step 1: Verify root README is currently absent**

Run:

```bash
test ! -e README.md
```

Expected: exit `0` before creation.

- [ ] **Step 2: Create the root README with only implemented workflows**

Create `README.md`:

```markdown
# Argus ROM Toolkit

Argus ROM Toolkit is a Rust + Flutter application under architecture-first development.

## Implementation scope

A governed specification may be Ready before its capability is active. Implement only the intersection of the active phase, active slice or approved plan, explicit Codex task, and governing documents. Do not scaffold future capabilities merely because their specifications are Ready.

## Repository layout

- `rust/` — Rust workspace and backend/bridge crates.
- `flutter/` — Flutter desktop application.
- `docs/` — governed architecture, phase, specification, convention, and planning documentation.
- `scripts/` — focused repository automation invoked through `just`.

## Developer prerequisites

Install these globally before bootstrapping the repository:

- Git
- just
- rustup
- FVM
- Bash
- ShellCheck
- native build prerequisites for the desktop platform you intend to build

On Windows, Git Bash is the canonical Bash environment. WSL is not required.

## Bootstrap

```bash
just bootstrap
```

Bootstrap installs only repository-pinned Rust/Flutter SDK state through already-installed `rustup` and FVM, resolves dependencies, and validates required tools.

It does not install global developer tools or modify machine-wide configuration.

## Canonical verification

```bash
just check
```

`just check` is the platform-neutral local/CI quality gate. It checks generated-source freshness, formatting, Rust/Flutter static analysis, ShellCheck, active architecture/dependency boundaries, and tests.

Useful focused commands:

```bash
just generate
just check-generated
just format
just lint
just test
```

## Documentation

Start with:

- `docs/README.md`
- `docs/architecture/architecture-overview.md`
- `docs/phases/phase-000-foundation.md`

The repository documentation is the durable source of architecture and implementation intent.
```

- [ ] **Step 3: Verify every documented root recipe exists**

Run:

```bash
for recipe in bootstrap generate check-generated format lint test check; do
  just --show "$recipe" >/dev/null
done
```

Expected: exit `0`.

- [ ] **Step 4: Verify documentation has no placeholder markers**

Run:

```bash
if grep -nE '\b(T[B]D|TO[D]O|FIX[M]E)\b' README.md; then
  exit 1
fi
```

Expected: no output, exit `0`.

- [ ] **Step 5: Commit checkpoint — only after explicit Daniel authorization**

Suggested commit message:

```text
docs: add repository bootstrap guide
```

Do not stage or commit without explicit authorization.

---

### Task 7: Execute the Slice Acceptance Gate

**Files:**
- No new production files expected.
- Modify only files proven necessary by a failing acceptance check; keep fixes within Slice 001 scope.

**Interfaces:**
- Consumes: all outputs from Tasks 1–6.
- Produces: evidence that `SLICE-P00-001` has a reproducible, non-mutating canonical quality gate and no application behavior.

**Codex task contract:**
- Parent: `PHASE-000` / `SLICE-P00-001`.
- Inspect first: `.gitignore`, `.gitattributes`, `rust-toolchain.toml`, `docs/conventions/conv-repo-001-repository-and-generated-file-conventions.md`, `rust/Cargo.toml`, `rust/Cargo.lock`, `rust/crates/*/Cargo.toml`, `rust/crates/*/src/lib.rs`, `flutter/.fvmrc`, `flutter/.metadata`, `flutter/pubspec.yaml`, `flutter/pubspec.lock`, `flutter/analysis_options.yaml`, `flutter/lib/main.dart`, `flutter/test/workspace_smoke_test.dart`, `flutter/windows/**`, `flutter/macos/**`, `flutter/linux/**`, `scripts/bootstrap.sh`, `scripts/check_rust_dependencies.sh`, `justfile`, `.github/workflows/ci.yml`, root `README.md`, `docs/phases/phase-000-foundation.md`, and `docs/conventions/conv-test-001-test-pyramid-fixtures-and-verification-commands.md`.
- Allowed paths: no new paths; if a check fails, edit only the already-authorized Slice 001 paths from Tasks 1-6 that directly own the defect.
- Forbidden paths: every path outside the combined Task 1-6 allowed sets, future feature/module trees, and this plan file.
- Deliverable: completion evidence for the repository/toolchain slice, not new functionality.
- Include: canonical gate, non-mutation proof, workspace/source topology, no-speculative-scaffolding check, clean-checkout sequence, targeted CI evidence.
- Exclude: any new dependency, feature, DTO, generated binding, route, persistence/runtime behavior, or refactor introduced merely to make a future spec look prepared.
- Acceptance criteria: all acceptance-gate steps produce the required evidence or are truthfully reported `FAIL`/`BLOCKED`; Slice 001 cannot be claimed complete while required evidence is absent.
- Verification/result reporting: execute this task's full acceptance gate and report every command/evidence item under the Global Codex Execution and Result Contract.

- [ ] **Step 1: Run clean formatting and static verification**

Run:

```bash
just check
```

Expected: exit `0` with Rust format/clippy/tests, Dart format/analyze/tests, ShellCheck, the active Rust dependency-boundary check, and the current generated-source no-op check all passing.

- [ ] **Step 2: Verify the canonical gate is non-mutating**

Run:

```bash
status_before="$(git status --porcelain --untracked-files=all)"
just check
status_after="$(git status --porcelain --untracked-files=all)"
test "$status_before" = "$status_after"
```

Expected: exit `0`.

- [ ] **Step 3: Verify workspace topology**

Run:

```bash
cargo metadata --manifest-path rust/Cargo.toml --no-deps --format-version 1
find rust/crates -mindepth 1 -maxdepth 1 -type d -print | sort
```

Expected crate directories exactly:

```text
rust/crates/argus-application
rust/crates/argus-bridge
rust/crates/argus-domain
rust/crates/argus-infrastructure
rust/crates/argus-runtime
```

No feature modules or persistence/runtime implementation is introduced in the source files.

- [ ] **Step 4: Verify Flutter remains infrastructure-only**

Run:

```bash
find flutter/lib -type f -print
find flutter/test -type f -print
```

Expected authored Dart source exactly:

```text
flutter/lib/main.dart
flutter/test/workspace_smoke_test.dart
```

No `app/`, `core/`, or `features/` tree exists yet.

- [ ] **Step 5: Verify no later-scope dependency or source scaffolding leaked into Slice 001**

Run:

```bash
if grep -RniE '(flutter_rust_bridge|riverpod|freezed|go_router|build_runner|rusqlite|sqlx|tokio|tracing)' \
  rust/Cargo.toml rust/crates/*/Cargo.toml flutter/pubspec.yaml; then
  exit 1
fi

test ! -d flutter/lib/app
test ! -d flutter/lib/core
test ! -d flutter/lib/features

find rust/crates -path '*/src/*' -type f -print | sort
```

Expected:

- the dependency scan prints nothing and exits `0`;
- no `app`, `core`, or `features` Flutter ownership tree exists yet;
- Rust authored source consists only of the five crate `src/lib.rs` boundary files;
- no persisted-job/background-operation, provider/source/indexing/transformation, bridge DTO/binding, or other future capability scaffolding exists.

- [ ] **Step 6: Verify tracked/ignored repository hygiene**

Run:

```bash
git status --short
git check-ignore flutter/.fvm/flutter_sdk || true
git check-ignore rust/target/debug || true
git check-ignore flutter/build || true
```

Expected: only intended Slice 001 authored/generated source is visible before its reviewed commit; FVM SDK/cache and build outputs are ignored.

- [ ] **Step 7: Run the documented clean-checkout sequence in a fresh worktree/checkout before claiming the slice complete**

Run in the isolated execution environment:

```bash
just bootstrap
just check
```

Expected: both commands exit `0` using only committed repository state plus documented global prerequisites.

- [ ] **Step 8: Review CI evidence**

Required evidence before Slice 001 is complete:

- Ubuntu platform-neutral quality gate passes;
- Windows native compile passes;
- macOS native compile passes;
- CI makes no source changes and does not auto-repair failures.

- [ ] **Step 9: Final slice commit checkpoint — only after explicit Daniel authorization**

If Daniel prefers one squashed Slice 001 commit rather than the task-level checkpoints above, stage exactly the reviewed Slice 001 paths and use:

```text
build: bootstrap Argus Rust and Flutter workspaces
```

Never push automatically.

---

## Plan Self-Review Checklist

Before implementation begins, verify this plan against the governing specs:

- [x] Repository shape matches CONV-REPO-001.
- [x] Committed text uses LF without a batch-file CRLF exception.
- [x] Rust workspace contains exactly the five SPEC-BE-001 crates.
- [x] Rust crate dependency edges match SPEC-BE-001 and contain no application behavior.
- [x] The active Rust crate dependency graph is mechanically enforced through the canonical `just check` gate.
- [x] Workspace-level `unsafe_code = "deny"` is inherited by all five handwritten Rust crates.
- [x] Flutter remains one package and does not pre-create FE-001 ownership trees.
- [x] Dart formatting checks the complete Flutter package (`.`), matching CONV-FLUTTER-001 rather than only `lib/` and `test/`.
- [x] Exact Rust/Flutter pins are repository state.
- [x] Root canonical `just` recipe vocabulary is complete.
- [x] `just check` is non-mutating.
- [x] Bootstrap does not install global prerequisites or use system package managers.
- [x] Generated-source recipes exist without pretending a generator already exists.
- [x] CI uses one platform-neutral quality gate plus targeted Windows/macOS native compilation.
- [x] CI validates the hosted ShellCheck prerequisite without `sudo` or a system package manager.
- [x] ShellCheck prerequisite matches the lint contract.
- [x] Lockfiles are committed.
- [x] Post-creation bootstrap, CI, and verification enforce committed Rust/Flutter lockfiles instead of silently repairing stale dependency resolution.
- [x] FVM SDK/cache state is ignored while `.fvmrc` is committed.
- [x] No Riverpod, Freezed, routing, FRB, SQLite, settings, startup, or design-system behavior leaks into Slice 001.
- [x] No persisted jobs, `BackgroundOperationManager`, operation handles, future routes, provider/source/indexing/transformation modules, or other later-ready scaffolding leaks into active Slice 001 scope.
- [x] Every implementation task carries explicit Codex inspection/allowed/forbidden paths, deliverable, include/exclude scope, acceptance, verification, and result-reporting requirements.
- [x] The Flutter scaffold organization value is explicitly non-production and does not pre-approve release/package identity.
- [x] Each Git checkpoint is explicitly conditional on Daniel's authorization.

## Slice Boundary / Next Plan

After this plan is implemented and accepted, the next implementation plan is **SLICE-P00-002 — Rust Startup and Persistence Kernel**. That plan will introduce the first backend behavior: data-directory resolution, SQLite connection/migration infrastructure, Unit of Work, startup result/error/logging/diagnostic foundations, and backend tests. It must not be folded into this bootstrap slice.
