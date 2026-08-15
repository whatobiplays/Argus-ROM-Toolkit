//! Strongly typed application notifications and their recording boundary.

use crate::{
    ApplicationPortError, JobProgress, JobRunId, LibraryRootChanged, LibraryRootId,
    LibraryRootsChanged, SourceEntryId,
};

/// Notification that the authoritative appearance aggregate changed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AppearanceSettingsChanged;

/// Notification that generic job lifecycle or control facts may have changed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct JobStateChanged {
    /// The affected execution identity.
    pub job_run_id: JobRunId,
}

/// Notification that structured job progress may have changed.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobProgressChanged {
    /// The bounded authoritative progress snapshot for the affected job.
    pub progress: JobProgress,
}

/// Explicit source-graph invalidation scope union.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourceEntriesChangeScope {
    /// Direct configured-root children may have changed.
    RootChildren,
    /// Direct children of exactly one source entry may have changed.
    EntryChildren(SourceEntryId),
    /// The entire root hierarchy may have changed.
    EntireRootHierarchy,
}

/// Notification that committed source-graph state may have changed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SourceEntriesChanged {
    /// The affected root identity.
    pub library_root_id: LibraryRootId,
    /// The invalidation scope union.
    pub scope: SourceEntriesChangeScope,
}

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
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ApplicationEvent {
    /// Consumers receive notification that the authoritative appearance may have changed.
    AppearanceSettingsChanged(AppearanceSettingsChanged),
    /// Consumers receive notification that configured root-list membership or
    /// ordering may have changed.
    LibraryRootsChanged(LibraryRootsChanged),
    /// Consumers receive notification that one root projection may have changed.
    LibraryRootChanged(LibraryRootChanged),
    /// Consumers receive notification that generic job state may have changed.
    JobStateChanged(JobStateChanged),
    /// Consumers receive notification that structured job progress changed.
    JobProgressChanged(JobProgressChanged),
    /// Consumers receive notification that committed source state changed.
    SourceEntriesChanged(SourceEntriesChanged),
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

/// Narrow application-facing consumer contract for generic job events.
pub trait JobsSubscriber: Send + Sync {
    /// Receives one bounded job-state invalidation.
    fn job_state_changed(&self, event: JobStateChanged) -> Result<(), EventSubscriberError>;

    /// Receives one bounded structured progress notification.
    fn job_progress_changed(&self, event: JobProgressChanged) -> Result<(), EventSubscriberError>;
}

/// Narrow application-facing consumer contract for source-graph events.
pub trait SourceEntriesSubscriber: Send + Sync {
    /// Receives one bounded source-graph invalidation.
    fn source_entries_changed(
        &self,
        event: SourceEntriesChanged,
    ) -> Result<(), EventSubscriberError>;
}

impl From<EventRecordingError> for ApplicationPortError {
    fn from(_: EventRecordingError) -> Self {
        Self::EventRecording
    }
}
