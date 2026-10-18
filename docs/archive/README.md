# Archive index

This index locates preserved historical material. Archived files support
traceability and audit; they do not provide active commands, compatibility
guarantees, or current acceptance authority. Use the current
[qualification operations guide](../qualification/README.md) for supported
host-validation behavior.

## Qualification archive

The [versioned archive manifest](qualification/issue-21-v1/archive-manifest-v1.json)
records the fixed baseline, preserved file inventory, original and archived
paths, file roles, and SHA-256 digests. The preserved source and technical
record are under `qualification/issue-21-v1/original/`.

### Qualification surface classification

The [surface classification artifact](qualification/issue-21-v1/surface-classifications-v1.json)
lists reviewed qualification surfaces by path and region. The four
classification values have these meanings:

| Classification | Meaning |
|---|---|
| `active` | A current qualification entrypoint, implementation, workflow, recipe, or technical document. These regions are subject to active naming checks. |
| `compatibility_only` | Retained internal support or explicit historical-name crosswalks. These do not create a supported public route. |
| `archival_planning` | Historical qualification material that is not current operating guidance or implementation authority. |
| `unrelated_development_test` | Test-only surfaces recorded for classification completeness and excluded from the active-surface naming scan. |

## Authority and checks

The classification artifact is the reviewed inventory that scopes
`just check-qualification-naming`. The check validates the artifact's schema,
required surfaces, categories, and declared file regions, then searches only
`active` regions for prohibited numbered planning labels. A compatibility-only
entry records why a historical reference remains; it does not enable that
route.

The archive manifest is authoritative for the preserved file list and byte
digests. `just check-qualification-archive` verifies those files against the
fixed repository baseline. Neither artifact changes the active qualification
contract in [ARCH-003](../architecture/qualification-architecture.md) or
[SPEC-X-003](../specifications/cross-cutting/spec-x-003-qualification-contract.md).
