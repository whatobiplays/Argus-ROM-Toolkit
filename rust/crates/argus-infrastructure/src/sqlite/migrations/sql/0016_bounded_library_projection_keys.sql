-- Normalize projection sort keys introduced by v15 to the exact byte bounds
-- used by the application cursor contract. SQLite TEXT functions treat an
-- embedded NUL as a terminator, so the migration works from BLOB values and
-- casts the selected UTF-8 prefix back to TEXT only after choosing its byte
-- boundary.

WITH RECURSIVE display_title_source(game_id, value) AS (
    SELECT game_id, CAST(display_title AS BLOB)
    FROM game_library_row
    WHERE length(CAST(display_title AS BLOB)) > 1024
), display_title_candidates(game_id, value, candidate_bytes) AS (
    SELECT game_id, value, 1024
    FROM display_title_source
    UNION ALL
    SELECT game_id, value, candidate_bytes - 1
    FROM display_title_candidates
    WHERE candidate_bytes > 1021
), display_title_boundaries(game_id, value, candidate_bytes) AS (
    SELECT game_id, value, candidate_bytes
    FROM display_title_candidates
    WHERE hex(substr(value, candidate_bytes, 1)) GLOB '[0-7][0-9A-F]'
       OR (candidate_bytes >= 2 AND hex(substr(value, candidate_bytes - 1, 2))
           GLOB '[C-D][2-9A-F][8-B][0-9A-F]')
       OR (candidate_bytes >= 3 AND hex(substr(value, candidate_bytes - 2, 3))
           GLOB '[E][0-9A-F][8-B][0-9A-F][8-B][0-9A-F]')
       OR (candidate_bytes >= 4 AND hex(substr(value, candidate_bytes - 3, 4))
           GLOB '[F][0-4][8-B][0-9A-F][8-B][0-9A-F][8-B][0-9A-F]')
), display_title_normalized(game_id, value) AS (
    SELECT game_id, CAST(substr(value, 1, MAX(candidate_bytes)) AS TEXT)
    FROM display_title_boundaries
    GROUP BY game_id, value
)
UPDATE game_library_row
SET display_title = (
    SELECT value
    FROM display_title_normalized
    WHERE display_title_normalized.game_id = game_library_row.game_id
)
WHERE game_id IN (SELECT game_id FROM display_title_normalized);

WITH RECURSIVE release_date_source(game_id, value) AS (
    SELECT game_id, CAST(release_date AS BLOB)
    FROM game_library_row
    WHERE release_date IS NOT NULL
      AND length(CAST(release_date AS BLOB)) > 64
), release_date_candidates(game_id, value, candidate_bytes) AS (
    SELECT game_id, value, 64
    FROM release_date_source
    UNION ALL
    SELECT game_id, value, candidate_bytes - 1
    FROM release_date_candidates
    WHERE candidate_bytes > 61
), release_date_boundaries(game_id, value, candidate_bytes) AS (
    SELECT game_id, value, candidate_bytes
    FROM release_date_candidates
    WHERE hex(substr(value, candidate_bytes, 1)) GLOB '[0-7][0-9A-F]'
       OR (candidate_bytes >= 2 AND hex(substr(value, candidate_bytes - 1, 2))
           GLOB '[C-D][2-9A-F][8-B][0-9A-F]')
       OR (candidate_bytes >= 3 AND hex(substr(value, candidate_bytes - 2, 3))
           GLOB '[E][0-9A-F][8-B][0-9A-F][8-B][0-9A-F]')
       OR (candidate_bytes >= 4 AND hex(substr(value, candidate_bytes - 3, 4))
           GLOB '[F][0-4][8-B][0-9A-F][8-B][0-9A-F][8-B][0-9A-F]')
), release_date_normalized(game_id, value) AS (
    SELECT game_id, CAST(substr(value, 1, MAX(candidate_bytes)) AS TEXT)
    FROM release_date_boundaries
    GROUP BY game_id, value
)
UPDATE game_library_row
SET release_date = (
    SELECT value
    FROM release_date_normalized
    WHERE release_date_normalized.game_id = game_library_row.game_id
)
WHERE game_id IN (SELECT game_id FROM release_date_normalized);
