# Issue #74 Readiness probe execution

1. Authority: owner-approved corrected A–I plan and explicit implementation handoff. Issue: https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/74. This is the implementation slice, not physical B1 or B2.
2. Source baseline: `07a7783948ae170c33b951cc55bc08bbee0fb759`. Dedicated branch: `codex/issue-74-b1-readiness-probe`. Worktree: `/Users/daniel/.codex/worktrees/issue-74-b1-readiness-probe/Argus-ROM-Toolkit`. Codex bootstrapped a clean task worktree and verified origin `git@github-wop:whatobiplays/Argus-ROM-Toolkit.git`.
3. Current policy: `danielbyon/development-process@e2afa055d1126763c69f0e0392d25b86bab98014`, migrated by the owner's explicit authorization for this issue only. Historical policy `142422527de28b8e20dea1158d2f54d020dcdcd5` remains provenance. Decision: https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/74#issuecomment-6909262173.
4. Risk: CRITICAL. Acceptance is the approved probe control, credential correlation, Readiness protocol, bounds, privacy, artifact and host-only validation behavior. No new PAC/TAC identifiers are assigned.
5. Implementation scope: standalone Android probe; isolated Python verification and tests; runbook; naming-surface registration; isolated CI. Existing product startup, active qualification pins and executors remain outside scope.
6. Execution uses a manual task contract. No native Delegation v3 materialization or lineage is claimed. Optional graph/index/configuration setup and MCP server lifecycle operations were not performed.
7. Physical B1: NOT_RUN. No ADB/device command, install, launch, forward, diagnostics acquisition, actual peer discovery or observer activation is authorized. Issue #74 remains open for physical B1 evidence and independently reviewed B2. No merge is authorized.

## Review and validation in progress

1. Standalone task inventory and dry-run executed with local Homebrew JDK 17.0.21, Gradle 9.1.0 and AGP 9.0.1. The first build exposed a removed AGP property; the build configuration was corrected. JVM tests, lint and unsigned packaging subsequently executed.
2. Initial independent local Cubic review identified a cancellation monitoring defect and a diagnostic completion defect. Corrections added regression tests and were submitted to a second full-diff review. That review identified additional deadline and cleanup findings requiring disposition before publication. No clean-review or readiness claim is made here.
3. Offline artifact verification succeeded against a disposable locally signed test APK. Its signer is not approved for physical use, and its embedded source revision was the pre-commit baseline. Final artifact provenance must be regenerated after the reviewed implementation commit. The temporary key was removed.
4. A full host regression run executed 1,229 tests with two skips and one stale inventory-expectation failure. The historical inventory assertions are preserved while exact new probe surfaces are added to the expected inventory. Final results will supersede this in-progress observation without erasing it.

## Verified host and build checks

1. Full Android qualification regression: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/android_qualification -p 'test_*.py' -t .` ran 1,261 tests successfully with two environment-dependent skips. Existing skip conditions cover permission-denial observability under root and unavailable host Flutter artifacts.
2. The naming check and whitespace check passed. Workflow YAML parsed successfully. Final native check used Homebrew JDK 17.0.21 and the installed API-36 SDK; no JDK installation was required.
3. Host review corrections enforce post-validation deadline rejection at equality, a separate 60-second cleanup reserve with absolute deadlines passed to injected adapters, and diagnostic profile/build/package/source binding. Adapter implementations must honor those deadlines; this slice provides no physical ADB adapter.
4. Receipt append and replay now require every closed provenance field and synchronize the containing directory before reporting durable append. Tests reject missing fields and hash-recomputed invalid records.
5. Local Cubic did not load GitHub repository context for the SSH origin alias; review used the supplied local full diff and contract instructions. This limitation does not imply GitHub review occurred. Automatic GitHub review remains a separate later pass.

## Review dispositions and implementation inventory

1. The later full host regression ran 1,264 tests successfully with the same two environment-dependent skips. The discovery record retains validated Android elapsed endpoints separately from host timing; the source interval may include at most the five-second admission window plus one-second release allowance. This does not extend admission authority.
2. Cubic's Busy-ID reuse finding is disputed against ObserverV1 section 11.2: all request, connection and attempt identities are unique within the authorized session, and a refusal grants no replay authority. Retaining refused identities enforces that rule.
3. The partial-control finding is disputed after the absolute-deadline correction. Incomplete control input cannot produce Ready. Every read reapplies the remaining absolute authority; a one-second control-frame budget cannot extend the request deadline, and the socket has an independent deadline-close timer. Waiting within that budget is not deadline extension. Drip-feed regressions exercise prefix and body exhaustion.
4. The EOF-after-cancellation finding is disputed: only a completely parsed, identity-matching cancellation can reach that branch. EOF then permits only Cancelled, never Ready or process-loss evidence. Observed second-control bytes are malformed; attempted writes that never enter a closed input stream are not accepted protocol frames.
5. The queued-discovery finding was validated and corrected with bounded native polling and a terminal queue check. Extra queued peers are denied without stream access and invalidate correlation. Poll/accept failure cannot create a policy. Native OS scheduling/teardown remains physically unverified.

The exact candidate changed-file inventory follows; build outputs and disposable signing material are excluded.

1. `.github/workflows/ci.yml`
2. `android-readiness-probe/.gitignore`
3. `android-readiness-probe/build.gradle.kts`
4. `android-readiness-probe/gradle.properties`
5. `android-readiness-probe/gradle/wrapper/gradle-wrapper.jar`
6. `android-readiness-probe/gradle/wrapper/gradle-wrapper.properties`
7. `android-readiness-probe/gradlew`
8. `android-readiness-probe/gradlew.bat`
9. `android-readiness-probe/settings.gradle.kts`
10. `android-readiness-probe/src/main/AndroidManifest.xml`
11. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/ActiveRead.kt`
12. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/AndroidPeerSocket.kt`
13. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/DiscoveryWindow.kt`
14. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/LauncherActivity.kt`
15. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/PeerConnection.kt`
16. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/ProbeControlActivity.kt`
17. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/ProbeSession.kt`
18. `android-readiness-probe/src/main/kotlin/com/argusromtoolkit/argus/readinessprobe/ReadinessProtocol.kt`
19. `android-readiness-probe/src/test/kotlin/com/argusromtoolkit/argus/readinessprobe/ActiveReadTest.kt`
20. `android-readiness-probe/src/test/kotlin/com/argusromtoolkit/argus/readinessprobe/ComponentPolicyTest.kt`
21. `android-readiness-probe/src/test/kotlin/com/argusromtoolkit/argus/readinessprobe/DiscoveryWindowTest.kt`
22. `android-readiness-probe/src/test/kotlin/com/argusromtoolkit/argus/readinessprobe/PeerConnectionTest.kt`
23. `android-readiness-probe/src/test/kotlin/com/argusromtoolkit/argus/readinessprobe/ProbeSessionTest.kt`
24. `android-readiness-probe/src/test/kotlin/com/argusromtoolkit/argus/readinessprobe/ReadinessProtocolTest.kt`
25. `docs/qualification/android-readiness-probe.md`
26. `docs/qualification/surface-classifications-v1.json`
27. `docs/tasks/task-issue-74-readiness-probe.md`
28. `scripts/android_qualification/readiness_probe.py`
29. `scripts/android_qualification/readiness_probe_artifact.py`
30. `scripts/android_qualification/readiness_probe_session.py`
31. `scripts/android_qualification/test_readiness_probe.py`
32. `scripts/android_qualification/test_readiness_probe_artifact.py`
33. `scripts/android_qualification/test_readiness_probe_session.py`
34. `scripts/android_qualification/test_repository_checks.py`

## PR #81 correction review

1. Correction base: `3a748a665fda46fde9c04ee3a1f0c62d1315a78c`, verified against the clean task worktree, remote branch and open draft PR. The Issue #74 policy remains `e2afa055d1126763c69f0e0392d25b86bab98014`.
2. Discovery admission and owner review now have separate bounds. The original host connection interval must fit strictly before the five-second admission deadline. Review and explicit UID approval can follow publication of the full-window result, within the original 600-second session. Existing host and Android intervals remain distinct, and no retry or authority extension is introduced.
3. Failed or late transport release remains `IncompleteEvidence`, including after request timeout. Existing receipt timing retains deadline-overrun evidence. Host-only secondary failure codes preserve request and cleanup outcomes without adding wire codes or changing the receipt schema. Raw cleanup exceptions remain private.
4. The isolated CI job now installs repository-pinned `just` 1.58.0 before the unchanged full Python suite. The earlier job log records five entrypoint failures caused by a missing `just` executable; its signing step did not run.
5. Eight deterministic correction tests initially reproduced two correlation errors and two cleanup-precedence failures. All eight now pass. The full host suite runs 1,272 tests successfully with two existing environment-dependent skips. Standalone task inventory, 32 Android tests, build and lint pass; lint retains zero errors and 13 warnings. Naming, whitespace and workflow YAML checks pass.
6. Cumulative review consists of the previous complete implementation review plus an independent review of these correction deltas. Exact-head CI and the disposable signing/verification step must be inspected after publication; local signing does not substitute for those CI results.
7. Changed paths: `.github/workflows/ci.yml`; `scripts/android_qualification/readiness_probe.py`; `scripts/android_qualification/readiness_probe_session.py`; their two corresponding test files; and this execution record.
8. Physical B1 remains NOT_RUN. No physical ADB, installs, real forwards, UID discovery, production observer change, B2, active repinning or merge is authorized. Native target behavior and OS profile qualification remain unverified.
9. The correction-delta review found an additional discovery-completeness gap: intervals shorter than the full observation window were accepted. Regression tests reproduced that issue and premature owner review. Discovery now requires a 5,000–6,000 ms Android interval and review after host admission closes; neither clock is converted into the other. Older valid fixtures now represent a completed observation, so their identity checks are not bypassed by earlier timing rejection.
10. Final local correction validation: 98 focused probe tests and the full 1,274-test host suite pass, with the same two existing environment-dependent skips. The ten new regression methods cover the requested admission/review and cleanup cases plus incomplete-window rejection. Standalone Android validation remains 32 passing tests, zero lint errors and 13 warnings. Naming, whitespace and workflow YAML checks pass.
11. Re-review also found that late verified cleanup could overwrite an earlier request failure. The final precedence rule retains an existing request failure, records timeout when an otherwise successful attempt completes late, and gives uncertain cleanup precedence over either. Regression tests cover cancellation and observer failure followed by verified cleanup at and after the request deadline, as well as late completion after a successful response.
12. Final correction validation now includes 13 new regression methods: all 101 focused probe tests and the complete 1,277-test host suite pass, with two existing skips. Native code is unchanged by these host corrections; standalone inventory, 32 Android tests, build and lint were verified in this correction session. Lint remains zero errors and 13 warnings. Exact-head CI results and the independent correction-review verdict are recorded with the updated PR after publication.
13. A further correction review required durable retention of both failure causes. Closed `request_code` and `cleanup_code` metadata now lives beside the unchanged receipt in the private record envelope and is covered by its hash. Append and replay reject unknown or inconsistent causes. Earlier records without the metadata remain readable. No ObserverV1 field, wire code, shared assessment schema or active pin changes. A maximal-record test confirms the existing 4-KiB bound still holds; integration tests prove timeout-plus-cleanup causes survive readback.
14. The timestamp-order finding is disputed by the enforced inequalities: `host_started <= host_finished` and `host_finished <= review_clock` imply `host_started <= review_clock`. Future-start and reversed/future interval regressions also reject those inputs. No additional authority or timestamp source is introduced.
15. Local validation after durable cause retention: 106 focused tests and the complete 1,282-test host suite pass, with two existing environment-dependent skips. All 32 Android tests, standalone build, lint, naming and YAML checks passed earlier in this correction session; native code is unchanged. Five further private-record tests exercise persisted causes, invalid metadata, hash-consistent corruption, maximal size and exclusion from wire responses. Independent re-review and exact-head CI results are recorded on PR #81 after publication.
