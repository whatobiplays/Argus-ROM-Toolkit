# Argus Documentation Architecture

**Document ID:** ARCH-002  
**Status:** Complete  
**Owner:** Daniel  
**Last Updated:** 2026-08-01  
**Depends On:** ARCH-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This document defines how Argus engineering knowledge is organized, identified, reviewed, referenced, and converted into Codex implementation work.

The repository—not chat history—is the durable source of truth.

## 2. Documentation Hierarchy

```text
Architecture
    ↓
Reference documents
    ↓
Phase specifications
    ↓
Subsystem specifications
    ↓
Implementation slices
    ↓
Codex task plans
```

ADRs and conventions support all levels without replacing them.

## 3. Document Types

### 3.1 Architecture

Answers: **What is Argus, and what system-wide constraints govern it?**

Architecture documents contain system boundaries, major components, cross-cutting invariants, and durable architectural direction. They do not contain task sequencing or file-by-file implementation instructions.

Identifier: `ARCH-NNN`

### 3.2 Reference

Answers: **What is the canonical vocabulary or registry?**

Examples include platform IDs, artwork taxonomy, event catalog, error catalog, job types, provider capabilities, and hash-scheme registries.

Identifier: `REF-<AREA>-NNN`

### 3.3 Phase

Answers: **What user-visible capability is being built next?**

A phase defines dependencies, scope, exclusions, deliverables, ordered implementation slices, and measurable exit criteria. A phase is not a Codex task.

Identifier: `PHASE-NNN`

### 3.4 Subsystem Specification

Answers: **How must one subsystem behave?**

A specification defines responsibilities, public interfaces, data/state models, workflows, failure behavior, persistence, security, and tests. It does not assign work or prescribe commit order.

Identifiers:

- Backend: `SPEC-BE-NNN`
- Frontend: `SPEC-FE-NNN`
- Cross-cutting: `SPEC-X-NNN`

### 3.5 Implementation Slice

Answers: **What independently testable increment advances a phase?**

A slice references its phase and required specifications. It defines one vertical deliverable across the necessary layers, acceptance criteria, and verification strategy.

Identifier: `SLICE-P<phase>-NNN`

Example: `SLICE-P00-003`.

### 3.6 Codex Task

Answers: **What exact bounded repository change should Codex implement?**

A task names files to inspect and edit, interfaces consumed and produced, acceptance criteria, exclusions, verification commands, and completion reporting.

Identifier: `TASK-P<phase>-NNN`

### 3.7 Architecture Decision Record

Answers: **Why was a durable architectural choice made?**

An ADR records context, options, decision, consequences, and supersession. It does not become a second subsystem specification.

Identifier: `ADR-NNN`

### 3.8 Convention

Answers: **What repeatable engineering rule should every contributor follow?**

Examples include Rust layout, Flutter feature boundaries, naming, errors, logging, tests, generated files, and documentation style.

Identifier: `CONV-<AREA>-NNN`

## 4. Status Lifecycle

Allowed statuses:

```text
Draft
Ready for Implementation
In Progress
Complete
Deprecated
```

### Draft

The document may contain unresolved decisions or incomplete criteria. Codex must not implement from a Draft phase, slice, or task.

### Ready for Implementation

The scope is accepted by Daniel, blocking design decisions are resolved, dependencies are identified, and readiness criteria pass.

### In Progress

Repository implementation has begun against the document.

### Complete

The document's measurable exit or acceptance criteria pass in the repository.

### Deprecated

The document is no longer authoritative. It must identify its replacement when one exists.

## 5. Solo-Development Readiness

This is a solo project. “Ready for Implementation” does not imply a committee approval process.

A phase becomes ready when:

1. Daniel accepts the intended capability and scope.
2. The document passes its readiness checklist.
3. No blocking architecture or product decisions remain.
4. Required subsystem specifications are available or explicitly scheduled before their dependent slice.

Daniel is the default owner and readiness authority unless a document states otherwise.

## 6. Required Metadata

Every governed document begins with:

```text
Document ID
Status
Owner
Last Updated
Depends On
Supersedes
Superseded By
```

Use `None` rather than omitting a field.

Templates may contain bracketed authoring prompts. Ready or Complete documents may not contain unresolved prompts, `TBD`, or `TODO` markers.

## 7. Reference Direction

Dependencies point upward:

```text
Phase → Architecture / Reference
Specification → Architecture / Phase / Reference
Slice → Phase / Specification / Reference
Task → Slice / Specification / Convention / Reference
```

Higher-level documents should not depend on lower-level implementation tasks.

Related-document links may be bidirectional for navigation, but the authoritative `Depends On` relationship must remain acyclic.

## 8. Ownership Boundaries

### Architecture

Owns system-wide design and invariants.

### Reference

Owns canonical vocabulary; other documents link to it instead of redefining it.

### Phase

Owns capability sequencing, scope, and exit criteria.

### Specification

Owns subsystem behavior and interfaces.

### Slice

Owns one vertical increment and acceptance criteria.

### Task

Owns one bounded repository change.

### Convention

Owns repeatable engineering rules.

## 9. Change Rules

- Material architecture changes require updating ARCH-001 and, when rationale matters, adding or superseding an ADR.
- A lower-level document must not silently override a higher-level one.
- When implementation reveals a specification defect, fix the specification before or with the implementation change.
- Filenames may change; stable document IDs must not be reused.
- Superseded documents remain in history and identify the replacement.
- Duplicated definitions must be consolidated into the highest appropriate reference or specification document.

## 10. Phase Readiness Checklist

```text
[ ] User-visible outcome is defined
[ ] Dependencies are available or explicitly sequenced
[ ] Scope and exclusions are explicit
[ ] Required public interfaces are identified
[ ] Persistence impact is identified
[ ] Failure and cancellation behavior are identified
[ ] Security and privacy impact is identified
[ ] Test requirements are specified
[ ] Implementation slices are ordered
[ ] Exit criteria are measurable
[ ] No blocking design questions remain
[ ] Daniel has accepted the intended capability and scope
```

## 11. Implementation-Slice Rule

After the minimal foundation phase, slices should be vertical. Each slice must produce observable, independently testable behavior across all required layers rather than merely adding an unused internal abstraction.

A slice may introduce infrastructure only when that infrastructure is required by the slice's user-visible or externally observable outcome.

## 12. Codex Task Rule

Codex tasks must be narrower than slices. Each task must:

- identify exact files or allowed paths
- define interfaces consumed and produced
- state explicit exclusions
- include acceptance criteria
- include verification commands
- preserve a compiling/testable repository
- produce a result summary
- avoid unresolved product or architecture decisions

## 13. Documentation Quality Gate

Before moving to Ready or Complete:

1. Search for unresolved placeholders.
2. Check internal consistency and terminology.
3. Verify links and document IDs.
4. Confirm scope fits the document type.
5. Confirm dependencies are acyclic.
6. Confirm requirements are testable where applicable.

## 14. Current Canonical Documents

| ID | Document | Status |
|---|---|---|
| ARCH-001 | [Architecture Overview](architecture-overview.md) | Complete |
| ARCH-002 | Documentation Architecture | Complete |

## 15. Next Documentation Milestone

Create and bring `PHASE-000`—the minimal foundation phase—to Ready for Implementation. Then write only the subsystem specifications required by its first vertical slices.
