# Android qualification operations

This guide describes the public host-validation commands, the internal
qualification test harness, and the boundary around device access. A valid
manifest is only a host validation result; it is not device admission or an
owner qualification verdict. The governing system boundary and acceptance
rules remain in [ARCH-003](../architecture/qualification-architecture.md) and
[SPEC-X-003](../specifications/cross-cutting/spec-x-003-qualification-contract.md).
The private authorization contract and current device-admission limits are
described in [Owner-authorized device admission](device-authorization.md).
The host-only append-only execution ledger, recovery contract, owner verdict
stream, and deterministic review packet are described in
[Durable qualification evidence](evidence-records.md).
The separately identified Android qualification APK can be built and inspected
without a device; see [Android qualification artifact packaging](android-qualification-artifact.md).

The host-only owner fixture preparation contract is described in
[Owner fixture preparation](fixture-staging.md).

## Public host validation

The fresh and no-reset entrypoints accept a qualification manifest and one of
two host-only flags. Both flags perform structural validation without starting
ADB or contacting a device:

```sh
just qualify-android-fresh <manifest-path> --dry-run
just qualify-android-fresh <manifest-path> --preflight
just qualify-android-no-reset <manifest-path> --dry-run
just qualify-android-no-reset <manifest-path> --preflight
```

The shell entrypoints expose the same checks directly:

```sh
bash scripts/qualify_android_fresh.sh --manifest <manifest-path> --dry-run
bash scripts/qualify_android_fresh.sh --manifest <manifest-path> --preflight
bash scripts/qualify_android_no_reset.sh --manifest <manifest-path> --dry-run
bash scripts/qualify_android_no_reset.sh --manifest <manifest-path> --preflight
```

`--dry-run` and `--preflight` are equivalent. Fresh mode requires a fresh-state
manifest with no inherited session reference. No-reset mode requires a
no-reset state and a non-null inherited session reference. Those references
are opaque at this stage; the host check does not establish their authority,
identity, or validity as live-device evidence. The root
[README](../../README.md#android-qualification-entrypoints) documents the
manifest fields and size limit.

The result and process status have these exact meanings:

| Result | Exit status | Meaning |
|---|---:|---|
| `HOST_VALIDATED` | `0` | The manifest has the supported structure and matches the selected state mode. No session or device operation was admitted. |
| Sanitized CLI or manifest validation block | `2` | The command or manifest is invalid. This takes precedence over a live request. |
| `LIVE_ADMISSION_NOT_IMPLEMENTED` | `3` | A structurally valid request omitted the host-only flag and requested live execution. The request was blocked before device access. |

Omitting both host-only flags requests live execution. The public entrypoints
continue to return `LIVE_ADMISSION_NOT_IMPLEMENTED` before device access. The
private authorization and admission interfaces documented below are injected
host-side controls; they do not add a public live command or a concrete device
transport. An exit status of `0` never means a device was reached, a
qualification session began, or qualification passed.

## Internal host test harness

`just test-android-qualification` is the sole combined Python qualification
test recipe. It discovers the host admission tests and the internal physical
scenario harness tests in one package-aware run. The physical scenarios are
exercised with fake devices and explicit test dependencies; they are not
physical-device qualification runs. The test suite also uses a poisoned ADB
shim to verify that host tests do not invoke ADB.

The internal orchestration seam is private to tests and requires a fake device
and explicit dependencies. The public `run()` and `main()` entrypoints, as
well as direct module execution, fail closed before constructing a device.
There is no active public compatibility command for the retired physical
route.

## Owner fixture preparation

The `fixture_staging` module validates ephemeral grants from loaded
authorization and approval inputs, the pinned plan, and the exact fixture
manifest. Public staging and cleanup remain fail-closed with
`BLOCKED_UNSUPPORTED_EXCLUSIVITY` until the host provides an OS-enforced
namespace boundary for the complete destination lifecycle. Transfer,
verification, publication, and recovery mechanics are exercised only through
private synthetic test adapters; they do not establish production isolation.
The result meanings, private manifest contract, capacity reserves, ownership
records, and recovery limits are documented in
[Owner fixture preparation](fixture-staging.md).

Cleanup is restricted to the neutral, device-owned directory
`/sdcard/ArgusQualification`. A cleanup request must name that directory
exactly; it cannot target a child, a neighboring path, or a broader storage
location. Historical paths are preserved only in the archived record linked
from the [archive index](../archive/README.md).

## Test and CI registration

`just test` invokes `just test-android-qualification` once. `just check` reaches
that same invocation through `test`; it does not invoke the combined Python
recipe a second time. The quality gate also runs the archive and naming checks
through `check-qualification-archive` and `check-qualification-naming`. CI's
quality job runs the canonical `just check` gate. The separate
`android-qualification-release` CI job packages and verifies the qualification
APK without production signing values, then checks that ordinary Release
packaging fails closed. The existing `android-arm64-package` Debug job remains
unchanged.

## Archive and naming checks

The former device-facing physical command has been retired and removed. It has
no active alias, fallback, or compatibility entrypoint. Do not restore it as a
public command. The preserved source and historical record are indexed in
[docs/archive/README.md](../archive/README.md); that material is evidence of
the former implementation, not current operating guidance.

The versioned archive manifest records the baseline, archived inventory,
original and preserved paths, roles, and SHA-256 digests. The archive check
compares the preserved files with the fixed baseline. Historical source and
observations do not define current acceptance criteria.

The [current surface classification registry](surface-classifications-v1.json)
is the reviewed inventory used by the naming check. It carries forward the
[archived Issue21 inventory](../archive/qualification/issue-21-v1/surface-classifications-v1.json)
as historical provenance and adds the current qualification surfaces. The
naming check validates the current registry and each declared region, then
checks active regions for prohibited planning labels. A compatibility-only
entry records history; it does not make a retired route callable.

The exact historical names below are retained only as the reviewed naming
crosswalk. They are not active commands or supported interfaces.

| Previous active name | Status | Current neutral surface |
|---|---|---|
| `scripts/phase_003_android_physical_qualification` | Retired and archived | `scripts/android_qualification/physical` |
| `scripts/run_phase_003_android_physical_qualification.sh` | Retired and archived | `retired; no active compatibility entrypoint` |
| `docs/implementation/phase-003-android-physical-automation.md` | Retired and archived | `docs/qualification/README.md` |
| `ArgusPhase003Qualification` | Retired and archived | `ArgusQualification` |

## Android qualification artifact

`just build-android-qualification` packages a Flutter Release AOT APK with the
separate `com.argusromtoolkit.argus.qualification` identity and ordinary Android
debug signing. `just verify-android-qualification` independently inspects the
APK, its exact permission inventory, FileProvider URI grants and path mapping,
signature, ARM64 native libraries and release-profile absence of compiler debug
sections, Rust-versus-Flutter version agreement, Release payload, and embedded
source record. Neither command starts ADB or contacts a device.

The artifact and provenance workflow is documented in
[Android qualification artifact packaging](android-qualification-artifact.md).
A dirty worktree produces only `PROVISIONAL_ARTIFACT`; clean-revision
`ARTIFACT_VALIDATED` output is required before physical admission.

A cold checkout does not need a Debug build first. The qualification build
runs Flutter's Release `--config-only` preparation to generate the ignored
Android Gradle wrapper and local configuration, then captures the source-state
fingerprint and packages the isolated qualification variant. Generated Kotlin
session files under `flutter/android/.kotlin/` are ignored and do not make the
source appear dirty.

## Deferred follow-on work

The Issue #23 safety layer provides a private authorization contract, injected
read-only admission, and a typed permission-operation boundary. These controls
are not connected to the public commands above. No live ADB transport is
included, no-reset admission remains blocked until an independent baseline
observer exists, and the public live route remains fail-closed. Host-only
transfer and publication mechanics are implemented only behind private
synthetic test adapters; public production staging remains blocked pending an
OS-enforced namespace boundary. Its evidence reports matches against
owner-approved expectations and does not independently establish game identity.
Device-side fixture admission, live execution orchestration, product scenarios,
and physical qualification remain deferred to their separately scoped issues.
The host-only durable execution and owner-review storage contract described in
[Durable qualification evidence](evidence-records.md) is implemented without a
CLI, device transport, live runner, release assessor, or product verdict.
See [Owner-authorized fixture preparation](fixture-staging.md)
for the manifest, coverage, timeout, and recovery contract, and see
[Owner-authorized device admission](device-authorization.md) for the
authorization format, evidence limits, and supported operation.
