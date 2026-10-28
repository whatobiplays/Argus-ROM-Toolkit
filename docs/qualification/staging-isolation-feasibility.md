# Historical: Production Staging Isolation Feasibility

> This document records the earlier privileged isolation proposal. It is
> retained as design history and is superseded for Issue #24 host staging by
> [ADR-004](../adr/adr-004-best-effort-fixture-staging.md). It is not current
> operating guidance. The privileged service, signing, and isolation procedure
> described below was not installed or qualified.

## 1. Status and boundaries

1. This was a prospective design for macOS-hosted Android qualification. It was
   not installed, was not a security attestation, and did not authorize the
   privileged procedure below. At the time of this proposal, production stage
   and cleanup returned `BLOCKED_UNSUPPORTED_EXCLUSIVITY` before caller
   inspection.
2. Host staging and Android staging are different namespaces. The proposed
   macOS anchor does not protect `/sdcard/ArgusQualification`, qualify an
   Android storage implementation, authorize ADB, or unblock Issue #26.
3. The earlier correction associated with this proposal was limited to integer
   clock precision and deterministic regressions. PR #47, Issue #23
   authorization, Issue #25 evidence, ordinary application state, private ROM
   originals, and historical blocked results retained their contracts.
4. The hostile actor is a distinct concurrent process with the operator's UID,
   including a process that ignores locks, launches legitimate executables,
   supplies malicious IPC, and races publication/recovery/cleanup. Root,
   kernel compromise, compromised trusted signed code, and arbitrary execution
   as the dedicated service identity are outside the proposed boundary. A
   service/client crash is inside the boundary. Availability is not guaranteed.

## 2. Installation and namespace ownership

1. Use a dedicated non-login account `_argusqual` with a private primary group,
   no supplementary groups, no reusable password, no interactive shell, and no
   write access to owner source trees. Root performs installation only; fixture
   handling runs as the dedicated account. Account UID/GID allocation must be
   recorded and collision-checked, never assumed from an account name.
2. Fix the production anchor at
   `/private/var/db/argus-qualification/staging`. Its parent is root-owned,
   mode `0755`, with no ACL allowing operator/service modification. The anchor
   is service-owned, mode `0700`. Root protects the anchor's directory entry;
   the service owns its contents. No caller-selected root is accepted.
3. Quarantines, final trees, generation files, locks, owner markers, retained
   temporary sidecars, and export-session state all remain below that anchor.
   Directory entries are service-owned `0700`; regular files are `0600`.
   There are no operator-owned exchange directories or temporary sidecars.
4. Install signed native broker/service binaries and all non-system resources
   under root-owned nonwritable parents. Do not launch Python from the checkout,
   a virtualenv, Homebrew, a user-controlled framework, or writable imports.
   The production implementation language/package needs a separate approved
   implementation design; the proof bundle below is an isolated native test
   artifact, not product integration.
5. The trusted chain includes launchd configuration, executable, dynamic loader,
   linked frameworks/libraries, resources, signing requirements, and any helper.
   Inventory executable hashes, designated requirements, entitlements, runtime
   flags, loaded-image paths, owners, ACLs, flags, and every ancestor. Reject
   writable rpaths, plugins, environment-based loading, debugger entitlement,
   disabled library validation, or extra service groups. Any missing receipt
   fails admission. A signed file in an attacker-writable parent is insufficient.

| Namespace | Operator and interfering same-UID actor | Service | Installer |
|---|---|---|---|
| Owner-private originals | Existing owner rights remain | Read-only validated descriptors | No routine access |
| Installed binaries/config and anchor parent | No mutation | Read/execute; no replacement | Controlled setup/update/removal |
| Anchor directory entry | No move, replace, or deletion | Cannot move entry in root-owned parent | Exceptional administration |
| State/quarantine/final/sidecars | No traversal, read, create, link, rename, replace, or delete | Sole routine reader/writer | Explicit recovery only |
| Cleanup targets | No direct mutation | Named-session cleanup under immutable authority | Separate recovery/disposal |
| Export pipe | Approved reader only | Producer; no destination pathname supplied | None |

6. The same permissions must hold before/during publication, while both peers
   are stopped, after crashes, and throughout recovery and deletion. Ordinary
   modes/ACLs become useful only because the service has a different UID.
   Same-UID `0700`, advisory locks, hidden names, inode checks, no-follow opens,
   and post-rename rechecks alone remain insufficient. User immutable flags
   are owner-reversible; system flags obstruct staging and require privilege.

## 3. Authenticated authority and narrow interface

1. Use a root-installed system Mach service and XPC. Service and broker validate
   each other's live audit-token-derived code identity: owner-approved signing
   team, exact bundle/designated requirement, and approved executable revision.
   Bind the connection to the live audit token, not a PID lookup or UID alone.
   The broker's trusted code and resources must have hardened runtime and no
   injection/debug entitlements. Validate effective credentials as well as
   signatures. The exact signing identity is an outstanding owner decision.
2. A copied legitimate broker binary is not session authorization. Before
   requesting a session, the broker displays the exact fixture/plan/rule and
   operation digests and obtains fresh owner consent using a trusted native
   interaction. It signs the exact consent envelope with a dedicated
   non-exportable P-256 owner key, gated by Keychain access control requiring
   user presence and the approved broker identity. The installer pins the public
   key. Enrollment/rotation requires separate owner authorization and belongs to
   future proof setup, not this correction. The service verifies the signature
   as well as the broker connection. Caller inputs cannot select the public key.
   It has no unattended approval, environment bypass, arbitrary
   command interface, or synthetic-consent production flag. Untrusted Python
   may request a review; it cannot approve it. The broker sends consent-bound
   immutable bytes on its authenticated connection. This additional consent
   does not replace the existing approval sidecar. The service independently
   parses and validates those bytes against the existing owner authorization,
   approval, allowed operation, package, deadlines, and digest contracts.
3. The broker generates a fresh request nonce; the service generates a session
   identifier and challenge. Consent covers both, the installed revision, live
   broker connection, exact input digests, allowed operations, and cleanup flag.
   The service durably consumes the nonce before mutation. Each mutation uses
   a strictly increasing request sequence linked to the last committed state.
   Duplicate, stale, reordered, cross-session, and cross-connection mutation
   requests are rejected. Read-only status queries report the durable outcome
   of an interrupted request; clients never blindly retry a mutation.
4. Only the service can issue production authority. Its session object stays
   inside the service and binds installation identity, owner consent, operation,
   original boot/timing record, and state generation. A version 1 consent
   envelope uses canonical JSON with integer-only values and binds owner-key ID,
   broker revision/audit-token identity, installation ID, service boot ID,
   challenge, nonce, session ID, authorization/approval/plan/rules/fixture digests,
   operation allowlist, cleanup flag, and original expiry limits. Unknown fields
   or versions, malformed signatures and ambiguous encodings block.
   A Python grant, bearer
   token, caller boolean, peer UID, or synthetic capability cannot mint it.
   Fresh IPC authority after restart does not renew a persisted deadline.
5. Define one private `StagingSessionStore` boundary owning isolation, state,
   publication, and destructive cleanup. Its fixed operations are
   `admit_session`, `stage_verified`, `inspect_session`, `validate_eligibility`,
   `open_readonly_export`, `classify_recovery`, and `cleanup_session`.
   Requests use opaque session/fixture identifiers, pinned inputs, and sequence
   numbers. No public `open`, `rename`, `write`, `unlink`, recursive deletion,
   shell execution, caller-root argument, or arbitrary destination path exists.
6. Cleanup requires its originally approved allowlist entry and valid cleanup
   authority at every destructive boundary, with ownership and installation
   proof. A same-UID attacker cannot use the broker to delete arbitrary paths,
   another session, or an expired session. Signing identifies code; explicit
   owner consent and service-side session checks supply operation authority.
7. Service loss immediately blocks admission/export/mutation. Broker loss
   invalidates connection authority. Recovery can classify retained state;
   reattachment requires fresh authenticated consent for the same original
   session and inputs, without altering its deadline. Uncertain transitions
   remain retained and ineligible; no automatic mutation retry or startup sweep.

## 4. Original sources and read-only export

1. The trusted broker runs as the owner. It opens approved roots and regular
   members read-only with no-follow directory-relative traversal, verifies the
   original directory/file identities and complete membership, and keeps the
   source permissions unchanged. It holds any required security-scoped access
   for the complete observation/transfer interval; denial or stale bookmarks
   block. Security scope does not override POSIX/ACL permissions.
2. Pass regular-file read descriptors using XPC descriptor transfer. The service
   checks `F_GETFL & O_ACCMODE == O_RDONLY`, regular type, owner, link count,
   size, device/inode and metadata; rejects writable handles and special files;
   independently hashes the complete contents against the approved manifest;
   and checks metadata before and after reading. No ROM ownership, ACL, or mode
   is changed, and the service does not obtain a writable source handle.
3. Namespace membership is verified by the authenticated broker under the
   owner's existing rights. The service independently validates descriptor
   identity and bytes; it must not pretend that hashing a retained descriptor
   proves the current pathname still names that file. Before publication and
   each eligibility/export decision, require the broker to reopen/revalidate
   the original hierarchy, exact members and descriptors, and require fresh
   service digest verification. An observed moved/replaced/changed source blocks
   even when an old open descriptor still reads the former content.
   These checks do not atomically exclude source-owner mutation after the last
   observation. This remains a production feasibility blocker. Before GO,
   demonstrate OS-enforced source stability covering publication and continuing
   eligibility without changing original permissions. A protected immutable
   snapshot is an alternative only after separate approval of its authority and
   semantics: it preserves captured bytes but does not prove originals remain
   unchanged. No snapshot or relaxation of continuing eligibility is authorized.
4. Broker/client or host restart loses source access authority. Reacquire
   owner-scoped access and revalidate against the original pins; never persist
   transferable source privileges or silently accept equivalent replacement
   files. Reboot/timing discontinuity blocks old destructive authority.
5. Export verified bytes through a service-produced anonymous pipe, not writable
   files or directory descriptors. Frame the ordered manifest/bundle members,
   sizes and digests; the receiver verifies completeness and hashes. It receives
   neither the staging namespace nor permission to mutate it. Broken pipes or
   incomplete exports are not successful delivery. No export replaces the
   source-revalidation or immutable-grant checks.
6. A future Android transport must independently authorize target/app identity,
   destination isolation, capacity, transfer, full readback, publication, and
   destructive cleanup, including device-side concurrent actors and crashes.
   `/sdcard/ArgusQualification` remains only the documented destination scope,
   not proof of exclusive namespace authority. Host export success is
   `HOST_PREPARATION_ONLY`, never Android admission or product qualification.

## 5. Timing precision and separate sleep decision

1. The CI defect occurs when an exact integer deadline is converted to float
   seconds and back: `17082823080000` becomes `17082823079999`, leaving one
   nanosecond of apparent authority. Production also acquired float seconds.
   The correction uses `time.monotonic_ns()` end to end, including private test
   clocks. Existing schema 1 integer values remain untouched.
2. CPython uses `mach_absolute_time()` on macOS; both monotonic APIs exclude
   system sleep. Linux's `CLOCK_MONOTONIC` also excludes suspend. Darwin's
   `CLOCK_MONOTONIC`, `mach_continuous_time()` and `CLOCK_MONOTONIC_RAW` include
   sleep; `CLOCK_MONOTONIC_RAW_APPROX` adds cached/stale observations and is not
   suitable for exact expiry boundaries. Thread `time.sleep()` is not suspend.
3. Existing UTC grant checks remain required, but a schema 1 uptime budget does
   not consume host-sleep duration. This is a residual authority limitation,
   especially if wall time changes. No physical sleep/wake test has been run;
   source research and synthetic clock-domain characterization are distinct
   from host qualification.
4. Proposed follow-up, requiring separate approval: introduce timing schema 2
   with an explicit sleep-inclusive platform clock identifier, integer readings,
   boot binding, and a fixed original continuous-clock deadline. Use exact
   `mach_continuous_time()` conversion on macOS and `CLOCK_BOOTTIME` on Linux;
   unsupported clocks block. Retain schema 1 records unchanged and inspectable;
   do not convert their start/deadline domain, resume them as schema 2, or renew
   cleanup. The conservative production default would make old-domain retained
   sessions ineligible for destructive automatic recovery pending owner review.

## 6. Independent fixture-oracle contract

1. Review this contract separately from installation and staging authority.
   A private versioned oracle record must bind its stable reference and revision
   to exact complete member bytes (size/digest), bundle layout, descriptor graph,
   expected game identity and edition/revision, platform, representation,
   grouping, order, and companion dependencies. Bind the oracle record digest
   to the approved fixture manifest and acceptance rules.
2. Record independent provenance: source/catalog/reference revision, acquisition
   or verification method, verifier/tool version where relevant, date, reviewer,
   identity evidence, and limitations. Define a fixture-specific acceptance rule
   for resolving disc sets, regional variants, patched content, and conflicting
   references. Missing or conflicting identity evidence blocks the identity claim.
3. File names, headers, structural recognition, copied bytes, Argus output, and
   agreement with the owner manifest do not independently establish identity.
   `owner_approved_expectation_match` keeps its current meaning. No new oracle
   schema or genuine fixture claim is implemented by this correction.
4. Keep raw names/hashes and references owner-private. Shared evidence contains
   approved opaque references and provenance links only. Positive full-format
   acceptance still needs genuine independently validated owner fixtures for
   the mandatory representation set; generated bytes prove mechanics only.

## 7. Privileged proof procedure — proposed, not authorized or executed

### 7.1 Environment and artifact gate

1. Use a disposable owner-selected macOS VM, native arm64, matching the observed
   host version or an explicitly approved target version. Take a powered-off
   baseline snapshot. Disable host shared folders, clipboard, USB passthrough,
   cloud synchronization, personal accounts and network after preparation.
   No ROMs, ADB, Android devices, or ordinary Argus installation are present.
2. Prepare a separately reviewed native proof bundle at
   `/Volumes/ArgusIsolationProof` containing signed `ArgusProofBroker.app`,
   `argus-proof-service`, `argus-proof-actor`, `argus-proof-driver`, launchd plist,
   fixture/consent-case definitions, `SHA256SUMS`, and `proof-manifest.json`.
   The manifest enumerates exact file hashes, approved designated requirements,
   entitlements, VM version, account allocation, expected effects and case IDs.
   These artifacts DO NOT EXIST in this change. The commands below specify their
   required interface; they cannot be treated as a runnable or proven receipt.
   Building/reviewing the bundle and pinning its actual hashes precedes approval
   to install it. No missing artifact is replaced with a stub that certifies GO.
   Pin the manifest and bootstrap-driver digests in out-of-band owner approval;
   a hash list supplied alongside an untrusted bundle is insufficient.
3. The native driver has separate inspect/install/test/report/retain/remove
   commands. Every command checks the manifest, host and proof-only scope;
   mutation subcommands fail unless explicitly approved. Its installation
   implementation must itself be reviewed before privileged execution.

### 7.2 Exact proposed invocation sequence

These commands are for the disposable VM after the second approval only. They
are an execution contract for the future reviewed proof bundle, not commands
to run from the development checkout.

```sh
sudo /usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap
sudo /usr/bin/install -o root -g wheel -m 0555 /Volumes/ArgusIsolationProof/argus-proof-driver /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver
sudo /usr/bin/install -o root -g wheel -m 0444 /Volumes/ArgusIsolationProof/proof-manifest.json /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json
/usr/bin/shasum -a 256 /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json
/usr/bin/codesign --verify --strict --verbose=4 /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver
proof_output=$(/usr/bin/mktemp -d /private/tmp/argus-proof.XXXXXXXX)
/Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver inspect --manifest /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json --output "$proof_output/preflight.json"
sudo /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver install --manifest /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json --receipt /private/var/db/argus-isolation-proof-evidence/install.json
/Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver verify-install --manifest /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json
/Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver test --manifest /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json --cases namespace,ipc,source,export,crash,recovery,cleanup --output "$proof_output/results"
/Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver report --results "$proof_output/results" --require-kernel-denials
sudo /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver retain-state --manifest /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json --output /private/var/db/argus-isolation-proof-evidence/retention.json
sudo /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver remove --manifest /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json --receipt /private/var/db/argus-isolation-proof-evidence/install.json --retain-unresolved
sudo /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/argus-proof-driver verify-removal --manifest /Library/PrivilegedHelperTools/ArgusIsolationProofBootstrap/proof-manifest.json --retention /private/var/db/argus-isolation-proof-evidence/retention.json
```

1. The medium must be read-only and protected against operator replacement.
   Reject existing bootstrap paths, symlinks, writable/ACL-granted ancestors,
   or an untrusted backing medium before these commands. System `install` is
   the only bootstrap operation. After installation, compare both printed hashes
   against out-of-band approved values, verify the exact approved signing
   requirement and root-only write ownership, and STOP on disagreement before
   executing the driver. No bundle executable runs privileged from the medium
   or user-writable storage. Verify and protect every dependency before activation.
2. Privileged outputs are restricted to the fixed root-owned `0700` evidence
   directory created exclusively by `install`. Files are `0600`, created using
   exclusive/no-follow descriptor-relative operations. Reject existing paths,
   unexpected links or owners. Only nonprivileged commands write to the private
   `mktemp` directory. Privileged commands reject `/private/tmp` output paths.

### 7.3 Filesystem and process effects

1. `install` creates only the dedicated account/group, root-owned proof bundle
   under `/Library/PrivilegedHelperTools/ArgusIsolationProof`, one root-owned
   launchd plist `/Library/LaunchDaemons/com.argusromtoolkit.isolation-proof.plist`,
   the root-owned parent/fixed staging anchor from section 2, dedicated consent
   key enrollment/public-key pin, and root-owned `0700` evidence directory and
   receipts. The protected bootstrap is installation-owned too. It rejects
   existing names/paths or writable ancestors;
   it never adopts or recursively changes an existing installation.
2. Launchd starts the service directly under the recorded non-login UID/GID,
   with an empty supplementary-group set and a clean fixed environment. The
   receipt records actual credentials, endpoint identity, loaded dependencies,
   ACLs, owners, ancestor identities and process lifecycle. The operator has no
   service-account credential or writable descriptor to protected storage.
3. Tests generate neutral byte fixtures in a VM-local owner-private directory
   and use the signed broker's real owner-consent flow. A separate concurrent
   actor runs under exactly the broker/operator UID. The actor uses raw syscalls
   and malicious IPC without the trusted driver's consent privileges.
4. At synchronized barriers before/during/after publication and cleanup, attempt
   `renameat`, rename-swap, `linkat`, symlink insertion, directory/sidecar
   replacement, unlink/rmdir, moving destination into the writable source root,
   replacing ancestors, and nonprivileged mount substitution where available.
   Record errno and syscall arguments with synthetic names. Expected namespace
   denials are `EACCES`/`EPERM`; `EXDEV`/unsupported calls are not proof of access
   isolation. Source/final/generation identities and digests must remain intact.
5. IPC cases cover unsigned/wrong-revision clients, copied legitimate broker
   without owner consent, forged Python grants, same-UID client, wrong session,
   stale challenge, duplicate/reordered sequence, expired operation, unauthorized
   cleanup, path injection and cross-session deletion. No rejected request may
   create state, mutate payloads, or delete a target. A read-only authorized
   status query may inspect its own already-existing session.
6. Source cases use `0700` roots and `0600` files unchanged before/after tests;
   deny writable or special descriptors, replace source entries, mutate bytes,
   revoke scoped access and kill the broker. Continued export/eligibility must
   block until approved original sources are freshly revalidated. Never broaden
   source permissions as a test workaround. Include mutation after the last
   source check but before publication/export. Until a source-stability mechanism
   passes that case, full production proof remains NO-GO even if destination
   namespace tests pass. Bounded rechecks alone cannot certify this requirement.
7. Crash cases terminate client and service separately before intent, after
   intent, after rename, before eligibility, and during cleanup. Restart must
   preserve the kernel boundary, generations and uncertainty, reject stale
   connection authority, and retain original deadlines. Reboot blocks old timing
   authority. Future schema 2 sleep tests must actually suspend/wake the VM and
   compare continuous/uptime measurements; they are not part of the precision fix.
8. Cleanup runs only for explicitly approved synthetic sessions. Include foreign
   replacement attempts, expired grants, interrupted removal, malformed state,
   retained sidecars and failed state fsync. No foreign/ambiguous entry is removed;
   failed proof yields retained resources and NO-GO, not an automatically cleaned
   fixture or a retry that conceals the failure.

### 7.4 Teardown, rollback and retained state

1. Stop new admissions, invalidate connections, stop/unregister only the proof
   launchd job, and seal proof receipts before removal. `retain-state` inventories
   and hashes unresolved trees without changing their ownership or deleting them.
2. `remove` verifies every installation-owned path against the original receipt.
   Remove only matching binaries/plist and proven clean synthetic session trees.
   Never run recursive deletion against the anchor. Unexpected contents, active
   sessions, or unresolved ownership retain the anchor, receipt and account; do
   not recycle their UID or orphan their files under another account identity.
3. `verify-removal` confirms the endpoint is gone, no service process remains,
   source fixtures are intact, and retained paths match the retention receipt.
   Before rollback, power off and preserve a complete immutable VM checkpoint
   containing unresolved trees, root-private receipts, account/key state and
   virtual disks in an owner-approved external retention location. Hash and
   independently verify that checkpoint and its metadata; sanitized reports
   alone are insufficient. Restore the baseline only into a separate VM copy
   or branch leaving the retained checkpoint intact. If preservation cannot be
   verified, do not restore/discard the failed VM. Bootstrap/key removal must
   preserve retained evidence and its inspectability. Disposal needs separate
   owner approval.
4. Any required owner consent, installation proof, adversarial case, or safe
   teardown that cannot be demonstrated makes the proof NO-GO. Passing namespace
   cases alone does not certify authenticated IPC, Android isolation, game
   identity, or production readiness.

## 8. Remaining decisions and gates

1. Approve the prospective service/broker/interface architecture, or retain the
   production blocker. No production adapter or privileged proof is implemented.
2. Select the disposable VM and approve construction/review of the native proof
   bundle. Supply/approve its signing identity, designated requirements,
   dedicated consent-key enrollment/user-presence policy, public-key pin, and exact
   revision pins. Review actual artifact hashes and installation effects before
   separately authorizing the commands in section 7.
3. Decide whether to adopt the separately versioned sleep-inclusive timing
   contract and conservative schema 1 recovery policy. This precision correction
   does not make that choice or silently reinterpret historical evidence.
4. Review the independent oracle contract and provide genuine private provenance
   under separate fixture authorization. Keep Android transport/storage and
   cleanup proof in their own authorized work. Separately resolve source stability
   without weakening continuing eligibility: approve a concrete OS mechanism or
   explicitly review different snapshot semantics.
5. Production integration requires successful complete OS/IPC/crash adversarial
   proof, independent review, and a new implementation approval. Privileged
   execution, ROM staging, ADB/device access and publication remain unauthorized.

## 9. Primary-source references

1. [Python monotonic clock and integer API](https://docs.python.org/3.14/library/time.html#time.monotonic).
2. [CPython shared monotonic implementation](https://github.com/python/cpython/blob/3.14/Python/pytime.c).
3. [Apple clock contracts](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.3)
   and [clock implementation](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.c).
4. [Apple continuous-time declaration](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/mach_time.h).
5. [Python Linux suspend-inclusive clock](https://docs.python.org/3.14/library/time.html#time.CLOCK_BOOTTIME).
6. [Apple XPC peer code requirement](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)).
7. [Apple audit-token code lookup implementation](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/SecCode.cpp).
8. [Apple sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?language=objc).
9. [Apple secure helper guidance](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/AccessControl.html).
10. [Apple rename permission contract](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/rename.2),
    [link contract](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/link.2),
    and [launchd configuration](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5).
