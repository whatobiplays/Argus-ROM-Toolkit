# macOS arm64 Rust/native deployment-target contract

**Document ID:** BUILD-MACOS-ARM64-DEPLOYMENT-TARGET
**Status:** Implemented — verified
**Owner:** Daniel
**Date:** 2026-09-02
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

The helper invoked by `scripts/run_rust.sh` owns the following contract:

| Invocation context | Generated macOS environment | Cache behavior |
| --- | --- | --- |
| Darwin arm64 host, effective target `aarch64-apple-darwin`, ordinary Cargo invocation | Set `MACOSX_DEPLOYMENT_TARGET=11.0` when the caller did not provide a non-empty value | Add a deterministic deployment-target input to the macOS-scoped Cargo/native fingerprints while preserving Cargo’s effective caller flags |
| Same native context with an explicit non-empty `MACOSX_DEPLOYMENT_TARGET` | Preserve the caller’s exact value | Fingerprint the explicit value |
| Same native context with `MACOSX_DEPLOYMENT_TARGET=""` | Resolve the empty value to `11.0` | Use the default fingerprint |
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

The helper adds the deployment marker to the highest effective Rust source
already selected by Cargo: encoded flags, global flags, target-specific flags,
or matching target configuration. For target configuration without a target
environment source, it adds a matching target-specific environment marker;
Cargo combines those two sources rather than masking the configuration. When
no higher source is active, it uses `CARGO_BUILD_RUSTFLAGS`. This avoids
introducing a higher-precedence global flag that would silently mask a
caller’s effective Cargo configuration. The marker is a semantically inert
`-C metadata=argus-macos-deployment-target-<hex>` value and changes the Rust
fingerprint without changing linker warning behavior.

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
`ARCHS=arm64` and `MACOSX_DEPLOYMENT_TARGET=11.0`. This makes the product
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

1. Native Darwin arm64 with no explicit value receives 11.0.
2. `aarch64-apple-darwin` is the only supported macOS Rust target; Intel macOS
   hosts/targets are rejected.
3. Native Darwin arm64 with an explicit non-empty value preserves that value;
   an empty value resolves to 11.0.
4. Linux, Android, and non-macOS cross-target invocations receive no generated
   macOS policy or macOS cache input.
5. Existing `RUSTFLAGS`, `CARGO_ENCODED_RUSTFLAGS`, target-specific flags, and
   `build.rustflags` remain effective alongside the deployment marker.
6. Native `cc` flag precedence covers the hyphenated target form, its
   underscore form, `TARGET_CFLAGS`, and plain `CFLAGS` without duplicating
   the marker.
7. Matching target-name and `cfg(...)` Cargo tables, including nested
   expressions, retain their caller flags alongside the deployment marker.
8. Pinned Cargo fingerprints change across 26.5 → 11.0 transitions, and the
   bridge archive is checked for stale 26.5 BLAKE3/native members.
9. Phase 000/001, ordinary Rust validation, CI, and the Xcode phase route
   through `run_rust.sh` where applicable.
10. Debug, Release, and Profile Xcode settings all use arm64/11.0 and retain
   the existing archive paths.
11. The `build-macos-debug` Just target provides the shared, documented
    Flutter macOS Debug build entry point.

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
