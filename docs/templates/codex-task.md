# [Task Name]

**Document ID:** TASK-P[phase]-[NNN]  
**Status:** Draft  
**Owner:** Daniel  
**Last Updated:** [YYYY-MM-DD]  
**Depends On:** [Slice, specification, convention, and reference IDs]  
**Supersedes:** None  
**Superseded By:** None

## 1. Objective

[One bounded implementation objective.]

## 2. Inspect First

- `[repo-relative path]`

## 3. Allowed Paths

- `[repo-relative path or narrow glob]`

## 4. Forbidden Paths

- `[repo-relative path or glob]`

## 5. Interfaces Consumed

[Exact names and signatures.]

## 6. Interfaces Produced

[Exact names and signatures required by later tasks.]

## 7. Implementation Scope

### Include

### Exclude

## 8. Acceptance Criteria

- [ ] [Concrete condition]

## 9. Verification Commands

```bash
[exact command]
```

## 10. Result Reporting

Codex must report:

- files changed
- behavior implemented
- commands run and `PASS` / `FAIL` / `NOT RUN` / `BLOCKED` results
- acceptance-criteria evidence
- unresolved issues
- deviations from the task
- documentation impact
- Git state (modified/staged/committed/pushed)
- commit SHA when committed
- remote/branch outcome when explicitly pushed

On completion, append a concise durable `Completion Result` section per CONV-DOC-001. Do not copy a raw agent transcript into the task document.

## 11. Git Boundary and Authorization

[Suggested local commit message and exact intended paths. This is planning guidance only. Codex must not stage, commit, or push unless the user explicitly requests the corresponding Git write. A commit request does not imply push authorization.]
