-- Slice 003: authoritative source-graph reconciliation lookup support.
--
-- Provider-native identity is deliberately NOT unique: hard links and
-- provider ambiguity may legitimately produce duplicate tokens. The partial
-- index serves root-scoped candidate matching while a bounded LIMIT 2 query
-- decides none/unique/ambiguous without loading every duplicate.
CREATE INDEX idx_source_entry_root_native_identity
    ON source_entry(library_root_id, provider_native_identity)
    WHERE provider_native_identity IS NOT NULL;
