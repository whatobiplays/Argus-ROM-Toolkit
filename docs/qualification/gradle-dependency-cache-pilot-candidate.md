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

The workflow accepts a push to `codex/issue-93-gradle-cache-pilot` and a PR `opened` event targeting `main`. Every push job checks the repository and owner IDs, actor ID `219249021`, triggering actor `whatobiplays`, exact branch ref, branch protection, a branch-creation event, and `run_attempt == 1`. The PR consumer checks the same repository, exact head branch and SHA, `main` base, authorized PR author and actor, and `run_attempt == 1`. It scans all pages of workflow history and rejects any prior PR consumer for the same PR or head. It accepts a seed only when exactly one push campaign exists for that head and that campaign succeeded on its first attempt. Complete the branch-creation push campaign successfully before opening the PR. Opening it earlier consumes the one allowed PR event and leaves the cache consumer without a successful seed; synchronize, reopen, workflow-dispatch, and rerun events do not start another campaign.

Before the first cold trial, `seed_cache_readback` restores the exact cache entry saved by `cache_seed` and compares its contents with the seed manifest. The PR consumer locates the one successful first-attempt push run for the same head SHA, downloads its seed-manifest artifact, verifies the run, source commit, branch, campaign, cache key, and manifest digest, then checks the restored cache against that digest. The evidence records PR head, base, merge, GitHub event, checked-out source, and seed source identities.

The PR consumer uses `cache-mode: read` and has only `actions: read` and `contents: read` permissions. Its save canary records the save step outcome and exact-key readback. An observed skipped step is recorded as skipped. A successful save step followed by a cache miss remains unresolved; neither green status nor an absent readback is described as an action-level skip or service denial.

Before hosted execution, the owner must create a ruleset that targets only `codex/issue-93-gradle-cache-pilot`. The ruleset allows initial branch creation, then blocks all updates, force pushes, and deletion. It has no bypass actors, including administrators and the owner. This lets the initial branch-creation push run while preventing later changes to the campaign source. The workflow also checks the actor and protected-ref state. No ruleset was created or changed for this candidate.

## Eighteen-job matrix

The workflow defines 17 push jobs and one PR consumer. The first group performs the dependency measurements; the remaining push jobs exercise bounded cache controls.

| Job IDs | Cache mode | Purpose |
| --- | --- | --- |
| `cache_seed` | `write-only` | Run the probe from an empty module cache, record the seed manifest, and save after a successful probe and daemon shutdown. |
| `trial_a_cold`, `trial_b_cold`, `trial_c_cold` | `none` | Run three fresh cold trials without cache reads or writes. |
| `trial_a_warm`, `trial_b_warm`, `trial_c_warm` | `read` | Restore the exact seed, compare its canonical manifest, and run the matching warm trial. |
| `cache_miss_invalidation` | `read` | Require a clean ordinary miss and a miss after changing the dependency-input fingerprint, then run a cold fallback. |
| `seed_cache_readback` | `read` | Independently restore the exact seed and compare its manifest before the first cold trial; record that a real service-fault test is unsupported. |
| `partial_extraction_recovery` | `none` | Force partial-cache cleanup to fail, prove the Gradle fallback sentinel is skipped, then remove the disposable path. |
| `bounded_fixture_seed` | `write-only` | Save separate 64 KiB semantic and collision fixtures. |
| `semantic_fixture_recovery` | `read` | Restore fixture A, damage only the local extraction, remove it, and restore A again from its immutable cache. |
| `immutable_collision_writer` | `write-only` | Attempt to save fixture B under fixture A's existing immutable key. |
| `immutable_collision_readback` | `read` | Require fixture A to survive the collision attempt. |
| `failed_writer_key_absent` | `read` | Verify the run-specific failed-writer key starts absent. |
| `expected_failed_writer` | `write` | Create a separate bounded payload, fail before save, and require the save step to be skipped. |
| `failed_writer_key_readback` | `read` | Require the failed-writer key to remain absent after the failure. |
| `pull_request_consumer` | `read` | Run the exact-head PR consumer and the action-level read-only save canary. |

The service-fault limitation is recorded in the independent seed-readback job. That job also gates the first cold trial. The failed-writer key is never seeded. The semantic and collision fixtures use separate keys; no trusted measurement entry is intentionally corrupted.

## Naming supplement

The investigation and candidate note use subject-based filenames without an issue number. The helper package is named for its Gradle dependency-cache responsibility, and its modules name their roles (`control`, `runner`, and the observer fixture). The workflow name identifies this as an experiment. The branch and cache namespace include Issue #93 intentionally so the hosted pilot can be isolated from production caches and other experiments. These names do not present the pilot as a reusable production cache implementation.

## Cache path, key, and trust scope

The only path eligible for the full dependency cache is:

```text
${{ runner.temp }}/gradle-dependency-cache-experiment/state/gradle-home/caches/modules-2
```

The helper sets `GRADLE_USER_HOME` to the sibling `gradle-home` directory. Gradle wrapper distributions, the isolated Robolectric Maven repository, build outputs, evidence, and fixtures are outside `caches/modules-2`. The workflow does not set `setup-java`'s `cache` input, so that action's optional dependency cache is disabled. No Gradle build-output cache or configuration cache is enabled.

All full-cache restore and save steps use `actions/cache` pinned to `cdf6c1fa76f9f475f3d7449005a359c84ca0f306`. There are no restore prefixes. A usable warm result requires a successful restore, `cache-hit == true`, an exact matched/primary-key match, and the same canonical manifest digest as the trusted seed. The independent readback job runs before `trial_a_cold`; the PR consumer obtains the same digest from the successful seed run for its exact head SHA. Every non-exact result removes only `caches/modules-2`; an action failure is an error, not a cache miss. An unexpected warm miss or manifest mismatch stops that measurement chain.

The key starts with the isolated `argus-gradle-issue93-pilot-v1` namespace and includes Linux, runner architecture, the actual Temurin vendor and Java 17 runtime, Gradle 9.1.0, Android command-line tools 12266719, the installed API 36 and build-tools 36.0.0 package revisions, and a SHA-256 over Gradle scripts, wrapper files, Gradle properties, version catalogs, lockfiles, and dependency-verification metadata. It does not hash application source. Including lock and verification files in the key does not add or strengthen those project controls. The PR computes the same key from its head checkout and can consume only an exact match. The invalidation control restores using the changed dependency-input key itself; it adds no synthetic suffix that could independently cause a miss.

The wrapper properties select `gradle-9.1.0-all.zip` but do not set `distributionSha256Sum`. Hashing the wrapper properties and JAR into the cache key does not verify the downloaded distribution. This candidate adds no wrapper checksum setting.

The workflow requests Temurin Java 17, matching the production probe's Java major. It records the installed `java.runtime.version` and vendor in the key, then requires each paired run to match the seed. This avoids a stale fixed patch literal: the Temurin release published on 18 November 2026 is tagged `17.0.21.1+2`, while the prior candidate literal `17.0.21+2` did not match that release. The setup-java v4 README documents exact SemVer forms, but not this four-part form, so the workflow uses the supported major-version request and compares the resolved runtime. Sources: [Temurin 17.0.21.1+2 release](https://github.com/adoptium/temurin17-binaries/releases/tag/jdk-17.0.21.1%2B2) and [setup-java v4 version syntax](https://github.com/actions/setup-java/blob/v4/README.md#supported-version-syntax).

GitHub cache scope still applies: push entries are written only under the protected pilot branch. The namespace distinguishes this experiment from ordinary repository caches. PR restoration is read-only and restricted to the same-repository pilot head. The workflow contains no writer for `main`. Repository cache inventory and remaining quota were not available through the authorized GitHub connector, so existing usage and storage headroom remain unverified. The 1 GiB limit applies to every regular file under the full `modules-2` path eligible for saving, including lock files and `gc.properties`; it does not predict compressed service size or account quota. Symlinks and non-regular entries are rejected before the canonical digest excludes transient metadata. The evidence records digest bytes and full archive expanded bytes separately.

## Trial procedure and measurements

Each hosted job checks out a fresh source tree. The runner fails if the probe's build directory already exists. It writes a wrapper-observation start record before the first `gradlew` command, snapshots wrapper distributions immediately before and after `gradlew --version`, and records elapsed time, file counts, byte counts, and snapshot digests. Wrapper files stay outside the cached path. Gradle 9.1.0 bypasses init scripts for `--version`, so the wrapper snapshot is the evidence for bootstrap effects; the internal observer covers each measured task invocation.

The observer is installed before the wrapper call. Its JSONL file is already open when the wrapper-observation marker is written. Each subsequent task inventory, dry-run, and actual build has a unique invocation ID with runner start and finish records. The init script must report exactly one readiness event for each ID, and every external-resource transfer must carry that ID. A missing marker, malformed record, observer error, or unbound transfer fails the measurement. The isolated fixture exercises a local Maven response and confirms that wrapper bootstrap and project dependency transfers are reported separately.

The runner follows the production `android-readiness-probe` sequence in `ci.yml`: task inventory, dry-run of `testProbeUnitTest lintProbe assembleProbe`, actual execution of those tasks, host-only qualification tests, and verification of a separately signed temporary APK copy. The actual build records each required task outcome and fails if any required task is missing, skipped, `NO-SOURCE`, `UP-TO-DATE`, `FROM-CACHE`, or failed. That copy is host-test material; it is not a distributable release or product qualification artifact. The runner passes `--no-build-cache` and `--no-configuration-cache`; each job starts with no probe build outputs. The unsigned APK is hashed before signing. Every warm run must match its paired cold SHA-256. Signing material and signed copies live in disposable `RUNNER_TEMP` directories and are not added to the cache or uploaded. Each invocation's elapsed time and task outcomes are persisted before the runner advances, so a later failure leaves earlier results and the failing command's timing in the uploaded evidence.

The hosted identity record includes the actual Gradle and Java versions, Java vendor, runner image OS/version, architecture, SDK package revisions, and a hash of the `RUNNER_TEMP` path. The key is built from the same identity. Each valid pair must match the seed; a drift stops the campaign.

The Gradle observer uses Gradle 9.1.0 internal build-operation APIs. It records resource identifiers as SHA-256 values, artifact suffix, transfer state, known byte count, and observer errors. The fixture qualifies the observed `ProgressLoggingExternalResourceAccessor$ReadOperationDetails` event type. For `org.robolectric:nativeruntime-dist-compat:1.0.18`, cold trials require a completed positive body transfer during `probe_build`. The control matches the event to the exact Maven coordinate and hashed artifact filename, then checks its byte count against the resulting `modules-2/files-2.1` file size and records that cached file's SHA-256. The URL and raw filename are not retained. Warm trials reject every artifact-body read event, including a completed zero-byte read. Missing, incomplete, and observer-error events fail observation coverage; the workflow does not count a missing observation as zero bytes.

Robolectric's local Maven repository is a separate sibling path set for test JVMs. Before and after file manifests record persisted file counts and bytes, hashed paths, content hashes, and whether a path is under `org/robolectric/nativeruntime-dist-compat/1.0.18/`. The runner records only transfer lines whose decoded Maven path contains adjacent `org/robolectric` segments. Each matching line is reduced to a resource SHA-256 and suffix; URLs and raw lines stay out of the evidence file. Failure lines mentioning Robolectric or `MavenArtifactFetcher` are counted separately. A persisted-file delta and a transfer attempt are separate observations. Neither a missing matching line nor an unchanged local repository proves that no network transfer occurred. No resolved transitive graph is asserted by this pilot.

Each measurement job uploads its redacted evidence with `if: always()` and a 14-day artifact retention target, including when the probe fails. The cache action archives the complete `modules-2` path. Before saving, validation checks every path and entry type and counts every file toward the 1 GiB expanded limit. Canonical digest generation then excludes only `.lock`, `.lck`, and `gc.properties`; its file count and digest byte count are reported separately from the full archive byte count. Stable manifests must match twice, two seconds apart. Cache-control fixtures are limited to 1 MiB; the workflow uses 64 KiB fixtures.

## Stop and rollback procedure

Stop the campaign if a writer predicate fails, the branch is not protected, the runner or JDK identity changes, a restore is inexact, a warm miss occurs, the canonical manifest differs, the artifact digest changes, or transfer evidence is missing or contradictory. Preserve every uploaded pair artifact. Do not rerun a failed job; the workflow rejects `run_attempt` values above one.

If a separately authorized hosted run must be rolled back, cancel the active run and disable the experimental workflow. Preserve the seed, cold/warm pair, PR, and failed-job evidence artifacts with their run IDs and source identities. Read the exact seed cache key from the trusted seed record, then remove only that key and the run-specific control keys: `argus-gradle-empty-miss-v1-${run_id}`, `argus-gradle-fixture-semantic-v1-${run_id}`, `argus-gradle-fixture-collision-v1-${run_id}`, `argus-gradle-failed-writer-v1-${run_id}-${run_attempt}`, and `argus-gradle-pr-read-only-canary-v1-${run_id}-${run_attempt}`. The invalidation key is read-only and is never saved. Confirm the exact keys are absent; leave default-branch caches and unrelated entries untouched. Remove the exact pilot branch ruleset and branch only with separate owner authorization. No rollback action was taken for this local candidate.

## Hosted resource ceiling and remaining gates

The 17 push jobs have a theoretical timeout ceiling of 615 runner-minutes: eight 60-minute jobs and nine 15-minute controls. One PR consumer adds at most 60 minutes. The experiment therefore stays within 18 jobs and 675 experimental runner-minutes for one branch-creation push and one PR-open event. The existing `ci.yml` defines at most nine runner jobs per event after matrix expansion, including its conditional macOS qualification job. One push and one PR-open event can add up to 18 ordinary CI jobs, for 36 jobs with this experiment. The proposed total ceiling remains 54 jobs including ordinary and conditional CI. No additional experimental job was added. These are configured timeout ceilings, not predicted runtime or billing. The workflow has no automatic retry or cancel-in-progress policy; an owner must cancel a run that should stop.

The selected `actions/setup-java@v4` matches the existing CI job, but its [upstream metadata marks v4 deprecated and no longer updated](https://raw.githubusercontent.com/actions/setup-java/v4/action.yml). Confirm that action maintenance status before any hosted authorization. No ruleset, branch publication, workflow dispatch, cache write, PR edit, issue close, or merge is authorized by this candidate.

| Criterion | Current candidate status |
| --- | --- |
| PAC-1 | Current workflow and existing cache behavior remain documented in the investigation report. |
| PAC-2 | Partial. The report has sampled failure evidence. Hosted cache inventory, hit/miss counts, transferred bytes, quota, and failure-rate data remain unavailable. |
| PAC-3 | Provider comparison is complete in the investigation report; this candidate uses the narrow manual `modules-2` design. |
| PAC-4 | The report's recommendation is recorded. This candidate does not establish that caching improves the build. |
| PAC-5 | The pilot workflow and paired measurement method are implemented locally. The isolated target-artifact observer fixture is qualified; hosted cold/warm measurements are not run. |
| PAC-6 | Risks, measurements, rollback, and authorization limits are recorded. Hosted storage and cache-service behavior remain unverified. |
| TAC-1 | Source, workflow, toolchain, task-invocation, seed, and candidate identities are recorded locally. There are no hosted run identities. |
| TAC-2 | Module dependencies, wrapper distributions, Robolectric artifacts, build outputs, and signing artifacts remain separate. |
| TAC-3 | The observer and isolated exact-artifact fixture are locally qualified. The hosted cold/warm comparison is not run. |
| TAC-4 | The workflow's task, host-test, signing, and artifact-verification sequence was compared with production `ci.yml`; the full candidate probe was not run. Required task outcomes now reject skipped or reused work. |
| TAC-5 | Only the authorized local candidate files changed. Production CI, dependencies, product code, issue state, report worktree, shared or hosted caches, and MCP registration were not changed. |
| TAC-6 | The correction delta and cumulative local candidate require independent non-authoring review before commit. Hosted PR review and CI remain outside this candidate. |

PAC/TAC status does not establish hosted readiness, completion of the experiment, acceptance of outstanding criteria, issue closure, or merge authorization.
