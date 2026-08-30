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

## Documentation

Start with:

- `docs/README.md`
- `docs/architecture/architecture-overview.md`
- `docs/phases/phase-001-local-sources-and-indexing.md` — active implementation milestone
- `docs/phases/phase-000-foundation.md` — implemented foundation and deferred manual completion evidence

The repository documentation is the durable source of architecture and implementation intent.
