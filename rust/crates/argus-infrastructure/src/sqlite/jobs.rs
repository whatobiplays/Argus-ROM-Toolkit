//! Typed SQLite adapters for Slice 002 job, scan, admission-target, and
//! source-entry state.

use argus_application::{
    ActiveScanOwnership, ApplicationPortError, JobControlAvailability, JobDetail, JobProgress,
    JobRunId, JobRunProjection, JobRunRepository, JobRunState, JobSummary, JobSummaryPage,
    JobsQueries, LibraryRootId, LibraryRootLastScanStatus, LibraryRootLastScanSummary,
    LibraryScanAdmissionContext, LibraryScanAdmissionContextRepository,
    LibraryScanAdmissionExclusion, LibraryScanInvocationKind, LibraryScanJobDetail,
    LibraryScanRootSummary, LibraryScanTarget, LibraryScanTargetEligibility,
    LibraryScanTargetExclusionReason, LibraryScanTargetKind, LibraryScanTargetRepository,
    NativeIdentityMatch, NewJobRun, NewLibraryScanAdmissionContext, NewLibraryScanTarget,
    NewScanRun, NewSourceEntry, OperationContext, PersistenceError, RelativeSourceLocator,
    ScanAdmissionReference, ScanProgressFacts, ScanRunId, ScanRunProjection, ScanRunRepository,
    ScanRunStatus, SourceEntryClassification, SourceEntryId, SourceEntryKind, SourceEntryRecord,
    SourceEntryRepository, SourceLocatorKey, evaluate_retry_eligibility,
};
use rusqlite::OptionalExtension;

use super::appearance::map_executor_error;
use super::connection::SqliteConnection;
use super::errors::SqliteOperationError;
use super::executor::SqliteDatabaseExecutor;
use super::unit_of_work::SqliteUnitOfWork;

type RootLastScanRaw = (
    Option<String>,
    Option<String>,
    Option<String>,
    Option<i64>,
    Option<i64>,
);

/// Transaction-scoped generic job-run repository.
pub struct SqliteJobRunRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteJobRunRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl JobRunRepository for SqliteJobRunRepository<'_, '_> {
    fn insert(&mut self, new: NewJobRun) -> Result<JobRunId, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let created: String = transaction
            .query_row(
                "INSERT INTO job_run
                    (job_run_id, operation_type, state, created_at, queued_at)
                 VALUES (lower(hex(randomblob(16))), ?1, 'queued', ?2, ?2)
                 RETURNING job_run_id",
                rusqlite::params![new.operation_type(), new.created_at_ms()],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;
        parse_job_run_id(created)
    }

    fn insert_retry_link(
        &mut self,
        source_job_run_id: JobRunId,
        successor_job_run_id: JobRunId,
    ) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO job_retry_link (source_job_run_id, successor_job_run_id)
                 VALUES (?1, ?2)",
                rusqlite::params![
                    source_job_run_id.to_string(),
                    successor_job_run_id.to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(())
    }

    fn request_cancellation(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Option<bool>, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let current: Option<(String, i64)> = transaction
            .query_row(
                "SELECT state, cancellation_requested
                 FROM job_run WHERE job_run_id = ?1",
                [job_run_id.to_string()],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        let Some((state, cancellation_requested)) = current else {
            return Ok(None);
        };
        let state = JobRunState::try_from(state.as_str())
            .map_err(|_| PersistenceError::CorruptOrIncompatible)?;
        if state.is_terminal() || cancellation_requested != 0 {
            return Ok(Some(false));
        }
        let changed = transaction
            .execute(
                "UPDATE job_run SET cancellation_requested = 1 WHERE job_run_id = ?1",
                [job_run_id.to_string()],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(Some(changed == 1))
    }

    fn set_state(
        &mut self,
        job_run_id: JobRunId,
        state: JobRunState,
        timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let changed = transaction
            .execute(
                "UPDATE job_run
                 SET state = ?1,
                     queued_at = COALESCE(queued_at, ?2),
                     started_at = COALESCE(started_at, CASE WHEN ?3 = 1 THEN ?2 END),
                     completed_at = CASE WHEN ?4 = 1 THEN ?2 ELSE completed_at END
                 WHERE job_run_id = ?5",
                rusqlite::params![
                    state.as_str(),
                    timestamp_ms,
                    i64::from(state == JobRunState::Running || state == JobRunState::Preparing),
                    i64::from(state.is_terminal()),
                    job_run_id.to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(changed == 1)
    }

    fn set_progress(
        &mut self,
        _job_run_id: JobRunId,
        progress: &JobProgress,
    ) -> Result<bool, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let changed = transaction
            .execute(
                "UPDATE job_run
                 SET current_phase = ?1,
                     completed_units = ?2,
                     total_units = ?3,
                     status_key = ?4
                 WHERE job_run_id = ?5",
                rusqlite::params![
                    progress.phase(),
                    progress.completed_units().map(|value| value as i64),
                    progress.total_units().map(|value| value as i64),
                    progress.status_key(),
                    progress.job_run_id().to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(changed == 1)
    }

    fn set_terminal_failure(
        &mut self,
        job_run_id: JobRunId,
        state: JobRunState,
        terminal_error_code: Option<String>,
        terminal_safe_context: Option<String>,
        timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let changed = transaction
            .execute(
                "UPDATE job_run
                 SET state = ?1,
                     completed_at = ?2,
                     terminal_error_code = ?3,
                     terminal_safe_context = ?4
                 WHERE job_run_id = ?5",
                rusqlite::params![
                    state.as_str(),
                    timestamp_ms,
                    terminal_error_code,
                    terminal_safe_context,
                    job_run_id.to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(changed == 1)
    }
}

/// Transaction-scoped per-root scan-run repository.
pub struct SqliteScanRunRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteScanRunRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl ScanRunRepository for SqliteScanRunRepository<'_, '_> {
    fn insert(&mut self, new: NewScanRun) -> Result<ScanRunId, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let created: String = transaction
            .query_row(
                "INSERT INTO scan_run
                    (scan_run_id, job_run_id, historical_library_root_id, root_locator,
                     root_display_name, safe_location_display, source_config_revision,
                     root_config_revision, status, started_at)
                 VALUES (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, ?6, ?7, 'running', ?8)
                 RETURNING scan_run_id",
                rusqlite::params![
                    new.job_run_id().to_string(),
                    new.library_root_id().to_string(),
                    new.root_locator().as_provider_value(),
                    new.display_name(),
                    new.safe_location_display(),
                    i64::from(new.source_config_revision()),
                    i64::from(new.root_config_revision()),
                    new.started_at_ms(),
                ],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;
        parse_scan_run_id(created)
    }

    fn set_status(
        &mut self,
        scan_run_id: ScanRunId,
        status: ScanRunStatus,
        completed_at_ms: Option<i64>,
        failure_reason: Option<String>,
    ) -> Result<bool, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let changed = transaction
            .execute(
                "UPDATE scan_run
                 SET status = ?1, completed_at = ?2, failure_reason = ?3
                 WHERE scan_run_id = ?4",
                rusqlite::params![
                    status.as_str(),
                    completed_at_ms,
                    failure_reason,
                    scan_run_id.to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(changed == 1)
    }

    fn set_progress_facts(
        &mut self,
        scan_run_id: ScanRunId,
        entries_observed: u64,
        entries_committed: u64,
        issue_count: u64,
    ) -> Result<bool, PersistenceError> {
        let changed = self
            .work
            .transaction_mut()?
            .execute(
                "UPDATE scan_run
                 SET entries_observed = ?1, entries_committed = ?2, issue_count = ?3
                 WHERE scan_run_id = ?4",
                rusqlite::params![
                    entries_observed as i64,
                    entries_committed as i64,
                    issue_count as i64,
                    scan_run_id.to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(changed == 1)
    }

    fn find_active_ownership(
        &mut self,
        library_root_id: LibraryRootId,
    ) -> Result<Option<ActiveScanOwnership>, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let row: Option<(String, String, i64)> = transaction
            .query_row(
                "SELECT s.job_run_id, s.scan_run_id,
                        (SELECT COUNT(*) FROM scan_run s2
                          WHERE s2.job_run_id = s.job_run_id AND s2.status = 'running')
                 FROM scan_run s
                 WHERE s.historical_library_root_id = ?1 AND s.status = 'running'
                 ORDER BY s.started_at ASC, s.scan_run_id ASC
                 LIMIT 1",
                [library_root_id.to_string()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        row.map(|(job_run_id, scan_run_id, count)| {
            Ok(ActiveScanOwnership::new(
                parse_job_run_id(job_run_id)?,
                parse_scan_run_id(scan_run_id)?,
                count as u32,
            ))
        })
        .transpose()
    }

    fn find_last_scan(
        &mut self,
        library_root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootLastScanSummary>, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let raw: Option<RootLastScanRaw> = transaction
            .query_row(
                "SELECT last_scan_scan_run_id, last_scan_job_run_id, last_scan_status,
                        last_scan_started_at, last_scan_completed_at
                 FROM library_root WHERE library_root_id = ?1",
                [library_root_id.to_string()],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    ))
                },
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        let Some((scan_run_id, job_run_id, status, started_at, completed_at)) = raw else {
            return Ok(None);
        };
        let (Some(scan_run_id), Some(job_run_id), Some(status), Some(started_at)) =
            (scan_run_id, job_run_id, status, started_at)
        else {
            return Ok(None);
        };
        let status = match status.as_str() {
            "complete" => LibraryRootLastScanStatus::Complete,
            "partial" => LibraryRootLastScanStatus::Partial,
            "unavailable" => LibraryRootLastScanStatus::Unavailable,
            "cancelled" => LibraryRootLastScanStatus::Cancelled,
            "failed" => LibraryRootLastScanStatus::Failed,
            "abandoned" => LibraryRootLastScanStatus::Abandoned,
            _ => return Err(PersistenceError::CorruptOrIncompatible),
        };
        Ok(Some(LibraryRootLastScanSummary::new(
            scan_run_id,
            job_run_id,
            status,
            started_at,
            completed_at,
        )))
    }

    fn list_by_job(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Vec<ScanRunProjection>, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let mut statement = transaction
            .prepare(
                "SELECT scan_run_id, job_run_id, historical_library_root_id,
                        root_display_name, safe_location_display, status,
                        started_at, completed_at
                 FROM scan_run WHERE job_run_id = ?1
                 ORDER BY started_at ASC, scan_run_id ASC",
            )
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map([job_run_id.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, i64>(6)?,
                    row.get::<_, Option<i64>>(7)?,
                ))
            })
            .map_err(map_persistence_operation_error)?;
        let raw = rows
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?;
        raw.into_iter()
            .map(
                |(scan_run_id, job, root, display, safe, status, started, completed)| {
                    Ok(ScanRunProjection::new(
                        parse_scan_run_id(scan_run_id)?,
                        parse_job_run_id(job)?,
                        parse_root_id(root)?,
                        display,
                        safe,
                        parse_scan_status(&status)?,
                        started,
                        completed,
                    ))
                },
            )
            .collect()
    }
}

/// Transaction-scoped source-entry repository.
pub struct SqliteSourceEntryRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteSourceEntryRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl SourceEntryRepository for SqliteSourceEntryRepository<'_, '_> {
    fn upsert(&mut self, entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
        let transaction = self.work.transaction_mut()?;
        let created: String = transaction
            .query_row(
                "INSERT INTO source_entry
                    (source_entry_id, library_root_id, parent_source_entry_id,
                     relative_locator, locator_key, display_name, display_location,
                     kind, classification, provider_native_identity, source_fingerprint,
                     last_observed_scan_id, created_at, updated_at)
                 VALUES (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10,
                         ?11, ?12, ?12)
                 ON CONFLICT(library_root_id, locator_key) DO UPDATE SET
                     parent_source_entry_id = excluded.parent_source_entry_id,
                     relative_locator = excluded.relative_locator,
                     display_name = excluded.display_name,
                     display_location = excluded.display_location,
                     kind = excluded.kind,
                     classification = excluded.classification,
                     provider_native_identity = excluded.provider_native_identity,
                     source_fingerprint = excluded.source_fingerprint,
                     last_observed_scan_id = excluded.last_observed_scan_id,
                     updated_at = excluded.updated_at
                 RETURNING source_entry_id",
                rusqlite::params![
                    entry.library_root_id().to_string(),
                    entry.parent_source_entry_id().map(|id| id.to_string()),
                    entry.relative_locator().as_provider_value(),
                    entry.locator_key().as_provider_value(),
                    entry.display_name(),
                    entry.display_location(),
                    entry.kind().as_str(),
                    entry.classification().as_str(),
                    entry.provider_native_identity(),
                    entry.source_fingerprint(),
                    entry.last_observed_scan_id().to_string(),
                    crate::sqlite::migrations::timestamp(),
                ],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;
        parse_source_entry_id(created)
    }

    fn find_by_locator_key(
        &mut self,
        library_root_id: LibraryRootId,
        locator_key: &SourceLocatorKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        let raw = self
            .work
            .transaction_mut()?
            .query_row(
                "SELECT source_entry_id, parent_source_entry_id, relative_locator, locator_key,
                        display_name, display_location, kind, classification,
                        provider_native_identity, source_fingerprint, last_observed_scan_id
                 FROM source_entry
                 WHERE library_root_id = ?1 AND locator_key = ?2",
                rusqlite::params![library_root_id.to_string(), locator_key.as_provider_value(),],
                source_entry_record_raw,
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        raw.map(source_entry_record_from_raw).transpose()
    }

    fn find_native_identity(
        &mut self,
        library_root_id: LibraryRootId,
        provider_native_identity: &str,
    ) -> Result<NativeIdentityMatch, PersistenceError> {
        let mut statement = self
            .work
            .transaction_mut()?
            .prepare(
                "SELECT source_entry_id, parent_source_entry_id, relative_locator, locator_key,
                        display_name, display_location, kind, classification,
                        provider_native_identity, source_fingerprint, last_observed_scan_id
                 FROM source_entry
                 WHERE library_root_id = ?1 AND provider_native_identity = ?2
                 ORDER BY created_at ASC, source_entry_id ASC
                 LIMIT 2",
            )
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(
                rusqlite::params![library_root_id.to_string(), provider_native_identity],
                source_entry_record_raw,
            )
            .map_err(map_persistence_operation_error)?;
        let raw = rows
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?;
        match raw.len() {
            0 => Ok(NativeIdentityMatch::None),
            1 => Ok(NativeIdentityMatch::Unique(source_entry_record_from_raw(
                raw.into_iter().next().expect("one row"),
            )?)),
            _ => Ok(NativeIdentityMatch::Ambiguous),
        }
    }

    fn reconcile_move(
        &mut self,
        entry: NewSourceEntry,
        existing_source_entry_id: SourceEntryId,
    ) -> Result<SourceEntryId, PersistenceError> {
        let changed = self
            .work
            .transaction_mut()?
            .execute(
                "UPDATE source_entry
                 SET parent_source_entry_id = ?1,
                     relative_locator = ?2,
                     locator_key = ?3,
                     display_name = ?4,
                     display_location = ?5,
                     kind = ?6,
                     classification = ?7,
                     provider_native_identity = ?8,
                     source_fingerprint = ?9,
                     last_observed_scan_id = ?10,
                     updated_at = ?11
                 WHERE source_entry_id = ?12 AND library_root_id = ?13",
                rusqlite::params![
                    entry.parent_source_entry_id().map(|id| id.to_string()),
                    entry.relative_locator().as_provider_value(),
                    entry.locator_key().as_provider_value(),
                    entry.display_name(),
                    entry.display_location(),
                    entry.kind().as_str(),
                    entry.classification().as_str(),
                    entry.provider_native_identity(),
                    entry.source_fingerprint(),
                    entry.last_observed_scan_id().to_string(),
                    crate::sqlite::migrations::timestamp(),
                    existing_source_entry_id.to_string(),
                    entry.library_root_id().to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        match changed {
            1 => Ok(existing_source_entry_id),
            0 => Err(PersistenceError::Conflict),
            _ => Err(PersistenceError::CorruptOrIncompatible),
        }
    }

    fn list_children(
        &mut self,
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<SourceEntryRecord>, PersistenceError> {
        let mut statement = self
            .work
            .transaction_mut()?
            .prepare(
                "SELECT source_entry_id, parent_source_entry_id, relative_locator, locator_key,
                        display_name, display_location, kind, classification,
                        provider_native_identity, source_fingerprint, last_observed_scan_id
                 FROM source_entry
                 WHERE library_root_id = ?1 AND parent_source_entry_id IS ?2
                 ORDER BY created_at ASC, source_entry_id ASC
                 LIMIT ?3 OFFSET ?4",
            )
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(
                rusqlite::params![
                    library_root_id.to_string(),
                    parent_source_entry_id.map(|id| id.to_string()),
                    i64::from(limit),
                    i64::from(offset),
                ],
                source_entry_record_raw,
            )
            .map_err(map_persistence_operation_error)?;
        let raw = rows
            .collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?;
        raw.into_iter().map(source_entry_record_from_raw).collect()
    }

    fn delete_subtree(
        &mut self,
        library_root_id: LibraryRootId,
        source_entry_id: SourceEntryId,
    ) -> Result<bool, PersistenceError> {
        let changed = self
            .work
            .transaction_mut()?
            .execute(
                "WITH RECURSIVE subtree(source_entry_id) AS (
                     SELECT source_entry_id FROM source_entry
                     WHERE source_entry_id = ?2 AND library_root_id = ?1
                     UNION ALL
                     SELECT child.source_entry_id
                     FROM source_entry child
                     JOIN subtree ON child.parent_source_entry_id = subtree.source_entry_id
                     WHERE child.library_root_id = ?1
                 )
                 DELETE FROM source_entry
                 WHERE source_entry_id IN (SELECT source_entry_id FROM subtree)
                   AND library_root_id = ?1",
                rusqlite::params![library_root_id.to_string(), source_entry_id.to_string()],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(changed > 0)
    }

    fn finalize_absent_scope(
        &mut self,
        library_root_id: LibraryRootId,
        parent_source_entry_id: Option<SourceEntryId>,
        observed_scan_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        let changed = self
            .work
            .transaction_mut()?
            .execute(
                "WITH RECURSIVE absent_root(source_entry_id) AS (
                     SELECT source_entry_id FROM source_entry
                     WHERE library_root_id = ?1
                       AND parent_source_entry_id IS ?2
                       AND last_observed_scan_id != ?3
                 ),
                 subtree(source_entry_id) AS (
                     SELECT source_entry_id FROM absent_root
                     UNION ALL
                     SELECT child.source_entry_id
                     FROM source_entry child
                     JOIN subtree ON child.parent_source_entry_id = subtree.source_entry_id
                     WHERE child.library_root_id = ?1
                 )
                 DELETE FROM source_entry
                 WHERE source_entry_id IN (SELECT source_entry_id FROM subtree)
                   AND library_root_id = ?1",
                rusqlite::params![
                    library_root_id.to_string(),
                    parent_source_entry_id.map(|id| id.to_string()),
                    observed_scan_id.to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(changed as u64)
    }

    fn delete_for_root(&mut self, library_root_id: LibraryRootId) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "DELETE FROM source_entry WHERE library_root_id = ?1",
                [library_root_id.to_string()],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(())
    }
}

type SourceEntryRecordRaw = (
    String,
    Option<String>,
    String,
    String,
    String,
    String,
    String,
    String,
    Option<String>,
    Option<String>,
    String,
);

fn source_entry_record_raw(row: &rusqlite::Row<'_>) -> rusqlite::Result<SourceEntryRecordRaw> {
    Ok((
        row.get(0)?,
        row.get(1)?,
        row.get(2)?,
        row.get(3)?,
        row.get(4)?,
        row.get(5)?,
        row.get(6)?,
        row.get(7)?,
        row.get(8)?,
        row.get(9)?,
        row.get(10)?,
    ))
}

fn source_entry_record_from_raw(
    raw: SourceEntryRecordRaw,
) -> Result<SourceEntryRecord, PersistenceError> {
    let (
        id,
        parent,
        relative,
        key,
        display,
        location,
        kind,
        classification,
        native,
        fingerprint,
        observed,
    ) = raw;
    let source_entry_id = parse_source_entry_id(id)?;
    let parent_source_entry_id = parent.map(parse_source_entry_id).transpose()?;
    let kind = match kind.as_str() {
        "directory" => SourceEntryKind::Directory,
        "file" => SourceEntryKind::File,
        "link_like" => SourceEntryKind::LinkLike,
        "unknown" => SourceEntryKind::Unknown,
        _ => return Err(PersistenceError::CorruptOrIncompatible),
    };
    let classification = match classification.as_str() {
        "container" => SourceEntryClassification::Container,
        "content_candidate" => SourceEntryClassification::ContentCandidate,
        "supporting_entry" => SourceEntryClassification::SupportingEntry,
        "ignored" => SourceEntryClassification::Ignored,
        "unknown" => SourceEntryClassification::Unknown,
        _ => return Err(PersistenceError::CorruptOrIncompatible),
    };
    Ok(SourceEntryRecord::new(
        source_entry_id,
        parent_source_entry_id,
        RelativeSourceLocator::from_provider(relative),
        SourceLocatorKey::from_provider(key),
        display,
        location,
        kind,
        classification,
        native,
        fingerprint,
        parse_scan_run_id(observed)?,
    ))
}

/// Transaction-scoped library-scan admission-target repository.
pub struct SqliteLibraryScanTargetRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteLibraryScanTargetRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl LibraryScanTargetRepository for SqliteLibraryScanTargetRepository<'_, '_> {
    fn insert(&mut self, target: NewLibraryScanTarget) -> Result<(), PersistenceError> {
        let exclusion = target.exclusion();
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO library_scan_target
                    (job_run_id, target_kind, historical_library_root_id, display_name,
                     safe_location_display, scan_run_id, exclusion_reason,
                     related_job_run_id, related_scan_run_id)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                rusqlite::params![
                    target.job_run_id().to_string(),
                    target.kind().as_str(),
                    target.library_root_id().to_string(),
                    target.display_name(),
                    target.safe_location_display(),
                    target.scan_run_id().map(|id| id.to_string()),
                    exclusion.map(|exclusion| exclusion.reason().as_str()),
                    exclusion.and_then(|exclusion| exclusion
                        .active_job_run_id()
                        .map(|id| id.to_string())),
                    exclusion.and_then(|exclusion| exclusion
                        .active_scan_run_id()
                        .map(|id| id.to_string())),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(())
    }

    fn list_by_job(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Vec<LibraryScanTarget>, PersistenceError> {
        let job_run_id = job_run_id.to_string();
        read_library_scan_targets(self.work.transaction_mut()?, &job_run_id)
    }
}

/// Transaction-scoped immutable LibraryScan admission-context repository.
pub struct SqliteLibraryScanAdmissionContextRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteLibraryScanAdmissionContextRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }
}

impl LibraryScanAdmissionContextRepository for SqliteLibraryScanAdmissionContextRepository<'_, '_> {
    fn insert(&mut self, new: NewLibraryScanAdmissionContext) -> Result<(), PersistenceError> {
        self.work
            .transaction_mut()?
            .execute(
                "INSERT INTO library_scan_admission_context
                    (job_run_id, invocation_kind, retry_source_job_run_id)
                 VALUES (?1, ?2, ?3)",
                rusqlite::params![
                    new.job_run_id().to_string(),
                    new.invocation_kind().as_str(),
                    new.retry_source_job_run_id().map(|id| id.to_string()),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        Ok(())
    }

    fn get_by_job(
        &mut self,
        job_run_id: JobRunId,
    ) -> Result<Option<LibraryScanAdmissionContext>, PersistenceError> {
        let raw: Option<(String, Option<String>)> = self
            .work
            .transaction_mut()?
            .query_row(
                "SELECT invocation_kind, retry_source_job_run_id
                 FROM library_scan_admission_context WHERE job_run_id = ?1",
                [job_run_id.to_string()],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        let Some((invocation_kind, retry_source)) = raw else {
            return Ok(None);
        };
        let invocation_kind = match invocation_kind.as_str() {
            "initial_single_root" => LibraryScanInvocationKind::InitialSingleRoot,
            "retry_single_root" => LibraryScanInvocationKind::RetrySingleRoot,
            _ => return Err(PersistenceError::CorruptOrIncompatible),
        };
        Ok(Some(LibraryScanAdmissionContext::new(
            job_run_id,
            invocation_kind,
            retry_source.map(parse_job_run_id).transpose()?,
        )))
    }
}

/// Loads all durable admission targets for one job from any live connection.
fn read_library_scan_targets(
    connection: &rusqlite::Connection,
    job_run_id: &str,
) -> Result<Vec<LibraryScanTarget>, PersistenceError> {
    let mut statement = connection
        .prepare(
            "SELECT target_kind, historical_library_root_id, display_name,
                    safe_location_display, scan_run_id, exclusion_reason,
                    related_job_run_id, related_scan_run_id
             FROM library_scan_target WHERE job_run_id = ?1
             ORDER BY target_kind ASC, historical_library_root_id ASC",
        )
        .map_err(map_persistence_operation_error)?;
    let rows = statement
        .query_map([job_run_id.to_string()], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, Option<String>>(4)?,
                row.get::<_, Option<String>>(5)?,
                row.get::<_, Option<String>>(6)?,
                row.get::<_, Option<String>>(7)?,
            ))
        })
        .map_err(map_persistence_operation_error)?;
    let raw = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_persistence_operation_error)?;
    raw.into_iter()
        .map(
            |(
                kind,
                root,
                display,
                safe,
                scan_run_id,
                exclusion_reason,
                related_job_run_id,
                related_scan_run_id,
            )| {
                let kind = match kind.as_str() {
                    "requested" => LibraryScanTargetKind::Requested,
                    "admitted" => LibraryScanTargetKind::Admitted,
                    "excluded" => LibraryScanTargetKind::Excluded,
                    _ => return Err(PersistenceError::CorruptOrIncompatible),
                };
                let exclusion = match (exclusion_reason, related_job_run_id, related_scan_run_id) {
                    (Some(reason), job, scan) => {
                        let reason = match reason.as_str() {
                            "already_scanning" => LibraryScanTargetExclusionReason::AlreadyScanning,
                            "no_longer_configured" => {
                                LibraryScanTargetExclusionReason::NoLongerConfigured
                            }
                            "invalid_configuration" => {
                                LibraryScanTargetExclusionReason::InvalidConfiguration
                            }
                            _ => return Err(PersistenceError::CorruptOrIncompatible),
                        };
                        Some(LibraryScanAdmissionExclusion::new(
                            parse_root_id(root.clone())?,
                            reason,
                            job.map(parse_job_run_id).transpose()?,
                            scan.map(parse_scan_run_id).transpose()?,
                        ))
                    }
                    (None, None, None) => None,
                    _ => return Err(PersistenceError::CorruptOrIncompatible),
                };
                Ok(LibraryScanTarget::new(
                    kind,
                    parse_root_id(root)?,
                    display,
                    safe,
                    scan_run_id.map(parse_scan_run_id).transpose()?,
                    exclusion,
                ))
            },
        )
        .collect()
}

/// Independent authoritative jobs query adapter.
#[derive(Clone)]
pub struct SqliteJobsQueries {
    executor: SqliteDatabaseExecutor,
}

impl SqliteJobsQueries {
    /// Creates a query adapter over an existing shared SQLite executor.
    pub const fn new(executor: SqliteDatabaseExecutor) -> Self {
        Self { executor }
    }
}

impl JobsQueries for SqliteJobsQueries {
    fn get_job(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<JobDetail>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                read_job_detail(connection, &job_run_id.to_string())
            })
            .map_err(map_executor_error)
    }

    fn list_active(&self, context: &OperationContext) -> Result<Vec<JobSummary>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), |connection| {
                read_job_summaries(
                    connection,
                    "SELECT job_run_id, operation_type, state, current_phase, created_at,
                            started_at, completed_at, cancellation_requested
                     FROM job_run
                     WHERE state IN ('queued', 'preparing', 'running')
                     ORDER BY created_at ASC, job_run_id ASC",
                    Vec::new(),
                )
            })
            .map_err(map_executor_error)
    }

    fn list_recent_terminal(
        &self,
        context: &OperationContext,
        offset: u32,
        page_size: u32,
    ) -> Result<JobSummaryPage, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                let total = connection.scalar_i64(
                    "SELECT COUNT(*) FROM job_run
                     WHERE state IN ('completed', 'completed_with_issues', 'failed',
                                     'cancelled', 'interrupted', 'abandoned')",
                )?;
                let items = read_job_summaries(
                    connection,
                    "SELECT job_run_id, operation_type, state, current_phase, created_at,
                            started_at, completed_at, cancellation_requested
                     FROM job_run
                     WHERE state IN ('completed', 'completed_with_issues', 'failed',
                                     'cancelled', 'interrupted', 'abandoned')
                     ORDER BY completed_at DESC, job_run_id DESC
                     LIMIT ?1 OFFSET ?2",
                    vec![
                        rusqlite::types::Value::Integer(i64::from(page_size)),
                        rusqlite::types::Value::Integer(i64::from(offset)),
                    ],
                )?;
                let next_offset = ((offset as u64 + items.len() as u64) < total as u64)
                    .then_some(offset + items.len() as u32);
                Ok(JobSummaryPage::new(items, total as u32, next_offset))
            })
            .map_err(map_executor_error)
    }

    fn find_retry_successor(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<JobRunId>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                let raw: Option<String> = connection
                    .connection
                    .query_row(
                        "SELECT successor_job_run_id
                         FROM job_retry_link WHERE source_job_run_id = ?1",
                        [job_run_id.to_string()],
                        |row| row.get::<_, Option<String>>(0),
                    )
                    .optional()
                    .map_err(|error| super::errors::operation_error(&error))?
                    .flatten();
                raw.map(parse_job_run_id)
                    .transpose()
                    .map_err(corrupt_sqlite)
            })
            .map_err(map_executor_error)
    }

    fn list_requested_library_scan_targets(
        &self,
        context: &OperationContext,
        job_run_id: JobRunId,
    ) -> Result<Option<Vec<LibraryScanTarget>>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                let operation: Option<String> = connection
                    .connection
                    .query_row(
                        "SELECT operation_type FROM job_run WHERE job_run_id = ?1",
                        [job_run_id.to_string()],
                        |row| row.get(0),
                    )
                    .optional()
                    .map_err(|error| super::errors::operation_error(&error))?;
                if operation.as_deref() != Some(argus_application::OPERATION_TYPE_LIBRARY_SCAN) {
                    return Ok(None);
                }
                let targets =
                    read_library_scan_targets(connection.connection, &job_run_id.to_string())
                        .map_err(corrupt_sqlite)?;
                let requested = targets
                    .into_iter()
                    .filter(|target| target.kind() == LibraryScanTargetKind::Requested)
                    .collect();
                Ok(Some(requested))
            })
            .map_err(map_executor_error)
    }

    fn find_scan_admission_for_root(
        &self,
        context: &OperationContext,
        library_root_id: LibraryRootId,
    ) -> Result<Option<ScanAdmissionReference>, PersistenceError> {
        self.executor
            .with_connection(context.clone(), move |connection| {
                let raw: Option<(String, String)> = connection
                    .connection
                    .query_row(
                        "SELECT job_run_id, scan_run_id
                         FROM scan_run
                         WHERE historical_library_root_id = ?1
                         ORDER BY started_at DESC, scan_run_id DESC
                         LIMIT 1",
                        [library_root_id.to_string()],
                        |row| Ok((row.get(0)?, row.get(1)?)),
                    )
                    .optional()
                    .map_err(|error| super::errors::operation_error(&error))?;
                raw.map(|(job_run_id, scan_run_id)| {
                    Ok(ScanAdmissionReference::new(
                        parse_job_run_id(job_run_id)?,
                        parse_scan_run_id(scan_run_id)?,
                    ))
                })
                .transpose()
                .map_err(corrupt_sqlite)
            })
            .map_err(map_executor_error)
    }
}

fn read_job_summaries(
    connection: &mut SqliteConnection<'_>,
    sql: &str,
    values: Vec<rusqlite::types::Value>,
) -> Result<Vec<JobSummary>, SqliteOperationError> {
    let mut statement = connection
        .connection
        .prepare(sql)
        .map_err(|error| super::errors::operation_error(&error))?;
    let params: Vec<&dyn rusqlite::ToSql> = values
        .iter()
        .map(|value| value as &dyn rusqlite::ToSql)
        .collect();
    let rows = statement
        .query_map(params.as_slice(), |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, i64>(4)?,
                row.get::<_, Option<i64>>(5)?,
                row.get::<_, Option<i64>>(6)?,
                row.get::<_, i64>(7)?,
            ))
        })
        .map_err(|error| super::errors::operation_error(&error))?;
    let raw = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| super::errors::operation_error(&error))?;
    raw.into_iter()
        .map(
            |(job, operation, state, phase, created, started, terminal, cancellation)| {
                Ok(JobSummary::new(
                    parse_job_run_id(job).map_err(corrupt_sqlite)?,
                    operation,
                    parse_job_state(&state).map_err(corrupt_sqlite)?,
                    phase,
                    created,
                    started,
                    terminal,
                    cancellation != 0,
                    None,
                ))
            },
        )
        .collect()
}

fn read_job_detail(
    connection: &mut SqliteConnection<'_>,
    job_run_id: &str,
) -> Result<Option<JobDetail>, SqliteOperationError> {
    let raw = connection
        .connection
        .query_row(
            "SELECT job_run_id, operation_type, state, current_phase, completed_units,
                    total_units, status_key, created_at, queued_at, started_at, completed_at,
                    cancellation_requested, terminal_error_code, terminal_safe_context
             FROM job_run WHERE job_run_id = ?1",
            [job_run_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, Option<String>>(3)?,
                    row.get::<_, Option<i64>>(4)?,
                    row.get::<_, Option<i64>>(5)?,
                    row.get::<_, Option<String>>(6)?,
                    row.get::<_, i64>(7)?,
                    row.get::<_, Option<i64>>(8)?,
                    row.get::<_, Option<i64>>(9)?,
                    row.get::<_, Option<i64>>(10)?,
                    row.get::<_, i64>(11)?,
                    row.get::<_, Option<String>>(12)?,
                    row.get::<_, Option<String>>(13)?,
                ))
            },
        )
        .optional()
        .map_err(|error| super::errors::operation_error(&error))?;
    let Some((
        job,
        operation,
        state,
        phase,
        completed,
        total,
        status_key,
        created,
        queued,
        started,
        terminal,
        cancellation,
        error_code,
        safe_context,
    )) = raw
    else {
        return Ok(None);
    };
    let job_run_id = parse_job_run_id(job).map_err(corrupt_sqlite)?;
    let state = parse_job_state(&state).map_err(corrupt_sqlite)?;
    let cancellation_requested = cancellation != 0;
    if operation != "library_scan" {
        return Ok(None);
    }

    let retry_source: Option<String> = connection
        .connection
        .query_row(
            "SELECT retry_source_job_run_id
             FROM library_scan_admission_context WHERE job_run_id = ?1",
            [job_run_id.to_string()],
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()
        .map_err(|error| super::errors::operation_error(&error))?
        .flatten();
    let retry_source = retry_source
        .map(parse_job_run_id)
        .transpose()
        .map_err(corrupt_sqlite)?;
    let successor: Option<String> = connection
        .connection
        .query_row(
            "SELECT successor_job_run_id
             FROM job_retry_link WHERE source_job_run_id = ?1",
            [job_run_id.to_string()],
            |row| row.get::<_, Option<String>>(0),
        )
        .optional()
        .map_err(|error| super::errors::operation_error(&error))?
        .flatten();
    let successor = successor
        .map(parse_job_run_id)
        .transpose()
        .map_err(corrupt_sqlite)?;

    let mut scan_runs = Vec::new();
    let mut observed_counts = Vec::new();
    let mut committed_counts = Vec::new();
    let mut issue_counts = Vec::new();
    {
        let mut statement = connection
            .connection
            .prepare(
                "SELECT scan_run_id, job_run_id, historical_library_root_id,
                        root_display_name, safe_location_display, status,
                        started_at, completed_at, entries_observed,
                        entries_committed, issue_count
                 FROM scan_run WHERE job_run_id = ?1
                 ORDER BY started_at ASC, scan_run_id ASC",
            )
            .map_err(|error| super::errors::operation_error(&error))?;
        let rows = statement
            .query_map([job_run_id.to_string()], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, i64>(6)?,
                    row.get::<_, Option<i64>>(7)?,
                    row.get::<_, Option<i64>>(8)?,
                    row.get::<_, Option<i64>>(9)?,
                    row.get::<_, Option<i64>>(10)?,
                ))
            })
            .map_err(|error| super::errors::operation_error(&error))?;
        for row in rows {
            let (
                scan_run_id,
                job,
                root,
                display,
                safe,
                status,
                started_at,
                completed_at,
                entries_observed,
                entries_committed,
                issue_count,
            ) = row.map_err(|error| super::errors::operation_error(&error))?;
            scan_runs.push(ScanRunProjection::new(
                parse_scan_run_id(scan_run_id).map_err(corrupt_sqlite)?,
                parse_job_run_id(job).map_err(corrupt_sqlite)?,
                parse_root_id(root).map_err(corrupt_sqlite)?,
                display,
                safe,
                parse_scan_status(&status).map_err(corrupt_sqlite)?,
                started_at,
                completed_at,
            ));
            observed_counts.push(entries_observed.map(|value| value as u64));
            committed_counts.push(entries_committed.map(|value| value as u64));
            issue_counts.push(issue_count.map(|value| value as u64));
        }
    }
    let mut requested_roots = Vec::new();
    let mut admitted_roots = Vec::new();
    let mut exclusions = Vec::new();
    let targets = read_library_scan_targets(connection.connection, &job_run_id.to_string())
        .map_err(corrupt_sqlite)?;
    let mut requested_targets = Vec::new();
    for target in &targets {
        match target.kind() {
            LibraryScanTargetKind::Requested => {
                requested_targets.push(target.clone());
                requested_roots.push(LibraryScanRootSummary::new(
                    target.library_root_id(),
                    target.display_name().to_owned(),
                    target.safe_location_display().to_owned(),
                ));
            }
            LibraryScanTargetKind::Admitted => admitted_roots.push(LibraryScanRootSummary::new(
                target.library_root_id(),
                target.display_name().to_owned(),
                target.safe_location_display().to_owned(),
            )),
            LibraryScanTargetKind::Excluded => {
                let exclusion =
                    target
                        .exclusion()
                        .cloned()
                        .ok_or(SqliteOperationError::Application(
                            ApplicationPortError::Persistence(
                                PersistenceError::CorruptOrIncompatible,
                            ),
                        ))?;
                exclusions.push(exclusion);
            }
        }
    }

    let mut eligibility_input = Vec::with_capacity(requested_targets.len());
    for target in &requested_targets {
        let root_id = target.library_root_id().to_string();
        let facts: (i64, i64, Option<String>, Option<String>) = connection
            .connection
            .query_row(
                "SELECT
                    EXISTS(SELECT 1 FROM library_root r WHERE r.library_root_id = ?1),
                    EXISTS(SELECT 1 FROM library_root r
                            JOIN library_source s
                              ON s.library_source_id = r.library_source_id
                           WHERE r.library_root_id = ?1),
                    (SELECT s.job_run_id FROM scan_run s
                      WHERE s.historical_library_root_id = ?1 AND s.status = 'running'
                      ORDER BY s.started_at ASC, s.scan_run_id ASC LIMIT 1),
                    (SELECT s.scan_run_id FROM scan_run s
                      WHERE s.historical_library_root_id = ?1 AND s.status = 'running'
                      ORDER BY s.started_at ASC, s.scan_run_id ASC LIMIT 1)",
                [root_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .map_err(|error| super::errors::operation_error(&error))?;
        let active_owner = match facts {
            (_, _, Some(job), Some(scan)) => Some(ActiveScanOwnership::new(
                parse_job_run_id(job).map_err(corrupt_sqlite)?,
                parse_scan_run_id(scan).map_err(corrupt_sqlite)?,
                1,
            )),
            (_, _, None, None) => None,
            _ => return Err(corrupt_sqlite(PersistenceError::CorruptOrIncompatible)),
        };
        eligibility_input.push((
            target.clone(),
            LibraryScanTargetEligibility {
                configured: facts.0 != 0,
                configuration_valid: facts.1 != 0,
                active_owner,
            },
        ));
    }
    let evaluation = evaluate_retry_eligibility(state, successor.is_some(), &eligibility_input);
    let controls = JobControlAvailability::new(
        state.is_active() && !cancellation_requested,
        evaluation.can_retry(),
    );
    let job_projection = JobRunProjection::new(
        job_run_id,
        operation.clone(),
        state,
        phase.clone(),
        completed.map(|value| value as u64),
        total.map(|value| value as u64),
        status_key,
        created,
        queued,
        started,
        terminal,
        cancellation_requested,
        controls,
        error_code,
        safe_context,
    );
    let progress = ScanProgressFacts::new(
        phase,
        completed.map(|value| value as u64),
        total.map(|value| value as u64),
        job_projection.status_key().map(str::to_owned),
        requested_roots.len() as u32,
        admitted_roots.len() as u32,
        scan_runs
            .iter()
            .filter(|run| run.status().is_terminal())
            .count() as u32,
        aggregate_scan_counter(&observed_counts),
        aggregate_scan_counter(&committed_counts),
        aggregate_scan_counter(&issue_counts),
    );
    let detail = LibraryScanJobDetail::new(
        requested_roots,
        admitted_roots,
        exclusions,
        scan_runs,
        progress,
        retry_source,
        successor,
    );
    Ok(Some(JobDetail::new(
        job_projection,
        argus_application::OperationDetail::LibraryScan(detail),
    )))
}

/// Aggregates nullable scan-run counters into one truthful projection.
///
/// Any contributing scan run with an unknown counter makes the aggregate
/// unknown; an empty scan-run set is also unknown rather than fabricated zero.
fn aggregate_scan_counter(values: &[Option<u64>]) -> Option<u64> {
    if values.is_empty() {
        return None;
    }
    let mut total = 0_u64;
    for value in values {
        total = total.checked_add((*value)?)?;
    }
    Some(total)
}

fn parse_job_state(value: &str) -> Result<JobRunState, PersistenceError> {
    JobRunState::try_from(value).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_scan_status(value: &str) -> Result<ScanRunStatus, PersistenceError> {
    ScanRunStatus::try_from(value).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_job_run_id(value: String) -> Result<JobRunId, PersistenceError> {
    JobRunId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_scan_run_id(value: String) -> Result<ScanRunId, PersistenceError> {
    ScanRunId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_source_entry_id(value: String) -> Result<SourceEntryId, PersistenceError> {
    SourceEntryId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_root_id(value: String) -> Result<LibraryRootId, PersistenceError> {
    LibraryRootId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

pub(crate) fn map_persistence_operation_error(error: rusqlite::Error) -> PersistenceError {
    match super::errors::operation_error(&error) {
        SqliteOperationError::Constraint => PersistenceError::ConstraintViolation,
        SqliteOperationError::Locked => PersistenceError::DatabaseLocked,
        SqliteOperationError::Failed => PersistenceError::Internal,
        SqliteOperationError::Application(_) => PersistenceError::Internal,
    }
}

fn corrupt_sqlite(error: PersistenceError) -> SqliteOperationError {
    SqliteOperationError::Application(ApplicationPortError::Persistence(error))
}
