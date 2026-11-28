# Gradle dependency caching investigation

## 1. Decision

The owner-approved disposition is to keep production CI unchanged, enable no permanent Gradle dependency cache, and end hosted campaigns without a third attempt. The isolated local comparison showed that a verified local `modules-2` cache removed the target artifact body transfer in the warm trial. It does not establish GitHub cache-service behavior, PR write restrictions, recovery controls, or a hosted timing benefit.

Two hosted campaigns were attempted. The first completed the probe build but failed observer coverage, so cache save was skipped. The second failed dependency resolution and also skipped cache save. A concurrent ordinary CI run independently recorded HTTP 429 for `org.robolectric:nativeruntime-dist-compat:1.0.18`; the redacted experimental request evidence does not establish that status for either campaign. Results and identities are in §4.

Retain the proposed manual restore/save configuration for `~/.gradle/caches/modules-2` and its validation strategy as historical findings, not as a recommendation to implement. Bounded retries for confirmed dependency-resolution HTTP 429 responses may be considered only through separately approved future work. No retry was configured or tested.

## 2. Approved scope and provenance

| Record | Value |
| --- | --- |
| Task pin | `2026.11.25` |
| Repository | `whatobiplays/Argus-ROM-Toolkit` |
| Owner | `danielbyon`, GitHub user ID `327737` |
| Approval policy source revision | `8e391636cb50f9bfe6e8def2d0f54eeb65d1d157` |
| Owner final disposition | The owner explicitly accepted the no-change recommendation and campaign stop in the 2026-11-28 finalization authorization for task pin `2026.11.25`. The disposition is to keep production CI unchanged and enable no permanent Gradle dependency cache. |
| Approved release workflow run | `45612390118`, attempt 1 successful |
| Frozen context SHA-256 | `2e8c68b73ad8bc1f78750094dfeb19ab945cbed744012de42725060778f2f7ca` |
| Manifest SHA-256 | `31d94f3bdc98347268e51e7f726545668c7780aae015a99933df14b94f51bb3a` |
| Task worktree | `/Users/daniel/.codex/worktrees/issue-93-gradle-cache-investigation/Argus-ROM-Toolkit` |
| Branch | `codex/issue-93-gradle-cache-investigation` |
| Main baseline | `1823686d39f72b6d5701a7f25bdeed83cdcf727b` |
| Worktree HEAD at correction start | `adea61625b928babc33c4c5b26fc908f4961ad09` |
| Initial worktree state | Clean; the prior commit contained only this report |
| CodeGraph | Initialized in the task worktree; the index contained 561 files at the original inspection. |
| TokenSave | Initialized for the task branch; status selected that branch without fallback at the original inspection. |
| Serena | Activated on the task worktree at the original inspection. |
| GPT Repo MCP enrollment | The exact worktree path was absent from the configured 31 roots. No registration was changed, and no additional enrollment is required. |

The primary checkout remained on `main` at the recorded baseline. Existing Issue #28 worktrees and MCP registrations were left intact. GitHub evidence came through the `whatobiplays` connection, ID `link_6add2c3a8e9081919f368fc87b22c1e4`. Issue #93 was open with the `needs-triage` label and had no comments at the original inspection. This investigation did not change its state.

This finalization changes only this report and the description of PR #94. The local qualification and two hosted campaigns recorded below were conducted earlier under their own approvals; this update does not rerun them. No production workflow, dependency, build configuration, cache content, device, release artifact, issue state, or MCP registration was changed during finalization. No third hosted campaign or cache mutation is performed.

## 3. Current Android workflow behavior

The three Android jobs are in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml).

| Job | Gradle setup and tasks | Existing cache behavior |
| --- | --- | --- |
| `android-readiness-probe` ([workflow section](../../.github/workflows/ci.yml#L508)) | Temurin 17, Android SDK/build tools 36, wrapper 9.1.0-all. It runs `tasks --all`, a dry run of `testProbeUnitTest lintProbe assembleProbe`, then those tasks. | No explicit Gradle cache action or `GRADLE_USER_HOME` override. |
| `android-arm64-package` ([workflow section](../../.github/workflows/ci.yml#L305)) | Temurin 17 and Flutter; runs `just build-android-debug`. | `setup-java@v4` has no Gradle cache input. Flutter SDK and Pub caches are separate. |
| `android-qualification-release` ([workflow section](../../.github/workflows/ci.yml#L377)) | Temurin 17 and Flutter; runs release config-only, build, and verification steps. | `setup-java@v4` has no Gradle cache input. Flutter/Pub caches are separate. Uploaded APKs and qualification records are workflow artifacts. |

The relevant paths are separate:

- Gradle dependency metadata and artifacts: `$GRADLE_USER_HOME/caches/modules-2`.
- Gradle wrapper distributions: `$GRADLE_USER_HOME/wrapper/dists`.
- Robolectric runtime Android SDK repository: by default `~/.m2/repository`.
- Project outputs and build state: probe `build/` and project `.gradle/`.

The reviewed Android Gradle files do not enable the task-output build cache or configuration cache. Flutter/Pub caches cover different tools. Release signing and qualification provenance remain separate. The probe creates its disposable signing key and signed test copy outside dependency paths. Those files do not belong in a dependency cache.

The probe's task inventory and dry run happen before the actual task invocation. Both can configure the build and resolve dependencies. A comparison that starts timing at `testProbeUnitTest` could miss earlier downloads and warm the supposedly cold run first.

## 4. CI and experimental evidence

All three PR #92 attempts checked out synthetic merge commit `ef7b7282cd066f7eed5fa02dea3ba67687341ca3`. The PR head was `deae51998b54d9049944bab53de8a82bb8406ad9`; the base was `cfb01eef1b20d28ec99c087a8a38f12aaf039d09`.

| Run and attempt | Checked-out `GITHUB_SHA` | PR head | Base | Probe result |
| --- | --- | --- | --- | --- |
| [PR #92, attempt 1](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/1) | `ef7b7282cd066f7eed5fa02dea3ba67687341ca3` | `deae51998b54d9049944bab53de8a82bb8406ad9` | `cfb01eef1b20d28ec99c087a8a38f12aaf039d09` | Failed: Maven Central returned HTTP 429 for `org.robolectric:nativeruntime-dist-compat:1.0.18` at `2026-11-26T06:45:08.5066578Z`. |
| [PR #92, attempt 2](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/2) | Same synthetic merge commit | Same PR head | Same base | Failed with HTTP 429 for the same artifact at `2026-11-26T07:09:49.6951993Z`. |
| [PR #92, attempt 3](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/3) | Same synthetic merge commit | Same PR head | Same base | Passed: `BUILD SUCCESSFUL in 1m 6s`; 58 actionable tasks executed. |
| [Post-merge run, attempt 1](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45801378699/attempts/1) | `1823686d39f72b6d5701a7f25bdeed83cdcf727b` | — | — | Failed with HTTP 429 for the same artifact at `2026-11-26T10:28:09.7239385Z`. |
| [Post-merge run, attempt 2](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45801378699/attempts/2) | Same main commit | — | — | Passed: `BUILD SUCCESSFUL in 57s`; 58 actionable tasks executed. Other applicable jobs passed on this attempt. |

Within PR #92, attempt 3 passed on the same synthetic merge, base, and PR-head identities after attempts 1 and 2 failed. The post-merge retry passed on the same main SHA after its first attempt failed. These were unchanged-source retries; they do not establish a cache effect. Differences in hosted locations and setup details also prevent a controlled timing comparison.

All five historical logs include the generic runner line `Cache mode: write`. None exposes a Gradle cache key, restore, save, hit, miss, or byte count. At the original investigation, the GitHub connection did not provide the cache-listing endpoint. The later read-only snapshot in §4.1 found six existing entries and no Issue #93 key, but still does not establish any Gradle cache hit or save. The generic runner line does not establish that Gradle dependencies were cached.

At the original investigation, the local Gradle home contained the named artifact and Gradle 9.1.0 wrapper distributions. The artifact occupied 159,130,191 bytes across two local files. That is local state, not a hosted cache or CI transfer measurement. The Mac used ARM64 and Java 25 by default; the probe runner uses Ubuntu and Temurin 17. No controlled comparison had been run at that time. A later isolated qualification used fresh Gradle homes and is summarized below; the original local Gradle home was not used as its seed.

### 4.1 Later qualification and hosted campaigns

**First hosted campaign.** Push run [46138508708](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/46138508708), attempt 1, used branch `codex/issue-93-gradle-cache-pilot` at `0995bb6d2e37e487f6309f015065cd02e5dfd0e6`. One of 18 jobs started; the other 17 were skipped. Task inventory and dry-run had complete observer coverage. The probe build exited successfully in 57.104 seconds, but its observer coverage had ten `external_resource_start_decode` errors. The observer recorded a 159,128,857-byte body transfer for `org.robolectric:nativeruntime-dist-compat:1.0.18`; the resulting cached file digest was not verified. The run therefore produced no trusted seed. Cache save and seed-manifest publication were skipped. The retained run artifact is [15260885934](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/46138508708/artifacts/15260885934). The pinned campaign record is also available in the [observer-repair candidate](https://github.com/whatobiplays/Argus-ROM-Toolkit/blob/fb9c662d4416b9eebf2ca5c68cfbb7ad9ab693c7/docs/qualification/gradle-dependency-cache-pilot-candidate.md#L62-L65).

**Isolated local qualification.** The observer repair qualified at candidate HEAD `4e3bbd2de468d3a5975d535465cc986f03cffdc9` on macOS 27.2.1 arm64 with Gradle 9.1.0 and Temurin 17.0.21.1+2. Each cold and warm trial comprised task inventory, dry-run, and actual probe-build invocations. All six invocations had complete observer coverage and no observer errors. In each actual probe build, `testProbeUnitTest`, `lintProbe`, and `assembleProbe` completed successfully. The cold trial recorded one completed target body transfer of 159,128,857 bytes. The resulting cached file had the same size and SHA-256 `a6c34d92c990754e5aee076032a36f8e38fcacb5eb878ebe0a324509f3864eef`. The warm trial recorded no Gradle external-resource body transfers.

The cold and warm `modules-2` manifests matched at SHA-256 `28a7cd1bebdcc5f5040c4fc24a143097f603a5f581ac8849f1c4bc4b8d6459ab`. Each covered 659 files, 507,209,725 manifest bytes, and 507,209,742 expanded bytes. The warm trial copied the verified directory into a fresh Gradle home. Each wrapper directory and Robolectric Maven repository started empty. Each trial downloaded a 721,155,298-byte wrapper distribution, and each isolated Robolectric repository grew by four files and 126,901,498 bytes. Probe-build time was 46.432 seconds cold and 34.990 seconds warm; total probe wall time was 121.994 and 117.763 seconds. This was one local cold/warm pair and does not estimate hosted performance. Both unsigned APKs were 2,148,781 bytes with the same SHA-256, `57f242dd8e333f6c54196193349e42b9270f96c17d93f38ad984bd6d3a1e487c`. Disposable signing and signed-APK inspection passed. The retained qualification summary has SHA-256 `f1bf4b47e903ef217f3c0023f779e59e218b0d8ca3d9061d5b899e98926fbfe9`; its measurements are recorded in the [pinned candidate summary](https://github.com/whatobiplays/Argus-ROM-Toolkit/blob/fb9c662d4416b9eebf2ca5c68cfbb7ad9ab693c7/docs/qualification/gradle-dependency-cache-pilot-candidate.md#L67-L71).

**Second hosted campaign.** Push run [46158618700](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/46158618700), attempt 1, used branch `codex/issue-93-gradle-cache-observer-repair`, campaign ID `gradle-dependency-cache-observer-repair-v2`, and source HEAD `fb9c662d4416b9eebf2ca5c68cfbb7ad9ab693c7`. The task inventory (40.331 seconds) and dry-run (8.154 seconds) completed. The probe build ran for 35.106 seconds and failed at `:generateProbeUnitTestLintModel` during runtime dependency resolution. The observer recorded four zero-byte error events for the target coordinate, including three identified JAR-body attempts, and one completed 1,334-byte metadata read; that metadata read was not a JAR body transfer. The redacted evidence does not establish an HTTP status for the experimental requests. The `modules-2` directory contained 622 files and 233,329,272 expanded bytes, with manifest SHA-256 `089204ebbd4d1e7034e146f37ba7a15685f8e201eeb3cb197595e54659f78d7f`. The wrapper distribution added 721,155,298 bytes. Cache save was skipped, no trusted seed was published, and the PR consumer and paired hosted warm trials did not run. The retained artifact is [15268772492](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/46158618700/artifacts/15268772492).

**Concurrent ordinary CI.** Run [46158618947](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/46158618947), on the same source HEAD and during the second campaign, independently logged HTTP 429 from Maven Central for `org.robolectric:nativeruntime-dist-compat:1.0.18`. It failed at the same dependency-resolution task. This confirms a contemporaneous 429 for the ordinary CI request; it does not supply the missing status for the separate experimental requests.

**Hosted cache inventory.** The read-only inventory on 28 November 2026 showed six active entries totaling 5,941,195,572 bytes, all main-branch Flutter SDK or Pub caches, and no Issue #93 pilot key. The owner approved GitHub's documented 10 GB and seven-day defaults as the planning assumption; configured limits remain independently unverified. The snapshot left 4,058,804,428 bytes below 10 GB before new entries. The preflight and entry breakdown are retained in the [pinned candidate record](https://github.com/whatobiplays/Argus-ROM-Toolkit/blob/fb9c662d4416b9eebf2ca5c68cfbb7ad9ab693c7/docs/qualification/gradle-dependency-cache-pilot-candidate.md#L120-L128). Usage can lag, concurrent cache growth is possible, and GitHub may evict entries. Neither campaign saved an Issue #93 cache entry.

## 5. Dependency path and existing integrity controls

The probe declares `org.robolectric:robolectric:4.16.1` in [its build file](../../android-readiness-probe/build.gradle.kts#L20). Its settings include Maven Central. Read-only published metadata proves this path:

| From | To | Metadata scope |
| --- | --- | --- |
| `org.robolectric:robolectric:4.16.1` | `org.robolectric:shadows-framework:4.16.1` | compile |
| `org.robolectric:shadows-framework:4.16.1` | `org.robolectric:nativeruntime:4.16.1` | compile |
| `org.robolectric:nativeruntime:4.16.1` | `org.robolectric:nativeruntime-dist-compat:1.0.18` | runtime |

The edges appear in the published [Robolectric POM](https://repo.maven.apache.org/maven2/org/robolectric/robolectric/4.16.1/robolectric-4.16.1.pom), [shadows-framework POM](https://repo.maven.apache.org/maven2/org/robolectric/shadows-framework/4.16.1/shadows-framework-4.16.1.pom), and [nativeruntime POM](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime/4.16.1/nativeruntime-4.16.1.pom). Their Gradle module metadata agrees. The published [`nativeruntime-dist-compat:1.0.18` POM](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime-dist-compat/1.0.18/nativeruntime-dist-compat-1.0.18.pom) has no dependency entries. Its `.module` URL returned HTTP 404 during this inspection, so no further transitive edge is established. CI reported the failure in `:probeUnitTestRuntimeClasspath` while configuring `:generateProbeUnitTestLintModel`, consistent with the runtime-scoped edge.

This is ordinary Gradle dependency resolution, so a successfully downloaded module descriptor and artifact belong in Gradle's `modules-2` dependency cache. The cache is technically relevant to the reported failure. The available logs do not show a restored cache or prove that a future cache hit would prevent another HTTP 429.

No Gradle dependency lockfile, `dependencyLocking` configuration, or `gradle/verification-metadata.xml` was found in the reviewed project files. Dependency verification is not configured there. The probe wrapper pins Gradle 9.1.0-all but has no `distributionSha256Sum` ([wrapper properties](../../android-readiness-probe/gradle/wrapper/gradle-wrapper.properties#L1)). The Flutter Android wrapper has the same distribution URL and no checksum property. The inspected `.github/workflows/ci.yml` does not call Gradle's wrapper-validation action. This source review does not establish whether another workflow or external repository policy validates the wrapper JAR.

These controls cover different files. `distributionSha256Sum` checks the downloaded wrapper distribution. A wrapper JAR validator checks the JAR. Gradle dependency verification checks resolved components against checked-in metadata. None was found in the reviewed probe/project files. The Gradle-specific action below validates wrapper JARs by default, but does not add the missing distribution checksum or dependency verification metadata.

## 6. Robolectric runtime downloads

Robolectric has a separate path for Android framework SDK JARs during test execution. In 4.16.1, `DefaultSdkProvider` selects `org.robolectric:android-all-instrumented` by default, or `android-all` when `robolectric.usePreinstrumentedJars` is disabled. It asks Robolectric's `DependencyResolver` for a local file. See [Robolectric 4.16.1 DefaultSdkProvider](https://github.com/robolectric/robolectric/blob/robolectric-4.16.1/robolectric/src/main/java/org/robolectric/plugins/DefaultSdkProvider.java#L118-L149).

The default `MavenDependencyResolver` uses its own repository settings and local repository. Its default repository is `https://repo1.maven.org/maven2`. It selects `maven.repo.local`, Maven settings, or `~/.m2/repository`. Its `MavenArtifactFetcher` downloads SDK POM and JAR files with `.sha512` files, validates both checksums, and installs them locally ([settings](https://github.com/robolectric/robolectric/blob/robolectric-4.16.1/plugins/maven-dependency-resolver/src/main/java/org/robolectric/MavenRoboSettings.java#L19-L38), [resolver](https://github.com/robolectric/robolectric/blob/robolectric-4.16.1/plugins/maven-dependency-resolver/src/main/java/org/robolectric/internal/dependency/MavenDependencyResolver.java#L121-L142), [fetcher](https://github.com/robolectric/robolectric/blob/robolectric-4.16.1/plugins/maven-dependency-resolver/src/main/java/org/robolectric/internal/dependency/MavenArtifactFetcher.java#L64-L117)). If the JAR already exists locally, the fetcher returns before checking downloaded checksums.

This resolver is separate from Gradle's `modules-2` cache. CI failed during Gradle runtime-classpath configuration, before Robolectric executed tests. Logs do not establish whether the SDK resolver ran on successful attempts or which SDK artifacts it requested.

Do not include `~/.m2/repository` in the proposed Gradle cache. A restored local artifact would take Robolectric's existing-file path and skip the remote SHA-512 comparison. Record these runtime downloads separately in a future experiment. If full job-time attribution later requires caching them, assess that as a separate experiment with its own integrity design and authorization.

## 7. Provider comparison

Each option keeps the probe's existing Gradle 9.1.0 wrapper and AGP 9.0.1 pin. The cache mechanisms do not change dependency declarations or those versions. The `setup-java` option would separately upgrade its action from v4 to v6; that action upgrade was not tested as part of this investigation.

### 7.1 `gradle/actions/setup-gradle` v6.4.1 Enhanced

- The default provider uses a Gradle-specific cache service with fine-grained entries, deduplication, cleanup, and a workflow cache summary.
- It saves and restores `$GRADLE_USER_HOME/caches` and `$GRADLE_USER_HOME/notifications` by default. The include/exclude filters can narrow the Gradle User Home portion to `caches/modules-2`. It also handles wrapper distributions at `$GRADLE_USER_HOME/wrapper/dists`, generated Gradle API jars under `$GRADLE_USER_HOME/caches/<version>/generated-gradle-jars`, Java toolchains under `$GRADLE_USER_HOME/jdks`, and Gradle distributions installed by `gradle-version`. The docs do not publish the local path for action-installed Gradle distributions, nor the exact keys for independently cached artifacts. The include filter does not establish a modules-only boundary; verify and measure the other entries if this provider is used.
- The Gradle User Home key is `${cache-protocol}-gradle|${runner-os}|${job-id}[${matrix-and-workflow-hash}]-${git-sha}`. Restore order is an exact OS/job/workflow/matrix/SHA match, then the newest match for the same OS/job/workflow/matrix, the same OS/job, and the same OS. It searches the current branch before the default branch. Each new commit SHA changes the exact key; compatible prior entries can still restore through these broader matches.
- `gradle-home-cache-strict-match: true` is experimental. The docs define it as preventing Gradle User Home restoration from other jobs; they do not say whether it also isolates independently cached artifacts. By inference from the documented same-job lookup and branch search, strict matching still permits a same-job default-branch fallback.
- By default, default-branch jobs write and other branches read. `cache-read-only` can make that policy explicit. The post action runs unless the job is cancelled. Cache cleanup defaults to `on-success`; the docs describe cleanup behavior, but no success-only save gate. Verify save behavior for a failed job before relying on it.
- Enhanced has the strongest cleanup and storage deduplication. It uses proprietary technology, free for public repositories. Its broad artifact behavior and shared restore keys add more moving parts than this one-job investigation needs. Its enhanced caching implementation is not published for independent source inspection.

### 7.2 `gradle/actions/setup-gradle` v6.4.1 Basic

- The open-source Basic provider uses GitHub's cache service. It stores whole `~/.gradle/caches` and `~/.gradle/wrapper` directories. It has no path filters, cleanup, or artifact-level deduplication. Entries consume standard GitHub cache storage and are subject to its retention and eviction policy.
- Its key is `setup-java-${RUNNER_OS}-${arch}-gradle-${hash}`. The hash includes Gradle build files, wrapper properties, selected `buildSrc` files, version catalogs, and `versions.properties`; it omits `gradle.properties`. Basic has no prefix restore keys, so a changed key starts empty, although an exact key can still be restored from the same or default branch. The key has no job discriminator, so another job with the same key and path may restore it.
- Default-branch jobs write by default; other branches read. The post hook runs unless the job is cancelled. The docs do not specify a success-only save gate.
- Whole-directory archives can include wrappers and unrelated Gradle cache content. Strict matching does not apply because Basic has no restore keys.

### 7.3 `actions/setup-java` v6.3.0 Gradle caching

- `cache: gradle` defaults to `~/.gradle/caches`. `cache-path` can narrow the primary dependency path to `~/.gradle/caches/modules-2`, but changing the path does not change the key.
- The primary key is `setup-java-${RUNNER_OS}-${node-arch}-gradle-${file-hash}`. The Gradle hash patterns are `**/*.gradle*`, `**/gradle.properties`, `**/gradle-wrapper.properties`, `buildSrc/**/Versions.kt`, `buildSrc/**/Dependencies.kt`, `gradle/*.versions.toml`, and `**/versions.properties`. The implementation uses no prefix restore keys; an exact match can still come from another job or the default branch. The dependency key does not include the selected JDK identity.
- Wrapper distributions are a separate entry at `~/.gradle/wrapper`, keyed `setup-java-${RUNNER_OS}-${node-arch}-gradle-wrapper-${wrapper-properties-hash}` from `**/gradle-wrapper.properties`. JDKs are a third entry at a runner tool-cache path under `RUNNER_TOOL_CACHE`; the exact subdirectory varies with the JDK identity. Its key is `setup-java-jdk-v1-${RUNNER_OS}-${architecture}-${identity-hash}`, where the identity includes distribution, package type, normalized architecture, resolved version, source identity, and signature-verification policy. JDK caching is enabled whenever dependency caching is enabled unless `cache-jdk: false`. All three entries consume standard GitHub cache storage; the action does not add Gradle-style artifact deduplication or stale-entry cleanup.
- `cache-read-only: true` disables saves for dependency, wrapper, and JDK caches. It defaults to false, so the action does not itself enforce default-branch push-only writes. The post-cleanup implementation reads `job-status` (defaulted from `${{ job.status }}`) and skips all saves unless the job succeeded. On a successful job, it skips an exact hit and saves after a miss or partial restore.
- This option would require upgrading the existing `setup-java@v4` step to v6. Its separate wrapper and JDK entries broaden the pilot.

### 7.4 Manual `actions/cache` restore and save

- A narrow pilot can restore only `~/.gradle/caches/modules-2`. Compose the key from OS, architecture, JDK 17, Gradle 9.1.0, a hash of all probe Gradle inputs, and the commit SHA. A restore prefix with the same input hash can reuse the most recent compatible prior entry. Do not add a broader prefix across dependency-input changes.
- Restore checks the exact key, then ordered prefixes; the newest matching partial entry wins. GitHub searches the run's branch first and then the default branch. PRs can restore from the base/default cache. A cache written by a PR is scoped to its merge ref.
- Split restore and save actions make the policy explicit. Restore never saves. A separate save step can require `success()` and a `push` to `refs/heads/main`; PRs get restore only. Reuse the restore action's primary key for saving. The combined `actions/cache@v4` action saves in a `success()` post hook; `save-always` is deprecated.
- GitHub entries are immutable. A new commit-specific key can create a full archive on every successful push. Old entries remain until expiration or eviction, so storage needs monitoring. This action does not deduplicate artifacts or clean stale dependency entries.
- Manual caching has the most custom maintenance: keep the key inputs, path, save condition, and recovery procedure current. It adds no wrapper validation or dependency verification.

### 7.5 Shared cache and maintenance rules

Jobs in the same repository and branch can share compatible entries when their keys and cache versions match. The manual pilot's `probe` namespace separates it from unrelated Android jobs that use another key. Pull requests can read base-branch caches, and any reader can inspect cache contents. GitHub does not sign or verify cached files. Keep secrets, signing data, signed APKs, and private artifacts outside every path accessible to PR workflows.

Read-only cache access prevents saving changes back to GitHub's cache. It does not make the restored `modules-2` directory read-only to Gradle during the job.

Do not stack providers over the same Gradle home. `setup-gradle`, `setup-java cache: gradle`, and manual `actions/cache` can restore and save overlapping paths. Combining them can duplicate downloads, compete on saves, expand paths, and make invalidation unclear. Flutter/Pub caches do not overlap with these Gradle paths.

### 7.6 Bounded dependency-fetch retries

A bounded retry for a confirmed HTTP 429 during dependency resolution is a separate mitigation from caching. It may recover from a transient Maven Central response without restoring a cache, but it does not reduce downloads and could repeat the full probe task sequence. Any later retry policy should cap attempts, preserve each failure, and apply only to the identified dependency-resolution response. It must not retry or mask test, lint, build, signing, or artifact-verification failures. No retry policy was configured or tested.

## 8. Historical pilot proposal and illustrative workflow diff

The investigation's proposed pilot was a manual restore/save pair for the probe's `modules-2` directory. It limits the archive to dependency files, avoids wrapper and JDK caches added by the Gradle-specific alternatives, and gives the workflow an explicit write gate. It does not cryptographically verify cached dependencies. The repository has no lock or verification metadata, so trusted seeds and read-only PR access were essential to the proposed trust boundary. The owner has accepted the no-change recommendation; this design remains historical and is not approved for implementation.

The diff is illustrative only. It is not an executable workflow or authorized change. Restore before the existing `tasks --all` step; save after all existing Gradle commands.

```diff
# Illustrative only; not an executable or authorized workflow change.
@@ android-readiness-probe job, before first Gradle command
+      - name: Restore probe Gradle dependencies
+        id: gradle-modules
+        continue-on-error: true
+        uses: actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
+        with:
+          path: ~/.gradle/caches/modules-2
+          key: gradle-deps-probe-v1-${{ runner.os }}-${{ runner.arch }}-jdk17-gradle9.1.0-${{ hashFiles('*.gradle*', 'settings.gradle*', 'gradle.properties', 'gradle/**', 'buildSrc/**', 'build-logic/**', 'gradle.lockfile', 'android-readiness-probe/**/*.gradle*', 'android-readiness-probe/**/gradle.properties', 'android-readiness-probe/**/gradle-wrapper.properties', 'android-readiness-probe/**/gradle/*.versions.toml', 'android-readiness-probe/**/gradle.lockfile', 'android-readiness-probe/**/gradle/verification-metadata.xml') }}-${{ github.sha }}
+          restore-keys: |
+            gradle-deps-probe-v1-${{ runner.os }}-${{ runner.arch }}-jdk17-gradle9.1.0-${{ hashFiles('*.gradle*', 'settings.gradle*', 'gradle.properties', 'gradle/**', 'buildSrc/**', 'build-logic/**', 'gradle.lockfile', 'android-readiness-probe/**/*.gradle*', 'android-readiness-probe/**/gradle.properties', 'android-readiness-probe/**/gradle-wrapper.properties', 'android-readiness-probe/**/gradle/*.versions.toml', 'android-readiness-probe/**/gradle.lockfile', 'android-readiness-probe/**/gradle/verification-metadata.xml') }}-
+
+      - name: Clear a failed cache restore
+        if: steps.gradle-modules.outcome == 'failure'
+        run: |
+          rm -rf -- "$HOME/.gradle/caches/modules-2"
+          test ! -e "$HOME/.gradle/caches/modules-2"
+
+      # Keep the existing inventory, dry-run, and actual Gradle task steps here.
+
+      - name: Save probe Gradle dependencies
+        if: >-
+          success() &&
+          steps.gradle-modules.outcome == 'success' &&
+          steps.gradle-modules.outputs.cache-hit != 'true' &&
+          github.repository == 'whatobiplays/Argus-ROM-Toolkit' &&
+          github.event_name == 'push' &&
+          github.ref == 'refs/heads/main'
+        uses: actions/cache/save@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
+        with:
+          path: ~/.gradle/caches/modules-2
+          key: ${{ steps.gradle-modules.outputs.cache-primary-key }}
```

The key separates this probe cache from other Android jobs with the `probe` namespace, OS, architecture, JDK, Gradle version, dependency-input hash, and source commit. It hashes the standalone probe's Gradle scripts, properties, wrapper configuration, version catalogs, and lock/verification files, plus repository-root Gradle configuration and shared `buildSrc`/`build-logic` paths. Its restore prefix keeps the same platform and input hash, so it can restore a prior commit's entry only when those inputs match. Changing the input hash or `v1` namespace invalidates the entry. GitHub's cache version also incorporates path and compression format. The sketch pins both cache steps to the inspected v4 source commit.

The key intentionally excludes probe Kotlin sources and the Android manifest. In the reviewed standalone build, `settings.gradle.kts` declares the repositories and `build.gradle.kts` declares the plugin and dependencies directly; source contents do not determine those coordinates. The cache stores Gradle module metadata and artifacts, not compiled outputs. A source edit can change the APK, but that output is not restored by this pilot. If future build logic derives plugin or dependency coordinates from source or generated data, include those inputs in the key before piloting.

A normal miss proceeds to Gradle's configured repositories. A failed archive restore removes only `modules-2` and verifies the path is absent before Gradle runs. If removal fails, the cleanup step fails and later Gradle steps do not run. Record that run as a restore error, not a warm hit. If Gradle rejects restored content or a task fails in a way consistent with cache corruption, retain the failure and retry under a new namespace after review. Do not suppress dependency, checksum, test, lint, build, or signing failures. A cache that extracts successfully but contains semantically corrupt files may not be detected before Gradle uses them.

The wrapper distribution stays outside the cache and downloads on each fresh runner. Measure its download separately from dependency restore and Gradle tasks. Robolectric's `~/.m2` resolver also stays outside the cache because its existing-file path skips the remote checksum comparison.

## 9. Historical experiment design and remaining qualification gaps

The isolated local cold/warm comparison was completed as an observer qualification with fresh Gradle homes and a verified local `modules-2` seed. It confirmed local dependency reuse and matching unsigned APK digests; the measured sizes and timings are in §4.1. This demonstrates that the local comparison was feasible. It does not exercise GitHub cache restore/save, hosted runner behavior, cache branch scope, PR write restrictions, or hosted recovery.

The two hosted campaigns did not produce a trusted seed or a successful warm restore. The first probe build succeeded but observer validation failed and save was skipped. The second probe build failed dependency resolution and save was skipped. The PR consumer, failed-job save behavior, eviction and invalidation, archive corruption recovery, and hosted output comparison remain unrun. The redacted experimental records do not establish HTTP 429 for the experimental requests, even though the concurrent ordinary CI run confirmed that status for the exact dependency.

The cold-seed vulnerability remains unresolved: until a trusted cold run completes dependency resolution, observer validation, manifest verification, and save, later jobs have no usable seed. A transient resolution failure at that first step prevents cache creation and leaves the next attempt exposed to the same cold download. Eviction or dependency-input invalidation can recreate that condition even after a successful seed. Local cache reuse did not test or remove this hosted failure mode.

The owner-approved stop decision reflects the measured limits and accepted no-change recommendation. It does not recast missing evidence as technical infeasibility or as a pass. No third campaign is planned or authorized.

The table below preserves the original hosted validation cases and their actual status:

| Proposed hosted case | Actual result and remaining evidence |
| --- | --- |
| Cold trusted seed | Attempted twice. The first campaign's build passed but observer validation failed; the second failed dependency resolution. Both saves were skipped, so no trusted seed exists. |
| Warm restore and subsequent save | No hosted warm restore occurred. No hosted cache hit, matched key, restore/save duration, or cache transfer size was measured. |
| Pull request | The PR consumer did not run. PR restore scope and write restrictions remain unqualified. |
| Failed job and rerun | Both campaign saves were skipped after earlier failures. Cache-service write restrictions and retry behavior were not tested by these outcomes. |
| Missing or evicted entry | The cold attempts demonstrate dependency resolution without a usable seed; a controlled eviction test and successful miss-recovery run were not performed. |
| Dependency or toolchain change | No hosted invalidation comparison was performed. |
| Failed archive or suspect contents | Archive corruption, cleanup failure, semantic corruption, and namespace recovery were not tested on GitHub Actions. |
| Artifact verification | Local unsigned APKs matched by SHA-256, and a separate disposable signed copy passed inspection. Hosted output equivalence was not measured. |

The original measurement protocol is retained below as an investigation finding. It is not an active campaign plan. The local cold/warm qualification and two incomplete hosted seed attempts are described above; the remaining hosted cases were not executed.

1. Bind a trusted seed: use a successful trusted `push` run on the default branch at the approved source identity. Record repository, workflow revision, source SHA, event/ref, run ID and attempt, action versions or SHAs, Gradle-input hash, path, primary/matched keys, branch scope, toolchain, and task outcomes. A PR run must not create the seed. If seed SHA differs from the measured SHA, require the complete Gradle-input hash to match and record both identities.
2. Use fresh trials: each cold/warm run gets a fresh checkout and hosted runner. Hold source SHA, runner image, Java 17 distribution/version, Android SDK/build tools 36, wrapper 9.1.0-all, and task sequence constant. Run at least three matched cold/warm pairs. Use a fresh cache namespace or skip restore for cold runs; do not delete or overwrite shared caches to manufacture a miss.
3. Separate wrapper effects: keep wrapper distributions outside the dependency cache. Start observation before invoking the wrapper. Record wrapper download/cache state and duration for each trial. Keep wrapper identity constant and report pairs broken by runner-image or distribution changes.
4. Start observation before Gradle: capture timestamps and cache state before the first wrapper invocation, including `tasks --all`, dry run, and actual tasks. Record total job time, each invocation's start/end, dependency-resolution events, cache match, matched key, save result, and compressed transfer size plus restored path size when exposed. The restore action exposes exact-hit, primary-key, and matched-key outputs; it does not promise a byte-count output. Mark unavailable measurements as unavailable.
5. Verify execution: start with a clean checkout and no project outputs. Keep task-output and configuration caches disabled. Inspect logs and task outcomes to confirm test, lint, and assembly actions executed. Any `FROM-CACHE`, skipped, or up-to-date task that replaces measured work invalidates that task's comparison. A cache hit alone does not prove the work ran.
6. Record Robolectric separately: capture SDK coordinates, repository activity, download time, and checksum outcomes from Robolectric's resolver. Do not cache `.m2` in this pilot. Those downloads remain a separate source of job-time variation.
7. Compare outputs: record each successful trial's unsigned probe APK path, size, and SHA-256. Compare cold and warm digests. Verify any disposable signed artifact separately on a copy outside cached paths; record signature verification and keep its temporary key out of the cache.
8. Keep failed pairs: retain every failed cold/warm run, rerun, log, cache summary, task outcome, and artifact digest. Mark incomplete pairs incomplete; do not drop failures from timing or reliability summaries. Preserve run IDs and source identities with the comparison manifest.
9. Roll back cleanly: if the authorized pilot fails or is no longer needed, stop writes and revert only the pilot workflow commit through a normal forward-moving commit. Leave immutable entries to expire or be evicted. For a suspect cache, bump the namespace, for example `v1` to `v2`, and repeat from a fresh miss while retaining the failed evidence.

The proposed cache-path trust boundary was ordinary public dependency artifacts under `modules-2`. It required trusted default-branch pushes as the only writers and PR restore-only behavior, with no PR save step. Credentials, signing inputs, task outputs, APKs, qualification records, wrapper distributions, Android SDK images, and `.m2` files stay outside the proposed cache. GitHub cache content is not signed, and Gradle verification metadata is absent. This proposal relied on trusted writers and ordinary Gradle resolution; it did not claim cryptographic verification of cache contents. Hosted enforcement of those rules remains unqualified.

## 10. Approved PAC and TAC mapping

### PAC criteria

| ID | Approved criterion | Evidence status | Evidence or remaining limit |
| --- | --- | --- | --- |
| PAC-1 | Document current caching behavior across all three Android jobs. | Complete as documentary review | The three jobs and their Gradle, Flutter/Pub, and artifact behavior are recorded above. |
| PAC-2 | Establish the available evidence for recurring dependency downloads and failures. | Partial; limitation accepted for investigation closeout | Historical attempts include three HTTP 429 failures and two later passes on unchanged source. The local cold/warm evidence is not hosted evidence. The two hosted campaigns did not produce a trusted seed; the concurrent ordinary CI run confirmed HTTP 429 for the exact target, but the experimental request status remains unavailable. The cache snapshot and owner-approved default-limit assumption are recorded above; configured limits remain unverified. |
| PAC-3 | Compare maintained caching approaches, including their security and operational trade-offs. | Complete as documentary review | Enhanced, Basic, setup-java v6, manual actions/cache, and no change are compared. No provider was configured or run. |
| PAC-4 | Produce an evidence-based recommendation, including no change if appropriate. | Complete as owner-approved no-change recommendation | Keep production CI unchanged, do not enable permanent Gradle dependency caching, and do not conduct a third hosted campaign. Any bounded retry for confirmed HTTP 429 responses requires separately approved future work. |
| PAC-5 | Propose a narrowly scoped configuration and cold/warm validation strategy. | Design retained; hosted validation incomplete | The historical proposal narrows the cache to modules-2. The local cold/warm qualification passed its observer, task, transfer-correlation, and output-digest checks. Hosted seed creation, warm restore, PR consumption, and cache-service behavior were not qualified. |
| PAC-6 | Identify residual risks, measurement limitations and required follow-up authorization. | Complete as documentary review; hosted risks remain | The cold-seed vulnerability, eviction and invalidation risk, cache trust boundary, local/hosted measurement limits, and unverified configured limits are documented. The owner accepted ending campaigns with these limits outstanding. |

### TAC criteria

| ID | Approved criterion | Evidence status | Evidence or remaining limit |
| --- | --- | --- | --- |
| TAC-1 | Bind investigation evidence to exact source, workflow, run and toolchain identities. | Complete as documentary review | PR head, base, synthetic merge SHA, post-merge SHA, workflow runs, wrapper, Java, and Android SDK identities are distinguished. |
| TAC-2 | Distinguish dependency caching from task-output and Flutter caching. | Complete as documentary review | Gradle `modules-2`, wrapper distributions, build outputs, Flutter/Pub, Android SDK downloads, and workflow artifacts are separated. |
| TAC-3 | Establish a defensible experimental methodology without conflating cache hits with skipped work. | Partially qualified; hosted measurement criteria remain unmet | The local observer bound evidence to each invocation, verified the target transfer against the cached-file digest, confirmed warm transfer absence, retained task outcomes, and matched unsigned APK digests. Neither hosted campaign produced a valid seed or warm trial; PR cache behavior remains untested. |
| TAC-4 | Preserve all existing CI, security, signing and qualification invariants. | Source/document review complete; hosted runtime validation incomplete | Production CI and dependencies remain unchanged. The local disposable signed copy passed inspection. Hosted PR trust and recovery controls remain unqualified. |
| TAC-5 | Make no unauthorized workflow, dependency, cache-policy or product changes. | Met for finalization | This finalization changes only the report and PR description. Earlier hosted campaigns had separate authorization; no third campaign, cache mutation, workflow change, or dependency change was performed. |
| TAC-6 | Obtain independent non-authoring review of the final investigation and its conclusions. | Independent review is a commit and publication gate | The final report digest, reviewer identity, coverage, findings, dispositions, and validation results are recorded in the PR description. |

Closing this investigation under the owner-approved limitation outcome does not turn failed or unexecuted hosted criteria into passes. It does not establish hosted cache readiness, close Issue #93, or authorize merging PR #94.

## 11. Sources

1. [Gradle dependency cache, Gradle 9.1](https://docs.gradle.org/9.1.0/userguide/dependency_caching.html), [build cache](https://docs.gradle.org/9.1.0/userguide/build_cache.html), and [configuration cache](https://docs.gradle.org/9.1.0/userguide/configuration_cache_enabling.html).
2. [Gradle setup-gradle v6.4.1 documentation](https://github.com/gradle/actions/blob/v6.4.1/docs/setup-gradle.md) and [action inputs and post hook](https://github.com/gradle/actions/blob/v6.4.1/setup-gradle/action.yml).
3. [setup-java v6.3.0 documentation](https://github.com/actions/setup-java/blob/v6.3.0/README.md), [dependency and wrapper cache implementation](https://github.com/actions/setup-java/blob/v6.3.0/src/cache.ts), [JDK cache implementation](https://github.com/actions/setup-java/blob/v6.3.0/src/jdk-cache.ts), [post-cleanup implementation](https://github.com/actions/setup-java/blob/v6.3.0/src/cleanup-java.ts), [job-status helper](https://github.com/actions/setup-java/blob/v6.3.0/src/util.ts), and [action inputs](https://github.com/actions/setup-java/blob/v6.3.0/action.yml).
4. [actions/cache restore implementation at inspected v4 source commit](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/src/restoreImpl.ts), [save implementation](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/src/saveImpl.ts), and [action metadata](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/action.yml). The sketch pins both actions to that commit.
5. [GitHub dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) and [cache management](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manage-caches).
6. Robolectric 4.16.1 [Robolectric POM](https://repo.maven.apache.org/maven2/org/robolectric/robolectric/4.16.1/robolectric-4.16.1.pom), [shadows-framework POM](https://repo.maven.apache.org/maven2/org/robolectric/shadows-framework/4.16.1/shadows-framework-4.16.1.pom), [nativeruntime POM](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime/4.16.1/nativeruntime-4.16.1.pom), and [nativeruntime-dist-compat POM](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime-dist-compat/1.0.18/nativeruntime-dist-compat-1.0.18.pom). The published Gradle module metadata for [Robolectric](https://repo.maven.apache.org/maven2/org/robolectric/robolectric/4.16.1/robolectric-4.16.1.module), [shadows-framework](https://repo.maven.apache.org/maven2/org/robolectric/shadows-framework/4.16.1/shadows-framework-4.16.1.module), and [nativeruntime](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime/4.16.1/nativeruntime-4.16.1.module) agrees with those POMs. The `nativeruntime-dist-compat` `.module` URL was unavailable (HTTP 404) during inspection. Robolectric's [runtime resolver](https://github.com/robolectric/robolectric/tree/robolectric-4.16.1/plugins/maven-dependency-resolver) is separate from Gradle metadata resolution.
7. [Gradle wrapper documentation](https://docs.gradle.org/9.1.0/userguide/gradle_wrapper.html) and [dependency verification](https://docs.gradle.org/9.1.0/userguide/dependency_verification.html).

## 12. Changed-file inventory

1. `docs/qualification/gradle-dependency-caching-investigation.md` — final evidence reconciliation and owner-approved no-change disposition.
2. The PR description records the same evidence and disposition. No workflow, dependency, build configuration, issue state, release artifact, device state, or MCP registration is changed by this finalization.
