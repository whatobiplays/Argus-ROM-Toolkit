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
/// owns all filesystem interpretation. Provider selections carry an opaque
/// identity that is meaningful only to the LocalFilesystem provider.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LocalFilesystemRootSelection {
    /// A desktop/native picker supplied a filesystem path.
    Path { selected_folder_path: String },
    /// The Argus-owned provider browser supplied an opaque selection identity.
    ProviderSelection { selection_identity: String },
}

impl LocalFilesystemRootSelection {
    /// Creates a path-backed selection. Kept as the compatibility constructor
    /// for existing desktop callers.
    pub fn new(selected_folder_path: String) -> Self {
        Self::path(selected_folder_path)
    }

    /// Creates a path-backed selection.
    pub fn path(selected_folder_path: String) -> Self {
        Self::Path {
            selected_folder_path,
        }
    }

    /// Creates an opaque provider-browser selection.
    pub fn provider_selection(selection_identity: String) -> Self {
        Self::ProviderSelection { selection_identity }
    }

    /// Returns the raw picker path only for the path variant.
    pub fn selected_folder_path(&self) -> Option<&str> {
        match self {
            Self::Path {
                selected_folder_path,
            } => Some(selected_folder_path),
            Self::ProviderSelection { .. } => None,
        }
    }

    /// Returns the opaque provider selection identity only for the provider
    /// variant.
    pub fn selection_identity(&self) -> Option<&str> {
        match self {
            Self::Path { .. } => None,
            Self::ProviderSelection { selection_identity } => Some(selection_identity),
        }
    }
}

/// Maximum number of mounted-volume facts accepted in one native snapshot.
pub const MAX_MOUNTED_LOCAL_FILESYSTEM_VOLUMES: usize = 32;

/// Maximum number of direct-child browse rows returned by one page.
pub const MAX_LOCAL_FILESYSTEM_BROWSE_PAGE_SIZE: u32 = 200;

/// Current mounted-volume fact supplied by the native platform layer.
///
/// The mount path is transient input for the provider registry. It must never
/// be persisted as a durable root locator.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MountedLocalFilesystemVolume {
    provider_volume_id: String,
    mount_path: String,
    display_name: String,
    is_primary: bool,
    is_removable: bool,
}

impl MountedLocalFilesystemVolume {
    /// Creates one bounded native mounted-volume fact.
    pub fn new(
        provider_volume_id: String,
        mount_path: String,
        display_name: String,
        is_primary: bool,
        is_removable: bool,
    ) -> Self {
        Self {
            provider_volume_id,
            mount_path,
            display_name,
            is_primary,
            is_removable,
        }
    }

    /// Returns the provider-stable volume identity.
    pub fn provider_volume_id(&self) -> &str {
        &self.provider_volume_id
    }

    /// Returns the transient current mount path.
    pub fn mount_path(&self) -> &str {
        &self.mount_path
    }

    /// Returns the safe native display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns whether this is the primary shared-storage volume.
    pub fn is_primary(&self) -> bool {
        self.is_primary
    }

    /// Returns whether this volume is removable.
    pub fn is_removable(&self) -> bool {
        self.is_removable
    }
}

/// Opaque provider-owned browse location.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct LocalFilesystemBrowseLocation(String);

impl LocalFilesystemBrowseLocation {
    /// Wraps a provider-produced browse location.
    pub fn from_provider(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque provider value for provider-internal transport.
    pub fn as_provider_value(&self) -> &str {
        &self.0
    }
}

/// Opaque provider-owned browse pagination cursor.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct LocalFilesystemBrowseCursor(String);

impl LocalFilesystemBrowseCursor {
    /// Wraps a provider-produced cursor.
    pub fn from_provider(value: String) -> Self {
        Self(value)
    }

    /// Returns the opaque provider value for provider-internal transport.
    pub fn as_provider_value(&self) -> &str {
        &self.0
    }
}

/// Safe projection of one mounted browse root.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowseRoot {
    location: LocalFilesystemBrowseLocation,
    display_name: String,
    safe_location_presentation: String,
}

impl LocalFilesystemBrowseRoot {
    /// Creates one provider-produced browse-root projection.
    pub fn new(
        location: LocalFilesystemBrowseLocation,
        display_name: String,
        safe_location_presentation: String,
    ) -> Self {
        Self {
            location,
            display_name,
            safe_location_presentation,
        }
    }

    /// Returns the opaque root location.
    pub fn location(&self) -> &LocalFilesystemBrowseLocation {
        &self.location
    }

    /// Returns the safe display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the provider-produced safe location presentation.
    pub fn safe_location_presentation(&self) -> &str {
        &self.safe_location_presentation
    }
}

/// Safe projection of one provider-generated breadcrumb.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowseBreadcrumb {
    location: LocalFilesystemBrowseLocation,
    display_name: String,
}

impl LocalFilesystemBrowseBreadcrumb {
    /// Creates one browse breadcrumb projection.
    pub fn new(location: LocalFilesystemBrowseLocation, display_name: String) -> Self {
        Self {
            location,
            display_name,
        }
    }

    /// Returns the opaque breadcrumb location.
    pub fn location(&self) -> &LocalFilesystemBrowseLocation {
        &self.location
    }

    /// Returns the safe breadcrumb label.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }
}

/// Safe projection of one selectable direct-child directory.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowseDirectory {
    location: LocalFilesystemBrowseLocation,
    display_name: String,
}

impl LocalFilesystemBrowseDirectory {
    /// Creates one browse directory projection.
    pub fn new(location: LocalFilesystemBrowseLocation, display_name: String) -> Self {
        Self {
            location,
            display_name,
        }
    }

    /// Returns the opaque child location.
    pub fn location(&self) -> &LocalFilesystemBrowseLocation {
        &self.location
    }

    /// Returns the safe directory label.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }
}

/// One bounded provider browse page.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalFilesystemBrowsePage {
    current: LocalFilesystemBrowseRoot,
    breadcrumbs: Vec<LocalFilesystemBrowseBreadcrumb>,
    directories: Vec<LocalFilesystemBrowseDirectory>,
    next_cursor: Option<LocalFilesystemBrowseCursor>,
}

impl LocalFilesystemBrowsePage {
    /// Creates one provider-produced browse page.
    pub fn new(
        current: LocalFilesystemBrowseRoot,
        breadcrumbs: Vec<LocalFilesystemBrowseBreadcrumb>,
        directories: Vec<LocalFilesystemBrowseDirectory>,
        next_cursor: Option<LocalFilesystemBrowseCursor>,
    ) -> Self {
        Self {
            current,
            breadcrumbs,
            directories,
            next_cursor,
        }
    }

    /// Returns the current safe location projection.
    pub fn current(&self) -> &LocalFilesystemBrowseRoot {
        &self.current
    }

    /// Returns provider-generated breadcrumbs from the volume root.
    pub fn breadcrumbs(&self) -> &[LocalFilesystemBrowseBreadcrumb] {
        &self.breadcrumbs
    }

    /// Returns the bounded direct-child directory rows.
    pub fn directories(&self) -> &[LocalFilesystemBrowseDirectory] {
        &self.directories
    }

    /// Returns the opaque cursor for the next page, if any.
    pub fn next_cursor(&self) -> Option<&LocalFilesystemBrowseCursor> {
        self.next_cursor.as_ref()
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

    /// Reads one source entry into a bounded, operation-scoped byte buffer.
    ///
    /// The provider owns path interpretation and returns bytes only. A
    /// default unsupported implementation keeps source providers that do not
    /// expose byte access compatible with the browse and indexing seams.
    fn read_entry_bytes(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
        max_bytes: usize,
    ) -> Result<Vec<u8>, SourceAccessError> {
        let _ = (root, relative, max_bytes);
        Err(SourceAccessError::UnsupportedOperation)
    }
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

    fn read_entry_bytes(
        &self,
        root: &ResolvedRoot,
        relative: &RelativeSourceLocator,
        max_bytes: usize,
    ) -> Result<Vec<u8>, SourceAccessError> {
        (**self).read_entry_bytes(root, relative, max_bytes)
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
    /// The browse request or mounted-volume snapshot violated provider bounds.
    InvalidBrowseRequest,
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

/// Additive LocalFilesystem browse and mounted-volume capability.
///
/// Existing validation, comparison, and access-only providers remain valid
/// implementations of [`LocalFilesystemProvider`].
pub trait LocalFilesystemBrowseProvider: LocalFilesystemProvider {
    /// Replaces the provider's transient mounted-volume registry atomically.
    fn replace_mounted_volumes(
        &self,
        volumes: &[MountedLocalFilesystemVolume],
    ) -> Result<(), ProviderError>;

    /// Lists currently mounted browse roots using safe projections.
    fn list_browse_roots(&self) -> Result<Vec<LocalFilesystemBrowseRoot>, ProviderError>;

    /// Lists one bounded page of direct-child browse directories.
    fn list_browse_directories(
        &self,
        location: &LocalFilesystemBrowseLocation,
        cursor: Option<&LocalFilesystemBrowseCursor>,
        page_size: u32,
    ) -> Result<LocalFilesystemBrowsePage, ProviderError>;
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

impl<P> LocalFilesystemBrowseProvider for &P
where
    P: LocalFilesystemBrowseProvider,
{
    fn replace_mounted_volumes(
        &self,
        volumes: &[MountedLocalFilesystemVolume],
    ) -> Result<(), ProviderError> {
        (*self).replace_mounted_volumes(volumes)
    }

    fn list_browse_roots(&self) -> Result<Vec<LocalFilesystemBrowseRoot>, ProviderError> {
        (*self).list_browse_roots()
    }

    fn list_browse_directories(
        &self,
        location: &LocalFilesystemBrowseLocation,
        cursor: Option<&LocalFilesystemBrowseCursor>,
        page_size: u32,
    ) -> Result<LocalFilesystemBrowsePage, ProviderError> {
        (*self).list_browse_directories(location, cursor, page_size)
    }
}
