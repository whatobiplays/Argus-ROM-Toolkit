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
    SELECT source_entry.derived_fingerprint
    FROM source_entry
    WHERE source_entry.source_entry_id = content_identity.proving_source_entry_id
      AND source_entry.coordinate_kind = 'derived'
      AND source_entry.source_fingerprint IS NULL
      AND source_entry.derived_fingerprint IS NOT NULL
      AND source_entry.last_observed_scan_id = content_identity.proving_scan_run_id
)
WHERE proving_derived_fingerprint IS NULL
  AND proving_source_entry_id IS NOT NULL
  AND proving_scan_run_id IS NOT NULL
  AND proving_source_fingerprint IS NULL
  AND EXISTS (
      SELECT 1
      FROM source_entry
      WHERE source_entry.source_entry_id = content_identity.proving_source_entry_id
        AND source_entry.coordinate_kind = 'derived'
        AND source_entry.source_fingerprint IS NULL
        AND source_entry.derived_fingerprint IS NOT NULL
        AND source_entry.last_observed_scan_id = content_identity.proving_scan_run_id
  );

UPDATE content_identity_provenance
SET derived_fingerprint = (
    SELECT source_entry.derived_fingerprint
    FROM source_entry
    WHERE source_entry.source_entry_id = content_identity_provenance.source_entry_id
      AND source_entry.coordinate_kind = 'derived'
      AND source_entry.source_fingerprint IS NULL
      AND source_entry.derived_fingerprint IS NOT NULL
      AND source_entry.last_observed_scan_id = content_identity_provenance.last_observed_scan_id
)
WHERE derived_fingerprint IS NULL
  AND last_observed_scan_id IS NOT NULL
  AND source_fingerprint IS NULL
  AND EXISTS (
      SELECT 1
      FROM source_entry
      WHERE source_entry.source_entry_id = content_identity_provenance.source_entry_id
        AND source_entry.coordinate_kind = 'derived'
        AND source_entry.source_fingerprint IS NULL
        AND source_entry.derived_fingerprint IS NOT NULL
        AND source_entry.last_observed_scan_id = content_identity_provenance.last_observed_scan_id
  );

UPDATE game_content_source
SET derived_fingerprint = (
    SELECT source_entry.derived_fingerprint
    FROM source_entry
    WHERE source_entry.source_entry_id = game_content_source.source_entry_id
      AND source_entry.coordinate_kind = 'derived'
      AND source_entry.source_fingerprint IS NULL
      AND source_entry.derived_fingerprint IS NOT NULL
      AND source_entry.last_observed_scan_id = game_content_source.last_observed_scan_id
)
WHERE derived_fingerprint IS NULL
  AND last_observed_scan_id IS NOT NULL
  AND source_fingerprint IS NULL
  AND EXISTS (
      SELECT 1
      FROM source_entry
      WHERE source_entry.source_entry_id = game_content_source.source_entry_id
        AND source_entry.coordinate_kind = 'derived'
        AND source_entry.source_fingerprint IS NULL
        AND source_entry.derived_fingerprint IS NOT NULL
        AND source_entry.last_observed_scan_id = game_content_source.last_observed_scan_id
  );

UPDATE grouping_evidence
SET derived_fingerprint = (
    SELECT source_entry.derived_fingerprint
    FROM source_entry
    WHERE source_entry.source_entry_id = grouping_evidence.playlist_source_entry_id
      AND source_entry.coordinate_kind = 'derived'
      AND source_entry.source_fingerprint IS NULL
      AND source_entry.derived_fingerprint IS NOT NULL
      AND source_entry.last_observed_scan_id = grouping_evidence.last_observed_scan_id
)
WHERE derived_fingerprint IS NULL
  AND last_observed_scan_id IS NOT NULL
  AND source_fingerprint IS NULL
  AND EXISTS (
      SELECT 1
      FROM source_entry
      WHERE source_entry.source_entry_id = grouping_evidence.playlist_source_entry_id
        AND source_entry.coordinate_kind = 'derived'
        AND source_entry.source_fingerprint IS NULL
        AND source_entry.derived_fingerprint IS NOT NULL
        AND source_entry.last_observed_scan_id = grouping_evidence.last_observed_scan_id
  );

UPDATE grouping_evidence_member
SET member_derived_fingerprint = (
    SELECT source_entry.derived_fingerprint
    FROM source_entry
    WHERE source_entry.source_entry_id = grouping_evidence_member.member_source_entry_id
      AND source_entry.coordinate_kind = 'derived'
      AND source_entry.source_fingerprint IS NULL
      AND source_entry.derived_fingerprint IS NOT NULL
      AND source_entry.last_observed_scan_id = grouping_evidence_member.member_last_observed_scan_id
)
WHERE member_derived_fingerprint IS NULL
  AND member_last_observed_scan_id IS NOT NULL
  AND member_source_fingerprint IS NULL
  AND EXISTS (
      SELECT 1
      FROM source_entry
      WHERE source_entry.source_entry_id = grouping_evidence_member.member_source_entry_id
        AND source_entry.coordinate_kind = 'derived'
        AND source_entry.source_fingerprint IS NULL
        AND source_entry.derived_fingerprint IS NOT NULL
        AND source_entry.last_observed_scan_id = grouping_evidence_member.member_last_observed_scan_id
  );
