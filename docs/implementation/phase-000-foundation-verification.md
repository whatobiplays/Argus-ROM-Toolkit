# Phase 000 Foundation — Completion Verification

**Document ID:** IMPL-P00-009-VERIFICATION
**Owner:** Daniel
**Last Updated:** 2026-08-14
**Status:** Active verification record for SLICE-P00-009

## Purpose

This document records the reproducible verification procedure for completing
Phase 000. It distinguishes automated gates from manual milestone checks that
cannot yet be automated honestly, and it requires that every evidence slot is
filled only after the corresponding check has actually been executed.

## Automated Completion Gates

Run these commands from the repository root in the order shown. The native
gate is intentionally outside the platform-neutral gate.

| Command | What it proves |
| --- | --- |
| `just generate` | Regenerates all canonical FRB/Riverpod/Freezed output through the repository's generation commands. |
| `just check-generated` | Registered generated files are current and reproducible, no unexpected generated output exists, and no machine-local absolute path appears in generated FRB output. |
| `just check` | The platform-neutral quality gate passes: formatting, lint/static analysis (including shellcheck), Rust dependency architecture checks, and the full deterministic offline Rust/Flutter test suite. |
| `just test-phase-000-native` | The macOS native milestone passes: the real Rust bridge rebuilds with locked inputs; native bridge smoke, native startup-failure/recovery/diagnostics smoke, and the real two-process restart restoration proof all pass against one test-owned temporary data directory. |

`just check` does not include `just test-phase-000-native`. The native gate is
kept separate because it launches real macOS application processes and is not
part of the portable, deterministic, offline quality gate.

## What the Restart Restoration Proof Covers

`just test-phase-000-native` executes the canonical Phase 000 restart chain:

```text
seed process (process one)
  → real Settings shell on a fresh isolated data directory
  → authoritative System confirmed before mutation
  → Dark selected through the real Theme Mode control
  → authoritative backend read confirms Dark
  → normal native shutdown
verify process (process two, same data directory)
  → backend Ready
  → authoritative appearance read returns Dark
  → first normal-shell frame is Dark with no earlier normal shell
```

Seed and verify are two distinct `flutter test ... -d macos` invocations in
two distinct Flutter application processes; no in-memory state crosses the
process boundary. Persisted appearance authority remains Rust/SQLite.

## Manual Milestone Evidence Slots

The following Phase 000 requirements are not yet automated by this slice.
Each slot must be recorded as exactly one of `PASS`, `FAIL`, `NOT RUN`, or
`BLOCKED` when the check is executed. An unexecuted check is `NOT RUN`; it must
never be pre-marked as passing.

| Evidence slot | What to execute | Status |
| --- | --- | --- |
| Keyboard walkthrough | Keyboard-only traversal of startup, shell, Settings, Theme Mode selection, and recovery surfaces on the primary development platform. | NOT RUN |
| Screen-reader smoke | Screen-reader smoke test of the canonical Phase 000 surfaces on the primary development platform. | NOT RUN |
| Reviewed visual evidence | Selective visual/golden review where SPEC-FE-007 requires it, reviewed rather than auto-accepted. | NOT RUN |
| Large text/display scaling | 200% text-scaling and display-scaling checks on the essential Phase 000 surfaces where supported. | NOT RUN |
| Reduced/disabled animation | Verification that Argus-authored motion honors reduced/disabled-animation platform requests where supported. | NOT RUN |
| Clean checkout | Clean-checkout build and `just check` instructions executed from a fresh clone without prior local state. | NOT RUN |

## Evidence Integrity

Completion claims for Phase 000 are valid only when:

1. the automated gates above were actually executed and passed on the primary
   development platform;
2. every manual slot above reflects an executed check;
3. no screen-reader, visual-golden, accessibility-walkthrough, or
   clean-checkout claim is reported as passed without executed evidence;
4. retained diagnostic artifacts satisfy the documented sanitization contract,
   and sanitization evidence combines native diagnostic-export proof with the
   platform-neutral redaction/allowlist tests rather than archive existence
   alone.
