-- Store the canonical root set on the existing one-to-one refresh intent.
-- Separate rows could be partly deleted and leave a plausible but incomplete
-- scope unless a second completeness ledger were maintained. The parent
-- marker keeps a missing intent detectable as corruption for new jobs. Version
-- zero and NULL preserve legacy history without reconstructing its scope.
ALTER TABLE job_run
    ADD COLUMN library_refresh_scope_version INTEGER NOT NULL DEFAULT 0
        CHECK (library_refresh_scope_version IN (0, 1));

ALTER TABLE library_refresh_intent
    ADD COLUMN requested_root_ids_json TEXT;

CREATE TRIGGER job_run_refresh_scope_version_insert
BEFORE INSERT ON job_run
WHEN (NEW.operation_type = 'library_refresh'
      AND NEW.library_refresh_scope_version <> 1)
  OR (NEW.operation_type <> 'library_refresh'
      AND NEW.library_refresh_scope_version <> 0)
BEGIN
    SELECT RAISE(ABORT, 'invalid LibraryRefresh scope version');
END;

CREATE TRIGGER job_run_refresh_scope_version_immutable
BEFORE UPDATE OF library_refresh_scope_version ON job_run
WHEN NEW.library_refresh_scope_version <> OLD.library_refresh_scope_version
BEGIN
    SELECT RAISE(ABORT, 'LibraryRefresh scope version is immutable');
END;

CREATE TRIGGER job_run_operation_type_immutable
BEFORE UPDATE OF operation_type ON job_run
WHEN NEW.operation_type <> OLD.operation_type
BEGIN
    SELECT RAISE(ABORT, 'JobRun operation type is immutable');
END;

CREATE TRIGGER library_refresh_scope_manifest_validate_insert
BEFORE INSERT ON library_refresh_intent
WHEN (SELECT library_refresh_scope_version
      FROM job_run WHERE job_run_id = NEW.job_run_id) IS NOT 1
  OR CASE
       WHEN NEW.requested_root_ids_json IS NULL THEN 1
       WHEN json_valid(NEW.requested_root_ids_json) <> 1 THEN 1
       WHEN json_type(NEW.requested_root_ids_json) <> 'array' THEN 1
       WHEN json_array_length(NEW.requested_root_ids_json) = 0 THEN 1
       WHEN NEW.requested_root_ids_json <> json(NEW.requested_root_ids_json) THEN 1
       WHEN EXISTS (
           SELECT 1 FROM json_each(NEW.requested_root_ids_json)
           WHERE type <> 'text'
              OR length(value) <> 32
              OR value = '00000000000000000000000000000000'
              OR value GLOB '*[^0-9a-f]*'
       ) THEN 1
       WHEN (SELECT COUNT(*) FROM json_each(NEW.requested_root_ids_json))
          <> (SELECT COUNT(DISTINCT value) FROM json_each(NEW.requested_root_ids_json))
       THEN 1
       WHEN EXISTS (
           SELECT 1
           FROM json_each(NEW.requested_root_ids_json) AS previous
           JOIN json_each(NEW.requested_root_ids_json) AS following
             ON CAST(following.key AS INTEGER) = CAST(previous.key AS INTEGER) + 1
           WHERE previous.value >= following.value
       ) THEN 1
       ELSE 0
     END = 1
BEGIN
    SELECT RAISE(ABORT, 'invalid LibraryRefresh requested-root manifest');
END;

CREATE TRIGGER library_refresh_scope_manifest_immutable_update
BEFORE UPDATE ON library_refresh_intent
WHEN NEW.job_run_id <> OLD.job_run_id
  OR NEW.requested_root_ids_json IS NOT OLD.requested_root_ids_json
  OR COALESCE((SELECT library_refresh_scope_version
               FROM job_run WHERE job_run_id = OLD.job_run_id), 0) = 1
BEGIN
    SELECT RAISE(ABORT, 'LibraryRefresh scope evidence is immutable');
END;

CREATE TRIGGER library_refresh_scope_manifest_prevent_delete
BEFORE DELETE ON library_refresh_intent
WHEN OLD.requested_root_ids_json IS NOT NULL
  OR COALESCE((SELECT library_refresh_scope_version
               FROM job_run WHERE job_run_id = OLD.job_run_id), 0) = 1
BEGIN
    SELECT RAISE(ABORT, 'LibraryRefresh scope evidence cannot be deleted');
END;
