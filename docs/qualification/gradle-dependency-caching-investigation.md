# Gradle dependency caching investigation

## 1. Decision

Keep the current workflow unchanged. Of the five inspected probe attempts, three returned HTTP 429 from Maven Central while resolving the same Robolectric dependency, and two later attempts passed. These outcomes establish repeated resolution failures in the inspected attempts. They do not establish that caching would prevent them or improve job time.

If a separate experiment is approved, start with manual `actions/cache/restore` and `actions/cache/save` steps in `android-readiness-probe`. Cache only Gradle's `caches/modules-2` directory. Keep the wrapper distribution and Robolectric's separate Android SDK downloads out of that cache and measure them independently.

The manual pilot takes more key and recovery maintenance than the Gradle-specific actions. It gives the clearest first experiment because it names one path, one cache namespace, and an explicit save condition. This report does not authorize workflow edits, cache seeding, hosted runs, or a local Gradle comparison.

## 2. Approved scope and provenance

| Record | Value |
| --- | --- |
| Task pin | `2026.11.25` |
| Repository | `whatobiplays/Argus-ROM-Toolkit` |
| Owner | `danielbyon`, GitHub user ID `327737` |
| Approval policy source revision | `8e391636cb50f9bfe6e8def2d0f54eeb65d1d157` |
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

This correction is limited to the report. No workflow, dependency, build configuration, Gradle cache, device, release artifact, issue state, or MCP registration was changed. No Gradle task, local comparison, hosted experiment, or experimental workflow was run.

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

## 4. CI failure evidence

All three PR #92 attempts checked out synthetic merge commit `ef7b7282cd066f7eed5fa02dea3ba67687341ca3`. The PR head was `deae51998b54d9049944bab53de8a82bb8406ad9`; the base was `cfb01eef1b20d28ec99c087a8a38f12aaf039d09`.

| Run and attempt | Checked-out `GITHUB_SHA` | PR head | Base | Probe result |
| --- | --- | --- | --- | --- |
| [PR #92, attempt 1](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/1) | `ef7b7282cd066f7eed5fa02dea3ba67687341ca3` | `deae51998b54d9049944bab53de8a82bb8406ad9` | `cfb01eef1b20d28ec99c087a8a38f12aaf039d09` | Failed: Maven Central returned HTTP 429 for `org.robolectric:nativeruntime-dist-compat:1.0.18` at `2026-11-26T06:45:08.5066578Z`. |
| [PR #92, attempt 2](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/2) | Same synthetic merge commit | Same PR head | Same base | Failed with HTTP 429 for the same artifact at `2026-11-26T07:09:49.6951993Z`. |
| [PR #92, attempt 3](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/3) | Same synthetic merge commit | Same PR head | Same base | Passed: `BUILD SUCCESSFUL in 1m 6s`; 58 actionable tasks executed. |
| [Post-merge run, attempt 1](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45801378699/attempts/1) | `1823686d39f72b6d5701a7f25bdeed83cdcf727b` | — | — | Failed with HTTP 429 for the same artifact at `2026-11-26T10:28:09.7239385Z`. |
| [Post-merge run, attempt 2](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45801378699/attempts/2) | Same main commit | — | — | Passed: `BUILD SUCCESSFUL in 57s`; 58 actionable tasks executed. Other applicable jobs passed on this attempt. |

Each failed attempt remains a failure even though a later attempt passed. Differences in hosted locations and setup details prevent a controlled timing comparison.

All five logs include the generic runner line `Cache mode: write`. None expose a Gradle cache key, restore, save, hit, miss, or byte count. The GitHub connection did not provide the cache-listing endpoint, so hosted cache entries, keys, and sizes remain unverified. The generic line does not establish that Gradle dependencies were cached.

At the original investigation, the local Gradle home contained the named artifact and Gradle 9.1.0 wrapper distributions. The artifact occupied 159,130,191 bytes across two local files. That is local state, not a hosted cache or CI transfer measurement. The Mac used ARM64 and Java 25 by default; the probe runner uses Ubuntu and Temurin 17. No local cold/warm comparison was run.

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

## 8. Preferred pilot and illustrative workflow diff

The preferred future pilot is the manual restore/save pair for the probe's `modules-2` directory. It limits the archive to the cache implicated by the HTTP 429 failure, avoids wrapper and JDK caches added by the Gradle-specific alternatives, and gives the workflow an explicit write gate. It does not cryptographically verify cached dependencies. The repository has no lock or verification metadata, so trusted default-branch seeds and read-only PR access are essential to the trust boundary.

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

## 9. Experiment design and authorization boundary

An isolated local cold/warm comparison is technically feasible with two fresh checkouts and separate temporary `GRADLE_USER_HOME` directories. The cold run resolves dependencies; the warm directory receives only the measured `caches/modules-2` seed. Keep each wrapper distribution outside that dependency seed and record its download separately. This measures the current Mac's ARM64/Java 25 behavior. It does not measure Ubuntu/Temurin 17, GitHub restore/save latency, cache branch scope, or hosted Maven throttling. The pre-existing local cache is not a valid cold or trusted warm seed. No local comparison was run.

The hosted experiment remains unrun. Missing authorization is a process boundary, not evidence of technical infeasibility. Separate authorization must name the workflow change, approved source and triggers, cache reads and writes, seed run, number of pairs, and stop/rollback authority. This report grants none of it.

If separately authorized, use this design:

| Future hosted case | Required evidence |
| --- | --- |
| Trusted default-branch push | A successful `push` to `main` writes only the probe dependency path; retain source, input hash, primary key, run, and save outcome. |
| Subsequent trusted push | Restore a compatible prior key and save under the new commit key only after success; record matched key, restore/save duration, and bytes when available. |
| Pull request | Restore from its base/default scope when available; verify there is no save from a PR or merge-ref run. |
| Failed job and rerun | A failed job does not save; record the rerun's matched key and confirm it follows the same trust gate. |
| Missing or evicted entry | Ordinary repository resolution proceeds; record the miss, downloads, and any upstream failure. |
| Dependency or toolchain change | Changed Gradle inputs or version namespace produce a miss; record old and new hashes and toolchain identities. |
| Failed archive or suspect contents | Archive restore failure clears only `modules-2` and proceeds cold; retain semantic-corruption failures and use a reviewed new namespace for recovery. |
| Artifact verification | Existing checks remain enabled; compare unsigned APK digests and verify any separate disposable signed copy and source provenance. |

These cases define future validation only. None has been executed.

1. Bind a trusted seed: use a successful trusted `push` run on the default branch at the approved source identity. Record repository, workflow revision, source SHA, event/ref, run ID and attempt, action versions or SHAs, Gradle-input hash, path, primary/matched keys, branch scope, toolchain, and task outcomes. A PR run must not create the seed. If seed SHA differs from the measured SHA, require the complete Gradle-input hash to match and record both identities.
2. Use fresh trials: each cold/warm run gets a fresh checkout and hosted runner. Hold source SHA, runner image, Java 17 distribution/version, Android SDK/build tools 36, wrapper 9.1.0-all, and task sequence constant. Run at least three matched cold/warm pairs. Use a fresh cache namespace or skip restore for cold runs; do not delete or overwrite shared caches to manufacture a miss.
3. Separate wrapper effects: keep wrapper distributions outside the dependency cache. Start observation before invoking the wrapper. Record wrapper download/cache state and duration for each trial. Keep wrapper identity constant and report pairs broken by runner-image or distribution changes.
4. Start observation before Gradle: capture timestamps and cache state before the first wrapper invocation, including `tasks --all`, dry run, and actual tasks. Record total job time, each invocation's start/end, dependency-resolution events, cache match, matched key, save result, and compressed transfer size plus restored path size when exposed. The restore action exposes exact-hit, primary-key, and matched-key outputs; it does not promise a byte-count output. Mark unavailable measurements as unavailable.
5. Verify execution: start with a clean checkout and no project outputs. Keep task-output and configuration caches disabled. Inspect logs and task outcomes to confirm test, lint, and assembly actions executed. Any `FROM-CACHE`, skipped, or up-to-date task that replaces measured work invalidates that task's comparison. A cache hit alone does not prove the work ran.
6. Record Robolectric separately: capture SDK coordinates, repository activity, download time, and checksum outcomes from Robolectric's resolver. Do not cache `.m2` in this pilot. Those downloads remain a separate source of job-time variation.
7. Compare outputs: record each successful trial's unsigned probe APK path, size, and SHA-256. Compare cold and warm digests. Verify any disposable signed artifact separately on a copy outside cached paths; record signature verification and keep its temporary key out of the cache.
8. Keep failed pairs: retain every failed cold/warm run, rerun, log, cache summary, task outcome, and artifact digest. Mark incomplete pairs incomplete; do not drop failures from timing or reliability summaries. Preserve run IDs and source identities with the comparison manifest.
9. Roll back cleanly: if the authorized pilot fails or is no longer needed, stop writes and revert only the pilot workflow commit through a normal forward-moving commit. Leave immutable entries to expire or be evicted. For a suspect cache, bump the namespace, for example `v1` to `v2`, and repeat from a fresh miss while retaining the failed evidence.

The cache-path trust boundary is ordinary public dependency artifacts under `modules-2`. Trusted default-branch pushes are the only writers; PRs restore from base/default scope and have no save step. Credentials, signing inputs, task outputs, APKs, qualification records, wrapper distributions, Android SDK images, and `.m2` files stay outside the cache. GitHub cache content is not signed, and Gradle verification metadata is absent. The proposal relies on trusted writers and ordinary Gradle resolution; it does not claim cryptographic verification of cache contents.

## 10. Approved PAC and TAC mapping

### PAC criteria

| ID | Approved criterion | Evidence status | Evidence or remaining limit |
| --- | --- | --- | --- |
| PAC-1 | Document current caching behavior across all three Android jobs. | Complete as documentary review | The three jobs and their Gradle, Flutter/Pub, and artifact behavior are recorded above. |
| PAC-2 | Establish the available evidence for recurring dependency downloads and failures. | Partial | Three of five inspected attempts failed with the same HTTP 429; two later attempts passed. Hosted cache inventory, keys, hits/misses, bytes, and failure-rate data remain unavailable. |
| PAC-3 | Compare maintained caching approaches, including their security and operational trade-offs. | Complete as documentary review | Enhanced, Basic, setup-java v6, manual actions/cache, and no change are compared. No provider was configured or run. |
| PAC-4 | Produce an evidence-based recommendation, including no change if appropriate. | Complete as a report recommendation | Keep current CI unchanged. A manual `modules-2` pilot is preferred only if separately authorized; its benefit remains unmeasured. |
| PAC-5 | Propose a narrowly scoped configuration and cold/warm validation strategy. | Designed; not run | Path, key, trust gate, measurements, and pair method are specified. No configuration or comparison was run. |
| PAC-6 | Identify residual risks, measurement limitations and required follow-up authorization. | Complete as documentary review | Hosted inventory and cold/warm comparison remain unverified/unrun. A separate explicit authorization is required before a pilot. |

### TAC criteria

| ID | Approved criterion | Evidence status | Evidence or remaining limit |
| --- | --- | --- | --- |
| TAC-1 | Bind investigation evidence to exact source, workflow, run and toolchain identities. | Complete as documentary review | PR head, base, synthetic merge SHA, post-merge SHA, workflow runs, wrapper, Java, and Android SDK identities are distinguished. |
| TAC-2 | Distinguish dependency caching from task-output and Flutter caching. | Complete as documentary review | Gradle `modules-2`, wrapper distributions, build outputs, Flutter/Pub, Android SDK downloads, and workflow artifacts are separated. |
| TAC-3 | Establish a defensible experimental methodology without conflating cache hits with skipped work. | Designed; not run | Fresh checkouts, first-invocation observations, task outcomes, and output digests are required. |
| TAC-4 | Preserve all existing CI, security, signing and qualification invariants. | Source/document review complete; runtime validation not performed | Proposed paths exclude signing and qualification data; no workflow was changed or executed. |
| TAC-5 | Make no unauthorized workflow, dependency, cache-policy or product changes. | Met for this correction | Only this report is changed. No cache was initialized; no workflow or dependency was modified. |
| TAC-6 | Obtain independent non-authoring review of the final investigation and its conclusions. | Review evidence is recorded with the reviewed PR candidate | Reviewer identity, exact candidate identity, coverage, findings, dispositions, and validation are retained in the draft PR record. |

PAC/TAC documentary status does not establish technical readiness, completion of the hosted experiment, acceptance of outstanding criteria, issue closure, or merge authorization.

## 11. Sources

1. [Gradle dependency cache, Gradle 9.1](https://docs.gradle.org/9.1.0/userguide/dependency_caching.html), [build cache](https://docs.gradle.org/9.1.0/userguide/build_cache.html), and [configuration cache](https://docs.gradle.org/9.1.0/userguide/configuration_cache_enabling.html).
2. [Gradle setup-gradle v6.4.1 documentation](https://github.com/gradle/actions/blob/v6.4.1/docs/setup-gradle.md) and [action inputs and post hook](https://github.com/gradle/actions/blob/v6.4.1/setup-gradle/action.yml).
3. [setup-java v6.3.0 documentation](https://github.com/actions/setup-java/blob/v6.3.0/README.md), [dependency and wrapper cache implementation](https://github.com/actions/setup-java/blob/v6.3.0/src/cache.ts), [JDK cache implementation](https://github.com/actions/setup-java/blob/v6.3.0/src/jdk-cache.ts), [post-cleanup implementation](https://github.com/actions/setup-java/blob/v6.3.0/src/cleanup-java.ts), [job-status helper](https://github.com/actions/setup-java/blob/v6.3.0/src/util.ts), and [action inputs](https://github.com/actions/setup-java/blob/v6.3.0/action.yml).
4. [actions/cache restore implementation at inspected v4 source commit](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/src/restoreImpl.ts), [save implementation](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/src/saveImpl.ts), and [action metadata](https://github.com/actions/cache/blob/0057852bfaa89a56745cba8c7296529d2fc39830/action.yml). The sketch pins both actions to that commit.
5. [GitHub dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) and [cache management](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manage-caches).
6. Robolectric 4.16.1 [Robolectric POM](https://repo.maven.apache.org/maven2/org/robolectric/robolectric/4.16.1/robolectric-4.16.1.pom), [shadows-framework POM](https://repo.maven.apache.org/maven2/org/robolectric/shadows-framework/4.16.1/shadows-framework-4.16.1.pom), [nativeruntime POM](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime/4.16.1/nativeruntime-4.16.1.pom), and [nativeruntime-dist-compat POM](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime-dist-compat/1.0.18/nativeruntime-dist-compat-1.0.18.pom). The published Gradle module metadata for [Robolectric](https://repo.maven.apache.org/maven2/org/robolectric/robolectric/4.16.1/robolectric-4.16.1.module), [shadows-framework](https://repo.maven.apache.org/maven2/org/robolectric/shadows-framework/4.16.1/shadows-framework-4.16.1.module), and [nativeruntime](https://repo.maven.apache.org/maven2/org/robolectric/nativeruntime/4.16.1/nativeruntime-4.16.1.module) agrees with those POMs. The `nativeruntime-dist-compat` `.module` URL was unavailable (HTTP 404) during inspection. Robolectric's [runtime resolver](https://github.com/robolectric/robolectric/tree/robolectric-4.16.1/plugins/maven-dependency-resolver) is separate from Gradle metadata resolution.
7. [Gradle wrapper documentation](https://docs.gradle.org/9.1.0/userguide/gradle_wrapper.html) and [dependency verification](https://docs.gradle.org/9.1.0/userguide/dependency_verification.html).

## 12. Changed-file inventory

1. `docs/qualification/gradle-dependency-caching-investigation.md` — corrected and expanded investigation report.
2. No workflow, dependency, build configuration, issue, release artifact, device state, or MCP registration was changed.
