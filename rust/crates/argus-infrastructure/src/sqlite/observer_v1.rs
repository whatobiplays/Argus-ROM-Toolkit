//! Host-only ObserverV1 JSON serialization for retained refresh measurements.
//!
//! This module is enabled by `test-support`. It measures the closed JSON
//! result shape without adding a listener or another runtime transport.

use std::collections::BTreeSet;

use argus_application::{
    ApplicationError, ApplicationSeverity, ArchitectureClass, DiagnosticStage, ErrorCategory,
    FailureRole, JobDetail, JobRunProjection, JobRunState, LibraryRefreshJobDetail,
    LibraryRefreshRootOutcomeCoverage, MigrationOutcome, OperationDetail, PathClass,
    PersistedSettingsReason, PlatformClass, Recoverability, RefreshIssueFact, RetryPolicy,
    SafeContextField, SafeContextValue, ScanRunProjection, ScanRunStatus, SettingsDomain,
    TechnicalClass,
};
use serde::Serialize;

/// Encoding failures for one retained-history result.
#[derive(Debug)]
pub enum ObserverV1SerializationError {
    /// The observer interval ended before it started.
    InvalidSnapshotInterval,
    /// A job or scope does not prove complete retained history.
    IncompleteHistory,
    /// A retained job identity appears more than once.
    DuplicateJobRunId,
    /// A detail is outside the LibraryRefresh result contract.
    InvalidJobDetail,
    /// JSON encoding failed.
    Json(serde_json::Error),
}

/// Encodes one complete retained-history result using the ObserverV1 field order.
///
/// The caller supplies elapsed-realtime timestamps from one monotonic clock.
/// Details with incomplete root coverage are rejected before any JSON is returned.
pub fn serialize_retained_library_refresh_history_v1(
    details: &[JobDetail],
    snapshot_started_elapsed_realtime_ms: u64,
    snapshot_finished_elapsed_realtime_ms: u64,
) -> Result<Vec<u8>, ObserverV1SerializationError> {
    if snapshot_finished_elapsed_realtime_ms < snapshot_started_elapsed_realtime_ms {
        return Err(ObserverV1SerializationError::InvalidSnapshotInterval);
    }

    let mut seen_job_run_ids = BTreeSet::new();
    let mut jobs = Vec::with_capacity(details.len());
    for detail in details {
        if !seen_job_run_ids.insert(detail.job().job_run_id().to_string()) {
            return Err(ObserverV1SerializationError::DuplicateJobRunId);
        }
        jobs.push(job_detail_dto(detail)?);
    }
    let retained_job_count =
        u64::try_from(jobs.len()).map_err(|_| ObserverV1SerializationError::InvalidJobDetail)?;
    let result = RetainedLibraryRefreshHistoryDto {
        retention_scope: "AllRetainedLibraryRefreshRunsAtSnapshot",
        snapshot_started_elapsed_realtime_ms,
        snapshot_finished_elapsed_realtime_ms,
        retained_job_count,
        jobs,
    };
    serde_json::to_vec(&result).map_err(ObserverV1SerializationError::Json)
}

fn job_detail_dto(detail: &JobDetail) -> Result<JobDetailDto<'_>, ObserverV1SerializationError> {
    if detail.job().operation_type() != "library_refresh" {
        return Err(ObserverV1SerializationError::InvalidJobDetail);
    }
    let OperationDetail::LibraryRefresh(refresh) = detail.operation_detail() else {
        return Err(ObserverV1SerializationError::InvalidJobDetail);
    };
    if refresh.root_outcome_coverage() != LibraryRefreshRootOutcomeCoverage::Complete {
        return Err(ObserverV1SerializationError::IncompleteHistory);
    }

    Ok(JobDetailDto {
        job: job_run_dto(detail.job()),
        operation_detail: OperationDetailDto {
            kind: "LibraryRefresh",
            detail: library_refresh_detail_dto(refresh),
        },
    })
}

fn job_run_dto(job: &JobRunProjection) -> JobRunDto<'_> {
    let terminal_error_code = job.terminal_error_code();
    let terminal_safe_context = job.terminal_safe_context();
    let bounded_terminal_failure = (terminal_error_code.is_some()
        || terminal_safe_context.is_some())
    .then_some(BoundedTerminalFailureDto {
        error_code: terminal_error_code,
        safe_context: terminal_safe_context,
    });

    JobRunDto {
        job_run_id: job.job_run_id().to_string(),
        operation_type: job.operation_type(),
        state: job_state_name(job.state()),
        phase: job.phase(),
        completed_units: job.completed_units(),
        total_units: job.total_units(),
        status_key: job.status_key(),
        created_at_ms: job.created_at_ms(),
        queued_at_ms: job.queued_at_ms(),
        started_at_ms: job.started_at_ms(),
        terminal_at_ms: job.terminal_at_ms(),
        cancellation_requested: job.cancellation_requested(),
        controls: JobControlAvailabilityDto {
            can_cancel: job.controls().can_cancel(),
            can_retry: job.controls().can_retry(),
        },
        bounded_terminal_failure,
    }
}

fn library_refresh_detail_dto<'a>(
    refresh: &'a LibraryRefreshJobDetail,
) -> LibraryRefreshDetailDto<'a> {
    let trigger = refresh.trigger();
    let trigger_root_id = trigger.root_id().map(|root_id| root_id.to_string());
    LibraryRefreshDetailDto {
        trigger: trigger.kind(),
        trigger_root_id,
        mode: refresh.mode().as_str(),
        requested_root_ids: refresh
            .requested_root_ids()
            .iter()
            .map(ToString::to_string)
            .collect(),
        scan_runs: refresh.scan_runs().iter().map(scan_run_dto).collect(),
        progress: refresh_progress_dto(refresh),
        retry_source_job_run_id: refresh
            .retry_source_job_run_id()
            .map(|job_run_id| job_run_id.to_string()),
        retry_successor_job_run_id: refresh
            .retry_successor_job_run_id()
            .map(|job_run_id| job_run_id.to_string()),
        exclusions: refresh.exclusions().iter().map(exclusion_dto).collect(),
        root_outcome_coverage: "Complete",
    }
}

fn scan_run_dto(scan_run: &ScanRunProjection) -> ScanRunDto<'_> {
    ScanRunDto {
        scan_run_id: scan_run.scan_run_id().to_string(),
        job_run_id: scan_run.job_run_id().to_string(),
        library_root_id: scan_run.library_root_id().to_string(),
        display_name: scan_run.display_name(),
        safe_location_display: scan_run.safe_location_display(),
        status: scan_status_name(scan_run.status()),
        started_at_ms: scan_run.started_at_ms(),
        completed_at_ms: scan_run.completed_at_ms(),
        failure_reason: scan_run.failure_reason(),
    }
}

fn refresh_progress_dto<'a>(refresh: &'a LibraryRefreshJobDetail) -> RefreshProgressDto<'a> {
    let progress = refresh.progress();
    RefreshProgressDto {
        phase: progress.phase(),
        completed_units: progress.completed_units(),
        total_units: progress.total_units(),
        status_key: progress.status_key(),
        issue_count: progress.issue_count(),
        issues: progress.issues().iter().map(refresh_issue_dto).collect(),
    }
}

fn refresh_issue_dto(issue: &RefreshIssueFact) -> RefreshIssueDto {
    RefreshIssueDto {
        kind: issue.kind().as_str(),
        reason: issue.reason().as_str(),
        provider_id: issue
            .provider_id()
            .map(|provider_id| provider_id.as_str().to_owned()),
        occurrences: issue.occurrences(),
    }
}

fn exclusion_dto(exclusion: &argus_application::LibraryScanAdmissionExclusion) -> ExclusionDto<'_> {
    ExclusionDto {
        library_root_id: exclusion.library_root_id().to_string(),
        reason: exclusion.reason().as_str(),
        active_job_run_id: exclusion
            .active_job_run_id()
            .map(|job_run_id| job_run_id.to_string()),
        active_scan_run_id: exclusion
            .active_scan_run_id()
            .map(|scan_run_id| scan_run_id.to_string()),
        application_error: exclusion.application_error().map(application_error_dto),
    }
}

fn application_error_dto(error: &ApplicationError) -> ApplicationErrorDto {
    ApplicationErrorDto {
        code: error.code.as_str().to_owned(),
        category: category_name(error.category),
        severity: severity_name(error.severity),
        recoverability: recoverability_name(error.recoverability),
        retry_policy: retry_policy_name(error.retry_policy),
        message_key: error.message_key.as_str().to_owned(),
        trace_id: error.trace_id.to_string(),
        safe_context: error
            .safe_context
            .iter()
            .map(|(field, value)| SafeContextEntryDto {
                field: safe_context_field_name(*field),
                value: safe_context_value_name(value),
            })
            .collect(),
    }
}

fn category_name(value: ErrorCategory) -> &'static str {
    match value {
        ErrorCategory::Validation => "validation",
        ErrorCategory::Configuration => "configuration",
        ErrorCategory::Filesystem => "filesystem",
        ErrorCategory::Persistence => "persistence",
        ErrorCategory::Provider => "provider",
        ErrorCategory::Runtime => "runtime",
        ErrorCategory::Operation => "operation",
        ErrorCategory::Internal => "internal",
    }
}

fn severity_name(value: ApplicationSeverity) -> &'static str {
    match value {
        ApplicationSeverity::Info => "Info",
        ApplicationSeverity::Warning => "Warning",
        ApplicationSeverity::Error => "Error",
        ApplicationSeverity::Fatal => "Fatal",
    }
}

fn recoverability_name(value: Recoverability) -> &'static str {
    match value {
        Recoverability::None => "None",
        Recoverability::Retry => "Retry",
        Recoverability::UserAction => "UserAction",
        Recoverability::RestartRequired => "RestartRequired",
        Recoverability::ManualIntervention => "ManualIntervention",
    }
}

fn retry_policy_name(value: RetryPolicy) -> &'static str {
    match value {
        RetryPolicy::Never => "Never",
        RetryPolicy::Immediate => "Immediate",
        RetryPolicy::Backoff => "Backoff",
        RetryPolicy::UserInitiated => "UserInitiated",
    }
}

fn safe_context_field_name(field: SafeContextField) -> &'static str {
    match field {
        SafeContextField::Stage => "stage",
        SafeContextField::PathClass => "path_class",
        SafeContextField::MigrationCount => "migration_count",
        SafeContextField::SchemaVersion => "schema_version",
        SafeContextField::MigrationOutcome => "migration_outcome",
        SafeContextField::ApplicationVersion => "application_version",
        SafeContextField::BackendVersion => "backend_version",
        SafeContextField::Platform => "platform",
        SafeContextField::Architecture => "architecture",
        SafeContextField::TechnicalClass => "technical_class",
        SafeContextField::FailureRole => "failure_role",
        SafeContextField::SettingsDomain => "settings_domain",
        SafeContextField::PersistedSettingsReason => "persisted_settings_reason",
    }
}

fn safe_context_value_name(value: &SafeContextValue) -> String {
    match value {
        SafeContextValue::Stage(stage) => match stage {
            DiagnosticStage::Environment => "environment".to_owned(),
            DiagnosticStage::Observability => "observability".to_owned(),
            DiagnosticStage::Persistence => "persistence".to_owned(),
        },
        SafeContextValue::PathClass(path_class) => match path_class {
            PathClass::StandardApplicationData => "standard_application_data".to_owned(),
            PathClass::ExplicitOverride => "explicit_override".to_owned(),
        },
        SafeContextValue::MigrationCount(count) => count.to_string(),
        SafeContextValue::SchemaVersion(version) => version.to_string(),
        SafeContextValue::MigrationOutcome(outcome) => match outcome {
            MigrationOutcome::Applied => "applied".to_owned(),
            MigrationOutcome::AlreadyCurrent => "already_current".to_owned(),
        },
        SafeContextValue::ApplicationVersion(version) => version.as_str().to_owned(),
        SafeContextValue::BackendVersion(version) => version.as_str().to_owned(),
        SafeContextValue::Platform(platform) => match platform {
            PlatformClass::Windows => "windows".to_owned(),
            PlatformClass::MacOs => "macos".to_owned(),
            PlatformClass::Unix => "unix".to_owned(),
            PlatformClass::Android => "android".to_owned(),
        },
        SafeContextValue::Architecture(architecture) => match architecture {
            ArchitectureClass::X8664 => "x86_64".to_owned(),
            ArchitectureClass::Aarch64 => "aarch64".to_owned(),
            ArchitectureClass::X86 => "x86".to_owned(),
            ArchitectureClass::Arm => "arm".to_owned(),
            ArchitectureClass::Unknown => "unknown".to_owned(),
        },
        SafeContextValue::TechnicalClass(technical) => match technical {
            TechnicalClass::ConfigurationInvalid => "configuration_invalid".to_owned(),
            TechnicalClass::FilesystemPermissionDenied => "filesystem_permission_denied".to_owned(),
            TechnicalClass::DatabaseOpenFailed => "database_open_failed".to_owned(),
            TechnicalClass::DatabaseLocked => "database_locked".to_owned(),
            TechnicalClass::MigrationFailed => "migration_failed".to_owned(),
            TechnicalClass::IncompatibleSchema => "incompatible_schema".to_owned(),
            TechnicalClass::Internal => "internal".to_owned(),
        },
        SafeContextValue::FailureRole(role) => match role {
            FailureRole::Primary => "primary".to_owned(),
            FailureRole::Secondary => "secondary".to_owned(),
        },
        SafeContextValue::SettingsDomain(domain) => match domain {
            SettingsDomain::Appearance => "appearance".to_owned(),
        },
        SafeContextValue::PersistedSettingsReason(reason) => match reason {
            PersistedSettingsReason::Missing => "missing".to_owned(),
            PersistedSettingsReason::InvalidValue => "invalid_value".to_owned(),
            PersistedSettingsReason::MappingFailed => "mapping_failed".to_owned(),
        },
    }
}

fn job_state_name(state: JobRunState) -> &'static str {
    match state {
        JobRunState::Queued => "Queued",
        JobRunState::Preparing => "Preparing",
        JobRunState::Running => "Running",
        JobRunState::Completed => "Completed",
        JobRunState::CompletedWithIssues => "CompletedWithIssues",
        JobRunState::Failed => "Failed",
        JobRunState::Cancelled => "Cancelled",
        JobRunState::Interrupted => "Interrupted",
        JobRunState::Abandoned => "Abandoned",
    }
}

fn scan_status_name(status: ScanRunStatus) -> &'static str {
    match status {
        ScanRunStatus::Running => "Running",
        ScanRunStatus::Complete => "Complete",
        ScanRunStatus::Partial => "Partial",
        ScanRunStatus::Failed => "Failed",
        ScanRunStatus::Cancelled => "Cancelled",
        ScanRunStatus::Abandoned => "Abandoned",
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RetainedLibraryRefreshHistoryDto<'a> {
    retention_scope: &'static str,
    snapshot_started_elapsed_realtime_ms: u64,
    snapshot_finished_elapsed_realtime_ms: u64,
    retained_job_count: u64,
    jobs: Vec<JobDetailDto<'a>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct JobDetailDto<'a> {
    job: JobRunDto<'a>,
    operation_detail: OperationDetailDto<'a>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct JobRunDto<'a> {
    job_run_id: String,
    operation_type: &'a str,
    state: &'static str,
    phase: Option<&'a str>,
    completed_units: Option<u64>,
    total_units: Option<u64>,
    status_key: Option<&'a str>,
    created_at_ms: i64,
    queued_at_ms: Option<i64>,
    started_at_ms: Option<i64>,
    terminal_at_ms: Option<i64>,
    cancellation_requested: bool,
    controls: JobControlAvailabilityDto,
    bounded_terminal_failure: Option<BoundedTerminalFailureDto<'a>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct JobControlAvailabilityDto {
    can_cancel: bool,
    can_retry: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BoundedTerminalFailureDto<'a> {
    error_code: Option<&'a str>,
    safe_context: Option<&'a str>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct OperationDetailDto<'a> {
    kind: &'static str,
    detail: LibraryRefreshDetailDto<'a>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LibraryRefreshDetailDto<'a> {
    trigger: &'a str,
    trigger_root_id: Option<String>,
    mode: &'a str,
    requested_root_ids: Vec<String>,
    scan_runs: Vec<ScanRunDto<'a>>,
    progress: RefreshProgressDto<'a>,
    retry_source_job_run_id: Option<String>,
    retry_successor_job_run_id: Option<String>,
    exclusions: Vec<ExclusionDto<'a>>,
    root_outcome_coverage: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ScanRunDto<'a> {
    scan_run_id: String,
    job_run_id: String,
    library_root_id: String,
    display_name: &'a str,
    safe_location_display: &'a str,
    status: &'static str,
    started_at_ms: i64,
    completed_at_ms: Option<i64>,
    failure_reason: Option<&'a str>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RefreshProgressDto<'a> {
    phase: Option<&'a str>,
    completed_units: Option<u64>,
    total_units: Option<u64>,
    status_key: Option<&'a str>,
    issue_count: Option<u64>,
    issues: Vec<RefreshIssueDto>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RefreshIssueDto {
    kind: &'static str,
    reason: &'static str,
    provider_id: Option<String>,
    occurrences: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ExclusionDto<'a> {
    library_root_id: String,
    reason: &'a str,
    active_job_run_id: Option<String>,
    active_scan_run_id: Option<String>,
    application_error: Option<ApplicationErrorDto>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ApplicationErrorDto {
    code: String,
    category: &'static str,
    severity: &'static str,
    recoverability: &'static str,
    retry_policy: &'static str,
    message_key: String,
    trace_id: String,
    safe_context: Vec<SafeContextEntryDto>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SafeContextEntryDto {
    field: &'static str,
    value: String,
}
