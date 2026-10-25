# Issue 24 production staging implementation ledger

## 1. Authority and baseline

The owner authorized production host fixture-staging implementation on 2026-10-25,
including the eight amendments governing storage, XPC, acyclic oracle provenance,
platform scope, recovery, qualification tiers, facade compatibility, and vertical
slices. This authorization permits issue-scoped source changes, tests, commits,
pushes and PRs. It does not authorize privileged installation on the owner's Mac,
owner-key enrollment, access to an undesignated ROM corpus, or fabricated evidence.

Baseline: `25bcbc0b2895673dc02022cec2fbd3f7ff58accf` (`origin/main`).
Branch: `codex/issue-24-production-staging` in an isolated managed worktree.
The primary checkout's 17 pre-existing untracked files and original index were
copied and hash-verified in an owner-private preservation directory before work.
Historical worktrees, archives, blocked evidence, and unrelated caches are retained.

## 2. Qualification tiers

| Tier | Meaning | Current result |
|---|---|---|
| A | Deterministic synthetic correctness | Baseline host suite passed previously; new implementation pending |
| B | Actual OS isolation and authenticated IPC in a verified disposable environment | NOT_RUN; no eligible VM available |
| C | Production signing, owner consent, installation and exact deployment configuration | BLOCKED; no approved production enrollment or installation |
| D | Explicitly authorized genuine private fixtures and independent identity provenance | BLOCKED; no corpus designated for this execution |

Passing a tier does not confer another tier. Host preparation does not establish
Android destination isolation, Add & Scan behavior, a physical product result,
or an owner verdict. Those product operations remain under Issue 26.

## 3. Environment and storage

Direct host inspection reports macOS 27.0.1, build 26A434, ARM64 and local APFS.
Xcode 27.1 supplies the macOS 27.0 SDK. The existing product compilation target is
macOS 12.0 ARM64. Compilation target, executable compatibility and qualified OS
coverage are separate properties; the new backend must not infer qualification
from API availability.

At implementation start the data volume had approximately 6.9 GiB available.
The worktree and `/private/tmp` share that volume. No external development volume
or eligible macOS VM tool/guest was found. Source size is approximately 14 MiB.
Use task-owned build/evidence directories with a checked 2 GiB host reserve for
small native builds; do not allocate VM disks or multi-gigabyte fixtures here.
No existing unrelated data or caches may be deleted to make space.

## 4. Execution sequence

1. Preservation, capacity preflight and bounded native build setup: VERIFIED; review pending.
2. Versioned snapshot/oracle authority, canonical schemas and tests: IN_PROGRESS.
3. Native namespace and authenticated broker/service interface: NOT_STARTED.
4. Immutable snapshot acquisition, verification and publication: NOT_STARTED.
5. Durable recovery, export and cleanup: NOT_STARTED.
6. Sleep-inclusive timing schema 2: NOT_STARTED.
7. Native/Python integration and production admission: NOT_STARTED.
8. Disposable-VM adversarial qualification: BLOCKED on infrastructure; bundle pending.
9. Genuine owner-corpus qualification and acceptance: BLOCKED on owner inputs.

## 5. Binding implementation decisions

1. The new, versioned contract makes sealed service-protected snapshots authoritative.
   Original files are read-only inputs. Their subsequent mutation does not mutate
   a sealed snapshot or prove that the original pathname stayed unchanged.
2. Preserve all legacy manifest, timing and evidence meanings. Do not migrate
   historical records into destructive authority or invent independent identity.
3. Use native Objective-C with ARC, public C XPC connection signing requirements,
   Security.framework, AppKit and POSIX operations. Check both peers before
   sensitive messages; message-derived code checks supplement connection checks.
4. Root protects the installation and staging ancestry. A distinct noninteractive
   service identity owns the fixed staging namespace. No elevated Python executes.
5. Production consent uses an enrolled non-exportable owner key and actual user
   presence. VM-only test keys and endpoints cannot satisfy production authority.
6. Persist mutation intent and sequence before effects. An uncertain mutation is
   never blindly repeated. Cleanup attempts are at most once per recorded member;
   retain unresolved state and replay tombstones outside deleted payloads.
7. Production `destination=None` may select only a verified installed native
   implementation. Caller-selected roots remain refused; no synthetic fallback.
8. Record byte integrity, structural validity, independent game identity, owner
   approval, producer completion and verified receiver completion separately.

## 6. Acceptance matrix

| Issue criterion | Existing evidence | Missing closeout evidence | Status |
|---|---|---|---|
| Versioned private manifest and independent expectations | Expectation-only schema 1 | Oracle provenance and genuine approved corpus | BLOCKED |
| Large streaming, reserve, tracks/playlists | Synthetic Python mechanics | Native actual transfer and genuine companion preservation | BLOCKED |
| Full verification, quarantine, proven-owned cleanup | Synthetic Python recovery | Kernel isolation, native publication and cleanup qualification | BLOCKED |
| Corruption, companion, capacity, interrupted-transfer tests | Baseline host suite | New contract/native regressions and fault qualification | IN_PROGRESS |

## 7. Validation and review log

The planning pass ran 765 host tests with two skips; archive, naming and diff
checks passed. These observations do not qualify a native implementation.
Implementation validations, source inventories, review dispositions, commit IDs
and remaining owner actions will be appended as each slice is verified.

### 7.1 Preservation and build setup

The isolated baseline host suite completed successfully (765 tests, two skips).
Six resource-admission tests passed after an initial missing-implementation
failure. The capacity guard checks the actual backing filesystem and requires
the complete estimated allocation plus reserve; it never creates the requested
artifact directory or frees existing content.

A 36 KiB task-owned Objective-C toolchain probe linked Foundation, Security,
AppKit and LocalAuthentication and executed on the actual ARM64 host with a
macOS 12.0 compilation target. This is build compatibility evidence, not native
isolation or support qualification. Docker offers only local/Linux contexts;
it cannot supply the required macOS isolation proof. No privileged operation ran.

Local Cubic identified unnecessary filesystem-device disclosure in successful
CLI output; the field was removed and a subprocess privacy regression added.
Independent review identified dangling/cyclic symlink ancestry being mistaken
for a directory not yet created; both cases reproduced before correction and
now fail closed. Cubic's local repository context is unavailable despite the
configured Git remote; its diff review is recorded without claiming hosted review.
