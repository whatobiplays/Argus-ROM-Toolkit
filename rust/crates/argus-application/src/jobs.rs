//! Generic durable background-job contracts for Phase 001 Slice 002.
//!
//! These types are application-owned and technology-neutral. `JobRunId`
//! identifies exactly one background execution attempt and `ScanRunId`
//! identifies one root-specific scan inside a job. Persistence ports remain
//! application contracts; the runtime owns generic lifecycle transitions.

use crate::unit_of_work::UnitOfWork;
use crate::{
    ApplicationError, ApplicationEvent, ApplicationPortError, ErrorCode, GameId, JobRunId,
    LibraryRootId, LibraryRootLastScanStatus, LibraryRootLastScanSummary, LibraryRootRepository,
    OperationContext, PersistenceError, SafeContext, SafeContextField, SafeContextValue, ScanRunId,
    SourceEntryId, TraceId,
};

use crate::sources::{RelativeSourceLocator, RootLocator, SourceLocatorKey};
use crate::transformation::{DerivedEntryKey, DerivedFingerprint, DerivedLocator};

/// Stable logical operation type for the built-in library scan.
pub const OPERATION_TYPE_LIBRARY_SCAN: &str = "library_scan";

/// Stable logical operation type for the composed Library refresh.
pub const OPERATION_TYPE_LIBRARY_REFRESH: &str = "library_refresh";

/// Stable logical operation type for a bounded Game refresh.
pub const OPERATION_TYPE_GAME_REFRESH: &str = "game_refresh";

/// Stable logical operation type for local-only preference re-resolution.
pub const OPERATION_TYPE_LIBRARY_RESOLUTION_REFRESH: &str = "library_resolution_refresh";

/// User-visible trigger retained by one composed Library refresh.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryRefreshTrigger {
    /// A user explicitly requested a Library refresh.
    Manual,
    /// A configured root was added and requested its first refresh.
    AddedRoot(LibraryRootId),
    /// Onboarding completed and admitted the initial refresh.
    InitialOnboarding,
}

impl LibraryRefreshTrigger {
    /// Returns the stable trigger category used by persistence and Jobs UI.
    pub const fn kind(self) -> &'static str {
        match self {
            Self::Manual => "manual",
            Self::AddedRoot(_) => "added_root",
            Self::InitialOnboarding => "initial_onboarding",
        }
    }

    /// Returns the root identity carried by an AddedRoot trigger.
    pub const fn root_id(self) -> Option<LibraryRootId> {
        match self {
            Self::AddedRoot(root_id) => Some(root_id),
            Self::Manual | Self::InitialOnboarding => None,
        }
    }
}

/// Freshness policy accepted by Library and Game refresh commands.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RefreshMode {
    /// Refresh only records eligible under current freshness policy.
    EligibleOnly,
    /// Bypass freshness for one bounded Game target only.
    Force,
}

impl RefreshMode {
    /// Returns the stable serialized mode.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::EligibleOnly => "eligible_only",
            Self::Force => "force",
        }
    }
}

/// Bounded progress facts for one Phase 003 refresh operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RefreshProgressFacts {
    phase: Option<String>,
    completed_units: Option<u64>,
    total_units: Option<u64>,
    status_key: Option<String>,
    issue_count: Option<u64>,
}

impl RefreshProgressFacts {
    /// Creates truthful progress facts without fabricating a total.
    pub fn new(
        phase: Option<String>,
        completed_units: Option<u64>,
        total_units: Option<u64>,
        status_key: Option<String>,
        issue_count: Option<u64>,
    ) -> Result<Self, JobProgressError> {
        if let (Some(completed), Some(total)) = (completed_units, total_units)
            && completed > total
        {
            return Err(JobProgressError);
        }
        Ok(Self {
            phase,
            completed_units,
            total_units,
            status_key,
            issue_count,
        })
    }

    /// Returns the current phase, if known.
    pub fn phase(&self) -> Option<&str> {
        self.phase.as_deref()
    }

    /// Returns completed work, if determinate.
    pub const fn completed_units(&self) -> Option<u64> {
        self.completed_units
    }

    /// Returns total work, if known.
    pub const fn total_units(&self) -> Option<u64> {
        self.total_units
    }

    /// Returns the presentation status key, if known.
    pub fn status_key(&self) -> Option<&str> {
        self.status_key.as_deref()
    }

    /// Returns the bounded issue count, if known.
    pub const fn issue_count(&self) -> Option<u64> {
        self.issue_count
    }
}

/// Canonical persisted lifecycle vocabulary for one job execution attempt.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum JobRunState {
    Queued,
    Preparing,
    Running,
    Completed,
    CompletedWithIssues,
    Failed,
    Cancelled,
    Interrupted,
    Abandoned,
}

impl JobRunState {
    /// Returns the canonical serialized state value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Preparing => "preparing",
            Self::Running => "running",
            Self::Completed => "completed",
            Self::CompletedWithIssues => "completed_with_issues",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
            Self::Interrupted => "interrupted",
            Self::Abandoned => "abandoned",
        }
    }

    /// Returns whether this state is terminal for the execution attempt.
    pub const fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Completed
                | Self::CompletedWithIssues
                | Self::Failed
                | Self::Cancelled
                | Self::Interrupted
                | Self::Abandoned
        )
    }

    /// Returns whether this state still represents active execution.
    pub const fn is_active(self) -> bool {
        matches!(self, Self::Queued | Self::Preparing | Self::Running)
    }
}

impl TryFrom<&str> for JobRunState {
    type Error = JobRunStateParseError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "queued" => Ok(Self::Queued),
            "preparing" => Ok(Self::Preparing),
            "running" => Ok(Self::Running),
            "completed" => Ok(Self::Completed),
            "completed_with_issues" => Ok(Self::CompletedWithIssues),
            "failed" => Ok(Self::Failed),
            "cancelled" => Ok(Self::Cancelled),
            "interrupted" => Ok(Self::Interrupted),
            "abandoned" => Ok(Self::Abandoned),
            _ => Err(JobRunStateParseError),
        }
    }
}

/// Failure while parsing a persisted job state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct JobRunStateParseError;

impl std::fmt::Display for JobRunStateParseError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("invalid job run state")
    }
}

impl std::error::Error for JobRunStateParseError {}

/// Failure while constructing structured progress.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct JobProgressError;

impl std::fmt::Display for JobProgressError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("invalid job progress")
    }
}

impl std::error::Error for JobProgressError {}

/// Structured phase-local progress for one job execution.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobProgress {
    job_run_id: JobRunId,
    phase: String,
    completed_units: Option<u64>,
    total_units: Option<u64>,
    status_key: Option<String>,
    updated_at_ms: i64,
}

impl JobProgress {
    /// Creates structured progress. `completed_units` must never exceed
    /// `total_units` when the total is known.
    pub fn new(
        job_run_id: JobRunId,
        phase: impl Into<String>,
        completed_units: Option<u64>,
        total_units: Option<u64>,
        status_key: Option<impl Into<String>>,
        updated_at_ms: i64,
    ) -> Result<Self, JobProgressError> {
        if let (Some(completed), Some(total)) = (completed_units, total_units)
            && completed > total
        {
            return Err(JobProgressError);
        }
        Ok(Self {
            job_run_id,
            phase: phase.into(),
            completed_units,
            total_units,
            status_key: status_key.map(Into::into),
            updated_at_ms,
        })
    }

    /// Returns the owning execution identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the stable operation-defined phase identifier.
    pub fn phase(&self) -> &str {
        &self.phase
    }

    /// Returns the completed units in the current phase, if determinate.
    pub fn completed_units(&self) -> Option<u64> {
        self.completed_units
    }

    /// Returns the total units in the current phase, if known.
    pub fn total_units(&self) -> Option<u64> {
        self.total_units
    }

    /// Returns the stable presentation/localization key, if any.
    pub fn status_key(&self) -> Option<&str> {
        self.status_key.as_deref()
    }

    /// Returns the progress observation timestamp.
    pub fn updated_at_ms(&self) -> i64 {
        self.updated_at_ms
    }
}

/// One new generic job execution attempt.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NewJobRun {
    operation_type: String,
    created_at_ms: i64,
}

impl NewJobRun {
    /// Creates a queued execution request.
    pub fn new(operation_type: impl Into<String>, created_at_ms: i64) -> Self {
        Self {
            operation_type: operation_type.into(),
            created_at_ms,
        }
    }

    /// Returns the stable logical operation type.
    pub fn operation_type(&self) -> &str {
        &self.operation_type
    }

    /// Returns the creation timestamp.
    pub fn created_at_ms(&self) -> i64 {
        self.created_at_ms
    }
}

/// Capability-neutral generic projection of one job execution.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobRunProjection {
    job_run_id: JobRunId,
    operation_type: String,
    state: JobRunState,
    phase: Option<String>,
    completed_units: Option<u64>,
    total_units: Option<u64>,
    status_key: Option<String>,
    created_at_ms: i64,
    queued_at_ms: Option<i64>,
    started_at_ms: Option<i64>,
    terminal_at_ms: Option<i64>,
    cancellation_requested: bool,
    controls: JobControlAvailability,
    terminal_error_code: Option<String>,
    terminal_safe_context: Option<String>,
}

impl JobRunProjection {
    /// Creates one generic job projection.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        job_run_id: JobRunId,
        operation_type: impl Into<String>,
        state: JobRunState,
        phase: Option<String>,
        completed_units: Option<u64>,
        total_units: Option<u64>,
        status_key: Option<String>,
        created_at_ms: i64,
        queued_at_ms: Option<i64>,
        started_at_ms: Option<i64>,
        terminal_at_ms: Option<i64>,
        cancellation_requested: bool,
        controls: JobControlAvailability,
        terminal_error_code: Option<String>,
        terminal_safe_context: Option<String>,
    ) -> Self {
        Self {
            job_run_id,
            operation_type: operation_type.into(),
            state,
            phase,
            completed_units,
            total_units,
            status_key,
            created_at_ms,
            queued_at_ms,
            started_at_ms,
            terminal_at_ms,
            cancellation_requested,
            controls,
            terminal_error_code,
            terminal_safe_context,
        }
    }

    /// Returns the execution identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the stable logical operation type.
    pub fn operation_type(&self) -> &str {
        &self.operation_type
    }

    /// Returns the authoritative lifecycle state.
    pub fn state(&self) -> JobRunState {
        self.state
    }

    /// Returns the current phase, when active.
    pub fn phase(&self) -> Option<&str> {
        self.phase.as_deref()
    }

    /// Returns the current phase completed units.
    pub fn completed_units(&self) -> Option<u64> {
        self.completed_units
    }

    /// Returns the current phase total units.
    pub fn total_units(&self) -> Option<u64> {
        self.total_units
    }

    /// Returns the stable status key.
    pub fn status_key(&self) -> Option<&str> {
        self.status_key.as_deref()
    }

    /// Returns the creation timestamp.
    pub fn created_at_ms(&self) -> i64 {
        self.created_at_ms
    }

    /// Returns the queued timestamp, when reached.
    pub fn queued_at_ms(&self) -> Option<i64> {
        self.queued_at_ms
    }

    /// Returns the started timestamp, when reached.
    pub fn started_at_ms(&self) -> Option<i64> {
        self.started_at_ms
    }

    /// Returns the terminal timestamp, when reached.
    pub fn terminal_at_ms(&self) -> Option<i64> {
        self.terminal_at_ms
    }

    /// Returns whether durable cancellation intent has been accepted.
    pub fn cancellation_requested(&self) -> bool {
        self.cancellation_requested
    }

    /// Returns backend-authoritative control availability.
    pub fn controls(&self) -> JobControlAvailability {
        self.controls
    }

    /// Returns the bounded terminal error code, if any.
    pub fn terminal_error_code(&self) -> Option<&str> {
        self.terminal_error_code.as_deref()
    }

    /// Returns the bounded terminal safe context, if any.
    pub fn terminal_safe_context(&self) -> Option<&str> {
        self.terminal_safe_context.as_deref()
    }
}

/// Bounded list-row projection for Jobs landing and shell summaries.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobSummary {
    job_run_id: JobRunId,
    operation_type: String,
    state: JobRunState,
    phase: Option<String>,
    created_at_ms: i64,
    started_at_ms: Option<i64>,
    terminal_at_ms: Option<i64>,
    cancellation_requested: bool,
    safe_context_summary: Option<String>,
}

impl JobSummary {
    /// Creates one bounded job row.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        job_run_id: JobRunId,
        operation_type: impl Into<String>,
        state: JobRunState,
        phase: Option<String>,
        created_at_ms: i64,
        started_at_ms: Option<i64>,
        terminal_at_ms: Option<i64>,
        cancellation_requested: bool,
        safe_context_summary: Option<String>,
    ) -> Self {
        Self {
            job_run_id,
            operation_type: operation_type.into(),
            state,
            phase,
            created_at_ms,
            started_at_ms,
            terminal_at_ms,
            cancellation_requested,
            safe_context_summary,
        }
    }

    /// Returns the execution identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the stable logical operation type.
    pub fn operation_type(&self) -> &str {
        &self.operation_type
    }

    /// Returns the authoritative lifecycle state.
    pub fn state(&self) -> JobRunState {
        self.state
    }

    /// Returns the current phase, when meaningful.
    pub fn phase(&self) -> Option<&str> {
        self.phase.as_deref()
    }

    /// Returns the creation timestamp.
    pub fn created_at_ms(&self) -> i64 {
        self.created_at_ms
    }

    /// Returns the started timestamp.
    pub fn started_at_ms(&self) -> Option<i64> {
        self.started_at_ms
    }

    /// Returns the terminal timestamp.
    pub fn terminal_at_ms(&self) -> Option<i64> {
        self.terminal_at_ms
    }

    /// Returns whether cancellation was durably requested.
    pub fn cancellation_requested(&self) -> bool {
        self.cancellation_requested
    }

    /// Returns the bounded safe context summary.
    pub fn safe_context_summary(&self) -> Option<&str> {
        self.safe_context_summary.as_deref()
    }
}

/// Bounded authoritative job-row page.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobSummaryPage {
    items: Vec<JobSummary>,
    total_count: u32,
    next_offset: Option<u32>,
}

impl JobSummaryPage {
    /// Creates one page with authoritative ordering.
    pub fn new(items: Vec<JobSummary>, total_count: u32, next_offset: Option<u32>) -> Self {
        Self {
            items,
            total_count,
            next_offset,
        }
    }

    /// Returns the page items.
    pub fn items(&self) -> &[JobSummary] {
        &self.items
    }

    /// Returns the authoritative total for the requested scope.
    pub fn total_count(&self) -> u32 {
        self.total_count
    }

    /// Returns the next bounded offset for terminal paging, if any.
    pub fn next_offset(&self) -> Option<u32> {
        self.next_offset
    }
}

/// Backend-authoritative control availability.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct JobControlAvailability {
    can_cancel: bool,
    can_retry: bool,
}

impl JobControlAvailability {
    /// Creates control availability from backend-authoritative facts.
    pub fn new(can_cancel: bool, can_retry: bool) -> Self {
        Self {
            can_cancel,
            can_retry,
        }
    }

    /// Returns whether cancellation may currently be requested.
    pub fn can_cancel(&self) -> bool {
        self.can_cancel
    }

    /// Returns whether retry is currently available.
    pub fn can_retry(&self) -> bool {
        self.can_retry
    }
}

/// Canonical per-root scan status.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ScanRunStatus {
    Running,
    Complete,
    Partial,
    Failed,
    Cancelled,
    Abandoned,
}

impl ScanRunStatus {
    /// Returns the canonical serialized status value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Complete => "complete",
            Self::Partial => "partial",
            Self::Failed => "failed",
            Self::Cancelled => "cancelled",
            Self::Abandoned => "abandoned",
        }
    }

    /// Returns whether this status is terminal.
    pub const fn is_terminal(self) -> bool {
        !matches!(self, Self::Running)
    }
}

impl TryFrom<&str> for ScanRunStatus {
    type Error = ScanRunStatusParseError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "running" => Ok(Self::Running),
            "complete" => Ok(Self::Complete),
            "partial" => Ok(Self::Partial),
            "failed" => Ok(Self::Failed),
            "cancelled" => Ok(Self::Cancelled),
            "abandoned" => Ok(Self::Abandoned),
            _ => Err(ScanRunStatusParseError),
        }
    }
}

/// Failure while parsing a persisted scan status.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ScanRunStatusParseError;

impl std::fmt::Display for ScanRunStatusParseError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("invalid scan run status")
    }
}

impl std::error::Error for ScanRunStatusParseError {}

/// One per-root scan projection with its historical display snapshot.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ScanRunProjection {
    scan_run_id: ScanRunId,
    job_run_id: JobRunId,
    library_root_id: LibraryRootId,
    display_name: String,
    safe_location_display: String,
    status: ScanRunStatus,
    started_at_ms: i64,
    completed_at_ms: Option<i64>,
}

impl ScanRunProjection {
    /// Creates one per-root scan projection.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        scan_run_id: ScanRunId,
        job_run_id: JobRunId,
        library_root_id: LibraryRootId,
        display_name: impl Into<String>,
        safe_location_display: impl Into<String>,
        status: ScanRunStatus,
        started_at_ms: i64,
        completed_at_ms: Option<i64>,
    ) -> Self {
        Self {
            scan_run_id,
            job_run_id,
            library_root_id,
            display_name: display_name.into(),
            safe_location_display: safe_location_display.into(),
            status,
            started_at_ms,
            completed_at_ms,
        }
    }

    /// Returns the scan identity.
    pub fn scan_run_id(&self) -> ScanRunId {
        self.scan_run_id
    }

    /// Returns the owning job identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the historical root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the historical display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the bounded historical safe location display.
    pub fn safe_location_display(&self) -> &str {
        &self.safe_location_display
    }

    /// Returns the authoritative per-root status.
    pub fn status(&self) -> ScanRunStatus {
        self.status
    }

    /// Returns the scan start timestamp.
    pub fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }

    /// Returns the scan terminal timestamp.
    pub fn completed_at_ms(&self) -> Option<i64> {
        self.completed_at_ms
    }
}

/// Durable active ownership of one root by one scan.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ActiveScanOwnership {
    job_run_id: JobRunId,
    scan_run_id: ScanRunId,
    owning_job_root_count: u32,
}

impl ActiveScanOwnership {
    /// Creates one active ownership projection.
    pub fn new(job_run_id: JobRunId, scan_run_id: ScanRunId, owning_job_root_count: u32) -> Self {
        Self {
            job_run_id,
            scan_run_id,
            owning_job_root_count,
        }
    }

    /// Returns the owning job identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the active scan identity.
    pub fn scan_run_id(&self) -> ScanRunId {
        self.scan_run_id
    }

    /// Returns the number of roots owned by the owning job.
    pub fn owning_job_root_count(&self) -> u32 {
        self.owning_job_root_count
    }
}

/// Bounded historical root display snapshot used by Jobs detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanRootSummary {
    library_root_id: LibraryRootId,
    display_name: String,
    safe_location_display: String,
}

impl LibraryScanRootSummary {
    /// Creates one bounded historical root summary.
    pub fn new(
        library_root_id: LibraryRootId,
        display_name: impl Into<String>,
        safe_location_display: impl Into<String>,
    ) -> Self {
        Self {
            library_root_id,
            display_name: display_name.into(),
            safe_location_display: safe_location_display.into(),
        }
    }

    /// Returns the historical root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the historical display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the bounded historical safe location display.
    pub fn safe_location_display(&self) -> &str {
        &self.safe_location_display
    }
}

/// Typed reason one root was excluded from an admitted scan job.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryScanTargetExclusionReason {
    AlreadyScanning,
    NoLongerConfigured,
    InvalidConfiguration,
}

impl LibraryScanTargetExclusionReason {
    /// Returns the canonical serialized reason value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::AlreadyScanning => "already_scanning",
            Self::NoLongerConfigured => "no_longer_configured",
            Self::InvalidConfiguration => "invalid_configuration",
        }
    }
}

/// One durable admission exclusion affecting an accepted job.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanAdmissionExclusion {
    library_root_id: LibraryRootId,
    reason: LibraryScanTargetExclusionReason,
    active_job_run_id: Option<JobRunId>,
    active_scan_run_id: Option<ScanRunId>,
    application_error: Option<ApplicationError>,
}

impl LibraryScanAdmissionExclusion {
    /// Creates one typed admission exclusion.
    pub fn new(
        library_root_id: LibraryRootId,
        reason: LibraryScanTargetExclusionReason,
        active_job_run_id: Option<JobRunId>,
        active_scan_run_id: Option<ScanRunId>,
    ) -> Self {
        Self {
            library_root_id,
            reason,
            active_job_run_id,
            active_scan_run_id,
            application_error: None,
        }
    }

    /// Creates one `InvalidConfiguration` exclusion carrying the canonical
    /// bounded application error.
    pub fn invalid_configuration(
        library_root_id: LibraryRootId,
        application_error: ApplicationError,
    ) -> Self {
        Self {
            library_root_id,
            reason: LibraryScanTargetExclusionReason::InvalidConfiguration,
            active_job_run_id: None,
            active_scan_run_id: None,
            application_error: Some(application_error),
        }
    }

    /// Returns the excluded root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the typed exclusion reason.
    pub fn reason(&self) -> LibraryScanTargetExclusionReason {
        self.reason
    }

    /// Returns the related active job identity, when applicable.
    pub fn active_job_run_id(&self) -> Option<JobRunId> {
        self.active_job_run_id
    }

    /// Returns the related active scan identity, when applicable.
    pub fn active_scan_run_id(&self) -> Option<ScanRunId> {
        self.active_scan_run_id
    }

    /// Returns the bounded `InvalidConfiguration` error, when applicable.
    pub fn application_error(&self) -> Option<&ApplicationError> {
        self.application_error.as_ref()
    }
}

/// Scan-specific structured progress facts.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct ScanProgressFacts {
    phase: Option<String>,
    completed_units: Option<u64>,
    total_units: Option<u64>,
    status_key: Option<String>,
    roots_requested: u32,
    roots_admitted: u32,
    roots_terminal: u32,
    entries_observed: Option<u64>,
    entries_committed: Option<u64>,
    issue_count: Option<u64>,
}

impl ScanProgressFacts {
    /// Creates the scan-specific progress projection.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        phase: Option<String>,
        completed_units: Option<u64>,
        total_units: Option<u64>,
        status_key: Option<String>,
        roots_requested: u32,
        roots_admitted: u32,
        roots_terminal: u32,
        entries_observed: Option<u64>,
        entries_committed: Option<u64>,
        issue_count: Option<u64>,
    ) -> Self {
        Self {
            phase,
            completed_units,
            total_units,
            status_key,
            roots_requested,
            roots_admitted,
            roots_terminal,
            entries_observed,
            entries_committed,
            issue_count,
        }
    }

    /// Returns the current phase.
    pub fn phase(&self) -> Option<&str> {
        self.phase.as_deref()
    }

    /// Returns the completed units.
    pub fn completed_units(&self) -> Option<u64> {
        self.completed_units
    }

    /// Returns the total units.
    pub fn total_units(&self) -> Option<u64> {
        self.total_units
    }

    /// Returns the stable status key.
    pub fn status_key(&self) -> Option<&str> {
        self.status_key.as_deref()
    }

    /// Returns the durable requested-root count.
    pub fn roots_requested(&self) -> u32 {
        self.roots_requested
    }

    /// Returns the durable admitted-root count.
    pub fn roots_admitted(&self) -> u32 {
        self.roots_admitted
    }

    /// Returns the terminal-root count.
    pub fn roots_terminal(&self) -> u32 {
        self.roots_terminal
    }

    /// Returns the observed source-entry count, when known.
    pub fn entries_observed(&self) -> Option<u64> {
        self.entries_observed
    }

    /// Returns the committed source-entry count, when known.
    pub fn entries_committed(&self) -> Option<u64> {
        self.entries_committed
    }

    /// Returns the bounded issue count, when known.
    pub fn issue_count(&self) -> Option<u64> {
        self.issue_count
    }
}

/// Typed operation-specific detail for one job.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum OperationDetail {
    LibraryScan(LibraryScanJobDetail),
    LibraryRefresh(LibraryRefreshJobDetail),
    GameRefresh(GameRefreshJobDetail),
    LibraryResolutionRefresh(LibraryResolutionRefreshJobDetail),
}

/// Typed detail for one composed Library refresh.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRefreshJobDetail {
    trigger: LibraryRefreshTrigger,
    mode: RefreshMode,
    requested_root_ids: Vec<LibraryRootId>,
    scan_runs: Vec<ScanRunProjection>,
    progress: RefreshProgressFacts,
    retry_source_job_run_id: Option<JobRunId>,
    retry_successor_job_run_id: Option<JobRunId>,
}

impl LibraryRefreshJobDetail {
    /// Creates one typed composed-refresh detail.
    pub fn new(
        trigger: LibraryRefreshTrigger,
        mode: RefreshMode,
        requested_root_ids: Vec<LibraryRootId>,
        progress: RefreshProgressFacts,
        retry_source_job_run_id: Option<JobRunId>,
        retry_successor_job_run_id: Option<JobRunId>,
    ) -> Self {
        Self {
            trigger,
            mode,
            requested_root_ids,
            scan_runs: Vec::new(),
            progress,
            retry_source_job_run_id,
            retry_successor_job_run_id,
        }
    }

    /// Attaches the committed scan-run projections owned by this refresh.
    pub fn with_scan_runs(mut self, scan_runs: Vec<ScanRunProjection>) -> Self {
        self.scan_runs = scan_runs;
        self
    }

    /// Returns the retained trigger intent.
    pub const fn trigger(&self) -> LibraryRefreshTrigger {
        self.trigger
    }

    /// Returns the freshness policy.
    pub const fn mode(&self) -> RefreshMode {
        self.mode
    }

    /// Returns the requested root identities in admission order.
    pub fn requested_root_ids(&self) -> &[LibraryRootId] {
        &self.requested_root_ids
    }

    /// Returns the committed scan-run projections.
    pub fn scan_runs(&self) -> &[ScanRunProjection] {
        &self.scan_runs
    }

    /// Returns the latest bounded progress facts.
    pub const fn progress(&self) -> &RefreshProgressFacts {
        &self.progress
    }

    /// Returns the source retry identity, when this is a retry successor.
    pub const fn retry_source_job_run_id(&self) -> Option<JobRunId> {
        self.retry_source_job_run_id
    }

    /// Returns the direct retry successor, when one exists.
    pub const fn retry_successor_job_run_id(&self) -> Option<JobRunId> {
        self.retry_successor_job_run_id
    }
}

/// Typed detail for one bounded Game refresh.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct GameRefreshJobDetail {
    game_ids: Vec<GameId>,
    mode: RefreshMode,
    progress: RefreshProgressFacts,
    retry_source_job_run_id: Option<JobRunId>,
    retry_successor_job_run_id: Option<JobRunId>,
}

impl GameRefreshJobDetail {
    /// Creates one typed Game refresh detail.
    pub fn new(
        game_ids: Vec<GameId>,
        mode: RefreshMode,
        progress: RefreshProgressFacts,
        retry_source_job_run_id: Option<JobRunId>,
        retry_successor_job_run_id: Option<JobRunId>,
    ) -> Self {
        Self {
            game_ids,
            mode,
            progress,
            retry_source_job_run_id,
            retry_successor_job_run_id,
        }
    }

    /// Returns the bounded target set.
    pub fn game_ids(&self) -> &[GameId] {
        &self.game_ids
    }

    /// Returns the freshness policy.
    pub const fn mode(&self) -> RefreshMode {
        self.mode
    }

    /// Returns the latest bounded progress facts.
    pub const fn progress(&self) -> &RefreshProgressFacts {
        &self.progress
    }

    /// Returns the source retry identity, when this is a retry successor.
    pub const fn retry_source_job_run_id(&self) -> Option<JobRunId> {
        self.retry_source_job_run_id
    }

    /// Returns the direct retry successor, when one exists.
    pub const fn retry_successor_job_run_id(&self) -> Option<JobRunId> {
        self.retry_successor_job_run_id
    }
}

/// Typed detail for one local-only Library preference re-resolution.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryResolutionRefreshJobDetail {
    job_run_id: JobRunId,
    settings_revision: u64,
    progress: RefreshProgressFacts,
    retry_source_job_run_id: Option<JobRunId>,
    retry_successor_job_run_id: Option<JobRunId>,
}

impl LibraryResolutionRefreshJobDetail {
    /// Creates one typed local-resolution detail.
    pub fn new(
        job_run_id: JobRunId,
        settings_revision: u64,
        progress: RefreshProgressFacts,
        retry_source_job_run_id: Option<JobRunId>,
        retry_successor_job_run_id: Option<JobRunId>,
    ) -> Self {
        Self {
            job_run_id,
            settings_revision,
            progress,
            retry_source_job_run_id,
            retry_successor_job_run_id,
        }
    }

    /// Returns the owning execution identity.
    pub const fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the committed settings revision captured by the intent.
    pub const fn settings_revision(&self) -> u64 {
        self.settings_revision
    }

    /// Returns the latest bounded progress facts.
    pub const fn progress(&self) -> &RefreshProgressFacts {
        &self.progress
    }

    /// Returns the source retry identity, when this is a retry successor.
    pub const fn retry_source_job_run_id(&self) -> Option<JobRunId> {
        self.retry_source_job_run_id
    }

    /// Returns the direct retry successor, when one exists.
    pub const fn retry_successor_job_run_id(&self) -> Option<JobRunId> {
        self.retry_successor_job_run_id
    }
}

/// Typed LibraryScan operation detail derived from durable admission context.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanJobDetail {
    requested_roots: Vec<LibraryScanRootSummary>,
    admitted_roots: Vec<LibraryScanRootSummary>,
    exclusions: Vec<LibraryScanAdmissionExclusion>,
    scan_runs: Vec<ScanRunProjection>,
    progress: ScanProgressFacts,
    retry_source_job_run_id: Option<JobRunId>,
    retry_successor_job_run_id: Option<JobRunId>,
}

impl LibraryScanJobDetail {
    /// Creates one typed LibraryScan detail.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        requested_roots: Vec<LibraryScanRootSummary>,
        admitted_roots: Vec<LibraryScanRootSummary>,
        exclusions: Vec<LibraryScanAdmissionExclusion>,
        scan_runs: Vec<ScanRunProjection>,
        progress: ScanProgressFacts,
        retry_source_job_run_id: Option<JobRunId>,
        retry_successor_job_run_id: Option<JobRunId>,
    ) -> Self {
        Self {
            requested_roots,
            admitted_roots,
            exclusions,
            scan_runs,
            progress,
            retry_source_job_run_id,
            retry_successor_job_run_id,
        }
    }

    /// Returns the requested root summaries.
    pub fn requested_roots(&self) -> &[LibraryScanRootSummary] {
        &self.requested_roots
    }

    /// Returns the admitted root summaries.
    pub fn admitted_roots(&self) -> &[LibraryScanRootSummary] {
        &self.admitted_roots
    }

    /// Returns the typed admission exclusions.
    pub fn exclusions(&self) -> &[LibraryScanAdmissionExclusion] {
        &self.exclusions
    }

    /// Returns the per-root scan projections.
    pub fn scan_runs(&self) -> &[ScanRunProjection] {
        &self.scan_runs
    }

    /// Returns the scan-specific structured progress facts.
    pub fn progress(&self) -> &ScanProgressFacts {
        &self.progress
    }

    /// Returns the retry source identity, when applicable.
    pub fn retry_source_job_run_id(&self) -> Option<JobRunId> {
        self.retry_source_job_run_id
    }

    /// Returns the retry successor identity, when applicable.
    pub fn retry_successor_job_run_id(&self) -> Option<JobRunId> {
        self.retry_successor_job_run_id
    }
}

/// Capability-neutral job detail with typed operation-specific detail.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct JobDetail {
    job: JobRunProjection,
    operation_detail: OperationDetail,
}

impl JobDetail {
    /// Creates one authoritative job detail.
    pub fn new(job: JobRunProjection, operation_detail: OperationDetail) -> Self {
        Self {
            job,
            operation_detail,
        }
    }

    /// Returns the generic execution projection.
    pub fn job(&self) -> &JobRunProjection {
        &self.job
    }

    /// Returns the typed operation detail.
    pub fn operation_detail(&self) -> &OperationDetail {
        &self.operation_detail
    }
}

/// Minimal identity-only handle returned by successful background admission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationHandle {
    job_run_id: JobRunId,
    operation_type: String,
}

impl OperationHandle {
    /// Creates one admission handle.
    pub fn new(job_run_id: JobRunId, operation_type: impl Into<String>) -> Self {
        Self {
            job_run_id,
            operation_type: operation_type.into(),
        }
    }

    /// Returns the canonical execution identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the stable logical operation type.
    pub fn operation_type(&self) -> &str {
        &self.operation_type
    }
}

/// Frozen immutable execution plan for one library scan.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanExecutionPlan {
    library_root_id: LibraryRootId,
    job_run_id: JobRunId,
    scan_run_id: ScanRunId,
    root_locator: RootLocator,
    display_name: String,
    safe_location_display: String,
    source_config_revision: u32,
    root_config_revision: u32,
    discovery_policy_revision: u32,
    started_at_ms: i64,
}

impl LibraryScanExecutionPlan {
    /// Creates one immutable scan plan.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        library_root_id: LibraryRootId,
        job_run_id: JobRunId,
        scan_run_id: ScanRunId,
        root_locator: RootLocator,
        display_name: impl Into<String>,
        safe_location_display: impl Into<String>,
        source_config_revision: u32,
        root_config_revision: u32,
        discovery_policy_revision: u32,
        started_at_ms: i64,
    ) -> Self {
        Self {
            library_root_id,
            job_run_id,
            scan_run_id,
            root_locator,
            display_name: display_name.into(),
            safe_location_display: safe_location_display.into(),
            source_config_revision,
            root_config_revision,
            discovery_policy_revision,
            started_at_ms,
        }
    }

    /// Returns the configured root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the owning job identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the admitted scan identity.
    pub fn scan_run_id(&self) -> ScanRunId {
        self.scan_run_id
    }

    /// Returns the frozen opaque root locator.
    pub fn root_locator(&self) -> &RootLocator {
        &self.root_locator
    }

    /// Returns the frozen display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the frozen safe location display.
    pub fn safe_location_display(&self) -> &str {
        &self.safe_location_display
    }

    /// Returns the frozen source configuration revision.
    pub fn source_config_revision(&self) -> u32 {
        self.source_config_revision
    }

    /// Returns the frozen root configuration revision.
    pub fn root_config_revision(&self) -> u32 {
        self.root_config_revision
    }

    /// Returns the frozen discovery policy revision.
    pub fn discovery_policy_revision(&self) -> u32 {
        self.discovery_policy_revision
    }

    /// Returns the frozen scan start timestamp.
    pub fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }
}

/// One admitted scan execution payload returned to the runtime.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AdmittedScan {
    job_run_id: JobRunId,
    scan_run_id: ScanRunId,
    plan: LibraryScanExecutionPlan,
}

impl AdmittedScan {
    /// Creates one admitted scan payload.
    pub fn new(
        job_run_id: JobRunId,
        scan_run_id: ScanRunId,
        plan: LibraryScanExecutionPlan,
    ) -> Self {
        Self {
            job_run_id,
            scan_run_id,
            plan,
        }
    }

    /// Returns the job identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the scan identity.
    pub fn scan_run_id(&self) -> ScanRunId {
        self.scan_run_id
    }

    /// Returns the frozen execution plan.
    pub fn plan(&self) -> &LibraryScanExecutionPlan {
        &self.plan
    }
}

/// Typed outcome of one single-root scan admission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum StartLibraryScanResult {
    /// The execution was durably admitted.
    Admitted(OperationHandle),
    /// The root already has an active scan owner.
    AlreadyScanning {
        library_root_id: LibraryRootId,
        active_job_run_id: JobRunId,
        active_scan_run_id: ScanRunId,
    },
}

/// Application-level admission result carrying the frozen execution payload.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanAdmissionResult {
    outcome: StartLibraryScanResult,
    admitted: Option<AdmittedScan>,
}

impl LibraryScanAdmissionResult {
    /// Creates a non-admitted admission result.
    pub fn not_admitted(outcome: StartLibraryScanResult) -> Self {
        Self {
            outcome,
            admitted: None,
        }
    }

    /// Creates an admitted admission result with its execution payload.
    pub fn admitted(handle: OperationHandle, admitted: AdmittedScan) -> Self {
        Self {
            outcome: StartLibraryScanResult::Admitted(handle),
            admitted: Some(admitted),
        }
    }

    /// Returns the caller-visible typed outcome.
    pub fn outcome(&self) -> &StartLibraryScanResult {
        &self.outcome
    }

    /// Returns the admitted execution payload, if admission succeeded.
    pub fn admitted_scan(&self) -> Option<&AdmittedScan> {
        self.admitted.as_ref()
    }
}

/// One accepted multi-root Scan All execution payload.
///
/// One job owns the ordered collection of admitted child plans. The order is
/// canonical historical `LibraryRootId` ascending and is therefore durable and
/// reproducible from the admitted target rows alone.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AdmittedLibraryScanJob {
    job_run_id: JobRunId,
    plans: Vec<LibraryScanExecutionPlan>,
}

impl AdmittedLibraryScanJob {
    /// Creates one accepted multi-root job from its ordered child plans.
    pub fn new(job_run_id: JobRunId, plans: Vec<LibraryScanExecutionPlan>) -> Self {
        Self { job_run_id, plans }
    }

    /// Returns the owning job identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the admitted child plans in canonical execution order.
    pub fn plans(&self) -> &[LibraryScanExecutionPlan] {
        &self.plans
    }
}

/// Typed caller-visible outcome of one Scan All admission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum StartLibraryScanAllResult {
    /// One durable job was admitted for all eligible roots.
    Admitted {
        operation_handle: OperationHandle,
        admitted_roots: Vec<LibraryRootId>,
        exclusions: Vec<LibraryScanAdmissionExclusion>,
    },
    /// No configured root was eligible, so no job was created.
    NothingEligible {
        exclusions: Vec<LibraryScanAdmissionExclusion>,
    },
}

impl StartLibraryScanAllResult {
    /// Returns the admission handle for `Admitted`.
    pub fn operation_handle(&self) -> Option<&OperationHandle> {
        match self {
            Self::Admitted {
                operation_handle, ..
            } => Some(operation_handle),
            Self::NothingEligible { .. } => None,
        }
    }

    /// Returns admitted root identities in canonical order.
    pub fn admitted_roots(&self) -> &[LibraryRootId] {
        match self {
            Self::Admitted { admitted_roots, .. } => admitted_roots,
            Self::NothingEligible { .. } => &[],
        }
    }

    /// Returns typed admission exclusions.
    pub fn exclusions(&self) -> &[LibraryScanAdmissionExclusion] {
        match self {
            Self::Admitted { exclusions, .. } => exclusions,
            Self::NothingEligible { exclusions } => exclusions,
        }
    }
}

/// Application-level Scan All admission result.
///
/// `admitted` carries the frozen execution payload only when this request
/// durably created the job. Idempotent request-identity replays return an
/// `Admitted` caller outcome with no fresh registration payload.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanAllAdmissionResult {
    outcome: StartLibraryScanAllResult,
    admitted: Option<AdmittedLibraryScanJob>,
}

/// Application-owned admission result for one composed Library refresh.
///
/// A refresh is one top-level `library_refresh` operation. Its internal scan
/// plans are retained only so the runtime can register the already-admitted
/// work; callers receive the canonical operation handle and never a
/// Scan-All-shaped result.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryRefreshAdmissionResult {
    outcome: LibraryRefreshAdmissionOutcome,
    admitted: Option<AdmittedLibraryScanJob>,
    admitted_job_exclusion_count: usize,
}

impl LibraryRefreshAdmissionResult {
    /// Creates a successful refresh admission with its frozen child plans.
    pub fn admitted(
        handle: OperationHandle,
        admitted: AdmittedLibraryScanJob,
        exclusion_count: usize,
    ) -> Self {
        Self {
            outcome: LibraryRefreshAdmissionOutcome::Admitted(handle),
            admitted: Some(admitted),
            admitted_job_exclusion_count: exclusion_count,
        }
    }

    /// Creates a definite no-admission outcome with its authoritative
    /// exclusions. The runtime maps this to a published application error at
    /// the public handle boundary.
    pub fn not_admitted(exclusions: Vec<LibraryScanAdmissionExclusion>) -> Self {
        Self {
            outcome: LibraryRefreshAdmissionOutcome::NothingEligible { exclusions },
            admitted: None,
            admitted_job_exclusion_count: 0,
        }
    }

    /// Returns the application-owned refresh outcome.
    pub const fn outcome(&self) -> &LibraryRefreshAdmissionOutcome {
        &self.outcome
    }

    /// Returns the newly admitted internal child plans, when present.
    pub fn admitted_job(&self) -> Option<&AdmittedLibraryScanJob> {
        self.admitted.as_ref()
    }

    /// Returns the count of requested roots excluded during admission.
    pub const fn admitted_job_exclusion_count(&self) -> usize {
        self.admitted_job_exclusion_count
    }
}

/// Closed application outcome for one composed refresh admission.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum LibraryRefreshAdmissionOutcome {
    /// One top-level refresh operation was durably admitted.
    Admitted(OperationHandle),
    /// No root could be admitted under the shared root-operation boundary.
    NothingEligible {
        exclusions: Vec<LibraryScanAdmissionExclusion>,
    },
}

impl LibraryScanAllAdmissionResult {
    /// Creates a non-admitted or replay-only Scan All outcome.
    pub fn not_admitted(outcome: StartLibraryScanAllResult) -> Self {
        Self {
            outcome,
            admitted: None,
        }
    }

    /// Creates an admitted Scan All outcome with its execution payload.
    pub fn admitted(
        handle: OperationHandle,
        admitted_roots: Vec<LibraryRootId>,
        exclusions: Vec<LibraryScanAdmissionExclusion>,
        admitted: AdmittedLibraryScanJob,
    ) -> Self {
        Self {
            outcome: StartLibraryScanAllResult::Admitted {
                operation_handle: handle,
                admitted_roots,
                exclusions,
            },
            admitted: Some(admitted),
        }
    }

    /// Returns the caller-visible typed outcome.
    pub fn outcome(&self) -> &StartLibraryScanAllResult {
        &self.outcome
    }

    /// Returns the fresh execution payload, if this request created the job.
    pub fn admitted_job(&self) -> Option<&AdmittedLibraryScanJob> {
        self.admitted.as_ref()
    }
}

/// The reason a Scan All client request identity is invalid.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryScanAllRequestIdentityError {
    /// The identity is empty.
    Empty,
    /// The identity exceeds the bounded durable length.
    TooLong,
    /// The identity contains a non-ASCII or non-identifier character.
    InvalidCharacter,
}

impl std::fmt::Display for LibraryScanAllRequestIdentityError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Empty => formatter.write_str("scan all request identity is empty"),
            Self::TooLong => formatter.write_str("scan all request identity is too long"),
            Self::InvalidCharacter => {
                formatter.write_str("scan all request identity contains an invalid character")
            }
        }
    }
}

impl std::error::Error for LibraryScanAllRequestIdentityError {}

/// Durable client-generated identity used to reconcile one ambiguous Scan All
/// transport outcome. It is operation metadata, never a second Job identity.
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct LibraryScanAllRequestIdentity(String);

impl LibraryScanAllRequestIdentity {
    /// Maximum persisted identity length in UTF-8 bytes.
    pub const MAX_BYTES: usize = 256;

    /// Returns the canonical durable representation.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<&str> for LibraryScanAllRequestIdentity {
    type Error = LibraryScanAllRequestIdentityError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        if value.is_empty() {
            return Err(LibraryScanAllRequestIdentityError::Empty);
        }
        if value.len() > Self::MAX_BYTES {
            return Err(LibraryScanAllRequestIdentityError::TooLong);
        }
        if !value.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.')
        }) {
            return Err(LibraryScanAllRequestIdentityError::InvalidCharacter);
        }
        Ok(Self(value.to_owned()))
    }
}

impl TryFrom<String> for LibraryScanAllRequestIdentity {
    type Error = LibraryScanAllRequestIdentityError;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::try_from(value.as_str())
    }
}

/// Authoritative replay lookup for one Scan All request identity.
pub trait LibraryScanAllRequestLookup {
    /// Returns the already accepted Scan All outcome for `request_identity`,
    /// or `None` when no admission is durably associated with it.
    fn find_existing(
        &self,
        context: &OperationContext,
        request_identity: &LibraryScanAllRequestIdentity,
    ) -> Result<Option<StartLibraryScanAllResult>, ApplicationError>;
}

/// Closed Jobs list scopes for Slice 002.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ListJobsScope {
    Active,
    RecentTerminal { offset: u32, page_size: u32 },
}

/// One bounded Jobs list query.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ListJobsQuery {
    scope: ListJobsScope,
}

impl ListJobsQuery {
    /// Creates one closed-scope Jobs list query.
    pub const fn new(scope: ListJobsScope) -> Self {
        Self { scope }
    }

    /// Returns the requested scope.
    pub const fn scope(self) -> ListJobsScope {
        self.scope
    }
}

/// Typed outcome of one cancel request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CancelJobResult {
    /// Durable cancellation intent was accepted.
    CancellationRequested,
    /// Current authoritative state no longer permits cancellation.
    NoLongerCancellable,
}

/// One retry request for a historical library scan execution.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RetryJobCommand {
    job_run_id: JobRunId,
}

impl RetryJobCommand {
    /// Creates a retry request for one historical execution identity.
    pub const fn new(job_run_id: JobRunId) -> Self {
        Self { job_run_id }
    }

    /// Returns the historical execution identity.
    pub const fn job_run_id(self) -> JobRunId {
        self.job_run_id
    }
}

/// Typed outcome of one retry request.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RetryJobResult {
    /// A new durable execution was admitted.
    Admitted(OperationHandle),
    /// The source run already has one direct retry successor.
    AlreadyRetried(JobRunId),
    /// The request was not admitted with a typed reason.
    NotAdmitted(RetryNotAdmittedReason),
}

/// Typed reason one retry request was not admitted.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RetryNotAdmittedReason {
    /// The source execution is not terminal.
    SourceRunNotTerminal,
    /// The operation type or terminal state is not retryable.
    OperationNotRetryable,
    /// No original target remains currently eligible.
    NoEligibleTargets(Vec<LibraryScanAdmissionExclusion>),
}

/// Application-level retry result carrying the frozen execution payload.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RetryJobAdmissionResult {
    outcome: RetryJobResult,
    admitted: Option<AdmittedScan>,
    admitted_job: Option<AdmittedLibraryScanJob>,
    admitted_job_exclusion_count: usize,
}

impl RetryJobAdmissionResult {
    /// Creates a non-admitted retry outcome.
    pub fn not_admitted(outcome: RetryJobResult) -> Self {
        Self {
            outcome,
            admitted: None,
            admitted_job: None,
            admitted_job_exclusion_count: 0,
        }
    }

    /// Creates an admitted retry outcome with its execution payload.
    pub fn admitted(handle: OperationHandle, admitted: AdmittedScan) -> Self {
        Self {
            outcome: RetryJobResult::Admitted(handle),
            admitted: Some(admitted),
            admitted_job: None,
            admitted_job_exclusion_count: 0,
        }
    }

    /// Creates an admitted multi-root Scan All retry outcome.
    pub fn admitted_scan_all(
        handle: OperationHandle,
        admitted_job: AdmittedLibraryScanJob,
        exclusion_count: usize,
    ) -> Self {
        Self {
            outcome: RetryJobResult::Admitted(handle),
            admitted: None,
            admitted_job: Some(admitted_job),
            admitted_job_exclusion_count: exclusion_count,
        }
    }

    /// Returns the caller-visible typed outcome.
    pub fn outcome(&self) -> &RetryJobResult {
        &self.outcome
    }

    /// Returns the admitted execution payload, if admission succeeded.
    pub fn admitted_scan(&self) -> Option<&AdmittedScan> {
        self.admitted.as_ref()
    }

    /// Returns the admitted multi-root execution payload, if applicable.
    pub fn admitted_job(&self) -> Option<&AdmittedLibraryScanJob> {
        self.admitted_job.as_ref()
    }

    /// Returns the number of durable exclusions carried by an admitted Scan
    /// All retry payload.
    pub fn admitted_job_exclusion_count(&self) -> usize {
        self.admitted_job_exclusion_count
    }
}

/// Transaction-scoped generic job-run repository port.
pub trait JobRunRepository {
    /// Inserts one queued job execution and returns its stable identity.
    fn insert(&mut self, new: NewJobRun) -> Result<JobRunId, PersistenceError>;

    /// Persists one durable linear retry link from a source run to its direct
    /// successor. Both identities must reference existing job runs; the
    /// durable schema enforces at most one direct successor per source and at
    /// most one source per successor.
    fn insert_retry_link(
        &mut self,
        source_job_run_id: JobRunId,
        successor_job_run_id: JobRunId,
    ) -> Result<(), PersistenceError>;

    /// Persists accepted cancellation intent for an active run. Returns
    /// `None` when the identity is missing, `false` when the run is already
    /// terminal or cancellation was already requested, and `true` when the
    /// intent was newly persisted.
    fn request_cancellation(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Option<bool>, PersistenceError>;

    /// Persists one generic lifecycle transition.
    fn set_state(
        &mut self,
        job_run_id: JobRunId,
        state: JobRunState,
        timestamp_ms: i64,
    ) -> Result<bool, PersistenceError>;

    /// Persists structured phase-local progress.
    fn set_progress(
        &mut self,
        job_run_id: JobRunId,
        progress: &JobProgress,
    ) -> Result<bool, PersistenceError>;

    /// Persists a terminal failure payload for one run.
    fn set_terminal_failure(
        &mut self,
        job_run_id: JobRunId,
        state: JobRunState,
        terminal_error_code: Option<String>,
        terminal_safe_context: Option<String>,
        timestamp_ms: i64,
    ) -> Result<bool, PersistenceError>;

    /// Persists the immutable intent for a composed Library refresh. The
    /// default keeps older application test doubles source-compatible.
    fn insert_library_refresh_intent(
        &mut self,
        _job_run_id: JobRunId,
        _trigger: LibraryRefreshTrigger,
        _mode: RefreshMode,
    ) -> Result<(), PersistenceError> {
        Ok(())
    }

    /// Persists the bounded Game target set for one Game refresh.
    fn insert_game_refresh_intent(
        &mut self,
        _job_run_id: JobRunId,
        _game_ids: &[GameId],
        _mode: RefreshMode,
    ) -> Result<(), PersistenceError> {
        Ok(())
    }

    /// Persists the settings revision captured by one local-only resolution
    /// refresh.
    fn insert_library_resolution_refresh_intent(
        &mut self,
        _job_run_id: JobRunId,
        _settings_revision: u64,
    ) -> Result<(), PersistenceError> {
        Ok(())
    }
}

/// One new root-specific scan execution record.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NewScanRun {
    job_run_id: JobRunId,
    library_root_id: LibraryRootId,
    root_locator: RootLocator,
    display_name: String,
    safe_location_display: String,
    source_config_revision: u32,
    root_config_revision: u32,
    started_at_ms: i64,
}

impl NewScanRun {
    /// Creates one active scan record from the frozen plan.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        job_run_id: JobRunId,
        library_root_id: LibraryRootId,
        root_locator: RootLocator,
        display_name: impl Into<String>,
        safe_location_display: impl Into<String>,
        source_config_revision: u32,
        root_config_revision: u32,
        started_at_ms: i64,
    ) -> Self {
        Self {
            job_run_id,
            library_root_id,
            root_locator,
            display_name: display_name.into(),
            safe_location_display: safe_location_display.into(),
            source_config_revision,
            root_config_revision,
            started_at_ms,
        }
    }

    /// Returns the owning job identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the configured root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the frozen opaque root locator.
    pub fn root_locator(&self) -> &RootLocator {
        &self.root_locator
    }

    /// Returns the frozen display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the frozen safe location display.
    pub fn safe_location_display(&self) -> &str {
        &self.safe_location_display
    }

    /// Returns the frozen source configuration revision.
    pub fn source_config_revision(&self) -> u32 {
        self.source_config_revision
    }

    /// Returns the frozen root configuration revision.
    pub fn root_config_revision(&self) -> u32 {
        self.root_config_revision
    }

    /// Returns the scan start timestamp.
    pub fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }
}

/// Transaction-scoped scan-run repository port.
pub trait ScanRunRepository {
    /// Inserts one durably active scan record.
    fn insert(&mut self, new: NewScanRun) -> Result<ScanRunId, PersistenceError>;

    /// Terminalizes one scan record.
    fn set_status(
        &mut self,
        scan_run_id: ScanRunId,
        status: ScanRunStatus,
        completed_at_ms: Option<i64>,
        failure_reason: Option<String>,
    ) -> Result<bool, PersistenceError>;

    /// Persists structured scan-run progress counters. Returns `false` when
    /// the scan identity is missing.
    fn set_progress_facts(
        &mut self,
        scan_run_id: ScanRunId,
        entries_observed: u64,
        entries_committed: u64,
        issue_count: u64,
    ) -> Result<bool, PersistenceError>;

    /// Returns the active owner of one root, if any.
    fn find_active_ownership(
        &mut self,
        library_root_id: LibraryRootId,
    ) -> Result<Option<ActiveScanOwnership>, PersistenceError>;

    /// Returns the most recent terminal scan summary for one root.
    fn find_last_scan(
        &mut self,
        library_root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootLastScanSummary>, PersistenceError>;

    /// Lists the per-root scan projections owned by one job.
    fn list_by_job(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Vec<ScanRunProjection>, PersistenceError>;
}

/// Durable admission-target kind.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryScanTargetKind {
    Requested,
    Admitted,
    Excluded,
}

impl LibraryScanTargetKind {
    /// Returns the canonical serialized kind value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Requested => "requested",
            Self::Admitted => "admitted",
            Self::Excluded => "excluded",
        }
    }
}

/// One durable library-scan admission target row.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NewLibraryScanTarget {
    job_run_id: JobRunId,
    kind: LibraryScanTargetKind,
    library_root_id: LibraryRootId,
    display_name: String,
    safe_location_display: String,
    scan_run_id: Option<ScanRunId>,
    exclusion: Option<LibraryScanAdmissionExclusion>,
}

impl NewLibraryScanTarget {
    /// Creates one durable admission target row.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        job_run_id: JobRunId,
        kind: LibraryScanTargetKind,
        library_root_id: LibraryRootId,
        display_name: impl Into<String>,
        safe_location_display: impl Into<String>,
        scan_run_id: Option<ScanRunId>,
        exclusion: Option<LibraryScanAdmissionExclusion>,
    ) -> Self {
        Self {
            job_run_id,
            kind,
            library_root_id,
            display_name: display_name.into(),
            safe_location_display: safe_location_display.into(),
            scan_run_id,
            exclusion,
        }
    }

    /// Returns the owning job identity.
    pub fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the target kind.
    pub fn kind(&self) -> LibraryScanTargetKind {
        self.kind
    }

    /// Returns the historical root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the historical display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the historical safe location display.
    pub fn safe_location_display(&self) -> &str {
        &self.safe_location_display
    }

    /// Returns the admitted scan identity, when admitted.
    pub fn scan_run_id(&self) -> Option<ScanRunId> {
        self.scan_run_id
    }

    /// Returns the typed exclusion, when excluded.
    pub fn exclusion(&self) -> Option<&LibraryScanAdmissionExclusion> {
        self.exclusion.as_ref()
    }
}

/// One persisted library-scan admission target.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanTarget {
    kind: LibraryScanTargetKind,
    library_root_id: LibraryRootId,
    display_name: String,
    safe_location_display: String,
    scan_run_id: Option<ScanRunId>,
    exclusion: Option<LibraryScanAdmissionExclusion>,
}

impl LibraryScanTarget {
    /// Creates one loaded admission target.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        kind: LibraryScanTargetKind,
        library_root_id: LibraryRootId,
        display_name: impl Into<String>,
        safe_location_display: impl Into<String>,
        scan_run_id: Option<ScanRunId>,
        exclusion: Option<LibraryScanAdmissionExclusion>,
    ) -> Self {
        Self {
            kind,
            library_root_id,
            display_name: display_name.into(),
            safe_location_display: safe_location_display.into(),
            scan_run_id,
            exclusion,
        }
    }

    /// Returns the target kind.
    pub fn kind(&self) -> LibraryScanTargetKind {
        self.kind
    }

    /// Returns the historical root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the historical display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the historical safe location display.
    pub fn safe_location_display(&self) -> &str {
        &self.safe_location_display
    }

    /// Returns the admitted scan identity, when applicable.
    pub fn scan_run_id(&self) -> Option<ScanRunId> {
        self.scan_run_id
    }

    /// Returns the typed exclusion, when applicable.
    pub fn exclusion(&self) -> Option<&LibraryScanAdmissionExclusion> {
        self.exclusion.as_ref()
    }
}

/// Transaction-scoped library-scan admission-target repository port.
pub trait LibraryScanTargetRepository {
    /// Inserts one durable admission target row.
    fn insert(&mut self, target: NewLibraryScanTarget) -> Result<(), PersistenceError>;

    /// Loads all admission targets for one job.
    fn list_by_job(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Vec<LibraryScanTarget>, PersistenceError>;
}

/// Operation-specific LibraryScan invocation vocabulary.
///
/// The vocabulary preserves the original requested intent so future Scan All
/// invocations can be reconstructed and retried distinctly from single-root
/// scans. Slice 006 extends this enum with Scan All invocation kinds.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryScanInvocationKind {
    /// A first single-root scan request.
    InitialSingleRoot,
    /// A retry that reconstructs one original single-root request.
    RetrySingleRoot,
    /// A first multi-root Scan All request.
    InitialScanAll,
    /// A retry that reconstructs one original multi-root Scan All request.
    RetryScanAll,
    /// The internal source-discovery stage of one composed Library refresh.
    InitialLibraryRefresh,
    /// A retry that reconstructs one composed Library refresh.
    RetryLibraryRefresh,
}

impl LibraryScanInvocationKind {
    /// Returns the canonical serialized value.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::InitialSingleRoot => "initial_single_root",
            Self::RetrySingleRoot => "retry_single_root",
            Self::InitialScanAll => "initial_scan_all",
            Self::RetryScanAll => "retry_scan_all",
            Self::InitialLibraryRefresh => "initial_library_refresh",
            Self::RetryLibraryRefresh => "retry_library_refresh",
        }
    }
}

/// Failure while parsing a persisted LibraryScan invocation kind.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LibraryScanInvocationKindParseError;

impl std::fmt::Display for LibraryScanInvocationKindParseError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("invalid library scan invocation kind")
    }
}

impl std::error::Error for LibraryScanInvocationKindParseError {}

impl TryFrom<&str> for LibraryScanInvocationKind {
    type Error = LibraryScanInvocationKindParseError;

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "initial_single_root" => Ok(Self::InitialSingleRoot),
            "retry_single_root" => Ok(Self::RetrySingleRoot),
            "initial_scan_all" => Ok(Self::InitialScanAll),
            "retry_scan_all" => Ok(Self::RetryScanAll),
            "initial_library_refresh" => Ok(Self::InitialLibraryRefresh),
            "retry_library_refresh" => Ok(Self::RetryLibraryRefresh),
            _ => Err(LibraryScanInvocationKindParseError),
        }
    }
}

/// Immutable LibraryScan admission-context facts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanAdmissionContext {
    job_run_id: JobRunId,
    invocation_kind: LibraryScanInvocationKind,
    retry_source_job_run_id: Option<JobRunId>,
    scan_all_request_identity: Option<LibraryScanAllRequestIdentity>,
}

impl LibraryScanAdmissionContext {
    /// Creates one loaded admission-context record.
    pub const fn new(
        job_run_id: JobRunId,
        invocation_kind: LibraryScanInvocationKind,
        retry_source_job_run_id: Option<JobRunId>,
    ) -> Self {
        Self {
            job_run_id,
            invocation_kind,
            retry_source_job_run_id,
            scan_all_request_identity: None,
        }
    }

    /// Creates one loaded Scan All admission-context record carrying the
    /// durable client request identity.
    pub const fn with_scan_all_request_identity(
        job_run_id: JobRunId,
        invocation_kind: LibraryScanInvocationKind,
        retry_source_job_run_id: Option<JobRunId>,
        scan_all_request_identity: LibraryScanAllRequestIdentity,
    ) -> Self {
        Self {
            job_run_id,
            invocation_kind,
            retry_source_job_run_id,
            scan_all_request_identity: Some(scan_all_request_identity),
        }
    }

    /// Returns the owning job identity.
    pub const fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the invocation kind.
    pub const fn invocation_kind(&self) -> LibraryScanInvocationKind {
        self.invocation_kind
    }

    /// Returns the immutable retry source identity, when this run is a retry.
    pub const fn retry_source_job_run_id(&self) -> Option<JobRunId> {
        self.retry_source_job_run_id
    }

    /// Returns the durable Scan All request identity, when applicable.
    pub const fn scan_all_request_identity(&self) -> Option<&LibraryScanAllRequestIdentity> {
        self.scan_all_request_identity.as_ref()
    }
}

/// One new immutable LibraryScan admission-context record.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NewLibraryScanAdmissionContext {
    job_run_id: JobRunId,
    invocation_kind: LibraryScanInvocationKind,
    retry_source_job_run_id: Option<JobRunId>,
    scan_all_request_identity: Option<LibraryScanAllRequestIdentity>,
}

impl NewLibraryScanAdmissionContext {
    /// Creates one new admission-context insert.
    pub const fn new(
        job_run_id: JobRunId,
        invocation_kind: LibraryScanInvocationKind,
        retry_source_job_run_id: Option<JobRunId>,
    ) -> Self {
        Self {
            job_run_id,
            invocation_kind,
            retry_source_job_run_id,
            scan_all_request_identity: None,
        }
    }

    /// Creates one new Scan All admission-context insert carrying the durable
    /// client request identity.
    pub const fn with_scan_all_request_identity(
        job_run_id: JobRunId,
        invocation_kind: LibraryScanInvocationKind,
        retry_source_job_run_id: Option<JobRunId>,
        scan_all_request_identity: LibraryScanAllRequestIdentity,
    ) -> Self {
        Self {
            job_run_id,
            invocation_kind,
            retry_source_job_run_id,
            scan_all_request_identity: Some(scan_all_request_identity),
        }
    }

    /// Returns the owning job identity.
    pub const fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the invocation kind.
    pub const fn invocation_kind(&self) -> LibraryScanInvocationKind {
        self.invocation_kind
    }

    /// Returns the immutable retry source identity, when this run is a retry.
    pub const fn retry_source_job_run_id(&self) -> Option<JobRunId> {
        self.retry_source_job_run_id
    }

    /// Returns the durable Scan All request identity, when applicable.
    pub const fn scan_all_request_identity(&self) -> Option<&LibraryScanAllRequestIdentity> {
        self.scan_all_request_identity.as_ref()
    }
}

/// Transaction-scoped LibraryScan admission-context repository port.
pub trait LibraryScanAdmissionContextRepository {
    /// Inserts one immutable admission-context record.
    fn insert(&mut self, new: NewLibraryScanAdmissionContext) -> Result<(), PersistenceError>;

    /// Loads the immutable admission context for one job, if present.
    fn get_by_job(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Option<LibraryScanAdmissionContext>, PersistenceError>;
}

/// Mutually exclusive coordinates for a provider-native or derived source entry.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum SourceEntryCoordinates {
    /// Coordinates interpreted by the source provider.
    Provider {
        relative_locator: RelativeSourceLocator,
        locator_key: SourceLocatorKey,
        provider_native_identity: Option<String>,
        source_fingerprint: Option<String>,
    },
    /// Coordinates interpreted only by the owning transformation adapter.
    Derived {
        derived_locator: DerivedLocator,
        derived_entry_key: DerivedEntryKey,
        derived_fingerprint: DerivedFingerprint,
        transformation_id: String,
        transformation_revision: u32,
    },
}

/// One new persisted positive source observation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NewSourceEntry {
    source_entry_id: Option<SourceEntryId>,
    library_root_id: LibraryRootId,
    parent_source_entry_id: Option<SourceEntryId>,
    display_name: String,
    display_location: String,
    kind: crate::sources::SourceEntryKind,
    classification: crate::sources::SourceEntryClassification,
    coordinates: SourceEntryCoordinates,
    last_observed_scan_id: ScanRunId,
    created_at: i64,
    updated_at: i64,
}

impl NewSourceEntry {
    /// Creates one provider-native positive observation insert.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        relative_locator: RelativeSourceLocator,
        locator_key: SourceLocatorKey,
        display_name: impl Into<String>,
        display_location: impl Into<String>,
        kind: crate::sources::SourceEntryKind,
        classification: crate::sources::SourceEntryClassification,
        provider_native_identity: Option<String>,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self {
            source_entry_id: None,
            library_root_id,
            parent_source_entry_id,
            display_name: display_name.into(),
            display_location: display_location.into(),
            kind,
            classification,
            coordinates: SourceEntryCoordinates::Provider {
                relative_locator,
                locator_key,
                provider_native_identity,
                source_fingerprint,
            },
            last_observed_scan_id,
            created_at: 0,
            updated_at: 0,
        }
    }

    /// Creates one transformation-derived positive observation insert.
    #[allow(clippy::too_many_arguments)]
    pub fn new_derived(
        source_entry_id: SourceEntryId,
        library_root_id: LibraryRootId,
        parent_source_entry_id: SourceEntryId,
        display_name: String,
        display_location: String,
        kind: crate::sources::SourceEntryKind,
        classification: crate::sources::SourceEntryClassification,
        derived_locator: DerivedLocator,
        derived_entry_key: DerivedEntryKey,
        derived_fingerprint: DerivedFingerprint,
        transformation_id: String,
        transformation_revision: u32,
        last_observed_scan_id: ScanRunId,
        created_at: i64,
        updated_at: i64,
    ) -> Self {
        Self {
            source_entry_id: Some(source_entry_id),
            library_root_id,
            parent_source_entry_id: Some(parent_source_entry_id),
            display_name,
            display_location,
            kind,
            classification,
            coordinates: SourceEntryCoordinates::Derived {
                derived_locator,
                derived_entry_key,
                derived_fingerprint,
                transformation_id,
                transformation_revision,
            },
            last_observed_scan_id,
            created_at,
            updated_at,
        }
    }

    /// Returns the caller-supplied source identity for a derived entry.
    pub fn source_entry_id(&self) -> Option<SourceEntryId> {
        self.source_entry_id
    }

    /// Returns the owning root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the parent source identity, if any.
    pub fn parent_source_entry_id(&self) -> Option<SourceEntryId> {
        self.parent_source_entry_id
    }

    /// Returns the complete provider-or-derived coordinate family.
    pub fn coordinates(&self) -> &SourceEntryCoordinates {
        &self.coordinates
    }

    /// Returns the provider locator, or `None` for a derived entry.
    pub fn relative_locator(&self) -> Option<&RelativeSourceLocator> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider {
                relative_locator, ..
            } => Some(relative_locator),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the provider equality key, or `None` for a derived entry.
    pub fn locator_key(&self) -> Option<&SourceLocatorKey> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { locator_key, .. } => Some(locator_key),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the derived locator, or `None` for a provider entry.
    pub fn derived_locator(&self) -> Option<&DerivedLocator> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                derived_locator, ..
            } => Some(derived_locator),
        }
    }

    /// Returns the derived equality key, or `None` for a provider entry.
    pub fn derived_entry_key(&self) -> Option<&DerivedEntryKey> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                derived_entry_key, ..
            } => Some(derived_entry_key),
        }
    }

    /// Returns the derived fingerprint, or `None` for a provider entry.
    pub fn derived_fingerprint(&self) -> Option<&DerivedFingerprint> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                derived_fingerprint,
                ..
            } => Some(derived_fingerprint),
        }
    }

    /// Returns the transformation identity, or `None` for a provider entry.
    pub fn transformation_id(&self) -> Option<&str> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                transformation_id, ..
            } => Some(transformation_id),
        }
    }

    /// Returns the transformation revision, or `None` for a provider entry.
    pub fn transformation_revision(&self) -> Option<u32> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                transformation_revision,
                ..
            } => Some(*transformation_revision),
        }
    }

    /// Returns the display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the root-relative display location.
    pub fn display_location(&self) -> &str {
        &self.display_location
    }

    /// Returns the persisted source-entry kind.
    pub fn kind(&self) -> crate::sources::SourceEntryKind {
        self.kind
    }

    /// Returns the persisted classification.
    pub fn classification(&self) -> crate::sources::SourceEntryClassification {
        self.classification
    }

    /// Returns the optional provider-native identity.
    pub fn provider_native_identity(&self) -> Option<&str> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider {
                provider_native_identity,
                ..
            } => provider_native_identity.as_deref(),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the optional provider fingerprint.
    pub fn source_fingerprint(&self) -> Option<&str> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider {
                source_fingerprint, ..
            } => source_fingerprint.as_deref(),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the scan that positively observed this entry.
    pub fn last_observed_scan_id(&self) -> ScanRunId {
        self.last_observed_scan_id
    }

    /// Returns the supplied creation timestamp for a derived entry.
    pub fn created_at(&self) -> i64 {
        self.created_at
    }

    /// Returns the supplied update timestamp for a derived entry.
    pub fn updated_at(&self) -> i64 {
        self.updated_at
    }
}

/// One bounded persisted source-entry record used by reconciliation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SourceEntryRecord {
    source_entry_id: SourceEntryId,
    parent_source_entry_id: Option<SourceEntryId>,
    display_name: String,
    display_location: String,
    kind: crate::sources::SourceEntryKind,
    classification: crate::sources::SourceEntryClassification,
    coordinates: SourceEntryCoordinates,
    last_observed_scan_id: ScanRunId,
}

impl SourceEntryRecord {
    /// Creates one provider-native persisted source-entry record.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        source_entry_id: SourceEntryId,
        parent_source_entry_id: Option<SourceEntryId>,
        relative_locator: RelativeSourceLocator,
        locator_key: SourceLocatorKey,
        display_name: impl Into<String>,
        display_location: impl Into<String>,
        kind: crate::sources::SourceEntryKind,
        classification: crate::sources::SourceEntryClassification,
        provider_native_identity: Option<String>,
        source_fingerprint: Option<String>,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self::from_coordinates(
            source_entry_id,
            parent_source_entry_id,
            display_name,
            display_location,
            kind,
            classification,
            SourceEntryCoordinates::Provider {
                relative_locator,
                locator_key,
                provider_native_identity,
                source_fingerprint,
            },
            last_observed_scan_id,
        )
    }

    /// Creates one persisted record from an already-validated coordinate family.
    #[allow(clippy::too_many_arguments)]
    pub fn from_coordinates(
        source_entry_id: SourceEntryId,
        parent_source_entry_id: Option<SourceEntryId>,
        display_name: impl Into<String>,
        display_location: impl Into<String>,
        kind: crate::sources::SourceEntryKind,
        classification: crate::sources::SourceEntryClassification,
        coordinates: SourceEntryCoordinates,
        last_observed_scan_id: ScanRunId,
    ) -> Self {
        Self {
            source_entry_id,
            parent_source_entry_id,
            display_name: display_name.into(),
            display_location: display_location.into(),
            kind,
            classification,
            coordinates,
            last_observed_scan_id,
        }
    }

    /// Returns the stable Argus source identity.
    pub fn source_entry_id(&self) -> SourceEntryId {
        self.source_entry_id
    }

    /// Returns the current parent identity, if any.
    pub fn parent_source_entry_id(&self) -> Option<SourceEntryId> {
        self.parent_source_entry_id
    }

    /// Returns the complete provider-or-derived coordinate family.
    pub fn coordinates(&self) -> &SourceEntryCoordinates {
        &self.coordinates
    }

    /// Returns the provider locator, or `None` for a derived entry.
    pub fn relative_locator(&self) -> Option<&RelativeSourceLocator> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider {
                relative_locator, ..
            } => Some(relative_locator),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the provider equality key, or `None` for a derived entry.
    pub fn locator_key(&self) -> Option<&SourceLocatorKey> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { locator_key, .. } => Some(locator_key),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the derived locator, or `None` for a provider entry.
    pub fn derived_locator(&self) -> Option<&DerivedLocator> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                derived_locator, ..
            } => Some(derived_locator),
        }
    }

    /// Returns the derived equality key, or `None` for a provider entry.
    pub fn derived_entry_key(&self) -> Option<&DerivedEntryKey> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                derived_entry_key, ..
            } => Some(derived_entry_key),
        }
    }

    /// Returns the derived fingerprint, or `None` for a provider entry.
    pub fn derived_fingerprint(&self) -> Option<&DerivedFingerprint> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                derived_fingerprint,
                ..
            } => Some(derived_fingerprint),
        }
    }

    /// Returns the transformation identity, or `None` for a provider entry.
    pub fn transformation_id(&self) -> Option<&str> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                transformation_id, ..
            } => Some(transformation_id),
        }
    }

    /// Returns the transformation revision, or `None` for a provider entry.
    pub fn transformation_revision(&self) -> Option<u32> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider { .. } => None,
            SourceEntryCoordinates::Derived {
                transformation_revision,
                ..
            } => Some(*transformation_revision),
        }
    }

    /// Returns the display name.
    pub fn display_name(&self) -> &str {
        &self.display_name
    }

    /// Returns the root-relative display location.
    pub fn display_location(&self) -> &str {
        &self.display_location
    }

    /// Returns the persisted source-entry kind.
    pub fn kind(&self) -> crate::sources::SourceEntryKind {
        self.kind
    }

    /// Returns the persisted classification.
    pub fn classification(&self) -> crate::sources::SourceEntryClassification {
        self.classification
    }

    /// Returns the optional provider-native identity.
    pub fn provider_native_identity(&self) -> Option<&str> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider {
                provider_native_identity,
                ..
            } => provider_native_identity.as_deref(),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the optional provider fingerprint.
    pub fn source_fingerprint(&self) -> Option<&str> {
        match &self.coordinates {
            SourceEntryCoordinates::Provider {
                source_fingerprint, ..
            } => source_fingerprint.as_deref(),
            SourceEntryCoordinates::Derived { .. } => None,
        }
    }

    /// Returns the scan that positively observed this entry.
    pub fn last_observed_scan_id(&self) -> ScanRunId {
        self.last_observed_scan_id
    }
}

/// Bounded outcome of one provider-native-identity candidate lookup.
///
/// The repository returns `Ambiguous` as soon as two persisted candidates
/// exist for the identity; it never materializes every duplicate. The
/// application decides continuity only from a `Unique` candidate that has
/// not already been positively observed by the current scan.
#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum NativeIdentityMatch {
    /// No persisted entry carries this provider-native identity.
    None,
    /// Exactly one persisted entry carries this identity.
    Unique(SourceEntryRecord),
    /// Two or more persisted entries carry this identity; never guessed.
    Ambiguous,
}

/// Transaction-scoped source-entry repository port.
pub trait SourceEntryRepository {
    /// Upserts one positive observation by root + locator key and returns the
    /// stable source identity.
    fn upsert(&mut self, entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError>;

    /// Upserts one transformation-derived child by its parent and derived
    /// coordinate family. Providers must never reuse this operation's
    /// locator-key equality domain.
    fn upsert_derived(&mut self, entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
        let _ = entry;
        Err(PersistenceError::Unavailable)
    }

    /// Resolves the configured root that owns one persisted source entry.
    ///
    /// Derived reconciliation receives only the parent source identity so the
    /// application does not need to duplicate root ownership in a scope
    /// coordinate. Persistence adapters resolve that ownership from the
    /// already-committed parent row.
    fn library_root_id_for_entry(
        &mut self,
        source_entry_id: SourceEntryId,
    ) -> Result<LibraryRootId, PersistenceError> {
        let _ = source_entry_id;
        Err(PersistenceError::Unavailable)
    }

    /// Finds the current entry at one exact locator within one root.
    fn find_by_locator_key(
        &mut self,
        library_root_id: LibraryRootId,
        locator_key: &SourceLocatorKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError>;

    /// Finds one derived child by transformation revision and derived key.
    fn find_derived_child(
        &mut self,
        parent: SourceEntryId,
        transformation_id: &str,
        revision: u32,
        key: &DerivedEntryKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        let _ = (parent, transformation_id, revision, key);
        Err(PersistenceError::Unavailable)
    }

    /// Classifies persisted provider-native-identity candidates in one root
    /// as none/unique/ambiguous without loading duplicate rows.
    fn find_native_identity(
        &mut self,
        library_root_id: LibraryRootId,
        provider_native_identity: &str,
    ) -> Result<NativeIdentityMatch, PersistenceError>;

    /// Moves one existing entry to a new observation while preserving its
    /// stable source identity. Fails when the entry is not persisted in the
    /// same root.
    fn reconcile_move(
        &mut self,
        entry: NewSourceEntry,
        existing_source_entry_id: SourceEntryId,
    ) -> Result<SourceEntryId, PersistenceError>;

    /// Lists one bounded page of prior direct children for an exact scope.
    /// `None` parent addresses the root scope's direct children.
    fn list_children(
        &mut self,
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<SourceEntryRecord>, PersistenceError>;

    /// Deletes one authoritative subtree (entry plus current descendants)
    /// atomically and reports whether the subtree root existed. Never
    /// touches user filesystem content.
    fn delete_subtree(
        &mut self,
        library_root_id: LibraryRootId,
        source_entry_id: SourceEntryId,
    ) -> Result<bool, PersistenceError>;

    /// Performs the coherent exact-scope absence mutation: deletes prior
    /// direct children of one scope that were not positively observed by
    /// `observed_scan_id`, plus their current descendants, in one bounded
    /// set-based statement. Returns the number of deleted rows.
    fn finalize_absent_scope(
        &mut self,
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        observed_scan_id: ScanRunId,
    ) -> Result<u64, PersistenceError>;

    /// Finalizes absence for one complete derived scope only.
    fn finalize_absent_derived_scope(
        &mut self,
        parent: SourceEntryId,
        transformation_id: &str,
        revision: u32,
        observation_run_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        let _ = (parent, transformation_id, revision, observation_run_id);
        Err(PersistenceError::Unavailable)
    }

    /// Removes all current Argus-owned entries for one root. Never touches
    /// user filesystem content.
    fn delete_for_root(&mut self, library_root_id: LibraryRootId) -> Result<(), PersistenceError>;
}

/// One authoritative scan-run admission reference for a historical root.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ScanAdmissionReference {
    job_run_id: JobRunId,
    scan_run_id: ScanRunId,
}

impl ScanAdmissionReference {
    /// Creates one scan-run admission reference.
    pub const fn new(job_run_id: JobRunId, scan_run_id: ScanRunId) -> Self {
        Self {
            job_run_id,
            scan_run_id,
        }
    }

    /// Returns the owning job identity.
    pub const fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the scan identity.
    pub const fn scan_run_id(&self) -> ScanRunId {
        self.scan_run_id
    }
}

/// Current authoritative eligibility facts for one original retry target.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanTargetEligibility {
    /// The historical root is still configured.
    pub configured: bool,
    /// The current root configuration resolves to a valid scan authority.
    pub configuration_valid: bool,
    /// Another active scan currently owns the root, when applicable.
    pub active_owner: Option<ActiveScanOwnership>,
}

/// Shared outcome of one retry-eligibility evaluation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LibraryScanRetryEvaluation {
    can_retry: bool,
    exclusions: Vec<LibraryScanAdmissionExclusion>,
}

impl LibraryScanRetryEvaluation {
    /// Returns whether at least one original target is currently eligible.
    pub const fn can_retry(&self) -> bool {
        self.can_retry
    }

    /// Returns the typed exclusions for the evaluated targets.
    pub fn exclusions(&self) -> &[LibraryScanAdmissionExclusion] {
        &self.exclusions
    }
}

/// One shared retry-eligibility seam.
///
/// Both the Jobs projection (`canRetry`) and Retry admission consume this
/// function so current-target eligibility semantics cannot drift between
/// control availability and mutation.
pub fn evaluate_retry_eligibility(
    source_state: JobRunState,
    has_successor: bool,
    targets: &[(LibraryScanTarget, LibraryScanTargetEligibility)],
) -> LibraryScanRetryEvaluation {
    evaluate_retry_eligibility_with_trace(None, source_state, has_successor, targets)
}

/// Shared retry-eligibility seam that may carry a bounded `InvalidConfiguration`
/// error for mutation. The projection-only caller passes `None`.
pub fn evaluate_retry_eligibility_with_trace(
    trace_id: Option<crate::TraceId>,
    source_state: JobRunState,
    has_successor: bool,
    targets: &[(LibraryScanTarget, LibraryScanTargetEligibility)],
) -> LibraryScanRetryEvaluation {
    let source_eligible = matches!(
        source_state,
        JobRunState::CompletedWithIssues
            | JobRunState::Failed
            | JobRunState::Cancelled
            | JobRunState::Abandoned
    );
    let mut exclusions = Vec::new();
    let mut any_eligible = false;
    for (target, eligibility) in targets {
        if target.kind() != LibraryScanTargetKind::Requested {
            continue;
        }
        if !eligibility.configured {
            exclusions.push(LibraryScanAdmissionExclusion::new(
                target.library_root_id(),
                LibraryScanTargetExclusionReason::NoLongerConfigured,
                None,
                None,
            ));
        } else if !eligibility.configuration_valid {
            let exclusion = match trace_id {
                Some(trace_id) => LibraryScanAdmissionExclusion::invalid_configuration(
                    target.library_root_id(),
                    invalid_configuration_error(trace_id),
                ),
                None => LibraryScanAdmissionExclusion::new(
                    target.library_root_id(),
                    LibraryScanTargetExclusionReason::InvalidConfiguration,
                    None,
                    None,
                ),
            };
            exclusions.push(exclusion);
        } else if let Some(owner) = eligibility.active_owner {
            exclusions.push(LibraryScanAdmissionExclusion::new(
                target.library_root_id(),
                LibraryScanTargetExclusionReason::AlreadyScanning,
                Some(owner.job_run_id()),
                Some(owner.scan_run_id()),
            ));
        } else {
            any_eligible = true;
        }
    }
    LibraryScanRetryEvaluation {
        can_retry: source_eligible && !has_successor && any_eligible,
        exclusions,
    }
}

fn invalid_configuration_error(trace_id: crate::TraceId) -> ApplicationError {
    let mut safe_context = SafeContext::new();
    safe_context
        .try_insert(
            SafeContextField::TechnicalClass,
            SafeContextValue::TechnicalClass(crate::TechnicalClass::ConfigurationInvalid),
        )
        .expect("technical class is an allowed ConfigurationInvalid field");
    safe_context
        .try_insert(
            SafeContextField::FailureRole,
            SafeContextValue::FailureRole(crate::FailureRole::Primary),
        )
        .expect("failure role is an allowed ConfigurationInvalid field");
    ApplicationError::from_code(ErrorCode::ConfigurationInvalid, trace_id, safe_context)
        .expect("ConfigurationInvalid context follows the published catalog")
}

/// Independent authoritative jobs query port.
pub trait JobsQueries {
    /// Reads one authoritative job detail, or `None` when unknown.
    fn get_job(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<JobDetail>, PersistenceError>;

    /// Lists the bounded active job set.
    fn list_active(&self, context: &OperationContext) -> Result<Vec<JobSummary>, PersistenceError>;

    /// Lists one bounded recent-terminal page, newest first.
    fn list_recent_terminal(
        &self,
        context: &OperationContext,
        offset: u32,
        page_size: u32,
    ) -> Result<JobSummaryPage, PersistenceError>;

    /// Returns the one direct retry successor of a source run, if any.
    fn find_retry_successor(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<JobRunId>, PersistenceError>;

    /// Lists the immutable requested targets of one LibraryScan job, or
    /// `None` when the identity is unknown or not a LibraryScan job.
    fn list_requested_library_scan_targets(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<Vec<LibraryScanTarget>>, PersistenceError>;

    /// Returns the immutable LibraryScan invocation kind for one job, if the
    /// identity is known and is a LibraryScan job.
    fn find_library_scan_invocation_kind(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<LibraryScanInvocationKind>, PersistenceError>;

    /// Finds the newest scan-run admission (active or terminal) owned by one
    /// historical root. This is the Jobs-authoritative fact used to reconcile
    /// an ambiguous Add & Scan transport outcome.
    fn find_scan_admission_for_root(
        &self,
        context: &OperationContext,
        library_root_id: LibraryRootId,
    ) -> Result<Option<ScanAdmissionReference>, PersistenceError>;
}

/// One child scan-run record needed by persistence-only startup recovery.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StaleLibraryScanRun {
    scan_run_id: ScanRunId,
    job_run_id: JobRunId,
    library_root_id: LibraryRootId,
    status: ScanRunStatus,
    started_at_ms: i64,
}

impl StaleLibraryScanRun {
    /// Creates one stale child record.
    pub const fn new(
        scan_run_id: ScanRunId,
        job_run_id: JobRunId,
        library_root_id: LibraryRootId,
        status: ScanRunStatus,
        started_at_ms: i64,
    ) -> Self {
        Self {
            scan_run_id,
            job_run_id,
            library_root_id,
            status,
            started_at_ms,
        }
    }

    /// Returns the child scan identity.
    pub const fn scan_run_id(&self) -> ScanRunId {
        self.scan_run_id
    }

    /// Returns the owning job identity.
    pub const fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the historical root identity.
    pub const fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the durable child status.
    pub const fn status(&self) -> ScanRunStatus {
        self.status
    }

    /// Returns the durable child start timestamp.
    pub const fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }
}

/// One stale active LibraryScan job plus its durable child/scope facts.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StaleLibraryScanJob {
    job_run_id: JobRunId,
    state: JobRunState,
    cancellation_requested: bool,
    scan_runs: Vec<StaleLibraryScanRun>,
    exclusions: Vec<LibraryScanAdmissionExclusion>,
}

impl StaleLibraryScanJob {
    /// Creates one stale active job snapshot.
    pub fn new(
        job_run_id: JobRunId,
        state: JobRunState,
        cancellation_requested: bool,
        scan_runs: Vec<StaleLibraryScanRun>,
        exclusions: Vec<LibraryScanAdmissionExclusion>,
    ) -> Self {
        Self {
            job_run_id,
            state,
            cancellation_requested,
            scan_runs,
            exclusions,
        }
    }

    /// Returns the stale job identity.
    pub const fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the durable active parent state.
    pub const fn state(&self) -> JobRunState {
        self.state
    }

    /// Returns whether durable cancellation intent was already accepted.
    pub const fn cancellation_requested(&self) -> bool {
        self.cancellation_requested
    }

    /// Returns all child scan-run records in canonical root order.
    pub fn scan_runs(&self) -> &[StaleLibraryScanRun] {
        &self.scan_runs
    }

    /// Returns the durable admission exclusions for this job.
    pub fn exclusions(&self) -> &[LibraryScanAdmissionExclusion] {
        &self.exclusions
    }
}

/// Persistence-only query port for startup LibraryScan reconciliation.
pub trait StaleLibraryScanQueries {
    /// Lists every active LibraryScan job and its durable children/exclusions
    /// without resolving providers or performing any user-visible work.
    fn list_stale_library_scan_jobs(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<StaleLibraryScanJob>, PersistenceError>;
}

/// One stale active operation and the durable child facts needed for startup
/// reconciliation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StaleOperationJob {
    operation_type: String,
    job_run_id: JobRunId,
    state: JobRunState,
    cancellation_requested: bool,
    scan_runs: Vec<StaleLibraryScanRun>,
    exclusions: Vec<LibraryScanAdmissionExclusion>,
}

impl StaleOperationJob {
    /// Creates one stale active operation snapshot.
    pub fn new(
        operation_type: impl Into<String>,
        job_run_id: JobRunId,
        state: JobRunState,
        cancellation_requested: bool,
        scan_runs: Vec<StaleLibraryScanRun>,
        exclusions: Vec<LibraryScanAdmissionExclusion>,
    ) -> Self {
        Self {
            operation_type: operation_type.into(),
            job_run_id,
            state,
            cancellation_requested,
            scan_runs,
            exclusions,
        }
    }

    /// Returns the stable operation type.
    pub fn operation_type(&self) -> &str {
        &self.operation_type
    }

    /// Returns the stale operation identity.
    pub const fn job_run_id(&self) -> JobRunId {
        self.job_run_id
    }

    /// Returns the durable active parent state.
    pub const fn state(&self) -> JobRunState {
        self.state
    }

    /// Returns whether durable cancellation intent was already accepted.
    pub const fn cancellation_requested(&self) -> bool {
        self.cancellation_requested
    }

    /// Returns durable child scan records, when the operation owns them.
    pub fn scan_runs(&self) -> &[StaleLibraryScanRun] {
        &self.scan_runs
    }

    /// Returns durable admission exclusions, when the operation owns them.
    pub fn exclusions(&self) -> &[LibraryScanAdmissionExclusion] {
        &self.exclusions
    }
}

/// Persistence-only query port for startup reconciliation of supported
/// background operations.
pub trait StaleOperationQueries {
    /// Lists active operations that require startup reconciliation without
    /// resolving providers or performing user-visible work.
    fn list_stale_operation_jobs(
        &self,
        context: &OperationContext,
    ) -> Result<Vec<StaleOperationJob>, PersistenceError>;
}

/// Persistence-only startup recovery for every supported active operation.
pub struct StaleOperationRecoveryHandler<Q, U> {
    queries: Q,
    unit_of_work: U,
}

impl<Q, U> StaleOperationRecoveryHandler<Q, U> {
    /// Composes the stale query and Unit of Work capabilities.
    pub const fn new(queries: Q, unit_of_work: U) -> Self {
        Self {
            queries,
            unit_of_work,
        }
    }
}

impl<Q, U> StaleOperationRecoveryHandler<Q, U>
where
    Q: StaleOperationQueries,
    U: crate::UnitOfWorkFactory + Clone,
{
    /// Reconciles every stale supported operation and returns only after all
    /// recovered state is coherent.
    pub fn handle(&self, context: &OperationContext) -> Result<(), ApplicationError> {
        let stale_jobs = self
            .queries
            .list_stale_operation_jobs(context)
            .map_err(|error| map_persistence_error(context.trace_id(), error))?;
        for job in stale_jobs {
            self.reconcile_job(context, job)?;
        }
        Ok(())
    }

    fn reconcile_job(
        &self,
        context: &OperationContext,
        job: StaleOperationJob,
    ) -> Result<(), ApplicationError> {
        let now = now_millis();
        let cancellation_requested = job.cancellation_requested();
        let reconciles_scan_children = matches!(
            job.operation_type(),
            OPERATION_TYPE_LIBRARY_SCAN | OPERATION_TYPE_LIBRARY_REFRESH
        );
        let parent_state = if cancellation_requested {
            JobRunState::Cancelled
        } else {
            JobRunState::Abandoned
        };
        self.unit_of_work
            .clone()
            .execute(context, move |mut scope| {
                if reconciles_scan_children {
                    for child in job.scan_runs() {
                        if child.status() != ScanRunStatus::Running {
                            continue;
                        }
                        let child_status = if cancellation_requested {
                            ScanRunStatus::Cancelled
                        } else {
                            ScanRunStatus::Abandoned
                        };
                        scope.scan_runs().set_status(
                            child.scan_run_id(),
                            child_status,
                            Some(now),
                            None,
                        )?;
                        let last_scan_status = if cancellation_requested {
                            LibraryRootLastScanStatus::Cancelled
                        } else {
                            LibraryRootLastScanStatus::Abandoned
                        };
                        scope.library_roots().set_last_scan(
                            child.library_root_id(),
                            Some(LibraryRootLastScanSummary::new(
                                child.scan_run_id().to_string(),
                                child.job_run_id().to_string(),
                                last_scan_status,
                                child.started_at_ms(),
                                Some(now),
                            )),
                        )?;
                    }
                }
                scope
                    .job_runs()
                    .set_state(job.job_run_id(), parent_state, now)?;
                scope.commit()?;
                Ok::<_, ApplicationPortError>(())
            })
            .map_err(|error| map_port_error(context.trace_id(), error))
    }
}

/// Persistence-only startup recovery for stale active LibraryScan jobs.
///
/// This handler has no provider, enumeration, or scheduling capability. It
/// terminalizes stale running children as `Cancelled` (accepted cancellation
/// intent) or `Abandoned` (no cancellation), preserves already-terminal
/// children, and then derives the parent state from durable child/exclusion
/// facts. Every mutation is a persistence transaction; no user files are
/// touched and no automatic resume is admitted.
pub struct LibraryScanRecoveryHandler<Q, U> {
    queries: Q,
    unit_of_work: U,
}

impl<Q, U> LibraryScanRecoveryHandler<Q, U> {
    /// Composes the stale query and Unit of Work capabilities.
    pub const fn new(queries: Q, unit_of_work: U) -> Self {
        Self {
            queries,
            unit_of_work,
        }
    }
}

impl<Q, U> LibraryScanRecoveryHandler<Q, U>
where
    Q: StaleLibraryScanQueries,
    U: crate::UnitOfWorkFactory + Clone,
{
    /// Reconciles every stale active LibraryScan job and returns only after
    /// all recovered state is coherent.
    pub fn handle(&self, context: &OperationContext) -> Result<(), ApplicationError> {
        let stale_jobs = self
            .queries
            .list_stale_library_scan_jobs(context)
            .map_err(|error| map_persistence_error(context.trace_id(), error))?;
        for job in stale_jobs {
            self.reconcile_job(context, job)?;
        }
        Ok(())
    }

    fn reconcile_job(
        &self,
        context: &OperationContext,
        job: StaleLibraryScanJob,
    ) -> Result<(), ApplicationError> {
        let now = now_millis();
        let cancellation_requested = job.cancellation_requested();
        let exclusions_count = job.exclusions().len();
        self.unit_of_work
            .clone()
            .execute(context, move |mut scope| {
                let mut child_statuses = Vec::with_capacity(job.scan_runs().len());
                for child in job.scan_runs() {
                    let status = if child.status() == ScanRunStatus::Running {
                        let target = if cancellation_requested {
                            ScanRunStatus::Cancelled
                        } else {
                            ScanRunStatus::Abandoned
                        };
                        scope.scan_runs().set_status(
                            child.scan_run_id(),
                            target,
                            Some(now),
                            None,
                        )?;
                        let last_scan_status = if cancellation_requested {
                            LibraryRootLastScanStatus::Cancelled
                        } else {
                            LibraryRootLastScanStatus::Abandoned
                        };
                        scope.library_roots().set_last_scan(
                            child.library_root_id(),
                            Some(LibraryRootLastScanSummary::new(
                                child.scan_run_id().to_string(),
                                child.job_run_id().to_string(),
                                last_scan_status,
                                child.started_at_ms(),
                                Some(now),
                            )),
                        )?;
                        target
                    } else {
                        child.status()
                    };
                    child_statuses.push(status);
                }
                let parent_state = aggregate_library_scan_state(
                    child_statuses.len() + exclusions_count,
                    child_statuses.len(),
                    &child_statuses
                        .iter()
                        .map(|status| match *status {
                            ScanRunStatus::Complete => LibraryScanChildCompletion::Complete,
                            ScanRunStatus::Partial => LibraryScanChildCompletion::Partial,
                            ScanRunStatus::Failed => LibraryScanChildCompletion::Failed,
                            ScanRunStatus::Cancelled => LibraryScanChildCompletion::Cancelled,
                            ScanRunStatus::Abandoned => LibraryScanChildCompletion::Abandoned,
                            ScanRunStatus::Running => LibraryScanChildCompletion::Abandoned,
                        })
                        .collect::<Vec<_>>(),
                );
                scope
                    .job_runs()
                    .set_state(job.job_run_id(), parent_state, now)?;
                scope.commit()?;
                Ok::<_, ApplicationPortError>(())
            })
            .map_err(|error| map_port_error(context.trace_id(), error))
    }
}

impl<Q> JobsQueries for &Q
where
    Q: JobsQueries,
{
    fn get_job(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<JobDetail>, PersistenceError> {
        (*self).get_job(context, job_run_id)
    }

    fn list_active(&self, context: &OperationContext) -> Result<Vec<JobSummary>, PersistenceError> {
        (*self).list_active(context)
    }

    fn list_recent_terminal(
        &self,
        context: &OperationContext,
        offset: u32,
        page_size: u32,
    ) -> Result<JobSummaryPage, PersistenceError> {
        (*self).list_recent_terminal(context, offset, page_size)
    }

    fn find_retry_successor(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<JobRunId>, PersistenceError> {
        (*self).find_retry_successor(context, job_run_id)
    }

    fn list_requested_library_scan_targets(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<Vec<LibraryScanTarget>>, PersistenceError> {
        (*self).list_requested_library_scan_targets(context, job_run_id)
    }

    fn find_library_scan_invocation_kind(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<LibraryScanInvocationKind>, PersistenceError> {
        (*self).find_library_scan_invocation_kind(context, job_run_id)
    }

    fn find_scan_admission_for_root(
        &self,
        context: &OperationContext,
        library_root_id: LibraryRootId,
    ) -> Result<Option<ScanAdmissionReference>, PersistenceError> {
        (*self).find_scan_admission_for_root(context, library_root_id)
    }
}

/// Capability-neutral job observation and control service.
pub struct JobsService<Q, U> {
    queries: Q,
    unit_of_work: U,
}

impl<Q, U> JobsService<Q, U> {
    /// Composes the jobs query and Unit of Work ports.
    pub const fn new(queries: Q, unit_of_work: U) -> Self {
        Self {
            queries,
            unit_of_work,
        }
    }
}

impl<Q, U> JobsService<Q, U>
where
    Q: JobsQueries,
{
    /// Reads one authoritative job detail.
    pub fn get_job(
        &self,
        job_run_id: JobRunId,
        context: OperationContext,
    ) -> Result<JobDetail, ApplicationError> {
        self.queries
            .get_job(&context, job_run_id)
            .map_err(|error| map_persistence_error(context.trace_id(), error))?
            .ok_or_else(|| {
                ApplicationError::from_code(
                    ErrorCode::JobRunNotFound,
                    context.trace_id(),
                    SafeContext::new(),
                )
                .expect("job run not found uses an allowlisted empty context")
            })
    }

    /// Lists one closed authoritative Jobs scope.
    pub fn list_jobs(
        &self,
        query: ListJobsQuery,
        context: OperationContext,
    ) -> Result<JobSummaryPage, ApplicationError> {
        match query.scope() {
            ListJobsScope::Active => {
                let items = self
                    .queries
                    .list_active(&context)
                    .map_err(|error| map_persistence_error(context.trace_id(), error))?;
                let total = items.len() as u32;
                Ok(JobSummaryPage::new(items, total, None))
            }
            ListJobsScope::RecentTerminal { offset, page_size } => self
                .queries
                .list_recent_terminal(&context, offset, page_size)
                .map_err(|error| map_persistence_error(context.trace_id(), error)),
        }
    }

    /// Reads the newest scan-run admission for one root (active or terminal).
    ///
    /// This focused query supplies Jobs-authoritative reconciliation for an
    /// ambiguous Add & Scan transport outcome: Flutter must never infer child
    /// admission from root `lastScan` alone.
    pub fn get_root_scan_admission(
        &self,
        library_root_id: LibraryRootId,
        context: OperationContext,
    ) -> Result<Option<ScanAdmissionReference>, ApplicationError> {
        self.queries
            .find_scan_admission_for_root(&context, library_root_id)
            .map_err(|error| map_persistence_error(context.trace_id(), error))
    }
}

impl<Q, U> JobsService<Q, U>
where
    Q: JobsQueries,
    U: crate::UnitOfWorkFactory + Clone,
{
    /// Persists durable cancellation intent for one active job.
    pub fn cancel_job<R>(
        &self,
        job_run_id: JobRunId,
        context: OperationContext,
        recorder: R,
    ) -> Result<CancelJobResult, ApplicationError>
    where
        R: crate::EventRecorder + Clone + Send + Sync + 'static,
    {
        #[derive(Clone, Copy, Debug, Eq, PartialEq)]
        enum CancelWork {
            Missing,
            NoLongerCancellable,
            Requested,
        }
        let work = self
            .unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                let outcome = scope.job_runs().request_cancellation(job_run_id)?;
                let work = match outcome {
                    None => CancelWork::Missing,
                    Some(false) => CancelWork::NoLongerCancellable,
                    Some(true) => {
                        recorder.record(ApplicationEvent::JobStateChanged(
                            crate::JobStateChanged { job_run_id },
                        ))?;
                        CancelWork::Requested
                    }
                };
                scope.commit()?;
                Ok::<_, ApplicationPortError>(work)
            })
            .map_err(|error| map_port_error(context.trace_id(), error))?;
        match work {
            CancelWork::Missing => Err(ApplicationError::from_code(
                ErrorCode::JobRunNotFound,
                context.trace_id(),
                SafeContext::new(),
            )
            .expect("job run not found uses an allowlisted empty context")),
            CancelWork::NoLongerCancellable => Ok(CancelJobResult::NoLongerCancellable),
            CancelWork::Requested => Ok(CancelJobResult::CancellationRequested),
        }
    }

    /// Retries one eligible historical Library execution into a new durable run.
    pub fn retry_job<R>(
        &self,
        command: RetryJobCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<RetryJobAdmissionResult, ApplicationError>
    where
        R: crate::EventRecorder + Clone + Send + Sync + 'static,
    {
        RetryJobHandler::new(&self.queries, self.unit_of_work.clone())
            .handle(command, context, recorder)
    }
}

/// Handles one durable Library execution retry admission.
pub struct RetryJobHandler<Q, U> {
    queries: Q,
    unit_of_work: U,
}

impl<Q, U> RetryJobHandler<Q, U> {
    /// Composes the jobs query and Unit of Work ports.
    pub const fn new(queries: Q, unit_of_work: U) -> Self {
        Self {
            queries,
            unit_of_work,
        }
    }
}

impl<Q, U> RetryJobHandler<Q, U>
where
    Q: JobsQueries,
    U: crate::UnitOfWorkFactory + Clone,
{
    /// Executes one retry admission.
    ///
    /// Check order: the source job must exist; an existing direct successor
    /// returns `AlreadyRetried` without branching; the operation must be a
    /// LibraryScan or composed Library refresh; the source state must be
    /// terminal and retryable; the
    /// original requested targets are then revalidated through the shared
    /// eligibility seam. Every admitted retry creates a fresh JobRunId and
    /// ScanRunId and records a durable linear source/successor relationship.
    pub fn handle<R>(
        &self,
        command: RetryJobCommand,
        context: OperationContext,
        recorder: R,
    ) -> Result<RetryJobAdmissionResult, ApplicationError>
    where
        R: crate::EventRecorder + Clone + Send + Sync + 'static,
    {
        let source_job_run_id = command.job_run_id();
        let trace_id = context.trace_id();

        let successor = self
            .queries
            .find_retry_successor(&context, source_job_run_id)
            .map_err(|error| map_persistence_error(trace_id, error))?;
        if let Some(successor) = successor {
            return Ok(RetryJobAdmissionResult::not_admitted(
                RetryJobResult::AlreadyRetried(successor),
            ));
        }

        let source = self
            .queries
            .get_job(&context, source_job_run_id)
            .map_err(|error| map_persistence_error(trace_id, error))?
            .ok_or_else(|| {
                ApplicationError::from_code(ErrorCode::JobRunNotFound, trace_id, SafeContext::new())
                    .expect("job run not found uses an allowlisted empty context")
            })?;
        let source_state = source.job().state();
        if source_state.is_active() {
            return Ok(RetryJobAdmissionResult::not_admitted(
                RetryJobResult::NotAdmitted(RetryNotAdmittedReason::SourceRunNotTerminal),
            ));
        }
        if !matches!(
            source_state,
            JobRunState::CompletedWithIssues
                | JobRunState::Failed
                | JobRunState::Cancelled
                | JobRunState::Abandoned
        ) {
            return Ok(RetryJobAdmissionResult::not_admitted(
                RetryJobResult::NotAdmitted(RetryNotAdmittedReason::OperationNotRetryable),
            ));
        }
        let is_library_refresh = source.job().operation_type() == OPERATION_TYPE_LIBRARY_REFRESH;
        let refresh_intent = if is_library_refresh {
            match source.operation_detail() {
                OperationDetail::LibraryRefresh(detail) => Some((detail.trigger(), detail.mode())),
                _ => None,
            }
        } else {
            None
        };
        if is_library_refresh && refresh_intent.is_none() {
            return Ok(RetryJobAdmissionResult::not_admitted(
                RetryJobResult::NotAdmitted(RetryNotAdmittedReason::OperationNotRetryable),
            ));
        }
        let requested_targets = self
            .queries
            .list_requested_library_scan_targets(&context, source_job_run_id)
            .map_err(|error| map_persistence_error(trace_id, error))?
            .ok_or_else(|| {
                ApplicationError::from_code(ErrorCode::JobRunNotFound, trace_id, SafeContext::new())
                    .expect("job run not found uses an allowlisted empty context")
            })?;
        let invocation_kind = self
            .queries
            .find_library_scan_invocation_kind(&context, source_job_run_id)
            .map_err(|error| map_persistence_error(trace_id, error))?
            .ok_or_else(|| {
                ApplicationError::from_code(ErrorCode::JobRunNotFound, trace_id, SafeContext::new())
                    .expect("job run not found uses an allowlisted empty context")
            })?;
        let is_scan_all = matches!(
            invocation_kind,
            LibraryScanInvocationKind::InitialScanAll | LibraryScanInvocationKind::RetryScanAll
        ) || is_library_refresh;

        #[derive(Clone, Debug, Eq, PartialEq)]
        enum RetryWork {
            NoEligibleTargets {
                exclusions: Vec<LibraryScanAdmissionExclusion>,
            },
            AdmittedSingle {
                job_run_id: JobRunId,
                scan_run_id: ScanRunId,
                plan: LibraryScanExecutionPlan,
            },
            AdmittedScanAll {
                job_run_id: JobRunId,
                plans: Vec<LibraryScanExecutionPlan>,
                exclusions_len: usize,
            },
        }

        let created_at_ms = now_millis();
        let work = self
            .unit_of_work
            .clone()
            .execute(&context, move |mut scope| {
                let mut evaluated = Vec::with_capacity(requested_targets.len());
                for target in &requested_targets {
                    let root_id = target.library_root_id();
                    let configured = scope.library_roots().exists(root_id)?;
                    let configuration = if configured {
                        scope.library_roots().get_scan_authority(root_id)?
                    } else {
                        None
                    };
                    let configuration_valid = configuration.is_some();
                    let active_owner = scope.scan_runs().find_active_ownership(root_id)?;
                    evaluated.push((
                        target.clone(),
                        LibraryScanTargetEligibility {
                            configured,
                            configuration_valid,
                            active_owner,
                        },
                        configuration,
                    ));
                }
                let eligibility_input: Vec<(LibraryScanTarget, LibraryScanTargetEligibility)> =
                    evaluated
                        .iter()
                        .map(|(target, eligibility, _)| (target.clone(), eligibility.clone()))
                        .collect();
                let evaluation = evaluate_retry_eligibility_with_trace(
                    Some(trace_id),
                    source_state,
                    false,
                    &eligibility_input,
                );
                if !evaluation.can_retry() {
                    scope.commit()?;
                    return Ok::<_, ApplicationPortError>(RetryWork::NoEligibleTargets {
                        exclusions: evaluation.exclusions().to_vec(),
                    });
                }

                let operation_type = if is_library_refresh {
                    OPERATION_TYPE_LIBRARY_REFRESH
                } else {
                    OPERATION_TYPE_LIBRARY_SCAN
                };
                let job_run_id = scope
                    .job_runs()
                    .insert(NewJobRun::new(operation_type, created_at_ms))?;
                if let Some((trigger, mode)) = refresh_intent {
                    scope
                        .job_runs()
                        .insert_library_refresh_intent(job_run_id, trigger, mode)?;
                }
                let invocation_kind = if is_library_refresh {
                    LibraryScanInvocationKind::RetryLibraryRefresh
                } else if is_scan_all {
                    LibraryScanInvocationKind::RetryScanAll
                } else {
                    LibraryScanInvocationKind::RetrySingleRoot
                };
                scope.library_scan_admission_context().insert(
                    NewLibraryScanAdmissionContext::new(
                        job_run_id,
                        invocation_kind,
                        Some(source_job_run_id),
                    ),
                )?;

                let mut admitted_plans = Vec::new();
                let mut admitted_root_ids = Vec::new();
                for (target, eligibility, configuration) in &evaluated {
                    scope
                        .library_scan_targets()
                        .insert(NewLibraryScanTarget::new(
                            job_run_id,
                            LibraryScanTargetKind::Requested,
                            target.library_root_id(),
                            target.display_name().to_owned(),
                            target.safe_location_display().to_owned(),
                            None,
                            None,
                        ))?;
                    if eligibility.configured
                        && eligibility.configuration_valid
                        && eligibility.active_owner.is_none()
                    {
                        let configuration = configuration
                            .as_ref()
                            .expect("eligible retry target has a valid configuration");
                        let scan_run_id = scope.scan_runs().insert(NewScanRun::new(
                            job_run_id,
                            configuration.root_id(),
                            configuration.locator().clone(),
                            configuration.display_name().to_owned(),
                            configuration.safe_location_presentation().to_owned(),
                            configuration.source_config_revision(),
                            configuration.config_revision(),
                            created_at_ms,
                        ))?;
                        scope
                            .library_scan_targets()
                            .insert(NewLibraryScanTarget::new(
                                job_run_id,
                                LibraryScanTargetKind::Admitted,
                                configuration.root_id(),
                                configuration.display_name().to_owned(),
                                configuration.safe_location_presentation().to_owned(),
                                Some(scan_run_id),
                                None,
                            ))?;
                        admitted_root_ids.push(configuration.root_id());
                        admitted_plans.push(LibraryScanExecutionPlan::new(
                            configuration.root_id(),
                            job_run_id,
                            scan_run_id,
                            configuration.locator().clone(),
                            configuration.display_name().to_owned(),
                            configuration.safe_location_presentation().to_owned(),
                            configuration.source_config_revision(),
                            configuration.config_revision(),
                            configuration.discovery_policy_revision(),
                            created_at_ms,
                        ));
                    } else {
                        let exclusion = evaluation
                            .exclusions()
                            .iter()
                            .find(|exclusion| {
                                exclusion.library_root_id() == target.library_root_id()
                            })
                            .expect("evaluation produced an exclusion for every ineligible target");
                        scope
                            .library_scan_targets()
                            .insert(NewLibraryScanTarget::new(
                                job_run_id,
                                LibraryScanTargetKind::Excluded,
                                target.library_root_id(),
                                target.display_name().to_owned(),
                                target.safe_location_display().to_owned(),
                                None,
                                Some(exclusion.clone()),
                            ))?;
                    }
                }
                if admitted_plans.is_empty() {
                    scope.rollback()?;
                    return Ok(RetryWork::NoEligibleTargets {
                        exclusions: evaluation.exclusions().to_vec(),
                    });
                }
                scope
                    .job_runs()
                    .insert_retry_link(source_job_run_id, job_run_id)?;
                recorder.record(ApplicationEvent::JobStateChanged(crate::JobStateChanged {
                    job_run_id,
                }))?;
                recorder.record(ApplicationEvent::JobStateChanged(crate::JobStateChanged {
                    job_run_id: source_job_run_id,
                }))?;
                for root_id in &admitted_root_ids {
                    recorder.record(ApplicationEvent::LibraryRootChanged(
                        crate::LibraryRootChanged {
                            library_root_id: *root_id,
                        },
                    ))?;
                }
                scope.commit()?;
                if is_scan_all {
                    Ok::<_, ApplicationPortError>(RetryWork::AdmittedScanAll {
                        job_run_id,
                        plans: admitted_plans,
                        exclusions_len: evaluation.exclusions().len(),
                    })
                } else {
                    let plan = admitted_plans
                        .into_iter()
                        .next()
                        .expect("single-root retry always builds one plan");
                    Ok::<_, ApplicationPortError>(RetryWork::AdmittedSingle {
                        job_run_id,
                        scan_run_id: plan.scan_run_id(),
                        plan,
                    })
                }
            })
            .map_err(|error| map_port_error(trace_id, error))?;

        match work {
            RetryWork::NoEligibleTargets { exclusions } => Ok(
                RetryJobAdmissionResult::not_admitted(RetryJobResult::NotAdmitted(
                    RetryNotAdmittedReason::NoEligibleTargets(exclusions),
                )),
            ),
            RetryWork::AdmittedSingle {
                job_run_id,
                scan_run_id,
                plan,
            } => {
                let operation_type = if is_library_refresh {
                    OPERATION_TYPE_LIBRARY_REFRESH
                } else {
                    OPERATION_TYPE_LIBRARY_SCAN
                };
                let handle = OperationHandle::new(job_run_id, operation_type);
                Ok(RetryJobAdmissionResult::admitted(
                    handle,
                    AdmittedScan::new(job_run_id, scan_run_id, plan),
                ))
            }
            RetryWork::AdmittedScanAll {
                job_run_id,
                plans,
                exclusions_len,
            } => {
                let operation_type = if is_library_refresh {
                    OPERATION_TYPE_LIBRARY_REFRESH
                } else {
                    OPERATION_TYPE_LIBRARY_SCAN
                };
                let handle = OperationHandle::new(job_run_id, operation_type);
                Ok(RetryJobAdmissionResult::admitted_scan_all(
                    handle,
                    AdmittedLibraryScanJob::new(job_run_id, plans),
                    exclusions_len,
                ))
            }
        }
    }
}

fn now_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

/// Cooperative progress reporting contract used by operation handlers.
pub trait JobProgressReporter: Send + Sync {
    /// Persists and publishes one structured progress update.
    fn report(&self, progress: JobProgress) -> Result<(), ApplicationError>;
}

/// Best-effort post-commit application notification sink.
pub trait ApplicationEventSink: Send + Sync {
    /// Publishes one committed application event without blocking authority.
    fn publish(&self, event: ApplicationEvent);
}

/// Terminal completion facts reported by an operation handler.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationCompletion {
    state: JobRunState,
    terminal_error_code: Option<String>,
    terminal_safe_context: Option<String>,
}

/// Closed set of cooperative reasons that can stop one live background run.
///
/// The runtime owns the transient stop signal, while operation handlers use
/// this application-level vocabulary to preserve durable business semantics.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BackgroundOperationStopReason {
    /// Durable user cancellation was accepted by the Jobs authority.
    CancellationRequested,
    /// The Android foreground execution host reached its platform time limit.
    ExecutionHostTimeout,
    /// The Android foreground execution host disappeared unexpectedly.
    ExecutionHostLost,
}

impl OperationCompletion {
    /// Creates one operation completion request.
    pub fn new(
        state: JobRunState,
        terminal_error_code: Option<String>,
        terminal_safe_context: Option<String>,
    ) -> Self {
        Self {
            state,
            terminal_error_code,
            terminal_safe_context,
        }
    }

    /// Returns the requested generic terminal state.
    pub fn state(&self) -> JobRunState {
        self.state
    }

    /// Returns the bounded terminal error code.
    pub fn terminal_error_code(&self) -> Option<&str> {
        self.terminal_error_code.as_deref()
    }

    /// Returns the bounded terminal safe context.
    pub fn terminal_safe_context(&self) -> Option<&str> {
        self.terminal_safe_context.as_deref()
    }
}

/// One terminal child outcome used by the shared LibraryScan parent
/// aggregation.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LibraryScanChildCompletion {
    /// The child scan completed with no issues.
    Complete,
    /// The child scan produced meaningful positive work but had issues.
    Partial,
    /// The child scan failed without meaningful indexing success.
    Failed,
    /// The child was terminalized because accepted job cancellation
    /// determined its termination.
    Cancelled,
    /// The child was terminalized by startup recovery without accepted
    /// cancellation intent.
    Abandoned,
}

/// Derives the terminal parent state for a LibraryScan job from its durable
/// requested/admitted scope and terminal child outcomes.
///
/// This is the single shared aggregation used by normal multi-root
/// completion and startup recovery so the two paths cannot drift:
/// - any `Cancelled` child (accepted cancellation determines termination)
///   yields `Cancelled`;
/// - any `Abandoned` child (recovery without accepted cancellation intent)
///   yields `Abandoned`;
/// - every requested root admitted and every child `Complete` yields
///   `Completed`;
/// - meaningful indexing success exists (`Complete` or `Partial` child) but
///   the requested scope was not fully satisfied yields `CompletedWithIssues`;
/// - otherwise the parent is `Failed`.
pub fn aggregate_library_scan_state(
    requested_count: usize,
    admitted_count: usize,
    children: &[LibraryScanChildCompletion],
) -> JobRunState {
    if children.contains(&LibraryScanChildCompletion::Cancelled) {
        return JobRunState::Cancelled;
    }
    if children.contains(&LibraryScanChildCompletion::Abandoned) {
        return JobRunState::Abandoned;
    }
    let fully_admitted = admitted_count == requested_count && children.len() == admitted_count;
    if fully_admitted
        && children
            .iter()
            .all(|child| *child == LibraryScanChildCompletion::Complete)
    {
        return JobRunState::Completed;
    }
    if children.iter().any(|child| {
        matches!(
            child,
            LibraryScanChildCompletion::Complete | LibraryScanChildCompletion::Partial
        )
    }) {
        return JobRunState::CompletedWithIssues;
    }
    JobRunState::Failed
}

/// One registered background operation handler.
pub trait BackgroundOperationHandler: Send + Sync {
    /// Executes the operation under the manager's typed stop and progress
    /// contracts and returns the generic terminal completion request.
    fn execute(
        &self,
        context: &OperationContext,
        stop_reason: &dyn Fn() -> Option<BackgroundOperationStopReason>,
        progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError>;

    /// Reconciles operation-owned durable state when the run is terminalized
    /// before its handler ever executes.
    /// The generic manager owns JobRun terminalization; this seam lets the
    /// operation bring its own child records to the governed terminal state.
    fn stopped_before_execution(
        &self,
        _context: &OperationContext,
        _reason: BackgroundOperationStopReason,
    ) -> Result<(), ApplicationError> {
        Ok(())
    }
}

fn map_port_error(trace_id: TraceId, error: ApplicationPortError) -> ApplicationError {
    match error {
        ApplicationPortError::Persistence(error) => map_persistence_error(trace_id, error),
        ApplicationPortError::EventRecording => {
            ApplicationError::from_code(ErrorCode::InternalUnexpected, trace_id, SafeContext::new())
                .expect("internal unexpected uses an allowlisted empty context")
        }
    }
}

fn map_persistence_error(trace_id: TraceId, error: PersistenceError) -> ApplicationError {
    let code = match error {
        PersistenceError::PersistedSettingsInvalid(_) => {
            ErrorCode::ConfigurationPersistedSettingsInvalid
        }
        PersistenceError::DatabaseLocked => ErrorCode::PersistenceDatabaseLocked,
        PersistenceError::Cancelled => ErrorCode::OperationCancelled,
        PersistenceError::MigrationFailed => ErrorCode::PersistenceMigrationFailed,
        PersistenceError::CorruptOrIncompatible => ErrorCode::PersistenceIncompatibleSchema,
        PersistenceError::Unavailable
        | PersistenceError::ConstraintViolation
        | PersistenceError::Conflict
        | PersistenceError::Internal => ErrorCode::InternalUnexpected,
    };
    ApplicationError::from_code(code, trace_id, SafeContext::new())
        .expect("jobs error context follows the published catalog")
}
