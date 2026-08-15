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
}
