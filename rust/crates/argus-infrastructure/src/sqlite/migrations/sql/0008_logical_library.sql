CREATE TABLE game_content (
    game_content_id TEXT PRIMARY KEY,
    platform_id TEXT NOT NULL CHECK (platform_id IN ('nintendo.gb', 'nintendo.gbc', 'nintendo.gba')),
    content_type TEXT NOT NULL CHECK (content_type = 'CartridgeImage'),
    presence_state TEXT NOT NULL CHECK (presence_state IN ('available', 'partially_unavailable', 'unavailable', 'orphaned')),
    identification_state TEXT NOT NULL CHECK (identification_state IN ('identified', 'needs_reidentification', 'unidentified')),
    grouping_revision INTEGER NOT NULL CHECK (grouping_revision > 0),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE content_identity (
    content_identity_id TEXT PRIMARY KEY,
    game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    scheme_id TEXT NOT NULL,
    identity_revision INTEGER NOT NULL CHECK (identity_revision > 0),
    identity_value TEXT NOT NULL,
    is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
    -- Historical proof may outlive the physical SourceEntry row so that a
    -- later independent re-identification can compare bounded evidence.
    proving_source_entry_id TEXT,
    proving_association_key TEXT,
    proving_source_fingerprint TEXT,
    proving_scan_run_id TEXT REFERENCES scan_run(scan_run_id),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX uq_content_identity_current_content
    ON content_identity(game_content_id)
    WHERE is_current = 1;

CREATE UNIQUE INDEX uq_content_identity_current_value
    ON content_identity(scheme_id, identity_value)
    WHERE is_current = 1;

CREATE INDEX idx_content_identity_proving_source
    ON content_identity(proving_source_entry_id);

CREATE TABLE game_content_source (
    game_content_source_id TEXT PRIMARY KEY,
    game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    source_entry_id TEXT NOT NULL REFERENCES source_entry(source_entry_id),
    association_key TEXT NOT NULL,
    source_fingerprint TEXT,
    last_observed_scan_id TEXT REFERENCES scan_run(scan_run_id),
    is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(game_content_id, source_entry_id, association_key)
);

CREATE INDEX idx_game_content_source_entry
    ON game_content_source(source_entry_id, is_current);

CREATE INDEX idx_game_content_source_content
    ON game_content_source(game_content_id, is_current);

CREATE TABLE game (
    game_id TEXT PRIMARY KEY,
    platform_id TEXT NOT NULL CHECK (platform_id IN ('nintendo.gb', 'nintendo.gbc', 'nintendo.gba')),
    lifecycle_state TEXT NOT NULL CHECK (lifecycle_state IN ('active', 'inactive_orphan', 'redirected')),
    grouping_revision INTEGER NOT NULL CHECK (grouping_revision > 0),
    fallback_title TEXT NOT NULL,
    fallback_title_provenance TEXT NOT NULL CHECK (fallback_title_provenance = 'local_fallback'),
    hydration_state TEXT NOT NULL CHECK (hydration_state IN ('hydrated', 'partially_hydrated', 'unmatched', 'refreshing')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE game_membership (
    game_membership_id TEXT PRIMARY KEY,
    game_id TEXT NOT NULL REFERENCES game(game_id),
    game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    relationship TEXT NOT NULL CHECK (relationship IN ('primary', 'secondary')),
    grouping_basis TEXT NOT NULL CHECK (grouping_basis IN ('exact_content_identity', 'provisional')),
    grouping_revision INTEGER NOT NULL CHECK (grouping_revision > 0),
    is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(game_id, game_content_id, relationship)
);

CREATE UNIQUE INDEX uq_game_membership_current_content
    ON game_membership(game_content_id)
    WHERE is_current = 1;

CREATE UNIQUE INDEX uq_game_membership_current_primary
    ON game_membership(game_id)
    WHERE is_current = 1 AND relationship = 'primary';

CREATE TABLE game_redirect (
    game_id TEXT PRIMARY KEY REFERENCES game(game_id),
    canonical_game_id TEXT NOT NULL REFERENCES game(game_id),
    created_at TEXT NOT NULL,
    CHECK (game_id <> canonical_game_id)
);

CREATE TABLE game_library_row (
    game_id TEXT PRIMARY KEY REFERENCES game(game_id),
    display_title TEXT NOT NULL,
    display_title_provenance TEXT NOT NULL CHECK (display_title_provenance = 'local_fallback'),
    platform_id TEXT NOT NULL CHECK (platform_id IN ('nintendo.gb', 'nintendo.gbc', 'nintendo.gba')),
    hydration_state TEXT NOT NULL CHECK (hydration_state IN ('hydrated', 'partially_hydrated', 'unmatched', 'refreshing')),
    availability_state TEXT NOT NULL CHECK (availability_state IN ('available', 'partially_unavailable', 'unavailable', 'inactive_orphan')),
    content_count INTEGER NOT NULL CHECK (content_count >= 0),
    source_count INTEGER NOT NULL CHECK (source_count >= 0),
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_game_library_row_default_order
    ON game_library_row(display_title COLLATE NOCASE ASC, game_id ASC);
