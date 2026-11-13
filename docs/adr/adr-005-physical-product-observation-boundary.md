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
