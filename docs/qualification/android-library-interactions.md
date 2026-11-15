# Android Library interaction qualification boundary

This document describes the private host-side Issue #27 plan for one fresh
Android Qualification Release session. Host tests validate the plan, oracle
bindings, authorization boundaries, safe execution order, and fail-closed UI
observations. They do not run Android, establish game identity, or produce an
owner verdict.

## 1. Execution boundary

Issue #27 has a distinct private authorization profile, admission function,
one-use execution capability, and executor. The profile uses the shared strict
authorization reader and validator, then accepts only the exact 42-operation
sequence described below. The public and legacy authorization loader retains
its 32-operation parser limit and Issue #26 retains its exact 19-operation
plan and executor capability. The Issue #26 executor and public UI selector
allowlist cannot claim or run an Issue #27 session.

The plan reuses Issue #26's target, artifact, staging, scan-admission,
terminalization, append-only evidence, timeout, fail-fast, and cleanup
mechanisms. Admission validates all non-cleanup operation timeouts, the
separately authorized cleanup timeout, session and approval deadlines, cleanup
deadline, and cleanup reserve before it claims the one-use approval or
observes the target. A fresh fixture-only session is required. No production
transport or public live runner is added.

The private operation field `oracle_version` and the pinned oracle field `schema_version` identify the same Issue #27 contract revision. Both are currently revision 3; operation plans must use the string `"3"`, and the oracle must declare integer `3`. Legacy revision `"2"` is rejected.

## 2. Closed operation sequence

The sequence has 17 shared setup and scan-terminal operations, 24 independently
recorded Library cases, and one final cleanup operation:

1. Run the Issue #26 fresh install/reset decision, stage the approved fixture
   set, launch the qualification app, and complete the normal onboarding.
2. Open the fixture root, perform the one Add & Scan action, observe admission,
   follow the unique View Job route, and observe the parent job plus child scan
   to terminal state.
3. Navigate to Library and observe complete fixture membership.
4. Exercise exact, partial, empty, clear, and post-selection searches; platform,
   region, hydration, and availability filters plus filter reset; selection;
   title/platform sorting in both directions; Grid/List view; exact Game detail
   routing and detail state; and return to Library.
5. Remove the session-owned fixture set exactly once as the final operation,
   after scan terminalization and verified staging ownership.

Each of the 24 Library cases has an opaque, session-bound assertion alias. The
case order is pinned by the authorization plan and private oracle. Before
cleanup, every case receives one categorical outcome. When complete-membership
observation is blocked, that case is `BLOCKED` and the 23 dependent cases are
`NOT_RUN`; the executor does not run controls against a partial Library.

## 3. Private oracle and evidence

The version-3 private oracle digest binds the fixture manifest version and
digest, APK digest, operation-plan version and digest, acceptance-rule version
and digest, fixture display identities, and the independently specified
expectations for every case. Sorted cases contain ordered groups of fixture
ordinals; members of a tie group may appear in either internal order. The
oracle also records expected selection identity/state, retained query, stable
detail facts, and the private searchable identity fields used to prove a
no-match query. A selected fixture must belong to the initial selection case's
expected result set. It separately labels selection, query, ordering, complete
membership, and detail assertions unsupported by the pinned Release UI
contract. These stored expectations are not inferred from product state and do
not make unsupported assertions executable. Fixture title and platform matching
reuses the existing exact identity token validation. A pinned identity
reference remains `pinned_unverified` and does not become independent identity
evidence or qualification.

Shared append-only execution evidence contains only opaque assertion aliases,
approved provenance pins, and categorical outcomes. It does not contain raw
titles, search strings, accessibility XML, screenshots, private filesystem
paths, target serials, or credentials. The existing evidence schema remains
unchanged. The executor does not create a `RESULT.json`, owner verdict, or
qualification approval.

## 4. Library observation limits

Issue #27 applies an extra-Game classifier only in its private XML path; the
shared `parse_ui` and fixture matcher used by Issue #26 remain fixture-only. A
confirmed extra Game requires the source-shaped title/platform label, explicit
selected state, tap action, and long-press action. An unknown comma-labeled
control that lacks any part of this full signature is ambiguous and records
`BLOCKED`; invalid or missing geometry also records `BLOCKED`. A conclusively
observed extra card is a wrong product result and records `FAILED`. Duplicate
or ambiguous fixture identities remain `BLOCKED`; an absent row alone is not
treated as a product failure while the host cannot prove that all pages were
observed.

Identical `text` and `content-desc` values are one accessibility label for
Game-card classification. Distinct labels remain ambiguous unless each label
is separately explained by a pinned fixture identity or a supported selector.
This keeps the complete unexpected-Game signature eligible for `FAILED`
without widening classification to controls that have conflicting accessible
names.

The no-match search case uses a private nonempty query independently checked
against every available searchable identity for the approved fixtures: display
titles, alternate titles, and active fallback titles. If any required field is
not independently established, the case records searchable-projection
completeness as unsupported; display-title and platform checks alone cannot
establish a zero-result query. The existing separate clear operation uses an
empty query and independently expects fixture membership to return. Query text
and searchable identities remain private and are never copied to shared
evidence. Search clear is an existing authorized case and operation, so the
plan remains 42 operations with 24 case outcomes.

Matching every expected fixture row proves only that those expected labels were
visible in that observation. It does not prove complete membership or order.
Repeating the same last-row observation is not an exhaustion signal. An
additional backend page may exist without having been requested or displayed.

The pinned Release UI has no verified accessibility signal for both traversal
completion and backend-pagination exhaustion. Therefore unavailable
completeness proof returns `BLOCKED`, including after synthetic exact matches.
`BLOCKED` means the host lacks sufficient evidence to decide the assertion;
`FAILED` means an observed product outcome conclusively contradicts the pinned
expectation. No caller-supplied boolean or synthetic hierarchy can grant
completion proof. The executor stops dependent interaction assertions and
proceeds only to the existing cleanup path when terminal scan state, staging
ownership, and all 24 durable categorical case outcomes are confirmed.

The source UI implements a 300 millisecond search debounce, cancellation of
prior debounce timers, request-token checks for stale asynchronous responses,
loading and loading-more states, and backend-owned filtering and ordering. The
current qualification transport exposes only typed observations and taps for
the existing Add & Scan flow; it has no typed text replacement or Library
query-generation signal. The current parser also lacks selectors for dynamic
filter chips, a backend response tied to the visible search value, exact
selected-Game identity across refreshes, and detail GameId/load-state. Search
or repeated stable presentation alone cannot prove which backend request
produced the visible rows. Those assertions remain blocked until a separately
approved, source-grounded transport and accessibility contract can observe the
required facts. This implementation does not add ADB commands, invent
selectors, or broaden the legacy runner.

## 5. Failure and physical qualification status

No product mutation is retried after an uncertain result. The one Add & Scan
tap may be followed by read-only admission and terminal-state observations;
cleanup remains withheld while scan state is uncertain. Once the session has a
verified staging receipt and terminal scan state, and all 24 case outcomes have
been appended successfully, the one cleanup operation is attempted last. If a
case outcome append fails, cleanup is withheld and owner recovery must resolve
the session-owned fixture set. A cleanup failure or uncertain result remains
blocked and requires owner recovery.

This implementation is host-only. Files access and notification permission
remain unresolved for physical execution. No permission workaround, device
mutation, ROM access, install, reset, physical run, or owner verdict is part of
this work. Host tests and source inspection do not establish physical Android
qualification.

## 6. Inactive C5 backend-membership assertion

**Status:** Normative successor assertion, inactive. The existing 42 physical
operations, 24 UI outcomes, their order, deadlines, one-capture membership
rule, and dependency chain remain unchanged. `C5.backend-membership.complete`
is an assertion key, not a new physical operation or a twenty-fifth UI case.
This P assertion is eligible only under a separately versioned successor
oracle and session authorization. The current private oracle revision 3 marks
complete membership unsupported and does not pin a complete expected GameId
set; it does not authorize this assertion.

The assertion uses evidence class `P` and the observer-owned
RevisionFenced membership contract in
[SPEC-BE-015 §21.7](../specifications/backend/spec-be-015-game-library-grouping-and-enrichment-contract.md#217-inactive-observer-owned-membership-read).
It passes only when the fixed All-active query is read without search or
filters, in title-ascending order and the specified fixed page size; every
page is fetched from first through the single terminal page under the same
token, generation, revision, query fingerprint, and observation attempt; the
completed GameId set is unique; and every required direct `GetGame` lookup
uses that token. Each `Redirected` target must occur in the completed set.
No second redirect hop is followed. View tokens and cursors remain inside the
app, and pages cannot be joined across revisions or attempts.

The P read is eligible only after the existing Add & Scan flow reaches its
terminal scan state and before final fixture cleanup begins, while the
approved fixture set remains intact. No membership-mutating operation may
occur between scan terminalization and the P read. If the scan is not terminal,
the fixture set has changed, or cleanup has begun, classify the P assertion as
`BLOCKED`; do not compare that read with the final expected set.

A future execution requires a separately versioned C5 successor oracle and
approved fixture manifest. The successor oracle must pin the complete expected
GameId set and its mapping to fixture identities before the session; both
digests must be covered by the future session authorization. The current
revision-3 oracle and its expectations cannot be reused as that pin. The
expected set never comes from the observer response or UI capture.

| Assertion result | Classification |
| --- | --- |
| Complete coherent set matches the separately versioned and authorized expected GameId set, and every required direct lookup is valid | `PASSED` |
| Missing successor pin, nonterminal scan state, changed fixture baseline, or cleanup already begun | `BLOCKED` |
| Missing, stale, duplicate, incomplete, unauthorized, timed-out, or over-bound evidence; uncertain identity or revision | `BLOCKED` |
| A coherent authoritative read proves a wrong committed set or invalid required direct redirect | `FAILED` |

The separate P assertion does not establish that Library cards rendered,
filters or sorts behaved correctly, a selection persisted, a detail screen
opened, or navigation returned to Library. It cannot replace U evidence or
any H authorization/provenance. OS-owned claims still require their specified
O evidence. Conversely, a complete UI hierarchy cannot prove the backend's
committed GameId set or redirect relation.

The original UI `membership` outcome still requires the existing single
hierarchy capture to establish its complete visible page chain. The backend
result cannot fill a missing page or be combined with multiple UI captures.
If that UI case is `BLOCKED`, the existing 23 dependent UI cases remain
`NOT_RUN`. The P result does not change any of the original UI case outcomes
or their dependency propagation. C5 as a whole cannot pass unless the new P
assertion and every applicable existing UI, host, and OS assertion pass under
their own evidence rules.

| Existing C5 UI case | Existing U/H contract | Can P replace it? |
| --- | --- | --- |
| `membership` | Existing one-capture complete visible-membership assertion remains mandatory. | No. It has its own separate P assertion. |
| `search_exact` | Existing U/H criteria and outcome remain unchanged. | No. |
| `search_partial` | Existing U/H criteria and outcome remain unchanged. | No. |
| `search_empty` | Existing U/H criteria and outcome remain unchanged. | No. |
| `search_clear` | Existing U/H criteria and outcome remain unchanged. | No. |
| `filter_platform` | Existing U/H criteria and outcome remain unchanged. | No. |
| `filter_region` | Existing U/H criteria and outcome remain unchanged. | No. |
| `filter_hydration` | Existing U/H criteria and outcome remain unchanged. | No. |
| `filter_availability` | Existing U/H criteria and outcome remain unchanged. | No. |
| `filter_reset` | Existing U/H criteria and outcome remain unchanged. | No. |
| `selection` | Existing U/H criteria and outcome remain unchanged. | No. |
| `sort_title` | Existing U/H criteria and outcome remain unchanged. | No. |
| `sort_title_ascending` | Existing U/H criteria and outcome remain unchanged. | No. |
| `sort_title_descending` | Existing U/H criteria and outcome remain unchanged. | No. |
| `sort_platform` | Existing U/H criteria and outcome remain unchanged. | No. |
| `sort_platform_ascending` | Existing U/H criteria and outcome remain unchanged. | No. |
| `sort_platform_descending` | Existing U/H criteria and outcome remain unchanged. | No. |
| `view_list` | Existing U/H criteria and outcome remain unchanged. | No. |
| `view_grid` | Existing U/H criteria and outcome remain unchanged. | No. |
| `search_after_selection` | Existing U/H criteria and outcome remain unchanged. | No. |
| `detail_open` | Existing U/H criteria and outcome remain unchanged. | No. |
| `detail_observation` | Existing U/H criteria and outcome remain unchanged. | No. |
| `return_to_library` | Existing U/H criteria and outcome remain unchanged. | No. |
| `return_observation` | Existing U/H criteria and outcome remain unchanged. | No. |

The P assertion uses its own operation grant, attempt identity, observer
reference, and read interval under the inactive lifecycle protocol in
[android-job-lifecycle.md §11](android-job-lifecycle.md#11-inactive-versioned-product-observer-successor).
It is reported separately from the 42 physical-operation count and 24 UI
outcomes. B1, B2, G3, G4, and G5 remain separately gated as specified there.
