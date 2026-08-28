# Library cross-platform lifecycle hardening implementation plan

## Scope

This plan implements the approved P03-008 work for reusable desktop and
Android Library lifecycle/integration qualification gates. It does not close
the later P03-009 Phase 003 qualification boundary.

The implementation must preserve these constraints:

1. Existing Delegation v3 capability boundaries remain authoritative. The
   application-lifetime lifecycle coordinator owns only OS lifecycle observation
   and one coalesced, read-only reconciliation signal.
2. Library, Sources, Jobs, browser, and Game-detail controllers remain owned by
   their existing feature composition/provider seams. The lifecycle coordinator
   does not retain or register any of them.
3. Startup recovery is persistence-only. It terminalizes stale supported
   operations, preserves accepted cancellation, reconciles scan children where
   applicable, and never performs provider or filesystem work.
4. Android foreground hosting remains a transient lease/projection capability;
   durable JobRun state and runtime ownership remain in the existing
   Flutter/Rust client.
5. Protected contract documentation under `docs/phases/**`,
   `docs/specifications/**`, and `docs/superpowers/specs/**` is not edited.
6. New operational names are domain-oriented and do not use `phase`, `P03`,
   `slice`, or `final`.

## TDD work items

### 1. Startup recovery and stop semantics

- Add a failing generic startup-recovery test covering every supported active
  operation type.
- Add a failing library-refresh child test for both accepted cancellation and
  unexpected host loss/timeout recovery semantics.
- Add a failing runtime test proving that timeout and host loss preserve partial
  committed work while cancellation remains cancellation.
- Implement the smallest persistence/application changes needed to turn those
  tests green, leaving the existing LibraryScan compatibility seam intact.

### 2. Application lifecycle composition

- Add failing coordinator tests for desktop coalescing and Android readiness
  re-certification before publication.
- Move the sole `WidgetsBindingObserver` responsibility into an app-lifetime
  coordinator and remove observation from the readiness presentation gate.
- Map the coordinator signal into the existing Library, Sources, and Jobs
  reconciliation demand sources.
- Add controller tests proving that loaded Sources scopes and the local browser
  refresh authoritative state without losing navigation context.

### 3. Android evidence and controls

- Add failing Dart and Kotlin tests for the bounded Activity identity and
  debug-only foreground-host qualification controls.
- Keep native controls unavailable in release builds and ensure stale Activity
  detach cannot clear a newer Activity attachment.
- Drive timeout and host-loss controls through the same service callbacks used
  by the Android foreground service when the service is attached.

### 4. Qualification gates

- Add one desktop Library lifecycle integration test using a test-owned native
  data directory and the production bootstrap.
- Add one Android Library lifecycle integration test using explicit device
  markers, real background/foreground actions, single-runtime assertions, and
  the bounded debug controls.
- Add domain-oriented runners that record `PASS`, `FAIL`, or `NOT RUN` with
  bounded evidence. Missing devices, toolchains, NDK selection, or package
  builds must never be reported as a pass.
- Register generated Dart output and expose separate `just` targets without
  making the platform-neutral check depend on connected Android hardware.

### 5. Regression and documentation

- Preserve the existing adaptive layout, ordinary Back, accessibility,
  credential, artwork, single-runtime, and host-loss tests and contracts.
- Run focused tests first, then generated-source checks, formatting, analysis,
  Rust tests, Flutter tests, Kotlin unit tests, ShellCheck, and any available
  native qualification gate.
- Record implementation and verification evidence in the companion file under
  `docs/implementation/` only. If a test demonstrates a contract contradiction,
  stop and report it instead of changing protected contract documentation.

## Completion criteria

The work is complete when the implementation and focused regression tests are
green, generated outputs are registered and reproducible, qualification runners
classify unavailable external prerequisites explicitly, and the verification
record states which desktop/Android evidence was actually observed. No commit or
push is part of this plan.
