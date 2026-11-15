# Physical Product Observation Boundary

**Document ID:** ADR-005
**Status:** Draft
**Owner:** Daniel
**Last Updated:** 2026-11-14
**Depends On:** ADR-001, ADR-002, SPEC-BE-008, SPEC-BE-015, Issues #28, #57, and #68
**Supersedes:** None
**Superseded By:** None

## Decision lifecycle and approval

The owner approved investigation of the smallest authenticated, read-only production observation path on 2026-11-13. That approval covers architectural and security exploration only. It does not approve a transport, permission scheme, production API, evidence algorithm, contract change, device operation, or physical qualification. The recorded decision is in the [Issue #68 owner comment](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/68#issuecomment-6853983880).

This ADR remains Draft. The 2026-11-13 investigation and Stage B feasibility findings below are historical snapshots, not a current veto on the owner's later design selection. On 2026-11-14, the owner confirmed the Q1-Q36 design choices and closed the decision tree at Q37. This authorizes documentation-only reconciliation, **not** implementation, device operations, contract activation or ADR completion. See the [decision log](adr-005-design-decision-log.md) and [proposed contract crosswalk](../qualification/adr-005-contract-reconciliation-proposal.md).

## Context

Issue #68 investigates physical product evidence for the Android lifecycle and recovery acceptance in Issue #28. Stage A found that a complete physical observer is **NO-GO** with the currently permitted sources. The [Stage A result](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/68#issuecomment-6853781812) leaves independent app-owned identity, complete Jobs history, complete Library membership and redirect proof, and task continuity blocked. No acceptance criterion was passed.

The application currently calls Rust through Flutter Rust Bridge. Android native bridges use Flutter `MethodChannel`s inside the application; there is no authenticated host-to-app product observer. The ordinary Library uses a revision-fenced query chain. Its view token and cursor remain private to a route-scoped Dart controller.

The qualification host has an owner-approval sidecar and binds a one-use capability to canonical authorization and plan digests, package, operation, arguments, and deadlines. Those host-side bindings do not provide a credential that Android independently verifies for the calling host or session.

## Options Considered

### Option 1: Keep the current architecture and affected assertions blocked

Make no product or transport change. Keep process/package/artifact observations separate from product facts. Product identity, complete Jobs history, Library membership and direct redirects, and task continuity remain blocked until their evidence sources meet the existing contracts. This is the fail-closed fallback.

### Option 2: Investigate an authenticated, read-only production observation path

This is the approved exploratory direction. Reuse existing authoritative product contracts wherever possible, including coherent `GetJob` and the existing revision-fenced Library behavior. Do not add a parallel database reader or report an unrelated query as evidence of the UI query.

An exported Android `ContentProvider` was examined as a possible transport and is **NO-GO under the evaluated authentication and startup design**. An exported provider is reachable by other applications subject to its declared permissions. `SHELL_UID` does not identify the particular authorized ADB host, and `android.permission.DUMP` is a broad platform permission documented as not for use by third-party applications. A permission or caller-UID check alone does not bind a request to an owner-approved session, package, operation, and argument set.

An owner-approved signed session capability could be investigated only after its trust root, key provisioning, package binding, permitted operations, expiry, replay protection, and revocation are defined. No Android-verifiable trust root or session credential is approved today. An external request that cold-starts the package can trigger product runtime initialization: `ArgusApplication.onCreate()` creates the Flutter engine and starts Dart. Android 11 `ActivityThread` installs and publishes providers before calling `Application.onCreate()`; that ordering does not establish when a particular incoming request reaches its handler relative to application initialization or when authorization is checked. The request can cause initialization even if it is ultimately denied. Authorization before data release and lifecycle non-interference remain separate requirements. The evaluated exported-provider design remains NO-GO.

A signature-protected service with a same-signed companion would authenticate a package signing identity, but would add an installed helper package and would not by itself authenticate an owner-approved session. It is not an approved substitute. Any acceptable mechanism must fail closed if its caller, session, target package, operation, or current app state is uncertain.

### Option 3: Add qualification-only instrumentation or a qualification-only product API

Do not use this under the current architectural direction. It would create a qualification-only observation path and may alter process, task, or foreground behavior. Changing this direction requires separate owner approval.

### Existing mechanisms that do not meet the requirement

The diagnostics `FileProvider` is non-exported, limited to the diagnostics directory, and grants temporary read access to a selected share recipient. It is not a host query interface and must not be repurposed or broadened. Direct private-database access and `run-as` are also excluded; they do not establish the approved typed product contract for the non-debuggable qualification package.

## Decision

**Approved:** Investigate the smallest authenticated, read-only production observation path using existing authoritative product contracts wherever possible.

**Not approved:**

- An exported `ContentProvider` implementation.
- Shell UID or `DUMP` as sufficient session authentication.
- A new host-to-app IPC mechanism.
- Changes to Flutter Library-controller ownership or lifetime.
- Multi-capture Library evidence.
- A new complete Jobs-history API.
- Changes to qualification contracts, evidence schemas, or oracle pins.
- Android device operations or physical qualification.

## Rationale

### Product facts and observer independence

SPEC-BE-008 §68.6 already defines a coherent `GetJob` read for one JobRun, including requested roots, per-root ScanRun results, exclusions, progress, and direct Retry links. A Retry successor is a separate JobRun and requires its own coherent read. Missing or conflicting detail remains unavailable or blocked under that contract.

The candidate independence boundary remains unresolved. One possible threshold is independence from Flutter presentation and the host accessibility parser while continuing to rely on the signed application, its Rust backend, and the same durable product data. Such an observer could compare typed product results with UI evidence; it could not independently corroborate a false backend response or a compromised app. The owner has not accepted this definition. If Issue #28 requires an independent backend or second source of truth, the current Option 2 direction cannot meet that requirement without further architectural approval.

### Library membership and redirects

The C5 `adapt_library_surface_observation()` adapter accepts one complete hierarchy capture. Its page and row observations must share that capture's reference. A host test rejects joining two captures even when both carry the same `obs-1` identifier. The parser and adapter do not scroll or capture a device; lazy rendering can omit rows or page markers, so incomplete membership remains blocked.

With no contract change, retain the single-capture requirement. If Android virtualization prevents complete observation in one capture, Library membership and dependent redirects remain **BLOCKED**.

Any future multi-capture proposal requires separate specification, oracle, evidence-contract, test, and owner approval. It must establish authoritative query identity, backend revision continuity, exact page and cursor relationships without exposing raw tokens or cursors, process/runtime incarnation, scrolling coverage, and complete terminal-page proof. A process restart ends the enumeration; pages from before and after restart cannot be joined. SPEC-BE-015 §21's exact same-view, exactly-once direct redirect requirements remain unchanged.

### Jobs-history completeness

Current Jobs reads expose active jobs and offset-paged recent terminal jobs. They do not establish a coherent all-history set or a stable revision across pages. The host `history_complete` value therefore remains `false`; recent history must not be relabeled as complete.

A future contract would need an explicitly defined history scope and retention boundary; a monotonic read revision; stable ordering and fixed-size pagination bound to that revision and the preceding cursor; consistent identity and required root/Retry detail coverage; and a terminal condition reconciled against the complete unique JobRun set. The owner must decide whether completeness covers all terminal jobs or only qualification-relevant Library Refresh history. This contract change is not approved.

### App and Android lifecycle

The application owns one cached Flutter engine, while `libraryControllerProvider` is an auto-disposed route-scoped provider. The active Library query, private view token, cursor, and request generation belong to that controller. A host request cannot assume that the controller exists or obtain it by reading the provider: doing so when the route is absent could create a new controller and a new query. The ordinary game-detail route uses `getGame`, not the active Library view's `getGameWithView`.

Activity detachment does not itself prove that the route controller remains available. Controller disposal, query replacement, in-flight pagination, stale tokens, or process restart invalidate access to the original observation. The controller's observation sequence may restart and reuse an `obs-N` value, so that value alone is not process continuity proof. A separate engine, fresh query, or new token cannot stand in for the original UI chain. Changes to controller ownership or lifetime require a product architecture decision.

Android process, foreground, and task-continuity evidence remain separate from product-owned evidence. Package/artifact reads and OS process observations are external observations. A product query in an already-running app is a product-state read. A provider request may cold-start the application and initialize Flutter. UI navigation changes the visible app/task state. A product request must not run during a controlled process-loss observation; if its effect cannot be represented under an already authorized read-only AND-04/AND-05 operation, it requires a separately reviewed operation plan.

### Failure modes

- Unauthenticated, expired, replayed, wrong-package, or out-of-scope requests must expose no product facts. If denial cannot occur before unintended runtime initialization, the transport remains NO-GO.
- An absent Activity, absent route controller, replaced query, disposed controller, or reused observation ID does not authorize a new query; return unavailable or blocked.
- A stale view, incomplete capture, virtualized rows, missing page boundary, duplicate ID, or absent terminal proof cannot establish complete membership.
- A `GetJob` failure or inconsistency cannot be downgraded to a complete identity claim. Missing all-history coverage keeps `history_complete=false`.
- Product queries cannot establish Android process, foreground, or task continuity.

## Consequences

### Positive

- The approved work remains an investigation into a read-only path that reuses existing typed product facts.
- Existing Library revision-fencing and direct-redirect requirements remain authoritative.
- Unsupported evidence stays blocked instead of being inferred from UI labels, recent history, or process identifiers.

### Negative

- Stage A remains NO-GO for a complete physical observer. Product identity, complete Jobs history, full Library membership/redirect proof, and task continuity remain blocked.
- There is no accepted host authentication mechanism or reliable host path to the exact route-scoped Library controller.
- Physical feasibility and the Issue #28/#57 acceptance work remain outstanding.

### Follow-Up

- Keep Issues #28, #57, and #68 open. This ADR does not pass any acceptance criterion.
- Preserve contract v5, capability v4, oracle v9, and the frozen AND-04/AND-05 operation counts of 31/45. Preserve the no-reset and fixture-only requirements.
- Keep latency-oracle correction and owner-pinned performance calibration as separate dependencies.
- Before any implementation, obtain owner decisions on the trust root and session authority, the required independence threshold, controller ownership, multi-capture evidence, complete-history scope, and permitted Android observations.
- Any approved production API or Android change needs a new exact artifact pin. Evidence-schema, C5, Jobs-history, or oracle changes need separately reviewed specification/contract revisions and new pins.
- Read-only device commands, installed APK byte reads, temporary device-file mutations, UI navigation, and full qualification remain separate authorization boundaries. A pre-existing fixed-path accessibility file of uncertain ownership is a stop condition; establish exclusive ownership before creating or deleting it.

## Owner design-tree reconciliation (2026-11-14; pending independent review)

The owner approved **design direction only** through Q1-Q36 and confirmed the complete decision tree in Q37. The following replaces the *open design questions* of the Stage A/B investigation, not its historical evidence, and does not authorize implementation. The previous Decision section's "Not approved" list is still binding as **implementation and device-operation authority** until explicit separate review. Full rationale, rejected options, race/lifecycle failures, and invariants are preserved in the [decision log](adr-005-design-decision-log.md).

| Design boundary | Owner's selected direction |
| --- | --- |
| Authority and threat model (Q1-Q4, Q24-Q25) | Rust product data remains authoritative; separately defined oracle expectations and Android OS evidence check correctness. Trust owner-controlled ADB host; require basic target-qualified socket peer UID, read-only allowlist, private typed IDs and sanitized shared evidence. Deliberate attacker conflicts are not design drivers; no PKI/key rotation by default. |
| Transport and lifecycle (Q3, Q8-Q9, Q12-Q13, Q18-Q19, Q23) | Investigate process-scoped Unix-domain socket reached through ADB forwarding. Same implementation in qualification and distributable Release; default-OFF Advanced/Diagnostics toggle survives restart when enabled. No observer-triggered app cold start, UI controller creation, navigation, new job, keepalive or process manipulation. One observer request at a time; Busy is non-evidence. |
| Product Job/Library proof (Q2, Q5-Q6, Q10, Q14-Q17) | A distinct read-only RevisionFenced Library enumeration inside the running app proves committed membership and direct redirects; it is not the Flutter UI query. C5 presentation assertions remain separate until explicitly revised. Jobs history means **all retained LibraryRefresh** JobRuns using one bounded coherent read; incomplete or changed observations BLOCK and cannot be silently retried. |
| OS/process/task evidence (Q7, Q11, Q20-Q21, Q26, Q30) | Checkpointed OS-backed package/process/foreground/task facts and transient locally filtered diagnostics, without a monitoring service. **Android PID only** for process identity (no extra runtime ID); equality across an unobserved gap cannot prove continuity. AND-04 requires same task on return; AND-05 requires independently verified stop/relaunch and durable state, not same task across force-stop. |
| Failure, cleanup, performance (Q27, Q29, Q31, Q33-Q35) | Distinguish FAILED product contradictions from BLOCKED incomplete evidence and downstream NOT_RUN. All-or-nothing socket results, no hidden retry; incomplete cleanup remains blocked until separately authorized remediation. Match diagnostics/workload in latency calibration; distributable smoke verifies disabled default/socket absent without enabling full qualification. |
| Gates and governance (Q22, Q28, Q32, Q36-Q37) | Propose G3 = admission/baseline, G4 = frozen AND-04 (31), G5 = frozen AND-05 (45). Produce assertion-level crosswalk; update versioned contracts first, then independently review. ADR remains Draft until essential target-specific socket/UID/OS/lifecycle feasibility is demonstrated and reviewed. |

**Outstanding engineering evidence, not unresolved owner choices:** Exact peer UID from ADB forwarding, socket feasibility and denial behavior, approved OS task-observation source, versioned API fields/bounds, static vs live diagnostics overhead, and applicability of each PAC/TAC requirement. Unsupported mechanisms remain NO-GO and dependent assertions BLOCKED; do not invent evidence.

**Frozen contracts:** Qualification contract v5, capability v4, oracle v9 and AND-04/AND-05 31/45 operations remain unchanged by this documentation. The [proposed contract reconciliation](../qualification/adr-005-contract-reconciliation-proposal.md) identifies future review work but is explicitly NON-NORMATIVE. Physical device access, installs, resets, ADB commands, observer coding, revised artifact pins, and qualification execution require their own approvals.

## Stage B feasibility assessment

This assessment records source-backed feasibility findings. It does not choose an implementation or change the approved investigation direction. Repository findings below are pinned to the [approved Stage B baseline `78748311cf5bef829d2f0b3fb2081b97e2844dfd`](https://github.com/whatobiplays/Argus-ROM-Toolkit/commit/78748311cf5bef829d2f0b3fb2081b97e2844dfd). Issue #68 still carries the older PR #58 planning baseline `517361b36c42c208c66c9ac9431c267273cce69b`; that value remains historical issue context and is not the source revision used here.

Evidence labels distinguish executable source, normative requirements, proposals, and physical proof:

| Label | Meaning |
| --- | --- |
| Source-code implementation | Executable repository code at the pinned baseline implements the named path. This does not prove the path ran on a device, is present in an installed artifact, or independently verifies its result. |
| Contractually specified | A pinned specification or qualification contract requires the named behavior. Specification alone is not implementation evidence. |
| Source-backed limitation | Repository code or a pinned contract limits the claim or the evidence that can establish it. |
| Hypothesis | A proposed mechanism or evidence receipt that is neither implemented nor required by the current contract. |
| Physical evidence unavailable | No authorized physical observation establishes the product or Android fact. Keep the claim BLOCKED or unqualified. |

### Feasibility matrix

Each claim record names its authority, concrete interface or path, independent evidence source, current capability, missing proof and trust boundary, feasibility, risk, required proof, and next owner decision.

#### Product Job identity and per-root relations

- Authority and path: **Contractually specified** by [SPEC-BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md). **Source-code implementation** runs through [ArgusClient](../../flutter/lib/core/client/src/argus_client.dart), [FrbArgusClientGateway](../../flutter/lib/core/bridge/src/frb_argus_client_gateway.dart) (`crateGetJob`), Rust `JobsQueries::get_job`, and the [SQLite Jobs adapter](../../rust/crates/argus-infrastructure/src/sqlite/jobs.rs). The typed Job detail includes the JobRun, ScanRun, and LibraryRoot identity tuple.
- Independent evidence: The host `JobLifecycleObserver` protocol and `JobIdentityObservation` evidence type describe qualification-side data; neither is an Android-authenticated product read. No independent source currently corroborates the product backend response.
- Capability and feasibility: **Implemented in source** for a coherent detail read of one known JobRun and its per-root details. Reusing that read is feasible to investigate. An authenticated host-to-product observation path remains unavailable.
- Gap and risk: The host cannot authenticate the read or prove it came from the approved package/session. A missing or mismatched root/ScanRun relation, or a Retry successor inferred from list order, could produce a false identity claim. Root locations and other private paths must not enter evidence output.
- Required proof and owner decision: Bind each reported JobRun to its own coherent `GetJob` result, verify each required ScanRun/root relation and direct Retry source/successor link, and preserve provenance with bounded, redacted output. The owner must set the required observer independence threshold and exact identity claims.

#### Complete Jobs history

- Authority and path: **Source-code implementation** in [JobsListController](../../flutter/lib/features/jobs/application/jobs_list_controller.dart) requests active Jobs and recent terminal pages of 20 through [ArgusClient](../../flutter/lib/core/client/src/argus_client.dart) and [FrbArgusClientGateway](../../flutter/lib/core/bridge/src/frb_argus_client_gateway.dart); the gateway reaches Rust `JobsQueries::list_active` and offset-based `list_recent_terminal`. Pages expose `totalCount` and `nextOffset`. No pinned requirement defines a complete all-history snapshot.
- Independent evidence: No authenticated host observer or independently sourced complete JobRun set is available. C5's `history_complete=false` is a fail-closed qualification result, not a source of missing history.
- Capability and feasibility: **Implemented in source** for active Jobs and offset-paged recent terminal Jobs. Complete all-history coverage is unavailable under the current interface.
- Gap and risk: There is no declared retention boundary or shared history revision across pages. Inserts, removals, or ordering changes can cause gaps or duplicates between offsets. Treating recent rows as complete could omit a failed or successor JobRun.
- Required proof and owner decision: Define history scope and retention, stable ordering and snapshot revision, revision-bound continuation, duplicate/gap detection, required detail coverage, and a terminal condition reconciled with the unique JobRun set. The owner must decide whether Issue #28 needs all retained terminal Jobs or a narrower qualification history; any new query requires a separately approved contract change.

#### Actual Library RevisionFenced page chain

- Authority and path: **Contractually specified** by [SPEC-BE-015 §21](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md). **Source-code implementation** runs from [LibraryController](../../flutter/lib/features/library/application/library_controller.dart), through [`ArgusClient.listGamesRevisionFenced`](../../flutter/lib/core/client/src/argus_client.dart) and [FrbArgusClientGateway](../../flutter/lib/core/bridge/src/frb_argus_client_gateway.dart), to Rust `crateListGames`. The route-scoped controller holds query shape, view token, next cursor, and accepted pages in memory.
- Independent evidence: No approved external receipt proves the exact query and page sequence used by the visible UI. A hierarchy capture records rendered accessibility content, not the underlying request parameters or tokens.
- Capability and feasibility: **Implemented in source** for a revision-fenced UI request chain. The contract requires the same query and token on continuation and exactly the preceding page's `nextCursor`. An opaque receipt tied to the actual UI sequence is a **hypothesis**.
- Gap and risk: No host-visible proof binds the external observation to that route controller's original query. Route disposal, query replacement, runtime replacement, or process restart ends the original chain. A fresh query cannot repair it. Exposing raw tokens or cursors creates a privacy and replay surface.
- Required proof and owner decision: Establish provenance for every request and response in the original chain without exposing raw token/cursor values, and fail closed on stale or missing pages. The owner must decide who owns the controller/query lifetime during observation and whether a narrowly scoped internal receipt is acceptable.

#### Library membership and direct redirects

- Authority and path: **Contractually specified** by [SPEC-BE-015 §21](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md). Rust's `LibraryViewToken` and revision-fenced page types support same-view continuation; the Dart client exposes `getGameWithView`. The ordinary game-detail route uses `getGame`, so that route does not establish a token-bound lookup in the active Library view.
- Independent evidence: No external evidence currently proves a complete first-to-terminal UI page chain or every required direct lookup against that chain.
- Capability and feasibility: **Specified** behavior requires an uninterrupted RevisionFenced enumeration and, for each required prior GameId, a token-bound direct `GetGame` that validates in the same transaction and returns the exact canonical target. Current host evidence does not prove those events.
- Gap and risk: Missing or repeated cursors, changed query shape, stale tokens, duplicate IDs, absent terminal page, or a lookup outside the same view can make membership or redirect results incomplete or incorrect.
- Required proof and owner decision: Prove the exact query, each page and cursor relationship, terminal completion, full unique membership, and every required canonical redirect target. Keep token/cursor values private. The owner must retain the current single-capture C5 rule or separately authorize a contract/schema/oracle revision for any multi-capture proposal.

#### C5 accessibility projection

- Authority and path: **Source-code implementation** in [`adapt_library_surface_observation`](../../scripts/android_qualification/physical/_job_lifecycle_ui.py) accepts one hierarchy capture and requires page/row references to match it. The [P003 C5 findings](../tasks/task-p003-028-android-job-lifecycle-recovery.md) document Flutter lazy-builder virtualization and incomplete offscreen exposure.
- Independent evidence: Host synthetic checks exercise parser behavior. They are not physical device captures and do not establish what Android exposes on the qualified target.
- Capability and feasibility: **Implemented in source** for single-capture parsing and consistency checks; it performs no capture, navigation, or scrolling. Under current C5, complete membership is **BLOCKED** when one hierarchy does not expose every row and boundary.
- Gap and risk: Virtualized rows and page markers can be absent from the hierarchy. Treating a partial tree as complete can create false membership or redirect claims; raw hierarchy data can also expose private paths and labels.
- Required proof and owner decision: Demonstrate complete one-capture exposure on the qualified target under a separately approved physical plan, or keep the claim blocked. The owner must separately decide whether to propose multi-capture evidence; Stage B does not change the single-capture contract.

#### Android package, process, foreground, and task facts

- Authority and path: Artifact pins identify the intended build but do not prove installed bytes or signer. The host lifecycle schema names process, foreground, and task observations; [ArgusApplication](https://github.com/whatobiplays/Argus-ROM-Toolkit/blob/78748311cf5bef829d2f0b3fb2081b97e2844dfd/flutter/android/app/src/main/kotlin/com/argusromtoolkit/argus/ArgusApplication.kt#L52) initializes the Flutter engine and Dart entrypoint in `onCreate()`.
- Independent evidence: No currently approved, qualified Android OS source establishes installed package identity, signer/digest, process loss, foreground package, or task continuity for this acceptance.
- Capability and feasibility: Product code can establish product-owned state only. A separately authorized OS observation could establish narrowly scoped OS facts, but its source and qualification are not established here. Current physical evidence for these claims is unavailable.
- Gap and risk: A product query cannot prove OS state. A request that cold-starts the package can trigger product initialization and confound process/lifecycle evidence, regardless of the authorization result. Provider installation order does not prove handler authorization order.
- Required proof and owner decision: Identify and qualify an independent, permitted OS source for each claimed fact and show that observation does not disturb the lifecycle under test. The owner must decide which OS observations and cold-start effects are acceptable.

#### Authentication and observer boundary

- Authority and path: The app has in-process Flutter/Rust `MethodChannel` bridges; the [host lifecycle executor](../../scripts/android_qualification/_job_lifecycle_executor.py) binds a one-use host-side capability to authorization and plan digests, package, operation, arguments, and deadlines. Android does not verify that sidecar as host/session authority.
- Independent evidence: No Android-verifiable trust root, session credential, or authenticated host-to-product observer exists in the current boundary.
- Capability and feasibility: The host-side binding is **implemented in source** on the qualification host. Android-side authentication and the observation transport are **hypotheses**, not implemented or contractually selected. An exported `ContentProvider` guarded only by caller UID or `DUMP` remains **NO-GO** under the evaluated design.
- Gap and risk: Trust root, credential issuance/protection, package and artifact binding, operation authorization, expiry, replay, revocation, key rotation, audit, privacy limits, and cold-start behavior remain unresolved. A second adapter to the same backend does not create independent product evidence.
- Required proof and owner decision: Before selecting any mechanism, define and test session authentication, a closed operation/argument allowlist, denial before data release, replay/expiry/revocation, bounded redacted output, and lifecycle non-interference. The owner must decide the trust root, session authority, permitted observations, and acceptable independence threshold. No transport, credential, observer architecture, or threshold is selected here.

### Candidate feasibility and trade-offs

The options and rejection rationale above remain the decision record. This table adds relative effort and security impact; it is not an implementation estimate.

| Candidate | Feasibility, relative cost, and complexity | Security and lifecycle trade-off |
| --- | --- | --- |
| Keep the current architecture and leave unsupported assertions BLOCKED | Feasible now; no implementation cost and low complexity. | Adds no data-access surface. Issue #28 acceptance remains incomplete. |
| Investigate a normal authenticated, read-only product channel | Investigation only; likely medium-to-high cost and high security/integration complexity. Physical feasibility is unknown. | Adds a sensitive access boundary and may still fail the independence threshold because it reads the same product backend. No transport or credential design is approved. |
| Qualification-only Android instrumentation and a narrow app seam | Not selected; likely medium-to-high cost and high lifecycle/qualification complexity. | Adds a package or test seam and can affect process/task observations. It does not resolve the independence question by itself. Reconsideration needs a separate owner reversal. |
| Exported provider guarded only by caller UID or `android.permission.DUMP` | NO-GO; cost is not estimated because the current design fails the required session-identity boundary. | Does not bind requests to an approved host session. A cold-starting request can trigger app runtime initialization. Android 11 installs and publishes providers before `Application.onCreate()`, but this does not establish when a particular request's handler authorization runs. Android marks `DUMP` as unavailable to third-party applications. See Option 2 and Existing mechanisms for the rejected provider, companion service, diagnostics `FileProvider`, private-database, and `run-as` paths. |

### Authentication, trust boundaries, and failure controls

| Boundary | Current evidence and risk | Decision or proof still required |
| --- | --- | --- |
| Host, caller, and session identity | A host-side approval record is not a credential the Android process verifies. Shell UID identifies the calling OS process class; it does not identify the particular approved host session. A package signature check identifies a signing identity, not the session's approval or scope. | Define the trust root, who issues a capability, how the app verifies it, key provisioning and protection, package/signer binding, host/session binding, and behavior when any identity is missing or ambiguous. No trust root is approved. |
| Authorization and least privilege | A read-only label does not limit a caller by itself. The existing sidecar binds a package, operation, arguments, plan digest, and deadline on the host side. | If a channel is later proposed, define a closed operation allowlist, argument constraints, target artifact/package binding, output bounds, and denial behavior. Reject unknown operations, wrong targets, changed arguments, and unauthorized effectful work. The owner must approve the permitted Android observations. |
| Replay, expiry, and revocation | No Android-verified one-use session, freshness check, replay state, or revocation mechanism exists in the current product boundary. | Define nonce/challenge semantics, expiry, replay rejection, revocation, key rotation, audit records, and recovery after host or app restart. Expired, replayed, revoked, or unverifiable requests must return no product facts. |
| Startup and lifecycle effects | Android 11 `ActivityThread` installs and publishes providers before invoking `Application.onCreate()`. This ordering does not establish when a particular incoming request reaches its handler relative to application initialization or when authorization is checked. A request that cold-starts this package can trigger `ArgusApplication.onCreate()`, which initializes the Flutter engine and Dart runtime, even if the request is ultimately denied. | Preserve the evaluated exported-provider NO-GO. Define whether any read may cold-start the product, prove authorization before data release, and show lifecycle non-interference. Any design must state how it avoids changing controlled process-loss, foreground, and task-continuity observations. |
| Product and OS trust domains | Product queries can report app-owned Job and Library state. Android OS evidence can report OS-owned package or process facts. Neither source substitutes for the other. A second adapter to the same backend is not a second source of truth. | Define the required independence level: separate from Flutter presentation, separate from the backend implementation, or independently corroborated product state. Bind every assertion to its source and provenance. |
| Privacy, output, and audit | Library tokens/cursors, personal paths, provider payloads, private database contents, raw XML, and broad system dumps are not approved evidence outputs. | Define a minimal typed response, bounded size, redaction, retention, and an audit receipt tied to the admitted session. Do not expose raw tokens/cursors or personal paths. Fail closed on oversized, partial, stale, or contradictory results. |
| Concurrent changes and process incarnation | Library tokens are in-memory query state; a process restart ends the enumeration. An `obs-N` identifier may be reused and is not process-incarnation proof. Jobs pages lack a shared history revision. | Any future receipt must identify one uninterrupted query generation and detect races, stale pages, controller disposal, runtime replacement, and restart. A changed or incomplete chain cannot be repaired by starting an unrelated query. |

### Dependency-ordered investigation

1. The owner defines the independence threshold and the exact claims that need independent proof. If the required standard is an independent backend or second product source, record that the selected direction cannot currently meet it.
2. The owner and security review define the Android-verifiable trust root, session authority, caller and package binding, authorization scope, replay protection, expiry, revocation, privacy limits, and accepted cold-start behavior. Do not select a transport before those boundaries are testable.
3. Map the required parent JobRun, per-root ScanRun relations, requested/admitted/excluded scope, and direct Retry source/successor facts to existing typed product reads. Separate facts available from one coherent `GetJob` from evidence that the host can actually receive and authenticate.
4. Decide whether Issue #28 needs all retained terminal Jobs or a narrower qualification history. If completeness requires a new history query, define its revision, retention, ordering, continuation, and terminal proof in a separately approved contract change.
5. Trace the ordinary Library query from the actual route-scoped controller through every RevisionFenced page and required token-bound direct redirect. Determine whether an internal, opaque proof can bind that exact UI request chain without exposing tokens or cursors. Keep the current C5 single-capture rule; assess multi-capture only after separate owner approval.
6. Evaluate package/process observations separately from product facts. Identify a narrowly scoped OS source for each proposed fact and show its lifecycle effects, privacy exposure, and limits. Do not treat process presence as foreground or task proof.
7. Compare the evidence path against the frozen AND-04/AND-05 operations and required gates. State unavailable fields as BLOCKED, identify dependent operations as NOT_RUN, and return unresolved design and contract questions to the owner before any implementation plan.

An infeasible mechanism is a finding about that mechanism. It does not end the remaining independent investigations. Stop the affected path when a required source, security boundary, or owner decision is absent; do not fill the gap with a weaker observation.

### Evidence mapping and acceptance status

The current qualification document defines AND-04 as 31 operations and AND-05 as 45. This ADR does not change either plan.

| Scenario range | Existing operation purpose | Feasibility consequence |
| --- | --- | --- |
| AND-04 7–17 | Refresh arrival/progress, Jobs, refresh detail, parent/child identity, Library | Missing independent Job/root identity or complete Library proof blocks the dependent assertion. |
| AND-04 18–21 | Background, process/foreground observation, return to the existing task, foreground surface | Process presence alone does not prove foreground or task continuity. |
| AND-04 22–30 | Recovered Jobs/detail, Sources root, and ScanRun state | UI semantics must be cross-checked with typed identity and root relations; missing facts remain BLOCKED. |
| AND-04 31 | Restore qualification foreground | Requires the existing task and foreground evidence; it is not a fresh-launch substitute. |
| AND-05 12–20 | Pre-loss Library, Sources root, refresh detail, identity, and pre-stop guard | Incomplete one-capture Library evidence or missing independent identity blocks before process stop. |
| AND-05 21–24 | Authorized process stop, process observation, launch, foreground surface | These operations are physical and are outside this documentation task. Product queries cannot establish their OS facts. |
| AND-05 25–33 | Recovered Sources, Library, Jobs, and refresh detail | Recovery claims require independent product identity and the same pinned artifact; unsupported rows remain BLOCKED. |
| AND-05 34–37 | Retry eligibility, the single Retry, outcome, and source/successor relation | A Retry must remain bound to its source JobRun and its own successor detail. No Retry is authorized here. |
| AND-05 38–45 | Post-Retry Library, root, Jobs, and terminal successor | Membership, root relation, and terminal successor remain blocked without complete Library and Jobs evidence. |

G3, G4, and G5 remain distinct owner-authorized gates. The reviewed task and qualification sources do not define each gate's canonical semantics. A #28-specific PAC/TAC mapping has not been supplied. Do not infer those mappings from unrelated plans. Keep them **UNDEFINED** until the owner provides the canonical crosswalk.

For either scenario, unavailable or incomplete evidence is **BLOCKED** and dependent operations are **NOT_RUN**. A conclusive contradictory identity or product result is **FAILED** under the approved oracle. No Stage B document finding passes an acceptance criterion.

### Proposed future verification

These checks are proposals for a later, separately approved design. They are not being run for this ADR update.

- Host fake-transport checks should bind every request to a fixed target, artifact, session, operation, arguments, and deadline. Exercise wrong package or signer, missing and expired authority, altered arguments, replay, revocation, unsupported operations, oversized responses, partial results, and ambiguous failures. Assert that rejection returns no product facts and causes no unauthorized action.
- Adversarial host tests should cover stale and reordered Jobs pages, duplicate or missing JobRun identities, a changed Jobs snapshot, Library query-shape changes, skipped or repeated cursors, missing terminal pages, duplicate GameIds, mismatched direct redirects, controller disposal, runtime replacement, and process restart between pages. A fresh query after a failure must not be accepted as proof of the original UI chain.
- Physical feasibility checks require separate exact owner authorization for target, artifact, operations, effects, time bounds, evidence handling, and restoration. The plan must first identify how each observation is sourced without using it to disturb the lifecycle claim under test. No ADB command, device access, install, UI interaction, or physical qualification is authorized or performed by this Stage B documentation work.

### Scope, exclusions, and approval gates

The only permitted change in this slice is this Draft ADR-005. It may record source-backed feasibility, costs and trade-offs, security boundaries, alternatives and their rejection rationale, dependency order, evidence mappings, blocked claims, and owner decisions. Do not edit the ADR index or create another feasibility document.

Do not change production code, the Android manifest, APIs, qualification contracts, evidence schemas, oracle, frozen operation plan, or artifact pins. Keep contract v5, capability v4, oracle v9, and AND-04/AND-05 counts 31/45 unchanged. Do not use ADB or operate a device. Do not start, stop, restart, reload, or otherwise manage an MCP server. If a later registration task requires editing an active verified MCP configuration, validate it statically and report **MCP RESTART REQUIRED — OWNER ACTION**; do not restart it.

Before any implementation architecture can be approved, the owner must decide:

1. What observer independence Issue #28 requires, including whether sharing the product backend is acceptable.
2. Which trust root and session authority an Android process can verify, who provisions and revokes it, and how authentication binds host, target package/artifact, allowed operation, arguments, and deadline.
3. Whether any observation may cold-start the app and initialize Flutter/Rust, and which startup effects would invalidate process, foreground, or task evidence.
4. Which exact Android OS observations are allowed and what independent source can establish foreground and task continuity on the qualified target.
5. Whether Jobs completeness covers all retained terminal jobs or only a defined qualification history, and the revision/retention contract that would make it complete.
6. How evidence will bind to the actual UI's RevisionFenced page chain and direct redirects while preserving token/cursor privacy and the current single-capture C5 contract. Any multi-capture change needs separate approval.
7. Who owns the Library controller/query lifetime during observation and how the design handles route disposal, query replacement, and runtime restart without creating a fresh query.
8. The canonical G3/G4/G5 definitions and #28 PAC/TAC crosswalk, including the evidence required for each operation range.
9. Whether a production channel or qualification-only instrumentation is acceptable after these questions are answered, with a new exact artifact pin and separately reviewed contract/schema/oracle revisions where required.

Until those decisions are recorded and the resulting security and evidence claims are directly reviewed, ADR-005 remains Draft and no implementation architecture is approved.

### Stage B source references

- [Issue #68 owner decision](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/68#issuecomment-6853983880)
- [SPEC-BE-008 §68.6](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md)
- [SPEC-BE-015 §21](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md)
- [LibraryController](../../flutter/lib/features/library/application/library_controller.dart), [ArgusClient](../../flutter/lib/core/client/src/argus_client.dart), [FRB gateway](../../flutter/lib/core/bridge/src/frb_argus_client_gateway.dart), and Rust [Library queries](../../rust/crates/argus-application/src/library.rs), including the RevisionFenced request shape and in-memory page observation.
- [JobsListController](../../flutter/lib/features/jobs/application/jobs_list_controller.dart), [ArgusClient](../../flutter/lib/core/client/src/argus_client.dart), [FRB gateway](../../flutter/lib/core/bridge/src/frb_argus_client_gateway.dart), [JobsQueries](../../rust/crates/argus-application/src/jobs.rs), and the [SQLite Jobs adapter](../../rust/crates/argus-infrastructure/src/sqlite/jobs.rs).
- [C5 Library adapter](../../scripts/android_qualification/physical/_job_lifecycle_ui.py) and [C5 findings](../tasks/task-p003-028-android-job-lifecycle-recovery.md).
- [Host lifecycle observer protocol](../../scripts/android_qualification/_job_lifecycle_executor.py) and [observation evidence types](../../scripts/android_qualification/_job_lifecycle_contract.py).
- [AND-04 and AND-05 operation tables](../qualification/android-job-lifecycle.md).
- [Android 11 ActivityThread provider/application startup order](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/java/android/app/ActivityThread.java)
- [Android ContentProvider lifecycle](https://developer.android.com/reference/android/content/ContentProvider#onCreate())
- [Android DUMP permission](https://developer.android.com/reference/android/Manifest.permission#DUMP)
- [Android ActivityManager task APIs](https://developer.android.com/reference/android/app/ActivityManager#getRunningTasks(int))
- [ArgusApplication lifecycle source at the approved baseline](https://github.com/whatobiplays/Argus-ROM-Toolkit/blob/78748311cf5bef829d2f0b3fb2081b97e2844dfd/flutter/android/app/src/main/kotlin/com/argusromtoolkit/argus/ArgusApplication.kt#L52)

## References

- [Issue #68](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/68)
- [Issue #68 owner decision](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/68#issuecomment-6853983880)
- [Issue #68 Stage A NO-GO result](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/68#issuecomment-6853781812)
- [Issue #28](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/28)
- [Issue #57](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/57)
- [ADR template](../templates/adr.md)
- [ADR-001: Qualification Artifact Separation](adr-001-qualification-artifact-separation.md)
- [ADR-002: Independent Evidence-Based Owner Verdicts](adr-002-independent-owner-verdicts.md)
- [SPEC-BE-008](../specifications/backend/spec-be-008-rust-to-flutter-bridge-dto-contract.md) §68.6
- [SPEC-BE-015](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md) §21
- [Android lifecycle qualification contract](../qualification/android-job-lifecycle.md)
- [Android Library interaction qualification](../qualification/android-library-interactions.md)
- [Android provider declaration and permission attributes](https://developer.android.com/guide/topics/manifest/provider-element)
- [Android `DUMP` permission](https://developer.android.com/reference/android/Manifest.permission.html)
- [AOSP Android 11 ContentProvider](https://android.googlesource.com/platform/frameworks/base/%2B/refs/tags/android-11.0.0_r25/core/java/android/content/ContentProvider.java)
- [Android 11 AOSP ActivityThread](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/core/java/android/app/ActivityThread.java)
