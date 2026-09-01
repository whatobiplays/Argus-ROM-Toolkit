# Phase 003 Manual Qualification Record

**Document ID:** IMPL-P03-MANUAL-QUALIFICATION
**Phase:** PHASE-003
**Owner:** Daniel
**Record state:** Owner execution pending
**Last Updated:** 2026-08-30

Qualification result: BLOCKED
Completion declaration: NOT COMPLETE
Phase status: In Progress

## 1. Purpose and completion rule

This record is the owner-executed closeout ledger for the Phase 003 manual qualification gate. It records direct observations made against a release or production artifact on the supported desktop and Android environments. Automated test output, inferred behavior, and historical evidence do not substitute for a manual observation in this record.

The phase cannot be declared complete until every applicable mandatory scenario below has a recorded `PASS`, with the environment, artifact, content, and evidence provenance needed to reproduce the observation. `NOT APPLICABLE` is permitted only as a predeclared applicability value for UX-M05, with a concrete reason; it is not a result status. No current scenario has been executed in this record.

The historical library-capability qualification record remains unchanged. This document is a new closeout record and does not rewrite historical P03-009 evidence.

## 2. Required qualification context

Manual execution requires the following context to be recorded before evidence can be accepted:

| Context | Required value or evidence |
| --- | --- |
| Artifact | Release or production artifact identifier, build/version, and platform |
| macOS | Supported macOS version and hardware identifier class |
| Android | Physical supported ARM64 device, Android version, and ABI |
| App state | Cleared/fresh state for first-run scenarios; explicit restart or interrupted-work state for recovery scenarios |
| Content | Representative native, optical, descriptor/track, multi-disc, archive, compressed, equivalent, unmatched, unavailable, and malformed/unsupported fixtures as applicable |
| Observation | Direct owner observation with UTC timestamp and concise actual result |
| Evidence | Non-sensitive evidence reference; do not store private ROMs, filesystem paths, hashes, credentials, screenshots, or recordings in the repository |

## 3. Result semantics

| Value | Meaning |
| --- | --- |
| `PASS` | The owner directly observed the complete scenario and every expected result. |
| `FAIL` | The owner directly observed a deviation from the expected result. |
| `BLOCKED` | Execution was attempted or a required prerequisite was assessed and could not proceed because a required dependency or environment was unavailable. |
| `NOT RUN` | No owner observation has been recorded. |

`NOT APPLICABLE` is permitted only in the `Applicability` field for UX-M05 when no shipping Phase 003 surface contains Argus-authored animation and a concrete reason is recorded. It is not a result status; the `Status` field remains one of `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN`. AND-06 is mandatory and must be `BLOCKED`, not `NOT APPLICABLE`, when the selected physical device cannot exercise a genuine supported temporary-storage-unavailability condition.

## 4. Scenario ledger

All scenarios below initially remain `NOT RUN`. Each row keeps independent applicability, expected result, status, actual observation, evidence, and defect/retest reference fields. The actual-observation and reference fields intentionally contain no inferred result.

| ID | Applicability | Procedure | Expected result | Status | Actual observation | Evidence reference | Defect/retest reference | Latest retest |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MAC-01 | REQUIRED | On a fresh supported macOS release build, complete onboarding, admit a real library root, run the initial scan and identification, and inspect the populated Library. | Onboarding and library-root admission complete; initial scan/identification produces a usable populated Library with truthful progress and no unexplained loss or error. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| MAC-02 | REQUIRED | On macOS, exercise Library browsing, paging, search, representative filters/facets, sorting, stable selection, and game detail. | Paging, search, filters/facets, and sorting show the correct records; selection remains stable and opens the corresponding game detail without stale or misleading state. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| MAC-03 | REQUIRED | Complete the full Playmatch, GameTDB, and SteamGridDB workflow, including credential setup, metadata hydration, artwork discovery/download/display, provider disable/re-enable, credential removal/replacement, and recovery. | Each provider workflow reaches the configured readiness state; metadata and artwork hydrate and display coherently; disable/re-enable, credential removal/replacement, failures, and recovery are explicit, bounded, and do not expose secrets or corrupt unrelated Library state. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| MAC-04 | REQUIRED | Complete onboarding, configure roots, and establish committed Library state on macOS; fully quit and relaunch the app. | Onboarding state, roots, committed Library records, metadata, and artwork persist across relaunch, and no significant scan/provider work starts silently. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| MAC-05 | REQUIRED | Terminate the macOS app during an active refresh, relaunch it, inspect the interrupted-work state, and perform an explicit retry. | Relaunch reports the interrupted work truthfully, does not silently resume it, preserves committed results, and completes a successful explicit retry without destructive mutation. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| AND-01 | REQUIRED | On cleared data on a physical supported ARM64 Android device, use the release artifact, complete onboarding with native folder selection, choose Add & Scan, and inspect the populated Library. | Cleared-data onboarding and native folder selection complete; Add & Scan produces a usable populated Library with truthful progress and no unexplained loss or error. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| AND-02 | REQUIRED | On Android, exercise the Library browse, search, filter, sort, and game-detail critical path. | Browse, search, filter, and sort show the correct records; selection opens the corresponding game detail and remains usable through the critical path. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| AND-03 | REQUIRED | On Android, verify provider readiness/configuration, production credential storage, one real refresh or hydration path, and metadata/artwork presentation. Do not duplicate the full macOS provider matrix. | Provider readiness and configuration are bounded; the production credential boundary does not expose secrets; one real refresh/hydration path presents coherent metadata and artwork and recovers from an actionable failure. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| AND-04 | REQUIRED | Exercise Android background/foreground lifecycle during relevant Library or job activity and inspect the runtime and job state after each transition. | Background/foreground transitions preserve one authoritative runtime/job state, communicate progress or interruption truthfully, and do not duplicate or silently lose work. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| AND-05 | REQUIRED | Terminate and relaunch the Android process after committed work and during an active refresh; inspect persistence and interrupted-work handling, then perform an explicit retry. | Committed state persists; active work is reported truthfully after relaunch; work does not silently resume; preserved results remain intact; explicit retry succeeds without destructive mutation. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| AND-06 | REQUIRED | Make a configured source or media location temporarily unavailable on the physical Android device, observe the Library and job state, reconnect or restore it, and exercise recovery. | Temporary unavailability is reported without false orphaning or destructive authority; committed records remain intact and recover after reconnection. If the device cannot exercise a genuine supported condition, record `BLOCKED`, not `NOT APPLICABLE`. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-01 | REQUIRED | Exercise a native cartridge fixture through import, identification, Library presentation, and the available action path. | The native cartridge is identified and presented coherently; the logical game remains stable through the action path and failures are bounded and non-destructive. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-02 | REQUIRED | Exercise a native optical-image fixture through import, identification, grouping, Library presentation, and the available action path. | The native optical image is admitted and identified according to the supported model, with coherent grouping and no fabricated or destructive result. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-03 | REQUIRED | Exercise a descriptor plus dependent tracks fixture, such as a CUE/BIN-style set, through admission, grouping, identification, and Library presentation. | The descriptor and dependent tracks are treated as one supported content unit, identified coherently, and do not appear as unrelated duplicate games or mutate unrelated records. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-04 | REQUIRED | Exercise multi-disc or playlist content and inspect grouping, ordering, selection, and game-detail presentation. | Discs or playlist members are grouped and ordered as supported; the logical game remains selectable and no duplicate or fabricated identities are created. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-05 | REQUIRED | Exercise an ordinary ZIP or 7z single-game archive through admission, extraction/identification, and Library presentation. | A supported single-game archive follows the documented path and produces one coherent logical game; any bounded failure is understandable and non-destructive. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-06 | REQUIRED | Exercise a CHD representation through admission, identification, and Library/detail presentation. | The CHD representation is handled according to the supported path and produces a coherent, stable logical game without unrelated mutation. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-07 | REQUIRED | Exercise at least one RVZ, CSO, or WBFS representation through admission, identification, and Library/detail presentation. | The selected supported representation is handled according to the documented path and produces a coherent, stable logical game with bounded failure behavior. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-08 | REQUIRED | Exercise two supported equivalent representations of the same logical game and compare their Library results. | Equivalent representations converge to one logical game without duplicate Library entries, while each source remains attributable and unrelated records remain unchanged. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-09 | REQUIRED | Exercise identified content for which no provider match is available and inspect Library and game-detail presentation. | The identified content remains visible with a bounded, understandable fallback presentation and no fabricated provider identity. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-10 | REQUIRED | Exercise successful provider metadata and artwork hydration for identified content and inspect both Library and game detail. | Hydrated metadata and artwork remain coherent, attributable to the logical game, and consistently presented in Library and detail. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-11 | REQUIRED | Make configured content or its source temporarily unavailable, observe the resulting state, restore access, and run the supported recovery path. | Temporary unavailability does not create a false orphan or destructive authority; committed content remains visible or recoverable and returns coherently after restoration. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| CNT-12 | REQUIRED | Exercise an intentionally malformed or unsupported safe fixture and inspect the failure and unrelated Library state. | The fixture produces a bounded, understandable failure or rejection, with no corruption, fabricated identity, or destructive change to unrelated Library records. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-M01 | REQUIRED | On macOS, exercise the critical path with keyboard-only input, including onboarding, Library navigation, search/filter, game detail, provider configuration, and Jobs actions. | Logical focus is visible and ordered; all critical actions are keyboard reachable; no focus trap or pointer-only step blocks completion. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-M02 | REQUIRED | On macOS with VoiceOver enabled, smoke-test onboarding, Library, search/filter, game detail, provider configuration, and Jobs. | Labels, roles, focus movement, state changes, progress, errors, and recovery actions are announced coherently across the critical surfaces. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-M03 | REQUIRED | Inspect representative Compact, Medium, Expanded, and Large macOS layouts across the shipping Phase 003 surfaces. | Each representative layout preserves readable hierarchy, reachable controls, stable selection, and truthful state without overlap or hidden essential actions. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-M04 | REQUIRED | Set macOS text scaling to 200% and exercise the critical Phase 003 surfaces. | At 200% text scaling, essential text and controls remain readable, reachable, and unambiguous without clipping or overlap. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-M05 | CONDITIONAL — if no shipping Phase 003 surface contains Argus-authored animation, record `NOT APPLICABLE` here with a concrete reason; otherwise execute | On a shipping Phase 003 surface with Argus-authored animation, exercise reduced/disabled animation settings and inspect the affected flow. | Reduced or disabled animation is respected wherever the shipping Phase 003 surface provides Argus-authored animation; if none exists, the applicability field may be `NOT APPLICABLE` with a concrete reason and the status field remains a closed result status. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-A01 | REQUIRED | On Android with TalkBack enabled, exercise the critical Library and game-detail flow. | Labels, roles, focus movement, state changes, progress, errors, and recovery actions are announced coherently through the critical Library/detail flow. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-A02 | REQUIRED | On Android, exercise touch targets for critical onboarding, Library, search/filter, detail, provider, and Jobs actions. | Critical touch targets are reliably usable, appropriately sized and spaced, and do not require an error-prone precision gesture. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |
| UX-A03 | REQUIRED | Exercise Android font and display scaling across the critical Library and game-detail surfaces. | Essential text and controls remain readable, reachable, and unambiguous at the supported scaling settings without clipping or overlap. | NOT RUN | NOT RUN — no owner observation recorded | NOT RECORDED | NOT RECORDED | — |

## 5. Retest history

Retests are append-only. A retest must identify the scenario, trigger, complete environment and artifact provenance, expected behavior, direct actual observation, result, non-sensitive evidence reference, and any defect reference. A retest does not overwrite an earlier observation or convert automated output into manual evidence.

No retests recorded.

| Retest ID | Scenario ID | Recorded UTC | Trigger | Environment/provenance reference | Expected | Actual observation | Result | Evidence reference | Defect reference |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## 6. Closeout conditions

- [ ] Release or production artifact provenance recorded.
- [ ] Fresh or cleared-state provenance recorded for first-run scenarios.
- [ ] MAC-01 through MAC-05 directly observed and recorded.
- [ ] AND-01 through AND-06 directly observed and recorded on a physical supported ARM64 device; AND-06 is `BLOCKED` if its genuine supported temporary-unavailability condition cannot be exercised, never `NOT APPLICABLE`.
- [ ] CNT-01 through CNT-12 directly observed and recorded.
- [ ] UX-M01 through UX-M04 and UX-A01 through UX-A03 directly observed and recorded.
- [ ] UX-M05 has either a direct result or a predeclared `NOT APPLICABLE` applicability value with a concrete reason.
- [ ] Every applicable mandatory scenario has direct evidence and status `PASS`.
- [ ] Phase status is updated only after the owner verifies the complete applicable ledger.

Manual qualification has not been executed by this record. The current owner action is to perform the scenarios against the required release/production environments and append direct observations; until then, the qualification result remains `BLOCKED` and the completion declaration remains `NOT COMPLETE`.

## 7. Evidence handling

Store only concise, non-sensitive references in this repository. Do not add private ROMs, filesystem paths, content hashes, credentials, screenshots, recordings, or other machine- or user-identifying artifacts. Evidence references should point to an approved external location or a sanitized human-readable note without embedding protected data.
