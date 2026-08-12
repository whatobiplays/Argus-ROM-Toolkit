CREATE TABLE appearance_settings (
    singleton_key INTEGER PRIMARY KEY CHECK (singleton_key = 1),
    theme_mode TEXT NOT NULL CHECK (theme_mode IN ('system', 'light', 'dark')),
    schema_revision INTEGER NOT NULL,
    updated_at TEXT NOT NULL
);

INSERT INTO appearance_settings (singleton_key, theme_mode, schema_revision, updated_at)
VALUES (1, 'system', 1, CURRENT_TIMESTAMP);
