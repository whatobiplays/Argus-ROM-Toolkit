-- Slice 005: durable LibraryScan retry metadata and structured progress facts.
--
-- The generic job_run table stays capability-neutral. LibraryScan-specific
-- immutable admission-context facts live in their own table, and the source
-- run's direct successor relation is separate durable retry-link metadata
-- with foreign keys on both endpoints.

CREATE TABLE library_scan_admission_context (
    job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    invocation_kind TEXT NOT NULL CHECK (invocation_kind IN (
        'initial_single_root', 'retry_single_root'
    )),
    retry_source_job_run_id TEXT REFERENCES job_run(job_run_id)
);

CREATE INDEX idx_library_scan_admission_retry_source
    ON library_scan_admission_context(retry_source_job_run_id)
    WHERE retry_source_job_run_id IS NOT NULL;

CREATE TABLE job_retry_link (
    source_job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    successor_job_run_id TEXT NOT NULL UNIQUE REFERENCES job_run(job_run_id)
);

ALTER TABLE scan_run ADD COLUMN entries_observed INTEGER;
ALTER TABLE scan_run ADD COLUMN entries_committed INTEGER;
ALTER TABLE scan_run ADD COLUMN issue_count INTEGER;

-- Existing Slice 002-004 library_scan history is an initial single-root
-- invocation; Scan All did not exist before Slice 006.
INSERT INTO library_scan_admission_context (job_run_id, invocation_kind)
SELECT job_run_id, 'initial_single_root'
FROM job_run
WHERE operation_type = 'library_scan';
