-- Slice 004: bounded keyset paging for authoritative hierarchy inspection.
--
-- The composite index serves direct-child scopes ordered by the deterministic
-- backend paging key (created_at, source_entry_id). It is purely additive:
-- existing reconciliation queries keep using their own indexes.
CREATE INDEX idx_source_entry_root_parent_created_id
    ON source_entry(library_root_id, parent_source_entry_id, created_at, source_entry_id);
