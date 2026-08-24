CREATE TABLE external_identity_mapping (
    mapping_id TEXT PRIMARY KEY,
    game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    provider_id TEXT NOT NULL CHECK (provider_id IN ('playmatch', 'gametdb', 'steamgriddb')),
    external_game_id TEXT NOT NULL,
    external_release_id TEXT,
    provider_platform_id TEXT NOT NULL,
    provider_confidence REAL,
    match_basis TEXT NOT NULL CHECK (
        match_basis IN (
            'playmatch_exact_content',
            'gametdb_exact_native_identifier',
            'existing_exact_mapping',
            'rejected_by_policy'
        )
    ),
    provider_revision INTEGER NOT NULL CHECK (provider_revision > 0),
    state TEXT NOT NULL CHECK (state IN ('current', 'stale', 'rejected_by_policy')),
    matched_at TEXT NOT NULL,
    last_validated_at TEXT NOT NULL,
    UNIQUE(game_content_id, provider_id, external_game_id, external_release_id)
);

CREATE INDEX idx_external_identity_mapping_content
    ON external_identity_mapping(game_content_id, state);

CREATE INDEX idx_external_identity_mapping_provider
    ON external_identity_mapping(provider_id, state);

CREATE TABLE provider_metadata (
    provider_metadata_id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL CHECK (provider_id IN ('playmatch', 'gametdb', 'steamgriddb')),
    external_game_id TEXT NOT NULL,
    provider_revision INTEGER NOT NULL CHECK (provider_revision > 0),
    region TEXT,
    language TEXT,
    fetched_at TEXT NOT NULL,
    expires_at TEXT,
    title TEXT,
    alternate_titles TEXT NOT NULL DEFAULT '',
    description TEXT,
    release_date TEXT,
    developers TEXT NOT NULL DEFAULT '',
    publishers TEXT NOT NULL DEFAULT '',
    genres TEXT NOT NULL DEFAULT '',
    languages TEXT NOT NULL DEFAULT '',
    adapter_quality INTEGER NOT NULL DEFAULT 0 CHECK (adapter_quality BETWEEN 0 AND 100),
    provenance TEXT NOT NULL,
    UNIQUE(provider_id, external_game_id, provider_revision, region, language)
);

CREATE INDEX idx_provider_metadata_lookup
    ON provider_metadata(provider_id, external_game_id, provider_revision);

CREATE TABLE resolved_metadata (
    game_id TEXT PRIMARY KEY REFERENCES game(game_id),
    display_title TEXT,
    sort_title TEXT,
    description TEXT,
    release_date TEXT,
    developers TEXT NOT NULL DEFAULT '',
    publishers TEXT NOT NULL DEFAULT '',
    genres TEXT NOT NULL DEFAULT '',
    languages TEXT NOT NULL DEFAULT '',
    presentation_region TEXT,
    field_provenance TEXT NOT NULL DEFAULT '',
    resolution_revision INTEGER NOT NULL CHECK (resolution_revision > 0),
    resolved_at TEXT NOT NULL
);

CREATE TABLE artwork_reference (
    reference_id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL CHECK (provider_id IN ('playmatch', 'gametdb', 'steamgriddb')),
    external_game_id TEXT NOT NULL,
    artwork_type TEXT NOT NULL,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('credential_free_url', 'provider_asset_locator')),
    source_value TEXT NOT NULL,
    thumbnail_value TEXT,
    width INTEGER,
    height INTEGER,
    format TEXT,
    mime_type TEXT,
    region TEXT,
    language TEXT,
    tags TEXT NOT NULL DEFAULT '',
    quality INTEGER NOT NULL DEFAULT 0 CHECK (quality BETWEEN 0 AND 100),
    discovered_at TEXT NOT NULL,
    provider_revision INTEGER NOT NULL CHECK (provider_revision > 0),
    UNIQUE(provider_id, external_game_id, artwork_type, source_kind, source_value)
);

CREATE INDEX idx_artwork_reference_lookup
    ON artwork_reference(provider_id, external_game_id, artwork_type);

CREATE TABLE artwork_asset (
    asset_id TEXT PRIMARY KEY,
    width INTEGER NOT NULL CHECK (width > 0),
    height INTEGER NOT NULL CHECK (height > 0),
    mime_type TEXT NOT NULL,
    byte_size INTEGER NOT NULL CHECK (byte_size > 0),
    storage_key TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL
);

CREATE TABLE resolved_artwork (
    game_id TEXT NOT NULL REFERENCES game(game_id),
    artwork_type TEXT NOT NULL,
    reference_id TEXT NOT NULL REFERENCES artwork_reference(reference_id),
    asset_id TEXT REFERENCES artwork_asset(asset_id),
    ordering INTEGER NOT NULL CHECK (ordering >= 0),
    selection_reason TEXT NOT NULL,
    resolution_revision INTEGER NOT NULL CHECK (resolution_revision > 0),
    resolved_at TEXT NOT NULL,
    PRIMARY KEY(game_id, artwork_type, ordering)
);

CREATE INDEX idx_resolved_artwork_asset
    ON resolved_artwork(asset_id);

CREATE TABLE metadata_settings (
    singleton_key INTEGER PRIMARY KEY CHECK (singleton_key = 1),
    preferred_regions TEXT NOT NULL DEFAULT '',
    preferred_languages TEXT NOT NULL DEFAULT '',
    revision INTEGER NOT NULL CHECK (revision > 0),
    updated_at TEXT NOT NULL
);

INSERT INTO metadata_settings
    (singleton_key, preferred_regions, preferred_languages, revision, updated_at)
VALUES (1, '', '', 1, CURRENT_TIMESTAMP);

CREATE TABLE metadata_provider_settings (
    singleton_key INTEGER PRIMARY KEY CHECK (singleton_key = 1),
    enabled_providers TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision > 0),
    updated_at TEXT NOT NULL
);

INSERT INTO metadata_provider_settings
    (singleton_key, enabled_providers, revision, updated_at)
VALUES (1, 'playmatch,gametdb,steamgriddb', 1, CURRENT_TIMESTAMP);
