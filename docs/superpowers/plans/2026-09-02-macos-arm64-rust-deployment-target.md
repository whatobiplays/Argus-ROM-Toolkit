# macOS arm64 Rust/native deployment-target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every repository-owned Apple Silicon macOS Rust/native bridge build use one deterministic deployment-target policy without allowing incompatible objects to persist in the shared Cargo cache.

**Architecture:** Add a focused shell policy helper that is sourced by `scripts/run_rust.sh`. The helper applies the default only to an arm64 Darwin Cargo invocation, preserves explicit deployment-target values, and adds a macOS-scoped global Rust fingerprint salt derived from the effective value so dependency build scripts and the final archive share one cache input. Keep all existing bridge callers on `run_rust.sh`; align the Xcode project’s arm64 configurations with the 11.0 product floor.

**Tech Stack:** Bash, Cargo/Rust 1.97.1, Xcode project build settings, Flutter macOS, `just`, shellcheck, and repository-owned shell contract tests.

## Global Constraints

- Supported macOS Rust target is `aarch64-apple-darwin`; Intel macOS is unsupported.
- The default native macOS deployment target is exactly `11.0`.
- An explicitly supplied `MACOSX_DEPLOYMENT_TARGET` value remains authoritative and is preserved byte-for-byte.
- No generated macOS deployment-target environment or macOS cache salt may enter Android, non-macOS, or other cross-target Cargo invocations.
- `scripts/run_rust.sh` remains the single repository-owned Rust build policy boundary.
- Cargo output is cleaned once after implementation for verification; builds do not clean on every invocation.
- Linker warnings are not suppressed and the shared target-directory architecture is not replaced.
- Existing Debug, Release, and Profile bridge archive paths remain unchanged.
- Documentation comments in new or changed shell code must explain the contract to an unfamiliar maintainer.

---

### Task 1: Add a failing macOS build-contract test

**Files:**
- Create: `scripts/test_macos_rust_build_environment.sh`

**Interfaces:**
- Consumes: The helper interface `argus_configure_macos_rust_build_environment <host-os> <host-arch> <cargo invocation...>` that Task 2 will provide.
- Produces: A portable executable test command, `bash scripts/test_macos_rust_build_environment.sh`, that exercises policy decisions without requiring a macOS host or an Android SDK.

- [x] **Step 1: Write the failing test.**

Create a strict Bash test harness that sources
`scripts/macos_rust_build_environment.sh`, resets the policy variables between
cases, and provides small `assert_equal`, `assert_contains`, and
`assert_unset` helpers. Include these concrete cases:

```bash
unset MACOSX_DEPLOYMENT_TARGET CARGO_BUILD_TARGET \
  CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS RUSTFLAGS
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_equal 11.0 "$MACOSX_DEPLOYMENT_TARGET"
assert_contains '-C metadata=argus-macos-deployment-target-' "$RUSTFLAGS"

unset CARGO_BUILD_TARGET CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS RUSTFLAGS
export MACOSX_DEPLOYMENT_TARGET=26.5
export RUSTFLAGS='-C opt-level=1'
export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS='-C opt-level=1'
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_equal 26.5 "$MACOSX_DEPLOYMENT_TARGET"
assert_contains '-C opt-level=1' "$RUSTFLAGS"
assert_contains '-C opt-level=1' \
  "$CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS"

unset MACOSX_DEPLOYMENT_TARGET CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
export CARGO_BUILD_TARGET=aarch64-linux-android
argus_configure_macos_rust_build_environment Darwin arm64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

unset CARGO_BUILD_TARGET
argus_configure_macos_rust_build_environment Darwin arm64 cargo ndk build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

argus_configure_macos_rust_build_environment Linux x86_64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS

argus_configure_macos_rust_build_environment Darwin x86_64 cargo build
assert_unset MACOSX_DEPLOYMENT_TARGET
assert_unset CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS
```

Also assert that `--target=aarch64-linux-android` and `--target
aarch64-linux-android` skip the policy, while `--target aarch64-apple-darwin`
uses it, and that invoking `rustc` rather than `cargo` does not add Cargo
policy. Call the native case twice and assert the fingerprint salt occurs only
once. Add source-contract assertions that Phase 000, Phase 001, Linux CMake,
Windows CMake, Android bridge build, and the Xcode bridge phase all route
through `run_rust.sh` where they build or install Rust tooling.

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
4. When `MACOSX_DEPLOYMENT_TARGET` is unset, export `11.0`; when it is set,
   including an empty value, do not assign to it.
5. Encode the effective deployment-target bytes as lowercase hexadecimal using
   POSIX `od`/`tr`, then append one global Rust flag of the form
   `-C metadata=argus-macos-deployment-target-<hex>` to `RUSTFLAGS`. Do not
   append a duplicate and preserve all existing global and target-specific flag
   text.

Use comments immediately above the exported environment and cache salt to
explain that the first controls native C build scripts and the second changes
Cargo’s global Rust fingerprint so dependency build scripts and the shared
archive cannot retain stale members.
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

Expected result: PASS for all native-default, explicit-value, duplicate-salt,
Android, cross-target, non-Darwin, unsupported-host-architecture, command,
and source-routing cases.

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
not add this command to any build wrapper or recurring recipe.

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
variable. Confirm the second run rebuilds the bridge archive and inspect its
members to confirm no 26.5 object remains. Run Flutter macOS Debug again and
require no linker warning. This proves the salt invalidates the final Rust
archive rather than merely rebuilding one native dependency.

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
