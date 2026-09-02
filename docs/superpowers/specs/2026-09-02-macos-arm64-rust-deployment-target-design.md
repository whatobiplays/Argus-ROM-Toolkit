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

The current Xcode project declares `MACOSX_DEPLOYMENT_TARGET=10.15`, while an
arm64 Xcode link on this host resolves to an effective minimum of 11.0. A
normal Rust build can therefore produce arm64 objects at 11.0, but a shared
target directory can also contain objects produced after a caller supplied a
newer deployment target.

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
| Darwin host, effective target `aarch64-apple-darwin`, ordinary Cargo invocation | Set `MACOSX_DEPLOYMENT_TARGET=11.0` only when the caller did not provide it | Add a deterministic deployment-target input to the macOS-scoped Cargo fingerprint while preserving existing target-specific flags |
| Same native context with an explicit `MACOSX_DEPLOYMENT_TARGET` | Preserve the caller’s exact value | Fingerprint the explicit value |
| Android `cargo ndk` or an explicit non-macOS target | Do not synthesize a macOS deployment target or macOS cache input | Leave Android/cross-compilation behavior unchanged |
| Non-Darwin host | Do not synthesize a macOS deployment target or macOS cache input | Leave the existing workflow unchanged |

The helper must not remove an explicitly supplied environment variable. The
default is applied only to the native Apple Silicon macOS build domain, and
the cache input is scoped to the native macOS build domain so Android and other
cross-compilation workflows cannot inherit macOS policy.

The cache input is a semantically inert global `RUSTFLAGS` salt applied only
inside the native arm64 macOS build domain and derived from the effective
deployment target. Global Rust flags are required here because Cargo can
otherwise leave a dependency build-script/native-output path fresh while
rebuilding only the root crate. The salt is deliberately part of Cargo’s
fingerprint inputs so changing from one deployment target to another rebuilds
dependency objects, Rust objects, and the final `libargus_bridge.a`; it is not
a linker flag and is not used to alter warning behavior. Existing
caller-provided global and target-specific Rust flags remain intact.

## 4. Xcode and phase integration

The project-level Debug, Release, and Profile configurations will declare
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

Focused contract tests will exercise the helper without requiring every host
platform:

1. Native Darwin arm64 with no explicit value receives 11.0.
2. Native Darwin arm64 with an explicit value preserves that value.
3. Linux, Android, and non-macOS cross-target invocations receive no generated
   macOS policy or macOS cache salt.
4. Existing target-specific Rust flags are preserved and the deployment input
   changes the cache salt.
5. Phase 000/001 and the Xcode phase still route through `run_rust.sh`.
6. Debug, Release, and Profile Xcode settings all use 11.0 and retain the
   existing archive paths.

The implementation will be verified with shellcheck, the repository’s
`just check`/focused checks, a one-time targeted cleanup of pre-existing
artifacts, a normal Rust build/test, direct inspection of arm64 archive member
load commands, and Flutter macOS Debug builds. The final macOS archive must
contain no object newer than the link deployment target, including BLAKE3
native objects.

## 6. Non-goals and risks

This change does not introduce separate target directories, change Rust or
Flutter architecture, raise an arbitrary product minimum, clean Cargo output
on every invocation, or suppress linker diagnostics. The main residual risk
is an unusual external Cargo invocation that bypasses `run_rust.sh`; repository
build paths remain governed by the shared wrapper, and the project contract
will document that boundary.
