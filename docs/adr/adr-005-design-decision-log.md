# ADR-005 decision log (working draft)

**Status:** Owner design choices Q1-Q36 confirmed by Q37 (2026-11-14); architecture and contract changes pending independent review and essential physical feasibility; ADR-005 remains Draft.
**Source:** Owner's answers in the ADR-005 Grill with Docs session, 2026-11-13 through 2026-11-14.
**Repository companion:** [ADR-005](adr-005-physical-product-observation-boundary.md). This document preserves the full rationale and is not itself an active qualification contract.
**Implementation authority:** None. Publication of this documentation does not amend the pinned qualification contract, capability, oracle, artifact, or permissions for device access.

## Governing threat model

Scope focuses on code correctness, race conditions, inconsistent state, partial or stale observations, lifecycle side effects, and accidental effects. The owner-controlled qualification host and authorized ADB connection are trusted. Deliberately malicious hosts, intentional interference by other apps, and adversarial credential attacks are not design drivers. Retain proportionate access restrictions, data minimization, bounded reads, and fail-closed behavior for correctness/privacy. Do not add PKI, key rotation, and cryptographic replay/revocation systems without a newly approved threat.

## Accepted decisions, rationale, alternatives, and invariants

### Q1 - Observer independence (approved: revised A)

Decision: Rust remains the authority for product-owned Jobs, ScanRun, and Library state. The observer must read actual product facts with verifiable source/session provenance, independently of Flutter presentation and host accessibility parsing. Compare UI projections with typed backend facts and evaluate product outcomes against independently specified fixture expectations. Android OS-owned facts require a separate OS evidence source.

Rationale: A second backend implementation is unnecessary for qualification and introduces its own consistency and maintenance burden. Distinguish observation authenticity from correctness relative to the oracle.

Rejected: independent duplicate backend/source of truth, as disproportionate and potentially inconsistent; accessibility-only observation, because it cannot prove full history or membership. Limitation: two adapters using the same backend do not independently prove that backend's correctness, and must not be represented as doing so.

### Q2 - Jobs history scope (approved: A)

Decision: Complete history for Issue #28 means all retained `LibraryRefresh` JobRuns in the isolated qualification installation, including prior runs, active and terminal runs, and relevant Retry source/successor relationships.

Rationale: The no-reset baseline requires visibility into preexisting refresh history. All operation types exceed the needed scope; current-session-only history cannot verify a preexisting baseline.

Rejected: all Job types (excessive scope), current-session-only Jobs (incomplete baseline). Invariant: declare retention boundary; never label partial or merely recent history complete.

### Q3 - Lifecycle non-interference (approved: A, with Q5 clarification)

Decision: Observation alone may not cold-start Argus, create a Flutter route controller, navigate, initiate Jobs, or change task/foreground state. Read-only backend queries under Q5 may execute against an *already running* app without creating or replacing the UI's query/controller. OS-only observations may execute while the app is stopped if separately authorized.

Rationale: Starting or navigating the subject while observing its lifecycle contaminates the evidence. Distinguish observer reads from explicitly authorized qualification actions that legitimately launch/stop/interact with the app.

Rejected: unrestricted observer-driven startup; conditional startup during evidence windows. Invariant: process-loss, foreground, and task-continuity assertions must have separate OS evidence and must not be altered by the observer.

### Q4 - Host and session trust (approved: A)

Decision: Trust owner-controlled host and authorized ADB connection. Reuse existing host-side owner/session authorization for target, operation, arguments, deadlines, and evidence handling. Prefer proportionate local access controls and a closed read-only operation allowlist rather than Android-verifiable signed-session credentials or PKI.

Rationale: Strong cryptographic authentication and key lifecycle would solve an attacker model that the owner explicitly excludes; the relevant risks are accidental misuse and software bugs.

Rejected: device-side PKI, signed credentials, elaborate revocation/replay protections as default; unaudited unrestricted product access. Invariant: enforce least privilege, size bounds, no unauthorized operations, clear wrong-target failures, and no deliberate lifecycle effects. ADB trust alone does not prove which installed APK is running; preserve independent package/signer/digest proof.

### Q5 - Product Library membership evidence (approved: A)

Decision: An observer may initiate a distinct, read-only RevisionFenced backend enumeration while the app is already running, independently of the visible Flutter controller. Prove the authorized All-active query shape, every page/cursor linkage, unique complete GameId set, terminal page, and direct same-token `GetGame` redirect results. Treat this as backend-state evidence and cross-check visible UI behavior separately.

Rationale: Avoid coupling qualification to route-scoped auto-disposed controller lifetime and virtualized accessibility. A new backend read does not pretend to be the UI's original query.

Rejected: binding qualification to the exact UI controller page chain (unnecessary coupling and potential unavailable state); UI-only membership proof (blocked by virtualization). Invariant: do not join chains across token, query shape, revision, or process restart. Keep token/cursor values private. Existing C5 single-capture requirements remain binding for UI assertions until explicitly revised; backend evidence cannot silently be relabeled C5 UI evidence.

### Q6 - Complete Jobs history implementation (approved: A)

Decision: Investigate a single bounded coherent database transaction/snapshot read returning all retained `LibraryRefresh` runs and required identities/Retry relations. If an explicitly supported resource bound is exceeded or the result cannot be obtained coherently, return BLOCKED.

Rationale: Smaller implementation and proof burden than revision-fenced Jobs keyset pagination, provided measured retained history fits a bounded read.

Rejected: new persistent history revision/keyset mechanism without demonstrated scale need; offset-paged recent jobs (not a completeness proof). Invariant: no truncation relabeled complete; stable snapshot and explicit retention boundary required. Escalate to a separately reviewed pagination contract if measured scale demands it.

### Q7 - Permitted Android OS observation (approved: A)

Decision: Permit specifically authorized, read-only Android diagnostics when a narrow OS API does not expose a required task/process fact. Underlying output may be broader, but filter locally and immediately; discard all unrelated data, retain only sanitized target-package-scoped facts and provenance. Do not retain raw dumps, screenshots, unrelated app state, device identifiers, or personal data.

Rationale: OS task-continuity proof may not be feasible using a strictly package-only diagnostic. A bounded and transient local filter balances feasibility with privacy.

Rejected: only inherently package-scoped OS APIs (could leave otherwise observable facts blocked), unrestricted diagnostics and raw retention (unnecessary exposure). Invariant: per-command allowlist and session authorization, no effects, sensitive-output handling, and fail-closed absence/ambiguity. This relaxes previous exclusion of broad activity/stack dumps only for a narrowly reviewed ephemeral parsing path; current contract cannot be silently broadened.

### Q8 - Android host-to-product transport (approved: A)

Decision: Investigate an application-owned Unix-domain socket (`localabstract`) reached from the trusted host using ADB forwarding. The listener exists only in the already-running application process. It must not be an exported Android `ContentProvider`, launch the app, retain a background process solely to serve the observer, or create a Flutter route controller. Select this as the first transport to qualify, not as proven feasible on the target.

Rationale: The Android-local, process-scoped socket avoids the provider cold-start mechanism and permits typed read-only queries without adding an installed helper package or a separate product backend. It is aligned with Q3 (non-interference), Q4 (trusted host), and Q5 (backend-owned read). A missing socket while the app is stopped is a truthful unavailable observation, not a reason to start the product. ADB forwarding is a proposed access path; transport visibility and device/runtime constraints must be verified before implementation.

Rejected: exporting a `ContentProvider` as the default, because a request can cause process initialization and complicates scoped access even without malicious callers; refusing any product observation transport, because it preserves the known membership/identity blockers. Invariant: no device/ADB action or production change authorized yet; constrain who can reach the socket through proportionate access controls, do not presume ADB forwarding alone makes it shell-exclusive, and fail closed on unavailability, ambiguous process incarnation, or unsupported requests.

### Q9 - Observer distribution and activation (approved: A)

Decision: Reuse one read-only observer implementation in the isolated qualification Release and normal distributable Release. It is inactive by default and becomes active only through explicit owner-controlled diagnostics enablement performed outside lifecycle measurement windows, before establishing the qualification baseline. The exact enablement mechanism, restart persistence, and permissions are not yet selected.

Rationale: Sharing implementation supports product-path equivalence and avoids qualification-only business logic. Default-off activation limits unnecessary exposure and background resource use. Enabling it before the baseline keeps observer activation from contaminating the lifecycle measurements.

Rejected: always-active listener, because it needlessly expands data exposure and runtime activity; qualification-only observer implementation, because it diverges from the selected normal-product-flow direction and may hide behavior differences. Invariant: same source-level observer behavior does not by itself establish binary equivalence; qualification and distributable artifacts retain separate identities/verification under ADR-001. Enabling diagnostics must not create a new session authorization or permit an unauthorized device operation. Product code/manifest changes require review and exact artifact repinning.

### Q10 - Backend membership and C5 UI evidence (approved: A)

Decision: Use the separate, complete, authenticated-to-the-trusted-host RevisionFenced backend query (Q5/Q8) as proof of committed Library membership and required direct, same-view redirects. Use C5 accessibility observations only for what the UI physically presents and for presentation-specific assertions. Modify the evidence/oracle contract explicitly to distinguish these sources; never relabel a backend query as an original Flutter controller query or as a complete UI hierarchy capture.

Rationale: Lazy Flutter builders may omit offscreen rows and page boundaries, so requiring all committed GameIds in one accessibility capture can make correct product state impossible to qualify. Backend membership proof is naturally complete under SPEC-BE-015 §21, while separate UI checks still catch presentation defects. The split avoids multi-capture stitching and controller-lifetime instrumentation.

Rejected: retaining one-complete-capture as the only membership proof, because virtualization can make that impossible; implementing multi-capture stitching and cursor/process cross-correlation by default, because it adds synchronization/provenance machinery without a demonstrated need. Invariant: the existing C5 single-capture rule remains binding for existing UI-assertion inputs until a separately approved specification, schema/oracle, and test revision; backend evidence cannot silently turn currently BLOCKED physical assertions into PASS. A UI view showing an identified wrong item must remain a UI failure even if the backend set is correct. Complete backend data does not prove every card was rendered.

### Q11 - Android task and process continuity (approved: A)

Decision: Require Android OS-backed process, foreground, and task-identity observations at the relevant before/after checkpoints, with corroborating visible-UI observations. Permit tightly scoped local, transient processing of wider OS diagnostics under Q7 when unavoidable. Identify which OS facts are actually available and stable on the selected Android target; if a required fact cannot be independently observed, that assertion remains BLOCKED.

Rationale: Product-reported lifecycle text cannot independently establish whether Android preserved the existing task or whether a process was lost/recreated. OS observations provide the appropriate source of truth for those claims, while UI observations determine what the user actually sees. Proportionate, narrowly retained diagnostics avoid building another monitoring service.

Rejected: app-reported events alone, because they can be emitted from a new process or fresh task and do not establish Android task continuity; removing task-continuity acceptance, because it weakens the original physical lifecycle qualification. Invariant: process presence is not proof of foreground status or retained task identity; PIDs and other potentially reused identifiers alone may be insufficient; ambiguity, missing source, or observer-induced task changes stay BLOCKED. No Android or ADB execution is granted by this decision.

### Q12 - Diagnostics activation lifetime (approved: A)

Decision: Maintain explicit, persistent, application-owned diagnostics enablement that is OFF by default and survives normal process termination and relaunch. Activate it under separately authorized preparation *before* recording the no-reset/lifecycle baseline; subsequently, a listener is available only when the app process is already running and ready. Authorized cleanup disables diagnostics and verifies that the setting is off. Persistent enablement is a configuration preference, not permission to cold-start or keep alive the app.

Rationale: AND-05 deliberately terminates and relaunches the process. Re-enabling the observer during recovery would contaminate the measured lifecycle and make evidence unreliable. A persistent default-off setting permits repeatable pre/post-loss observation without adding an always-running service.

Rejected: process-local enablement (requires reactivation after force-stop); per-connection UI activation (would interfere with the measurement and may force navigation). Invariants: no listener solely keeps the app process alive; denied or unavailable observations must never relaunch it; diagnostics remains subject to the trusted-host session authorization and explicit setup/cleanup evidence. The mechanism to change the persistent setting, its readiness signal, and cleanup verification remain for subsequent decisions.

### Q13 - Read-only socket protocol (approved: A)

Decision: Design a small, versioned, typed, closed-set protocol exposing only runtime/readiness state, authoritative Job detail, coherent complete retained LibraryRefresh history, complete RevisionFenced Library membership, and directly bound redirect evidence required by qualification. Each operation has bounded arguments and output, typed outcomes, and fixed source/provenance semantics. This protocol does not expose generic Rust/Flutter bridge calls, arbitrary SQL, arbitrary filesystem reads, mutation commands, or unrestricted diagnostics.

Rationale: A tailored protocol is easy to review, test, and attribute. It reuses existing product queries without exposing a general-purpose administrative gateway whose surface would be larger and harder to bound for accidental misuse and failures.

Rejected: a generic allowlisted bridge-method proxy (more coupling and a larger evolving surface); arbitrary backend introspection (unnecessary data access). Invariants: unknown commands, unsupported versions, invalid/oversized arguments, and ambiguous results fail closed without product facts or effects; session approval and artifact/target identity remain host-enforced under Q4. The exact method names, binary/wire framing, limits, and error-code schema require later reviewed design and tests.

### Q14 - Library enumeration execution boundary (approved: A)

Decision: The in-app observer performs the entire authorized RevisionFenced backend first-to-terminal page chain and all required *direct* same-view redirect lookups. It proves query shape, stable generation/revision/token, predecessor cursor linkage, fixed page size, complete unique GameId membership, terminal completion, and direct canonical redirect target membership. Return minimal structured and sanitized evidence/provenance; never export raw view tokens or cursors or ask the host to manage them. The observation remains independent of and does not replace the existing Flutter route controller's query.

Rationale: One application-side operation reduces cross-process orchestration, token exposure, and controller coupling, while permitting the existing Rust backend to enforce its revision fences. It is lighter than new snapshots and easier to invalidate atomically on a read failure.

Rejected: host-driven per-page paging (cross-process cursor lifetime/replay complexity); separate materialized observation snapshot (duplicates already accepted RevisionFenced machinery and retention policy). Invariants: never combine results from different token, revision, query, process incarnation, or observation attempt; do not infer redirect continuity from a UI detail screen or follow multiple redirect hops. A coherent successful enumeration does not by itself prove what the UI rendered.

### Q15 - Library mutation/race failure handling (approved: A)

Decision: If Library membership changes and invalidates the RevisionFenced query during an observation, the whole attempt is invalid and returns BLOCKED, with its failed/partial attempt evidence preserved append-only. Do not quietly retry and report only a later success. A new, explicitly attributable attempt may begin from page one under its own authorization/provenance, never as a continuation or repair of the prior chain.

Rationale: Hidden restarts could mask timing and recovery bugs or produce a composite result unrelated to the initial state. Explicit failures make race conditions diagnosable and prevent false complete-membership claims.

Rejected: automatic restart until successful with only final attempt reported (conceals invalidated evidence); stitching remaining pages from newer revision (violates the same-view contract). Invariants: a stale/invalid token, cursor gap, query change, duplicate/partial page, process restart, or uncertain transport cannot establish membership. Continue using the approved oracle's specific FAILED vs BLOCKED distinctions for conclusive contradictory behavior versus insufficient evidence. A blocked prerequisite never authorizes dependent Retry.

### Q16 - Jobs-history bounds and retention (approved: A)

Decision: Determine a concrete maximum size/resource budget from representative qualification workloads, then return the entire retained LibraryRefresh history and required JobRun/root/ScanRun/Retry relationships as one coherent bounded read. If the required set exceeds the explicit bound, return BLOCKED and preserve evidence of the limit breach. The observer does not introduce deletion, truncation, retention-policy changes, or cleanup of historic Jobs.

Rationale: Bound memory, transaction time, and response size while using the simpler coherent read approved in Q6. An arbitrary newest-N subset would invalidate no-reset baseline completeness and can omit recovery-related failures.

Rejected: unbounded all-history reads (uncontrolled costs and latency); silently returning recent history as complete (false absence/coverage proof). Invariants: a declared retention boundary, atomic coverage, explicit resource cap, typed incomplete/failure result, and no mutation of historical Jobs. Actual numeric bounds and performance evidence are implementation-review inputs, not invented here.

### Q17 - UI/backend evidence correlation (approved: A)

Decision: Represent backend committed-membership/redirect assertions and UI presentation assertions as separate evidence claims with independently identified sources and times. Validate visible UI identities/behavior against permitted backend facts where correlation is established. Assert a shared committed revision only with actual supporting revision/provenance evidence, not merely similar counts or titles. A conclusive UI defect fails the UI assertion; an unresolved timing mismatch or missing correlation is BLOCKED, not an inferred PASS or FAIL.

Rationale: The observer and Flutter UI run at different moments and may see different valid committed revisions. Treating any mismatch as a product error would create false failures; treating the backend as sufficient UI evidence would conceal rendering defects.

Rejected: requiring every UI capture to display the full backend set (impossible under lazy virtualization); treating correct backend membership as an automatic UI PASS (weakens presentation qualification). Invariants: no false equivalence between an observer-generated query and the actual UI request chain; preserve C5's single-capture rule for claims still governed by it until separately revised; do not turn backend proof into rendered-card completeness or task-continuity proof.

### Q18 - Diagnostics activation mechanism (approved: A)

Decision: Expose a visible default-OFF observer enablement toggle in the existing application's Advanced/Diagnostics settings in both release-configured artifact classes. The owner explicitly authorizes enablement as qualification preparation, and the operator enables it before the no-reset/lifecycle baseline. The choice persists under Q12 through process termination and relaunch; shutdown of the listener on process exit is not equivalent to turning the setting off. Owner-authorized cleanup must turn it off and verify the resulting disabled state.

Rationale: This provides a discoverable, maintainable and auditable control without granting the host another remote app-control entry point. It supports recovery qualification without toggling the setting mid-scenario. It does not grant Android/ADB or UI navigation authority in this discussion.

Rejected: an ADB-facing activation command (new Android surface and possibility of unintended activation or cold start); a hidden gesture/menu (fragile, hard to audit and discover). Invariants/failure modes: no observer-initiated launch, foreground transition, or route creation; a setting that fails to persist, cannot be disabled, or cannot be verified at cleanup leaves the affected preparation/cleanup gate BLOCKED. If Argus is unavailable after a failure, do not claim successful cleanup merely because its socket is absent. Explicit owner authority is needed for each effectful preparation/cleanup operation.

### Q19 - Observer availability while backgrounded (approved: A)

Decision: Allow the in-app listener to serve typed read-only requests while the existing Argus application process and authoritative backend runtime are alive, even with no attached Activity or visible Library route. It must not initialize an unavailable engine/backend, launch the app, create a Flutter controller, or independently keep the process alive. Socket absence or backend unavailability is a typed unavailable/BLOCKED observation, not permission to launch or recreate state.

Rationale: AND-04 explicitly tests foreground/background behavior; restricting observation to a foreground Activity would defeat those checkpoints. A dedicated keep-alive service would distort process behavior under test.

Rejected: foreground-only observation (cannot support background proof); dedicated always-on service (changes lifecycle and resource behavior). Invariants/failure modes: an Activity detachment is not evidence of process death; a missing/transitioning backend cannot be treated as a valid empty state; process-loss and foreground claims remain OS sourced under Q11/Q21. Observer activity must not create an artificial liveness guarantee.

### Q20 - Process identity via Android PID only (approved: B; deliberately narrower than recommended A)

Decision: Do **not** add an application-generated per-process incarnation identifier. Use OS-observed Android PID as the sole process identity value for this observer design. Keep the existing scenario timeline and authorized stop/launch observations to delimit known process interruptions; those observations are evidence checkpoints, not a new incarnation ID.

Rationale: The owner explicitly chose the simpler PID-only model, consistent with prioritizing correctness and ordinary race conditions over elaborate identity mechanisms. A separate app runtime nonce would add new state and contract complexity. This choice accepts that the available evidence may be weaker in certain PID-reuse cases.

Rejected: A, generating and correlating a fresh app process-incarnation ID (additional implementation and protocol surface not justified by the owner); C, omitting process identity entirely (would remove basic OS correlation). **Important limitation:** Android PIDs are reusable. Equal PID values before and after an unobserved process-loss interval do **not** prove process continuity. Known force-stop/launch steps are a discontinuity even if a numerical PID is reused; a broken socket/partial Library chain cannot be stitched across a restart. If PID reuse or missing checkpoints makes continuity uncertain, mark the specific continuity assertion BLOCKED, never PASS based on PID equality alone. The choice does not weaken Q15's uninterrupted single-attempt RevisionFenced proof or Q11's independent OS source requirement.

### Q21 - Android lifecycle evidence sampling (approved: A)

Decision: Sample allowlisted, read-only Android OS facts at the specifically authorized qualification checkpoints rather than installing a persistent monitoring agent. Use Q7's transient local filtering for OS outputs that include unrelated data; retain only sanitized, package-scoped process, foreground and task facts with source, timing and authorized-session provenance. Coordinate with AND-04's background/return operations and AND-05's force-stop/relaunch operations. Any required fact unavailable through a qualified source remains BLOCKED.

Rationale: Checkpoint observations meet the physical evidence need without introducing a service that itself affects task/process lifetimes. Application logs and lifecycle callbacks are useful diagnostics but cannot independently establish Android process and task facts.

Rejected: continuous on-device lifecycle monitoring service (additional component that may perturb behavior and need its own qualification); relying only on app events/logs (wrong authority for OS facts). Invariants/failure modes: approved, package-scoped acquisition with no unauthorized mutations; timestamp/correlation and privacy controls; do not conflate process presence, foreground package or task continuity; unknown/ambiguous OS output remains BLOCKED; no device actions authorized by this decision.

### Q22 - Canonical meanings of physical gates G3/G4/G5 (approved: A; new proposed canonical crosswalk)

Decision: Adopt the owner's definitions for future reviewed specifications: **G3 = physical admission and baseline readiness**, requiring the approved target, installed qualification package/artifact/signing identity, observer readiness, and fixture-only/no-reset preflight; **G4 = Android background/foreground lifecycle qualification**, grounded in AND-04's exact existing 31 operations; **G5 = Android process-loss and explicit recovery qualification**, grounded in AND-05's exact existing 45 operations, including committed-state integrity and source-bound Retry. Each gate still requires its own authorized evidence and owner assessment under applicable rules.

Rationale: The prior ADR explicitly said that canonical meanings were undefined. An admission -> foreground/background -> interruption/recovery sequence is intelligible and maps to the frozen scenario boundaries without inventing additional operations. This decision defines future terminology; it does not assert these were historically canonical or that any gate passed.

Rejected: retaining undefined gates pending a separate definition task (keeps acceptance crosswalk ambiguous); defining gates by evidence-source type (mixes OS and product facts and obscures scenario progress). Invariants/failure modes: do not rename, add, remove, reorder or grant the 31/45 authorized operations by this decision; reconstruct the exact PAC/TAC evidence crosswalk and owner verdict rules under a reviewed contract revision; G3/G4/G5 remain BLOCKED/NOT_RUN until physically qualified as applicable. Latency oracle/calibration and separate device/session authorization remain independent prerequisites and are not silently waived.

### Q23 - Observer request concurrency (approved: A)

Decision: Allow at most one in-flight observer request per running app process. A concurrent second request returns a typed `Busy` response with no partial product facts, and no queued hidden execution. This restriction applies to the diagnostic socket, not ordinary UI or background Job work. Backend concurrent mutations can still invalidate an in-flight observer read according to Q15.

Rationale: Serial request execution produces unambiguous provenance with a small, testable protocol and matches the existing serial qualification plan. Parallelism would add synchronization/cancellation complexity with no demonstrated qualification benefit.

Rejected: bounded multi-request concurrency (unneeded complexity until a concrete need arises); unrestricted observer concurrency (resource pressure, harder race interpretation). Invariants/failure modes: the observer must not hold a global lock that blocks normal product Jobs/UI, or continue unboundedly after host disconnect; timeouts, process shutdown, and `Busy` fail safely without producing complete evidence or authorizing a new Job/Retry. Host mapping of `Busy` to BLOCKED rather than product FAILED requires a reviewed evidence contract.

### Q24 - Socket peer access and trusted host (approved: A)

Decision: On each application-owned Unix-domain socket connection, verify the peer's Android UID against a narrowly approved set established by a **target-specific feasibility test**. Use this proportionate local access restriction alongside the owner-controlled ADB host and host-side session authorization accepted in Q4. If the actual forwarded peer, its UID, or the target's connection semantics cannot be established, deny that connection without disclosing product facts. ADB forwarding, socket naming, or a diagnostics enablement toggle alone is not proof of peer identity.

Rationale: A peer-UID check provides a small, reviewable defense against accidental access by unintended local callers without introducing PKI, device-side signed session credentials, key rotation, or attacker-focused replay machinery. Which UID appears over the proposed ADB forwarding path is a feasibility question, not an assumption that it will be the shell UID or any other specific UID.

Rejected: relying only on an enabled flag, socket name, and trusted environment (no peer binding and possible accidental access); cryptographic per-client authentication (disproportionate for the approved non-adversarial threat model). Invariants/failure modes: verify target OS behavior before pinning a UID allowlist; reject unknown/unexpected UID, unexpected package/artifact, unavailable socket, or malformed request without product data; do not cold-start Argus or retry via an unapproved transport. A necessary access-design change after a NO-GO requires an explicit reviewed architecture decision.

### Q25 - Private identifiers across the observation boundary (approved: A)

Decision: Permit the trusted, owner-private observation channel to carry exact typed `GameId`, `JobRunId`, `ScanRunId`, and `LibraryRootId` identities and their direct relationships, to support the approved product-state comparisons. Keep identifiers and any other sensitive source material out of shared logs and reports. Shared append-only evidence contains only permitted sanitized aliases, digests, categorical assertion outcomes, and bounded provenance; never export raw Library view tokens/cursors or personal root paths through the observer.

Rationale: Counts and digests alone cannot establish exact per-root ScanRun attribution, source/successor Retry links, or missing-ID redirect continuity. Confidentiality is better enforced at the owner-private-to-shared evidence boundary than by discarding the identities before authorized comparisons can occur.

Rejected: transmitting only aggregated counts/digests (insufficient for exact identity assertions); publishing full raw responses in shared qualification evidence (unnecessary privacy exposure). Invariants/failure modes: data minimization and response size bounds apply even on the trusted channel; avoid raw XML/screenshots, serial numbers, ROM names, file paths, credentials, and private database dumps in shared records. Unredacted or misattributed data is an evidence/privacy failure, not a reason to weaken identity verification. Exact retention and redaction tests remain part of contract implementation review.

### Q26 - Same-task continuity (approved: A)

Decision: For AND-04 background-and-return qualification, require separately sourced Android OS evidence that the intended task identity persists across the controlled background/return operation, along with the expected foreground package and corresponding visible UI surface. Treat Android PID as a separate process observation under Q20. Use only a proven, permitted task-identity source; if the selected target cannot supply one, the affected task-continuity assertion is BLOCKED.

Rationale: Foreground-package equality or a screen that looks familiar could result from a fresh task rather than a return to the existing one. The scenario specifically intends *existing-task* continuity, so task identity is required. At the same time, task and process identity answer different questions and must not be substituted for one another.

Rejected: relying on foreground package plus matching UI alone (does not demonstrate task identity); relying on UI navigation alone (could hide a fresh launch/task). Invariants/failure modes: do not infer continuity from PID equality, app success text, or task identifiers observed only at one endpoint; establish before/after correspondence with the reviewed OS source, and classify unavailable/ambiguous task identity as BLOCKED. The semantics of task identity after AND-05's intentional force-stop/explicit relaunch remain a separate downstream decision.

### Q27 - Diagnostics cleanup failure (approved: A)

Decision: If diagnostics cannot be disabled and independently verified during authorized cleanup (including when Argus cannot relaunch), record cleanup as incomplete or BLOCKED, retain the owner-private and sanitized evidence, and require *separately authorized remediation*. Do not silently reset app data, assume a stopped process implies disabled configuration, or claim restoration based on an absent listening socket.

Rationale: Persistent enablement under Q12 survives process death. Without verified disablement, an otherwise complete scenario may leave a modified diagnostic state. The no-reset owner-data policy makes implicit reset unacceptable.

Rejected: automatic clearing/resetting application data (unapproved destructive effect); treating socket absence as sufficient evidence of disabled persisted state (false cleanup claim). Invariants/failure modes: retain original authorized preparation and cleanup boundaries, report partial restoration truthfully, and do not attempt an unapproved launch, UI navigation, permission change, or device reset merely to make cleanup appear complete. The exact owner-directed recovery path is conditional on device condition and requires explicit permission.

### Q28 - Qualification-contract migration sequence (approved: A)

Decision: Use a **contract-first, versioned, independently reviewed sequence**. Define and approve the ADR/specification changes, evidence-source rules, host data contracts and oracle assertions, and G3/G4/G5 crosswalk before implementing the production-side socket observer. Then implement product observer, host adapter, and physical qualification as independently reviewable slices, with new exact artifact and affected rule/schema/oracle pins. Preserve prior immutable execution evidence and owner decisions with their historical versions.

Rationale: Q10's separation of backend-state and UI evidence changes what can satisfy an assertion; Q7 alters permissible OS observation inputs; Q22 makes new canonical gate definitions. Implementation must not accidentally redefine a frozen qualification oracle after the fact. Review isolation allows each correctness boundary to be evaluated on its own merits.

Rejected: implementing first and changing specs to fit later (risks post hoc acceptance definitions); reinterpreting the existing pinned v5/v4/v9 contract without version change (breaks evidentiary meaning and provenance). Invariants/failure modes: contract v5, capability v4, oracle v9 and AND-04/AND-05 counts 31/45 remain frozen until individually reviewed/authorized revisions; no silent retroactive reinterpretation, waiver, rewriting of historical records, device action, or physical session grant. ADR-005 itself remains Draft until architectural approval under its governing lifecycle.

### Q29 - Observer state and latency qualification (approved: A)

Decision: Use the **same actual diagnostics enablement state** and representative workload for owner-approved latency baseline calibration and the relevant physical qualification execution. Where material, separately characterize observer overhead. Numerical latency ceilings, warmup/sample rules, timeouts, oracle versions, and rule digests remain under explicit owner approval; this decision creates no new performance criterion and opens no latency execution gate.

Rationale: Calibrating with diagnostics off and qualifying with diagnostics on introduces an uncontrolled change in the measurement environment. Ignoring observer overhead would overstate comparability. A pinned state makes measurements reproducible and interpretable without designing elaborate performance instrumentation.

Rejected: off-state calibration followed by on-state qualification (non-equivalent conditions); excluding observer overhead without measuring it (unsupported performance claim). Invariants/failure modes: record enablement and representative workload in the approved provenance, do not confuse operation timeouts with p95 acceptance ceilings, and keep the pending malformed-latency-evidence oracle correction and owner-pinned calibration as separate prerequisites. If state/workload differs or is unverified, do not treat the latency evidence as an equivalent PASS.

### Q30 - AND-05 task identity after force-stop (approved: A)

Decision: Preserve the distinct lifecycle requirements. AND-04 requires the same Android task when backgrounding and returning to the existing task (Q26). AND-05 intentionally force-stops the application and relaunches it, so it does **not** require the pre-stop task identity to survive that explicit process-loss boundary. Instead, independently establish process loss, an authorized relaunch, the expected foreground application, and correct durable product recovery and Retry identity.

Rationale: Android task identity and process identity are different facts; an intentional force-stop/relaunch is not the same operation as returning to a backgrounded existing task. Requiring the old task to survive force-stop would add an unrelated, potentially platform-specific condition and obscure the actual recovery guarantee. This does not waive task identity for AND-04.

Rejected: demanding the original task identity across AND-05 force-stop/relaunch (overconstrains recovery with unrelated task semantics); removing task observations from both scenarios (would weaken AND-04). Invariants/failure modes: no inferred continuity from equal PID across unobserved intervals (Q20), matching UI screen, or package name; independently observe process loss and subsequent target package, then separately verify committed Job/Library state. Missing or ambiguous OS evidence is BLOCKED, not PASSED. Preserve the frozen AND-04/AND-05 operation sequence and distinct owner authorizations.

### Q31 - Observer failure and product defect classification (approved: A)

Decision: Preserve the existing fail-closed result semantics. Record a conclusively wrong artifact or product behavior (including wrong verified identity or demonstrated committed-state loss) as `FAILED`. Record unavailable, stale, timed-out, `Busy`, incomplete, unauthorized/unverifiable peer, or otherwise ambiguous observer evidence as `BLOCKED`. Dependent operations not executed because a prerequisite blocked are `NOT_RUN`. Record `PASSED` only when the specific behavior is correct and its required evidence is complete.

Rationale: Infrastructure or observer uncertainty is not itself proof of a product defect; conversely, a conclusive negative product observation must not be hidden as mere observer uncertainty. Keeping these classifications distinct makes qualification truthful and recoverable.

Rejected: treating every observer/transport error as product FAILED (false product failures); treating all inconsistencies as BLOCKED (could hide proven product defects). Invariants/failure modes: classify based on the actual assertion and evidence, not the appearance of an error string. A failed authorization or wrong target with no trustworthy product identity is not promoted to a product failure without a conclusive artifact observation. Invalid or incomplete prerequisites never authorize Retry or other dependent effects. Any new response-to-outcome mapping requires reviewed contract and oracle tests under Q28; no change to existing evidence outcomes is silently authorized.

### Q32 - Canonical physical-gate assertion crosswalk (approved: A)

Decision: Prepare an **assertion-level** crosswalk of the frozen AND-04 (31 operations), AND-05 (45 operations), and Issue #28 requirements into the newly approved G3/G4/G5 definitions (Q22). For each applicable operation/claim, define expected behavior, evidence source and provenance, prerequisite assertions, resulting classifications, and the relevant acceptance criteria. Preserve real historical PAC/TAC identifiers only when grounded in the authoritative sources; do not invent a mapping or identifiers to fill gaps.

Rationale: Gate-level titles and operation ranges are insufficient for repeatable qualification or independent review. The assertion map makes unsupported sources and dependency propagation explicit without increasing the number of physical operations.

Rejected: range-only gate coverage (insufficient granularity); gate-level completion descriptions alone (leaves evidence and failure handling implicit). Invariants/failure modes: crosswalk creation is a reviewed contract/documentation task, not authorization to execute operations, waive assertions, rename gates retrospectively, or add/reorder the frozen 31/45 operations. Keep G3 admission distinct from G4 and G5; all physical claims remain BLOCKED/NOT_RUN until appropriately qualified.

### Q33 - Response to a NO-GO feasibility finding (approved: A)

Decision: If a specific mechanism fails target-device feasibility (for example, task-identity evidence, forwarded socket accessibility, or peer UID verification), record an explicit NO-GO with supporting evidence, stop that affected path, and pursue a revised mechanism only through independent architecture and authorization review. Continue unrelated investigations whose prerequisites remain satisfied. Do not quietly substitute a weaker source or downgrade qualification requirements.

Rationale: A mechanism-specific failure does not establish that the entire architecture is impossible, but it is not authority to change the chosen mechanism or oracle. Focused NO-GO records preserve the basis for subsequent design decisions.

Rejected: stopping all design work at the first infeasible mechanism (unnecessary coupling); automatically adopting any available substitute despite lower proof quality (unreviewed weakening). Invariants/failure modes: previously approved fallback is to leave unsupported assertions BLOCKED and dependent operations NOT_RUN. Any alternative may require revised ADR/specification, scoped permissions, artifact pins, and explicit owner authorization. Do not convert a NO-GO finding into a passing claim or device-operation grant.

### Q34 - Disconnects, timeouts, and atomic observer results (approved: A)

Decision: Treat each observer operation as **all-or-nothing** for qualification evidence. If its connection closes, times out, or loses coherence before the complete result, publish no partial or cached product facts as complete; retain a bounded sanitized failure receipt. Cancel outstanding work safely when supported, avoid unbounded continued resource use, and treat any later request as a separately identified observation attempt rather than a transparent continuation or replay.

Rationale: Partial enumeration or history is not a complete membership/history result; implicit reconnect/retry would erase important evidence about failed attempts and could join observations across different revisions or process lifetimes.

Rejected: accepting an incomplete partial response for sufficiency evaluation (cannot prove completeness under the selected contract); automatically reconnecting, resuming, or repeating without reporting the interruption (hides the failed observation and may cross revisions). Invariants/failure modes: no application mutation, startup, or additional Job/Retry due to observer recovery. A DB transaction must be released after cancellation/error; if cancellation cannot safely interrupt work, bound its duration and resource use. Map an ambiguous incomplete attempt to BLOCKED, dependent effects to NOT_RUN, and preserve the failure attempt's provenance. Q15 revision invalidation and Q23 single-request policy remain binding.

### Q35 - Default-off observer in distributable smoke (approved: A)

Decision: In the separately authorized exact-distributable Release smoke scope, add bounded checks that diagnostics are **disabled by default** and that no observer socket is available while disabled. Do not enable diagnostics or run full lifecycle qualification against the ordinary distributable installation without separate owner authorization. The isolated qualification Release remains the fixture-only target for the functional G3/G4/G5 work.

Rationale: Because Q9 ships the same observer implementation in both Release variants, smoke should verify its inactive default without unnecessarily exposing, resetting, or using ordinary application data. ADR-001 deliberately separates distributable smoke and full fixture-based qualification.

Rejected: duplicating all lifecycle qualification on the ordinary installation (disproportionate and potentially data-affecting); omitting any smoke check of observer default-off behavior (leaves a shipping-state regression untested). Invariants/failure modes: tests must be bounded to the pinned exact distributable artifact and separately approved smoke operations. A disabled listener must not be cold-started to test it; missing proof remains BLOCKED and an independently verified contrary default is FAILED under the reviewed oracle. Shared variant behavior must be evidenced rather than inferred from source equality alone.

### Q36 - Conditions to mark ADR-005 Complete (approved: A)

Decision: Keep ADR-005 Draft until all architectural decisions are reconciled into reviewed versioned contracts and the **essential target-specific feasibility** is demonstrated: observer socket connectivity/access restrictions including peer identity, lifecycle non-interference, and the OS evidence sources needed for relevant process/foreground/task claims. Once these are independently reviewed and approved, the ADR may become Complete even though full AND-04/AND-05 physical qualification, G3/G4/G5 verdicts, and latency acceptance remain outstanding.

Rationale: A finished ADR should describe an implementable, supported architecture rather than an unverified proposal; nevertheless, an architecture decision should not be blocked on execution of every end-to-end product qualification scenario. This separates feasibility evidence and architecture approval from release qualification evidence.

Rejected: declaring Complete on documentation approval alone while essential Android feasibility remains unverified (premature architecture confidence); waiting for complete end-to-end physical qualification before accepting the architectural decision (unnecessary coupling to implementation and release-gate work). Invariants/failure modes: infeasible required mechanisms remain NO-GO and the ADR remains Draft or is revised; review/approval of documentation is not physical session authority, code implementation permission, successful G3/G4/G5 qualification, or release approval. Keep issue trackers open as applicable and preserve exact artifact, contract, and oracle provenance. Any feasibility testing requiring app activation, launch, ADB access, or device mutation needs its own explicit scoped owner permission.

## Existing approved invariants to keep until separately revised

- ADR-005 stays Draft; #28 and #57 physical acceptance remains open as applicable.
- Host qualification contract v5, capability v4, oracle v9, and the frozen AND-04/AND-05 operation counts (31 / 45) remain unchanged until separately reviewed.
- No Android commands or mutation authorized by these design answers; no reset, install, force-stop, app launch, Retry, fixture copy, UI interaction, or physical qualification.
- Incomplete, stale, ambiguous, oversized, or uncertain observations must not become passing evidence; dependent effectful actions stay NOT_RUN.
- A new production API or Android transport requires review and a new exact signed artifact pin. Revision of C5 membership evidence, Jobs history API, OS observer allowlists, contract/schema/oracle behavior requires explicit reviewed updates and repinning as applicable.
- Preserve historical failure records, rationale for rejected alternatives, and the evidence needed to evaluate any future design.
- Q20 permits only PID as the process identity value. Neither PID equality after an unobserved gap nor a reused PID after authorized force-stop proves uninterrupted process lifetime; continuity uncertainty stays BLOCKED.
- Q22 supplies proposed canonical gate names and scenario mapping; no earlier physical acceptance is inferred from that mapping.
- Q24 requires a device-verified peer-UID allowlist for socket access; no fixed UID is yet confirmed. Unexpected/unverifiable peers receive no product facts. The host remains the trusted session authority under Q4.
- Q25 permits owner-private exact typed identities for comparisons, while shared records remain sanitized and never include raw cursors/tokens, raw identities, private paths, or personal device data.
- Q26 requires independent *same-task* evidence for AND-04 background-and-return; PID-only process evidence does not substitute for task continuity. Unavailable task evidence stays BLOCKED.
- Q27 forbids automatic resets or presumed cleanup after process loss. Persisted diagnostics OFF must be separately verified; incomplete cleanup stays visible.
- Q28 requires reviewed versioned contract and oracle revisions before implementation. Approval of these decisions is not approval to edit code, repin an artifact, or access a device.
- Q29 requires matched diagnostics state and representative workload across latency calibration/qualification. Owner-approved latency rules and physical gates remain closed.
- Q30 explicitly limits AND-04 same-task proof to background/return, not across the intentional AND-05 force-stop. AND-05 independently proves process loss, relaunch, foreground, and durable recovery.
- Q31 preserves the distinction between demonstrably incorrect product behavior (FAILED) and unavailable or uncertain observer evidence (BLOCKED), with downstream effects NOT_RUN and PASS only on complete evidence.
- Q32 requires the frozen operation-to-assertion crosswalk with real provenance and no fabricated PAC/TAC identifiers or added operations.
- Q33 makes infeasible mechanisms NO-GO without globally halting independent investigations or silently weakening acceptance requirements.
- Q34 requires all-or-nothing read results and bounded sanitized failure receipts; no hidden retries, partial completeness, or work continuing without resource limits after disconnect.
- Q35 adds separately authorized exact-distributable smoke of diagnostics default OFF/socket absent, never ordinary-app full lifecycle work by implication.
- Q36 allows ADR Complete only after reviewed architectural/contract reconciliation and demonstrated essential physical feasibility, not after documentation alone and not only after full release qualification.


## Reconciliation required in ADR-005

1. Earlier assumption that Android independently verify a cryptographically signed host/session capability is replaced by the trusted-host, proportionate-access threat model (Q4), with a target-qualified socket peer-UID allowlist selected under Q24; the actual forwarded peer UID remains unverified.
2. The no-new-query statement must distinguish forbidden new Flutter UI-controller/query recreation from allowed read-only backend enumeration (Q3/Q5).
3. The existing C5 single-capture UI membership rule is not met by backend membership evidence (Q5). Define exactly which assertions may use typed backend evidence versus which still require UI evidence; do not silently change the oracle.
4. The complete Jobs history requirement is scoped to retained LibraryRefresh (Q2), with a bounded atomic read as the first design (Q6).
5. Previously excluded broad OS diagnostics are only eligible as ephemeral, locally filtered, explicitly authorized observation inputs (Q7). Formal OS operation scope and privacy rules require review.
6. Prefer a process-scoped Unix-domain socket over ADB forwarding as the first read-only product transport to investigate (Q8). A localabstract listener's access restriction, Android compatibility, runtime readiness, and privacy limits remain unproven; the option is not yet an implementation authorization.
7. Include the same observer implementation in both isolated qualification Release and distributable Release, default OFF (Q9), and persist explicit enablement across process termination/relaunch with verified disablement during cleanup (Q12). The exact activation UI/control, readiness signal, and cleanup procedure still need design; variant equivalence remains evidence-based, not assumed.
8. For membership and redirects, revise the explicit evidence contracts to admit authoritative backend RevisionFenced proof while keeping UI presentation evidence separate (Q10). Do not bypass the current frozen C5/oracle pins before reviewed versioned revisions.
9. For process, foreground, and task continuity, require separate, source-qualified Android OS observations plus corroborating UI, with transient local filtering under Q7 (Q11). The actual target-only task evidence API and identity-stability proof remain open; unsupported facts stay BLOCKED.
10. Implement only a versioned, closed-set, read-only typed protocol; do not build a generic bridge, SQL, filesystem, or mutation gateway (Q13). Exact wire framing, method signatures, numeric limits, versioning tests, and platform feasibility remain open.
11. Keep the full Library revision-fenced enumeration and its direct same-token redirect lookups within one application-side observer operation (Q14). Raw cursors/tokens remain inside the app; the observer result is not a capture of the Flutter UI query.
12. A changed revision, stale/invalid cursor, process restart, or incomplete enumeration invalidates and BLOCKS that attempt, which must be preserved rather than silently retried/stitched (Q15). New attempts require independent provenance.
13. Set Jobs-history bounds from measured workloads; no new pruning or retention policy. Return BLOCKED when the full retained LibraryRefresh set cannot be atomically and safely returned (Q16).
14. Maintain separate UI and backend assertions, with explicit correlation evidence when claiming one revision; conclusive UI defects FAIL while timing ambiguity BLOCKS (Q17).
15. Implement persistent default-OFF Advanced/Diagnostics enablement and owner-authorized pre-baseline preparation and verified cleanup (Q18); disablement must not be inferred from app death alone.
16. Preserve background service availability only within an existing live app/runtime process; do not add a keep-alive or reconstruct missing runtime state (Q19).
17. Use Android PID only, rather than a newly generated app process-incarnation ID (Q20). A reused/equal PID cannot establish continuity across an unobserved gap; fail BLOCKED if insufficient proof, and never combine RevisionFenced chains across known process loss.
18. Perform package-scoped OS sampling at the exact qualification checkpoints with transient privacy filtering (Q21); do not install continuous monitoring or use product callbacks as the OS authority.
19. Define G3 as physical admission/baseline, G4 as AND-04 background/foreground qualification (31 operations), and G5 as AND-05 process-loss/recovery qualification (45 operations). This newly accepted definition requires a reviewed canonical gate and PAC/TAC crosswalk; no historical qualification result is inferred (Q22).
20. Serialize observer socket requests; overlapping requests return typed Busy without product data, while ordinary product work continues and can invalidate an observer attempt (Q23).
21. Q24 selects socket peer-UID verification, but the actual target UID/forwarding behavior and permitted UID allowlist have not been proven. No exact socket implementation, numeric bounds, complete OS command allowlist, revised contract, or physical session authorization is approved.
22. Permit exact typed product identities only on the owner-private observation path (Q25); define redaction, shared evidence aliases/digests, and retention tests before introducing live transport.
23. For AND-04, bind original and returned task identity using independent OS evidence and UI confirmation (Q26); never substitute package foreground, PID, or a newly navigated task. Q30 explicitly resolves the AND-05 force-stop boundary: the same pre-stop task identity is not required after the authorized relaunch; process loss and product recovery still require independent proof.
24. When persistent diagnostics cannot be disabled and verified, retain an incomplete/BLOCKED cleanup result and escalate to separately authorized remediation (Q27), rather than resetting app data or interpreting a stopped listener as OFF.
25. Stage reviewed ADR/specification, source/evidence-contract, oracle, and gate crosswalk changes before building transport or physical qualification (Q28). Keep all superseded or incompatible historical evidence attributable to its original rule and artifact pins.
26. Require matched diagnostics enablement and representative workload for latency calibration and qualification (Q29); preserve pending oracle-malformed-evidence correction and owner-approved numerical p95 ceilings as independent prerequisites. No implementation approval is implied.
27. Preserve distinct task/process requirements: same-task proof applies to AND-04's background/return; AND-05 must show actual process loss, authorized relaunch, expected foreground, and durable product state without requiring identical pre-stop/post-relaunch task identity (Q30).
28. Define outcome mapping at each observer/OS/product assertion boundary (Q31): incomplete/ambiguous/BUSY/unverifiable evidence BLOCKED, proven wrong result FAILED, dependent operations NOT_RUN, and complete proven correct results PASSED. Retain the evidence for adjudication under versioned contracts.
29. Produce the exact assertion-level AND-04/AND-05 and G3/G4/G5 PAC/TAC crosswalk from authoritative sources and freeze operation counts (Q32). Do not invent historical criterion identifiers.
30. NO-GO applies to an unproven mechanism (Q33) with review before substituting any alternative; continue only independent unaffected investigation and leave unsupported acceptance BLOCKED.
31. All-or-nothing observer response semantics (Q34) need bounded failure evidence, disconnect/cancellation behavior, provenance distinguishing each attempt, and no partial history/Library set mislabeled complete.
32. Reconcile ADR-001 exact-distributable smoke with diagnostics default-off checks and socket inactivity without broadening ordinary-app operations or presuming variant equivalence (Q35).
33. Specify essential target-specific feasibility evidence and owner-granted preparation/test boundaries separately from full physical qualification. Complete ADR-005 only after that proof and reviewed contracts, with G3/G4/G5 and latency acceptance still open as applicable (Q36).


## References

- `docs/adr/adr-005-physical-product-observation-boundary.md`
- `docs/qualification/android-job-lifecycle.md`
- `docs/qualification/android-library-interactions.md`
- `docs/specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md` section 68.6
- `docs/specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md` section 21
- `CONTEXT.md` (canonical REF-QUAL-001 qualification terminology)
- GitHub issues #28, #57, #68 in `whatobiplays/Argus-ROM-Toolkit`

## Q37 - Design-tree closure and documentation-only reconciliation (approved: A)

Decision: The owner confirms the Q1-Q36 architectural design and authorizes a reviewed, documentation-only reconciliation of ADR-005 and its dependent contracts. Implementing the observer, changing frozen qualification contracts, operating a device, or marking ADR-005 Complete requires separate gates and authorization.

Rationale: Explicit closure makes it possible to reconcile the historical Stage A/B investigation against the agreed design without mistaking implementation hypotheses for demonstrated feasibility. Contract and evidence changes must be reviewed before code.

Rejected: indefinite additional architectural grilling without a concrete unresolved decision (unnecessary churn); immediately treating Q1-Q36 as implemented, physically qualified, or an owner release verdict (unsupported leap). Failure modes and invariants: keep full rationale and alternatives for every Q1-Q36 choice, preserve historical no-go evidence, retain Q20's PID-only uncertainty caveat, keep contract v5/capability v4/oracle v9 and AND-04/AND-05 counts 31/45 unchanged until independently approved, and keep Issues #28/#57/#68 open as applicable.
