-- Activate the bounded logical-library browsing projection. Existing logical
-- identities and enrichment rows remain authoritative; these columns are
-- application-owned presentation/search facts maintained incrementally by the
-- logical repository.

ALTER TABLE game_library_row RENAME TO game_library_row_legacy;

DROP INDEX IF EXISTS idx_game_library_row_default_order;

CREATE TABLE game_library_row (
    game_id TEXT PRIMARY KEY REFERENCES game(game_id),
    display_title TEXT NOT NULL,
    display_title_provenance TEXT NOT NULL CHECK (
        display_title_provenance IN ('local_fallback', 'resolved_metadata')
    ),
    platform_id TEXT NOT NULL CHECK (platform_id IN (
        'nintendo.nes', 'nintendo.fds', 'nintendo.snes',
        'nintendo.gb', 'nintendo.gbc', 'nintendo.gba',
        'nintendo.n64', 'nintendo.nds', 'nintendo.3ds',
        'nintendo.gamecube', 'nintendo.wii',
        'sega.sms', 'sega.gamegear', 'sega.genesis', 'sega.32x',
        'sega.sega-cd', 'sega.saturn', 'sega.dreamcast',
        'sony.playstation', 'sony.playstation2', 'sony.psp'
    )),
    presentation_region TEXT,
    selected_cover_asset_id TEXT REFERENCES artwork_asset(asset_id),
    release_date TEXT,
    search_text TEXT NOT NULL DEFAULT '',
    hydration_state TEXT NOT NULL CHECK (
        hydration_state IN ('hydrated', 'partially_hydrated', 'unmatched', 'refreshing')
    ),
    availability_state TEXT NOT NULL CHECK (
        availability_state IN ('available', 'partially_unavailable', 'unavailable', 'inactive_orphan')
    ),
    content_count INTEGER NOT NULL CHECK (content_count >= 0),
    source_count INTEGER NOT NULL CHECK (source_count >= 0),
    updated_at TEXT NOT NULL
);

INSERT INTO game_library_row (
    game_id, display_title, display_title_provenance, platform_id,
    presentation_region, selected_cover_asset_id, release_date, search_text,
    hydration_state, availability_state, content_count, source_count, updated_at
)
SELECT
    legacy.game_id,
    COALESCE(NULLIF(TRIM(metadata.display_title), ''), game.fallback_title),
    CASE
        WHEN NULLIF(TRIM(metadata.display_title), '') IS NULL
            THEN 'local_fallback'
        ELSE 'resolved_metadata'
    END,
    legacy.platform_id,
    metadata.presentation_region,
    (
        SELECT artwork.asset_id
        FROM resolved_artwork artwork
        WHERE artwork.game_id = legacy.game_id
          AND artwork.artwork_type = 'cover_front'
          AND artwork.asset_id IS NOT NULL
        ORDER BY artwork.ordering ASC, artwork.reference_id ASC
        LIMIT 1
    ),
    metadata.release_date,
    lower(trim(
        COALESCE(NULLIF(TRIM(metadata.display_title), ''), '') || ' ' ||
        COALESCE(metadata.sort_title, '') || ' ' ||
        COALESCE(game.fallback_title, '') || ' ' ||
        COALESCE((
            SELECT group_concat(
                COALESCE(provider_metadata.title, '') || ' ' ||
                COALESCE(provider_metadata.alternate_titles, ''),
                ' '
            )
            FROM game_membership membership
            JOIN external_identity_mapping mapping
              ON mapping.game_content_id = membership.game_content_id
             AND mapping.state = 'current'
            JOIN provider_metadata
              ON provider_metadata.provider_id = mapping.provider_id
             AND provider_metadata.external_game_id = mapping.external_game_id
             AND provider_metadata.provider_revision = mapping.provider_revision
            WHERE membership.game_id = legacy.game_id
              AND membership.is_current = 1
        ), '')
    )),
    legacy.hydration_state,
    legacy.availability_state,
    legacy.content_count,
    legacy.source_count,
    legacy.updated_at
FROM game_library_row_legacy AS legacy
LEFT JOIN game ON game.game_id = legacy.game_id
LEFT JOIN resolved_metadata metadata ON metadata.game_id = legacy.game_id;

DROP TABLE game_library_row_legacy;

CREATE INDEX idx_game_library_row_default_order
    ON game_library_row(display_title COLLATE NOCASE ASC, game_id ASC);

CREATE INDEX idx_game_library_row_search
    ON game_library_row(search_text COLLATE NOCASE);

CREATE INDEX idx_game_library_row_platform
    ON game_library_row(platform_id, display_title COLLATE NOCASE, game_id);

CREATE INDEX idx_game_library_row_release_date
    ON game_library_row(
        (CASE WHEN release_date IS NULL THEN 1 ELSE 0 END) ASC,
        release_date ASC,
        display_title COLLATE NOCASE ASC,
        platform_id ASC,
        game_id ASC
    );

CREATE INDEX idx_game_library_row_release_date_desc
    ON game_library_row(
        (CASE WHEN release_date IS NULL THEN 1 ELSE 0 END) ASC,
        release_date DESC,
        display_title COLLATE NOCASE DESC,
        platform_id DESC,
        game_id DESC
    );

CREATE INDEX idx_game_library_row_updated_at
    ON game_library_row(
        (COALESCE(
            CAST(strftime('%s', updated_at) AS INTEGER) * 1000,
            CAST(updated_at AS INTEGER) * 1000,
            0
        )) ASC,
        display_title COLLATE NOCASE ASC,
        platform_id ASC,
        game_id ASC
    );

CREATE INDEX idx_game_library_row_updated_at_desc
    ON game_library_row(
        (COALESCE(
            CAST(strftime('%s', updated_at) AS INTEGER) * 1000,
            CAST(updated_at AS INTEGER) * 1000,
            0
        )) DESC,
        display_title COLLATE NOCASE DESC,
        platform_id DESC,
        game_id DESC
    );

CREATE INDEX idx_game_content_source_scope
    ON game_content_source(source_entry_id, is_current, game_content_id);
