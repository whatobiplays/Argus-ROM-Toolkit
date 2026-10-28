# Issue 24 production staging implementation ledger

**Historical status checkpoint (2026-10-26):** This ledger records incremental host work
that began on 2026-10-25. Native contract, store, security, timing, service,
broker-session, export-verification, and fail-closed proof components are
implemented and have bounded host-test results. The authenticated end-to-end
XPC/owner transport is incomplete: Python does not open and drive the native
session or consume a versioned owner export-evidence contract. Public
production staging remains `BLOCKED_UNSUPPORTED_EXCLUSIVITY`. Sleep-inclusive
timing schema 2 remains an unapproved policy choice even where bounded native
timing code exists; manifest schema 2 is a separate contract.

**Current code-level status (2026-10-27):** The owner-side client calls
`OwnerPrivateLifecycleJournal.dispatch` before native transport dispatch and
accepts ACK only after validating the complete service completion, including
the native `members_sha256` contract, against the attempt and authenticated
peer. Receipt-only recovery never resends an uncertain export. The native
service persists the broker completion in its fixed protected journal and
serves record/query messages only on the peer-authenticated XPC connection.
Host tests exercise ordered hello/admit/stage/export dispatch, document and
open-descriptor attachments, private durable delivery, receipt binding, and
recovery through synthetic authority seams. The source also exports
`create_production_owner_export_preparation`, which creates a lazy preparation
bound to the exact grant and expected attempt manifest and authorization
digests. `_stage_production_export` validates those bindings and the supplied
manifest and authorization bytes before native preparation, passes the same
verified installation identity into the factory, and checks the returned
attempt before dispatch. The helper does not establish
installed production authority or qualification. Required installed identities,
owner-key enrollment, live consent, and kernel-enforced isolation remain
unavailable; the public runner continues to return
`BLOCKED_UNSUPPORTED_EXCLUSIVITY` before side effects.

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

## 2. Qualification tiers at the 2026-10-25 baseline

| Tier | Meaning | Result at checkpoint |
|---|---|---|
| A | Deterministic synthetic correctness | Bounded host suites passed for implemented components; end-to-end production path remains incomplete |
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

## 4. Execution sequence checkpoint (first recorded 2026-10-25; updated 2026-10-27)

1. Preservation, capacity preflight and bounded native build setup: VERIFIED; review pending.
2. Versioned snapshot/oracle authority, canonical schemas and tests: PARTIAL; native manifest schema 2 and oracle/evidence schema 1 host components are implemented, with closeout pending.
3. Native namespace and authenticated broker/service interface: PARTIAL; service, broker-session, and owner-adapter source are implemented and exercised by host seams; installed signed-peer qualification is incomplete.
4. Immutable snapshot acquisition, verification and publication: PARTIAL; bounded AQStore components are host-tested; installed production qualification is not performed.
5. Durable recovery, export and cleanup: PARTIAL; native store recovery, broker export verification, and durable receipt components are host-tested; owner integration and production qualification are incomplete.
6. Sleep-inclusive timing schema 2: IMPLEMENTED AS A BOUNDED NATIVE CHECKPOINT; POLICY NOT APPROVED. It is distinct from manifest schema 2 and cannot redefine schema-1 deadlines or immutable limits.
7. Native/Python integration and production admission: INCOMPLETE for production. A source-level factory assembles the dispatch helper from a probed installation, but it does not establish installed owner authority or production qualification; installed XPC qualification has not run.
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
| Corruption, companion, capacity, interrupted-transfer tests | Baseline host suite | New contract/native regressions and fault qualification | UNVERIFIED |

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

### 7.2 Contract and JSON native slice

The native `AQValidateSnapshotContract` boundary now implements manifest schema
2 plus oracle/evidence schema 1 validation. It uses the bounded `AQJSON` byte
parser for every document, enforces exact object fields and integer spellings,
checks authorization and revision pins, walks complete acyclic fixture and
evidence graphs, rejects unused records and back-references, and validates all
claims against manifest rules. It exposes no external reference-verifier API;
genuine records remain `pinned_unverified`. Malformed input and internal
exceptions produce fixed sanitized errors without a partial assessment.

The contract-only build mode compiles `AQJSON`, `AQContract`, and the shared
golden-vector suite without requiring the unfinished store, broker, or service
slices. It retains the macOS ARM64 target and 2 GiB disk-reserve admission.

Verification on the host:

1. `bash scripts/build_fixture_staging_native.sh contract` exited 0 after
   capacity admission and reported `contract tests: 123 checks, 0 failures`.
2. `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=scripts python3 -m unittest
   scripts.android_qualification.test_fixture_oracle -v` exited 0 with 34 tests
   passing.
3. Strict `clang` syntax checks passed for `AQJSON.m`, `AQContract.m`, and
   `contract_tests.m` with ARC, ARM64, macOS 12.0, `-Wall -Wextra -Werror`.
   Clang static analysis also completed without diagnostics for `AQJSON.m` and
   `AQContract.m`.
4. Instrumented line coverage was 96.39% for `AQJSON.m` and 86.38% for
   `AQContract.m`; remaining misses are defensive validation branches.

These results establish deterministic host contract behavior only. They do not
establish authenticated authorization, production key enrollment, kernel
isolation, genuine corpus access, owner approval, or physical-device
qualification.

### 7.3 Native service, broker, session, and proof checkpoint

Added a service-owned session boundary over the completed `AQSecurity`,
`AQContract`, and `AQStore` interfaces. The boundary binds a service-generated
connection, fresh broker nonce and service challenge, grant, epoch,
installation, boot identity, input pins, operation allowlist, reserves, and
immutable continuous-clock deadline. Owner signature verification is separate
from oracle provenance. Genuine evidence without an independently installed
reference provider is refused. Requests compute their canonical digest in the
service, include descriptor identities, and delegate at-most-once sequencing,
publication, export, recovery, and uncertain cleanup to `AQStore`.

The service executable loads only the fixed installed policy and protected
staging root, validates every XPC message with `AQValidatePeerMessage`, and
revokes a session when its connection is lost. The broker executable provides
bounded self-check, exact owner-consent signing, and authenticated relay paths.
Its streaming export verifier checks header bounds, member digests, trailer, and
terminal transcript digest without buffering complete payloads.

The proof driver and actor compile as fail-closed development checkpoints. They
do not install a helper, mutate the host, enroll a key, or claim that kernel
isolation exists. Privileged proof mutation remains unavailable until a signed,
hash-pinned bundle and disposable VM are separately authorized.

Host checks completed before the native build-capacity gate changed:

1. Strict ARC/ARM64/macOS 12.0 `-Wall -Wextra -Werror` syntax checks passed for
   `service/AQServiceProtocol.m`, `service/main.m`,
   `broker/AQBrokerProtocol.m`, `broker/main.m`, proof entry points, and the
   focused service/broker tests.
2. `bash -n scripts/build_fixture_staging_native.sh` exited 0.
3. `plutil -lint broker/Info.plist` reported `OK`.
4. Focused Python oracle and Issue 24 public-boundary tests completed 35 tests
   with no failures, including `destination=None` fail-closed coverage.
5. Linked native execution was not run: the checked build commands returned
   `BUILD_CAPACITY_INSUFFICIENT` after available free space fell below the
   mandatory 2 GiB reserve. No unrelated data was deleted and the guard was not
   bypassed.

The Python facade remains unchanged and `destination=None` cannot enter a
synthetic fallback. Public production staging and cleanup remain
`BLOCKED_UNSUPPORTED_EXCLUSIVITY` until installation verification and the
external proof gates succeed. No signed installation, owner enrollment, real
corpus, XPC two-process proof, namespace denial, reboot/crash proof, or product
qualification was performed.

### 7.4 Bounded native checkpoint verification

The linked native targets were subsequently built and executed after build
capacity was available. A malformed `documents` field on an XPC message is now
rejected and revokes its connection instead of being treated as absent. The
broker requires the export header bytes to equal their canonical JSON spelling,
and a verified export sends payload bytes on standard output while its
transcript result and completion record go to standard error. These changes
keep export data separate from broker diagnostics.

Focused host results on 2026-10-25:

1. `bash scripts/build_fixture_staging_native.sh test` exited 0; contract,
   store, security, timing, service, broker, and proof targets all ran. Contract
   reported 123 checks, security reported 171 checks, and store, service, and
   broker reported 0 failures; the timing executable exited 0.
2. Separate contract and security modes exited 0 with 123 checks and 171
   checks respectively; store mode exited 0 with 0 failures.
3. `argus-proof-driver --self-check` and `argus-proof-actor --self-check` each
   exited 2 as required. They reported
   `PROOF_BUNDLE_AND_OWNER_APPROVAL_UNAVAILABLE` and
   `PROOF_NAMESPACE_NOT_INSTALLED`, respectively.
4. The Python oracle and Issue 24 public-boundary suites exited 0 with 35 tests
   passing.

These checks establish compilation and deterministic host behavior only. The
production blockers listed above remain unresolved, including installation
signing and hash pins, owner-key enrollment, independent genuine-evidence
attestation, kernel namespace isolation, two-process XPC and crash recovery
proofs, real owner-authorized corpus verification, and physical-device
qualification. Public production staging and cleanup remain
`BLOCKED_UNSUPPORTED_EXCLUSIVITY`.

### 7.5 Python admission and native CI boundary

Added `_fixture_staging_native.py` as the Python boundary for installed native
results. It reads only fixed installed policy, broker, and service locations,
requires a root-owned non-writable executable and parent ancestry, and invokes only bounded prompt-free
`--self-check` operations. Public `stage_fixtures(destination=None)` consults
that selector and returns `BLOCKED_UNSUPPORTED_EXCLUSIVITY` when the
installation or its proof state is unavailable. Other destination values keep
the existing fail-closed behavior. The selector never constructs a filesystem
or synthetic adapter.

`authorize_fixture_staging` now selects the schema-specific admission path.
Schema 1 retains the legacy strict manifest parser and its
`owner_approved_expectation_match` behavior. Schema 2 securely loads the
caller-supplied oracle and evidence files, calls
`fixture_oracle.validate_snapshot_contract` with the authorization's manifest,
plan, and rules pins, and attaches `synthetic_only` or `pinned_unverified` to
the fixture expectations. Genuine records cannot be promoted from Python: no
caller callback or boolean is accepted. The native contract and service also
expose no reference-verifier block or Boolean. No authenticated independent
native provider is installed, so `verified_independent_reference` cannot be
produced and genuine owner-private admission fails closed. These tiers remain
separate from the separately loaded owner approval; validation does not make
the snapshot authoritative, and `byte_integrity` remains unchecked until
staging readback.

The native-result boundary also cross-checks a canonical broker/service
envelope against the Python contract, grant fixture order, required, selected,
and mandatory coverage identifiers, source authority, and support list. Native
owner consent remains separate from
`owner_approval`, which must remain `not_checked`. Document validation likewise
leaves `byte_integrity` as `not_checked`.

Owner-side native readiness now asks the fixed root-owned broker to relay a
non-authoritative readiness request to the installed service. The broker and
service retain their authenticated XPC peer checks, and the service retains its
configured-UID check before returning readiness facts. The owner process no
longer executes the service directly. Host tests validate the request and
routing shape but are not signed-process evidence.

Added `just build-fixture-staging-native` and
`just test-fixture-staging-native` with a `macos-15` GitHub Actions job that
asserts an ARM64 host, builds production native surfaces, proves their object
symbols exclude test seams, then builds and runs deterministic nonprivileged
tests. The job records privileged installation, signing, owner enrollment, and
VM proof as skipped. The existing archive inventory test includes the live
Issue #24 boundary and CI surfaces.

Bounded validation on the host:

1. `just test-android-qualification` exited 0: 817 tests passed with two skips.
2. The focused Python oracle, native-boundary, authorization, Issue 24, and
repository-check suites exited 0: 131 tests passed.
3. `just test-fixture-staging-native` exited 0; contract reported 118 checks,
   security 171 checks, and store, service, and broker zero failures. The
   timing suite was invoked and exited 0.
4. Archive, naming, qualification-record, `bash -n`, ShellCheck, YAML parsing,
   `just --show`, Python compilation, and `git diff --check` completed without
   errors. `actionlint` and `yamllint` are not installed locally.

The CI job has not run in GitHub Actions. No signed or hash-pinned helper was
installed, no owner key or consent was enrolled, no VM or kernel-isolation
proof ran, no production staging root was opened, and no genuine corpus was
used. A durable Python-driven hello/consent/admission/staging session remains
unimplemented, so production staging and cleanup remain blocked.

### 7.6 Independent review corrections

Journal replay now treats every first event of a previously unseen session as
an independent `admitted` record, regardless of its global journal ordinal.
Request-digest uniqueness is scoped to a session. Recovered sessions remain
`blocked_retained`, while a new unused session identity may be admitted after
restart without replaying an old request. The store suite stages two sessions,
reopens the same journal, verifies both recovered generations, and admits and
stages a third session.

Contract regressions now require a case-folded path alias to fail after all
manifest, oracle, evidence, and authorization pins have been refreshed. A
separate regression changes only the manifest fixture identity so that the
manifest-to-oracle binding is the first and only conflicting check. Removing
either guard makes its regression fail. The golden vectors are unchanged.

The Python native-result validator now compares the response's
`mandatory_fixture_ids` with the exact plan coverage retained by the issued
grant. A focused test replaces that list with an empty list and verifies the
response is rejected as `EXPECTATION_UNVERIFIED`.

The production and test native configurations are compiled separately. The
production `build` target compiles only production sources and reports
`NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT` after inspecting every compiled object;
a separate `nm -gU` check of the four final linked production binaries also
reports no test symbols. The `test` target invokes focused contract, store,
security, timing, service, broker, and proof configurations without defining
both testing macros globally. CI runs the production build before the
deterministic test target.

The Python installed-executable check now walks the executable and all of its
parents with `lstat`. The executable and each directory must be root-owned, must
not grant group or world write access, and must not resolve through a symbolic
link. Focused subtests reject a group-writable intermediate directory and a
symlink in the fixed parent ancestry. An additional subtest rejects a
group-writable executable file, keeping the same fail-closed error path.

The native service now records a hello request's broker nonce before generating
its session and challenge tokens. If token generation or later setup fails,
that nonce remains consumed and a retry is rejected as `REPLAY_REJECTED`. A
deterministic native regression forces challenge-token generation to fail, then
retries with a new request identifier and the old nonce.

The schema support classification regression now exercises a contract containing
both `synthetic_only` and `pinned_unverified` fixture records. The aggregate
classification is `pinned_unverified`; the lower synthetic tier cannot mask the
pinned declaration.

Final host evidence at this checkpoint: the focused Python oracle, native
boundary, authorization, Issue 24 boundary, and repository-check suites passed
131 tests; the full Android qualification suite passed 817 tests with two
skips. The complete native test target exited 0 with contract 118 checks and
security 171 checks, with zero store, service, or broker failures. The strict
`-Wnullable-to-nonnull-conversion` build flag is enabled in the native harness.
The production build reported `NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT`, Clang
static analysis reported zero diagnostics, and the ASan/UBSan target exited 0.
Archive, naming, qualification-record, ShellCheck, `bash -n`, YAML parsing,
recipe lookup, Python AST parsing, and `git diff --check` completed without
errors. `yamllint` and `actionlint` are not installed. These are host test
results only.

The native contract and service expose no reference-verifier callback, block,
or Boolean. Native genuine records therefore remain `pinned_unverified`, and
the service refuses admission that requires the reserved provider tier. The
Python genuine records also remain `pinned_unverified`; a caller callable is
rejected at the validator and grant-issuer boundaries, and a native response
that asserts independent verification is rejected when the Python contract
does not bind that tier. The native validator remains authoritative for native
admission while the Python layer cross-checks the canonical result.

No signed broker/service installation was available for this checkpoint: the
fixed policy and both installed executables were absent, so the exact readiness
blocker is `NATIVE_INSTALLATION_NOT_PRESENT`. Host tests are not signed-process
evidence, no owner enrollment or VM proof ran, no production staging root was
opened, and production staging and cleanup remain blocked.

The final unmodified local `cubic review --json` exited 1 with two findings. Its
repository context remained unavailable because the configured worktree has no
GitHub origin remote.

1. **P1, intentional behavior** —
   `native/fixture-staging/broker/main.m:183`, "Exported bytes are written
   before the complete frame is verified": "The sink writes each payload chunk
   to standard output while the verifier is still checking later members, the
   trailer, and the terminal digest. If a later check fails, the caller has
   already received an unverified partial export and may act on it despite the
   broker reporting failure." The relay streams large payloads to standard
   output and emits the separate `VERIFIED_RECEIVER_COMPLETION` record only
   after the verifier accepts the entire transfer. A caller must require that
   completion record and a successful process exit before treating received
   bytes as a verified export. No production staging/export consumer is enabled
   while the durable native session remains unimplemented.
2. **P2, intentional behavior** —
   `scripts/android_qualification/_fixture_staging_orchestration.py:97`,
   "Installation probe cannot enable production staging": "The `destination is
   None` branch probes the installation, but both outcomes return
   `BLOCKED_UNSUPPORTED_EXCLUSIVITY`; even when `operation_enabled` is true, the
   branch returns the blocker unconditionally. As a result, the probe and
   readiness work cannot affect public staging behavior, and this path adds dead
   complexity until the durable native session is implemented." The probe is
   deliberately non-enabling: it records readiness while the durable native
   session and the external isolation, enrollment, and installation gates are
   unavailable. Keeping the public path blocked in both outcomes prevents a
   readiness response from being mistaken for production admission.

These findings are review records, not qualification evidence or resolved
acceptance gates.

### Verified-spool broker correction (2026-10-25)

The earlier P1 review record describes the superseded streaming behavior. The
current broker verifies the complete export before writing payload bytes to
standard output:

1. The exact incoming frame is written to a private `0600`, single-link,
   exclusive temporary file. Spool creation and pre-delivery validation both
   inspect the live descriptor's mode, link count, owner, and `FD_CLOEXEC`
   flag. Raw parser input and canonical output are each capped at 64 KiB; when
   both coexist, their documented byte-buffer ceiling is 128 KiB. Decoded
   Foundation object storage is proportional to the returned document.
2. Once the canonical header is available, frame capacity is admitted against
   the spool filesystem with a 2 GiB reserve. Integer overflow, insufficient
   capacity, and spool write failure close and unlink the spool.
3. The frame's session, generation, canonical manifest digest, and ordered
   member path, size, and digest list are compared with the trusted request's
   `export_manifest` and the request's session and expected generation.
4. Member and terminal digests must pass, the complete frame must end exactly
   at EOF, and trailing bytes are rejected immediately.
5. Only after those checks does the verifier stream payload member bytes to its
   sink. A nil sink fails without a completion record. The broker then emits a
   `VERIFIED_RECEIVER_COMPLETION` record bound to `request_id`, session,
   generation, manifest digest, and member count on standard error. Relay
   failures are diagnostics on standard error, leaving standard output free of
   binary payload unless the verified emission begins.
6. Revocation cannot recall bytes already emitted by a successful export.
   Consumers must require the bound completion record and successful broker
   exit; a crash or output failure before completion leaves all delivered bytes
   untrusted.

Regression coverage includes deferred delivery until `finish`, nil-sink
rejection after a valid frame, live spool metadata inspection and permission,
link-count, and close-on-exec mutations, the exact 2 GiB reserve boundary,
zero sink bytes for member and terminal digest failures, wrong
session/generation/manifest rejection, member-path mismatch rejection,
trailing bytes after a complete frame, ordered multi-member delivery, and
exact request-bound completion data.
No production export consumer is enabled, and production staging remains
blocked.

Checkpoint verification on 2026-10-25:

1. `bash scripts/build_fixture_staging_native.sh broker` exited 0 with
   `broker tests: 0 failure(s)`.
2. `bash scripts/build_fixture_staging_native.sh test` exited 0. It reported
   `contract tests: 118 checks, 0 failures`, `security tests: 171 checks,
   0 failures`, and zero failures for store, service, and broker. Production
   symbol checks reported `NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT` for both the
   service and broker targets.
3. `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest` over
   `test_fixture_staging_native` and `test_fixture_oracle` exited 0: 47 tests
   passed.
4. `bash scripts/build_fixture_staging_native.sh build` exited 0 with
   `NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT`.
5. `bash scripts/build_fixture_staging_native.sh analyze` exited 0 with no
   Clang static-analysis diagnostics.
6. `bash scripts/build_fixture_staging_native.sh sanitize` exited 0. Contract
   checks were 118/118, security checks were 171/171, and store, service, and
   broker suites each reported zero failures under ASan/UBSan.
7. `just test-android-qualification` exited 0: 818 tests passed with two
   skips.
8. `bash -n`, ShellCheck, Ruby YAML parsing of every tracked YAML file, and
   `git diff --check` all exited 0.

The local Cubic JSON review is recorded at
`.build/fixture-staging/cubic-review-before-ledger.json`. The review is not
clean and reported three P1 findings:

1. `native/fixture-staging/broker/AQBrokerProtocol.m:533`, "Sink receives data
   backed by a reused stack buffer": a sink that retains the no-copy `NSData`
   can receive bytes overwritten by the next read or invalid after return.
2. `native/fixture-staging/broker/main.m:225`, "Short writes are treated as
   complete payload delivery": a short stdout write is not retried, so the
   broker can emit a truncated payload and then report failure.
3. `native/fixture-staging/core/AQStore.m:1`, "Store implementation combines
   too many responsibilities": the 1,971-line module mixes manifest,
   session, journal, filesystem, recovery, and export concerns. Splitting it is
   an architecture change outside this bounded correction and was not
   implemented. The other two findings were also left for a separately
   authorized broker correction so this checkpoint would not expand scope.

Cubic reported `repository_context.status=unavailable` with reason "no GitHub
origin remote". The shell wrapper's exit-code capture failed because zsh
treats `status` as a read-only variable; the valid JSON output above is the
recorded review result, and this checkpoint does not claim a clean Cubic run.

None of these host results authorizes production staging. Production
installation and signing, authenticated signed-process exchange, disposable-VM
isolation proof, genuine independently approved corpus delivery, and a durable
production export consumer remain blocked.

### 7.7 Broker delivery and output-write P1 corrections (2026-10-25)

The two broker-local P1 findings recorded in Section 7.6 were corrected without
changing the verified-spool architecture:

1. `AQBrokerExportVerifier` now copies each completed 64 KiB member read into
   independently owned immutable `NSData` before invoking the sink. The sink
   contract returns `BOOL`; delivery is synchronous, the verifier waits for
   each callback, and returning `NO` aborts delivery, discards the spool, and
   leaves `completion` nil.
2. The broker stdout path now uses `AQBrokerWriteAll`. The helper retries
   partial writes and `EINTR`, advances by the number of bytes accepted, and
   fails on a zero-byte write, another POSIX error, or an impossible byte
   count. `VERIFIED_RECEIVER_COMPLETION` is not printed unless every verified
   payload byte has been accepted.
3. Broker regressions added `TestDeliveredChunksRemainOwnedAcrossReuse`,
   `TestNoCopyStorageReuseCorruptsRetainedData`,
   `TestSinkFailurePreventsCompletion`, and `TestCompleteWriteHelper`. The
   complete-write test covers partial writes, `EINTR`, zero-byte writes,
   `EPIPE`, invalid overrun, empty input, stale-error clearing, and a nil
   operation.
4. `native/fixture-staging/core/AQStore.m` was not changed. Its remaining
   architecture finding remains outside this bounded broker correction.

Fresh results:

1. `bash scripts/build_fixture_staging_native.sh broker` exited 0:
   `broker tests: 0 failure(s)`.
2. `bash scripts/build_fixture_staging_native.sh test` exited 0. Contract
   reported 118 checks with 0 failures, security reported 171 checks with 0
   failures, and store, service, and broker each reported 0 failures.
3. Focused Python native and oracle tests exited 0: 47 tests passed.
4. `just test-android-qualification` exited 0: unittest ran 818 tests and
   reported `OK (skipped=2)`.
5. `bash scripts/build_fixture_staging_native.sh build` exited 0 and reported
   `NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT`.
6. `bash scripts/build_fixture_staging_native.sh analyze` exited 0 without
   Clang static-analysis diagnostics. `bash
   scripts/build_fixture_staging_native.sh sanitize` exited 0; contract passed
   118/118 checks, security passed 171/171 checks, and store, service, and
   broker reported zero failures under ASan/UBSan.
7. A completed `cubic review --json` run over the implementation, before the
   proof-only documentation edits, exited 1 because one non-blocking P2
   remained: `native/fixture-staging/core/AQStore.m:1`, "Store implementation
   concentrates too many security-sensitive responsibilities". That run
   reported zero P1 findings. A final documentation-only rerun was interrupted
   at the bounded checkpoint; `.build/fixture-staging/cubic-review-current.json`
   records `Review interrupted` and is not a clean review. Cubic again reported
   `repository_context.status=unavailable` because the checkout has no GitHub
   origin remote.

These results clear the two broker-local review findings and establish host
behavior only. Production installation and signing, authenticated
signed-process exchange, disposable-VM isolation proof, genuine independently
approved corpus delivery, a durable production export consumer, and physical
device acceptance remain blocked.

### 7.8 Trust and recovery boundary corrections (2026-10-25)

Four review findings in the current fixture-staging trust/recovery slice were
addressed without enabling production staging or cleanup:

1. Public cleanup now records a durable, non-authoritative
   `<session-id>.cleanup-blocked.json` follow-up when a valid sealed grant and
   exact production destination establish that exclusivity is unavailable.
   This works when no ownership generation has ever existed. The record binds
   the session, destination path/device/inode, candidate resource names,
   operation and authorization digests, original operation deadline,
   cleanup-authorization deadline, cleanup-reserve start, and disk reserves. It
   states the owner-inspection retention obligation, cannot be promoted to
   ownership, and leaves fixture content untouched. Public cleanup still
   returns `BLOCKED_UNSUPPORTED_EXCLUSIVITY` and never calls destructive
   cleanup.
2. Python's aggregate support classifier now treats a caller-built
   `verified_independent_reference` declaration as `pinned_unverified` because
   `SnapshotContract` has no sealed authenticated verifier result. The native
   envelope validator likewise returns `owner_consent="unverified"` from raw
   caller-supplied bytes, even when those bytes contain the literal
   `verified_by_installed_owner_key` value.
3. AQStore cleanup now captures the device/inode identity of every verified
   file and directory during full preflight. Immediately before each
   descriptor-relative no-follow unlink/rmdir, it repeats `fstatat`; files are
   reopened and rehashed against the pinned size and SHA-256. A same-user
   replacement injected after preflight is retained and recorded as
   `blocked_retained` with `effect_state=retained`. The regression replaces
   `fixture/game.bin` at the cleanup boundary and verifies the replacement bytes
   survive.
4. The export writer's root-blocked, revocation, and deadline reads now use
   store synchronization, and the journal root-blocked state uses one lock
   discipline. A deterministic interleaving test blocks the export thread at
   `before_export_member`, revokes the session, releases the writer, and verifies
   the session remains revoked and retained.

Focused verification in this checkpoint:

1. `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest` over
   `test_fixture_staging_native`, `test_fixture_staging_recovery`, and
   `test_fixture_staging_authorization` exited 0 after 85 tests.
2. `just test-android-qualification` exited 0: 820 tests ran and two were
   skipped.
3. `just test-fixture-staging-native` ran contract, store, security, and service
   suites with zero reported failures, including the two new store regressions.
   At that checkpoint, the overall command exited 1 before broker tests because the
   `native/fixture-staging/tests/broker_tests.m` defines
   `BrokerCreateForeignFile` and `BrokerReadFile` without using them under
   `-Werror,-Wunused-function`. Section 7.9 records the subsequent correction
   and passing command; this historical result is not a current blocker.
4. `bash scripts/build_fixture_staging_native.sh store` exited 0 with
   `store tests: 0 failure(s)`.

These corrections do not establish kernel-enforced namespace isolation,
signed-process transport authentication, owner-key enrollment, genuine corpus
verification, device behavior, or independent qualification. Official
production staging and cleanup remain blocked. The remaining AQStore module
size finding remains a separately owner-gated architecture decision.

### 7.9 Broker spool pathname regression recovery (2026-10-25)

The full native command exposed compiler warnings from two broker test helpers
that no longer had call sites after spool creation changed to unlink its
pathname immediately. The helpers were retained for their intended adversarial
checks rather than removed or marked unused:

1. `TestSpoolPathReplacementCannotAffectVerifiedBytes` creates a distinct
   inode at the former spool pathname, overwrites that replacement, and verifies
   successful delivery still reads the original verified descriptor bytes.
   Successful descriptor cleanup leaves the replacement file and its mutated
   bytes intact.
2. `TestSpoolDiscardRetainsForeignReplacement` forces live spool metadata
   rejection after creating a foreign replacement. Failed verification discards
   the anonymous descriptor only; the replacement remains readable and is never
   unlinked by broker cleanup.
3. The obsolete hard-link subcase in `TestSpoolMetadataRejectsMutation` was
   removed because it attempted to address the former pathname after unlinking,
   which necessarily failed with `ENOENT`. The same test still checks live
   descriptor regular-file type, mode `0600`, owner, zero link count,
   `FD_CLOEXEC`, and absent former pathname.

Fresh host results:

1. `bash scripts/build_fixture_staging_native.sh broker` exited 0 and reported
   `broker tests: 0 failure(s)`.
2. `just test-fixture-staging-native` exited 0. Contract reported 118 checks
   with 0 failures, security reported 171 checks with 0 failures, and store,
   service, and broker each reported 0 failures. Timing tests and both
   fail-closed proof executable checks also completed successfully.
3. `bash scripts/build_fixture_staging_native.sh build` exited 0 and reported
   `NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT`. Its first capacity observation
   reported 4,277,563,392 available bytes against a 2,147,483,648-byte reserve,
   so the capacity guard admitted the build.
4. `bash scripts/build_fixture_staging_native.sh sanitize` exited 0 under
   AddressSanitizer and UndefinedBehaviorSanitizer. Contract remained 118/118,
   security remained 171/171, and store, service, and broker each reported 0
   failures. The production-object symbol check again reported
   `NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT`.

The native test and warning blockers from this slice are resolved. These host
results remain Tier A deterministic evidence and do not remove broader
qualification blockers:

1. `NATIVE_INSTALLATION_NOT_PRESENT` blocks testing an installed signed service
   and broker at the fixed production paths.
2. `AWAITING_XPC_DEPENDENCY_PROOF` blocks claims of authenticated signed-process
   exchange and kernel-enforced namespace isolation.
3. No authenticated independent corpus provider is installed, so genuine
   records remain `pinned_unverified`.
4. Installed production owner/XPC authority and the qualified production export
   consumer remain incomplete. The source owner-session adapter, source factory
   helper, and versioned owner export-evidence validator exist and have host
   tests, but none establishes installed production authority or qualification.
5. Disposable-VM adversarial qualification and physical-device acceptance have
   not been performed.
6. The `AQStore` module-size P2 remains a separately owner-gated architecture
   decision and was not changed by this broker test correction.

### 7.10 Owner-side lifecycle journal slice (2026-10-27)

Added a private append-only Python lifecycle journal for the owner side of the
native session boundary. It records each attempt before dispatch, syncs the
record and containing directory, and chains canonical records with SHA-256.
Session owner, installed identities, authorization, consent, service boot,
session, original deadline, manifest, generation, and ordered member digests
remain immutable for an attempt. A new authenticated connection does not
continue that mutation: a new `hello` creates a new service session and cannot
be substituted for the original session binding. Recovery opens a fresh
authenticated transport only for a bounded, read-only receipt query carrying
the original attempt binding. It does not send `hello` or replay mutation.
Request identifiers and nonces cannot be reused. An interrupted attempt
becomes `UNKNOWN` with a durable recovery record and blocks a new attempt until
a matching durable native receipt resolves it. Corrupt journals fail closed
and create a durable `UNKNOWN` marker.

Focused Python regressions cover pre-dispatch durability and restart, unknown
replay refusal, reconnection binding and deadline preservation, nonce replay,
incomplete or non-durable receipt rejection, deadline expiry, journal
corruption, concurrent preparation and dispatch reservation, post-deadline
read-only reconciliation, production clock API boundaries, receipt size bounds,
and query-only reconnect binding. The journal validates receipt bindings and
completeness; it cannot create native authentication. The production entry
point remains
`BLOCKED_UNSUPPORTED_EXCLUSIVITY`, and this slice does not complete the missing
Python-to-native session transport or enable production admission. Those
integration and qualification gaps remain open.

### 7.11 Fail-closed cleanup and present source inventory (2026-10-27)

Public cleanup now returns `BLOCKED_UNSUPPORTED_EXCLUSIVITY` immediately when
production namespace admission fails. It does not inspect caller-supplied
grant, destination, session, or time values, and it does not read or mutate
destination state. Regressions verify unchanged staged data and denial with
unreadable caller inputs. Production authorization and isolation gates are
unchanged.

The active qualification inventory now classifies the two added lifecycle
journal paths and no longer treats eight absent continuation-only Python files
as active. Its archived classification prefix remains byte-for-byte unchanged.
The missing signed installed authority and Python-to-native authenticated XPC
session/export integration remain blockers; this journal does not authenticate
or dispatch a native operation.

### 7.12 Authenticated session and owner delivery adapter (2026-10-27)

This checkpoint supersedes earlier ledger statements that Python did not drive
the native session. `OwnerSessionExportClient` now validates the signed export
request and ordered hello/admit/stage/export workflow, persists ATTEMPT before
calling the installed broker adapter, and accepts ACK only after a matching
receipt returned on the authenticated native connection. Recovery performs a
receipt query and never replays an uncertain export. The native broker accepts
admission documents and source descriptors on the corresponding operations;
it writes verified, ordered export member bytes to the owner-created private
delivery descriptor and syncs the complete delivery before service receipt
recording. The native service persists and queries receipts through the same
authenticated peer boundary.

The owner journal's SHA-256 chain detects corruption but is not resistant to a
same-UID writer and is not an authorization source. Native peer authentication
and the service-owned receipt journal establish the completion trust boundary.
Targeted host tests cover the adapter and native components, but no installed
signed identity, enrolled owner key, live consent, or kernel isolation proof is
available. Public production staging and cleanup remain blocked by
`BLOCKED_UNSUPPORTED_EXCLUSIVITY`. AQSecurity prompt/consent paths, AQStore
cleanup and recovery, and the complete acceptance matrix have not received the
independent exhaustive review; their current host tests are not a substitute
for that review.

### 7.13 Specification review reconciliation (2026-10-27)

Receipt query and record use a separate 256 KiB bound from ordinary 64 KiB
service messages, covering the accepted 1,024-member export and the 64 KiB
metadata header duplicated in the receipt binding and completion. Receipt
lookup is nonblocking, no-follow, and rejects nonregular entries. Expired
attempts retain their original mutation deadline; the owner may resolve one
only by a bounded read-only query bound to that original attempt and installed
peer authority. No matching receipt leaves the obligation `UNKNOWN` and blocks
new attempts.

Production operations sample monotonic OS time internally. Caller clock
overrides were removed from the production factory and public receipt-recovery
API; clock injection is private to synthetic tests. Owner-session preparation
and dispatch now reserve the single session under a lock. AQStore replay
requires event-specific predecessor/state transitions, with sequence advances
only on dispatch and generation advances only on eligible staging. Replay also freezes operations and both reserve-byte policy fields across events. The broker
validates the full admit/stage/export template sequence before requesting
consent signing and checks member hashes over the bytes accepted by the
receiver before recording success.

Cleanup remains `BLOCKED_UNSUPPORTED_EXCLUSIVITY`. The service-owned directory excludes ordinary owner-UID reach, but source cannot atomically unlink by previously verified inode against service-UID replacement in the final check-to-unlink interval. The service-root pathname checks also cannot prevent a service-UID or privileged actor from replacing a checked descendant with a FIFO or another entry before the following open. Both races remain outside the ordinary owner-UID boundary and require proven identity-preserving removal and enforced isolation before cleanup can be enabled. The source factory helper also does not establish installed production authority. Acceptance criteria 1–3 remain blocked; criterion 4 test evidence remains unverified. No new acceptance evidence added here.

### 7.14 Final durability and pre-consent validation fixes (2026-10-27)

The owner transport now applies the native 12 MiB line bound, including
framing, to prepared workflow requests and responses. Receipt queries use a
separate 256 KiB framed bound. Document input remains limited to 64 KiB per
document and 8 MiB aggregate after decoding. The owner lifecycle journal
preflights each append against its 8 MiB read limit while holding the journal
lock; a capacity failure prevents durable attempt authorization and dispatch.
Receipt-journal startup removes only exact-format, service-owned stale writer
temporary files after regular-file, owner, link-count, mode, and size checks.

The native service now binds authorization manifest, plan, and rules claims to
the hello pins. Before requesting owner consent signing, the broker validates
the canonical plan and rules digest, manifest/oracle/evidence contract, and
authorized fixture coverage. Synthetic regressions exercise these rejection
and recovery boundaries. Production staging and public cleanup remain
`BLOCKED_UNSUPPORTED_EXCLUSIVITY`; synthetic spool tests do not establish
same-UID confidentiality, and the production broker continues to fail closed.
The revision-3 archive and historical `RESULT.json` remain frozen artifacts;
the source digest named by that archive is historical after these edits.

### 7.15 Fresh admission recovery binding (2026-10-27)

After restart, recovered sessions remain blocked and the store exposes at most
one fresh admission. The service marks only the connection whose admission
consumed that fresh authority. During this recovery state, that connection may
stage and export only while its original admission, connection, grant, and
store-epoch bindings remain valid. Recovered or unmarked connections stay
denied, and the exception does not authorize cleanup or another admission.
Native regressions cover stage and export on the marked connection and reject
an unmarked connection. This host evidence does not establish production
isolation or authorization; public staging and cleanup remain
`BLOCKED_UNSUPPORTED_EXCLUSIVITY`.
