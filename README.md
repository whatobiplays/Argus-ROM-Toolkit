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

Cleanup targets a fixed inventory of repository-owned generated directories.
Preview is read-only and uses the same admission policy as apply:

```bash
just clean-preview
just clean
just clean-deep-preview
just clean-deep
```

`just clean-preview-deep` remains a compatibility alias for
`just clean-deep-preview`. The commands are offline and do not invoke
Cargo, Gradle, Xcode, Flutter, Python build tools, or package managers.

### Approved directory ownership

Routine cleanup removes these complete roots:

1. `rust/target`
2. `flutter/build/app/intermediates`
3. `flutter/build/app/generated`
4. `flutter/build/app/tmp`
5. `flutter/build/app/.cxx`
6. `flutter/build/macos/Build/Intermediates.noindex`
7. Every `scripts/**/__pycache__` directory found by walking the `scripts`
   tree without following symbolic links

Deep cleanup additionally removes these complete roots:

1. `flutter/.dart_tool/flutter_build`
2. `flutter/android/.gradle`
3. `flutter/android/.kotlin`

No other directory is approved for cleanup. An admitted root is an ownership
boundary: cleanup removes the entire approved directory, including unknown
names, extensionless files, dot files, lock files, fingerprint state, native
and cross-compilation output, and files whose names resemble credentials,
APKs, ROMs, or other durable artifacts. Internal filenames and producer
signatures do not change eligibility.

Do not place durable files anywhere inside an approved cleanup root. Move
evidence, packages, source, configuration, and other retained data outside
those directories before running cleanup. Cleanup never removes an approved
root's parent directory. Similar paths and every path outside the approved
roots remain protected.

The preview and apply reports identify durable locations outside cleanup
roots that are intentionally retained, including review evidence,
qualification records, `flutter/lib`, the FVM SDK, Android application
outputs, and distribution artifacts.

### Safety checks and limits

Before admitting a candidate, cleanup verifies that it is in the physical Git
worktree containing the invoked helper and that Git context was not redirected
through ambient repository environment variables. The candidate path must
match an approved root exactly. The helper rejects a symbolic-link root or
symbolic-link ancestor, tracked content beneath the root, nested Git
repositories and worktrees, and a root that the repository ignore policy does
not classify as generated.

A symbolic link inside an admitted tree is unlinked as a symbolic link; its
target is never followed. Unsupported filesystem objects fail the candidate
instead of being traversed or removed. A `CARGO_TARGET_DIR` redirect makes
`rust/target` ineligible.

Cleanup compares the `st_dev` filesystem device identity of the candidate and
each descendant. Different-device boundaries are detected and reject the
entire candidate.
Same-device bind mounts cannot be distinguished by these checks and are not
claimed to be detected.

A safety failure rejects the complete candidate before deletion, so none of
its content is removed. Other candidates may still succeed, and apply reports
that result as partial rather than implying a transaction.

### Reporting and idle operation

Preview reports selected roots, rejected roots with policy reasons, categories,
logical estimated bytes, snapshot reliability, and operational warnings. Apply
revalidates the safety policy and reports each outcome plus
`verified_reclaimed_bytes` for entries no longer present.

Byte counts are logical file and symbolic-link sizes, not allocated filesystem
space. Hard-linked entries are counted once by device and inode. Directory
metadata is excluded. A recursive deletion or permission failure produces a
nonzero apply result and a failed or partial report so a later run can retry.

Run cleanup only in an idle checkout. Do not run a build, test, generator, IDE
operation, package manager, or another cleanup command at the same time.
Cleanup does not detect or coordinate with active processes, so it assumes
that no process is writing beneath the approved roots.

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
