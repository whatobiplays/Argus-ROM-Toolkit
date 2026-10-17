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
- ripgrep
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

## Android qualification entrypoints

The phase-neutral host entrypoints accept an owner-private qualification
manifest and an optional host-only flag. The Justfile forwards the manifest as
`--manifest` and forwards a supplied final argument unchanged to the Python
CLI:

```bash
just qualify-android-fresh <manifest-path> --dry-run
just qualify-android-fresh <manifest-path> --preflight
just qualify-android-no-reset <manifest-path> --dry-run
just qualify-android-no-reset <manifest-path> --preflight
```

Omitting the flag requests live execution. That path validates the manifest,
then exits `3` with the live-admission block until Issue #23 provides the
required authorization and device admission controls.

The shell entrypoints expose the same arguments directly:

```bash
bash scripts/qualify_android_fresh.sh --manifest <manifest-path> --dry-run
bash scripts/qualify_android_no_reset.sh --manifest <manifest-path> --preflight
```

`--dry-run` and `--preflight` are equivalent on these entrypoints. Both perform
structural manifest validation only and make no ADB or device calls.
`HOST_VALIDATED` means the manifest has the supported shape and state-mode
references. It does not establish session authorization or admission under
SPEC-X-003, begin a qualification session, or establish qualification status.
Live execution fails closed until Issue #23 implements the required admission
and authorization controls.

The manifest input must be a readable regular UTF-8 JSON file no larger than
64 KiB. Version 1 uses these opaque fields:

```json
{
  "schema_version": 1,
  "authorization_ref": "authorization-example",
  "target_ref": "target-example",
  "artifact_ref": "artifact-example",
  "plan_ref": "plan-example",
  "scope_ref": "scope-example",
  "state_mode": "fresh",
  "inherited_state_session_ref": null
}
```

The no-reset entrypoint requires `state_mode` set to `no-reset` and a non-null
`inherited_state_session_ref`. The fresh entrypoint rejects an inherited
session reference. References are opaque identities; their authorization,
artifact, fixture, digest, and target semantics are deferred to Issue #23.

Exit status `0` reports `HOST_VALIDATED`, `2` reports a sanitized CLI or
manifest validation block, and `3` reports that live execution is blocked
because live authorization and device admission are not implemented.

The historical `scripts/run_phase_003_android_physical_qualification.sh`
command and its `--preflight-only` flag retain their legacy behavior. That flag
is not a device-free dry-run: the historical path can perform ADB/device
preflight work. Use only the new host-only entrypoints above when device
access is not authorized.

## Documentation

Start with:

- `docs/README.md`
- `docs/architecture/architecture-overview.md`
- `docs/phases/phase-003-game-identification-and-enrichment.md` — active implementation milestone
- `docs/phases/phase-000-foundation.md` — implemented foundation and deferred manual completion evidence

The repository documentation is the durable source of architecture and implementation intent.
