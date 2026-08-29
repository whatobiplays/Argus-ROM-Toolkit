-- Preserve derived source-version evidence separately from provider evidence.
--
-- Historical proof rows are only backfilled when their recorded observation is
-- provably the same source-entry version. A currently-present derived source
-- is not sufficient evidence for an older proof, so rows with missing sources,
-- provider sources, or different scan observations intentionally remain NULL.

ALTER TABLE content_identity
    ADD COLUMN proving_derived_fingerprint TEXT;

ALTER TABLE content_identity_provenance
    ADD COLUMN derived_fingerprint TEXT;

ALTER TABLE game_content_source
    ADD COLUMN derived_fingerprint TEXT;

ALTER TABLE grouping_evidence
    ADD COLUMN derived_fingerprint TEXT;

ALTER TABLE grouping_evidence_member
    ADD COLUMN member_derived_fingerprint TEXT;

UPDATE content_identity
SET proving_derived_fingerprint = (
    SELECT CASE
        WHEN source_entry.last_observed_scan_id = content_identity.proving_scan_run_id
        THEN COALESCE(
            content_identity.proving_source_fingerprint,
            source_entry.derived_fingerprint
        )
    END
    FROM source_entry
    WHERE source_entry.source_entry_id = content_identity.proving_source_entry_id
      AND source_entry.coordinate_kind = 'derived'
),
proving_source_fingerprint = CASE
    WHEN EXISTS (
        SELECT 1
        FROM source_entry
        WHERE source_entry.source_entry_id = content_identity.proving_source_entry_id
          AND source_entry.coordinate_kind = 'derived'
    ) THEN NULL
    ELSE proving_source_fingerprint
END
WHERE proving_source_entry_id IS NOT NULL;

UPDATE content_identity_provenance
SET derived_fingerprint = (
    SELECT CASE
        WHEN source_entry.last_observed_scan_id = content_identity_provenance.last_observed_scan_id
        THEN COALESCE(
            content_identity_provenance.source_fingerprint,
            source_entry.derived_fingerprint
        )
    END
    FROM source_entry
    WHERE source_entry.source_entry_id = content_identity_provenance.source_entry_id
      AND source_entry.coordinate_kind = 'derived'
),
source_fingerprint = CASE
    WHEN EXISTS (
        SELECT 1
        FROM source_entry
        WHERE source_entry.source_entry_id = content_identity_provenance.source_entry_id
          AND source_entry.coordinate_kind = 'derived'
    ) THEN NULL
    ELSE source_fingerprint
END
WHERE source_entry_id IS NOT NULL;

UPDATE game_content_source
SET derived_fingerprint = (
    SELECT CASE
        WHEN source_entry.last_observed_scan_id = game_content_source.last_observed_scan_id
        THEN COALESCE(
            game_content_source.source_fingerprint,
            source_entry.derived_fingerprint
        )
    END
    FROM source_entry
    WHERE source_entry.source_entry_id = game_content_source.source_entry_id
      AND source_entry.coordinate_kind = 'derived'
),
source_fingerprint = CASE
    WHEN EXISTS (
        SELECT 1
        FROM source_entry
        WHERE source_entry.source_entry_id = game_content_source.source_entry_id
          AND source_entry.coordinate_kind = 'derived'
    ) THEN NULL
    ELSE source_fingerprint
END
WHERE source_entry_id IS NOT NULL;

UPDATE grouping_evidence
SET derived_fingerprint = (
    SELECT CASE
        WHEN source_entry.last_observed_scan_id = grouping_evidence.last_observed_scan_id
        THEN COALESCE(
            grouping_evidence.source_fingerprint,
            source_entry.derived_fingerprint
        )
    END
    FROM source_entry
    WHERE source_entry.source_entry_id = grouping_evidence.playlist_source_entry_id
      AND source_entry.coordinate_kind = 'derived'
),
source_fingerprint = CASE
    WHEN EXISTS (
        SELECT 1
        FROM source_entry
        WHERE source_entry.source_entry_id = grouping_evidence.playlist_source_entry_id
          AND source_entry.coordinate_kind = 'derived'
    ) THEN NULL
    ELSE source_fingerprint
END
WHERE playlist_source_entry_id IS NOT NULL;

UPDATE grouping_evidence_member
SET member_derived_fingerprint = (
    SELECT CASE
        WHEN source_entry.last_observed_scan_id = grouping_evidence_member.member_last_observed_scan_id
        THEN COALESCE(
            grouping_evidence_member.member_source_fingerprint,
            source_entry.derived_fingerprint
        )
    END
    FROM source_entry
    WHERE source_entry.source_entry_id = grouping_evidence_member.member_source_entry_id
      AND source_entry.coordinate_kind = 'derived'
),
member_source_fingerprint = CASE
    WHEN EXISTS (
        SELECT 1
        FROM source_entry
        WHERE source_entry.source_entry_id = grouping_evidence_member.member_source_entry_id
          AND source_entry.coordinate_kind = 'derived'
    ) THEN NULL
    ELSE member_source_fingerprint
END
WHERE member_source_entry_id IS NOT NULL;
