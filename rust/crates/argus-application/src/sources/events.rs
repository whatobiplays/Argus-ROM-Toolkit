//! Application events for configured library-root state.

use crate::{EventSubscriberError, LibraryRootId};

/// Notification that configured root-list membership or ordering may have
/// changed. Carries no authoritative snapshot.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LibraryRootsChanged;

/// Notification that one root projection may have changed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LibraryRootChanged {
    /// The affected root identity. Bounded invalidation only.
    pub library_root_id: LibraryRootId,
}

/// Narrow application-facing consumer contract for library-root events.
pub trait LibraryRootsSubscriber: Send + Sync {
    /// Receives one bounded root-list invalidation.
    fn library_roots_changed(&self, event: LibraryRootsChanged)
    -> Result<(), EventSubscriberError>;

    /// Receives one bounded single-root invalidation.
    fn library_root_changed(&self, event: LibraryRootChanged) -> Result<(), EventSubscriberError>;
}
