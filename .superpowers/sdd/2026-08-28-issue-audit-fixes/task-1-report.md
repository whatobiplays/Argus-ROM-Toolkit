# Task 1 Report: Mechanical test, documentation, and dependency corrections

## Scope and baseline

- Workspace: `/Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues`
- Baseline commit: `fcbc886`
- Branch: `codex/validate-fix-issues`
- Owned write set:
  - `rust/crates/argus-application/tests/content_contract.rs`
  - `rust/crates/argus-infrastructure/tests/content_session.rs`
  - `rust/crates/argus-infrastructure/tests/archive_content.rs`
  - `rust/crates/argus-infrastructure/tests/chd_content.rs`
  - `docs/architecture/architecture-overview.md`
  - `docs/superpowers/plans/2026-08-26-containers-and-compressed-representations.md`
  - `rust/Cargo.toml` and `rust/Cargo.lock` only if the dependency audit justified a compatible replacement for `fs2`

## What was validated

1. The reported duplicate assertion in `content_contract.rs` was real and redundant.
2. The reported dead/unused test state in `archive_content.rs` and `chd_content.rs` was real and removable without changing behavior.
3. The low-space fixture in `content_session.rs` did not actually reach the available-space branch before correction.
4. The architecture and plan documents had stale wording around Phase 003 RAR support and did not explicitly reflect the enter/leave container depth accounting now implemented.
5. The current dependency graph still routes `fs2` only through `argus-infrastructure`, and the current production code uses `fs2::available_space` in `rust/crates/argus-infrastructure/src/content_session.rs`.

## Changes made

### Tests

- `rust/crates/argus-application/tests/content_contract.rs`
  - Removed a duplicate assertion that repeated the same `descriptor.accepts_representation(...)` check.

- `rust/crates/argus-infrastructure/tests/archive_content.rs`
  - Removed the unused `offset` field from `BytesReader`.
  - Removed the dead assignments that only maintained that unused field.

- `rust/crates/argus-infrastructure/tests/chd_content.rs`
  - Removed dead state at the end of `chd_gd_uses_validated_track_metadata_and_existing_gd_identity`.
  - Removed the now-unneeded `mut` from `logical`.

- `rust/crates/argus-infrastructure/tests/content_session.rs`
  - Converted the low-space test from a same-error false positive into a branch-sensitive check.
  - Added a probe call counter so the test proves the space probe is invoked.
  - Corrected the low-space fixture budget so the staged input is no longer rejected first by representation-size/staged-budget limits.

### Documentation

- `docs/architecture/architecture-overview.md`
  - Replaced the stale “ZIP/7z/RAR/stream archive support” wording with Phase 003 wording that explicitly defers RAR.
  - Updated `ParsingSession` wording to mention explicit container-depth state.
  - Updated resource-limit wording to mention enter/leave container depth accounting explicitly.

- `docs/superpowers/plans/2026-08-26-containers-and-compressed-representations.md`
  - Updated the architecture summary to reflect explicit enter/leave container depth state.
  - Updated the tech-stack summary to match the implemented decoder feature pins:
    - `chd` with `std` and `verify_block_crc`
    - `sevenz-rust2` with only `bzip2`, `deflate`, `ppmd`, `util`
    - `flate2` with `rust_backend`
    - `zip` with `deflate-flate2`
    - `ruzstd` with `std`
  - Updated the RAR constraint to state that RAR remains excluded from the Phase 003 production transformation registry.

## TDD evidence for the fixture correction

This task required TDD only for the behavior-sensitive fixture correction in `content_session.rs`.

### Red

I first changed the test to assert that the low-space probe is called exactly once, without fixing the budget. That exposed the false positive.

Command:

```bash
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo test --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-infrastructure --features test-support --test content_session staging_checks_remaining_budget_and_available_space_before_copy
```

Observed result:

```text
running 1 test
test staging_checks_remaining_budget_and_available_space_before_copy ... FAILED

thread 'staging_checks_remaining_budget_and_available_space_before_copy' panicked:
assertion `left == right` failed
  left: 0
 right: 1
```

Interpretation: the test never reached the available-space probe. The input was being rejected earlier by other limits, so the original test was not validating the intended branch.

### Green

I then raised only the low-space fixture budget enough for the 101-byte staged input to pass the earlier checks while still exceeding the mocked available space of 100 bytes.

Command:

```bash
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo test --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-infrastructure --features test-support --test content_session staging_checks_remaining_budget_and_available_space_before_copy
```

Observed result:

```text
running 1 test
test staging_checks_remaining_budget_and_available_space_before_copy ... ok
```

Interpretation: the corrected fixture now exercises the intended available-space rejection path.

## Dependency audit: `fs2`

### Current code and graph

Command:

```bash
rg -n "fs2|lock_exclusive|lock_shared|FileExt|try_lock" /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust
```

Relevant findings:

```text
rust/Cargo.toml:20:fs2 = "0.4.3"
rust/crates/argus-infrastructure/src/content_session.rs:17:use fs2::available_space;
rust/crates/argus-infrastructure/Cargo.toml:22:fs2.workspace = true
```

Command:

```bash
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo tree --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-infrastructure -i fs2
```

Observed result:

```text
fs2 v0.4.3
└── argus-infrastructure v0.1.0
```

### API inspection

- `fs2` 0.4.3 documents `available_space(path) -> Result<u64>` on docs.rs.
- `fs4` 1.1.0 documents the same `available_space(path) -> Result<u64>` API on docs.rs and identifies itself as a fork of `fs2`.

Sources inspected:

- `https://docs.rs/fs2/latest/fs2/fn.available_space.html`
- `https://docs.rs/fs4/latest/fs4/fn.available_space.html`
- `https://docs.rs/fs4/latest/fs4/`

### Conclusion

I left `rust/Cargo.toml` and `rust/Cargo.lock` unchanged.

Reasoning:

1. The current code does not use `fs2` as a lock API here; it uses only `available_space`.
2. Replacing `fs2` with `fs4` would require at least one production source edit outside this task’s allowed write set (`rust/crates/argus-infrastructure/src/content_session.rs`), because the import path is `use fs2::available_space;`.
3. The task explicitly says to leave the dependency unchanged and document that conclusion if the replacement is not justified by the current supported behavior or would require broader change. That condition is met here.

## Commands run and results

### Baseline targeted tests

```bash
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo test --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-infrastructure --features test-support --test content_session
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo test --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-infrastructure --features test-support --test archive_content --test chd_content
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo test --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-application --test content_contract
```

Observed result:

- `content_session`: 6 passed
- `archive_content`: 14 passed
- `chd_content`: 6 passed
- `content_contract`: 9 passed

### Formatting

```bash
/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustfmt /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/crates/argus-application/tests/content_contract.rs /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/crates/argus-infrastructure/tests/content_session.rs /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/crates/argus-infrastructure/tests/archive_content.rs /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/crates/argus-infrastructure/tests/chd_content.rs
```

Observed result: success, no output.

### Final targeted tests

```bash
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo test --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-infrastructure --features test-support --test content_session --test archive_content --test chd_content
RUSTC=/Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/rustc /Users/daniel/.rustup/toolchains/1.97.1-aarch64-apple-darwin/bin/cargo test --manifest-path /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/rust/Cargo.toml -p argus-application --test content_contract
```

Observed result:

- `archive_content`: 14 passed
- `chd_content`: 6 passed
- `content_session`: 6 passed
- `content_contract`: 9 passed

### Documentation consistency checks

No repository-owned docs consistency command was found by repo search, so I validated the touched contract points directly with targeted text checks.

Command:

```bash
rg -n 'RAR remains explicitly deferred|enter/leave container depth accounting|explicit enter/leave container depth state|Phase 003 production transformation registry' /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/docs/architecture/architecture-overview.md /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues/docs/superpowers/plans/2026-08-26-containers-and-compressed-representations.md
```

Observed result:

```text
docs/superpowers/plans/2026-08-26-containers-and-compressed-representations.md:7: ... explicit enter/leave container depth state ...
docs/superpowers/plans/2026-08-26-containers-and-compressed-representations.md:19: ... excluded from the Phase 003 production transformation registry.
docs/architecture/architecture-overview.md:273: ... RAR remains explicitly deferred ...
docs/architecture/architecture-overview.md:633: ... enter/leave container depth accounting ...
```

### Diff hygiene

Command:

```bash
git -C /Users/daniel/Projects/Argus-ROM-Toolkit/.worktrees/validate-fix-issues diff --check
```

Observed result: success, no output.

## Files changed

- `docs/architecture/architecture-overview.md`
- `docs/superpowers/plans/2026-08-26-containers-and-compressed-representations.md`
- `rust/crates/argus-application/tests/content_contract.rs`
- `rust/crates/argus-infrastructure/tests/archive_content.rs`
- `rust/crates/argus-infrastructure/tests/chd_content.rs`
- `rust/crates/argus-infrastructure/tests/content_session.rs`

## Concerns

1. There is an unrelated untracked file in the worktree, `docs/superpowers/plans/2026-08-28-issue-audit-fixes.md`. I did not modify or stage it.
2. The dependency audit found a plausible maintained replacement (`fs4`) for the current `available_space` API, but this task could not adopt it without touching production source outside the allowed write set. The dependency remains unchanged intentionally.
