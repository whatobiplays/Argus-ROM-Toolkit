# macOS arm64 Rust/native deployment-target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every repository-owned Apple Silicon macOS Rust/native bridge build use one deterministic deployment-target policy without allowing incompatible objects to persist in the shared Cargo cache.

**Architecture:** Add a focused shell policy helper that is sourced by `scripts/run_rust.sh`. The helper applies the default only to an arm64 Darwin Cargo invocation, normalizes an empty deployment-target value to 11.0, rejects Intel macOS hosts/targets, and adds a deployment fingerprint to Cargo’s effective Rust flag source without masking caller configuration. It also adds an inert deployment fingerprint to the effective native `CFLAGS` source so cc-rs/BLAKE3 rebuilds when the deployment target changes. Keep all existing bridge callers on `run_rust.sh`; align the Xcode project’s arm64 configurations with the 11.0 product floor.

**Tech Stack:** Bash, Cargo/Rust 1.97.1, Xcode project build settings, Flutter macOS, `just`, shellcheck, and repository-owned shell contract tests.

## Global Constraints

- Supported macOS Rust target is `aarch64-apple-darwin`; Intel macOS is unsupported.
- The default native macOS deployment target is exactly `11.0`.
- An explicitly supplied non-empty `MACOSX_DEPLOYMENT_TARGET` value remains authoritative and is preserved byte-for-byte; an explicitly empty value resolves to `11.0`.
- No generated macOS deployment-target environment or macOS cache salt may enter Android, non-macOS, or other cross-target Cargo invocations.
- `CARGO_ENCODED_RUSTFLAGS`, `RUSTFLAGS`, target-specific Rust flags/configuration, and `build.rustflags` must remain effective under the pinned Cargo precedence rules.
- `scripts/run_rust.sh` remains the single repository-owned Rust build policy boundary.
- Cargo output is cleaned once after implementation for verification; builds do not clean on every invocation.
- Linker warnings are not suppressed and the shared target-directory architecture is not replaced.
- Existing Debug, Release, and Profile bridge archive paths remain unchanged.
- Documentation comments in new or changed shell code must explain the contract to an unfamiliar maintainer.

### Correction addendum (2026-09-02)

Pinned Cargo 1.97.1 probes showed that `CARGO_ENCODED_RUSTFLAGS` masks
`RUSTFLAGS`, target-specific environment flags mask global flags for the target
compile, matching target-specific configuration combines with the target
environment source, and `CARGO_BUILD_RUSTFLAGS` combines with `build.rustflags`
when no higher source is active. A global `RUSTFLAGS` salt therefore cannot be
used unconditionally: it can mask configuration and an encoded or target-
specific source can bypass it.

The corrected helper appends the Rust metadata marker to the highest effective
source already selected by Cargo. It appends a separate inert hexadecimal
preprocessor definition to effective native `CFLAGS`; cc-rs tracks CFLAGS while
the affected BLAKE3 build script does not track `MACOSX_DEPLOYMENT_TARGET`
itself. This preserves caller flags/configuration and invalidates both Rust and
native outputs across a deployment-target transition without forcing a Cargo
`--target` argument or cleaning on every build.

---

### Task 1: Add a failing macOS build-contract test

**Files:**
- Create: `scripts/test_macos_rust_build_environment.sh`

**Interfaces:**
- Consumes: The helper interface `argus_configure_macos_rust_build_environment <host-os> <host-arch> <cargo invocation...>` that Task 2 will provide.
- Produces: A portable executable test command, `bash scripts/test_macos_rust_build_environment.sh`, that exercises policy decisions without requiring a macOS host or an Android SDK.

- [x] **Step 1: Write the failing test.**

Create a strict Bash test harness that sources
`scripts/macos_rust_build_environment.sh`, resets all policy variables between
cases, and provides assertion helpers. Cover the native default and explicit
value, empty-value normalization, duplicate-marker prevention, Intel host/target
rejection, Android/non-macOS skips, and `rustc` versus Cargo routing. Assert
that the helper selects the effective source among
`CARGO_ENCODED_RUSTFLAGS`, `RUSTFLAGS`,
`CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS`, matching target configuration,
and `CARGO_BUILD_RUSTFLAGS`, while adding the native `CFLAGS` marker. On a
Darwin arm64 host, invoke pinned Cargo with `-vv` and assert the existing
caller flag and deployment marker both appear in the effective `rustc`
command. Reuse one target directory to prove the encoded-flag deployment
transition recompiles a Rust artifact. Add source-contract assertions that
Phase 000, Phase 001, Linux CMake, Windows CMake, Android bridge build, and
the Xcode bridge phase all route through `run_rust.sh` where they build or
install Rust tooling.

- [x] **Step 2: Run the test to verify it fails.**

Run:

```bash
bash scripts/test_macos_rust_build_environment.sh
```

Expected result: FAIL because `scripts/macos_rust_build_environment.sh` does
not exist and the policy function has not yet been implemented.

### Task 2: Implement and centralize the arm64 macOS policy

**Files:**
- Create: `scripts/macos_rust_build_environment.sh`
- Modify: `scripts/run_rust.sh:1-58`

**Interfaces:**
- Consumes: Host OS/architecture supplied by `run_rust.sh`, Cargo command-line arguments, `CARGO_BUILD_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, `RUSTFLAGS`, and existing target-specific Rust flags.
- Produces: `argus_configure_macos_rust_build_environment <host-os> <host-arch> <cargo invocation...>`, which mutates only the current shell environment and returns success for policy-skip contexts.

- [x] **Step 1: Implement target resolution and policy helpers.**

Implement the following behavior in the new helper:

1. Read a command-line target from `--target=<triple>` or `--target <triple>`;
   command-line target takes precedence over `CARGO_BUILD_TARGET`.
2. Apply policy only when the supplied host is `Darwin`, the supplied host
   architecture is `arm64`, the invocation begins with `cargo`, and the second
   Cargo argument is not `ndk`.
3. If no explicit target exists, treat the invocation as the native
   `aarch64-apple-darwin` build. If a target exists, apply policy only for
   `aarch64-apple-darwin`.
4. When `MACOSX_DEPLOYMENT_TARGET` is unset or empty, export `11.0`; preserve
   a non-empty explicit value.
5. Encode the effective deployment-target bytes as lowercase hexadecimal using
   POSIX `od`/`tr`, then append one metadata marker to the highest effective
   Cargo Rust flag source. Use encoded separators for
   `CARGO_ENCODED_RUSTFLAGS`, use `CARGO_BUILD_RUSTFLAGS` when it can combine
   with `build.rustflags`, and detect exact target-specific configuration before
   using `CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS`.
6. Append an inert
   `-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=<hex>` marker to effective
   native `CFLAGS` so cc-rs build scripts observe the same transition. Do not
   append duplicates, replace caller flags, or mutate skip-context variables.

Use comments immediately above the exported deployment environment, Rust
marker, and native C marker to explain how each participates in the shared
cache without masking caller flags or changing linker warning behavior.
Do not export or unset any macOS-specific variable in skip contexts.

- [x] **Step 2: Source and invoke the helper from `run_rust.sh`.**

After argument validation and before resolving/executing the pinned Cargo
toolchain, add:

```bash
source "$ROOT_DIR/scripts/macos_rust_build_environment.sh"
argus_configure_macos_rust_build_environment "$(uname -s)" "$(uname -m)" "$@"
```

Keep the existing rustup path resolution and `exec env PATH=... rustup run ...`
logic unchanged. The helper must run before Cargo so both Cargo build scripts
and Rust compilation observe the same environment.

- [x] **Step 3: Run the focused test to verify it passes.**

Run:

```bash
bash scripts/test_macos_rust_build_environment.sh
```

Expected result: PASS for all native-default, explicit-value, empty-value,
duplicate-marker, Cargo-precedence, Android, cross-target, non-Darwin,
unsupported-host/target, command, effective-pinned-Cargo, and source-routing
cases.

- [x] **Step 4: Run shellcheck on the changed scripts.**

Run:

```bash
shellcheck scripts/run_rust.sh scripts/macos_rust_build_environment.sh \
  scripts/test_macos_rust_build_environment.sh
```

Expected result: exit 0 with no diagnostics.

### Task 3: Align the macOS product configurations and repository checks

**Files:**
- Modify: `flutter/macos/Runner.xcodeproj/project.pbxproj:496,578,628`
- Modify: `justfile:79-83`

**Interfaces:**
- Consumes: The centralized wrapper from Task 2.
- Produces: Debug, Release, and Profile Xcode configurations that declare the
  same arm64-only/11.0 contract as ordinary Cargo builds, with unchanged Rust
  archive paths. The design spec already records the explicit `ARCHS=arm64`
  setting.

- [x] **Step 1: Update all Xcode project-level configurations.**

Change each of the three existing
`MACOSX_DEPLOYMENT_TARGET = 10.15;` assignments to
`MACOSX_DEPLOYMENT_TARGET = 11.0;`. Add `ARCHS = arm64;` to the same project-level
Debug, Release, and Profile build-setting dictionaries so the project cannot
silently produce an Intel macOS product. Leave the Xcode shell phase’s
`run_rust.sh` invocation and the Debug/Release archive paths unchanged.

- [x] **Step 2: Add a dedicated `just` entry point.**

Add:

```make
test-macos-rust-build-contract:
    bash scripts/test_macos_rust_build_environment.sh
```

Make the existing `test` recipe invoke this recipe’s command directly once,
before Rust tests, so `just test` and `just check` both enforce the contract
without recursively starting another `just` process.

- [x] **Step 3: Run the focused contract and Xcode setting checks.**

Run:

```bash
bash scripts/test_macos_rust_build_environment.sh
xcodebuild -project flutter/macos/Runner.xcodeproj -scheme Runner \
  -configuration Debug -showBuildSettings
```

Expected result: the focused test passes; the Xcode settings report
`ARCHS = arm64`, `MACOSX_DEPLOYMENT_TARGET = 11.0`, and the existing Debug
bridge archive path. Repeat `-configuration Release` and `Profile` when the
host Xcode supports the profile configuration.

### Task 4: Rebuild from a clean implementation boundary and verify artifacts

**Files:**
- No additional source files; verification inspects `rust/target` and Flutter build output.

**Interfaces:**
- Consumes: The completed wrapper, Xcode settings, and contract tests.
- Produces: Evidence that native C objects and Rust archive members are built
  under the same arm64 deployment target and that Android/non-macOS workflows
  remain valid.

- [x] **Step 1: Perform the permitted one-time targeted cleanup.**

After Tasks 1–3 are implemented, run:

```bash
bash scripts/run_rust.sh cargo clean --manifest-path rust/Cargo.toml
```

This removes stale shared Cargo artifacts once for the verification run. Do
not add this command to any build wrapper or recurring recipe; deployment
transitions are handled by the effective Rust/native fingerprint inputs.

- [x] **Step 2: Run focused tests and repository static checks.**

Run:

```bash
bash scripts/test_macos_rust_build_environment.sh
shellcheck scripts/*.sh
just check-android-contract
```

Expected result: all commands exit 0. The Android source contract must remain
ARM64-only and must not acquire a macOS deployment-target export.

- [x] **Step 3: Build and test the Rust bridge through the wrapper.**

Run:

```bash
bash scripts/run_rust.sh cargo build \
  --manifest-path rust/Cargo.toml --package argus-bridge --locked
bash scripts/run_rust.sh cargo test \
  --manifest-path rust/Cargo.toml --package argus-bridge --locked
```

Expected result: both commands exit 0. Extract the members of
`rust/target/debug/libargus_bridge.a` into a temporary directory and use
`otool -l` to verify every arm64 Mach-O member, including the BLAKE3 native
member, has a minimum OS no newer than 11.0.

- [x] **Step 4: Verify Flutter macOS Debug linking.**

Run:

```bash
cd flutter
fvm flutter build macos --debug --no-pub
```

Capture the complete output and require exit 0 with no `ld: warning: object
file` line. Confirm the built Debug bridge archive remains
`rust/target/debug/libargus_bridge.a` and that its native members still report
the same minimum target.

- [x] **Step 5: Verify repeated policy transitions cannot reuse incompatible members.**

Use temporary logs and the shared target directory to run one wrapper build
with `MACOSX_DEPLOYMENT_TARGET=26.5`, then a normal wrapper build without that
variable. Confirm the second run rebuilds the bridge archive and the BLAKE3
native build, and inspect its members to confirm no 26.5 object remains. Run
Flutter macOS Debug again and require no linker warning. This proves the
combined Rust/native markers invalidate the final archive rather than merely
rebuilding one root crate.

- [x] **Step 6: Run the repository-level verification.**

Run:

```bash
just check
```

If the Phase 000 and Phase 001 native harness prerequisites are available, also
run `just test-phase-000-native` and `just test-phase-001-native`; otherwise
record the exact missing prerequisite and retain the focused/static/build
results. Review `git diff --check`, `git status --short`, and the final diff to
confirm no generated artifacts or unrelated architecture changes were added.

- [x] **Step 7: Commit the implementation.**

Commit the helper, wrapper integration, tests, `just` registration, and Xcode
configuration change together:

```bash
git add docs/superpowers/specs/2026-09-02-macos-arm64-rust-deployment-target-design.md \
  docs/superpowers/plans/2026-09-02-macos-arm64-rust-deployment-target.md \
  scripts/macos_rust_build_environment.sh \
  scripts/test_macos_rust_build_environment.sh scripts/run_rust.sh \
  justfile flutter/macos/Runner.xcodeproj/project.pbxproj
git commit -m "build: stabilize macOS arm64 native deployment target"
```

## Correction addendum (2026-09-02, approved)

The current macOS deployment-target contract remains Apple Silicon-only with a
minimum target of 11.0. This addendum corrects the remaining edge cases found
after the initial implementation:

- native `cc` flags must honor the hyphenated target variable before its
  underscore form, then `TARGET_CFLAGS`, then plain `CFLAGS`;
- Cargo target tables written with matching `cfg(...)` expressions must be
  recognized so the deployment marker survives Cargo's source precedence;
- the shared repository validation profile needs explicit `test`, `build`,
  and `lint` entries while retaining `all`;
- the August Android slice records are historical and must retain their
  original wording; the later September macOS record is the current product
  authority.

- [x] **Step 8: Add regression tests before changing the implementation.**

Extend `scripts/test_macos_rust_build_environment.sh` to cover all four native
`cc` variable spellings, including a child `env` invocation for the
hyphenated name, a nested matching `cfg(...)` Cargo target table, and the
`build-macos-debug` Just target.

Run:

```bash
bash scripts/test_macos_rust_build_environment.sh
```

The new assertions initially failed against the current helper, proving the
tests exercised the reported gaps; the completed focused run now exits 0.

- [x] **Step 9: Implement the smallest policy corrections.**

Update the sourced helper and wrapper so hyphenated environment assignments
are carried through `env` to pinned Cargo, while valid shell identifiers are
exported normally. Evaluate matching Cargo target `cfg(...)` expressions from
the pinned target's `rustc --print cfg` output and route the deployment marker
to the target-specific Rust flags source when such a table supplies
`rustflags`. Add `build-macos-debug` as the repository's documented Flutter
macOS build entry point.

Run:

```bash
bash scripts/test_macos_rust_build_environment.sh
shellcheck scripts/*.sh
```

Observed result: the focused contract and shell checks exit 0.

- [x] **Step 10: Restore historical records and update current documentation.**

Restore the three August 21 Android-slice documents byte-for-byte to their
pre-macOS-change wording. Update the September design and plan records with
the `cc` precedence, matching `cfg(...)` behavior, pinned-toolchain detail,
and the historical-document supersession note.

Run:

```bash
git diff HEAD^ -- docs/implementation/phase-002-slice-007-android-ci-distribution-and-first-class-platform-hardening.md docs/superpowers/plans/2026-08-21-phase-002-slice-007-android-ci-distribution-and-first-class-platform-hardening.md docs/superpowers/specs/2026-08-21-phase-002-slice-007-android-ci-distribution-and-first-class-platform-hardening-design.md
```

Observed result: those historical files have no net diff from the previous
implementation commit.

- [x] **Step 11: Update and validate the sibling Argus profile without staging it.**

Change only the ignored Argus entry in
`/Users/daniel/Projects/gpt-repo-mcp/config.local.json` to use `just test`,
`just build-macos-debug`, `just lint`, and `just check` for its respective
profiles. Preserve every unrelated working-tree change in that repository.

Run:

```bash
jq empty /Users/daniel/Projects/gpt-repo-mcp/config.local.json
cd /Users/daniel/Projects/gpt-repo-mcp && npm run check:config
```

Observed result: the local configuration parses and both the profile assertion
and documented config check pass.

- [ ] **Step 12: Verify the corrected contract and commit on `main`.**

Run the focused test, Android contract, lint, test, build, and repository check
commands. Poison the shared Rust target with a 26.5 deployment-target wrapper
build, recover with the normal wrapper, inspect the bridge archive and native
members, then run `just build-macos-debug` and inspect the resulting arm64
binary, minimum OS, and `Info.plist`. Review `git diff --check` and stage only
Argus files before committing directly on `main`.

```bash
just test-macos-rust-build-contract
just check-android-contract
just lint
just test
just build-macos-debug
just check
git diff --check
git status --short
```
