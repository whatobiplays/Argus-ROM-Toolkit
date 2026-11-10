CREATE TABLE library_view_state (
    singleton_key INTEGER PRIMARY KEY CHECK (singleton_key = 1),
    generation_id TEXT NOT NULL
        CHECK (length(generation_id) = 32 AND generation_id NOT GLOB '*[^0-9a-f]*'),
    membership_revision INTEGER NOT NULL CHECK (membership_revision >= 1),
    query_contract_version INTEGER NOT NULL CHECK (query_contract_version >= 1)
) STRICT;

INSERT INTO library_view_state (
    singleton_key,
    generation_id,
    membership_revision,
    query_contract_version
)
VALUES (1, lower(hex(randomblob(16))), 1, 1);
