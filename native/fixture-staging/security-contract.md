# Native authentication contract

## 1. Integration boundary

`core/AQSecurity.h` is the integration interface. Link `AQSecurity.m` with ARC,
Foundation, AppKit, Security and LocalAuthentication, using public C XPC APIs.
The compilation target is macOS 12.0 ARM64; this is not a qualification claim.
`int AQRunSecurityTests(void)` in `tests/security_tests.m` returns a failure count.
Define `AQ_SECURITY_TEST_MAIN` only for a standalone test executable.

`AQLoadInstallationPolicy` is the only production policy source. The standalone
`AQParseInstallationPolicy` function supports validation but returns an untrusted
policy that peer authentication and owner-key operations refuse. Policies are
immutable. There is no production test mode, software signing key, alternate
installation path, implicit enrollment or caller-selected verification key.

## 2. Installation policy version 1

The sole configuration path is
`/Library/PrivilegedHelperTools/ArgusFixtureStaging/installation.json`.
It is a UTF-8 JSON object of at most 16,384 bytes with exactly these fields.
Duplicate keys (including escaped spellings), unknown keys, nested values,
incorrect types and invalid values fail closed. Whitespace and field order are
insignificant; this policy format is independent of operation-envelope encoding.

| Field | Required value |
|---|---|
| `schema` | Integer `1`; a JSON boolean or floating-point number is invalid |
| `team_id` | Ten uppercase ASCII letters/digits belonging to the approved signing authority |
| `broker_cdhash` | Exactly 40 lowercase hexadecimal digits: approved broker CodeDirectory hash |
| `service_cdhash` | Exactly 40 lowercase hexadecimal digits: approved service CodeDirectory hash |
| `owner_uid` | Integer 1 through 4,294,967,294 identifying the interactive owner |
| `service_uid` | Integer in the same range, different from `owner_uid`, identifying the noninteractive service account |
| `key_access_group` | `<team_id>.com.argusromtoolkit.fixture-staging.broker` |
| `key_tag` | `com.argusromtoolkit.fixture-staging.owner-consent.v1` |
| `owner_public_key` | Canonical base64 of the 65-byte uncompressed X9.63 P-256 public point, or JSON `null` before explicit enrollment |

A null key never authorizes signing or an operation. Enrollment returns a public
key; an independently authorized installer must pin it into the root-protected
policy. This component does not update configuration or install anything.
UID provisioning and noninteractive account configuration are installer duties.

## 3. Paths and peer authentication

1. The immutable production staging root is
   `/private/var/db/argus-qualification/staging`.
2. The broker executable is
   `/Library/PrivilegedHelperTools/ArgusFixtureStaging/ArgusStagingBroker.app/Contents/MacOS/ArgusStagingBroker`;
   its signing identifier is `com.argusromtoolkit.fixture-staging.broker`.
3. The service executable is
   `/Library/PrivilegedHelperTools/ArgusFixtureStaging/argus-staging-service`;
   its signing identifier is `com.argusromtoolkit.fixture-staging.service`.
4. The Mach service is `com.argusromtoolkit.fixture-staging`.

Installation ancestry uses root-owned directories with exact mode 0755, no ACL
entries and no symbolic links. Executables are root-owned 0755 regular files
with exactly one hard link; configuration is root-owned 0644. Descriptor-relative
opens and metadata checks fail closed. The staging namespace itself is owned by
the separate service identity and is validated by the namespace component; it
must not be passed to the root-owned installation validator as if it were an
installation directory.

The pinned service UID must resolve to a dedicated account with the unusable
password marker `*`, a non-login shell and only its primary group. Missing
accounts, login users and supplementary groups fail closed. These account checks
supplement the UID, CodeDirectory and filesystem checks; none is authority by
itself.

`AQOpenProductionStagingRoot` opens the fixed staging anchor through root-owned
ancestry. The final directory must be owned by the pinned service UID, have
exact mode 0700 and have an empty ACL. The function returns a checked descriptor
so callers continue with descriptor-relative operations. No caller-selected
staging root or writable installation directory is accepted.

Call `AQConfigurePeerRequirement` exactly once before activating each new
connection. Configure the service listener and every accepted broker connection
for `AQPeerBroker`; configure broker outgoing connections for `AQPeerService`.
Cancel on error. The requirement pins Apple-anchored team, identifier and CDHash.
`AQValidatePeerMessage` additionally derives a `SecCode` from the received XPC
message, checks its validity, code revision, exact executable path and protected
ancestry, hardened runtime and debug/library-validation restrictions. It also
checks the live remote connection's UID. No PID-only lookup or private audit
token API is used. A caller-provided path is never peer identity.

Apple's connection requirement authenticates received messages. Both sides must
first exchange **non-sensitive** handshakes and authenticate each received live
message before transmitting private data or accepting authority. Reconnect,
interruption and invalidation discard authentication and authorization state.
Never reuse a session on a substituted connection or an anonymous endpoint.
See Apple's [XPC authentication guidance](https://developer.apple.com/forums/thread/681053)
and the SDK documentation for `xpc_connection_set_peer_code_signing_requirement`.

Export completion and receipt lookup use this same authenticated live XPC peer
boundary. A durable receipt is stored by the service only after the signed
broker reports complete frame verification, ordered member and digest checks,
generation and deadline binding, and durable receiver acceptance. Receipt
responses bind the original request, session, boot epoch, sequence, deadline,
manifest, generation, and ordered member digests. The service returns a receipt
only to the authenticated broker on that connection; the receipt is not a
detached signature and does not introduce another key. Reconnection permits a
read-only receipt query over a newly authenticated connection, bound to the
original request, session, boot, sequence, deadline, manifest, generation, and
members. A new `hello` creates a different session and cannot continue or
replace that attempt. Reconnection never repeats an uncertain export.
The broker uses a separate `query_deadline_ns`, capped at five seconds, for
the read-only control exchange and response. It removes that transport budget
before sending the query to the service, leaving the original deadline in the
receipt binding unchanged.

The public connection requirement is available on macOS 12.0 and later.
`SecCodeCreateWithXPCMessage` is a macOS-only API; the SDK does not assign it a
later availability version. The module refuses a deployment target older than
macOS 12.0. `AQAuthenticatedPeerAPIsAvailable` resolves both public function
symbols from the loaded frameworks at runtime and fails closed if either symbol
is absent. There is no PID, audit-token, synthetic-dictionary or unsigned-message
fallback. The XPC setter's nonzero result, including `ENOTSUP`, is also a
failure. A message-derived code object uses the message audit token to locate
the live process and is still insufficient alone: policy pinning, filesystem
identity, dynamic signature state and live peer UID must all agree.

## 4. Consent and signature boundary

The parent strict parser supplies the canonical operation-envelope bytes.
Security code does not parse or recanonicalize that envelope. It copies at entry,
accepts 1–65,536 bytes, and displays those exact bytes before signing. The parent
must validate the complete operation, session, fresh nonce/challenge, input pins,
oracle references and replay state before presentation and again before using a
signature. Before requesting consent signing, the broker validates the complete
`admit`, `stage`, `export` template sequence, each operation name, required
template fields, and the absence of pre-supplied freshness or consent
signatures. It also decodes admission documents and validates canonical plan
bytes, manifest/plan/rules pins, oracle references, evidence references, and
plan coverage before requesting any consent or freshness signature. The service
binds the authorization's manifest, plan, and rules claims to the hello pins and
repeats document validation before admission. ECDSA verification alone is not
current owner approval or mutation authority. The daemon only verifies against
its installed pinned public key.
The service burns an accepted broker nonce before generating session and
challenge tokens, so a later setup failure cannot leave that challenge nonce
reusable.

`AQRequestOwnerSignature` uses an existing permanent P-256 Secure Enclave key in
the Data Protection keychain. `AQEnrollOwnerKey` is a separate entry point with a
distinct explicit enrollment confirmation and fresh owner authentication. Both
check approved live broker identity and owner UID. Each operation uses a new
`LAContext` with Touch ID reuse duration zero and invalidates it on completion.
Key protection is `WhenUnlockedThisDeviceOnly`, `userPresence` and
`privateKeyUsage`; no software-key fallback exists. Returned key attributes and
access group must match the actual queried item, and the public key must match
the root-protected pin before signing is accepted.

Entitlement inspection and successful broker key access do **not** prove exclusion
of every other signed app. Production qualification requires actual access-group
denial tests using the intended provisioning profiles and separately signed
attackers. See Apple's [Secure Enclave key guidance](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave).

## 5. Qualification boundary

Unit tests exercise deterministic policy/preconditions and real rejection paths,
including hard-linked and special-file descriptors plus spoofed PID fields and
spoofed audit tokens, without prompts, key writes or privilege changes. They do not
establish IPC isolation, copied-binary resistance, same-UID exclusion, reconnect
behavior, Secure Enclave ACL enforcement or a qualified installation.
Disposable-VM adversarial tests and an approved signed production deployment
remain required.

The proof actor's synthetic suite also attempts real filesystem syscalls against
a newly created, private temporary directory. It verifies rename, swap, link,
symlink, unlink, and directory-removal behavior, and records an actual
permission-denied result after removing access from that test directory. This
demonstrates local filesystem behavior only; it is not evidence that the
operator UID is isolated from the service-owned staging namespace.
Test authorities live only in `tests/security_tests.m` and the
`AQ_SECURITY_TESTING` build. That flag exposes pure predicates and a policy
provenance override solely for the disposable executable. It also supplies a
compile-time-only switch that simulates absent peer APIs to prove fail-closed
behavior. Production builds omit those symbols. Synthetic policies, software
P-256 keys, anonymous XPC endpoints and caller-supplied dictionaries never
establish production authority.

Run the focused target with:

```sh
scripts/build_fixture_staging_native.sh security
```

The target compiles only `AQJSON.m`, `AQSecurity.m` and the security tests. It
performs an in-process anonymous-XPC round trip to prove that a received message
resolves to its live peer `SecCode` and UID, while production validation still
rejects that unapproved test identity. This is API-level fail-closed evidence,
not broker/service isolation evidence. A successful signed two-process test,
actual non-login `_argusqual` installation, real Secure Enclave enrollment and
user-presence prompts remain required in a disposable VM or approved
deployment.
