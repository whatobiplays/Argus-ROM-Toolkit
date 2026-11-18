# Android Readiness probe

## 1. Evidence boundary

The standalone probe exercises the inactive ObserverV1 Readiness profile. It has no Flutter engine, ArgusApplication, Jobs, Library, ROM access, production Diagnostics setting or product observer. Its success result is exactly `{"state":"Ready"}` inside the reviewed envelope. This establishes probe readiness only.

Physical B1 is NOT_RUN. Software tests and CI signing provide no device evidence. Issue #74 remains open through physical B1 and independently reviewed B2; ADR-005 stays Draft. Preserve contract v5, capability v4, oracle v9, SPEC-X-003 global rules v1.0.0 and assessment schema v1.

## 2. Owner control and discovery

The exported launcher accepts no mode, UID, endpoint or session authority from intents. Only the non-exported control screen can arm discovery or enforcement through direct owner confirmation. Ordinary launch opens no listener. Backgrounding, recreation, process death or expiry terminates the session. There is no saved permissive UID or automatic reactivation.

Before discovery, the owner binds the exact target/build, signed probe artifact, session, fresh socket endpoint, one absent-before-creation forward and host discovery attempt. The host records ownership before connecting. The owner arms the matching bounded discovery window. The probe reads kernel peer credentials and denies the connection without obtaining application streams or returning bytes. It never automatically trusts the first UID.

Correlation requires matching session, endpoint, attempt label, connection count and coordinated host/device intervals. Compare clocks within their own domains; do not subtract Android and host clocks. Unsolicited, multiple, late, stale, mismatched or uncertain observations invalidate enrollment. This is operational correlation under a trusted-host, non-adversarial model, not cryptographic host authentication.

Only after recording that correlation may the owner separately approve and enter the exact UID and explicitly start enforcement. Every enforcing connection checks credentials before protocol I/O. Repeated transitions, wildcards, alternate transports and automatic retries are forbidden.

## 3. Resource and wire boundaries

The four-byte unsigned big-endian prefix counts UTF-8 body bytes. Reject zero or excessive lengths before allocation. Request, response and cancellation body caps are 274, 393 and 227 bytes respectively. The largest closed failure response is 297 bytes. Objects are closed: maximum depth 3, eight members per object, eleven total members and no arrays. Reject duplicate keys, invalid Unicode, unknown fields, coercion, unsupported tags and inexact integers. Preserve the exact member casing and envelopes in android-job-lifecycle.md section 11.2.

A connection carries one request, optionally one matching cancellation, and at most one response. Permit one executing request and one bounded rejection connection without a work queue. Session duration is bounded to 600 seconds, Readiness to five seconds and cancellation release to one second; reserve a separate 60-second cleanup window. Use host monotonic deadlines and discard late or incomplete responses. Reserve one of eight 4-KiB failure-receipt slots before dispatch; never evict earlier evidence to admit another attempt.

## 4. Independent OS observations

Prefer exact-package OS observations. If they cannot supply the required task fact, ADR-005 Q7 permits review of this specific ephemeral candidate: `adb -s <approved-target> shell dumpsys -t 3 activity activities`. This text is not execution permission. Do not add client-dump flags or substitute a generic diagnostic command.

Before use, pin a parser profile to the exact Android/OEM build. Review target package/component/user ownership, task membership, task ID, resumed/top-resumed status, display/windowing ambiguity and complete-output markers. A probe callback or matching PID cannot independently establish task continuity.

Stream output directly into a local bounded parser: at most 1 MiB total, 16 KiB per line, three-second device timeout and five-second host deadline. Immediately discard unrelated records. Never retain raw output, unrelated app names, intent contents, screenshots or raw-dump hashes. Commit sanitized target facts only after complete successful acquisition. Retain command/profile/build references and independent acquisition times. Overflow, timeout, truncation, ambiguity or unsupported format discards the entire observation. No fallback or automatic retry is permitted.

## 5. Future device admission and restoration

The owner must separately approve the exact reviewed source and signed APK SHA-256, signer certificate, target/build, private controls, UID correlation/pinning, fixed requests, forward tuple, OS commands, deadlines, evidence retention date and cleanup effects. Historical target selection and CI artifacts grant no authority.

Use the [Issue #74 B1 authorization packet proposal](issue-74-b1-authorization-packet.md) to collect these approvals. The unpopulated template grants no authority.

Record restoration obligations before mutation. Remove only a forward proven session owned and still matching the approved tuple. Do not adopt pre-existing resources. An uncertain create, replacement, ownership or restoration leaves a durable blocker. Cleanup is not successful merely because a command exited zero. Further recovery requires exact owner authority.

## 6. Outcomes and review

Verified incorrect behavior is FAILED/NO-GO. Missing or uncertain evidence is BLOCKED. Dependent unattempted checks are NOT_RUN. Expected denial/cancellation tests can pass their control assertion without supplying successful Readiness evidence. Neither documentation nor synthetic observations can satisfy physical feasibility.

Require independent full-diff review before proposing physical use, and direct ChatGPT source/test inspection before technical readiness. No production activation, qualification repinning, B2 or merge is authorized by this document.

## 7. Build and CI artifact separation

The independent Gradle application exposes only the non-debuggable `probe` build type. Verify the generated task inventory and dry-run `testProbeUnitTest lintProbe assembleProbe` before relying on those task names. Run those tasks and the repository Android qualification and naming checks from the dedicated task checkout. Local JVM and Android SDK versions must be recorded with results.

Gradle produces an unsigned probe. CI signs a copy using a disposable key under runner-temporary private storage, verifies it offline and removes the temporary signing directory. Keys and passwords must not be committed, cached or uploaded. A CI signature is test evidence only. Physical admission requires a separately owner-approved signer and the exact final signed APK digest; rebuilding or signing changes the artifact identity.

The host artifact checker and injected workflow do not authorize device access. Existing public live-execution blocks remain binding.

## 8. Host ADB adapter boundary

The host adapter is available only through the injected `ForwardAdapter` and `Transport` interfaces. Importing it does not run ADB, connect to a socket, or start a qualification session. It accepts these command forms only:

1. `adb -s <serial> get-state`
2. `adb -s <serial> shell getprop ro.build.fingerprint`
3. `adb -s <serial> forward --list`
4. `adb -s <serial> forward --no-rebind tcp:<port> localabstract:<name>`
5. `adb -s <serial> forward --remove tcp:<port>`

There is no shell, generic command, device-discovery command, install, pull or diagnostic command interface. The Q7 `dumpsys` candidate in section 4 remains a separate, future procedure requiring its own build-specific review and authority.

The session binds one explicit serial and build fingerprint. Each ADB argument vector includes that serial. `ForwardSession` rereads identity at each phase and rejects a changed target or build. Creation requires an absent mapping observed in the same phase, records the creation obligation before mutation, issues one `--no-rebind` request and records ownership only after an exact target/local/remote readback. A failed, late, missing or mismatched first readback leaves creation uncertain; a later matching listing cannot adopt it. A pre-existing, duplicate or uncertain mapping is never adopted. Removal requires the verified owned tuple and an exact same-phase readback. The first post-remove listing must prove absence; any remaining mapping, failed read or ambiguous result leaves removal terminally uncertain. Later listings cannot authorize another removal. The durable session obligation remains authoritative; uncertain creation or cleanup remains unresolved. The host model assumes no concurrent external forward mutator.

Discovery uses one deny-only connection through `ForwardSession.open_discovery_transport()` while the session is `Armed`. That transport does not allow protocol writes. Its deadline ends at the earlier of five seconds after arming or the session deadline. The host must close this connection within the separate one-second release allowance before correlating discovery. After owner confirmation of the observation and approval of the exact UID, the session enters `Enforcing`; only then may `ForwardSession.open_readiness_transport()` open one distinct Readiness connection. Both session methods recheck the bound identity and exact forward. The adapter repeats those checks immediately before connecting and accepts only the one-shot authorization supplied by the session. Pre-arm discovery, discovery after its admission window, Readiness before UID approval, direct adapter calls and repeated opens fail closed. The readiness connection has a close deadline one second after its phase deadline.

The session records whether discovery connected and closed successfully. Correlation requires both records. The adapter caps discovery release at six seconds after arming even when a caller supplies a later deadline. A late release still closes the local socket when possible, but it cannot authorize correlation. Cleanup remains blocked until every opened transport has a confirmed close within its release deadline.

The adapter uses fixed, nonzero local TCP ports. Successful create and remove commands must have empty stdout; unexpected output leaves the operation unresolved. Dynamic `tcp:0` allocation is outside this host checkpoint.

Every subprocess and socket operation uses its supplied absolute host-monotonic deadline. Each session phase has at most five seconds, including ADB process I/O. The subprocess runner drains stdout and stderr concurrently, accepts at most 64 KiB combined, retains stdout only until parsing and never retains stderr. Timeout, overflow, malformed output or nonzero exit fails closed. The runner observes client exit with POSIX `waitid(WNOWAIT)`, signals the isolated process group before reaping, and rejects before spawning when the host lacks the required wait flags. macOS can return `EPERM` when only an unreaped zombie remains. In that case, a fixed `/bin/ps` query must confirm that every process left in the isolated group is a zombie or absent; the query has a 250 ms deadline and a 64 KiB output cap. Missing, malformed or live-process evidence fails closed. If group termination is uncertain during cleanup, the runner kills the direct child before waiting. Process termination and reaping use the subprocess operation's same absolute deadline. The runner waits at most one second or the time left before that deadline, whichever is shorter. When no time remains, it makes a nonblocking reap attempt; cleanup is incomplete if exit and group cleanup cannot be confirmed. `WNOWAIT` leaves the child waitable, and Python has supported `waitid` on macOS since 3.13 ([Python documentation](https://docs.python.org/3.14/library/os.html#os.waitid)).

The AOSP server startup code starts its daemon in a new session with `setsid()` before acknowledging startup ([AOSP `client/main.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/main.cpp#L179-L197)). This adapter invokes `adb` through `PATH`, so verify that the selected Platform Tools binary has the same process behavior before physical use. An exited client with a still-open output pipe is treated as incomplete. The socket transport connects only to IPv4 loopback and bounds each request/response frame by the existing wire caps.

Readiness keeps its five-second request deadline and one-second socket-release deadline. The separate 60-second reserve starts after the authorized session deadline and applies only to outstanding host-side forward cleanup. Each cleanup phase remains capped at five seconds within that reserve. It does not extend a request, connection, device observation or socket-release deadline.

Host command output and raw process errors are transient. Shared evidence must use sanitized outcome codes and opaque references; do not publish serials, build fingerprints, stderr, command output or local paths. A future physical approval packet must identify the reviewed host-adapter source, the procedure revision, and the APK source independently. The APK's `probeSourceCommit` must name the exact source revision used to build that APK; it must not be copied from the host adapter or procedure revision. The packet also needs the exact signed APK digest and signer, target/build, approved command effects and forward tuple, deadlines, evidence retention, and cleanup authority. No values are preapproved by this host-only checkpoint.

## 9. OS evidence readiness and observation prerequisites

The current Q7 parser returns only the bound package, task ID and one resumed flag. Its synthetic fixtures establish parser behavior; they do not qualify an Android/OEM build. No diagnostic acquisition adapter or physically qualified profile is shipped. Parser implementation is deferred until owner-selected target/build evidence supports a concrete, separately reviewed change.

The matrix describes the evidence needed to assess feasibility under ADR-005 Q7/Q8/Q11 and ObserverV1 section 11.6. It adds no physical operation or acceptance criterion. Checkpoints must be specified in the reviewed session procedure before collection.

| Required OS evidence | Acquisition checkpoints | Current parser coverage | Ambiguity that blocks the assertion | Missing qualification proof |
|---|---|---|---|---|
| Target package, component and Android user ownership | At baseline and each relevant task/foreground observation | Bound package string only | Component or user absent, conflicting ownership, multiple target candidates | Exact-build source semantics and independently observed ownership |
| Task membership and task identity | Before and after each authorized transition for which task continuity is required | One task ID only | Reused task number, missing membership or checkpoint, uncertain transition | Source-qualified task membership and evidence linking the same task across the required checkpoints |
| Resumed and distinct top-resumed state | At each relevant foreground checkpoint | One resumed flag only | Resumed treated as top-resumed, conflicting activity records | Exact-build interpretation and independent target observations for both states |
| Display and windowing state | With each task/foreground checkpoint | None | Multiple displays/windows, unsupported mode or incomplete association | Qualified display/windowing facts sufficient to resolve foreground ambiguity |
| Package-scoped process identity and foreground state | At baseline and relevant before/after lifecycle checkpoints | None | PID reuse, missing process association or an unobserved lifecycle gap | Qualified OS process source, acquisition times and required corroborating visible-UI evidence |
| Complete, fresh acquisition and provenance | For every observation | Bounded stream, configured completion marker, successful exit and profile/build binding; no physical freshness qualification | Truncation, stale observation, timeout, inconsistent binding or unsupported grammar | Exact-build completion contract and session/checkpoint timing evidence |

OS/O facts remain independent of host/H command receipts, probe-reported readiness or lifecycle callbacks, and visible-UI/U observations. Neither a matching PID nor a probe callback proves task continuity. Retain only sanitized target facts with opaque target/build references in shared evidence; identifying build values stay private.

Before proposing collection, obtain the selected target/build and review authoritative format or Android/OEM source evidence where available. Prefer package-scoped sources. If broader Q7 output is necessary, establish a safe transient filtering procedure and reliable completion contract before authorizing acquisition. Do not collect a broad dump to discover its grammar afterward. If those prerequisites cannot be established, collection remains BLOCKED.

The packet must distinguish a preliminary target-observation attempt from physical B1 execution. Each requires its own reviewed scope and explicit owner authority. A preliminary observation cannot grant installation, launch, UID enrollment, forwarding or later B1 authority by implication. Preserve the section 4 limits and command restriction; retain no raw dump, stderr, unrelated records or raw-dump hash. No automatic retry is allowed.

After sufficient evidence is available, prepare a separate parser/acquisition implementation plan with exact facts, grammar, interfaces and deterministic failure tests. Physical profile qualification still requires separately authorized target observations. Final signed-artifact provenance, peer-UID discovery/approval and verified restoration remain prerequisites for B1; offline preparation leaves physical B1 NOT_RUN.

## 10. Source-backed target OS evidence feasibility

This section records what generic Android platform sources make plausible to observe. It does not establish that an exact Android/OEM build exposes the same fields, output grammar, access or behavior. No target-specific OS profile is qualified.

### Existing platform facilities

| Fact area | Source-backed possibility | Qualification limit |
|---|---|---|
| Task and activity identity | In the pinned AOSP implementation, `dumpsys activity activities` reaches `ActivityTaskManagerService` and `RootWindowContainer`. The activity dump walks displays and root tasks; task records include a task ID, user ID and activity component. The task model also carries a resolved windowing mode. | This is generic AOSP implementation evidence. It does not establish the selected OEM build's output or a stable grammar. The public `ActivityManager.getRunningTasks()` API is restricted for third-party applications and may return only a small subset, so it cannot be assumed to provide a complete task list. |
| Resumed and top-resumed activity | The pinned AOSP service has a distinct top-resumed activity dump and includes a top-resumed record in its activity dump. | A resumed flag alone is not proof of top-resumed status. The exact build's record selection and representation remain unverified. |
| Display and windowing | The pinned AOSP activity dump traverses display contents and labels display IDs. AOSP task configuration resolves a windowing mode. | Display-to-task association and windowing fields must be present and unambiguous in the selected build's evidence. AOSP source alone does not prove that the diagnostic output renders them in a parseable form. |
| Process identity and importance | `ActivityManager.RunningAppProcessInfo` documents PID, UID, process name, loaded package names and process importance. | API visibility and process coverage depend on the caller and Android version. Process importance is not task continuity, and matching PID values cannot prove an uninterrupted process lifetime. |

The AOSP implementation references are pinned to individual source revisions: [`ActivityTaskManagerService.java` at `296c28979c5b212e9e32be397901f93e15b60bf3`](https://android.googlesource.com/platform/frameworks/base/+/296c28979c5b212e9e32be397901f93e15b60bf3/services/core/java/com/android/server/wm/ActivityTaskManagerService.java#L3892), [`RootWindowContainer.java` at `f7224f068f783060608ffce90653aef50b662231`](https://android.googlesource.com/platform/frameworks/base/+/f7224f068f783060608ffce90653aef50b662231/services/core/java/com/android/server/wm/RootWindowContainer.java#L3642), and [`Task.java` user/component dump at `c223642`](https://android.googlesource.com/platform/frameworks/base/+/c223642/services/core/java/com/android/server/wm/Task.java#L3805), which also prints task ID ([line 3895](https://android.googlesource.com/platform/frameworks/base/+/c223642/services/core/java/com/android/server/wm/Task.java#L3895)) and resolves windowing mode ([line 2420](https://android.googlesource.com/platform/frameworks/base/+/c223642/services/core/java/com/android/server/wm/Task.java#L2420)). Public API references: [`ActivityManager.getRunningTasks`](https://developer.android.com/reference/android/app/ActivityManager#getRunningTasks(int)) and [`ActivityManager.RunningAppProcessInfo`](https://developer.android.com/reference/android/app/ActivityManager.RunningAppProcessInfo). These sources describe generic Android facilities; none is evidence from a selected physical target.

### Completion and filtering constraints

The pinned AOSP [`dumpsys.cpp` revision `0fea11479ed647dec873734fcd5800c8f0ec6d9b`](https://android.googlesource.com/platform/frameworks/native/+/0fea11479ed647dec873734fcd5800c8f0ec6d9b/cmds/dumpsys/dumpsys.cpp#L253) prints a service-timeout notice when the dump times out, then returns exit code zero after the service loop. A successful exit therefore cannot independently establish complete acquisition. A build-specific profile must distinguish a complete capture from timeout notices, service errors, truncated output and incomplete transport.

The current parser accepts only a configured full-line target grammar for package, task ID and resumed state, plus a configured completion line, a matching source/build binding and a zero command exit. Its input limits are bounded, and it returns sanitized target fields; however, the grammar and completion behavior have only synthetic fixtures. No physical profile or diagnostic acquisition adapter is qualified. In particular, the configured completion line has not been validated against the AOSP timeout notice or any OEM output.

Before proposing an acquisition or parser change, resolve each of these gaps against the exact owner-selected build:

1. Define the exact-build grammar and field meanings for package, component, Android user, task membership and identity, resumed versus top-resumed state, display, windowing and process facts.
2. Specify complete-output, timeout and error semantics, including how the timeout notice is rejected even if the command exits zero. Define behavior for truncation, malformed text, missing markers and partial transport.
3. Review a safe transient filter for that grammar. It must discard unrelated records before they can enter retained files, logs or shared evidence. The parser's generic line filtering has not been qualified against real target output.
4. Define independent before/after OS checkpoints and their acquisition times for every required transition. A single sample, matching PID, probe callback or lifecycle event cannot establish task continuity.

If any required fact, filter or completion rule cannot be qualified, keep the OS assertion BLOCKED and dependent physical work NOT_RUN. Do not collect a broad dump to discover its format.

### Historical target and future identity-only preflight

Issue [#28](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/28) records the AYANEO Pocket Air Mini as a previously owner-selected candidate for that issue. That historical selection and its bounded preflight authority do not select a target or authorize any operation for Issue #74. The Issue #74 target and build remain unselected.

To make later source review target-specific, the minimum proposed identity-only preflight is a separate, explicitly authorized operation using the same exact owner-selected serial for these read-only commands:

```text
adb -s <owner-approved-target> get-state
adb -s <owner-approved-target> shell getprop ro.build.fingerprint
```

The proposal is limited to one invocation of each command with the existing five-second host phase bound, no retries, no device enumeration, and private handling of the serial and fingerprint. It does not include `dumpsys`, UID discovery, forwarding, probe execution or any application action. This preflight is not approved by this documentation change and must not be started until the owner separately selects the Issue #74 target and authorizes the exact operation. The existing authorization packet remains unchanged.
