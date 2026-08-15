-- Slice 006: durable Scan All admission metadata, bounded InvalidConfiguration
-- exclusions, deterministic target ordering, and restart-recovery support.
--
-- The generic job_run table stays capability-neutral. Scan All request
-- identity is operation-specific admission metadata, never a second Job ID.

-- Rebuild LibraryScan admission context so the invocation vocabulary accepts
-- Scan All values and admits one durable client request identity per accepted
-- Scan All admission. Existing single-root rows keep their original values.
CREATE TABLE library_scan_admission_context_new (
    job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    invocation_kind TEXT NOT NULL CHECK (invocation_kind IN (
        'initial_single_root', 'retry_single_root',
        'initial_scan_all', 'retry_scan_all'
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
SELECT job_run_id, invocation_kind, retry_source_job_run_id, NULL
FROM library_scan_admission_context;

DROP TABLE library_scan_admission_context;
ALTER TABLE library_scan_admission_context_new
    RENAME TO library_scan_admission_context;

CREATE INDEX idx_library_scan_admission_retry_source
    ON library_scan_admission_context(retry_source_job_run_id)
    WHERE retry_source_job_run_id IS NOT NULL;

-- Rebuild admission targets with bounded InvalidConfiguration error columns.
-- The migration stage table lets legacy invalid-configuration rows be
-- backfilled to the canonical ConfigurationInvalid error before the final
-- table's validation constraints are applied.
CREATE TABLE library_scan_target_stage (
    job_run_id TEXT NOT NULL,
    target_kind TEXT NOT NULL,
    historical_library_root_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    safe_location_display TEXT NOT NULL,
    scan_run_id TEXT,
    exclusion_reason TEXT,
    related_job_run_id TEXT,
    related_scan_run_id TEXT,
    exclusion_error_code TEXT,
    exclusion_error_trace_id TEXT,
    exclusion_error_safe_context TEXT
);

INSERT INTO library_scan_target_stage
    (job_run_id, target_kind, historical_library_root_id, display_name,
     safe_location_display, scan_run_id, exclusion_reason,
     related_job_run_id, related_scan_run_id,
     exclusion_error_code, exclusion_error_trace_id,
     exclusion_error_safe_context)
SELECT job_run_id, target_kind, historical_library_root_id, display_name,
       safe_location_display, scan_run_id, exclusion_reason,
       related_job_run_id, related_scan_run_id,
       NULL, NULL, NULL
FROM library_scan_target;

UPDATE library_scan_target_stage
SET exclusion_error_code = 'ARGUS.V1.CONFIGURATION.INVALID',
    exclusion_error_trace_id = '00000000000000000000000000000001',
    exclusion_error_safe_context =
        'technical_class:636f6e66696775726174696f6e5f696e76616c6964;failure_role:7072696d617279'
WHERE exclusion_reason = 'invalid_configuration';

CREATE TABLE library_scan_target_new (
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
    exclusion_error_code TEXT,
    exclusion_error_trace_id TEXT,
    exclusion_error_safe_context TEXT,
    PRIMARY KEY (job_run_id, target_kind, historical_library_root_id),
    CHECK (
        (exclusion_reason IS NULL
            AND related_job_run_id IS NULL
            AND related_scan_run_id IS NULL)
        OR
        (exclusion_reason = 'already_scanning'
            AND related_job_run_id IS NOT NULL
            AND related_scan_run_id IS NOT NULL)
        OR
        (exclusion_reason IN ('no_longer_configured', 'invalid_configuration')
            AND related_job_run_id IS NULL
            AND related_scan_run_id IS NULL)
    ),
    CHECK (
        (exclusion_reason != 'invalid_configuration'
            AND exclusion_error_code IS NULL
            AND exclusion_error_trace_id IS NULL
            AND exclusion_error_safe_context IS NULL)
        OR
        (exclusion_reason = 'invalid_configuration'
            AND exclusion_error_code IS NOT NULL
            AND exclusion_error_trace_id IS NOT NULL
            AND exclusion_error_safe_context IS NOT NULL)
    )
);

INSERT INTO library_scan_target_new
    (job_run_id, target_kind, historical_library_root_id, display_name,
     safe_location_display, scan_run_id, exclusion_reason,
     related_job_run_id, related_scan_run_id,
     exclusion_error_code, exclusion_error_trace_id,
     exclusion_error_safe_context)
SELECT job_run_id, target_kind, historical_library_root_id, display_name,
       safe_location_display, scan_run_id, exclusion_reason,
       related_job_run_id, related_scan_run_id,
       exclusion_error_code, exclusion_error_trace_id,
       exclusion_error_safe_context
FROM library_scan_target_stage;

DROP TABLE library_scan_target_stage;
DROP TABLE library_scan_target;
ALTER TABLE library_scan_target_new RENAME TO library_scan_target;

CREATE INDEX idx_library_scan_target_job ON library_scan_target(job_run_id);
