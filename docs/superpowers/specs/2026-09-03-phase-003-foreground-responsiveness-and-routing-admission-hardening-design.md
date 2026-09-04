# Phase 003 Foreground Responsiveness and Routing Admission Hardening Design

**Date:** 2026-09-03  
**Phase:** PHASE-003  
**Implementation slice:** P03-010  
**Status:** Approved Design  
**Owner:** Daniel

## 1. Purpose

P03-010 corrects two coupled defects exposed by owner-observed Phase 003 qualification with a real macOS Library:

1. an admitted Phase 003 background refresh can retain the shared `KernelBootstrap` lifecycle mutex across long-running identification/enrichment/provider and related Phase 003 execution, starving foreground queries and making the application appear hung; and
2. GoRouter currently performs an authoritative onboarding API read inside redirect evaluation, so shell navigation is coupled to backend latency and directly violates SPEC-FE-004 redirect-purity rules.

The correction preserves the existing product and runtime architecture. It does not introduce a second runtime, database authority, scheduler, job state machine, onboarding authority, or provider orchestration layer.

The required user-visible outcome is simple: once the application shell is ready, active Library work may continue in the background without preventing the user from switching destinations, reading Library/Sources/Jobs/Settings state, or controlling jobs.

## 2. Observed Failure

The qualifying macOS run successfully completed onboarding, admitted the initial `library_refresh`, and eventually rendered the populated Library. Before the refresh released its long-running critical section, however:

- Library remained on its initial loading spinner;
- Library/Sources/Jobs/Settings destinations showed pointer interaction but did not navigate;
- job completion/progress was not observable through normal foreground queries;
- the UI became responsive only after background processing advanced far enough to release the shared kernel mutex.

This distinguishes the defect from a permanently wedged scanner. The background work can make progress and ultimately complete, while foreground request starvation makes the application temporarily unusable.

## 3. Root Cause

### 3.1 Runtime starvation

`ApplicationRuntime` owns the active `KernelBootstrap` behind a shared lifecycle handle. Phase 003 background handlers currently retain that handle as an execution dependency and call long-running work through a helper that holds the mutex for the entire closure.

The affected execution paths include:

- `library_refresh` committed-root identification/enrichment;
- `game_refresh` focused provider/enrichment work;
- `library_resolution_refresh` local re-resolution work.

The `library_refresh` path is the highest-impact case because the critical section may include parsing, identification, grouping, synchronous provider requests, metadata/artwork work, and multiple persisted checkpoints for a real root.

Foreground reads such as Library queries, Jobs queries, onboarding state, Sources/root queries, and other focused APIs require access through the same lifecycle handle. They therefore wait behind unrelated background execution.

The mutex is not itself the defect. The defect is ownership: a runtime-lifecycle guard spans work whose lifetime is intentionally independent and potentially long-running.

### 3.2 Router I/O

Before this correction, `app_router.dart` executed `client.onboarding.getState()` inside GoRouter redirect evaluation.

This contradicts the existing SPEC-FE-004 contract, which already requires:

- one narrow app-owned presentation-readiness projection;
- pure routing policy;
- no focused API calls from redirects;
- deterministic, convergent redirect behavior.

Because that redirect awaited backend I/O, even a correct shell destination callback could appear inert whenever the onboarding query was delayed by runtime contention or other backend latency.

## 4. Design Goals

P03-010 must:

1. keep foreground interaction responsive while Phase 003 background work is active;
2. remove long-running background execution from the `KernelBootstrap` lifecycle mutex boundary;
3. preserve one authoritative runtime, `BackgroundOperationManager`, SQLite authority, job lifecycle, cancellation model, and event channel;
4. preserve current Phase 003 refresh semantics, provider policy, durable checkpoints, retry/recovery semantics, and bridge DTOs unless a narrowly justified contract addition becomes unavoidable;
5. make GoRouter redirect evaluation synchronous and free of focused API/native calls;
6. preserve backend-authoritative onboarding completion without introducing a Flutter-persisted completion flag;
7. add deterministic concurrency and routing regressions that reproduce the observed failure without sleeps or live networking;
8. keep the manual closeout gate after P03-010 and require a direct retest of the failure mode.

## 5. Non-Goals

P03-010 does not add or change:

- persistence schema or migrations;
- provider timeout values or retry policy;
- provider roster or provider-specific behavior;
- generic background priorities;
- a new scheduler or worker runtime;
- a second Rust runtime or SQLite connection authority;
- a Flutter workaround that merely hides loading indicators;
- polling-based navigation or Jobs state;
- broad router architecture beyond the required onboarding/readiness projection correction;
- unrelated Library performance optimizations;
- new Phase 003 product features.

## 6. Chosen Runtime Design

### 6.1 Capability-detached background execution

The selected approach is to detach Phase 003 background execution from the runtime lifecycle mutex.

During command admission/registration, the runtime may acquire the kernel lifecycle handle briefly to validate the current generation and construct or clone the bounded execution capabilities needed by the admitted operation. The background handler then owns those execution capabilities directly and executes without retaining `Arc<Mutex<Option<KernelBootstrap>>>` as an operational dependency.

Conceptually:

```text
ApplicationRuntime
    |
    | short lifecycle lock during admission
    v
KernelBootstrap
    |
    +--> build/clone operation execution capabilities
            |
            +-- UnitOfWorkFactory
            +-- event/publication sink
            +-- immutable identity/transformation policy
            +-- enrichment/provider-session construction
            +-- metadata/artwork/grouping execution capabilities
            +-- required app-private storage handles
            |
            v
      BackgroundOperationHandler
      owns independent execution context
```

The exact private Rust type decomposition is an implementation decision, but the ownership invariant is normative: background work must not need to reacquire and hold the lifecycle mutex merely to execute ordinary Phase 003 business work.

### 6.2 Scope of detachment

The correction applies consistently to:

- `LibraryRefreshOperationHandler`;
- `Phase003RefreshHandler` game-refresh execution;
- `Phase003RefreshHandler` library-resolution execution.

Standalone Phase 001 scan execution already follows a more appropriate capability-owned model and should not be unnecessarily restructured.

### 6.3 Allowed lifecycle-lock usage

A short lifecycle lock remains valid for operations such as:

- validating that the request targets the active runtime generation;
- reading the current kernel instance during admission;
- cloning immutable/owned operation capabilities;
- shutdown/runtime-replacement coordination that genuinely belongs to runtime lifecycle.

The lifecycle lock must not span:

- filesystem traversal or source reads;
- hashing/canonicalization/parsing/transformation;
- provider network requests or provider retry waits;
- identification/grouping loops;
- metadata/artwork hydration loops;
- per-game or per-root long-running work;
- sleeps, waits, or bounded external I/O;
- whole-job persistence/checkpoint sequences.

### 6.4 Why not split locks around individual substeps

An alternative would preserve the current handler/kernel coupling and manually release/reacquire the mutex around expensive substeps. This is rejected because it makes mutex correctness a distributed concern across orchestration code. Future provider/parser changes could silently reintroduce starvation by moving expensive work inside one guarded closure.

The chosen capability-owned boundary makes the safe behavior structural rather than conventional.

### 6.5 Why not replace `Mutex` with `RwLock`

This is rejected because synchronization primitive choice does not correct the ownership problem. Long-running background operations include writes and mutable coordination, and a reader/writer lock would still permit foreground starvation or create false confidence around unsafe critical-section duration.

## 7. Runtime Invariants

After P03-010:

1. `ApplicationRuntime` remains the sole runtime-generation authority.
2. `BackgroundOperationManager` remains the sole top-level background admission/resource/job execution authority.
3. `JobRun` durability, progress, cancellation, retry, recovery, and terminalization semantics remain unchanged.
4. SQLite repositories/unit-of-work remain the single persistence authority.
5. Background operation handlers may own cloneable execution capabilities but do not own or create a second kernel/runtime.
6. Queries may execute concurrently with logically unrelated background work, subject to the existing persistence/resource boundaries.
7. Persistence serialization or short repository-level locking is permitted; starvation caused by holding the runtime lifecycle mutex across whole background stages is not.
8. Cancellation must remain observable while background enrichment is blocked at a deterministic test seam.
9. Shutdown/runtime replacement must still safely invalidate or stop admitted work according to existing BE-004 lifecycle policy.
10. No background handler may obtain correctness by holding a runtime-generation mutex for the duration of its business operation.

## 8. Chosen Routing Design

### 8.1 Routing-safe onboarding projection

The router will consume a narrow app-owned readiness/onboarding projection instead of querying `LibraryOnboardingApi` from `redirect`.

Conceptually:

```text
backend/runtime readiness
+
appearance authority
+
authoritative LibraryOnboardingState
        |
        v
app-owned presentation/readiness projection
        |
        v
pure synchronous routing policy
```

The projection may represent states equivalent to:

```text
preReady
appearanceInitializing
appearanceUnavailable
onboardingInitializing
onboardingUnavailable
onboardingRequired
ready
```

Exact names and type placement should follow existing Riverpod/app-bootstrap conventions.

### 8.2 Authority model

The projection is not a second onboarding authority.

It must:

- hydrate from `LibraryOnboardingApi.getState()` only after the current runtime generation is ready and appearance authority permits product-onboarding evaluation;
- be invalidated/re-hydrated when the root `ArgusClient` or runtime generation changes;
- publish only routing-safe readiness/completion state;
- never persist an independent Flutter completion flag;
- never infer completion from URI, selected destination, root count, or presence of Library rows.

When `completeAndRefresh()` returns an authoritative `LibraryOnboardingState`, the app-owned onboarding projection should consume that returned state so routing can observe committed completion immediately, without issuing another redirect-time native query.

Other onboarding mutations continue to reconcile through the owning onboarding UI/controller/API path and authoritative reads as required by FE-010.

### 8.3 Router behavior

`GoRouter.redirect` becomes synchronous routing policy over requested location plus the routing-safe projection.

It must perform no:

- `await`;
- `ArgusClient` focused API read;
- FRB/native call;
- controller mutation;
- persistence;
- dialog/snackbar side effect.

Router refresh is driven by changes to the app-owned readiness projection through the existing notifier/listenable mechanism or an equivalent app-owned adapter.

### 8.4 Route-intent preservation

The correction must preserve FE-004 route-intent rules:

- an incomplete required onboarding gate cannot be bypassed;
- a ready destination requested before onboarding completion remains a frontend route intent, not backend state;
- after onboarding commits, valid preserved intent is revalidated and may activate;
- onboarding/recovery surfaces do not pollute normal shell history;
- later backend latency or an active background refresh must not prevent switching among already-admitted ready-shell destinations.

## 9. Foreground Presentation Behavior

The existing frontend architecture rule remains authoritative:

> Once startup completes, background work must never block unrelated interaction or replace already usable content with a global loading state.

P03-010 strengthens this for initial post-onboarding Library entry:

- the first Library query must be able to complete while the admitted initial `library_refresh` remains active;
- if no rows have committed yet, Library may truthfully render its normal empty/loading presentation for that focused query, but it must not wait on the whole background job merely because the runtime lifecycle mutex is occupied;
- once usable rows exist, background refresh/reconciliation uses explicit operational state and incremental invalidation rather than reverting the screen to a whole-page blocking spinner;
- Sources, Jobs, and Settings remain navigable during active refresh;
- Jobs remains queryable/control-capable so cancellation and status are available while provider/enrichment work continues.

No new optimistic Library data authority is introduced.

## 10. Failure and Cancellation Semantics

Detaching execution capabilities must not weaken existing failure semantics.

Required behavior remains:

- provider/content failures are isolated as narrowly as existing Phase 003 contracts require;
- committed coherent results survive later failures/cancellation;
- cancellation stops new downstream work at existing safe checkpoints;
- retry creates a new top-level operation according to existing contracts;
- process loss never silently resumes significant work;
- runtime shutdown/replacement invalidates or terminates background work through existing lifecycle policy;
- foreground query failure is reported as that query's typed failure and is not fabricated from background job state.

A background provider stall must not require holding the lifecycle mutex, and cancellation/query paths must remain able to execute while that stall is intentionally held open in tests.

## 11. Specification Amendments

P03-010 implementation begins by reconciling the existing owning documents. No new subsystem specification is required.

Required amendments:

### 11.1 PHASE-003

- add P03-010 after P03-009 and before manual closeout;
- define foreground responsiveness and pure routing admission as Phase 003 exit requirements;
- update manual-closeout wording so the gate follows P03-010 rather than P03-009;
- require owner retest of navigation/query responsiveness during an active refresh.

### 11.2 Phase 003 design

- add P03-010 to the ordered slice list;
- add lifecycle-lock ownership and redirect-purity invariants;
- record the observed failure mode and rejected lock-substitution alternatives.

### 11.3 SPEC-BE-004

Strengthen runtime/background-operation policy so runtime-generation/lifecycle locks are explicitly short-lived coordination boundaries. Long-running operation execution must use owned/cloneable capabilities and may not retain a runtime lifecycle guard across external I/O, parser/CPU loops, provider waits, or whole-job checkpoint sequences.

### 11.4 SPEC-BE-015

Amend composed refresh concurrency requirements so `library_refresh`, `game_refresh`, and `library_resolution_refresh` remain query/control responsive while running. Make foreground starvation a contract failure, not merely a performance concern.

### 11.5 SPEC-FE-004

The spec already prohibits focused API calls from redirects. Add explicit Phase 003 regression requirements proving the routing-safe onboarding projection is hydrated outside redirect evaluation and that shell destination switching remains synchronous with respect to routing policy during active backend work.

### 11.6 SPEC-FE-010

Clarify ownership and update rules for the routing-safe onboarding completion projection, including use of the authoritative state returned by `completeAndRefresh()`. Add the initial-refresh responsiveness and shell-navigation concurrency scenarios.

### 11.7 Manual qualification record

Record the owner-observed starvation/navigation failure and require an append-only retest after P03-010. Historical P03-009 evidence remains unchanged.

## 12. Deterministic Test Design

### 12.1 Runtime concurrency regression

Add a deterministic test seam that deliberately blocks Phase 003 enrichment/provider execution after the background job has started, without using real networking or timing sleeps.

While that blocker is held, prove that independent foreground operations return within a deterministic synchronization protocol:

- `list_games`;
- `get_library_facets` as applicable;
- `list_library_roots` / focused Sources reads;
- `list_jobs` and/or `get_job`;
- `library_onboarding_state`;
- cancellation request/control path.

Then release the blocker and prove the refresh reaches its correct terminal state.

The test must fail against the current lifecycle-lock implementation for the actual reason being corrected, not by introducing an artificial unrelated lock.

### 12.2 Game and resolution refresh regression

Equivalent deterministic coverage must prove `game_refresh` and `library_resolution_refresh` do not hold the runtime lifecycle mutex across their long-running execution loops.

The tests may share one test-owned blocking execution seam where doing so preserves clear failure attribution.

### 12.3 Routing purity tests

Tests must prove:

- router redirect evaluation performs no onboarding/focused API call;
- onboarding-initializing/incomplete/complete projection states produce deterministic convergent redirects;
- completion state returned from the authoritative onboarding command permits routing without an extra redirect-time query;
- runtime/client replacement invalidates old projection state and rehydrates against the new authority.

No routing test relies on arbitrary delays.

### 12.4 Active-refresh shell navigation

Flutter/widget/integration coverage must simulate an active deliberately blocked refresh and prove:

```text
Library -> Sources
Sources -> Jobs
Jobs -> Settings
Settings -> Library
```

remains navigable while the background blocker is still held.

Where controllers need backend reads, use deterministic fakes or the native concurrency seam appropriate to the layer under test. The test must distinguish routing responsiveness from feature-query completion.

### 12.5 Presentation regression

Prove that a usable Library does not revert to whole-page loading due only to a background reconciliation demand, preserving the existing FE-010/controller operational-state model.

## 13. Qualification

P03-010 is not complete from unit tests alone.

Required evidence includes:

1. deterministic Rust runtime concurrency tests;
2. deterministic Flutter routing/controller/widget tests;
3. full repository validation through the normal Phase 003 gate;
4. desktop native qualification exercising a deliberately active refresh while foreground queries/navigation remain usable;
5. applicable Android/native regression coverage preserving Phase 002/003 lifecycle guarantees;
6. owner-observed macOS retest using a representative real Library, recording that shell navigation and Jobs/Library queries remain responsive while initial refresh continues.

The owner retest may observe normal provider/network duration. It must not require the refresh to finish before navigation becomes usable.

## 14. Compatibility and Preservation Requirements

Implementation must preserve:

- current bridge/public DTO shapes unless a proven contract gap requires a narrowly scoped addition;
- Phase 001 source/scan semantics;
- Phase 002 Android foreground-hosting and single-runtime rules;
- Phase 003 `LibraryRefreshTrigger` durability;
- root add -> onboarding completion -> initial refresh sequencing;
- current provider credential/security/redaction boundaries;
- event notification plus authoritative-query reconciliation;
- existing JobRun IDs, operation types, retry semantics, and progress vocabulary;
- current database schema and migrations;
- current macOS durable authorization/root-locator behavior;
- FE-010 progressive hydration and backend-owned paging/query semantics.

## 15. Rejected Alternatives

### 15.1 Tune provider timeouts

Rejected because it only changes how long the app is starved. A faster timeout does not make holding the runtime lifecycle mutex across provider I/O correct.

### 15.2 Poll Jobs or routing state harder

Rejected because foreground polling would itself queue behind the same mutex and adds load without correcting ownership.

### 15.3 Hide the Library spinner

Rejected because the problem is blocked authority/query access, not merely presentation.

### 15.4 Move provider work to another Dart isolate

Rejected because the contention is inside the Rust runtime lifecycle boundary.

### 15.5 Replace `Mutex` with `RwLock`

Rejected because it does not structurally prevent long critical sections and cannot make provider/write work safely concurrent by itself.

### 15.6 Cache onboarding completion only in Flutter

Rejected because that creates a second authority, fails across runtime replacement, and contradicts query-authoritative onboarding.

## 16. Acceptance Criteria

P03-010 is complete only when all of the following are true:

1. Phase 003 background handlers do not retain the shared `KernelBootstrap` lifecycle mutex across long-running execution.
2. `library_refresh`, `game_refresh`, and `library_resolution_refresh` use owned execution capabilities rather than the kernel lifecycle handle as their business-execution dependency.
3. While deterministic refresh work is deliberately blocked, Library, Sources, Jobs, and onboarding foreground queries can still execute according to their normal focused API contracts.
4. Job cancellation/control remains available while Phase 003 provider/enrichment work is blocked.
5. Releasing the deterministic blocker allows the background operation to terminalize with existing durable semantics.
6. GoRouter redirect evaluation is synchronous and performs no focused API, FRB, or native call.
7. Routing consumes one app-owned routing-safe onboarding/readiness projection hydrated from backend authority outside redirect execution.
8. No Flutter-persisted or URI-inferred onboarding-completion authority is introduced.
9. The authoritative state returned from onboarding completion can update the routing projection without an extra redirect-time query.
10. Runtime/client replacement invalidates stale onboarding projection state and rehydrates from the new authoritative generation.
11. Shell destination switching remains responsive during an active Phase 003 refresh.
12. A previously usable Library is not replaced by whole-page loading solely because background refresh/reconciliation is active.
13. Existing persistence, provider, job, cancellation, recovery, Android foreground-hosting, and security semantics remain intact.
14. PHASE-003, the Phase 003 design, BE-004, BE-015, FE-004, FE-010, and manual qualification documentation are reconciled before implementation is declared complete.
15. Deterministic tests, native qualification, full repository validation, and owner-observed macOS retest pass.
16. Phase 003 manual closeout remains after P03-010 and cannot be marked complete until the new retest evidence is recorded.

## 17. Implementation Ordering

Implementation should proceed in this order:

1. amend the owning Phase 003/backend/frontend contracts;
2. add failing deterministic runtime starvation tests;
3. introduce the private capability-owned execution boundary and migrate `library_refresh`;
4. migrate `game_refresh` and `library_resolution_refresh` to the same invariant;
5. add the routing-safe onboarding/readiness projection and remove redirect-time backend I/O;
6. add routing/navigation/presentation regressions;
7. run deterministic and native validation;
8. update the manual qualification ledger with the required P03-010 retest slot;
9. perform owner-observed qualification before Phase 003 closeout.

## 18. Final Invariants

P03-010 is correct only if these statements remain true:

1. Background work is independent in lifetime but not independent in authority.
2. Runtime lifecycle synchronization coordinates generations; it does not serialize whole product workflows.
3. Foreground reads/control remain available during unrelated background execution.
4. Routing policy is pure and synchronous over app-owned routing-safe state.
5. Backend state remains authoritative for onboarding; Flutter projects it but does not replace it.
6. No workaround trades correctness for apparent responsiveness.
7. Phase 003 remains one coherent backend architecture across desktop and Android.
