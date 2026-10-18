# Argus ROM Toolkit Documentation

This directory is the canonical engineering knowledge base for Argus ROM Toolkit.

## Start Here

1. [Architecture Overview](architecture/architecture-overview.md) — complete backend/frontend architecture and MVP boundaries.
2. [Documentation Architecture](architecture/documentation-architecture.md) — document hierarchy, identifiers, statuses, ownership, and reference rules.
3. [Phases](phases/README.md) — capability sequencing and implementation readiness. Current milestone: [PHASE-003 — Game Identification and Enrichment](phases/phase-003-game-identification-and-enrichment.md); the implemented Phase 000 and Phase 001 baselines remain `In Progress` only because their explicitly deferred manual evidence is still `NOT RUN`.
4. [Specifications](specifications/README.md) — subsystem contracts and behavior.
5. [Implementation](implementation/README.md) — approved vertical slices.
6. [Tasks](tasks/README.md) — bounded Codex implementation tasks.

## Documentation Layers

| Layer | Purpose | Typical reader |
|---|---|---|
| Architecture | Defines what Argus is and its system-wide invariants | Everyone |
| Reference | Defines canonical vocabulary and registries | Everyone |
| Phase | Defines the next user-visible capability and its exit criteria | Daniel, planning agents |
| Specification | Defines how a subsystem behaves | Implementers, reviewers |
| Implementation slice | Defines one independently testable increment | Codex, reviewers |
| Task | Defines one bounded repository change | Codex |
| ADR | Records why a durable architectural choice was made | Future maintainers |
| Convention | Defines repeatable engineering rules | All contributors and agents |

## Directory Map

```text
docs/
├── README.md
├── architecture/
│   ├── architecture-overview.md
│   └── documentation-architecture.md
├── phases/
├── specifications/
│   ├── backend/
│   └── frontend/
├── implementation/
├── tasks/
├── adr/
├── reference/
├── conventions/
├── templates/
└── superpowers/plans/
```

## Source-of-Truth Rule

Do not rely on chat history as the durable specification. Material decisions made in chat must be written into the appropriate repository document before implementation depends on them.

Lower-level documents may refine higher-level documents but must not contradict them. When a conflict exists, the higher-level document controls until it is formally revised.

`Ready for Implementation` describes design maturity, not blanket implementation authorization. An agent implements only the intersection of the active phase, active slice or approved plan, explicit task authority, and governing documents; later-ready specifications constrain compatibility without expanding current scope.


## Qualification authority

- [Qualification operations](qualification/README.md) documents the public host-validation commands, exit semantics, internal test-harness boundary, and retired-route policy.
- [Archive index](archive/README.md) locates preserved qualification records and the reviewed surface-classification artifact.
- [Qualification architecture (ARCH-003)](architecture/qualification-architecture.md) defines the system boundary and invariants.
- [Qualification contract (SPEC-X-003)](specifications/cross-cutting/spec-x-003-qualification-contract.md) defines acceptance, evidence, applicability, owner verdict, and readiness requirements.
- [Qualification glossary (REF-QUAL-001)](../CONTEXT.md) provides canonical vocabulary.
- [Qualification decision and approval record (REF-QUAL-002)](reference/qualification-design-decisions.md) preserves all 126 source decisions and the verified package/hash approval record.
- [ADR-001 through ADR-003](adr/README.md) record the three accepted decisions.
