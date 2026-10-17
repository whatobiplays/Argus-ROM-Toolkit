# Argus Qualification

**Document ID:** REF-QUAL-001
**Status:** Complete
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-001, ARCH-002
**Supersedes:** None
**Superseded By:** None

## Adoption and provenance

This is the canonical REF-QUAL-001 glossary adopted from approved source `CONTEXT.md` (SHA-256 `e33b456245c987427f3b5b6cf0d8391a3aa0f69b28be101513901def848c262d`). Its source sentence describing a design-session draft records the pre-approval state; the governed metadata above records current adoption. The source vocabulary below is retained without rewriting. Package approval and all source hashes appear in [REF-QUAL-002](docs/reference/qualification-design-decisions.md).

## Approved source vocabulary


Vocabulary for repeatable product qualification of a specific release artifact in a controlled environment. This is a design-session draft, not a committed repository document.

## Language

**Qualification Plan**:
A versioned specification of the product behaviors and scenarios to evaluate against a release artifact.
_Avoid_: Ad hoc test script, release checklist

**Qualification Scenario**:
One named, bounded product behavior with explicit prerequisites, expected observations, and acceptance criteria.
_Avoid_: Script command, assertion

**Qualification Session**:
One owner-authorized execution of a qualification plan against a pinned artifact and identified environment, with bounded authority and recorded outcomes.
_Avoid_: Unbounded test run

**Session Authorization**:
The owner's approval of a specific artifact, target, scope, and permitted operations for one qualification session.
_Avoid_: Blanket device permission

**Automated Assertion**:
A machine-evaluated check of observed product behavior against independently defined expected behavior.
_Avoid_: Owner verdict

**Automated Result**:
A machine-produced scenario outcome grounded in assertions and observations; it does not confer final qualification authority.
_Avoid_: Qualification approval

**Owner Verdict**:
The owner's final determination for a qualification scenario, based on direct observation or reviewed, sufficient objective evidence according to the scenario's approved evidence requirements.
_Avoid_: Script pass, automatic approval

**Qualification Evidence**:
Sanitized product observations and provenance retained to substantiate automated results and owner verdicts, excluding sensitive content.
_Avoid_: Raw test dump

**Release Artifact**:
The exact signed product binary under evaluation, identified by an immutable digest and build provenance.
_Avoid_: Latest build

**Qualification Target**:
The specific environment and installed product state against which a session executes.
_Avoid_: Any connected device

**Fixture Corpus**:
An owner-approved immutable collection of representative content and synthetic cases used to exercise documented behavior.
_Avoid_: Arbitrarily selected files

**Fixture Expectation Manifest**:
A private, versioned statement of expected outcomes for the approved fixture corpus, defined independently of the application under test.
_Avoid_: Expected results inferred from product output

**State-Preserving Qualification**:
Qualification against an existing configured installation without an authorized data reset. App data retention is intended, but the term alone does not prove preservation of application records.
_Avoid_: Fresh install, reset run, verified backup

**Fresh-State Qualification**:
Qualification from an explicitly authorized cleared-data installation, with no assertion of preserving its previous application state.
_Avoid_: State-preserving run

**Provider Contract Check**:
Deterministic verification of provider integration behavior using controlled responses without claiming success against the live provider.
_Avoid_: Live provider qualification

**Live Provider Qualification**:
Assessment of production provider behavior through a real service and its normal application credential boundary.
_Avoid_: Stubbed provider check

**Fail-Fast Qualification**:
Execution that stops further scenarios on an unexpected failure or unresolved blocked prerequisite, retaining completed evidence and performing mandatory safe cleanup.
_Avoid_: Automatic scenario retries, continue-on-failure

**Transient Visual Capture**:
An image temporarily acquired for automated visual observation and deleted after inspection; it is not retained as qualification evidence.
_Avoid_: Archived screenshot evidence

**Qualification Execution Record**:
An immutable, append-only account of a qualification session's observed assertions, outcomes, artifact identity, and restoration status.
_Avoid_: Editable owner verdict

**Session-Owned Resource**:
A fixture, temporary capture, or environment change created under one identifiable qualification session's exclusive control.
_Avoid_: Arbitrary device file

**Prerequisite Remediation**:
A bounded, expressly authorized preparation action that resolves a missing qualification prerequisite without representing itself as a product test result.
_Avoid_: Product repair, scenario retry

**Qualification Preparation**:
The authorized portion of a qualification session that establishes required tools, permissions, and test resources before evaluating product scenarios.
_Avoid_: Qualification result, silent repair

**Owner-Attended Session**:
A qualification session in which automated interactions are paired with direct owner observation for judgments that cannot be established by objective assertions alone.
_Avoid_: Unattended automatic verdict

**Scenario Oracle**:
The independently specified expectations and observation rules used to decide whether a qualification scenario behaved correctly.
_Avoid_: App-reported success alone

**Authorized Device Operation**:
A specifically enumerated action permitted within a session's agreed scope and subject to its documented safety and restoration conditions.
_Avoid_: General-purpose ADB permission

**Qualified Fixture Root**:
A separate Library source containing session-owned copies of approved fixtures, admitted through normal product interactions.
_Avoid_: Reused historical content directory

**Evidence Review Rule**:
A scenario-specific, preapproved standard specifying which observations are sufficient for retrospective owner sign-off and which require direct owner observation.
_Avoid_: After-the-fact pass criteria

**Qualification Release Variant**:
A release-configured signed application with a distinct install identity, intended to run a controlled fixture-only Library without sharing the ordinary application's installed data. It is not the identical distributable binary.
_Avoid_: Debug test harness, original production APK

**Distributable Release Artifact**:
The signed application packaged with the product's normal public installation identity.
_Avoid_: Qualification variant

**Fixture-Only Library**:
The Library state of an isolated qualification installation containing only the approved fixtures for its authorized test plan.
_Avoid_: Arbitrary personal Library

**Release Variant Equivalence**:
An evidence-backed claim that a qualification Release variant and its distributable counterpart share the specified product behavior despite their different application identities.
_Avoid_: Identical binaries

**Format Coverage Matrix**:
A versioned set of supported archive and compressed-media representations requiring independent positive qualification observations.
_Avoid_: One sample format stands for all

**Simulated Source Unavailability**:
A deliberate, reversible loss of access to a qualification-owned source induced by a controlled test operation rather than actual media removal.
_Avoid_: Physical removal, demonstrated removable-media unplug

**Distributable Smoke Qualification**:
A bounded assessment of the exact public Release artifact to verify identity-dependent installation, startup, permissions, secure storage, and essential product behavior not established by the isolated variant.
_Avoid_: Full fixture matrix, isolated-variant qualification

**Release Variant Equivalence Evidence**:
Recorded provenance supporting comparison of a qualification variant with its distributable counterpart, including their common source revision and known packaging differences; source equality alone does not prove identical behavior.
_Avoid_: Byte-identical build claim, proven behavioral equivalence from source equality alone

**Qualification Credential Namespace**:
The qualification application's distinct secure-credential identity, isolated from credentials belonging to the normally installed app.
_Avoid_: Shared production credentials

**Controlled Path Unavailability**:
A reversible, authorized change that makes a session-owned content source inaccessible at its expected location and then restores that location without altering its contents.
_Avoid_: Media unplug

**Controlled Permission Unavailability**:
A reversible denial of the qualification application's source access through a supported permission mechanism, followed by restoration of its prior access state.
_Avoid_: Physical media removal

**Application-Identity Boundary**:
The package or bundle identity that separates the installed qualification application and its operating-system-managed state from the ordinarily installed app.
_Avoid_: Window title, app icon

**Qualification Signing Profile**:
The signing identity of an isolated qualification artifact, which can differ from the distributable Release while the artifact is still compiled using production Release settings.
_Avoid_: Debug build, distributable signature

**Distributable Artifact Smoke Result**:
An outcome from a separately authorized test of the exact publicly identified Release binary, distinct from the isolated qualification variant's functional results.
_Avoid_: Qualification variant result

**Qualification Reset Policy**:
A session-specific commitment to fresh qualification-app data by default or explicitly authorized preservation of the qualification app's existing state.
_Avoid_: Implicit reset, automatic clearing of the ordinary installed app

**Qualification Data Reset**:
An authorized clearing of only the isolated qualification application's private state, without claiming that separate secure-credential namespaces or external fixture directories are also cleared.
_Avoid_: Fixture cleanup, credential deletion, normal-app reset

**Private Qualification Target Reference**:
An opaque identifier used in shared execution evidence to refer to a physical target whose identifying details are held only in the owner-private session authorization.
_Avoid_: Published ADB serial, app display name as device identity

**Qualification Credential Baseline**:
The independently verified credential state of the isolated qualification application's secure-store namespace before a session begins.
_Avoid_: Assumed fresh credentials, ordinary-app credentials

**Verified Staged Fixture**:
An owner-provided fixture copy whose bytes and required companion-file relationships have been checked against the approved private manifest before the qualification application can admit it.
_Avoid_: Partially transferred fixture, unverified upload

**No-Reset Admission State**:
The specifically authorized pre-existing qualification-app state against which a no-reset session checks its starting conditions, including relevant Library membership, job state, and unresolved cleanup.
_Avoid_: Arbitrary inherited app data

**Session Interruption Record**:
An append-only evidence entry identifying an execution that ended without normal terminalization, without altering observations already recorded.
_Avoid_: Reconstructed successful completion, silent automatic resume

**Qualification Assessment**:
An owner-reviewed evaluation of whether a release candidate satisfies the approved qualification requirements using compatible execution records and separately identified distributable smoke evidence.
_Avoid_: Union of arbitrary green test runs

**Owner Review Record**:
An append-only statement of the owner's scenario verdict, linked to exact execution evidence and a predetermined acceptance rule, which can only be corrected by a new superseding record.
_Avoid_: Editing automated results, GitHub comment as sole approval

**Qualification Acceptance Rule**:
A versioned, preapproved statement of the required observable outcomes and evidence sufficient to evaluate a qualification scenario.
_Avoid_: Runtime-selected acceptance criteria, after-the-fact pass rationale

**Qualification Review Packet**:
A sanitized, human-readable assembly of linked execution evidence and acceptance-rule coverage prepared for owner adjudication.
_Avoid_: Owner verdict, conversational run summary

**Release Qualification Gate**:
The requirement that all applicable mandatory qualification scenarios, coverage obligations, cleanup outcomes, and distributable-artifact checks have compatible owner-approved evidence before a candidate can be accepted.
_Avoid_: Percentage of green scripts, project completion status

**Qualification Candidate**:
A particular release artifact and its pinned relevant qualification inputs whose acceptance is assessed independently of binaries that precede or follow it.
_Avoid_: Any build with the same version number, latest main

**Qualification Latency Criterion**:
A preapproved, measured maximum elapsed time for a specified observable foreground operation under a defined workload.
_Avoid_: Generic timeout, subjective responsiveness judgment

**Platform Qualification Assessment**:
An evaluation of whether one supported platform's mandatory product qualification scenarios have sufficient owner-approved evidence, without claiming whole-release readiness.
_Avoid_: Whole-release qualification, project completion status

**Qualification Evidence Archive**:
Retained historical execution observations and owner verdicts whose provenance must remain identifiable even when a newer qualification assessor does not support their original schema.
_Avoid_: Automatically reusable current qualification evidence

**Release Readiness Assessment**:
A deterministic evaluation of required platform assessments, verified distributable-artifact smoke results, owner approvals and safety conditions for a pinned release candidate; it does not publish the release.
_Avoid_: CI green status, automatic release publication


**Platform Capability Matrix**:
A preapproved statement of which product qualification configurations are applicable and exercisable on a specified supported environment.
_Avoid_: Runtime-inferred waiver, arbitrary skip list

**Current Qualification Evidence**:
A qualification execution record expressed in the evidence schema currently supported by the assessment system and eligible for compatibility checks against the relevant artifact, rule, and fixture versions.
_Avoid_: Any archived evidence regardless of schema

**Qualification Evidence Exclusion**:
A documented conclusion that a particular configuration is not supported by the authorized platform capability matrix, distinct from an assertion that the tested product behavior passed.
_Avoid_: Unrecorded skip, successful execution

**Qualification Acceptance Revision**:
A specific version of the preapproved observation rules that governs a scenario, independent of the application binary version.
_Avoid_: Candidate-specific passing threshold

**Qualification Operator**:
The trusted agent or person executing an authorized qualification session using the required operational controls, distinct from the owner who issues final verdicts.
_Avoid_: Automated release approver