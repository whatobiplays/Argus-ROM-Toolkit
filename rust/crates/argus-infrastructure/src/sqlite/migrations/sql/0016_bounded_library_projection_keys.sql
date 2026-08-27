-- Normalize projection sort keys introduced by v15 to the byte bounds used
-- by the application cursor contract. SQLite substr() counts characters, so
-- each fallback is at most one quarter of the byte bound, which is safe for
-- every valid UTF-8 code point.

UPDATE game_library_row
SET display_title = CASE
        WHEN length(CAST(display_title AS BLOB)) <= 1024 THEN display_title
        WHEN length(CAST(substr(display_title, 1, 1024) AS BLOB)) <= 1024
            THEN substr(display_title, 1, 1024)
        WHEN length(CAST(substr(display_title, 1, 512) AS BLOB)) <= 1024
            THEN substr(display_title, 1, 512)
        ELSE substr(display_title, 1, 256)
    END,
    release_date = CASE
        WHEN release_date IS NULL
            OR length(CAST(release_date AS BLOB)) <= 64
            THEN release_date
        WHEN length(CAST(substr(release_date, 1, 64) AS BLOB)) <= 64
            THEN substr(release_date, 1, 64)
        WHEN length(CAST(substr(release_date, 1, 32) AS BLOB)) <= 64
            THEN substr(release_date, 1, 32)
        ELSE substr(release_date, 1, 16)
    END
WHERE length(CAST(display_title AS BLOB)) > 1024
   OR length(CAST(release_date AS BLOB)) > 64;
