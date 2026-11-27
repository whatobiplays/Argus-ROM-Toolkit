# Issue #93 hosted Gradle cache pilot candidate

## Status and provenance

This is a local candidate for a separately authorized hosted experiment. No hosted workflow was dispatched, no GitHub cache entry was created, and no production workflow or dependency file was changed. The investigation report and draft PR #94 remain in their separate worktree.

| Item | Identity or status |
| --- | --- |
| Task pin | `2026.11.25` |
| Policy revision | `8e391636cb50f9bfe6e8def2d0f54eeb65d1d157` |
| Approved base | `1823686d39f72b6d5701a7f25bdeed83cdcf727b` |
| Branch | `codex/issue-93-gradle-cache-pilot` |
| Worktree | `/Users/daniel/.codex/worktrees/issue-93-gradle-cache-pilot/Argus-ROM-Toolkit` |
| Investigation report worktree | `/Users/daniel/.codex/worktrees/issue-93-gradle-cache-investigation/Argus-ROM-Toolkit` at `795eee3bcf1339a9ea1a7816790739cc8599459f` |
| Investigation report SHA-256 | `8e51311303bbf7b848fec66fcad47fd71abfc9bf06c9d398f89500d439e9d895` |
| Task-scoped tools | CodeGraph, TokenSave, and Serena initialized for this worktree |
| GPT Repo MCP | Pilot worktree is not enrolled. The approved-root list includes the primary checkout and Issue #76 worktree, but not this path. No registration changed and no restart was needed. |
| Investigation report MCP | The separate report worktree is also absent from the approved-root list. Its earlier MCP disposition remains unchanged. |

The investigation report remains the source for the issue history and the approved PAC/TAC definitions: [Gradle dependency caching investigation](gradle-dependency-caching-investigation.md).

## Workflow boundary

The candidate adds one workflow, `.github/workflows/gradle-dependency-cache-experiment.yml`, and the isolated helper package under `scripts/gradle_dependency_cache/`. It does not edit `.github/workflows/ci.yml`, build files, dependency declarations, product code, or the investigation report.

The workflow trigger accepts pushes to `codex/issue-93-gradle-cache-pilot` and PR `opened` or `synchronize` events targeting `main`. Every push job checks the repository and owner IDs, actor ID `219249021`, triggering actor `whatobiplays`, exact branch ref, branch protection, a branch-creation event, and `run_attempt == 1`. A failed trust predicate prevents the job from running.

The PR consumer requires a same-repository head on the exact pilot branch, a `main` base, and PR author ID `219249021`. Its job uses `cache-mode: read`. It restores an exact key and runs the probe without saving. A unique save-canary step checks the access mode. The pinned cache action skips that save in read mode; the workflow records an action-level skip and a cache miss. It does not describe this result as a cache-service denial.

Before hosted execution, the owner would need an active ruleset that targets only `codex/issue-93-gradle-cache-pilot`, marks the branch protected, blocks force pushes and deletion, and limits branch creation and updates to the authorized owner. The workflow independently checks the actor and protected-ref state. No ruleset was created or changed for this candidate.

## Eighteen-job matrix

The workflow defines 17 push jobs and one PR consumer. The first group performs the dependency measurements; the remaining push jobs exercise bounded cache controls.

| Job IDs | Cache mode | Purpose |
| --- | --- | --- |
| `cache_seed` | `write-only` | Run the probe from an empty module cache, record the seed manifest, and save after a successful probe and daemon shutdown. |
| `trial_a_cold`, `trial_b_cold`, `trial_c_cold` | `none` | Run three fresh cold trials without cache reads or writes. |
| `trial_a_warm`, `trial_b_warm`, `trial_c_warm` | `read` | Restore the exact seed, compare its canonical manifest, and run the matching warm trial. |
| `cache_miss_invalidation` | `read` | Require a clean ordinary miss and a miss after changing the dependency-input fingerprint, then run a cold fallback. |
| `service_fault_observation` | `none` | Record that a safe cache-service fault could not be demonstrated. This job succeeds so it does not skip later controls. |
| `partial_extraction_recovery` | `none` | Create a disposable partial `modules-2` fixture, remove only that path, and verify cleanup before fallback. |
| `bounded_fixture_seed` | `write-only` | Save separate 64 KiB semantic and collision fixtures. |
| `semantic_fixture_recovery` | `read` | Restore fixture A, damage only the local extraction, remove it, and restore A again from its immutable cache. |
| `immutable_collision_writer` | `write-only` | Attempt to save fixture B under fixture A's existing immutable key. |
| `immutable_collision_readback` | `read` | Require fixture A to survive the collision attempt. |
| `failed_writer_key_absent` | `read` | Verify the run-specific failed-writer key starts absent. |
| `expected_failed_writer` | `write` | Create a separate bounded payload, fail before save, and require the save step to be skipped. |
| `failed_writer_key_readback` | `read` | Require the failed-writer key to remain absent after the failure. |
| `pull_request_consumer` | `read` | Run the exact-head PR consumer and the action-level read-only save canary. |

The unsupported service-fault control records its limitation and does not gate the rest of the validation chain. The failed-writer key is never seeded. The semantic and collision fixtures use separate keys; no trusted measurement entry is intentionally corrupted.

## Naming supplement

The investigation and candidate note use subject-based filenames without an issue number. The helper package is named for its Gradle dependency-cache responsibility, and its modules name their roles (`control`, `runner`, and the observer fixture). The workflow name identifies this as an experiment. The branch and cache namespace include Issue #93 intentionally so the hosted pilot can be isolated from production caches and other experiments. These names do not present the pilot as a reusable production cache implementation.

## Cache path, key, and trust scope

The only path eligible for the full dependency cache is:

```text
${{ runner.temp }}/gradle-dependency-cache-experiment/state/gradle-home/caches/modules-2
```

The helper sets `GRADLE_USER_HOME` to the sibling `gradle-home` directory. Gradle wrapper distributions, the isolated Robolectric Maven repository, build outputs, evidence, and fixtures are outside `caches/modules-2`. The workflow does not set `setup-java`'s `cache` input, so that action's optional dependency cache is disabled. No Gradle build-output cache or configuration cache is enabled.

All full-cache restore and save steps use `actions/cache` pinned to `cdf6c1fa76f9f475f3d7449005a359c84ca0f306`. There are no restore prefixes. A usable warm result requires a successful restore, `cache-hit == true`, an exact matched/primary-key match, and the same canonical manifest digest as the trusted seed. Every non-exact result removes only `caches/modules-2`; an action failure is an error, not a cache miss. An unexpected warm miss or manifest mismatch stops that measurement chain.

The key starts with the isolated `argus-gradle-issue93-pilot-v1` namespace and includes Linux, runner architecture, the actual Temurin vendor and Java 17 runtime, Gradle 9.1.0, Android command-line tools 12266719, the installed API 36 and build-tools 36.0.0 package revisions, and a SHA-256 over Gradle scripts, wrapper files, Gradle properties, version catalogs, lockfiles, and dependency-verification metadata. It does not hash application source. Including lock and verification files in the key does not add or strengthen those project controls. The PR computes the same key from its head checkout and can only consume an exact match.

The wrapper properties select `gradle-9.1.0-all.zip` but do not set `distributionSha256Sum`. Hashing the wrapper properties and JAR into the cache key does not verify the downloaded distribution. This candidate adds no wrapper checksum setting.

The workflow requests Temurin Java 17, matching the production probe's Java major. It records the installed `java.runtime.version` and vendor in the key, then requires each paired run to match the seed. This avoids a stale fixed patch literal: the Temurin release published on 18 November 2026 is tagged `17.0.21.1+2`, while the prior candidate literal `17.0.21+2` did not match that release. The setup-java v4 README documents exact SemVer forms, but not this four-part form, so the workflow uses the supported major-version request and compares the resolved runtime. Sources: [Temurin 17.0.21.1+2 release](https://github.com/adoptium/temurin17-binaries/releases/tag/jdk-17.0.21.1%2B2) and [setup-java v4 version syntax](https://github.com/actions/setup-java/blob/v4/README.md#supported-version-syntax).

GitHub cache scope still applies: push entries are written only under the protected pilot branch. The namespace distinguishes this experiment from ordinary repository caches. PR restoration is read-only and restricted to the same-repository pilot head. The workflow contains no writer for `main`. Repository cache inventory and remaining quota were not available through the authorized GitHub connector, so existing usage and storage headroom remain unverified. The 1 GiB limit below is an expanded local path ceiling, not a claim about compressed service size or account quota.

## Trial procedure and measurements

Each hosted job checks out a fresh source tree. The runner fails if the probe's build directory already exists. It snapshots Gradle wrapper distributions before and after `gradlew --version`; wrapper files are outside the cached path and their new byte count and elapsed version-query time are recorded separately.

The observer is installed before that wrapper call. The local fixture showed that `gradlew --version` bypasses init scripts and makes no project-artifact request. The first build command loads the installed `init.d` observer before task configuration and dependency resolution. The observer fixture then downloaded a local POM and JAR and reported the completed JAR body bytes once. This keeps wrapper bootstrap separate from project dependency transfer measurements.

The runner follows the production `android-readiness-probe` sequence in `ci.yml`: task inventory, dry-run of `testProbeUnitTest lintProbe assembleProbe`, actual execution of those tasks, host-only qualification tests, and verification of a separately signed temporary APK copy. That copy is host-test material; it is not a distributable release or product qualification artifact. The runner passes `--no-build-cache` and `--no-configuration-cache`; each job starts with no probe build outputs. The unsigned APK is hashed before signing. Every warm run must match its paired cold SHA-256. Signing material and signed copies live in disposable `RUNNER_TEMP` directories and are not added to the cache or uploaded.

The hosted identity record includes the actual Gradle and Java versions, Java vendor, runner image OS/version, architecture, SDK package revisions, and a hash of the `RUNNER_TEMP` path. The key is built from the same identity. Each valid pair must match the seed; a drift stops the campaign.

The Gradle observer uses Gradle 9.1.0 internal build-operation APIs. It records resource identifiers as SHA-256 values, artifact suffix, transfer state, known byte count, and observer errors. The fixture qualifies the observed `ProgressLoggingExternalResourceAccessor$ReadOperationDetails` event type. Cold trials require completed artifact-body bytes greater than zero. Warm trials reject every artifact-body read event, including a completed zero-byte read. A local regression test covers this case. Missing, incomplete, and observer-error events remain visible; the workflow does not count a missing observation as zero bytes.

Robolectric's local Maven repository is a separate sibling path set for test JVMs. Before/after file manifests record persisted file count and bytes, hashed paths, content hashes, and whether the path is under `org/robolectric/nativeruntime-dist-compat/1.0.18/`. The runner records only transfer lines whose decoded Maven path contains adjacent `org/robolectric` segments. Each matching line is reduced to a resource SHA-256 and suffix; URLs and raw lines stay out of the evidence file. Failure lines mentioning Robolectric or `MavenArtifactFetcher` are counted separately. A persisted-file delta and a transfer attempt are separate observations. Neither a missing matching line nor an unchanged local repository proves that no network transfer occurred. No resolved transitive graph is asserted by this pilot.

Each measurement job uploads its redacted evidence with `if: always()` and a 14-day artifact retention target, including when the probe fails. Full-cache manifests reject symlinks and non-regular files, ignore only lock files and `gc.properties`, require two identical snapshots two seconds apart, and cap expanded `modules-2` contents at 1 GiB. Cache-control fixtures are limited to 1 MiB; the workflow uses 64 KiB fixtures.

## Stop and rollback procedure

Stop the campaign if a writer predicate fails, the branch is not protected, the runner or JDK identity changes, a restore is inexact, a warm miss occurs, the canonical manifest differs, the artifact digest changes, or transfer evidence is missing or contradictory. Preserve every uploaded pair artifact. Do not rerun a failed job; the workflow rejects `run_attempt` values above one.

If a separately authorized hosted run must be rolled back, cancel its active workflow run, preserve the evidence artifacts, and disable the experimental workflow. After recording exact keys, remove only entries matching the experiment's run-specific prefixes: `argus-gradle-issue93-pilot-v1-*`, `argus-gradle-empty-miss-v1-${run_id}`, `argus-gradle-fixture-*-v1-${run_id}`, `argus-gradle-failed-writer-v1-${run_id}-${run_attempt}`, and `argus-gradle-pr-read-only-canary-v1-${run_id}-${run_attempt}`. Remove the exact pilot branch ruleset and branch only after the owner approves those actions. Leave all default-branch caches and unrelated cache entries untouched. No rollback action was taken for this local candidate.

## Hosted resource ceiling and remaining gates

The 17 push jobs have a theoretical timeout ceiling of 615 runner-minutes: eight 60-minute measurement jobs plus nine 15-minute controls. One PR consumer can add 60 minutes, for 675 minutes across one push event and one PR event. Each later PR `synchronize` event can add another 60 minutes. These are configured timeout ceilings, not predicted runtime or billing. The workflow has no automatic retry or cancel-in-progress policy; an owner must cancel a run that should stop.

The selected `actions/setup-java@v4` matches the existing CI job, but its [upstream metadata marks v4 deprecated and no longer updated](https://raw.githubusercontent.com/actions/setup-java/v4/action.yml). Confirm that action maintenance status before any hosted authorization. No ruleset, branch publication, workflow dispatch, cache write, PR edit, issue close, or merge is authorized by this candidate.

| Criterion | Current candidate status |
| --- | --- |
| PAC-1 | Current workflow and existing cache behavior remain documented in the investigation report. |
| PAC-2 | Partial. The report has sampled failure evidence; hosted cache inventory, cache hit/miss counts, transferred bytes, quota, and failure-rate data remain unavailable. |
| PAC-3 | Provider comparison is complete in the investigation report; this candidate uses the narrow manual `modules-2` design. |
| PAC-4 | The report's recommendation is recorded. This candidate does not establish that caching improves the build. |
| PAC-5 | The pilot workflow and paired measurement method are implemented locally. Hosted cold/warm measurements are not run. |
| PAC-6 | Risks, measurements, rollback, and authorization limits are recorded. Hosted storage and cache-service behavior remain unverified. |
| TAC-1 | Source, workflow, toolchain, and candidate identities are bound locally. There are no hosted run identities. |
| TAC-2 | Module dependencies, wrapper distributions, Robolectric artifacts, build outputs, and signing artifacts remain separate. |
| TAC-3 | The observer and isolated fixture are locally qualified. The hosted cold/warm comparison is not run. |
| TAC-4 | The workflow's task, host-test, signing, and artifact-verification sequence was compared with production `ci.yml`; the full candidate probe was not run. |
| TAC-5 | Only the authorized local candidate files changed. Production CI, dependencies, product code, issue state, report worktree, caches, and MCP registration were not changed. |
| TAC-6 | Independent non-authoring review of the final candidate is a required pre-commit gate; its evidence will be reported with the exact reviewed commit. |

PAC/TAC status does not establish hosted readiness, completion of the experiment, acceptance of outstanding criteria, issue closure, or merge authorization.
