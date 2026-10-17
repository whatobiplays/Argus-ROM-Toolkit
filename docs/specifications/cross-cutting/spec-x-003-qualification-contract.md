# Product Qualification System Specification

**Document ID:** SPEC-X-003
**Status:** Ready for Implementation
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-001, ARCH-002, ARCH-003, REF-QUAL-001, REF-QUAL-002, SPEC-X-001, SPEC-X-002
**Supersedes:** None
**Superseded By:** None

## Adoption and provenance

SPEC-X-003 adopts the approved qualification specification source (SHA-256 `b25d713ca62a941cdc746709def86a73a5b3a5eac055fe6955c3ce89f51a9b35`). The original draft and pending-approval labels are preserved below as historical metadata. Package approval and source hashes are recorded in [REF-QUAL-002](../../reference/qualification-design-decisions.md). This contract is planning-cycle neutral: platform, capability, artifact, and evidence applicability govern qualification; phase, milestone, and slice identifiers do not.

## Versioned assessment record contract

The serialized assessment envelope begins at **schema version 1**. Acceptance-rule versioning is independent: the initial adopted rule-set version is **`1.0.0`**, and each record pins its rule-set version and SHA-256 digest. A schema-version change describes a change to the serialized envelope; a rule-set-version change describes changed acceptance expectations. Neither version substitutes for the other. A reader accepts only the exact schema version it implements. Unknown-version evidence remains preserved but is ineligible for a new assessment; records are never rewritten or silently migrated.

A sanitized record identifies the exact artifact, rule set, immutable authorization-manifest digest, fixture-manifest digest, platform/capability applicability, scenario coverage, evidence references, and separate append-only owner-verdict stream. Each referenced evidence item is append-only and records a stable evidence ID, capture time, source-session reference, exact artifact and rule-set digests, and its own integrity digest. Private manifests, device identifiers, raw fixture identities, credentials, and screenshots are not embedded. The following JSON is a **synthetic shape example only**; identifiers and all-zero digests are illustrative and do not attest to a real artifact, result, authorization, fixture, or owner verdict.

```json
{
  "schema_version": 1,
  "assessment_id": "synthetic-assessment-001",
  "artifact": {"package_id": "example.argus.synthetic", "version": "0.0.0-synthetic", "sha256": "0000000000000000000000000000000000000000000000000000000000000000"},
  "acceptance_rules": {"version": "1.0.0", "sha256": "0000000000000000000000000000000000000000000000000000000000000000"},
  "authorization_manifest_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "fixture_manifest_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "applicability": [{"platform_family": "android", "capability_id": "synthetic-library-browse", "classification": "REQUIRED"}],
  "coverage": [{"scenario_id": "synthetic-library-browse", "applicability": "REQUIRED", "automated_status": "NOT_RUN", "evidence_refs": ["synthetic-admission-001"]}],
  "evidence": [{
    "evidence_id": "synthetic-admission-001",
    "kind": "session_admission",
    "source_session_ref": "synthetic-session-001",
    "captured_at": "2026-10-15T00:00:00Z",
    "artifact_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "acceptance_rules_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "authorization_manifest_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "fixture_manifest_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "evidence_sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  }],
  "owner_verdicts": []
}
```

The example uses the specification's applicability vocabulary (`REQUIRED`, `SUPPORTED`, `EXCLUDED_UNSUPPORTED`) and scenario states (`PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`). Exclusion is not a product `PASS`. Owner verdicts use a separate `PASS`, `FAIL`, `BLOCKED`, or `NOT_RUN` state and reference immutable evidence digests. Whole-release readiness requires every mandatory applicable criterion and required owner verdict to pass; missing or incompatible evidence cannot be promoted.

### Historical source metadata

```text
**Document ID:** SPEC-X-003 (proposed; confirm available before repository adoption)
**Status:** Draft - pending owner approval
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-001, ARCH-002, ARCH-003, SPEC-X-001, SPEC-X-002
**Supersedes:** None
**Superseded By:** None
```

### Approved specification content

## 1. Purpose

Provide repeatable, owner-authorized technical qualification of Argus Release behavior, independent of the planning or delivery cycle in which the evidence is consumed. This specification defines artifacts, session admission, execution, observability, fixture truth, safety, evidence, owner review, and release assessment.

## 2. Responsibilities

- Select and pin versioned acceptance rules and a linear plan of stable scenario IDs.
- Validate a specific signed artifact, one target environment, a private fixture manifest, and the exact session authorization before mutation.
- Execute observable product scenarios against a Release-configured qualification installation or an exact distributable smoke target.
- Apply scenario-specific independent oracles, fail fast, retain sanitized append-only evidence, and verify cleanup.
- Produce review packets, separately record owner verdicts, and calculate deterministic platform/release readiness.

## 3. Non-responsibilities

- Automatically approving final scenario verdicts or publishing releases.
- Editing private ROM originals, inventing provider/content truth, using test-only privileged application APIs, silently clearing the ordinary app, or bypassing owner authorization.
- Treating success banners, physical-media simulation, source revision equality, or Android install success as proof of stronger properties they cannot establish.
- Implementing a general dependency scheduler, an OS sandbox around Codex, or historical evidence compatibility adapters in v1.

## 3.1 Platform applicability

| Capability | Android (initial) | macOS (follow-up) |
| --- | --- | --- |
| Qualification Release identity and isolation | Platform-specific package and signing | Platform-specific bundle, entitlements, signing and Keychain namespace |
| Device driver | Python/ADB and accessibility hierarchy | Separate platform adapter, not required for initial implementation |
| Fixture manifest and independent oracles | Shared contract | Shared contract |
| Session authorization and append-only evidence | Shared | Shared |
| Owner review and readiness assessment | Shared | Shared |
| Exact distributable smoke qualification | Physical device, explicit installation authority | Actual distributable bundle, independent smoke contract |

## 4. Public conceptual interfaces

1. `prepare_authorization(plan, artifacts, fixtures, target, operations, limits) -> immutable session manifest` (owner approval required).
2. `admit(manifest) -> accepted | blocked(reason)`; admission performs read-only identity, environment, fixture, capability and expected-state checks.
3. `prepare(manifest) -> prepared | blocked(reason)`; bounded and allowed mutations only, before qualification scenarios.
4. `execute(manifest) -> append-only evidence stream`; exact linear order, never automatically repeats a mutating scenario.
5. `close_session(manifest) -> cleanup/restoration and terminal record` even after failures/interruption where possible.
6. `build_review_packet(evidence) -> sanitized inspection artifact` without granting a verdict.
7. `record_owner_verdict(packet, scenario, decision) -> append-only linked review entry`.
8. `assess_readiness(candidate, rules, evidence, owner_verdicts) -> READY | NOT_READY(reasons)`; read-only, no release publication.

Every command or API has a separate dry-run/simulated-transport validation path; simulation results do not count as physical product qualification.

## 5. Data and state model

### 5.1 Versioned artifacts and plans

A plan contains stable scenario IDs, selected scenario order, rule references and rule digests, required fixture capabilities, applicable platform matrix, evidence sufficiency class (`objective_review` or `direct_owner_observation`), approved latency thresholds and bounded timeouts. A plan contains no delivery/planning identifiers.

A candidate identifies its release artifact hash, version, source revision, signing certificate identity, application identity, platform, architecture, and build-mode verification. The comprehensive qualification app and exact distributable artifact are separate, linked but noninterchangeable candidates.

### 5.2 Immutable session authorization

The private manifest binds: `authorization_id`, canonical digest, designated owner, target serial or device identifier (private only), opaque public device reference, exact artifact digest and certificate, package/bundle identity, plan/rule digests, private fixture-manifest digest, allowed typed operations, expected reset/no-reset state, permitted remediation, timeout ceilings, storage reserve policy and approval.

An operator cannot change these fields by command-line override once the session begins. Changes require a new authorization. A build is a separate operation; an execution must not substitute a newly built artifact for the approved binary.

### 5.3 Result layers

- **Assertion:** `PASS`, `FAIL`, `BLOCKED`, or `NOT_RUN` on a specific expected observation. Negative content acceptance may legitimately `PASS` when the specified rejection occurs.
- **Configuration applicability:** `REQUIRED`, `SUPPORTED`, or `EXCLUDED_UNSUPPORTED` as declared by the approved capability matrix. Exclusion is not an observed product PASS.
- **Automated scenario:** `PASS`, `FAIL`, `BLOCKED`, or `NOT_RUN` derived from eligible assertions and required configuration coverage.
- **Session:** terminal success, product failure, blocked admission, interruption, or cleanup/restoration failure; never silently resumed.
- **Owner scenario verdict:** separate `PASS`, `FAIL`, `BLOCKED`, or `NOT_RUN` with precise evidence and rule links.
- **Platform/release assessment:** `READY` or `NOT_READY`, with machine-readable reasons. A platform READY does not imply whole-release READY.

### 5.4 Append-only evidence

Use canonical, schema-validated JSON with current-version parsing only. Each recorded assertion references a session, sequence, scenario, rule revision/digest, exact artifact, private fixture alias, expected and sanitized actual observation, observation kind, timestamps, result basis and environment profile. Include append-only mutation/restoration and terminal/interruption records, and a final integrity-linked manifest.

ROM bytes, names, private ROM hashes, raw directories, passwords, sensitive UI trees, raw screenshots, device serials and unredacted command output do not belong in publicly shared evidence. Private owner-only manifest files may contain precise device and fixture identities. Owner approvals reference evidence digest(s), not mutable report paths alone.

Retain historical records until authorized disposal but do not require the current assessor to understand an old evidence schema. Prefer backward-compatible schema changes where practical. Only current-schema eligible evidence can be aggregated into a new automated assessment; no in-place evidence rewriting.

## 6. Workflows and state transitions

### 6.1 Qualification Release preparation

A stable separate qualification package/bundle identity prevents collision with the ordinary product. Android uses Release compilation with debug signing; verify non-debuggable packaging, ARM64 libraries, stable signer fingerprint and identity. macOS uses Apple Development signing, expected sandbox/entitlements and a distinct Keychain service namespace. Pin source revision and essential packaging invariants; do not claim full binary equivalence.

A fresh qualification session normally clears only that app's private state. A no-reset entrypoint runs only with an approved inherited-state reference and read-only membership/job/cleanup admission checks. Secure-store emptiness for fresh state is independently established; clearing app data alone is insufficient proof. Owner provisions live credentials through the normal product UI before unattended provider tests.

### 6.2 Admission and preparation

Verify one exact target and active package, approved artifact, signer, target OS/ABI, required tools, required independent fixture expectations, total selected fixture size, effective free space and reserve, ability to restore settings, and applicable configurations. A complete coverage plan is blocked by missing mandatory positive fixtures. A smaller explicitly authorized plan may proceed without claiming full release coverage.

Preparation may install approved host tools, establish exclusively owned temporary fixture roots, prevalidate ROM bytes and companion relationships, stage streamed copies, confirm staged digests, and make only authorized reversible app-specific setting changes. Source originals stay read-only. No automatic remediation after product execution begins.

### 6.3 Product execution and observation

UI interactions require one uniquely identified accessible control, validated application foreground identity, and a verified transition; no inferred or guessed tap location. Changes to normal user-facing accessibility semantics require a separate code change and a newly pinned artifact before resumption. Accept observations of actual Library content, job state, provider outcomes, and fixture relationships only when the normal product surface can establish their meaning.

At runtime an unexpected assertion FAIL or unresolved BLOCKED condition ends further product scenarios. Read-only polling within approved deadlines is allowed; automatic retry of a mutating operation is not. Each new attempt receives a new session authorization, and prior failure evidence remains.

### 6.4 Unavailable-source simulations

Execute both reversible mechanisms where authorized and supported: (1) hide and restore an exclusively owned source at its expected path without changing its content, (2) temporarily deny and restore only the qualification app's supported storage permission/app-op. Validate the induced unavailability, product response and recovery; retain pre/post expected state observations specifically required by this scenario. Declare the induced cause as `simulated_path_loss` or `simulated_permission_denial` in evidence. Do not claim actual removable-media hardware was exercised.

### 6.5 Distributable smoke

Use the exact distributable binary under an independent bounded authorization. Reject unsafe install, downgrade, signing mismatch and any need to uninstall or clear ordinary-app data. Test installation/startup, actual signing and identity-dependent system behavior, permission/credential boundary, basic Library operation, and bounded lifecycle. No root additions, credential mutations or Refresh without separate explicit authority. Package-manager data retention is not app-record preservation proof.

### 6.6 Owner review and assessment

Produce a deterministic sanitized review packet with eligible scenario matrix, exact expectations, observed facts, missing proof, environment and artifact provenance, explicit failures/blockers, and verified cleanup state. Owner signs off objective scenarios by inspecting sufficient evidence and attends subjective TalkBack/readability tests directly. New owner decisions append to a separate review stream; corrections supersede earlier verdicts without editing them.

Assessment combines current-schema compatible sessions for the same exact artifact, expected fixtures and relevant environment, checking each scenario against its exact acceptance-rule revision/digest. A changed binary invalidates qualification eligibility; a changed rule requires new evidence for affected scenarios, while evidence for unchanged scenario rules may remain eligible despite a later plan revision. Legacy evidence may be retained but is not implicitly reused. Mandatory covered scenarios, owner PASS results, supported-format obligations, distributable smoke, and restored environment must all pass before whole-release `READY`.

## 7. Persistence and retention

Evidence is owner-private and append-only. Write durable assertions before advancing to the next observation boundary. If an execution is found unterminated after a crash, append an interruption entry; never reconstruct a success or auto-resume. Temporary screenshots must be in private session-owned storage, deleted immediately after inspection, and scrubbed on verified startup cleanup; any unverified cleanup blocks later automation. Separate fixture staging can only be cleaned with exclusive ownership proof. No automatic disposal of historical evidence.

## 8. Concurrency and cancellation

No host/device mutex or session lock in v1; this is an explicitly accepted operational risk. The operator rechecks physical target, package, foreground application and relevant environment on device operations. Observable competing activity terminates the session. Cancellation does not skip mandatory cleanup or alter already committed evidence. Session deadlines, scenario deadlines and action deadlines are independently bounded and may not extend themselves during a run.

## 9. Failure and recovery behavior

- Missing or unverified prerequisites: `BLOCKED` before admission unless repaired within the authorized preparation stage.
- Unexpected product behavior: `FAIL` and fail fast; no hidden retries.
- Expected malformed input rejection: `PASS` only when documented negative oracle and unrelated-record integrity checks succeed.
- Missing mandatory observation: `BLOCKED`, never infer success from UI labels alone.
- Unsupported configuration: record capability-matrix exclusion; a scenario can pass only when its remaining mandatory supported configurations pass, and cannot pass with zero exercisable required configurations.
- Restoration failure, unknown session-owned cleanup, device substitution, signer mismatch, foreign-app selection, insufficient disk reserve, or corrupt fixture: `BLOCKED`, owner follow-up required.
- A past session that failed cannot become successful because another session subsequently passed; both remain immutable and can be assessed separately.

## 10. Events and observability

Event categories: admission, preparation, fixture staged/verified, device mutation, UI interaction, assertion observation, scenario verdict proposal, fail-fast termination, cleanup/restoration, execution terminal state, owner review, and readiness assessment. Use sanitized identifiers and fixed categorical messages. A local review UI or static report may present aggregated events without owning the original evidence.

## 11. Security and privacy

No production-internal debug/qualification APIs, direct database access, secret extraction, raw ROM capture, or arbitrary shell commands inside the approved driver. Allowlisted operations constrain the qualification workflow, not a generally privileged Codex operator. Privately scoped device identifiers and fixture hashes must not flow into public logs. Screenshot access is transient and deletion/restoration must be verifiable. Live provider secrets enter only through ordinary user-facing credential setup.

## 12. Performance requirements

Action, scenario and total-session timeouts are versioned and pinned. Foreground responsiveness under active background work uses separate owner-approved latency ceilings calibrated from repeated measurements on representative workloads before qualification. Staging has no arbitrary fixed total-size cap, but requires streamed copies, realistic available capacity and OS/app free-space reserve, with precise failure rather than disk exhaustion.

## 13. Testing and acceptance

1. Host/CI safety tests: exact target binding, signature rejection, manifest mismatches, unsafe operation rejection, ambiguous UI target, storage reserves, partial fixture copy, cancellation, crash recovery, staging cleanup, settings restoration, legacy schema refusal, fail-fast behavior and owner-review separation.
2. Full physical format coverage: every supported positive format declared by the production catalog, with independently validated ROMs provided by the owner; target platform-specific cases and Rust format compatibility tests complement one another.
3. Functional: onboarding, roots, scanning, grouping, content detail/actions, browsing, filters, search, sorting, metadata/artwork, provider boundary, lifecycle, process loss, retry, simulated source/path/permission absence, malformed input and unaffected-record integrity.
4. Android accessibility: effective 48 x 48 dp touch regions with approved exceptions; labels, roles, focus/states and reachable controls; applied font scales 1.0, 1.3 and 2.0 and supported display configurations; transient visual review plus owner-attended subjective checks.
5. Qualification system first physical acceptance demonstration: one owner-authorized isolated Release physical session with artifact/fixture admission, one genuine product assertion, fail-fast path, append-only evidence, verified cleanup and usable owner packet.
6. No code-review/CI result grants authorization to operate a physical device; each session has its own specific owner-approved manifest.

## 14. Out of scope

Automatic final PASS, arbitrary privileged app introspection, dynamic dependency graphs, nonlocal device control orchestration, universal historical schema adapters, all-format automatic ROM acquisition, unbounded credential provisioning, automatic releases, and mandatory physical removable-media removal.

## 15. References

- ARCH-001, ARCH-002, SPEC-X-001, SPEC-X-002, relevant product identity/Library/provider specifications.
- Owner-approved 126-decision design record, separate from this normative technical specification.
- Historical manual and physical automation records as immutable archival provenance, not as current executable test definitions.
