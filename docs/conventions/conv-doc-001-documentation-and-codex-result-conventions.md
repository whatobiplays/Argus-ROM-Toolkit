# Documentation and Codex Result Conventions

**Document ID:** CONV-DOC-001  
**Status:** Ready for Implementation  
**Owner:** Daniel  
**Last Updated:** 2026-08-11  
**Depends On:** ARCH-001, ARCH-002, PHASE-000, CONV-REPO-001, CONV-TEST-001  
**Supersedes:** None  
**Superseded By:** None

## 1. Purpose

This convention defines repeatable documentation-maintenance, Codex-task, implementation-result, evidence-reporting, and agent-artifact rules for Argus ROM Toolkit.

It operationalizes ARCH-002's central rule:

> **The repository—not chat history—is the durable source of truth.**

The convention exists so that human work, ChatGPT-assisted planning, and Codex implementation all leave the repository in a state where a future session can determine:

- what Argus is intended to do;
- which document owns each durable requirement;
- which implementation work is approved;
- what was actually implemented;
- what verification actually ran;
- which deviations were accepted;
- whether work is modified, staged, committed, or pushed;
- what remains unresolved.

This convention does not turn raw agent transcripts into documentation. Agent output is transient unless reviewed facts are promoted into the governed repository document that owns them.

## 2. Governing Invariant

> **Agent output is transient; repository knowledge is durable. A Codex run may explain what happened, but only reviewed source, tests, governed documentation, and Git history define what Argus now is.**

A second operational rule follows:

> **Every durable fact should have one obvious repository owner, and governed documentation must describe the current intended system rather than preserve the history of how an agent happened to implement it.**

## 3. Scope

This convention owns repository-wide rules for:

- governed engineering-document maintenance;
- document ownership and duplication avoidance;
- metadata/status discipline;
- index and link maintenance;
- documentation quality gates;
- Codex task boundaries;
- Codex deviations from a task;
- Codex result reporting;
- verification-evidence wording;
- completion summaries;
- transient `.chatgpt`/agent artifacts;
- implementation discoveries that affect documentation;
- Git commit/push authorization for Codex work.

It does not redefine:

- the documentation hierarchy and document-type semantics owned by ARCH-002;
- architecture or subsystem behavior owned by architecture/specification documents;
- repository Git/generated-file policy owned by CONV-REPO-001;
- test evidence semantics owned by CONV-TEST-001;
- language-specific implementation conventions;
- the technical behavior of ChatGPT/Codex tooling itself.

## 4. Documentation Authority

Argus uses one authoritative owner for each durable kind of fact.

| Durable fact | Owning document type |
|---|---|
| System-wide invariant or architecture | `ARCH-*` |
| Canonical vocabulary or registry | `REF-*` |
| Phase capability, sequencing, and exit criteria | `PHASE-*` |
| Subsystem behavior/interface | `SPEC-*` |
| Independently testable vertical increment | `SLICE-*` |
| Bounded repository implementation change | `TASK-*` |
| Repeatable engineering rule | `CONV-*` |
| Durable architectural decision rationale | `ADR-*` |

Lower-level documents may summarize higher-level context, but they must clearly defer to the authoritative owner and must not redefine it inconsistently.

## 5. Single-Source-of-Truth Rule

Do not duplicate a durable definition merely to make a document self-contained.

Prefer:

```text
TASK-P00-003
  depends on SPEC-BE-005
  states the exact behavior this task must implement
  links to SPEC-BE-005 for the authoritative settings contract
```

over copying the full settings contract into the task.

A short contextual summary is acceptable when it helps the reader understand why the lower-level document exists. The summary must not become a second normative definition.

When duplicated requirements are discovered, consolidate them into the highest appropriate owner and replace lower-level copies with references where practical.

## 6. Governed Document Metadata

Governed engineering documents follow ARCH-002 and begin with:

```text
Document ID
Status
Owner
Last Updated
Depends On
Supersedes
Superseded By
```

Use `None` rather than silently omitting an applicable metadata field.

### 6.1 Document IDs

Document IDs are stable identities.

Rules:

1. Do not reuse an ID for a different document.
2. A filename/location change does not change the document ID.
3. References should use the stable ID in prose even when they also link by repository-relative path.
4. A superseded document retains its original ID in history.

### 6.2 Last Updated

`Last Updated` changes when the governed document materially changes.

Do not create timestamp churn for formatting-only operations that do not change document content/meaning unless tooling makes that unavoidable.

### 6.3 Owner

Daniel is the default owner/readiness authority for this solo-developed repository unless a document explicitly states another owner.

## 7. Status Lifecycle

Allowed governed-document statuses remain:

```text
Draft
Ready for Implementation
In Progress
Complete
Deprecated
```

### 7.1 Draft

A Draft may contain unresolved decisions or incomplete criteria.

Codex must not implement from a Draft phase, slice, or task as though unresolved design were approved.

### 7.2 Ready for Implementation

A Ready document has resolved blocking design decisions, identified dependencies, explicit scope, and testable acceptance/readiness criteria appropriate to its type.

Ready status describes design maturity, not blanket implementation authorization. Executable agent scope is the intersection of the active phase, active slice or approved plan, explicit task path/scope authority, and governing architecture, specifications, references, and conventions. A Ready future specification does not authorize speculative scaffolding in an earlier phase.

Ready documents must not contain unresolved template prompts, `TBD`, or `TODO` markers presented as unfinished design.

### 7.3 In Progress

`In Progress` means repository implementation has actually begun against the governed phase/slice/task.

Status must not be advanced merely because an agent session was opened or a prompt was prepared.

### 7.4 Complete

`Complete` means the document's measurable exit/acceptance criteria are satisfied by repository evidence.

A commit existing is not enough by itself.

A task/slice/phase must not be marked Complete while required verification is failed, blocked, or not performed unless its owning criteria explicitly allow that evidence to remain manual/conditional.

### 7.5 Deprecated

A Deprecated document is no longer authoritative.

When a replacement exists, `Superseded By` identifies it and navigation should make the replacement discoverable.

## 8. Status Authority for Codex

Codex must not silently promote governed-document status merely because implementation work appears successful.

A task may include a status transition when:

- the transition is in scope;
- the required evidence exists;
- the user/task author has authorized that documentation change.

Normal implementation completion does not implicitly authorize broader phase/specification status transitions.

## 9. Dependency and Reference Direction

`Depends On` represents authority/dependency, not a miscellaneous related-links list.

Dependencies remain acyclic and follow ARCH-002's direction:

```text
Phase -> Architecture / Reference
Specification -> Architecture / Phase / Reference
Slice -> Phase / Specification / Convention / Reference
Task -> Slice / Specification / Convention / Reference
```

Navigation links may be bidirectional where useful.

Higher-level architecture/specification documents must not become dependent on individual lower-level Codex tasks merely because a task implemented them.

## 10. Repository-Relative Links

Documentation links should be repository-relative and durable enough to survive normal clone/worktree placement.

Do not use:

- local absolute filesystem paths;
- `file://` links to a developer machine;
- chat-only references as durable dependencies;
- opaque local-agent paths as architectural references.

When moving a governed document, update inbound indexes/known references in the same reviewed change where practical.

## 11. Index and Discoverability Rules

A governed document is incompletely integrated if it exists but cannot be reasonably discovered through its owning documentation area.

When creating, moving, deprecating, or promoting a governed document, update the relevant index/navigation in the same change.

Examples:

```text
new convention
    -> docs/conventions/README.md

new backend specification
    -> docs/specifications/backend/README.md

new phase
    -> docs/phases/README.md / docs/README.md as applicable

new template category
    -> docs/templates/README.md
```

An index should identify the stable ID, descriptive title, and status when that area already uses a table/list with status.

Do not create a second competing index for the same document family without a demonstrated navigation need.

## 12. Documentation Writing Style

Use plain technical Markdown.

Prefer:

- concrete nouns and identifiers;
- active voice where natural;
- explicit normative words: `must`, `must not`, `should`, `may`;
- exact command names;
- exact document/interface identifiers;
- concise examples for non-obvious contracts;
- tables only for genuinely tabular/comparative information;
- short code/text blocks for structured examples.

Avoid:

- marketing language;
- conversational filler;
- performative certainty without evidence;
- unexplained acronyms;
- vague requirements such as "handle errors appropriately";
- duplicated rationale;
- long implementation diaries;
- low-level syntax in a document that owns only architectural behavior.

## 13. Normative Language

Use normative wording intentionally.

- **must / must not** — required for correctness, architecture, safety, or repository policy;
- **should / should not** — expected default with a legitimate narrow exception possible;
- **may** — explicitly permitted but optional;
- descriptive present tense — established architecture/fact, not necessarily a new requirement.

Do not use `should` when an implementation is actually forbidden from deviating.

Do not use `must` for stylistic preference that has no durable engineering consequence.

## 14. Document Length and Decomposition

Argus does not impose arbitrary line or word limits on governed documents.

Long documents are acceptable when one owner genuinely needs that detail.

Split when:

- the document contains multiple independently owned concerns;
- separate parts have different lifecycle/owners;
- a canonical registry belongs in a `REF-*` document rather than inside a behavioral specification;
- one section evolves independently enough to justify a separate governed contract.

Do not split solely to satisfy an arbitrary size target.

## 15. Durable Contract Versus Incidental Mechanics

Document what future implementation/review work needs to know.

Do not preserve incidental mechanics solely because they occurred during one implementation session.

Durable examples:

```text
Repository transaction owns atomic commit.
Run `just check` before claiming the canonical repository gate passed.
Bridge DTOs must not leak into Flutter feature code.
```

Transient examples:

```text
Codex tried helper X first while debugging.
A command took 14 seconds on one developer machine.
The agent inspected files in a particular order.
```

If an abandoned approach captures important durable rationale, promote that rationale into an ADR/specification rather than preserving the debugging transcript.

## 16. Documentation Changes During Implementation

Update governed documentation when the documented truth changes.

Typical triggers include material changes to:

- public interfaces/contracts;
- architecture boundaries;
- persistence/schema behavior;
- supported configuration;
- operational workflows;
- verification commands;
- slice/task acceptance state;
- compatibility/security behavior.

Minor internal refactoring that does not change a documented contract does not require documentation churn.

The rule is:

> **Update documentation when the documented truth changes, not merely because code changed.**

## 17. Documentation Impact Check

Every implementation task must consider:

> **Did this change alter any durable documented truth?**

If **no**, no documentation edit is required solely for ceremony.

If **yes**:

1. identify the owning governed document;
2. update it in the same reviewed change when the correction is within already-approved design authority; or
3. stop/surface a material decision when the required update would change product/architecture authority beyond the task.

A transient `RESULT.md` note is not an acceptable substitute for updating a stale authoritative specification.

## 18. Specification Defects Discovered During Implementation

When implementation reveals a specification defect, Codex must not silently code around it and leave the repository documentation false.

If the correction:

- preserves approved architecture/product intent;
- is within allowed paths/scope or is explicitly authorized;
- removes an inconsistency/ambiguity rather than introducing a new material decision;

then the owning documentation may be updated with the implementation change.

If correction requires a material product/architecture decision, the task must not invent that decision. Report the block/deviation and surface the decision for review.

## 19. Transient Agent Artifacts

Local agent/assistant artifacts are workflow aids, not governed documentation.

Examples include:

```text
.chatgpt/codex-runs/<run-id>/PROMPT.md
.chatgpt/codex-runs/<run-id>/RESULT.md
.chatgpt/handoffs/*.local.md
chat transcripts
local agent logs
terminal history
```

These may contain useful detail for immediate review/resume, but they are not authoritative repository knowledge.

CONV-REPO-001/.gitignore keep `.chatgpt/` and `.codex/` local unless a future explicit policy changes that.

## 20. Promotion from Transient Artifacts

When a transient agent artifact contains durable knowledge, promote the fact to its natural owner.

Use:

```text
architecture change       -> ARCH / ADR
subsystem contract        -> SPEC
canonical vocabulary      -> REF
repeatable engineering    -> CONV
phase scope/ordering       -> PHASE
slice completion/evidence -> SLICE
bounded implementation    -> TASK
```

Do not commit raw transcripts merely to preserve one important sentence.

## 21. Codex Task Requirements

A Codex task is narrower than its parent implementation slice and normally describes one independently reviewable repository change.

Every Ready Codex task must define:

- one bounded objective;
- files/paths to inspect first;
- allowed paths;
- forbidden paths where useful;
- interfaces consumed;
- interfaces produced;
- explicit include/exclude scope;
- concrete acceptance criteria;
- verification commands;
- result-reporting requirements;
- intended Git/commit boundary as planning guidance when useful.

Tasks must not contain unresolved product or architecture decisions.

## 22. Task Scope Discipline

Codex must not broaden a task merely because adjacent cleanup appears useful.

Do not combine unrelated:

- refactoring;
- dependency upgrades;
- naming cleanup;
- formatting churn outside touched/required scope;
- documentation restructuring;
- speculative infrastructure.

When unrelated work is discovered, report it separately as a follow-up candidate unless it is necessary to complete the approved task correctly.

### 22.1 Active-Scope Intersection

A task may reference broader Ready specifications for compatibility and extension constraints, but it implements only behavior activated by its parent phase or slice and explicit task. Codex must not create future modules, routes, DTOs, migrations, dependencies, fixtures, tests, placeholders, generated contracts, or generated output solely because a referenced specification is Ready.

If an explicit task appears broader than its active phase or slice authority, Codex treats that as a documentation defect or material scope decision rather than silently expanding implementation.

## 23. Allowed Implementation-Level Deviations

A minor implementation-level deviation may be made without stopping when all of these are true:

1. it remains inside approved architecture/product intent;
2. it remains inside allowed paths/scope;
3. it does not change a public/durable contract;
4. it does not change security/privacy behavior;
5. it is required or clearly beneficial to complete the task correctly;
6. it is reported explicitly in the result when non-trivial.

Examples may include:

- renaming a private helper;
- adjusting private module placement within the approved boundary;
- adding a missing focused regression test;
- using an equivalent standard-library mechanism;
- removing obviously dead private scaffolding created within the task.

## 24. Material Deviations Require Authority

Codex must not independently decide material deviations involving:

- system architecture;
- product behavior;
- persistence/schema contracts;
- bridge/public API contracts;
- security/privacy policy;
- dependency direction;
- task scope boundaries;
- durable compatibility/versioning behavior;
- destructive repository/Git operations.

A material deviation requires the owning design/document to be revised or explicit user direction before implementation proceeds beyond the approved authority.

## 25. Result Reporting Principles

Codex result reporting states what actually happened, not what was expected to happen.

A useful result answers:

- what changed;
- which behavior was implemented;
- which files were materially changed;
- which required commands were run;
- what each verification command returned;
- which acceptance criteria are satisfied;
- what failed/was blocked/not run;
- what deviations occurred;
- whether documentation required updating;
- current Git state;
- unresolved issues/follow-up items relevant to the task.

Result reporting should be concise enough for review while retaining evidence needed to support completion claims.

## 26. Verification Status Vocabulary

For required commands/checks, report one of these outcomes:

```text
PASS
FAIL
NOT RUN
BLOCKED
```

Definitions:

### PASS

The stated command/check ran over the reported scope and succeeded.

### FAIL

The command/check ran and returned a failing result.

### NOT RUN

The command/check was not executed.

State why when the omission matters to completion.

### BLOCKED

The command/check could not be executed because a prerequisite/environment/capability was unavailable.

State the blocker and do not report the behavior as verified.

## 27. Verification Scope Must Be Exact

Do not inflate narrower evidence into a broader claim.

Non-compliant:

```text
All tests pass.
```

when only:

```text
cargo test -p argus-settings
```

was executed.

Compliant:

```text
cargo test -p argus-settings
PASS

just check
NOT RUN - canonical root workflow is outside/unavailable for this task state
```

`CONV-TEST-001` remains authoritative for what each verification surface proves.

## 28. Acceptance-Criteria Traceability

Task completion evidence should map back to the task's acceptance criteria.

Exact formatting is not mandated, but the result must make it possible to determine why each material criterion is considered satisfied or not satisfied.

Example:

```text
Acceptance criterion: failed settings writes preserve the confirmed value
Status: PASS
Evidence: settings_controller_reverts_on_failure test
```

A list of changed files without behavioral evidence is not sufficient completion reporting.

## 29. Partial and Failed Tasks

A Codex task may end partially complete, failed, or blocked.

Do not fabricate success to make the result cleaner.

A partial/failed result records:

- work completed;
- files changed;
- tests/checks that passed;
- tests/checks that failed or were not run;
- remaining work;
- blockers;
- current repository/Git state;
- any recovery considerations relevant to the user's next action.

The governed task remains `In Progress` until its acceptance criteria actually pass.

## 30. Completion Result in Governed Task Documentation

When a governed `TASK-*` reaches Complete, append or maintain a concise durable completion summary in the task document or the repository's adopted equivalent completion field.

The durable summary records, as applicable:

- material files changed;
- behavior implemented;
- verification commands/results;
- approved deviations;
- unresolved non-blocking issues;
- local commit SHA when committed;
- remote/branch outcome when explicitly pushed.

Do not copy a raw `RESULT.md` transcript into the task document.

A parent `SLICE-*` owns broader completion evidence across multiple tasks.

## 31. Generated Files in Results

When a task changes generator inputs and generated source is part of the committed source/build contract:

1. generated output belongs to the same logical task;
2. the result identifies generated files separately from handwritten files where useful;
3. `just check-generated` or the applicable equivalent verifies freshness;
4. generated output is not described as handwritten implementation;
5. no generated file is manually edited unless the owning generator policy explicitly permits it.

CONV-REPO-001 owns the generated-source commit policy.

## 32. Git State Reporting

A result must distinguish relevant Git states rather than saying only "done".

Use clear statements such as:

```text
modified, unstaged
staged, uncommitted
committed locally at <sha>
pushed to <remote>/<branch>
```

When no Git write was requested, explicitly leaving changes uncommitted is normal and not a task failure.

## 33. Commit and Push Authorization

Codex must **never stage/commit/push automatically merely because implementation or verification succeeded**.

Git write authority is explicit and user-controlled.

Rules:

1. **Commit requested** — Codex may stage the reviewed intended paths and create the local commit.
2. **Push requested** — Codex may push the explicitly approved commit/branch when the active tooling supports pushing.
3. **Commit and push requested** — Codex may perform both in sequence after required verification and scope review.
4. **No explicit request** — leave changes uncommitted/unpushed.
5. A task's suggested commit message or commit boundary is planning guidance, not authorization.
6. Successful verification is not authorization to commit.
7. Successful commit is not authorization to push.

> **Codex may prepare work for review freely, but commit and push operations require explicit user authorization. Neither occurs automatically because a task completed successfully.**

## 34. Pre-Commit Requirements

When the user explicitly requests a commit, Codex must before committing:

- inspect current Git status/diff;
- verify the exact intended path set;
- avoid unrelated pre-existing changes;
- run/confirm the verification evidence required for the claimed task state, subject to available tooling;
- report any blocking verification failures instead of silently committing as though complete when the user's request presumes a completed task.

A user may explicitly request a commit despite known failures/partial state; if so, the result/commit context must not misrepresent those failures.

## 35. Push Requirements

When the user explicitly requests a push:

- verify the commit/branch/remote target to the extent supported by the active tooling;
- do not push unrelated unapproved commits by accident;
- report whether the push succeeded or was unavailable/blocked;
- do not claim a push occurred when the active environment cannot perform it.

If the current tool cannot push, report that limitation. Do not fabricate remote state.

## 36. Suggested Commit Boundary

A `TASK-*` may include a suggested commit message and exact intended paths to make review/staging predictable.

That section answers:

> **If the user later requests a commit, what cohesive local commit should this task normally produce?**

It does not answer:

> **May Codex commit now?**

Authorization comes only from the user's explicit request.

## 37. Handoffs

Local ChatGPT/Codex handoffs may summarize current work for session continuity.

They remain transient unless a durable fact is promoted to the appropriate governed document.

A handoff may safely record:

- current branch/HEAD known at the time;
- local dirty state;
- active task/slice;
- recent decisions already approved;
- concrete next steps;
- tool limitations.

A handoff must not become the only place an architectural decision or requirement exists.

## 38. Security and Privacy in Documentation/Results

Documentation and result files must not expose secrets or private user content.

Do not commit or copy into durable docs/results:

- API keys/tokens/passwords;
- credential-bearing URLs;
- private provider account payloads;
- real ROM/BIOS content;
- unsanitized diagnostic bundles;
- machine-local secrets/environment values;
- unnecessary personally identifying absolute paths/usernames.

When a failure contains sensitive data, summarize the safe error category/context rather than preserving the raw secret-bearing output.

## 39. Tool and Environment Claims

Results must distinguish project facts from environment/tool limitations.

Examples:

```text
Project requires `just check` before completion.
Current environment cannot execute Flutter native build.
Therefore: native build evidence BLOCKED, not PASS.
```

Do not rewrite a project requirement merely because one agent environment cannot currently perform it.

## 40. Documentation Quality Gate

Before a governed document moves to Ready or Complete, perform the ARCH-002 quality gate:

1. scan for unresolved placeholders;
2. check internal consistency and terminology;
3. verify links and document IDs;
4. confirm scope fits the document type;
5. confirm dependency direction is acyclic;
6. confirm requirements are testable where applicable;
7. confirm the owning index/navigation is current;
8. confirm no lower-level document silently overrides a higher-level owner.

## 41. Placeholder Rules

Templates may contain bracketed authoring prompts.

Ready/Complete governed documents may not contain unresolved:

- `[placeholder]` authoring prompts;
- `TBD`;
- `TODO` representing unfinished design;
- fake example values presented as actual configuration;
- empty mandatory sections.

A deliberate code `TODO` discussed by an implementation convention is separate from a documentation placeholder and remains governed by that implementation convention.

## 42. Link and Identifier Review

When changing a governed document:

- verify its own metadata links/IDs;
- update directly owned indexes;
- update known links that would otherwise break;
- avoid broad unrelated link churn;
- prefer stable IDs in explanatory prose.

Broken documentation navigation is a repository defect even when source code still builds.

## 43. Prohibited Patterns

The following are prohibited unless explicitly justified by a higher-level policy:

- treating chat history as the only durable source of an approved requirement;
- committing raw agent chain-of-thought/reasoning transcripts as engineering documentation;
- copying full specifications into Codex tasks;
- lower-level tasks silently redefining architecture/specification contracts;
- Ready/Complete governed documents containing unresolved authoring prompts/TBD/TODO design markers;
- status promotion without supporting evidence;
- marking a task Complete while required acceptance criteria remain failed/blocked;
- reporting `PASS` for a command that was not run;
- reporting "all tests pass" from a narrower filtered suite;
- hiding material deviations in implementation without updating/reporting authority;
- using `RESULT.md` as a substitute for updating a stale specification;
- committing `.chatgpt` transcripts solely as historical clutter;
- automatically staging/committing/pushing when the user did not explicitly request the Git write;
- treating a suggested commit boundary as commit authorization;
- pushing merely because the user requested a commit;
- including unrelated dirty work in a requested commit;
- claiming a push succeeded when tooling cannot prove it;
- storing secrets/private user data in durable docs/results;
- arbitrary documentation size limits that force ownership fragmentation;
- documentation churn for internal refactors that do not alter documented truth.

## 44. Examples

### 44.1 Compliant: Spec discovery during implementation

```text
Codex discovers SPEC-BE-005 says error X is recoverable,
but implementation acceptance requires it to be fatal.

Action:
- do not silently choose one;
- identify the contradiction;
- surface/update the owning specification with explicit authority before proceeding.
```

### 44.2 Non-Compliant: RESULT-only workaround

```text
Implemented fatal behavior even though SPEC-BE-005 says recoverable.
Mentioned mismatch only in local RESULT.md.
```

The durable repository contract remains false.

### 44.3 Compliant: Narrow verification report

```text
cargo test -p argus-settings
PASS

just check
NOT RUN - not available in the current task environment
```

### 44.4 Non-Compliant: Inflated verification claim

```text
All checks pass.
```

when only one package test ran.

### 44.5 Compliant: Commit boundary without authorization

```text
Suggested commit:
docs: add settings task
Paths:
- docs/tasks/task-p00-003-settings.md

Git state:
modified, unstaged
```

No commit occurs until the user requests it.

### 44.6 Compliant: Explicit commit request

```text
User: commit this

Codex:
- reviews exact diff;
- verifies intended paths;
- runs/reads required verification;
- stages only approved paths;
- commits locally;
- reports SHA;
- does not push unless push was also requested.
```

### 44.7 Compliant: Explicit commit and push request

```text
User: commit and push

Codex:
- verifies reviewed scope;
- commits;
- pushes the approved branch when tooling supports it;
- reports commit SHA and push outcome.
```

### 44.8 Non-Compliant: Automatic Git write

```text
Task passes tests.
Codex stages, commits, and pushes without user request.
```

### 44.9 Compliant: Durable promotion

```text
Local handoff notes a newly approved invariant.
Before ending the design work, the invariant is written to SPEC/CONV/ADR as appropriate.
The handoff remains only session continuity metadata.
```

## 45. Enforcement

This convention is enforced through documentation review, task templates, repository indexes, Git workflow controls, and completion verification.

### 45.1 Templates

Governed templates encode required metadata/sections and should direct authors toward this convention rather than re-inventing task/result rules.

### 45.2 Documentation Review

Review checks:

- correct document owner/type;
- metadata completeness;
- dependency direction;
- placeholder absence in Ready/Complete docs;
- single-source-of-truth adherence;
- links/indexes;
- testable acceptance wording.

### 45.3 Codex Task Review

Before implementation, a Ready task is reviewed for:

- bounded objective;
- exact path authority;
- consumed/produced interfaces;
- scope/exclusions;
- acceptance criteria;
- verification commands;
- absence of unresolved design decisions.

### 45.4 Codex Result Review

After implementation, result review checks:

- exact changed paths;
- evidence for acceptance criteria;
- verification statuses/scopes;
- deviations;
- documentation impact;
- Git state;
- blockers/unresolved issues.

### 45.5 Git Authorization

Tooling/process must preserve the rule that commit/push actions require explicit user request.

A task plan or passing verification does not itself grant Git-write authority.

## 46. Exceptions

Use the lightest durable exception mechanism that preserves documentation authority.

1. A task may omit a section that is genuinely inapplicable if the template/convention permits omission and the omission does not create ambiguity.
2. A transient result may contain more detail than the durable task completion summary.
3. A local handoff may contain session-specific paths/state because it is intentionally non-authoritative and ignored.
4. A material deviation from document ownership/status/Git-authorization rules requires updating this convention or the higher-level architecture rather than relying on repeated ad hoc exceptions.
5. If tooling cannot perform an explicitly requested push, report the limitation; the authorization remains valid but the action remains unperformed.

## 47. Acceptance Criteria

CONV-DOC-001 is satisfied when applicable repository documentation/workflows follow these rules:

1. The repository remains the durable source of engineering truth; chat/agent history is not required to recover approved architecture or requirements.
2. Durable facts have one clear owning document type.
3. Lower-level documents reference rather than inconsistently duplicate higher-level contracts.
4. Governed documents use ARCH-002 metadata/status rules.
5. Ready/Complete documents contain no unresolved design placeholders.
6. Document IDs remain stable across filename/path changes.
7. `Depends On` remains acyclic and expresses authority/dependency rather than generic related links.
8. Creating/moving/deprecating a governed document updates its owning index/navigation.
9. Documentation changes accompany implementation when documented truth materially changes.
10. Internal refactoring that does not change documented truth does not require ceremonial documentation churn.
11. Implementation discoveries that reveal specification defects are promoted to the owning document rather than left only in transient results.
12. Material product/architecture decisions are not invented by a Codex task outside its approved authority.
13. Codex tasks are narrower than slices and identify inspect/allowed paths, interfaces, scope, acceptance criteria, verification, and result expectations.
14. Unrelated cleanup is not silently folded into a task.
15. Minor implementation deviations remain within approved boundaries and are reported when non-trivial.
16. Result reporting distinguishes actual changes from intended changes.
17. Verification commands are reported as `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED` with truthful scope.
18. Narrow verification is not reported as broader repository success.
19. Task completion evidence maps materially to acceptance criteria.
20. Partial/failed tasks report actual state rather than fabricated completion.
21. Completed task documentation retains a concise durable completion summary rather than raw run transcripts.
22. Generated files are identified/verified according to CONV-REPO-001.
23. Transient `.chatgpt`/Codex artifacts remain non-authoritative and local by default.
24. Durable knowledge from transient artifacts is promoted to ARCH/ADR/SPEC/REF/PHASE/SLICE/TASK/CONV as appropriate.
25. Documentation/results do not contain secrets/private user data.
26. Codex does not automatically stage, commit, or push merely because work completed.
27. A commit occurs only after an explicit user commit request.
28. A push occurs only after an explicit user push request.
29. A requested commit does not imply permission to push.
30. Suggested commit boundaries/messages are planning guidance, not Git authorization.
31. Before a requested commit, the exact intended diff/path set and relevant verification evidence are reviewed.
32. After a commit/push action, the result reports the actual SHA and/or remote/branch outcome that tooling can verify.
33. Governed-document quality gates verify placeholders, consistency, links, IDs, scope, dependencies, and testability before Ready/Complete transitions.
34. Ready status is not treated as blanket implementation authorization; Codex implements only the intersection of active phase, active slice or approved plan, explicit task authority, and governing documents.

## 48. References

- [ARCH-001 — Argus ROM Toolkit Architecture](../architecture/architecture-overview.md)
- [ARCH-002 — Argus Documentation Architecture](../architecture/documentation-architecture.md)
- [PHASE-000 — Foundation](../phases/phase-000-foundation.md)
- [CONV-REPO-001 — Repository and Generated-File Conventions](conv-repo-001-repository-and-generated-file-conventions.md)
- [CONV-TEST-001 — Test Pyramid, Fixtures, and Verification Commands](conv-test-001-test-pyramid-fixtures-and-verification-commands.md)
- [Codex Task Plans](../tasks/README.md)
- [Codex Task Template](../templates/codex-task.md)
- [Convention Template](../templates/convention.md)
