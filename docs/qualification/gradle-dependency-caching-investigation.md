# Gradle dependency caching investigation

## Decision

Keep the three Android CI jobs unchanged for now. The workflow has no explicit Gradle dependency cache, and two CI runs show repeated Maven Central HTTP 429 responses while resolving the same Robolectric artifact. Later attempts passed on the same source revisions. That pattern is consistent with a transient repository rate limit, but it does not show that a GitHub Actions cache would prevent the failure.

The available run logs do not report Gradle cache keys, restores, saves, or transferred bytes. They therefore cannot establish a cache hit rate, a time saving, or a reliability improvement. The runner's generic `Cache mode: write` header does not identify a Gradle cache.

If a measured follow-up is approved, pilot a Gradle dependency cache in `android-readiness-probe` only. Its task is where the observed resolution failures occurred. Target Gradle's `caches/modules-2` dependency state, allow trusted default-branch runs to write, and let pull requests restore without writing. The Gradle action also documents separate wrapper-distribution caching, so confirm that the selected Enhanced configuration can exclude that entry. If it cannot, list wrapper caching as part of the experiment scope and measure it separately. Keep project `.gradle` state, build outputs, APKs, signing material, and qualification records outside the cache. This is a candidate for a separately authorized experiment, not an implementation decision.

## Scope and evidence record

This investigation was limited to the approved worktree and read-only evidence. No workflow, dependency, cache policy, CI run, local Gradle cache, release artifact, or device state was changed. No build, test, or hosted experiment was run.

| Record | Observed value |
| --- | --- |
| Worktree | Codex task worktree `issue-93-gradle-cache-investigation/Argus-ROM-Toolkit` |
| Task pin | `2026.11.25` |
| Branch | `codex/issue-93-gradle-cache-investigation` |
| Baseline | `1823686d39f72b6d5701a7f25bdeed83cdcf727b` |
| Initial state | Clean worktree at the approved baseline |
| CodeGraph | Initialized in the task worktree; indexed 561 files |
| TokenSave | Initialized and registered for the task branch; status selected that branch without fallback |
| Serena | Activated on the task worktree |
| GPT Repo MCP enrollment | The exact worktree was absent from the configured roots. No shared registration or server lifecycle change was made. |

The primary checkout remained on `main` at the approved baseline. Existing Issue #28 worktrees and MCP registrations were left untouched. GitHub issue and Actions evidence came from the `whatobiplays` connection for `whatobiplays/Argus-ROM-Toolkit`. Issue #93 was open with the `needs-triage` label and had no comments when inspected. No issue state was changed.

## Current workflow behavior

The Android jobs are defined in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml). The links below identify the relevant job sections.

| Job | Gradle and Android setup | Cache behavior seen in the workflow | Other cached or published data |
| --- | --- | --- | --- |
| `android-readiness-probe` ([workflow section](../../.github/workflows/ci.yml#L508)) | Temurin 17, Android SDK 36 and build tools 36; Gradle wrapper 9.1.0-all; runs task inventory, dry-run, then `testProbeUnitTest lintProbe assembleProbe` | No explicit Gradle cache action or `GRADLE_USER_HOME` override | No Android or Pub cache is configured in this job |
| `android-arm64-package` ([workflow section](../../.github/workflows/ci.yml#L305)) | Temurin 17 and Flutter; invokes `just build-android-debug` | `setup-java` has no Gradle cache option | Flutter action has `cache: true` and `pub-cache: true`; those cover Flutter SDK and Pub data, not Gradle dependency state |
| `android-qualification-release` ([workflow section](../../.github/workflows/ci.yml#L377)) | Temurin 17 and Flutter; runs the release config-only step and qualification build/verification | `setup-java` has no Gradle cache option | Flutter SDK and Pub caches are enabled. APK, provenance, and qualification records are uploaded as workflow artifacts, which is artifact retention rather than a dependency cache. |

The reviewed Android Gradle properties do not enable Gradle's task output build cache or configuration cache. Gradle's dependency cache is a separate store under `GRADLE_USER_HOME/caches`; the wrapper distribution is also a separate part of Gradle user-home state. The probe wrapper uses `GRADLE_USER_HOME` for `wrapper/dists`. No workflow-level cache configuration for either was found.

The release path contains fail-closed production signing checks and separate qualification signing and provenance handling. The probe creates a disposable signed test copy under `RUNNER_TEMP` and removes its temporary signing material. A cache must not include production keys, temporary signing directories, signed APKs, or qualification evidence. Existing artifact and qualification boundaries are documented in [`docs/qualification/android-readiness-probe.md`](android-readiness-probe.md) and [`docs/qualification/README.md`](README.md).

## CI evidence

The same dependency resolution failed in the probe job with HTTP 429 from Maven Central for `org.robolectric:nativeruntime-dist-compat:1.0.18`. The failure was reported while configuring `:generateProbeUnitTestLintModel` for `:probeUnitTestRuntimeClasspath`.

| Run and attempt | Source revision | Probe result | Relevant evidence |
| --- | --- | --- | --- |
| [PR #92, attempt 1](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/1) | `deae51998b54d9049944bab53de8a82bb8406ad9` | Failed | Maven Central returned HTTP 429 for the Robolectric artifact at `2026-11-26T06:45:08.5066578Z`. |
| [PR #92, attempt 2](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/2) | Same SHA | Failed | Same artifact and HTTP 429 at `2026-11-26T07:09:49.6951993Z`. |
| [PR #92, attempt 3](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45770182144/attempts/3) | Same SHA | Passed | Gradle reported `BUILD SUCCESSFUL in 1m 6s`; 58 actionable tasks executed. |
| [Post-merge run, attempt 1](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45801378699/attempts/1) | `1823686d39f72b6d5701a7f25bdeed83cdcf727b` | Failed | Same artifact and HTTP 429 at `2026-11-26T10:28:09.7239385Z`. |
| [Post-merge run, attempt 2](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/45801378699/attempts/2) | Same SHA | Passed | Gradle reported `BUILD SUCCESSFUL in 57s`; 58 actionable tasks executed. The other applicable jobs passed on this attempt. |

In the failed attempts, task inventory completed in about 42 seconds, dry-run in about one second, and task execution failed after about 25 to 26 seconds. Successful attempts used different hosted compute locations or images and setup details. These timings are not a controlled comparison and do not show that a cache improves runtime or success rate. A later pass leaves the earlier failure as a failure.

All five logs include the generic runner line `Cache mode: write`. None expose a Gradle cache key, restore or save event, hit or miss, or byte count. The GitHub connection did not allow the Actions cache listing endpoint, so hosted cache entries, sizes, and keys remain unknown. The generic line is not evidence that Gradle dependencies were cached.

On this Mac, the local Gradle home already contains the named artifact and Gradle 9.1.0 wrapper distributions. The artifact occupies 159,130,191 bytes across two local files. This is local machine state, not a measurement of the hosted cache or the exact transfer size in CI. The local host uses macOS ARM64 and Java 25 by default, while the probe CI uses Ubuntu and Java 17. No local cold/warm experiment was run.

## Options

| Option | Assessment for this issue | Limitation or cost |
| --- | --- | --- |
| Leave the workflow unchanged | Recommended on current evidence. It avoids claiming an unmeasured reliability or speed benefit. | Cold runs remain exposed to Maven Central availability and rate limits. |
| Pilot `gradle/actions/setup-gradle` in the probe job | Best focused candidate for a separately approved experiment. Its Enhanced provider supports path filters, cache cleanup, and deduplication. Its documentation supports narrowing included Gradle-home paths to `caches/modules-2`. | Enhanced uses a commercial library, free for public repositories. The action also documents separate wrapper-distribution caching, so confirm whether the proposed path filters exclude that entry. If they do not, measure wrapper caching as part of the pilot. |
| Use setup-gradle Basic provider | MIT-licensed and based on GitHub's standard cache action. | It stores the full `~/.gradle/caches` and `~/.gradle/wrapper` directories, has fixed paths and no restore keys, and does not support path filtering, cleanup, or deduplication. It cannot meet a dependency-only cache boundary. |
| Use `actions/setup-java` Gradle caching | Provides a simpler package-manager cache option. Current documentation supports separate dependency, wrapper, and JDK caches and a read-only mode. | The repository currently uses `setup-java@v4`, which upstream marks deprecated. Updating that action is separate scope. A Gradle cache rollout should not silently combine an action-version migration with cache evaluation. |
| Add a manual `actions/cache` entry | Gives direct control over keys and paths. | Adds custom key, restore, save, invalidation, and trust-policy logic. It overlaps with the supported Gradle-specific options and is not justified by the current evidence. |
| Add retries | Could reduce the impact of a transient repository response. | Does not demonstrate that dependency caching helps and changes failure timing and CI semantics. Keep it as a separate reliability proposal. |

The action documentation reviewed for this comparison is [`gradle/actions` v6.4.1](https://github.com/gradle/actions/blob/v6.4.1/docs/setup-gradle.md) and [`actions/setup-java` v6.3.0](https://github.com/actions/setup-java/blob/v6.3.0/README.md). Those versions identify current documentation reviewed on 2026-11-26; this report does not request an action upgrade. For setup-gradle, Enhanced is the only provider that supports path filters. Basic caches both the Gradle `caches` and `wrapper` directories as fixed paths. Both providers default to writes on the default branch and read-only behavior on other branches; set `cache-read-only` explicitly for pull-request runs in an approved pilot. Enhanced cache cleanup defaults to running only when all Gradle builds in the job succeed. That setting controls cleanup of restored files; it does not establish whether cache data is saved after a failed job. The failed-job case must record the actual save behavior.

## Proposed experiment, pending separate authorization

The local machine can support a limited Gradle cold/warm comparison using a fresh temporary `GRADLE_USER_HOME`, but that would write cache data and contact dependency repositories. It would measure Gradle behavior on macOS ARM64, not GitHub cache restore/save behavior or hosted Maven Central throttling. The primary evidence needed for the issue is a hosted comparison with the actual runner and workflow. Neither experiment was run under the current approval.

For a hosted pilot, change only `android-readiness-probe` in a separately approved change. Use the reviewed Gradle action's Enhanced provider, restrict its Gradle-home include paths to `caches/modules-2`, and make the cache write policy explicit: trusted default-branch runs may write; pull-request runs may read an eligible trusted cache but may not write to it. Before calling the scope dependency-only, verify whether Enhanced's separate wrapper-distribution entry can be excluded with the documented path filters. If it cannot, include wrapper caching in the pilot scope and record its restore and transfer data separately. Do not combine this pilot with Gradle task-output caching, configuration caching, Flutter/Pub changes, dependency changes, or retries.

Compare at least three matched cold/warm pairs using the same commit, runner image, Java and Android SDK versions, and exact task sequence. Record the workflow run and attempt, cache key and scope, restore/save status, transferred bytes if available, dependency-resolution time, each Gradle invocation time, full job time, task outcome, and whether tasks executed. Keep task-output and configuration caches disabled. The selected action's supported method for producing a cold miss must be confirmed before the experiment; do not delete or overwrite shared cache entries as an improvised reset. Retain failed cold runs and incomplete pairs in the results.

The follow-up should exercise these cases in an isolated, approved workflow:

1. A trusted default-branch push creates an eligible cache and completes the probe.
2. A later trusted run restores the eligible cache and completes the same probe.
3. A pull request can restore an eligible trusted cache but cannot write to the trusted cache scope.
4. A failed job and its rerun report whether a cache is restored or saved, with the actual provider policy recorded.
5. A missing or evicted cache falls back to ordinary dependency resolution and reports the outcome.
6. A dependency or Gradle toolchain input change causes the expected cache invalidation or safe reuse, as documented for the selected action.
7. A stale or unusable cache recovers through normal Gradle resolution without weakening repository or integrity checks. Any deliberately invalid cache data must use a disposable isolated key.
8. APK and qualification artifact verification remains unchanged, and no signing material or signed output enters the cache.

These are proposed cases, not completed checks. GitHub documents that caches are immutable, have branch and event scope, and can be evicted under storage pressure. Its security guidance warns that workflows able to access a cache can expose its contents. Keep secrets and signing material out of all cache paths, and do not let untrusted workflows write into a trusted cache scope. See [GitHub dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), [cache security](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching), and [cache management](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manage-caches).

## Acceptance evidence

Issue #93 does not define numbered PAC or TAC identifiers. The report uses local identifiers below for review traceability; they do not create new project requirements.

| ID | Criterion | Status | Evidence or remaining work |
| --- | --- | --- | --- |
| PAC-1 | Document current caching and the recurring download failure with source and CI references. | Met | Workflow inventory and five probe attempts above; the recurring response is a Maven Central HTTP 429 for one artifact. |
| PAC-2 | Give an evidence-based recommendation, tradeoffs, residual risk, and a cold/warm validation plan. | Partial | The recommendation and documented tradeoffs are present. Hosted cache behavior and measured cold/warm impact were unavailable and remain unmeasured. |
| PAC-3 | Identify follow-up authorization and retain failed attempts as failures. | Met | The hosted experiment is explicitly pending separate authorization; each failed attempt remains failed in the evidence table. |
| TAC-1 | Audit Gradle user-home, wrapper, dependency, and build-output caching across the three Android jobs; distinguish Flutter/Pub caching. | Met | Job-by-job workflow inventory and cache boundaries above. |
| TAC-2 | Compare relevant cache approaches and their policies. | Met as documentary analysis | The report compares setup-gradle Enhanced and Basic, setup-java, manual caching, and no change. Enhanced supports path filtering, cleanup, and deduplication; Basic uses fixed full-directory paths without restore keys or cleanup. No cache configuration was installed or exercised. |
| TAC-3 | Compare cold and warm behavior for the same SHA and toolchain. | Not run | The report specifies a matched hosted experiment. No cache mutation or CI dispatch was authorized. |
| TAC-4 | Preserve toolchain, isolation, checks, signing, and provenance boundaries. | Audited; runtime validation not performed | The candidate is limited to the probe job. Whether the selected Enhanced configuration also caches wrapper distributions must be verified before the cache scope is finalized. Release signing, qualification artifacts, and generated signing material remain outside scope and cache paths. |
| TAC-5 | Avoid secrets, untrusted cache writes, mirrors, integrity weakening, and skipped checks. | Met as a plan constraint | The experiment policy excludes those changes. No configuration was implemented or tested. |

## Source references

1. [Gradle 9.1 dependency caching](https://docs.gradle.org/9.1.0/userguide/dependency_caching.html) describes the dependency cache under Gradle user home and its artifact and metadata contents.
2. [Gradle 9.1 build cache](https://docs.gradle.org/9.1.0/userguide/build_cache.html) and [configuration cache](https://docs.gradle.org/9.1.0/userguide/configuration_cache_enabling.html) describe distinct caches for task outputs and configured build state.
3. [Android Gradle Plugin compatibility](https://developer.android.com/build/releases/about-agp) lists the minimum Gradle version for AGP 9.0. The repository's reviewed wrapper is Gradle 9.1.0.
4. [Gradle setup action v6.4.1 documentation](https://github.com/gradle/actions/blob/v6.4.1/docs/setup-gradle.md) describes Enhanced and Basic providers, path controls, wrapper distributions, and branch behavior.
5. [`setup-java` v6.3.0 documentation](https://github.com/actions/setup-java/blob/v6.3.0/README.md) describes its cache options and notes the status of older major versions.
6. [GitHub dependency cache reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) and [cache management guide](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manage-caches) describe cache scope, immutability, and eviction.

## Changed files

1. Added this investigation report. No workflow, dependency, build configuration, qualification record, issue, or release artifact was changed.
