ALTER TABLE library_root
    ADD COLUMN last_scan_status TEXT;
ALTER TABLE library_root
    ADD COLUMN last_scan_scan_run_id TEXT;
ALTER TABLE library_root
    ADD COLUMN last_scan_job_run_id TEXT;
ALTER TABLE library_root
    ADD COLUMN last_scan_started_at INTEGER;
ALTER TABLE library_root
    ADD COLUMN last_scan_completed_at INTEGER;

CREATE TABLE job_run (
    job_run_id TEXT PRIMARY KEY,
    operation_type TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN (
        'queued', 'preparing', 'running', 'completed', 'completed_with_issues',
        'failed', 'cancelled', 'interrupted', 'abandoned'
    )),
    command_id TEXT,
    resumed_from_job_run_id TEXT,
    created_at INTEGER NOT NULL,
    queued_at INTEGER,
    started_at INTEGER,
    completed_at INTEGER,
    current_phase TEXT,
    completed_units INTEGER,
    total_units INTEGER,
    status_key TEXT,
    cancellation_requested INTEGER NOT NULL DEFAULT 0
        CHECK (cancellation_requested IN (0, 1)),
    terminal_error_code TEXT,
    terminal_safe_context TEXT
);

CREATE INDEX idx_job_run_state_created ON job_run(state, created_at, job_run_id);

CREATE TABLE scan_run (
    scan_run_id TEXT PRIMARY KEY,
    job_run_id TEXT NOT NULL REFERENCES job_run(job_run_id),
    historical_library_root_id TEXT NOT NULL,
    root_locator TEXT NOT NULL,
    root_display_name TEXT NOT NULL,
    safe_location_display TEXT NOT NULL,
    source_config_revision INTEGER NOT NULL,
    root_config_revision INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN (
        'running', 'complete', 'partial', 'failed', 'cancelled', 'abandoned'
    )),
    started_at INTEGER NOT NULL,
    completed_at INTEGER,
    failure_reason TEXT
);

CREATE UNIQUE INDEX uq_scan_run_active_root
    ON scan_run(historical_library_root_id)
    WHERE status = 'running';

CREATE INDEX idx_scan_run_job ON scan_run(job_run_id);
CREATE INDEX idx_scan_run_root ON scan_run(historical_library_root_id);

CREATE TABLE library_scan_target (
    job_run_id TEXT NOT NULL REFERENCES job_run(job_run_id),
    target_kind TEXT NOT NULL CHECK (target_kind IN (
        'requested', 'admitted', 'excluded'
    )),
    historical_library_root_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    safe_location_display TEXT NOT NULL,
    scan_run_id TEXT,
    exclusion_reason TEXT,
    related_job_run_id TEXT,
    related_scan_run_id TEXT,
    PRIMARY KEY (job_run_id, target_kind, historical_library_root_id)
);

CREATE INDEX idx_library_scan_target_job ON library_scan_target(job_run_id);

CREATE TABLE source_entry (
    source_entry_id TEXT PRIMARY KEY,
    library_root_id TEXT NOT NULL,
    parent_source_entry_id TEXT,
    relative_locator TEXT NOT NULL,
    locator_key TEXT NOT NULL,
    display_name TEXT NOT NULL,
    display_location TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN (
        'directory', 'file', 'link_like', 'unknown'
    )),
    classification TEXT NOT NULL CHECK (classification IN (
        'container', 'content_candidate', 'supporting_entry', 'ignored', 'unknown'
    )),
    provider_native_identity TEXT,
    source_fingerprint TEXT,
    last_observed_scan_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE (library_root_id, locator_key)
);

CREATE INDEX idx_source_entry_root_parent
    ON source_entry(library_root_id, parent_source_entry_id);
