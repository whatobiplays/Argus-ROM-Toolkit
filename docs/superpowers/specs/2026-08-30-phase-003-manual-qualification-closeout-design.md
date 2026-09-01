# Phase 003 Manual Qualification Closeout Design

**Document ID:** IMPL-P03-MANUAL-CLOSEOUT-DESIGN
**Status:** Approved — Owner Execution Required
**Owner:** Daniel
**Date:** 2026-08-30
**Phase:** PHASE-003
**Related:** PHASE-003, SPEC-X-001, IMPL-P03-MANUAL-QUALIFICATION

## 1. Purpose and authority

This design defines the owner-executed manual qualification gate required to
close Phase 003 after the automated and native qualification work is complete.
It turns the approved product expectations into a bounded, repeatable written
record without changing production architecture or creating another
implementation slice.

P03-001 through P03-009 remain the complete Phase 003 implementation sequence.
The manual gate is closeout evidence, not P03-010. Existing automated, native,
live-provider, and scale evidence in
`docs/implementation/library-capability-qualification.md` remains historical
P03-009 authority and is not rewritten by this design or its ledger.

Only direct observation by the owner can produce manual evidence. Automated
tests, native qualification runners, provider responses, existing documents,
or an expected product behavior cannot be converted into a manual PASS.

## 2. Completion model

The phase remains `In Progress` until the owner has executed every applicable
mandatory scenario in the companion ledger and recorded `PASS` for each one.
Any `FAIL`, `BLOCKED`, or `NOT RUN` mandatory scenario prevents closeout.

The result vocabulary is intentionally closed:

| Result | Meaning |
| --- | --- |
| `PASS` | The owner directly observed the complete expected behavior and recorded structured written evidence. |
| `FAIL` | The owner executed the scenario and directly observed a product defect or unmet expectation. |
| `BLOCKED` | A required prerequisite or environment condition prevented execution or made the result unreliable. |
| `NOT RUN` | The scenario has not been executed and has no owner-observed result. |

`NOT APPLICABLE` is never a result. It is permitted only in the
`Applicability` field of UX-M05 when no shipping Phase 003 surface contains
Argus-authored animation and a concrete reason is recorded. A conditional
scenario that is applicable but not executed remains `NOT RUN` and blocks
closeout. AND-06 is mandatory; if the selected physical device cannot
exercise its genuine supported temporary-storage-unavailability condition, it
is `BLOCKED`, not `NOT APPLICABLE`.

## 3. Required qualification environment

Manual qualification uses the following fixed environment policy:

| Dimension | Required decision | Recording rule |
| --- | --- | --- |
| Artifact | Release/production artifact only | Record release identity and bounded build provenance; debug artifacts do not satisfy the gate. |
| Application state | Fresh application state | Record a fresh-state confirmation without committing private database paths or user data. |
| macOS | Supported macOS release artifact | Execute the primary macOS journey and the full provider workflow. |
| Android | Physical supported ARM64 Android device | Execute the primary Android journey and Android-specific provider smoke; emulators do not satisfy this manual gate. |
| Content | Risk-based representative matrix | Use a mixture of real user-owned content and safe synthetic or repository fixtures; record only sanitized content classes/fixture labels. |
| Evidence | Structured written evidence only | Do not commit screenshots, recordings, ROM/BIOS bytes, titles, filenames, hashes, paths, credentials, or auth headers. |

Each execution records, at minimum, the operator, UTC timestamp, artifact
release/build identity, platform, OS, device/API/ABI where applicable,
fresh-state confirmation, sanitized content/fixture class, provider readiness
state, scenario ID, expected behavior, actual observation, result, and any
retest reference. Secrets and identifying local details remain external to the
repository.

## 4. Journeys and focused probes

The ledger separates canonical journeys from focused probes so a passing
journey cannot conceal a missing accessibility, content, recovery, or provider
check.

### 4.1 macOS primary journey

1. `MAC-01` — fresh release-build onboarding, real library-root admission,
   initial scan/identification, and a populated Library.
2. `MAC-02` — Library browsing/paging/search, representative
   filters/facets/sorting, stable selection, and game detail.
3. `MAC-03` — the full Playmatch/GameTDB/SteamGridDB workflow, including
   credential setup, metadata hydration, artwork discovery/download/display,
   provider disable/re-enable, credential removal/replacement, and recovery.
4. `MAC-04` — full quit/relaunch persistence for onboarding, roots, committed
   Library state, metadata, and artwork, with no significant work silently
   started.
5. `MAC-05` — termination during active refresh, truthful interrupted-work
   state after relaunch, no silent resume, preserved committed results, and a
   successful explicit retry.

### 4.2 Android primary journey

1. `AND-01` — cleared-data physical ARM64 release onboarding, native folder
   selection, Add & Scan, and a populated Library.
2. `AND-02` — Library browse/search/filter/sort/game-detail critical path.
3. `AND-03` — provider readiness/configuration, production credential storage,
   one real refresh/hydration path, and metadata/artwork presentation; the
   full macOS provider matrix is not duplicated.
4. `AND-04` — background/foreground lifecycle with one authoritative
   runtime/job state.
5. `AND-05` — process termination/relaunch persistence plus active-refresh
   interruption, no silent resume, and explicit retry.
6. `AND-06` — temporary configured source/media unavailability followed by
   reconnection/recovery without false destructive authority. This is
   mandatory; an unsupported device condition is `BLOCKED`, not
   `NOT APPLICABLE`.

### 4.3 Focused content probes

The owner selects representative, redistributable or user-owned content before
execution and records only sanitized labels. The stable probes are:

1. `CNT-01` — native cartridge.
2. `CNT-02` — native optical image.
3. `CNT-03` — descriptor plus dependent tracks (CUE/BIN-style).
4. `CNT-04` — multi-disc/playlist grouping.
5. `CNT-05` — ordinary ZIP or 7z single-game archive.
6. `CNT-06` — CHD.
7. `CNT-07` — at least one RVZ, CSO, or WBFS representation.
8. `CNT-08` — two supported equivalent representations converge without
   duplicate logical games.
9. `CNT-09` — identified content with no provider match remains visible with
   bounded fallback presentation.
10. `CNT-10` — successful provider metadata plus artwork hydration remains
    coherent in Library/detail.
11. `CNT-11` — temporarily unavailable content/source recovers without false
    orphan/destructive behavior.
12. `CNT-12` — intentionally malformed or unsupported safe fixture produces a
    bounded understandable failure without corrupting unrelated Library state.

The manual matrix is risk-based and representative. It does not replace the
full automated identity matrix or rewrite its historical evidence.

### 4.4 Focused UX and accessibility probes

1. `UX-M01` — macOS keyboard-only critical path, logical focus, and no focus
   trap.
2. `UX-M02` — macOS VoiceOver smoke across onboarding, Library, search/filter,
   game detail, provider configuration, and Jobs.
3. `UX-M03` — representative Compact, Medium, Expanded, and Large macOS
   layouts.
4. `UX-M04` — 200% macOS text scaling without clipped or unreachable essential
   controls.
5. `UX-M05` — reduced/disabled animation where a shipping Phase 003 surface
   contains Argus-authored animation. This is the only conditional scenario;
   if none exists, `Applicability` may be `NOT APPLICABLE` with a concrete
   reason while `Status` remains `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN`.
6. `UX-A01` — Android TalkBack critical Library/detail flow.
7. `UX-A02` — Android touch-target usability on critical actions.
8. `UX-A03` — Android font/display scaling without clipped or unreachable
   essential controls.

### 4.5 Independent rows and recovery coverage

The companion ledger retains one independent row for every stable ID above,
with separate `Applicability`, `Expected result`, `Status`, `Actual
observation`, and `Defect/retest reference` fields. A single observed event may
satisfy multiple rows only when it genuinely satisfies each row's preconditions
and expected result; each row retains its own status and cross-reference.

The macOS and Android journey rows cover their respective restart and
interrupted-refresh expectations. CNT-11 and AND-06 cover temporary
content/source or configured-media unavailability and recovery. The focused UX
rows cover keyboard/focus, VoiceOver, TalkBack, layout, scaling, animation,
and touch-target behavior without being collapsed into a generic accessibility
check.

## 5. Evidence and retest rules

The companion ledger is the authoritative manual record. Its scenario rows
contain stable IDs, independent applicability, procedure, expected result,
status, actual observation, evidence reference, defect/retest reference, and
latest retest reference. Its run provenance section identifies the environment
without storing private data.

Evidence is written as concise, structured observations. A manual result is
not valid merely because a command exited successfully or a screen appeared
once; the owner must state what was observed against the scenario expectation.

Retests are append-only. A retest adds a new row containing a retest ID,
scenario ID, UTC timestamp, trigger, environment/provenance reference,
expected behavior, actual observation, result, and evidence reference. The
prior attempt is never overwritten. The scenario ledger may point to the
latest retest while retaining the complete attempt history.

## 6. Schema-8 compatibility decision

The minimum supported state for an existing production database is schema 8.
An existing production database is eligible for normal forward migration only
when its validated migration history ends at schema 8 or later. A validated
production history ending at schema 1–7 is an unsupported pre-Phase-003
development install and fails closed before pending migrations, without silent
recreation or destructive repair.

A genuinely fresh production database has no migration history and remains
supported. It bootstraps through the complete immutable embedded migration
registry beginning at migration 1. Released migration SQL and checksum/history
validation remain unchanged.

This floor belongs to the production embedded registry and normal production
database-open path. Arbitrary `MigrationRegistry` instances and
`open_with_registry(...)` test/custom registries retain their independent
version semantics unless a caller explicitly configures a floor.

The startup failure continues to use the existing incompatible-schema
classification. No separate public below-floor error vocabulary is introduced.

## 7. Closeout boundary

This preparation task does not execute any manual scenario, create human
evidence, or change the phase to `Complete`. The owner closes the phase only
after updating the ledger with direct observations, resolving all applicable
mandatory rows to `PASS`, and completing the governed phase review.
