//! SQLite persistence for canonical content and the focused logical library.
//!
//! The repository deliberately accepts only already-validated derivations. It
//! performs cheap persisted-version checks and short SQL mutations; source
//! bytes, parsing, canonicalization, and hashing belong outside this write
//! transaction.

use argus_application::{
    ContentIdentitySummary, ContentProvenanceSummary, ContentType, ConvergenceOutcome,
    GameContentId, GameContentPresence, GameContentSummary, GameDetail, GameId, GameLibraryPage,
    GameLibraryRow, GameLifecycle, GameListCursor, GameMembershipSummary, GetGameResult,
    GroupingBasis, HydrationState, IdentificationState, IdentityConvergenceStore, IdentityDigest,
    LibraryRootId, ListGamesQuery, LogicalContentRepository, LogicalLibraryQueries,
    MembershipRelationship, PersistenceError, PlatformId, ScanRunId, SourceEntryId,
    SourceVersionEvidence, ValidatedContentDerivation,
};
use rusqlite::{OptionalExtension, Row, params_from_iter};

use super::jobs::map_persistence_operation_error;
use super::unit_of_work::SqliteUnitOfWork;

/// Transaction-scoped logical-content repository.
pub struct SqliteLogicalContentRepository<'scope, 'connection> {
    work: &'scope mut SqliteUnitOfWork<'connection>,
}

impl<'scope, 'connection> SqliteLogicalContentRepository<'scope, 'connection> {
    pub(crate) fn new(work: &'scope mut SqliteUnitOfWork<'connection>) -> Self {
        Self { work }
    }

    fn source_ids(source_entry_ids: &[SourceEntryId]) -> Vec<String> {
        source_entry_ids.iter().map(ToString::to_string).collect()
    }

    fn transaction(&mut self) -> Result<&mut rusqlite::Transaction<'connection>, PersistenceError> {
        self.work.transaction_mut()
    }
}

/// Finalizes source associations before their source rows are removed. The
/// caller remains responsible for deleting the source rows in the same
/// transaction.
pub(crate) fn finalize_sources(
    work: &mut SqliteUnitOfWork<'_>,
    source_entry_ids: &[SourceEntryId],
) -> Result<u64, PersistenceError> {
    SqliteLogicalContentRepository::new(work).finalize_source_absence(source_entry_ids)
}

/// Recomputes content and projection availability after a configured root's
/// reachability evidence changes. Identity proof is intentionally untouched.
pub(crate) fn refresh_root_availability(
    work: &mut SqliteUnitOfWork<'_>,
    root_id: LibraryRootId,
) -> Result<(), PersistenceError> {
    let content_ids: Vec<String> = {
        let mut statement = work
            .transaction_mut()?
            .prepare(
                "SELECT DISTINCT s.game_content_id
             FROM game_content_source s
             JOIN source_entry e ON e.source_entry_id = s.source_entry_id
             WHERE s.is_current = 1 AND e.library_root_id = ?1",
            )
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map([root_id.to_string()], |row| row.get(0))
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    if content_ids.is_empty() {
        return Ok(());
    }
    for content_id in &content_ids {
        refresh_content(work.transaction_mut()?, content_id)?;
    }
    let content_placeholders = placeholders(content_ids.len());
    let game_ids: Vec<String> = {
        let sql = format!(
            "SELECT DISTINCT game_id
             FROM game_membership
             WHERE is_current = 1 AND game_content_id IN ({content_placeholders})"
        );
        let mut statement = work
            .transaction_mut()?
            .prepare(&sql)
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(params_from_iter(content_ids.iter()), |row| row.get(0))
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    for game_id in game_ids {
        refresh_game(work.transaction_mut()?, &game_id)?;
    }
    Ok(())
}

impl IdentityConvergenceStore for SqliteLogicalContentRepository<'_, '_> {
    fn source_version_matches(
        &mut self,
        evidence: &SourceVersionEvidence,
    ) -> Result<bool, PersistenceError> {
        let persisted: Option<(Option<String>, String)> = self
            .transaction()?
            .query_row(
                "SELECT source_fingerprint, last_observed_scan_id
                 FROM source_entry
                 WHERE source_entry_id = ?1",
                [evidence.source_entry_id().to_string()],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        Ok(persisted
            .map(|(fingerprint, scan_id)| {
                fingerprint.as_deref() == evidence.source_fingerprint()
                    && scan_id == evidence.last_observed_scan_id().to_string()
            })
            .unwrap_or(false))
    }

    fn converge_identity(
        &mut self,
        derivation: &ValidatedContentDerivation,
    ) -> Result<ConvergenceOutcome, PersistenceError> {
        validate_scheme(derivation)?;

        let source_id = derivation.source_entry_id().to_string();
        let association_key = derivation.association_key();
        let existing_source: Option<String> = self
            .transaction()?
            .query_row(
                "SELECT game_content_id
                 FROM game_content_source
                 WHERE source_entry_id = ?1
                   AND association_key = ?2
                   AND is_current = 1",
                [&source_id, association_key],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;

        let identity = derivation.identity();
        let digest = digest_hex(identity.digest());
        let current_identity: Option<(String, i64)> = self
            .transaction()?
            .query_row(
                "SELECT game_content_id, identity_revision
                 FROM content_identity
                 WHERE scheme_id = ?1
                   AND identity_value = ?2
                   AND is_current = 1",
                rusqlite::params![identity.scheme_id(), digest],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;

        if let Some((raw_content_id, persisted_revision)) = current_identity {
            if persisted_revision != i64::from(identity.revision()) {
                return Err(PersistenceError::Conflict);
            }
            let content_id = parse_game_content_id(raw_content_id.clone())?;
            if let Some(existing_source) = existing_source.as_deref()
                && existing_source != raw_content_id
            {
                return Err(PersistenceError::Conflict);
            }

            let game_id = current_game_for_content(self.transaction()?, &raw_content_id)?;
            ensure_source_association(self.transaction()?, derivation, &raw_content_id)?;
            refresh_content(self.transaction()?, &raw_content_id)?;
            refresh_game(self.transaction()?, &game_id.to_string())?;
            return Ok(ConvergenceOutcome::Attached {
                game_content_id: content_id,
                game_id,
            });
        }

        // Revision is proof metadata: only rows with the same validated
        // revision are semantically comparable for orphan reconnection.
        // Deliberately collect every candidate so ambiguity cannot be hidden
        // by an arbitrary ORDER BY/LIMIT choice.
        let retained_matches: Vec<(String, String, i64)> = {
            let mut statement = self
                .transaction()?
                .prepare(
                    "SELECT content_identity_id, game_content_id, identity_revision
                     FROM content_identity
                     WHERE scheme_id = ?1
                       AND identity_value = ?2
                       AND identity_revision = ?3
                       AND is_current = 0",
                )
                .map_err(map_persistence_operation_error)?;
            let rows = statement
                .query_map(
                    rusqlite::params![identity.scheme_id(), digest, i64::from(identity.revision())],
                    |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
                )
                .map_err(map_persistence_operation_error)?;
            rows.collect::<Result<Vec<_>, _>>()
                .map_err(map_persistence_operation_error)?
        };

        if let [(identity_id, raw_content_id, persisted_revision)] = retained_matches.as_slice() {
            if *persisted_revision != i64::from(identity.revision()) {
                return Err(PersistenceError::Conflict);
            }
            let content_id = parse_game_content_id(raw_content_id.clone())?;
            if let Some(existing_source) = existing_source.as_deref()
                && existing_source != raw_content_id
            {
                return Err(PersistenceError::Conflict);
            }
            let game_id = current_game_for_content(self.transaction()?, raw_content_id)?;
            self.transaction()?
                .execute(
                    "UPDATE content_identity
                 SET is_current = 1,
                     proving_source_entry_id = ?1,
                     proving_association_key = ?2,
                     proving_source_fingerprint = ?3,
                     proving_scan_run_id = ?4,
                     updated_at = CURRENT_TIMESTAMP
                 WHERE content_identity_id = ?5
                   AND is_current = 0",
                    rusqlite::params![
                        source_id,
                        association_key,
                        derivation.source_version().source_fingerprint(),
                        derivation
                            .source_version()
                            .last_observed_scan_id()
                            .to_string(),
                        identity_id,
                    ],
                )
                .map_err(map_persistence_operation_error)?;
            ensure_source_association(self.transaction()?, derivation, raw_content_id)?;
            refresh_content(self.transaction()?, raw_content_id)?;
            refresh_game(self.transaction()?, &game_id.to_string())?;
            return Ok(ConvergenceOutcome::Attached {
                game_content_id: content_id,
                game_id,
            });
        }

        if existing_source.is_some() {
            return Err(PersistenceError::Conflict);
        }

        let raw_content_id: String = self
            .transaction()?
            .query_row(
                "INSERT INTO game_content
                    (game_content_id, platform_id, content_type, presence_state,
                     identification_state, grouping_revision, created_at, updated_at)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, ?2, 'available', 'identified', 1,
                     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                 RETURNING game_content_id",
                rusqlite::params![
                    derivation.platform().as_str(),
                    derivation.content_type().as_str()
                ],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;
        let raw_game_id: String = self
            .transaction()?
            .query_row(
                "INSERT INTO game
                    (game_id, platform_id, lifecycle_state, grouping_revision,
                     fallback_title, fallback_title_provenance, hydration_state,
                     created_at, updated_at)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, 'active', 1, ?2, 'local_fallback',
                     'partially_hydrated', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                 RETURNING game_id",
                rusqlite::params![derivation.platform().as_str(), derivation.fallback_title()],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;

        self.transaction()?
            .execute(
                "INSERT INTO content_identity
                    (content_identity_id, game_content_id, scheme_id, identity_revision,
                     identity_value, is_current, proving_source_entry_id,
                     proving_association_key, proving_source_fingerprint,
                     proving_scan_run_id, created_at, updated_at)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, 1, ?5, ?6, ?7, ?8,
                     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                rusqlite::params![
                    raw_content_id,
                    identity.scheme_id(),
                    i64::from(identity.revision()),
                    digest,
                    source_id,
                    association_key,
                    derivation.source_version().source_fingerprint(),
                    derivation
                        .source_version()
                        .last_observed_scan_id()
                        .to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        self.transaction()?
            .execute(
                "INSERT INTO game_content_source
                (game_content_source_id, game_content_id, source_entry_id, association_key,
                 source_fingerprint, last_observed_scan_id, is_current, created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, 1,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                rusqlite::params![
                    raw_content_id,
                    source_id,
                    association_key,
                    derivation.source_version().source_fingerprint(),
                    derivation
                        .source_version()
                        .last_observed_scan_id()
                        .to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
        self.transaction()?
            .execute(
                "INSERT INTO game_membership
                (game_membership_id, game_id, game_content_id, relationship,
                 grouping_basis, grouping_revision, is_current, created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, ?2, 'primary', 'provisional', 1, 1,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                rusqlite::params![raw_game_id, raw_content_id],
            )
            .map_err(map_persistence_operation_error)?;
        self.transaction()?
            .execute(
                "INSERT INTO game_library_row
                (game_id, display_title, display_title_provenance, platform_id,
                 hydration_state, availability_state, content_count, source_count, updated_at)
             VALUES
                (?1, ?2, 'local_fallback', ?3, 'partially_hydrated', 'available', 1, 1,
                 CURRENT_TIMESTAMP)",
                rusqlite::params![
                    raw_game_id,
                    derivation.fallback_title(),
                    derivation.platform().as_str()
                ],
            )
            .map_err(map_persistence_operation_error)?;

        Ok(ConvergenceOutcome::Created {
            game_content_id: parse_game_content_id(raw_content_id)?,
            game_id: parse_game_id(raw_game_id)?,
        })
    }
}

impl LogicalLibraryQueries for SqliteLogicalContentRepository<'_, '_> {
    fn list_games(&mut self, query: &ListGamesQuery) -> Result<GameLibraryPage, PersistenceError> {
        if query.scope() != argus_application::LibraryScope::All
            || query.search().is_some()
            || !query.filters_empty()
            || query.sort() != argus_application::LibrarySort::DisplayTitleAscending
        {
            return Err(PersistenceError::ConstraintViolation);
        }

        let mut rows = Vec::new();
        let mut sql = String::from(
            "SELECT r.game_id, r.display_title, r.platform_id, r.hydration_state,
                    r.availability_state, r.content_count, r.source_count,
                    COALESCE(CAST(strftime('%s', r.updated_at) AS INTEGER) * 1000,
                             CAST(r.updated_at AS INTEGER) * 1000, 0)
             FROM game_library_row r
             JOIN game g ON g.game_id = r.game_id
             WHERE g.lifecycle_state = 'active'",
        );
        let mut values: Vec<String> = Vec::new();
        if let Some(cursor) = query.cursor() {
            sql.push_str(
                " AND (r.display_title COLLATE NOCASE > ?1
                       OR (r.display_title COLLATE NOCASE = ?1 AND r.game_id > ?2))",
            );
            values.push(cursor.display_title().to_owned());
            values.push(cursor.game_id().to_string());
        }
        let limit_placeholder = if values.is_empty() { "?1" } else { "?3" };
        sql.push_str(" ORDER BY r.display_title COLLATE NOCASE ASC, r.game_id ASC LIMIT ");
        sql.push_str(limit_placeholder);
        values.push((query.page_size() as u64 + 1).to_string());
        let params = params_from_iter(values.iter());
        let mut statement = self
            .transaction()?
            .prepare(&sql)
            .map_err(map_persistence_operation_error)?;
        let mapped = statement
            .query_map(params, read_library_row)
            .map_err(map_persistence_operation_error)?;
        for row in mapped {
            rows.push(row.map_err(map_persistence_operation_error)?);
        }
        let has_more = rows.len() > query.page_size() as usize;
        if has_more {
            rows.truncate(query.page_size() as usize);
        }
        let next_cursor = has_more.then(|| {
            let row = rows.last().expect("a page with more rows has a last row");
            GameListCursor::from_paging_keys(row.display_title(), row.game_id())
        });
        Ok(GameLibraryPage::new(rows, next_cursor))
    }

    fn get_game(&mut self, game_id: GameId) -> Result<GetGameResult, PersistenceError> {
        let (canonical, redirected) = resolve_redirect(self.transaction()?, game_id)?;
        if redirected {
            return Ok(GetGameResult::Redirected(canonical));
        }

        let raw_game_id = canonical.to_string();
        let game: Option<(String, String, String, String, String)> = self
            .transaction()?
            .query_row(
                "SELECT platform_id, lifecycle_state, hydration_state, fallback_title,
                        (SELECT availability_state FROM game_library_row WHERE game_id = game.game_id)
                 FROM game
                 WHERE game_id = ?1",
                [&raw_game_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        let Some((platform, lifecycle, hydration, fallback_title, availability)) = game else {
            return Ok(GetGameResult::NotFound);
        };
        let platform = parse_platform(&platform)?;
        let lifecycle = parse_lifecycle(&lifecycle)?;
        let hydration = parse_hydration(&hydration)?;
        let availability = parse_availability(&availability)?;

        let memberships = {
            let mut statement = self
                .transaction()?
                .prepare(
                    "SELECT game_content_id, relationship, grouping_basis, grouping_revision
                 FROM game_membership
                 WHERE game_id = ?1 AND is_current = 1
                 ORDER BY CASE relationship WHEN 'primary' THEN 0 ELSE 1 END,
                          game_content_id ASC",
                )
                .map_err(map_persistence_operation_error)?;
            let mapped = statement
                .query_map([&raw_game_id], |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                })
                .map_err(map_persistence_operation_error)?;
            let mut values = Vec::new();
            for row in mapped {
                let (content_id, relationship, basis, revision) =
                    row.map_err(map_persistence_operation_error)?;
                values.push(GameMembershipSummary::new(
                    parse_game_content_id(content_id)?,
                    parse_relationship(&relationship)?,
                    parse_grouping_basis(&basis)?,
                    revision as u32,
                ));
            }
            values
        };

        let content = {
            let mut statement = self.transaction()?.prepare(
                "SELECT gc.game_content_id, gc.platform_id, gc.content_type,
                        gc.presence_state, gc.identification_state,
                        COUNT(DISTINCT CASE WHEN gcs.is_current = 1 THEN gcs.game_content_source_id END),
                        ci.scheme_id, ci.identity_revision, ci.identity_value,
                        ci.proving_source_entry_id, ci.proving_association_key,
                        ci.proving_source_fingerprint, ci.proving_scan_run_id
                 FROM game_membership gm
                 JOIN game_content gc ON gc.game_content_id = gm.game_content_id
                 LEFT JOIN game_content_source gcs ON gcs.game_content_id = gc.game_content_id
                 LEFT JOIN content_identity ci
                   ON ci.game_content_id = gc.game_content_id AND ci.is_current = 1
                 WHERE gm.game_id = ?1 AND gm.is_current = 1
                 GROUP BY gc.game_content_id, gc.platform_id, gc.content_type,
                          gc.presence_state, gc.identification_state,
                          ci.content_identity_id
                 ORDER BY gc.game_content_id ASC",
            )
            .map_err(map_persistence_operation_error)?;
            let mapped = statement
                .query_map([&raw_game_id], read_content_summary)
                .map_err(map_persistence_operation_error)?;
            let mut values = Vec::new();
            for row in mapped {
                values.push(row.map_err(map_persistence_operation_error)?);
            }
            values
        };

        Ok(GetGameResult::Found(GameDetail::new(
            canonical,
            platform,
            lifecycle,
            hydration,
            fallback_title,
            memberships,
            content,
            availability,
        )))
    }
}

impl LogicalContentRepository for SqliteLogicalContentRepository<'_, '_> {
    fn finalize_source_absence(
        &mut self,
        source_entry_ids: &[SourceEntryId],
    ) -> Result<u64, PersistenceError> {
        if source_entry_ids.is_empty() {
            return Ok(0);
        }
        let ids = Self::source_ids(source_entry_ids);
        let source_placeholders = placeholders(ids.len());
        let affected_contents: Vec<String> = {
            let sql = format!(
                "SELECT DISTINCT game_content_id
                 FROM game_content_source
                 WHERE is_current = 1 AND source_entry_id IN ({source_placeholders})"
            );
            let mut statement = self
                .transaction()?
                .prepare(&sql)
                .map_err(map_persistence_operation_error)?;
            let mapped = statement
                .query_map(params_from_iter(ids.iter()), |row| row.get(0))
                .map_err(map_persistence_operation_error)?;
            let mut values = Vec::new();
            for row in mapped {
                values.push(row.map_err(map_persistence_operation_error)?);
            }
            values
        };
        if affected_contents.is_empty() {
            return Ok(0);
        }

        let update_sql = format!(
            "UPDATE game_content_source
             SET is_current = 0, updated_at = CURRENT_TIMESTAMP
             WHERE is_current = 1 AND source_entry_id IN ({source_placeholders})"
        );
        let changed = self
            .transaction()?
            .execute(&update_sql, params_from_iter(ids.iter()))
            .map_err(map_persistence_operation_error)?;

        for content_id in &affected_contents {
            self.transaction()?
                .execute(
                    "UPDATE content_identity
                 SET is_current = 0, updated_at = CURRENT_TIMESTAMP
                 WHERE game_content_id = ?1
                   AND is_current = 1
                   AND NOT EXISTS (
                       SELECT 1
                       FROM game_content_source s
                       WHERE s.game_content_id = content_identity.game_content_id
                         AND s.is_current = 1
                         AND s.source_entry_id = content_identity.proving_source_entry_id
                         AND (content_identity.proving_association_key IS NULL
                              OR s.association_key = content_identity.proving_association_key)
                   )",
                    [content_id],
                )
                .map_err(map_persistence_operation_error)?;
            refresh_content(self.transaction()?, content_id)?;
        }

        let game_ids: Vec<String> = {
            let content_placeholders = placeholders(affected_contents.len());
            let sql = format!(
                "SELECT DISTINCT game_id
                 FROM game_membership
                 WHERE is_current = 1 AND game_content_id IN ({content_placeholders})"
            );
            let mut statement = self
                .transaction()?
                .prepare(&sql)
                .map_err(map_persistence_operation_error)?;
            let mapped = statement
                .query_map(params_from_iter(affected_contents.iter()), |row| row.get(0))
                .map_err(map_persistence_operation_error)?;
            let mut values = Vec::new();
            for row in mapped {
                values.push(row.map_err(map_persistence_operation_error)?);
            }
            values
        };
        for game_id in game_ids {
            refresh_game(self.transaction()?, &game_id)?;
        }

        // Source rows are authoritative physical observations and are about
        // to be deleted by the caller. Historical identity proof above keeps
        // only the bounded evidence needed for future re-identification.
        let delete_sql = format!(
            "DELETE FROM game_content_source WHERE source_entry_id IN ({source_placeholders})"
        );
        self.transaction()?
            .execute(&delete_sql, params_from_iter(ids.iter()))
            .map_err(map_persistence_operation_error)?;
        Ok(changed as u64)
    }
}

fn validate_scheme(derivation: &ValidatedContentDerivation) -> Result<(), PersistenceError> {
    let expected = match (derivation.platform(), derivation.content_type()) {
        (argus_domain::PlatformId::NintendoNes, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-nes.cartridge.v1"
        }
        (argus_domain::PlatformId::NintendoFds, argus_domain::ContentType::MagneticDiskImage) => {
            "argus.content.identity.nintendo-fds.disk.v1"
        }
        (argus_domain::PlatformId::NintendoSnes, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-snes.cartridge.v1"
        }
        (argus_domain::PlatformId::NintendoGb, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-gb.cartridge.v1"
        }
        (argus_domain::PlatformId::NintendoGbc, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-gbc.cartridge.v1"
        }
        (argus_domain::PlatformId::NintendoGba, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-gba.cartridge.v1"
        }
        (argus_domain::PlatformId::NintendoN64, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-n64.cartridge.v1"
        }
        (argus_domain::PlatformId::NintendoNds, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-nds.cartridge.v1"
        }
        (argus_domain::PlatformId::Nintendo3ds, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.nintendo-3ds.nocrypto-ncsd.v1"
        }
        (argus_domain::PlatformId::SegaSms, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.sega-sms.cartridge.v1"
        }
        (argus_domain::PlatformId::SegaGameGear, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.sega-gamegear.cartridge.v1"
        }
        (argus_domain::PlatformId::SegaGenesis, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.sega-genesis.cartridge.v1"
        }
        (argus_domain::PlatformId::Sega32x, argus_domain::ContentType::CartridgeImage) => {
            "argus.content.identity.sega-32x.cartridge.v1"
        }
        _ => return Err(PersistenceError::ConstraintViolation),
    };
    (derivation.identity().scheme_id() == expected && derivation.identity().revision() == 1)
        .then_some(())
        .ok_or(PersistenceError::ConstraintViolation)
}

fn ensure_source_association(
    transaction: &mut rusqlite::Transaction<'_>,
    derivation: &ValidatedContentDerivation,
    content_id: &str,
) -> Result<(), PersistenceError> {
    transaction
        .execute(
            "INSERT INTO game_content_source
                (game_content_source_id, game_content_id, source_entry_id, association_key,
                 source_fingerprint, last_observed_scan_id, is_current, created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, 1,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
             ON CONFLICT(game_content_id, source_entry_id, association_key)
             DO UPDATE SET source_fingerprint = excluded.source_fingerprint,
                           last_observed_scan_id = excluded.last_observed_scan_id,
                           is_current = 1,
                           updated_at = CURRENT_TIMESTAMP",
            rusqlite::params![
                content_id,
                derivation.source_entry_id().to_string(),
                derivation.association_key(),
                derivation.source_version().source_fingerprint(),
                derivation
                    .source_version()
                    .last_observed_scan_id()
                    .to_string(),
            ],
        )
        .map_err(map_persistence_operation_error)?;
    Ok(())
}

fn current_game_for_content(
    transaction: &mut rusqlite::Transaction<'_>,
    content_id: &str,
) -> Result<GameId, PersistenceError> {
    let raw: Option<String> = transaction
        .query_row(
            "SELECT game_id FROM game_membership
             WHERE game_content_id = ?1 AND is_current = 1
             ORDER BY CASE relationship WHEN 'primary' THEN 0 ELSE 1 END
             LIMIT 1",
            [content_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(map_persistence_operation_error)?;
    raw.map(parse_game_id)
        .transpose()
        .map_err(|_| PersistenceError::CorruptOrIncompatible)?
        .ok_or(PersistenceError::CorruptOrIncompatible)
}

fn refresh_content(
    transaction: &mut rusqlite::Transaction<'_>,
    content_id: &str,
) -> Result<(), PersistenceError> {
    transaction
        .execute(
            "UPDATE game_content
             SET presence_state = CASE
                 WHEN NOT EXISTS (
                     SELECT 1 FROM game_content_source
                     WHERE game_content_id = ?1 AND is_current = 1
                 ) THEN 'orphaned'
                 WHEN EXISTS (
                     SELECT 1
                     FROM game_content_source s
                     JOIN source_entry e ON e.source_entry_id = s.source_entry_id
                     JOIN library_root r ON r.library_root_id = e.library_root_id
                     WHERE s.game_content_id = ?1 AND s.is_current = 1
                       AND r.availability_status = 'available'
                 )
                 AND EXISTS (
                     SELECT 1
                     FROM game_content_source s
                     JOIN source_entry e ON e.source_entry_id = s.source_entry_id
                     JOIN library_root r ON r.library_root_id = e.library_root_id
                     WHERE s.game_content_id = ?1 AND s.is_current = 1
                       AND r.availability_status <> 'available'
                 ) THEN 'partially_unavailable'
                 WHEN EXISTS (
                     SELECT 1
                     FROM game_content_source s
                     JOIN source_entry e ON e.source_entry_id = s.source_entry_id
                     JOIN library_root r ON r.library_root_id = e.library_root_id
                     WHERE s.game_content_id = ?1 AND s.is_current = 1
                       AND r.availability_status = 'available'
                 ) THEN 'available'
                 ELSE 'unavailable'
             END,
             identification_state = CASE
                 WHEN EXISTS (
                     SELECT 1 FROM content_identity
                     WHERE game_content_id = ?1 AND is_current = 1
                 ) THEN 'identified'
                 ELSE 'needs_reidentification'
             END,
             updated_at = CURRENT_TIMESTAMP
             WHERE game_content_id = ?1",
            [content_id],
        )
        .map_err(map_persistence_operation_error)?;
    Ok(())
}

fn refresh_game(
    transaction: &mut rusqlite::Transaction<'_>,
    game_id: &str,
) -> Result<(), PersistenceError> {
    transaction
        .execute(
            "UPDATE game
             SET lifecycle_state = CASE
                 WHEN EXISTS (
                     SELECT 1
                     FROM game_membership m
                     JOIN game_content c ON c.game_content_id = m.game_content_id
                     WHERE m.game_id = ?1 AND m.is_current = 1
                       AND c.presence_state <> 'orphaned'
                 ) THEN 'active'
                 ELSE 'inactive_orphan'
             END,
             updated_at = CURRENT_TIMESTAMP
             WHERE game_id = ?1",
            [game_id],
        )
        .map_err(map_persistence_operation_error)?;
    transaction
        .execute(
            "UPDATE game_library_row
             SET hydration_state = (SELECT hydration_state FROM game WHERE game_id = ?1),
                 availability_state = CASE
                     WHEN NOT EXISTS (
                         SELECT 1 FROM game_membership m
                         JOIN game_content c ON c.game_content_id = m.game_content_id
                         WHERE m.game_id = ?1 AND m.is_current = 1
                           AND c.presence_state <> 'orphaned'
                     ) THEN 'inactive_orphan'
                     WHEN NOT EXISTS (
                         SELECT 1 FROM game_membership m
                         JOIN game_content c ON c.game_content_id = m.game_content_id
                         WHERE m.game_id = ?1 AND m.is_current = 1
                           AND c.presence_state IN ('partially_unavailable', 'unavailable')
                     ) THEN 'available'
                     WHEN EXISTS (
                         SELECT 1 FROM game_membership m
                         JOIN game_content c ON c.game_content_id = m.game_content_id
                         WHERE m.game_id = ?1 AND m.is_current = 1
                           AND c.presence_state = 'available'
                     ) THEN 'partially_unavailable'
                     ELSE 'unavailable'
                 END,
                 content_count = (
                     SELECT COUNT(*) FROM game_membership
                     WHERE game_id = ?1 AND is_current = 1
                 ),
                 source_count = (
                     SELECT COUNT(*)
                     FROM game_membership m
                     JOIN game_content_source s ON s.game_content_id = m.game_content_id
                     WHERE m.game_id = ?1 AND m.is_current = 1 AND s.is_current = 1
                 ),
                 updated_at = CURRENT_TIMESTAMP
             WHERE game_id = ?1",
            [game_id],
        )
        .map_err(map_persistence_operation_error)?;
    Ok(())
}

fn read_library_row(row: &Row<'_>) -> rusqlite::Result<GameLibraryRow> {
    Ok(GameLibraryRow::from_persisted(
        parse_game_id(row.get::<_, String>(0)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        row.get::<_, String>(1)?,
        parse_platform(&row.get::<_, String>(2)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        parse_hydration(&row.get::<_, String>(3)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        parse_availability(&row.get::<_, String>(4)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        row.get::<_, i64>(5)? as u32,
        row.get::<_, i64>(6)? as u32,
        row.get(7)?,
    ))
}

fn read_content_summary(row: &Row<'_>) -> rusqlite::Result<GameContentSummary> {
    let game_content_id = parse_game_content_id(row.get::<_, String>(0)?)
        .map_err(|_| rusqlite::Error::InvalidQuery)?;
    let identity_scheme: Option<String> = row.get(6)?;
    let identity_revision: Option<i64> = row.get(7)?;
    let identity_value: Option<String> = row.get(8)?;
    let proving_source_entry_id: Option<String> = row.get(9)?;
    let proving_association_key: Option<String> = row.get(10)?;
    let proving_fingerprint: Option<String> = row.get(11)?;
    let proving_scan_id: Option<String> = row.get(12)?;
    let identity = match (identity_scheme, identity_revision, identity_value) {
        (Some(scheme), Some(revision), Some(value)) => Some(ContentIdentitySummary::new(
            scheme,
            revision as u32,
            IdentityDigest::from_bytes(
                parse_digest(&value).map_err(|_| rusqlite::Error::InvalidQuery)?,
            ),
        )),
        (None, None, None) => None,
        _ => return Err(rusqlite::Error::InvalidQuery),
    };
    let provenance = match (
        proving_source_entry_id,
        proving_association_key,
        proving_scan_id,
    ) {
        (Some(source), Some(key), Some(scan)) => Some(ContentProvenanceSummary::new(
            parse_source_entry_id(source).map_err(|_| rusqlite::Error::InvalidQuery)?,
            key,
            proving_fingerprint,
            parse_scan_run_id(scan).map_err(|_| rusqlite::Error::InvalidQuery)?,
        )),
        (None, None, None) => None,
        _ => return Err(rusqlite::Error::InvalidQuery),
    };
    Ok(GameContentSummary::with_identity(
        game_content_id,
        parse_platform(&row.get::<_, String>(1)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        parse_content_type(&row.get::<_, String>(2)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        parse_presence(&row.get::<_, String>(3)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        parse_identification(&row.get::<_, String>(4)?)
            .map_err(|_| rusqlite::Error::InvalidQuery)?,
        row.get::<_, i64>(5)? as u32,
        identity,
        provenance,
    ))
}

fn resolve_redirect(
    transaction: &mut rusqlite::Transaction<'_>,
    requested: GameId,
) -> Result<(GameId, bool), PersistenceError> {
    let mut current = requested.to_string();
    let mut redirected = false;
    for _ in 0..64 {
        let next: Option<String> = transaction
            .query_row(
                "SELECT canonical_game_id FROM game_redirect WHERE game_id = ?1",
                [&current],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        let Some(next) = next else {
            return Ok((parse_game_id(current)?, redirected));
        };
        if next == current {
            return Err(PersistenceError::CorruptOrIncompatible);
        }
        current = next;
        redirected = true;
    }
    Err(PersistenceError::CorruptOrIncompatible)
}

fn parse_platform(value: &str) -> Result<PlatformId, PersistenceError> {
    PlatformId::try_from(value).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_content_type(value: &str) -> Result<ContentType, PersistenceError> {
    ContentType::try_from(value).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_presence(value: &str) -> Result<GameContentPresence, PersistenceError> {
    match value {
        "available" => Ok(GameContentPresence::Available),
        "partially_unavailable" => Ok(GameContentPresence::PartiallyUnavailable),
        "unavailable" => Ok(GameContentPresence::Unavailable),
        "orphaned" => Ok(GameContentPresence::Orphaned),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_identification(value: &str) -> Result<IdentificationState, PersistenceError> {
    match value {
        "identified" => Ok(IdentificationState::Identified),
        "needs_reidentification" => Ok(IdentificationState::NeedsReidentification),
        "unidentified" => Ok(IdentificationState::Unidentified),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_lifecycle(value: &str) -> Result<GameLifecycle, PersistenceError> {
    match value {
        "active" => Ok(GameLifecycle::Active),
        "inactive_orphan" => Ok(GameLifecycle::InactiveOrphan),
        "redirected" => Ok(GameLifecycle::Redirected),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_hydration(value: &str) -> Result<HydrationState, PersistenceError> {
    match value {
        "hydrated" => Ok(HydrationState::Hydrated),
        "partially_hydrated" => Ok(HydrationState::PartiallyHydrated),
        "unmatched" => Ok(HydrationState::Unmatched),
        "refreshing" => Ok(HydrationState::Refreshing),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_availability(value: &str) -> Result<argus_domain::AvailabilityState, PersistenceError> {
    match value {
        "available" => Ok(argus_domain::AvailabilityState::Available),
        "partially_unavailable" => Ok(argus_domain::AvailabilityState::PartiallyUnavailable),
        "unavailable" => Ok(argus_domain::AvailabilityState::Unavailable),
        "inactive_orphan" => Ok(argus_domain::AvailabilityState::InactiveOrphan),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_relationship(value: &str) -> Result<MembershipRelationship, PersistenceError> {
    match value {
        "primary" => Ok(MembershipRelationship::Primary),
        "secondary" => Ok(MembershipRelationship::Secondary),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_grouping_basis(value: &str) -> Result<GroupingBasis, PersistenceError> {
    match value {
        "exact_content_identity" => Ok(GroupingBasis::ExactContentIdentity),
        "provisional" => Ok(GroupingBasis::Provisional),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_game_content_id(value: String) -> Result<GameContentId, PersistenceError> {
    GameContentId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_game_id(value: String) -> Result<GameId, PersistenceError> {
    GameId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_source_entry_id(value: String) -> Result<SourceEntryId, PersistenceError> {
    SourceEntryId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn parse_scan_run_id(value: String) -> Result<ScanRunId, PersistenceError> {
    ScanRunId::try_from(value.as_str()).map_err(|_| PersistenceError::CorruptOrIncompatible)
}

fn digest_hex(digest: argus_application::IdentityDigest) -> String {
    digest
        .as_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn parse_digest(value: &str) -> Result<[u8; 32], ()> {
    if value.len() != 64 {
        return Err(());
    }
    let mut digest = [0_u8; 32];
    for (index, pair) in value.as_bytes().chunks_exact(2).enumerate() {
        let high = hex_digit(pair[0]).ok_or(())?;
        let low = hex_digit(pair[1]).ok_or(())?;
        digest[index] = high << 4 | low;
    }
    Ok(digest)
}

fn hex_digit(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

fn placeholders(count: usize) -> String {
    (1..=count)
        .map(|index| format!("?{index}"))
        .collect::<Vec<_>>()
        .join(", ")
}
