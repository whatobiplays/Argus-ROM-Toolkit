-- Expand the logical catalog for native optical content and normalize exact
-- identity provenance. Existing row identities and timestamps are copied
-- verbatim; only constrained vocabularies and proof storage are extended.

ALTER TABLE content_identity RENAME TO content_identity_legacy;
ALTER TABLE game_content_source RENAME TO game_content_source_legacy;
ALTER TABLE game_membership RENAME TO game_membership_legacy;
ALTER TABLE game_redirect RENAME TO game_redirect_legacy;
ALTER TABLE game_library_row RENAME TO game_library_row_legacy;
ALTER TABLE external_identity_mapping RENAME TO external_identity_mapping_legacy;
ALTER TABLE resolved_metadata RENAME TO resolved_metadata_legacy;
ALTER TABLE resolved_artwork RENAME TO resolved_artwork_legacy;
ALTER TABLE game_content RENAME TO game_content_legacy;
ALTER TABLE game RENAME TO game_legacy;

DROP INDEX IF EXISTS uq_content_identity_current_content;
DROP INDEX IF EXISTS uq_content_identity_current_value;
DROP INDEX IF EXISTS idx_content_identity_proving_source;
DROP INDEX IF EXISTS idx_game_content_source_entry;
DROP INDEX IF EXISTS idx_game_content_source_content;
DROP INDEX IF EXISTS uq_game_membership_current_content;
DROP INDEX IF EXISTS uq_game_membership_current_primary;
DROP INDEX IF EXISTS idx_game_library_row_default_order;
DROP INDEX IF EXISTS idx_external_identity_mapping_content;
DROP INDEX IF EXISTS idx_external_identity_mapping_provider;
DROP INDEX IF EXISTS idx_resolved_artwork_asset;

CREATE TABLE game_content (
    game_content_id TEXT PRIMARY KEY,
    platform_id TEXT NOT NULL CHECK (platform_id IN (
        'nintendo.nes', 'nintendo.fds', 'nintendo.snes',
        'nintendo.gb', 'nintendo.gbc', 'nintendo.gba',
        'nintendo.n64', 'nintendo.nds', 'nintendo.3ds',
        'nintendo.gamecube', 'nintendo.wii',
        'sega.sms', 'sega.gamegear', 'sega.genesis', 'sega.32x',
        'sega.sega-cd', 'sega.saturn', 'sega.dreamcast',
        'sony.playstation', 'sony.playstation2', 'sony.psp'
    )),
    content_type TEXT NOT NULL CHECK (content_type IN (
        'CartridgeImage', 'MagneticDiskImage', 'OpticalDiscCd',
        'OpticalDiscGd', 'OpticalDiscDvd', 'OpticalDiscGameCube',
        'OpticalDiscWii', 'OpticalDiscUmd'
    )),
    presence_state TEXT NOT NULL CHECK (presence_state IN ('available', 'partially_unavailable', 'unavailable', 'orphaned')),
    identification_state TEXT NOT NULL CHECK (identification_state IN ('identified', 'needs_reidentification', 'unidentified')),
    grouping_revision INTEGER NOT NULL CHECK (grouping_revision > 0),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK (
        (platform_id = 'nintendo.fds' AND content_type = 'MagneticDiskImage')
        OR (platform_id IN ('nintendo.gamecube') AND content_type = 'OpticalDiscGameCube')
        OR (platform_id = 'nintendo.wii' AND content_type = 'OpticalDiscWii')
        OR (platform_id IN ('sega.sega-cd', 'sega.saturn', 'sony.playstation')
            AND content_type = 'OpticalDiscCd')
        OR (platform_id = 'sega.dreamcast' AND content_type = 'OpticalDiscGd')
        OR (platform_id = 'sony.playstation2'
            AND content_type IN ('OpticalDiscCd', 'OpticalDiscDvd'))
        OR (platform_id = 'sony.psp' AND content_type = 'OpticalDiscUmd')
        OR (platform_id NOT IN (
            'nintendo.fds', 'nintendo.gamecube', 'nintendo.wii',
            'sega.sega-cd', 'sega.saturn', 'sega.dreamcast',
            'sony.playstation', 'sony.playstation2', 'sony.psp'
        ) AND content_type = 'CartridgeImage')
    )
);

CREATE TABLE game (
    game_id TEXT PRIMARY KEY,
    platform_id TEXT NOT NULL CHECK (platform_id IN (
        'nintendo.nes', 'nintendo.fds', 'nintendo.snes',
        'nintendo.gb', 'nintendo.gbc', 'nintendo.gba',
        'nintendo.n64', 'nintendo.nds', 'nintendo.3ds',
        'nintendo.gamecube', 'nintendo.wii',
        'sega.sms', 'sega.gamegear', 'sega.genesis', 'sega.32x',
        'sega.sega-cd', 'sega.saturn', 'sega.dreamcast',
        'sony.playstation', 'sony.playstation2', 'sony.psp'
    )),
    lifecycle_state TEXT NOT NULL CHECK (lifecycle_state IN ('active', 'inactive_orphan', 'redirected')),
    grouping_revision INTEGER NOT NULL CHECK (grouping_revision > 0),
    fallback_title TEXT NOT NULL,
    fallback_title_provenance TEXT NOT NULL CHECK (fallback_title_provenance = 'local_fallback'),
    hydration_state TEXT NOT NULL CHECK (hydration_state IN ('hydrated', 'partially_hydrated', 'unmatched', 'refreshing')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

INSERT INTO game_content (
    game_content_id, platform_id, content_type, presence_state,
    identification_state, grouping_revision, created_at, updated_at
)
SELECT game_content_id, platform_id, content_type, presence_state,
       identification_state, grouping_revision, created_at, updated_at
FROM game_content_legacy;

INSERT INTO game (
    game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
    fallback_title_provenance, hydration_state, created_at, updated_at
)
SELECT game_id, platform_id, lifecycle_state, grouping_revision, fallback_title,
       fallback_title_provenance, hydration_state, created_at, updated_at
FROM game_legacy;

CREATE TABLE content_identity (
    content_identity_id TEXT PRIMARY KEY,
    game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    scheme_id TEXT NOT NULL,
    identity_revision INTEGER NOT NULL CHECK (identity_revision > 0),
    identity_value TEXT NOT NULL,
    is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
    -- Retained scalar columns keep the pre-normalization SQL compatibility
    -- surface. The normalized member table below is authoritative for new
    -- multi-source proofs and is populated for every legacy proving row.
    proving_source_entry_id TEXT,
    proving_association_key TEXT,
    proving_source_fingerprint TEXT,
    proving_scan_run_id TEXT REFERENCES scan_run(scan_run_id),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

INSERT INTO content_identity (
    content_identity_id, game_content_id, scheme_id, identity_revision,
    identity_value, is_current, proving_source_entry_id, proving_association_key,
    proving_source_fingerprint, proving_scan_run_id, created_at, updated_at
)
SELECT content_identity_id, game_content_id, scheme_id, identity_revision,
       identity_value, is_current, proving_source_entry_id, proving_association_key,
       proving_source_fingerprint, proving_scan_run_id, created_at, updated_at
FROM content_identity_legacy;

CREATE UNIQUE INDEX uq_content_identity_current_content
    ON content_identity(game_content_id)
    WHERE is_current = 1;

CREATE UNIQUE INDEX uq_content_identity_current_value
    ON content_identity(scheme_id, identity_value)
    WHERE is_current = 1;

CREATE INDEX idx_content_identity_proving_source
    ON content_identity(proving_source_entry_id);

CREATE TABLE content_identity_provenance (
    provenance_member_id TEXT PRIMARY KEY,
    content_identity_id TEXT NOT NULL REFERENCES content_identity(content_identity_id),
    role TEXT NOT NULL CHECK (role IN ('primary', 'descriptor', 'required_data', 'supporting')),
    association_key TEXT,
    source_entry_id TEXT NOT NULL,
    source_fingerprint TEXT,
    last_observed_scan_id TEXT,
    identity_is_current INTEGER NOT NULL CHECK (identity_is_current IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(content_identity_id, role, source_entry_id, association_key)
);

INSERT INTO content_identity_provenance (
    provenance_member_id, content_identity_id, role, association_key,
    source_entry_id, source_fingerprint, last_observed_scan_id,
    identity_is_current, created_at, updated_at
)
SELECT lower(hex(randomblob(16))), content_identity_id, 'primary',
       proving_association_key, proving_source_entry_id, proving_source_fingerprint,
       proving_scan_run_id, is_current, created_at, updated_at
FROM content_identity
WHERE proving_source_entry_id IS NOT NULL;

CREATE INDEX idx_content_identity_provenance_source
    ON content_identity_provenance(source_entry_id, identity_is_current);

CREATE INDEX idx_content_identity_provenance_identity
    ON content_identity_provenance(content_identity_id, identity_is_current);

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

INSERT INTO game_content_source (
    game_content_source_id, game_content_id, source_entry_id, association_key,
    source_fingerprint, last_observed_scan_id, is_current, created_at, updated_at
)
SELECT game_content_source_id, game_content_id, source_entry_id, association_key,
       source_fingerprint, last_observed_scan_id, is_current, created_at, updated_at
FROM game_content_source_legacy;

CREATE INDEX idx_game_content_source_entry
    ON game_content_source(source_entry_id, is_current);

CREATE INDEX idx_game_content_source_content
    ON game_content_source(game_content_id, is_current);

CREATE TABLE game_membership (
    game_membership_id TEXT PRIMARY KEY,
    game_id TEXT NOT NULL REFERENCES game(game_id),
    game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    relationship TEXT NOT NULL CHECK (relationship IN (
        'primary_content', 'regional_variant', 'language_variant',
        'revision_variant', 'disc', 'equivalent_release_representation'
    )),
    grouping_basis TEXT NOT NULL CHECK (grouping_basis IN (
        'exact_content_identity', 'provisional', 'explicit_relationship_evidence'
    )),
    grouping_revision INTEGER NOT NULL CHECK (grouping_revision > 0),
    is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(game_id, game_content_id, relationship)
);

INSERT INTO game_membership (
    game_membership_id, game_id, game_content_id, relationship, grouping_basis,
    grouping_revision, is_current, created_at, updated_at
)
SELECT game_membership_id, game_id, game_content_id,
       CASE relationship
           WHEN 'primary' THEN 'primary_content'
           WHEN 'secondary' THEN 'equivalent_release_representation'
           ELSE relationship
       END,
       grouping_basis, grouping_revision, is_current, created_at, updated_at
FROM game_membership_legacy;

CREATE UNIQUE INDEX uq_game_membership_current_content
    ON game_membership(game_content_id)
    WHERE is_current = 1;

CREATE UNIQUE INDEX uq_game_membership_current_primary
    ON game_membership(game_id)
    WHERE is_current = 1 AND relationship = 'primary_content';

CREATE TABLE game_redirect (
    game_id TEXT PRIMARY KEY REFERENCES game(game_id),
    canonical_game_id TEXT NOT NULL REFERENCES game(game_id),
    created_at TEXT NOT NULL,
    CHECK (game_id <> canonical_game_id)
);

INSERT INTO game_redirect (game_id, canonical_game_id, created_at)
SELECT game_id, canonical_game_id, created_at FROM game_redirect_legacy;

CREATE TABLE game_library_row (
    game_id TEXT PRIMARY KEY REFERENCES game(game_id),
    display_title TEXT NOT NULL,
    display_title_provenance TEXT NOT NULL CHECK (display_title_provenance = 'local_fallback'),
    platform_id TEXT NOT NULL CHECK (platform_id IN (
        'nintendo.nes', 'nintendo.fds', 'nintendo.snes',
        'nintendo.gb', 'nintendo.gbc', 'nintendo.gba',
        'nintendo.n64', 'nintendo.nds', 'nintendo.3ds',
        'nintendo.gamecube', 'nintendo.wii',
        'sega.sms', 'sega.gamegear', 'sega.genesis', 'sega.32x',
        'sega.sega-cd', 'sega.saturn', 'sega.dreamcast',
        'sony.playstation', 'sony.playstation2', 'sony.psp'
    )),
    hydration_state TEXT NOT NULL CHECK (hydration_state IN ('hydrated', 'partially_hydrated', 'unmatched', 'refreshing')),
    availability_state TEXT NOT NULL CHECK (availability_state IN ('available', 'partially_unavailable', 'unavailable', 'inactive_orphan')),
    content_count INTEGER NOT NULL CHECK (content_count >= 0),
    source_count INTEGER NOT NULL CHECK (source_count >= 0),
    updated_at TEXT NOT NULL
);

INSERT INTO game_library_row (
    game_id, display_title, display_title_provenance, platform_id, hydration_state,
    availability_state, content_count, source_count, updated_at
)
SELECT game_id, display_title, display_title_provenance, platform_id, hydration_state,
       availability_state, content_count, source_count, updated_at
FROM game_library_row_legacy;

CREATE INDEX idx_game_library_row_default_order
    ON game_library_row(display_title COLLATE NOCASE ASC, game_id ASC);

CREATE TABLE external_identity_mapping (
    mapping_id TEXT PRIMARY KEY,
    game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    provider_id TEXT NOT NULL CHECK (provider_id IN ('playmatch', 'gametdb', 'steamgriddb')),
    external_game_id TEXT NOT NULL,
    external_release_id TEXT,
    provider_platform_id TEXT NOT NULL,
    provider_confidence REAL,
    match_basis TEXT NOT NULL CHECK (match_basis IN (
        'playmatch_exact_content', 'gametdb_exact_native_identifier',
        'existing_exact_mapping', 'rejected_by_policy'
    )),
    provider_revision INTEGER NOT NULL CHECK (provider_revision > 0),
    state TEXT NOT NULL CHECK (state IN ('current', 'stale', 'rejected_by_policy')),
    matched_at TEXT NOT NULL,
    last_validated_at TEXT NOT NULL,
    UNIQUE(game_content_id, provider_id, external_game_id, external_release_id)
);

INSERT INTO external_identity_mapping
SELECT mapping_id, game_content_id, provider_id, external_game_id, external_release_id,
       provider_platform_id, provider_confidence, match_basis, provider_revision,
       state, matched_at, last_validated_at
FROM external_identity_mapping_legacy;

CREATE INDEX idx_external_identity_mapping_content
    ON external_identity_mapping(game_content_id, state);
CREATE INDEX idx_external_identity_mapping_provider
    ON external_identity_mapping(provider_id, state);

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

INSERT INTO resolved_metadata
SELECT game_id, display_title, sort_title, description, release_date, developers,
       publishers, genres, languages, presentation_region, field_provenance,
       resolution_revision, resolved_at
FROM resolved_metadata_legacy;

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

INSERT INTO resolved_artwork
SELECT game_id, artwork_type, reference_id, asset_id, ordering, selection_reason,
       resolution_revision, resolved_at
FROM resolved_artwork_legacy;

CREATE INDEX idx_resolved_artwork_asset ON resolved_artwork(asset_id);

-- M3U is relationship evidence only. It has no content identity and no
-- membership ordinal; ordered member facts are normalized here instead.
CREATE TABLE grouping_evidence (
    grouping_evidence_id TEXT PRIMARY KEY,
    evidence_kind TEXT NOT NULL CHECK (evidence_kind = 'm3u'),
    playlist_source_entry_id TEXT NOT NULL REFERENCES source_entry(source_entry_id),
    source_fingerprint TEXT,
    last_observed_scan_id TEXT REFERENCES scan_run(scan_run_id),
    is_current INTEGER NOT NULL CHECK (is_current IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_grouping_evidence_playlist
    ON grouping_evidence(playlist_source_entry_id, is_current);

CREATE TABLE grouping_evidence_member (
    grouping_evidence_id TEXT NOT NULL REFERENCES grouping_evidence(grouping_evidence_id),
    member_game_content_id TEXT NOT NULL REFERENCES game_content(game_content_id),
    member_source_entry_id TEXT NOT NULL REFERENCES source_entry(source_entry_id),
    member_source_fingerprint TEXT,
    member_last_observed_scan_id TEXT REFERENCES scan_run(scan_run_id),
    ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
    PRIMARY KEY(grouping_evidence_id, ordinal),
    UNIQUE(grouping_evidence_id, member_game_content_id)
);

CREATE INDEX idx_grouping_evidence_member_content
    ON grouping_evidence_member(member_game_content_id);

DROP TABLE content_identity_legacy;
DROP TABLE game_content_source_legacy;
DROP TABLE game_membership_legacy;
DROP TABLE game_redirect_legacy;
DROP TABLE game_library_row_legacy;
DROP TABLE external_identity_mapping_legacy;
DROP TABLE resolved_metadata_legacy;
DROP TABLE resolved_artwork_legacy;
DROP TABLE game_content_legacy;
DROP TABLE game_legacy;
