CREATE TABLE library_source (
    library_source_id TEXT PRIMARY KEY,
    source_provider_type TEXT NOT NULL CHECK (source_provider_type IN ('local_filesystem')),
    display_name TEXT NOT NULL,
    provider_config TEXT NOT NULL,
    config_revision INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX uq_library_source_local_filesystem
    ON library_source(source_provider_type)
    WHERE source_provider_type = 'local_filesystem';

CREATE TABLE library_root (
    library_root_id TEXT PRIMARY KEY,
    library_source_id TEXT NOT NULL REFERENCES library_source(library_source_id),
    root_locator TEXT NOT NULL,
    display_name TEXT NOT NULL,
    safe_location_presentation TEXT NOT NULL,
    availability_status TEXT NOT NULL CHECK (availability_status IN ('available', 'unavailable', 'unknown')),
    config_revision INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_library_root_source ON library_root(library_source_id);
CREATE INDEX idx_library_root_created ON library_root(created_at, library_root_id);
