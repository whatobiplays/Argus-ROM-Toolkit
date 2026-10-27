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

## Generated output cleanup

The cleanup commands inspect only the physical Git worktree containing the
invoked Justfile. They are offline and do not build, install tools, fetch
dependencies, or call platform toolchains. Preview first:

```bash
just clean-preview
just clean-deep-preview
```

Apply the same selection policy with `just clean` or `just clean-deep`.
`just clean-preview-deep` remains a compatibility alias for
`just clean-deep-preview`.

Routine cleanup selects these untracked, producer-owned output roots:

1. `rust/target`
2. `flutter/build/app/intermediates`
3. `flutter/build/app/generated`
4. `flutter/build/app/tmp`
5. `flutter/build/app/.cxx`
6. `flutter/build/macos/Build/Intermediates.noindex`
7. Eligible `scripts/**/__pycache__` bytecode directories

Deep cleanup also selects `flutter/.dart_tool/flutter_build`,
`flutter/android/.gradle`, and `flutter/android/.kotlin`. These are
project-local generated caches. Removing them can force Dart or Kotlin
regeneration and longer platform builds. Package configuration, generator
projects, cargo-ndk state elsewhere beneath `.dart_tool`, the FVM SDK, and
global package caches are retained.

Cleanup uses explicit positive allowlists and retains tracked content plus
unknown or unclassified entries. It also retains nested `.chatgpt/`, `.codex/`,
and `.superpowers/` state; archives and qualification records; environment and
machine-local files; credentials, databases, ROMs, and signing material;
distributable packages and APKs; generated Dart source; test fixtures; root
`build/`; `flutter/.fvm/`; Android IDE/build outputs;
`flutter/build/native-jni/`; and `flutter/build/qualification/`. Candidate
directories, generic data files, and individual files must match reviewed
producer layouts and signatures. A `CARGO_TARGET_DIR` redirect makes
`rust/target` ineligible.

The physical worktree root is resolved before Git confirmation. Candidate
roots and their static parent components cannot be symbolic links, and
candidates cannot cross a filesystem boundary or contain nested Git state.
An intermediate candidate parent containing `.git` is refused even when it is
a nested repository or another linked worktree. Tracked files and protected
names are never removed.

Preview reports each selected or skipped path, its category, the policy
reason, and an estimated logical byte count. The estimate excludes directory
metadata and filesystem allocation, and hard-linked entries count once. Apply
reports `verified_reclaimed_bytes` from entries that are gone after successful
file or symbolic-link deletion. Python bytecode writes are disabled before the
cleanup policy is imported, including for direct helper invocation.

Run cleanup only on an idle checkout. Do not run a build, test,
generator, IDE operation, package manager, or another cleanup command at the
same time. Cleanup does not detect or coordinate with other processes.
Ordinary permission or recursive deletion failures return a nonzero status,
retain the content that remains, and produce a failed or partial report so a
later cleanup can retry it. Inaccessible Python cache trees are reported rather
than silently skipped; preview fails and apply returns a failed or partial
status.

## Android qualification entrypoints

The host-only entrypoints accept an owner-private qualification
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

### Android qualification APK

```bash
just build-android-qualification
just verify-android-qualification
```

The build produces a Flutter Release AOT APK with the separate
`com.argusromtoolkit.argus.qualification` application ID and ordinary Android
debug signing. The ordinary application ID and distributable Release signing
requirements remain unchanged. Verification independently checks the merged
manifest, exact permission inventory, FileProvider URI grants and path mapping,
signature, version identity including the Rust workspace version, ARM64 native
libraries without compiler debug sections, Flutter Release payload, and source
provenance. It compares every packaged native library with the declared
release-profile build metadata. A dirty worktree is reported as
`PROVISIONAL_ARTIFACT` and is not eligible for physical admission.

See [Android qualification artifact packaging](docs/qualification/android-qualification-artifact.md)
for the host-only build contract, outputs, provenance fields, and limitations.

The former physical qualification command is retired. See
[Qualification operations](docs/qualification/README.md) for the canonical host
suite and device-isolation rules, and the [archive index](docs/archive/README.md)
for preserved records, surface classifications, and archive provenance.

Host-only owner fixture preparation is documented in
[Owner fixture preparation](docs/qualification/fixture-staging.md). Live-device
authorization, installation, device-side fixture admission, and product
qualification remain deferred follow-on work.

## Documentation

Start with:

- `docs/README.md`
- `docs/architecture/architecture-overview.md`
- `docs/phases/phase-003-game-identification-and-enrichment.md` — active implementation milestone
- `docs/phases/phase-000-foundation.md` — implemented foundation and deferred manual completion evidence

The repository documentation is the durable source of architecture and implementation intent.
