# Codex Task Plans

Task plans define one bounded repository change for Codex.

Task planning, result reporting, documentation impact, and Git authorization follow [CONV-DOC-001](../conventions/conv-doc-001-documentation-and-codex-result-conventions.md).

**Identifier format:** `TASK-P<phase>-NNN`

Each task must identify:

- parent slice and specifications
- exact files to inspect
- allowed and forbidden paths
- interfaces consumed and produced
- explicit implementation scope and exclusions
- acceptance criteria
- verification commands
- expected result reporting

A task may suggest an intended commit boundary, but that is planning guidance only. Codex must not stage, commit, or push unless the user explicitly requests the corresponding Git write.

Tasks must not contain unresolved design choices.

A task's executable scope is the intersection of its active phase, parent implementation slice or approved plan, explicit allowed/forbidden paths and deliverable, and governing architecture/specifications/conventions. Referencing a Ready future specification does not authorize speculative modules, routes, DTOs, migrations, dependencies, fixtures, tests, placeholders, or generated output.

If a task appears broader than its parent phase or slice, correct or surface the authority conflict rather than silently expanding implementation.

Use [the Codex task template](../templates/codex-task.md).
