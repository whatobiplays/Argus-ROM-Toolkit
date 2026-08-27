-- Give source entries one mutually exclusive coordinate family.
--
-- SQLite cannot add a table-level CHECK that normalizes the existing scalar
-- columns in place, so the table is rebuilt while preserving every durable
-- source_entry_id. SQLite rewrites foreign-key declarations when a referenced
-- table is renamed, so the dependent tables are rebuilt in the same migration
-- to make their final declarations point at the replacement source_entry
-- table.
PRAGMA legacy_alter_table = ON;

DROP INDEX IF EXISTS idx_source_entry_root_parent;
DROP INDEX IF EXISTS idx_source_entry_root_parent_created_id;
DROP INDEX IF EXISTS idx_source_entry_root_native_identity;
DROP INDEX IF EXISTS idx_game_content_source_entry;
DROP INDEX IF EXISTS idx_game_content_source_content;
DROP INDEX IF EXISTS idx_grouping_evidence_playlist;
DROP INDEX IF EXISTS idx_grouping_evidence_member_content;

ALTER TABLE game_content_source RENAME TO game_content_source_legacy;
ALTER TABLE grouping_evidence_member RENAME TO grouping_evidence_member_legacy;
ALTER TABLE grouping_evidence RENAME TO grouping_evidence_legacy;
ALTER TABLE source_entry RENAME TO source_entry_legacy;

CREATE TABLE source_entry (
    source_entry_id TEXT PRIMARY KEY,
    library_root_id TEXT NOT NULL,
    parent_source_entry_id TEXT,
    coordinate_kind TEXT NOT NULL CHECK (coordinate_kind IN ('provider', 'derived')),
    relative_locator TEXT,
    locator_key TEXT,
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
    derived_locator TEXT,
    derived_entry_key TEXT,
    derived_fingerprint TEXT,
    derivation_transformation_id TEXT,
    derivation_revision INTEGER,
    last_observed_scan_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (
        (
            coordinate_kind = 'provider'
            AND relative_locator IS NOT NULL
            AND locator_key IS NOT NULL
            AND derived_locator IS NULL
            AND derived_entry_key IS NULL
            AND derived_fingerprint IS NULL
            AND derivation_transformation_id IS NULL
            AND derivation_revision IS NULL
        ) OR (
            coordinate_kind = 'derived'
            AND relative_locator IS NULL
            AND locator_key IS NULL
            AND provider_native_identity IS NULL
            AND source_fingerprint IS NULL
            AND derived_locator IS NOT NULL
            AND derived_entry_key IS NOT NULL
            AND derived_fingerprint IS NOT NULL
            AND derivation_transformation_id IS NOT NULL
            AND derivation_revision > 0
        )
    )
);

INSERT INTO source_entry (
    source_entry_id, library_root_id, parent_source_entry_id, coordinate_kind,
    relative_locator, locator_key, display_name, display_location, kind,
    classification, provider_native_identity, source_fingerprint,
    last_observed_scan_id, created_at, updated_at
)
SELECT source_entry_id, library_root_id, parent_source_entry_id, 'provider',
       relative_locator, locator_key, display_name, display_location, kind,
       classification, provider_native_identity, source_fingerprint,
       last_observed_scan_id, created_at, updated_at
FROM source_entry_legacy;

CREATE UNIQUE INDEX uq_source_entry_provider_locator
    ON source_entry(library_root_id, locator_key)
    WHERE coordinate_kind = 'provider';

CREATE UNIQUE INDEX uq_source_entry_derived_key
    ON source_entry(
        parent_source_entry_id,
        derivation_transformation_id,
        derivation_revision,
        derived_entry_key
    )
    WHERE coordinate_kind = 'derived';

CREATE INDEX idx_source_entry_root_parent
    ON source_entry(library_root_id, parent_source_entry_id);

CREATE INDEX idx_source_entry_root_parent_created_id
    ON source_entry(library_root_id, parent_source_entry_id, created_at, source_entry_id);

CREATE INDEX idx_source_entry_root_native_identity
    ON source_entry(library_root_id, provider_native_identity)
    WHERE coordinate_kind = 'provider' AND provider_native_identity IS NOT NULL;

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

INSERT INTO game_content_source
SELECT game_content_source_id, game_content_id, source_entry_id,
       association_key, source_fingerprint, last_observed_scan_id,
       is_current, created_at, updated_at
FROM game_content_source_legacy;

CREATE INDEX idx_game_content_source_entry
    ON game_content_source(source_entry_id, is_current);

CREATE INDEX idx_game_content_source_content
    ON game_content_source(game_content_id, is_current);

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

INSERT INTO grouping_evidence
SELECT grouping_evidence_id, evidence_kind, playlist_source_entry_id,
       source_fingerprint, last_observed_scan_id, is_current, created_at,
       updated_at
FROM grouping_evidence_legacy;

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

INSERT INTO grouping_evidence_member
SELECT grouping_evidence_id, member_game_content_id, member_source_entry_id,
       member_source_fingerprint, member_last_observed_scan_id, ordinal
FROM grouping_evidence_member_legacy;

CREATE INDEX idx_grouping_evidence_member_content
    ON grouping_evidence_member(member_game_content_id);

DROP TABLE game_content_source_legacy;
DROP TABLE grouping_evidence_member_legacy;
DROP TABLE grouping_evidence_legacy;
DROP TABLE source_entry_legacy;

PRAGMA legacy_alter_table = OFF;
