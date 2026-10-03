-- Durable Library-refresh issue detail for Phase 003 refresh operations.
--
-- A refresh can legitimately reach its safe terminal boundary with meaningful
-- committed work while some admitted scope stayed unsatisfied, which the
-- generic Jobs lifecycle reports as `completed_with_issues`. The refresh issue
-- summary and its bounded typed facts are the operation-specific authority that
-- explains that state. They are refresh-owned rather than scan-owned, so a
-- refresh never reuses a child scan run's intake counters as its own issue
-- projection.
--
-- The stored vocabulary is closed and safe: a category key, a normalized reason
-- key, an optional provider identity, and a positive occurrence count. No raw
-- error text, provider payload, locator, path, URL, or secret is representable
-- here.

CREATE TABLE library_refresh_issue_summary (
    job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    issue_count INTEGER NOT NULL CHECK (issue_count >= 0)
);

CREATE TABLE library_refresh_issue_fact (
    job_run_id TEXT NOT NULL REFERENCES job_run(job_run_id),
    issue_ordinal INTEGER NOT NULL CHECK (issue_ordinal >= 0 AND issue_ordinal < 128),
    issue_kind TEXT NOT NULL CHECK (issue_kind IN (
        'matching', 'metadata', 'artwork_discovery', 'artwork_download',
        'asset_store', 'content', 'scope'
    )),
    issue_reason TEXT NOT NULL CHECK (issue_reason IN (
        'provider_authentication_failed', 'provider_authorization_failed',
        'provider_misconfigured', 'provider_rate_limited', 'provider_timeout',
        'provider_unavailable', 'provider_invalid_response',
        'provider_unsupported_capability', 'artwork_asset_too_large',
        'artwork_asset_invalid_image', 'artwork_asset_dimensions_too_large',
        'artwork_asset_store_unavailable', 'content_unavailable',
        'content_malformed_or_unsupported', 'content_encrypted_unsupported',
        'content_dependency_missing', 'content_resource_limit_exceeded',
        'content_changed_during_refresh', 'content_identity_unsupported',
        'content_identification_failed', 'content_grouping_failed',
        'content_refresh_failed', 'scope_root_not_admitted',
        'scope_root_scan_incomplete', 'scope_root_scan_failed'
    )),
    provider_id TEXT CHECK (provider_id IN (
        'playmatch', 'gametdb', 'steamgriddb'
    )),
    occurrences INTEGER NOT NULL CHECK (occurrences > 0),
    PRIMARY KEY (job_run_id, issue_ordinal)
);

-- One row per complete typed identity keeps the durable representation
-- deterministic and keeps an aggregate total reconstructible.
CREATE UNIQUE INDEX uq_library_refresh_issue_identity
    ON library_refresh_issue_fact (
        job_run_id,
        issue_kind,
        issue_reason,
        COALESCE(provider_id, '')
    );
