-- Phase 003 Library refresh invocation kinds.
-- The operation-specific admission table remains the authority for scan
-- recovery metadata; composed refreshes use the same child-plan boundary but
-- never carry a public Scan All request identity.

CREATE TABLE library_scan_admission_context_new (
    job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    invocation_kind TEXT NOT NULL CHECK (invocation_kind IN (
        'initial_single_root', 'retry_single_root',
        'initial_scan_all', 'retry_scan_all',
        'initial_library_refresh', 'retry_library_refresh'
    )),
    retry_source_job_run_id TEXT REFERENCES job_run(job_run_id),
    scan_all_request_identity TEXT UNIQUE CHECK (
        (invocation_kind = 'initial_scan_all'
            AND scan_all_request_identity IS NOT NULL
            AND length(scan_all_request_identity) BETWEEN 1 AND 256)
        OR
        (invocation_kind != 'initial_scan_all'
            AND scan_all_request_identity IS NULL)
    )
);

INSERT INTO library_scan_admission_context_new
    (job_run_id, invocation_kind, retry_source_job_run_id, scan_all_request_identity)
SELECT job_run_id, invocation_kind, retry_source_job_run_id, scan_all_request_identity
FROM library_scan_admission_context;

DROP TABLE library_scan_admission_context;
ALTER TABLE library_scan_admission_context_new
    RENAME TO library_scan_admission_context;

CREATE INDEX idx_library_scan_admission_retry_source
    ON library_scan_admission_context(retry_source_job_run_id)
    WHERE retry_source_job_run_id IS NOT NULL;
