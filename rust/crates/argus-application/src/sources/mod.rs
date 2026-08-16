//! Phase 001 library-source and library-root configuration capabilities.

mod events;
mod hierarchy;
mod library;
mod provider;
mod scan;

pub use events::{LibraryRootChanged, LibraryRootsChanged, LibraryRootsSubscriber};
pub use hierarchy::{
    GetSourceEntryHandler, GetSourceEntryQuery, ListSourceEntryChildrenHandler,
    ListSourceEntryChildrenQuery,
};
pub use hierarchy::{
    SourceEntryChildrenPage, SourceEntryCursor, SourceEntryCursorError,
    SourceEntryDetailProjection, SourceEntryProjection, SourceEntryQueries,
};
pub use library::{
    AddLocalLibraryRootAndScanCommand, AddLocalLibraryRootAndScanHandler,
    AddLocalLibraryRootAndScanResult, AddLocalLibraryRootCommand, AddLocalLibraryRootHandler,
    AddLocalLibraryRootResult, GetLibraryRootHandler, GetLibraryRootQuery,
    LibraryRootActiveScanSummary, LibraryRootAvailability, LibraryRootConfiguration,
    LibraryRootLastScanStatus, LibraryRootLastScanSummary, LibraryRootPage, LibraryRootProjection,
    LibraryRootQueries, LibraryRootRepository, LibraryRootScanConfiguration,
    LibraryScanChildAdmission, LibraryScanChildAdmissionIssue, LibraryService,
    LibrarySourceRepository, ListLibraryRootsHandler, ListLibraryRootsQuery, NewLibraryRoot,
    RemoveLibraryRootCommand, RemoveLibraryRootHandler, RemoveLibraryRootResult,
    StartLibraryScanAllCommand, StartLibraryScanAllHandler, StartLibraryScanCommand,
    StartLibraryScanHandler, SyncLocalFilesystemMountedVolumesCommand,
};
pub use provider::{
    DiscoveryPath, DiscoverySegment, EnumerationOutcome, EnumerationResult, LibrarySourceAccess,
    LocalFilesystemBrowseBreadcrumb, LocalFilesystemBrowseCursor, LocalFilesystemBrowseDirectory,
    LocalFilesystemBrowseLocation, LocalFilesystemBrowsePage, LocalFilesystemBrowseProvider,
    LocalFilesystemBrowseRoot, LocalFilesystemProvider, LocalFilesystemRootSelection,
    MAX_LOCAL_FILESYSTEM_BROWSE_PAGE_SIZE, MAX_MOUNTED_LOCAL_FILESYSTEM_VOLUMES,
    MountedLocalFilesystemVolume, ObservedEntryKind, ProviderError, RelativeSourceLocator,
    ResolvedRoot, RootLocator, RootRelationship, SourceAccessError, SourceEntryClassification,
    SourceEntryKind, SourceLocatorKey, SourceObservation, SourceProviderType,
    SourceProviderTypeError, ValidatedLocalRoot,
};
pub use scan::LibraryScanOperationHandler;
