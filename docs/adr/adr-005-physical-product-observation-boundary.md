# Physical Product Observation Boundary

**Document ID:** ADR-005
**Status:** Draft
**Owner:** Daniel
**Last Updated:** 2026-11-13
**Depends On:** ADR-001, ADR-002, SPEC-BE-008, SPEC-BE-015, Issues #28, #57, and #68
**Supersedes:** None
**Superseded By:** None

## Decision lifecycle and approval

The owner approved investigation of the smallest authenticated, read-only production observation path on 2026-11-13. That approval covers architectural and security exploration only. It does not approve a transport, permission scheme, production API, evidence algorithm, contract change, device operation, or physical qualification. The recorded decision is in the [Issue #68 owner comment](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/68#issuecomment-6853983880).

This ADR remains Draft. It records the approved direction and the boundaries that any later architecture decision must resolve; it does not select an implementation architecture.

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

An owner-approved signed session capability could be investigated only after its trust root, key provisioning, package binding, permitted operations, expiry, replay protection, and revocation are defined. No Android-verifiable trust root or session credential is approved today. A request that cold-starts this package may run `ArgusApplication.onCreate()`, which creates the Flutter engine and starts Dart before a provider handler can authorize the request. A handler-level check therefore cannot establish denial before runtime initialization.

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

## Stage B feasibility assessment

This assessment records source-backed feasibility findings. It does not choose an implementation or change the approved investigation direction. Repository findings below are pinned to the [approved Stage B baseline `78748311cf5bef829d2f0b3fb2081b97e2844dfd`](https://github.com/whatobiplays/Argus-ROM-Toolkit/commit/78748311cf5bef829d2f0b3fb2081b97e2844dfd). Issue #68 still carries the older PR #58 planning baseline `517361b36c42c208c66c9ac9431c267273cce69b`; that value remains historical issue context and is not the source revision used here.

The status words below keep implemented behavior separate from proposals and missing evidence.

| Status | Meaning in this assessment |
| --- | --- |
| Implemented | A repository source or contract defines the behavior. This does not establish that a physical device has exposed or qualified it. |
| Source-supported limitation | Current code or a pinned contract prevents the proposed claim or constrains how it could be proved. |
| Hypothesis | A candidate mechanism that still needs design, threat-model, and owner review. |
| Unavailable evidence | No approved source or physical observation currently establishes the claim. Keep it BLOCKED or unqualified. |

### Feasibility matrix

| Claim | Source evidence at the approved baseline | Feasibility and remaining gap |
| --- | --- | --- |
| Product Job identity and per-root relations | SPEC-BE-008 §68.6 defines typed refresh details and the per-root identity tuple of `JobRunId`, `ScanRunId`, and `LibraryRootId` (DTO fields `jobRunId`, `scanRunId`, and `libraryRootId`). A coherent `GetJob` read can report one JobRun and its details. The qualification host defines `JobLifecycleObserver` and `JobIdentityObservation`; these are host protocols and evidence shapes. | Reusing typed product reads is a plausible investigation path. No authenticated host-to-product observer is implemented. A UI label, host protocol, or second adapter does not independently prove the backend result. A Retry successor requires its own coherent read and a direct source/successor relation. |
| Complete Jobs history | The Flutter Jobs controller loads active jobs and offset-paged recent terminal jobs, initially 20 at a time. Its page carries `totalCount` and `nextOffset`, but no stable history revision or declared retention boundary. C5 keeps `history_complete=false` because visible rows do not prove completeness. | Current sources cannot prove an all-history set. A later contract would need an owner-defined scope and retention boundary, stable snapshot/revision, deterministic ordering, revision-bound continuation, duplicate/gap checks, required detail coverage, and an unambiguous terminal condition. Whether that covers every retained terminal job or only qualification-relevant refresh history is unresolved. |
| Actual Library page chain | The route-scoped `LibraryController` builds RevisionFenced requests, keeps the query shape, view token, next cursor, and accepted pages in its in-memory observation, and rejects stale or mismatched continuations. SPEC-BE-015 §21 requires the same query and token on every continuation and exactly the previous page's `nextCursor`. | The app has a coherent UI request chain, but no approved external receipt proves the exact chain used by the visible UI. A fresh query cannot stand in for it. An opaque receipt tied to the actual request sequence is a hypothesis; its source, lifetime, and evidence contract have not been designed or approved. Raw tokens and cursors must remain private. |
| Library membership and direct redirects | SPEC-BE-015 §21 requires an uninterrupted first-to-terminal RevisionFenced enumeration. A token-bound direct `GetGame` lookup must validate in the same transaction and return the exact canonical target for each required prior GameId; the result is checked against the completed membership set. | Current host/UI observations do not prove full chain coverage, every required direct lookup, or its result. Missing pages, changed query shape, stale token, duplicate IDs, missing terminal proof, or incomplete lookup coverage leave membership and dependent redirect claims BLOCKED. |
| C5 accessibility projection | The C5 adapter accepts one complete hierarchy parse, checks that all page and row references point to that capture, and performs no capture, navigation, or scrolling. Flutter uses lazy Library builders, so Android accessibility can omit offscreen rows or page boundaries. The process-local `obs-N` value is not process continuity evidence. | Synthetic host coverage proves parser behavior only. It does not prove that a device exposes every row in one capture. The v5 single-capture contract remains in force; multi-capture evidence needs separate specification, schema, oracle, and owner approval. |
| Android package and lifecycle facts | Package/artifact pins identify the intended build; they are not observations of the installed package. Stage A records package presence, signer/digests, storage, and no-reset fixture baseline as blocked or unqualified. A package-scoped process observation may establish a point-in-time process fact when separately authorized. | Product reads cannot prove package signer, process loss, foreground package, or task continuity. The host observation schema names process, foreground, and task fields but does not supply an Android source. The current Stage A review identifies no permitted host source for foreground/task continuity. These claims remain BLOCKED until an independent, authorized OS source is established and qualified. |
| Transport and observer boundary | The product uses an in-process Flutter/Rust bridge. No authenticated host-to-app product observer exists. The host approval sidecar binds a one-use capability to authorization and plan digests, package, operation, arguments, and deadlines; Android does not independently verify that sidecar as a host/session credential. | A normal read-only channel is the owner's selected direction for investigation only. It could separate observation from Flutter presentation while still sharing the same app backend and durable state. It cannot independently corroborate a false backend response or compromised product process. Whether that independence is sufficient is an owner decision. |

### Candidate feasibility and trade-offs

The options and rejection rationale above remain the decision record. This table adds relative effort and security impact; it is not an implementation estimate.

| Candidate | Feasibility and relative cost | Incremental trade-off |
| --- | --- | --- |
| Keep the current architecture and leave unsupported assertions BLOCKED | Feasible now; low cost. | Adds no data-access surface. Issue #28 acceptance remains incomplete. |
| Investigate a normal authenticated, read-only product channel | Selected for investigation only; likely medium-to-high cost. Physical feasibility is unknown. | Adds a sensitive access boundary and may still fail the independence threshold because it reads the same product backend. No transport or credential design is approved. |
| Qualification-only Android instrumentation and a narrow app seam | Not selected; likely medium-to-high cost. | Adds a package or test seam and can affect process/task observations. It does not resolve the independence question by itself. Reconsideration needs a separate owner reversal. |
| Exported provider guarded only by caller UID or `android.permission.DUMP` | NO-GO under the evaluated design. | Does not bind requests to an approved host session. Provider startup can initialize the Flutter engine before handler authorization. Android marks `DUMP` as unavailable to third-party applications. See Option 2 and Existing mechanisms for the rejected provider, companion service, diagnostics `FileProvider`, private-database, and `run-as` paths. |

### Authentication, trust boundaries, and failure controls

| Boundary | Current evidence and risk | Decision or proof still required |
| --- | --- | --- |
| Host, caller, and session identity | A host-side approval record is not a credential the Android process verifies. Shell UID identifies the calling OS process class; it does not identify the particular approved host session. A package signature check identifies a signing identity, not the session's approval or scope. | Define the trust root, who issues a capability, how the app verifies it, key provisioning and protection, package/signer binding, host/session binding, and behavior when any identity is missing or ambiguous. No trust root is approved. |
| Authorization and least privilege | A read-only label does not limit a caller by itself. The existing sidecar binds a package, operation, arguments, plan digest, and deadline on the host side. | If a channel is later proposed, define a closed operation allowlist, argument constraints, target artifact/package binding, output bounds, and denial behavior. Reject unknown operations, wrong targets, changed arguments, and unauthorized effectful work. The owner must approve the permitted Android observations. |
| Replay, expiry, and revocation | No Android-verified one-use session, freshness check, replay state, or revocation mechanism exists in the current product boundary. | Define nonce/challenge semantics, expiry, replay rejection, revocation, key rotation, audit records, and recovery after host or app restart. Expired, replayed, revoked, or unverifiable requests must return no product facts. |
| Startup and lifecycle effects | Android initializes registered providers as part of application startup. In this repository, `ArgusApplication.onCreate()` constructs and starts the cached Flutter engine. A handler check runs after that startup path. | Decide whether a read may cold-start the product. If authorization must precede engine or runtime initialization, a handler-level provider check does not meet that requirement. Any design must also state how it avoids changing the controlled process-loss, foreground, and task-continuity observation. |
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
- [LibraryController](../../flutter/lib/features/library/application/library_controller.dart), including its RevisionFenced request shape and in-memory page observation.
- [JobsListController](../../flutter/lib/features/jobs/application/jobs_list_controller.dart) and the [Jobs client models and interfaces](../../flutter/lib/core/client/src/models.dart).
- [C5 Library adapter](../../scripts/android_qualification/physical/_job_lifecycle_ui.py) and [C5 findings](../tasks/task-p003-028-android-job-lifecycle-recovery.md).
- [Host lifecycle observer protocol](../../scripts/android_qualification/_job_lifecycle_executor.py) and [observation evidence types](../../scripts/android_qualification/_job_lifecycle_contract.py).
- [AND-04 and AND-05 operation tables](../qualification/android-job-lifecycle.md).
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
- [AOSP ActivityThread](https://android.googlesource.com/platform/frameworks/base/%2B/refs/heads/main/core/java/android/app/ActivityThread.java)
