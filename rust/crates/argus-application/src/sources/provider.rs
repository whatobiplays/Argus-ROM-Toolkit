//! Source-provider boundary contracts owned by the application.
//!
//! These types are provider-facing normalized vocabulary. Generic application
//! code may transport them through the provider port but must never parse,
//! normalize, compare, or infer filesystem semantics from provider-owned
//! values such as [`RootLocator`] or [`LocalFilesystemRootSelection`].

/// Stable provider implementation family.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceProviderType {
    /// The local desktop filesystem provider family.
    LocalFilesystem,
}

impl SourceProviderType {
    /// Returns the canonical serialized provider-family value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::LocalFilesystem => "local_filesystem",
        }
    }
}

impl TryFrom<&str> for SourceProviderType {
    type Error = SourceProviderTypeError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "local_filesystem" => Ok(Self::LocalFilesystem),
            _ => Err(SourceProviderTypeError),
        }
    }
}

/// Failure while parsing a provider-family value.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SourceProviderTypeError;

/// Opaque provider-owned coordinate of one configured library root.
///
/// Only the owning source provider interprets the enclosed value. Generic
/// application, persistence, bridge, and Flutter code must treat it as an
/// opaque token.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct RootLocator(String);

impl RootLocator {
    /// Wraps a provider-produced opaque locator value.
    pub fn from_provider(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque provider value for persistence/transport only.
    ///
    /// This accessor exists for the owning provider adapter and persistence
    /// boundary; callers must not interpret the returned text.
    pub fn as_provider_value(&self) -> &str {
        &self.0
    }
}

/// Untrusted typed local-folder selection supplied by the native picker seam.
///
/// The selected folder path is request input only. Flutter and generic
/// application code must not normalize, canonicalize, split, compare, or
/// derive identity/overlap semantics from it; the LocalFilesystem provider
/// owns all filesystem interpretation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemRootSelection {
    selected_folder_path: String,
}

impl LocalFilesystemRootSelection {
    /// Creates a typed selection from the raw picker-provided path string.
    pub fn new(selected_folder_path: String) -> Self {
        Self {
            selected_folder_path,
        }
    }

    /// Returns the raw provider input path string.
    pub fn selected_folder_path(&self) -> &str {
        &self.selected_folder_path
    }
}

/// Provider-owned relationship between two configured root locators.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RootRelationship {
    /// The two locators address the same root.
    Same,
    /// The first locator contains the second as a proper descendant scope.
    Ancestor,
    /// The first locator is contained by the second as a proper descendant.
    Descendant,
    /// The provider proved the locators address disjoint scopes.
    Disjoint,
    /// The provider could not establish the relationship reliably.
    Unknown,
}

impl RootRelationship {
    /// Returns the canonical serialized relationship value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Same => "same",
            Self::Ancestor => "ancestor",
            Self::Descendant => "descendant",
            Self::Disjoint => "disjoint",
            Self::Unknown => "unknown",
        }
    }
}

/// Provider result after validating one local-folder selection.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ValidatedLocalRoot {
    locator: RootLocator,
    display_name: String,
    safe_location_presentation: String,
}

impl ValidatedLocalRoot {
    /// Creates the validated root descriptor from provider-owned facts.
    pub fn new(
        locator: RootLocator,
        display_name: String,
        safe_location_presentation: String,
    ) -> Self {
        Self {
            locator,
            display_name,
            safe_location_presentation,
        }
    }

    /// Returns the provider-owned opaque locator.
    pub fn locator(&self) -> &RootLocator {
        &self.locator
    }

    /// Returns the provider-supplied safe display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the provider-supplied safe presentation location.
    pub fn safe_location_presentation(&self) -> &str {
        &self.safe_location_presentation
    }
}

/// Structural storage shape reported by a provider.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ObservedEntryKind {
    Directory,
    File,
    LinkLike,
    Other,
}

impl ObservedEntryKind {
    /// Returns the canonical serialized kind value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Directory => "directory",
            Self::File => "file",
            Self::LinkLike => "link_like",
            Self::Other => "other",
        }
    }
}

/// Application-owned richer persisted source-entry kind.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceEntryKind {
    Directory,
    File,
    LinkLike,
    Unknown,
}

impl SourceEntryKind {
    /// Returns the canonical serialized kind value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Directory => "directory",
            Self::File => "file",
            Self::LinkLike => "link_like",
            Self::Unknown => "unknown",
        }
    }
}

/// Application-owned classification of one source entry.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceEntryClassification {
    Container,
    ContentCandidate,
    SupportingEntry,
    Ignored,
    Unknown,
}

impl SourceEntryClassification {
    /// Returns the canonical serialized classification value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Container => "container",
            Self::ContentCandidate => "content_candidate",
            Self::SupportingEntry => "supporting_entry",
            Self::Ignored => "ignored",
            Self::Unknown => "unknown",
        }
    }
}

/// Opaque provider-owned locator of one entry beneath a resolved root.
///
/// Generic application and persistence code may transport and store the
/// opaque value but must never parse, normalize, or construct it.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct RelativeSourceLocator(String);

impl RelativeSourceLocator {
    /// Wraps a provider-produced opaque relative locator value.
    pub fn from_provider(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque provider value for persistence/transport only.
    pub fn as_provider_value(&self) -> &str {
        &self.0
    }
}

/// Provider-defined canonical equality key for one current location.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct SourceLocatorKey(String);

impl SourceLocatorKey {
    /// Wraps a provider-produced canonical equality key.
    pub fn from_provider(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque provider value for persistence/comparison only.
    pub fn as_provider_value(&self) -> &str {
        &self.0
    }
}

/// One root-relative logical segment of a provider-neutral discovery path.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DiscoverySegment(String);

impl DiscoverySegment {
    /// Creates one logical child-name segment.
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// Returns the logical segment value.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Provider-neutral path projection used by generic discovery policy.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DiscoveryPath {
    segments: Vec<DiscoverySegment>,
}

impl DiscoveryPath {
    /// Creates a root-relative discovery path.
    pub fn new(segments: Vec<DiscoverySegment>) -> Self {
        Self { segments }
    }

    /// Returns the logical segments in root-relative order.
    pub fn segments(&self) -> &[DiscoverySegment] {
        &self.segments
    }
}

/// Normalized provider-owned fact set for one observed entry.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceObservation {
    relative_locator: RelativeSourceLocator,
    locator_key: SourceLocatorKey,
    discovery_path: DiscoveryPath,
    observed_kind: ObservedEntryKind,
    display_name: String,
    provider_native_identity: Option<String>,
    source_fingerprint: Option<String>,
    size: Option<u64>,
    modified_at_ms: Option<i64>,
}

impl SourceObservation {
    /// Creates one normalized positive observation.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        relative_locator: RelativeSourceLocator,
        locator_key: SourceLocatorKey,
        discovery_path: DiscoveryPath,
        observed_kind: ObservedEntryKind,
        display_name: impl Into<String>,
        provider_native_identity: Option<String>,
        source_fingerprint: Option<String>,
        size: Option<u64>,
        modified_at_ms: Option<i64>,
    ) -> Self {
        Self {
            relative_locator,
            locator_key,
            discovery_path,
            observed_kind,
            display_name: display_name.into(),
            provider_native_identity,
            source_fingerprint,
            size,
            modified_at_ms,
        }
    }

    /// Returns the opaque relative locator.
    pub fn relative_locator(&self) -> &RelativeSourceLocator {
        &self.relative_locator
    }

    /// Returns the provider-defined location equality key.
    pub fn locator_key(&self) -> &SourceLocatorKey {
        &self.locator_key
    }

    /// Returns the provider-neutral discovery path.
    pub fn discovery_path(&self) -> &DiscoveryPath {
        &self.discovery_path
    }

    /// Returns the structural observed kind.
    pub fn observed_kind(&self) -> ObservedEntryKind {
        self.observed_kind
    }

    /// Returns the safe display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the optional opaque provider-native continuity identity.
    pub fn provider_native_identity(&self) -> Option<&str> {
        self.provider_native_identity.as_deref()
    }

    /// Returns the optional cheap change-evidence fingerprint.
    pub fn source_fingerprint(&self) -> Option<&str> {
        self.source_fingerprint.as_deref()
    }

    /// Returns the cheap size fact, when available.
    pub fn size(&self) -> Option<u64> {
        self.size
    }

    /// Returns the cheap modified timestamp, when available.
    pub fn modified_at_ms(&self) -> Option<i64> {
        self.modified_at_ms
    }
}

/// Terminal outcome of one exact enumeration scope.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EnumerationOutcome {
    Complete,
    Partial,
    Unavailable,
    Failed,
    Cancelled,
}

impl EnumerationOutcome {
    /// Returns the canonical serialized outcome value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Complete => "complete",
            Self::Partial => "partial",
            Self::Unavailable => "unavailable",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
        }
    }
}

/// One streamed enumeration result for an exact scope.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EnumerationResult {
    observations: Vec<SourceObservation>,
    outcome: EnumerationOutcome,
}

impl EnumerationResult {
    /// Creates one scope result.
    pub fn new(observations: Vec<SourceObservation>, outcome: EnumerationOutcome) -> Self {
        Self {
            observations,
            outcome,
        }
    }

    /// Returns the positive observations produced by the scope.
    pub fn observations(&self) -> &[SourceObservation] {
        &self.observations
    }

    /// Returns the exact-scope terminal outcome.
    pub fn outcome(&self) -> EnumerationOutcome {
        self.outcome
    }
}

/// Transient provider-owned resolved-root handle.
///
/// The enclosed value is opaque to generic application code; only the owning
/// provider interprets it. It is never persisted or bridged.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResolvedRoot(String);

impl ResolvedRoot {
    /// Wraps a provider-produced opaque root token.
    pub fn from_provider(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque provider token for provider-internal use only.
    pub fn as_provider_value(&self) -> &str {
        &self.0
    }
}

/// Stable provider-side failure vocabulary.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceAccessError {
    SourceUnavailable,
    EntryNotFound,
    PermissionDenied,
    AuthorizationUnavailable,
    InvalidLocator,
    InvalidConfiguration,
    UnsupportedOperation,
    IoFailure,
    InvalidResponse,
    Cancelled,
}

/// Operation-scoped source access for one execution attempt.
///
/// The provider owns root resolution, locator interpretation, direct-child
/// enumeration, native identity/capability facts, and native error
/// translation. Application/indexing code never parses provider values.
pub trait LibrarySourceAccess: Send + Sync {
    /// Resolves the configured root and returns a transient root handle.
    fn resolve_root(&self) -> Result<ResolvedRoot, SourceAccessError>;

    /// Enumerates the direct children of the resolved root.
    fn enumerate_root_direct_children(
        &self,
        root: &ResolvedRoot,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError>;

    /// Enumerates the direct children of one opaque relative scope.
    fn enumerate_direct_children(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError>;
}

impl LibrarySourceAccess for Box<dyn LibrarySourceAccess> {
    fn resolve_root(&self) -> Result<ResolvedRoot, SourceAccessError> {
        (**self).resolve_root()
    }

    fn enumerate_root_direct_children(
        &self,
        root: &ResolvedRoot,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError> {
        (**self).enumerate_root_direct_children(root, is_cancelled)
    }

    fn enumerate_direct_children(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
        is_cancelled: &dyn Fn() -> bool,
    ) -> Result<EnumerationResult, SourceAccessError> {
        (**self).enumerate_direct_children(root, relative, is_cancelled)
    }
}

/// Sanitized provider validation failure. Native objects and paths never
/// escape the provider boundary through this type.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProviderError {
    /// The supplied value is not a usable local-folder selection.
    InvalidSelection,
    /// The selection is a normal file rather than a directory-like root.
    NotADirectory,
    /// The selection is a link-like object such as a symlink or junction.
    LinkLikeRoot,
    /// Access to the selection was denied.
    PermissionDenied,
    /// The selection could not currently be reached as an enumerable root.
    Unavailable,
    /// An unexpected provider-side failure occurred.
    Internal,
}

/// Application-owned port through which the LocalFilesystem provider exposes
/// validation and root-relationship semantics.
pub trait LocalFilesystemProvider {
    /// Validates one typed selection and constructs the provider-owned
    /// locator plus safe presentation facts. Successful validation must
    /// establish that the selection is currently reachable and enumerable as
    /// a directory-like root without scanning its contents.
    fn validate(
        &self,
        selection: &LocalFilesystemRootSelection,
    ) -> Result<ValidatedLocalRoot, ProviderError>;

    /// Compares two opaque root locators using provider-owned filesystem
    /// semantics. `Unknown` is returned whenever the relationship cannot be
    /// proven reliably.
    fn compare_roots(&self, left: &RootLocator, right: &RootLocator) -> RootRelationship;

    /// Opens one execution-scoped source access bound to a configured root.
    fn open_access(
        &self,
        locator: &RootLocator,
    ) -> Result<Box<dyn LibrarySourceAccess>, SourceAccessError>;
}

impl<P> LocalFilesystemProvider for &P
where
    P: LocalFilesystemProvider,
{
    fn validate(
        &self,
        selection: &LocalFilesystemRootSelection,
    ) -> Result<ValidatedLocalRoot, ProviderError> {
        (*self).validate(selection)
    }

    fn compare_roots(&self, left: &RootLocator, right: &RootLocator) -> RootRelationship {
        (*self).compare_roots(left, right)
    }

    fn open_access(
        &self,
        locator: &RootLocator,
    ) -> Result<Box<dyn LibrarySourceAccess>, SourceAccessError> {
        (*self).open_access(locator)
    }
}
