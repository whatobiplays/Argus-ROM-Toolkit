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

Use [the Codex task template](../templates/codex-task.md).
