//! Shared no-op repository fakes for application contract tests.

use std::marker::PhantomData;

use argus_application::{
    ActiveScanOwnership, AppearanceSettings, AppearanceSettingsRepository, JobProgress, JobRunId,
    JobRunRepository, JobRunState, LibraryRootAvailability, LibraryRootId,
    LibraryRootLastScanSummary, LibraryRootRepository, LibraryRootScanConfiguration,
    LibraryScanAdmissionContext, LibraryScanAdmissionContextRepository, LibraryScanTarget,
    LibraryScanTargetRepository, LibrarySourceId, LibrarySourceRepository, NativeIdentityMatch,
    NewJobRun, NewLibraryRoot, NewLibraryScanAdmissionContext, NewLibraryScanTarget, NewScanRun,
    NewSourceEntry, PersistenceError, ScanRunId, ScanRunProjection, ScanRunRepository,
    ScanRunStatus, SourceEntryId, SourceEntryRecord, SourceEntryRepository, SourceLocatorKey,
    ThemeMode,
};

/// Transaction-scoped no-op appearance repository.
#[allow(dead_code)]
pub struct NoopAppearanceRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl AppearanceSettingsRepository for NoopAppearanceRepository<'_> {
    fn get(&mut self) -> Result<AppearanceSettings, PersistenceError> {
        Ok(AppearanceSettings::new(ThemeMode::System))
    }

    fn save(&mut self, _settings: &AppearanceSettings) -> Result<(), PersistenceError> {
        Ok(())
    }
}

/// Transaction-scoped no-op internal library-source repository.
#[allow(dead_code)]
pub struct NoopLibrarySourceRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl LibrarySourceRepository for NoopLibrarySourceRepository<'_> {
    fn ensure_local_filesystem_source(&mut self) -> Result<LibrarySourceId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

/// Transaction-scoped no-op job-run repository.
#[allow(dead_code)]
pub struct NoopJobRunRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl JobRunRepository for NoopJobRunRepository<'_> {
    fn insert(&mut self, _new: NewJobRun) -> Result<JobRunId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn insert_retry_link(
        &mut self,
        _source_job_run_id: JobRunId,
        _successor_job_run_id: JobRunId,
    ) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn request_cancellation(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Option<bool>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn set_state(
        &mut self,
        _job_run_id: JobRunId,
        _state: JobRunState,
        _timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn set_progress(
        &mut self,
        _job_run_id: JobRunId,
        _progress: &JobProgress,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn set_terminal_failure(
        &mut self,
        _job_run_id: JobRunId,
        _state: JobRunState,
        _terminal_error_code: Option<String>,
        _terminal_safe_context: Option<String>,
        _timestamp_ms: i64,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

/// Transaction-scoped no-op scan-run repository.
#[allow(dead_code)]
pub struct NoopScanRunRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl ScanRunRepository for NoopScanRunRepository<'_> {
    fn insert(&mut self, _new: NewScanRun) -> Result<ScanRunId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn set_status(
        &mut self,
        _scan_run_id: ScanRunId,
        _status: ScanRunStatus,
        _completed_at_ms: Option<i64>,
        _failure_reason: Option<String>,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn set_progress_facts(
        &mut self,
        _scan_run_id: ScanRunId,
        _entries_observed: u64,
        _entries_committed: u64,
        _issue_count: u64,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_active_ownership(
        &mut self,
        _library_root_id: LibraryRootId,
    ) -> Result<Option<ActiveScanOwnership>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_last_scan(
        &mut self,
        _library_root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootLastScanSummary>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn list_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Vec<ScanRunProjection>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

/// Transaction-scoped no-op source-entry repository.
#[allow(dead_code)]
pub struct NoopSourceEntryRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl SourceEntryRepository for NoopSourceEntryRepository<'_> {
    fn upsert(&mut self, _entry: NewSourceEntry) -> Result<SourceEntryId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_by_locator_key(
        &mut self,
        _library_root_id: LibraryRootId,
        _locator_key: &SourceLocatorKey,
    ) -> Result<Option<SourceEntryRecord>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn find_native_identity(
        &mut self,
        _library_root_id: LibraryRootId,
        _provider_native_identity: &str,
    ) -> Result<NativeIdentityMatch, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn reconcile_move(
        &mut self,
        _entry: NewSourceEntry,
        _existing_source_entry_id: SourceEntryId,
    ) -> Result<SourceEntryId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn list_children(
        &mut self,
        _library_root_id: LibraryRootId,
        _parent_source_entry_id: Option<SourceEntryId>,
        _offset: u32,
        _limit: u32,
    ) -> Result<Vec<SourceEntryRecord>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete_subtree(
        &mut self,
        _library_root_id: LibraryRootId,
        _source_entry_id: SourceEntryId,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn finalize_absent_scope(
        &mut self,
        _library_root_id: LibraryRootId,
        _parent_source_entry_id: Option<SourceEntryId>,
        _observed_scan_id: ScanRunId,
    ) -> Result<u64, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete_for_root(&mut self, _library_root_id: LibraryRootId) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

/// Transaction-scoped no-op admission-target repository.
#[allow(dead_code)]
pub struct NoopLibraryScanTargetRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl LibraryScanTargetRepository for NoopLibraryScanTargetRepository<'_> {
    fn insert(&mut self, _target: NewLibraryScanTarget) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn list_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Vec<LibraryScanTarget>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

/// Transaction-scoped no-op LibraryScan admission-context repository.
#[allow(dead_code)]
pub struct NoopLibraryScanAdmissionContextRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl LibraryScanAdmissionContextRepository for NoopLibraryScanAdmissionContextRepository<'_> {
    fn insert(&mut self, _new: NewLibraryScanAdmissionContext) -> Result<(), PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn get_by_job(
        &mut self,
        _job_run_id: JobRunId,
    ) -> Result<Option<LibraryScanAdmissionContext>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}

/// Transaction-scoped no-op configured-root repository.
#[allow(dead_code)]
pub struct NoopLibraryRootRepository<'scope> {
    pub marker: PhantomData<&'scope mut ()>,
}

impl LibraryRootRepository for NoopLibraryRootRepository<'_> {
    fn insert(&mut self, _root: NewLibraryRoot) -> Result<LibraryRootId, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn delete(&mut self, _root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn exists(&mut self, _root_id: LibraryRootId) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn set_availability(
        &mut self,
        _root_id: LibraryRootId,
        _availability: LibraryRootAvailability,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn set_last_scan(
        &mut self,
        _root_id: LibraryRootId,
        _summary: Option<LibraryRootLastScanSummary>,
    ) -> Result<bool, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }

    fn get_scan_authority(
        &mut self,
        _root_id: LibraryRootId,
    ) -> Result<Option<LibraryRootScanConfiguration>, PersistenceError> {
        Err(PersistenceError::Unavailable)
    }
}
