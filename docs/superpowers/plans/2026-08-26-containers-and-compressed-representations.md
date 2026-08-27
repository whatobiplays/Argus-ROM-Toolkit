# Containers and Compressed Representations Implementation Plan

> **Required subskill for implementation:** use `superpowers:test-driven-development` for every behavior change, `superpowers:systematic-debugging` for any unexpected failure, and `superpowers:verification-before-completion` before claiming the work complete.

**Goal:** Activate the approved container/compressed-representation contract so supported ZIP, 7z, tar, gzip, bzip2, xz, CHD, RVZ, CSO, and WBFS inputs participate in the existing source → identity → grouping → hydration → Library flow with persistent derived source truth, exact canonical convergence, cumulative resource safety, and no packaging-sensitive identity.

**Architecture:** Keep BE-012's transformation graph central. Native provider entries and transformation-derived entries remain one `SourceEntry` graph with different coordinate/version evidence. A single operation-scoped `ParsingSession` owns cancellation, cumulative budget accounting, and app-private staging. Generic wrappers enumerate persistent derived scopes; alternate optical representations decode into the P03-005 canonical optical contracts. Application code owns transformation admission, single-game policy, dependency admission, reconciliation authority, and error mapping; infrastructure owns format parsing/decoding, bounded reads, staging mechanics, and SQLite.

**Tech Stack:** Rust 1.97.1 / edition 2024, SQLite/rusqlite, SHA-256, existing Argus runtime/UoW/job architecture. Pure-Rust decoder policy: `chd` 0.3.4 with `max_perf` disabled and block-CRC verification enabled; `sevenz-rust2` 0.22.x with a deliberately restricted feature set; `flate2` 1.1.x with `rust_backend`; `ruzstd` 0.9.x; pure-Rust LZMA/BZip2 codecs where required. Do not add `nod`, `zstd`, `liblzma`, `bzip2-sys`, libchdr, libarchive, unrar, or external decoder executables to the production dependency graph.

**Spec:** `docs/superpowers/specs/2026-08-26-containers-and-compressed-representations-design.md`

**Governing contracts:** `docs/specifications/backend/spec-be-011-source-provider-and-indexing-contract.md`, `spec-be-012-transformation-and-hash-scheme-contract.md`, `spec-be-014-production-content-identity-catalog.md`, and `spec-be-015-game-library-grouping-and-enrichment-contract.md`.

## Global Constraints

1. Preserve every existing cartridge/native-optical identity scheme ID, identity revision, digest value, `GameContent`, `Game`, and current source association across migration and unchanged refreshes.
2. Do not hash ZIP/7z/CHD/RVZ/CSO/WBFS container bytes as logical game identity.
3. RAR, encrypted/password-protected archives, and split/multi-volume archives remain unsupported in MVP.
4. Multi-game archives persist truthful derived source structure but materialize no member `GameContent` from that archive.
5. Only `Complete + validated stable input` grants absence authority for an exact derived scope.
6. All nested transformations share one cumulative budget: 16 GiB single representation, 32 GiB expanded, 16 GiB staged, 65,536 derived entries, nesting depth 4, and a finite parser-work ceiling sufficient for the largest advertised optical representation.
7. All handwritten Argus Rust remains `unsafe`-free. No production decoder dependency may require a C/C++ decoder library, native build toolchain, or external executable.
8. Staging is app-private, transient, operation-scoped, never a `SourceEntry`, never a reusable cache, and startup-cleanable after process loss.
9. Do not add new Library browsing/detail UX or physical-device qualification in this task.
10. New source/API/schema names must describe domain concepts; do not put phase/slice identifiers into them.
11. Use only synthetic redistributable media fixtures.
12. **Execution note:** the commit steps below are for normal superpowers worktree execution. A Delegation v3/Codex task that explicitly forbids Git history changes overrides only those commit actions; in that mode, leave changes unstaged and use each commit point as a logical checkpoint.

## Current File / Interface Map

- `rust/crates/argus-application/src/content.rs` — production transformation registry and immutable identity catalog.
- `rust/crates/argus-application/src/logical.rs` — `SourceVersionEvidence`, provenance, identity convergence.
- `rust/crates/argus-application/src/sources/provider.rs` — provider-owned locators, native observations, source-read port.
- `rust/crates/argus-application/src/sources/scan.rs` — native traversal, positive reconciliation, exact-scope finalization.
- `rust/crates/argus-application/src/jobs.rs` — `NewSourceEntry`, `SourceEntryRecord`, `SourceEntryRepository` transaction contract.
- `rust/crates/argus-infrastructure/src/content_stream.rs` — bounded random-access `ContentReader`, current per-source budget wrapper, blocked-container detection.
- `rust/crates/argus-infrastructure/src/content_optical.rs` — already-qualified native optical parsing and canonical envelopes.
- `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs` — production local provider/source reads.
- `rust/crates/argus-infrastructure/src/sqlite/jobs.rs` — transaction-scoped source-entry repository implementation.
- `rust/crates/argus-infrastructure/src/sqlite/source_entries.rs` — hierarchy read projection.
- `rust/crates/argus-infrastructure/src/sqlite/logical.rs` — logical identity/provenance persistence and source-version validation.
- `rust/crates/argus-infrastructure/src/sqlite/migrations/mod.rs` — migration registry, currently through v13.
- `rust/crates/argus-runtime/src/runtime.rs` / `lib.rs` — production composition seams.

---

## Task 1: Add transformation/derived-entry vocabulary and published errors

**Files:**
- Create: `rust/crates/argus-application/src/transformation.rs`
- Modify: `rust/crates/argus-application/src/lib.rs`
- Modify: `rust/crates/argus-application/src/content.rs`
- Modify: `rust/crates/argus-application/src/logical.rs`
- Modify: `rust/crates/argus-application/src/errors.rs`
- Modify: `rust/crates/argus-application/tests/content_contract.rs`
- Create: `rust/crates/argus-application/tests/transformation_contract.rs`

### Step 1: Write failing contract tests

Add tests that require:

```rust
use argus_application::{
    DerivedEntryKey, DerivedFingerprint, DerivedLocator, DerivedScopeOutcome,
    ErrorCode, SourceVersionEvidence, SourceVersionKind, TransformationBudget,
    TransformationOutput, TransformationRegistry,
};

#[test]
fn production_budget_matches_the_approved_safety_envelope() {
    assert_eq!(
        TransformationBudget::production(),
        TransformationBudget::new(
            16 * 1024 * 1024 * 1024,
            32 * 1024 * 1024 * 1024,
            65_536,
            4,
            16 * 1024 * 1024 * 1024,
            64 * 1024 * 1024 * 1024,
        )
    );
}

#[test]
fn source_version_distinguishes_provider_and_derived_evidence() {
    let derived = SourceVersionKind::Derived(DerivedFingerprint::from_transformation("df:v1".into()));
    assert_ne!(derived, SourceVersionKind::Provider(None));
}

#[test]
fn published_container_errors_match_be_012() {
    assert_eq!(ErrorCode::ValidationContentMalformed.as_str(), "ARGUS.V1.VALIDATION.CONTENT_MALFORMED");
    assert_eq!(ErrorCode::ValidationContentUnsupportedRepresentation.as_str(), "ARGUS.V1.VALIDATION.CONTENT_UNSUPPORTED_REPRESENTATION");
    assert_eq!(ErrorCode::ValidationContentEncryptedUnsupported.as_str(), "ARGUS.V1.VALIDATION.CONTENT_ENCRYPTED_UNSUPPORTED");
    assert_eq!(ErrorCode::ValidationMultiGameContainerUnsupported.as_str(), "ARGUS.V1.VALIDATION.MULTI_GAME_CONTAINER_UNSUPPORTED");
    assert_eq!(ErrorCode::FilesystemContentDependencyMissing.as_str(), "ARGUS.V1.FILESYSTEM.CONTENT_DEPENDENCY_MISSING");
    assert_eq!(ErrorCode::ValidationContentRecognitionAmbiguous.as_str(), "ARGUS.V1.VALIDATION.CONTENT_RECOGNITION_AMBIGUOUS");
    assert_eq!(ErrorCode::OperationTransformationResourceLimitExceeded.as_str(), "ARGUS.V1.OPERATION.TRANSFORMATION_RESOURCE_LIMIT_EXCEEDED");
}
```

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-application --test transformation_contract --test content_contract
```

Expected: fail because the new types/errors and alternate representation registrations do not exist.

### Step 2: Add application-owned types

Create `transformation.rs` with closed, opaque vocabulary:

```rust
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct DerivedLocator(String);
impl DerivedLocator {
    pub fn from_transformation(value: String) -> Self { Self(value) }
    pub fn as_transformation_value(&self) -> &str { &self.0 }
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct DerivedEntryKey(String);
impl DerivedEntryKey {
    pub fn from_transformation(value: String) -> Self { Self(value) }
    pub fn as_transformation_value(&self) -> &str { &self.0 }
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct DerivedFingerprint(String);
impl DerivedFingerprint {
    pub fn from_transformation(value: String) -> Self { Self(value) }
    pub fn as_transformation_value(&self) -> &str { &self.0 }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DerivedScopeOutcome { Complete, Partial, Failed, Cancelled }

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransformationFailure {
    NotApplicable,
    UnsupportedFeature,
    Malformed,
    EncryptedUnsupported,
    MultiGameUnsupported,
    MissingDependency,
    AmbiguousRecognition,
    ResourceLimitExceeded,
    Cancelled,
    ReadFailure,
    SourceChanged,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransformationOutput {
    DerivedScope,
    TypedContent { platform: crate::PlatformId, content_type: crate::ContentType },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TransformationBudget {
    max_staged_bytes: u64,
    max_expanded_bytes: u64,
    max_derived_entries: u64,
    max_nesting_depth: u32,
    max_single_representation_bytes: u64,
    max_parser_work: u64,
}
```

`TransformationBudget::production()` must return the exact approved values. Use 64 GiB as the initial finite `max_parser_work`; this is enough for several full passes over the largest supported 8.5 GiB class optical media while remaining bounded. Keep the constructor public so tests can inject tiny budgets.

Define `DerivedEntryObservation` with `derived_locator`, `derived_entry_key`, `display_name`, `SourceEntryKind`, optional cheap size, and `derived_fingerprint`. Do not put parser-library types in it.

### Step 3: Generalize source-version evidence without breaking callers

Change `SourceVersionEvidence` to hold an explicit version kind:

```rust
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SourceVersionKind {
    Provider(Option<String>),
    Derived(DerivedFingerprint),
}

pub struct SourceVersionEvidence {
    source_entry_id: SourceEntryId,
    version: SourceVersionKind,
    last_observed_scan_id: ScanRunId,
}

impl SourceVersionEvidence {
    pub fn new(
        source_entry_id: SourceEntryId,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self::provider(source_entry_id, source_fingerprint, last_observed_scan_id)
    }

    pub fn provider(
        source_entry_id: SourceEntryId,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self {
            source_entry_id,
            version: SourceVersionKind::Provider(source_fingerprint),
            last_observed_scan_id,
        }
    }

    pub fn derived(
        source_entry_id: SourceEntryId,
        derived_fingerprint: DerivedFingerprint,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self {
            source_entry_id,
            version: SourceVersionKind::Derived(derived_fingerprint),
            last_observed_scan_id,
        }
    }

    pub fn version(&self) -> &SourceVersionKind { &self.version }
}
```

Retain `source_fingerprint()` as a compatibility accessor that returns only provider fingerprints; add `derived_fingerprint()` for derived evidence. Update exact version matching later rather than flattening derived evidence into the provider field.

### Step 4: Generalize `TransformationDescriptor`

Replace the assumption that every transformation directly yields typed content:

```rust
pub struct TransformationDescriptor {
    id: &'static str,
    revision: u32,
    representation: &'static str,
    output: TransformationOutput,
}
```

Register derived wrappers `zip`, `sevenzip`, `tar`, `gzip`, `bzip2`, `xz`, plus typed alternate optical transforms `chd-cd`, `chd-gd`, `chd-dvd`, `chd-umd`, `rvz`, `cso`, `wbfs`. Do **not** register `rar`.

Update the existing optical identity scheme descriptors to accept the BE-014 alternate representations while keeping scheme IDs/revisions unchanged:

```text
Sega CD/Saturn/PS1/PS2 CD: + chd-cd
Dreamcast: + chd-gd
PS2 DVD: + chd-dvd
PSP UMD: + cso + chd-umd
GameCube: + rvz
Wii: + rvz + wbfs
```

ZIP/7z/tar/gzip/bzip2/xz must **not** be accepted directly by an identity scheme; their inner recognized representation is what selects identity.

### Step 5: Add error codes/policies

Add the seven BE-012 codes to `ErrorCode`, `phase_003_all`, `as_str`, and `policy`. Use the severity/recovery policy already specified in BE-003: validation warnings are user-action/never-retry, dependency missing is filesystem error/user-initiated retry, transformation resource exhaustion is operation warning/user-initiated retry.

### Step 6: Run tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-application --test transformation_contract --test content_contract
cargo test --manifest-path rust/Cargo.toml -p argus-application
```

Expected: pass.

### Step 7: Commit/checkpoint

```bash
git add rust/crates/argus-application
git commit -m "feat: add derived transformation contracts"
```

---

## Task 2: Replace whole-entry reads with bounded range-readable source access

**Files:**
- Modify: `rust/crates/argus-application/src/sources/provider.rs`
- Modify: `rust/crates/argus-infrastructure/src/local_filesystem/mod.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_stream.rs`
- Modify: `rust/crates/argus-infrastructure/tests/local_filesystem_contract.rs`
- Modify: `rust/crates/argus-infrastructure/tests/content_recognition.rs`

### Step 1: Write failing range-read tests

Require a source to expose length plus bounded positional reads without allocating the whole file:

```rust
let mut read = access.open_entry_read(&root, &locator).expect("open read");
assert_eq!(read.len().expect("len"), 10 * 1024 * 1024);
let mut buf = [0_u8; 4096];
assert_eq!(read.read_at(8 * 1024 * 1024, &mut buf).expect("range"), buf.len());
```

Also test that a read request above the port's maximum is rejected and that opening a directory/link-like entry fails without following it.

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test local_filesystem_contract
```

Expected: fail because `open_entry_read` does not exist.

### Step 2: Introduce an application-owned read handle

In `provider.rs`:

```rust
pub trait SourceReadHandle: Send {
    fn len(&self) -> Result<u64, SourceAccessError>;
    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, SourceAccessError>;
    fn max_read_size(&self) -> usize { 64 * 1024 }
}

Add this method to the existing `LibrarySourceAccess` trait:

```rust
fn open_entry_read(
    &self,
    root: &ResolvedRoot,
    relative: &RelativeSourceLocator,
) -> Result<Box<dyn SourceReadHandle>, SourceAccessError>;
```

Keep the existing `read_entry_bytes` signature unchanged. Reimplement its body as a compatibility helper using `open_entry_read`, with this guard before allocation:

```rust
let mut read = self.open_entry_read(root, relative)?;
let len = read.len()?;
if len > max_bytes as u64 {
    return Err(SourceAccessError::InvalidResponse);
}
let mut bytes = vec![0_u8; len as usize];
read_exact_source(&mut *read, &mut bytes)?;
Ok(bytes)
```
```

The compatibility helper must reject `len > max_bytes` before allocation.

### Step 3: Implement LocalFilesystem positional reads

Use `std::fs::File` and platform-neutral `seek + read` behind the execution-scoped handle. The provider must keep no-follow admission semantics from the existing source graph and must not canonicalize a new path from user-controlled archive text.

```rust
struct LocalFileRead {
    file: std::fs::File,
    len: u64,
}

impl SourceReadHandle for LocalFileRead {
    fn len(&self) -> Result<u64, SourceAccessError> { Ok(self.len) }
    fn read_at(&mut self, offset: u64, destination: &mut [u8]) -> Result<usize, SourceAccessError> {
        use std::io::{Read, Seek, SeekFrom};
        if destination.len() > 64 * 1024 { return Err(SourceAccessError::InvalidResponse); }
        self.file.seek(SeekFrom::Start(offset)).map_err(|_| SourceAccessError::IoFailure)?;
        self.file.read(destination).map_err(|_| SourceAccessError::IoFailure)
    }
}
```

### Step 4: Adapt infrastructure `ContentReader`

Add a small adapter from `&mut dyn SourceReadHandle` to `ContentReader`; do not move filesystem concepts into the parser layer.

### Step 5: Run focused and regression tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test local_filesystem_contract --test content_recognition
cargo test --manifest-path rust/Cargo.toml -p argus-application
```

Expected: pass with previous `read_entry_bytes` callers still working.

### Step 6: Commit/checkpoint

```bash
git add rust/crates/argus-application/src/sources/provider.rs rust/crates/argus-infrastructure/src/local_filesystem rust/crates/argus-infrastructure/src/content_stream.rs rust/crates/argus-infrastructure/tests
git commit -m "refactor: add bounded source range reads"
```

---

## Task 3: Make derived `SourceEntry` coordinates durable

**Files:**
- Create: `rust/crates/argus-infrastructure/src/sqlite/migrations/sql/0014_derived_source_entries.sql`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/migrations/mod.rs`
- Modify: `rust/crates/argus-application/src/jobs.rs`
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/jobs.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/source_entries.rs`
- Modify: `rust/crates/argus-infrastructure/src/sqlite/logical.rs`
- Create: `rust/crates/argus-infrastructure/tests/migration_v14.rs`
- Create: `rust/crates/argus-infrastructure/tests/derived_source_entries.rs`

### Step 1: Write failing migration and repository tests

Seed a v13 database with provider-native source rows and logical provenance, upgrade to v14, and assert every old ID/relationship is byte-for-byte logically unchanged. Then insert/reconcile a derived child and assert provider-coordinate columns are NULL while derived fields are populated.

Require these repository behaviors:

```rust
let id1 = repo.upsert_derived(new_derived.clone())?;
let id2 = repo.upsert_derived(new_derived)?;
assert_eq!(id1, id2);

let found = repo.find_derived_child(
    parent_id,
    "argus.transformation.zip.v1",
    1,
    &DerivedEntryKey::from_transformation("member:game.gba".into()),
)?;
assert_eq!(found.unwrap().source_entry_id(), id1);
```

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test migration_v14 --test derived_source_entries
```

Expected: fail.

### Step 2: Rebuild `source_entry` with mutually exclusive coordinate families

Migration v14 should create `source_entry_new`, copy existing rows, then swap tables. Preserve all `source_entry_id` values. The invariant must be expressible in SQL:

```sql
CHECK (
    (
        coordinate_kind = 'provider'
        AND relative_locator IS NOT NULL
        AND locator_key IS NOT NULL
        AND derived_locator IS NULL
        AND derived_entry_key IS NULL
        AND derived_fingerprint IS NULL
        AND derivation_transformation_id IS NULL
        AND derivation_revision IS NULL
    ) OR (
        coordinate_kind = 'derived'
        AND relative_locator IS NULL
        AND locator_key IS NULL
        AND provider_native_identity IS NULL
        AND source_fingerprint IS NULL
        AND derived_locator IS NOT NULL
        AND derived_entry_key IS NOT NULL
        AND derived_fingerprint IS NOT NULL
        AND derivation_transformation_id IS NOT NULL
        AND derivation_revision > 0
    )
)
```

Indexes:

```sql
CREATE UNIQUE INDEX uq_source_entry_provider_locator
ON source_entry(library_root_id, locator_key)
WHERE coordinate_kind = 'provider';

CREATE UNIQUE INDEX uq_source_entry_derived_key
ON source_entry(parent_source_entry_id, derivation_transformation_id, derivation_revision, derived_entry_key)
WHERE coordinate_kind = 'derived';
```

Retain the parent/root indexes and provider-native identity candidate index.

### Step 3: Replace scalar source coordinates with an enum

Application record shape:

```rust
pub enum SourceEntryCoordinates {
    Provider {
        relative_locator: RelativeSourceLocator,
        locator_key: SourceLocatorKey,
        provider_native_identity: Option<String>,
        source_fingerprint: Option<String>,
    },
    Derived {
        derived_locator: DerivedLocator,
        derived_entry_key: DerivedEntryKey,
        derived_fingerprint: DerivedFingerprint,
        transformation_id: String,
        transformation_revision: u32,
    },
}
```

Update `NewSourceEntry` and `SourceEntryRecord` to own one `coordinates` value. Keep provider compatibility constructors/accessors for existing callers, but accessors that are provider-only must return `Option` rather than fabricate data.

Add this exact constructor to `NewSourceEntry`:

```rust
pub fn new_derived(
    source_entry_id: SourceEntryId,
    library_root_id: LibraryRootId,
    parent_source_entry_id: SourceEntryId,
    display_name: String,
    display_location: String,
    kind: SourceEntryKind,
    classification: SourceEntryClassification,
    derived_locator: DerivedLocator,
    derived_entry_key: DerivedEntryKey,
    derived_fingerprint: DerivedFingerprint,
    transformation_id: String,
    transformation_revision: u32,
    last_observed_scan_id: ScanRunId,
    created_at: i64,
    updated_at: i64,
) -> Self {
    Self {
        source_entry_id,
        library_root_id,
        parent_source_entry_id: Some(parent_source_entry_id),
        display_name,
        display_location,
        kind,
        classification,
        coordinates: SourceEntryCoordinates::Derived {
            derived_locator,
            derived_entry_key,
            derived_fingerprint,
            transformation_id,
            transformation_revision,
        },
        last_observed_scan_id,
        created_at,
        updated_at,
    }
}
```

Add repository methods:

```rust
fn upsert_derived(&mut self, entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError>;
fn find_derived_child(
    &mut self,
    parent: SourceEntryId,
    transformation_id: &str,
    revision: u32,
    key: &DerivedEntryKey,
) -> Result<Option<SourceEntryRecord>, PersistenceError>;
fn finalize_absent_derived_scope(
    &mut self,
    parent: SourceEntryId,
    transformation_id: &str,
    revision: u32,
    observation_run_id: ScanRunId,
) -> Result<u64, PersistenceError>;
```

Do not reuse `locator_key` for derived equality.

### Step 4: Update source-version matching

`sqlite/logical.rs::source_version_matches` must compare `SourceVersionKind::Provider` only to provider `source_fingerprint`, and `SourceVersionKind::Derived` only to derived fingerprint + current derived row. A kind mismatch is `false`, not an internal error.

### Step 5: Preserve hierarchy reads

Hierarchy projections continue to return display name/location/kind/classification for both entry kinds. They must not expose raw derived locator strings to Flutter. `display_location` remains a safe transformation-produced presentation path.

### Step 6: Run migration/repository regressions

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test migration_v14 --test derived_source_entries --test source_hierarchy --test logical_content_convergence
```

Expected: pass.

### Step 7: Commit/checkpoint

```bash
git add rust/crates/argus-application rust/crates/argus-infrastructure/src/sqlite rust/crates/argus-infrastructure/tests
git commit -m "feat: persist derived source entries"
```

---

## Task 4: Implement one cumulative `ParsingSession` with staging and cancellation

**Files:**
- Create: `rust/crates/argus-infrastructure/src/content_session.rs`
- Modify: `rust/crates/argus-infrastructure/src/content.rs`
- Modify: `rust/crates/argus-infrastructure/src/lib.rs`
- Modify: `rust/crates/argus-infrastructure/Cargo.toml`
- Create: `rust/crates/argus-infrastructure/tests/content_session.rs`
- Modify: `rust/crates/argus-runtime/src/runtime.rs`

### Step 1: Write failing budget/staging tests

Tests must prove that nested work shares counters and cleanup is deterministic:

```rust
let mut session = ParsingSession::for_tests(
    TransformationBudget::new(64, 96, 3, 2, 64, 128),
    staging_dir,
    || false,
);
session.charge_expanded(48)?;
session.enter_container()?;
session.charge_expanded(48)?;
assert_eq!(session.charge_expanded(1), Err(TransformationFailure::ResourceLimitExceeded));
```

Also prove:
- depth 3 fails when max depth is 2;
- fourth derived observation fails at max entries 3;
- staging above remaining staged budget fails before trusted handoff;
- cancellation interrupts a copy loop;
- dropping/finishing a session removes its operation directory;
- startup cleanup removes only recognized abandoned Argus staging directories, never arbitrary sibling paths.

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test content_session
```

Expected: fail.

### Step 2: Implement the session state machine

Core shape:

```rust
pub struct ParsingSession<'a> {
    budget: TransformationBudget,
    expanded_bytes: u64,
    staged_bytes: u64,
    derived_entries: u64,
    nesting_depth: u32,
    parser_work: u64,
    staging: SessionStaging,
    is_cancelled: &'a dyn Fn() -> bool,
}

impl ParsingSession<'_> {
    fn charge(counter: &mut u64, delta: u64, limit: u64) -> Result<(), TransformationFailure> {
        let next = counter
            .checked_add(delta)
            .ok_or(TransformationFailure::ResourceLimitExceeded)?;
        if next > limit {
            return Err(TransformationFailure::ResourceLimitExceeded);
        }
        *counter = next;
        Ok(())
    }

    pub fn charge_expanded(&mut self, bytes: u64) -> Result<(), TransformationFailure> {
        Self::charge(&mut self.expanded_bytes, bytes, self.budget.max_expanded_bytes())
    }

    pub fn charge_staged(&mut self, bytes: u64) -> Result<(), TransformationFailure> {
        Self::charge(&mut self.staged_bytes, bytes, self.budget.max_staged_bytes())
    }

    pub fn charge_derived_entry(&mut self) -> Result<(), TransformationFailure> {
        Self::charge(&mut self.derived_entries, 1, self.budget.max_derived_entries())
    }

    pub fn charge_parser_work(&mut self, units: u64) -> Result<(), TransformationFailure> {
        Self::charge(&mut self.parser_work, units, self.budget.max_parser_work())
    }

    pub fn with_container<T>(
        &mut self,
        f: impl FnOnce(&mut Self) -> Result<T, TransformationFailure>,
    ) -> Result<T, TransformationFailure> {
        let next_depth = self
            .nesting_depth
            .checked_add(1)
            .ok_or(TransformationFailure::ResourceLimitExceeded)?;
        if next_depth > self.budget.max_nesting_depth() {
            return Err(TransformationFailure::ResourceLimitExceeded);
        }
        self.nesting_depth = next_depth;
        let result = f(self);
        self.nesting_depth -= 1;
        result
    }

    pub fn check_cancelled(&self) -> Result<(), TransformationFailure> {
        if (self.is_cancelled)() {
            Err(TransformationFailure::Cancelled)
        } else {
            Ok(())
        }
    }
}
```

Use a guard so nesting depth is decremented on all return paths. Every counter uses `checked_add` and fails closed.

### Step 3: Implement staging

`SessionStaging` creates one random app-private operation directory below an Argus-owned staging root. A staged representation is created only through a method that:

1. checks the representation-length ceiling;
2. checks remaining staged budget;
3. queries/probes current available space through the runtime-owned staging root abstraction;
4. copies in bounded chunks while charging parser/staged work and checking cancellation;
5. flushes and reopens the completed file as immutable downstream input;
6. deletes partial output on every error.

The free-space seam should be an Argus trait so tests can deterministically return low-space without allocating GiB:

```rust
pub trait StagingSpaceProbe: Send + Sync {
    fn available_bytes(&self, staging_root: &std::path::Path) -> std::io::Result<u64>;
}
```

Production may use platform OS filesystem facts behind this trait; do not pull a decoder/native C library into the dependency graph for this purpose.

### Step 4: Integrate startup cleanup

Runtime startup should call one bounded cleanup routine before new transformation work. Recognize only directories carrying the Argus staging prefix plus valid marker file; ignore unrelated files.

### Step 5: Run tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test content_session
cargo test --manifest-path rust/Cargo.toml -p argus-runtime
```

Expected: pass.

### Step 6: Commit/checkpoint

```bash
git add rust/crates/argus-infrastructure rust/crates/argus-runtime
git commit -m "feat: add cumulative parsing sessions"
```

---

## Task 5: Implement safe generic wrapper enumeration

**Files:**
- Modify: `rust/Cargo.toml`
- Modify: `rust/Cargo.lock`
- Modify: `rust/crates/argus-infrastructure/Cargo.toml`
- Create: `rust/crates/argus-infrastructure/src/content_archive.rs`
- Modify: `rust/crates/argus-infrastructure/src/content.rs`
- Modify: `rust/crates/argus-infrastructure/src/content_stream.rs`
- Create: `rust/crates/argus-infrastructure/tests/archive_content.rs`

### Step 1: Add failing synthetic wrapper tests

Generate tiny fixtures at test time for:
- ZIP stored + deflate;
- 7z LZMA/LZMA2 and supported pure-Rust methods;
- tar regular file/directory members;
- gzip, bzip2, xz single-stream wrappers;
- traversal-like member names (`../`, absolute, drive-prefix-like, NUL/invalid forms);
- encrypted ZIP/7z;
- RAR magic;
- multipart/split signatures;
- declared-size and expansion-bomb budget failures.

Assert a successful wrapper returns `DerivedScopeOutcome::Complete` and observations, but no logical identity itself.

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test archive_content
```

Expected: fail.

### Step 2: Pin only permitted decoder dependencies

Use explicit feature selection. The production graph must contain no native decoder backend. The intended dependency shape is:

```toml
flate2 = { version = "1.1.9", default-features = false, features = ["rust_backend"] }
chd = { version = "0.3.4", default-features = false, features = ["verify_block_crc"] }
sevenz-rust2 = { version = "0.22.0", default-features = false, features = ["bzip2", "deflate", "ppmd", "util"] }
ruzstd = { version = "0.9.0", default-features = false }
oxiarc-bzip2 = { version = "0.4.1", default-features = false }
oxiarc-lzma = { version = "0.4.1", default-features = false }
```

For ZIP, keep `zip = 8.6.0` but change the workspace feature from unspecified `deflate` to `deflate-flate2` and enable only pure-Rust compression methods actually qualified by tests. Never enable ZIP `zstd` because it pulls the native `zstd` binding. Never enable `chd/max_perf`.

Do not add `tar`: implement the bounded read-only TAR subset in Argus so the no-C/C++-FFI dependency rule is unambiguous and archive paths are never unpacked.

### Step 3: Implement one infrastructure-private wrapper interface

```rust
pub struct DerivedScopeResult {
    observations: Vec<DerivedEntryObservation>,
    outcome: DerivedScopeOutcome,
    member_index: DerivedMemberIndex,
}

pub trait DerivedContainerDecoder {
    fn transformation_id(&self) -> &'static str;
    fn revision(&self) -> u32 { 1 }
    fn enumerate(
        &self,
        reader: &mut dyn ContentReader,
        parent_version: &SourceVersionEvidence,
        session: &mut ParsingSession<'_>,
    ) -> Result<DerivedScopeResult, TransformationFailure>;
}
```

`DerivedMemberIndex` is transient and transformation-owned; application/runtime can ask it to reopen an admitted member or resolve a relative companion reference, but generic code never parses `DerivedLocator`.

### Step 4: Normalize safe member presentation, not provider paths

For every archive member:
- parse the archive's own member coordinate;
- reject absolute roots, parent traversal, NUL, and invalid component forms;
- preserve the original logical member hierarchy only as transformation-owned coordinates/safe display segments;
- never call an `unpack` API and never write a member path beneath a user-supplied directory.

Derived fingerprint input must include parent `SourceVersionEvidence`, transform ID/revision, derived key, and version-relevant member metadata. Hash a canonical encoded tuple with BLAKE3 or SHA-256; do not use it as `ContentIdentity`.

### Step 5: Handle single-stream wrappers

Gzip/bzip2/xz expose exactly one derived child. Use stable transformation-owned key `stream:0`; derive display name by removing only the wrapper suffix for presentation, never for identity or platform selection. Charge every emitted byte to `expanded_bytes` and every decoder step/chunk to parser work.

### Step 6: RAR/encryption/multipart failure mapping

Detect these before any authoritative derived materialization:

```rust
match probe_wrapper(header) {
    WrapperProbe::Rar | WrapperProbe::SplitArchive => Err(TransformationFailure::UnsupportedFeature),
    WrapperProbe::Encrypted => Err(TransformationFailure::EncryptedUnsupported),
    WrapperProbe::Supported(kind) => {
        decode_supported_wrapper(kind, reader, parent_version, session)
    },
    WrapperProbe::NotApplicable => Err(TransformationFailure::NotApplicable),
}
```

No password callback exists anywhere in the API.

### Step 7: Remove supported wrappers from `is_blocked_container`

Keep RAR/multipart explicitly unsupported, but route ZIP/7z/tar/gzip/bzip2/xz through the registered derived-container path instead of the old blanket block.

### Step 8: Verify dependency graph and tests

```bash
cargo tree --manifest-path rust/Cargo.toml -p argus-infrastructure -e normal
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test archive_content --test content_recognition
```

Inspect the normal dependency tree and fail the task if it contains `zstd-sys`, `libz-sys`, `libz-ng-sys`, `lzma-sys`, `bzip2-sys`, libchdr bindings, or another native decoder dependency.

### Step 9: Commit/checkpoint

```bash
git add rust/Cargo.toml rust/Cargo.lock rust/crates/argus-infrastructure
git commit -m "feat: add bounded archive transformations"
```

---

## Task 6: Reconcile derived scopes and enforce single-game archive admission

**Files:**
- Create: `rust/crates/argus-application/src/sources/derived.rs`
- Modify: `rust/crates/argus-application/src/sources/mod.rs`
- Modify: `rust/crates/argus-application/src/sources/scan.rs`
- Modify: `rust/crates/argus-application/src/optical.rs`
- Modify: `rust/crates/argus-application/src/logical.rs`
- Modify: `rust/crates/argus-runtime/src/runtime.rs`
- Create: `rust/crates/argus-application/tests/derived_reconciliation.rs`
- Create: `rust/crates/argus-infrastructure/tests/archive_library_convergence.rs`

### Step 1: Write failing reconciliation/admission tests

Cover these exact cases:

```text
game.zip -> game.gba                         accepted
sidecars.zip -> game.gba + README + cover   accepted
ps1.7z -> game.cue + track01.bin            accepted as one content family
multi.7z -> game.m3u + disc1.cue/bin + disc2.cue/bin accepted one release
collection.zip -> mario.nes + zelda.nes     MULTI_GAME_CONTAINER_UNSUPPORTED, zero GameContent from archive
nested.zip -> inner.7z -> game.gba           accepted while sharing one budget
```

Persistence tests must show all safe members remain derived `SourceEntry`s even for the rejected collection.

Also prove a failed/cancelled nested scope cannot cause absence deletion in its parent/child exact scope.

### Step 2: Add application-owned derived reconciliation

Create a coordinator around `SourceEntryRepository`:

```rust
pub struct DerivedScopeIdentity<'a> {
    pub parent_source_entry_id: SourceEntryId,
    pub transformation_id: &'a str,
    pub transformation_revision: u32,
}

pub fn reconcile_derived_scope(
    entries: &mut impl SourceEntryRepository,
    scope: &DerivedScopeIdentity<'_>,
    observations: &[DerivedEntryObservation],
    observation_run_id: ScanRunId,
    stable_input: bool,
    outcome: DerivedScopeOutcome,
) -> Result<Vec<SourceEntryId>, PersistenceError>;
```

Positive observations may be upserted only from validated immutable/stable bytes. `finalize_absent_derived_scope` is called only for `stable_input && outcome == Complete`.

### Step 3: Compose derived traversal in runtime without leaking `ParsingSession`

Do not teach the filesystem provider about archives and do not put an infrastructure session type in application APIs. The production refresh/runtime composition owns one concrete `ParsingSession` for the source-processing attempt and loops over application-owned reconciliation plus infrastructure-owned decoding:

```rust
let mut pending = vec![provider_source_entry];
while let Some(entry) = pending.pop() {
    session.check_cancelled().map_err(map_transformation_failure)?;
    let Some(scope_result) = container_engine.enumerate_if_supported(&entry, &mut session)? else {
        continue;
    };

    let reconciled = unit_of_work_factory.in_unit_of_work(|scope| {
        reconcile_derived_scope(
            &mut scope.source_entries(),
            &scope_result.scope_identity,
            &scope_result.observations,
            scan_run_id,
            scope_result.stable_input,
            scope_result.outcome,
        )
    })?;

    for child in reconciled.into_iter().rev() {
        if child.classification() == SourceEntryClassification::Container {
            pending.push(child);
        }
    }
}
```

`container_engine` is infrastructure-private and receives the concrete session, so it can stage safely. Application code still owns `reconcile_derived_scope`, exact-scope absence policy, and later archive eligibility. Derived directories are source-graph nodes only; they are not handed to `LibrarySourceAccess`.

### Step 4: Generalize optical dependency admission for derived scopes

Keep `resolve_optical_dependencies` application-owned. Add a coordinate-neutral candidate abstraction rather than converting derived members into `RelativeSourceLocator`:

```rust
pub struct ContentDependencyCandidate {
    source: SourceEntryRecord,
    scope_reference: String,
}

pub fn resolve_content_dependencies(
    descriptor_reference: &str,
    references: &[String],
    candidates: &[ContentDependencyCandidate],
) -> Result<Vec<SourceEntryRecord>, OpticalDependencyError>;
```

Provider-native callers construct `scope_reference` from provider-supplied discovery facts; derived-container callers construct it from the transformation-owned safe member index. The resolver validates normalized relative references but never parses a provider or `DerivedLocator` token.

### Step 5: Enforce archive-level single-game policy before convergence

Collect validated content-family candidates for one outer generic archive. The application rule is:

```rust
match independently_usable_families.len() {
    0 => ArchiveEligibility::NoSupportedGame,
    1 => ArchiveEligibility::SingleGame(independently_usable_families.remove(0)),
    _ => return Err(application_error(
        ErrorCode::ValidationMultiGameContainerUnsupported,
        context.trace_id(),
    )),
}
```

Treat CUE + required tracks as one family; treat M3U-linked already-valid disc families as one release eligibility decision while each disc still converges separately. Sidecars never become families merely because they are files.

Do not call `IdentificationService::converge` for any family until the whole bounded archive traversal has established the one-game rule.

### Step 6: Run tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-application --test derived_reconciliation --test optical_contract
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test archive_library_convergence --test scan_reconciliation --test logical_content_convergence
```

Expected: pass.

### Step 7: Commit/checkpoint

```bash
git add rust/crates/argus-application rust/crates/argus-infrastructure/tests rust/crates/argus-runtime
git commit -m "feat: reconcile derived container scopes"
```

---

## Task 7: Add CHD media adapters that feed existing optical canonicalization

**Files:**
- Create: `rust/crates/argus-infrastructure/src/content_chd.rs`
- Modify: `rust/crates/argus-infrastructure/src/content.rs`
- Modify: `rust/crates/argus-infrastructure/Cargo.toml`
- Create: `rust/crates/argus-infrastructure/tests/chd_content.rs`
- Modify: `rust/crates/argus-infrastructure/tests/optical_content.rs`

### Step 1: Write synthetic convergence tests first

Create minimal CHDs during tests from fabricated media if the crate's writer/test helper permits; otherwise embed only repository-generated tiny fixture bytes with provenance comments. Required comparisons:

```rust
assert_eq!(native_cd.identity_digest(), chd_cd.identity_digest());
assert_eq!(native_gd.identity_digest(), chd_gd.identity_digest());
assert_eq!(native_ps2_dvd.identity_digest(), chd_dvd.identity_digest());
assert_eq!(native_psp_umd.identity_digest(), chd_umd.identity_digest());
```

Negative fixtures: wrong CHD media metadata, missing required GD high-density structure, contradictory track geometry, truncated hunks, cancellation, and tiny parser-work budget.

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test chd_content
```

Expected: fail.

### Step 2: Adapt `chd` behind Argus types

Do not expose `chd::*` from `argus-infrastructure::content`. Keep the public result `OpticalRecognition`.

```rust
pub fn recognize_chd(
    reader: &mut dyn ContentReader,
    session: &mut ParsingSession<'_>,
) -> Result<OpticalRecognition, OpticalError>;
```

If the CHD crate requires `Read + Seek`, stage the validated parent source through `ParsingSession` and give the crate only the staged file.

### Step 3: Reconstruct BE-014 media envelopes exactly

- CD: translate CHD track metadata into the same track ordering/mode/pregap sector feed used by `canonicalize_descriptor_with_cancel`; distinguish stored `INDEX 00` bytes from synthesized pregap.
- GD: require complete Dreamcast low/high-density session metadata and feed the same GD envelope.
- DVD/UMD: expose exactly 2048-byte logical sectors to the existing PS2 DVD/PSP UMD canonical reader.

Do not infer media type from `.chd`, folder, or caller platform.

### Step 4: Charge work/cancellation

For every hunk/sector decoded:

```rust
session.check_cancelled().map_err(map_session_to_optical)?;
session.charge_parser_work(decoded_len as u64).map_err(map_session_to_optical)?;
```

A failed hunk never yields partial identity.

### Step 5: Run tests/regressions

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test chd_content --test optical_content
```

Expected: pass.

### Step 6: Commit/checkpoint

```bash
git add rust/crates/argus-infrastructure
git commit -m "feat: decode chd optical representations"
```

---

## Task 8: Add PSP CSO exact-sector decoding

**Files:**
- Create: `rust/crates/argus-infrastructure/src/content_cso.rs`
- Modify: `rust/crates/argus-infrastructure/src/content.rs`
- Create: `rust/crates/argus-infrastructure/tests/cso_content.rs`

### Step 1: Write failing ISO/CSO convergence tests

Create a fabricated PSP UMD ISO stream and a CSO representation of the same sectors. Test compressed and plain blocks, index alignment, EOF, truncation, impossible index order, cancellation, and budget exhaustion.

Run:

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test cso_content
```

Expected: fail.

### Step 2: Implement the bounded CSO parser

Read and validate `CISO` header fields, block size, alignment shift, total bytes, and complete block index before decoding payload. Use checked arithmetic only.

Core flow:

```rust
for block in 0..block_count {
    session.check_cancelled()?;
    let start = index[block] & 0x7fff_ffff;
    let end = index[block + 1] & 0x7fff_ffff;
    let plain = (index[block] & 0x8000_0000) != 0;
    let sector = if plain {
        read_exact_block(reader, start << align, block_size)?
    } else {
        inflate_raw_deflate(reader, start << align, end << align, block_size, session)?
    };
    canonical_umd_hasher.update(&sector);
}
```

Reject a decoded block whose length is not the exact expected logical block length. Feed output into the existing PSP UMD canonical envelope, never hash CSO indexes/header.

### Step 3: Run tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test cso_content --test optical_content
```

Expected: pass.

### Step 4: Commit/checkpoint

```bash
git add rust/crates/argus-infrastructure
git commit -m "feat: decode psp cso images"
```

---

## Task 9: Add RVZ exact reconstruction and WBFS sparse-disc decoding

**Files:**
- Create: `rust/crates/argus-infrastructure/src/content_rvz.rs`
- Create: `rust/crates/argus-infrastructure/src/content_wbfs.rs`
- Modify: `rust/crates/argus-infrastructure/src/content.rs`
- Modify: `rust/crates/argus-infrastructure/Cargo.toml`
- Create: `rust/crates/argus-infrastructure/tests/rvz_content.rs`
- Create: `rust/crates/argus-infrastructure/tests/wbfs_content.rs`
- Modify: `rust/crates/argus-infrastructure/tests/optical_content.rs`

### Step 1: Write RVZ convergence and rejection tests

Use minimal fabricated GameCube and Wii logical discs. Generate deterministic RVZ fixtures with only codecs that the production pure-Rust path supports. Prove:

```rust
assert_eq!(raw_gamecube.identity_digest(), rvz_gamecube.identity_digest());
assert_eq!(raw_wii.identity_digest(), rvz_wii.identity_digest());
```

Negative cases: missing required data, invalid chunk map, corrupted hash/checksum if present, impossible offsets/sizes, unsupported lossy/non-reconstructable form, cancellation, work/expansion budget exhaustion.

### Step 2: Implement RVZ container parsing in Argus-owned safe Rust

Do **not** add `nod` as a production dependency because its current normal compression stack includes native-backed `zstd`/`liblzma`/older bzip2 options. Implement the WIA/RVZ structural reader needed by BE-014 and use pure-Rust codecs:

```rust
enum RvzCodec { None, Purge, Bzip2, Lzma2, Zstd }

fn decode_rvz_group(
    codec: RvzCodec,
    compressed: &[u8],
    expected_len: usize,
    session: &mut ParsingSession<'_>,
) -> Result<Vec<u8>, OpticalError> {
    session.charge_parser_work(compressed.len() as u64)?;
    let decoded = match codec {
        RvzCodec::None | RvzCodec::Purge => decode_uncompressed_or_purge(compressed, expected_len)?,
        RvzCodec::Bzip2 => decode_oxiarc_bzip2(compressed, expected_len)?,
        RvzCodec::Lzma2 => decode_oxiarc_lzma2(compressed, expected_len)?,
        RvzCodec::Zstd => decode_ruzstd(compressed, expected_len)?,
    };
    session.charge_expanded(decoded.len() as u64)?;
    if decoded.len() != expected_len { return Err(OpticalError::Truncated); }
    Ok(decoded)
}
```

The structural decoder must reconstruct all canonical bytes required for GameCube/complete Wii before recognition. If RVZ metadata indicates a representation from which those bytes cannot be reconstructed exactly, return `UnsupportedRepresentation` rather than filling gaps.

### Step 3: Write WBFS tests before implementation

Create two WBFS containers with identical allocation extents/bytes but different irrelevant container metadata and assert equal sparse identity. Create a third with a changed preserved byte and assert different identity. Prove scrubbed WBFS does not equal complete raw/RVZ merely because missing extents would be zeros.

### Step 4: Implement WBFS sparse extent reader

Validate header geometry, disc table, WLBA table, block bounds, and non-overlap with checked arithmetic. Build an ordered list of logical extents that are actually present:

```rust
struct PreservedExtent { logical_offset: u64, byte_len: u64, physical_offset: u64 }

for extent in validated_extents {
    sparse_hasher.update_extent_header(extent.logical_offset, extent.byte_len);
    hash_reader_range(reader, extent.physical_offset, extent.byte_len, &mut sparse_hasher, session)?;
}
```

Use the existing BE-014 Wii sparse envelope prefix/encoding from `content_optical.rs` (factor a helper out if necessary). Do not decrypt, infer filesystem use, synthesize absent data, or hash WBFS allocation structures as game payload.

### Step 5: Run RVZ/WBFS tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test rvz_content --test wbfs_content --test optical_content
```

Expected: pass.

### Step 6: Re-run dependency audit

```bash
cargo tree --manifest-path rust/Cargo.toml -p argus-infrastructure -e normal
```

Expected: no production native decoder/sys library introduced by RVZ/WBFS work.

### Step 7: Commit/checkpoint

```bash
git add rust/crates/argus-infrastructure rust/Cargo.toml rust/Cargo.lock
git commit -m "feat: decode rvz and wbfs media"
```

---

## Task 10: Reopen provider/derived bytes through one transformation graph and wire production refresh

**Files:**
- Create: `rust/crates/argus-infrastructure/src/content_source.rs`
- Modify: `rust/crates/argus-infrastructure/src/content.rs`
- Modify: `rust/crates/argus-runtime/src/runtime.rs`
- Modify: `rust/crates/argus-runtime/src/lib.rs`
- Modify: `rust/crates/argus-application/src/phase_003.rs`
- Modify: `rust/crates/argus-application/src/content.rs`
- Create: `rust/crates/argus-infrastructure/tests/transformation_graph.rs`
- Modify: `rust/crates/argus-infrastructure/tests/logical_content_convergence.rs`

### Step 1: Write failing nested/reopen tests

Persist this chain and prove a later identification attempt can reopen it without trusting a stale staged file:

```text
provider source.zip
  -> derived inner.7z
      -> derived game.gba
```

Mutation of `source.zip` after enumeration must make the current derived proof fail `SOURCE_CHANGED_DURING_PROCESSING` rather than reuse old staged bytes.

### Step 2: Add one source resolver

Infrastructure resolver input is a `SourceEntryRecord` plus the provider access/root and current session. It recursively walks parent `SourceEntryId` relationships from persistence, opens the nearest provider-native ancestor through `LibrarySourceAccess`, then replays each registered transformation using the persisted transformation ID/revision + opaque `DerivedLocator`.

```rust
pub trait ContentSourceResolver {
    fn open<'a>(
        &'a self,
        entry: &SourceEntryRecord,
        session: &'a mut ParsingSession<'_>,
    ) -> Result<Box<dyn ContentReader + 'a>, TransformationFailure>;
}
```

Never persist a staged path. Never interpret a derived locator outside its owning decoder.

### Step 3: Wire the registry into composed refresh

Production runtime should use one `TransformationRegistry::production()` for:
- deciding whether a source is a derived container or typed representation;
- enumerating supported generic wrappers;
- reopening derived children;
- dispatching alternate optical decoders;
- selecting the existing identity scheme after canonical recognition.

Remove the old supported-container blanket rejection in `content_stream`; RAR remains an explicit unsupported probe.

### Step 4: Ensure identity catalog selection uses decoded representation

Examples:

```rust
catalog.select_identity(PlatformId::SonyPsp, ContentType::OpticalDiscUmd, "cso", digest)
catalog.select_identity(PlatformId::NintendoWii, ContentType::OpticalDiscWii, "rvz", digest)
```

Generic archive wrapping does not change that representation string; `game.gba` inside ZIP still selects the GBA raw-cartridge scheme.

### Step 5: Run tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test transformation_graph --test logical_content_convergence
cargo test --manifest-path rust/Cargo.toml -p argus-runtime
```

Expected: pass.

### Step 6: Commit/checkpoint

```bash
git add rust/crates/argus-infrastructure rust/crates/argus-runtime rust/crates/argus-application
git commit -m "feat: wire container transformations into refresh"
```

---

## Task 11: Prove lifecycle, absence authority, cancellation, and cleanup end to end

**Files:**
- Create: `rust/crates/argus-infrastructure/tests/container_lifecycle.rs`
- Modify: `rust/crates/argus-infrastructure/tests/reconciliation.rs`
- Modify: `rust/crates/argus-infrastructure/tests/scan_reconciliation.rs`
- Modify: `rust/crates/argus-infrastructure/tests/logical_content_convergence.rs`
- Modify: `rust/crates/argus-application/tests/phase_003_jobs.rs`

### Step 1: Write lifecycle scenarios

Prove all of the following with real SQLite UoW state:

1. unchanged archive refresh preserves derived `SourceEntryId`, `GameContentId`, `GameId`, identity, and enrichment;
2. complete stable re-enumeration removes a vanished derived child and triggers the existing provenance/re-identification/orphan path;
3. failed/cancelled/budget-exhausted/changed re-enumeration preserves prior children from absence deletion;
4. outer source removal removes the derived subtree and exact current provenance coherently in one source-removal mutation;
5. returning equivalent content reconnects only after fresh canonical identity proof, not from matching derived locator/key;
6. cancellation deletes partial staging and terminalizes the owning durable job correctly;
7. a malformed/encrypted/multi-game archive produces a scoped issue while unrelated refresh work completes.

### Step 2: Add stable failure mapping assertions

Every parser/session failure maps before crossing the application boundary:

```rust
assert_eq!(map_failure(TransformationFailure::Malformed), ErrorCode::ValidationContentMalformed);
assert_eq!(map_failure(TransformationFailure::EncryptedUnsupported), ErrorCode::ValidationContentEncryptedUnsupported);
assert_eq!(map_failure(TransformationFailure::ResourceLimitExceeded), ErrorCode::OperationTransformationResourceLimitExceeded);
```

RAR and multipart input map to `ValidationContentUnsupportedRepresentation`.

### Step 3: Run lifecycle tests

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support --test container_lifecycle --test reconciliation --test scan_reconciliation --test logical_content_convergence
cargo test --manifest-path rust/Cargo.toml -p argus-application --test phase_003_jobs
```

Expected: pass.

### Step 4: Commit/checkpoint

```bash
git add rust/crates/argus-application/tests rust/crates/argus-infrastructure/tests
git commit -m "test: prove container lifecycle semantics"
```

---

## Task 12: Complete matrix qualification and repository validation

**Files:**
- Modify as needed only within the already-touched Rust test modules and dependency manifests.
- Do not modify the approved governing specs unless a genuine spec defect is discovered and owner approval is obtained first.

### Step 1: Add one explicit production matrix test

The test should enumerate the exact P03-006 advertised representations and prove RAR is absent:

```rust
let supported = [
    "zip", "sevenzip", "tar", "gzip", "bzip2", "xz",
    "chd-cd", "chd-gd", "chd-dvd", "chd-umd", "rvz", "cso", "wbfs",
];
for representation in supported {
    assert!(TransformationRegistry::production().supports(representation));
}
assert!(!TransformationRegistry::production().supports("rar"));
```

Also assert all current identity scheme IDs and revisions remain exactly unchanged from pre-P03-006 expectations.

### Step 2: Run all focused Rust suites

```bash
cargo test --manifest-path rust/Cargo.toml -p argus-application
cargo test --manifest-path rust/Cargo.toml -p argus-infrastructure --features test-support
cargo test --manifest-path rust/Cargo.toml -p argus-runtime
cargo test --manifest-path rust/Cargo.toml -p argus-bridge
```

Expected: all pass.

### Step 3: Dependency safety audit

```bash
cargo tree --manifest-path rust/Cargo.toml -p argus-infrastructure -e normal
```

Fail completion if the production tree includes a decoder path through `zstd-sys`, `libz-sys`, `libz-ng-sys`, `lzma-sys`, `bzip2-sys`, libchdr/native archive bindings, unrar, or an external-executable wrapper. `chd` must remain on its pure-Rust default path with `max_perf` disabled.

### Step 4: Architecture search

Verify no parser library type leaked into application/domain public APIs and no derived locator is stored in provider fields. Use repository search for decoder crate names outside `argus-infrastructure` and for writes to `relative_locator` on derived-row paths.

### Step 5: Run repository validation

```bash
just check
```

Expected: full repository validation passes, including Rust, Flutter, generated bridge/source checks, lint/format, migrations, schemas, and tests.

### Step 6: Verification-before-completion review

Before completion, re-read the approved design acceptance section and produce concrete evidence for:
- every generic wrapper;
- single-game/multi-game behavior;
- nested shared budgets;
- derived reconciliation/absence authority;
- CHD/CSO/RVZ/WBFS convergence/rejection rules;
- source mutation/cancellation/staging cleanup;
- migration preservation;
- RAR/encrypted/multipart exclusions;
- unchanged native cartridge/optical identities.

No criterion may be marked passed from code inspection alone when a deterministic test can prove it.

### Step 7: Commit/checkpoint

```bash
git add rust
git commit -m "feat: complete container representation coverage"
```

## Plan Self-Review

- **Spec coverage:** every approved wrapper/alternate media representation, derived persistence invariant, one-game archive rule, nesting/resource policy, staging/cancellation rule, RAR/encryption/multipart exclusion, migration requirement, and convergence requirement has an implementation/test task.
- **No placeholders:** all implementation decisions needed by this plan are resolved. The parser-work production ceiling is fixed at 64 GiB; test budgets are injectable.
- **Type consistency:** provider and derived coordinate/version evidence remain distinct; `SourceEntryId` remains the common durable graph identity; generic wrappers never enter `IdentitySchemeCatalog` directly; alternate optical representations select existing scheme IDs.
- **Isolation:** format libraries are infrastructure-private; application owns admission/reconciliation/policy; runtime only composes; persistence stores opaque transformation coordinates without interpreting them.
- **Scope:** no RAR, password workflow, multipart archives, new Library UX, or physical-device qualification is included.
