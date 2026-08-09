# Subsystem Specifications

Specifications define how backend, frontend, and cross-cutting subsystems behave.

```text
specifications/
├── backend/
├── frontend/
└── cross-cutting/
```

**Identifier formats:**

- `SPEC-BE-NNN`
- `SPEC-FE-NNN`
- `SPEC-X-NNN`

Current indexes:

- [Backend specifications](backend/README.md)
- [Frontend specifications](frontend/README.md)
- [Cross-cutting specifications](cross-cutting/README.md)

Specifications own interfaces, state/data models, workflows, persistence behavior, failures, security, and testing requirements. They do not own implementation ordering or Codex task boundaries.

Use [the subsystem specification template](../templates/subsystem-specification.md).
