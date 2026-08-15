//! Phase 001 library-source and library-root configuration capabilities.

mod events;
mod library;
mod provider;
mod scan;

pub use events::{LibraryRootChanged, LibraryRootsChanged, LibraryRootsSubscriber};
pub use library::{
    AddLocalLibraryRootCommand, AddLocalLibraryRootHandler, AddLocalLibraryRootResult,
    GetLibraryRootHandler, GetLibraryRootQuery, LibraryRootActiveScanSummary,
    LibraryRootAvailability, LibraryRootConfiguration, LibraryRootLastScanStatus,
    LibraryRootLastScanSummary, LibraryRootPage, LibraryRootProjection, LibraryRootQueries,
    LibraryRootRepository, LibraryRootScanConfiguration, LibraryService, LibrarySourceRepository,
    ListLibraryRootsHandler, ListLibraryRootsQuery, NewLibraryRoot, RemoveLibraryRootCommand,
    RemoveLibraryRootHandler, RemoveLibraryRootResult, StartLibraryScanCommand,
    StartLibraryScanHandler,
};
pub use provider::{
    DiscoveryPath, DiscoverySegment, EnumerationOutcome, EnumerationResult, LibrarySourceAccess,
    LocalFilesystemProvider, LocalFilesystemRootSelection, ObservedEntryKind, ProviderError,
    RelativeSourceLocator, ResolvedRoot, RootLocator, RootRelationship, SourceAccessError,
    SourceEntryClassification, SourceEntryKind, SourceLocatorKey, SourceObservation,
    SourceProviderType, SourceProviderTypeError, ValidatedLocalRoot,
};
pub use scan::LibraryScanOperationHandler;
