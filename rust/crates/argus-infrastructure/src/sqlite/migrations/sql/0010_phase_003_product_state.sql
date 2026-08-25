-- Phase 003 product onboarding and focused refresh intent.
-- These tables retain immutable command intent without introducing a generic
-- workflow-node scheduler or mixing it into the capability-neutral JobRun row.

CREATE TABLE library_onboarding_progress (
    singleton_key INTEGER PRIMARY KEY CHECK (singleton_key = 1),
    accepted_privacy_terms_version TEXT,
    accepted_privacy_at_ms INTEGER,
    metadata_preferences_confirmed INTEGER NOT NULL DEFAULT 0
        CHECK (metadata_preferences_confirmed IN (0, 1)),
    provider_setup_outcome TEXT NOT NULL DEFAULT 'pending'
        CHECK (provider_setup_outcome IN ('pending', 'configured', 'skipped')),
    completed_at_ms INTEGER
);

INSERT INTO library_onboarding_progress (singleton_key)
VALUES (1);

CREATE TABLE library_refresh_intent (
    job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    trigger_kind TEXT NOT NULL CHECK (
        trigger_kind IN ('manual', 'added_root', 'initial_onboarding')
    ),
    trigger_root_id TEXT,
    mode TEXT NOT NULL CHECK (mode IN ('eligible_only', 'force')),
    CHECK (
        (trigger_kind = 'added_root' AND trigger_root_id IS NOT NULL)
        OR (trigger_kind <> 'added_root' AND trigger_root_id IS NULL)
    )
);

CREATE TABLE game_refresh_intent (
    job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    game_ids TEXT NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('eligible_only', 'force'))
);

CREATE TABLE library_resolution_refresh_intent (
    job_run_id TEXT PRIMARY KEY REFERENCES job_run(job_run_id),
    settings_revision INTEGER NOT NULL CHECK (settings_revision >= 0)
);
