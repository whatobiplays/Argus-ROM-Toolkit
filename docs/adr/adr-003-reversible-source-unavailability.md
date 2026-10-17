# Reversible Source-Unavailability Qualification

**Document ID:** ADR-003
**Status:** Complete
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-003, SPEC-X-003, REF-QUAL-002
**Supersedes:** None
**Superseded By:** None

## Decision lifecycle and approval

The owner accepted this decision on 2026-10-15 as part of the explicit package approval recorded in [REF-QUAL-002](../reference/qualification-design-decisions.md). `Complete` is the repository-governed lifecycle status for this finished record; acceptance is stated in the Decision section, not represented by a new status value.

## Context

Source unavailability and permission-boundary behavior must be testable without destructive operations or dependence on physically removable media. Simulated and physical mechanisms establish different facts.

## Decision

Require both reversible simulated mechanisms: (1) qualification-owned source-path relocation or unavailability, and (2) qualification-application-specific permission denial. Each simulation requires explicit authorization and verified restoration and must be labeled as simulated. Actual removable-media removal is optional supplemental hardware-integration coverage; it does not replace either mandatory simulation, and simulation must never be reported as physical removal.

## Consequences

The test plan verifies source-loss behavior and recovery on supported platforms while protecting ordinary application state. Failed or uncertain restoration blocks subsequent automated sessions. Historical records describing physical media remain unchanged.

## Source decision traceability

`Q56B`, `Q62A`, and `Q63A` in [REF-QUAL-002](../reference/qualification-design-decisions.md).
