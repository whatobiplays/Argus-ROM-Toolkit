-- Normalize projection sort keys introduced by v15 to the exact byte bounds
-- used by the application cursor contract. SQLite substr() counts characters,
-- so each recursive search finds the longest character prefix whose UTF-8 byte
-- length is still within the corresponding bound.

WITH RECURSIVE display_title_search(game_id, value, lower, upper) AS (
    SELECT game_id, display_title, 0, length(display_title)
    FROM game_library_row
    WHERE length(CAST(display_title AS BLOB)) > 1024
    UNION ALL
    SELECT
        game_id,
        value,
        CASE
            WHEN length(CAST(substr(value, 1, (lower + upper) / 2) AS BLOB)) <= 1024
                THEN (lower + upper) / 2
            ELSE lower
        END,
        CASE
            WHEN length(CAST(substr(value, 1, (lower + upper) / 2) AS BLOB)) <= 1024
                THEN upper
            ELSE (lower + upper) / 2
        END
    FROM display_title_search
    WHERE upper - lower > 1
), display_title_normalized(game_id, value) AS (
    SELECT game_id, substr(value, 1, lower)
    FROM display_title_search
    WHERE upper - lower = 1
)
UPDATE game_library_row
SET display_title = (
    SELECT value
    FROM display_title_normalized
    WHERE display_title_normalized.game_id = game_library_row.game_id
)
WHERE game_id IN (SELECT game_id FROM display_title_normalized);

WITH RECURSIVE release_date_search(game_id, value, lower, upper) AS (
    SELECT game_id, release_date, 0, length(release_date)
    FROM game_library_row
    WHERE release_date IS NOT NULL
      AND length(CAST(release_date AS BLOB)) > 64
    UNION ALL
    SELECT
        game_id,
        value,
        CASE
            WHEN length(CAST(substr(value, 1, (lower + upper) / 2) AS BLOB)) <= 64
                THEN (lower + upper) / 2
            ELSE lower
        END,
        CASE
            WHEN length(CAST(substr(value, 1, (lower + upper) / 2) AS BLOB)) <= 64
                THEN upper
            ELSE (lower + upper) / 2
        END
    FROM release_date_search
    WHERE upper - lower > 1
), release_date_normalized(game_id, value) AS (
    SELECT game_id, substr(value, 1, lower)
    FROM release_date_search
    WHERE upper - lower = 1
)
UPDATE game_library_row
SET release_date = (
    SELECT value
    FROM release_date_normalized
    WHERE release_date_normalized.game_id = game_library_row.game_id
)
WHERE game_id IN (SELECT game_id FROM release_date_normalized);
