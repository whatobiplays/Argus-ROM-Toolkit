# SLICE-P01-007 — Cross-Platform and Phase Hardening Design

## 1. Outcome

Finish Phase 001 by proving the complete Local Sources and Indexing capability through repository-owned automated verification. Preserve the platform-neutral `just check` contract, add a required macOS native Phase 001 milestone to normal CI, exercise real LocalFilesystem behavior on Windows and Linux, harden architectural boundaries, keep diagnostics sanitized, and prevent Phase 002+ capability leakage.

This is the seventh and final implementation slice of Phase 001. It adds no product capability beyond correcting genuine defects required to satisfy existing Phase 001 contracts.

## 2. Governing contracts

The design is governed by `docs/phases/phase-001-local-sources-and-indexing.md`, especially the canonical demonstration scenario, Slice P01-007, testing requirements, and exit criteria; the Phase 000 verification baseline; SPEC-BE-003/004/007/008/011/013; SPEC-FE-003/004/008/009; and SPEC-X-001.

The existing Phase 000 native milestone remains intact. Slice 007 extends the repository's verification architecture rather than replacing it with a generalized cross-phase framework.

## 3. Chosen approach

Use repository-owned verification targets and scripts as the authority, with GitHub Actions acting only as orchestration.

- `just check` retains its existing deterministic, platform-neutral meaning.
- Add a dedicated Phase 001 macOS native milestone alongside the Phase 000 native harness.
- Add focused repository-owned native-provider verification for Windows and Linux.
- Run the macOS Phase 001 milestone as a required normal push/pull-request CI gate.
- Run targeted real LocalFilesystem/provider coverage on Windows and Linux without duplicating the full macOS E2E suite.
- Extend existing architecture checks where practical rather than introducing a parallel checker.

Rejected alternatives:

1. A generalized cross-phase native-test framework was rejected because Slice 007 should harden the shipped phase rather than refactor already-proven Phase 000 verification infrastructure.
2. CI-owned validation logic was rejected because developers must be able to reproduce CI failures through repository-owned commands.
3. On-demand or local-only macOS Phase 001 verification was rejected because the final phase milestone must provide continuous regression protection.

## 4. macOS native Phase 001 milestone

The macOS milestone proves the canonical Phase 001 workflow through the real Rust/FRB/SQLite/Flutter composition against test-owned state. It should cover, where deterministic and practical:

1. Add a temporary library folder through the real UI/client/backend path.
2. Execute Add & Scan and observe durable Jobs state.
3. Inspect committed hierarchy data while preserving incremental-authority semantics.
4. Mutate the test filesystem and run Scan Again.
5. Verify authoritative add/remove reconciliation and trustworthy move preservation where provider evidence permits it.
6. Configure a second root and exercise Scan All with independent per-root outcomes.
7. Exercise cooperative cancellation and durable terminal behavior.
8. Interrupt active scan execution, relaunch against the same test-owned application data, and verify restart recovery with no automatic resume.
9. Remove a configured root and verify user filesystem contents are untouched.
10. Verify terminal job/scan history remains intelligible after root removal.

The native milestone is a composition proof, not a duplicate of every lower-level edge-case test. Deterministic backend/provider/controller tests remain responsible for exhaustive contract details.

The harness owns creation and cleanup of all temporary application, database, and library-tree state. It must not depend on production directories, ambient user libraries, or existing Argus data. Isolation must prevent an interrupted run from contaminating a later run.

## 5. Windows and Linux provider coverage

Windows and Linux CI must execute real LocalFilesystem behavior rather than compile-only checks. Focused native tests should cover the platform-sensitive portions of the Phase 001 provider contract, including as applicable:

- root normalization and identity;
- directory enumeration;
- retained file/directory classification;
- link-like boundary handling;
- missing or inaccessible roots and nested scopes;
- trustworthy provider-native move evidence where the platform supports it;
- provider-to-application filesystem error mapping.

Tests use test-owned temporary trees and assert provider contracts rather than broad OS stereotypes or implementation details.

Full duplication of the macOS Flutter E2E suite on Windows/Linux is explicitly unnecessary unless implementation evidence exposes a specific platform risk that cannot be covered below the full UI stack.

## 6. Architecture hardening

Extend existing architecture verification where practical so Phase 001 regressions mechanically reject:

- Flutter filesystem traversal or direct native filesystem authority;
- provider-native concepts leaking through public Flutter-facing contracts;
- feature-owned native event streams;
- event payloads being treated as authoritative application state;
- duplicate Sources, Jobs, scan, or background-operation authority paths.

Generated FRB, Riverpod, and Freezed output remains registered, reproducible, and free of machine-local path leakage.

Diagnostics and test failure evidence must remain sanitized under SPEC-BE-003. Native/E2E failures should provide enough bounded evidence to distinguish application, transport, harness, and platform/environment failures without exposing sensitive raw filesystem details.

## 7. Failure handling and deterministic testing

Hardening failures are evidence of defects and must not be hidden by weakening assertions or gates.

- Timing-sensitive scan, cancellation, and restart tests synchronize on authoritative durable state or explicit lifecycle signals rather than arbitrary sleeps.
- Platform-specific expectations live as close as practical to LocalFilesystem/provider tests; macOS E2E assertions stay product-contract oriented.
- Cleanup runs on success and failure where possible.
- CI commands remain reproducible through repository-owned targets.
- A defect discovered in Slices 001–006 may be corrected within Slice 007 only when necessary to satisfy an already-approved Phase 001 contract.
- Such corrections must not redefine the contract, add speculative infrastructure, or introduce Phase 002+ capability.

## 8. Verification matrix

Slice 007 completes the automated Phase 001 verification matrix:

1. `just check` passes and remains deterministic/platform-neutral.
2. Generated FRB/Riverpod/Freezed output is current and reproducible.
3. Formatting, linting, architecture checks, Rust tests, and Flutter tests pass.
4. The required macOS Phase 001 native milestone passes on normal CI.
5. Windows targeted native LocalFilesystem/provider coverage passes on CI.
6. Linux targeted native LocalFilesystem/provider coverage passes on CI.
7. Existing Phase 000 startup, recovery, diagnostics, event lifecycle, routing, settings, appearance, and native verification contracts remain protected.
8. Architecture guards enforce the Phase 001 authority boundaries.
9. No game-content parsing, hashing, metadata, artwork, RetroAchievements, watching, extra providers, or other Phase 002+ capability is introduced.

Manual keyboard, screen-reader, visual, and exploratory filesystem verification remains explicitly `NOT RUN/deferred` unless it is actually performed. Automated evidence and result artifacts must never convert deferred manual verification into a pass.

## 9. Completion criteria

Slice P01-007 is complete when the implemented Phase 001 capability satisfies the automated portions of the Phase 001 exit criteria with truthful evidence: the platform-neutral gate passes, the macOS native canonical milestone passes as required CI, Windows/Linux real provider coverage passes, architecture and generated-output gates pass, Phase 000 behavior remains intact, and no later-phase scope has leaked into implementation.

After Slice 007, Phase 001 requires a closeout review against all 31 phase exit criteria. Any genuinely deferred manual checks remain recorded as `NOT RUN/deferred`; they are not grounds for inventing an eighth implementation slice unless the closeout exposes a real implementation defect or an approved contract change.
