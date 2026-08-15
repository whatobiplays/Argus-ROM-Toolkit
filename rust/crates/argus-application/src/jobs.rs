//! Generic durable background-job contracts for Phase 001 Slice 002.
//!
//! These types are application-owned and technology-neutral. `JobRunId`
//! identifies exactly one background execution attempt and `ScanRunId`
//! identifies one root-specific scan inside a job. Persistence ports remain
//! application contracts; the runtime owns generic lifecycle transitions.

use crate::unit_of_work::UnitOfWork;
use crate::{
    ApplicationError, ApplicationEvent, ApplicationPortError, ErrorCode, JobRunId, LibraryRootId,
    LibraryRootLastScanSummary, OperationContext, PersistenceError, SafeContext, ScanRunId,
    SourceEntryId, TraceId,
};

use crate::sources::{RelativeSourceLocator, RootLocator, SourceLocatorKey};

/// Stable logical operation type for the built-in library scan.
pub const OPERATION_TYPE_LIBRARY_SCAN: &str = "library_scan";

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
    /// Creates control availability. Slice 002 never enables retry.
    pub fn new(can_cancel: bool) -> Self {
        Self {
            can_cancel,
            can_retry: false,
        }
    }

    /// Returns whether cancellation may currently be requested.
    pub fn can_cancel(&self) -> bool {
        self.can_cancel
    }

    /// Returns whether retry is available. Always false in Slice 002.
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
    entries_committed: u64,
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
        entries_committed: u64,
    ) -> Self {
        Self {
            phase,
            completed_units,
            total_units,
            status_key,
            roots_requested,
            roots_admitted,
            roots_terminal,
            entries_committed,
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

    /// Returns the committed source-entry count.
    pub fn entries_committed(&self) -> u64 {
        self.entries_committed
    }
}

/// Typed operation-specific detail for one job.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum OperationDetail {
    LibraryScan(LibraryScanJobDetail),
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

/// Transaction-scoped generic job-run repository port.
pub trait JobRunRepository {
    /// Inserts one queued job execution and returns its stable identity.
    fn insert(&mut self, new: NewJobRun) -> Result<JobRunId, PersistenceError>;

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

/// One new persisted positive source observation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NewSourceEntry {
    library_root_id: LibraryRootId,
    parent_source_entry_id: Option<SourceEntryId>,
    relative_locator: RelativeSourceLocator,
    locator_key: SourceLocatorKey,
    display_name: String,
    display_location: String,
    kind: crate::sources::SourceEntryKind,
    classification: crate::sources::SourceEntryClassification,
    provider_native_identity: Option<String>,
    source_fingerprint: Option<String>,
    last_observed_scan_id: ScanRunId,
}

impl NewSourceEntry {
    /// Creates one positive observation insert.
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
            library_root_id,
            parent_source_entry_id,
            relative_locator,
            locator_key,
            display_name: display_name.into(),
            display_location: display_location.into(),
            kind,
            classification,
            provider_native_identity,
            source_fingerprint,
            last_observed_scan_id,
        }
    }

    /// Returns the owning root identity.
    pub fn library_root_id(&self) -> LibraryRootId {
        self.library_root_id
    }

    /// Returns the parent source identity, if any.
    pub fn parent_source_entry_id(&self) -> Option<SourceEntryId> {
        self.parent_source_entry_id
    }

    /// Returns the opaque relative locator.
    pub fn relative_locator(&self) -> &RelativeSourceLocator {
        &self.relative_locator
    }

    /// Returns the provider-defined location equality key.
    pub fn locator_key(&self) -> &SourceLocatorKey {
        &self.locator_key
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

    /// Returns the optional opaque native identity.
    pub fn provider_native_identity(&self) -> Option<&str> {
        self.provider_native_identity.as_deref()
    }

    /// Returns the optional cheap source fingerprint.
    pub fn source_fingerprint(&self) -> Option<&str> {
        self.source_fingerprint.as_deref()
    }

    /// Returns the scan that positively observed this entry.
    pub fn last_observed_scan_id(&self) -> ScanRunId {
        self.last_observed_scan_id
    }
}

/// Transaction-scoped source-entry repository port.
pub trait SourceEntryRepository {
    /// Upserts one positive observation by root + locator key and returns the
    /// stable source identity.
    fn upsert(&mut self, entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError>;

    /// Removes all current Argus-owned entries for one root. Never touches
    /// user filesystem content.
    fn delete_for_root(&mut self, library_root_id: LibraryRootId) -> Result<(), PersistenceError>;
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
}

impl<Q, U> JobsService<Q, U>
where
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

/// One registered background operation handler.
pub trait BackgroundOperationHandler: Send + Sync {
    /// Executes the operation under the manager's cancellation and progress
    /// contracts and returns the generic terminal completion request.
    fn execute(
        &self,
        context: &OperationContext,
        is_cancelled: &dyn Fn() -> bool,
        progress: &dyn JobProgressReporter,
    ) -> Result<OperationCompletion, ApplicationError>;

    /// Reconciles operation-owned durable state when the run is terminalized
    /// before its handler ever executes (queued cancellation or shutdown).
    /// The generic manager owns JobRun terminalization; this seam lets the
    /// operation bring its own child records to the governed terminal state.
    fn cancelled_before_execution(
        &self,
        _context: &OperationContext,
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
