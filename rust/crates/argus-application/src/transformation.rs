//! Application-owned vocabulary for transient transformations and derived source facts.

use crate::sources::SourceEntryKind;

/// Opaque locator for one transformation-produced source member.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct DerivedLocator(String);

impl DerivedLocator {
    /// Wraps a value produced by the owning transformation adapter.
    pub fn from_transformation(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque value for the owning transformation adapter.
    pub fn as_transformation_value(&self) -> &str {
        &self.0
    }
}

/// Stable transformation-owned key for one member within a derived scope.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct DerivedEntryKey(String);

impl DerivedEntryKey {
    /// Wraps a key produced by the owning transformation adapter.
    pub fn from_transformation(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque value for the owning transformation adapter.
    pub fn as_transformation_value(&self) -> &str {
        &self.0
    }
}

/// Cheap version evidence for one derived source member.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct DerivedFingerprint(String);

impl DerivedFingerprint {
    /// Wraps a fingerprint produced by the owning transformation adapter.
    pub fn from_transformation(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque value for persistence and version comparison.
    pub fn as_transformation_value(&self) -> &str {
        &self.0
    }
}

/// Terminal state of one derived-scope observation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DerivedScopeOutcome {
    /// The complete scope was read from validated stable input.
    Complete,
    /// Some observations were produced, but absence cannot be trusted.
    Partial,
    /// Processing failed before a complete scope was established.
    Failed,
    /// Processing stopped because cancellation was accepted.
    Cancelled,
}

/// Failure categories that infrastructure transformations map at the boundary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransformationFailure {
    /// The input is not handled by this transformation.
    NotApplicable,
    /// The input uses an intentionally unsupported feature or representation.
    UnsupportedFeature,
    /// The input violates the representation grammar.
    Malformed,
    /// The input requires a password or unavailable encryption support.
    EncryptedUnsupported,
    /// The input contains more than one independently usable game.
    MultiGameUnsupported,
    /// A required companion member is absent or invalid.
    MissingDependency,
    /// Recognition produced more than one authoritative candidate.
    AmbiguousRecognition,
    /// A cumulative transformation ceiling was exceeded.
    ResourceLimitExceeded,
    /// The owning operation accepted cancellation.
    Cancelled,
    /// Source access failed while reading or decoding.
    ReadFailure,
    /// Source version evidence changed during processing.
    SourceChanged,
}

/// Kind of durable or transient output produced by a transformation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TransformationOutput {
    /// The transformation produces persistent derived source observations.
    DerivedScope,
    /// The transformation produces typed content for an existing identity scheme.
    TypedContent {
        /// Platform established by the transformation's validated media contract.
        platform: crate::PlatformId,
        /// Content class established by the transformation's validated media contract.
        content_type: crate::ContentType,
    },
}

/// Fixed safety ceilings shared by every nested transformation in one operation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TransformationBudget {
    max_single_representation_bytes: u64,
    max_expanded_bytes: u64,
    max_derived_entries: u64,
    max_nesting_depth: u32,
    max_staged_bytes: u64,
    max_parser_work: u64,
}

impl TransformationBudget {
    /// Creates an explicit budget, primarily allowing small deterministic test limits.
    pub const fn new(
        max_single_representation_bytes: u64,
        max_expanded_bytes: u64,
        max_derived_entries: u64,
        max_nesting_depth: u32,
        max_staged_bytes: u64,
        max_parser_work: u64,
    ) -> Self {
        Self {
            max_single_representation_bytes,
            max_expanded_bytes,
            max_derived_entries,
            max_nesting_depth,
            max_staged_bytes,
            max_parser_work,
        }
    }

    /// Returns the fixed production safety envelope.
    pub const fn production() -> Self {
        Self::new(
            16 * 1024 * 1024 * 1024,
            32 * 1024 * 1024 * 1024,
            65_536,
            4,
            16 * 1024 * 1024 * 1024,
            64 * 1024 * 1024 * 1024,
        )
    }

    /// Returns the maximum size of one source representation.
    pub const fn max_single_representation_bytes(self) -> u64 {
        self.max_single_representation_bytes
    }

    /// Returns the maximum cumulative expanded output.
    pub const fn max_expanded_bytes(self) -> u64 {
        self.max_expanded_bytes
    }

    /// Returns the maximum cumulative derived-entry count.
    pub const fn max_derived_entries(self) -> u64 {
        self.max_derived_entries
    }

    /// Returns the maximum nested transformation depth.
    pub const fn max_nesting_depth(self) -> u32 {
        self.max_nesting_depth
    }

    /// Returns the maximum cumulative staged bytes.
    pub const fn max_staged_bytes(self) -> u64 {
        self.max_staged_bytes
    }

    /// Returns the maximum cumulative parser work units.
    pub const fn max_parser_work(self) -> u64 {
        self.max_parser_work
    }
}

/// One safely enumerated transformation-produced source member.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DerivedEntryObservation {
    derived_locator: DerivedLocator,
    derived_entry_key: DerivedEntryKey,
    display_name: String,
    display_location: String,
    kind: SourceEntryKind,
    cheap_size: Option<u64>,
    derived_fingerprint: DerivedFingerprint,
}

impl DerivedEntryObservation {
    /// Creates one observation without exposing parser-library types.
    pub fn new(
        derived_locator: DerivedLocator,
        derived_entry_key: DerivedEntryKey,
        display_name: String,
        kind: SourceEntryKind,
        cheap_size: Option<u64>,
        derived_fingerprint: DerivedFingerprint,
    ) -> Self {
        Self {
            derived_locator,
            derived_entry_key,
            display_location: display_name.clone(),
            display_name,
            kind,
            cheap_size,
            derived_fingerprint,
        }
    }

    /// Sets the safe scope-relative display location while retaining the
    /// concise display name used by hierarchy rows.
    pub fn with_display_location(mut self, display_location: String) -> Self {
        self.display_location = display_location;
        self
    }

    /// Returns the transformation-owned member locator.
    pub fn derived_locator(&self) -> &DerivedLocator {
        &self.derived_locator
    }

    /// Returns the stable key within the containing transformation scope.
    pub fn derived_entry_key(&self) -> &DerivedEntryKey {
        &self.derived_entry_key
    }

    /// Returns the safe presentation name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the safe scope-relative display location used for companion
    /// dependency admission.
    pub fn display_location(&self) -> &str {
        &self.display_location
    }

    /// Returns the observed source-entry kind.
    pub const fn kind(&self) -> SourceEntryKind {
        self.kind
    }

    /// Returns the bounded member size when the format provides one.
    pub const fn cheap_size(&self) -> Option<u64> {
        self.cheap_size
    }

    /// Returns the cheap transformation-owned version evidence.
    pub fn derived_fingerprint(&self) -> &DerivedFingerprint {
        &self.derived_fingerprint
    }
}
