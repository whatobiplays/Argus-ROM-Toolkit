//! Strongly typed application notifications and their recording boundary.

use crate::{ApplicationPortError, LibraryRootChanged, LibraryRootsChanged};

/// Notification that the authoritative appearance aggregate changed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AppearanceSettingsChanged;

/// Failure returned by an application-owned appearance event consumer.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EventSubscriberError {
    /// The consumer could not complete its bounded notification work.
    Failed,
}

/// Narrow application-facing consumer contract for the appearance event.
pub trait AppearanceSettingsSubscriber: Send + Sync {
    /// Receives one immutable, payload-free appearance notification.
    fn appearance_settings_changed(
        &self,
        event: AppearanceSettingsChanged,
    ) -> Result<(), EventSubscriberError>;
}

/// Application-event representation for the implemented product slices.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ApplicationEvent {
    /// Consumers receive notification that the authoritative appearance may have changed.
    AppearanceSettingsChanged(AppearanceSettingsChanged),
    /// Consumers receive notification that configured root-list membership or
    /// ordering may have changed.
    LibraryRootsChanged(LibraryRootsChanged),
    /// Consumers receive notification that one root projection may have changed.
    LibraryRootChanged(LibraryRootChanged),
}

/// Failure while recording a pending application event.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EventRecordingError {
    /// The operation-scoped pending collector cannot accept another event.
    CapacityExceeded,
}

/// Narrow application-facing capability for recording a pending event.
pub trait EventRecorder: Send + Sync {
    /// Records an immutable event without publishing or performing I/O.
    fn record(&self, event: ApplicationEvent) -> Result<(), EventRecordingError>;
}

impl From<EventRecordingError> for ApplicationPortError {
    fn from(_: EventRecordingError) -> Self {
        Self::EventRecording
    }
}
