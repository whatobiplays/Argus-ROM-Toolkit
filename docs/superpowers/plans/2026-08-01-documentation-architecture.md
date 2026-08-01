# Documentation Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a canonical, navigable documentation system for Argus ROM Toolkit that future chats, Codex agents, and maintainers can use as the repository source of truth.

**Architecture:** Keep the existing architecture overview as the top-level system specification. Add purpose-specific directories, status and identifier conventions, one-way reference rules, indexes, and reusable templates for phases, subsystem specifications, implementation slices, Codex tasks, ADRs, references, and conventions.

**Tech Stack:** Markdown, Git, repository-local documentation.

## Global Constraints

- Documentation is the canonical source of architectural and implementation intent.
- References point from lower-level documents to higher-level documents, never the reverse as a dependency.
- Stable document identifiers remain valid even when filenames change.
- Do not duplicate architecture rationale in implementation slices or Codex tasks.
- Status values are limited to Draft, Ready for Implementation, In Progress, Complete, and Deprecated.
- The repository is a solo-development project; Daniel is the default document owner and readiness authority.

---

### Task 1: Define the documentation architecture

**Files:**
- Create: `docs/architecture/documentation-architecture.md`
- Modify: `docs/architecture/architecture-overview.md`

**Interfaces:**
- Consumes: the approved architecture overview and documentation hierarchy decisions.
- Produces: canonical document types, identifiers, metadata, status lifecycle, reference direction, and readiness rules.

- [ ] Create the documentation architecture specification.
- [ ] Add canonical metadata to the architecture overview.
- [ ] Verify both documents agree on the documentation hierarchy.

### Task 2: Add repository indexes and category ownership

**Files:**
- Create: `docs/README.md`
- Create: category `README.md` files under `phases`, `specifications`, `implementation`, `tasks`, `adr`, `reference`, and `conventions`.

**Interfaces:**
- Consumes: documentation architecture.
- Produces: discoverable entry points and placement rules for every document category.

- [ ] Create the root documentation index.
- [ ] Create category indexes with purpose, exclusions, identifiers, and status rules.
- [ ] Verify all documented paths exist.

### Task 3: Add reusable document templates

**Files:**
- Create: templates for phase, subsystem specification, implementation slice, Codex task, ADR, reference, and convention documents.

**Interfaces:**
- Consumes: canonical metadata and readiness rules.
- Produces: consistent authoring contracts for future documentation.

- [ ] Create each template with required metadata and sections.
- [ ] Ensure templates contain measurable completion/readiness criteria where applicable.
- [ ] Verify templates do not contain conflicting ownership or status rules.

### Task 4: Review the documentation system

**Files:**
- Review all files under `docs/`.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: a coherent documentation tree ready for Phase 00 design.

- [ ] Inspect the final tree.
- [ ] Check identifiers, links, statuses, and terminology for consistency.
- [ ] Confirm no unresolved placeholder text exists outside intentionally blank template fields.
