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
