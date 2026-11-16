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

Record restoration obligations before mutation. Remove only a forward proven session owned and still matching the approved tuple. Do not adopt pre-existing resources. An uncertain create, replacement, ownership or restoration leaves a durable blocker. Cleanup is not successful merely because a command exited zero. Further recovery requires exact owner authority.

## 6. Outcomes and review

Verified incorrect behavior is FAILED/NO-GO. Missing or uncertain evidence is BLOCKED. Dependent unattempted checks are NOT_RUN. Expected denial/cancellation tests can pass their control assertion without supplying successful Readiness evidence. Neither documentation nor synthetic observations can satisfy physical feasibility.

Require independent full-diff review before proposing physical use, and direct ChatGPT source/test inspection before technical readiness. No production activation, qualification repinning, B2 or merge is authorized by this document.

## 7. Build and CI artifact separation

The independent Gradle application exposes only the non-debuggable `probe` build type. Verify the generated task inventory and dry-run `testProbeUnitTest lintProbe assembleProbe` before relying on those task names. Run those tasks and the repository Android qualification and naming checks from the dedicated task checkout. Local JVM and Android SDK versions must be recorded with results.

Gradle produces an unsigned probe. CI signs a copy using a disposable key under runner-temporary private storage, verifies it offline and removes the temporary signing directory. Keys and passwords must not be committed, cached or uploaded. A CI signature is test evidence only. Physical admission requires a separately owner-approved signer and the exact final signed APK digest; rebuilding or signing changes the artifact identity.

The host artifact checker and injected workflow do not authorize device access. Existing public live-execution blocks remain binding.
