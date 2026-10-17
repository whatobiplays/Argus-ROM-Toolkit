# Argus Product Qualification Architecture

**Document ID:** ARCH-003
**Status:** Complete
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-001, ARCH-002, REF-QUAL-001
**Supersedes:** None
**Superseded By:** None

## Adoption and provenance

ARCH-003 adopts the approved architecture source (SHA-256 `54cdf1d3c43ac27098f3e99467c86660b0e47b05b88e39a1081f3c64dd89c801`). Its canonical dependency edges are **ARCH-001, ARCH-002, REF-QUAL-001**, following ARCH-002. `SPEC-X-001` and `SPEC-X-002` are related references, not authoritative architecture dependencies. The former source metadata, including its dependency line, is preserved below as historical provenance and does not define the current graph. The source's final adoption gate is reconciled at the end of this document; its pending-approval wording remains in the historical metadata and source archive. Package approval and all source hashes are recorded in [REF-QUAL-002](../reference/qualification-design-decisions.md).

### Historical source metadata

```text
**Document ID:** ARCH-003 (proposed; confirm available before repository adoption)
**Status:** Draft - pending owner approval
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-001, ARCH-002, SPEC-X-001, SPEC-X-002
**Supersedes:** None
**Superseded By:** None
```

### Related specifications and decisions

`SPEC-X-001`, `SPEC-X-002`, `SPEC-X-003`, `ADR-001`, `ADR-002`, and `ADR-003` are related references. They are not authoritative `Depends On` edges for ARCH-003.

### Approved architecture content

## 1. Purpose

Build a durable, planning-agnostic qualification capability that evaluates signed Argus Release software on controlled hardware using independently defined product expectations. Qualification is distinct from automated unit/integration testing, owner approval, and project completion. The initial physical executor targets Android with a future extension seam for macOS.

Qualification must not depend on the naming or timeline of any delivery target. Planning records map qualification scenarios to project obligations; technical code, scenario plans, evidence schemas, and active specifications never carry planning identifiers.

## 2. Architectural boundaries

1. **Product:** The ordinary Flutter/Rust application, its production storage and credential boundaries, and its real accessible UI; no privileged qualification-only product APIs.
2. **Qualification artifacts:** A separately identified Release-configured qualification app for comprehensive fixture-based testing, and the exact distributable Release for bounded smoke testing.
3. **Execution operator:** Codex or an owner-operated runner executing a pinned, owner-authorized session. Codex is trusted at the host level, not sandboxed by this design.
4. **Qualification harness:** Planning-agnostic Python/ADB device adapter, host fixture validation, application-facing UI driver, independent oracles, typed mutation operations, evidence appenders, and restoration controls.
5. **Owner authority:** A separate owner review and final scenario verdict, followed by deterministic, read-only platform and release readiness assessments.
6. **Project planning:** An external mapping from approved scenario results to delivery-target completion; no reverse authority into test outcomes.

## 3. Two-artifact strategy

### Qualification Release

A reproducible release-configured application with a stable install identity different from the ordinary product:

- Android qualification build uses the Android Release build type and its production optimization/non-debuggable semantics, signed using the ordinary debug signing configuration. It is NOT an Android Debug build.
- macOS qualification build uses Apple Development signing with the relevant product sandbox and entitlements.
- Qualification variants use separate OS application state and qualification-specific secure credential namespaces. On macOS, a changed bundle identifier alone is insufficient: the currently stable Rust secure-store service name must also be isolated without changing credential-store semantics.
- The qualification Library contains only the approved fixture corpus. Fresh app-private state is the default. Explicitly authorized no-reset sessions support persistence and interrupted-work scenarios.
- The variant uses the same pinned source revision and production functional features as its distributable counterpart. Essential packaging checks confirm expected identity, Release mode, debuggability, signing identity, and native components. Source parity is not claimed to prove binary or full behavioral equivalence.

### Exact distributable Release

The distributable application is independently pinned by SHA-256, package or bundle identifier, signing identity, source revision and version. Its separately approved smoke qualification checks identity-dependent installation/startup, expected signing, permissions, real credential boundary, a basic Library operation, and bounded foreground/background transitions.

A smoke run on the ordinary Android installation is restricted to data-preserving, separately authorized operations. If the exact binary cannot install without uninstall, data clearing, signing workarounds or forced downgrade, the session is BLOCKED. An `install -r` success does not establish that any historical Library record has been independently preserved.

Both the comprehensive qualification result and exact distributable smoke result are mandatory for whole-release readiness. They are distinct artifact classes and are never interchangeable.

## 4. Session lifecycle

```text
Versioned acceptance rules + capability catalog + private fixture expectations
                           |
Owner-authorized plan + immutable target/artifact/operation manifest
                           |
Read-only admission: provenance, device identity, capabilities, storage,
                    fixture integrity, expected no-reset state (if selected)
                           |
Authorized preparation: bounded tools/fixtures/settings/credential baseline
                           |
Frozen qualifying environment and linear scenario order
                           |
Strict observation -> independent oracle -> append-only evidence
                           |
PASS continues; FAIL/BLOCKED terminates without scenario retry
                           |
Bounded cleanup/restoration and immutable terminal/interruption report
                           |
Sanitized review packet -> append-only owner verdict(s)
                           |
Read-only, deterministic platform/release assessment
```

Every device-mutating operation must have been enumerated in the immutable authorization before execution. Product scenarios never adjust acceptance rules, switch binaries or automatically repair prerequisites once qualification has started. A session that fails is terminal; a new approval is required to test remaining scenarios.

## 5. Device control and state isolation

- Separate invocable entrypoints distinguish fresh-state and state-preserving sessions while sharing safe infrastructure.
- Android automation begins with Python, ADB, unique accessibility/UI selectors and verified transitions. No guessed coordinates. UI Automator instrumentation may be investigated later.
- Enforce a typed operation allowlist for application installation, launch, navigation, refresh, controlled force-stop, app-specific settings, session-owned fixture preparation, and permitted cleanup. Recheck exact physical device and app identity before relevant interactions; refuse foreign or ambiguous targets.
- Codex is a trusted local operator. These controls are an approved workflow contract, not a security sandbox against arbitrary ADB execution from its host shell. No exclusive session lock is required in v1; detect and terminate on observable interference.
- A fresh reset clears only the qualification application's data, never the ordinary app. External fixture directories and secure-store namespaces are governed separately. A no-reset session must check its authorized inherited state and cannot silently normalize unexpected data.
- Preparation may repair only explicitly approved prerequisites and reversible settings, before scenarios run. Permission restoration failure or uncertain deletion/capture cleanup blocks future automation pending owner intervention.
- No fixed total fixture-byte cap. Require streamed copying, sufficient measured capacity and free-space reserve, private temporary staging, verified final copies and exclusively owned cleanup. Never alter owner ROM originals.

## 6. Independent observation and oracles

Positive assertions derive from a separately validated and owner-approved fixture expectation manifest, never from captured Argus output. Manifest expectations include appropriate platform, content representation, logical identity, grouping, companion dependencies, attribution, ordering and relevant provider semantics. All advertised supported archive/compressed representations require genuine positive coverage; the production capability catalog determines the mandatory set. Broader platform-by-representation coverage may use independent Rust contract tests and targeted physical cases.

Automated PASS requires observable behavior corresponding to the specified expectation, not merely a success banner. If necessary state is unavailable through normal product surfaces and permitted OS observations, the relevant assertion remains BLOCKED. Normal product accessibility semantics can be improved before rebuilding and reauthorizing the candidate; they must not be used to conceal a product defect or introduce testing-only behavior.

Simulation of content-source unavailability through both controlled path loss and qualification-app-specific permission denial is mandatory. Each mechanism must be reversible, checked for restoration, and explicitly labeled as simulated. Actual removable-media unplugging is optional supplemental hardware-integration coverage; historical reports describing physical media remain unchanged.

Live providers use normal application/credential pathways and are distinguished from deterministic provider contract checks. Owner enters live credentials without disclosing their values to Codex. Unsupported live-service prerequisites are distinct from product failures.

## 7. Acceptance, evidence, and ownership

- Acceptance rules are versioned, owner-reviewed, and pinned with digests before execution; owner-approved device capability matrices declare unsupported configurations.
- Objective accessibility checks must have preapproved measurable criteria for touch targets, names/roles/state/focus, control reachability and applied font/display configurations. The cross-cutting specification owns their exact thresholds. Owner TalkBack and subjective visual-usability review remain distinct.
- Responsiveness uses independently measured and owner-approved latency thresholds, separately from operation timeouts.
- Failed product assertions or blocked prerequisites fail fast. An expected rejection of malformed content can pass when that rejection is the declared oracle and unrelated records remain intact.
- Sanitize private content, filesystem paths, credentials, identifying device attributes and screen captures. Temporary screenshots are owner-private, immediately removed, and subject to interruption-safe cleanup checks.
- Append-only machine evidence and owner verdicts are distinct. Past evidence remains archived until owner-authorized disposal; current automated assessors need only read the latest schema. Strive for backward-compatible evolution when practical, but never silently convert or requalify legacy evidence.
- A rule change demands new evidence for affected scenarios. A changed product binary is a new candidate that requires new qualification. Multiple compatible current-schema sessions may contribute to a single owner assessment without overwriting earlier failures.
- Owner verdicts, not Codex alone, determine whether mandatory scenarios pass. Deterministic readiness reports never publish or tag a release.

## 8. Migration and authority

Migrate current active qualification scripts, scenario plans, and governed technical documentation to names and identifiers unrelated to project planning. Preserve original historical records, including old command/path references and failure facts, as archived planning/evidence rather than rewriting their contents. The active qualification contract must be formally revised where it previously required physical media removal or owner observation of every objective scenario.

A previously accepted manual verdict remains a historical finding; it does not automatically certify a new binary, new rule, or new current-schema readiness assessment. Existing macOS approvals must be treated according to their actual candidate provenance when the overall readiness assessor is introduced.

## 9. Known limits and deferred work

- No general OS-level restriction prevents a trusted Codex host operator from invoking ADB outside the qualification runner.
- No exclusive device-session lock; some concurrent interference may be undetectable.
- Debug-signed qualification APKs and development-signed macOS variants may behave differently from distributable packages; exact-artifact smoke qualification mitigates but does not prove complete equivalence.
- App data-preserving installation is not byte-level or logical-record preservation proof.
- Current-schema-only assessors cannot automatically reuse obsolete evidence formats.
- Deferred: autonomous final qualification approval, dependency-aware scenario scheduling, a native UI Automator backend, full cross-platform orchestration framework, and automatic impact-based requalification.

## 10. Adoption gate

The source archive's final adoption gate stated that owner approval was still required; that sentence records the package's pre-approval state. Owner approval for this documentation adoption is recorded in [REF-QUAL-002](../reference/qualification-design-decisions.md) on 2026-10-15. That approval does not authorize implementation, application changes, or device operations. Each implementation task or PR and every physical-device execution manifest requires separate approval.
