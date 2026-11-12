//! Builds the per-game semantic key used to fence Library reads.
//!
//! The key records persisted projection values and relationships that affect
//! search, filters, facets, sorting, membership, source scope, redirects, and
//! active refresh hydration. Before commit, transaction-local triggers compare
//! the saved keys with the post-mutation keys. The Library revision advances
//! once only when committed keys changed. When query semantics change, add each
//! newly queried value or relationship to this key, then track every write path
//! that can change it. Leave presentation-only values out when they do not
//! affect query results.

use rusqlite::{Connection, OptionalExtension, Transaction};

use argus_application::{ApplicationPortError, LibraryViewToken, ListGamesQuery, PersistenceError};

const TRACKING_TABLE: &str = "library_view_before";
const TOKEN_VERSION: &str = "lvt1";
const TOKEN_MAC_BYTES: usize = 64;

#[derive(Debug)]
struct TokenClaims {
    generation: String,
    revision: i64,
    query_contract_version: i64,
    page_size: u32,
    query_binding: String,
}

pub(crate) fn create_token(
    transaction: &Transaction<'_>,
    key: &[u8; 32],
    query: &ListGamesQuery,
) -> Result<LibraryViewToken, ApplicationPortError> {
    let (generation, revision, query_contract_version) =
        read_state(transaction).map_err(ApplicationPortError::Persistence)?;
    if revision < 1 || query_contract_version < 1 {
        return Err(ApplicationPortError::Persistence(
            PersistenceError::CorruptOrIncompatible,
        ));
    }
    let page_size = query.page_size();
    let query_binding = query_binding(query);
    let payload = format!(
        "{TOKEN_VERSION}:{generation}:{revision}:{query_contract_version}:{page_size}:{query_binding}"
    );
    let mac = blake3::keyed_hash(key, payload.as_bytes()).to_hex();
    LibraryViewToken::try_from_external(format!("{payload}:{mac}"))
}

pub(crate) fn validate_list_token(
    transaction: &Transaction<'_>,
    key: &[u8; 32],
    query: &ListGamesQuery,
    token: &LibraryViewToken,
) -> Result<(), ApplicationPortError> {
    let claims = authenticate_token(key, token)?;
    if claims.page_size != query.page_size() || claims.query_binding != query_binding(query) {
        return Err(ApplicationPortError::LibraryViewTokenInvalid);
    }
    validate_current_state(transaction, &claims)
}

pub(crate) fn validate_game_token(
    transaction: &Transaction<'_>,
    key: &[u8; 32],
    token: &LibraryViewToken,
) -> Result<(), ApplicationPortError> {
    let claims = authenticate_token(key, token)?;
    validate_current_state(transaction, &claims)
}

fn validate_current_state(
    transaction: &Transaction<'_>,
    claims: &TokenClaims,
) -> Result<(), ApplicationPortError> {
    let (generation, revision, query_contract_version) =
        read_state(transaction).map_err(ApplicationPortError::Persistence)?;
    if revision != claims.revision
        || query_contract_version != claims.query_contract_version
        || generation != claims.generation
    {
        return Err(ApplicationPortError::LibraryViewStale);
    }
    Ok(())
}

fn authenticate_token(
    key: &[u8; 32],
    token: &LibraryViewToken,
) -> Result<TokenClaims, ApplicationPortError> {
    let value = token.as_str();
    if value.len() > LibraryViewToken::MAX_BYTES {
        return Err(ApplicationPortError::LibraryViewTokenInvalid);
    }
    let fields = value.split(':').collect::<Vec<_>>();
    if fields.len() != 7 || fields[0] != TOKEN_VERSION {
        return Err(ApplicationPortError::LibraryViewTokenInvalid);
    }
    let payload_end = value
        .rfind(':')
        .ok_or(ApplicationPortError::LibraryViewTokenInvalid)?;
    let payload = &value[..payload_end];
    let provided_mac = fields[6];
    if provided_mac.len() != TOKEN_MAC_BYTES
        || !provided_mac
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(ApplicationPortError::LibraryViewTokenInvalid);
    }
    let expected_mac = blake3::keyed_hash(key, payload.as_bytes()).to_hex();
    if !constant_time_equal(provided_mac.as_bytes(), expected_mac.as_bytes()) {
        return Err(ApplicationPortError::LibraryViewTokenInvalid);
    }

    let generation = fields[1];
    if generation.len() != 32
        || !generation
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(ApplicationPortError::LibraryViewTokenInvalid);
    }
    let revision = parse_positive_i64(fields[2])?;
    let query_contract_version = parse_positive_i64(fields[3])?;
    let page_size = fields[4]
        .parse::<u32>()
        .ok()
        .filter(|size| *size > 0)
        .ok_or(ApplicationPortError::LibraryViewTokenInvalid)?;
    let query_binding = fields[5];
    if query_binding.len() != TOKEN_MAC_BYTES
        || !query_binding
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(ApplicationPortError::LibraryViewTokenInvalid);
    }
    Ok(TokenClaims {
        generation: generation.to_owned(),
        revision,
        query_contract_version,
        page_size,
        query_binding: query_binding.to_owned(),
    })
}

fn parse_positive_i64(value: &str) -> Result<i64, ApplicationPortError> {
    value
        .parse::<i64>()
        .ok()
        .filter(|parsed| *parsed > 0)
        .ok_or(ApplicationPortError::LibraryViewTokenInvalid)
}

fn query_binding(query: &ListGamesQuery) -> String {
    blake3::hash(format!("{}:{}", query.query_fingerprint(), query.page_size()).as_bytes())
        .to_hex()
        .to_string()
}

fn constant_time_equal(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    left.iter()
        .zip(right)
        .fold(0_u8, |difference, (left, right)| {
            difference | (left ^ right)
        })
        == 0
}

pub(crate) fn install_tracking(connection: &Connection) -> Result<(), rusqlite::Error> {
    let has_view_state: bool = connection.query_row(
        "SELECT EXISTS(
            SELECT 1 FROM main.sqlite_master
            WHERE type = 'table' AND name = 'library_view_state'
        )",
        [],
        |row| row.get(0),
    )?;

    connection.execute_batch(
        "CREATE TEMP VIEW library_view_refresh_targets AS
        SELECT job.job_run_id, job.state, game.game_id
        FROM main.job_run AS job
        JOIN main.game_refresh_intent AS intent
            ON intent.job_run_id = job.job_run_id
        JOIN main.game AS game
            ON instr(',' || intent.game_ids || ',', ',' || game.game_id || ',') > 0
        WHERE job.operation_type = 'game_refresh'

        UNION ALL

        SELECT job.job_run_id, job.state, projection.game_id
        FROM main.job_run AS job
        JOIN main.library_resolution_refresh_intent AS intent
            ON intent.job_run_id = job.job_run_id
        JOIN main.game_library_row AS projection ON 1 = 1
        JOIN main.game AS game ON game.game_id = projection.game_id
        WHERE job.operation_type = 'library_resolution_refresh'
            AND game.lifecycle_state = 'active'
            AND NOT EXISTS (
                SELECT 1 FROM main.game_redirect AS redirect
                WHERE redirect.game_id = game.game_id
            )

        UNION ALL

        SELECT job.job_run_id, job.state, membership.game_id
        FROM main.job_run AS job
        JOIN main.library_refresh_intent AS intent
            ON intent.job_run_id = job.job_run_id
        JOIN json_each(intent.requested_root_ids_json) AS requested_root
        JOIN main.source_entry AS entry
            ON entry.library_root_id = requested_root.value
        JOIN main.game_content_source AS source
            ON source.source_entry_id = entry.source_entry_id
            AND source.is_current = 1
        JOIN main.game_membership AS membership
            ON membership.game_content_id = source.game_content_id
            AND membership.is_current = 1
        WHERE job.operation_type = 'library_refresh';

        CREATE TEMP VIEW library_view_current AS
        SELECT game.game_id,
            CASE WHEN EXISTS (
                SELECT 1
                FROM library_view_refresh_targets AS target
                WHERE target.game_id = game.game_id
                    AND target.state IN ('queued', 'preparing', 'running')
            ) THEN 'refreshing'
                ELSE (
                    SELECT projection.hydration_state
                    FROM main.game_library_row AS projection
                    WHERE projection.game_id = game.game_id
                )
            END AS effective_hydration_state,
            json_array(
                game.lifecycle_state,
                (SELECT redirect.canonical_game_id
                 FROM main.game_redirect AS redirect
                 WHERE redirect.game_id = game.game_id),
                (SELECT json_array(
                    projection.display_title,
                    projection.platform_id,
                    projection.presentation_region,
                    projection.release_date,
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM library_view_refresh_targets AS target
                        WHERE target.game_id = game.game_id
                            AND target.state IN ('queued', 'preparing', 'running')
                    ) THEN 'refreshing' ELSE projection.hydration_state END,
                    projection.availability_state,
                    projection.search_text,
                    COALESCE(
                        CAST(strftime('%s', projection.updated_at) AS INTEGER) * 1000,
                        CAST(projection.updated_at AS INTEGER) * 1000,
                        0
                    )
                 )
                 FROM main.game_library_row AS projection
                 WHERE projection.game_id = game.game_id),
                (SELECT COALESCE(
                    json_group_array(json_array(
                        membership.game_content_id,
                        membership.relationship,
                        membership.grouping_basis,
                        membership.grouping_revision
                    )),
                    '[]'
                 )
                 FROM (
                    SELECT game_content_id, relationship, grouping_basis, grouping_revision
                    FROM main.game_membership
                    WHERE game_id = game.game_id AND is_current = 1
                    ORDER BY game_content_id, relationship
                 ) AS membership),
                (SELECT COALESCE(
                    json_group_array(json_array(
                        membership.game_content_id,
                        source.source_entry_id,
                        entry.library_root_id,
                        root.library_source_id
                    )),
                    '[]'
                 )
                 FROM (
                    SELECT game_content_id
                    FROM main.game_membership
                    WHERE game_id = game.game_id AND is_current = 1
                    ORDER BY game_content_id
                 ) AS membership
                 JOIN main.game_content_source AS source
                   ON source.game_content_id = membership.game_content_id
                  AND source.is_current = 1
                 JOIN main.source_entry AS entry
                   ON entry.source_entry_id = source.source_entry_id
                 JOIN main.library_root AS root
                   ON root.library_root_id = entry.library_root_id
                 ORDER BY membership.game_content_id, source.source_entry_id)
            ) AS key_json
        FROM main.game AS game;",
    )?;

    if !has_view_state {
        return Ok(());
    }

    connection.execute_batch(
        "CREATE TEMP TABLE library_view_before (
            game_id TEXT PRIMARY KEY,
            existed INTEGER NOT NULL,
            key_json TEXT
        ) WITHOUT ROWID;",
    )?;

    install_direct_tracking(connection, "game", "game_id")?;
    install_direct_tracking(connection, "game_redirect", "game_id")?;
    install_direct_tracking(connection, "game_library_row", "game_id")?;
    install_direct_tracking(connection, "game_membership", "game_id")?;
    install_related_tracking(
        connection,
        "game_content_source",
        "game_content_id",
        "SELECT DISTINCT membership.game_id
         FROM main.game_membership AS membership
         WHERE membership.game_content_id = {value}",
    )?;
    install_related_tracking(
        connection,
        "game_content",
        "game_content_id",
        "SELECT DISTINCT membership.game_id
         FROM main.game_membership AS membership
         WHERE membership.game_content_id = {value}",
    )?;
    install_related_tracking(
        connection,
        "source_entry",
        "source_entry_id",
        "SELECT DISTINCT membership.game_id
         FROM main.game_content_source AS source
         JOIN main.game_membership AS membership
           ON membership.game_content_id = source.game_content_id
         WHERE source.source_entry_id = {value}",
    )?;
    install_related_tracking(
        connection,
        "library_root",
        "library_root_id",
        "SELECT DISTINCT membership.game_id
         FROM main.source_entry AS entry
         JOIN main.game_content_source AS source
           ON source.source_entry_id = entry.source_entry_id
         JOIN main.game_membership AS membership
           ON membership.game_content_id = source.game_content_id
         WHERE entry.library_root_id = {value}",
    )?;
    install_related_tracking(
        connection,
        "library_source",
        "library_source_id",
        "SELECT DISTINCT membership.game_id
         FROM main.library_root AS root
         JOIN main.source_entry AS entry
           ON entry.library_root_id = root.library_root_id
         JOIN main.game_content_source AS source
           ON source.source_entry_id = entry.source_entry_id
         JOIN main.game_membership AS membership
           ON membership.game_content_id = source.game_content_id
         WHERE root.library_source_id = {value}",
    )?;
    install_refresh_tracking(connection)?;

    Ok(())
}

fn install_refresh_tracking(connection: &Connection) -> Result<(), rusqlite::Error> {
    connection.execute_batch(&format!(
        "CREATE TEMP TRIGGER library_view_track_job_run_state
        BEFORE UPDATE OF state ON main.job_run
        WHEN OLD.state IS NOT NEW.state
        BEGIN {} END;

        CREATE TEMP TRIGGER library_view_track_job_run_delete
        BEFORE DELETE ON main.job_run
        BEGIN {} END;",
        record_job_targets("OLD.job_run_id"),
        record_job_targets("OLD.job_run_id"),
    ))?;

    install_refresh_intent_tracking(
        connection,
        "game_refresh_intent",
        "SELECT current.game_id
         FROM library_view_current AS current
         WHERE instr(',' || {row}.game_ids || ',', ',' || current.game_id || ',') > 0",
    )?;
    install_refresh_intent_tracking(
        connection,
        "library_refresh_intent",
        "SELECT DISTINCT current.game_id
         FROM library_view_current AS current
         WHERE EXISTS (
             SELECT 1
             FROM json_each({row}.requested_root_ids_json) AS requested_root
             JOIN main.source_entry AS entry
                 ON entry.library_root_id = requested_root.value
             JOIN main.game_content_source AS source
                 ON source.source_entry_id = entry.source_entry_id
                 AND source.is_current = 1
             JOIN main.game_membership AS membership
                 ON membership.game_content_id = source.game_content_id
                 AND membership.is_current = 1
             WHERE membership.game_id = current.game_id
         )",
    )?;
    install_refresh_intent_tracking(
        connection,
        "library_resolution_refresh_intent",
        "SELECT current.game_id
         FROM library_view_current AS current
         JOIN main.game AS game ON game.game_id = current.game_id
         WHERE game.lifecycle_state = 'active'
             AND NOT EXISTS (
                 SELECT 1 FROM main.game_redirect AS redirect
                 WHERE redirect.game_id = game.game_id
             )
             AND EXISTS (
                 SELECT 1 FROM main.game_library_row AS projection
                 WHERE projection.game_id = current.game_id
             )",
    )?;
    Ok(())
}

fn install_refresh_intent_tracking(
    connection: &Connection,
    table: &str,
    target_query: &str,
) -> Result<(), rusqlite::Error> {
    for event in ["INSERT", "UPDATE", "DELETE"] {
        let trigger_name = format!("library_view_track_{table}_{}", event.to_lowercase());
        let body = match event {
            "INSERT" => record_selected_games("NEW", target_query),
            "DELETE" => format!(
                "{} {}",
                record_job_targets("OLD.job_run_id"),
                record_selected_games("OLD", target_query)
            ),
            _ => format!(
                "{} {} {} {}",
                record_job_targets("OLD.job_run_id"),
                record_job_targets("NEW.job_run_id"),
                record_selected_games("OLD", target_query),
                record_selected_games("NEW", target_query)
            ),
        };
        connection.execute_batch(&format!(
            "CREATE TEMP TRIGGER {trigger_name}
            BEFORE {event} ON main.{table}
            BEGIN {body} END;"
        ))?;
    }
    Ok(())
}

fn record_job_targets(job_run_id: &str) -> String {
    format!(
        "INSERT INTO {TRACKING_TABLE} (game_id, existed, key_json)
         SELECT DISTINCT current.game_id, 1, current.key_json
         FROM library_view_refresh_targets AS target
         JOIN library_view_current AS current ON current.game_id = target.game_id
         WHERE target.job_run_id = {job_run_id}
             AND NOT EXISTS (
                 SELECT 1 FROM {TRACKING_TABLE} AS before
                 WHERE before.game_id = current.game_id
             );"
    )
}

fn record_selected_games(row: &str, target_query: &str) -> String {
    let query = target_query.replace("{row}", row);
    format!(
        "INSERT INTO {TRACKING_TABLE} (game_id, existed, key_json)
         SELECT selected.game_id, 1, current.key_json
         FROM ({query}) AS selected
         JOIN library_view_current AS current ON current.game_id = selected.game_id
         WHERE NOT EXISTS (
             SELECT 1 FROM {TRACKING_TABLE} AS before
             WHERE before.game_id = selected.game_id
         );"
    )
}

fn install_direct_tracking(
    connection: &Connection,
    table: &str,
    id_column: &str,
) -> Result<(), rusqlite::Error> {
    for event in ["INSERT", "UPDATE", "DELETE"] {
        let trigger_name = format!("library_view_track_{table}_{}", event.to_lowercase());
        let body = match event {
            "INSERT" => record_game("NEW", id_column),
            "DELETE" => record_game("OLD", id_column),
            _ => format!(
                "{} {}",
                record_game("OLD", id_column),
                record_game("NEW", id_column)
            ),
        };
        connection.execute_batch(&format!(
            "CREATE TEMP TRIGGER {trigger_name}
             BEFORE {event} ON main.{table}
             BEGIN {body} END;"
        ))?;
    }
    Ok(())
}

fn install_related_tracking(
    connection: &Connection,
    table: &str,
    id_column: &str,
    related_games: &str,
) -> Result<(), rusqlite::Error> {
    for event in ["INSERT", "UPDATE", "DELETE"] {
        let trigger_name = format!("library_view_track_{table}_{}", event.to_lowercase());
        let body = match event {
            "INSERT" => record_related_games("NEW", id_column, related_games),
            "DELETE" => record_related_games("OLD", id_column, related_games),
            _ => format!(
                "{} {}",
                record_related_games("OLD", id_column, related_games),
                record_related_games("NEW", id_column, related_games)
            ),
        };
        connection.execute_batch(&format!(
            "CREATE TEMP TRIGGER {trigger_name}
             BEFORE {event} ON main.{table}
             BEGIN {body} END;"
        ))?;
    }
    Ok(())
}

fn record_game(row: &str, id_column: &str) -> String {
    let game_id = format!("{row}.{id_column}");
    format!(
        "INSERT INTO {TRACKING_TABLE} (game_id, existed, key_json)
         SELECT {game_id},
             EXISTS(SELECT 1 FROM library_view_current WHERE game_id = {game_id}),
             (SELECT key_json FROM library_view_current WHERE game_id = {game_id})
         WHERE NOT EXISTS (
             SELECT 1 FROM {TRACKING_TABLE} WHERE game_id = {game_id}
         );"
    )
}

fn record_related_games(row: &str, id_column: &str, related_games: &str) -> String {
    let id = format!("{row}.{id_column}");
    let query = related_games.replace("{value}", &id);
    format!(
        "INSERT INTO {TRACKING_TABLE} (game_id, existed, key_json)
         SELECT related.game_id, 1,
             (SELECT key_json FROM library_view_current WHERE game_id = related.game_id)
         FROM ({query}) AS related
         WHERE NOT EXISTS (
             SELECT 1 FROM {TRACKING_TABLE} WHERE game_id = related.game_id
         );"
    )
}

pub(crate) fn prepare_commit(transaction: &Transaction<'_>) -> Result<(), PersistenceError> {
    let tracking_exists: bool = transaction
        .query_row(
            "SELECT EXISTS(
                SELECT 1 FROM sqlite_temp_master
                WHERE type = 'table' AND name = ?1
            )",
            [TRACKING_TABLE],
            |row| row.get(0),
        )
        .map_err(map_sqlite_error)?;
    if !tracking_exists {
        return Ok(());
    }

    let keys_changed: bool = transaction
        .query_row(
            "SELECT EXISTS(
                SELECT 1
                FROM temp.library_view_before AS before
                LEFT JOIN temp.library_view_current AS current
                  ON current.game_id = before.game_id
                WHERE before.existed <> (current.game_id IS NOT NULL)
                   OR before.key_json IS NOT current.key_json
            )",
            [],
            |row| row.get(0),
        )
        .map_err(map_sqlite_error)?;

    if keys_changed {
        advance_membership_revision(transaction)?;
    }
    transaction
        .execute("DELETE FROM temp.library_view_before", [])
        .map_err(map_sqlite_error)?;
    Ok(())
}

pub(crate) fn advance_query_contract_version(
    transaction: &Transaction<'_>,
) -> Result<(), PersistenceError> {
    let (generation, revision, version) = read_state(transaction)?;
    if version < 1 || revision < 1 {
        return Err(PersistenceError::CorruptOrIncompatible);
    }

    if version == i64::MAX {
        let next_generation = fresh_generation(transaction, &generation)?;
        transaction
            .execute(
                "UPDATE library_view_state
                 SET generation_id = ?1, membership_revision = 1,
                     query_contract_version = 1
                 WHERE singleton_key = 1",
                [next_generation],
            )
            .map_err(map_sqlite_error)?;
    } else {
        transaction
            .execute(
                "UPDATE library_view_state
                 SET query_contract_version = ?1
                 WHERE singleton_key = 1",
                [version + 1],
            )
            .map_err(map_sqlite_error)?;
    }
    Ok(())
}

pub(crate) fn read_state(
    transaction: &Transaction<'_>,
) -> Result<(String, i64, i64), PersistenceError> {
    transaction
        .query_row(
            "SELECT generation_id, membership_revision, query_contract_version
             FROM library_view_state WHERE singleton_key = 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()
        .map_err(map_sqlite_error)?
        .ok_or(PersistenceError::CorruptOrIncompatible)
}

fn advance_membership_revision(transaction: &Transaction<'_>) -> Result<(), PersistenceError> {
    let (generation, revision, version) = read_state(transaction)?;
    if revision < 1 || version < 1 {
        return Err(PersistenceError::CorruptOrIncompatible);
    }

    if revision == i64::MAX {
        let next_generation = fresh_generation(transaction, &generation)?;
        transaction
            .execute(
                "UPDATE library_view_state
                 SET generation_id = ?1, membership_revision = 1
                 WHERE singleton_key = 1",
                [next_generation],
            )
            .map_err(map_sqlite_error)?;
    } else {
        transaction
            .execute(
                "UPDATE library_view_state
                 SET membership_revision = ?1
                 WHERE singleton_key = 1",
                [revision + 1],
            )
            .map_err(map_sqlite_error)?;
    }
    Ok(())
}

fn fresh_generation(
    transaction: &Transaction<'_>,
    previous: &str,
) -> Result<String, PersistenceError> {
    for _ in 0..8 {
        let candidate: String = transaction
            .query_row("SELECT lower(hex(randomblob(16)))", [], |row| row.get(0))
            .map_err(map_sqlite_error)?;
        if candidate != previous {
            return Ok(candidate);
        }
    }
    Err(PersistenceError::Internal)
}

fn map_sqlite_error(error: rusqlite::Error) -> PersistenceError {
    match error {
        rusqlite::Error::SqliteFailure(code, _)
            if code.code == rusqlite::ErrorCode::DatabaseBusy
                || code.code == rusqlite::ErrorCode::DatabaseLocked =>
        {
            PersistenceError::DatabaseLocked
        }
        rusqlite::Error::SqliteFailure(code, _)
            if code.code == rusqlite::ErrorCode::ConstraintViolation =>
        {
            PersistenceError::ConstraintViolation
        }
        _ => PersistenceError::CorruptOrIncompatible,
    }
}
