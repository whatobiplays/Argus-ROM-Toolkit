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

Before using an observation to support a qualification assertion, pin a reviewed parser profile to the exact Android/OEM build. Review target package/component/user ownership, task membership, task ID, resumed/top-resumed status, display/windowing ambiguity and complete-output markers. Bounded exploratory acquisition may precede that qualification under section 9. A probe callback or matching PID cannot independently establish task continuity.

For qualified observations, stream output directly into the reviewed local bounded parser: at most 1 MiB total, 16 KiB per line, three-second device timeout and five-second host deadline. Immediately discard unrelated records. Never retain raw output, unrelated app names, intent contents, screenshots or raw-dump hashes. Commit sanitized target facts only after complete successful acquisition. Retain command/profile/build references and independent acquisition times. Overflow, timeout, truncation, ambiguity or unsupported format discards the entire observation. No fallback or automatic retry is permitted. Exploratory acquisition keeps the same command, bounds and privacy controls; it produces no qualified facts.

## 5. Future device admission and restoration

Present the exact reviewed source and signed APK SHA-256, signer certificate, target/build, private controls, UID correlation/pinning, fixed requests, forward tuple, OS commands, deadlines, evidence handling and cleanup effects together. One owner approval covers the bounded B1 session and its listed operations. Preserve the in-session owner confirmation of the observed peer UID before enforcement. B2 requires its own session approval. Historical target selection and CI artifacts grant no authority.

Use the compact [B1 session record](issue-74-b1-authorization-packet.md) and the [proportionate session workflow](device-authorization.md#proportionate-session-workflow). The executor fills values available from source, artifacts and existing records; the owner decides scope and authorizes the session. A separate packet-digest review, external receipt custodian and calendar deletion date are not admission requirements. A template is not authorization.

Record restoration obligations before mutation. Remove only a forward proven session owned and still matching the approved tuple. Do not adopt pre-existing resources. An uncertain create, replacement, ownership or restoration leaves a durable blocker. Cleanup is not successful merely because a command exited zero. Further recovery requires exact owner authority.

## 6. Outcomes and review

Verified incorrect behavior is FAILED/NO-GO. Missing or uncertain evidence is BLOCKED. Dependent unattempted checks are NOT_RUN. Expected denial/cancellation tests can pass their control assertion without supplying successful Readiness evidence. Neither documentation nor synthetic observations can satisfy physical feasibility.

Require independent full-diff review before proposing physical use, and direct ChatGPT source/test inspection before technical readiness. No production activation, qualification repinning, B2 or merge is authorized by this document.

## 7. Build and CI artifact separation

The independent Gradle application exposes only the non-debuggable `probe` build type. Verify the generated task inventory and dry-run `testProbeUnitTest lintProbe assembleProbe` before relying on those task names. Run those tasks and the repository Android qualification and naming checks from the dedicated task checkout. Local JVM and Android SDK versions must be recorded with results.

Gradle produces an unsigned probe. CI signs a copy using a disposable key under runner-temporary private storage, verifies it offline and removes the temporary signing directory. Keys and passwords must not be committed, cached or uploaded. A CI signature is test evidence only. Physical admission requires a separately owner-approved signer and the exact final signed APK digest; rebuilding or signing changes the artifact identity.

The host artifact checker and injected workflow do not authorize device access. Existing public live-execution blocks remain binding.

## 8. Host ADB adapter boundary

Importing the host adapter does not run ADB, connect a socket, or start a qualification session. Its fixed operations bind the selected target and build, read the API level and numeric Android user ID, inspect the two approved packages, launch Readiness, project matching process rows, and manage one Package Manager install session. The first current-user query binds the numeric user ID. Package, process and launcher operations use that bound user. Package queries retain only version and UID; process output is reduced to matching package roles and UID consistency, and unrelated rows are discarded.

The adapter writes and syncs an owner-private journal before the first install mutation. The journal binds one attempt to the target, build, Android user, pinned APK and baseline package/session state. Immediately before creating the install session, the adapter rechecks all-user package absence, device identity, current user and the session snapshot. A complete snapshot requires the observed section sequence and a recognized empty legacy map. An incomplete dump or expired deadline blocks mutation.

The [Issue #74 cleanup decision](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/74#issuecomment-7099744334) excludes invisible external replacement on the controlled device. A present package can be removed only when its user, version, UID, installed APK digest and successful install session match a unique journal attempt. Observed interference blocks cleanup. The adapter writes and syncs cleanup intent before uninstall and checks package absence and session state afterward. Verified absence needs no uninstall. A failed command or incomplete readback leaves an outstanding recovery obligation.

The selected build's historical sessions have three field rows. They start with six spaces, wrap at column 120 and continue with a two-space prefix. Android 12 AOSP prints the live rows directly, with four spaces and breaks between complete fields as well as at column 120. The parser checks row order, endings and the binding between the session installer and UID. The install parameters contain a separate installer field. An explicitly null package in a complete historical row is retained as an unattributed session ID. A live null binding or a null binding for the expected session still blocks. Calibration verifies the live format on a selected build before using it in preparation.

Session-only calibration stops after creating and observing the session. It never calls install-write or install-commit. Its caller runs recovery even if rich parsing fails. Precommit recovery can abandon the exact ID from the durable install-create result. It requires a complete session listing and matching package, user and shell installer bindings. The session must be standalone, unstaged, unsealed and uncommitted. The adapter verifies package absence for all users and records the abandon intent before the command. Recovery verifies that the ID is no longer live and that the package is absent. An incomplete readback leaves the journal open. This limited view supplies no authority to transfer an APK, commit, or uninstall.

The recovery reader accepts the original v1 preparation record's UTC timestamps with three fractional digits and hashes the original file bytes. The [Issue #74 fresh-baseline decision](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/74#issuecomment-7103342817) permits a new attempt when two valid v1 records match the bound target, build, user and artifact but disagree on UID. The records remain unresolved. The new journal carries an immutable fresh-baseline marker. Only that journal's verified lineage can authorize its cleanup.

The adapter stages the pinned APK in a mode-0400 file inside a mode-0700 temporary directory and streams it through a Package Manager install session. It checks the digest before and after staging, verifies the installed base APK, and never uses a replacement install option. The launcher accepts only the reviewed component and retains bounded completion fields. Adapter methods return sanitized results but do not validate external authorization. All forward lifecycle and transport operations use `ForwardSession` through the injected `ForwardAdapter` and `Transport` interfaces.

The adapter accepts these command forms only:

1. `adb -s <serial> get-state`
2. `adb -s <serial> shell getprop ro.build.fingerprint`
3. `adb -s <serial> shell getprop ro.build.version.sdk`
4. `adb -s <serial> shell getprop ro.product.cpu.abi`
5. `adb -s <serial> shell am get-current-user`
6. `adb -s <serial> shell pm list users`
7. `adb -s <serial> shell pm list packages --show-versioncode -U --user <bound-user-id> <approved-package>`
8. `adb -s <serial> shell dumpsys -t 3 package installs`
9. `adb -s <serial> shell pm install-create -S <size> --user <bound-user-id> --pkg <readiness-package>`
10. `adb -s <serial> shell pm install-write -S <size> <session-id> base -`
11. `adb -s <serial> shell pm install-commit <session-id>`
12. `adb -s <serial> shell pm install-abandon <session-id>`
13. `adb -s <serial> shell pm path <readiness-package>`
14. `adb -s <serial> exec-out cat <validated-installed-base-apk-path>`
15. `adb -s <serial> shell am start --user <bound-user-id> -W -n <readiness-component>`
16. `adb -s <serial> shell ps -A -n -w -o UID,PID,NAME`
17. `adb -s <serial> forward --list`
18. `adb -s <serial> forward --no-rebind tcp:<port> localabstract:<name>`
19. `adb -s <serial> forward --remove tcp:<port>`
20. `adb -s <serial> shell pm uninstall --user <bound-user-id> --versionCode <pinned-version> <readiness-package>`

The runner rejects other command vectors, including `adb devices`. Package and process checks accept only the two approved package IDs. Process rows and install-session output are filtered in bounded memory; unrelated package identities and raw rows are discarded. A package-list result counts as absence only after the bounded command exits successfully with empty stderr. Nonempty stderr, timeout, nonzero exit, truncation or parse failure never counts as absence. The runner does not retain stderr. Install input is limited to the pinned APK digest and streamed from a read-only descriptor. Q7 activity-dump acquisition remains a separate fixed command with its own privacy limits. A successful exploratory parse does not establish semantic completeness or qualify an OS assertion.

For the identity-only preflight, record the owner's instruction and call `AdbForwardAdapter.identity()` with the selected private serial and one host-monotonic deadline set to `monotonic() + 5.0`. The method issues `get-state` once and runs `getprop ro.build.fingerprint` once only when the first result is exactly `device`. Both calls use that same deadline. Do not create a `ForwardSession` with an invented fingerprint. Keep the returned serial and fingerprint in a small owner-private outcome record with the source/procedure reference, acquisition time, command counts and classification. Retain no raw output or stderr and publish only an opaque target reference and sanitized status. A failed, malformed, late or inconsistent result is BLOCKED. No retry or extra command is permitted. No independent identity-packet review or separate integrity receipt is required.

The session binds one explicit serial and build fingerprint. Each ADB argument vector includes that serial. `ForwardSession` rereads identity at each phase and rejects a changed target or build. Creation requires an absent mapping observed in the same phase, records the creation obligation before mutation, issues one `--no-rebind` request and records ownership only after an exact target/local/remote readback. A failed, late, missing or mismatched first readback leaves creation uncertain; a later matching listing cannot adopt it. A pre-existing, duplicate or uncertain mapping is never adopted. Removal requires the verified owned tuple and an exact same-phase readback. The first post-remove listing must prove absence; any remaining mapping, failed read or ambiguous result leaves removal terminally uncertain. Later listings cannot authorize another removal. The durable session obligation remains authoritative; uncertain creation or cleanup remains unresolved. The host model assumes no concurrent external forward mutator.

Discovery uses one deny-only connection through `ForwardSession.open_discovery_transport()` while the session is `Armed`. That transport does not allow protocol writes. Its deadline ends at the earlier of five seconds after arming or the session deadline. The host must close this connection within the separate one-second release allowance before correlating discovery. After owner confirmation of the observation and approval of the exact UID, the session enters `Enforcing`; only then may `ForwardSession.open_readiness_transport()` open one distinct Readiness connection. Both session methods recheck the bound identity and exact forward. The adapter repeats those checks immediately before connecting and accepts only the one-shot authorization supplied by the session. Pre-arm discovery, discovery after its admission window, Readiness before UID approval, and repeated opens are rejected. The readiness connection has a close deadline one second after its phase deadline.

The session records whether discovery connected and closed successfully. Correlation requires both records. The adapter caps discovery release at six seconds after arming even when a caller supplies a later deadline. A late release still closes the local socket when possible, but it cannot authorize correlation. Cleanup remains blocked until every opened transport has a confirmed close within its release deadline.

The adapter uses fixed, nonzero local TCP ports. Successful create and remove commands must have empty stdout; unexpected output leaves the operation unresolved. Dynamic `tcp:0` allocation is outside this host checkpoint.

Every subprocess and socket operation uses its supplied absolute host-monotonic deadline. Each session phase has at most five seconds, including ADB process I/O. The subprocess runner drains stdout and stderr concurrently, accepts at most 64 KiB combined, retains stdout only until parsing and never retains stderr. Timeout, overflow, malformed output or nonzero exit fails closed. The runner observes client exit with POSIX `waitid(WNOWAIT)`, signals the isolated process group before reaping, and rejects before spawning when the host lacks the required wait flags. macOS can return `EPERM` when only an unreaped zombie remains. In that case, a fixed `/bin/ps` query must confirm that every process left in the isolated group is a zombie or absent; the query has a 250 ms deadline and a 64 KiB output cap. Missing, malformed or live-process evidence fails closed. If group termination is uncertain during cleanup, the runner kills the direct child before waiting. Process termination and reaping use the subprocess operation's same absolute deadline. The runner waits at most one second or the time left before that deadline, whichever is shorter. When no time remains, it makes a nonblocking reap attempt; cleanup is incomplete if exit and group cleanup cannot be confirmed. `WNOWAIT` leaves the child waitable, and Python has supported `waitid` on macOS since 3.13 ([Python documentation](https://docs.python.org/3.14/library/os.html#os.waitid)).

The AOSP server startup code starts its daemon in a new session with `setsid()` before acknowledging startup ([AOSP `client/main.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/main.cpp#L179-L197)). This adapter invokes `adb` through `PATH`, so verify that the selected Platform Tools binary has the same process behavior before physical use. An exited client with a still-open output pipe is treated as incomplete. The socket transport connects only to IPv4 loopback and bounds each request/response frame by the existing wire caps.

Readiness keeps its five-second request deadline and one-second socket-release deadline. The separate 60-second reserve starts after the authorized session deadline and applies only to outstanding host-side forward cleanup. Each cleanup phase remains capped at five seconds within that reserve. It does not extend a request, connection, device observation or socket-release deadline.

Host command output and raw process errors are transient. Shared evidence must use sanitized outcome codes and opaque references; do not publish serials, build fingerprints, stderr, command output or local paths. The B1 session record must identify the reviewed host-adapter source, the procedure revision, and the APK source independently. The APK's `probeSourceCommit` must name the exact source revision used to build that APK; it must not be copied from the host adapter or procedure revision. Include the exact signed APK digest and signer, target/build, approved command effects and forward tuple, deadlines, evidence location and cleanup authority. Preserve runtime failure receipts and evidence-integrity checks; removing external receipt custody does not change those controls. No values are preapproved by this host-only checkpoint.

## 9. OS evidence readiness and observation prerequisites

The bounded Q7 helper and structural filter are shipped with deterministic tests. They retain sanitized record and field names, hierarchy, anonymized relationships, allowlisted package and component values, user/task associations, resumed and top-resumed representations, display/windowing and process fields, and recognized completion or timeout indicators. They discard unrelated application records and raw lines. Parser errors report a sanitized subtype and structural position. These controls support exploration only: no exact-build grammar or semantic profile is qualified, and a single snapshot cannot establish task or process continuity.

The matrix describes the evidence needed to assess feasibility under ADR-005 Q7/Q8/Q11 and ObserverV1 section 11.6. It adds no physical operation or acceptance criterion. Checkpoints must be specified in the reviewed session procedure before collection.

| Required OS evidence | Acquisition checkpoints | Current parser coverage | Ambiguity that blocks the assertion | Missing qualification proof |
|---|---|---|---|---|
| Target package, component and Android user ownership | At baseline and each relevant task/foreground observation | Sanitized allowlisted package/component values, user fields and record relationships; ownership semantics remain unqualified | Component or user absent, conflicting ownership, multiple target candidates | Exact-build source semantics and independently observed ownership |
| Task membership and task identity | Before and after each authorized transition for which task continuity is required | Activity/task hierarchy and anonymized record relationships; stable task identity and continuity are not established | Reused task number, missing membership or checkpoint, uncertain transition | Source-qualified task membership and evidence linking the same task across the required checkpoints |
| Resumed and distinct top-resumed state | At each relevant foreground checkpoint | Recognized field names, aliases and values are retained as structure; their exact-build meanings are unqualified | Resumed treated as top-resumed, conflicting activity records | Exact-build interpretation and independent target observations for both states |
| Display and windowing state | With each task/foreground checkpoint | Sanitized display/windowing fields and their observed structural relationships | Multiple displays/windows, unsupported mode or incomplete association | Qualified display/windowing facts sufficient to resolve foreground ambiguity |
| Package-scoped process identity and foreground state | At baseline and relevant before/after lifecycle checkpoints | A fixed process-list query can produce a target-package-only role/count and UID-match projection; lifecycle continuity is not established | PID reuse, missing process association or an unobserved lifecycle gap | Qualified OS process source, acquisition times and required corroborating visible-UI evidence |
| Complete, fresh acquisition and provenance | For every observation | Bounded output and sanitized exit, timeout, limit, parser-stage and completion indicators; no accepted exact-build completion contract | Truncation, stale observation, timeout, inconsistent binding or unsupported grammar | Exact-build completion contract and session/checkpoint timing evidence |

OS/O facts remain independent of host/H command receipts, probe-reported readiness or lifecycle callbacks, and visible-UI/U observations. Neither a matching PID nor a probe callback proves task continuity. Retain only sanitized target facts with opaque target/build references in shared evidence; identifying build values stay private.

Before collection, establish the selected target/build, prefer package-scoped sources and review authoritative format or Android/OEM source evidence where available. When source evidence cannot resolve the build's grammar or available facts, the owner may authorize a bounded exploratory observation. State the exact question, command, target, maximum acquisition count and timing. The existing Q7 command and section 4 size/time limits still apply; no unrestricted shell or additional diagnostic command is implied.

Review the exploratory acquisition/privacy path before running it: keep raw output only in bounded local memory, exclude it from logs, terminal transcripts, tool responses and shared chat, immediately discard unrelated records, and retain only sanitized target notes and acquisition provenance marked exploratory. A fully qualified exact-build semantic parser or completion marker is not required merely to investigate that format. If safe transient handling cannot be established, acquisition is BLOCKED. Timeout, overflow or failed acquisition supplies no usable target facts; record only the limitation. While completeness rules are unqualified, sanitized notes may describe observed syntax and open questions, but must make no claim of complete target state. Never present partial output as a complete observation.

An ordinary owner instruction can cover the complete exploratory scope; there is no packet per observation or separate receipt custodian. A preliminary observation grants no installation, launch, UID enrollment, forwarding or later B1 authority by implication. Retain no raw dump, stderr, unrelated records or raw-dump hash, and perform no automatic retry.

Use exploration to inform the concrete parser/acquisition change and its failure tests. Independently review the resulting exact-build semantics and completeness/error handling before admitting fresh complete observations as qualified OS evidence. Exploration and synthetic fixtures cannot satisfy B1/B2 assertions. Final signed-artifact provenance, peer-UID discovery/approval and verified restoration remain prerequisites for B1; offline preparation leaves physical B1 NOT_RUN.

An activity dump may not show how Android associates the probe window with a display and root task. The bounded exploratory helper also supports one fixed WindowManager snapshot: `adb -s <approved-target> shell dumpsys -t 3 window displays`. It writes a separate exploratory record and keeps target-linked Readiness structure with anonymized references. Target-bound output keeps the nearest display ancestor on each unique parent path and drops other display records with their attached fields and links. If no target component appears, it keeps only display headers, random local record references, and the presence of `displayId` and `rootTaskCount` fields. It redacts those values and drops task and window records and application identities. The fields show available display structure, but do not identify which display hosts the probe or retain the numeric task count. Structural counters in this header-only projection cover retained fields; dropped lines do not contribute. Android 12 AOSP prints display IDs and root-task counts in this dump, followed by the display hierarchy ([`DisplayContent`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android12-release/services/core/java/com/android/server/wm/DisplayContent.java), [`RootWindowContainer`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android12-release/services/core/java/com/android/server/wm/RootWindowContainer.java)). Those sources describe AOSP behavior; they do not establish the selected device's grammar or semantics. This snapshot has no qualified completion marker, so EOF and exit status alone do not establish a complete observation or support a qualification assertion.

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

The Q7 parser now keeps a bounded structural projection rather than requiring a guessed full-line grammar. It can retain record hierarchy, field names and values, anonymized relationships, and recognized completion or internal-timeout indicators while suppressing raw lines and unrelated application identities. It also reports sanitized parser stage, structural position and rejection subtype. These changes improve exploration and error diagnosis; they do not define the selected build's grammar, prove semantic completeness from EOF or exit status, or qualify an exact-build profile. No physical OS assertion is qualified by these parser capabilities.

Before using an acquisition/parser profile for formal qualification, resolve each of these gaps against the exact owner-selected build. Section 9 exploration may supply sanitized development notes while the profile is being designed:

1. Define the exact-build grammar and field meanings for package, component, Android user, task membership and identity, resumed versus top-resumed state, display, windowing and process facts.
2. Specify complete-output, timeout and error semantics, including how the timeout notice is rejected even if the command exits zero. Define behavior for truncation, malformed text, missing markers and partial transport.
3. Review the structural filter against exact-build observations. It must discard unrelated records before they can enter retained files, logs or shared evidence, and must keep unrecognized fields distinct from confirmed absence.
4. Define independent before/after OS checkpoints and their acquisition times for every required transition. A single sample, matching PID, probe callback or lifecycle event cannot establish task continuity.

If any required fact, filter or completion rule cannot be qualified, keep the OS assertion BLOCKED and dependent qualification checks NOT_RUN. The narrowly scoped exploratory path in section 9 may investigate the gap but cannot turn it into PASS.

### Historical target and identity-only preflight

Issue [#28](https://github.com/whatobiplays/Argus-ROM-Toolkit/issues/28) records the AYANEO Pocket Air Mini as a previously owner-selected candidate for that issue. Its authority does not carry into Issue #74. The owner selected the KONKR Pocket Advance for Issue #74. Its identity preflight established the exact build fingerprint, which remains in owner-private evidence; do not copy it into tracked or shared records.

The identity-only preflight is a separate, explicitly authorized observation using the same exact owner-selected serial for the two read-only commands listed in section 8:

```text
adb -s <owner-approved-target> get-state
adb -s <owner-approved-target> shell getprop ro.build.fingerprint
```

The owner's instruction must cover this selected target and the complete conditional two-command attempt. The current attended session can be its execution window; no separate appointment, packet digest, independent preflight reviewer or receipt custody is needed. Record the instruction reference, source/procedure reference, private target, acquisition time, host-monotonic start/finish, command counts and outcome. The fingerprint is an unobserved output before execution, not a value to invent or approve in advance. Record a skipped conditional command as NOT_RUN. Do not fill unrelated APK, UID, forwarding or Q7 forms for an attempt that uses none of them.

This preflight does not include `dumpsys`, UID discovery, forwarding, probe execution or any application action. A successful result establishes only target/build identity; physical B1 remains NOT_RUN. The existing private draft may be retained as preparation history; it need not be completed under the superseded packet/custody requirements. The owner's process-simplification approval is not an instruction to run the preflight, and no device operation is recorded by this change.
