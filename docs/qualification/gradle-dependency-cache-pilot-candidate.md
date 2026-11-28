# Issue #93 observer-repair campaign candidate

## Status and provenance

This candidate prepares a second hosted campaign after the first failed during its trusted cold seed. The observer repair passed an isolated local cold/warm qualification, but hosted cache-service behavior remains unverified. The second campaign has not been dispatched, and no remote state has changed. The investigation report and draft PR #94 remain in their separate worktree.

| Item | Identity or status |
| --- | --- |
| Task pin | `2026.11.25` |
| Policy revision | `8e391636cb50f9bfe6e8def2d0f54eeb65d1d157` |
| Approved base | `1823686d39f72b6d5701a7f25bdeed83cdcf727b` |
| Candidate starting commit | `4e3bbd2de468d3a5975d535465cc986f03cffdc9` |
| Second-campaign branch | `codex/issue-93-gradle-cache-observer-repair` |
| Worktree | `/Users/daniel/.codex/worktrees/issue-93-gradle-cache-observer-repair/Argus-ROM-Toolkit` |
| Campaign identity | `gradle-dependency-cache-observer-repair-v2` |
| Dependency-cache namespace | `argus-gradle-dependency-cache-observer-repair-v2` |
| Investigation report worktree | `/Users/daniel/.codex/worktrees/issue-93-gradle-cache-investigation/Argus-ROM-Toolkit` at `795eee3bcf1339a9ea1a7816790739cc8599459f` |
| Investigation report SHA-256 | `8e51311303bbf7b848fec66fcad47fd71abfc9bf06c9d398f89500d439e9d895` |
| Task-scoped tools | CodeGraph, TokenSave, and Serena initialized for this worktree |
| GPT Repo MCP | Pilot worktree is not enrolled. The approved-root list includes the primary checkout and Issue #76 worktree, but not this path. No registration changed and no restart was needed. |
| Investigation report MCP | The separate report worktree is also absent from the approved-root list. Its earlier MCP disposition remains unchanged. |

The investigation report remains the source for issue history and the approved PAC/TAC definitions. It is maintained in the separate worktree recorded above.

## Workflow boundary

The candidate changes one workflow, `.github/workflows/gradle-dependency-cache-experiment.yml`, and the isolated helper package under `scripts/gradle_dependency_cache/`. It does not edit `.github/workflows/ci.yml`, build files, dependency declarations, product code, or the investigation report.

The second campaign accepts pushes only to `codex/issue-93-gradle-cache-observer-repair` and PR `opened` events targeting `main`. Every push job checks the repository and owner IDs, actor ID `219249021`, triggering actor `whatobiplays`, the exact branch ref, branch protection, branch-creation event, and `run_attempt == 1`. The PR consumer checks the same repository, exact head branch and SHA, `main` base, authorized PR author and actor, and `run_attempt == 1`. It scans paginated workflow history and rejects a prior PR consumer for the same PR or head. It accepts a seed only when exactly one push run for the same head succeeded on its first attempt. Complete the branch-creation push campaign before opening the PR. Opening the PR earlier would use the single allowed PR event before a successful seed exists. Synchronize, reopen, workflow-dispatch, and rerun events do not start another campaign.

Before the first cold trial, `seed_cache_readback` restores the exact cache entry saved by `cache_seed` and compares its contents with the seed manifest. The PR consumer locates the successful first-attempt push run for the same head SHA, downloads its seed-manifest artifact, verifies the run, source commit, second-campaign branch and identity, cache key, and manifest digest, then checks the restored cache against that digest. Evidence records the PR head, base, merge, GitHub event, checked-out source, and seed source identities.

The PR consumer uses `cache-mode: read` and has only `actions: read` and `contents: read` permissions. A small JavaScript action records the effective `ACTIONS_CACHE_MODE` value when the runner provides it. The classifier also records the save-step outcome, exact-key readback, and hosted run, attempt, workflow, job, and step identities. A successful save step followed by a confirmed miss is recorded as `save_succeeded_readback_miss_unresolved`. That result remains unresolved until the exact action log is inspected, and the consumer remains successful. Retained evidence identifies the run-attempt log and `canary_save` step. The report does not infer an action-level skip or service denial from a green step or absent readback. Failed or contradictory readbacks and unexpected readable cache entries fail the consumer.

The first campaign’s exact-branch ruleset remains associated with `codex/issue-93-gradle-cache-pilot`; this candidate leaves it untouched. The proposed second-campaign ruleset targets only `codex/issue-93-gradle-cache-observer-repair`. It permits initial branch creation, then blocks updates, force pushes, and deletion. Its bypass list is empty, including for administrators and the owner. The workflow also checks the actor and protected-ref state. The second-campaign ruleset has not been created or changed.

The proposed repository ruleset payload is shown below for review only. It has not been submitted or created:

```json
{
  "name": "Issue 93 Gradle cache observer repair",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/codex/issue-93-gradle-cache-observer-repair"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "update", "parameters": { "update_allows_fetch_and_merge": false } },
    { "type": "deletion" },
    { "type": "non_fast_forward" }
  ]
}
```

The payload omits a `creation` rule so the initial push can create the matching branch. With an empty bypass list, the `update` rule blocks later pushes; `deletion` blocks branch deletion, and `non_fast_forward` blocks force pushes. GitHub documents these rule meanings and the repository ruleset API fields in its [available rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) and [REST API schema](https://docs.github.com/en/rest/repos/rules).

## First hosted campaign and local qualification

The first campaign used branch `codex/issue-93-gradle-cache-pilot`, campaign ID `gradle-dependency-cache-pilot-v1`, and cache namespace `argus-gradle-dependency-cache-pilot-v1`. Hosted run [46138508708](https://github.com/whatobiplays/Argus-ROM-Toolkit/actions/runs/46138508708), attempt 1, failed during `cache_seed`. Only one of 18 jobs started, `cache_seed`; the other 17 were skipped. The seed ran on Ubuntu 24 x86_64 with Gradle 9.1.0, Temurin 17.0.21.1+2, Android platform revision 2, and build-tools 36.0.0.

Task inventory and dry-run completed with full observer coverage. The probe build exited 0 after 57.104 seconds, but its observer coverage was incomplete: ten `external_resource_start_decode` errors occurred. The workflow stopped before trusted-manifest binding, cache save, or seed-manifest publication. It recorded a 159,128,857-byte body transfer for `org.robolectric:nativeruntime-dist-compat:1.0.18`, but did not verify the cached-file digest. This run is not a valid cold seed. The separate Robolectric repository grew by four files and 126,901,498 bytes; its target-file count was zero, and transfer-attempt logging was not observed. The directory change does not establish whether a network transfer occurred. The first branch, ruleset, and run evidence remain historical and unchanged.

The observer repair qualified locally at candidate HEAD `4e3bbd2de468d3a5975d535465cc986f03cffdc9` on macOS 27.2.1 arm64, with Gradle 9.1.0 and Temurin 17.0.21.1+2. Three cold and three warm Gradle invocations had complete observer coverage, zero observer errors, and successful `testProbeUnitTest`, `lintProbe`, and `assembleProbe` outcomes. The cold trial recorded one completed target transfer of 159,128,857 bytes. The resulting cached file had the same size and SHA-256 `a6c34d92c990754e5aee076032a36f8e38fcacb5eb878ebe0a324509f3864eef`. The warm trial recorded no Gradle external-resource body transfers. Both unsigned APKs were 2,148,781 bytes with SHA-256 `57f242dd8e333f6c54196193349e42b9270f96c17d93f38ad984bd6d3a1e487c`; disposable signing and signed-APK inspection passed.

The cold and warm `modules-2` manifests matched at SHA-256 `28a7cd1bebdcc5f5040c4fc24a143097f603a5f581ac8849f1c4bc4b8d6459ab`. Each covered 659 files, 507,209,725 manifest bytes, and 507,209,742 expanded bytes. The warm trial copied the verified directory into a fresh Gradle home. The wrapper directory and Robolectric Maven repository started empty. Each trial downloaded the wrapper distribution into its own home; the measured distribution was 721,155,298 bytes. Each isolated Robolectric repository grew by four files and 126,901,498 bytes. Probe-build time was 46.432 seconds cold and 34.990 seconds warm; total probe wall time was 121.994 and 117.763 seconds. One local pair cannot estimate hosted performance.

The local warm trial reused a copied local dependency cache. It did not exercise GitHub Actions cache restore or save, a hosted runner, or GitHub cache-service behavior. The observer implementation and measurement sequence remain unchanged by this campaign retarget. The retained qualification summary has SHA-256 `f1bf4b47e903ef217f3c0023f779e59e218b0d8ca3d9061d5b899e98926fbfe9`.

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

The report and candidate filenames describe the investigation without an issue number. The helper package, modules, and workflow name their responsibilities. The second-campaign branch is issue-specific because its ruleset and workflow guard target that exact ref. Cache keys begin with `argus-gradle-dependency-cache-observer-repair-v2`. The first campaign’s `argus-gradle-dependency-cache-pilot-v1` namespace remains historical.

## Cache path, key, and trust scope

The only path eligible for the full dependency cache is:

```text
${{ runner.temp }}/gradle-dependency-cache-experiment/state/gradle-home/caches/modules-2
```

The helper sets `GRADLE_USER_HOME` to the sibling `gradle-home` directory. Gradle wrapper distributions, the isolated Robolectric Maven repository, build outputs, evidence, and fixtures are outside `caches/modules-2`. The workflow does not set `setup-java`'s `cache` input, so that action's optional dependency cache is disabled. No Gradle build-output cache or configuration cache is enabled.

All full-cache restore and save steps use `actions/cache` pinned to `cdf6c1fa76f9f475f3d7449005a359c84ca0f306`. There are no restore prefixes. A usable warm result requires a successful restore, `cache-hit == true`, an exact matched/primary-key match, and the same canonical manifest digest as the trusted seed. The independent readback job runs before `trial_a_cold`; the PR consumer obtains the same digest from the successful seed run for its exact head SHA. Every non-exact result removes only `caches/modules-2`; an action failure is an error, not a cache miss. An unexpected warm miss or manifest mismatch stops that measurement chain.

The key begins with `argus-gradle-dependency-cache-observer-repair-v2` and includes Linux, runner architecture, the actual Temurin vendor and Java 17 runtime, Gradle 9.1.0, Android command-line tools 12266719, installed API 36 and build-tools 36.0.0 package revisions, and a SHA-256 over Gradle scripts, wrapper files, Gradle properties, version catalogs, lockfiles, and dependency-verification metadata. It does not hash application source. Including lock and verification files in the key does not add or strengthen project controls. The PR computes the same key from its head checkout and can consume only an exact match. The invalidation control restores using the changed dependency-input key itself; it adds no synthetic suffix that could independently cause a miss.

The wrapper properties select `gradle-9.1.0-all.zip` but do not set `distributionSha256Sum`. Hashing the wrapper properties and JAR into the cache key does not verify the downloaded distribution. This candidate adds no wrapper checksum setting.

The workflow requests Temurin Java 17, matching the production probe's Java major. It records the installed `java.runtime.version` and vendor in the key, then requires each paired run to match the seed. The setup-java v4 metadata and README support Temurin and the major-version request; Gradle 9.1.0 supports running on Java 17. The pinned v4 action metadata also marks that release deprecated and no longer maintained. This retarget keeps the action version and Java input unchanged; hosted runner compatibility remains untested. The major-version request avoids relying on the four-part Temurin release tag `17.0.21.1+2`, which the setup-java v4 README does not document as an exact SemVer input. Sources: [Temurin 17.0.21.1+2 release](https://github.com/adoptium/temurin17-binaries/releases/tag/jdk-17.0.21.1%2B2), [setup-java v4 README](https://raw.githubusercontent.com/actions/setup-java/v4/README.md), [setup-java v4 metadata](https://raw.githubusercontent.com/actions/setup-java/v4/action.yml), and [Gradle compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html).

GitHub cache scope still applies: push entries are written only under the protected `codex/issue-93-gradle-cache-observer-repair` branch. The namespace separates this campaign from the first campaign and ordinary repository caches. PR restoration is read-only and restricted to a same-repository observer-repair head. The workflow has no writer for `main`. The 1 GiB limit applies to every regular file under the full `modules-2` path eligible for saving, including lock files and `gc.properties`; it does not predict compressed service size or account quota. Symlinks and non-regular entries are rejected before the canonical digest excludes transient metadata. Evidence records digest bytes and full archive expanded bytes separately.

### Read-only hosted cache and setup-java preflight

On 28 November 2026, read-only GETs to GitHub’s [cache usage](https://docs.github.com/en/rest/actions/cache#get-github-actions-cache-usage-for-a-repository) and [cache listing](https://docs.github.com/en/rest/actions/cache#list-github-actions-caches-for-a-repository) endpoints reported six active entries totaling 5,941,195,572 bytes. All six were `refs/heads/main` Flutter SDK or Flutter pub caches. The paginated inventory contained no Issue #93 pilot key. The [storage-limit](https://docs.github.com/en/rest/actions/cache#get-github-actions-cache-storage-limit-for-a-repository) and [retention-limit](https://docs.github.com/en/rest/actions/cache#get-github-actions-cache-retention-limit-for-a-repository) endpoints returned HTTP 402 with a billing-access message, so configured limits remain independently unverified. The owner accepts GitHub’s documented defaults of 10 GB and seven-day retention as the operating assumption. The snapshot leaves 4,058,804,428 bytes below 10 GB before new entries. Usage can lag by about five minutes; concurrent cache growth and automatic eviction remain risks.

| Existing key | Bytes |
| --- | ---: |
| `flutter-linux-stable-3.44.7-x64-84fc5cbb223bc12f83d65b647ff8a56caf779ffd` | 1,690,636,307 |
| `flutter-macos-stable-3.44.7-arm64-84fc5cbb223bc12f83d65b647ff8a56caf779ffd` | 2,175,969,151 |
| `flutter-pub-linux-stable-3.44.7-x64-84fc5cbb223bc12f83d65b647ff8a56caf779ffd-f02ad488710aa52818a76009e714e8e3a24b8e146a55c2c18e84de7c14b4dc0a` | 67,150,676 |
| `flutter-pub-macos-stable-3.44.7-arm64-84fc5cbb223bc12f83d65b647ff8a56caf779ffd-f02ad488710aa52818a76009e714e8e3a24b8e146a55c2c18e84de7c14b4dc0a` | 62,014,106 |
| `flutter-pub-windows-stable-3.44.7-x64-84fc5cbb223bc12f83d65b647ff8a56caf779ffd-f02ad488710aa52818a76009e714e8e3a24b8e146a55c2c18e84de7c14b4dc0a` | 50,448,747 |
| `flutter-windows-stable-3.44.7-x64-84fc5cbb223bc12f83d65b647ff8a56caf779ffd` | 1,894,976,585 |

The pinned `actions/setup-java@v4` accepts Temurin Java 17, and Gradle 9.1.0's documented Java runtime range includes Java 17. This establishes input-level compatibility from upstream documentation, not hosted runner behavior. The pinned action metadata marks v4 deprecated and no longer updated; that maintenance status is recorded for a future authorization decision. GitHub documents that a mode-blocked cache save can log an informational message and complete successfully, and that JavaScript actions can read the effective `ACTIONS_CACHE_MODE`; the canary records both facts without treating them as proof of a service denial. No workflow version or Java input changed in this candidate. Sources: [GitHub cache-mode behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#controlling-cache-access-with-cache-mode), [setup-java v4 metadata](https://raw.githubusercontent.com/actions/setup-java/v4/action.yml), and [Gradle 9.1.0 compatibility](https://docs.gradle.org/9.1.0/userguide/compatibility.html).

## Trial procedure and measurements

Each hosted job checks out a fresh source tree. The runner fails if the probe's build directory already exists. It writes a wrapper-observation start record before the first `gradlew` command, snapshots wrapper distributions immediately before and after `gradlew --version`, and records elapsed time, file counts, byte counts, and snapshot digests. Wrapper files stay outside the cached path. Gradle 9.1.0 bypasses init scripts for `--version`, so the wrapper snapshot is the evidence for bootstrap effects; the internal observer covers each measured task invocation.

The observer is installed before the wrapper call. Its JSONL file is already open when the wrapper-observation marker is written. Each subsequent task inventory, dry-run, and actual build has a unique invocation ID with runner start and finish records. The init script must report exactly one readiness event for each ID, and every external-resource transfer must carry that ID. A missing marker, malformed record, observer error, or unbound transfer fails the measurement. The isolated fixture exercises a local Maven response and confirms that wrapper bootstrap and project dependency transfers are reported separately.

The runner follows the production `android-readiness-probe` sequence in `ci.yml`: task inventory, dry-run of `testProbeUnitTest lintProbe assembleProbe`, actual execution of those tasks, host-only qualification tests, and verification of a separately signed temporary APK copy. The actual build records each required task outcome and fails if any required task is missing, skipped, `NO-SOURCE`, `UP-TO-DATE`, `FROM-CACHE`, or failed. That copy is host-test material; it is not a distributable release or product qualification artifact. The runner passes `--no-build-cache` and `--no-configuration-cache`; each job starts with no probe build outputs. The unsigned APK is hashed before signing. Every warm run must match its paired cold SHA-256. Signing material and signed copies live in disposable `RUNNER_TEMP` directories and are not added to the cache or uploaded. Each invocation's elapsed time and task outcomes are persisted before the runner advances, so a later failure leaves earlier results and the failing command's timing in the uploaded evidence.

The hosted identity record includes the actual Gradle and Java versions, Java vendor, runner image OS/version, architecture, SDK package revisions, and a hash of the `RUNNER_TEMP` path. The key is built from the same identity. Each valid pair must match the seed; a drift stops the campaign.

The Gradle observer uses Gradle 9.1.0 internal build-operation APIs. It records resource identifiers as SHA-256 values, artifact suffix, transfer state, known byte count, and observer errors. The fixture qualifies the observed `ProgressLoggingExternalResourceAccessor$ReadOperationDetails` event type. For `org.robolectric:nativeruntime-dist-compat:1.0.18`, cold trials require a completed positive body transfer during `task_inventory`, `dry_run`, or `probe_build`. The control matches each event to the exact Maven coordinate and hashed artifact filename, then checks its byte count against the resulting `modules-2/files-2.1` file size and records that cached file's SHA-256. The URL and raw filename are not retained. Warm trials reject every artifact-body read event, including a completed zero-byte read. Missing, incomplete, and observer-error events fail observation coverage; the workflow does not count a missing observation as zero bytes.

Robolectric's local Maven repository is a separate sibling path set for test JVMs. Before and after file manifests record persisted file counts and bytes, hashed paths, content hashes, and whether a path is under `org/robolectric/nativeruntime-dist-compat/1.0.18/`. The runner records only transfer lines whose decoded Maven path contains adjacent `org/robolectric` segments. Each matching line is reduced to a resource SHA-256 and suffix; URLs and raw lines stay out of the evidence file. Failure lines mentioning Robolectric or `MavenArtifactFetcher` are counted separately. A persisted-file delta and a transfer attempt are separate observations. Neither a missing matching line nor an unchanged local repository proves that no network transfer occurred. No resolved transitive graph is asserted by this pilot.

Each measurement job uploads its redacted evidence with `if: always()` and a 14-day artifact retention target, including when the probe fails. The cache action archives the complete `modules-2` path. Before saving, validation checks every path and entry type and counts every file toward the 1 GiB expanded limit. Canonical digest generation then excludes only `.lock`, `.lck`, and `gc.properties`; its file count and digest byte count are reported separately from the full archive byte count. Stable manifests must match twice, two seconds apart. Cache-control fixtures are limited to 1 MiB; the workflow uses 64 KiB fixtures.

## Stop and rollback procedure

Stop the campaign if a writer predicate fails, the branch is not protected, the runner or JDK identity changes, a restore is inexact, a warm miss occurs, the canonical manifest differs, the artifact digest changes, or transfer evidence is missing or contradictory. Preserve every uploaded pair artifact. Do not rerun a failed job; the workflow rejects `run_attempt` values above one.

If the separately authorized second campaign must be rolled back, cancel the active run and disable the experimental workflow. Preserve the seed, cold/warm pair, PR, and failed-job evidence artifacts with their run IDs and source identities. Read the exact seed cache key from the trusted seed record, then remove only that key and the run-specific control keys: `argus-gradle-observer-repair-v2-empty-miss-${run_id}`, `argus-gradle-observer-repair-v2-fixture-semantic-${run_id}`, `argus-gradle-observer-repair-v2-fixture-collision-${run_id}`, `argus-gradle-observer-repair-v2-failed-writer-${run_id}-${run_attempt}`, and `argus-gradle-observer-repair-v2-pr-read-only-canary-${run_id}-${run_attempt}`. The invalidation key is read-only and is never saved. Confirm those exact keys are absent; leave default-branch caches and unrelated entries untouched. Remove the second-campaign branch and its ruleset only with separate owner authorization. Leave the first campaign’s branch, ruleset, and cache entries untouched. No rollback action was taken for this local candidate.

## Hosted resource ceiling and remaining gates

The 17 push jobs have a theoretical timeout ceiling of 615 runner-minutes: eight 60-minute jobs and nine 15-minute controls. One PR consumer adds at most 60 minutes. The experiment therefore stays within 18 jobs and 675 experimental runner-minutes for one branch-creation push and one PR-open event. The existing `ci.yml` defines at most nine runner jobs per event after matrix expansion, including its conditional macOS qualification job. One push and one PR-open event can add up to 18 ordinary CI jobs, for 36 jobs with this experiment. The proposed total ceiling remains 54 jobs including ordinary and conditional CI. No additional experimental job was added. These are configured timeout ceilings, not predicted runtime or billing. The workflow has no automatic retry or cancel-in-progress policy; an owner must cancel a run that should stop.

The selected `actions/setup-java@v4` matches the existing CI job, but its [upstream metadata marks v4 deprecated and no longer updated](https://raw.githubusercontent.com/actions/setup-java/v4/action.yml). Confirm that action maintenance status before any hosted authorization. This candidate does not authorize creating the second ruleset, publishing a remote branch, dispatching the workflow, writing hosted caches, opening an experimental PR, editing the report PR, closing the issue, or merging.

| Criterion | Current candidate status |
| --- | --- |
| PAC-1 | Current workflow and existing cache behavior remain documented in the investigation report. |
| PAC-2 | Partial. The first hosted attempt recorded a target transfer but did not verify its cached-file digest, and all paired hosted trials were skipped. The local cold/warm pair is documented separately. The six-entry inventory remains read-only; configured limits are unverified, and the owner-approved 10 GB/seven-day defaults remain an operating assumption. |
| PAC-3 | Provider comparison is complete in the investigation report; this candidate uses the narrow manual `modules-2` design. |
| PAC-4 | The report's recommendation is recorded. This candidate does not establish that caching improves the build. |
| PAC-5 | The local cold/warm measurement and isolated target-artifact observer are qualified. The second campaign’s hosted measurements have not run. |
| PAC-6 | Risks, measurements, rollback, and authorization limits are recorded. Existing entries were inventoried read-only. Configured cache limits and second-campaign cache-service behavior remain unverified; automatic eviction and concurrent growth remain risks. |
| TAC-1 | Local source, workflow, toolchain, invocation, seed, and candidate identities are recorded, as is failed hosted run `46138508708`. The second campaign has no hosted run identity. |
| TAC-2 | Module dependencies, wrapper distributions, Robolectric artifacts, build outputs, and signing artifacts remain separate. |
| TAC-3 | The observer passed local cold/warm artifact checks. The first hosted attempt had incomplete observer coverage and no verified cached-file digest; the second hosted comparison has not run. |
| TAC-4 | The probe, required tasks, host tests, disposable signing, and artifact verification passed locally. The first hosted probe exited 0 but failed observer-coverage validation. The second hosted probe has not run. |
| TAC-5 | Only in-scope candidate files changed. Production CI, dependencies, product code, issue state, report worktree, shared or hosted caches, and MCP registration were not changed. |
| TAC-6 | Independent clean-context review of the campaign-retargeting diff completed with no code or scope findings. Supplemental ruleset and evidence checks found no discrepancies. The proposal remains unsubmitted; hosted PR review and CI remain outside scope. |

PAC/TAC status does not establish hosted readiness, completion of the experiment, acceptance of outstanding criteria, issue closure, or merge authorization.
