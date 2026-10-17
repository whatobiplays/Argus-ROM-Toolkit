# Argus Qualification System - Incremental Implementation Plan

**Status:** Proposed - owner approval required  
**Prepared:** 2026-10-15  
**Repository:** `whatobiplays/Argus-ROM-Toolkit`  
**Governing drafts:** ARCH-003, SPEC-X-003, Argus Qualification `CONTEXT.md`  
**Authority:** Planning artifact only. No repository edits, APK installation, application reset, credential changes, or physical-device actions are authorized by this document.

## Objective

Replace project-milestone-specific qualification automation with a reusable owner-authorized system. Deliver its first end-to-end Android physical Release qualification result through small, independently reviewed PRs; then expand to all Android, content and Android UX obligations, with macOS and whole-release readiness integration to follow.

## Entry conditions

- Approve consolidated architecture and acceptance specification explicitly.
- Preserve primary checkout, active local worktrees and untracked owner files.
- Use WhatObiPlays GitHub identity only. Keep author name and private email aligned to that identity.
- Treat the exact distributable Argus installation on GT78-VN as protected. No ADB execution before a separately authorized session manifest.
- Preserve historical qualification evidence verbatim when archiving it. Never transform prior failures or owner findings into new test results.

## Proposed PRs and review boundaries

### PR A - Authority, contracts and neutral naming

- Adopt ARCH-003 and SPEC-X-003 with repository metadata conventions; review canonical glossary and selected ADRs.
- Define qualification scenario IDs, production capability matrix owner, acceptance rule schema, current evidence schema, owner-review status semantics, and private/committable data boundaries.
- Migrate active qualification scripts, packages, entrypoints, test plans and current technical documents to names independent of delivery management. Archive retired historical commands/reports unchanged. Update indexes and path references without falsifying provenance.
- Separate existing manual-observation contract from the new objective-evidence owner review contract; revise the active unavailable-source acceptance criterion to clearly allow both specified simulations.
- Validation: documentation lint/link checks, schema examples, checks that active qualification source and tests contain no planning identifiers, and unchanged historical archive checksum manifest.
- Exit: two approved technical contracts; all old tests still runnable through migrated neutral paths or explicitly retired with preserved evidence; no device activity.

### PR B - Isolated Release packaging and identity

- Add stable qualification Android application ID using Release build behavior with Android debug signing (not Debug build type). Keep functional source/features unchanged; independently verify `debuggable=false`, signing fingerprint, package/component identity and ARM64 bridge packaging.
- Ensure manifest placeholders, native Android components, filesystem/provider authorities and credential boundaries resolve for the new package. Ordinary product package and release signing remain unchanged.
- Add packaging validation and a source-revision match check against the selected distributable candidate; do not claim complete binary parity.
- Define analogous macOS qualification bundle ID, development signing, entitlements and distinct Keychain service namespace as a follow-on PR only when that adapter is ready. Do not change ordinary macOS store service identity.
- Exit: qualification artifact can be built and verified without shipping-signing secrets and without colliding with the ordinary package; no installation performed without later owner authorization.

### PR C - Authorization, admission and safe fixture staging

- Implement immutable manifest validation and typed ADB operations with exact device/app identity checks, explicit fresh-state vs no-reset entrypoints and bounded preparation/cleanup.
- Implement streaming, size-unbounded (subject to free-space reserve) verification of owner-controlled, read-only ROM sources and exclusively staged copies. Preserve descriptor/playlist companion relationships. Owner private manifest contains hashes and paths; public evidence uses aliases only.
- Add explicit credential baseline and owner setup boundaries; no secret reads. Fresh reset affects qualification-app private data only. External fixture cleanup requires exclusive ownership.
- Simulated transport/unit tests: wrong signer/target, foreign package/UI, unsafe mutation, invalid/changed ROM, partial transfer, missing reserve, interrupted copy, permission restore failure, unexpected inherited state, orphan screenshot cleanup and attempted reuse of old unowned fixture directories.
- Exit: the preparation engine is demonstrably fail-closed without a physical device.

### PR D - First executable physical scenario and append-only evidence

- Implement accessibility-first UI driver with unique selectors, verified transitions and transient screenshot handling. Correct ordinary product accessibility semantics where a trivial gap blocks a real control; any corrected product binary is rebuilt and re-pinned before a run.
- Implement one small, independently validated fixture-based scan and Library assertion against the isolated Release, plus separately exercised negative fail-fast/cleanup paths using simulations.
- Define append-only current-schema execution evidence, integrity-linked final manifest, interrupted-session recovery, sanitized review packet, and separate owner verdict entry.
- Exit: host safety tests and all relevant CI jobs pass. Then request **new explicit owner authorization** to execute one bounded physical session on GT78-VN. First physical milestone must verify a real product behavior, an authentic signed Release-configured artifact, fixture provenance, durable evidence and cleanup.

### PR E - Complete Android product and content oracles

- Extend to onboarding, Library navigation/search/filter/sort/detail, active refresh and job lifecycle, controlled force-stop, persistence, explicit retry, provider preparation/live hydration, known-unmatched fallback, malformed content isolation and both simulated source-unavailability mechanisms.
- Require independently owner-validated positive fixture coverage for each advertised archive/compressed format, with targeted optical, descriptor, playlist and equivalence combinations; use separate Rust contract tests for the broader platform-by-representation matrix.
- Pin rule/fixture versions and measured foreground-performance thresholds before any qualifying run.
- Exit: every required objective assertion is either backed by product-visible independent evidence or honestly BLOCKED; no invented success based on UI labels.

### PR F - Android UX owner-attended coverage and distributable smoke

- Implement objective 48 x 48 dp target, accessibility role/name/state/focus, effective font/display scaling, critical text/control geometry and overlap assertions.
- Build owner-attended TalkBack/visual usability review workflow; distinguish machine observations from direct owner verdicts.
- Add independently authorized exact-distributable smoke plan for signing, identity, install safety, startup, basic Library, credentials/permissions and bounded lifecycle. Reject installs requiring downgrade, uninstall, data reset or signing mismatch.
- Exit: reusable owner review packet and all supported Android scenarios adjudicable; distributable smoke is separately grounded and safe for the ordinary installation.

### PR G - Deterministic readiness and platform extension

- Implement read-only platform and whole-release READY/NOT_READY assessment of current-schema evidence with exact artifact, owner-verdict, acceptance-rule and fixture compatibility checks.
- Require owner PASS for all mandatory scenarios; unsupported configurations excluded only under a preapproved matrix with at least one exercisable required configuration. Current-only evidence assessor retains older records as archive, without assuming they are new proof.
- Verify macOS UX outstanding requirements separately, adopting macOS qualification identity and runner as needed. Planning-layer mapping consumes results without affecting qualification code or technical evidence.
- Exit: complete reproducible gate evaluation, never auto-publishes or tags a release.

## First physical execution checkpoint

The initial physical run is not authorized by merging any PR. Before invocation, present the owner with:

1. Exact signed qualification APK path/digest, source revision, signing fingerprint and verified Release-mode properties.
2. GT78-VN target identity, Android OS/ABI, selected plan/rules/fixtures and allowed commands.
3. Clear vs no-reset choice, scoped credential and storage permissions, resource reserve and all relevant restoration/cleanup consequences.
4. Explicit scope, timeout ceilings, fail-fast conditions, persistent evidence destination and expected owner-review packet.
5. A manifest digest that can be matched to the approved execution arguments and final report.

Only after approval may Codex run the local device executor. Do not independently modify or uninstall the ordinary Argus app.

## Acceptance checks across PRs

- Exact owner approval must precede each mutating device session; test/PR approval is not session approval.
- Work performed in isolated worktrees; source review covers Standards and Specification axes, CI verifies deterministic host checks, and changed build artifacts have fresh provenance.
- Fail-fast sessions never silently continue after product failure or blocked runtime prerequisites; cleanup remains mandatory.
- Credentials and private ROM originals are never committed or echoed into sanitized output.
- No fixed fixture-byte limit may cause an otherwise admissible session to fail; capacity and free-space reserve remain mandatory.
- Any changed product binary is a new qualification candidate; any changed rule requires fresh evidence for affected scenarios.
- Preserve immutable historical observations and failed attempts; a later success supersedes only owner interpretation, never the underlying evidence.

## Prioritized ADR candidates (not yet assigned IDs)

1. **Dual-artifact qualification:** Isolated Release for deep functional oracles plus exact-distributable smoke, instead of applying the entire fixture corpus to users' ordinary app state.
2. **Owner authority with black-box evidence:** Separate automated assertions, sanitized immutable execution, and owner-approved verdicts; no privileged product introspection or automated final approval.
3. **Simulated source loss as mandatory acceptance:** Reversible path and app-specific permission denial replace required physical disconnect in current acceptance rules, while physical hardware removal becomes optional supplemental coverage.

These merit ADRs because they establish lasting, nonobvious boundaries among plausible alternatives. Schema compatibility, timeout defaults and driver implementation choices should remain in specifications/conventions, not duplicate ADRs.

## Approvals needed after design review

1. Explicit owner acceptance of ARCH-003, SPEC-X-003, vocabulary, migration approach and the three ADR decisions.
2. Separate authorization to create documentation and code PRs; do not assume PR publication or merge authority.
3. Explicit authorization per physical test session, with exact pinned inputs and permitted mutations.
4. Owner review of qualification evidence and final scenario verdicts before any readiness declaration.
