# Snapshot and oracle contract

## 1. Scope and authority

`scripts/android_qualification/fixture_oracle.py` validates private declarations
for manifest schema 2, oracle schema 1, and evidence schema 1. It does not open
files, discover ROMs, access a network, grant staging authority, or issue owner
verdicts. The legacy manifest parser and historical evidence meanings remain
unchanged. Schema 1 manifests are not accepted by this validator.

The dependency graph is `authorization → manifest → oracle → evidence`.
Evidence can reference other evidence. No oracle or evidence field references
an enclosing manifest, authorization, or oracle digest. References are opaque
identifiers, never filesystem paths or URLs to fetch. All dependencies must be
supplied explicitly, be reachable from the manifest, and form an acyclic graph.

Authorization must pin the manifest's canonical digest, plan digest, and rules
digest. Matching caller-supplied pins proves consistency, not authenticated
authorization. The native authenticated service must establish those pins and
owner consent through its separate authority boundary. The manifest's source
authority declaration means sealed service-protected snapshots are the intended
source of truth; validation alone does not establish such protection.

## 2. Canonical bytes and limits

1. Documents are UTF-8 JSON objects without a byte-order mark. Each encoded
   document and its canonical serialization must fit in 65,536 bytes.
2. Keys are ASCII and sorted by ASCII byte value. Arrays retain their order.
   Separators are `,` and `:` without spaces. String serialization follows
   Python `json.dumps(ensure_ascii=False)`: escape quotes, backslashes and
   controls; do not escape `/` or non-ASCII Unicode scalar values.
3. Every string value must already be NFC. Non-NFC values and unpaired surrogates
   are rejected rather than normalized. Unknown or duplicate object keys are
   rejected, including nested duplicates before canonicalization.
4. Booleans are distinct from integers. Integers range from `-9223372036854775808`
   to `9223372036854775807`. Floats, exponent notation, non-finite numbers, and
   the JSON integer spelling `-0` are rejected. Null is supported by the generic
   canonical encoder but is not a valid value for any schema field.
5. Root depth is zero; each array/object value adds one. Maximum depth is 32.
   At most 128 oracle and evidence records combined may be supplied. Record
   registries must be lists or tuples; unbounded iterators are unsupported.
6. Digest strings are exactly 64 lowercase hexadecimal characters. Hashes are:
   `manifest = SHA256(canonical_bytes)`,
   `oracle = SHA256("argus.fixture-oracle.v1" + NUL + canonical_bytes)`,
   `evidence = SHA256("argus.fixture-evidence.v1" + NUL + canonical_bytes)`.
   Prefixes are ASCII bytes, with exactly one terminal zero byte. The manifest
   hash deliberately preserves the existing authorization plain-hash algorithm.

Hash helpers encode bounded JSON values; they do not themselves validate schema
or establish authenticity. The validator performs both schema and pin checks.

## 3. Exact manifest schema 2

Every listed field is required unless explicitly marked optional. All objects
reject additional fields. Versions are integers, never booleans. Identifiers,
revisions, provenance, and descriptive fields are nonempty, trimmed strings
without control characters. Identifier fields are at most 256 characters and
exclude `/`, `\\`, `:`, `.` and `..` as complete identifiers. Revisions are
opaque nonempty strings of at most 256 characters, not mutable version aliases.

| Manifest field | Type / value |
| --- | --- |
| `schema_version` | integer `2` |
| `source_authority` | `"service_protected_snapshot_v1"` |
| `plan_sha256`, `rules_sha256` | SHA-256 digests matching authorization inputs |
| `coverage_mode` | `"mandatory_full_plan"` or `"authorized_partial_plan"` |
| `selected_fixture_ids` | nonempty ordered array of distinct fixture identifiers |
| `fixtures` | nonempty array of fixtures, in exactly the selected-ID order |

The caller must separately check coverage against the authorized plan; this
slice validates the manifest selection and digest binding, not plan contents.

| Fixture field | Type / value |
| --- | --- |
| `fixture_id` | identifier; distinct under NFD/casefold across the manifest |
| `platform`, `representation`, `group_id` | strings, maximum 256 characters |
| `identity` | string, maximum 512 characters |
| `order` | nonnegative signed 64-bit integer; strictly ascending within each group |
| `entrypoint` | safe relative path naming a declared file |
| `files` | nonempty ordered array of `{path,role,size,sha256}` |
| `companions` | ordered array of distinct `{source,target}` path edges |
| `identity_evidence` | `"synthetic_expectation_v2"` or `"independent_reference_pinned_v1"` |
| `oracle_pin` | `{schema_version:1,oracle_ref,revision,sha256}` |
| `facts` (optional) | nonempty object containing any of `edition`, `region`, `disc_set`; each a string of at most 256 characters |

File `size` is nonnegative signed 64-bit; `role` is a string of at most 64
characters. Paths are at most 4096 characters, relative NFC POSIX paths with
no empty, `.` or `..` components, backslashes, colons, or control characters.
Every path and directory component must have a unique NFD/casefold spelling.
File/directory prefix collisions are rejected. Each companion endpoint names a
declared file. The directed graph must be acyclic and every file must be
reachable from the entrypoint. Array ordering is part of the exact binding.

## 4. Exact oracle and evidence schemas 1

| Shared field | Type / value |
| --- | --- |
| `schema_version` | integer `1` |
| `revision` | immutable revision string, at most 256 characters |
| `fixture` | exact fixture object from section 3, excluding `identity_evidence` and `oracle_pin` |
| `corpus_origin` | `"synthetic"` or `"owner_private_genuine"` |
| `acceptance_rule_sha256` | must equal manifest `rules_sha256` |
| `method` | `"synthetic_expectation"` for synthetic; `"independent_reference"` for genuine |
| `provenance` | bounded descriptive string, at most 4096 characters; not authentication |
| `limitations`, `conflicts` | arrays of distinct descriptive strings, each at most 4096 characters; may be empty |
| `evidence_refs` | array of distinct evidence pins `{schema_version:1,evidence_ref,revision,sha256}` |

An oracle additionally requires `oracle_ref`, an identifier. Evidence instead
requires `evidence_ref`, an identifier. Independent evidence additionally
requires `reference:{ref,revision,sha256}`, where `ref` is a bounded opaque
external-source reference string (4096 characters maximum), `revision` is a
256-character immutable revision string, and `sha256` pins the source artifact
bytes. Synthetic evidence must omit `reference`. Oracles never contain it.

Oracle/evidence registry identifiers are unique within their respective
namespaces, even if duplicate records have equal bytes. Every supplied record
must be reachable. Reference pins must match the target record's exact revision,
version, and domain-separated digest. Multiple uses of the same reference must
agree. All reachable evidence must bind the same exact fixture, origin, and
acceptance rule as its oracle. Any nonempty `conflicts` array blocks validation.
Uses of the same external `reference.ref` must also agree on revision and digest
throughout the supplied graph; contradictory pins are an evidence conflict.
Cycle and missing-reference detection precede digest checks on evidence edges.
The contract API has no caller-supplied reference-verifier callback or Boolean.

Genuine oracles require at least one evidence reference, and every reachable
genuine evidence record requires an independent source pin. Filenames, headers,
Argus output, and generated fixtures are not independent reference methods.
Synthetic records always remain synthetic. No authenticated independent native
provider is installed, so genuine declarations remain `pinned_unverified`;
production admission fails closed when it requires verified independent support.
An `independent_reference_pinned_v1` manifest label describes a declaration;
it is explicitly distinct from legacy `owner_approved_expectation_match` and
does not assert verified independent identity or owner approval.

## 5. Public Python interface

```python
canonical_json(value: object) -> bytes
decode_document(encoded: bytes) -> dict[str, object]
manifest_sha256(document: object) -> str
oracle_sha256(document: object) -> str
evidence_sha256(document: object) -> str
validate_snapshot_contract(
    manifest: bytes,
    oracles: list[bytes] | tuple[bytes, ...],
    evidence: list[bytes] | tuple[bytes, ...],
    *,
    authorized_manifest_sha256: str,
    authorized_plan_sha256: str,
    authorized_rules_sha256: str,
) -> SnapshotContract
```

`SnapshotContract` is an immutable dataclass containing `manifest_sha256`,
`source_authority`, and a `fixtures` tuple of immutable `FixtureAssessment`s.
Each assessment contains `fixture_id`, `oracle_ref`, `oracle_revision`,
`oracle_sha256`, `corpus_origin`, `byte_integrity`, `structural_expectation`,
`independent_support`, and `owner_approval`.

`byte_integrity` and `owner_approval` are always `"not_checked"`.
`structural_expectation` is `"validated"`; it describes the declared graph,
not observed content. `independent_support` is `"synthetic_only"` for synthetic
corpora or `"pinned_unverified"` for genuine declarations. This Python function
has no native verifier result and cannot accept a callback or boolean that
promotes a declaration to `"verified_independent_reference"`. The installed
native service also has no reference-verifier injection point. The aggregate
classifier likewise treats a caller-built contract that merely declares
`"verified_independent_reference"` as `pinned_unverified`; only a future sealed,
authenticated contract result could justify a stronger tier. A future
authenticated provider requires a separately designed authority boundary;
absence of that authority leaves genuine declarations `pinned_unverified` and
makes service admission fail closed when verified support is required.

No file loader is included. Callers must acquire owner-only regular documents
without following aliases, enforce their existing private-input policy and the
64 KiB limit, and sanitize all file-operation errors before using this API.
The validator has no ambient filesystem or network access.

Failures raise `OracleError`, whose `code` and message contain only a fixed code:
`INPUT_INVALID`, `LIMIT_EXCEEDED`, `SCHEMA_UNSUPPORTED`, `PIN_MISMATCH`,
`MISSING_REFERENCE`, `REFERENCE_CYCLE`, `EVIDENCE_CONFLICT`,
or `UNUSED_RECORD`. Raw input, paths, and exception text are not included. No
partial result is returned after a failure.

### 5.1 Staging grant admission

`authorize_fixture_staging` branches on the manifest schema version before
issuing an ephemeral preparation grant. Schema 1 keeps the existing strict
owner-approved manifest parser and does not read oracle inputs. Schema 2 reads
each caller-supplied oracle and evidence path through the private-input loader,
then passes the original manifest bytes and loaded documents to
`validate_snapshot_contract`. The loader rejects aliases, non-regular files,
unsafe ownership or permissions, and oversized documents before validation.

The grant retains the per-fixture result as `synthetic_only` or
`pinned_unverified`. The Python validator never promotes a declaration to
`verified_independent_reference`; that status can only come from the installed
native authority after its authenticated provider and owner evidence checks.
A schema 1 manifest
retains `owner_approved_expectation_match`. These values describe expectation
support only. The separately loaded session authorization and owner approval
still govern grant issuance, `byte_integrity` remains unchecked until staging
readback, and contract validation never makes the manifest a snapshot
authority.

### 5.2 Authenticated independent-reference provider

The installed native session exposes this provider operation over the
authenticated broker/service boundary:

```python
fetch_reference(
    query: IndependentReferenceQuery,
) -> IndependentReferenceResult
```

The query contains only the evidence identifier, pinned source reference,
revision and digest, the authorization and manifest digests, and the complete
session binding. It contains no reference bytes. The service verifies the live
broker peer and owner authorization, then asks the installed owner-authorized
provider for the source. The provider result binds the same session identity,
request ID, sequence, nonce, original deadline, authorization digest, and
manifest digest. It returns the exact query, reference bytes through a private
seekable stream, source identity, and bounded provenance. The service persists
the authenticated result in the owner journal before reporting completion.

Python streams the bytes through its local SHA-256 and content checks and
requires the returned query to match exactly. This verifies delivered bytes
against the declared pin; only the authenticated native result establishes
provider identity and provenance and owns the admission decision. Python does
not accept a caller-supplied verifier, Boolean, path, or bundled value as
independent-reference proof.

This interface defines the required mechanism. No authenticated provider is
currently installed and no genuine owner records are present. Its existence in
source or successful fake-provider tests does not upgrade genuine support,
provide owner consent, or enable production admission.

## 6. Native Objective-C interface

`native/fixture-staging/core/AQContract.h` exposes the same no-I/O validation
boundary for native service code. `AQValidateSnapshotContract` accepts document
bytes and explicit authorization pins. It never opens a file, resolves a path,
or starts a network request. The trusted service must securely acquire the
documents and authenticate the pins before calling it.

The native function applies these checks in authorization, manifest, oracle,
evidence order. It validates every document through `AQJSON`, so integer,
depth, UTF-8, NFC, duplicate-key, and canonical-size checks do not rely on
Foundation JSON parsing. Exact field sets reject unknown fields, including
attempts to add authorization or manifest back-references. Registry and
fixture graphs must be reachable, acyclic, and complete; unused records are
rejected before any supported tier is assigned.

The native function accepts no reference-verifier block or Boolean. Synthetic
records are `synthetic_only`, and genuine records are always
`pinned_unverified` because no authenticated independent provider is installed.
No caller-controlled input can mint `verified_independent_reference`.

On success the function returns an immutable dictionary containing
`manifest_sha256`, `source_authority`, and an ordered `fixtures` array. Each
assessment reports the fixture and oracle identity, corpus origin, validated
structural declaration, independent-support tier, and the separate
`not_checked` values for byte integrity and owner approval. Returning a result
does not authorize staging and does not establish actual file content.

All failures return `nil` with an `NSError` in `AQContractErrorDomain`. The
localized description is one fixed code: `INPUT_INVALID`, `LIMIT_EXCEEDED`,
`SCHEMA_UNSUPPORTED`, `PIN_MISMATCH`, `MISSING_REFERENCE`, `REFERENCE_CYCLE`,
`EVIDENCE_CONFLICT`, or `UNUSED_RECORD`. Raw JSON, paths, and provider
exception text are not copied into the error.

The contract-only harness compiles `AQJSON`, `AQContract`, and their tests
without requiring the later store, security, broker, or service slices:

```sh
bash scripts/build_fixture_staging_native.sh contract
```

The script preserves the mandatory disk-capacity admission check and the
macOS ARM64 build target. It is a deterministic host test harness, not native
isolation or production-authority evidence.

## 7. Synthetic conformance evidence

`native/fixture-staging/fixtures/oracle-contract-v1-golden.json` pins canonical
bytes and literal expected digests computed independently with OpenSSL. Its
`canonical_vectors` entries contain `input_json`, expected `canonical_utf8`,
`canonical_utf8_hex`, and the three digest variants. Its `snapshot_vector`
contains the complete manifest, oracle/evidence registries, authorization pins,
expected canonical record bytes/digests and synthetic support result.
`invalid_json_vectors` contains parser rejection cases, except the explicitly
marked `parse_only_valid` case: unknown schemas can be parsed as generic JSON,
but cannot pass contract validation. Native helpers must distinguish those
two operations.

The vectors contain only synthetic data. Python tests exercise them and
deliberate invalid graphs. Native consumers must use the same vectors,
distinguish JSON booleans from integers, and preserve signed 64-bit values
without floating conversion.
Passing these tests is deterministic tier-A evidence only; it does not qualify
OS isolation, production authorization, genuine fixtures, or an owner verdict.

## 8. Authorization pin binding before consent signing

The service hello message binds the canonical authorization document to the
manifest, plan, and rules digests carried by the request. The authorization's
`fixture_manifest_sha256` claim and nested `plan.plan_sha256` and
`plan.rules_sha256` claims must each be valid SHA-256 values equal to those
request pins. A digest match for the authorization bytes alone does not satisfy
this binding.

Before requesting an owner consent signature, the broker decodes the admission
documents and checks their canonical plan bytes and rules digest against those
same pins. It validates the manifest, oracle registry, and evidence registry
with `AQValidateSnapshotContract`, then verifies that the manifest selection
agrees with the authorized plan coverage. Invalid document bytes, broken
references, mismatched pins, or inconsistent coverage are rejected before any
consent or freshness signature is requested. The service repeats the admission
checks at the authenticated mutation boundary.
