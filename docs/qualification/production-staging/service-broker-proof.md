# Native staging service, broker, and isolation proof boundary

## Purpose

This document describes the native production boundary used by Issue 24. A
reader does not need prior context to understand the components, authority
separation, wire protocol, and remaining qualification gates.

The implementation is intentionally separate from the Python fixture-staging
mechanics. Python continues to return
`BLOCKED_UNSUPPORTED_EXCLUSIVITY` for production staging and cleanup. The
native sources demonstrate the intended service boundary, but they do not
authorize installation, enrollment, privileged execution, or data mutation.

## Components

### Service

`native/fixture-staging/service/main.m` is the production daemon entry point.
It may initialize only after all of these checks succeed:

1. `AQLoadInstallationPolicy` reads the fixed root-protected policy.
2. The installed policy pins an owner public key.
3. The configured service account is a dedicated non-login account.
4. The running effective UID matches the service UID in the policy.
5. The public code-attestation APIs are available at runtime.
6. `AQOpenProductionStagingRoot` opens
   `/private/var/db/argus-qualification/staging` through protected,
   descriptor-relative ancestry.
7. `AQStore` initializes from that descriptor and an installation identity.

Every accepted connection is configured with the broker signing requirement
before it is resumed. Every message is then checked with
`AQValidatePeerMessage` before its bounded contents reach the session state
machine. A malformed `documents` value is rejected and revokes the connection;
it is never treated as if the field were absent. A failed identity check
cancels the connection and revokes any session already bound to it.

`--self-check` performs the same readiness checks and exits without opening a
listener. It writes a fixed status object to standard output. Missing policy,
account, executable, root, signing, or runtime API prerequisites produce a
bounded blocker code and never an owner prompt.

### Broker

`native/fixture-staging/broker/main.m` runs as the owner and connects only to
the installed Mach service. It supports a diagnostic self-check and bounded
`session` and compatibility `relay` operations:

1. `--self-check` checks installed policy, owner-key presence, service account,
   and authenticated-peer API availability without prompting. It reports
   `NOT_READY` while live XPC identity and IPC proof are absent.
   The Python readiness adapter compares the service-reported broker revision
   and owner key identifier with the root-protected policy's `broker_cdhash`
   and `key_tag`. It keeps broker readiness and operations disabled while the
   self-check remains diagnostic.
2. `session` reads an ordered hello, admission, stage, and export workflow from
   standard input, carries inherited source descriptors and admission
   documents, authenticates service replies, and emits bounded responses.
   Consent bytes are signed only after the broker validates the complete
   consent schema, every operation claim, and their bindings. There is no
   generic command that signs caller-provided bytes. The export request also
   supplies `export_manifest`, the independently approved manifest. The broker
   removes broker-only fields before forwarding each service request.

The export verifier processes frames incrementally, keeps its scratch buffers bounded, and checks member and terminal digests before delivery. The header session, generation, manifest digest, and ordered member paths, sizes, and digests must match the approved export manifest. Delivery uses an owner-created private descriptor, complete writes, and `fsync`; successful completion requires the delivered byte count to equal the approved manifest total.

The production broker currently fails closed before creating an export spool. The supported macOS target has no anonymous-from-inception spool or enforced isolation boundary for a named temporary file. Named, unlinked spools remain available only in synthetic test builds to exercise streaming and digest behavior. Their delivery hash detects mutation but does not protect confidentiality from a same-UID process that retained the inode descriptor. Production therefore delivers no user bytes and publishes no success receipt while this isolation requirement is unmet.

After complete verification and durable owner delivery, the service persists receiver completion in its protected receipt journal. Records are limited to 256 KiB and the aggregate journal is capped at 64 MiB and 256 entries. Admission durably reserves 512 KiB for every session authorized to export before AQStore mutation; export checks the reservation again before dispatch. Recording a receipt consumes its reservation. Receipts are never pruned because they may be needed to reconcile uncertain outcomes. When capacity is exhausted, new admission or export mutation is rejected while receipt queries remain available. Receipt recording and lookup require an authenticated XPC peer and bind the original request, session, service boot, sequence, deadline, manifest, generation, and ordered member digests. The Python adapter records ATTEMPT before dispatch, accepts ACK only after an authenticated receipt, and recovers by querying without replaying an uncertain mutation.

If a delivery sink fails after accepting only part of the payload, no completion is published and the owner does not report the attempt as delivered. Recovery remains query-only until the service returns a durable receipt.

The broker does not accept caller-selected signing keys, unaudited owner
approval, arbitrary destination roots, or environment-controlled signature
verification. Application-bundle metadata identifies the expected broker
bundle; signing and provisioning remain external responsibilities.

Host tests exercise the ordered session adapter, admission documents, source
descriptors, private delivery descriptor, and receipt query boundary. These
tests use synthetic owner authority; they do not prove an installed signed
service, real owner consent, or kernel-enforced exclusivity. The public
production runner therefore continues to return
`BLOCKED_UNSUPPORTED_EXCLUSIVITY` before side effects.

### Session authority

`AQServiceSessionCore` is the non-XPC state machine. It enforces:

- one service-generated connection identifier per authenticated peer;
- a deterministic request identifier derived from the session, one-based
  sequence, operation, and canonical request digest; identifier replay state is
  constant-size and has no count quota, TTL, eviction policy, or growing set;
- a fresh broker nonce and explicit hello sequence for each owner-consent
  exchange. The service keeps one sequence high-water mark per installed owner
  for its process boot and rejects a repeated nonce/sequence before token,
  callback, or protected-loader work;
- one owner-signed canonical freshness record for every post-hello request,
  binding the installed installation, service boot, broker revision, owner key,
  connection, session, service boot identity as the process epoch, deterministic
  request identifier, strictly increasing sequence, operation, exact request
  digest, authorization digest, and original immutable schema-1 `deadline_ns`;
- signature and all freshness bindings are checked before request-specific
  documents, source descriptors, callbacks, capacity reservation, or store
  dispatch; the service creates a fresh random service boot identity at runtime
  startup, so a signed record from a previous process is rejected even when a
  deterministic test generator reuses its connection and session identifiers;
- immutable binding among the session, grant, connection, service boot identity,
  installation, manifest, plan, rules, operations, reserves, and the schema-1
  `time.monotonic_ns()` deadline. Production checks that deadline with
  sleep-exclusive `mach_absolute_time()` nanoseconds, including the unchanged
  3,600-second maximum. At hello, the service samples AQStore's continuous tick
  clock before sampling the service clock and maps the remaining signed deadline
  duration with the platform timebase, rounding down. It rejects a
  `store_deadline_ticks` value at or before the sampled store tick, beyond that
  mapped upper bound, or outside signed-64-bit arithmetic. The original
  `deadline_ns` remains immutable and is never compared as continuous-clock
  nanoseconds. Continuous store ticks may cause an earlier expiry after system
  suspend, but the mapping cannot extend store authority beyond the original
  sleep-exclusive deadline. Existing persisted store ticks are not rebased.
  This does not approve the separately proposed timing schema 2 or create a
  second freshness timeout;
- a 1 through 65,536 byte owner-consent envelope verified against the exact
  installed owner key by `AQSecurity`;
- at most 128 oracle/evidence documents, 64 KiB per document and 8 MiB total;
- at most 1,024 source descriptors, each required to be readable, regular, and
  single-linked before dispatch to `AQStore`;
- a request digest computed by the service over the canonical store fields,
  request identifier, and descriptor device/inode/size identities;
- operation admission from the owner-consented allowlist; and
- at-most-once operation sequencing delegated to `AQStore`.

A connection loss revokes the bound store session. Inspection and recovery are
read-only and may resume after reconnect. Mutation authority is never recreated
from a prior nonce, bearer value, caller boolean, or peer UID. An uncertain
mutation remains for durable inspection and is not automatically retried.

## Authority separation

Owner consent and oracle provenance are separate verdicts.

- `AQValidateSnapshotContract` evaluates manifest structure, pins, and fixture
  and evidence graphs. It has no caller-supplied reference-verifier input.
- `AQSecurity` verifies the owner's signature over the exact consent envelope.
- The service returns `owner_consent=verified_by_installed_owner_key` only after
  that signature succeeds.
- The contract assessment continues to report `owner_approval=not_checked` and
  `byte_integrity=not_checked` before transfer.
- Staged byte integrity is established later by `AQStore` full readback.
- Genuine owner-private fixtures remain `pinned_unverified`; the service refuses
  them because no authenticated independent provider is installed to produce
  `verified_independent_reference`.

No accepted digest, filename, structural match, owner signature, or Argus
output substitutes for another verdict.

## Plan and store integration

The service validates the pinned plan's `fixture_coverage` against the manifest
and validated contract. Supported modes are `mandatory_full_plan` and
`authorized_partial_plan`. Selected fixture identifiers must match the
contract in exact order. Every mandatory identifier must be selected, and full
plans must select every required identifier. The plan's `rules` canonical
digest must equal the manifest rules pin, and its host reserve must equal the
owner-consented reserve.

Admission constructs the exact immutable authority dictionary expected by
`AQStore`. Stage, eligibility, export, and cleanup use the store's own sequence,
generation, journal, verification, publication, recovery, and uncertain-effect
semantics. The service does not retry uncertain store mutations.

Export remains an anonymous read-only pipe. The store preflights the canonical
metadata header before its durable dispatch record, using the same 64 KiB
metadata bound as the broker decoder. The limit does not cap streamed payload
member sizes. The broker validates the exact `AQSNAP1\n` frame, canonical
header, per-member SHA-256 values, `AQEND1\r\n`
terminator, and terminal transcript SHA-256 while the bytes are quarantined in
the private spool. Successful pipe creation is not receiver completion. The
broker emits payload bytes only after complete validation and trusted-request
binding, and reports completion only after the verified payload has been
written.

Delivery is not revocable by the broker. Once a successful export has emitted
bytes, revoking the service session or store session prevents later authority
but cannot recall bytes already copied by the receiver or child processes.
Callers must require both the bound completion record and a successful broker
exit before treating stdout as an export. A crash or output failure before that
record leaves the export failed and any partial bytes untrusted.

## Readiness transport

The owner-side selector invokes the fixed, root-owned broker with a canonical
readiness request. The broker configures the service's code requirement, then
the service verifies the authenticated broker peer and its configured service
UID before returning non-authoritative `readinessFacts`. The owner process does
not execute the service directly. Host tests cover request validation and
transport routing; only a signed installed broker/service exchange can be used
as signed-process readiness evidence.

## Namespace and exclusivity

The service accepts no caller-selected staging root. The only production root is
`/private/var/db/argus-qualification/staging`, opened by `AQSecurity` and
retained by `AQStore`. The readiness record reports
`namespace_authority=protected_service_identity`, while cleanup remains marked
as requiring a kernel-isolation proof.

Protected location, service UID, and CodeDirectory checks are necessary but do
not independently prove that another process cannot interfere. Production
exclusivity and destructive cleanup remain blocked until the disposable-VM
proof demonstrates kernel-enforced namespace denial and crash behavior.

## Isolation proof harness

`native/fixture-staging/proof/driver.m` and `actor.m` are bounded entry points
for the separately reviewed proof bundle. The actor also exposes a fixed,
nonprivileged synthetic syscall suite. Its `--synthetic-self-test` command
creates a new mode-0700 temporary directory owned by the invoking user and
attempts `renameat`, `renameatx_np(RENAME_SWAP)`, `linkat`, `symlinkat`,
`unlinkat`, and directory removal only against fixed synthetic entry names in
that directory. It records the effective UID, syscall result, and actual
`errno`, then removes only its synthetic entries. The suite changes the
temporary directory mode to 000 and confirms that an unlink attempt is denied
by the host filesystem before restoring the mode.

These checks are synthetic filesystem tests. They do not prove that the
ordinary operator UID is excluded from the service-owned production namespace.
The source tree has neither an owner-approved signed proof manifest nor a
disposable VM authorization. Consequently:

- privileged mutation commands fail closed with
  `PRIVILEGED_PROOF_EXECUTION_NOT_AUTHORIZED`;
- missing bundle authority reports
  `PROOF_BUNDLE_AND_OWNER_APPROVAL_UNAVAILABLE`;
- actor cases report `KERNEL_ISOLATION_AUTHORITY_UNAVAILABLE`; and
- both executables support prompt-free `--self-check` failure validation; and
- both executables support `--synthetic-self-test`, which reports
  `SYNTHETIC_ONLY` and never opens the installed staging namespace.

The proof must run only from a reviewed, signed, hash-pinned bundle in a
disposable macOS ARM64 VM. The development checkout is not an installation
implementation and must not receive a root exception.

## Build and focused tests

The build modes do not install, sign, enroll, prompt, or access a real corpus:

```sh
bash scripts/build_fixture_staging_native.sh service
bash scripts/build_fixture_staging_native.sh broker
bash scripts/build_fixture_staging_native.sh proof
bash scripts/build_fixture_staging_native.sh test
```

`service` builds the daemon and deterministic session tests. `broker` builds the
broker bundle and tests the export transcript and uncertain-reconnect guard.
`proof` builds both proof executables, checks their nonprivileged fail-closed
output, and runs the synthetic syscall suite. `test` builds all production
targets and runs the deterministic contract, store, security, timing, service,
broker, and proof suites.
Every mode passes through the repository's checked 2 GiB reserve admission
before invoking the compiler.

The service and broker tests use synthetic dictionaries and bytes. They do not
enroll a key, present an owner prompt, open the production root, install a
helper, invoke a real owner corpus, or claim kernel isolation.

Verification on 2026-10-25 produced these results:

1. `bash scripts/build_fixture_staging_native.sh broker` exited 0 and reported
   `broker tests: 0 failure(s)`. The broker suite includes retained-chunk,
   no-copy mutation, sink-failure, complete-write, foreign pathname
   replacement, and failed-cleanup replacement-retention regressions. The
   replacement tests verify that pathname operations cannot change the
   anonymous verified descriptor and that closing a discarded descriptor does
   not unlink a substitute file.
2. `bash scripts/build_fixture_staging_native.sh test` exited 0. Contract
   reported 118 checks with 0 failures, security reported 171 checks with 0
   failures, and store, service, and broker each reported 0 failures.
3. Focused Python native and oracle tests exited 0: 47 tests passed.
4. `just test-android-qualification` exited 0: unittest ran 818 tests and
   reported `OK (skipped=2)`.
5. The production symbol build exited 0 and reported
   `NATIVE_PRODUCTION_TEST_SYMBOLS=ABSENT`.
6. Clang static analysis exited 0 without diagnostics. The ASan/UBSan suite
   exited 0 with the same 118 contract checks, 171 security checks, and zero
   store, service, and broker failures.
7. A completed local `cubic review --json` run over the implementation, before
   the proof-only documentation edits, reported no P1 finding in the broker
   path. Its only remaining finding was a P2 at
   `native/fixture-staging/core/AQStore.m:1` concerning concentration of store
   responsibilities; that architecture change is outside this broker
   correction and remains a separate decision. A final documentation-only
   rerun was interrupted at the checkpoint boundary and is not recorded as a
   clean review.

## Python boundary

`scripts/android_qualification/_fixture_staging_native.py` is the Python
admission check for native results. It reads only the fixed installed policy,
service, and broker paths; rejects non-root-owned, writable, symlinked, or
oversized inputs; and invokes only the prompt-free `--self-check` operation.
The broker self-check reports `NOT_READY` with `AWAITING_XPC_DEPENDENCY_PROOF`. This is a static diagnostic; live broker identity and IPC proof remain required before production readiness can be claimed.

The broker's durable completion includes its absolute `receipt_path`, while
the service binds the completion to the current `service_boot_id` and
`sequence` before journaling and returning it. The Python session verifier
requires that complete DTO, validates the receipt path, and hashes the
canonical receipt fields while excluding the service binding fields, the
receipt digest itself, and `receipt_path` (which is added after the receipt
file is synchronized).

Before consuming reserved receipt capacity, the service requires the exact
18-field completion schema, checks the member count and digest, and recomputes
`receipt_sha256` over the canonical broker payload. A malformed or stale digest
is rejected before any receipt is persisted or the reservation is removed.

`validate_snapshot_contract_for_grant` runs the manifest-schema-2 oracle
validator with the issued staging grant's manifest, plan, and rules pins. It
requires the ordered fixture identifiers to match the grant and preserves these
distinct support tiers:

1. `synthetic_only` means the declarations and evidence are synthetic.
2. `pinned_unverified` means a genuine independent-source pin exists but no
   authenticated independent provider established its source, revision, and
   claim support.
3. `verified_independent_reference` is reserved for a future authenticated
   native provider. This implementation has no API that can produce it, so
   service admission of genuine owner-private fixtures fails closed.

`validate_native_contract_result` additionally consumes the canonical
broker/service envelope and enforces exact manifest, selected-fixture,
oracle-support, and coverage bindings. Its response argument is raw caller
bytes: a literal `owner_consent=verified_by_installed_owner_key` field cannot
prove that Python received a sealed native transport result. The validated
Python result therefore sets `owner_consent="unverified"` until such transport
authentication exists. This remains separate from `owner_approval`, which stays
`not_checked`. Document validation does not supply snapshot authority, and
`byte_integrity` stays `not_checked` until the store verifies staged bytes.

Host-scope status: `OwnerSessionExportClient` drives the ordered
hello/admit/stage/export workflow through the broker adapter. Host tests exercise
the public dispatch path with synthetic authority, including descriptor
attachments, durable owner delivery, receipt validation, and query-only
recovery. These tests establish the adapter contract; they do not qualify an
installed signed service or broker.

The source exports `create_production_owner_export_preparation` to build a lazy
preparation from the grant, expected attempt digests, caller intent, and open
descriptors. `stage_fixtures(destination=None)` validates the grant binding
and the supplied manifest and authorization bytes before invoking native
preparation, then verifies the broker-returned attempt before dispatch. The
helper does not establish installed production authority or qualification.
Public staging still requires kernel-isolation admission and
the fixed native-installation probe. A missing prerequisite returns
`BLOCKED_UNSUPPORTED_EXCLUSIVITY` before side effects. Installed identity,
owner consent, exclusivity evidence, and production XPC qualification remain
unavailable, so host-seam coverage is not a production-qualified integration
claim.

## Remaining production gates

1. Approved team signing, provisioning profiles, hardened runtime, and exact
   broker/service CodeDirectory pins.
2. Owner-key enrollment in the approved access group and denial tests against
   separately signed applications.
3. An installed reference provider for genuine independent fixture evidence.
4. Disposable-VM proof of service-account isolation, descriptor/source
   stability, XPC substitution and replay rejection, namespace denial, export
   interruption, crash recovery, and uncertain cleanup.
5. A real owner-authorized corpus with independent expectations and complete
   byte verification.
6. End-to-end owner transport spanning hello, owner consent, contract
   admission, staging, export-evidence acceptance, and cleanup. The broker's
   durable receipt is consumed through a versioned native owner export-evidence
   contract and production admission issuer; neither is implemented. The
   Python boundary selects only the fixed installation and deliberately returns
   `BLOCKED_UNSUPPORTED_EXCLUSIVITY` until that transport and its proof gates
   exist; it cannot select a synthetic or local adapter.

Passing a host build or deterministic test does not satisfy any item above.
