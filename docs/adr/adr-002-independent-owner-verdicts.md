# Independent Evidence-Based Owner Verdicts

**Document ID:** ADR-002
**Status:** Complete
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-003, SPEC-X-003, REF-QUAL-002
**Supersedes:** None
**Superseded By:** None

## Decision lifecycle and approval

The owner accepted this decision on 2026-10-15 as part of the explicit package approval recorded in [REF-QUAL-002](../reference/qualification-design-decisions.md). `Complete` is the repository-governed lifecycle status for this finished record; acceptance is stated in the Decision section, not represented by a new status value.

## Context

Automated assertions and qualification tooling can produce structured observations, but final owner qualification also requires human judgment. Automated success alone cannot issue an owner decision or establish whole-release readiness.

## Decision

Keep each owner scenario verdict separate from automated scenario results and readiness assessment. The owner may review sufficient immutable objective evidence for objective scenarios. Scenarios requiring subjective UX judgment require direct owner observation. Record each owner verdict append-only and link it to the evidence digests and rule revision it evaluates; corrections append a new decision rather than editing history.

## Consequences

Objective evidence can support retrospective owner review only when its artifact, rule, environment, and provenance meet the current evidence contract. Subjective observations cannot be inferred from automation or reconstructed from a status label. Readiness remains read-only and reports missing owner decisions as not ready.

## Source decision traceability

`Q2A`, `Q11B`, `Q30A`, `Q31A`, and `Q119A` in [REF-QUAL-002](../reference/qualification-design-decisions.md).
