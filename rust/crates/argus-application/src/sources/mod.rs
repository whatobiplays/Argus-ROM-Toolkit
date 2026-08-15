//! Phase 001 library-source and library-root configuration capabilities.

mod events;
mod library;
mod provider;

pub use events::{LibraryRootChanged, LibraryRootsChanged, LibraryRootsSubscriber};
pub use library::{
    AddLocalLibraryRootCommand, AddLocalLibraryRootHandler, AddLocalLibraryRootResult,
    GetLibraryRootHandler, GetLibraryRootQuery, LibraryRootActiveScanSummary,
    LibraryRootAvailability, LibraryRootConfiguration, LibraryRootLastScanStatus,
    LibraryRootLastScanSummary, LibraryRootPage, LibraryRootProjection, LibraryRootQueries,
    LibraryRootRepository, LibraryService, LibrarySourceRepository, ListLibraryRootsHandler,
    ListLibraryRootsQuery, NewLibraryRoot, RemoveLibraryRootCommand, RemoveLibraryRootHandler,
    RemoveLibraryRootResult,
};
pub use provider::{
    LocalFilesystemProvider, LocalFilesystemRootSelection, ProviderError, RootLocator,
    RootRelationship, SourceProviderType, SourceProviderTypeError, ValidatedLocalRoot,
};
