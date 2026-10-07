# macOS arm64 Rust/native deployment-target contract

**Document ID:** BUILD-MACOS-ARM64-DEPLOYMENT-TARGET
**Status:** Implemented — verified
**Owner:** Daniel
**Date:** 2026-09-02
**Last amended:** 2026-10-07 — deployment fingerprint no longer touches Cargo
crate identity, and Release build-time crates stay unstripped (see section 8);
supported macOS floor raised from 11.0 to 12.0 on 2026-10-05 (see section 7)
**Scope:** macOS Rust/native-library builds feeding the Flutter application

## 1. Purpose

This design makes the macOS native build deterministic when Rust and native
dependency objects share `rust/target`. The supported macOS architecture is
Apple Silicon (`aarch64-apple-darwin`); Intel macOS is not a supported build or
runtime target.

The change preserves the existing build topology and keeps
`scripts/run_rust.sh` as the common entry point used by ordinary Rust builds,
Phase 000/001 native checks, Android tooling, and the Xcode native bridge
phase.

## 2. Evidence and root cause

Before this correction, the Xcode project declared
`MACOSX_DEPLOYMENT_TARGET=10.15`, while an arm64 Xcode link on this host
resolved to an effective minimum of 11.0. The project now declares the
supported arm64/11.0 contract. A normal Rust build can still produce arm64
objects at 11.0, but a shared target directory can also contain objects
produced after a caller supplied a newer deployment target.

*(Amended 2026-10-05: the supported floor has since risen from 11.0 to 12.0;
see section 7. The 10.15 → 11.0 correction described above remains the
historical record of the September work.)*

The failure was reproduced by building with
`MACOSX_DEPLOYMENT_TARGET=26.5`. The BLAKE3 build script emitted
`blake3_neon.o` with a 26.5 minimum, and the resulting Rust archive retained
that member. A later Flutter/Xcode build linked at 11.0 and reused the stale
archive members, producing linker warnings even though the later native build
script observed a different deployment-target environment.

The defect is therefore shared-cache invalidation and policy drift, not a
linker-warning configuration problem. Suppressing the warning would leave an
incompatible archive in the build graph.

## 3. Build contract

The helper invoked by `scripts/run_rust.sh` owns the following contract
(deployment-target values below include the 2026-10-05 amendment in section 7):

| Invocation context | Generated macOS environment | Cache behavior |
| --- | --- | --- |
| Darwin arm64 host, effective target `aarch64-apple-darwin`, ordinary Cargo invocation | Set `MACOSX_DEPLOYMENT_TARGET=12.0` when the caller did not provide a non-empty value | Add a deterministic deployment-target input to the macOS-scoped Cargo/native fingerprints while preserving Cargo’s effective caller flags |
| Same native context with an explicit non-empty `MACOSX_DEPLOYMENT_TARGET` | Preserve the caller’s exact value | Fingerprint the explicit value |
| Same native context with `MACOSX_DEPLOYMENT_TARGET=""` | Resolve the empty value to `12.0` | Use the default fingerprint |
| Android `cargo ndk` or an explicit non-macOS target | Do not synthesize a macOS deployment target or macOS cache input | Leave Android/cross-compilation behavior unchanged |
| Intel macOS host or an Intel/other macOS Rust target | Reject the invocation with a diagnostic | Intel macOS is outside the supported product contract |
| Non-Darwin host | Do not synthesize a macOS deployment target or macOS cache input | Leave the existing workflow unchanged |

The default is applied only to the native Apple Silicon macOS build domain,
and the cache inputs are scoped to that domain so Android and other
cross-compilation workflows cannot inherit macOS policy.

### 3.1 Cargo precedence and cache inputs

Pinned Cargo 1.97.1 probes established the effective precedence relevant to
this wrapper:

1. `CARGO_ENCODED_RUSTFLAGS` takes precedence over `RUSTFLAGS` and the Cargo
   configuration sources.
2. `RUSTFLAGS` takes precedence over `build.rustflags` and target-specific
   configuration for the target compile. A target-specific environment value
   is the effective target source when it is present, while global flags remain
   relevant to host/build-script compilation.
3. `CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS` combines with matching
   `target.aarch64-apple-darwin.rustflags` configuration and otherwise masks
   lower-precedence global/configuration sources for that target.
4. Matching target-specific configuration takes precedence over
   `build.rustflags`.
5. `CARGO_BUILD_RUSTFLAGS` combines with `build.rustflags` when no higher
   source is active.

Cargo target configuration may be keyed by the exact target name or by a
matching target `cfg(...)` expression. The helper evaluates matching cfg
tables against the pinned target's rustc --print cfg output, including the
`all`, `any`, and `not` combinators, then uses the target-specific
environment source so Cargo combines its deployment marker with the table's
own flags. Multiple matching tables remain Cargo's responsibility; the helper
does not invent a second merge order.

### 3.2 Cargo configuration resolution

The pinned `cargo 1.97.1` binary exposes `cargo config get`, but that command
is still unstable and rejects the pinned stable channel. The helper therefore
does not attempt to obtain resolved configuration through Cargo itself. It
uses a bounded resolver whose only configuration question is whether an
active target-level `rustflags` source exists; Cargo remains responsible for
parsing and merging the actual values.

The resolver accepts whitespace around the equals sign in inline `--config`
assignments, recognizes exact and matching `cfg(...)` target tables in both
dotted and table forms, and scans every `--config` argument. For file-based
configuration it follows the top-level `include` array recursively, resolves
configuration it follows the top-level `include` array recursively and
resolves relative paths from the directory containing the including file. For
an inline CLI `--config KEY=VALUE` include, it resolves relative paths from
Cargo's current working directory. These base directories are passed
explicitly to the resolver so the two Cargo-defined contexts cannot be
confused. The resolver skips absent optional includes and tracks canonical
paths so cycles terminate. Missing required includes remain Cargo errors when
Cargo loads the same invocation. During hierarchical discovery it selects
`.cargo/config` over `.cargo/config.toml` when both exist in one directory,
matching Cargo's compatibility behavior; the same choice is applied to the
Cargo home configuration.

The helper adds the deployment marker to the highest effective Rust source
already selected by Cargo: encoded flags, global flags, target-specific flags,
or matching target configuration. For target configuration without a target
environment source, it adds a matching target-specific environment marker;
Cargo combines those two sources rather than masking the configuration. When
no higher source is active, it uses `CARGO_BUILD_RUSTFLAGS`. This avoids
introducing a higher-precedence global flag that would silently mask a
caller’s effective Cargo configuration. The marker is a semantically inert
single-token custom cfg, `--cfg=argus_macos_deployment_target_fingerprint_<hex>`,
which changes the Rust fingerprint without changing linker warning behavior or
Cargo’s crate-identity metadata. (The September design appended an extra
`-C metadata=argus-macos-deployment-target-<hex>` value instead; section 8
records that amendment and why it was made.)

Cargo/cc-rs does not make BLAKE3 rerun merely because
`MACOSX_DEPLOYMENT_TARGET` changed. The helper therefore also appends an
inert hexadecimal preprocessor definition,
`-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=<hex>`, to the effective native
`CFLAGS` source. cc-rs checks native flags in this order:
`CFLAGS_aarch64-apple-darwin`, `CFLAGS_aarch64_apple_darwin`,
`TARGET_CFLAGS`, and `CFLAGS`, while retaining all defined inputs. The
helper adds the marker only to the highest-priority defined source, so the
effective native flags contain one marker and all caller flags remain in
place. Because Bash cannot assign a hyphenated variable, `run_rust.sh`
carries that hyphenated assignment through `env` when it is the selected
source. cc-rs tracks the resulting input, so BLAKE3 and other affected native
build scripts rebuild under the same deployment-target transition.
The locked dependency currently resolves cc-rs 1.4.2, whose target_envs and
envflags implementation establishes this precedence and retains lower-priority
caller inputs.

The August 21 Android-slice documents retain their original historical
desktop wording. They are not current macOS product authority; this September
contract supersedes them for the macOS architecture and deployment-target
policy.

## 4. Xcode and phase integration

The project-level Debug, Release, and Profile configurations declare
`ARCHS=arm64` and `MACOSX_DEPLOYMENT_TARGET=12.0`. This makes the product
architecture, the `Info.plist` minimum-system-version substitution, and the
arm64 linker floor describe the same supported contract. It is not an Intel
compatibility baseline, because Intel macOS is outside the product support
scope.

The Xcode “Build Argus native bridge” phase will continue to invoke
`scripts/run_rust.sh`; it will not maintain a second deployment-target policy.
The Phase 000 and Phase 001 scripts will likewise continue to use that entry
point. Debug, Release, and Profile archive paths remain the existing shared
Cargo paths.

Android scripts will continue to use `run_rust.sh` for toolchain consistency,
but the helper will recognize `cargo ndk`/Android targets and will not apply
the macOS contract.

## 5. Regression coverage

Focused contract tests exercise the helper and, on the supported host, invoke
the pinned Cargo toolchain to inspect effective `rustc` arguments:

1. Native Darwin arm64 with no explicit value receives 12.0.
2. `aarch64-apple-darwin` is the only supported macOS Rust target; Intel macOS
   hosts/targets are rejected.
3. Native Darwin arm64 with an explicit non-empty value preserves that value;
   an empty value resolves to 12.0.
4. Linux, Android, and non-macOS cross-target invocations receive no generated
   macOS policy or macOS cache input.
5. Existing `RUSTFLAGS`, `CARGO_ENCODED_RUSTFLAGS`, target-specific flags, and
   `build.rustflags` remain effective alongside the deployment marker.
6. Native `cc` flag precedence covers the hyphenated target form, its
   underscore form, `TARGET_CFLAGS`, and plain `CFLAGS` without duplicating
   the marker.
7. Matching target-name and `cfg(...)` Cargo tables, including nested
   expressions, retain their caller flags alongside the deployment marker.
8. Effective pinned-Cargo probes cover compact and whitespace-valid `--config`
   assignments, file-based direct and recursive includes, CLI string and
   inline-table includes, optional missing includes in both contexts,
   include-cycle termination, multiple `--config` files, and `.cargo/config`
   versus `.cargo/config.toml` precedence.
9. Pinned Cargo fingerprints change across 26.5 → 12.0 transitions, and
   distinct deployment targets produce distinct native C flag fingerprints so
   shared Cargo output cannot keep native members built above the 12.0 floor.
10. Phase 000/001, ordinary Rust validation, CI, and the Xcode phase route
   through `run_rust.sh` where applicable.
11. Debug, Release, and Profile Xcode settings all use arm64/12.0 and retain
   the existing archive paths.
12. The `build-macos-debug` Just target provides the shared, documented
   Flutter macOS Debug build entry point.
13. Every effective Rust flag source carries the deployment fingerprint exactly
   once as the `--cfg=` marker, no effective source or verbose `rustc`
   invocation carries the retired `-C metadata=argus-macos-deployment-target-`
   marker, and a caller-supplied `-C metadata=...` value is preserved
   unchanged.
14. A clean build of the bridge package, whose dependency graph contains host
   proc-macro crates, completes without missing-crate errors, duplicate macro
   definitions, or dynamic-loader failures.

Verification completed with shellcheck, the repository’s `just check` and
focused checks, a one-time targeted cleanup of pre-existing artifacts, normal
Rust builds/tests, direct inspection of arm64 archive member load commands,
and a Flutter macOS Debug build. The verified macOS archive contains no object
newer than the link deployment target, including BLAKE3 native objects.

## 6. Non-goals and risks

This change does not introduce separate target directories, change Rust or
Flutter architecture, raise an arbitrary product minimum, clean Cargo output
on every invocation, reintroduce Intel macOS support, or suppress linker
diagnostics. The main residual risk is an unusual external Cargo invocation
that bypasses `run_rust.sh`; repository build paths remain governed by the
shared wrapper, and the project contract documents that boundary.

## 7. Amendment 2026-10-05: supported macOS floor raised from 11.0 to 12.0

**Current contract:** the supported Apple Silicon macOS deployment floor is
`MACOSX_DEPLOYMENT_TARGET=12.0`. Everything else in this document is
unchanged: arm64-only macOS support, `scripts/run_rust.sh` as the single
repository-owned build policy boundary, the deployment-target fingerprinting
scheme, the existing Debug/Profile/Release archive paths, and the current
signing and entitlement behavior.

### 7.1 Why the floor changed

The Xcode toolchain used to produce the supported Release artifact no longer
accepts `11.0` as a macOS deployment target. On 2026-10-05 the installed
toolchain (Xcode 27.0, build 27A266a, macOS 27.0 SDK) declares
`SupportedTargets.macosx.MinimumDeploymentTarget = 12.0` and
`MaximumDeploymentTarget = 27.0.99`, and Xcode rejects the checked-in
project before compiling anything:

```
error: The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 11.0,
but the range of supported deployment target versions is 12.0 to 27.0.x.
(in target 'Runner' from project 'Runner')
```

Because that failure happens while Xcode configures the project, the supported
Release artifact cannot be produced at all, and owner qualification of the
macOS product had no build to exercise. The supported floor therefore moves to
`12.0`.

This is an intentional product support-floor change, not a warning suppression
and not a qualification-only workaround. Keeping the project at `11.0` would
require an environment override or a local Xcode setting, which would leave the
checked-in contract advertising a minimum that the supported toolchain cannot
build.

### 7.2 Effect on the contract

- Ordinary native Apple Silicon Rust builds through `scripts/run_rust.sh`
  synthesize `MACOSX_DEPLOYMENT_TARGET=12.0` when the caller supplies no
  non-empty value, and resolve an explicitly empty value to `12.0`.
- The project-level Debug, Release, and Profile configurations declare
  `MACOSX_DEPLOYMENT_TARGET = 12.0` alongside the unchanged `ARCHS = arm64`,
  so the `Info.plist` minimum-system-version substitution and the linker floor
  continue to describe one contract.
- An explicit non-empty `MACOSX_DEPLOYMENT_TARGET` remains authoritative and is
  preserved byte-for-byte, and it still changes the Cargo and native cache
  fingerprints; callers may still build above the floor locally.
- Intel macOS remains unsupported, Android and non-macOS invocations still
  receive no synthesized macOS policy, and no separate Cargo target directory
  and no per-build clean is introduced.

### 7.3 Verification for this amendment

- `just test-macos-rust-build-contract` covers the `12.0` default, the empty
  value, the three Xcode configuration values, and the shared-cache transition
  from an explicit `26.5` back to the `12.0` floor, which must rebuild the
  affected Rust output rather than reuse it.
- `just test-macos-release-linkage` builds the Release artifact and confirms
  `_frb_get_rust_content_hash` is still exported by the final Mach-O.
- The supported Release artifact must report arm64 with a `12.0` minimum
  platform version in both `Info.plist` (`LSMinimumSystemVersion`) and the
  Mach-O build-version load command, and must keep the Release signing and
  entitlement behavior.

### 7.4 Relationship to the September record

Sections 2 and 5 record the 2026-09-02 correction that moved the declared
targets from `10.15` to `11.0` and introduced the deployment-target
fingerprinting scheme. That account, including its evidence about stale `26.5`
BLAKE3 members in a shared target directory, remains the accurate history of
that work. This amendment changes only the supported floor; it does not revise
the mechanism, the rationale, or the cache-input design those sections
describe.

## 8. Amendment 2026-10-07: deployment fingerprint no longer touches Cargo crate identity

**Current contract:** the deployment-target Rust fingerprint is the benign
custom cfg marker `--cfg=argus_macos_deployment_target_fingerprint_<hex>`,
appended to the highest effective Rust flag source. Everything else in this
document is unchanged: the `12.0` support floor, arm64-only macOS support,
`scripts/run_rust.sh` as the single repository-owned build policy boundary, the
native `-DARGUS_MACOS_DEPLOYMENT_TARGET_FINGERPRINT=<hex>` C flag marker, the
Debug/Profile/Release archive paths, and the signing and entitlement behavior.

### 8.1 Why the representation changed

Cargo already treats the effective Rust flags as a build input and rebuilds the
affected units when they change, so the repository marker only has to make two
deployment targets distinct. The September design did that by appending an
extra `-C metadata=argus-macos-deployment-target-<hex>` value. `-C metadata` is
not a general cache tag: it participates in rustc’s crate identity, so a
repository-controlled value in a flag that Cargo manages makes the repository
share ownership of an input it does not own. The amendment removes that
overlap. The marker is a custom cfg token, which is inert for the product
sources, cannot collide with Cargo’s own metadata, and is still
fingerprinted by Cargo as part of the effective Rust flags.

The change was made while investigating a clean Release build failure in which
host proc-macro crates failed with `error[E0463]: can't find crate for
rustversion`. Differential testing disproved the marker as the cause: the
failure reproduces with the marker removed, in a fresh Cargo target directory,
and in a dependency-free proc-macro crate that never invokes `run_rust.sh`;
verbose pinned-Cargo logs also show that the marker is not part of host
proc-macro `rustc` invocations. The observed failures come from release-profile
proc-macro dylibs whose host debuginfo stripping pass leaves a mis-aligned
LINKEDIT string pool, which `dyld` rejects while loading; that upstream defect
and its resolution are recorded in section 8.4.

### 8.2 Effect on the contract

- The Rust marker is a single token that is representable identically in
  `CARGO_ENCODED_RUSTFLAGS`, `RUSTFLAGS`, target-specific Rust flag variables
  and `CARGO_BUILD_RUSTFLAGS`, so all existing precedence behavior is preserved
  and a caller’s own `-C metadata=...` value is passed through untouched.
- Distinct deployment targets still produce distinct Rust fingerprint markers,
  so returning from an explicit target such as `26.5` to the `12.0` floor
  rebuilds the affected Rust units instead of reusing shared Cargo output.
- The native C flag marker keeps its role for cc-rs and the BLAKE3 native
  objects, because Cargo’s own fingerprint cannot invalidate them when only
  `MACOSX_DEPLOYMENT_TARGET` changes.

### 8.3 Verification for this amendment

`just test-macos-rust-build-contract` asserts that every effective Rust flag
source carries the `--cfg=` marker exactly once, that neither the effective
sources nor the verbose `rustc` invocations carry
`metadata=argus-macos-deployment-target-`, that a caller-supplied
`-C metadata=...` value is preserved, that distinct deployment targets produce
distinct markers, that the shared-output transition from `26.5` back to `12.0`
recompiles the Rust probe and rebuilds the native BLAKE3 members, and that a
clean Release build of the bridge package compiles and loads its host
proc-macro crates with an 8-byte aligned `LC_SYMTAB.stroff` on every produced
build-time dylib. `just test-macos-release-linkage` remains the integration
regression for the Release artifact.

### 8.4 Resolved: Release build-time proc-macro stripping (2026-10-07)

Clean Release builds of the build-time crate graph were entering the
`-C strip=debuginfo` failure mode on the pinned Rust 1.97.1 toolchain. That
stripping pass can emit a host proc-macro dylib whose Mach-O `LC_SYMTAB` string
pool is not 8-byte aligned; `dyld` refuses to load the dylib, and `rustc` then
reports the proc macro as a missing crate. The clean Release bridge build
failed with `error[E0463]: can't find crate rustversion` even though the crate
itself had compiled successfully: the missing-crate message is a symptom of a
build-time dylib load failure, not of a dependency problem. rust-lang/rust
issue #157750 documents the stripping defect and the malformed Mach-O result
it produces.

`rust/Cargo.toml` therefore sets:

```toml
[profile.release.build-override]
strip = "none"
```

The build-override profile applies only to build scripts, proc macros, and
their build-time dependencies. Argus pins `strip = "none"` for those crates so
inherited or otherwise effective stripping cannot corrupt proc-macro dylibs
while the defect is reachable on the pinned toolchain; Cargo's documented
Release profile default is `strip = "none"`, and this override keeps that
guarantee explicit for the affected build-time path. Build-time crates are
never shipped, so shipped Release artifacts are not changed by the override.
The `12.0` support floor, the deployment fingerprint, the Debug/Profile/Release
archive paths, and the current signing and entitlement behavior are all
unchanged, and no package-specific override is used. This is a compatibility
workaround for an upstream compiler/toolchain defect, not a product-behavior
change or a suppression of toolchain diagnostics.

The defect has since been fixed upstream, but the pinned `1.97.1` toolchain
demonstrably remains affected. Keep the override until a future pinned-toolchain
upgrade is explicitly qualified without it. Section 8.3 describes the
regression that keeps the override and the 8-byte-aligned build-time dylibs
asserted.
