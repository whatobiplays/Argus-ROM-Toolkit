# Governed Qualification Decision Record

**Document ID:** REF-QUAL-002
**Status:** Complete
**Owner:** Daniel
**Last Updated:** 2026-10-15
**Depends On:** ARCH-003, REF-QUAL-001
**Supersedes:** None
**Superseded By:** None

## Owner approval and archive integrity

The owner explicitly approved adoption of the five authority sources for Issue #19 on **October 15, 2026**. This approval is recorded against archive SHA-256 `f7996b9d5d4e12615179e94c08cb6e3e825ebafc3b0cd259bf36983303c27ee7` and the individual source hashes below. The ZIP passed CRC verification and its members matched the verified inventory. It contains no separate checksum manifest; the hashes were computed directly from the verified member bytes. `README.md` is ancillary archive inventory, not an approved authority source.

| Package member | Role | SHA-256 |
|---|---|---|
| `CONTEXT.md` | Approved authority source | `e33b456245c987427f3b5b6cf0d8391a3aa0f69b28be101513901def848c262d` |
| `design-decisions.md` | Approved authority source; 126 decisions | `ab198ecf0fde7b357a7cd0a81dce1ec50cc7ec86c802259df1d38d6dd3a054cf` |
| `qualification-architecture.md` | Approved authority source; ARCH-003 | `54cdf1d3c43ac27098f3e99467c86660b0e47b05b88e39a1081f3c64dd89c801` |
| `qualification-specification.md` | Approved authority source; SPEC-X-003 | `b25d713ca62a941cdc746709def86a73a5b3a5eac055fe6955c3ce89f51a9b35` |
| `qualification-implementation-plan.md` | Approved authority source; planning artifact only | `6621af8e110acc909e56ab9efbd786f58658d29fe514a83482695f5e5fc94796` |
| `README.md` | Ancillary inventory; not an authority source | `1f3d79555cef8892743585d1bf56035f6812600abeac7a7c17998ffb10e6dd9b` |

The source documents' original draft and pending-approval labels are retained below or in the verbatim planning artifact. They describe the package before this explicit approval. The archive itself remains unchanged.

## Decision-record preservation

The following approved source text is copied verbatim from `design-decisions.md`. All 126 decision entries, rationales, alternatives, failure modes, and invariants remain in their original order and wording. `Q53(custom)` is retained exactly. Draft and pending-approval language inside the source block records the archive historical state; the explicit approval above governs adoption.

<!-- BEGIN APPROVED SOURCE design-decisions.md SHA-256 ab198ecf0fde7b357a7cd0a81dce1ec50cc7ec86c802259df1d38d6dd3a054cf -->
# Argus Qualification Automation - Design Decisions (Draft)

Status: 126 interview decisions settled; consolidated design drafts pending explicit owner approval. This is a working decision record, not an implementation or device-execution authorization.

## Settled - Round 1 (Q1-Q10)

- Q1A: Scope: prioritize Android, content, and Android accessibility, with architecture that can later support desktop qualification.
- Q2A: Authority: owner retains final scenario verdicts; automated final decisions may be considered later.
- Q3B: Autonomy: owner authorizes a bounded qualification session rather than each device operation individually.
- Q4A: Fresh-state: use separate device or a separately authorized reset; preserve the existing Android installation.
- Q5A: Product observation: qualify the signed production Release through black-box interfaces and independent expectations, not test-only instrumentation.
- Q6C: Visual evidence: allow transient image inspection but retain only sanitized structured findings.
- Q7A: Fixtures: owner-approved immutable corpus plus synthetic positive and negative cases.
- Q8A: Providers: deterministic integration checks are distinct from actual live-provider qualification.
- Q9A: Session policy: fail fast on a failed scenario; dependency-aware continuation is a possible future enhancement only.
- Q10A: Lifetime: reusable qualification infrastructure, independent of planning terminology and reusable across releases.

## Settled - Round 2 (Q11-Q20)

- Q11B: Sign-off: owner may approve objective scenarios after reviewing sufficient automated evidence; subjective UX still requires direct owner observation. This will require updating the existing manual qualification contract.
- Q12C: Naming: planning-language identifiers must be removed from active qualification implementation and test plans; user also wants historical documentation rewritten. Historical provenance treatment remains to be resolved.
- Q13A: Scope of authorization: one session may authorize in-place installation, jobs, UI operation, controlled force-stop/relaunch, and reversible setting changes; destructive operations remain prohibited.
- Q14A: Driver: Python, ADB, and accessibility/UI hierarchy are the primary automation stack; Android UI Automator instrumentation is an optional future enhancement.
- Q15A: Artifact: pin exact binary digest, signing identity, source provenance, and version; no implicit rebuild or substitution.
- Q16A: Outcome evidence: assertions must compare observable product behavior against independent expected facts. Unverifiable outcomes cannot be recorded as objective passes.
- Q17A: Fixture manifest: keep private, versioned expectations outside the repository; public code contains generic test definitions only.
- Q18A: Credentialed live providers: owner provisions credentials through the production app boundary; automation must not read secret values.
- Q19A: Visual capture: use owner-private, temporary files where necessary, delete immediately, and detect cleanup failures.
- Q20A: Fail-fast trigger: stop on unexpected product failure or blocked prerequisite. Expected rejection in a negative scenario is success when the expected assertions are satisfied.

## Settled - Round 3 (Q21-Q32)

- Q21A: Historical migration: modernize current documents and archive immutable historical execution records with their original facts and references. Project planning terminology remains confined to planning and archive artifacts, not active qualification code, test plans, or product qualification interfaces.
- Q22A: Entry points: keep state-preserving and fresh-state execution paths separately invocable; share safe libraries rather than using a single destructive mode switch.
- Q23A: Authorization: owner approves an immutable manifest pinned to device identity, APK digest, plan, fixture expectations, permitted operations, and bounded execution limits. Refuse mismatches.
- Q24A: Fixtures: existing device fixtures remain read-only; new copies belong to uniquely identified sessions and cannot be overwritten or deleted without conclusive ownership.
- Q25C: Installed app preservation: rely on Android package-manager data-retention behavior for an in-place update, without mandatory app-level before/after baseline checks. Do not assert that historical records were independently verified as preserved.
- Q26A: UI interactions: accessibility-first selectors and verified transitions; no guessed coordinates. Trivially fixable accessibility implementation gaps may be corrected in product code when they do not alter normal product functionality; the exact boundary and release re-qualification behavior remain open.
- Q27A: Screenshot cleanup: temporary owner-private captures are deleted after use, abandoned owned captures are detected on startup, and unverified cleanup blocks further automation.
- Q28A: Timeout and retry: bounded per-action, per-scenario, and per-session deadlines; repeat read-only observations but do not retry state-changing operations automatically.
- Q29A: Restoration: attempt bounded restoration; if not verifiable, block subsequent automated sessions until the owner resolves the environment.
- Q30A: Records: immutable append-only execution evidence and separate linked owner qualification verdicts.
- Q31A: Acceptance: each scenario declares its versioned evidence requirements and whether retrospective owner approval is permissible before it runs.
- Q32C: Missing prerequisites: permit Codex to remediate prerequisites automatically rather than always stopping at read-only preflight; exact remediation authority and safety limits remain to be decided.

## Existing-contract friction to resolve

1. The manual qualification ledger currently allows final PASS only on direct owner observation; that rule must be revised before reviewed automated evidence can support owner verdicts.
2. The existing physical Android runner resets application data and can remove a fixture directory; it must never be used unmodified on the state-preserving target.
3. Prior execution records and reports include older names and paths. A terminology migration must not falsify or erase historical provenance.
4. Production black-box qualification cannot rely on test-only bridge or internal database inspection. If required facts are unobservable, record a blocker rather than inventing evidence.
5. Choosing package-manager success without app-level preservation comparison cannot establish that historical JobRun or root records survived; subsequent product scenarios must not imply such proof.
6. Automatic prerequisite remediation must be reconciled with immutable authorization, fail-fast testing, and mandatory device-setting restoration.
7. Improving accessibility semantics changes production-facing TalkBack behavior even if it leaves the visual and business behavior unchanged; define permissible repairs and rebuild/re-authorization boundaries.

## Deferred

- Automatic final qualification verdicts.
- Dependency-aware continuation following scenario failure.
- Native Android UI Automator driver.
- General cross-platform qualification framework.

## Settled - Round 4 (Q33-Q44)

- Q33A: Preparation repair authority: only explicitly authorized, bounded prerequisite repairs are allowed, including approved host tools, session-owned fixture preparation, and reversible device settings. No credential creation, data reset, automatic APK replacement, or unrelated file mutation.
- Q34A: Preparation boundary: remediation is confined to an explicit preparation stage before product qualification begins. A prerequisite becoming unavailable during execution ends the session; no state-changing scenario auto-retry.
- Q35A: Accessibility improvements: improve production accessibility labels, roles, hints, and identifiers without altering product functionality or visual behavior. Any necessary product change occurs before building and pinning the qualifying Release; an issue found mid-session requires a new artifact and new authorization.
- Q36A: Preservation proof: retain Q25C without exceptions. An `adb install -r` success is evidence only for package-manager success; no special mandatory verification of the prior failed job or configured root. Neither historical-record nor logical-state preservation is independently claimed.
- Q37A: Fixture ownership: newly staged fixtures live under a uniquely created session-owned directory and are admitted as a separate qualification root through the production UI. Keep them until explicitly authorized cleanup; existing fixture locations remain read-only and untouched.
- Q38A: Device operations: a typed ADB/device-operation allowlist with preconditions, ownership proofs, and restoration rules. No arbitrary ADB shell commands during qualification.
- Q39A: Evidence: detailed, sanitized, immutable, append-only execution records in an owner-private local store; source control receives only approved sanitized summaries and evidence references, separate from owner verdicts.
- Q40A: Plan: immutable, versioned, linear scenario order, with the owner allowed to authorize a pinned subset. No dynamic reordering or dependency graph in v1.
- Q41A: Owner-attended UX: separate supervised sessions for TalkBack/subjective accessibility or visual observations; Codex may drive the app, but only the owner observes and issues the verdict.
- Q42A: Interrupted/failed sessions: permanently terminated. Preserve completed evidence; a new, separately authorized session may run remaining scenarios; never silently resume.
- Q43A: CI: validates schemas, scripts, simulated-device tests, and host qualification infrastructure. Physical Android Release runs require an explicitly authorized local Codex session, not an always-on self-hosted CI runner.
- Q44A: Deadlines: versioned action/scenario/session timeout profiles based on measured workloads; owner approval required to raise an authorized ceiling; no runtime auto-extension.

## Additional future migration requirements

- Migrate the current `scripts/phase_003_android_physical_qualification` automation into phase-neutral active source, tests, and test plans. Keep retired source references as historical provenance only in planning/archival evidence.
- Implement two explicitly separate invocation paths for state-preserving versus fresh-state execution, with shared safe primitives.
- The existing signed Release candidate is immutable for a session. Accessibility fixes discovered during the run belong to a new binary and new session; never replace the binary under qualification.
- Since historical-data preservation is not checked, write precise report claims: `installed with data-preserving package-manager operation`, not `historical JobRun preserved`.
- New state-preserving fixtures require a newly owned directory and separate product-admitted Library root; cleanup requires its own authorization.

## Settled - Round 5 (Q45-Q56)

- Q45A: versioned and schema-validated fixture expectations cover platform, representation, logical identity, grouping, source membership, ordering, and relevant metadata as needed by each scenario.
- Q46A: ground truth is established independently through trusted parsers, format specifications, generated known fixtures, and owner-reviewed expectations with provenance; never bootstrap truth from Argus.
- Q47A: unobservable essential product requirements result in BLOCKED, not a plausibility-based PASS.
- Q48A: equivalence and grouping assertions cover logical identity, duplicate suppression, source attribution, and supported ordering; game count alone is insufficient.
- Q49B: complete release qualification exercises every supported archive and compressed representation. The approved representation design currently lists ZIP, 7z, tar, gzip, bzip2, xz, CHD, RVZ, CSO, and WBFS. Exactly which platform/representation combinations require physical coverage is not yet decided.
- Q50A: a negative malformed-content scenario may perform narrow before/after observation of specified unrelated control records, without introducing a general installation-preservation comparison.
- Q51A: no-match fallback uses independently approved expectations; changing upstream assumptions trigger separate fixture revalidation rather than silently changing acceptance criteria.
- Q52A: live-provider oracles verify identity, attribution, association, and presentation semantically, not exact mutable pixels/text. Independently proven service unavailability is BLOCKED; incorrect handling of an available response is FAIL.
- Q53(custom): qualification should run under a distinct platform application identifier (Android application ID, macOS bundle identifier), with a fixture-only Library and independent app data from ordinary debug/release installations. This changes the previously assumed exact-distributable-binary qualification model; equivalence and authority need explicit clarification.
- Q54A: qualify the app's content-action selection/handoff or truthful unsupported feedback; actual emulator execution belongs to separate integration coverage.
- Q55A: automated geometry, accessibility semantics, scale-state and clipping checks complement direct owner review of announcement quality and visual usability.
- Q56B: controlled permission denial or qualification-owned source renaming may simulate source unavailability in place of physical detach for this testing model. Current mandatory AND-06/CNT-11 wording requires genuine supported unavailability; acceptance wording and simulated-vs-physical reporting must be explicitly reconciled before a simulated result can count.

## Round 5 decisions requiring downstream resolution

1. The qualification Release variant is signed and release-configured but necessarily differs from the exact distributable APK/app because the installation identifier changes. Decide which outcomes the variant may qualify and whether a separate distributable-binary smoke check is required.
2. Android currently fixes `applicationId` in Gradle and the Python runner fixes the package name. macOS currently uses a fixed bundle identifier in AppInfo.xcconfig. Build variant selection and validation must be explicit and phase-neutral.
3. macOS secure credential storage uses a fixed service namespace (`org.argus-rom-toolkit.providers`), independent of its bundle identifier; a distinct app ID alone is insufficient proof of credential isolation.
4. The full format matrix is broader than the historical physical scenario minimum and includes six generic archive/stream formats plus four compressed optical representations. Need a versioned coverage definition.
5. Simulated source absence from path changes and permission denial may exercise different failure classifications from genuine media removal; qualification acceptance must not conflate these observations without a deliberate contract revision.
6. Session authorization and isolation rules must distinguish operations on the dedicated qualification application from any operation against the ordinary installed production application.

## Settled - Round 6 (Q57-Q66)

- Q57B: comprehensive functional qualification uses an isolated signed Release variant, followed by a smaller identity-sensitive smoke qualification against the exact distributable Release artifact; neither binary is represented as identical to the other.
- Q58A: use explicit, reproducible, phase-neutral Android/macOS Release build variants; allow only reviewed packaging/identity differences, preserve production runtime logic and release optimization, and validate permitted differences.
- Q59A: isolate macOS qualification credentials using a separate secure-store service namespace; do not share the ordinary app's Keychain entry.
- Q60A: fresh-state execution may clear only the qualification app when separately authorized. State-preserving execution never performs a reset and verifies the fixture-only Library as a prerequisite.
- Q61A: require one positive physical product scenario for each supported format (currently ZIP, 7z, tar, gzip, bzip2, xz, CHD, RVZ, CSO, WBFS). Use deterministic contract tests for the full advertised platform/representation matrix and targeted physical checks rather than every cross-product combination physically.
- Q62A: revise mandatory acceptance criteria so controlled simulated source loss/restoration qualifies source-unavailability behavior; actual removable-media removal becomes an optional, separately identifiable hardware-integration test. Do not report simulation as physical removal.
- Q63A: test both distinct simulated failure mechanisms: session-owned source path relocation/unavailability and qualification-app-specific permission denial/restoration. Both require explicit authorization and verified restoration.
- Q64A: provision any live provider credential through the qualification application's ordinary production credential UI and secure boundary; Codex must not read credential bytes, and credentials must not be copied from the normal installation.
- Q65A: preserve the existing GT78-VN ordinary Argus installation untouched; install the isolated qualification variant side by side. The exact distributable Release receives a separate, explicitly authorized smoke session, not implicit installation/replacement during variant execution.
- Q66A: verify authorized package identity and foreground activity before every product interaction; reject ambiguous/foreign targets except narrowly enumerated Android system permission and picker surfaces.

## Consequences and conflicts to resolve downstream

1. Exact distributable smoke qualification and variant equivalence need precise minimum checks, identity-specific state policy, and evidence linking both distinct artifacts.
2. Qualifier app identity may affect Android component authorities, task behavior, app-scoped access and secure storage, and macOS bundle/container, bookmarks and Keychain. All must be included in the packaging-difference inventory.
3. Distinct qualification credentials cannot silently reuse macOS's fixed `org.argus-rom-toolkit.providers` service name; the namespace must be variant-aware while preserving native secure storage.
4. New simulated-unavailability acceptance criteria require a deliberate historical-contract change. Preserve the original requirements and results as historical project planning evidence rather than retroactively claiming prior physical-media testing.
5. Path relocation and permission denial test different loss mechanisms; prove both restore correctly and cannot target the ordinary app or unowned fixtures.
6. Qualifying one positive case per format must cover actual supported decoding/identity/presentation, not header recognition alone. Independent format expectations and validity remain prerequisites.

## Continued deferrals

- Automatic owner-equivalent final PASS authority.
- Dependency-aware continuation after a failed/blocked scenario.
- Android UI Automator instrumentation as primary driver.
- Self-hosted physical-device GitHub Actions automation.

## Settled - Round 7 (Q67-Q78)

- Q67B: execute a separately authorized, data-preserving smoke installation of the exact distributable Release on the existing GT78-VN, after isolated qualification; never clear or uninstall its ordinary application data as part of this smoke session. Per Q36A, this does not certify that historical application records survived.
- Q68C: use ordinary Android debug signing for the *isolated qualification variant*. Q58A still requires Release-mode compilation, optimization, production runtime and no Debug build substitution. Confirm exact signing/configuration semantics in the next round.
- Q69A: configure stable, distinct qualifier application identifiers on Android and macOS rather than generating a new identity per run.
- Q70A: distributable smoke covers actual installation/signature, package identity, startup, permissions, secure credential boundary, basic Library behavior and foreground/background lifecycle.
- Q71B: treat matching source commit as sufficient variant-equivalence assurance rather than adding an automated packaging/runtime-difference comparator. This is a deliberately weaker proof: retain Q58A's design intent to allow only appropriate identity/packaging differences and report equivalence limits explicitly.
- Q72A: derive mandatory format coverage from a versioned production capability catalog. New supported capabilities introduce new qualification obligations; fixture availability does not redefine support.
- Q73A: owner provides the ROM/representation corpus. Independent validation, complete usable positive fixtures, controlled copies, and private expectations are required; Codex does not select or download public ROMs autonomously.
- Q74A: verify separate installed qualification and ordinary credential namespaces using black-box, non-secret observations, with independent authorization for operations against the ordinary app.
- Q75A: simulated permission denial targets only the qualification app's supported storage app-op/permission; snapshot original value, prove denial, restore and verify.
- Q76C: automatically clear the *qualification application's* data before every session to establish a fixture-only Library, never the ordinary application. **Unresolved conflict:** this supersedes or requires an exception to Q60A, Q22A, and the previously approved state-preserving qualification path; decide its effect on persistence/cross-session checks explicitly in Round 8.
- Q77A: store schema-versioned JSON session manifests and append-only evidence events in an owner-private location, with canonical digests, timestamps, artifact provenance, assertion outcomes and cleanup state. Digests alone do not provide tamper-proof attestation.
- Q78B: rely on operator/Codex discipline rather than enforce host/device exclusive locks. Acknowledge that two concurrent sessions could interfere and invalidate results; no automated concurrency safety claim is permitted.

## Round 7 consequences to resolve downstream

1. Decide whether Q76C's always-reset policy eliminates state-preserving sessions altogether or applies only to isolated fresh-state qualification plans. Do not silently claim simultaneous compatibility with Q60A.
2. Android debug *signing* must be distinguished from Debug *build type*: qualification remains Release-mode, non-debuggable, production logic and runtime; its signature is not a production-release signer.
3. Source-revision equality per Q71B does not establish full equivalence across differing package IDs, macOS bundles, entitlements or secure-storage service identifiers. The separate exact-distributable smoke test is mandatory and reports its own artifact provenance.
4. Without a session lock per Q78B, safe execution depends on owner/operator ensuring exclusive control; this is a consciously accepted operational risk.
5. The owner supplies the complete private ROM corpus; do not substitute fake headers, publicly downloaded ROMs, or results inferred from Argus for positive assertions.
6. Normal and qualification installed applications remain distinct, including the environment and credential namespace. Credential isolation checks touching the ordinary app require separately authorized operations.

## Settled - Round 8 (Q79-Q88)

- Q79B: clearing isolated qualification-app data is the default, but a specifically authorized no-reset session is permitted. This refines Q76C and preserves Q60A: an explicitly state-preserving session must not clear app data.
- Q80A: authorized clearing affects only qualification-app private state, not session-owned external fixture directories and not the ordinarily installed app. Do not assume this also clears Keychain entries or other secure credentials stored outside that private state; verify platform-specific behavior separately.
- Q81A: build the Android isolated variant in Release mode with the ordinary debug signing configuration, retaining production optimization/features and `debuggable=false`. The published distributable Release continues to use its actual production signing configuration.
- Q82B: require source commit equality and essential artifact/package checks (Release mode, debuggable status, intended app ID, signing identity, native libraries/components). Do not implement a comprehensive behavioral equivalence or packaging-diff comparator; explicitly report the remaining assurance limits.
- Q83A: use an Apple Development signing identity for local macOS qualification Release builds, retaining and checking required sandbox and security entitlements. Verify the separately built distributable app under its own signing contract.
- Q84A: owner-supplied ROM corpus remains immutable and read-only. Verify a private fixture manifest, copy only the approved fixtures selected for the authorized plan, and preserve multi-file descriptors and layout; never reorganize originals.
- Q85B: remove artificial per-fixture and total staging-size caps. Use available storage rather than a preset quota. This does not grant authority to modify host ROM originals or unrelated device data. Define disk-exhaustion safeguards and partial-copy cleanup in the next round.
- Q86A: block a distributable-artifact smoke installation before mutation when signing mismatch, downgrade, or another condition would require uninstall, data clearing, or a workaround. Do not try an override or represent the previously installed binary as the selected smoke artifact.
- Q87A: do not implement an exclusive device lock. Keep repeated device/app identity checks and fail fast on detected external interference; reports must not assert exclusive ownership or undetectable interference prevention.
- Q88A: keep full physical device identifiers only in protected local session authorization. Bind runtime device checks to those details; use an opaque target reference in shared evidence, and never emit the serial in sanitized reports.

## Round 8 follow-on decisions required

1. The qualifier can be reset by default or left intact only with manifest-bound, explicit no-reset authorization; pin how non-reset sessions prove a fixture-only baseline and how prior run state may be reused.
2. Android app-data clearing and macOS bundle/container clearing may not erase qualification-scoped Keychain or secure-storage entries. Define cleanup or validation of the isolated credential namespace without accessing the ordinary app's secrets.
3. Unlimited fixture-size staging under Q85B requires a policy for observed free-space exhaustion, reserve space, streaming transfers and cleanup of failed partially staged copies. Avoid silently restoring the discarded 8192 MiB cap.
4. Source equality plus minimal packaging checks are not proof of behavioral equivalence: keep separate distributable smoke outcomes and avoid overstated release acceptance.
5. Without enforced locks, repeated target identity and foreground-state checks mitigate, but cannot exclude, concurrent external manipulation.
6. Simulated path-loss and permission-loss tests require separately proven restoration, including when a session fails or terminates unexpectedly.

## Settled - Round 9 (Q89-Q100)

- Q89A: fresh-state preparation must independently establish an empty qualification-specific secure-credential namespace. Remove stale qualification credentials only through an explicitly authorized, product-owned operation, verify removal, and never access or delete ordinary-app credentials. This applies beyond app-private data clearing, especially to macOS Keychain.
- Q90A: credentialed live-provider qualification may include an owner-attended preparation step using the isolated application's ordinary credential UI. After verifying readiness without exposing credential bytes to Codex, the owner-authorized execution can run unattended.
- Q91A: pin the Android qualification signing-certificate fingerprint. A mismatch blocks an in-place no-reset update; any fresh-state uninstall/reinstall requires an explicit authorization and must not affect the ordinary app.
- Q92A: stage fixtures with measured free-space checks, a protected OS/application space reserve, and streaming transfers, without fixed per-fixture or corpus-wide size caps. Insufficient capacity blocks before risking exhaustion.
- Q93A: transfer content into exclusively owned temporary locations. Only fully transferred and independently verified copies may be admitted to the qualification Library. Remove proven session-owned partial copies after failure; report and block on uncertain cleanup.
- Q94A: verify each selected owner-supplied original against the private immutable expectation/identity manifest and verify its staged copy before use, retaining complete multi-file relationships. Any changed source bytes or inconsistent staged copy invalidates the affected authorized run; never silently update the oracle.
- Q95A: a complete qualification plan fails admission if any mandatory positive fixture or representation is unavailable. Explicitly scoped partial plans can run but must not claim complete format coverage; fixture availability cannot reduce the production capability catalog's requirements.
- Q96A: a no-reset authorization names its expected prior application state or originating session. Read-only admission checks must validate fixture-only Library membership, relevant job states, and pending cleanup before operations. Unexpected inherited state blocks, with no automatic normalization or repair.
- Q97A: persist append-only assertion and observation evidence at defined durable boundaries. Upon finding an unterminated execution, append an interruption record without revising prior evidence or resuming that session. The original session remains terminated.
- Q98A: one owner qualification assessment may reference results from multiple completed sessions only when artifact identity, plan and oracle versions, fixture expectations, and relevant environment are compatible. Preserve each underlying execution record; exact distributable smoke and isolated-variant outcomes remain explicitly distinct artifact classes.
- Q99A: smoke testing the ordinary installed distributable application permits only separately authorized, non-destructive checks of identity, startup, permission/credential readiness, basic Library browsing, and bounded foreground/background lifecycle. No root addition, credential changes, or Refresh without independent authorization; no data preservation claim beyond the package-manager operation.
- Q100A: the owner records verdicts in a distinct append-only review stream referencing exact evidence, scenario IDs, rule versions, and explicit PASS/FAIL/BLOCKED outcomes. Corrections append a superseding review entry, never overwrite an execution or approval record.

## Round 9 consequences and remaining decisions

1. A fresh data reset does not establish credential freshness by itself. Credential namespace cleanup and owner-assisted live-provider setup must be explicit preparation stages, compatible with Q34A's preparation-only repair boundary.
2. A no-reset session cannot silently normalize inherited state. Q96A's rejection of unexpected state takes precedence over generic prerequisite repair permission for that session.
3. The storage policy distinguishes unlimited *configured fixture size* from bounded environmental safety: streamed staging, reserve capacity, and proof of exclusive cleanup ownership remain mandatory.
4. Durable append-only observations and owner reviews need a canonical schema, a stable linkage method, and crash/interruption handling that does not claim a resumed session.
5. Aggregated owner assessments must not combine incompatible artifact identities or substitute isolated functional coverage for the exact distributable Release smoke outcomes.
6. Remaining design frontier: measurable UI/accessibility criteria, thresholds and observation rules, owner-review experience, release acceptance aggregation, and staged implementation authority/verification.

## Settled - Round 10 (Q101-Q112)

- Q101A: enforce a minimum 48 x 48 dp effective target for critical Android controls, with a reviewed accessibility justification for explicit exceptions. The effective interactive region, not only the rendered icon, is the criterion; flag ambiguous overlapping targets.
- Q102A: require objective critical-workflow assertions for accessible names, roles, enabled/selected state, focus, and announced/observable state transitions. Owner-reviewed TalkBack announcement quality remains distinct from automated semantics checks.
- Q103A: validate default, 1.3x, and 2.0x Android font scales and default plus expanded display configurations where the target supports them. Assert applied settings before using geometry evidence; unsupported configurations cannot be silently passed.
- Q104A: use deterministic control and essential-text geometry, reachability, clipping, and overlap checks, augmented by transient visual inspection and owner observation when actual readability or usability is subjective. Record the observation boundaries precisely.
- Q105A: establish versioned, measured foreground latency acceptance ceilings for navigation, Library queries, and job controls while background work is active. Freeze acceptance thresholds before qualifying a candidate and distinguish them from safety timeouts.
- Q106A: test product-visible job identity, progress, terminalization, interruption, explicit retry, absence of silent resumption, and nonduplication of relevant work. Essential unobservable properties produce BLOCKED rather than success inferred from a status label.
- Q107A: require schema-validated per-assertion evidence: scenario and rule version, observation type, expected result, sanitized actual result, timestamps, verdict basis, artifact and fixture references, and relevant environment facts.
- Q108A: unexpected failures and timeouts terminate the session and remain in append-only evidence. A new authorized retest produces new evidence; flaky behavior is not erased by a subsequent PASS and merits tracking as a reliability defect.
- Q109A: complete release assessment requires owner-approved PASS for every mandatory scenario, all applicable supported-format coverage, successful exact-distributable smoke, verified safety restoration, and compatible provenance. No threshold pass rate or implicit waiver substitutes for the mandatory acceptance contract.
- Q110A: produce a sanitized local review packet summarizing scenario coverage, assertions, failures, blockers, artifact/environment provenance, and evidence references. An owner's subsequent approval is recorded separately in append-only verdict records.
- Q111A: any changed application binary is a new qualification candidate. Verify its provenance and qualify the new candidate; earlier evidence remains historical but does not by itself certify the replacement binary. No automatic change-impact reuse in v1.
- Q112A: phase-neutral qualification outcomes and owner-approved assessments are consumed through a separate planning-layer mapping. The qualification system does not declare project phases or slices complete.

## Round 10 consequences and remaining decisions

1. Acceptance latency limits must be independently measured and versioned before a session; Codex may not relax a failing threshold during execution.
2. Strong objective accessibility assertions do not establish the entire owner-attended TalkBack and visual-readability requirements by themselves.
3. The current historical manual ledger must be reconciled with owner review of sufficient objective evidence and with the revised simulated-unavailability acceptance contract. Preserve its original facts while changing the active contract.
4. For whole-release closeout, pending macOS UX scenarios remain mandatory even though initial automation delivery focuses on Android; separate the initial Android qualification milestone from a completed release assessment.
5. New binaries require requalification. Plan/tool/schema evolution and evidence retention/migration need their own decisions before implementation.

## Settled - Round 11 (Q113-Q122)

- Q113A: keep phase-neutral, version-controlled qualification acceptance rules. Rule updates require owner-reviewed PRs, and each execution pins its precise rule version and digest. Runtime adjustment to turn a failure into success is forbidden.
- Q114C: the qualification tooling supports only the latest evidence schema. No historical format compatibility adapter or in-place migration is required. The effect on archived evidence, multi-session aggregation and past owner verdicts remains to be clarified, given Q98A, Q100A, Q111A and Q115A.
- Q115A: retain sanitized structured execution evidence and owner verdicts until a separately authorized archive/disposal decision, and preserve necessary provenance of any disposal. This is an archival requirement, not necessarily a requirement that the current assessment tool parse every old schema.
- Q116A: use canonical integrity digests and manifest linkage; pin approved digests in immutable owner review records and publish a sanitized reference when approved. Do not claim cryptographic authenticity or tamper-proofing without an external trust anchor.
- Q117A: measure baseline foreground-operation latency on the actual qualification device under defined, representative workloads; the owner approves fixed thresholds before the qualifying candidate is tested.
- Q118B: automatically omit unsupported platform configurations and count the relevant scenario as passing. This is a deliberate change to Q103A's treatment of unsupported scale settings, but needs a precise boundary to avoid silently waiving Q109A's mandatory coverage. An unsupported prerequisite must not be conflated with a product failure.
- Q119A: a deterministic, read-only readiness assessment evaluates evidence, owner verdicts, mandatory coverage and provenance and reports READY or NOT READY with reasons; it never publishes/tags releases autonomously.
- Q120A: permit platform-scoped assessments. Passing Android qualification does not imply complete release qualification while mandatory macOS scenarios remain outstanding.
- Q121A: implement incrementally in separate, reviewable PRs: contracts/naming, isolated variants, fixture/safety infrastructure, objective execution, evidence/owner review, and physical qualification. Code approval does not authorize physical device operations.
- Q122A: first acceptance milestone is a real, authorized, isolated Android Release qualification session that validates artifact/fixture admission, one real product behavior, fail-fast behavior, durable evidence, safety cleanup and owner-review packet; deterministic host safety tests precede physical execution.

## Round 11 consistency issues (resolved in Round 12)

1. Under Q114C and Q115A, old evidence is retained but might become unreadable to the current assessment tool. Decide whether new assessments must always produce current-schema evidence, or whether a narrowly scoped historical reference remains allowed. Do not silently convert or delete the old records.
2. Q118B can only support a strict mandatory gate if the term *unsupported configuration* is defined outside the runtime candidate's discretion, with clear rules about optional matrix cells versus mandatory coverage. Decide whether an entirely unsupported mandatory scenario can still be marked PASS.
3. Pin the effect of accepted-rule changes on existing evidence for an unchanged candidate. The current design pins rules and artifacts, forbids automatic requalification of changed binaries, and supports only the latest evidence format.
4. Distinguish the typed, allowlisted qualification runner from Codex's general host-machine capability. If unrestricted ADB is otherwise available, a runner-level allowlist is not a hard security boundary; decide whether that operational risk is accepted in v1.
5. The implemented architecture must preserve the distinction between current evidence assessment and historical audit retention, and between platform-specific readiness and overall release readiness.


## Settled - Round 12 (Q123-Q126)

- Q123A: strive for backward-compatible evidence changes where feasible, but the current automated qualification assessor need only read the latest evidence schema. Retain older structured evidence and owner review records as historical provenance; do not require migration, compatibility adapters, deletion, or perpetual reassessment of obsolete formats. Compatibility is a design goal, not a release gate.
- Q124A: a preapproved platform capability matrix controls which configurations are supported. Unsupported configurations may be automatically excluded with an explicit recorded reason; passing the remaining required supported configurations is sufficient for scenario PASS. If no required configuration can actually be exercised, mark the scenario BLOCKED, never PASS.
- Q125A: changes to acceptance rules require new evidence for the affected scenarios, even when the tested application binary is unchanged. Compatible, unaffected evidence for the same pinned binary may remain eligible. This does not override the requirement to requalify a *changed* application binary.
- Q126A: Codex is a trusted local host operator. The qualification runner's typed operation allowlist and owner-approved authorization manifest are the approved process controls, not an OS-enforced sandbox preventing a Codex host shell from running ADB directly. Document this limitation and enforce the policy in runner tests and review.

## Consolidated reconciliation

1. New qualification applications receive stable separate installation identities; Android qualification uses Release compilation with debug signing and macOS uses development signing with sandbox entitlements. A source revision match and essential packaging assertions establish admissibility, not literal binary equivalence. Exact distributable smoke coverage is separately mandatory.
2. Fresh qualification-app data is the default, but explicitly authorized no-reset sessions are permitted. Only qualification-app private data is reset; secure credential namespaces and session-owned external fixtures have separate lifecycle contracts. The ordinary installed application's data is never auto-cleared.
3. Format coverage derives from the production capability catalog, includes a genuine validated positive fixture for each mandatory advertised format, and is distinct from targeted physical platform/representation cases plus wider Rust contract coverage. Owner-provided ROMs are read-only and verified before staging.
4. Simulated, reversible source-path and qualification-app permission loss constitute the approved mandatory source-unavailability test. They must be called simulations in evidence. The old physical-media-removal acceptance wording must be superseded prospectively without altering historical observations.
5. No general before/after application-record preservation check is required for the ordinary app's data-preserving installation. Specific negative or recovery scenarios may check observable records when their own approved oracle requires it; no silent assertion of preserved historical jobs follows from package-manager success alone.
6. Older evidence remains archived but is not automatically eligible in a new current-schema assessment. Previously accepted historical owner observations are still historical facts; changed binaries require fresh qualification, and a present-day whole-release gate cannot silently treat incompatible old machine evidence as current.
7. Unsupported environmental configurations may be excluded only under the prior approved capability matrix, and at least one required exercisable configuration must actually pass for the scenario. A missing mandatory positive fixture or actual supported configuration remains a blocker.
8. A fail-fast execution stops on unanticipated product failure or unresolved prerequisite. Prerequisite repair is restricted to a bounded, separately tracked preparation stage; a changed binary or acceptance rule cannot be swapped in during execution. Cleanup and append-only evidence continue after failure.
9. The driver allowlist is a governance and test enforcement boundary, not hard isolation against a trusted Codex host operator. Device identity and package identity are rechecked; cross-process concurrent interference has no lock and is detected only where observable.
10. Governed technical specifications, active source and test plans remain free of planning-stage terminology. Historical execution records stay factually intact within planning/archive material, while current plans and scripts are migrated to neutral names.

## Owner approval gate

The 126 design answers establish consensus for drafting, not authorization to commit code, publish a PR, install APKs, reset app data, change device settings, or begin physical execution. Approve the consolidated architecture/specification and subsequent bounded implementation work separately. Physical sessions require their own exact owner-approved authorization manifests.
<!-- END APPROVED SOURCE design-decisions.md SHA-256 ab198ecf0fde7b357a7cd0a81dce1ec50cc7ec86c802259df1d38d6dd3a054cf -->

## Prospective Q100 clarification

**Provenance:** Issue #25, approved for the durable evidence implementation. The approved source block above remains byte-for-byte identical to archive member `design-decisions.md` (SHA-256 `ab198ecf0fde7b357a7cd0a81dce1ec50cc7ec86c802259df1d38d6dd3a054cf`). This section records a prospective interpretation and is not part of that archived source.

- `NOT_RUN` is a fourth explicit owner verdict. It records that the owner did not run the required observation. It is distinct from an absent verdict, an objective failure, and `BLOCKED`. This clarification adds a supported outcome without changing the historical Q100A decision or any retained record.
