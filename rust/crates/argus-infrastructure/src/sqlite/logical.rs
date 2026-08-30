//! SQLite persistence for canonical content and the focused logical library.
//!
//! The repository deliberately accepts only already-validated derivations. It
//! performs cheap persisted-version checks and short SQL mutations; source
//! bytes, parsing, canonicalization, and hashing belong outside this write
//! transaction.

use std::collections::BTreeMap;

use argus_application::{
    AvailabilityStateFacetBucket, ContentIdentitySummary, ContentProvenanceMemberSummary,
    ContentProvenanceRole, ContentProvenanceSummary, ContentType, ConvergenceOutcome,
    GameContentId, GameContentPresence, GameContentSourceSummary, GameContentSummary, GameDetail,
    GameId, GameLibraryPage, GameLibraryRow, GameLifecycle, GameListCursor, GameMembershipSummary,
    GetGameResult, GroupingBasis, HydrationState, HydrationStateFacetBucket, IdentificationState,
    IdentityConvergenceStore, IdentityDigest, LibraryFacetQuery, LibraryFacets, LibraryFilter,
    LibraryRootId, LibraryScope, LibrarySort, LibrarySortDirection, LibrarySortField,
    ListGamesQuery, LogicalContentRepository, LogicalLibraryQueries, MembershipRelationship,
    PersistenceError, PlatformFacetBucket, PlatformId, RegionFacetBucket, ScanRunId, SourceEntryId,
    SourceVersionEvidence, SourceVersionKind, ValidatedContentDerivation, ValidatedM3uGrouping,
    bounded_library_display_title, bounded_library_release_date,
};
use rusqlite::{OptionalExtension, Row, params_from_iter, types::Value};

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
        let persisted: Option<(String, Option<String>, Option<String>, String)> = self
            .transaction()?
            .query_row(
                "SELECT coordinate_kind, source_fingerprint, derived_fingerprint,
                        last_observed_scan_id
                 FROM source_entry
                 WHERE source_entry_id = ?1",
                [evidence.source_entry_id().to_string()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        Ok(persisted
            .map(
                |(coordinate_kind, provider_fingerprint, derived_fingerprint, scan_id)| {
                    source_version_matches_values(
                        &coordinate_kind,
                        provider_fingerprint.as_deref(),
                        derived_fingerprint.as_deref(),
                        &scan_id,
                        evidence,
                    )
                },
            )
            .unwrap_or(false))
    }

    fn converge_identity(
        &mut self,
        derivation: &ValidatedContentDerivation,
    ) -> Result<ConvergenceOutcome, PersistenceError> {
        validate_scheme(derivation)?;

        let existing_source = existing_source_for_derivation(self.transaction()?, derivation)?;

        let identity = derivation.identity();
        let digest = digest_hex(identity.digest());
        let current_identity: Option<(String, String, i64)> = self
            .transaction()?
            .query_row(
                "SELECT content_identity_id, game_content_id, identity_revision
                 FROM content_identity
                 WHERE scheme_id = ?1
                   AND identity_value = ?2
                   AND is_current = 1",
                rusqlite::params![identity.scheme_id(), digest],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;

        if let Some((_identity_id, raw_content_id, persisted_revision)) = current_identity {
            if persisted_revision != i64::from(identity.revision()) {
                return Err(PersistenceError::Conflict);
            }
            let content_id = parse_game_content_id(raw_content_id.clone())?;
            if existing_source
                .iter()
                .any(|source| source != &raw_content_id)
            {
                return Err(PersistenceError::Conflict);
            }

            let game_id = current_game_for_content(self.transaction()?, &raw_content_id)?;
            ensure_source_associations(self.transaction()?, derivation, &raw_content_id)?;
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
            if existing_source
                .iter()
                .any(|source| source != raw_content_id)
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
                     proving_derived_fingerprint = ?4,
                     proving_scan_run_id = ?5,
                     updated_at = CURRENT_TIMESTAMP
                 WHERE content_identity_id = ?6
                   AND is_current = 0",
                    rusqlite::params![
                        derivation.source_entry_id().to_string(),
                        derivation.association_key(),
                        derivation.source_version().source_fingerprint(),
                        derivation
                            .source_version()
                            .derived_fingerprint()
                            .map(|value| value.as_transformation_value()),
                        derivation
                            .source_version()
                            .last_observed_scan_id()
                            .to_string(),
                        identity_id,
                    ],
                )
                .map_err(map_persistence_operation_error)?;
            update_identity_provenance(self.transaction()?, identity_id, derivation, true)?;
            ensure_source_associations(self.transaction()?, derivation, raw_content_id)?;
            refresh_content(self.transaction()?, raw_content_id)?;
            refresh_game(self.transaction()?, &game_id.to_string())?;
            return Ok(ConvergenceOutcome::Attached {
                game_content_id: content_id,
                game_id,
            });
        }

        if !existing_source.is_empty() {
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

        let identity_id: String = self
            .transaction()?
            .query_row(
                "INSERT INTO content_identity
                    (content_identity_id, game_content_id, scheme_id, identity_revision,
                     identity_value, is_current, proving_source_entry_id,
                     proving_association_key, proving_source_fingerprint,
                     proving_derived_fingerprint, proving_scan_run_id,
                     created_at, updated_at)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, 1, ?5, ?6, ?7, ?8, ?9,
                     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                 RETURNING content_identity_id",
                rusqlite::params![
                    raw_content_id,
                    identity.scheme_id(),
                    i64::from(identity.revision()),
                    digest,
                    derivation.source_entry_id().to_string(),
                    derivation
                        .provenance()
                        .first()
                        .and_then(|member| member.association_key()),
                    derivation.source_version().source_fingerprint(),
                    derivation
                        .source_version()
                        .derived_fingerprint()
                        .map(|value| value.as_transformation_value()),
                    derivation
                        .source_version()
                        .last_observed_scan_id()
                        .to_string(),
                ],
                |row| row.get(0),
            )
            .map_err(map_persistence_operation_error)?;
        update_identity_provenance(self.transaction()?, &identity_id, derivation, true)?;
        ensure_source_associations(self.transaction()?, derivation, &raw_content_id)?;
        self.transaction()?
            .execute(
                "INSERT INTO game_membership
                (game_membership_id, game_id, game_content_id, relationship,
                 grouping_basis, grouping_revision, is_current, created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, ?2, 'primary_content', 'provisional', 1, 1,
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

        // The legacy insert above keeps the creation path compatible with
        // existing identity tests; immediately derive every v15 projection
        // field, including search text and resolved presentation facts.
        refresh_game_library_projection(self.transaction()?, &raw_game_id)?;

        Ok(ConvergenceOutcome::Created {
            game_content_id: parse_game_content_id(raw_content_id)?,
            game_id: parse_game_id(raw_game_id)?,
        })
    }
}

impl LogicalLibraryQueries for SqliteLogicalContentRepository<'_, '_> {
    fn list_games(&mut self, query: &ListGamesQuery) -> Result<GameLibraryPage, PersistenceError> {
        let mut sql = String::from(
            "SELECT r.game_id, r.display_title, r.platform_id,
                    r.presentation_region, r.selected_cover_asset_id,
                    r.release_date, r.hydration_state, r.availability_state,
                    r.content_count, r.source_count,
                    COALESCE(CAST(strftime('%s', r.updated_at) AS INTEGER) * 1000,
                             CAST(r.updated_at AS INTEGER) * 1000, 0)
             FROM game_library_row r
             CROSS JOIN game g ON g.game_id = r.game_id
             WHERE g.lifecycle_state = 'active'
               AND NOT EXISTS (
                   SELECT 1 FROM game_redirect redirect
                   WHERE redirect.game_id = r.game_id
               )",
        );
        let mut values = Vec::<Value>::new();
        append_library_scope(&mut sql, &mut values, query.scope());
        append_library_filters(&mut sql, &mut values, query.filters());
        if let Some(search) = query.search() {
            sql.push_str(" AND r.search_text LIKE ? ESCAPE '\\'");
            values.push(Value::Text(format!("%{}%", escape_like(search))));
        }
        if let Some(cursor) = query.cursor() {
            append_cursor_predicate(&mut sql, &mut values, query, cursor);
        }
        append_ordering(&mut sql, query.sort());
        sql.push_str(" LIMIT ?");
        values.push(Value::Integer(i64::from(query.page_size()) + 1));

        let mut rows = Vec::new();
        let params = params_from_iter(values);
        let mut statement = self
            .transaction()?
            .prepare(&sql)
            .map_err(map_persistence_operation_error)?;
        let mapped = statement
            .query_map(params, read_library_row)
            .map_err(map_persistence_operation_error)?;
        rows.extend(
            mapped
                .map(|row| row.map_err(map_persistence_operation_error))
                .collect::<Result<Vec<_>, _>>()?,
        );
        let has_more = rows.len() > query.page_size() as usize;
        if has_more {
            rows.truncate(query.page_size() as usize);
        }
        let next_cursor = has_more
            .then(|| {
                let row = rows.last().expect("a page with more rows has a last row");
                GameListCursor::from_query_position(
                    query,
                    row.display_title(),
                    row.platform_id(),
                    row.release_date_for_cursor(),
                    row.updated_at_ms(),
                    row.game_id(),
                )
                .map_err(|_| PersistenceError::CorruptOrIncompatible)
            })
            .transpose()?;
        Ok(GameLibraryPage::new(rows, next_cursor))
    }

    fn get_library_facets(
        &mut self,
        query: &LibraryFacetQuery,
    ) -> Result<LibraryFacets, PersistenceError> {
        let platforms = read_platform_facets(self.transaction()?, query)?;
        let regions = read_region_facets(self.transaction()?, query)?;
        let hydration_states = read_hydration_facets(self.transaction()?, query)?;
        let availability_states = read_availability_facets(self.transaction()?, query)?;
        Ok(LibraryFacets::new(
            platforms,
            regions,
            hydration_states,
            availability_states,
        ))
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
                 ORDER BY CASE relationship WHEN 'primary_content' THEN 0 ELSE 1 END,
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
            let summaries = {
                let mut statement = self.transaction()?.prepare(
                    "SELECT gc.game_content_id, gc.platform_id, gc.content_type,
                            gc.presence_state, gc.identification_state,
                            COUNT(DISTINCT CASE WHEN gcs.is_current = 1 THEN gcs.game_content_source_id END),
                            ci.scheme_id, ci.identity_revision, ci.identity_value,
                            ci.proving_source_entry_id, ci.proving_association_key,
                            ci.proving_source_fingerprint, ci.proving_derived_fingerprint,
                            ci.proving_scan_run_id,
                            (SELECT coordinate_kind
                             FROM source_entry
                             WHERE source_entry_id = ci.proving_source_entry_id)
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
                mapped
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(map_logical_read_error)?
            };
            let content_ids = summaries
                .iter()
                .map(|summary| summary.game_content_id().to_string())
                .collect::<Vec<_>>();
            let provenances = read_normalized_provenance_batch(self.transaction()?, &content_ids)?;
            let sources = read_content_sources_batch(self.transaction()?, &content_ids)?;

            summaries
                .into_iter()
                .map(|summary| {
                    let content_id = summary.game_content_id().to_string();
                    let summary = match provenances.get(&content_id).cloned().flatten() {
                        Some(provenance) => GameContentSummary::with_identity(
                            summary.game_content_id(),
                            summary.platform_id(),
                            summary.content_type(),
                            summary.presence(),
                            summary.identification(),
                            summary.source_count(),
                            summary.identity().cloned(),
                            Some(provenance),
                        ),
                        None => summary,
                    };
                    summary.with_sources(sources.get(&content_id).cloned().unwrap_or_default())
                })
                .collect()
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

fn append_library_scope(sql: &mut String, values: &mut Vec<Value>, scope: LibraryScope) {
    match scope {
        LibraryScope::All => {}
        LibraryScope::Platform(platform) => {
            sql.push_str(" AND r.platform_id = ?");
            values.push(Value::Text(platform.as_str().to_owned()));
        }
        LibraryScope::Source(source) => {
            sql.push_str(
                " AND EXISTS (
                    SELECT 1
                    FROM game_membership scoped_membership
                    JOIN game_content_source scoped_source
                      ON scoped_source.game_content_id = scoped_membership.game_content_id
                    JOIN source_entry scoped_entry
                      ON scoped_entry.source_entry_id = scoped_source.source_entry_id
                    JOIN library_root scoped_root
                      ON scoped_root.library_root_id = scoped_entry.library_root_id
                    WHERE scoped_membership.game_id = r.game_id
                      AND scoped_membership.is_current = 1
                      AND scoped_source.is_current = 1
                      AND scoped_root.library_source_id = ?
                )",
            );
            values.push(Value::Text(source.to_string()));
        }
        LibraryScope::LibraryRoot(root) => {
            sql.push_str(
                " AND EXISTS (
                    SELECT 1
                    FROM game_membership scoped_membership
                    JOIN game_content_source scoped_source
                      ON scoped_source.game_content_id = scoped_membership.game_content_id
                    JOIN source_entry scoped_entry
                      ON scoped_entry.source_entry_id = scoped_source.source_entry_id
                    WHERE scoped_membership.game_id = r.game_id
                      AND scoped_membership.is_current = 1
                      AND scoped_source.is_current = 1
                      AND scoped_entry.library_root_id = ?
                )",
            );
            values.push(Value::Text(root.to_string()));
        }
    }
}

fn append_library_filters(sql: &mut String, values: &mut Vec<Value>, filters: &LibraryFilter) {
    append_platform_filter(sql, values, filters.platform_ids());
    append_string_filter(sql, values, "r.presentation_region", filters.regions());
    append_state_filter(
        sql,
        values,
        "r.hydration_state",
        filters
            .hydration_states()
            .iter()
            .copied()
            .map(hydration_value),
    );
    append_state_filter(
        sql,
        values,
        "r.availability_state",
        filters
            .availability_states()
            .iter()
            .copied()
            .map(availability_value),
    );
}

fn append_platform_filter(sql: &mut String, values: &mut Vec<Value>, platforms: &[PlatformId]) {
    if platforms.is_empty() {
        return;
    }
    sql.push_str(" AND r.platform_id IN (");
    sql.push_str(&placeholders(platforms.len()));
    sql.push(')');
    values.extend(
        platforms
            .iter()
            .map(|platform| Value::Text(platform.as_str().to_owned())),
    );
}

fn append_string_filter(
    sql: &mut String,
    values: &mut Vec<Value>,
    column: &str,
    values_to_match: &[String],
) {
    if values_to_match.is_empty() {
        return;
    }
    sql.push_str(" AND ");
    sql.push_str(column);
    sql.push_str(" IN (");
    sql.push_str(&placeholders(values_to_match.len()));
    sql.push(')');
    values.extend(values_to_match.iter().cloned().map(Value::Text));
}

fn append_state_filter<I>(sql: &mut String, values: &mut Vec<Value>, column: &str, states: I)
where
    I: IntoIterator<Item = &'static str>,
{
    let states = states.into_iter().collect::<Vec<_>>();
    if states.is_empty() {
        return;
    }
    sql.push_str(" AND ");
    sql.push_str(column);
    sql.push_str(" IN (");
    sql.push_str(&placeholders(states.len()));
    sql.push(')');
    values.extend(
        states
            .into_iter()
            .map(|state| Value::Text(state.to_owned())),
    );
}

fn append_cursor_predicate(
    sql: &mut String,
    values: &mut Vec<Value>,
    query: &ListGamesQuery,
    cursor: &GameListCursor,
) {
    let ascending = query.sort().direction() == LibrarySortDirection::Ascending;
    let operator = if ascending { ">" } else { "<" };

    if cursor.as_str().starts_with("v1:") {
        sql.push_str(
            " AND (r.display_title COLLATE NOCASE > ?
                   OR (r.display_title COLLATE NOCASE = ? AND r.game_id > ?))",
        );
        values.push(Value::Text(cursor.display_title().to_owned()));
        values.push(Value::Text(cursor.display_title().to_owned()));
        values.push(Value::Text(cursor.game_id().to_string()));
        return;
    }

    match query.sort().field() {
        LibrarySortField::DisplayTitle => {
            sql.push_str(" AND (");
            append_title_game_predicate(sql, values, cursor, operator);
            sql.push(')');
        }
        LibrarySortField::Platform => {
            sql.push_str(" AND (r.platform_id ");
            sql.push_str(operator);
            sql.push_str(" ? OR (r.platform_id = ? AND (");
            values.push(Value::Text(cursor.platform_id().as_str().to_owned()));
            values.push(Value::Text(cursor.platform_id().as_str().to_owned()));
            append_title_game_predicate(sql, values, cursor, operator);
            sql.push_str(")))");
        }
        LibrarySortField::ReleaseDate => {
            sql.push_str(" AND (");
            let cursor_rank = if cursor.release_date().is_some() {
                0
            } else {
                1
            };
            sql.push_str("CASE WHEN r.release_date IS NULL THEN 1 ELSE 0 END > ?");
            values.push(Value::Integer(cursor_rank));
            sql.push_str(" OR (CASE WHEN r.release_date IS NULL THEN 1 ELSE 0 END = ? AND ");
            values.push(Value::Integer(cursor_rank));
            if let Some(release_date) = cursor.release_date() {
                sql.push_str("(r.release_date ");
                sql.push_str(operator);
                sql.push_str(" ? OR (r.release_date = ? AND ");
                values.push(Value::Text(release_date.to_owned()));
                values.push(Value::Text(release_date.to_owned()));
                append_title_platform_game_predicate(sql, values, cursor, operator);
                sql.push_str("))");
            } else {
                append_title_platform_game_predicate(sql, values, cursor, operator);
            }
            sql.push(')');
            sql.push(')');
        }
        LibrarySortField::UpdatedAt => {
            let expression = updated_at_expression();
            sql.push_str(" AND (");
            sql.push_str(expression);
            sql.push(' ');
            sql.push_str(operator);
            sql.push_str(" ? OR (");
            sql.push_str(expression);
            sql.push_str(" = ? AND ");
            values.push(Value::Integer(cursor.updated_at_ms()));
            values.push(Value::Integer(cursor.updated_at_ms()));
            append_title_platform_game_predicate(sql, values, cursor, operator);
            sql.push_str("))");
        }
    }
}

fn append_title_game_predicate(
    sql: &mut String,
    values: &mut Vec<Value>,
    cursor: &GameListCursor,
    operator: &str,
) {
    sql.push_str("r.display_title COLLATE NOCASE ");
    sql.push_str(operator);
    sql.push_str(" ? OR (r.display_title COLLATE NOCASE = ? AND r.game_id ");
    sql.push_str(operator);
    sql.push_str(" ?)");
    values.push(Value::Text(cursor.display_title().to_owned()));
    values.push(Value::Text(cursor.display_title().to_owned()));
    values.push(Value::Text(cursor.game_id().to_string()));
}

fn append_title_platform_game_predicate(
    sql: &mut String,
    values: &mut Vec<Value>,
    cursor: &GameListCursor,
    operator: &str,
) {
    sql.push_str("r.display_title COLLATE NOCASE ");
    sql.push_str(operator);
    sql.push_str(" ? OR (r.display_title COLLATE NOCASE = ? AND (");
    values.push(Value::Text(cursor.display_title().to_owned()));
    values.push(Value::Text(cursor.display_title().to_owned()));
    sql.push_str("r.platform_id ");
    sql.push_str(operator);
    sql.push_str(" ? OR (r.platform_id = ? AND r.game_id ");
    sql.push_str(operator);
    sql.push_str(" ?)))");
    values.push(Value::Text(cursor.platform_id().as_str().to_owned()));
    values.push(Value::Text(cursor.platform_id().as_str().to_owned()));
    values.push(Value::Text(cursor.game_id().to_string()));
}

fn append_ordering(sql: &mut String, sort: LibrarySort) {
    let direction = match sort.direction() {
        LibrarySortDirection::Ascending => "ASC",
        LibrarySortDirection::Descending => "DESC",
    };
    match sort.field() {
        LibrarySortField::DisplayTitle => sql.push_str(&format!(
            " ORDER BY r.display_title COLLATE NOCASE {direction},
                      r.game_id {direction}"
        )),
        LibrarySortField::Platform => sql.push_str(&format!(
            " ORDER BY r.platform_id {direction},
                      r.display_title COLLATE NOCASE {direction}, r.game_id {direction}"
        )),
        LibrarySortField::ReleaseDate => sql.push_str(&format!(
            " ORDER BY CASE WHEN r.release_date IS NULL THEN 1 ELSE 0 END ASC,
                      r.release_date {direction}, r.display_title COLLATE NOCASE {direction},
                      r.platform_id {direction}, r.game_id {direction}"
        )),
        LibrarySortField::UpdatedAt => {
            let expression = updated_at_expression();
            sql.push_str(&format!(
                " ORDER BY {expression} {direction},
                          r.display_title COLLATE NOCASE {direction},
                          r.platform_id {direction}, r.game_id {direction}"
            ));
        }
    }
}

fn updated_at_expression() -> &'static str {
    "COALESCE(CAST(strftime('%s', r.updated_at) AS INTEGER) * 1000,
              CAST(r.updated_at AS INTEGER) * 1000, 0)"
}

fn escape_like(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn hydration_value(value: HydrationState) -> &'static str {
    match value {
        HydrationState::Hydrated => "hydrated",
        HydrationState::PartiallyHydrated => "partially_hydrated",
        HydrationState::Unmatched => "unmatched",
        HydrationState::Refreshing => "refreshing",
    }
}

fn availability_value(value: argus_application::AvailabilityState) -> &'static str {
    match value {
        argus_application::AvailabilityState::Available => "available",
        argus_application::AvailabilityState::PartiallyUnavailable => "partially_unavailable",
        argus_application::AvailabilityState::Unavailable => "unavailable",
        argus_application::AvailabilityState::InactiveOrphan => "inactive_orphan",
    }
}

#[derive(Clone, Copy)]
enum FacetCategory {
    Platform,
    Region,
    Hydration,
    Availability,
}

struct FacetQueryParts {
    from_where: String,
    values: Vec<Value>,
}

fn facet_query_parts(query: &LibraryFacetQuery, omitted: FacetCategory) -> FacetQueryParts {
    let mut from_where = String::from(
        "FROM game_library_row r
         CROSS JOIN game g ON g.game_id = r.game_id
         WHERE g.lifecycle_state = 'active'
           AND NOT EXISTS (
               SELECT 1 FROM game_redirect redirect
               WHERE redirect.game_id = r.game_id
           )",
    );
    let mut values = Vec::new();
    append_library_scope(&mut from_where, &mut values, query.scope());
    if let Some(search) = query.search() {
        from_where.push_str(" AND r.search_text LIKE ? ESCAPE '\\'");
        values.push(Value::Text(format!("%{}%", escape_like(search))));
    }
    let filters = query.filters();
    if !matches!(omitted, FacetCategory::Platform) {
        append_platform_filter(&mut from_where, &mut values, filters.platform_ids());
    }
    if !matches!(omitted, FacetCategory::Region) {
        append_string_filter(
            &mut from_where,
            &mut values,
            "r.presentation_region",
            filters.regions(),
        );
    }
    if !matches!(omitted, FacetCategory::Hydration) {
        append_state_filter(
            &mut from_where,
            &mut values,
            "r.hydration_state",
            filters
                .hydration_states()
                .iter()
                .copied()
                .map(hydration_value),
        );
    }
    if !matches!(omitted, FacetCategory::Availability) {
        append_state_filter(
            &mut from_where,
            &mut values,
            "r.availability_state",
            filters
                .availability_states()
                .iter()
                .copied()
                .map(availability_value),
        );
    }
    FacetQueryParts { from_where, values }
}

fn read_platform_facets(
    transaction: &mut rusqlite::Transaction<'_>,
    query: &LibraryFacetQuery,
) -> Result<Vec<PlatformFacetBucket>, PersistenceError> {
    let parts = facet_query_parts(query, FacetCategory::Platform);
    let sql = format!(
        "SELECT r.platform_id, COUNT(*) {} GROUP BY r.platform_id",
        parts.from_where
    );
    let mut statement = transaction
        .prepare(&sql)
        .map_err(map_persistence_operation_error)?;
    let rows = statement
        .query_map(params_from_iter(parts.values), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })
        .map_err(map_persistence_operation_error)?;
    let mut result = rows
        .map(|row| {
            let (platform, count) = row.map_err(map_persistence_operation_error)?;
            Ok(PlatformFacetBucket::new(
                parse_platform(&platform)?,
                u32::try_from(count).map_err(|_| PersistenceError::CorruptOrIncompatible)?,
            ))
        })
        .collect::<Result<Vec<_>, PersistenceError>>()?;
    result.sort_by_key(|bucket| bucket.platform_id());
    Ok(result)
}

fn read_region_facets(
    transaction: &mut rusqlite::Transaction<'_>,
    query: &LibraryFacetQuery,
) -> Result<Vec<RegionFacetBucket>, PersistenceError> {
    let mut parts = facet_query_parts(query, FacetCategory::Region);
    parts
        .from_where
        .push_str(" AND r.presentation_region IS NOT NULL");
    let sql = format!(
        "SELECT r.presentation_region, COUNT(*) {} GROUP BY r.presentation_region ORDER BY r.presentation_region ASC",
        parts.from_where
    );
    let mut statement = transaction
        .prepare(&sql)
        .map_err(map_persistence_operation_error)?;
    let rows = statement
        .query_map(params_from_iter(parts.values), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })
        .map_err(map_persistence_operation_error)?;
    rows.map(|row| {
        let (region, count) = row.map_err(map_persistence_operation_error)?;
        Ok(RegionFacetBucket::new(
            region,
            u32::try_from(count).map_err(|_| PersistenceError::CorruptOrIncompatible)?,
        ))
    })
    .collect()
}

fn read_hydration_facets(
    transaction: &mut rusqlite::Transaction<'_>,
    query: &LibraryFacetQuery,
) -> Result<Vec<HydrationStateFacetBucket>, PersistenceError> {
    let parts = facet_query_parts(query, FacetCategory::Hydration);
    let sql = format!(
        "SELECT r.hydration_state, COUNT(*) {} GROUP BY r.hydration_state",
        parts.from_where
    );
    let mut statement = transaction
        .prepare(&sql)
        .map_err(map_persistence_operation_error)?;
    let rows = statement
        .query_map(params_from_iter(parts.values), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })
        .map_err(map_persistence_operation_error)?;
    let mut result = rows
        .map(|row| {
            let (state, count) = row.map_err(map_persistence_operation_error)?;
            Ok(HydrationStateFacetBucket::new(
                parse_hydration(&state)?,
                u32::try_from(count).map_err(|_| PersistenceError::CorruptOrIncompatible)?,
            ))
        })
        .collect::<Result<Vec<_>, PersistenceError>>()?;
    result.sort_by_key(|bucket| hydration_facet_sort_key(bucket.hydration_state()));
    Ok(result)
}

fn read_availability_facets(
    transaction: &mut rusqlite::Transaction<'_>,
    query: &LibraryFacetQuery,
) -> Result<Vec<AvailabilityStateFacetBucket>, PersistenceError> {
    let parts = facet_query_parts(query, FacetCategory::Availability);
    let sql = format!(
        "SELECT r.availability_state, COUNT(*) {} GROUP BY r.availability_state",
        parts.from_where
    );
    let mut statement = transaction
        .prepare(&sql)
        .map_err(map_persistence_operation_error)?;
    let rows = statement
        .query_map(params_from_iter(parts.values), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })
        .map_err(map_persistence_operation_error)?;
    let mut result = rows
        .map(|row| {
            let (state, count) = row.map_err(map_persistence_operation_error)?;
            Ok(AvailabilityStateFacetBucket::new(
                parse_availability(&state)?,
                u32::try_from(count).map_err(|_| PersistenceError::CorruptOrIncompatible)?,
            ))
        })
        .collect::<Result<Vec<_>, PersistenceError>>()?;
    result.sort_by_key(|bucket| availability_facet_sort_key(bucket.availability_state()));
    Ok(result)
}

fn hydration_facet_sort_key(value: HydrationState) -> u8 {
    match value {
        HydrationState::Hydrated => 0,
        HydrationState::PartiallyHydrated => 1,
        HydrationState::Unmatched => 2,
        HydrationState::Refreshing => 3,
    }
}

fn availability_facet_sort_key(value: argus_application::AvailabilityState) -> u8 {
    match value {
        argus_application::AvailabilityState::Available => 0,
        argus_application::AvailabilityState::PartiallyUnavailable => 1,
        argus_application::AvailabilityState::Unavailable => 2,
        argus_application::AvailabilityState::InactiveOrphan => 3,
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
        release_grouping_evidence_for_sources(self.transaction()?, &ids)?;
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
                   AND (
                       EXISTS (
                           SELECT 1
                           FROM content_identity_provenance p
                           WHERE p.content_identity_id = content_identity.content_identity_id
                             AND p.identity_is_current = 1
                             AND NOT EXISTS (
                                 SELECT 1
                                 FROM game_content_source s
                                 WHERE s.game_content_id = content_identity.game_content_id
                                   AND s.source_entry_id = p.source_entry_id
                                   AND s.association_key = COALESCE(p.association_key, '')
                                   AND s.is_current = 1
                             )
                       )
                       OR (
                           NOT EXISTS (
                               SELECT 1 FROM content_identity_provenance p
                               WHERE p.content_identity_id = content_identity.content_identity_id
                           )
                           AND NOT EXISTS (
                               SELECT 1
                               FROM game_content_source s
                               WHERE s.game_content_id = content_identity.game_content_id
                                 AND s.is_current = 1
                                 AND s.source_entry_id = content_identity.proving_source_entry_id
                                 AND (content_identity.proving_association_key IS NULL
                                      OR s.association_key = content_identity.proving_association_key)
                           )
                       )
                   )",
                    [content_id],
                )
                .map_err(map_persistence_operation_error)?;
            self.transaction()?
                .execute(
                    "UPDATE content_identity_provenance
                     SET identity_is_current = 0, updated_at = CURRENT_TIMESTAMP
                     WHERE content_identity_id IN (
                         SELECT content_identity_id FROM content_identity
                         WHERE game_content_id = ?1 AND is_current = 0
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

    fn apply_m3u_grouping(
        &mut self,
        grouping: &ValidatedM3uGrouping,
    ) -> Result<GameId, PersistenceError> {
        apply_m3u_grouping_transaction(self.transaction()?, grouping)
    }

    fn reconcile_m3u_grouping_evidence(
        &mut self,
        active_playlist_source_ids: &[SourceEntryId],
    ) -> Result<(), PersistenceError> {
        let active: std::collections::BTreeSet<String> = active_playlist_source_ids
            .iter()
            .map(ToString::to_string)
            .collect();
        let playlist_ids: Vec<String> = {
            let mut statement = self
                .transaction()?
                .prepare(
                    "SELECT DISTINCT playlist_source_entry_id
                     FROM grouping_evidence
                     WHERE is_current = 1",
                )
                .map_err(map_persistence_operation_error)?;
            let rows = statement
                .query_map([], |row| row.get(0))
                .map_err(map_persistence_operation_error)?;
            rows.collect::<Result<Vec<_>, _>>()
                .map_err(map_persistence_operation_error)?
        };
        for playlist_id in playlist_ids {
            if !active.contains(&playlist_id) {
                release_playlist_evidence(self.transaction()?, &playlist_id, &[])?;
            }
        }
        Ok(())
    }
}

fn apply_m3u_grouping_transaction(
    transaction: &mut rusqlite::Transaction<'_>,
    grouping: &ValidatedM3uGrouping,
) -> Result<GameId, PersistenceError> {
    let playlist_evidence = grouping.playlist_source_version();
    if !source_version_matches_transaction(transaction, playlist_evidence)? {
        return Err(PersistenceError::Conflict);
    }
    for member in grouping.members() {
        if !source_version_matches_transaction(transaction, member.source_version())? {
            return Err(PersistenceError::Conflict);
        }
    }

    let playlist_id = playlist_evidence.source_entry_id().to_string();
    let member_ids: Vec<String> = grouping
        .members()
        .iter()
        .map(|member| member.game_content_id().to_string())
        .collect();
    let mut platform = None;
    let mut current_games = Vec::new();
    for member in grouping.members() {
        let content_id = member.game_content_id().to_string();
        let content: Option<(String, String, String)> = transaction
            .query_row(
                "SELECT platform_id, content_type, identification_state
                 FROM game_content
                 WHERE game_content_id = ?1",
                [&content_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        let Some((content_platform, content_type, identification_state)) = content else {
            return Err(PersistenceError::Conflict);
        };
        if identification_state != "identified"
            || !matches!(
                content_type.as_str(),
                "OpticalDiscCd"
                    | "OpticalDiscGd"
                    | "OpticalDiscDvd"
                    | "OpticalDiscGameCube"
                    | "OpticalDiscWii"
                    | "OpticalDiscUmd"
            )
        {
            return Err(PersistenceError::ConstraintViolation);
        }
        if let Some(expected) = &platform {
            if expected != &content_platform {
                return Err(PersistenceError::Conflict);
            }
        } else {
            platform = Some(content_platform);
        }
        let source_association: Option<i64> = transaction
            .query_row(
                "SELECT 1
                 FROM game_content_source
                 WHERE game_content_id = ?1 AND source_entry_id = ?2 AND is_current = 1
                 LIMIT 1",
                rusqlite::params![
                    content_id,
                    member.source_version().source_entry_id().to_string()
                ],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        if source_association.is_none() {
            return Err(PersistenceError::Conflict);
        }
        let overlapping_playlist: Option<String> = transaction
            .query_row(
                "SELECT e.playlist_source_entry_id
                 FROM grouping_evidence_member m
                 JOIN grouping_evidence e
                   ON e.grouping_evidence_id = m.grouping_evidence_id
                 WHERE m.member_game_content_id = ?1
                   AND e.is_current = 1
                   AND e.playlist_source_entry_id <> ?2
                 LIMIT 1",
                [&content_id, &playlist_id],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_operation_error)?;
        if overlapping_playlist.is_some() {
            return Err(PersistenceError::Conflict);
        }
        let game_id: String = transaction
            .query_row(
                "SELECT game_id
                 FROM game_membership
                 WHERE game_content_id = ?1 AND is_current = 1
                 LIMIT 1",
                [&content_id],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_persistence_operation_error)?
            .ok_or(PersistenceError::Conflict)?;
        if !current_games.iter().any(|candidate| candidate == &game_id) {
            current_games.push(game_id);
        }
    }

    release_playlist_evidence(transaction, &playlist_id, &member_ids)?;

    let game_placeholders = placeholders(current_games.len());
    let survivor: String = transaction
        .query_row(
            &format!(
                "SELECT g.game_id
                 FROM game g
                 JOIN game_membership m ON m.game_id = g.game_id
                 WHERE m.is_current = 1
                   AND m.game_id IN ({game_placeholders})
                 GROUP BY g.game_id
                 ORDER BY MIN(g.created_at) ASC, g.game_id ASC
                 LIMIT 1"
            ),
            params_from_iter(current_games.iter()),
            |row| row.get(0),
        )
        .map_err(map_persistence_operation_error)?;
    let next_revision: i64 = transaction
        .query_row(
            "SELECT grouping_revision FROM game WHERE game_id = ?1",
            [&survivor],
            |row| row.get::<_, i64>(0),
        )
        .map_err(map_persistence_operation_error)?
        .checked_add(1)
        .ok_or(PersistenceError::Conflict)?;

    let existing_memberships: Vec<(String, String, String)> = {
        let sql = format!(
            "SELECT game_content_id, relationship, grouping_basis
             FROM game_membership
             WHERE is_current = 1 AND game_id IN ({game_placeholders})"
        );
        let mut statement = transaction
            .prepare(&sql)
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(params_from_iter(current_games.iter()), |row| {
                Ok((row.get(0)?, row.get(1)?, row.get(2)?))
            })
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    transaction
        .execute(
            &format!(
                "UPDATE game_membership
                 SET is_current = 0, updated_at = CURRENT_TIMESTAMP
                 WHERE is_current = 1 AND game_id IN ({game_placeholders})"
            ),
            params_from_iter(current_games.iter()),
        )
        .map_err(map_persistence_operation_error)?;
    transaction
        .execute(
            "UPDATE game
             SET grouping_revision = ?1, updated_at = CURRENT_TIMESTAMP
             WHERE game_id = ?2",
            rusqlite::params![next_revision, survivor],
        )
        .map_err(map_persistence_operation_error)?;

    let mut inserted = std::collections::BTreeSet::new();
    for (content_id, relationship, grouping_basis) in existing_memberships {
        if member_ids.iter().any(|member| member == &content_id) {
            continue;
        }
        let relationship = if relationship == "primary_content" {
            "equivalent_release_representation"
        } else {
            relationship.as_str()
        };
        if !inserted.insert((content_id.clone(), relationship.to_owned())) {
            continue;
        }
        upsert_current_membership(
            transaction,
            &survivor,
            &content_id,
            relationship,
            &grouping_basis,
            next_revision,
        )?;
    }
    for (ordinal, member) in grouping.members().iter().enumerate() {
        let relationship = if ordinal == 0 {
            "primary_content"
        } else {
            "disc"
        };
        upsert_current_membership(
            transaction,
            &survivor,
            &member.game_content_id().to_string(),
            relationship,
            "explicit_relationship_evidence",
            next_revision,
        )?;
    }

    for game_id in &current_games {
        if game_id == &survivor {
            continue;
        }
        transaction
            .execute(
                "INSERT INTO game_redirect (game_id, canonical_game_id, created_at)
                 VALUES (?1, ?2, CURRENT_TIMESTAMP)
                 ON CONFLICT(game_id) DO UPDATE SET
                   canonical_game_id = excluded.canonical_game_id",
                rusqlite::params![game_id, survivor],
            )
            .map_err(map_persistence_operation_error)?;
        transaction
            .execute(
                "UPDATE game SET lifecycle_state = 'redirected', updated_at = CURRENT_TIMESTAMP
                 WHERE game_id = ?1",
                [game_id],
            )
            .map_err(map_persistence_operation_error)?;
    }
    refresh_game(transaction, &survivor)?;

    let evidence_id: String = transaction
        .query_row(
            "INSERT INTO grouping_evidence
                (grouping_evidence_id, evidence_kind, playlist_source_entry_id,
                 source_fingerprint, derived_fingerprint, last_observed_scan_id, is_current,
                 created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), 'm3u', ?1, ?2, ?3, ?4, 1,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
             RETURNING grouping_evidence_id",
            rusqlite::params![
                playlist_id,
                playlist_evidence.source_fingerprint(),
                playlist_evidence
                    .derived_fingerprint()
                    .map(|value| value.as_transformation_value()),
                playlist_evidence.last_observed_scan_id().to_string(),
            ],
            |row| row.get(0),
        )
        .map_err(map_persistence_operation_error)?;
    for member in grouping.members() {
        transaction
            .execute(
                "INSERT INTO grouping_evidence_member
                    (grouping_evidence_id, member_game_content_id,
                     member_source_entry_id, member_source_fingerprint,
                     member_derived_fingerprint, member_last_observed_scan_id, ordinal)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                rusqlite::params![
                    evidence_id,
                    member.game_content_id().to_string(),
                    member.source_version().source_entry_id().to_string(),
                    member.source_version().source_fingerprint(),
                    member
                        .source_version()
                        .derived_fingerprint()
                        .map(|value| value.as_transformation_value()),
                    member.source_version().last_observed_scan_id().to_string(),
                    i64::from(member.ordinal()),
                ],
            )
            .map_err(map_persistence_operation_error)?;
    }
    parse_game_id(survivor)
}

fn source_version_matches_transaction(
    transaction: &mut rusqlite::Transaction<'_>,
    evidence: &SourceVersionEvidence,
) -> Result<bool, PersistenceError> {
    let persisted: Option<(String, Option<String>, Option<String>, String)> = transaction
        .query_row(
            "SELECT coordinate_kind, source_fingerprint, derived_fingerprint,
                    last_observed_scan_id
             FROM source_entry
             WHERE source_entry_id = ?1",
            [evidence.source_entry_id().to_string()],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()
        .map_err(map_persistence_operation_error)?;
    Ok(persisted
        .map(
            |(coordinate_kind, provider_fingerprint, derived_fingerprint, scan_id)| {
                source_version_matches_values(
                    &coordinate_kind,
                    provider_fingerprint.as_deref(),
                    derived_fingerprint.as_deref(),
                    &scan_id,
                    evidence,
                )
            },
        )
        .unwrap_or(false))
}

fn source_version_matches_values(
    coordinate_kind: &str,
    provider_fingerprint: Option<&str>,
    derived_fingerprint: Option<&str>,
    scan_id: &str,
    evidence: &SourceVersionEvidence,
) -> bool {
    if scan_id != evidence.last_observed_scan_id().to_string() {
        return false;
    }
    match evidence.version() {
        SourceVersionKind::Provider(expected) => {
            coordinate_kind == "provider"
                && provider_fingerprint == expected.as_deref()
                && derived_fingerprint.is_none()
        }
        SourceVersionKind::Derived(expected) => {
            coordinate_kind == "derived"
                && provider_fingerprint.is_none()
                && derived_fingerprint == Some(expected.as_transformation_value())
        }
    }
}

fn upsert_current_membership(
    transaction: &mut rusqlite::Transaction<'_>,
    game_id: &str,
    content_id: &str,
    relationship: &str,
    grouping_basis: &str,
    grouping_revision: i64,
) -> Result<(), PersistenceError> {
    transaction
        .execute(
            "INSERT INTO game_membership
                (game_membership_id, game_id, game_content_id, relationship,
                 grouping_basis, grouping_revision, is_current, created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, 1,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
             ON CONFLICT(game_id, game_content_id, relationship)
             DO UPDATE SET grouping_basis = excluded.grouping_basis,
                           grouping_revision = excluded.grouping_revision,
                           is_current = 1,
                           updated_at = CURRENT_TIMESTAMP",
            rusqlite::params![
                game_id,
                content_id,
                relationship,
                grouping_basis,
                grouping_revision,
            ],
        )
        .map_err(map_persistence_operation_error)?;
    Ok(())
}

fn release_playlist_evidence(
    transaction: &mut rusqlite::Transaction<'_>,
    playlist_source_entry_id: &str,
    keep_content_ids: &[String],
) -> Result<(), PersistenceError> {
    let evidence_ids: Vec<String> = {
        let mut statement = transaction
            .prepare(
                "SELECT grouping_evidence_id
                 FROM grouping_evidence
                 WHERE playlist_source_entry_id = ?1 AND is_current = 1",
            )
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map([playlist_source_entry_id], |row| row.get(0))
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    if evidence_ids.is_empty() {
        return Ok(());
    }
    let evidence_placeholders = placeholders(evidence_ids.len());
    let old_content_ids: Vec<String> = {
        let sql = format!(
            "SELECT DISTINCT member_game_content_id
             FROM grouping_evidence_member
             WHERE grouping_evidence_id IN ({evidence_placeholders})"
        );
        let mut statement = transaction
            .prepare(&sql)
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(params_from_iter(evidence_ids.iter()), |row| row.get(0))
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    transaction
        .execute(
            "UPDATE grouping_evidence
             SET is_current = 0, updated_at = CURRENT_TIMESTAMP
             WHERE playlist_source_entry_id = ?1 AND is_current = 1",
            [playlist_source_entry_id],
        )
        .map_err(map_persistence_operation_error)?;

    for content_id in old_content_ids {
        if keep_content_ids.iter().any(|keep| keep == &content_id) {
            continue;
        }
        detach_content_to_provisional_game(transaction, &content_id)?;
    }
    Ok(())
}

fn release_grouping_evidence_for_sources(
    transaction: &mut rusqlite::Transaction<'_>,
    source_ids: &[String],
) -> Result<(), PersistenceError> {
    if source_ids.is_empty() {
        return Ok(());
    }
    let source_placeholders = placeholders_from(source_ids.len(), 1);
    let playlist_ids: Vec<String> = {
        let sql = format!(
            "SELECT DISTINCT e.playlist_source_entry_id
             FROM grouping_evidence e
             WHERE e.playlist_source_entry_id IN ({source_placeholders})
                OR EXISTS (
                    SELECT 1
                    FROM grouping_evidence_member m
                    WHERE m.grouping_evidence_id = e.grouping_evidence_id
                      AND m.member_source_entry_id IN ({source_placeholders})
                )"
        );
        let params: Vec<&dyn rusqlite::ToSql> = source_ids
            .iter()
            .map(|value| value as &dyn rusqlite::ToSql)
            .collect();
        let mut statement = transaction
            .prepare(&sql)
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(params.as_slice(), |row| row.get(0))
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    for playlist_id in &playlist_ids {
        release_playlist_evidence(transaction, playlist_id, &[])?;
    }

    let evidence_ids: Vec<String> = {
        let sql = format!(
            "SELECT DISTINCT e.grouping_evidence_id
             FROM grouping_evidence e
             WHERE e.playlist_source_entry_id IN ({source_placeholders})
                OR EXISTS (
                    SELECT 1
                    FROM grouping_evidence_member m
                    WHERE m.grouping_evidence_id = e.grouping_evidence_id
                      AND m.member_source_entry_id IN ({source_placeholders})
                )"
        );
        let params: Vec<&dyn rusqlite::ToSql> = source_ids
            .iter()
            .map(|value| value as &dyn rusqlite::ToSql)
            .collect();
        let mut statement = transaction
            .prepare(&sql)
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(params.as_slice(), |row| row.get(0))
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    if evidence_ids.is_empty() {
        return Ok(());
    }
    let evidence_placeholders = placeholders_from(evidence_ids.len(), 1);
    let source_placeholders_after_evidence =
        placeholders_from(source_ids.len(), evidence_ids.len() + 1);
    let delete_member_sql = format!(
        "DELETE FROM grouping_evidence_member
         WHERE grouping_evidence_id IN ({evidence_placeholders})
            OR member_source_entry_id IN ({source_placeholders_after_evidence})"
    );
    let member_params: Vec<&dyn rusqlite::ToSql> = evidence_ids
        .iter()
        .map(|value| value as &dyn rusqlite::ToSql)
        .chain(source_ids.iter().map(|value| value as &dyn rusqlite::ToSql))
        .collect();
    transaction
        .execute(&delete_member_sql, member_params.as_slice())
        .map_err(map_persistence_operation_error)?;
    let delete_evidence_sql = format!(
        "DELETE FROM grouping_evidence
         WHERE grouping_evidence_id IN ({evidence_placeholders})"
    );
    transaction
        .execute(&delete_evidence_sql, params_from_iter(evidence_ids.iter()))
        .map_err(map_persistence_operation_error)?;
    Ok(())
}

fn detach_content_to_provisional_game(
    transaction: &mut rusqlite::Transaction<'_>,
    content_id: &str,
) -> Result<(), PersistenceError> {
    let current: Option<(String, String)> = transaction
        .query_row(
            "SELECT game_id, relationship
             FROM game_membership
             WHERE game_content_id = ?1 AND is_current = 1
             LIMIT 1",
            [content_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(map_persistence_operation_error)?;
    let Some((old_game_id, _)) = current else {
        return Ok(());
    };
    let (platform_id, fallback_title): (String, String) = transaction
        .query_row(
            "SELECT c.platform_id, g.fallback_title
             FROM game_content c
             JOIN game_membership m ON m.game_content_id = c.game_content_id
             JOIN game g ON g.game_id = m.game_id
             WHERE c.game_content_id = ?1 AND m.is_current = 1
             LIMIT 1",
            [content_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(map_persistence_operation_error)?;
    transaction
        .execute(
            "UPDATE game_membership
             SET is_current = 0, updated_at = CURRENT_TIMESTAMP
             WHERE game_content_id = ?1 AND is_current = 1",
            [content_id],
        )
        .map_err(map_persistence_operation_error)?;
    let new_game_id: String = transaction
        .query_row(
            "INSERT INTO game
                (game_id, platform_id, lifecycle_state, grouping_revision,
                 fallback_title, fallback_title_provenance, hydration_state,
                 created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, 'active', 1, ?2, 'local_fallback',
                 'partially_hydrated', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
             RETURNING game_id",
            rusqlite::params![platform_id, fallback_title],
            |row| row.get(0),
        )
        .map_err(map_persistence_operation_error)?;
    transaction
        .execute(
            "INSERT INTO game_membership
                (game_membership_id, game_id, game_content_id, relationship,
                 grouping_basis, grouping_revision, is_current, created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, ?2, 'primary_content', 'provisional', 1, 1,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
            rusqlite::params![new_game_id, content_id],
        )
        .map_err(map_persistence_operation_error)?;
    let source_count: i64 = transaction
        .query_row(
            "SELECT COUNT(*) FROM game_content_source
             WHERE game_content_id = ?1 AND is_current = 1",
            [content_id],
            |row| row.get(0),
        )
        .map_err(map_persistence_operation_error)?;
    transaction
        .execute(
            "INSERT INTO game_library_row
                (game_id, display_title, display_title_provenance, platform_id,
                 hydration_state, availability_state, content_count, source_count, updated_at)
             VALUES
                (?1, ?2, 'local_fallback', ?3, 'partially_hydrated', 'available', 1, ?4,
                 CURRENT_TIMESTAMP)",
            rusqlite::params![new_game_id, fallback_title, platform_id, source_count],
        )
        .map_err(map_persistence_operation_error)?;
    refresh_game(transaction, &new_game_id)?;
    refresh_game(transaction, &old_game_id)?;
    Ok(())
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
        (argus_domain::PlatformId::SegaCd, argus_domain::ContentType::OpticalDiscCd) => {
            "argus.content.identity.sega-cd.disc.v1"
        }
        (argus_domain::PlatformId::SegaSaturn, argus_domain::ContentType::OpticalDiscCd) => {
            "argus.content.identity.sega-saturn.disc.v1"
        }
        (argus_domain::PlatformId::SegaDreamcast, argus_domain::ContentType::OpticalDiscGd) => {
            "argus.content.identity.sega-dreamcast.gdrom.v1"
        }
        (argus_domain::PlatformId::SonyPlaystation, argus_domain::ContentType::OpticalDiscCd) => {
            "argus.content.identity.sony-playstation.disc.v1"
        }
        (argus_domain::PlatformId::SonyPlaystation2, argus_domain::ContentType::OpticalDiscCd) => {
            "argus.content.identity.sony-playstation2.cd.v1"
        }
        (argus_domain::PlatformId::SonyPlaystation2, argus_domain::ContentType::OpticalDiscDvd) => {
            "argus.content.identity.sony-playstation2.dvd.v1"
        }
        (argus_domain::PlatformId::SonyPsp, argus_domain::ContentType::OpticalDiscUmd) => {
            "argus.content.identity.sony-psp.umd.v1"
        }
        (
            argus_domain::PlatformId::NintendoGameCube,
            argus_domain::ContentType::OpticalDiscGameCube,
        ) => "argus.content.identity.nintendo-gamecube.disc.v1",
        (argus_domain::PlatformId::NintendoWii, argus_domain::ContentType::OpticalDiscWii) => {
            "argus.content.identity.nintendo-wii.disc.v1"
        }
        _ => return Err(PersistenceError::ConstraintViolation),
    };
    (derivation.identity().scheme_id() == expected && derivation.identity().revision() == 1)
        .then_some(())
        .ok_or(PersistenceError::ConstraintViolation)
}

fn existing_source_for_derivation(
    transaction: &mut rusqlite::Transaction<'_>,
    derivation: &ValidatedContentDerivation,
) -> Result<Vec<String>, PersistenceError> {
    let mut content_ids = Vec::new();
    for member in derivation.provenance() {
        let source_id = member.source_entry_id().to_string();
        let association_key = member.association_key().unwrap_or("");
        let existing: Option<String> = transaction
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
        if let Some(content_id) = existing
            && !content_ids.iter().any(|candidate| candidate == &content_id)
        {
            content_ids.push(content_id);
        }
    }
    Ok(content_ids)
}

fn ensure_source_associations(
    transaction: &mut rusqlite::Transaction<'_>,
    derivation: &ValidatedContentDerivation,
    content_id: &str,
) -> Result<(), PersistenceError> {
    for member in derivation.provenance() {
        let association_key = member.association_key().unwrap_or("");
        transaction
            .execute(
                "INSERT INTO game_content_source
                (game_content_source_id, game_content_id, source_entry_id, association_key,
                 source_fingerprint, derived_fingerprint, last_observed_scan_id,
                 is_current, created_at, updated_at)
             VALUES
                (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, ?6, 1,
                 CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
             ON CONFLICT(game_content_id, source_entry_id, association_key)
             DO UPDATE SET source_fingerprint = excluded.source_fingerprint,
                           derived_fingerprint = excluded.derived_fingerprint,
                           last_observed_scan_id = excluded.last_observed_scan_id,
                           is_current = 1,
                           updated_at = CURRENT_TIMESTAMP",
                rusqlite::params![
                    content_id,
                    member.source_entry_id().to_string(),
                    association_key,
                    member.source_version().source_fingerprint(),
                    member
                        .source_version()
                        .derived_fingerprint()
                        .map(|value| value.as_transformation_value()),
                    member.source_version().last_observed_scan_id().to_string(),
                ],
            )
            .map_err(map_persistence_operation_error)?;
    }
    Ok(())
}

fn update_identity_provenance(
    transaction: &mut rusqlite::Transaction<'_>,
    identity_id: &str,
    derivation: &ValidatedContentDerivation,
    identity_is_current: bool,
) -> Result<(), PersistenceError> {
    transaction
        .execute(
            "DELETE FROM content_identity_provenance WHERE content_identity_id = ?1",
            [identity_id],
        )
        .map_err(map_persistence_operation_error)?;
    for member in derivation.provenance() {
        transaction
            .execute(
                "INSERT INTO content_identity_provenance
                    (provenance_member_id, content_identity_id, role, association_key,
                     source_entry_id, source_fingerprint, derived_fingerprint,
                     last_observed_scan_id,
                     identity_is_current, created_at, updated_at)
                 VALUES
                    (lower(hex(randomblob(16))), ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8,
                     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)",
                rusqlite::params![
                    identity_id,
                    member.role().as_str(),
                    member.association_key(),
                    member.source_entry_id().to_string(),
                    member.source_version().source_fingerprint(),
                    member
                        .source_version()
                        .derived_fingerprint()
                        .map(|value| value.as_transformation_value()),
                    member.source_version().last_observed_scan_id().to_string(),
                    if identity_is_current { 1_i64 } else { 0_i64 },
                ],
            )
            .map_err(map_persistence_operation_error)?;
    }
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
             ORDER BY CASE relationship WHEN 'primary_content' THEN 0 ELSE 1 END
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
    refresh_game_library_projection(transaction, game_id)
}

/// Recomputes the denormalized Library row for one affected Game inside the
/// caller's transaction. Every value is derived from already-persisted
/// canonical, enrichment, artwork, and source facts; no filesystem or
/// provider work is possible at this layer.
pub(crate) fn refresh_game_library_projection(
    transaction: &mut rusqlite::Transaction<'_>,
    game_id: &str,
) -> Result<(), PersistenceError> {
    let affected_rows = transaction
        .execute(
            "INSERT INTO game_library_row (
                 game_id, display_title, display_title_provenance, platform_id,
                 presentation_region, selected_cover_asset_id, release_date, search_text,
                 hydration_state, availability_state, content_count, source_count, updated_at
             )
             SELECT
                 g.game_id,
                 COALESCE(NULLIF(TRIM(metadata.display_title), ''), g.fallback_title),
                 CASE
                     WHEN NULLIF(TRIM(metadata.display_title), '') IS NULL
                         THEN 'local_fallback'
                     ELSE 'resolved_metadata'
                 END,
                 g.platform_id,
                 metadata.presentation_region,
                 (
                     SELECT artwork.asset_id
                     FROM resolved_artwork artwork
                     WHERE artwork.game_id = g.game_id
                       AND artwork.artwork_type = 'cover_front'
                       AND artwork.asset_id IS NOT NULL
                     ORDER BY artwork.ordering ASC, artwork.reference_id ASC
                     LIMIT 1
                 ),
                 metadata.release_date,
                 lower(trim(
                     COALESCE(NULLIF(TRIM(metadata.display_title), ''), '') || ' ' ||
                     COALESCE(metadata.sort_title, '') || ' ' ||
                     COALESCE(g.fallback_title, '') || ' ' ||
                     COALESCE((
                         SELECT group_concat(
                             COALESCE(provider_metadata.title, '') || ' ' ||
                             COALESCE(provider_metadata.alternate_titles, ''),
                             ' '
                         )
                         FROM game_membership membership
                         JOIN external_identity_mapping mapping
                           ON mapping.game_content_id = membership.game_content_id
                          AND mapping.state = 'current'
                         JOIN provider_metadata
                           ON provider_metadata.provider_id = mapping.provider_id
                          AND provider_metadata.external_game_id = mapping.external_game_id
                          AND provider_metadata.provider_revision = mapping.provider_revision
                         WHERE membership.game_id = g.game_id
                           AND membership.is_current = 1
                     ), '')
                 )),
                 g.hydration_state,
                 CASE
                     WHEN NOT EXISTS (
                         SELECT 1
                         FROM game_membership membership
                         JOIN game_content content
                           ON content.game_content_id = membership.game_content_id
                         WHERE membership.game_id = g.game_id
                           AND membership.is_current = 1
                           AND content.presence_state <> 'orphaned'
                     ) THEN 'inactive_orphan'
                     WHEN NOT EXISTS (
                         SELECT 1
                         FROM game_membership membership
                         JOIN game_content content
                           ON content.game_content_id = membership.game_content_id
                         WHERE membership.game_id = g.game_id
                           AND membership.is_current = 1
                           AND content.presence_state IN ('partially_unavailable', 'unavailable')
                     ) THEN 'available'
                     WHEN EXISTS (
                         SELECT 1
                         FROM game_membership membership
                         JOIN game_content content
                           ON content.game_content_id = membership.game_content_id
                         WHERE membership.game_id = g.game_id
                           AND membership.is_current = 1
                           AND content.presence_state = 'available'
                     ) THEN 'partially_unavailable'
                     ELSE 'unavailable'
                 END,
                 (
                     SELECT COUNT(*)
                     FROM game_membership membership
                     WHERE membership.game_id = g.game_id
                       AND membership.is_current = 1
                 ),
                 (
                     SELECT COUNT(*)
                     FROM game_membership membership
                     JOIN game_content_source source
                       ON source.game_content_id = membership.game_content_id
                     WHERE membership.game_id = g.game_id
                       AND membership.is_current = 1
                       AND source.is_current = 1
                 ),
                 CURRENT_TIMESTAMP
             FROM game g
             LEFT JOIN resolved_metadata metadata ON metadata.game_id = g.game_id
             WHERE g.game_id = ?1
             ON CONFLICT(game_id) DO UPDATE SET
                 display_title = excluded.display_title,
                 display_title_provenance = excluded.display_title_provenance,
                 platform_id = excluded.platform_id,
                 presentation_region = excluded.presentation_region,
                 selected_cover_asset_id = excluded.selected_cover_asset_id,
                 release_date = excluded.release_date,
                 search_text = excluded.search_text,
                 hydration_state = excluded.hydration_state,
                 availability_state = excluded.availability_state,
                 content_count = excluded.content_count,
                 source_count = excluded.source_count,
                 updated_at = excluded.updated_at",
            [game_id],
        )
        .map_err(map_persistence_operation_error)?;
    if affected_rows == 0 {
        return Ok(());
    }

    // The source facts may be longer than the bounded cursor contract. Keep
    // the persisted presentation keys and the cursor keys identical so a
    // valid projection never produces an unreadable continuation token.
    let (display_title, release_date): (String, Option<String>) = transaction
        .query_row(
            "SELECT display_title, release_date
             FROM game_library_row
             WHERE game_id = ?1",
            [game_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(map_persistence_operation_error)?;
    let bounded_display_title = bounded_library_display_title(&display_title);
    let bounded_release_date = release_date.as_deref().map(bounded_library_release_date);
    if display_title != bounded_display_title || release_date != bounded_release_date {
        transaction
            .execute(
                "UPDATE game_library_row
                 SET display_title = ?1, release_date = ?2
                 WHERE game_id = ?3",
                rusqlite::params![bounded_display_title, bounded_release_date, game_id],
            )
            .map_err(map_persistence_operation_error)?;
    }
    Ok(())
}

/// Refreshes only the Games currently owning one changed GameContent unit.
/// This helper is used by metadata persistence where the mutation carries a
/// content identity rather than a direct Game identity.
pub(crate) fn refresh_games_for_content(
    transaction: &mut rusqlite::Transaction<'_>,
    content_id: &str,
) -> Result<(), PersistenceError> {
    let game_ids = {
        let mut statement = transaction
            .prepare(
                "SELECT DISTINCT game_id
                 FROM game_membership
                 WHERE game_content_id = ?1 AND is_current = 1",
            )
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map([content_id], |row| row.get::<_, String>(0))
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    for game_id in game_ids {
        refresh_game_library_projection(transaction, &game_id)?;
    }
    Ok(())
}

/// Refreshes only Games whose current mapping points at changed provider
/// metadata. Search text includes provider-native titles, so replacing a
/// metadata record must update those projections in the same transaction.
pub(crate) fn refresh_games_for_provider_metadata(
    transaction: &mut rusqlite::Transaction<'_>,
    provider_id: &str,
    external_game_id: &str,
    provider_revision: u64,
) -> Result<(), PersistenceError> {
    let game_ids = {
        let mut statement = transaction
            .prepare(
                "SELECT DISTINCT membership.game_id
                 FROM external_identity_mapping mapping
                 JOIN game_membership membership
                   ON membership.game_content_id = mapping.game_content_id
                  AND membership.is_current = 1
                 WHERE mapping.provider_id = ?1
                   AND mapping.external_game_id = ?2
                   AND mapping.provider_revision = ?3
                   AND mapping.state = 'current'",
            )
            .map_err(map_persistence_operation_error)?;
        let rows = statement
            .query_map(
                rusqlite::params![
                    provider_id,
                    external_game_id,
                    i64::try_from(provider_revision).unwrap_or(i64::MAX),
                ],
                |row| row.get::<_, String>(0),
            )
            .map_err(map_persistence_operation_error)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(map_persistence_operation_error)?
    };
    for game_id in game_ids {
        refresh_game_library_projection(transaction, &game_id)?;
    }
    Ok(())
}

fn read_library_row(row: &Row<'_>) -> rusqlite::Result<GameLibraryRow> {
    let selected_cover_asset_id = row
        .get::<_, Option<String>>(4)?
        .map(|value| {
            argus_application::ArtworkAssetId::try_from(value.as_str())
                .map_err(|_| rusqlite::Error::InvalidQuery)
        })
        .transpose()?;
    Ok(GameLibraryRow::from_persisted_with_presentation(
        parse_game_id(row.get::<_, String>(0)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        row.get::<_, String>(1)?,
        parse_platform(&row.get::<_, String>(2)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        row.get(3)?,
        selected_cover_asset_id,
        row.get(5)?,
        parse_hydration(&row.get::<_, String>(6)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        parse_availability(&row.get::<_, String>(7)?).map_err(|_| rusqlite::Error::InvalidQuery)?,
        row.get::<_, i64>(8)? as u32,
        row.get::<_, i64>(9)? as u32,
        row.get(10)?,
    ))
}

/// Loads source/root presentation context for every content member in one
/// bounded query. Detail reads must not issue a query for each content member.
fn read_content_sources_batch(
    transaction: &mut rusqlite::Transaction<'_>,
    content_ids: &[String],
) -> Result<BTreeMap<String, Vec<GameContentSourceSummary>>, PersistenceError> {
    let mut grouped = BTreeMap::new();
    if content_ids.is_empty() {
        return Ok(grouped);
    }

    let sql = format!(
        "SELECT game_content_source.game_content_id,
                source_entry.source_entry_id,
                library_source.library_source_id,
                library_source.display_name,
                library_root.library_root_id,
                library_root.display_name,
                library_root.safe_location_presentation
         FROM game_content_source
         JOIN source_entry
           ON source_entry.source_entry_id = game_content_source.source_entry_id
         JOIN library_root
           ON library_root.library_root_id = source_entry.library_root_id
         JOIN library_source
           ON library_source.library_source_id = library_root.library_source_id
         WHERE game_content_source.game_content_id IN ({})
           AND game_content_source.is_current = 1
         ORDER BY game_content_source.game_content_id ASC,
                  library_root.library_root_id ASC,
                  source_entry.source_entry_id ASC",
        placeholders(content_ids.len())
    );
    let mut statement = transaction
        .prepare(&sql)
        .map_err(map_persistence_operation_error)?;
    let rows = statement
        .query_map(params_from_iter(content_ids.iter()), |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, String>(6)?,
            ))
        })
        .map_err(map_persistence_operation_error)?;
    for row in rows {
        let (
            content_id,
            source_entry_id,
            library_source_id,
            source_display_name,
            library_root_id,
            root_display_name,
            safe_location_presentation,
        ) = row.map_err(map_persistence_operation_error)?;
        grouped
            .entry(content_id)
            .or_default()
            .push(GameContentSourceSummary::new(
                parse_source_entry_id(source_entry_id)?,
                argus_application::LibrarySourceId::try_from(library_source_id.as_str())
                    .map_err(|_| PersistenceError::CorruptOrIncompatible)?,
                source_display_name,
                LibraryRootId::try_from(library_root_id.as_str())
                    .map_err(|_| PersistenceError::CorruptOrIncompatible)?,
                root_display_name,
                safe_location_presentation,
            ));
    }
    Ok(grouped)
}

/// Loads all normalized provenance members for a detail projection in one
/// query and groups them by content. This keeps provenance reads independent
/// of the number of content members in one logical game.
fn read_normalized_provenance_batch(
    transaction: &mut rusqlite::Transaction<'_>,
    content_ids: &[String],
) -> Result<BTreeMap<String, Option<ContentProvenanceSummary>>, PersistenceError> {
    let mut members_by_content = BTreeMap::<String, Vec<ContentProvenanceMemberSummary>>::new();
    if content_ids.is_empty() {
        return Ok(BTreeMap::new());
    }

    let sql = format!(
        "SELECT i.game_content_id, p.role, p.association_key, p.source_entry_id,
                p.source_fingerprint, p.derived_fingerprint,
                p.last_observed_scan_id, e.coordinate_kind
         FROM content_identity_provenance p
         JOIN content_identity i ON i.content_identity_id = p.content_identity_id
         LEFT JOIN source_entry e ON e.source_entry_id = p.source_entry_id
         WHERE i.game_content_id IN ({})
           AND i.is_current = 1
           AND p.identity_is_current = 1
         ORDER BY i.game_content_id ASC, p.rowid ASC",
        placeholders(content_ids.len())
    );
    let mut statement = transaction
        .prepare(&sql)
        .map_err(map_persistence_operation_error)?;
    let rows = statement
        .query_map(params_from_iter(content_ids.iter()), |row| {
            let role = parse_provenance_role(&row.get::<_, String>(1)?)
                .map_err(|_| rusqlite::Error::InvalidQuery)?;
            let association_key = row.get::<_, Option<String>>(2)?;
            let source_entry_id = parse_source_entry_id(row.get::<_, String>(3)?)
                .map_err(|_| rusqlite::Error::InvalidQuery)?;
            let source_fingerprint: Option<String> = row.get(4)?;
            let derived_fingerprint: Option<String> = row.get(5)?;
            let coordinate_kind: Option<String> = row.get(7)?;
            if source_fingerprint.is_some() && derived_fingerprint.is_some() {
                return Err(rusqlite::Error::InvalidQuery);
            }
            if matches!(coordinate_kind.as_deref(), Some("provider"))
                && derived_fingerprint.is_some()
            {
                return Err(rusqlite::Error::InvalidQuery);
            }
            if matches!(coordinate_kind.as_deref(), Some("derived")) && source_fingerprint.is_some()
            {
                return Err(rusqlite::Error::InvalidQuery);
            }
            let scan_id = row
                .get::<_, Option<String>>(6)?
                .ok_or(rusqlite::Error::InvalidQuery)
                .and_then(|value| {
                    parse_scan_run_id(value).map_err(|_| rusqlite::Error::InvalidQuery)
                })?;
            let member = ContentProvenanceMemberSummary::new_with_version(
                role,
                association_key,
                source_entry_id,
                source_fingerprint,
                derived_fingerprint,
                scan_id,
            )
            .map_err(|_| rusqlite::Error::InvalidQuery)?;
            Ok((row.get::<_, String>(0)?, member))
        })
        .map_err(map_persistence_operation_error)?;
    for row in rows {
        let (content_id, member) = row.map_err(map_logical_read_error)?;
        members_by_content
            .entry(content_id)
            .or_default()
            .push(member);
    }
    Ok(members_by_content
        .into_iter()
        .map(|(content_id, members)| (content_id, ContentProvenanceSummary::from_members(members)))
        .collect())
}

fn map_logical_read_error(error: rusqlite::Error) -> PersistenceError {
    if matches!(error, rusqlite::Error::InvalidQuery) {
        PersistenceError::CorruptOrIncompatible
    } else {
        map_persistence_operation_error(error)
    }
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
    let proving_derived_fingerprint: Option<String> = row.get(12)?;
    let proving_scan_id: Option<String> = row.get(13)?;
    let proving_coordinate_kind: Option<String> = row.get(14)?;
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
        proving_fingerprint,
        proving_derived_fingerprint,
        proving_scan_id,
    ) {
        (Some(source), Some(key), provider, derived, Some(scan)) => {
            if provider.is_some() && derived.is_some() {
                return Err(rusqlite::Error::InvalidQuery);
            }
            if matches!(proving_coordinate_kind.as_deref(), Some("provider")) && derived.is_some() {
                return Err(rusqlite::Error::InvalidQuery);
            }
            if matches!(proving_coordinate_kind.as_deref(), Some("derived")) && provider.is_some() {
                return Err(rusqlite::Error::InvalidQuery);
            }
            Some(
                ContentProvenanceSummary::new_with_version(
                    parse_source_entry_id(source).map_err(|_| rusqlite::Error::InvalidQuery)?,
                    key,
                    provider,
                    derived,
                    parse_scan_run_id(scan).map_err(|_| rusqlite::Error::InvalidQuery)?,
                )
                .map_err(|_| rusqlite::Error::InvalidQuery)?,
            )
        }
        (None, None, None, None, None) => None,
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
        "primary" | "primary_content" => Ok(MembershipRelationship::PrimaryContent),
        "regional_variant" => Ok(MembershipRelationship::RegionalVariant),
        "language_variant" => Ok(MembershipRelationship::LanguageVariant),
        "revision_variant" => Ok(MembershipRelationship::RevisionVariant),
        "disc" => Ok(MembershipRelationship::Disc),
        "equivalent_release_representation" | "secondary" => {
            Ok(MembershipRelationship::EquivalentReleaseRepresentation)
        }
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_provenance_role(value: &str) -> Result<ContentProvenanceRole, PersistenceError> {
    match value {
        "primary" => Ok(ContentProvenanceRole::Primary),
        "descriptor" => Ok(ContentProvenanceRole::Descriptor),
        "required_data" => Ok(ContentProvenanceRole::RequiredData),
        "supporting" => Ok(ContentProvenanceRole::Supporting),
        _ => Err(PersistenceError::CorruptOrIncompatible),
    }
}

fn parse_grouping_basis(value: &str) -> Result<GroupingBasis, PersistenceError> {
    match value {
        "exact_content_identity" => Ok(GroupingBasis::ExactContentIdentity),
        "provisional" => Ok(GroupingBasis::Provisional),
        "explicit_relationship_evidence" => Ok(GroupingBasis::ExplicitRelationshipEvidence),
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
    (0..count).map(|_| "?").collect::<Vec<_>>().join(", ")
}

fn placeholders_from(count: usize, start: usize) -> String {
    (1..=count)
        .map(|index| format!("?{}", start + index - 1))
        .collect::<Vec<_>>()
        .join(", ")
}
