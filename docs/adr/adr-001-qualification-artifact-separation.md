# Qualification Artifact Separation

**Document ID:** ADR-001
**Status:** Complete
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-003, SPEC-X-003, REF-QUAL-002
**Supersedes:** None
**Superseded By:** None

## Decision lifecycle and approval

The owner accepted this decision on 2026-10-15 as part of the explicit package approval recorded in [REF-QUAL-002](../reference/qualification-design-decisions.md). `Complete` is the repository-governed lifecycle status for this finished record; acceptance is stated in the Decision section, not represented by a new status value.

## Context

Comprehensive functional qualification and exact-distributable smoke qualification have different purposes and target identities. One test target cannot establish both fixture-driven behavior and identity-sensitive behavior of the shipped artifact.

## Decision

Run comprehensive functional qualification against an isolated, signed Release-configured qualification variant with a fixture-only Library and independent app data. Run a separate, bounded smoke qualification against the exact distributable Release artifact pinned by digest and signing identity. Keep the artifact classes and results distinct; neither result substitutes for the other. The distributable smoke is separately authorized and data-preserving; it does not authorize uninstall, ordinary-app data clearing, signing workarounds, or claims of record preservation beyond the package-manager operation.

## Consequences

The isolated variant supports broad fixture scenarios without replacing the ordinary installation. The distributable smoke checks the exact package’s identity-sensitive installation/startup and bounded product behavior. Both are mandatory for whole-release readiness; a mismatch or destructive prerequisite blocks the smoke session.

## Source decision traceability

`Q5A`, `Q15A`, `Q53(custom)`, `Q57B`, `Q65A`, `Q67B`, `Q86A`, and `Q99A` in [REF-QUAL-002](../reference/qualification-design-decisions.md).
